import Foundation

/// Composition root: constructs and holds the app's long-lived service dependencies.
struct AppDependencies {
    let fileSystem: any FileSystem
    let commandRunner: any CommandRunner
    let powerEventObserver: any PowerEventObserving
    let catalog: any AerialCataloging
    let categoryResolver: CategoryResolver
    let stateStore: any AerialEngineStateStore
    let excludedAerialsCleanupStateStore: any ExcludedAerialsCleanupStateStoring
    let directoryDetector: ActiveVideoDirectoryDetector
    let features: AerialFlowFeatures
    let downloader: any AssetDownloadEnsuring
    let brightnessStore: any AerialBrightnessStoring
    let storeEditor: WallpaperStoreEditor
    let reloader: any WallpaperReloading
    let excludedAerialsCleaner: ExcludedAerialsCleaner
    let screensaverLauncher: any ScreensaverLaunching
    let hotkeyBinder: any HotkeyBinding
    let launchAtLoginManager: any LaunchAtLoginManaging
    let picker: any AssetPicking
    let urlSelector: any AssetURLSelecting
    let engine: AerialEngine
    let updaterViewModel: UpdaterViewModel
    let systemAccessProbe: any SystemAccessProbing
    let notificationPermissionService: any NotificationPermissionServicing
    let systemSettingsOpener: any SystemSettingsOpening

    static func live(
        userDefaults: UserDefaults = .standard,
        screensaverLauncher: (any ScreensaverLaunching)? = nil,
        hotkeyBinder: (any HotkeyBinding)? = nil,
        launchAtLoginManager: (any LaunchAtLoginManaging)? = nil,
        updaterViewModel: UpdaterViewModel? = nil
    ) -> AppDependencies {
        let fileSystem: any FileSystem = DefaultFileSystem()
        let runner: any CommandRunner = ProcessCommandRunner()
        let features = AerialFlowFeatures.live()
        let powerEventObserver: any PowerEventObserving = NSWorkspacePowerEventObserver()
        let catalog: any AerialCataloging = AerialCatalog(fileSystem: fileSystem)
        let categoryResolver = CategoryResolver(fileSystem: fileSystem)
        let stateStore: any AerialEngineStateStore = UserDefaultsEngineStateStore(userDefaults: userDefaults)
        let excludedAerialsCleanupStateStore: any ExcludedAerialsCleanupStateStoring = UserDefaultsExcludedAerialsCleanupStateStore(userDefaults: userDefaults)
        let directoryDetector = ActiveVideoDirectoryDetector(runner: runner)
        let urlSessionDownloader: any Downloading = URLSessionDownloader(session: .shared)
        let downloader: any AssetDownloadEnsuring = AssetDownloader(
            fileSystem: fileSystem,
            downloader: urlSessionDownloader,
            directoryDetector: directoryDetector,
            features: features
        )
        let brightnessStore: any AerialBrightnessStoring = AerialBrightnessStore(
            userDefaults: userDefaults,
            fileSystem: fileSystem,
            downloader: urlSessionDownloader
        )
        let storeEditor = WallpaperStoreEditor(fileSystem: fileSystem)
        let reloader: any WallpaperReloading = WallpaperReloader(runner: runner)
        let excludedAerialsCleaner = ExcludedAerialsCleaner(
            fileSystem: fileSystem,
            directoryDetector: directoryDetector,
            catalog: catalog,
            features: features
        )
        let screensaverLauncher = screensaverLauncher ?? ScreensaverLauncher(runner: runner)
        let hotkeyBinder = hotkeyBinder ?? KeyboardShortcutsHotkeyBinder()
        let launchAtLoginManager = launchAtLoginManager ?? LaunchAtLoginManager()
        let picker: any AssetPicking = AssetPicker()
        let urlSelector: any AssetURLSelecting = AssetURLSelector()
        let updaterViewModel = updaterViewModel ?? {
            let isRunningTests = NSClassFromString("XCTestCase") != nil
            let manager = AutoUpdateManager(startingUpdater: !isRunningTests)
            return UpdaterViewModel(controller: manager.controller)
        }()
        let systemAccessProbe: any SystemAccessProbing = SystemAccessProbe(
            fileSystem: fileSystem,
            directoryDetector: directoryDetector,
            storeEditor: storeEditor,
            features: features
        )
        let notificationPermissionService: any NotificationPermissionServicing = NotificationPermissionService()
        let systemSettingsOpener: any SystemSettingsOpening = SystemSettingsOpener()

        let engine = AerialEngine(
            catalog: catalog,
            picker: picker,
            urlSelector: urlSelector,
            downloader: downloader,
            brightnessStore: brightnessStore,
            storeEditor: storeEditor,
            reloader: reloader,
            stateStore: stateStore,
            features: features
        )

        return AppDependencies(
            fileSystem: fileSystem,
            commandRunner: runner,
            powerEventObserver: powerEventObserver,
            catalog: catalog,
            categoryResolver: categoryResolver,
            stateStore: stateStore,
            excludedAerialsCleanupStateStore: excludedAerialsCleanupStateStore,
            directoryDetector: directoryDetector,
            features: features,
            downloader: downloader,
            brightnessStore: brightnessStore,
            storeEditor: storeEditor,
            reloader: reloader,
            excludedAerialsCleaner: excludedAerialsCleaner,
            screensaverLauncher: screensaverLauncher,
            hotkeyBinder: hotkeyBinder,
            launchAtLoginManager: launchAtLoginManager,
            picker: picker,
            urlSelector: urlSelector,
            engine: engine,
            updaterViewModel: updaterViewModel,
            systemAccessProbe: systemAccessProbe,
            notificationPermissionService: notificationPermissionService,
            systemSettingsOpener: systemSettingsOpener
        )
    }
}

extension AppDependencies {
    /// Convenience wrapper to avoid threading yet another stored dependency through every initializer callsite.
    var catalogPresentation: CatalogPresentationService {
        CatalogPresentationService(catalog: catalog, resolver: categoryResolver)
    }

    /// Convenience wrapper to avoid threading yet another stored dependency through every initializer callsite.
    var launchAtLoginCoordinator: LaunchAtLoginCoordinator {
        LaunchAtLoginCoordinator(manager: launchAtLoginManager)
    }
}


