import SwiftUI

struct SystemAccessStatusView: View {
    let report: SystemAccessReport?
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("System Access")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    onRefresh()
                }
                .font(.footnote)
            }

            if let report {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(report.items) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Label(item.title, systemImage: iconName(for: item.state))
                                .labelStyle(.titleAndIcon)
                                .foregroundStyle(color(for: item.state))
                            Text(item.detail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
            } else {
                Text("No status available yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconName(for state: SystemAccessItem.State) -> String {
        switch state {
        case .ok:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private func color(for state: SystemAccessItem.State) -> Color {
        switch state {
        case .ok:
            return .green
        case .warning:
            return .yellow
        case .error:
            return .red
        }
    }
}


