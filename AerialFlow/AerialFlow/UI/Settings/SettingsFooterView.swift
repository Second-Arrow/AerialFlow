import SwiftUI

struct SettingsFooterView: View {
    let statusLine: String
    let hasError: Bool
    let isBusy: Bool
    let onNextAerial: () async -> Void

    var body: some View {
        HStack {
            Button("Next Aerial") {
                Task { await onNextAerial() }
            }
            .disabled(isBusy)

            Spacer()

            Text("Current Aerial: \(statusLine)")
                .font(.footnote)
                .foregroundStyle(hasError ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
        }
    }
}

