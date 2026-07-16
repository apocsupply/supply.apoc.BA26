import MediaPlayer
import UIKit

// MARK: - NowPlayingManager
/// Keeps the Lock Screen / Control Centre metadata in sync with the current album.
///
/// **Playback controls**:
///   - Play / Pause / Toggle are enabled and routed via callbacks.
///   - All other commands (next, previous, seek, skip) are explicitly disabled
///     so that the scrub bar / seek slider never appears.
///
/// **Artwork**: Uses the square cover image ("{Title}.jpg") from each
/// album folder for rich Lock Screen display.
///
/// **Threading**: Intentionally *not* `@MainActor`-isolated.
/// `MPNowPlayingInfoCenter` & `MPRemoteCommandCenter` have internal
/// dispatch-queue assertions that conflict with Swift concurrency's
/// `@MainActor` hop (iOS 26 beta).  All public methods must be called from
/// the GCD main queue.

final class NowPlayingManager: @unchecked Sendable {

    static let shared = NowPlayingManager()
    private let imageCache = AlbumImageCache.shared
    private var isConfigured = false

    // MARK: - Remote Command Callbacks

    var onRemotePlay: (() -> Void)?
    var onRemotePause: (() -> Void)?
    var onRemoteToggle: (() -> Void)?

    private init() {}

    // MARK: - Configuration

    func configure() {
        guard !isConfigured else { return }
        isConfigured = true

        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { [weak self] _ in
            Self.setRateImmediate(1.0)
            self?.onRemotePlay?()
            return .success
        }

        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { [weak self] _ in
            Self.setRateImmediate(0.0)
            self?.onRemotePause?()
            return .success
        }

        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { [weak self] _ in
            let current = MPNowPlayingInfoCenter.default().nowPlayingInfo?[
                MPNowPlayingInfoPropertyPlaybackRate
            ] as? Double ?? 1.0
            Self.setRateImmediate(current > 0 ? 0.0 : 1.0)
            self?.onRemoteToggle?()
            return .success
        }

        cc.nextTrackCommand.isEnabled = false
        cc.previousTrackCommand.isEnabled = false
        cc.changePlaybackPositionCommand.isEnabled = false
        cc.skipForwardCommand.isEnabled = false
        cc.skipBackwardCommand.isEnabled = false
    }

    // MARK: - Immediate Rate

    private static func setRateImmediate(_ rate: Double) {
        let center = MPNowPlayingInfoCenter.default()
        center.playbackState = rate > 0 ? .playing : .paused
        guard var info = center.nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        center.nowPlayingInfo = info
    }

    // MARK: - Update

    /// Updates Now Playing metadata.
    /// - Parameters:
    ///   - rate: The actual playback rate (1.0 normal, 0.0 paused, >1 momentum).
    ///           The Lock Screen uses this to advance its elapsed-time counter
    ///           between updates, so it must match the real engine speed.
    func update(
        album: Album,
        elapsed: TimeInterval,
        duration: TimeInterval,
        rate: Double
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: album.title,
            MPMediaItemPropertyArtist: album.artist,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: rate,
        ]

        if let image = imageCache.coverImage(for: album) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            info[MPMediaItemPropertyArtwork] = artwork
        }

        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = info
        center.playbackState = rate > 0 ? .playing : .paused
    }
}
