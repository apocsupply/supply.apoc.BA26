import SwiftUI

// MARK: - BackgroundImageLayer
/// Renders a single album's square cover art scaled to fill the screen
/// height, centred horizontally with sides cropped.
///
/// A dithering shader controls visibility: at ditherProgress = 0 the image is
/// fully visible; at ditherProgress = 1 it is fully transparent (black behind).

struct BackgroundImageLayer: View {

    let album: Album
    let ditherProgress: Float
    let time: Float
    let screenSize: CGSize

    private let imageCache = AlbumImageCache.shared

    var body: some View {
        if let image = imageCache.coverImage(for: album) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: screenSize.width, height: screenSize.height)
                .clipped()
                .layerEffect(
                    ShaderLibrary.ditherTransition(
                        .boundingRect,
                        .float(ditherProgress),
                        .float(time)
                    ),
                    maxSampleOffset: .zero
                )
        }
    }
}
