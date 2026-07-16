#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 ditherTransition(
    float2 pos,
    SwiftUI::Layer l,
    float4 bounds,
    float progress,
    float time
) {
    float2 size = bounds.zw;
    float t = 0.5 * time;

    float pxSize = 1.0;
    float2 pxUV = floor(pos / pxSize);
    float2 cellCenter = (pxUV + 0.5) * pxSize;

    // Warp shape — ported from Paper Shaders (shape="warp")
    float2 shapeUV = (cellCenter - 0.5 * size) * 0.005;
    for (float i = 1.0; i < 6.0; i += 1.0) {
        shapeUV.x += 0.6 / i * cos(i * 2.5 * shapeUV.y + t);
        shapeUV.y += 0.6 / i * cos(i * 1.5 * shapeUV.x + t);
    }
    float shape = 0.15 / max(0.001, abs(sin(t - shapeUV.y - shapeUV.x)));
    shape = smoothstep(0.02, 1.0, shape);

    // 4×4 Bayer dithering — ported from Paper Shaders (type="4x4")
    int2 bc = int2(pxUV);
    int bx = ((bc.x % 4) + 4) % 4;
    int by = ((bc.y % 4) + 4) % 4;
    const int bayer4x4[16] = {
         0,  8,  2, 10,
        12,  4, 14,  6,
         3, 11,  1,  9,
        15,  7, 13,  5
    };
    float dithering = float(bayer4x4[by * 4 + bx]) / 16.0 - 0.5;

    // Reference formula: step(0.5, shape + dithering)
    // Shift shape by (1−progress)*2−1 to drive the transition:
    //   progress 0 → shape+1 → all above 0.5 → fully visible
    //   progress 1 → shape−1 → all below 0.5 → fully invisible
    float shiftedShape = shape + (1.0 - progress) * 2.0 - 1.0;
    float visible = step(0.5, shiftedShape + dithering);

    half4 color = l.sample(pos);
    color *= half(visible);
    return color;
}
