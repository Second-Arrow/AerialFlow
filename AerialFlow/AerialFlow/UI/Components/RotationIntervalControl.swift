import SwiftUI

/// Combined rotation interval control:
/// - Slider for the common range (1...240 minutes)
/// - Manual input for custom values outside the slider range (e.g. > 4h)
struct RotationIntervalControl: View {
    @Binding var minutes: Int
    let minMinutes: Int
    let sliderMaxMinutes: Int

    @State private var manualMinutesText: String = ""
    @FocusState private var isManualFieldFocused: Bool

    init(
        minutes: Binding<Int>,
        minMinutes: Int = 1,
        sliderMaxMinutes: Int = Constants.maximumRotationIntervalMinutes
    ) {
        self._minutes = minutes
        self.minMinutes = minMinutes
        self.sliderMaxMinutes = sliderMaxMinutes
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Slider(value: sliderBinding, in: Double(minMinutes)...Double(sliderMaxMinutes), step: 1)
                .accessibilityLabel("Interval")
                .controlSize(.large)
                .padding(.vertical, 4)
                .frame(maxWidth: 260)

            TextField("", text: $manualMinutesText)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
                .focused($isManualFieldFocused)
                .onSubmit { commitManualInput() }
                .onChange(of: isManualFieldFocused) { _, focused in
                    if !focused { commitManualInput() }
                }

            Text("min")
                .foregroundStyle(.secondary)

            if minutes > sliderMaxMinutes {
                Text("(Custom)")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            syncManualTextFromMinutes()
        }
        .onChange(of: minutes) { _, _ in
            guard !isManualFieldFocused else { return }
            syncManualTextFromMinutes()
        }
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                let clamped = min(sliderMaxMinutes, max(minMinutes, minutes))
                return Double(clamped)
            },
            set: { newValue in
                let rounded = Int(newValue.rounded())
                minutes = min(sliderMaxMinutes, max(minMinutes, rounded))
            }
        )
    }

    private func syncManualTextFromMinutes() {
        manualMinutesText = "\(minutes)"
    }

    private func commitManualInput() {
        let trimmed = manualMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            syncManualTextFromMinutes()
            return
        }

        guard let parsed = Int(trimmed) else {
            syncManualTextFromMinutes()
            return
        }

        minutes = max(minMinutes, parsed)
        syncManualTextFromMinutes()
    }
}


