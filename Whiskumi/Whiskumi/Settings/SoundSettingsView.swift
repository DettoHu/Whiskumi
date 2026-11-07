import SwiftUI

struct SoundSettingsView: View {
    let settings: AppSettings
    let audio: AudioManager

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            if !audio.hasAnyAssets {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Whiskumi is quiet for now")
                                .font(.headline)
                            SettingCaption("No sound files are installed. Add audio named after an effect — meow, purr, eat, drink, sleep, play or interact (for example meow_1.m4a) — to Resources/Sounds and rebuild. These controls will come alive.")
                        }
                    } icon: {
                        Image(systemName: "speaker.slash")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Sound Effects") {
                Toggle("Play sound effects", isOn: $settings.soundEffects)
                LabeledSlider(title: "Volume", value: $settings.masterVolume, range: 0...1, low: "Quiet", high: "Loud",
                              valueText: "\(Int((settings.masterVolume * 100).rounded()))%")
                    .disabled(!settings.soundEffects)
            }
            .disabled(!audio.hasAnyAssets)

            Section("Sounds") {
                Toggle("Meowing", isOn: $settings.meowing)
                Toggle("Purring and interaction sounds", isOn: $settings.interactionSounds)
                if audio.hasAnyAssets {
                    SettingCaption("Installed: " + audio.availableEffects.map(\.title).joined(separator: ", "))
                }
            }
            .disabled(!audio.hasAnyAssets || !settings.soundEffects)
        }
    }
}
