import SwiftUI

// MARK: - RootView
/// Root content view.  Creates the three main state objects and hands them
/// to `TransitionContainer`.
///
/// Observes `scenePhase` to:
///   - Start/stop CoreMotion (gyroscope scope fix).
///   - Auto-resume playback when returning to foreground if the user paused
///     via Lock Screen / Control Centre.

struct RootView: View {

    @StateObject private var playbackVM: PlaybackViewModel
    @StateObject private var selectionVM = SelectionViewModel()
    @StateObject private var tiltManager = TiltManager()

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Init

    init() {
        let start = Album.allAlbums.randomElement()
            ?? Album(id: 1, rank: 1, title: "Unknown", artist: "Unknown")
        _playbackVM = StateObject(wrappedValue: PlaybackViewModel(album: start))
    }

    // MARK: - Body

    var body: some View {
        TransitionContainer(
            playbackVM: playbackVM,
            selectionVM: selectionVM,
            tiltManager: tiltManager
        )
        .onAppear {
            playbackVM.setup()
            tiltManager.startIfActive()
        }
        .onDisappear {
            tiltManager.stopUpdates()
            playbackVM.tearDown()
            selectionVM.tearDown()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                tiltManager.startIfActive()
                playbackVM.handleForegroundResume()
            case .inactive, .background:
                tiltManager.stopUpdates()
            @unknown default:
                break
            }
        }
    }
}
