import SwiftUI

// MARK: - RingGestureOverlay
/// An invisible overlay that recognises circular drag gestures on a donut-shaped
/// hit region. Reports angular position changes and angular velocity.

struct RingGestureOverlay: View {

    let outerRadius: CGFloat
    let innerRadius: CGFloat

    /// Called once when the finger first touches the ring.
    var onBegan: ((_ angle: Double) -> Void)?

    /// Called every frame the finger moves. Includes the current angle.
    var onChanged: ((_ angle: Double) -> Void)?

    /// Called when the finger lifts. Includes the estimated angular velocity (°/s).
    var onEnded: ((_ velocity: Double) -> Void)?

    // MARK: - Private State

    @State private var lastAngle: Double?
    @State private var lastTime: Date?
    @State private var velocitySamples: [Double] = []

    // MARK: - Body

    var body: some View {
        let diameter = outerRadius * 2
        Color.clear
            .frame(width: diameter, height: diameter)
            .contentShape(donutShape)
            .gesture(dragGesture)
    }

    // MARK: - Helpers

    private var donutShape: DonutShape {
        DonutShape(outerRadius: outerRadius, innerRadius: innerRadius)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let center = CGPoint(x: outerRadius, y: outerRadius)
                let currentAngle = Self.angle(of: value.location, relativeTo: center)

                if lastAngle == nil {
                    // Touch began
                    lastAngle = currentAngle
                    lastTime = Date()
                    velocitySamples.removeAll()
                    onBegan?(currentAngle)
                    return
                }

                // Calculate velocity
                let now = Date()
                if let lt = lastTime {
                    let dt = now.timeIntervalSince(lt)
                    if dt > 0 {
                        let delta = Self.angleDelta(from: lastAngle!, to: currentAngle)
                        let vel = delta / dt
                        velocitySamples.append(vel)
                        // Keep a sliding window of recent samples
                        if velocitySamples.count > 5 {
                            velocitySamples.removeFirst()
                        }
                    }
                }

                onChanged?(currentAngle)
                lastAngle = currentAngle
                lastTime = now
            }
            .onEnded { _ in
                // Average recent velocity samples for a smooth flick estimate
                let avgVelocity: Double
                if velocitySamples.isEmpty {
                    avgVelocity = 0
                } else {
                    avgVelocity = velocitySamples.reduce(0, +) / Double(velocitySamples.count)
                }
                onEnded?(avgVelocity)
                lastAngle = nil
                lastTime = nil
                velocitySamples.removeAll()
            }
    }

    // MARK: - Geometry

    /// Angle (in degrees) of `point` relative to `center`. 0° = right, 90° = down.
    static func angle(of point: CGPoint, relativeTo center: CGPoint) -> Double {
        atan2(Double(point.y - center.y), Double(point.x - center.x)) * 180 / .pi
    }

    /// Signed angular delta normalised to (−180°, 180°].
    /// Positive = clockwise in screen coordinates.
    static func angleDelta(from a: Double, to b: Double) -> Double {
        var d = b - a
        while d >  180 { d -= 360 }
        while d < -180 { d += 360 }
        return d
    }
}
