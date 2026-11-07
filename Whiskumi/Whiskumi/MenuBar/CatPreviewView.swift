import SwiftUI

/// Mirrors whatever Whiskumi is doing on the desktop right now, drawn pixel-sharp.
struct CatPreviewView: View {
    let cat: CatController

    var body: some View {
        ZStack {
            if let frame = cat.preview {
                Image(decorative: frame.image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(x: frame.flipped ? -1 : 1, y: 1)
                    .opacity(cat.isVisible ? 1 : 0.55)
                    .accessibilityLabel("Whiskumi is \(cat.state.displayName.lowercased())")
            }
        }
    }
}
