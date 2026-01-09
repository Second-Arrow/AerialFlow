import SwiftUI

struct SettingsFooterView: View {
    let statusLine: String
    let hasError: Bool

    var body: some View {
        Text("Current Aerial: \(statusLine)")
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(hasError ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
    }
}

