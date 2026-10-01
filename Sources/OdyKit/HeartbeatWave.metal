#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// HeartbeatWave.swift's ECG, sampled per pixel: a glowing trace, brightest at its leading edge, scrolling at bpm.

static float bump(float x, float c, float w, float h) {
    float d = (x - c) / w;
    return h * exp(-d * d);
}

static float ecg(float phase) {
    float x = phase - floor(phase);
    return bump(x, 0.18, 0.025, 0.12) + bump(x, 0.275, 0.008, -0.12) + bump(x, 0.3, 0.012, 1.0)
        + bump(x, 0.325, 0.01, -0.22) + bump(x, 0.5, 0.05, 0.25);
}

[[ stitchable ]] half4 heartbeatWave(float2 position, half4 color, float2 size, float time, float bpm) {
    const float beats = 2.5;
    float phase = position.x / size.x * beats + time * bpm / 60.0;
    float y = size.y * (0.6 - 0.45 * ecg(phase));
    // Perpendicular distance, not vertical: slope in pixels from one pixel either side, so the R spike keeps the line's weight.
    float perPixel = beats / size.x;
    float yBefore = size.y * (0.6 - 0.45 * ecg(phase - perPixel));
    float yAfter = size.y * (0.6 - 0.45 * ecg(phase + perPixel));
    float slope = (yAfter - yBefore) * 0.5;
    float d = abs(position.y - y) / sqrt(1.0 + slope * slope);
    float core = smoothstep(2.0, 0.0, d);
    float glow = exp(-d * d / 60.0) * 0.45;
    // Fade in from the left edge so the trace reads as moving toward the right.
    float edge = smoothstep(0.0, 0.25, position.x / size.x);
    float a = clamp(core + glow, 0.0, 1.0) * edge;
    return half4(color.rgb * a, a);
}
