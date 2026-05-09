#[compute]
#version 450

// Pass 3: edge-aware à-trous wavelet filter, single iteration.
// Run multiple times with increasing `step_size` (1, 2, 4) using ping-pong
// textures. Each iteration applies a 5x5 separable-style kernel weighted by
// a 1D Gaussian and edge-stops on depth and normal. No luminance edge-stop
// in this lite variant — temporal accumulation already handles most of the
// "fireflies" problem and luminance stops can over-blur in dim regions.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0) uniform sampler2D input_tex;
layout(set = 0, binding = 1) uniform sampler2D depth_tex;
layout(set = 0, binding = 2) uniform sampler2D normal_roughness_tex;
layout(set = 0, binding = 3, rgba16f) uniform restrict writeonly image2D output_tex;

layout(set = 0, binding = 4, std140) uniform Params {
    ivec2 full_size;
    ivec2 half_size;
    int step_size;
    float sigma_z;
    float sigma_n;
    int _pad0;
} params;

vec3 decode_normal_oct(vec2 e) {
    e = e * 2.0 - 1.0;
    vec3 n = vec3(e.xy, 1.0 - abs(e.x) - abs(e.y));
    if (n.z < 0.0) {
        vec2 s = vec2(n.x >= 0.0 ? 1.0 : -1.0, n.y >= 0.0 ? 1.0 : -1.0);
        n.xy = (1.0 - abs(n.yx)) * s;
    }
    return normalize(n);
}

float gauss_weight(int dx, int dy) {
    // 1-2-1 separable Gaussian extended to 5x5: weights = [1, 4, 6, 4, 1] / 16.
    const float w[3] = float[3](6.0, 4.0, 1.0);
    return w[abs(dx)] * w[abs(dy)] / (16.0 * 16.0);
}

void main() {
    ivec2 hpix = ivec2(gl_GlobalInvocationID.xy);
    if (hpix.x >= params.half_size.x || hpix.y >= params.half_size.y) {
        return;
    }

    ivec2 fpix = hpix * 2;
    vec2 uv_full = (vec2(fpix) + 0.5) / vec2(params.full_size);
    float center_depth = texture(depth_tex, uv_full).r;
    vec3 center_normal = decode_normal_oct(texture(normal_roughness_tex, uv_full).rg);

    if (center_depth >= 1.0 || dot(center_normal, center_normal) < 0.01) {
        imageStore(output_tex, hpix, texelFetch(input_tex, hpix, 0));
        return;
    }

    vec3 sum_color = vec3(0.0);
    float sum_weight = 0.0;
    float sum_alpha = 0.0;

    int step = max(1, params.step_size);

    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            ivec2 sample_hpix = hpix + ivec2(dx, dy) * step;
            if (sample_hpix.x < 0 || sample_hpix.y < 0
                || sample_hpix.x >= params.half_size.x
                || sample_hpix.y >= params.half_size.y) {
                continue;
            }
            ivec2 sample_fpix = sample_hpix * 2;
            vec2 sample_uv_full = (vec2(sample_fpix) + 0.5) / vec2(params.full_size);

            float sample_depth = texture(depth_tex, sample_uv_full).r;
            if (sample_depth >= 1.0) continue;
            vec3 sample_normal = decode_normal_oct(texture(normal_roughness_tex, sample_uv_full).rg);

            float wz = exp(-abs(center_depth - sample_depth) / max(params.sigma_z, 1.0e-5));
            float wn = pow(max(0.0, dot(center_normal, sample_normal)), max(params.sigma_n, 1.0));
            float wg = gauss_weight(dx, dy);
            float w = wz * wn * wg;

            vec4 c = texelFetch(input_tex, sample_hpix, 0);
            sum_color += c.rgb * w;
            sum_alpha += c.a * w;
            sum_weight += w;
        }
    }

    if (sum_weight > 0.0) {
        imageStore(output_tex, hpix, vec4(sum_color / sum_weight, sum_alpha / sum_weight));
    } else {
        imageStore(output_tex, hpix, texelFetch(input_tex, hpix, 0));
    }
}
