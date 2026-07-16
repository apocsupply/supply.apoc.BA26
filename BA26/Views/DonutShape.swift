import SwiftUI

// MARK: - DonutShape
/// A ring (annulus) shape defined by outer and inner radii.
/// Conforms to `InsettableShape` so it can be used with `.glassEffect(in:)`.
///
/// The two arcs use **opposite winding directions** so that the centre hole
/// is produced by both the non-zero winding rule (used by `.glassEffect`)
/// and the even-odd fill rule (used by the mask fallback).

struct DonutShape: InsettableShape {
    var outerRadius: CGFloat
    var innerRadius: CGFloat

    // MARK: - Animatable

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(outerRadius, innerRadius) }
        set {
            outerRadius = newValue.first
            innerRadius = newValue.second
        }
    }

    // MARK: - Shape

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()

        // Outer circle — counter-clockwise (winding +1)
        path.addArc(
            center: center,
            radius: max(outerRadius, 0),
            startAngle: .zero,
            endAngle: .degrees(360),
            clockwise: false
        )

        // Inner circle — CLOCKWISE (winding −1 → cancels outer → hole)
        path.addArc(
            center: center,
            radius: max(innerRadius, 0),
            startAngle: .zero,
            endAngle: .degrees(360),
            clockwise: true
        )

        return path
    }

    // MARK: - InsettableShape

    func inset(by amount: CGFloat) -> DonutShape {
        DonutShape(
            outerRadius: outerRadius - amount,
            innerRadius: innerRadius + amount
        )
    }
}
