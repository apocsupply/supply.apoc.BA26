import SwiftUI

// MARK: - DonutContentLayer
/// Renders the donut ring content for both screens.
///
/// On Screen 1 (ditherProgress ≈ 0): album cover art fills the ring,
///   rotating at 33⅓ RPM.
/// On Screen 2 (ditherProgress ≈ 1): the art is fully dithered away,
///   revealing the semi-transparent black base.  The full-screen glass shader
///   refracts the background through this dark ring.
///
/// A `DonutShape` mask clips the content to the ring area so the hole and
/// exterior remain transparent (the background shows through them).

struct DonutContentLayer: View {

    let album: Album
    let rotation: Angle
    let outerDiameter: CGFloat
    let outerRadius: CGFloat
    let innerRadius: CGFloat
    let ditherProgress: Float
    let time: Float

    private let imageCache = AlbumImageCache.shared

    var body: some View {
        ZStack {
            Color.black

            if let image = imageCache.coverImage(for: album) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: outerDiameter, height: outerDiameter)
                    .rotationEffect(rotation)
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
        .frame(width: outerDiameter, height: outerDiameter)
        .mask {
            DonutShape(outerRadius: outerRadius, innerRadius: innerRadius)
        }
    }
}
