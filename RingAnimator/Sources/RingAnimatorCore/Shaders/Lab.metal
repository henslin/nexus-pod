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
                               float cell, float roundness, float gain)
{
    float2 c = floor(position / cell) * cell + cell * 0.5f;
    half4 s = layer.sample(c);
    float2 d = (position - c) / (cell * 0.5f);
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
                                float2 size, float cell, float bulge, float frost, float grout, float coverage)
{
    float edgeX = size.x * (1.0f - coverage);
    if (position.x < edgeX) return layer.sample(position);
    float2 local = float2(position.x - edgeX, position.y);
    float2 c = floor(local / cell) * cell + cell * 0.5f;
    float2 uv = (local - c) / (cell * 0.5f);          // -1…1 within the tile
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
