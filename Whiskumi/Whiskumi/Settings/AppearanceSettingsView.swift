import AppKit
import SwiftUI

struct AppearanceSettingsView: View {
    let settings: AppSettings
    /// Height of the sitting cat in art pixels.
    let standingHeight: CGFloat

    private var backingScale: CGFloat { NSScreen.main?.backingScaleFactor ?? 2 }

    /// The size actually used on screen, after Pixel Perfect snapping.
    private var effectivePointsPerPixel: CGFloat {
        PixelScale.pointsPerPixel(size: settings.catSize, quality: settings.renderQuality, backingScale: backingScale)
    }

    private var sizeDescription: String {
        let percent = Int((effectivePointsPerPixel / PixelScale.basePointsPerPixel * 100).rounded())
        let points = Int((standingHeight * effectivePointsPerPixel).rounded())
        return "\(percent)% · \(points) pt tall"
    }

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            Section("Size") {
                LabeledSlider(title: "Cat size", value: $settings.catSize, range: AppSettings.sizeRange,
                              low: "Small", high: "Large", valueText: sizeDescription)
                HStack {
                    SettingCaption(settings.renderQuality == .pixelPerfect
                                   ? "Pixel Perfect moves in crisp steps so every art pixel lands on whole screen pixels."
                                   : "Sizes between the crisp steps make some art pixels one screen pixel wider than others.")
                    Spacer()
                    Button("Default Size") { settings.catSize = 1 }
                        .disabled(abs(settings.catSize - 1) < 0.001)
                }
            }

            Section("Animation") {
                LabeledSlider(title: "Animation speed", value: $settings.animationSpeed, range: AppSettings.speedRange,
                              low: "Unhurried", high: "Brisk", valueText: String(format: "%.1f×", settings.animationSpeed))
            }

            Section("Rendering") {
                Picker("Pixel art quality", selection: $settings.renderQuality) {
                    ForEach(RenderQuality.allCases) { quality in
                        Text(quality.title).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                SettingCaption(settings.renderQuality.detail)
            }

            Section("Effects") {
                Toggle(isOn: $settings.visualEffects) {
                    Text("Show little effects")
                    SettingCaption("Hearts, sleepy Zs, question marks and other flourishes from the artwork.")
                }
                Toggle(isOn: $settings.groundShadow) {
                    Text("Shadow while jumping or carried")
                }
            }

            Section("Default Position") {
                Picker("Where Whiskumi first appears", selection: $settings.defaultPosition) {
                    ForEach(DefaultPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
            }
        }
    }
}
