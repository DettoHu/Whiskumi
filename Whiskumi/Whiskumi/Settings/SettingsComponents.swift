import SwiftUI

/// Common chrome for every settings pane: a grouped form at a fixed width that sizes to its content.
struct SettingsPane<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            content
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// A secondary line of explanation under a control.
struct SettingCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// A labelled slider with words at each end instead of raw numbers.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let low: String
    let high: String
    var valueText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                if let valueText {
                    Text(valueText)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Slider(value: $value, in: range) {
                EmptyView()
            } minimumValueLabel: {
                Text(low).font(.caption).foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(high).font(.caption).foregroundStyle(.secondary)
            }
            .labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

/// Trait meter used for the personality read-out.
struct TraitMeter: View {
    let title: String
    let symbol: String
    let value: Double

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(title)
                .frame(width: 86, alignment: .leading)
            ProgressView(value: value.clamped(to: 0...1))
                .tint(.accentColor)
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}
