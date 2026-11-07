import SwiftUI

/// Mirrors whatever Whiskumi is doing on the desktop right now.
///
/// Drawn at exactly one device pixel per art pixel on Retina with nearest-neighbour sampling,
/// feet pinned to the same spot, so every pose keeps the same scale and no pixel is resampled.
/// (On a 1× screen it is drawn at half size, where smooth downscaling is the right filter.)
struct CatPreviewView: View {
    let cat: CatController
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { proxy in
            if let frame = cat.preview {
                let scale = max(displayScale, 1)
                let pointsPerPixel: CGFloat = scale >= 2 ? 1 / scale : 0.5
                let width = CGFloat(frame.image.width) * pointsPerPixel
                let height = CGFloat(frame.image.height) * pointsPerPixel
                let anchorX = (frame.flipped ? CGFloat(frame.image.width) - frame.anchor.x : frame.anchor.x) * pointsPerPixel
                let footX = (proxy.size.width / 2 * scale).rounded() / scale
                let footY = (proxy.size.height - 6).rounded()
                Image(decorative: frame.image, scale: 1)
                    .interpolation(scale >= 2 ? .none : .medium)
                    .antialiased(false)
                    .resizable()
                    .frame(width: width, height: height)
                    .scaleEffect(x: frame.flipped ? -1 : 1, y: 1)
                    .offset(x: footX - anchorX, y: footY - frame.anchor.y * pointsPerPixel)
                    .opacity(cat.isVisible ? 1 : 0.55)
                    .accessibilityLabel("Whiskumi is \(cat.state.displayName.lowercased())")
            }
        }
        .clipped()
    }
}
