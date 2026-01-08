import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    @State private var catalogSnapshot: AerialCatalog.Snapshot?
    @State private var catalogErrorMessage: String?
    @State private var categoryDisplayNameByID: [String: String] = [:]
    @State private var assetDisplayNameByID: [String: String] = [:]
    @State private var currentAssetID: String?
    @State private var exclusionsSearchText: String = ""

    @State private var isPickingIndexPlist: Bool = false
    @State private var indexPlistPickerError: String?
    @State private var localSelectedDestination: AppState.SettingsDestination = .general

    private let sidebarSections: [(String, [AppState.SettingsDestination])] = [
        ("Settings", [.general, .rotation, .filtering, .exclusions, .hotkeys]),
        ("Tools", [.diagnostics]),
        ("Other", [.advanced, .about]),
    ]

    var body: some View {
        GeometryReader { proxy in
            let titlebarInsetHeight = max(proxy.safeAreaInsets.top, 28)
            // Start content a bit higher while still staying safely below the traffic lights.
            let contentTopInset = max(titlebarInsetHeight - 10, 18)
            let panelCornerRadius: CGFloat = 12
            let panelShadowColor = Color.black.opacity(0.10)
            let panelBorderColor = Color.primary.opacity(0.08)

            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    // Reserve the titlebar / traffic-lights area so content never paints underneath it.
                    Color.clear
                        .frame(height: contentTopInset)

                    HStack(alignment: .top, spacing: 12) {
                        List(selection: $localSelectedDestination) {
                            ForEach(sidebarSections, id: \.0) { sectionTitle, destinations in
                                Section(sectionTitle) {
                                    ForEach(destinations, id: \.self) { destination in
                                        Label(destination.title, systemImage: destination.systemImage)
                                            .tag(destination)
                                    }
                                }
                            }
                        }
                        .listStyle(.sidebar)
                        .scrollContentBackground(.hidden)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                                .strokeBorder(panelBorderColor)
                        )
                        .shadow(color: panelShadowColor, radius: 10, x: 0, y: 4)
                        .frame(width: 220)

                        detailView(for: localSelectedDestination)
                            .scrollContentBackground(.hidden)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                                    .strokeBorder(panelBorderColor)
                            )
                            .shadow(color: panelShadowColor, radius: 10, x: 0, y: 4)
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Current Aerial: \(appState.statusLine)")
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(
                                appState.lastErrorMessage == nil
                                    ? AnyShapeStyle(.secondary)
                                    : AnyShapeStyle(Color.red)
                            )

//                        Button("Support Development…") {
//                            guard let url = Constants.supportURL else { return }
//                            openURL(url)
//                        }
                        .font(.footnote)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: panelCornerRadius, style: .continuous)
                            .strokeBorder(panelBorderColor)
                    )
                    .shadow(color: panelShadowColor, radius: 10, x: 0, y: 4)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
        }
        .frame(width: 760, height: 620)
        .onAppear {
            localSelectedDestination = appState.selectedSettingsDestination
        }
        .onChange(of: localSelectedDestination) { _, newValue in
            appState.selectedSettingsDestination = newValue
        }
        .task { await loadCatalogDataIfNeeded() }
        .task { await refreshCurrentAssetID() }
        .onChange(of: appState.statusLine) { _, _ in
            Task { await refreshCurrentAssetID() }
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
                indexPlistPickerError = error.localizedDescription
            }
        }
        .alert("Couldn't Select File", isPresented: Binding(
            get: { indexPlistPickerError != nil },
            set: { if !$0 { indexPlistPickerError = nil } }
        )) {
            Button("OK") { indexPlistPickerError = nil }
        } message: {
            Text(indexPlistPickerError ?? "Unknown error")
        }
    }

    // MARK: - Detail routing

    @ViewBuilder
    private func detailView(for destination: AppState.SettingsDestination) -> some View {
        switch destination {
        case .general:
            generalPane
        case .rotation:
            rotationPane
        case .filtering:
            filteringPane
        case .exclusions:
            exclusionsPane
        case .hotkeys:
            hotkeysPane
        case .diagnostics:
            DiagnosticsView()
        case .advanced:
            advancedPane
        case .about:
            AboutView()
        }
    }

    // MARK: - Panes

    private var generalPane: some View {
        Form {
            Section {
                Text("Control how AerialFlow runs in the background and how it interacts with macOS permissions and notifications.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("System access") {
                SystemAccessStatusView(
                    report: appState.systemAccessReport,
                    onRefresh: { appState.refreshSystemAccessReport() }
                )
            }

            Section("Startup") {
            let launchAtLoginBinding = Binding(
                get: { appState.settings.launchAtLogin },
                set: { appState.setLaunchAtLoginEnabled($0) }
            )

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

                Button("Open Login Items…") {
                    appState.openLoginItemsSettings()
                }
                .help("Open System Settings where macOS asks you to approve AerialFlow as a login item.")
            }

            Section("Storage") {
            let excludedCleanupEnabledBinding = Binding(
                get: { appState.settings.isExcludedAerialCleanupEnabled },
                set: { appState.settings.isExcludedAerialCleanupEnabled = $0 }
            )

                    Toggle("Automatically remove excluded Aerials", isOn: excludedCleanupEnabledBinding)
                        .help("Once a day, remove excluded Aerial .mov files from the storage location. This does not run while your Mac is asleep.")

                HStack(spacing: 10) {
                    Button("Clean Now") {
                        appState.cleanExcludedAerialsNow()
                    }
                    .disabled(appState.isCleaningExcludedAerials)
                    .help("Remove excluded Aerial .mov files now (even if the daily schedule is off).")

                    if appState.isCleaningExcludedAerials {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text("This affects downloaded video files only; it does not change your exclusions.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Updates") {
                CheckForUpdatesView()
            }

            Section("Notifications") {
                HStack(alignment: .firstTextBaseline) {
                    Text("Status: \(notificationStatusText(appState.notificationAuthorizationStatus))")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Refresh") {
                        Task { await appState.refreshNotificationAuthorizationStatus() }
                    }
                }

                HStack(spacing: 10) {
                    Button("Enable Notifications…") {
                        appState.requestNotificationAuthorization()
                    }
                    .disabled(appState.notificationAuthorizationStatus != .notDetermined)

                    Button("Open Notification Settings…") {
                        appState.openNotificationSettings()
                    }
                }

                Text("Used to show an alert if a user-triggered action fails (for example: Next Aerial).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var rotationPane: some View {
        Form {
            Section {
                Text("Schedule automatic background changes. Rotation pauses while your Mac sleeps or screens are off.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Rotation") {
            let rotationEnabledBinding = Binding(
                get: { appState.settings.isRotationEnabled },
                set: { appState.settings.isRotationEnabled = $0 }
            )

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

                let minutesBinding = Binding<Int>(
                    get: { max(1, appState.settings.rotationIntervalSeconds / 60) },
                    set: { appState.settings.rotationIntervalSeconds = max(60, $0 * 60) }
                )

                LabeledContent("Interval") {
                    RotationIntervalControl(
                        minutes: minutesBinding,
                        minMinutes: 1,
                        sliderMaxMinutes: Constants.maximumRotationIntervalMinutes
                    )
                }
                .disabled(!appState.settings.isRotationEnabled)

                let resumeBehaviorBinding = Binding<AppSettings.SleepResumeBehavior>(
                    get: { appState.settings.sleepResumeBehavior },
                    set: { appState.settings.sleepResumeBehavior = $0 }
                )

                LabeledContent("After sleep / display off") {
                    Picker("", selection: resumeBehaviorBinding) {
                        Text("Use original time left")
                            .tag(AppSettings.SleepResumeBehavior.useOriginalTimeLeft)
                        Text("Immediately go to next Aerial")
                            .tag(AppSettings.SleepResumeBehavior.immediatelyGoToNextAerial)
                        Text("Restart the rotation timer")
                            .tag(AppSettings.SleepResumeBehavior.restartRotationTimer)
                    }
                    .labelsHidden()
                }
                .help("What to do when macOS wakes up or your displays turn back on.")

                Text("AerialFlow stores the remaining time when sleep/screen-off happens, then resumes based on this setting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var filteringPane: some View {
        Form {
            Section {
                Text("Optionally prefer darker Aerials outside a time window, based on each Aerial’s preview-image brightness.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
            }

            Section("Light-sensitive filtering") {
                let enabledBinding = Binding(
                        get: { appState.settings.isLightSensitiveFilteringEnabled },
                        set: { appState.settings.isLightSensitiveFilteringEnabled = $0 }
                )

                Toggle("Enable light-sensitive filtering", isOn: enabledBinding)
                    .help("Outside the allowed light window, AerialFlow prefers darker Aerials.")

                LabeledContent("Light allowed") {
                    TimeRangeSlider(
                        title: "",
                        startMinutes: Binding(
                            get: { appState.settings.allowedLightStartMinutes },
                            set: { appState.settings.allowedLightStartMinutes = $0 }
                        ),
                        endMinutes: Binding(
                            get: { appState.settings.allowedLightEndMinutes },
                            set: { appState.settings.allowedLightEndMinutes = $0 }
                        ),
                        range: 0...(24 * 60),
                        step: 5
                    )
                    .frame(maxWidth: 360)
                }
                .disabled(!appState.settings.isLightSensitiveFilteringEnabled)

                LabeledContent("Sensitivity") {
                    let sensitivityBinding = Binding<Double>(
                        get: { appState.settings.lightSensitivity },
                        set: { appState.settings.lightSensitivity = $0 }
                    )

                    HStack(spacing: 10) {
                        Slider(value: sensitivityBinding, in: 0...1, step: 0.01)
                            .frame(width: 260)
                        Text(sensitivityBinding.wrappedValue.formatted(.number.precision(.fractionLength(2))))
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                .disabled(!appState.settings.isLightSensitiveFilteringEnabled)
                .help("Brightness threshold (0–1). Outside the allowed window, only Aerials below this value are eligible.")

                if appState.settings.isLightSensitiveFilteringEnabled, appState.settings.lightSensitivity < 0.15 {
                    Text("Tip: very low sensitivity values (below 0.15) can be too strict and may not find any suitable Aerials.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var exclusionsPane: some View {
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
                let mainCategories = AerialCategory.uniqueMainCategories(snapshot.categories)
                let rows = ExclusionRow.rows(fromMainCategories: mainCategories, assets: snapshot.assets)

                ExcludedCategoriesPicker(
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
                    currentAssetID: currentAssetID
                )
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

    private var hotkeysPane: some View {
        Form {
            Section {
                Text("Hotkeys are global. If a shortcut doesn’t work, it’s often due to macOS permissions or conflicts with another app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Aerial navigation") {
                LabeledContent("Next Aerial") {
                        KeyboardShortcuts.Recorder("", name: .nextAerial)
                    }
                    .help("Immediately switch to the next Aerial wallpaper.")

                LabeledContent("Next In Subcategory") {
                        KeyboardShortcuts.Recorder("", name: .nextInSubcategory)
                    }
                    .help("Advance within the current Aerial’s primary subcategory (deterministic).")

                LabeledContent("Exclude current aerial + Next") {
                        KeyboardShortcuts.Recorder("", name: .excludeCurrentSubcategoryAndNext)
                    }
                    .help("Exclude the current Aerial and immediately switch to the next eligible Aerial.")
            }

            Section("System controls") {
                LabeledContent("Pause / Continue") {
                        KeyboardShortcuts.Recorder("", name: .togglePause)
                    }
                    .help("Toggle scheduled rotation on or off.")

                LabeledContent("Go To Screensaver") {
                        KeyboardShortcuts.Recorder("", name: .goToScreensaver)
                    }
                    .help("Start the screensaver right away.")
            }

            Section("Permissions") {
                Text("If hotkeys don’t work, enable AerialFlow in these macOS privacy sections:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button("Open Input Monitoring…") {
                            appState.openInputMonitoringSettings()
                        }
                        Button("Open Accessibility…") {
                            appState.openAccessibilitySettings()
                        }
                    }
            }
        }
        .formStyle(.grouped)
    }

    private var advancedPane: some View {
        Form {
            Section {
                Text("These options are for troubleshooting and custom setups. Most users should leave them at the defaults.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Downloads") {
                let timeoutMinutesBinding = Binding<Int>(
                    get: { max(1, Int(appState.settings.downloadTimeout) / 60) },
                    set: { appState.settings.downloadTimeout = TimeInterval(max(60, $0 * 60)) }
                )

                LabeledContent("Download timeout") {
                    Stepper(value: timeoutMinutesBinding, in: 1...120, step: 1) {
                        Text("\(timeoutMinutesBinding.wrappedValue) min")
                            .frame(minWidth: 72, alignment: .trailing)
                    }
                }
                .help("How long AerialFlow will wait for a download to complete before failing.")
            }

            Section("Wallpaper store") {
                LabeledContent("Index.plist") {
                    Text(appState.settings.indexPlistURL.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                .help("The Index.plist file AerialFlow edits to apply the next Aerial. The default is the system wallpaper store.")

                LabeledContent("Location") {
                    HStack(spacing: 8) {
                        Button("Choose…") {
                            isPickingIndexPlist = true
                        }
                        Button("Reset") {
                            appState.settings.indexPlistURL = WallpaperStoreEditor.defaultIndexPlistURL
                        }
                    }
                }

                Text("Changing this can prevent AerialFlow from updating your wallpaper if it points to the wrong store.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Backups") {
                let backupRetentionBinding = Binding<Int>(
                    get: { appState.settings.backupRetentionCount },
                    set: { appState.settings.backupRetentionCount = $0 }
                )

                LabeledContent("Backups to keep") {
                    Stepper(value: backupRetentionBinding, in: 1...Constants.maximumBackupRetentionCount, step: 1) {
                        Text("\(backupRetentionBinding.wrappedValue)")
                            .frame(minWidth: 44, alignment: .trailing)
                    }
                }
                .help("How many Index.plist backups AerialFlow keeps next to the original. Older backups are pruned automatically.")
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func notificationStatusText(_ status: UNAuthorizationStatus?) -> String {
        guard let status else { return "Unknown" }
        switch status {
        case .notDetermined: return "Not determined"
        case .denied: return "Denied"
        case .authorized: return "Allowed"
        case .provisional: return "Provisional"
        case .ephemeral: return "Ephemeral"
        @unknown default: return "Unknown"
        }
    }

    private func refreshCurrentAssetID() async {
        currentAssetID = await appState.currentAssetID()
    }

    private func loadCatalogDataIfNeeded() async {
        guard catalogSnapshot == nil, catalogErrorMessage == nil else { return }
        do {
            let snapshot = try await appState.loadCatalogSnapshot()
            catalogSnapshot = snapshot

            let mainCategories = AerialCategory.uniqueMainCategories(snapshot.categories)
            let rows = ExclusionRow.rows(fromMainCategories: mainCategories, assets: snapshot.assets)
            let categories = rows.compactMap { row in
                switch row {
                case .category(let category, _, _):
                    return category
                case .asset:
                    return nil
                }
            }
            categoryDisplayNameByID = await appState.categoryDisplayNamesByID(categories: categories)
            assetDisplayNameByID = await appState.assetDisplayNamesByID(assets: snapshot.assets)
        } catch {
            catalogErrorMessage = error.localizedDescription
        }
    }
}
