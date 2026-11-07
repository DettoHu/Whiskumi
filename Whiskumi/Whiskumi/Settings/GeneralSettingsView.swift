import SwiftUI

struct GeneralSettingsView: View {
    let dependencies: SettingsDependencies
    @State private var confirmingReset = false

    private var settings: AppSettings { dependencies.settings }
    private var loginItem: LaunchAtLoginManager { dependencies.loginItem }
    private var cat: CatController { dependencies.cat }

    var body: some View {
        @Bindable var settings = settings
        SettingsPane {
            Section("Startup") {
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.setEnabled($0) }))
                if loginItem.requiresApproval {
                    HStack {
                        SettingCaption("macOS needs your approval in Login Items before Whiskumi can start automatically.")
                        Spacer()
                        Button("Open Login Items…") { loginItem.openSystemSettings() }
                    }
                }
                if let error = loginItem.lastError {
                    SettingCaption(error)
                }
                Toggle(isOn: $settings.showCatOnLaunch) {
                    Text("Start Whiskumi automatically")
                    SettingCaption("Show the cat on your desktop as soon as the app opens.")
                }
                Toggle(isOn: $settings.showMenuBarIcon) {
                    Text("Show menu bar icon")
                    SettingCaption("Without it, right-click Whiskumi or open the app again to reach these settings.")
                }
            }

            Section("Window") {
                Picker("Window level", selection: $settings.windowLayer) {
                    ForEach(WindowLayer.allCases) { layer in
                        Text(layer.title).tag(layer)
                    }
                }
                SettingCaption(settings.windowLayer.detail)
                Toggle("Show Whiskumi on all desktops", isOn: $settings.showOnAllDesktops)
            }

            Section("Position") {
                Toggle("Restore previous position at launch", isOn: $settings.restorePosition)
                HStack {
                    Text("Bring Whiskumi back to the default spot")
                    Spacer()
                    Button("Reset Position") { cat.resetPosition() }
                }
            }

            Section {
                HStack(spacing: 0) {
                    StatTile(value: cat.stats.pets, label: "Pets")
                    StatTile(value: cat.stats.meals + cat.stats.drinks, label: "Meals")
                    StatTile(value: cat.stats.playSessions, label: "Games")
                    StatTile(value: cat.stats.naps, label: "Naps")
                }
                HStack {
                    SettingCaption("Together since \(cat.stats.adoptedOn.formatted(date: .long, time: .omitted))")
                    Spacer()
                    Button("Adopt a New Kitten…", role: .destructive) { confirmingReset = true }
                }
            } header: {
                Text("Whiskumi")
            }
        }
        .confirmationDialog("Start over with a new kitten?", isPresented: $confirmingReset) {
            Button("Adopt a New Kitten", role: .destructive) { cat.resetCat() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Whiskumi's needs, personality and history will be reset. Your settings are kept.")
        }
    }
}

private struct StatTile: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
