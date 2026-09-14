#include <metal_stdlib>
using namespace metal;

// The wave ring's colour sweep, per pixel.
//
// This is the "realtime gradient": colour is a function of (angle, time)
// evaluated at every pixel every frame, so there are no stops at all and
// the band pattern can change shape over time — bands widen, narrow and
// slide — without blending two layers and washing the colour out, which
// is what the CPU "Flow" layer did.
//
// Colours arrive as OKLab triples (converted on the CPU once per frame
// from the configured Colors) and are interpolated in OKLab here, with
// smoothstep easing per segment — the same math as PerceptualGradient,
// just per pixel instead of per stop.

static float3 oklab_to_linear_srgb(float3 lab) {
    float l_ = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
    float m_ = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
    float s_ = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;
    float l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
    return float3(
         4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
        -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
        -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s);
}

static float3 linear_to_srgb(float3 c) {
    c = clamp(c, 0.0f, 1.0f);
    float3 lo = c * 12.92f;
    float3 hi = 1.055f * pow(c, 1.0f / 2.4f) - 0.055f;
    return select(hi, lo, c <= 0.0031308f);
}

// `phase`, `warpA` and `warpB` arrive already reduced to one turn — see
// `RingView.shaderSweep` for why that has to happen in Double on the CPU.
[[ stitchable ]] half4 ringSweep(float2 position, half4 color,
                                  float2 size, float phase,
                                  float warpA, float warpB, float warpAmount,
                                  device const float *lab, int labCount)
{
    if (color.a <= 0.0h) { return color; }
    int count = labCount / 3;
    if (count < 1) { return color; }

    float2 d = position - size * 0.5f;
    float theta = atan2(d.y, d.x);              // -pi ... pi
    const float twoPi = 6.28318530718f;

    // Position around the loop, 0...1, rotated by the ring's phase.
    float u = theta / twoPi - phase / twoPi;

    // The part a stop-based gradient cannot do: the mapping from angle to
    // colour breathes. Two harmonics at unrelated rates so it never reads
    // as a repeating wobble. Zero amount is exactly the static sweep.
    if (warpAmount > 0.0f) {
        float w = sin(theta * 2.0f + warpA) * 0.6f
                + sin(theta * 3.0f - warpB) * 0.4f;
        u += warpAmount * w / twoPi;
    }
    u = fract(u);

    // Closed loop: count segments, the last running back to colour 0.
    float t = u * float(count);
    int i = int(floor(t));
    if (i >= count) { i = count - 1; }
    float f = t - float(i);
    f = f * f * (3.0f - 2.0f * f);
    int j = (i + 1) % count;

    float3 a = float3(lab[3 * i], lab[3 * i + 1], lab[3 * i + 2]);
    float3 b = float3(lab[3 * j], lab[3 * j + 1], lab[3 * j + 2]);
    float3 rgb = linear_to_srgb(oklab_to_linear_srgb(mix(a, b, f)));

    return half4(half3(rgb) * color.a, color.a);
}
