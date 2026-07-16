import SwiftUI
import AVFoundation
import Combine
import QuartzCore

// MARK: - PlaybackViewModel
/// Manages Screen 1: current album, vinyl rotation, audio engine, fast-seek
/// interaction (hold left = 60× rewind, hold right = 60× fast-forward),
/// the auto-rewind animation, and Now Playing / remote-command integration.
///
/// **Hold interaction**:
///   The donut ring is split vertically.  Holding the RIGHT half fast-forwards
///   at 60× speed; holding the LEFT half rewinds at 60× speed.  Audio is
///   paused (silent) during the hold.
///
///   Forward hold stops at stage 100.  Rewind triggers only on release.
///   Backward hold stops at stage 0.

@MainActor
final class PlaybackViewModel: ObservableObject {

    // MARK: - Published State

    @Published var currentAlbum: Album
    @Published var rotationDegrees: Double = 0
    @Published var isRewinding: Bool = false
    @Published var isHolding: Bool = false
    @Published var blockInteraction: Bool = false

    /// True when the user paused via Lock Screen / Control Centre.
    var isPausedByRemote: Bool = false

    // MARK: - Audio

    let audioEngine = VinylAudioEngine()

    // MARK: - Hold State  (left = rewind 60×, right = fast-forward 60×)

    private var holdForward: Bool = true
    private var holdTimer: Timer?
    private var holdActivationTimer: Timer?
    private let holdSpeedMultiplier: Double = 60.0

    /// True when a forward hold has reached the end of the album.  The vinyl
    /// stops spinning; the rewind animation triggers only when the user lifts
    /// their finger.
    private var holdReachedEnd: Bool = false

    /// True when a backward hold has reached the beginning.  Vinyl stays at 0.
    private var holdReachedStart: Bool = false

    /// After a seek the engine's reported position may be stale for a couple
    /// of frames.  Skip `deriveRotationFromAudio` briefly to prevent a snap.
    private var skipDeriveCount: Int = 0

    /// True between `prepareForTransitionToPlay` and `startPlaybackAfterTransition`.
    /// Prevents `deriveRotationFromAudio()` from reading the OLD album's
    /// position while the transition animation is in flight.
    private var awaitingAlbumLoad: Bool = false

    // MARK: - Sound Effect

    private var sfxPlayer: AVAudioPlayer?

    // MARK: - Rewind

    private var rewindTimer: Timer?

    // MARK: - Now Playing

    private let nowPlayingManager = NowPlayingManager.shared
    private let haptics = HapticManager.shared
    private var nowPlayingTimer: Timer?

    // MARK: - Init

    init(album: Album) {
        self.currentAlbum = album
    }

    // MARK: - Setup

    func setup() {
        audioEngine.setup()
        audioEngine.loadAlbum(currentAlbum)

        audioEngine.onAlbumEnd = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, !self.isHolding else { return }
                self.startRewind()
            }
        }

        audioEngine.onInterrupted = { [weak self] in
            Task { @MainActor [weak self] in
                self?.updateNowPlaying()
            }
        }

        audioEngine.onAutoResume = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPausedByRemote = false
                self.updateNowPlaying()
            }
        }

        prepareSoundEffect()

        // ── Now Playing ──

        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }

                self.nowPlayingManager.configure()

                self.nowPlayingManager.onRemotePlay = { [weak self] in
                    MainActor.assumeIsolated { self?.handleRemotePlay() }
                }
                self.nowPlayingManager.onRemotePause = { [weak self] in
                    MainActor.assumeIsolated { self?.handleRemotePause() }
                }
                self.nowPlayingManager.onRemoteToggle = { [weak self] in
                    MainActor.assumeIsolated {
                        guard let self else { return }
                        if self.isPausedByRemote {
                            self.handleRemotePlay()
                        } else {
                            self.handleRemotePause()
                        }
                    }
                }

                self.updateNowPlaying()

                self.nowPlayingTimer = Timer.scheduledTimer(
                    withTimeInterval: 0.5,
                    repeats: true
                ) { [weak self] _ in
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { self?.updateNowPlaying() }
                    }
                }
            }
        }
    }

    // MARK: - Frame Update  (called from TimelineView ≈120 Hz)

    func updateRotation(dt: TimeInterval) {
        guard !isRewinding else { return }

        if isHolding {
            if holdReachedEnd || holdReachedStart {
                return
            }
            let direction: Double = holdForward ? 1 : -1
            let speed = VinylAudioEngine.degreesPerSecond * holdSpeedMultiplier
            rotationDegrees = max(0, rotationDegrees + direction * speed * dt)
            return
        }

        // ── Derive rotation from audio position ──
        if awaitingAlbumLoad {
            return
        } else if skipDeriveCount > 0 {
            skipDeriveCount -= 1
        } else {
            deriveRotationFromAudio()
        }
    }

    // MARK: - Rotation Sync

    /// Snap `rotationDegrees` to match the current audio engine position.
    /// Call before a transition animation so the vinyl doesn't jump.
    func syncRotationToAudio() {
        deriveRotationFromAudio()
    }

    // MARK: - Hold Interaction  (Screen 1)
    //
    // The donut ring is split vertically:
    //   Left half  → rewind at 60× speed
    //   Right half → fast-forward at 60× speed
    //
    // Audio is paused (silent) during the hold.  A timer seeks the position
    // at 60× speed.  The vinyl spins smoothly via `updateRotation`.
    //
    // Forward hold stops at the end (stage 100); rewind triggers on release.
    // Backward hold stops at the beginning (stage 0).

    func holdBegan(forward: Bool) {
        guard !blockInteraction else { return }
        holdForward = forward
        holdReachedEnd = false
        holdReachedStart = false

        holdActivationTimer?.invalidate()
        holdActivationTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 3.0,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.activateHold()
            }
        }
    }

    private func activateHold() {
        guard !blockInteraction else { return }
        isHolding = true
        haptics.vinylGrab()
        playSoundEffect()

        audioEngine.pause()

        let interval: TimeInterval = 1.0 / 20.0
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(
            withTimeInterval: interval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isHolding,
                      !self.holdReachedEnd, !self.holdReachedStart else { return }

                let duration = self.audioEngine.getDuration()
                guard duration > 0 else { return }

                let currentTime = self.audioEngine.getCurrentTime()
                let seekAmount = (self.holdForward ? 1.0 : -1.0)
                    * self.holdSpeedMultiplier * interval
                let newTime = currentTime + seekAmount

                if self.holdForward && newTime >= duration {
                    self.audioEngine.seek(toProgress: 1.0)
                    self.audioEngine.pause()
                    self.holdReachedEnd = true

                    let totalTurns = duration * VinylAudioEngine.normalTurnsPerSecond
                    self.rotationDegrees = totalTurns * 360.0
                    return
                }

                if !self.holdForward && newTime <= 0 {
                    self.audioEngine.seek(toProgress: 0)
                    self.audioEngine.pause()
                    self.holdReachedStart = true
                    self.rotationDegrees = 0
                    return
                }

                let targetProgress = max(0, min(newTime / duration, 1.0))
                self.audioEngine.seek(toProgress: targetProgress)
            }
        }
    }

    func holdEnded() {
        holdActivationTimer?.invalidate()
        holdActivationTimer = nil

        guard isHolding else { return }
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil

        if holdReachedEnd {
            holdReachedEnd = false
            holdReachedStart = false
            startRewind()
            return
        }

        holdReachedEnd = false
        holdReachedStart = false

        let duration = audioEngine.getDuration()
        let totalTurns = duration * VinylAudioEngine.normalTurnsPerSecond
        if totalTurns > 0 && duration > 0 {
            let targetProgress = max(0, min(
                rotationDegrees / (totalTurns * 360.0), 1.0
            ))
            audioEngine.seek(toProgress: targetProgress)
        }

        skipDeriveCount = 3

        audioEngine.setRate(1.0)
        audioEngine.resume()
        updateNowPlaying()
    }

    // MARK: - Auto-Rewind  (33 turns + fractional, 1 second, ease-out, silent)

    func startRewind() {
        guard !isRewinding else { return }
        isRewinding = true
        blockInteraction = true
        isHolding = false
        holdTimer?.invalidate()
        holdTimer = nil

        let startRotation = rotationDegrees

        audioEngine.pause()

        guard startRotation > 0 else {
            completeRewind()
            return
        }

        let fractional = startRotation.truncatingRemainder(dividingBy: 360.0)
        let adjustedFrac = fractional >= 0 ? fractional : fractional + 360.0
        let totalRewindDegrees = 33.0 * 360.0 + adjustedFrac

        let startTime = CACurrentMediaTime()

        rewindTimer?.invalidate()
        rewindTimer = Timer.scheduledTimer(
            withTimeInterval: 1.0 / 60.0,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRewinding else {
                    self?.rewindTimer?.invalidate()
                    return
                }

                let elapsed = CACurrentMediaTime() - startTime
                let t = min(elapsed / 1.0, 1.0)

                let easeOut = 1.0 - pow(1.0 - t, 3.0)
                self.rotationDegrees = startRotation - totalRewindDegrees * easeOut

                if t >= 1.0 {
                    self.completeRewind()
                }
            }
        }
    }

    func cancelRewind() {
        rewindTimer?.invalidate()
        rewindTimer = nil
        isRewinding = false
        blockInteraction = false
    }

    private func completeRewind() {
        rewindTimer?.invalidate()
        rewindTimer = nil

        rotationDegrees = 0
        audioEngine.seek(toProgress: 0)
        audioEngine.setRate(1.0)
        audioEngine.resume()

        isRewinding = false
        blockInteraction = false
        updateNowPlaying()
    }

    // MARK: - Album Switch

    func switchAlbum(_ album: Album) {
        cancelRewind()
        isPausedByRemote = false
        currentAlbum = album
        rotationDegrees = 0
        audioEngine.loadAlbum(album)
        audioEngine.setRate(1.0)
        updateNowPlaying()
    }

    func prepareForTransitionToPlay(with album: Album) {
        cancelRewind()
        isPausedByRemote = false
        currentAlbum = album
        rotationDegrees = 0
        awaitingAlbumLoad = true
    }

    func startPlaybackAfterTransition() {
        audioEngine.loadAlbum(currentAlbum)
        audioEngine.setRate(1.0)
        awaitingAlbumLoad = false
        skipDeriveCount = 5
        updateNowPlaying()
    }

    func resumePlayback() {
        audioEngine.setRate(1.0)
        audioEngine.resume()
        isPausedByRemote = false
        updateNowPlaying()
    }

    // MARK: - Remote Play / Pause  (Lock Screen & Control Centre)

    func handleRemotePlay() {
        isPausedByRemote = false
        audioEngine.setRate(1.0)
        audioEngine.resume()
        updateNowPlaying()
    }

    func handleRemotePause() {
        isPausedByRemote = true
        audioEngine.pause()
        updateNowPlaying()
    }

    func handleForegroundResume() {
        try? AVAudioSession.sharedInstance().setActive(true)

        let wasRemotePaused = isPausedByRemote
        let enginePaused = audioEngine.isPaused

        guard wasRemotePaused || enginePaused else { return }

        isPausedByRemote = false
        audioEngine.resume()
        updateNowPlaying()

        for delay in [0.3, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated { self?.updateNowPlaying() }
            }
        }
    }

    // MARK: - Cleanup

    func tearDown() {
        nowPlayingTimer?.invalidate()
        holdActivationTimer?.invalidate()
        holdTimer?.invalidate()
        rewindTimer?.invalidate()
        audioEngine.stop()
    }

    // MARK: - Private Helpers

    private func deriveRotationFromAudio() {
        let progress = audioEngine.getProgress()
        let duration = audioEngine.getDuration()
        guard duration > 0 else { return }
        let totalTurns = duration * VinylAudioEngine.normalTurnsPerSecond
        rotationDegrees = progress * totalTurns * 360.0
    }

    private func updateNowPlaying() {
        let rate: Double
        if isPausedByRemote || isRewinding || isHolding {
            rate = 0.0
        } else {
            rate = 1.0
        }
        nowPlayingManager.update(
            album: currentAlbum,
            elapsed: audioEngine.getCurrentTime(),
            duration: audioEngine.getDuration(),
            rate: rate
        )
    }

    // MARK: - Sound Effect

    private func prepareSoundEffect() {
        guard let url = Bundle.main.url(
            forResource: "sound",
            withExtension: "mp3",
            subdirectory: "assets"
        ) else { return }
        sfxPlayer = try? AVAudioPlayer(contentsOf: url)
        sfxPlayer?.prepareToPlay()
    }

    private func playSoundEffect() {
        guard let player = sfxPlayer else { return }
        if player.isPlaying { return }
        player.currentTime = 0
        player.play()
    }
}
