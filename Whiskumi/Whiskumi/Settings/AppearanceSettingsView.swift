import SwiftUI

struct AppearanceSettingsView: View {
    let settings: AppSettings

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            Section("Size") {
                LabeledSlider(title: "Cat size", value: $settings.catScale, range: AppSettings.scaleRange,
                              low: "Small", high: "Large", valueText: "\(Int((settings.catScale * 100).rounded()))%")
                if settings.renderQuality == .pixelPerfect {
                    SettingCaption("Pixel Perfect rendering rounds the size to the nearest crisp step for your display.")
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
