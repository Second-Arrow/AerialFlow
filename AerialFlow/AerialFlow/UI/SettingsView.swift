import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var categorySearchText: String = ""
    @State private var catalogSnapshot: AerialCatalog.Snapshot?
    @State private var catalogErrorMessage: String?
    @State private var categoryDisplayNameByID: [String: String] = [:]
    @State private var isPickingIndexPlist: Bool = false
    @State private var currentSubcategoryIDs: Set<String> = []
    @State private var isShowingTipJar: Bool = false

    private let tipProductIDs: [String] = [
        "com.secondarrow.AerialFlow.tip.small",
        "com.secondarrow.AerialFlow.tip.coffee",
        "com.secondarrow.AerialFlow.tip.lunch",
        "com.secondarrow.AerialFlow.tip.bigThanks"
    ]

    var body: some View {
        VStack(spacing: 12) {
            TabView(selection: $appState.selectedSettingsTab) {
                pane(generalTab)
                    .tabItem { Label("General", systemImage: "gearshape") }
                    .tag(AppState.SettingsTab.general)

                pane(rotationTab)
                    .tabItem { Label("Rotation", systemImage: "arrow.triangle.2.circlepath") }
                    .tag(AppState.SettingsTab.rotation)

                pane(categoriesTab)
                    .tabItem { Label("Categories", systemImage: "square.grid.2x2") }
                    .tag(AppState.SettingsTab.categories)

                pane(hotkeysTab)
                    .tabItem { Label("Hotkeys", systemImage: "keyboard") }
                    .tag(AppState.SettingsTab.hotkeys)

                pane(DiagnosticsView())
                    .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
                    .tag(AppState.SettingsTab.diagnostics)

                pane(AboutView())
                    .tabItem { Label("About", systemImage: "info.circle") }
                    .tag(AppState.SettingsTab.about)
            }
            // Prefer classic toolbar-style preferences tabs.
            .tabViewStyle(.automatic)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Text("Current Aerial: \(appState.statusLine)")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(
                        appState.lastErrorMessage == nil
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(Color.red)
                    )

                Button("Support Development…") {
                    isShowingTipJar = true
                }
                .font(.footnote)
            }
        }
        .padding(20)
        .frame(width: 640, height: 560)
        .sheet(isPresented: $isShowingTipJar) {
            TipJarView(purchaser: appState.tipJarPurchaser, productIDs: tipProductIDs)
        }
        .task {
            guard catalogSnapshot == nil, catalogErrorMessage == nil else { return }
            do {
                let snapshot = try await appState.loadCatalogSnapshot()
                catalogSnapshot = snapshot
                let mainCategories = AerialCategory.uniqueMainCategories(snapshot.categories)
                let rows = CategoryRow.rows(fromMainCategories: mainCategories)
                categoryDisplayNameByID = await appState.categoryDisplayNamesByID(categories: rows.map(\.category))
            } catch {
                catalogErrorMessage = error.localizedDescription
            }
        }
        .task {
            currentSubcategoryIDs = await appState.currentSubcategoryIDs()
        }
        .onChange(of: appState.statusLine) { _, _ in
            Task {
                currentSubcategoryIDs = await appState.currentSubcategoryIDs()
            }
        }
        .fileImporter(
            isPresented: $isPickingIndexPlist,
            allowedContentTypes: [.propertyList],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                appState.settings.indexPlistURL = url
            case .failure(let error):
                // Error handling for Index.plist selection
                _ = error
            }
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            let launchAtLoginBinding = Binding(
                get: { appState.settings.launchAtLogin },
                set: { appState.setLaunchAtLoginEnabled($0) }
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("Startup")
                    .font(.headline)

                Toggle("Launch at login", isOn: launchAtLoginBinding)
                    .help("Launch AerialFlow automatically after you sign in. macOS may require approval in Login Items.")

                if let message = appState.launchAtLoginErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                } else {
                    Text("Start AerialFlow automatically when you sign in.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Run Conditions")
                    .font(.headline)

                Toggle(
                    "Don’t run when display is off",
                    isOn: Binding(
                        get: { appState.settings.skipWhenDisplayOff },
                        set: { appState.settings.skipWhenDisplayOff = $0 }
                    )
                )
                .help("Skips scheduled rotation when your displays are asleep.")

                Toggle(
                    "Don’t run while screensaver active",
                    isOn: Binding(
                        get: { appState.settings.skipWhenScreensaverActive },
                        set: { appState.settings.skipWhenScreensaverActive = $0 }
                    )
                )
                .help("Skips scheduled rotation while the screensaver is running.")

                Toggle(
                    "Don’t run at login window",
                    isOn: Binding(
                        get: { appState.settings.skipAtLoginWindow },
                        set: { appState.settings.skipAtLoginWindow = $0 }
                    )
                )
                .help("Skips scheduled rotation when macOS is showing the login window.")

                Text("These conditions apply to scheduled background rotation. Manual actions (like \"Next Aerial\") can still be used.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            let timeoutMinutesBinding = Binding<Int>(
                get: { max(1, Int(appState.settings.downloadTimeout) / 60) },
                set: { appState.settings.downloadTimeout = TimeInterval(max(60, $0 * 60)) }
            )

            let backupRetentionBinding = Binding<Int>(
                get: { appState.settings.backupRetentionCount },
                set: { appState.settings.backupRetentionCount = $0 }
            )

            VStack(alignment: .leading, spacing: 10) {
                DisclosureGroup("Advanced") {
                    SettingsRow("Download timeout") {
                        Stepper(value: timeoutMinutesBinding, in: 1...120, step: 1) {
                            Text("\(timeoutMinutesBinding.wrappedValue) min")
                        }
                    }
                    .help("How long AerialFlow will wait for a download to complete before failing.")

                    SettingsRow("Index.plist") {
                        Text(appState.settings.indexPlistURL.path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                    .help("The Index.plist file AerialFlow edits to apply the next Aerial. The default is the system wallpaper store.")

                    SettingsRow("Index.plist location") {
                        HStack(spacing: 8) {
                            Button("Choose…") {
                                isPickingIndexPlist = true
                            }
                            .help("Select a custom Index.plist location. Most users should keep the default.")
                            Button("Reset") {
                                appState.settings.indexPlistURL = WallpaperStoreEditor.defaultIndexPlistURL
                            }
                            .help("Restore the default system wallpaper store location.")
                        }
                    }

                    SettingsRow("Backups to keep") {
                        Stepper(value: backupRetentionBinding, in: 1...Constants.maximumBackupRetentionCount, step: 1) {
                            Text("\(backupRetentionBinding.wrappedValue)")
                        }
                    }
                    .help("How many Index.plist backups AerialFlow keeps next to the original. Older backups are pruned automatically.")
                }
            }
        }
    }

    private var rotationTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            let rotationEnabledBinding = Binding(
                get: { appState.settings.isRotationEnabled },
                set: { appState.settings.isRotationEnabled = $0 }
            )

            let minutesBinding = Binding<Int>(
                get: { max(1, appState.settings.rotationIntervalSeconds / 60) },
                set: { appState.settings.rotationIntervalSeconds = max(60, $0 * 60) }
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Rotation")
                    .font(.headline)

                Toggle("Enable scheduled rotation", isOn: rotationEnabledBinding)
                    .help("Automatically switch to the next Aerial on a schedule.")

                Toggle(
                    "Random mode",
                    isOn: Binding(
                        get: { appState.settings.randomMode },
                        set: { appState.settings.randomMode = $0 }
                    )
                )
                .help("Pick a random eligible Aerial instead of cycling in order. Some repeats may occur over time.")

                SettingsRow("Interval") {
                    Stepper(value: minutesBinding, in: 1...Constants.maximumRotationIntervalMinutes, step: 1) {
                        Text("\(minutesBinding.wrappedValue) min")
                    }
                }
                .disabled(!appState.settings.isRotationEnabled)
                .help("How often AerialFlow schedules a rotation. Minimum 1 minute, maximum 4 hours.")

                if appState.settings.isRotationEnabled {
                    Text("AerialFlow runs quietly in the background and advances your wallpaper on the chosen interval.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Turn on scheduled rotation to adjust the interval.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var categoriesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Excluded Categories")
                .font(.headline)

            if let catalogErrorMessage {
                Text(catalogErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
            }

            if let snapshot = catalogSnapshot {
                let mainCategories = AerialCategory.uniqueMainCategories(snapshot.categories)
                let rows = CategoryRow.rows(fromMainCategories: mainCategories)
                ExcludedCategoriesPicker(
                    rows: rows,
                    categoryDisplayNameByID: categoryDisplayNameByID,
                    excludedCategoryIDs: Binding(
                        get: { appState.settings.excludedCategoryIDs },
                        set: { appState.settings.excludedCategoryIDs = $0 }
                    ),
                    excludedSubcategoryIDs: Binding(
                        get: { appState.settings.excludedSubcategoryIDs },
                        set: { appState.settings.excludedSubcategoryIDs = $0 }
                    ),
                    searchText: $categorySearchText,
                    currentSubcategoryIDs: currentSubcategoryIDs
                )
            } else {
                Text("Loading categories…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Checked categories and subcategories are excluded from selection and rotation.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var hotkeysTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Hotkeys")
                .font(.headline)

            SettingsRow("Next Aerial") {
                KeyboardShortcuts.Recorder("", name: .nextAerial)
            }
            .help("Immediately switch to the next Aerial wallpaper.")

            SettingsRow("Pause / Continue") {
                KeyboardShortcuts.Recorder("", name: .togglePause)
            }
            .help("Toggle scheduled rotation on or off.")

            SettingsRow("Go To Screensaver") {
                KeyboardShortcuts.Recorder("", name: .goToScreensaver)
            }
            .help("Start the screensaver right away.")

            Text("Hotkeys are global and may conflict with other apps. If one doesn't work, choose a different shortcut.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }


    @ViewBuilder
    private func pane<Content: View>(_ content: Content) -> some View {
        ScrollView {
            content
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}


private struct CategoryRow: Hashable, Sendable {
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

private struct ExcludedCategoriesPicker: View {
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

