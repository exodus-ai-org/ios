#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The desktop's dither field (beui "image forming"): a grid of dots on a 10 pt pitch; a soft cluster drifts over it,
// swelling and pushing the dots near it, while a sparse ordered-dither sparkle flickers over a gradient wash.
// Drawn over a shape filled with the tone, so `color` is the tone; the result is the tone at the field's alpha.

static float hash21(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

static float bayer4(float2 cell) {
    const float m[16] = { 0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5 };
    int2 i = int2(fmod(cell, 4.0));
    return (m[i.y * 4 + i.x] + 0.5) / 16.0;
}

[[ stitchable ]] half4 imageForming(float2 position, half4 color, float2 size, float time) {
    const float gap = 10.0;
    float2 cluster = size * 0.5 + float2(sin(time / 1.7) * size.x * 0.12, cos(time / 2.1) * size.y * 0.10);
    float radius = min(size.x, size.y) * 0.38;
    float2 origin = (size - (floor(size / gap)) * gap) * 0.5;

    float dots = 0.0;
    float2 cell = floor((position - origin) / gap + 0.5);
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            float2 anchor = origin + (cell + float2(dx, dy)) * gap;
            float2 delta = anchor - cluster;
            float distance = length(delta);
            float proximity = max(0.0, 1.0 - distance / radius);
            float influence = proximity * proximity * (3.0 - 2.0 * proximity);
            float2 direction = distance > 0.0 ? delta / distance : float2(0.0);
            float2 spot = anchor + direction * influence * influence * 9.0;
            float dotRadius = 0.65 + influence * 0.85;
            float coverage = 1.0 - smoothstep(dotRadius - 0.5, dotRadius + 0.5, length(position - spot));
            dots = max(dots, coverage * (0.22 + influence * 0.72));
        }
    }

    float2 uv = position / max(size, float2(1.0));
    float glow = max(0.0, 1.0 - length(position - cluster) / (radius * 1.6));
    float wash = 0.06 + 0.10 * glow + 0.05 * (1.0 - uv.y);
    float2 pixel = floor(position / 2.0);
    float flicker = hash21(pixel + float2(floor(time * 6.0) * 17.0, 0.0));
    float sparkle = step(bayer4(pixel) * 0.5 + 0.62, glow * 0.55 + flicker * 0.45) * 0.3;

    float alpha = clamp(max(dots, max(wash, sparkle)), 0.0, 1.0);
    return half4(color.rgb, 1.0h) * half(alpha) * color.a;
}
