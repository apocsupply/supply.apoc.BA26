import SwiftUI
import Combine

// MARK: - SelectionViewModel
/// Manages Screen 2 state: the randomised album pool, circular scroll wheel,
/// and scroll momentum.
///
/// **33 ridges per turn**: Exactly 33 album positions per 360° rotation.
/// With 99 albums in the pool, this means exactly 3 full rotations to cycle
/// through all albums.  The list wraps circularly.
///
/// CRITICAL: This ViewModel has ZERO effect on audio.  Screen 2's donut is
/// purely a visual selection wheel.  The currently playing album's audio
/// continues completely unaffected while the user browses.
///
/// The donut on Screen 2 does NOT auto-spin.  It only moves in direct
/// response to the user's circular touch gestures for browsing albums.
///
/// Album transitions use a dithering dissolve driven by scroll position.

@MainActor
final class SelectionViewModel: ObservableObject {

    // MARK: - Published State

    @Published var displayedAlbum: Album

    /// 0–1 progress between the current album ridge and the next.
    /// Drives the dithering transition on the background.
    @Published var scrollDitherProgress: CGFloat = 0

    /// The album that will become `displayedAlbum` when the scroll crosses the
    /// next ridge threshold.  `nil` when the user isn't scrolling.
    @Published var nextScrollAlbum: Album?

    // MARK: - Pool

    private(set) var albumPool: [Album] = []
    private var currentIndex: Int = 0

    // MARK: - Scroll Wheel
    //
    // 33 albums per full 360° turn.
    // 99 albums ÷ 33 = exactly 3 full rotations.

    private var lastAngle: Double = 0
    private var accumulatedDelta: Double = 0
    private let degreesPerAlbum: Double = 360.0 / 33.0

    // MARK: - Momentum

    private var momentumVelocity: Double = 0
    private var momentumTimer: Timer?
    private let frictionDecel: Double = 600

    // MARK: - Snap Animation

    private var snapTimer: Timer?
    private var snapStartProgress: CGFloat = 0
    private var snapTargetProgress: CGFloat = 0
    private var snapDuration: TimeInterval = 0
    private var snapElapsed: TimeInterval = 0
    private var snapIsForward: Bool = false
    private var snapScrollDirection: Bool = true

    private let haptics = HapticManager.shared

    // MARK: - Init

    init() {
        self.displayedAlbum = Album.allAlbums.first
            ?? Album(id: 1, rank: 1, title: "Unknown", artist: "Unknown")
    }

    // MARK: - Pool Setup

    func setupPool(excluding playingAlbum: Album) {
        albumPool = Album.allAlbums
            .filter { $0.id != playingAlbum.id }
            .shuffled()

        currentIndex = 0
        accumulatedDelta = 0
        scrollDitherProgress = 0
        nextScrollAlbum = nil
        if let first = albumPool.first {
            displayedAlbum = first
        }
    }

    // MARK: - Scroll Gesture Handlers (NO audio effects)

    func scrollBegan(at angle: Double) {
        lastAngle = angle
        accumulatedDelta = 0
        scrollDitherProgress = 0
        nextScrollAlbum = nil
        momentumTimer?.invalidate()
        snapTimer?.invalidate()
        momentumVelocity = 0
    }

    func scrollChanged(to angle: Double) {
        let delta = RingGestureOverlay.angleDelta(from: lastAngle, to: angle)
        accumulatedDelta += delta
        lastAngle = angle

        while accumulatedDelta > degreesPerAlbum {
            accumulatedDelta -= degreesPerAlbum
            advanceAlbum(forward: true)
        }
        while accumulatedDelta < -degreesPerAlbum {
            accumulatedDelta += degreesPerAlbum
            advanceAlbum(forward: false)
        }

        updateScrollDitherState()
    }

    func scrollEnded(velocity: Double) {
        let flickThreshold: Double = 150
        if abs(velocity) > flickThreshold {
            momentumVelocity = velocity
            startMomentum()
        } else {
            snapToClosestRidge()
        }
    }

    /// Reset scroll dithering state (called when leaving Screen 2).
    func resetScrollProgress() {
        scrollDitherProgress = 0
        nextScrollAlbum = nil
        accumulatedDelta = 0
        snapTimer?.invalidate()
    }

    // MARK: - Album Advance (circular wrap)

    private func advanceAlbum(forward: Bool) {
        guard !albumPool.isEmpty else { return }

        haptics.scrollDetent()

        if forward {
            currentIndex = (currentIndex + 1) % albumPool.count
        } else {
            currentIndex = (currentIndex - 1 + albumPool.count) % albumPool.count
        }

        displayedAlbum = albumPool[currentIndex]
    }

    // MARK: - Scroll Dithering

    private func updateScrollDitherState() {
        guard !albumPool.isEmpty else {
            scrollDitherProgress = 0
            nextScrollAlbum = nil
            return
        }

        let frac = abs(accumulatedDelta) / degreesPerAlbum
        scrollDitherProgress = min(frac, 1.0)

        if frac > 0.02 {
            let forward = accumulatedDelta > 0
            let nextIndex = forward
                ? (currentIndex + 1) % albumPool.count
                : (currentIndex - 1 + albumPool.count) % albumPool.count
            nextScrollAlbum = albumPool[nextIndex]
        } else {
            nextScrollAlbum = nil
        }
    }

    // MARK: - Momentum

    private func startMomentum() {
        momentumTimer?.invalidate()
        accumulatedDelta = 0

        momentumTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let dt = 1.0 / 60.0
                let sign: Double = self.momentumVelocity > 0 ? 1 : -1
                self.momentumVelocity -= sign * self.frictionDecel * dt

                if sign * self.momentumVelocity <= 0 {
                    self.momentumVelocity = 0
                    self.momentumTimer?.invalidate()
                    self.snapToClosestRidge()
                    return
                }

                self.accumulatedDelta += self.momentumVelocity * dt

                while self.accumulatedDelta > self.degreesPerAlbum {
                    self.accumulatedDelta -= self.degreesPerAlbum
                    self.advanceAlbum(forward: true)
                }
                while self.accumulatedDelta < -self.degreesPerAlbum {
                    self.accumulatedDelta += self.degreesPerAlbum
                    self.advanceAlbum(forward: false)
                }

                self.updateScrollDitherState()
            }
        }
    }

    // MARK: - Snap to Ridge

    private func snapToClosestRidge() {
        snapTimer?.invalidate()

        let currentFrac = abs(accumulatedDelta) / degreesPerAlbum

        if currentFrac < 0.01 {
            scrollDitherProgress = 0
            nextScrollAlbum = nil
            accumulatedDelta = 0
            return
        }

        snapIsForward = currentFrac > 0.5
        snapScrollDirection = accumulatedDelta > 0
        snapStartProgress = scrollDitherProgress
        snapElapsed = 0

        if snapIsForward {
            snapTargetProgress = 1.0
            snapDuration = 0.42 * (1.0 - currentFrac)

            if nextScrollAlbum == nil, !albumPool.isEmpty {
                let nextIndex = snapScrollDirection
                    ? (currentIndex + 1) % albumPool.count
                    : (currentIndex - 1 + albumPool.count) % albumPool.count
                nextScrollAlbum = albumPool[nextIndex]
            }
        } else {
            snapTargetProgress = 0.0
            snapDuration = 0.42 * currentFrac
        }

        if snapDuration < 0.01 {
            finishSnap()
            return
        }

        snapTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 120.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.snapElapsed += 1.0 / 120.0
                let t = min(self.snapElapsed / self.snapDuration, 1.0)
                let eased = 1.0 - (1.0 - t) * (1.0 - t)

                self.scrollDitherProgress = self.snapStartProgress
                    + (self.snapTargetProgress - self.snapStartProgress) * eased

                if t >= 1.0 {
                    self.snapTimer?.invalidate()
                    self.finishSnap()
                }
            }
        }
    }

    private func finishSnap() {
        if snapIsForward {
            advanceAlbum(forward: snapScrollDirection)
        }
        scrollDitherProgress = 0
        nextScrollAlbum = nil
        accumulatedDelta = 0
    }

    // MARK: - Cleanup

    func tearDown() {
        momentumTimer?.invalidate()
        snapTimer?.invalidate()
    }
}
