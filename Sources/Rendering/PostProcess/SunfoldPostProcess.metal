//  SunfoldPostProcess.metal
//
//  The GPU half of the final-image pass. Three stages:
//
//    1. sunfoldBrightPass  — quarter-res downsample + soft-knee bright extraction.
//    2. sunfoldBlur        — separable 9-tap Gaussian (5 fetches via the linear
//                            sampling trick), run H/V twice at widening stride.
//    3. sunfoldComposite   — chromatic aberration, bloom add, ACES filmic tonemap,
//                            split-tone grade, saturation, vignette.
//
//  Stages 1 and 2 are compute kernels writing into scratch textures the Swift side
//  owns (always rgba16Float, always .shaderWrite). Stage 3 is a RENDER pass, not a
//  compute write: RealityKit's target texture is guaranteed to be a render target
//  but is not guaranteed to carry .shaderWrite, and rendering also lets the
//  hardware do the sRGB encode when the target is an _srgb format.
//
//  Colour space: all maths happens in LINEAR light. `decodeMode`/`encodeMode` say
//  whether the hardware already did the transfer function for us (sRGB-tagged
//  formats, or float formats that are linear to begin with) or whether we must do
//  it by hand (plain 8-bit unorm). SunfoldPostProcess.swift decides, at runtime,
//  from the actual pixel formats RealityKit hands over.

#include <metal_stdlib>
using namespace metal;

// Layout is mirrored exactly by `SunfoldPostParams` in SunfoldPostProcess.swift.
// The two float4s lead so that no interior padding is ever inferred differently
// by the two compilers; `pad` keeps the scalar block 16-byte aligned.
struct SunfoldPostParams {
    float4 shadowTint;      // rgb = shadow multiplier, w = grade strength
    float4 highlightTint;   // rgb = highlight multiplier, w = split-tone pivot
    float2 dstTexel;        // 1 / destination dimensions
    float2 srcTexel;        // 1 / source dimensions
    float2 blurDirection;   // (1,0) or (0,1)
    float2 pad0;
    // Exactly sixteen scalars (64 bytes) so the struct is 128 bytes on the nose
    // and neither compiler has to infer trailing padding.
    float threshold;
    float softKnee;
    float bloomIntensity;
    float exposure;
    float tonemapStrength;
    float vignetteStrength;
    float vignetteRadius;
    float vignetteSoftness;
    float aberration;
    float saturation;
    float decodeMode;       // 0 = hardware already gave us linear, 1 = decode here
    float encodeMode;       // 0 = hardware will encode on write, 1 = encode here
    float blurStride;
    float pad1;
    float pad2;
    float pad3;
};

constexpr sampler kSunfoldSampler(filter::linear,
                                  mip_filter::none,
                                  address::clamp_to_edge,
                                  coord::normalized);

constant float3 kSunfoldLuma = float3(0.2126f, 0.7152f, 0.0722f);

// Gaussian sigma ~2.0 collapsed to 5 bilinear fetches.
constant float kSunfoldWeight0 = 0.2270270270f;
constant float kSunfoldWeight1 = 0.3162162162f;
constant float kSunfoldWeight2 = 0.0702702703f;
constant float kSunfoldOffset1 = 1.3846153846f;
constant float kSunfoldOffset2 = 3.2307692308f;

static inline float3 sunfoldToLinear(float3 c, float mode) {
    if (mode < 0.5f) { return c; }
    c = max(c, 0.0f);
    return select(c * (1.0f / 12.92f),
                  pow((c + 0.055f) * (1.0f / 1.055f), 2.4f),
                  c > 0.04045f);
}

static inline float3 sunfoldToDisplay(float3 c, float mode) {
    if (mode < 0.5f) { return c; }
    c = max(c, 0.0f);
    return select(c * 12.92f,
                  1.055f * pow(c, 1.0f / 2.4f) - 0.055f,
                  c > 0.0031308f);
}

/// Narkowicz's fit of the ACES filmic curve. Lifts mid-tones, rolls highlights
/// off instead of clipping them, and gently crushes the toe — which is exactly
/// the "not flat sRGB" falloff the void needs behind a luminous faction.
static inline float3 sunfoldACES(float3 x) {
    const float a = 2.51f, b = 0.03f, c = 2.43f, d = 0.59f, e = 0.14f;
    return saturate((x * (a * x + b)) / (x * (c * x + d) + e));
}

// MARK: - Stage 1: bright pass

kernel void sunfoldBrightPass(texture2d<float, access::sample> source [[texture(0)]],
                              texture2d<float, access::write> destination [[texture(1)]],
                              constant SunfoldPostParams &p [[buffer(0)]],
                              uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) { return; }

    const float2 uv = (float2(gid) + 0.5f) * p.dstTexel;

    // 3x3 bilinear tent spanning the destination texel's whole footprint plus a
    // half-texel of overlap into its neighbours. A naive 4-tap box at quarter res
    // point-samples only four of the sixteen source texels it stands for, so a
    // small bright thing — a star, a seam highlight — pops in and out of the
    // bloom as the camera pans. The overlap is what makes it stable.
    const float2 h = p.dstTexel * 0.5f;
    float3 c = source.sample(kSunfoldSampler, uv).rgb * 4.0f;
    c += (source.sample(kSunfoldSampler, uv + float2(-h.x, 0.0f)).rgb
        + source.sample(kSunfoldSampler, uv + float2( h.x, 0.0f)).rgb
        + source.sample(kSunfoldSampler, uv + float2(0.0f, -h.y)).rgb
        + source.sample(kSunfoldSampler, uv + float2(0.0f,  h.y)).rgb) * 2.0f;
    c += source.sample(kSunfoldSampler, uv + float2(-h.x, -h.y)).rgb
       + source.sample(kSunfoldSampler, uv + float2( h.x, -h.y)).rgb
       + source.sample(kSunfoldSampler, uv + float2(-h.x,  h.y)).rgb
       + source.sample(kSunfoldSampler, uv + float2( h.x,  h.y)).rgb;
    c = sunfoldToLinear(c * (1.0f / 16.0f), p.decodeMode);

    const float luma = dot(c, kSunfoldLuma);

    // Soft-knee threshold. A hard threshold pops as a seam crosses it while the
    // camera moves; the quadratic knee fades contribution in over `softKnee`.
    const float knee = max(p.softKnee, 1e-4f);
    float soft = clamp(luma - p.threshold + knee, 0.0f, 2.0f * knee);
    soft = soft * soft / (4.0f * knee);
    const float contribution = max(soft, luma - p.threshold) / max(luma, 1e-4f);

    destination.write(float4(c * contribution, 1.0f), gid);
}

// MARK: - Stage 2: separable blur

kernel void sunfoldBlur(texture2d<float, access::sample> source [[texture(0)]],
                        texture2d<float, access::write> destination [[texture(1)]],
                        constant SunfoldPostParams &p [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= destination.get_width() || gid.y >= destination.get_height()) { return; }

    const float2 uv = (float2(gid) + 0.5f) * p.dstTexel;
    const float2 step = p.blurDirection * p.srcTexel * p.blurStride;

    float3 c = source.sample(kSunfoldSampler, uv).rgb * kSunfoldWeight0;
    c += (source.sample(kSunfoldSampler, uv + step * kSunfoldOffset1).rgb
        + source.sample(kSunfoldSampler, uv - step * kSunfoldOffset1).rgb) * kSunfoldWeight1;
    c += (source.sample(kSunfoldSampler, uv + step * kSunfoldOffset2).rgb
        + source.sample(kSunfoldSampler, uv - step * kSunfoldOffset2).rgb) * kSunfoldWeight2;

    destination.write(float4(c, 1.0f), gid);
}

// MARK: - Stage 3: composite

struct SunfoldFullscreenVertex {
    float4 position [[position]];
    float2 uv;
};

vertex SunfoldFullscreenVertex sunfoldFullscreenVertex(uint vertexID [[vertex_id]]) {
    // One oversized triangle: cheaper than a quad and has no diagonal seam.
    const float2 uv = float2(float((vertexID << 1) & 2), float(vertexID & 2));
    SunfoldFullscreenVertex out;
    out.uv = uv;
    out.position = float4(uv * float2(2.0f, -2.0f) + float2(-1.0f, 1.0f), 0.0f, 1.0f);
    return out;
}

fragment float4 sunfoldCompositeFragment(SunfoldFullscreenVertex in [[stage_in]],
                                         texture2d<float, access::sample> source [[texture(0)]],
                                         texture2d<float, access::sample> bloom [[texture(1)]],
                                         constant SunfoldPostParams &p [[buffer(0)]])
{
    const float2 uv = in.uv;
    const float2 centered = uv * 2.0f - 1.0f;
    const float radiusSquared = dot(centered, centered);

    // Lateral chromatic aberration: zero at the optical centre, growing with the
    // square of the radius the way a real lens does. Kept sub-pixel-ish so it
    // reads as glass rather than as a broken frame.
    float3 c;
    if (p.aberration > 0.0f) {
        const float2 offset = centered * (p.aberration * radiusSquared);
        c.r = source.sample(kSunfoldSampler, uv + offset).r;
        c.g = source.sample(kSunfoldSampler, uv).g;
        c.b = source.sample(kSunfoldSampler, uv - offset).b;
    } else {
        c = source.sample(kSunfoldSampler, uv).rgb;
    }
    c = sunfoldToLinear(c, p.decodeMode);

    // Bloom is already linear — the bright pass linearised it before blurring.
    c += bloom.sample(kSunfoldSampler, uv).rgb * p.bloomIntensity;

    // Tonemap. Blending against the clamped original keeps the curve a dial
    // rather than a commitment; the source is display-referred already, so a
    // full-strength film curve on top would read as a second grade.
    const float3 exposed = c * p.exposure;
    c = mix(saturate(exposed), sunfoldACES(exposed), p.tonemapStrength);

    // Split-tone: cool indigo in the toe, warm in the shoulder. This is the
    // cheapest way to stop a single-hue palette reading as flat.
    const float luma = dot(c, kSunfoldLuma);
    const float3 grade = mix(p.shadowTint.rgb,
                             p.highlightTint.rgb,
                             smoothstep(0.0f, max(p.highlightTint.w, 1e-3f), luma));
    c = mix(c, c * grade, p.shadowTint.w);

    c = max(mix(float3(luma), c, p.saturation), 0.0f);

    // Vignette, applied last so it darkens the graded image rather than feeding
    // the tonemap a falsely dark frame.
    // Written out rather than as a reversed smoothstep: Metal leaves
    // smoothstep(edge0, edge1, x) undefined when edge0 >= edge1, which is exactly
    // the argument order a "bright at the centre" falloff wants.
    const float inner = p.vignetteRadius - max(p.vignetteSoftness, 1e-3f);
    const float t = saturate((length(centered) - inner)
                             / max(p.vignetteRadius - inner, 1e-3f));
    const float falloff = 1.0f - t * t * (3.0f - 2.0f * t);
    c *= mix(1.0f, falloff, p.vignetteStrength);

    return float4(sunfoldToDisplay(saturate(c), p.encodeMode), 1.0f);
}
