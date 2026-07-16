import AVFoundation
import Foundation

// MARK: - VinylAudioEngine
/// Audio playback engine built on AVAudioPlayer.
///
/// AVAudioPlayer handles interruption lifecycle natively — `currentTime` is
/// always accurate (even after pause, seek, or interruption), and calling
/// `play()` after an interruption resumes from the exact position.  No manual
/// engine restart, buffer scheduling, or position tracking is needed.

final class VinylAudioEngine: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {

    // MARK: - Constants

    static let normalTurnsPerSecond: Double = 33.333 / 60.0
    static let degreesPerSecond: Double = normalTurnsPerSecond * 360.0

    // MARK: - Callbacks

    var onAlbumEnd: (() -> Void)?
    var onInterrupted: (() -> Void)?
    var onAutoResume: (() -> Void)?

    // MARK: - State

    private let lock = NSLock()
    private var player: AVAudioPlayer?
    private var _paused: Bool = false
    private var wasPlayingBeforeInterruption: Bool = false
    private var interruptionObserver: Any?

    var isPaused: Bool {
        lock.lock()
        let p = _paused
        lock.unlock()
        return p
    }

    // MARK: - Setup

    func setup() {
        guard interruptionObserver == nil else { return }

        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }
    }

    // MARK: - Album Loading

    func loadAlbum(_ album: Album) {
        player?.stop()
        player?.delegate = nil

        lock.lock()
        _paused = false
        lock.unlock()

        guard let url = album.audioURL else {
            print("[VinylAudioEngine] No audio for \(album.title)")
            player = nil
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            p.play()
        } catch {
            print("[VinylAudioEngine] Load failed: \(error)")
        }
    }

    // MARK: - Transport

    func pause() {
        player?.pause()
        lock.lock()
        _paused = true
        lock.unlock()
    }

    func resume() {
        lock.lock()
        let wasPaused = _paused
        _paused = false
        lock.unlock()

        guard wasPaused else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
    }

    func setRate(_ rate: Double) {
        // No-op — always 1× playback
    }

    func seek(toProgress progress: Double) {
        guard let player = player, player.duration > 0 else { return }
        player.currentTime = max(0, min(progress, 1.0)) * player.duration
    }

    func seekByTime(_ seconds: Double) {
        guard let player = player, player.duration > 0 else { return }
        player.currentTime = max(0, min(player.currentTime + seconds, player.duration))
    }

    // MARK: - Queries

    func getProgress() -> Double {
        guard let player = player, player.duration > 0 else { return 0 }
        return max(0, min(player.currentTime / player.duration, 1.0))
    }

    func getDuration() -> Double {
        player?.duration ?? 0
    }

    func getCurrentTime() -> Double {
        player?.currentTime ?? 0
    }

    // MARK: - Teardown

    func stop() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        player?.stop()
        player?.delegate = nil
        player = nil
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard flag else { return }
        onAlbumEnd?()
    }

    // MARK: - Interruption Handling

    private func handleInterruption(_ notification: Notification) {
        guard let info = notification.userInfo,
              let typeRaw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeRaw)
        else { return }

        switch type {
        case .began:
            lock.lock()
            wasPlayingBeforeInterruption = !_paused
            _paused = true
            lock.unlock()
            onInterrupted?()

        case .ended:
            guard wasPlayingBeforeInterruption else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            lock.lock()
            _paused = false
            lock.unlock()
            player?.play()
            onAutoResume?()

        @unknown default:
            break
        }
    }
}
