import SwiftUI
import AppKit

struct CategoryRow: Hashable, Sendable {
    let category: AerialCategory
    let depth: Int
    let rootMainCategoryID: String

    var id: String { category.id }
    var isMainCategory: Bool { depth == 0 }

    static func rows(fromMainCategories categories: [AerialCategory]) -> [CategoryRow] {
        var out: [CategoryRow] = []
        out.reserveCapacity(categories.count)

        for main in categories {
            guard !main.id.isEmpty else { continue }
            out.append(CategoryRow(category: main, depth: 0, rootMainCategoryID: main.id))
            appendSubcategories(of: main, depth: 1, rootMainCategoryID: main.id, into: &out)
        }

        return out
    }

    private static func appendSubcategories(
        of category: AerialCategory,
        depth: Int,
        rootMainCategoryID: String,
        into out: inout [CategoryRow]
    ) {
        for sub in category.subcategories.sorted(by: AerialCategory.sortByPreferredOrderThenID) {
            guard !sub.id.isEmpty else { continue }
            out.append(CategoryRow(category: sub, depth: depth, rootMainCategoryID: rootMainCategoryID))
            appendSubcategories(of: sub, depth: depth + 1, rootMainCategoryID: rootMainCategoryID, into: &out)
        }
    }
}

struct ExcludedCategoriesPicker: View {
    let rows: [CategoryRow]
    let categoryDisplayNameByID: [String: String]
    @Binding var excludedCategoryIDs: Set<String>
    @Binding var excludedSubcategoryIDs: Set<String>
    @Binding var searchText: String
    let currentSubcategoryIDs: Set<String>

    var body: some View {
        SettingsRow("Search") {
            TextField("Category name", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }

        VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredRows, id: \.self) { row in
                Toggle(isOn: bindingForRow(row)) {
                    HStack(spacing: 8) {
                        Color.clear
                            .frame(width: CGFloat(row.depth) * 14)
                        Text(displayName(for: row.category))
                            .strikethrough(isRowExcluded(row))
                        Spacer()
                        if row.depth > 0 && currentSubcategoryIDs.contains(row.category.id) {
                            Text("current")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(nsColor: .quaternaryLabelColor).opacity(0.3))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .disabled(row.depth > 0 && excludedCategoryIDs.contains(row.rootMainCategoryID))
                .help("When enabled, this category will never be selected.")
                .padding(.vertical, 6)

                Divider()
            }
        }
        .padding(.horizontal, 10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var filteredRows: [CategoryRow] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return rows
        }

        let lower = trimmed.lowercased()
        return rows
            .filter { row in
                let name = displayName(for: row.category).lowercased()
                return name.contains(lower) || row.category.id.lowercased().contains(lower)
            }
    }

    private func displayName(for category: AerialCategory) -> String {
        categoryDisplayNameByID[category.id] ?? category.id
    }

    private func isRowExcluded(_ row: CategoryRow) -> Bool {
        if row.isMainCategory {
            return excludedCategoryIDs.contains(row.id)
        }
        return excludedSubcategoryIDs.contains(row.id) || excludedCategoryIDs.contains(row.rootMainCategoryID)
    }

    private func bindingForRow(_ row: CategoryRow) -> Binding<Bool> {
        if row.isMainCategory {
            return Binding(
                get: { excludedCategoryIDs.contains(row.id) },
                set: { isExcluded in
                    if isExcluded {
                        excludedCategoryIDs.insert(row.id)
                    } else {
                        excludedCategoryIDs.remove(row.id)
                    }
                }
            )
        }

        return Binding(
            get: { excludedSubcategoryIDs.contains(row.id) },
            set: { isExcluded in
                if isExcluded {
                    excludedSubcategoryIDs.insert(row.id)
                } else {
                    excludedSubcategoryIDs.remove(row.id)
                }
            }
        )
    }
}


