#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// MARK: - donutDistort
/// Liquid-glass distortion shader for a donut (annulus) shape.
/// Adapted from a circle-based distortion; works with SwiftUI `.layerEffect`.
///
/// Pixels inside the ring get ripple distortion + edge refraction.
/// Pixels outside the ring pass through unchanged.
///
/// All radii are in points.  The shader converts them to aspect-corrected
/// UV space internally so the donut is always circular on screen.
///
/// Usage in SwiftUI:
///   .layerEffect(
///       ShaderLibrary.donutDistort(
///           .boundingRect,
///           .float(outerRadius),
///           .float(innerRadius),
///           .float(distortion)
///       ),
///       maxSampleOffset: CGSize(width: 50, height: 50)
///   )

[[ stitchable ]] half4 donutDistort(
    float2 pos,
    SwiftUI::Layer l,
    float4 bounds,
    float outerR,
    float innerR,
    float distortion
) {
    float2 size = bounds.zw;
    float2 uv = pos / size;
    float2 center = float2(0.5, 0.5);
    float2 delta = uv - center;

    // Aspect-correct so the donut is circular on a non-square screen
    float aspect = size.x / size.y;
    float2 ad = float2(delta.x * aspect, delta.y);
    float dist = length(ad);

    // Radii in aspect-corrected UV space
    float oR = outerR / size.y;
    float iR = innerR / size.y;
    float mid = (oR + iR) * 0.5;
    float hw  = (oR - iR) * 0.5;

    // ── Smooth donut mask ──
    float oMask = 1.0 - smoothstep(oR - 0.004, oR + 0.002, dist);
    float iMask = smoothstep(iR - 0.002, iR + 0.004, dist);
    float donutMask = oMask * iMask;

    // Ring-centre falloff: 1 at the midline of the ring, 0 at edges
    float t = clamp(abs(dist - mid) / max(hw, 0.001), 0.0, 1.0);
    float ringFalloff = 1.0 - t * t;

    // ── Liquid distortion (adapted from circle shader) ──

    // Ripple pattern
    float2 ripple = float2(sin(delta.x * 3.0), cos(delta.y * 3.0));

    // Edge refraction: radial push outward at outer edge, inward at inner
    float2 radial = ad / max(dist, 0.001);
    radial.x /= aspect;   // convert back to UV space
    float outerEdge = smoothstep(mid, oR, dist);
    float innerEdge = smoothstep(mid, iR, dist);

    float2 newpos = uv;
    newpos -= ripple * distortion * ringFalloff;
    newpos += radial * pow(outerEdge, 2.0) * distortion * 0.5;
    newpos -= radial * pow(innerEdge, 2.0) * distortion * 0.5;

    // ── Sample & blend ──
    half4 distorted = l.sample(newpos * size);
    half4 original  = l.sample(pos);

    // Ring area → distorted, outside → original (unchanged)
    return mix(original, distorted, half(donutMask));
}
