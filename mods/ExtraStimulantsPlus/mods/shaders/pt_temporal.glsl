#[compute]
#version 450

// Pass 2: temporal reprojection of the half-res indirect estimate.
// For each half-res pixel, reproject its world position into the previous
// frame's clip space, sample the previous history, run a depth/normal-based
// disocclusion test, and exponentially blend the new sample into history.
// Output A channel stores normalized accumulation count (0..1, scaled by
// alpha_max) so the next frame's blend weight is bounded.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D indirect_curr;
layout(set = 0, binding = 1) uniform sampler2D history_prev;
layout(set = 0, binding = 2) uniform sampler2D depth_tex;
layout(set = 0, binding = 3, rgba16f) uniform restrict writeonly image2D history_out;

layout(set = 0, binding = 4, std140) uniform Params {
    mat4 inv_view_proj;
    mat4 prev_view_proj;
    ivec2 full_size;
    ivec2 half_size;
    int alpha_max;
    int reset_history;
    float depth_tol;
    float _pad0;
} params;

vec3 reconstruct_world(vec2 uv, float depth) {
    vec4 ndc = vec4(uv * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0);
    vec4 world = params.inv_view_proj * ndc;
    return world.xyz / world.w;
}

void main() {
    ivec2 hpix = ivec2(gl_GlobalInvocationID.xy);
    if (hpix.x >= params.half_size.x || hpix.y >= params.half_size.y) {
        return;
    }

    ivec2 fpix = hpix * 2;
    vec2 uv_full = (vec2(fpix) + 0.5) / vec2(params.full_size);
    vec2 uv_half = (vec2(hpix) + 0.5) / vec2(params.half_size);

    float depth = texture(depth_tex, uv_full).r;
    vec4 curr = texture(indirect_curr, uv_half);

    if (depth >= 1.0 || params.reset_history != 0) {
        imageStore(history_out, hpix, vec4(curr.rgb, 1.0 / float(max(1, params.alpha_max))));
        return;
    }

    vec3 world_pos = reconstruct_world(uv_full, depth);

    // Reproject world position into prev-frame clip space.
    vec4 prev_clip = params.prev_view_proj * vec4(world_pos, 1.0);
    if (prev_clip.w <= 0.0) {
        imageStore(history_out, hpix, vec4(curr.rgb, 1.0 / float(max(1, params.alpha_max))));
        return;
    }
    vec3 prev_ndc = prev_clip.xyz / prev_clip.w;
    vec2 prev_uv = prev_ndc.xy * 0.5 + 0.5;

    bool valid = all(greaterThanEqual(prev_uv, vec2(0.0))) && all(lessThanEqual(prev_uv, vec2(1.0)));

    // Approximate disocclusion: reprojected depth should not be significantly
    // behind whatever is currently visible at prev_uv. Without a stored prev
    // depth this misses some cases (objects that moved toward the camera) but
    // catches the common case of camera motion across static geometry.
    if (valid) {
        float curr_depth_at_prev_uv = texture(depth_tex, prev_uv).r;
        float reprojected_depth = prev_ndc.z * 0.5 + 0.5;
        if (reprojected_depth - curr_depth_at_prev_uv > params.depth_tol) {
            valid = false;
        }
    }

    if (!valid) {
        imageStore(history_out, hpix, vec4(curr.rgb, 1.0 / float(max(1, params.alpha_max))));
        return;
    }

    vec4 hist = texture(history_prev, prev_uv);
    // Stored alpha is 1/N; recover N, increment, clamp, recompute alpha.
    float prev_count = max(1.0, 1.0 / max(hist.a, 1.0e-4));
    float new_count = min(prev_count + 1.0, float(params.alpha_max));
    float alpha = 1.0 / new_count;

    vec3 blended = mix(hist.rgb, curr.rgb, alpha);
    imageStore(history_out, hpix, vec4(blended, alpha));
}
