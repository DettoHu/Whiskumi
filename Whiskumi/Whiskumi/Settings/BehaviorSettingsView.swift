import SwiftUI

struct BehaviorSettingsView: View {
    let settings: AppSettings
    let cat: CatController

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            Section("Rhythm") {
                Picker("Temperament", selection: Binding(
                    get: { settings.matchingPreset },
                    set: { if let preset = $0 { settings.apply(preset) } }
                )) {
                    ForEach(BehaviorPreset.allCases) { preset in
                        Text(preset.title).tag(Optional(preset))
                    }
                    if settings.matchingPreset == nil {
                        Text("Custom").tag(BehaviorPreset?.none)
                    }
                }
                SettingCaption(settings.matchingPreset?.detail ?? "Your own mix of the settings below.")
                LabeledSlider(title: "Activity frequency", value: $settings.activityFrequency, range: 0...1, low: "Calm", high: "Lively")
                LabeledSlider(title: "Walking", value: $settings.walkingFrequency, range: 0...1, low: "Rarely", high: "Often")
                LabeledSlider(title: "Naps", value: $settings.sleepFrequency, range: 0...1, low: "Rarely", high: "Often")
            }

            Section("Independence") {
                Toggle(isOn: $settings.randomActivities) {
                    Text("Random activities")
                    SettingCaption("Grooming, stretching, exploring and other things cats do on their own.")
                }
                Toggle(isOn: $settings.cursorReactions) {
                    Text("React to the pointer")
                    SettingCaption("Whiskumi may look at, bat at or occasionally chase your pointer.")
                }
                Toggle(isOn: $settings.autonomousMovement) {
                    Text("Walk around on its own")
                }
            }

            Section {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                    GridRow {
                        TraitMeter(title: CatPersonality.Trait.playfulness.title, symbol: CatPersonality.Trait.playfulness.symbolName, value: cat.personality.playfulness)
                        TraitMeter(title: CatPersonality.Trait.laziness.title, symbol: CatPersonality.Trait.laziness.symbolName, value: cat.personality.laziness)
                    }
                    GridRow {
                        TraitMeter(title: CatPersonality.Trait.curiosity.title, symbol: CatPersonality.Trait.curiosity.symbolName, value: cat.personality.curiosity)
                        TraitMeter(title: CatPersonality.Trait.affection.title, symbol: CatPersonality.Trait.affection.symbolName, value: cat.personality.affection)
                    }
                }
                SettingCaption("Grows slowly with your time together: play, petting, naps and exploring each leave their mark.")
            } header: {
                HStack {
                    Text("Personality")
                    Spacer()
                    Text(cat.personality.summary)
                        .foregroundStyle(.secondary)
                        .fontWeight(.regular)
                }
            }
        }
    }
}
