import CoreMotion
import SwiftUI

// MARK: - AppScreen

enum AppScreen: Sendable {
    case play
    case selection
}

// MARK: - TiltManager
/// Reads device pitch via CoreMotion and determines which screen should be active.
///
/// CRITICAL FIX: Motion updates start/stop with the app's foreground state.
///   - `startIfActive()` begins updates only when the app is `.active`.
///   - `stopUpdates()` halts them immediately when the app goes to background
///     or inactive.  Zero tilt detection occurs while backgrounded.

@MainActor
final class TiltManager: ObservableObject {

    @Published var currentScreen: AppScreen = .play
    @Published var angleFromHorizontal: Double = 90

    private let motionManager = CMMotionManager()
    private let playThreshold: Double = 50
    private let selectionThreshold: Double = 40

    private var isRunning = false

    // MARK: - Foreground / Background

    /// Call when scenePhase becomes `.active`.
    func startIfActive() {
        #if targetEnvironment(simulator)
        return
        #else
        guard !isRunning else { return }
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.processMotion(motion)
        }
        isRunning = true
        #endif
    }

    /// Call when scenePhase leaves `.active` (→ `.inactive` or `.background`).
    func stopUpdates() {
        #if targetEnvironment(simulator)
        return
        #else
        guard isRunning else { return }
        motionManager.stopDeviceMotionUpdates()
        isRunning = false
        #endif
    }

    // MARK: - Legacy (kept for RootView onDisappear symmetry)

    func start() { startIfActive() }
    func stop() { stopUpdates() }

    /// Manual toggle for Simulator testing or accessibility.
    func manualToggle() {
        currentScreen = currentScreen == .play ? .selection : .play
    }

    // MARK: - Private

    private func processMotion(_ motion: CMDeviceMotion) {
        let g = motion.gravity
        guard abs(g.x) < 0.7, g.z < 0.1 else { return }

        let radians = atan2(-g.z, sqrt(g.x * g.x + g.y * g.y))
        let degrees = radians * 180.0 / .pi
        angleFromHorizontal = degrees

        switch currentScreen {
        case .play:
            if degrees < selectionThreshold {
                currentScreen = .selection
            }
        case .selection:
            if degrees > playThreshold {
                currentScreen = .play
            }
        }
    }
}
