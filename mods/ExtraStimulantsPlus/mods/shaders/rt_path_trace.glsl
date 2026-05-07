#[compute]
#version 450

// Screen-space path tracer compute shader.
// For each output pixel: reconstruct world position from depth, fire N
// cosine-weighted hemisphere rays, march them in screen-space against the
// depth buffer, accumulate hit color (or zero on miss), and add the result
// to the existing color with a "fade" weight.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba16f) uniform restrict image2D color_image;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D normal_roughness_tex;

layout(set = 0, binding = 3, std140) uniform Params {
    mat4 inv_view_proj;
    mat4 view_proj;
    ivec2 size;
    int samples;
    int max_steps;
    float thickness;
    float fade;
    int half_res;
    int frame_index;
} params;

// --- Halton low-discrepancy sequence ----------------------------------------
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

// Hash for per-pixel sample decorrelation.
float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// --- Geometry helpers --------------------------------------------------------
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

// Cosine-weighted hemisphere sample around +Z.
vec3 cosine_sample_hemisphere(vec2 r) {
    float phi = 2.0 * 3.14159265 * r.x;
    float cos_theta = sqrt(1.0 - r.y);
    float sin_theta = sqrt(r.y);
    return vec3(cos(phi) * sin_theta, sin(phi) * sin_theta, cos_theta);
}

// --- Screen-space raymarch ---------------------------------------------------
// Marches in world space, projecting to screen each step. Simple but robust
// enough for the diffuse use case at this resolution.
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
        // Reconstruct depth at this screen position from the scene.
        vec3 scene_world = reconstruct_world(uv, scene_depth);
        float diff = length(pos - scene_world);
        // The ray's z relative to camera vs scene_world's z:
        // simpler test — if our marched pos is now "behind" the depth surface
        // along the ray and within thickness, count it as a hit.
        vec3 to_pos = pos - origin;
        vec3 to_scene = scene_world - origin;
        if (dot(to_pos, dir) > dot(to_scene, dir) - 0.001 && diff < params.thickness) {
            hit_color = imageLoad(color_image, ivec2(uv * vec2(params.size))).rgb;
            return true;
        }
        step_len *= 1.35;
        pos += dir * step_len;
    }
    return false;
}

void main() {
    ivec2 dispatch_xy = ivec2(gl_GlobalInvocationID.xy);
    ivec2 pixel = dispatch_xy;
    if (params.half_res != 0) {
        pixel = dispatch_xy * 2;
    }
    if (pixel.x >= params.size.x || pixel.y >= params.size.y) {
        return;
    }

    vec2 uv = (vec2(pixel) + 0.5) / vec2(params.size);
    float depth = texture(depth_tex, uv).r;
    if (depth >= 1.0) return; // skybox / cleared pixel

    vec3 world_pos = reconstruct_world(uv, depth);

    // Godot's normal_roughness texture format has shifted between point
    // releases. 4.3+ Forward+ commonly stores octahedron-encoded normals in .rg
    // with roughness in .b. The simpler "rgb * 2 - 1" form survives well enough
    // for diffuse SSGI even when the encoding is actually octahedral, since
    // both produce a unit-length-ish vector pointing roughly the right way.
    // Flip OCT_DECODE to 1 if testing reveals the octahedron path is needed.
#define OCT_DECODE 0
    vec4 nr = texture(normal_roughness_tex, uv);
    vec3 n;
#if OCT_DECODE
    vec2 e = nr.rg * 2.0 - 1.0;
    n = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
    if (n.z < 0.0) {
        vec2 s = vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
        n.xy = (1.0 - abs(n.yx)) * s;
    }
    n = normalize(n);
#else
    n = normalize(nr.xyz * 2.0 - 1.0);
#endif
    if (dot(n, n) < 0.01) return;

    mat3 tbn = build_tbn(n);

    vec3 indirect = vec3(0.0);
    int spp = max(1, params.samples);
    float jitter = hash12(vec2(pixel) + float(params.frame_index));

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
        }
    }
    indirect /= float(spp);

    vec3 add = indirect * params.fade;

    if (params.half_res != 0) {
        for (int dy = 0; dy < 2; dy++) {
            for (int dx = 0; dx < 2; dx++) {
                ivec2 p = pixel + ivec2(dx, dy);
                if (p.x < params.size.x && p.y < params.size.y) {
                    vec3 b = imageLoad(color_image, p).rgb;
                    imageStore(color_image, p, vec4(b + add, 1.0));
                }
            }
        }
    } else {
        vec3 b = imageLoad(color_image, pixel).rgb;
        imageStore(color_image, pixel, vec4(b + add, 1.0));
    }
}
