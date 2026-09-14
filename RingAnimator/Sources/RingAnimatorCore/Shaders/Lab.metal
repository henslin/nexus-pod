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

static float lab_fbm_n(float2 p, int octaves) {
    float v = 0.0f, a = 0.5f;
    float2x2 rot = float2x2(0.8f, 0.6f, -0.6f, 0.8f);
    for (int i = 0; i < octaves; i++) {
        v += a * lab_noise(p);
        p = rot * p * 2.0f + 100.0f;
        a *= 0.5f;
    }
    return v;
}

static float lab_fbm(float2 p) { return lab_fbm_n(p, 5); }

// MARK: - Aurora (colorEffect)
//
// A domain-warped noise field — noise fed through itself twice — mapped
// onto the palette. This is the standard "ethereal" construction: the
// warping is what turns blobs into flowing sheets. `audio` widens the
// warp and lifts the brightness, so sound makes it churn rather than
// just flash.

// `knobs`: warp, scale, octaves, veil contrast, rim, colour drift — see
// `LabExperiment.parameters` for `.aurora`, in that order.
[[ stitchable ]] half4 labAurora(float2 position, half4 color,
                                 float2 size, float time, float intensity, float audio,
                                 device const float *knobs, int knobCount,
                                 device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.94f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);

    float kWarp = knobs[0], kScale = knobs[1], kVeil = knobs[3], kRim = knobs[4], kDrift = knobs[5];
    int octaves = clamp(int(knobs[2] + 0.5f), 1, 6);

    float2 p = uv * kScale;
    float warp = kWarp * (0.7f + intensity * 0.6f) + audio * 3.0f;
    float2 q = float2(lab_fbm_n(p + time * 0.12f, octaves), lab_fbm_n(p + float2(5.2f, 1.3f) - time * 0.09f, octaves));
    float2 w = float2(lab_fbm_n(p + warp * q + float2(1.7f, 9.2f) + time * 0.15f, octaves),
                      lab_fbm_n(p + warp * q + float2(8.3f, 2.8f) - time * 0.11f, octaves));
    float v = lab_fbm_n(p + warp * w, octaves);

    // A periodic angle term, not the raw angle: atan2 jumps at ±π and the
    // seam drew a hard line across the disc.
    float angle = atan2(uv.y, uv.x);
    float3 c = lab_palette_linear(v * 1.3f + 0.12f * sin(angle + time * 0.2f) + time * kDrift, lab, labCount);

    // Sheets: brightness follows the field's ridges, so there are veils
    // of light with dark between them rather than an even wash. Kept
    // under 1 so the palette's colour survives — pushed past it the
    // channels clip and everything goes white.
    float veil = smoothstep(0.3f, 0.8f, v);
    float floorLight = 0.6f - 0.5f * kVeil;
    float bright = (floorLight * 0.4f + 0.65f * veil + 0.2f * (1.0f - kVeil)) * (0.8f + intensity * 0.35f) * (1.0f + audio * 0.45f);
    // Darker toward the rim, then a thin lit edge.
    float depth = 1.0f - 0.55f * smoothstep(0.3f, 1.0f, r);
    float rim = smoothstep(0.86f, 0.97f, r) * (1.0f - smoothstep(0.97f, 1.0f, r));
    float3 lin = c * bright * depth + c * rim * kRim;

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

// `knobs`: light angle (degrees), rim, highlight, gloss, swirl scale,
// swirl speed — `.orb`'s parameters in order.
[[ stitchable ]] half4 labOrb(float2 position, half4 color,
                              float2 size, float time, float intensity, float audio,
                              device const float *knobs, int knobCount,
                              device const float *lab, int labCount)
{
    float kLight = knobs[0] * M_PI_F / 180.0f, kRim = knobs[1], kSpec = knobs[2], kGloss = knobs[3];
    float kSwirl = knobs[4], kSwirlSpeed = knobs[5];
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
    float a = time * kSwirlSpeed;
    float2x2 rot = float2x2(cos(a), sin(a), -sin(a), cos(a));
    float2 sp = rot * (n.xy * (1.2f + 0.4f * (1.0f - n.z)));
    float swirl = lab_fbm(sp * kSwirl + float2(time * 0.2f, -time * 0.13f) + audio * 0.6f);
    float3 base = lab_palette_linear(swirl * 1.1f + time * 0.04f, lab, labCount);

    // Light angle: 0° is right, 90° is up (screen y is down, so flip).
    float3 L = normalize(float3(cos(kLight) * 0.8f, -sin(kLight) * 0.8f, 0.6f));
    float diffuse = max(dot(n, L), 0.0f);
    float fresnel = pow(1.0f - n.z, 2.2f);
    float3 V = float3(0, 0, 1);
    float3 H = normalize(L + V);
    float spec = pow(max(dot(n, H), 0.0f), kGloss);

    float glow = (0.55f + intensity * 0.4f) * (1.0f + audio * 0.45f);
    float3 lin = base * (0.3f + 0.7f * diffuse) * glow
               + base * fresnel * kRim
               + float3(1.0f) * spec * kSpec;

    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Bloom (layerEffect)
//
// Samples the layer beneath in two rings around each pixel and adds the
// average back on top: a cheap radial blur, added, which is what "glow"
// is. `radius` is in pixels and must be within the `maxSampleOffset` the
// call site declares. 24 taps — enough for a smooth halo at ring widths,
// cheap enough for 120Hz.

static half4 lab_bright(half4 c, half threshold) {
    // Luminance above the threshold, rescaled, so only the highlights
    // feed the halo when a threshold is set.
    half l = dot(c.rgb, half3(0.2126h, 0.7152h, 0.0722h));
    half k = threshold <= 0.0h ? 1.0h : clamp((l - threshold) / max(1.0h - threshold, 0.01h), 0.0h, 1.0h);
    return c * k;
}

[[ stitchable ]] half4 labBloom(float2 position, SwiftUI::Layer layer,
                                float radius, float strength, float threshold)
{
    half4 src = layer.sample(position);
    half4 acc = half4(0);
    half th = half(threshold);
    // The sample ring is rotated by a per-pixel hash so the tap pattern
    // dissolves into grain instead of drawing a 16-point star at wide
    // radii — the standard trick for cheap blurs.
    float jitter = lab_hash(position) * 2.0f * M_PI_F;
    const int taps = 20;
    for (int i = 0; i < taps; i++) {
        float a = jitter + float(i) / float(taps) * 2.0f * M_PI_F;
        float2 d = float2(cos(a), sin(a));
        acc += lab_bright(layer.sample(position + d * radius), th);
        acc += lab_bright(layer.sample(position + d * radius * 0.62f), th);
        if (i % 2 == 0) acc += lab_bright(layer.sample(position + d * radius * 0.3f), th);
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

[[ stitchable ]] float2 labRipple(float2 position, float2 size, float time, float amp,
                                  float freq, float waveSpeed, float hold)
{
    float2 c = size * 0.5f;
    float2 d = position - c;
    float r = length(d) / (min(size.x, size.y) * 0.5f);
    if (r < 0.001f) return position;
    float wave = sin(r * freq - time * waveSpeed);
    float falloff = smoothstep(hold, hold + 0.45f, r);
    return position - normalize(d) * wave * amp * falloff;
}

// MARK: - Refraction (layerEffect)
//
// A glass sphere over whatever is beneath. Inside the lens each pixel
// samples the layer from where a sphere would bend the ray toward it —
// the standard lens approximation: offset toward the centre by an amount
// that grows with the surface slope. Outside the lens, the layer passes
// through untouched. A Fresnel rim and a specular hit sell the sphere.
// `center` and `radius` are in pixels.

[[ stitchable ]] half4 labRefract(float2 position, SwiftUI::Layer layer,
                                  float2 center, float radius,
                                  float strength, float rim, float spec, float lightAngle)
{
    float2 d = (position - center) / radius;
    float r2 = dot(d, d);
    if (r2 >= 1.0f) return layer.sample(position);
    float z = sqrt(1.0f - r2);
    float3 n = float3(d, z);
    // Bend: a glass sphere *minifies* — the ray reaching a pixel near the
    // rim came from further out — so sample outward, by an amount that
    // grows with the surface slope (flat at the centre, steep at the
    // rim). The first cut sampled inward, which is a magnifier, and it
    // pushed the ring out past the lens leaving a dark ball. The offset
    // eases to zero over the last 12% so the lens edge is continuous
    // with what is outside it rather than a hard cut.
    float rr = sqrt(r2);
    float ease = 1.0f - smoothstep(0.88f, 1.0f, rr);
    float2 offset = d * (1.0f - z) * strength * radius * 1.4f * ease;
    half4 under = layer.sample(position + offset);

    float fresnel = pow(1.0f - z, 2.5f);
    float3 L = normalize(float3(cos(lightAngle) * 0.8f, -sin(lightAngle) * 0.8f, 0.6f));
    float3 H = normalize(L + float3(0, 0, 1));
    float hit = pow(max(dot(n, H), 0.0f), 140.0f);
    // A thin bright line at the very edge — the rim a glass ball has.
    float edgeLine = smoothstep(0.93f, 0.985f, rr) * (1.0f - smoothstep(0.985f, 1.0f, rr));
    float light = fresnel * rim * 0.5f + edgeLine * rim * 0.6f + hit * spec;

    half3 rgb = under.rgb * half(1.0f - 0.2f * fresnel) + half3(light);
    half a = max(under.a, half(min(light, 1.0f)));
    return half4(rgb, a);
}

// MARK: - Chromatic (layerEffect)
//
// The three channels sampled from three slightly different places. With
// `radial` 1 the offset is along the radius from `center`, so the fringe
// grows toward the rim the way a real lens's does; with 0 it is a fixed
// sideways shift, the "glitch" look.

[[ stitchable ]] half4 labChromatic(float2 position, SwiftUI::Layer layer,
                                    float2 center, float radius, float split, float radial)
{
    float2 d = position - center;
    float r = length(d) / radius;
    float2 dir = mix(float2(1.0f, 0.0f), r > 0.001f ? normalize(d) : float2(1.0f, 0.0f), radial);
    float amount = split * mix(1.0f, r, radial);
    half4 rC = layer.sample(position + dir * amount);
    half4 gC = layer.sample(position);
    half4 bC = layer.sample(position - dir * amount);
    return half4(rC.r, gC.g, bC.b, max(max(rC.a, gC.a), bC.a));
}
