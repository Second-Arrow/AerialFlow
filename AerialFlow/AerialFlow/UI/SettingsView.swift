import SwiftUI
import KeyboardShortcuts
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    private let catalog: any AerialCataloging
    private let catalogPresentation: CatalogPresentationService
    private let stateStore: any AerialEngineStateStore
    private let systemSettingsOpener: any SystemSettingsOpening

    @State private var catalogSnapshot: AerialCatalog.Snapshot?
    @State private var catalogErrorMessage: String?
    @State private var categoryDisplayNameByID: [String: String] = [:]
    @State private var assetDisplayNameByID: [String: String] = [:]
    @State private var currentAssetID: String?
    @State private var exclusionsSearchText: String = ""

    @State private var isPickingIndexPlist: Bool = false
    @State private var indexPlistPickerError: String?
    @State private var localSelectedDestination: AppState.SettingsDestination = .general

    init(
        catalog: any AerialCataloging,
        catalogPresentation: CatalogPresentationService,
        stateStore: any AerialEngineStateStore,
        systemSettingsOpener: any SystemSettingsOpening
    ) {
        self.catalog = catalog
        self.catalogPresentation = catalogPresentation
        self.stateStore = stateStore
        self.systemSettingsOpener = systemSettingsOpener
    }

    var body: some View {
        GeometryReader { proxy in
            let titlebarInsetHeight = max(proxy.safeAreaInsets.top, 28)
            // Start content a bit higher while still staying safely below the traffic lights.
            let contentTopInset = max(titlebarInsetHeight - 20, 12)
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
                            ForEach(SettingsSidebarModel.sections, id: \.self) { section in
                                Section(section.title) {
                                    ForEach(section.destinations, id: \.self) { destination in
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
                        SettingsFooterView(
                            statusLine: appState.statusLine,
                            hasError: appState.lastErrorMessage != nil
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
            GeneralSettingsPane(systemSettingsOpener: systemSettingsOpener)
        case .rotation:
            RotationSettingsPane()
        case .filtering:
            FilteringSettingsPane()
        case .exclusions:
            ExclusionsSettingsPane(
                catalogSnapshot: catalogSnapshot,
                catalogErrorMessage: catalogErrorMessage,
                categoryDisplayNameByID: categoryDisplayNameByID,
                assetDisplayNameByID: assetDisplayNameByID,
                currentAssetID: currentAssetID,
                exclusionsSearchText: $exclusionsSearchText
            )
        case .hotkeys:
            HotkeysSettingsPane(systemSettingsOpener: systemSettingsOpener)
        case .diagnostics:
            DiagnosticsView()
        case .advanced:
            AdvancedSettingsPane(isPickingIndexPlist: $isPickingIndexPlist)
        case .about:
            AboutView()
        }
    }

    // MARK: - Helpers

    private func refreshCurrentAssetID() async {
        currentAssetID = await stateStore.getLastAssetID()
    }

    private func loadCatalogDataIfNeeded() async {
        guard catalogSnapshot == nil, catalogErrorMessage == nil else { return }
        do {
            let snapshot = try await catalog.loadSnapshot()
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
            categoryDisplayNameByID = await catalogPresentation.categoryDisplayNamesByID(categories: categories)
            assetDisplayNameByID = await catalogPresentation.assetDisplayNamesByID(assets: snapshot.assets)
        } catch {
            catalogErrorMessage = error.localizedDescription
        }
    }
}
