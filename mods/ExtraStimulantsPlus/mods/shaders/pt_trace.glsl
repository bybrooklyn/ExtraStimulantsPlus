#[compute]
#version 450

// Pass 1 of the path-tracer pipeline: half-resolution single-frame trace.
// For each output pixel (half-res), reconstruct world position from depth,
// fire N cosine-weighted hemisphere rays, march them in screen-space against
// depth, sample the color-history snapshot on hit, and write the per-pixel
// indirect estimate to indirect_out. Temporal accumulation and denoising
// happen in later passes.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D depth_tex;
layout(set = 0, binding = 1) uniform sampler2D normal_roughness_tex;
layout(set = 0, binding = 2) uniform sampler2D color_history_tex;
layout(set = 0, binding = 3, rgba16f) uniform restrict writeonly image2D indirect_out;

layout(set = 0, binding = 4, std140) uniform Params {
    mat4 inv_view_proj;
    mat4 view_proj;
    ivec2 full_size;
    ivec2 half_size;
    int samples;
    int max_steps;
    float thickness;
    float fade;
    vec3 sky_color;
    float sky_intensity;
    int frame_index;
    int _pad0;
    int _pad1;
    int _pad2;
} params;

float halton(int i, int b) {
    float f = 1.0;
    float r = 0.0;
    int idx = i;
    while (idx > 0) {
        f = f / float(b);
        r = r + f * float(idx % b);
        idx = idx / b;
    }
    return r;
}

float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

vec3 reconstruct_world(vec2 uv, float depth) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 world = params.inv_view_proj * ndc;
    return world.xyz / world.w;
}

bool project_to_screen(vec3 world_pos, out vec3 ndc) {
    vec4 clip = params.view_proj * vec4(world_pos, 1.0);
    if (clip.w <= 0.0) return false;
    ndc = clip.xyz / clip.w;
    return all(greaterThanEqual(ndc.xy, vec2(-1.0))) && all(lessThanEqual(ndc.xy, vec2(1.0)));
}

mat3 build_tbn(vec3 n) {
    vec3 up = abs(n.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 t = normalize(cross(up, n));
    vec3 b = cross(n, t);
    return mat3(t, b, n);
}

vec3 cosine_sample_hemisphere(vec2 r) {
    float phi = 2.0 * 3.14159265 * r.x;
    float cos_theta = sqrt(1.0 - r.y);
    float sin_theta = sqrt(r.y);
    return vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
}

// Octahedral decode for Forward+ normal_roughness texture.
// Godot 4.3+ packs the world-space normal into .rg as octahedron coordinates;
// roughness lives in .b. We don't need roughness here.
vec3 decode_normal_oct(vec2 e) {
    e = e * 2.0 - 1.0;
    vec3 n = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
    if (n.z < 0.0) {
        vec2 s = vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
        n.xy = (1.0 - abs(n.yx)) * s;
    }
    return normalize(n);
}

// Returns true on hit, sets hit_color from the color-history snapshot.
// Returns false on miss.
bool march_ray(vec3 origin, vec3 dir, out vec3 hit_color) {
    hit_color = vec3(0.0);
    float step_len = 0.25;
    vec3 pos = origin + dir * step_len;
    for (int i = 0; i < params.max_steps; i++) {
        vec3 ndc;
        if (!project_to_screen(pos, ndc)) {
            return false;
        }
        vec2 uv = ndc.xy * 0.5 + 0.5;
        float scene_depth = texture(depth_tex, uv).r;
        vec3 scene_world = reconstruct_world(uv, scene_depth);
        float diff = length(pos - scene_world);
        vec3 to_pos = pos - origin;
        vec3 to_scene = scene_world - origin;
        if (dot(to_pos, dir) > dot(to_scene, dir) - 0.001 && diff < params.thickness) {
            hit_color = textureLod(color_history_tex, uv, 0.0).rgb;
            return true;
        }
        step_len *= 1.35;
        pos += dir * step_len;
    }
    return false;
}

void main() {
    ivec2 hpix = ivec2(gl_GlobalInvocationID.xy);
    if (hpix.x >= params.half_size.x || hpix.y >= params.half_size.y) {
        return;
    }
    // Map half-res pixel to a representative full-res pixel.
    ivec2 fpix = hpix * 2;
    vec2 uv = (vec2(fpix) + 0.5) / vec2(params.full_size);

    float depth = texture(depth_tex, uv).r;
    if (depth >= 1.0) {
        // Sky/cleared pixel: no indirect contribution.
        imageStore(indirect_out, hpix, vec4(0.0, 0.0, 0.0, 0.0));
        return;
    }

    vec3 world_pos = reconstruct_world(uv, depth);
    vec4 nr = texture(normal_roughness_tex, uv);
    vec3 n = decode_normal_oct(nr.rg);
    if (dot(n, n) < 0.01) {
        imageStore(indirect_out, hpix, vec4(0.0, 0.0, 0.0, 0.0));
        return;
    }

    mat3 tbn = build_tbn(n);

    vec3 indirect = vec3(0.0);
    int spp = max(1, params.samples);
    float jitter = hash12(vec2(fpix) + float(params.frame_index) * 17.0);

    for (int s = 0; s < spp; s++) {
        int hi = params.frame_index * spp + s;
        vec2 r = vec2(
            fract(halton(hi + 1, 2) + jitter),
            fract(halton(hi + 1, 3) + jitter)
        );
        vec3 local = cosine_sample_hemisphere(r);
        vec3 dir = normalize(tbn * local);
        vec3 origin = world_pos + n * 0.01;

        vec3 hit_color;
        if (march_ray(origin, dir, hit_color)) {
            indirect += hit_color;
        } else {
            // Miss: contribute the sky term so corners don't go pitch-black.
            indirect += params.sky_color * params.sky_intensity;
        }
    }
    indirect /= float(spp);

    imageStore(indirect_out, hpix, vec4(indirect * params.fade, 1.0));
}
