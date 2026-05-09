#[compute]
#version 450

// Pass 4: full-resolution composite of the half-res indirect into color.
// For each full-res pixel, sample 4 neighboring half-res taps with bilinear
// weights modulated by depth similarity (depth-aware bilateral upsample),
// then add the result to the existing color. Replaces the previous "write
// 2x2 quad of the same value" approach which produced visible blockiness.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D indirect_tex;     // half-res, denoised
layout(set = 0, binding = 1) uniform sampler2D depth_tex;        // full-res scene depth
layout(set = 0, binding = 2, rgba16f) uniform restrict image2D color_image;

layout(set = 0, binding = 3, std140) uniform Params {
    ivec2 full_size;
    ivec2 half_size;
    float depth_sigma;
    float intensity;
    int _pad0;
    int _pad1;
} params;

void main() {
    ivec2 fpix = ivec2(gl_GlobalInvocationID.xy);
    if (fpix.x >= params.full_size.x || fpix.y >= params.full_size.y) {
        return;
    }

    float center_depth = texelFetch(depth_tex, fpix, 0).r;
    if (center_depth >= 1.0) return;

    vec2 uv_full = (vec2(fpix) + 0.5) / vec2(params.full_size);
    // Floating-point half-res coord; floor gives the top-left tap.
    vec2 hcoord = uv_full * vec2(params.half_size) - 0.5;
    ivec2 base = ivec2(floor(hcoord));
    vec2 frac = hcoord - vec2(base);

    vec3 sum = vec3(0.0);
    float sum_w = 0.0;
    for (int dy = 0; dy < 2; dy++) {
        for (int dx = 0; dx < 2; dx++) {
            ivec2 hpix = base + ivec2(dx, dy);
            hpix = clamp(hpix, ivec2(0), params.half_size - ivec2(1));
            float wx = (dx == 0) ? (1.0 - frac.x) : frac.x;
            float wy = (dy == 0) ? (1.0 - frac.y) : frac.y;
            float bilinear_w = wx * wy;

            // Sample the matching full-res depth for this half-res tap.
            ivec2 fpix_for_tap = hpix * 2;
            fpix_for_tap = clamp(fpix_for_tap, ivec2(0), params.full_size - ivec2(1));
            float tap_depth = texelFetch(depth_tex, fpix_for_tap, 0).r;
            float depth_w = exp(-abs(center_depth - tap_depth) / max(params.depth_sigma, 1.0e-5));
            float w = bilinear_w * depth_w;
            sum += texelFetch(indirect_tex, hpix, 0).rgb * w;
            sum_w += w;
        }
    }

    vec3 indirect = (sum_w > 0.0) ? (sum / sum_w) : vec3(0.0);

    vec4 base_color = imageLoad(color_image, fpix);
    imageStore(color_image, fpix, vec4(base_color.rgb + indirect * params.intensity, base_color.a));
}
