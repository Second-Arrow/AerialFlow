import SwiftUI

/// A reusable row component for settings views with a label and content area.
struct SettingsRow<Content: View>: View {
    let label: String
    private let labelWidth: CGFloat
    @ViewBuilder let content: () -> Content

    init(_ label: String, labelWidth: CGFloat = 140, @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.labelWidth = labelWidth
        self.content = content
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .frame(width: labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

