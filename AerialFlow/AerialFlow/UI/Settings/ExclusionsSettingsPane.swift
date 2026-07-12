import SwiftUI

struct ExclusionsSettingsPane: View {
    @EnvironmentObject private var appState: AppState

    let catalogSnapshot: AerialCatalog.Snapshot?
    let catalogErrorMessage: String?
    let categoryDisplayNameByID: [String: String]
    let assetDisplayNameByID: [String: String]
    let currentAssetID: String?
    @Binding var exclusionsSearchText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Exclude categories and individual Aerials from selection and scheduled rotation.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let catalogErrorMessage {
                Text(catalogErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }

            if let snapshot = catalogSnapshot {
                // Hide non-landscape Aerials (e.g. the "Mac" wallpapers) here too, matching selection.
                let filter = NonLandscapeAerialFilter()
                let visibleCategories = filter.filter(categories: snapshot.categories)
                let visibleAssets = filter.filter(assets: snapshot.assets, categories: snapshot.categories)
                let mainCategories = AerialCategory.uniqueMainCategories(visibleCategories)
                let rows = ExclusionRow.rows(fromMainCategories: mainCategories, assets: visibleAssets)

                let viewModel = ExclusionPickerViewModel(
                    rows: rows,
                    categoryDisplayNameByID: categoryDisplayNameByID,
                    assetDisplayNameByID: assetDisplayNameByID,
                    excludedCategoryIDs: Binding(
                        get: { appState.settings.excludedCategoryIDs },
                        set: { appState.settings.excludedCategoryIDs = $0 }
                    ),
                    excludedSubcategoryIDs: Binding(
                        get: { appState.settings.excludedSubcategoryIDs },
                        set: { appState.settings.excludedSubcategoryIDs = $0 }
                    ),
                    excludedAssetIDs: Binding(
                        get: { appState.settings.excludedAssetIDs },
                        set: { appState.settings.excludedAssetIDs = $0 }
                    ),
                    searchText: $exclusionsSearchText,
                    currentAssetID: currentAssetID,
                    onApplyAsset: { assetID in
                        Task { await appState.applyAsset(id: assetID) }
                    }
                )

                ExcludedCategoriesPicker(viewModel: viewModel)
            } else {
                Text("Loading Aerial catalog…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 560, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
    }
}

