import CoreGraphics

// MARK: - DonutMetrics
/// Provides the exact donut dimensions for each screen and interpolation helpers.
/// All values are in points (divide the spec's pixel values by 3).

enum DonutMetrics {

    // ───── Screen 1 (Play) ─────
    static let playOuterDiameter: CGFloat = 163      // 488 px / 3
    static let playInnerDiameter: CGFloat = 41       // 122 px / 3
    static let playOuterRadius: CGFloat   = 81.5
    static let playInnerRadius: CGFloat   = 20.5
    // Ring width ≈ 61 pt

    // ───── Screen 2 (Selection) ─────
    static let selectOuterDiameter: CGFloat = 325    // 976 px / 3
    static let selectInnerDiameter: CGFloat = 244    // 732 px / 3
    static let selectOuterRadius: CGFloat   = 162.5
    static let selectInnerRadius: CGFloat   = 122
    // Ring width ≈ 40.5 pt

    // ───── Helpers ─────

    /// Linear interpolation between `a` and `b` at progress `t` (0…1).
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    /// Outer radius at the given transition progress (0 = play, 1 = selection).
    static func outerRadius(at progress: CGFloat) -> CGFloat {
        lerp(playOuterRadius, selectOuterRadius, progress)
    }

    /// Inner radius at the given transition progress.
    static func innerRadius(at progress: CGFloat) -> CGFloat {
        lerp(playInnerRadius, selectInnerRadius, progress)
    }
}
