import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var categorySearchText: String = ""
    @State private var catalogSnapshot: AerialCatalog.Snapshot?
    @State private var catalogErrorMessage: String?
    @State private var configurationStatus: WallpaperStoreEditor.AerialConfigurationStatus?
    @State private var configurationErrorMessage: String?
    @State private var isRepairingConfiguration: Bool = false

    var body: some View {
        Form {
            Section("Rotation") {
                Toggle(
                    "Enable scheduled rotation",
                    isOn: Binding(
                        get: { appState.settings.isRotationEnabled },
                        set: { appState.settings.isRotationEnabled = $0 }
                    )
                )

                let minutesBinding = Binding<Int>(
                    get: { max(1, appState.settings.rotationIntervalSeconds / 60) },
                    set: { appState.settings.rotationIntervalSeconds = max(60, $0 * 60) }
                )

                Stepper(value: minutesBinding, in: 1...240, step: 1) {
                    Text("Interval: \(minutesBinding.wrappedValue) min")
                }
                .disabled(!appState.settings.isRotationEnabled)
            }

            Section("Categories") {
                if let catalogErrorMessage {
                    Text(catalogErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                }

                if let snapshot = catalogSnapshot {
                    CategoriesPicker(
                        categories: snapshot.categories,
                        categoryDisplayNameByID: appState.categoryDisplayNamesByID(categories: snapshot.categories),
                        excludedCategoryIDs: Binding(
                            get: { appState.settings.excludedCategoryIDs },
                            set: { appState.settings.excludedCategoryIDs = $0 }
                        ),
                        searchText: $categorySearchText
                    )
                } else {
                    Text("Loading categories…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Downloads") {
                Picker(
                    "Quality",
                    selection: Binding(
                        get: { appState.settings.qualityPreference },
                        set: { appState.settings.qualityPreference = $0 }
                    )
                ) {
                    Text("240fps (largest)").tag(VideoQualityPreference.prefer240fps)
                    Text("4K").tag(VideoQualityPreference.prefer4k)
                    Text("1080p").tag(VideoQualityPreference.prefer1080)
                }
                .pickerStyle(.segmented)
            }

            Section("Configuration") {
                if let configurationErrorMessage {
                    Text(configurationErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                } else if let configurationStatus {
                    Text(configurationSummaryLine(for: configurationStatus))
                        .font(.footnote)
                        .foregroundStyle(configurationStatus.isLikelyConfigured ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.red))
                } else {
                    Text("Checking configuration…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Fix Automatically") {
                        Task { await repairConfiguration() }
                    }
                    .disabled(isRepairingConfiguration)

                    Button("Open System Settings…") {
                        appState.openSystemSettingsForWallpaper()
                    }
                }
            }

            Text(appState.statusLine)
                .font(.footnote)
                .foregroundStyle(
                    appState.lastErrorMessage == nil
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(Color.red)
                )
        }
        .padding(20)
        .frame(width: 520)
        .task {
            guard catalogSnapshot == nil, catalogErrorMessage == nil else { return }
            do {
                catalogSnapshot = try await appState.loadCatalogSnapshot()
            } catch {
                catalogErrorMessage = error.localizedDescription
            }
        }
        .task {
            await refreshConfigurationStatus()
        }
    }

    private func refreshConfigurationStatus() async {
        do {
            let status = try appState.inspectAerialConfiguration()
            configurationStatus = status
            configurationErrorMessage = nil
        } catch {
            configurationStatus = nil
            configurationErrorMessage = error.localizedDescription
        }
    }

    private func repairConfiguration() async {
        guard !isRepairingConfiguration else { return }
        isRepairingConfiguration = true
        defer { isRepairingConfiguration = false }

        do {
            _ = try await appState.repairAerialConfiguration()
            await refreshConfigurationStatus()
        } catch {
            configurationErrorMessage = error.localizedDescription
        }
    }

    private func configurationSummaryLine(for status: WallpaperStoreEditor.AerialConfigurationStatus) -> String {
        if status.isLikelyConfigured {
            return "Configured. Provider nodes: \(status.totalProviderNodes)."
        }

        var parts: [String] = []
        if status.totalProviderNodes == 0 {
            parts.append("No Aerial provider nodes found.")
        } else {
            parts.append("Provider nodes: \(status.totalProviderNodes) (Desktop \(status.desktopProviderNodes), Idle \(status.idleProviderNodes)).")
        }

        if status.issues.contains(.missingDesktopNode) { parts.append("Desktop not set to Aerials.") }
        if status.issues.contains(.missingIdleNode) { parts.append("Screen Saver not set to Aerials.") }
        if status.issues.contains(.indexPlistMissing) { parts.append("Index.plist missing.") }

        return parts.joined(separator: " ")
    }
}

private struct CategoriesPicker: View {
    let categories: [AerialCategory]
    let categoryDisplayNameByID: [String: String]
    @Binding var excludedCategoryIDs: Set<String>
    @Binding var searchText: String

    var body: some View {
        TextField("Search categories", text: $searchText)

        List(filteredCategories, id: \.id) { category in
            Toggle(
                "Exclude \(displayName(for: category))",
                isOn: Binding(
                    get: { excludedCategoryIDs.contains(category.id) },
                    set: { isExcluded in
                        if isExcluded {
                            excludedCategoryIDs.insert(category.id)
                        } else {
                            excludedCategoryIDs.remove(category.id)
                        }
                    }
                )
            )
        }
        .frame(height: 220)

        Button("Exclude Earth") {
            guard let earthID = findFirstCategoryID(matching: "earth") else { return }
            excludedCategoryIDs.insert(earthID)
        }
        .disabled(findFirstCategoryID(matching: "earth") == nil)
    }

    private var filteredCategories: [AerialCategory] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return categories.sorted { displayName(for: $0) < displayName(for: $1) }
        }

        let lower = trimmed.lowercased()
        return categories
            .filter { category in
                let name = displayName(for: category).lowercased()
                return name.contains(lower) || category.id.lowercased().contains(lower)
            }
            .sorted { displayName(for: $0) < displayName(for: $1) }
    }

    private func displayName(for category: AerialCategory) -> String {
        categoryDisplayNameByID[category.id] ?? category.id
    }

    private func findFirstCategoryID(matching lowerNeedle: String) -> String? {
        for category in categories {
            let name = displayName(for: category).lowercased()
            if name.contains(lowerNeedle) { return category.id }
        }
        return nil
    }
}

