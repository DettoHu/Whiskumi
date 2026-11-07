import SwiftUI

/// The compact status popover: a live look at Whiskumi, needs at a glance, quick care actions.
struct MenuBarPopover: View {
    let cat: CatController
    let settings: AppSettings
    let actions: AppActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            NeedsGrid(needs: cat.needs)
            QuickActions(cat: cat)
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(colors: [Color(red: 0.36, green: 0.31, blue: 0.62), Color(red: 0.22, green: 0.19, blue: 0.42)],
                                       startPoint: .top, endPoint: .bottom)
                    )
                CatPreviewView(cat: cat)
                    .padding(8)
            }
            .frame(width: 92, height: 82)

            VStack(alignment: .leading, spacing: 4) {
                Text("Whiskumi")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Label(cat.mood.title, systemImage: cat.mood.symbolName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                Text(cat.isVisible ? cat.state.displayName : "Hidden")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack {
            Toggle(isOn: Binding(get: { cat.isVisible }, set: { _ in actions.toggleCat() })) {
                Text("Show Whiskumi")
                    .font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            Spacer()
            Button {
                actions.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings")
            Button {
                actions.quit()
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help("Quit Whiskumi")
        }
    }
}

private struct NeedsGrid: View {
    let needs: CatNeeds

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
            NeedRow(title: "Food", symbol: "fork.knife", value: needs.fullness, caption: hungerCaption, tint: .orange)
            NeedRow(title: "Water", symbol: "drop.fill", value: needs.hydration, caption: thirstCaption, tint: .teal)
            NeedRow(title: "Energy", symbol: "bolt.fill", value: needs.energy, caption: energyCaption, tint: .indigo)
            NeedRow(title: "Happiness", symbol: "heart.fill", value: needs.happiness, caption: happinessCaption, tint: .pink)
        }
    }

    private var hungerCaption: String {
        switch needs.fullness {
        case ..<0.2: "Hungry"
        case ..<0.45: "Peckish"
        case ..<0.8: "Satisfied"
        default: "Full"
        }
    }

    private var thirstCaption: String {
        switch needs.hydration {
        case ..<0.2: "Thirsty"
        case ..<0.5: "Could drink"
        default: "Refreshed"
        }
    }

    private var energyCaption: String {
        switch needs.energy {
        case ..<0.25: "Sleepy"
        case ..<0.6: "Relaxed"
        default: "Energetic"
        }
    }

    private var happinessCaption: String {
        switch needs.happiness {
        case ..<0.3: "A bit low"
        case ..<0.65: "Content"
        default: "Delighted"
        }
    }
}

private struct NeedRow: View {
    let title: String
    let symbol: String
    let value: Double
    let caption: String
    let tint: Color

    var body: some View {
        GridRow {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 12))
                .frame(width: 70, alignment: .leading)
            ProgressView(value: value.clamped(to: 0...1))
                .progressViewStyle(.linear)
                .tint(tint)
                .frame(maxWidth: .infinity)
            Text(caption)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(value * 100)) percent, \(caption)")
    }
}

private struct QuickActions: View {
    let cat: CatController
    @State private var choosingFood = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ActionButton(title: cat.isSleeping ? "Wake" : "Pet", symbol: cat.isSleeping ? "sun.max.fill" : "hand.raised.fill") {
                    cat.isSleeping ? cat.wakeUp() : cat.pet()
                }
                .disabled(!cat.isVisible)

                ActionButton(title: "Feed", symbol: "fork.knife", isActive: choosingFood) {
                    withAnimation(.snappy(duration: 0.2)) { choosingFood.toggle() }
                }
                .disabled(!cat.isVisible)

                ActionButton(title: cat.ballOut ? "Ball Away" : "Play", symbol: cat.ballOut ? "tray.and.arrow.down.fill" : "circle.circle.fill") {
                    cat.ballOut ? cat.putAwayBall() : cat.startPlaying()
                }
                .disabled(!cat.isVisible || !cat.play.canPlay)

                ActionButton(title: "Sleep", symbol: "moon.zzz.fill") {
                    cat.letSleep()
                }
                .disabled(!cat.isVisible || cat.isSleeping)
            }
            if choosingFood && cat.isVisible {
                HStack(spacing: 6) {
                    ForEach(FoodItem.allCases) { food in
                        FoodChip(title: food.title, symbol: food.symbolName) {
                            cat.feed(food)
                            choosingFood = false
                        }
                        .disabled(!cat.feeding.canEat(food))
                        .help(food.detail)
                    }
                    FoodChip(title: "Water", symbol: "drop.fill") {
                        cat.giveWater()
                        choosingFood = false
                    }
                    .disabled(!cat.feeding.canDrink)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct FoodChip: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovering && isEnabled ? 0.25 : 0.12))
            )
            .opacity(isEnabled ? 1 : 0.35)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ActionLabel(title: title, symbol: symbol, isActive: isActive)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

private struct ActionLabel: View {
    let title: String
    let symbol: String
    var isActive = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(height: 18)
            Text(title)
                .font(.system(size: 11, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.22) : Color.primary.opacity(hovering && isEnabled ? 0.1 : 0.05))
        )
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
