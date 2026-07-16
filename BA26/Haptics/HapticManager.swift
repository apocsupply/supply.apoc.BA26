import UIKit

// MARK: - HapticManager
/// Thin wrapper around UIImpactFeedbackGenerator for the two haptic patterns
/// the app uses: vinyl grab and scroll-wheel detent.

@MainActor
final class HapticManager {
    static let shared = HapticManager()

    private let lightGenerator = UIImpactFeedbackGenerator(style: .light)

    private init() {
        lightGenerator.prepare()
    }

    /// Fired once when the user first touches the vinyl ring.
    func vinylGrab() {
        lightGenerator.impactOccurred()
    }

    /// Fired at each album increment while scrolling the selection wheel.
    func scrollDetent() {
        lightGenerator.impactOccurred(intensity: 0.6)
    }

    /// Re-prepare generators (call after a period of inactivity).
    func prepare() {
        lightGenerator.prepare()
    }
}
