import SwiftUI

// MARK: - TransitionContainer
/// The heart of the app.  Maintains the rendering stack at every frame —
/// including during transitions.
///
/// **Rendering stack** (bottom → top, all processed by the full-screen
/// donut-distortion shader):
///
///   1. Permanent #000 black fill (always present).
///   2. Background album art (Screen 2): square cover image, scaled to fill
///      the screen height, centred.  Visibility controlled by a dithering
///      shader keyed to `1 - transitionProgress`.
///   3. Scroll overlay (Screen 2 only): the next album's cover art, dithered
///      in proportion to the user's finger position between ridges.
///   4. Donut content (Screen 1): square cover image inside a ring mask
///      (`DonutShape`), rotating at 33⅓ RPM.  Dithers out as
///      `transitionProgress` rises.  A semi-transparent black base ensures
///      a glass-like refraction effect on the dark ring during Screen 2.
///
/// The full-screen `donutDistort` shader applies ripple + edge refraction
/// in the ring area and passes everything else through unchanged.
///
/// `transitionProgress` (0 = Play, 1 = Selection) drives all interpolation.
/// Both directions animate with `.easeOut(duration: 0.42)`.

struct TransitionContainer: View {

    @ObservedObject var playbackVM: PlaybackViewModel
    @ObservedObject var selectionVM: SelectionViewModel
    @ObservedObject var tiltManager: TiltManager

    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Transition State

    @State private var transitionProgress: CGFloat = 0
    @State private var isTransitioning = false
    @State private var lastFrameDate: Date?

    @State private var wasBackgroundedOnScreen2 = false

    // MARK: - Interpolated Metrics

    private var outerRadius: CGFloat {
        DonutMetrics.outerRadius(at: transitionProgress)
    }
    private var innerRadius: CGFloat {
        DonutMetrics.innerRadius(at: transitionProgress)
    }
    private var outerDiameter: CGFloat { outerRadius * 2 }

    private var currentlyOnPlay: Bool { transitionProgress < 0.5 }

    private var distortionStrength: CGFloat {
        DonutMetrics.lerp(0.018, 0.028, transitionProgress)
    }

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let screenSize = geo.size

            TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: false)) { context in
                let time = Float(context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000.0))

                contentStack(screenSize: screenSize, center: center, time: time)
                    .overlay {
                        RingGestureOverlay(
                            outerRadius: outerRadius,
                            innerRadius: innerRadius,
                            onBegan: { angle in gestureBegan(angle: angle) },
                            onChanged: { angle in gestureChanged(angle: angle) },
                            onEnded: { velocity in gestureEnded(velocity: velocity) }
                        )
                        .position(center)
                    }
                    .onChange(of: context.date) { oldDate, newDate in
                        let dt: TimeInterval
                        if let last = lastFrameDate {
                            dt = min(newDate.timeIntervalSince(last), 1.0 / 30.0)
                        } else {
                            dt = 0
                        }
                        lastFrameDate = newDate

                        if transitionProgress < 0.01 {
                            playbackVM.updateRotation(dt: dt)
                        }
                    }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .statusBarHidden(true)
        .onChange(of: tiltManager.currentScreen) { _, newScreen in
            handleScreenTransition(to: newScreen)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active && transitionProgress > 0.5 {
                wasBackgroundedOnScreen2 = true
            }
        }
        #if targetEnvironment(simulator)
        .onTapGesture(count: 2) {
            tiltManager.manualToggle()
        }
        #endif
    }

    // MARK: - Content Stack (background + donut + glass shader)

    @ViewBuilder
    private func contentStack(
        screenSize: CGSize,
        center: CGPoint,
        time: Float
    ) -> some View {
        ZStack {
            // 1. Permanent black
            Color.black.ignoresSafeArea()

            // 2. Background album art (Screen 2)
            //    ditherProgress = 1 on Screen 1 (invisible) → 0 on Screen 2 (visible)
            BackgroundImageLayer(
                album: selectionVM.displayedAlbum,
                ditherProgress: Float(1.0 - transitionProgress),
                time: time,
                screenSize: screenSize
            )

            // 3. Scroll transition overlay (Screen 2 album wheel)
            if transitionProgress > 0.99,
               selectionVM.scrollDitherProgress > 0.01,
               let nextAlbum = selectionVM.nextScrollAlbum {
                BackgroundImageLayer(
                    album: nextAlbum,
                    ditherProgress: Float(1.0 - selectionVM.scrollDitherProgress),
                    time: time,
                    screenSize: screenSize
                )
            }

            // 4. Donut content (ring-masked album art for Screen 1)
            //    ditherProgress = 0 on Screen 1 (visible) → 1 on Screen 2 (transparent)
            DonutContentLayer(
                album: playbackVM.currentAlbum,
                rotation: .degrees(playbackVM.rotationDegrees),
                outerDiameter: outerDiameter,
                outerRadius: outerRadius,
                innerRadius: innerRadius,
                ditherProgress: Float(transitionProgress),
                time: time
            )
            .position(center)
        }
        .layerEffect(
            ShaderLibrary.donutDistort(
                .boundingRect,
                .float(outerRadius),
                .float(innerRadius),
                .float(distortionStrength)
            ),
            maxSampleOffset: CGSize(width: 50, height: 50)
        )
    }

    // MARK: - Gesture Routing

    private func gestureBegan(angle: Double) {
        guard !isTransitioning else { return }
        guard !playbackVM.blockInteraction else { return }
        if currentlyOnPlay {
            let isRightSide = abs(angle) < 90
            playbackVM.holdBegan(forward: isRightSide)
        } else {
            selectionVM.scrollBegan(at: angle)
        }
    }

    private func gestureChanged(angle: Double) {
        guard !isTransitioning else { return }
        guard !playbackVM.blockInteraction else { return }
        if !currentlyOnPlay {
            selectionVM.scrollChanged(to: angle)
        }
    }

    private func gestureEnded(velocity: Double) {
        guard !isTransitioning else { return }
        guard !playbackVM.blockInteraction else { return }
        if currentlyOnPlay {
            playbackVM.holdEnded()
        } else {
            selectionVM.scrollEnded(velocity: velocity)
        }
    }

    // MARK: - Screen Transition

    private func handleScreenTransition(to screen: AppScreen) {
        isTransitioning = true

        switch screen {
        case .play:
            // ── Selection → Play ──

            let keepCurrentAlbum = wasBackgroundedOnScreen2
            wasBackgroundedOnScreen2 = false

            let selectedAlbum = selectionVM.displayedAlbum
            let isSameAlbum = keepCurrentAlbum
                || selectedAlbum.id == playbackVM.currentAlbum.id

            if !isSameAlbum {
                playbackVM.prepareForTransitionToPlay(with: selectedAlbum)
            } else {
                playbackVM.syncRotationToAudio()
            }

            selectionVM.resetScrollProgress()

            withAnimation(.easeOut(duration: 0.42)) {
                transitionProgress = 0
            } completion: {
                isTransitioning = false
                if !isSameAlbum {
                    playbackVM.startPlaybackAfterTransition()
                } else {
                    playbackVM.resumePlayback()
                }
            }

        case .selection:
            // ── Play → Selection ──
            wasBackgroundedOnScreen2 = false
            playbackVM.cancelRewind()
            selectionVM.setupPool(excluding: playbackVM.currentAlbum)

            withAnimation(.easeOut(duration: 0.42)) {
                transitionProgress = 1
            } completion: {
                isTransitioning = false
            }
        }
    }
}
