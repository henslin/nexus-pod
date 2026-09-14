#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// The Lab's shaders — see `Lab/LabExperiment.swift`. Each one is a
// demonstration of one SwiftUI shader entry point, at its most flattering:
//
//   colorEffect      → `labAurora`, `labOrb`   (colour per pixel, no input)
//   layerEffect      → `labBloom`              (samples the view beneath)
//   distortionEffect → `labRipple`             (moves pixels)
//
// They share the palette code with `RingSweep.metal`: colours arrive as
// OKLab triples and are looped through with smoothstep, so every
// experiment is in the ring's own colours and comparisons are fair.

// MARK: - Colour

static float3 lab_oklab_to_linear(float3 lab) {
    float l_ = lab.x + 0.3963377774f * lab.y + 0.2158037573f * lab.z;
    float m_ = lab.x - 0.1055613458f * lab.y - 0.0638541728f * lab.z;
    float s_ = lab.x - 0.0894841775f * lab.y - 1.2914855480f * lab.z;
    float l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_;
    return float3(
         4.0767416621f * l - 3.3077115913f * m + 0.2309699292f * s,
        -1.2684380046f * l + 2.6097574011f * m - 0.3413193965f * s,
        -0.0041960863f * l - 0.7034186147f * m + 1.7076147010f * s);
}

static float3 lab_linear_to_srgb(float3 c) {
    c = clamp(c, 0.0f, 1.0f);
    float3 lo = c * 12.92f;
    float3 hi = 1.055f * pow(c, 1.0f / 2.4f) - 0.055f;
    return select(hi, lo, c <= 0.0031308f);
}

/// The palette at `t` in [0, 1), looping back to the first colour.
/// `labCount` is the number of *floats* — SwiftUI's `.floatArray` passes
/// the array length — so the number of colours is a third of it.
static float3 lab_palette_linear(float t, device const float *lab, int labCount) {
    int n = labCount / 3;
    if (n <= 0) return float3(0.5f);
    if (n == 1) return lab_oklab_to_linear(float3(lab[0], lab[1], lab[2]));
    float u = fract(t) * float(n);
    int i = int(u);
    int j = (i + 1) % n;
    float f = u - float(i);
    f = f * f * (3.0f - 2.0f * f);
    float3 a = float3(lab[i * 3], lab[i * 3 + 1], lab[i * 3 + 2]);
    float3 b = float3(lab[j * 3], lab[j * 3 + 1], lab[j * 3 + 2]);
    return lab_oklab_to_linear(mix(a, b, f));
}

// MARK: - Noise

static float lab_hash(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.x + p3.y) * p3.z);
}

static float lab_noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0f - 2.0f * f);
    return mix(mix(lab_hash(i + float2(0, 0)), lab_hash(i + float2(1, 0)), u.x),
               mix(lab_hash(i + float2(0, 1)), lab_hash(i + float2(1, 1)), u.x), u.y);
}

static float lab_fbm(float2 p) {
    float v = 0.0f, a = 0.5f;
    float2x2 rot = float2x2(0.8f, 0.6f, -0.6f, 0.8f);
    for (int i = 0; i < 5; i++) {
        v += a * lab_noise(p);
        p = rot * p * 2.0f + 100.0f;
        a *= 0.5f;
    }
    return v;
}

// MARK: - Aurora (colorEffect)
//
// A domain-warped noise field — noise fed through itself twice — mapped
// onto the palette. This is the standard "ethereal" construction: the
// warping is what turns blobs into flowing sheets. `audio` widens the
// warp and lifts the brightness, so sound makes it churn rather than
// just flash.

[[ stitchable ]] half4 labAurora(float2 position, half4 color,
                                 float2 size, float time, float intensity, float audio,
                                 device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.94f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);

    float2 p = uv * 1.7f;
    float warp = 2.5f + intensity * 3.0f + audio * 3.0f;
    float2 q = float2(lab_fbm(p + time * 0.12f), lab_fbm(p + float2(5.2f, 1.3f) - time * 0.09f));
    float2 w = float2(lab_fbm(p + warp * q + float2(1.7f, 9.2f) + time * 0.15f),
                      lab_fbm(p + warp * q + float2(8.3f, 2.8f) - time * 0.11f));
    float v = lab_fbm(p + warp * w);

    // A periodic angle term, not the raw angle: atan2 jumps at ±π and the
    // seam drew a hard line across the disc.
    float angle = atan2(uv.y, uv.x);
    float3 c = lab_palette_linear(v * 1.3f + 0.12f * sin(angle + time * 0.2f) + time * 0.03f, lab, labCount);

    // Sheets: brightness follows the field's ridges, so there are veils
    // of light with dark between them rather than an even wash. Kept
    // under 1 so the palette's colour survives — pushed past it the
    // channels clip and everything goes white.
    float veil = smoothstep(0.3f, 0.8f, v);
    float bright = (0.22f + 0.65f * veil) * (0.8f + intensity * 0.35f) * (1.0f + audio * 0.45f);
    // Darker toward the rim, then a thin lit edge.
    float depth = 1.0f - 0.55f * smoothstep(0.3f, 1.0f, r);
    float rim = smoothstep(0.86f, 0.97f, r) * (1.0f - smoothstep(0.97f, 1.0f, r));
    float3 lin = c * bright * depth + c * rim * 0.9f;

    float alpha = mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(alpha), half(alpha));
}

// MARK: - Orb (colorEffect)
//
// A sphere shaded in the shader: a normal from the disc position, a key
// light, a Fresnel rim, a specular hit, and the palette swirling across
// the surface as if it were inside. No geometry, no RealityKit — this is
// the "Siri orb" construction, and it is what a 3D-looking ball in a 2D
// app usually is.

[[ stitchable ]] half4 labOrb(float2 position, half4 color,
                              float2 size, float time, float intensity, float audio,
                              device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float radius = 0.96f + audio * 0.03f;
    float r = length(uv) / radius;
    float mask = 1.0f - smoothstep(0.985f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float rr = min(r, 1.0f);
    float3 n = float3(uv / radius, sqrt(max(0.0f, 1.0f - rr * rr)));

    // Swirl: the surface colour comes from noise on a coordinate that
    // turns with time and is squeezed toward the edge, so the pattern
    // reads as wrapping round the sphere.
    float a = time * 0.35f;
    float2x2 rot = float2x2(cos(a), sin(a), -sin(a), cos(a));
    float2 sp = rot * (n.xy * (1.2f + 0.4f * (1.0f - n.z)));
    float swirl = lab_fbm(sp * 2.2f + float2(time * 0.2f, -time * 0.13f) + audio * 0.6f);
    float3 base = lab_palette_linear(swirl * 1.1f + time * 0.04f, lab, labCount);

    float3 L = normalize(float3(-0.55f, 0.7f, 0.6f));
    float diffuse = max(dot(n, L), 0.0f);
    float fresnel = pow(1.0f - n.z, 2.2f);
    float3 V = float3(0, 0, 1);
    float3 H = normalize(L + V);
    float spec = pow(max(dot(n, H), 0.0f), 90.0f);

    float glow = (0.55f + intensity * 0.4f) * (1.0f + audio * 0.45f);
    float3 lin = base * (0.3f + 0.7f * diffuse) * glow
               + base * fresnel * 0.9f
               + float3(1.0f) * spec * 0.5f;

    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Bloom (layerEffect)
//
// Samples the layer beneath in two rings around each pixel and adds the
// average back on top: a cheap radial blur, added, which is what "glow"
// is. `radius` is in pixels and must be within the `maxSampleOffset` the
// call site declares. 24 taps — enough for a smooth halo at ring widths,
// cheap enough for 120Hz.

[[ stitchable ]] half4 labBloom(float2 position, SwiftUI::Layer layer,
                                float radius, float strength)
{
    half4 src = layer.sample(position);
    half4 acc = half4(0);
    // The sample ring is rotated by a per-pixel hash so the tap pattern
    // dissolves into grain instead of drawing a 16-point star at wide
    // radii — the standard trick for cheap blurs.
    float jitter = lab_hash(position) * 2.0f * M_PI_F;
    const int taps = 20;
    for (int i = 0; i < taps; i++) {
        float a = jitter + float(i) / float(taps) * 2.0f * M_PI_F;
        float2 d = float2(cos(a), sin(a));
        acc += layer.sample(position + d * radius);
        acc += layer.sample(position + d * radius * 0.62f);
        if (i % 2 == 0) acc += layer.sample(position + d * radius * 0.3f);
    }
    acc /= half(taps * 2 + taps / 2);
    // Added, not blended: light accumulates. The source keeps its own
    // alpha; the halo carries the blurred alpha so it fades to nothing.
    half4 halo = acc * half(strength);
    return half4(src.rgb + halo.rgb, min(half(1), src.a + halo.a));
}

// MARK: - Ripple (distortionEffect)
//
// Pushes pixels along the radius by a travelling sine, damped toward the
// centre so the ring's core stays put and its edge wobbles. `amp` is in
// pixels. The Lab drives `amp` from audio, so a beat sends a ring out.

[[ stitchable ]] float2 labRipple(float2 position, float2 size, float time, float amp)
{
    float2 c = size * 0.5f;
    float2 d = position - c;
    float r = length(d) / (min(size.x, size.y) * 0.5f);
    if (r < 0.001f) return position;
    float wave = sin(r * 18.0f - time * 7.0f);
    float falloff = smoothstep(0.15f, 0.6f, r);
    return position - normalize(d) * wave * amp * falloff;
}
