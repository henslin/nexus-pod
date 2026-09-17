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
    float kBands = knobCount > 6 ? knobs[6] : 0.0f;
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
    // Bands: sharpen the swirl into glossy stripes — the marble / lollipop
    // reference — by pushing the noise through a steep curve.
    float banded = 0.5f + 0.5f * sin(swirl * 12.0f + time * 0.5f);
    swirl = mix(swirl, banded, kBands);
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
    float rj = lab_hash(position + 17.3f);
    const int taps = 24;
    // Angle *and* radius jittered per pixel, the radius on a golden-ratio
    // ladder, so the taps cover the disc evenly and no ring of samples
    // draws itself as a band — three fixed radii did, at wide settings.
    for (int i = 0; i < taps; i++) {
        float a = jitter + float(i) / float(taps) * 2.0f * M_PI_F;
        float rs = sqrt(fract(rj + float(i) * 0.618034f));
        float2 d = float2(cos(a), sin(a)) * radius * rs;
        acc += lab_bright(layer.sample(position + d), th);
    }
    acc /= half(taps);
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

// MARK: - Liquid (colorEffect)
//
// Metaballs. Each blob contributes size²/d² to a field; the surface is
// where the field crosses a threshold, so two blobs approaching merge
// into one shape before they touch — the mercury look. Blob positions
// are functions of time (no state), each on its own Lissajous orbit.
// Colour is the field-weighted mix of each blob's palette colour, so
// where blobs meet, colours blend. A normal from the field's gradient
// gives the surface sphere shading.
//
// `knobs`: blobs, size, goo, orbit, edge, shade — `.liquid`'s order.

static float2 lab_blob_pos(int i, float time, float orbit, float audio) {
    float fi = float(i);
    float wa = 0.31f + 0.13f * fi, wb = 0.23f + 0.17f * fi;
    float ph = fi * 1.7f;
    float r = (0.28f + 0.12f * fract(fi * 0.618f)) * (1.0f + audio * 0.9f);
    return float2(cos(time * orbit * wa + ph), sin(time * orbit * wb + ph * 0.7f)) * r;
}

[[ stitchable ]] half4 labLiquid(float2 position, half4 color,
                                 float2 size, float time, float intensity, float audio,
                                 device const float *knobs, int knobCount,
                                 device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float rdisc = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, rdisc);
    if (mask <= 0.0f) return half4(0);

    int blobs = clamp(int(knobs[0] + 0.5f), 2, 8);
    float bsize = knobs[1] * (0.8f + intensity * 0.4f);
    float goo = knobs[2];
    float orbit = knobs[3];
    float edge = knobs[4];
    float shade = knobs[5];
    int n = max(labCount / 3, 1);

    // Field and colour, plus the field at two offsets for a gradient.
    float field = 0.0f, fx = 0.0f, fy = 0.0f;
    float3 col = float3(0);
    const float eps = 0.02f;
    for (int i = 0; i < blobs; i++) {
        float2 c = lab_blob_pos(i, time, orbit, audio);
        float s2 = bsize * bsize;
        float d2 = max(dot(uv - c, uv - c), 1e-4f);
        float f = s2 / d2;
        field += f;
        fx += s2 / max(dot(uv + float2(eps, 0) - c, uv + float2(eps, 0) - c), 1e-4f);
        fy += s2 / max(dot(uv + float2(0, eps) - c, uv + float2(0, eps) - c), 1e-4f);
        float3 bc = lab_oklab_to_linear(float3(lab[(i % n) * 3], lab[(i % n) * 3 + 1], lab[(i % n) * 3 + 2]));
        col += bc * f;
    }
    col /= max(field, 1e-4f);

    // Threshold 1 is the classic surface; `goo` widens the merge zone.
    float threshold = 1.0f / (1.0f + goo * 4.0f);
    float softness = mix(0.5f, 0.008f, edge * edge);
    float surface = smoothstep(threshold - softness, threshold + softness, field * 0.35f);
    if (surface <= 0.001f) return half4(0);

    // Shading from the field gradient — steep where the surface curves.
    float2 g = float2(fx - field, fy - field) / eps;
    // The gradient is steep near each blob's core and flat between them;
    // normalising it gives a dome per blob and a saddle at each merge,
    // which is the mercury look once lit.
    float3 nrm = normalize(float3(-g * 0.12f, 1.0f));
    float3 L = normalize(float3(-0.5f, 0.6f, 0.65f));
    float diffuse = 0.35f + 0.65f * max(dot(nrm, L), 0.0f);
    float spec = pow(max(dot(nrm, normalize(L + float3(0, 0, 1))), 0.0f), 40.0f);
    float rimL = pow(1.0f - nrm.z, 1.5f);
    float lit = mix(1.0f, diffuse, shade);
    float3 lin = col * lit * (0.9f + intensity * 0.3f) + float3(spec * shade * 0.7f) + col * rimL * shade * 0.6f;

    float a = surface * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(a), half(a));
}

// MARK: - Rays (layerEffect)
//
// Radial blur, added: for each pixel, march back toward the centre and
// accumulate what is there with a decaying weight. Bright things throw
// streaks outward. `twist` rotates the march direction with distance,
// bending straight rays into a swirl. `reach` is in pixels and must be
// within `maxSampleOffset`.

[[ stitchable ]] half4 labRays(float2 position, SwiftUI::Layer layer,
                               float2 center, float reach, float strength, float decay, float twist)
{
    half4 src = layer.sample(position);
    float2 d = position - center;
    float r = length(d);
    if (r < 0.5f) return src;
    float2 dir = d / r;
    const int steps = 24;
    half4 acc = half4(0);
    half w = half(1);
    half total = half(0);
    float jitter = lab_hash(position) * 0.9f;
    for (int i = 1; i <= steps; i++) {
        float t = (float(i) - jitter) / float(steps);
        float a = twist * t * 1.2f;
        float2 rd = float2(dir.x * cos(a) - dir.y * sin(a), dir.x * sin(a) + dir.y * cos(a));
        float2 sp = position - rd * reach * t;
        acc += layer.sample(sp) * w;
        total += w;
        w *= half(decay);
    }
    acc /= max(total, half(0.001));
    half4 rays = acc * half(strength);
    return half4(src.rgb + rays.rgb, min(half(1), src.a + rays.a));
}

// MARK: - Sphere (colorEffect)
//
// The After Effects "gradient sphere" recipe (reference video, Chris,
// 2026-09-14), as one shader: a small gradient shape → box blur →
// turbulent displace → lens → rim. Deep Glow is the Bloom post effect
// on top. Each stage is a knob group here so his numbers have somewhere
// to go:
//
//   shape (0 star, 1 blob, 2 ring), source size, blur
//   displace amount, displace size, complexity (octaves), evolution
//   wiggle (the source wanders), curvature (the lens), rim, exposure
//
// `knobs` in that order — `.sphere`'s parameters.

static float lab_star_radius(float theta, float points) {
    return 0.62f + 0.3f * cos(theta * points);
}

[[ stitchable ]] half4 labSphere(float2 position, half4 color,
                                 float2 size, float time, float intensity, float audio,
                                 device const float *knobs, int knobCount,
                                 device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.985f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);

    int shape = clamp(int(knobs[0] + 0.5f), 0, 2);
    float srcSize = knobs[1];
    float blur = knobs[2];
    float dispAmount = knobs[3] * (0.7f + intensity * 0.6f) + audio * 0.6f;
    float dispSize = knobs[4];
    int octaves = clamp(int(knobs[5] + 0.5f), 1, 5);
    float evolution = knobs[6];
    float wiggle = knobs[7];
    float curvature = knobs[8];
    float rimAmount = knobs[9];
    float exposure = knobs[10] * (1.0f + audio * 0.5f);

    // Lens: map the disc onto a sphere's surface. Positive curvature
    // pinches the source toward the rim (CC Lens with high convergence),
    // negative bulges it. `z` is the sphere height at this pixel.
    float rr = min(r, 1.0f);
    float z = sqrt(max(0.0f, 1.0f - rr * rr));
    float lensScale = pow(max(z, 0.06f), -curvature * 1.4f);
    float2 p = uv * lensScale;

    // Wiggle: the source wanders on a slow Lissajous, like the expression
    // on his layer position.
    float2 wander = float2(sin(time * 0.37f), cos(time * 0.53f)) * wiggle * 0.35f;
    p -= wander;

    // Turbulent displace: push the sampling point by a noise vector.
    float2 np = p * dispSize + float2(time * evolution * 0.15f, -time * evolution * 0.11f);
    float2 disp = float2(lab_fbm_n(np, octaves), lab_fbm_n(np + float2(7.1f, 3.3f), octaves)) - 0.5f;
    p += disp * dispAmount;

    // The source: a shape with a soft (blurred) edge, in a gradient.
    float pr = length(p) / max(srcSize, 0.02f);
    float theta = atan2(p.y, p.x);
    float sd;
    if (shape == 0)      sd = pr - lab_star_radius(theta, 5.0f);
    else if (shape == 1) sd = pr - (0.75f + 0.12f * sin(theta * 3.0f + time * 0.4f));
    else                 sd = abs(pr - 0.7f) - 0.14f;
    float soft = 0.02f + blur * 0.9f;
    float body = 1.0f - smoothstep(-soft, soft, sd);
    // Gradient across the source, top to bottom, through the palette.
    float g = clamp((p.y / max(srcSize, 0.02f)) * 0.5f + 0.5f, 0.0f, 1.0f);
    float3 col = lab_palette_linear(g * 0.9f + time * 0.02f, lab, labCount);

    // Rim: a thin bright line at the sphere's edge, in the colour the
    // source has near that edge — so the rim is pink where the pink is.
    float rimLine = smoothstep(0.90f, 0.975f, rr) * (1.0f - smoothstep(0.975f, 1.0f, rr));
    float3 rimCol = lab_palette_linear(0.5f + 0.5f * sin(theta * 1.0f + time * 0.3f), lab, labCount);
    float fresnel = pow(1.0f - z, 3.0f);

    float3 lin = col * body * exposure
               + rimCol * (rimLine * rimAmount * 0.9f + fresnel * body * 0.6f);
    float a = mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(a), half(a));
}

// MARK: - Kaleido (layerEffect)
//
// Folds the angle around `center` into `segments` mirrored wedges and
// samples the layer there. Anything under it becomes a mandala; the
// ring becomes a flower. `rotate` spins the fold.

[[ stitchable ]] half4 labKaleido(float2 position, SwiftUI::Layer layer,
                                  float2 center, float segments, float rotate, float mixAmount)
{
    float2 d = position - center;
    float r = length(d);
    float a = atan2(d.y, d.x) + rotate;
    float seg = 2.0f * M_PI_F / max(segments, 1.0f);
    float folded = fmod(fmod(a, seg) + seg, seg);
    if (folded > seg * 0.5f) folded = seg - folded;
    float2 sp = center + float2(cos(folded), sin(folded)) * r;
    half4 k = layer.sample(sp);
    half4 src = layer.sample(position);
    return mix(src, k, half(mixAmount));
}

// MARK: - Dots (layerEffect)
//
// An LED matrix: the layer quantised to cells, each drawn as a round dot
// of the cell's centre colour. Bright cells get bigger dots, which is
// what a real matrix looks like through a diffuser. `cell` is in pixels.

[[ stitchable ]] half4 labDots(float2 position, SwiftUI::Layer layer,
                               float cell, float roundness, float gain, float lens)
{
    float2 c = floor(position / cell) * cell + cell * 0.5f;
    float2 d = (position - c) / (cell * 0.5f);
    // Lens: each dot bends what is behind it (reference: a dot grid over
    // a gradient sphere, every dot its own little glass bead) rather
    // than flat-sampling its centre.
    float dz = sqrt(max(0.0f, 1.0f - dot(d, d)));
    half4 s = lens > 0.0f ? layer.sample(c + d * (1.0f - dz) * lens * cell) : layer.sample(c);
    float lum = dot(float3(s.rgb), float3(0.2126f, 0.7152f, 0.0722f));
    float radius = mix(0.95f, 0.35f + 0.6f * lum, roundness);
    float dist = length(d);
    float dot = 1.0f - smoothstep(radius - 0.12f, radius + 0.05f, dist);
    half4 out = s * half(dot * gain);
    return half4(out.rgb, min(half(1), out.a));
}

// MARK: - Grain (layerEffect)
//
// Film: fine noise added, a vignette darkening the corners, optional
// desaturation. Everything looks shot rather than rendered.

[[ stitchable ]] half4 labGrain(float2 position, SwiftUI::Layer layer,
                                float2 size, float time, float amount, float vignette, float desat)
{
    half4 s = layer.sample(position);
    float n = lab_hash(position + fract(time * 13.7f) * 100.0f) - 0.5f;
    float2 uv = position / size * 2.0f - 1.0f;
    float vig = 1.0f - vignette * smoothstep(0.5f, 1.4f, length(uv));
    half lum = dot(s.rgb, half3(0.2126h, 0.7152h, 0.0722h));
    half3 rgb = mix(s.rgb, half3(lum), half(desat));
    rgb = rgb * half(vig) + half(n * amount) * s.a;
    return half4(rgb, s.a);
}

// MARK: - Tunnel (colorEffect)
//
// Rings flying at the viewer: the log of the radius, scrolled by time,
// so the rings accelerate toward the edge the way a tunnel does. Colour
// from the angle through the palette, twisted with depth.

[[ stitchable ]] half4 labTunnel(float2 position, half4 color,
                                 float2 size, float time, float intensity, float audio,
                                 device const float *knobs, int knobCount,
                                 device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, r);
    if (mask <= 0.0f || r < 0.001f) return half4(0);
    float kRings = knobs[0], kSpeed = knobs[1], kTwist = knobs[2], kGlow = knobs[3], kDepth = knobs[4];
    float depth = -log(max(r, 0.001f));               // 0 at the rim, large at the centre
    float a = atan2(uv.y, uv.x);
    float scroll = depth * kRings - time * kSpeed * (1.0f + audio * 0.8f);
    float ring = 0.5f + 0.5f * cos(scroll * 2.0f * M_PI_F);
    ring = pow(ring, 2.0f + kGlow * 6.0f);
    float t = a / (2.0f * M_PI_F) + depth * kTwist * 0.15f + time * 0.03f;
    float3 c = lab_palette_linear(t, lab, labCount);
    float fade = exp(-depth * kDepth);                 // the far end goes dark
    float3 lin = c * ring * fade * (0.8f + intensity * 0.6f) * (1.0f + audio * 0.5f);
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Ink (compute) — feedback simulation
//
// A fluid-ish trail buffer: each step, every texel takes the previous
// frame's colour from a little way *upstream* along a curl-noise flow
// (advection), fades it, and adds fresh ink from a few emitters orbiting
// the centre. The trails persist because the buffer does — this is the
// one thing a SwiftUI shader cannot do, since it never sees the previous
// frame. Ping-pong between two textures; the view presents the newest.
//
// `p` layout: time, dt, decay, flowScale, flowSpeed, injectRadius,
// emitterCount, audio, orbitRadius, swirl, then 3 floats per palette
// colour (linear rgb, up to 8).

struct InkParams {
    float time, dt, decay, flowScale, flowSpeed, injectRadius, emitters, audio, orbit, swirl;
    float3 colors[8];
};

static float2 ink_curl(float2 p, float t) {
    const float e = 0.01f;
    float n1 = lab_fbm_n(p + float2(0, e) + t, 3), n2 = lab_fbm_n(p - float2(0, e) + t, 3);
    float n3 = lab_fbm_n(p + float2(e, 0) + t, 3), n4 = lab_fbm_n(p - float2(e, 0) + t, 3);
    return float2((n1 - n2), -(n3 - n4)) / (2.0f * e);
}

kernel void inkStep(texture2d<half, access::sample> prev [[texture(0)]],
                    texture2d<half, access::write> next [[texture(1)]],
                    constant InkParams &p [[buffer(0)]],
                    uint2 gid [[thread_position_in_grid]])
{
    uint w = next.get_width(), h = next.get_height();
    if (gid.x >= w || gid.y >= h) return;
    float2 uv = (float2(gid) + 0.5f) / float2(w, h);
    float2 c = uv * 2.0f - 1.0f;
    float aspect = float(w) / float(h);
    c.x *= aspect;

    // Advect: sample upstream along the flow plus a swirl about the centre.
    float2 flow = ink_curl(c * p.flowScale, p.time * 0.1f) * p.flowSpeed;
    float2 tangent = float2(-c.y, c.x);
    flow += tangent * p.swirl;
    float2 src = uv - flow * p.dt / float2(aspect, 1.0f);
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    half4 prevC = prev.sample(s, src);
    half4 col = prevC * half(p.decay);

    // Inject: emitters on an orbit, each in its palette colour.
    int n = clamp(int(p.emitters), 1, 8);
    for (int i = 0; i < n; i++) {
        float ph = float(i) / float(n) * 2.0f * M_PI_F;
        float rad = p.orbit * (1.0f + p.audio * 0.5f);
        float2 e = float2(cos(p.time * 0.6f + ph), sin(p.time * 0.45f + ph * 1.3f)) * rad;
        float d = length(c - e);
        float ink = exp(-d * d / (p.injectRadius * p.injectRadius)) * (0.6f + p.audio);
        col.rgb += half3(p.colors[i]) * half(ink * p.dt * 18.0f);
        col.a = max(col.a, half(min(1.0f, ink * 2.0f)));
    }
    col.a = max(col.a * half(p.decay), half(0));
    next.write(min(col, half4(1)), gid);
}

// Presenting the ink buffer: a full-screen triangle pair sampling the
// newest texture, premultiplied so it composites over the stage.
struct InkVertexOut { float4 position [[position]]; float2 uv; };

vertex InkVertexOut inkVertex(uint vid [[vertex_id]]) {
    float2 quad[6] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(-1, 1), float2(1, -1), float2(1, 1) };
    InkVertexOut o;
    o.position = float4(quad[vid], 0, 1);
    o.uv = float2(quad[vid].x * 0.5f + 0.5f, 0.5f - quad[vid].y * 0.5f);
    return o;
}

fragment half4 inkFragment(InkVertexOut in [[stage_in]], texture2d<half> tex [[texture(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    half4 c = tex.sample(s, in.uv);
    // A disc: the buffer is square, the pod is round.
    float2 d = in.uv * 2.0f - 1.0f;
    half mask = half(1.0f - smoothstep(0.96f, 1.0f, length(d)));
    half a = min(half(1), max(c.a, max(c.r, max(c.g, c.b)))) * mask;
    return half4(c.rgb * mask, a);
}

// MARK: - Glitch (layerEffect)
//
// Digital damage: horizontal slices shifted sideways, a channel split,
// and blocks of noise, all gated so it happens in bursts. `trigger` is
// 0…1 — the beat, or a slow pulse when there is no audio.

[[ stitchable ]] half4 labGlitch(float2 position, SwiftUI::Layer layer,
                                 float2 size, float time, float amount, float trigger, float blocks)
{
    float t = floor(time * 12.0f);
    float rowKey = floor(position.y / (6.0f + 30.0f * (1.0f - amount)));
    float h = lab_hash(float2(rowKey, t));
    float gate = step(1.0f - trigger * 0.6f - amount * 0.15f, h);
    float shift = (lab_hash(float2(rowKey, t + 7.0f)) - 0.5f) * size.x * 0.25f * amount * gate;
    float split = 3.0f * amount * (0.3f + trigger);
    half4 r = layer.sample(position + float2(shift + split, 0));
    half4 g = layer.sample(position + float2(shift, 0));
    half4 b = layer.sample(position + float2(shift - split, 0));
    half4 c = half4(r.r, g.g, b.b, max(max(r.a, g.a), b.a));
    // Blocks: rectangles that go solid or invert for a frame.
    float2 cell = floor(position / (size / 8.0f));
    float bh = lab_hash(cell + t * 3.1f);
    if (bh > 1.0f - blocks * trigger * 0.5f && c.a > 0.01h) {
        c.rgb = half3(1) - c.rgb;
    }
    return c;
}

// MARK: - CRT (layerEffect)
//
// A tube: barrel curvature, scanlines, and a little phosphor bleed.

[[ stitchable ]] half4 labCRT(float2 position, SwiftUI::Layer layer,
                              float2 size, float curve, float lines, float bleed)
{
    float2 uv = position / size * 2.0f - 1.0f;
    float2 d = uv * (1.0f + curve * 0.25f * dot(uv, uv));
    float2 sp = (d * 0.5f + 0.5f) * size;
    if (any(abs(d) > 1.0f)) return half4(0);
    half4 c = layer.sample(sp);
    half4 l = layer.sample(sp + float2(bleed * 2.0f, 0));
    half4 rgt = layer.sample(sp - float2(bleed * 2.0f, 0));
    c.r = mix(c.r, l.r, half(bleed * 0.5f));
    c.b = mix(c.b, rgt.b, half(bleed * 0.5f));
    float scan = 0.5f + 0.5f * sin(sp.y * 3.14159f);
    c.rgb *= half(1.0f - lines * 0.5f * (1.0f - scan));
    // Corner darkening, like glass.
    c.rgb *= half(1.0f - 0.3f * curve * dot(uv, uv));
    return c;
}

// MARK: - Neon (layerEffect)
//
// Edges only: a Sobel on luminance, coloured by the source, so anything
// becomes its own wireframe — a neon sign of itself. `keep` mixes the
// original back in.

[[ stitchable ]] half4 labNeon(float2 position, SwiftUI::Layer layer,
                               float thickness, float gain, float keep)
{
    float t = thickness;
    half lum[9];
    int k = 0;
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        half4 s = layer.sample(position + float2(i, j) * t);
        lum[k++] = dot(s.rgb, half3(0.2126h, 0.7152h, 0.0722h)) * s.a;
    }
    half gx = -lum[0] - 2.0h * lum[3] - lum[6] + lum[2] + 2.0h * lum[5] + lum[8];
    half gy = -lum[0] - 2.0h * lum[1] - lum[2] + lum[6] + 2.0h * lum[7] + lum[8];
    half edge = min(half(1), sqrt(gx * gx + gy * gy) * half(gain));
    half4 src = layer.sample(position);
    half3 col = src.a > 0.01h ? src.rgb / max(src.a, 0.01h) : half3(1);
    half3 neon = (col * 0.6h + 0.4h) * edge;
    return half4(neon + src.rgb * half(keep), max(edge, src.a * half(keep)));
}

// MARK: - Frost (layerEffect)
//
// Frosted glass: each pixel samples from a jittered position, the
// jitter drawn from a noise field, so the image is scattered rather
// than blurred — the texture of real frost.

[[ stitchable ]] half4 labFrost(float2 position, SwiftUI::Layer layer,
                                float amount, float scale, float time)
{
    float2 n = float2(lab_noise(position / scale + time * 0.2f), lab_noise(position / scale + float2(31.7f, 9.2f) - time * 0.15f)) - 0.5f;
    float2 j = float2(lab_hash(position), lab_hash(position + 5.3f)) - 0.5f;
    float2 offset = (n * 2.0f + j * 0.6f) * amount;
    half4 acc = half4(0);
    acc += layer.sample(position + offset);
    acc += layer.sample(position + offset * 0.5f + float2(amount * 0.2f, 0));
    acc += layer.sample(position + offset * 0.5f - float2(0, amount * 0.2f));
    acc += layer.sample(position - offset * 0.3f);
    return acc * 0.25h;
}

// MARK: - Duotone (layerEffect)
//
// Recolours anything into the palette: luminance becomes a position
// along the sweep. The way to make a photo, or Sparks, wear the
// ring's colours.

[[ stitchable ]] half4 labDuotone(float2 position, SwiftUI::Layer layer,
                                  float mixAmount, float shift,
                                  device const float *lab, int labCount)
{
    half4 s = layer.sample(position);
    if (s.a < 0.001h) return s;
    float lum = float(dot(s.rgb / max(s.a, 0.01h), half3(0.2126h, 0.7152h, 0.0722h)));
    float3 c = lab_palette_linear(lum * 0.85f + shift, lab, labCount);
    half3 mapped = half3(lab_linear_to_srgb(c)) * s.a;
    return half4(mix(s.rgb, mapped, half(mixAmount)), s.a);
}

// MARK: - Spin (layerEffect)
//
// Angular motion blur about the centre: samples along an arc. A ring
// smears into itself; anything with detail streaks round.

[[ stitchable ]] half4 labSpin(float2 position, SwiftUI::Layer layer,
                               float2 center, float angle, float radialAmount)
{
    float2 d = position - center;
    float r = length(d);
    float a0 = atan2(d.y, d.x);
    half4 acc = half4(0);
    const int taps = 16;
    float jitter = lab_hash(position) - 0.5f;
    for (int i = 0; i < taps; i++) {
        float t = (float(i) + jitter) / float(taps) - 0.5f;
        float a = a0 + t * angle;
        float rr = r * (1.0f + t * radialAmount);
        acc += layer.sample(center + float2(cos(a), sin(a)) * rr);
    }
    return acc / half(taps);
}

// MARK: - Cells (colorEffect)
//
// Voronoi: the disc split into cells around drifting seeds, each in a
// palette colour, with lit edges where cells meet. Energy cells, a
// honeycomb, scales — depending on the knobs.

[[ stitchable ]] half4 labCells(float2 position, half4 color,
                                float2 size, float time, float intensity, float audio,
                                device const float *knobs, int knobCount,
                                device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float kScale = knobs[0], kDrift = knobs[1], kEdge = knobs[2], kFill = knobs[3], kSpeed = knobs[4];
    float2 p = uv * kScale;
    float2 ip = floor(p), fp = fract(p);
    float d1 = 8.0f, d2 = 8.0f;
    float2 cellId = float2(0);
    for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) {
        float2 g = float2(i, j);
        float2 h = float2(lab_hash(ip + g), lab_hash(ip + g + 19.1f));
        float2 o = 0.5f + kDrift * 0.5f * sin(time * kSpeed + h * 6.2831f);
        float2 diff = g + o - fp;
        float d = dot(diff, diff);
        if (d < d1) { d2 = d1; d1 = d; cellId = ip + g; }
        else if (d < d2) { d2 = d; }
    }
    float edge = sqrt(d2) - sqrt(d1);
    float line = 1.0f - smoothstep(0.0f, kEdge * 0.25f + 0.01f, edge);
    float3 cellColor = lab_palette_linear(lab_hash(cellId) + time * 0.02f, lab, labCount);
    float3 lin = cellColor * kFill * (0.5f + 0.5f * (1.0f - sqrt(d1))) * (0.8f + intensity * 0.4f)
               + cellColor * line * (1.2f + audio * 1.5f);
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Shapeshift (colorEffect)
//
// A filled shape morphing between a circle, a rounded square, a star
// and a blob, as a blend of signed distance fields — so the in-between
// shapes are real shapes, not cross-fades. Lit as a slab, edged in the
// palette. The pod becoming a glyph-like mark and back.

static float sd_circle(float2 p) { return length(p) - 0.72f; }
static float sd_square(float2 p) {
    float2 q = abs(p) - 0.58f;
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - 0.14f;
}
static float sd_star(float2 p) {
    float a = atan2(p.y, p.x);
    float r = 0.55f + 0.22f * cos(a * 5.0f);
    return length(p) - r;
}
static float sd_blob(float2 p, float t) {
    float a = atan2(p.y, p.x);
    float r = 0.66f + 0.08f * sin(a * 3.0f + t * 1.3f) + 0.05f * sin(a * 7.0f - t * 0.9f);
    return length(p) - r;
}

[[ stitchable ]] half4 labShapeshift(float2 position, half4 color,
                                     float2 size, float time, float intensity, float audio,
                                     device const float *knobs, int knobCount,
                                     device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kHold = knobs[0], kMorph = knobs[1], kEdge = knobs[2], kShade = knobs[3], kSpin = knobs[4];
    float a = time * kSpin;
    float2x2 rot = float2x2(cos(a), sin(a), -sin(a), cos(a));
    float2 p = rot * uv * (1.0f - audio * 0.1f);
    // Which two shapes, and how far between them.
    float cycle = time / max(kHold, 0.2f);
    int from = int(floor(cycle)) % 4;
    int to = (from + 1) % 4;
    float f = fract(cycle);
    float blend = smoothstep(1.0f - kMorph, 1.0f, f);
    float ds[4] = { sd_circle(p), sd_square(p), sd_star(p), sd_blob(p, time) };
    float d = mix(ds[from], ds[to], blend);
    float fill = 1.0f - smoothstep(-0.01f, 0.01f, d);
    float edge = (1.0f - smoothstep(0.0f, kEdge * 0.12f + 0.005f, abs(d)));
    // Slab lighting from the distance gradient near the edge.
    float dx = mix(ds[from], ds[to], blend);
    float2 e = float2(0.01f, 0);
    float gx = (mix(sd_circle(p + e.xy), sd_square(p + e.xy), 0.0f) - dx);
    float lightness = 0.75f + kShade * 0.5f * clamp(-d * 6.0f, 0.0f, 1.0f) + kShade * 0.2f * gx * 30.0f;
    float3 body = lab_palette_linear(0.15f + 0.4f * (uv.y * 0.5f + 0.5f) + time * 0.02f, lab, labCount) * lightness * (0.8f + intensity * 0.4f);
    float3 rim = lab_palette_linear(0.6f + time * 0.05f, lab, labCount) * (1.2f + audio);
    float3 lin = body * fill + rim * edge;
    float alpha = max(fill, edge);
    return half4(half3(lab_linear_to_srgb(lin)) * half(alpha), half(alpha));
}

// MARK: - Tiles (layerEffect)
//
// A panel of glass tiles over the layer — reference: an orange sphere
// behind a grid of square lenses, each tile bulging so the image inside
// it is bent and offset, with a soft grout line and a frosted haze.
// `coverage` is how much of the width, from the right, the panel spans,
// so it can sit over half the subject the way the reference does.

[[ stitchable ]] half4 labTiles(float2 position, SwiftUI::Layer layer,
                                float2 size, float cell, float bulge, float frost, float grout, float coverage, float orientation)
{
    float edgeX = size.x * (1.0f - coverage);
    if (position.x < edgeX) return layer.sample(position);
    float2 local = float2(position.x - edgeX, position.y);
    float2 c = floor(local / cell) * cell + cell * 0.5f;
    float2 uv = (local - c) / (cell * 0.5f);          // -1…1 within the tile
    // Flutes: a 1-D lens — reeded glass — vertical (1) or horizontal (2).
    if (orientation > 0.5f && orientation < 1.5f) uv.y = 0.0f;
    if (orientation >= 1.5f) uv.x = 0.0f;
    float r2 = min(dot(uv, uv), 1.0f);
    float z = sqrt(1.0f - r2);
    // A lens per tile: sample from further out toward the tile's edge.
    float2 offset = uv * (1.0f - z) * bulge * cell;
    float2 sp = position + offset;
    // Frost: a little scatter.
    float2 j = (float2(lab_hash(position), lab_hash(position + 3.1f)) - 0.5f) * frost * 6.0f;
    half4 s = layer.sample(sp + j);
    s = (s + layer.sample(sp - j) + layer.sample(sp + float2(j.y, -j.x))) / 3.0h;
    // Grout: a soft dark line at the tile edge and a lit bevel just inside.
    float edge = max(abs(uv.x), abs(uv.y));
    float line = smoothstep(0.86f, 1.0f, edge) * grout;
    float bevel = smoothstep(0.7f, 0.86f, edge) * (1.0f - smoothstep(0.86f, 0.95f, edge)) * grout * 0.5f;
    // Grout and haze only where there is something behind the glass —
    // over empty stage the panel would otherwise draw itself as a grey
    // grid, which is right for the reference's wall and wrong for a pod.
    half3 rgb = s.rgb * half(1.0f - line * 0.5f) + half3(bevel * 0.35f) * s.a;
    half haze = half(0.04f + frost * 0.06f) * s.a;
    return half4(rgb + haze, s.a);
}

// MARK: - Bubble (colorEffect)
//
// A soap bubble: a thin film whose colour comes from interference —
// the film's thickness, which varies with noise and drains downward,
// sets which wavelength survives. Rendered as the palette cycling with
// thickness, strongest at the rim where the film is seen edge-on
// (Fresnel), dark and see-through in the middle, with a soft palette
// glow pooling at the bottom the way the reference has. `knobs`:
// thickness, drain, iridescence, rim, pool, highlight, wobble.

[[ stitchable ]] half4 labBubble(float2 position, half4 color,
                                 float2 size, float time, float intensity, float audio,
                                 device const float *knobs, int knobCount,
                                 device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kThick = knobs[0], kDrain = knobs[1], kIrid = knobs[2], kRim = knobs[3], kPool = knobs[4], kSpec = knobs[5], kWobble = knobs[6];
    float kShell = knobCount > 7 ? knobs[7] : 0.0f;
    float kFloor = knobCount > 8 ? knobs[8] : 0.0f;
    float kBandSpeed = knobCount > 9 ? knobs[9] : 1.0f;
    float kBands = knobCount > 10 ? knobs[10] : 3.0f;
    // Wobble: the bubble is never quite round.
    float ang = atan2(uv.y, uv.x);
    float wob = 1.0f + kWobble * 0.03f * sin(ang * 3.0f + time * 1.7f) + kWobble * 0.02f * sin(ang * 5.0f - time * 2.3f) + audio * 0.03f;
    float r = length(uv) / wob;
    float mask = 1.0f - smoothstep(0.985f, 1.0f, r);
    if (mask <= 0.0f) {
        // Floor: a soft glow below the bubble, outside it — the
        // reference's lit floor.
        float2 fp = (uv - float2(0, 1.05f)) / float2(0.9f, 0.35f);
        float floorGlow = exp(-dot(fp, fp) * 1.5f) * kFloor * 0.5f * step(0.6f, uv.y);
        float3 fcol = lab_palette_linear(0.2f + time * 0.02f, lab, labCount) * floorGlow;
        return half4(half3(lab_linear_to_srgb(fcol)) * half(min(floorGlow, 1.0f)), half(min(floorGlow, 1.0f)));
    }
    float rr = min(r, 1.0f);
    float z = sqrt(max(0.0f, 1.0f - rr * rr));
    // Steep: the film only shows where it is seen edge-on, so the middle
    // stays black and see-through like the reference.
    float fresnel = pow(1.0f - z, 5.0f);

    // Film thickness: noise, plus drainage — thinner at the top, thicker
    // at the bottom, sliding down over time.
    float n = lab_fbm_n(uv * 2.5f + float2(0, time * kDrain * 0.3f), 3);
    float thickness = kThick * (0.6f + 0.8f * n) + kDrain * 0.5f * (uv.y * 0.5f + 0.5f) + audio * 0.3f;
    // Interference: the palette cycles with thickness × the view angle.
    float phase = thickness * (2.0f + 2.0f * (1.0f - z)) + time * 0.05f * kBandSpeed;
    float3 film = lab_palette_linear(phase, lab, labCount);

    // The rim: a thin bright band at the edge, plus the Fresnel-weighted
    // film. Shell widens the rim into a glass wall with its own inner
    // edge — the bonus reference's thick bubble — with the film's bands
    // sliding round inside it.
    float rimLine = smoothstep(0.93f, 0.985f, rr) * (1.0f - smoothstep(0.985f, 1.0f, rr));
    float innerEdge = 1.0f - kShell * 0.22f;
    float wall = smoothstep(innerEdge - 0.02f, innerEdge + 0.03f, rr) * (1.0f - smoothstep(0.975f, 1.0f, rr)) * kShell;
    float innerLine = smoothstep(innerEdge - 0.015f, innerEdge, rr) * (1.0f - smoothstep(innerEdge, innerEdge + 0.02f, rr)) * kShell;
    float bands = 0.5f + 0.5f * sin(ang * kBands + time * 1.2f * kBandSpeed + thickness * 4.0f);
    float3 lin = film * (fresnel * kIrid * 1.3f + rimLine * kRim * 1.6f)
               + film * wall * (0.35f + 0.65f * bands) * kIrid
               + film * innerLine * 0.8f * kRim;

    // The pool: palette glow gathering at the bottom *edge* — inside the
    // film, near the rim, not across the whole lower half (which filled
    // the bubble in). It fades toward the centre with the radius.
    float lower = smoothstep(0.3f, 1.0f, uv.y);
    float pool = lower * smoothstep(0.35f, 0.95f, rr);
    lin += lab_palette_linear(0.35f + time * 0.03f, lab, labCount) * pool * kPool * 0.6f;
    // The centre is see-through: only a breath of the film.
    lin += film * 0.012f;

    // Highlights: two small specular hits, upper left and lower right.
    float3 nrm = float3(uv / wob, z);
    float3 L1 = normalize(float3(-0.6f, -0.7f, 0.5f)), L2 = normalize(float3(0.7f, 0.6f, 0.4f));
    float s1 = pow(max(dot(nrm, normalize(L1 + float3(0, 0, 1))), 0.0f), 220.0f);
    float s2 = pow(max(dot(nrm, normalize(L2 + float3(0, 0, 1))), 0.0f), 400.0f);
    lin += float3(1.0f) * (s1 * 0.7f + s2 * 0.4f) * kSpec;

    float alpha = max(max(lin.r, lin.g), lin.b);
    alpha = min(1.0f, alpha * 1.3f + fresnel * 0.1f) * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(alpha));
}

// MARK: - Slices (colorEffect)
//
// A sphere cut into vertical slats — reference: a gradient sphere as a
// row of slivers, each a lens-shaped slice, colour running across, with
// a fine moiré in the slices. `knobs`: slats, duty, gap wobble, moiré,
// tilt, reflection.

[[ stitchable ]] half4 labSlices(float2 position, half4 color,
                                 float2 size, float time, float intensity, float audio,
                                 device const float *knobs, int knobCount,
                                 device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kSlats = knobs[0], kDuty = knobs[1], kWobble = knobs[2], kMoire = knobs[3], kTilt = knobs[4], kReflect = knobs[5];
    // The sphere sits in the top ~65%; its reflection, squashed, below.
    float2 p = uv;
    float reflected = 0.0f;
    float top = -0.3f;                // sphere centre y
    float radius = 0.6f;
    float2 sp = float2(p.x / radius, (p.y - top) / radius);
    float2 rp = float2(p.x / radius, (p.y - (top + radius * 2.05f)) / (radius * 0.5f));
    if (length(rp) < 1.0f && kReflect > 0.0f && p.y > top + radius) { sp = rp; reflected = 1.0f; }
    float r = length(sp);
    if (r > 1.0f) return half4(0);
    // Slats along x, rotated by tilt; each is on for `duty` of its pitch.
    float ca = cos(kTilt), sa = sin(kTilt);
    float x = sp.x * ca - sp.y * sa;
    float slot = x * kSlats * 0.5f + 0.5f;
    float idx = floor(slot);
    float f = fract(slot);
    float wob = kWobble * 0.15f * sin(idx * 1.3f + time * 1.1f) + audio * 0.1f;
    float on = 1.0f - smoothstep(kDuty + wob - 0.02f, kDuty + wob + 0.02f, f);
    if (on <= 0.0f) return half4(0);
    // Each slat is a lens: its own little sphere in cross-section.
    float sf = (f / max(kDuty + wob, 0.05f)) * 2.0f - 1.0f;
    float slatShade = sqrt(max(0.0f, 1.0f - sf * sf));
    float z = sqrt(max(0.0f, 1.0f - r * r));
    // Colour runs across x through the palette; the reflection takes the
    // palette from further along, like the reference's green/blue.
    float t = (sp.x * 0.5f + 0.5f) * 0.6f + reflected * 0.5f + time * 0.02f;
    float3 c = lab_palette_linear(t, lab, labCount);
    // Moiré: a fine ring pattern inside each slat.
    float moire = 1.0f - kMoire * 0.35f * (0.5f + 0.5f * sin(r * 260.0f + f * 40.0f));
    float3 lin = c * (0.45f + 0.55f * z * slatShade) * moire * (0.85f + intensity * 0.3f);
    if (reflected > 0.0f) lin *= 0.75f * kReflect;
    return half4(half3(lab_linear_to_srgb(lin)) * half(on), half(on));
}

// MARK: - Chrome (layerEffect)
//
// A material for anything with an alpha edge: a bevel from the alpha
// gradient gives a normal; the normal reflects a striped environment
// (chrome) and, with `iridescence`, an interference palette (the
// holographic bolt in the reference). `bevel` is the sample distance in
// pixels — the bevel's width.

[[ stitchable ]] half4 labChrome(float2 position, SwiftUI::Layer layer,
                                 float bevel, float iridescence, float shine, float keep, float time,
                                 device const float *lab, int labCount)
{
    half4 src = layer.sample(position);
    if (src.a < 0.002h) return src;
    float aL = float(layer.sample(position - float2(bevel, 0)).a);
    float aR = float(layer.sample(position + float2(bevel, 0)).a);
    float aU = float(layer.sample(position - float2(0, bevel)).a);
    float aD = float(layer.sample(position + float2(0, bevel)).a);
    float aL2 = float(layer.sample(position - float2(bevel * 2.0f, 0)).a);
    float aR2 = float(layer.sample(position + float2(bevel * 2.0f, 0)).a);
    float aU2 = float(layer.sample(position - float2(0, bevel * 2.0f)).a);
    float aD2 = float(layer.sample(position + float2(0, bevel * 2.0f)).a);
    float2 g = float2((aR + aR2) - (aL + aL2), (aD + aD2) - (aU + aU2));
    float3 n = normalize(float3(-g * 1.5f, 0.6f));
    // Environment: bright above, dark band, bright below — the stripes a
    // chrome capsule reflects. Reflected by the normal's y.
    float envY = n.y * 0.5f + 0.5f;
    float env = 0.25f + 0.75f * (smoothstep(0.0f, 0.25f, envY) * (1.0f - smoothstep(0.35f, 0.5f, envY)) + smoothstep(0.62f, 0.85f, envY));
    float3 L = normalize(float3(-0.4f, -0.6f, 0.7f));
    float spec = pow(max(dot(n, normalize(L + float3(0, 0, 1))), 0.0f), 40.0f);
    float edge = min(1.0f, length(g) * 1.2f);
    // Iridescence: palette by the normal's angle and the edge.
    float3 irid = lab_palette_linear(atan2(n.y, n.x) / 6.2831f + edge * 0.6f + time * 0.03f, lab, labCount);
    float3 base = mix(float3(env), lab_linear_to_srgb(irid) * (0.4f + env), iridescence);
    half3 rgb = half3(base) * src.a * half(shine) + half3(spec * 0.9f) * src.a + src.rgb * half(keep);
    return half4(min(rgb, half3(1)), src.a);
}

// MARK: - Holo (colorEffect)
//
// A holographic foil disc: a diffraction grating whose rainbow shifts
// with the viewing angle — the sticker on a credit card. The "view" is
// a slow virtual tilt (plus audio), so the bands sweep across. Two
// gratings at an angle to each other give the cross-hatched shimmer.

[[ stitchable ]] half4 labHolo(float2 position, half4 color,
                               float2 size, float time, float intensity, float audio,
                               device const float *knobs, int knobCount,
                               device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float kPitch = knobs[0], kTilt = knobs[1], kAngle = knobs[2], kMetal = knobs[3], kNoise = knobs[4];
    // Virtual view direction, wandering.
    float2 view = float2(sin(time * 0.5f), cos(time * 0.37f)) * kTilt * (1.0f + audio * 0.8f);
    // Two gratings: the phase along each grating direction, modulated by
    // the view — this is what makes the bands slide as you tilt.
    float a = kAngle;
    float2 g1 = float2(cos(a), sin(a)), g2 = float2(cos(a + 1.1f), sin(a + 1.1f));
    float n = lab_fbm_n(uv * 3.0f + time * 0.1f, 3) * kNoise;
    float p1 = dot(uv, g1) * kPitch + dot(view, g1) * 4.0f + n * 2.0f;
    float p2 = dot(uv, g2) * kPitch * 0.7f + dot(view, g2) * 4.0f - n * 1.5f;
    float3 c1 = lab_palette_linear(fract(p1 * 0.5f), lab, labCount);
    float3 c2 = lab_palette_linear(fract(p2 * 0.5f + 0.33f), lab, labCount);
    // Sharpness: a rainbow band is bright where the grating "focuses".
    float band1 = 0.5f + 0.5f * cos(p1 * 6.2831f);
    float band2 = 0.5f + 0.5f * cos(p2 * 6.2831f);
    // Broad, bright bands — the foil is mostly colour, with the darkest
    // point between bands still lit.
    float3 rainbow = c1 * (0.35f + 0.9f * pow(band1, 1.2f)) + c2 * (0.2f + 0.6f * pow(band2, 1.2f));
    // Metallic base: a silver disc with a soft specular that follows the view.
    float spec = pow(max(0.0f, 1.0f - length(uv - view * 0.6f) * 1.2f), 2.0f);
    float3 metal = float3(0.35f) + float3(0.5f) * spec;
    float3 lin = mix(rainbow * (0.7f + intensity * 0.5f), metal, kMetal) + rainbow * spec * 0.6f;
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Lenticular (colorEffect)
//
// A lenticular print: the disc under fine vertical lenses, each strip
// showing one of two pictures depending on the viewing angle — here
// two gradient spheres in different palette halves, swapping as a
// virtual view sweeps. Between the two the image tears the way the
// real thing does when you're halfway.

[[ stitchable ]] half4 labLenticular(float2 position, half4 color,
                                     float2 size, float time, float intensity, float audio,
                                     device const float *knobs, int knobCount,
                                     device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.985f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float kLenses = knobs[0], kSweep = knobs[1], kShade = knobs[2], kTear = knobs[3];
    float view = 0.5f + 0.5f * sin(time * kSweep) + audio * 0.3f;   // 0 picture A … 1 picture B
    float strip = fract(uv.x * kLenses * 0.5f);
    // Each lens shows A on one side of its width and B on the other; the
    // boundary slides with the view. Tear: the boundary is ragged.
    float tear = kTear * 0.2f * sin(uv.y * 20.0f + time * 2.0f);
    float showB = smoothstep(view - 0.06f + tear, view + 0.06f + tear, strip);
    float rr = min(r, 1.0f);
    float z = sqrt(max(0.0f, 1.0f - rr * rr));
    float shade = mix(1.0f, 0.35f + 0.65f * z, kShade);
    float3 a = lab_palette_linear((uv.y * 0.5f + 0.5f) * 0.4f + time * 0.02f, lab, labCount);
    float3 b = lab_palette_linear((uv.x * 0.5f + 0.5f) * 0.4f + 0.5f + time * 0.02f, lab, labCount);
    float3 lin = mix(a, b, showB) * shade * (0.8f + intensity * 0.4f);
    // The lens ridges: a faint bright line per lens.
    float ridge = 1.0f - smoothstep(0.0f, 0.08f, min(strip, 1.0f - strip));
    lin += float3(ridge * 0.12f);
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Moiré (colorEffect)
//
// Two fine ring gratings, one turning against the other: their
// interference makes patterns far larger than either — the moiré
// inside the sliced sphere reference, on its own. Coloured by the
// beat pattern through the palette. Hypnotic and nearly free.

[[ stitchable ]] half4 labMoire(float2 position, half4 color,
                                float2 size, float time, float intensity, float audio,
                                device const float *knobs, int knobCount,
                                device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float kPitch = knobs[0], kOffset = knobs[1], kSpeed = knobs[2], kContrast = knobs[3], kMode = knobs[4];
    // Two centres drifting apart and round each other.
    float2 c1 = float2(cos(time * kSpeed), sin(time * kSpeed * 0.8f)) * kOffset * (1.0f + audio * 0.6f);
    float2 c2 = -c1;
    float g1, g2;
    if (kMode < 0.5f) {
        g1 = 0.5f + 0.5f * cos(length(uv - c1) * kPitch);
        g2 = 0.5f + 0.5f * cos(length(uv - c2) * kPitch);
    } else {
        // Line gratings at a slowly changing angle.
        float a = time * kSpeed * 0.3f;
        g1 = 0.5f + 0.5f * cos((uv.x * cos(a) + uv.y * sin(a)) * kPitch);
        g2 = 0.5f + 0.5f * cos((uv.x * cos(a + kOffset) + uv.y * sin(a + kOffset)) * kPitch);
    }
    float beat = g1 * g2;
    float v = pow(beat, mix(1.0f, 3.0f, kContrast));
    float3 c = lab_palette_linear(v * 0.6f + atan2(uv.y, uv.x) / 6.2831f * 0.2f + time * 0.02f, lab, labCount);
    float3 lin = c * (0.15f + v * 1.1f) * (0.8f + intensity * 0.4f);
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Frost Orb (colorEffect)
//
// The light-mode family from the references: a frosted glass sphere on
// a pale ground with colour *inside* it — soft blobs of the palette
// drifting behind a milky shell — a white Fresnel rim, and a soft
// shadow beneath. The colour is a sum of gaussians round moving
// centres, which blurs for free. `knobs`: blobs, blur, frost, rim,
// shadow, drift, saturation.

[[ stitchable ]] half4 labFrostOrb(float2 position, half4 color,
                                   float2 size, float time, float intensity, float audio,
                                   device const float *knobs, int knobCount,
                                   device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    int blobs = clamp(int(knobs[0] + 0.5f), 1, 8);
    float kBlur = knobs[1], kFrost = knobs[2], kRim = knobs[3], kShadow = knobs[4], kDrift = knobs[5], kSat = knobs[6];
    float kCore = knobCount > 7 ? knobs[7] : 0.0f;
    int n = max(labCount / 3, 1);
    // The sphere sits slightly above centre so the shadow has room.
    float2 c = float2(0, -0.06f);
    float radius = 0.78f;
    float2 p = (uv - c) / radius;
    float r = length(p);

    // Shadow: a soft ellipse below, outside the sphere.
    float2 sp = (uv - float2(0, 0.62f)) / float2(0.75f, 0.22f);
    float shadow = exp(-dot(sp, sp) * 1.6f) * kShadow * 0.35f;

    float mask = 1.0f - smoothstep(0.985f, 1.0f, r);
    if (mask <= 0.0f) {
        // Only the shadow out here — a darkening, premultiplied.
        return half4(0, 0, 0, half(shadow));
    }
    float rr = min(r, 1.0f);
    float z = sqrt(max(0.0f, 1.0f - rr * rr));
    float fresnel = pow(1.0f - z, 2.0f);

    // Colour: gaussian blobs on slow orbits, each a palette colour,
    // summed (so they blend where they overlap) then normalised.
    float3 col = float3(0);
    float wsum = 0.0f;
    for (int i = 0; i < blobs; i++) {
        float fi = float(i);
        float2 bc = float2(sin(time * kDrift * (0.31f + fi * 0.11f) + fi * 1.9f),
                           cos(time * kDrift * (0.23f + fi * 0.13f) + fi * 1.3f)) * (0.35f + 0.15f * fract(fi * 0.618f)) * (1.0f + audio * 0.5f);
        float sigma = 0.25f + kBlur * 0.5f;
        float w = exp(-dot(p - bc, p - bc) / (2.0f * sigma * sigma)) * (0.8f + 0.4f * sin(time * 0.7f + fi));
        float3 bcol = lab_oklab_to_linear(float3(lab[(i % n) * 3], lab[(i % n) * 3 + 1], lab[(i % n) * 3 + 2]));
        col += bcol * w;
        wsum += w;
    }
    float coverage = min(1.0f, wsum * (0.9f + intensity * 0.5f));
    col = wsum > 0.0f ? col / wsum : float3(1);
    // Saturation: pull toward the colour's own luminance.
    float lum = dot(col, float3(0.2126f, 0.7152f, 0.0722f));
    col = mix(float3(lum), col, kSat);

    // Frost: the shell is milky white, more so toward the rim, and the
    // colour shows through the middle. Light-mode: the base is white.
    float milk = kFrost * (0.35f + 0.65f * fresnel);
    float3 lin = mix(mix(float3(1.0f), col, coverage * 0.85f), float3(1.0f), milk);
    // Rim: a bright white edge line, and a faint darker line just inside
    // so the sphere separates from a white ground.
    float rimLine = smoothstep(0.9f, 0.975f, rr) * (1.0f - smoothstep(0.975f, 1.0f, rr));
    float inner = smoothstep(0.82f, 0.9f, rr) * (1.0f - smoothstep(0.9f, 0.95f, rr));
    lin = lin * (1.0f - inner * 0.08f * kRim) + float3(1.0f) * rimLine * 0.5f * kRim;
    // A soft highlight upper-left, and an optional lit core — the
    // sphere glowing from inside, brighter with audio.
    float3 nrm = float3(p, z);
    float hl = pow(max(dot(nrm, normalize(float3(-0.5f, -0.6f, 0.65f))), 0.0f), 6.0f);
    lin = mix(lin, float3(1.0f), hl * 0.35f);
    float core = exp(-rr * rr * 3.0f) * kCore * (0.6f + audio * 0.8f);
    lin = mix(lin, lab_oklab_to_linear(float3(lab[0], lab[1], lab[2])) * 1.4f + 0.3f, core * 0.6f);

    float alpha = mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(alpha), half(alpha));
}

// MARK: - Globe (colorEffect)
//
// A clear glass sphere with liquid in it, the surface a wave — the
// pink-fill reference. Light-mode. `knobs`: level, wave, wave speed,
// tint, glass, tilt.

[[ stitchable ]] half4 labGlobe(float2 position, half4 color,
                                float2 size, float time, float intensity, float audio,
                                device const float *knobs, int knobCount,
                                device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kLevel = knobs[0], kWave = knobs[1], kSpeed = knobs[2], kTint = knobs[3], kGlass = knobs[4], kTilt = knobs[5];
    float kBubbles = knobCount > 6 ? knobs[6] : 0.0f;
    float kCaustic = knobCount > 7 ? knobs[7] : 1.0f;
    float ca = cos(kTilt), sa = sin(kTilt);
    float2 p = float2(uv.x * ca - uv.y * sa, uv.x * sa + uv.y * ca) / 0.9f;
    float r = length(p);
    float mask = 1.0f - smoothstep(0.985f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float rr = min(r, 1.0f);
    float z = sqrt(max(0.0f, 1.0f - rr * rr));
    float fresnel = pow(1.0f - z, 2.5f);

    float level = clamp(kLevel + audio * 0.2f, 0.0f, 1.0f);
    float surface = 1.0f - level * 2.0f;                          // y of the surface, screen-down
    float wave = kWave * 0.12f * sin(p.x * 5.0f + time * kSpeed * 2.0f)
               + kWave * 0.05f * sin(p.x * 11.0f - time * kSpeed * 3.1f + 1.0f)
               + audio * 0.06f * sin(p.x * 8.0f + time * 6.0f);
    float liquid = smoothstep(surface + wave - 0.015f, surface + wave + 0.015f, p.y);
    // Liquid colour: palette, deeper toward the bottom, lit through the glass.
    float3 liq = lab_palette_linear(0.1f + (p.y * 0.5f + 0.5f) * 0.25f + time * 0.01f, lab, labCount);
    float depth = smoothstep(surface, 1.0f, p.y);
    float3 liqLin = mix(liq * 1.6f, liq * 0.8f, depth) * (0.8f + intensity * 0.4f);
    // Surface line: a bright meniscus and a soft caustic under it.
    float men = 1.0f - smoothstep(0.0f, 0.02f, abs(p.y - surface - wave));
    float caustic = (1.0f - smoothstep(0.0f, 0.12f, p.y - surface - wave)) * liquid;
    // Compose over a near-white glass body.
    float3 glass = float3(0.97f);
    float3 lin = mix(glass, liqLin, liquid * kTint);
    lin += liq * caustic * 0.35f * kCaustic + float3(1.0f) * men * 0.6f;
    // Bubbles rising through the liquid.
    if (kBubbles > 0.0f) {
        float bub = 0.0f;
        for (int i = 0; i < 10; i++) {
            float fi = float(i);
            float h1 = lab_hash(float2(fi, 1.0f)), h2 = lab_hash(float2(fi, 2.0f));
            float by = 1.0f - fract(time * (0.12f + h2 * 0.2f) + h1) * (1.0f - surface);
            float bx = (h1 - 0.5f) * 1.2f + 0.04f * sin(time * 2.5f + fi);
            float bd = length(p - float2(bx, by));
            float bsz = 0.015f + h2 * 0.02f;
            bub += (1.0f - smoothstep(bsz * 0.6f, bsz, bd)) * (0.4f + 0.6f * (1.0f - smoothstep(0.0f, bsz * 0.5f, bd)));
        }
        lin += float3(1.0f) * bub * kBubbles * liquid * 0.8f;
    }
    // Fresnel: whiter at the rim; a rim line; a highlight.
    lin = mix(lin, float3(1.0f), fresnel * 0.5f * kGlass);
    float rimLine = smoothstep(0.93f, 0.985f, rr) * (1.0f - smoothstep(0.985f, 1.0f, rr));
    lin = lin * (1.0f - smoothstep(0.86f, 0.93f, rr) * 0.06f) + float3(1.0f) * rimLine * 0.4f * kGlass;
    float3 nrm = float3(p, z);
    float hl = pow(max(dot(nrm, normalize(float3(-0.5f, -0.7f, 0.6f))), 0.0f), 30.0f);
    lin = mix(lin, float3(1.0f), hl * 0.7f);
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Silk (colorEffect)
//
// A translucent pastel membrane that folds — the reference's near-white
// sphere with colour only at the folds. The silhouette is a disc whose
// radius is pushed by low-frequency noise; inside, the surface is lit
// as a thin sheet: white where it faces you, saturating toward the
// palette where it is seen edge-on (folds and rim). `knobs`: fold,
// fold speed, tint, rim, softness.

[[ stitchable ]] half4 labSilk(float2 position, half4 color,
                               float2 size, float time, float intensity, float audio,
                               device const float *knobs, int knobCount,
                               device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kFold = knobs[0], kSpeed = knobs[1], kTint = knobs[2], kRim = knobs[3], kSoft = knobs[4];
    float ang = atan2(uv.y, uv.x);
    // Silhouette: the radius wanders with noise round the angle.
    float rad = 0.8f + kFold * 0.15f * (lab_fbm_n(float2(cos(ang), sin(ang)) * 1.5f + time * kSpeed * 0.2f, 3) - 0.5f) * 2.0f
              + audio * 0.05f * sin(ang * 4.0f + time * 5.0f);
    float r = length(uv) / rad;
    float mask = 1.0f - smoothstep(1.0f - 0.03f * kSoft - 0.005f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    // Folds: a second noise field across the surface gives creases —
    // where its gradient is steep the sheet is seen edge-on.
    float2 fp = uv * 2.0f + float2(time * kSpeed * 0.15f, -time * kSpeed * 0.1f);
    const float e = 0.02f;
    float n0 = lab_fbm_n(fp, 3);
    float gx = lab_fbm_n(fp + float2(e, 0), 3) - n0;
    float gy = lab_fbm_n(fp + float2(0, e), 3) - n0;
    float crease = clamp(length(float2(gx, gy)) / e * kFold * 0.35f, 0.0f, 1.0f);
    float rr = min(r, 1.0f);
    float edgeOn = pow(rr, 4.0f) * kRim + crease;
    edgeOn = clamp(edgeOn, 0.0f, 1.0f);
    // Colour where edge-on, through the palette by position.
    float3 tint = lab_palette_linear(n0 * 0.6f + ang / 6.2831f * 0.2f + time * 0.02f, lab, labCount);
    float3 lin = mix(float3(1.0f), tint, edgeOn * kTint * (0.7f + intensity * 0.5f));
    // The membrane is translucent: alpha grows where it is edge-on.
    float alpha = (0.35f + 0.65f * edgeOn) * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(alpha), half(alpha));
}

// MARK: - Liquid Ring (colorEffect)
//
// The ring as a fluid: a band whose inner and outer edges are pushed by
// flowing noise, white-hot where the flow bunches, with a faint dot
// field inside — the reference's temperature dial. `knobs`: width,
// turbulence, flow, heat, dots, dot density.

[[ stitchable ]] half4 labLiquidRing(float2 position, half4 color,
                                     float2 size, float time, float intensity, float audio,
                                     device const float *knobs, int knobCount,
                                     device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kWidth = knobs[0], kTurb = knobs[1], kFlow = knobs[2], kHeat = knobs[3], kDots = knobs[4], kDensity = knobs[5];
    float kGlow = knobCount > 6 ? knobs[6] : 1.0f;
    float r = length(uv);
    float ang = atan2(uv.y, uv.x);
    float2 dir = float2(cos(ang), sin(ang));
    // Two noise fields round the ring: one pushes the edges, one lights
    // the band. Both flow round with time.
    float n1 = lab_fbm_n(dir * 2.2f + float2(time * kFlow * 0.3f, 0), 3) - 0.5f;
    float n2 = lab_fbm_n(dir * 3.5f - float2(0, time * kFlow * 0.45f) + 7.0f, 3);
    float turb = kTurb * (1.0f + audio * 1.5f);
    float outer = 0.9f + n1 * 0.1f * turb;
    float inner = outer - kWidth * (0.5f + 0.5f * n2 + audio * 0.4f);
    float band = smoothstep(inner - 0.01f, inner + 0.02f, r) * (1.0f - smoothstep(outer - 0.02f, outer + 0.01f, r));
    // Heat: the band's brightness follows n2; hot spots go white.
    float heat = pow(n2, 2.0f) * kHeat * (1.0f + audio);
    float3 base = lab_palette_linear(n2 * 0.4f + time * 0.03f, lab, labCount);
    float3 lin = base * band * (0.6f + intensity * 0.6f) + float3(1.0f) * band * heat;
    // A soft glow inside the ring, in the palette.
    float glow = (1.0f - smoothstep(inner - 0.25f, inner, r)) * smoothstep(inner - 0.6f, inner, r) * 0.25f * kGlow;
    lin += base * glow;
    // Dot field inside: a polar grid of dots, dimmer toward the centre,
    // rippling with the flow.
    if (kDots > 0.0f && r < inner) {
        float rings = kDensity;
        float ringIdx = floor(r * rings);
        float count = max(6.0f, floor(ringIdx * 6.5f));
        float a = fract(ang / 6.2831f * count + time * kFlow * 0.05f * (fmod(ringIdx, 2.0f) == 0.0f ? 1.0f : -1.0f));
        float rf = fract(r * rings);
        float dd = length(float2((a - 0.5f) * 2.0f, (rf - 0.5f) * 2.0f));
        float dot = 1.0f - smoothstep(0.15f, 0.3f, dd);
        float ripple = 0.5f + 0.5f * sin(r * 20.0f - time * 3.0f + n1 * 4.0f);
        lin += base * dot * kDots * (0.35f + 0.65f * ripple) * smoothstep(0.1f, 0.9f, r / inner);
    }
    float alpha = min(1.0f, max(band, glow + (r < inner ? kDots * 0.3f : 0.0f)));
    alpha = max(alpha, max(max(lin.r, lin.g), lin.b) * 0.8f);
    return half4(half3(lab_linear_to_srgb(lin)) * half(min(alpha, 1.0f)), half(min(alpha, 1.0f)));
}

// MARK: - Tide (colorEffect) — water in a sphere, tumbling in 3D
//
// Three of Chris's references (2026-09-15) are the same object: a glass
// sphere with liquid in it, and the *direction of gravity* slowly
// turning, so the surface is seen from above (a wavy disc), then
// edge-on (a thin line — the fish-tank view), then from below. The
// pink one has dense water; the pastel one has water so clear that only
// the surface shows, as a film; the blue one is behind frosted glass.
// Density and Frost are knobs, so one lab reaches all three.
//
// Rendered honestly: an orthographic ray per pixel through the unit
// sphere; the liquid is the half-space below a plane whose normal is
// "down"; waves are noise on that plane; the ray is marched through the
// sphere summing how much liquid it crosses (Beer-Lambert absorption
// gives the colour) and finding the first air↔liquid crossing (the
// surface: highlights, thin-film colour where it is seen edge-on, a
// cooler cast when seen from underneath).
//
// `knobs`: level, tumble, wave, density, frost, film, highlight, tilt.

static float3 tide_palette(float t, device const float *lab, int labCount) {
    return lab_palette_linear(t, lab, labCount);
}

[[ stitchable ]] half4 labTide(float2 position, half4 color,
                               float2 size, float time, float intensity, float audio,
                               device const float *knobs, int knobCount,
                               device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kLevel = knobs[0], kTumble = knobs[1], kWave = knobs[2], kDensity = knobs[3];
    float kFrost = knobs[4], kFilm = knobs[5], kSpec = knobs[6], kTilt = knobs[7];
    float kSheen = knobCount > 8 ? knobs[8] : 1.0f;
    float kGlass = knobCount > 9 ? knobs[9] : 0.3f;
    float kShadow = knobCount > 10 ? knobs[10] : 0.0f;
    float kSway = knobCount > 11 ? knobs[11] : 0.3f;
    float kColorDepth = knobCount > 12 ? knobs[12] : 0.5f;

    // Sphere, radius 1 in a 0.9 disc so the rim breathes.
    float2 p2 = uv / 0.9f;
    float r2 = dot(p2, p2);
    float mask = 1.0f - smoothstep(0.985f, 1.0f, sqrt(r2));
    if (mask <= 0.0f) {
        // Shadow below, outside the sphere (light mode).
        float2 sp = (uv - float2(0, 1.02f)) / float2(0.8f, 0.24f);
        float sh = exp(-dot(sp, sp) * 1.6f) * kShadow * 0.35f * step(0.7f, uv.y);
        return half4(0, 0, 0, half(sh));
    }
    float z0 = sqrt(max(0.0f, 1.0f - r2));   // front of the sphere (toward the viewer, +z)
    float z1 = -z0;                           // back

    // Down: a unit vector that swings and turns — the tumble. Audio
    // gives it a kick, so a loud moment sloshes.
    float t1 = 0.55f * sin(time * kTumble * 0.37f) + kTilt + audio * 0.4f + kSway * 0.2f * sin(time * 1.9f);
    float t2 = time * kTumble * 0.23f + kSway * 0.15f * sin(time * 1.3f);
    float3 g = normalize(float3(sin(t1) * cos(t2), cos(t1), sin(t1) * sin(t2)));
    float3 u = normalize(cross(g, float3(0.31f, 0.12f, 0.94f)));
    float3 v = cross(g, u);
    float level = clamp(kLevel + audio * 0.15f, 0.02f, 0.98f);
    float h0 = 1.0f - 2.0f * level;           // surface height along g; liquid where dot(p, g) > h0

    // March front to back.
    const int N = 16;
    float thickness = 0.0f;
    bool prevInside = false, haveSurface = false, fromAbove = false;
    float3 surfaceP = float3(0);
    float wAtSurface = 0.0f;
    float2 wgrad = float2(0);
    float step = (z0 - z1) / float(N);
    for (int i = 0; i < N; i++) {
        float z = z0 - (float(i) + 0.5f) * step;
        float3 p = float3(p2, z);
        float2 pl = float2(dot(p, u), dot(p, v));
        float w = kWave * 0.12f * (lab_fbm_n(pl * 1.7f + float2(time * 0.45f, -time * 0.3f), 2) - 0.5f) * 2.0f;
        bool inside = dot(p, g) > h0 + w;
        if (inside) thickness += step;
        if (i == 0) { prevInside = inside; }
        else if (inside != prevInside && !haveSurface) {
            haveSurface = true;
            fromAbove = inside;                // air → liquid: we look down onto the surface
            surfaceP = p;
            wAtSurface = w;
            const float e = 0.03f;
            float wu = kWave * 0.12f * (lab_fbm_n((pl + float2(e, 0)) * 1.7f + float2(time * 0.45f, -time * 0.3f), 2) - 0.5f) * 2.0f;
            float wv = kWave * 0.12f * (lab_fbm_n((pl + float2(0, e)) * 1.7f + float2(time * 0.45f, -time * 0.3f), 2) - 0.5f) * 2.0f;
            wgrad = float2(wu - w, wv - w) / e;
        }
        prevInside = inside;
    }
    // If the ray starts inside, the front of the sphere is under water:
    // there is no crossing but we are looking up through the liquid.
    bool underwater = !haveSurface && prevInside && thickness > 0.0f;

    // Body: absorption by thickness, in the palette; deeper is darker
    // and shifts along the palette a little.
    float3 liq = tide_palette(0.15f + thickness * 0.25f * kColorDepth + time * 0.01f, lab, labCount);
    float transmit = exp(-thickness * kDensity * 2.2f);
    float3 glass = float3(0.97f);
    float3 lin = mix(liq * (1.0f - 0.25f * min(thickness, 2.0f)), glass, transmit);

    // The surface.
    float3 view = float3(0, 0, 1);
    float surfaceLight = 0.0f;
    float3 surfaceCol = float3(0);
    if (haveSurface) {
        // Normal: up, tilted by the wave's slope.
        float3 nUp = normalize(-g + (u * wgrad.x + v * wgrad.y) * 0.5f);
        float facing = dot(nUp, view);                  // +1 seen from straight above, −1 from below
        float edgeOn = 1.0f - abs(facing);
        // Thin-film colour where the surface is seen at a grazing angle —
        // the pastel edges of the clear reference.
        float3 film = tide_palette(0.5f + edgeOn * 0.6f + dot(surfaceP, u) * 0.15f + time * 0.03f, lab, labCount);
        surfaceCol += film * pow(edgeOn, 1.6f) * kFilm * 1.4f;
        // Highlight from a key light, only on the side facing us.
        float3 L = normalize(float3(-0.5f, 0.75f, 0.6f));
        float3 H = normalize(L + view);
        float spec = pow(max(dot(nUp, H), 0.0f), 70.0f) * max(facing, 0.0f);
        // The sheen is the broad band of light the surface throws back —
        // the gold sheet in the orange reference. It takes the palette's
        // warm end rather than plain white, and it is wide.
        float sheen = pow(max(dot(nUp, H), 0.0f), 3.0f) * max(facing, 0.0f) * 0.55f * kSheen;
        float3 sheenCol = mix(float3(1.0f), tide_palette(0.75f, lab, labCount) * 1.4f, 0.7f);
        surfaceCol += float3(1.0f) * spec * 0.5f * kSpec + sheenCol * sheen * kSpec;
        // From below the surface is a silvery mirror (total internal
        // reflection) — a cool wash.
        surfaceCol += float3(0.85f, 0.92f, 1.0f) * max(-facing, 0.0f) * 0.25f * kSpec;
        surfaceLight = max(max(surfaceCol.r, surfaceCol.g), surfaceCol.b);
    }
    if (underwater) {
        // Looking up through the water: the body colour, brightened
        // toward the sphere's rim where the surface would be.
        lin = mix(lin, liq * 1.3f, 0.2f);
    }
    // Energy-conserving: the surface's light replaces what is under it
    // rather than piling on top, so a bright sheet stays coloured
    // instead of clipping to white.
    float sMix = min(1.0f, surfaceLight);
    lin = mix(lin, surfaceCol / max(sMix, 0.001f), sMix * 0.85f);

    // The glass: Fresnel whitening, frost, a rim line, a highlight, and
    // the sphere's own shading so it reads as a ball.
    float fres = pow(1.0f - z0, 2.5f);
    float3 nS = float3(p2, z0);
    float shade = 0.85f + 0.15f * max(dot(nS, normalize(float3(-0.4f, 0.6f, 0.7f))), 0.0f);
    lin *= shade;
    lin = mix(lin, float3(1.0f), kFrost * (0.25f + 0.75f * fres));
    float rr = sqrt(r2);
    float rimLine = smoothstep(0.93f, 0.985f, rr) * (1.0f - smoothstep(0.985f, 1.0f, rr));
    lin += float3(1.0f) * rimLine * 0.45f;
    float hl = pow(max(dot(nS, normalize(normalize(float3(-0.5f, 0.75f, 0.6f)) + view)), 0.0f), 90.0f);
    lin += float3(1.0f) * hl * 0.6f;

    // Alpha: the liquid and frost are opaque-ish; clear glass over
    // nothing stays mostly see-through so it works on a dark stage too.
    float bodyAlpha = 1.0f - transmit;
    float alpha = max(max(bodyAlpha, kFrost * 0.7f + fres * 0.45f + kGlass * 0.35f), min(surfaceLight, 1.0f) + rimLine * 0.5f + hl * 0.6f);
    alpha = min(1.0f, alpha) * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(alpha), half(alpha));
}

// ============================================================================
// Round five: the water family (Chris, 2026-09-15 — "based on where we're
// going"). Nine bases, five post effects.
// ============================================================================

// Cheap 3-D value noise from the 2-D one: two slices blended along z.
static float lab_noise3(float3 p) {
    float zi = floor(p.z), zf = p.z - zi;
    zf = zf * zf * (3.0f - 2.0f * zf);
    float a = lab_noise(p.xy + zi * 17.31f);
    float b = lab_noise(p.xy + (zi + 1.0f) * 17.31f);
    return mix(a, b, zf);
}
static float lab_fbm3(float3 p, int octaves) {
    float v = 0.0f, a = 0.5f;
    for (int i = 0; i < octaves; i++) { v += a * lab_noise3(p); p *= 2.03f; a *= 0.5f; }
    return v;
}

// MARK: - Droplet (colorEffect)
//
// A water drop: a disc sagging under its own weight, refracting the
// palette behind it, with a Fresnel rim and a window highlight.
// `knobs`: sag, wobble, refraction, tint, highlight.

[[ stitchable ]] half4 labDroplet(float2 position, half4 color,
                                  float2 size, float time, float intensity, float audio,
                                  device const float *knobs, int knobCount,
                                  device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kSag = knobs[0], kWobble = knobs[1], kRefract = knobs[2], kTint = knobs[3], kSpec = knobs[4];
    float ang = atan2(uv.y, uv.x);
    // Shape: fatter at the bottom (sag), modes of wobble that swell on audio.
    float w = kWobble * (0.03f * sin(ang * 2.0f + time * 2.1f) + 0.02f * sin(ang * 3.0f - time * 1.7f)) + audio * 0.05f * sin(ang * 4.0f + time * 8.0f);
    float rad = 0.92f + kSag * 0.06f * uv.y + w;
    float r = length(uv) / rad;
    float mask = 1.0f - smoothstep(0.985f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float rr = min(r, 1.0f);
    float z = sqrt(max(0.0f, 1.0f - rr * rr));
    float3 n = float3(uv / rad, z);
    // What's behind: a palette gradient, seen through the drop, bent
    // toward the edge — the drop as a lens.
    float2 bent = uv * (1.0f + (1.0f - z) * kRefract * 1.2f);
    float3 back = lab_palette_linear((bent.y * 0.5f + 0.5f) * 0.5f + bent.x * 0.15f + time * 0.02f, lab, labCount);
    float fres = pow(1.0f - z, 3.0f);
    float3 lin = mix(float3(0.96f), back, kTint) * (0.85f + 0.15f * z);
    lin = mix(lin, float3(1.0f), fres * 0.55f);
    // Rim line and a window highlight (a soft rectangle upper-left).
    float rimLine = smoothstep(0.93f, 0.985f, rr) * (1.0f - smoothstep(0.985f, 1.0f, rr));
    lin += float3(1.0f) * rimLine * 0.5f;
    float2 wp = (uv - float2(-0.4f, -0.45f)) / float2(0.22f, 0.14f);
    float window = (1.0f - smoothstep(0.7f, 1.0f, max(abs(wp.x), abs(wp.y)))) * z;
    lin = mix(lin, float3(1.0f), window * 0.85f * kSpec);
    float hl = pow(max(dot(n, normalize(float3(0.5f, 0.6f, 0.7f))), 0.0f), 40.0f) * 0.5f * kSpec;
    lin += float3(hl);
    float alpha = max(kTint * 0.7f + fres * 0.5f, rimLine * 0.6f + window * 0.9f + hl) * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(min(alpha, 1.0f)), half(min(alpha, 1.0f)));
}

// MARK: - Pour (colorEffect)
//
// Liquid filling the sphere from a stream at the top, ripples where it
// lands, foam at the surface — the pod filling as it listens. Level
// cycles on its own or follows the audio. `knobs`: rate, stream,
// ripples, foam, tint, hold.

[[ stitchable ]] half4 labPour(float2 position, half4 color,
                               float2 size, float time, float intensity, float audio,
                               device const float *knobs, int knobCount,
                               device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kRate = knobs[0], kStream = knobs[1], kRipple = knobs[2], kFoam = knobs[3], kTint = knobs[4], kHold = knobs[5];
    float2 p = uv / 0.92f;
    float r = length(p);
    float mask = 1.0f - smoothstep(0.985f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float z = sqrt(max(0.0f, 1.0f - min(r, 1.0f) * min(r, 1.0f)));
    // Level: a cycle of fill → hold → drain, plus audio.
    float cycle = kRate > 0.0f ? fract(time * kRate * 0.1f) : 0.5f;
    float filling = smoothstep(0.0f, 0.45f, cycle) * (1.0f - smoothstep(0.45f + kHold * 0.4f, 1.0f, cycle));
    float level = clamp(filling * 0.85f + audio * 0.15f, 0.0f, 0.95f);
    float surfaceY = 1.0f - level * 2.0f;
    float pouring = filling > 0.02f && filling < 0.98f && cycle < 0.5f ? 1.0f : 0.0f;
    // Stream: a thin wavy column from the top down to the surface.
    float sx = 0.05f * sin(p.y * 9.0f + time * 6.0f);
    float stream = (1.0f - smoothstep(0.02f * kStream, 0.05f * kStream, abs(p.x - sx))) * step(-1.0f, p.y) * step(p.y, surfaceY) * pouring * kStream;
    // Ripples from the impact point, on the surface.
    float impact = length(float2(p.x, (p.y - surfaceY) * 3.0f));
    float ripple = sin(impact * 24.0f - time * 12.0f) * exp(-impact * 3.0f) * kRipple * pouring * 0.05f;
    float wave = 0.02f * sin(p.x * 7.0f + time * 3.0f) + ripple;
    float liquid = smoothstep(surfaceY + wave - 0.01f, surfaceY + wave + 0.01f, p.y);
    float3 liq = lab_palette_linear(0.15f + (p.y * 0.5f + 0.5f) * 0.3f + time * 0.01f, lab, labCount);
    float3 lin = mix(float3(0.97f), liq * (0.7f + 0.3f * z), liquid * kTint);
    // Foam: a bright band at the surface, more when pouring.
    float foam = (1.0f - smoothstep(0.0f, 0.04f + 0.03f * pouring, abs(p.y - surfaceY - wave))) * kFoam;
    lin += float3(1.0f) * foam * 0.8f + liq * stream * 1.2f + float3(1.0f) * stream * 0.4f;
    // Glass.
    float fres = pow(1.0f - z, 2.5f);
    lin = mix(lin, float3(1.0f), fres * 0.4f);
    float rr = min(r, 1.0f);
    float rimLine = smoothstep(0.93f, 0.985f, rr) * (1.0f - smoothstep(0.985f, 1.0f, rr));
    lin += float3(1.0f) * rimLine * 0.4f;
    float alpha = max(max(liquid * 0.9f, fres * 0.5f + 0.06f), foam + stream + rimLine * 0.5f) * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(min(alpha, 1.0f)), half(min(alpha, 1.0f)));
}

// MARK: - Pool (colorEffect)
//
// Water seen from above: rings from drops landing, refracting a palette
// floor, caustic highlights on the wave slopes. `knobs`: drops, ring
// speed, ring width, refraction, caustic, calm.

[[ stitchable ]] half4 labPool(float2 position, half4 color,
                               float2 size, float time, float intensity, float audio,
                               device const float *knobs, int knobCount,
                               device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kDrops = knobs[0], kSpeed = knobs[1], kWidth = knobs[2], kRefract = knobs[3], kCaustic = knobs[4], kCalm = knobs[5];
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    // Height field: a handful of drops, each an expanding, fading ring,
    // plus a calm swell.
    float h = 0.0f;
    float2 grad = float2(0);
    int n = clamp(int(kDrops + 0.5f), 1, 8);
    for (int i = 0; i < n; i++) {
        float fi = float(i);
        float period = 2.5f + lab_hash(float2(fi, 3.0f)) * 2.0f;
        float tl = fract(time / period + fi * 0.37f) * period;         // time since this drop landed
        float2 c = float2(lab_hash(float2(fi, 1.0f)), lab_hash(float2(fi, 2.0f))) * 1.4f - 0.7f;
        float d = length(uv - c);
        float ringR = tl * kSpeed * 0.4f;
        float env = exp(-tl * 0.9f) * exp(-pow((d - ringR) / (0.08f + kWidth * 0.1f), 2.0f));
        float phase = (d - ringR) * 22.0f;
        h += env * sin(phase);
        grad += env * cos(phase) * 22.0f * (uv - c) / max(d, 0.001f);
    }
    h *= 0.03f * (1.0f + audio); grad *= 0.03f * (1.0f + audio);
    float swell = kCalm * 0.015f * sin(uv.x * 4.0f + time) * cos(uv.y * 3.0f - time * 0.7f);
    h += swell;
    grad += kCalm * 0.015f * float2(4.0f * cos(uv.x * 4.0f + time) * cos(uv.y * 3.0f - time * 0.7f), -3.0f * sin(uv.x * 4.0f + time) * sin(uv.y * 3.0f - time * 0.7f));
    // Refract the floor by the slope; the floor is a palette gradient.
    float2 bent = uv + grad * kRefract * 0.6f;
    float3 floorCol = lab_palette_linear((bent.y * 0.5f + 0.5f) * 0.45f + bent.x * 0.1f + time * 0.015f, lab, labCount);
    float3 lin = floorCol * (0.75f + intensity * 0.35f);
    // Caustics: bright where the slope focuses light.
    float slope = length(grad);
    float caustic = smoothstep(0.1f, 0.6f, slope) * kCaustic;
    lin += float3(1.0f) * caustic * 0.5f + floorCol * caustic * 0.5f;
    // A soft specular that moves with the height.
    float3 nrm = normalize(float3(-grad, 1.0f));
    float spec = pow(max(dot(nrm, normalize(float3(-0.4f, -0.5f, 0.8f))), 0.0f), 60.0f);
    lin += float3(spec * 0.5f);
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Caustics (colorEffect)
//
// The bright web light makes on the bottom of a pool: layered noise
// folded so its ridges become lines, two layers drifting against each
// other, tinted by the palette. `knobs`: scale, speed, sharpness,
// layers, tint, floor.

[[ stitchable ]] half4 labCaustics(float2 position, half4 color,
                                   float2 size, float time, float intensity, float audio,
                                   device const float *knobs, int knobCount,
                                   device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kScale = knobs[0], kSpeed = knobs[1], kSharp = knobs[2], kLayers = knobs[3], kTint = knobs[4], kFloor = knobs[5];
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float web = 0.0f;
    int layers = clamp(int(kLayers + 0.5f), 1, 3);
    for (int i = 0; i < layers; i++) {
        float fi = float(i);
        float2 p = uv * kScale * (1.0f + fi * 0.35f) + float2(time * kSpeed * (0.2f + fi * 0.1f), -time * kSpeed * (0.15f + fi * 0.07f)) + fi * 5.0f;
        float n = lab_fbm_n(p, 3);
        float line = 1.0f - abs(n - 0.5f) * 2.0f;                     // ridges become lines
        web += pow(clamp(line, 0.0f, 1.0f), 2.0f + kSharp * 10.0f) / float(layers);
    }
    web *= (1.0f + audio * 0.8f);
    float3 floorCol = lab_palette_linear(0.1f + (uv.y * 0.5f + 0.5f) * 0.3f + time * 0.01f, lab, labCount) * kFloor;
    float3 tint = mix(float3(1.0f), lab_palette_linear(0.5f + time * 0.02f, lab, labCount), kTint);
    float3 lin = floorCol + tint * web * (0.8f + intensity * 0.6f);
    float alpha = max(kFloor, min(1.0f, web)) * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(alpha), half(alpha));
}

// MARK: - Lava (colorEffect)
//
// A lava lamp: warm blobs rise from the bottom, stretch, merge and sink,
// as one metaball field with a vertical drift and a glow. `knobs`:
// blobs, heat, size, goo, glow, stretch.

[[ stitchable ]] half4 labLava(float2 position, half4 color,
                               float2 size, float time, float intensity, float audio,
                               device const float *knobs, int knobCount,
                               device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    int blobs = clamp(int(knobs[0] + 0.5f), 1, 8);
    float kHeat = knobs[1], kSize = knobs[2], kGoo = knobs[3], kGlow = knobs[4], kStretch = knobs[5];
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    int n = max(labCount / 3, 1);
    float field = 0.0f;
    float3 col = float3(0);
    for (int i = 0; i < blobs; i++) {
        float fi = float(i);
        float h1 = lab_hash(float2(fi, 7.0f)), h2 = lab_hash(float2(fi, 8.0f));
        float period = 6.0f + h2 * 6.0f;
        float ph = fract(time * kHeat * 0.15f / (period / 8.0f) + h1);   // 0 bottom … 1 top … back
        float y = 0.75f - (0.5f - 0.5f * cos(ph * 6.2831f)) * 1.5f;      // up and down
        float x = (h1 - 0.5f) * 1.5f + 0.15f * sin(time * 0.6f + fi * 2.0f);
        float2 c = float2(x, y);
        float2 d = uv - c;
        d.y /= (1.0f + kStretch * 0.6f * abs(sin(ph * 6.2831f)));           // stretched while moving
        float s2 = kSize * kSize * (0.8f + 0.4f * h2) * (1.0f + audio * 0.3f);
        float f = s2 / max(dot(d, d), 1e-4f);
        field += f;
        col += lab_oklab_to_linear(float3(lab[(i % n) * 3], lab[(i % n) * 3 + 1], lab[(i % n) * 3 + 2])) * f;
    }
    col /= max(field, 1e-4f);
    float threshold = 1.0f / (1.0f + kGoo * 3.0f);
    float body = smoothstep(threshold - 0.05f, threshold + 0.05f, field * 0.3f);
    float halo = smoothstep(threshold * 0.3f, threshold, field * 0.3f) * kGlow;
    float3 lin = col * body * (0.9f + intensity * 0.4f) + col * halo * 0.4f;
    float alpha = min(1.0f, max(body, halo * 0.5f)) * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(alpha), half(alpha));
}

// MARK: - Jelly (colorEffect)
//
// A gelatin sphere: its outline wobbles in a few spring modes that ring
// on a beat and settle; translucent with a bright core, a shell
// highlight. `knobs`: wobble, springiness, translucency, core,
// highlight, modes.

[[ stitchable ]] half4 labJelly(float2 position, half4 color,
                                float2 size, float time, float intensity, float audio,
                                device const float *knobs, int knobCount,
                                device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kWobble = knobs[0], kSpring = knobs[1], kTrans = knobs[2], kCore = knobs[3], kSpec = knobs[4];
    int modes = clamp(int(knobs[5] + 0.5f), 1, 6);
    float ang = atan2(uv.y, uv.x);
    // Idle wobble in each mode, plus audio ringing the modes harder;
    // higher modes ring faster, as a real jelly's do.
    float dr = 0.0f;
    for (int k = 2; k < 2 + modes; k++) {
        float fk = float(k);
        float freq = kSpring * (1.0f + fk * 0.6f);
        dr += (kWobble * 0.03f + audio * 0.06f) / fk * sin(ang * fk + time * freq + fk * 1.3f);
    }
    float rad = 0.93f + dr;
    float r = length(uv) / rad;
    float mask = 1.0f - smoothstep(0.985f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float rr = min(r, 1.0f);
    float z = sqrt(max(0.0f, 1.0f - rr * rr));
    float3 n = float3(uv / rad, z);
    float3 base = lab_palette_linear(0.2f + (uv.y * 0.5f + 0.5f) * 0.3f + time * 0.02f, lab, labCount);
    // Translucent: brighter toward the core (light scattering inside),
    // dimmer at the edge, plus a Fresnel sheen.
    float core = exp(-rr * rr * 2.5f) * kCore;
    float fres = pow(1.0f - z, 2.0f);
    float3 lin = base * (0.5f + 0.5f * z) * (0.8f + intensity * 0.4f);
    lin = mix(lin, base * 1.6f + 0.2f, core * 0.7f);
    lin = mix(lin, float3(1.0f), fres * 0.25f * kSpec);
    float spec = pow(max(dot(n, normalize(float3(-0.5f, -0.6f, 0.65f))), 0.0f), 50.0f);
    lin += float3(spec * 0.7f * kSpec);
    float alpha = (1.0f - kTrans * 0.6f * (1.0f - fres)) * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(alpha), half(alpha));
}

// MARK: - Slick (colorEffect)
//
// Oil on water: thin-film colour from a swirling thickness field over a
// dark reflective surface. `knobs`: swirl, scale, iridescence, speed,
// contrast, water.

[[ stitchable ]] half4 labSlick(float2 position, half4 color,
                                float2 size, float time, float intensity, float audio,
                                device const float *knobs, int knobCount,
                                device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kSwirl = knobs[0], kScale = knobs[1], kIrid = knobs[2], kSpeed = knobs[3], kContrast = knobs[4], kWater = knobs[5];
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    float2 p = uv * kScale;
    float2 q = float2(lab_fbm_n(p + time * kSpeed * 0.1f, 3), lab_fbm_n(p + float2(3.1f, 7.7f) - time * kSpeed * 0.08f, 3));
    float thick = lab_fbm_n(p + kSwirl * 3.0f * q + time * kSpeed * 0.05f, 3);
    // Interference: several cycles through the palette across the
    // thickness range; contrast sharpens the bands.
    float phase = thick * (2.0f + kIrid * 4.0f) + audio * 0.5f;
    float3 film = lab_palette_linear(phase, lab, labCount);
    float band = 0.5f + 0.5f * cos(phase * 6.2831f);
    band = mix(band, pow(band, 3.0f), kContrast);
    float3 water = float3(0.02f, 0.03f, 0.05f) * kWater;
    float3 lin = water + film * (0.35f + 0.65f * band) * (0.8f + intensity * 0.5f) * kIrid * 0.9f;
    // A soft reflection of a sky across the top.
    lin += float3(1.0f) * pow(max(0.0f, -uv.y), 3.0f) * 0.15f;
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Deep (colorEffect)
//
// Looking up from under water: light shafts from the surface, a caustic
// web, motes drifting up, the palette darkening with depth. `knobs`:
// rays, motes, depth, surface, sway.

[[ stitchable ]] half4 labDeep(float2 position, half4 color,
                               float2 size, float time, float intensity, float audio,
                               device const float *knobs, int knobCount,
                               device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kRays = knobs[0], kMotes = knobs[1], kDepth = knobs[2], kSurface = knobs[3], kSway = knobs[4];
    float r = length(uv);
    float mask = 1.0f - smoothstep(0.97f, 1.0f, r);
    if (mask <= 0.0f) return half4(0);
    // The water: palette, bright at the top (the surface), dark below.
    float depth = uv.y * 0.5f + 0.5f;
    float3 water = lab_palette_linear(0.2f + depth * 0.25f + time * 0.01f, lab, labCount) * mix(1.2f, 0.15f, pow(depth, 0.7f) * kDepth);
    // Rays: bright shafts fanning down from a point above the disc.
    float2 src = float2(kSway * 0.3f * sin(time * 0.4f), -1.4f);
    float2 d = uv - src;
    float a = atan2(d.x, d.y);
    float shaft = 0.0f;
    for (int i = 0; i < 3; i++) {
        float fi = float(i);
        shaft += pow(0.5f + 0.5f * sin(a * (14.0f + fi * 7.0f) + time * (0.3f + fi * 0.2f) + fi), 6.0f) / 3.0f;
    }
    shaft *= kRays * (1.0f - depth * 0.8f) * (1.0f + audio * 0.6f);
    // Caustic web near the surface.
    float web = 1.0f - abs(lab_fbm_n(uv * 4.0f + float2(time * 0.2f, -time * 0.15f), 3) - 0.5f) * 2.0f;
    web = pow(clamp(web, 0.0f, 1.0f), 6.0f) * (1.0f - depth) * kSurface;
    // Motes: little bright specks rising.
    float motes = 0.0f;
    for (int i = 0; i < 14; i++) {
        float fi = float(i);
        float h1 = lab_hash(float2(fi, 4.0f)), h2 = lab_hash(float2(fi, 5.0f));
        float2 m = float2((h1 - 0.5f) * 1.8f + 0.05f * sin(time + fi), 1.0f - fract(time * (0.03f + h2 * 0.05f) + h1) * 2.0f);
        float md = length(uv - m);
        motes += (1.0f - smoothstep(0.0f, 0.012f + h2 * 0.01f, md)) * (0.5f + 0.5f * h2);
    }
    motes *= kMotes;
    float3 lin = water * (0.8f + intensity * 0.4f) + float3(0.9f, 0.95f, 1.0f) * (shaft * 0.5f + web * 0.6f + motes * 0.8f);
    return half4(half3(lab_linear_to_srgb(lin)) * half(mask), half(mask));
}

// MARK: - Nebula (colorEffect) — a cloud inside glass
//
// Volumetric noise ray-marched through a sphere: a soft cloud in the
// palette, lit from a direction, denser where the noise is, drifting.
// The frosted-blue reference's interior, honestly. `knobs`: density,
// scale, flow, glow, shell, light.

[[ stitchable ]] half4 labNebula(float2 position, half4 color,
                                 float2 size, float time, float intensity, float audio,
                                 device const float *knobs, int knobCount,
                                 device const float *lab, int labCount)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float kDensity = knobs[0], kScale = knobs[1], kFlow = knobs[2], kGlow = knobs[3], kShell = knobs[4], kLight = knobs[5];
    float2 p2 = uv / 0.92f;
    float r2 = dot(p2, p2);
    float mask = 1.0f - smoothstep(0.985f, 1.0f, sqrt(r2));
    if (mask <= 0.0f) return half4(0);
    float z0 = sqrt(max(0.0f, 1.0f - r2));
    const int N = 12;
    float step = 2.0f * z0 / float(N);
    float transmit = 1.0f;
    float3 acc = float3(0);
    float3 L = normalize(float3(-0.5f, -0.6f, 0.7f));
    for (int i = 0; i < N; i++) {
        float z = z0 - (float(i) + 0.5f) * step;
        float3 p = float3(p2, z);
        float3 q = p * kScale + float3(time * kFlow * 0.15f, -time * kFlow * 0.1f, time * kFlow * 0.08f);
        float dens = smoothstep(0.42f, 0.7f, lab_fbm3(q, 3)) * kDensity * (1.0f + audio * 0.6f);
        if (dens > 0.001f) {
            // Cheap lighting: density a little toward the light.
            float dl = smoothstep(0.42f, 0.7f, lab_fbm3(q + L * 0.15f, 2)) * kDensity;
            float lit = clamp(1.0f - (dl - dens) * 2.0f, 0.2f, 1.0f) * kLight + (1.0f - kLight);
            float3 c = lab_palette_linear(0.2f + (p.y * 0.5f + 0.5f) * 0.3f + dens * 0.2f + time * 0.02f, lab, labCount);
            float a = 1.0f - exp(-dens * step * 3.0f);
            acc += transmit * a * c * lit * (0.9f + kGlow * 0.6f);
            transmit *= (1.0f - a);
        }
    }
    float fres = pow(1.0f - z0, 2.5f);
    float3 lin = acc * (0.85f + intensity * 0.4f);
    lin = mix(lin, float3(1.0f), fres * 0.35f * kShell);
    float rr = sqrt(r2);
    float rimLine = smoothstep(0.93f, 0.985f, rr) * (1.0f - smoothstep(0.985f, 1.0f, rr));
    lin += float3(1.0f) * rimLine * 0.4f * kShell;
    float alpha = min(1.0f, (1.0f - transmit) + fres * 0.4f * kShell + rimLine * 0.5f * kShell) * mask;
    return half4(half3(lab_linear_to_srgb(lin)) * half(alpha), half(alpha));
}

// MARK: - Water (layerEffect), post
//
// Refracts the layer through a rippling water surface — a noise height
// field — with caustic brightening on the slopes. Anything under it is
// under water. `amount` in pixels.

[[ stitchable ]] half4 labWater(float2 position, SwiftUI::Layer layer,
                                float2 size, float time, float amount, float scale, float caustic)
{
    float2 p = position / scale;
    float2 flow = float2(time * 0.4f, -time * 0.3f);
    const float e = 0.08f;
    float h = lab_fbm_n(p + flow, 3);
    float hx = lab_fbm_n(p + float2(e, 0) + flow, 3) - h;
    float hy = lab_fbm_n(p + float2(0, e) + flow, 3) - h;
    float2 grad = float2(hx, hy) / e;
    half4 s = layer.sample(position + grad * amount);
    float bright = 1.0f + caustic * clamp(length(grad) * 1.5f - 0.3f, 0.0f, 1.0f);
    return half4(s.rgb * half(bright), s.a);
}

// MARK: - Haze (layerEffect), post
//
// A soft palette veil over the layer, breathing with noise — depth
// fog. `amount` is the veil's strength.

[[ stitchable ]] half4 labHaze(float2 position, SwiftUI::Layer layer,
                               float2 size, float time, float amount, float scale, float breathe,
                               device const float *lab, int labCount)
{
    half4 s = layer.sample(position);
    float2 uv = position / size;
    float n = lab_fbm_n(uv * scale + float2(time * 0.1f, -time * 0.07f), 3);
    float veil = amount * (0.5f + 0.5f * n) * (0.8f + breathe * 0.2f * sin(time * 1.3f));
    float3 fog = lab_linear_to_srgb(lab_palette_linear(0.3f + n * 0.3f + time * 0.02f, lab, labCount));
    half3 rgb = mix(s.rgb, half3(fog) * s.a, half(veil));
    return half4(rgb, s.a);
}

// MARK: - Fizz (layerEffect), post
//
// Small bubbles rising over the layer: bright rims, dark centres, each
// on its own lane. `count` up to 40.

[[ stitchable ]] half4 labFizz(float2 position, SwiftUI::Layer layer,
                               float2 size, float time, float count, float speed, float bubbleSize)
{
    half4 s = layer.sample(position);
    float2 uv = position / size;
    float add = 0.0f, cut = 0.0f;
    int n = clamp(int(count), 1, 40);
    for (int i = 0; i < n; i++) {
        float fi = float(i);
        float h1 = lab_hash(float2(fi, 9.0f)), h2 = lab_hash(float2(fi, 10.0f));
        float y = 1.0f - fract(time * speed * (0.05f + h2 * 0.08f) + h1);
        float x = h1 * 0.9f + 0.05f + 0.02f * sin(time * 3.0f + fi);
        float d = length((uv - float2(x, y)) * float2(size.x / size.y, 1.0f)) * size.y;
        float rad = bubbleSize * (0.6f + h2 * 0.8f);
        float rim = (1.0f - smoothstep(rad * 0.7f, rad, d)) * smoothstep(rad * 0.45f, rad * 0.7f, d);
        add += rim;
        cut += (1.0f - smoothstep(rad * 0.3f, rad * 0.5f, d)) * 0.4f;
    }
    // Only over content: bubbles in empty space read as litter.
    half gate = smoothstep(0.05h, 0.4h, s.a);
    half3 rgb = s.rgb * half(1.0f - min(cut, 0.5f) * float(gate)) + half3(min(add, 1.0f)) * 0.8h * gate;
    return half4(min(rgb, half3(1)), s.a);
}

// MARK: - Glints (layerEffect), post
//
// A star filter: bright pixels throw four thin streaks. Samples along
// the arms and keeps what is above the threshold. `length` in pixels.

[[ stitchable ]] half4 labGlints(float2 position, SwiftUI::Layer layer,
                                 float threshold, float len, float strength, float rotate)
{
    half4 s = layer.sample(position);
    half3 acc = half3(0);
    const int steps = 12;
    float ca = cos(rotate), sa = sin(rotate);
    float2 arms[4] = { float2(ca, sa), float2(-sa, ca), float2(-ca, -sa), float2(sa, -ca) };
    for (int a = 0; a < 4; a++) {
        for (int i = 1; i <= steps; i++) {
            float t = float(i) / float(steps);
            half4 q = layer.sample(position + arms[a] * t * len);
            half l = dot(q.rgb, half3(0.2126h, 0.7152h, 0.0722h));
            half k = max(half(0), l - half(threshold)) / max(half(1.0f - threshold), 0.01h);
            acc += q.rgb * k * half((1.0f - t) * (1.0f - t)) / half(steps);
        }
    }
    half3 rgb = s.rgb + acc * half(strength);
    return half4(min(rgb, half3(1)), max(s.a, min(half(1), (acc.r + acc.g + acc.b) * half(strength))));
}

// MARK: - Parallax (layerEffect), post
//
// Depth for a flat thing: a dark, softened copy offset one way (its
// shadow on the glass behind) and a light copy offset the other (the
// light catching its edge). Under Liquid Glass this is what makes a
// layer read as an object with thickness. Offsets in pixels.

[[ stitchable ]] half4 labParallax(float2 position, SwiftUI::Layer layer,
                                   float2 offset, float shadow, float light, float soften)
{
    half4 s = layer.sample(position);
    half4 sh = half4(0);
    for (int i = 0; i < 4; i++) {
        float a = float(i) * 1.5708f;
        sh += layer.sample(position - offset + float2(cos(a), sin(a)) * soften);
    }
    sh *= 0.25h;
    half4 hi = layer.sample(position + offset * 0.5f);
    half shadowA = sh.a * half(shadow) * (1.0h - s.a);
    half lightA = hi.a * half(light) * (1.0h - s.a) * 0.5h;
    half3 rgb = s.rgb + half3(1.0h) * lightA;
    half a = s.a + shadowA + lightA;
    return half4(rgb, min(a, 1.0h));
}

// MARK: - Focus (layerEffect), post — depth of field
//
// A camera's shallow focus without a depth buffer: sharp at a focal
// point (or along a focal band), blurring with distance from it, and the
// blur is a *disc* — jittered taps on a circle — so bright points bloom
// into bokeh rather than smearing. `focus` in 0…1 across the layer,
// `radius` the maximum blur in pixels, `band` 0 radial / 1 horizontal.

[[ stitchable ]] half4 labFocus(float2 position, SwiftUI::Layer layer,
                                float2 size, float2 focus, float radius, float band, float falloff, float bokeh)
{
    float2 uv = position / size;
    float dist = band < 0.5f ? length((uv - focus) * float2(size.x / size.y, 1.0f)) : abs(uv.y - focus.y);
    float amount = clamp(pow(dist * 2.0f, falloff), 0.0f, 1.0f) * radius;
    if (amount < 0.5f) return layer.sample(position);
    half4 acc = half4(0);
    half wsum = half(0);
    float jitter = lab_hash(position) * 6.2831f;
    float rj = lab_hash(position + 9.7f);
    const int taps = 24;
    for (int i = 0; i < taps; i++) {
        float a = jitter + float(i) / float(taps) * 6.2831f;
        float rs = sqrt(fract(rj + float(i) * 0.618034f));
        half4 s = layer.sample(position + float2(cos(a), sin(a)) * amount * rs);
        // Bokeh: bright samples weigh more, so highlights stay discs.
        half l = dot(s.rgb, half3(0.2126h, 0.7152h, 0.0722h));
        half w = 1.0h + half(bokeh) * l * l * 6.0h;
        acc += s * w;
        wsum += w;
    }
    return acc / max(wsum, half(0.001));
}

// MARK: - Metal ring (colorEffect) — libraries.dev's "Metal", natively
//
// A polished metal ring round a shape: the sheen is a conic band pattern
// (chromatic: hue bands; silver: grey bands; gold: warm bands) with a
// specular hit that follows the pointer, and an inner shadow inside the
// ring. Drawn over a transparent view whose size is the control's
// footprint. `shapeKind`: 0 circle, 1 capsule, 2 rounded rect. Pointer
// is in the view's own points; a negative pointer.x means none.

static float metal_sd(float2 p, float2 hs, float kind) {
    if (kind < 0.5f) return length(p) - min(hs.x, hs.y);
    float r = kind < 1.5f ? min(hs.x, hs.y) : min(hs.x, hs.y) * 0.45f;
    float2 q = abs(p) - (hs - r);
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - r;
}

[[ stitchable ]] half4 labMetal(float2 position, half4 color,
                                float2 size, float time, float shapeKind, float ringWidth,
                                float preset, float strength, float bandScale, float innerShadow,
                                float2 pointer, float reflect, float reflectDistance, float reflectFalloff, float specular,
                                device const float *lab, int labCount)
{
    float2 hs = size * 0.5f;
    float2 p = position - hs;
    float d = metal_sd(p, hs - 1.0f, shapeKind);          // 0 at the outer edge, negative inside
    // The ring: a band `ringWidth` wide just inside the edge.
    float ring = (1.0f - smoothstep(-0.8f, 0.8f, d)) * smoothstep(-ringWidth - 0.8f, -ringWidth + 0.8f, d);
    // Inside the ring: a soft inner shadow falling in from it.
    float inside = 1.0f - smoothstep(-ringWidth - 0.5f, -ringWidth + 0.5f, d);
    float shadow = inside * (1.0f - smoothstep(-ringWidth - 10.0f * innerShadow, -ringWidth, d)) * 0.35f * innerShadow;
    if (ring <= 0.001f && shadow <= 0.001f) return half4(0);

    // Sheen: bands round the ring by angle, turning slowly.
    float a = atan2(p.y, p.x);
    float bands = 0.5f + 0.5f * sin(a * bandScale * 3.0f + time * 0.4f)
                * (0.6f + 0.4f * sin(a * bandScale * 7.0f - time * 0.25f));
    float3 metal;
    if (preset < 0.5f) {
        // Chromatic: thin hue fringes on a bright ring — rainbow at the
        // bands' edges, white between.
        float3 hue = lab_linear_to_srgb(lab_palette_linear(fract(a / 6.2831f * 2.0f + time * 0.03f), lab, labCount));
        metal = mix(float3(0.85f), hue * 1.2f, pow(bands, 3.0f) * 0.9f);
    } else if (preset < 1.5f) {
        metal = float3(0.35f + 0.6f * pow(bands, 1.5f));       // silver
    } else {
        metal = float3(0.95f, 0.78f, 0.45f) * (0.45f + 0.6f * pow(bands, 1.5f)); // gold
    }
    // Reflection: a specular highlight on the ring facing the pointer,
    // falling off with distance to it.
    if (pointer.x >= 0.0f && reflect > 0.0f) {
        float2 toP = pointer - hs;
        float pa = atan2(toP.y, toP.x);
        float da = abs(atan2(sin(a - pa), cos(a - pa)));
        float dist = length(toP);
        float near = 1.0f - smoothstep(0.0f, reflectDistance, max(dist - reflectFalloff, 0.0f));
        float spot = pow(max(0.0f, 1.0f - da / 1.2f), specular) * near * reflect;
        metal += float3(1.0f) * spot;
    }
    metal = mix(float3(0.5f), metal, strength);
    float3 out = metal * ring;
    float alpha = min(1.0f, ring + shadow);
    // Premultiplied: the shadow darkens (black at its alpha), the ring adds.
    return half4(half3(out), half(alpha));
}

// MARK: - Dent (distortionEffect) — the cursor bend
//
// Pixels within `reach` of the pointer are pulled toward it by up to
// `maxDent`, strongest at the pointer, easing to nothing at the reach.

[[ stitchable ]] float2 labDent(float2 position, float2 pointer, float reach, float maxDent)
{
    if (pointer.x < 0.0f) return position;
    float2 d = pointer - position;
    float dist = length(d);
    if (dist > reach || dist < 0.001f) return position;
    float k = 1.0f - dist / reach;
    k = k * k * (3.0f - 2.0f * k);
    return position - normalize(d) * maxDent * k * -1.0f;
}

// MARK: - Voice Orb (colorEffect) — assistant-ui's orb, ported
//
// assistant-ui's `VoiceOrb` (MIT, © 2025 AgentbaseAI Inc.), its GLSL
// fragment carried over line for line: a hard circle with a soft edge,
// three simplex noise fields mixed through three colours, a distortion
// field for the veins, a depth shade, a rim, two speculars, an outer
// glow. Their state table and volume mapping live in Swift.

static float3 vo_mod289(float3 x) { return x - floor(x / 289.0f) * 289.0f; }
static float4 vo_mod289(float4 x) { return x - floor(x / 289.0f) * 289.0f; }
static float4 vo_permute(float4 x) { return vo_mod289((x * 34.0f + 1.0f) * x); }
static float4 vo_taylorInvSqrt(float4 r) { return 1.79284291400159f - 0.85373472095314f * r; }

static float vo_snoise(float3 v) {
    const float2 C = float2(1.0f / 6.0f, 1.0f / 3.0f);
    float3 i = floor(v + dot(v, float3(C.y)));
    float3 x0 = v - i + dot(i, float3(C.x));
    float3 g = step(x0.yzx, x0.xyz);
    float3 l = 1.0f - g;
    float3 i1 = min(g, l.zxy);
    float3 i2 = max(g, l.zxy);
    float3 x1 = x0 - i1 + C.x;
    float3 x2 = x0 - i2 + C.y;
    float3 x3 = x0 - 0.5f;
    i = vo_mod289(i);
    float4 p = vo_permute(vo_permute(vo_permute(
        i.z + float4(0.0f, i1.z, i2.z, 1.0f))
        + i.y + float4(0.0f, i1.y, i2.y, 1.0f))
        + i.x + float4(0.0f, i1.x, i2.x, 1.0f));
    float4 j = p - 49.0f * floor(p / 49.0f);
    float4 x_ = floor(j / 7.0f);
    float4 y_ = floor(j - 7.0f * x_);
    float4 x = (x_ * 2.0f + 0.5f) / 7.0f - 1.0f;
    float4 y = (y_ * 2.0f + 0.5f) / 7.0f - 1.0f;
    float4 h = 1.0f - abs(x) - abs(y);
    float4 b0 = float4(x.xy, y.xy);
    float4 b1 = float4(x.zw, y.zw);
    float4 s0 = floor(b0) * 2.0f + 1.0f;
    float4 s1 = floor(b1) * 2.0f + 1.0f;
    float4 sh = -step(h, float4(0.0f));
    float4 a0 = b0.xzyw + s0.xzyw * sh.xxyy;
    float4 a1 = b1.xzyw + s1.xzyw * sh.zzww;
    float3 g0 = float3(a0.xy, h.x);
    float3 g1 = float3(a0.zw, h.y);
    float3 g2 = float3(a1.xy, h.z);
    float3 g3 = float3(a1.zw, h.w);
    float4 norm = vo_taylorInvSqrt(float4(dot(g0, g0), dot(g1, g1), dot(g2, g2), dot(g3, g3)));
    g0 *= norm.x; g1 *= norm.y; g2 *= norm.z; g3 *= norm.w;
    float4 m = max(0.6f - float4(dot(x0, x0), dot(x1, x1), dot(x2, x2), dot(x3, x3)), 0.0f);
    m = m * m;
    return 42.0f * dot(m * m, float4(dot(g0, x0), dot(g1, x1), dot(g2, x2), dot(g3, x3)));
}

[[ stitchable ]] half4 labVoiceOrb(float2 position, half4 color,
                                   float2 size, float time,
                                   float speed, float amplitude, float glowK, float brightness, float pulse, float saturation,
                                   half4 color0, half4 color1, half4 color2)
{
    float2 uv = (position / size) * 2.0f - 1.0f;
    float dist = length(uv);
    float t = time * speed;
    float3 c0 = float3(color0.rgb), c1 = float3(color1.rgb), c2 = float3(color2.rgb);

    float radius = 0.44f;
    float circle = 1.0f - smoothstep(radius - 0.008f, radius + 0.008f, dist);
    if (circle < 0.001f) {
        float glowDist = dist - radius;
        float glow = exp(-glowDist * 12.0f) * glowK * 0.4f;
        float3 glowColor = mix(c0, c1, 0.5f);
        return half4(half3(glowColor * glow), half(glow));
    }

    float n1 = vo_snoise(float3(uv * 2.0f, t * 0.6f)) * 0.5f + 0.5f;
    float n2 = vo_snoise(float3(uv * 3.5f + 7.0f, t * 0.9f)) * 0.5f + 0.5f;
    float n3 = vo_snoise(float3(uv * 1.5f - 3.0f, t * 0.4f + 10.0f)) * 0.5f + 0.5f;
    float2 distort = float2(vo_snoise(float3(uv * 2.0f + 5.0f, t * 0.7f)),
                            vo_snoise(float3(uv * 2.0f + 15.0f, t * 0.7f))) * amplitude * 2.0f;
    float n4 = vo_snoise(float3((uv + distort) * 3.0f, t * 0.5f)) * 0.5f + 0.5f;

    float3 col = mix(c0, c1, n1);
    col = mix(col, c2, n2 * 0.5f);
    col = mix(col, c1 * 1.3f, n4 * 0.4f);
    float vein = pow(n3, 3.0f) * amplitude * 6.0f;
    col += vein * mix(c1, float3(1.0f), 0.3f);
    float centerDist = dist / radius;
    float depthShade = 1.0f - centerDist * centerDist * 0.4f;
    col *= depthShade;
    float rim = pow(centerDist, 4.0f) * 0.6f;
    col += rim * mix(c0, float3(1.0f), 0.5f);
    float2 lightPos = float2(-0.15f, -0.18f);
    float specDist = length(uv - lightPos);
    float spec = exp(-specDist * specDist * 30.0f) * 0.7f;
    col += spec;
    float2 lightPos2 = float2(0.2f, 0.25f);
    float spec2 = exp(-length(uv - lightPos2) * 8.0f) * 0.15f;
    col += spec2 * c1;
    float pulseFactor = 1.0f + pulse * sin(time * 3.5f) * 0.35f;
    float lum = dot(col, float3(0.299f, 0.587f, 0.114f));
    col = mix(float3(lum), col, saturation);
    col *= brightness * pulseFactor;
    col = clamp(col, 0.0f, 1.0f);
    return half4(half3(col * circle), half(circle));
}

// MARK: - Orb 21 (colorEffect) — shadercn's ORB-21, ported
//
// "Light diffusing through a cloud." Shader by XorDev (https://x.com/XorDev),
// ported for shadercn's Orbkit with the author's permission and carried
// here from their TypeGPU source: NON-COMMERCIAL USE ONLY, with attribution
// to XorDev — keep this notice with the file. A ray march through a
// sphere of cos-warped density, a short march toward an orbiting light for
// self-shadowing, Henyey-Greenstein forward scatter, tanh tone map.
//
// knobs: 0 camDist 1 focal 2 radius 3 scale 4 churn 5 threshold 6 edgeSoft
// 7 density 8 absorb 9 shadowAbsorb 10 shadowLift 11 aniso 12 lightSpin
// 13 power 14 ambient 15 exposure 16 alphaGain 17 steps 18 lightSteps

static float o21_density(float3 p, float animTime, float nimbusDensity,
                         float radius, float scale, float churn, float threshold, float edgeSoft)
{
    float shell = 1.0f - length(p) / radius;
    if (shell <= 0.0f) return 0.0f;
    float3 q = p * scale;
    float f = 1.0f;
    for (int k = 0; k < 4; k++) {
        q += cos(float3(q.y, q.z, q.x) * f + animTime * churn) / f;
        f *= 1.8f;
    }
    float n = ((sin(q.x) + sin(q.y) + sin(q.z)) / 3.0f) * 0.5f + 0.5f;
    float clump = smoothstep(threshold, 1.0f, n);
    return clump * pow(shell, edgeSoft) * nimbusDensity;
}

static float o21_phaseHG(float c, float g) {
    float g2 = g * g;
    return (1.0f - g2) / pow(max(1.0f + g2 - 2.0f * g * c, 0.0001f), 1.5f);
}

[[ stitchable ]] half4 labOrb21(float2 position, half4 color,
                                float2 size, float animTime, float inputVol, float outputVol,
                                device const float *knobs, int knobCount,
                                half4 lightColor, half4 shadowColor)
{
    float camDist = knobs[0], focal = knobs[1], radius = knobs[2], scale = knobs[3], churn = knobs[4];
    float threshold = knobs[5], edgeSoft = knobs[6], density = knobs[7], absorb = knobs[8];
    float shadowAbsorb = knobs[9], shadowLift = knobs[10], aniso = knobs[11], lightSpin = knobs[12];
    float power = knobs[13], ambient = knobs[14], exposure = knobs[15], alphaGain = knobs[16];
    int steps = max(8, int(knobs[17]));
    int lightSteps = max(1, int(knobs[18]));
    float3 cLight = float3(lightColor.rgb), cShadow = float3(shadowColor.rgb);

    float nimbusPower = power * (0.7f + 0.9f * outputVol);
    float nimbusDensity = density * (1.0f + 0.35f * inputVol);

    // Their frag coord is y-up; SwiftUI's is y-down.
    float2 fragCoord = float2(position.x, size.y - position.y);
    float2 uv = (fragCoord * 2.0f - size) / min(size.x, size.y);
    float3 ro = float3(0.0f, 0.0f, -camDist);
    float3 rd = normalize(float3(uv.x, uv.y, focal));
    float3 L = normalize(float3(cos(animTime * lightSpin) * 0.7f, 0.45f, sin(animTime * lightSpin) * 0.35f + 0.65f));
    float phase = o21_phaseHG(dot(rd, L), aniso);

    float tStart = max(camDist - radius, 0.0f);
    float span = 2.0f * radius;
    float dt = span / float(steps);
    float T = 1.0f;
    float3 scattered = float3(0.0f);
    float lstep = radius / float(lightSteps);

    for (int i = 0; i < steps; i++) {
        float t = tStart + (float(i) + 0.5f) * dt;
        float3 p = ro + rd * t;
        float dn = o21_density(p, animTime, nimbusDensity, radius, scale, churn, threshold, edgeSoft);
        if (dn > 0.001f) {
            float shadow = 1.0f;
            for (int k = 0; k < lightSteps; k++) {
                float fk = float(k) + 1.0f;
                float3 lp = p + L * ((fk - 0.5f) * lstep);
                shadow *= exp(-o21_density(lp, animTime, nimbusDensity, radius, scale, churn, threshold, edgeSoft) * lstep * shadowAbsorb);
            }
            float3 lit = mix(cShadow * shadowLift, cLight, shadow);
            scattered += lit * (T * dn * dt * phase * nimbusPower);
            T *= exp(-dn * dt * absorb);
            if (T < 0.01f) break;
        }
    }
    float body = 1.0f - T;
    scattered += cShadow * (body * ambient);
    float3 e = exp(clamp(scattered * exposure, -10.0f, 10.0f) * 2.0f);
    float3 col = (e - 1.0f) / (e + 1.0f);
    float a = clamp(body * alphaGain, 0.0f, 1.0f);
    // Scattered light is already premultiplied.
    return half4(half3(clamp(col, 0.0f, 1.0f)), half(a));
}
