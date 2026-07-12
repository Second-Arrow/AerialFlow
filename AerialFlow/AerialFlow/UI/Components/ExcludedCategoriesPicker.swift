import SwiftUI
import AppKit

private struct ExclusionPickerSearchBar: View {
    let searchText: Binding<String>
    let currentAssetID: String?
    let onScrollToCurrent: () -> Void

    var body: some View {
        SettingsRow("Search", labelWidth: 70) {
            HStack(spacing: 10) {
                TextField("Category, subcategory, or asset name", text: searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)

                Button("Current") {
                    guard let currentAssetID, !currentAssetID.isEmpty else { return }
                    withAnimation { searchText.wrappedValue = "" }
                    DispatchQueue.main.async {
                        onScrollToCurrent()
                    }
                }
                .disabled(currentAssetID == nil || currentAssetID?.isEmpty == true)
                .help("Scroll to the currently active Aerial.")
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            }
        }
    }
}

private struct ExclusionPickerRowView: View {
    let row: ExclusionRow
    let displayName: String
    let isExcluded: Bool
    let isCurrent: Bool
    /// Non-nil only for asset rows that can be applied immediately.
    let onApply: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: CGFloat(row.depth) * 14)
            Text(displayName)
                .strikethrough(isExcluded)
            Spacer()
            if let onApply, isHovered {
                Button("Apply current", action: onApply)
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .help("Apply this Aerial now and set it as the next one.")
            }
            if isCurrent {
                Text("current")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

struct ExcludedCategoriesPicker: View {
    let viewModel: ExclusionPickerViewModel

    /// Returns an apply closure only for asset rows when an apply handler is available.
    private func applyAction(for row: ExclusionRow) -> (() -> Void)? {
        guard let assetID = row.assetID, let onApplyAsset = viewModel.onApplyAsset else { return nil }
        return { onApplyAsset(assetID) }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 12) {
                ExclusionPickerSearchBar(
                    searchText: viewModel.searchText,
                    currentAssetID: viewModel.currentAssetID,
                    onScrollToCurrent: {
                        guard let currentAssetID = viewModel.currentAssetID, !currentAssetID.isEmpty else { return }
                        proxy.scrollTo("asset:\(currentAssetID)", anchor: .center)
                    }
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(viewModel.filteredRows, id: \.self) { row in
                            Toggle(isOn: viewModel.bindingForRow(row)) {
                                ExclusionPickerRowView(
                                    row: row,
                                    displayName: viewModel.displayName(for: row),
                                    isExcluded: viewModel.isRowExcluded(row),
                                    isCurrent: (row.assetID != nil && row.assetID == viewModel.currentAssetID),
                                    onApply: applyAction(for: row)
                                )
                            }
                            .disabled(viewModel.isRowDisabled(row))
                            .help("When enabled, this item will never be selected.")
                            .padding(.vertical, 6)
                            .id(viewModel.scrollID(for: row))

                            Divider()
                        }
                    }
                    .padding(.horizontal, 10)
                }
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}


