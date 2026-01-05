import Foundation

/// Composition root: constructs and holds the app's long-lived service dependencies.
struct AppDependencies {
    let fileSystem: any FileSystem
    let commandRunner: any CommandRunner
    let catalog: any AerialCataloging
    let categoryResolver: CategoryResolver
    let stateStore: any AerialEngineStateStore
    let directoryDetector: ActiveVideoDirectoryDetector
    let downloader: any AssetDownloadEnsuring
    let storeEditor: WallpaperStoreEditor
    let reloader: any WallpaperReloading
    let runGuard: any RunGuarding
    let screensaverLauncher: any ScreensaverLaunching
    let hotkeyBinder: any HotkeyBinding
    let launchAtLoginManager: any LaunchAtLoginManaging
    let picker: any AssetPicking
    let urlSelector: any AssetURLSelecting
    let engine: AerialEngine

    static func live(
        userDefaults: UserDefaults = .standard,
        screensaverLauncher: (any ScreensaverLaunching)? = nil,
        hotkeyBinder: (any HotkeyBinding)? = nil,
        launchAtLoginManager: (any LaunchAtLoginManaging)? = nil
    ) -> AppDependencies {
        let fileSystem: any FileSystem = DefaultFileSystem()
        let runner: any CommandRunner = ProcessCommandRunner()
        let catalog: any AerialCataloging = AerialCatalog(fileSystem: fileSystem)
        let categoryResolver = CategoryResolver(fileSystem: fileSystem)
        let stateStore: any AerialEngineStateStore = UserDefaultsEngineStateStore(userDefaults: userDefaults)
        let directoryDetector = ActiveVideoDirectoryDetector(runner: runner)
        let urlSessionDownloader: any Downloading = URLSessionDownloader(session: .shared)
        let downloader: any AssetDownloadEnsuring = AssetDownloader(
            fileSystem: fileSystem,
            downloader: urlSessionDownloader,
            directoryDetector: directoryDetector
        )
        let storeEditor = WallpaperStoreEditor(fileSystem: fileSystem)
        let reloader: any WallpaperReloading = WallpaperReloader(runner: runner)
        let runGuard: any RunGuarding = RunGuard(runner: runner)
        let screensaverLauncher = screensaverLauncher ?? ScreensaverLauncher(runner: runner)
        let hotkeyBinder = hotkeyBinder ?? KeyboardShortcutsHotkeyBinder()
        let launchAtLoginManager = launchAtLoginManager ?? LaunchAtLoginManager()
        let picker: any AssetPicking = AssetPicker()
        let urlSelector: any AssetURLSelecting = AssetURLSelector()

        let engine = AerialEngine(
            catalog: catalog,
            picker: picker,
            urlSelector: urlSelector,
            downloader: downloader,
            storeEditor: storeEditor,
            reloader: reloader,
            stateStore: stateStore
        )

        return AppDependencies(
            fileSystem: fileSystem,
            commandRunner: runner,
            catalog: catalog,
            categoryResolver: categoryResolver,
            stateStore: stateStore,
            directoryDetector: directoryDetector,
            downloader: downloader,
            storeEditor: storeEditor,
            reloader: reloader,
            runGuard: runGuard,
            screensaverLauncher: screensaverLauncher,
            hotkeyBinder: hotkeyBinder,
            launchAtLoginManager: launchAtLoginManager,
            picker: picker,
            urlSelector: urlSelector,
            engine: engine
        )
    }
}


