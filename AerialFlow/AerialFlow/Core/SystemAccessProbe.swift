import Foundation

protocol SystemAccessProbing: Sendable {
    func probe(settings: AppSettings) -> SystemAccessReport
}

struct SystemAccessReport: Sendable, Equatable {
    let items: [SystemAccessItem]
}

struct SystemAccessItem: Sendable, Equatable, Identifiable {
    enum State: Sendable, Equatable {
        case ok
        case warning
        case error
    }

    let id: String
    let title: String
    let state: State
    let detail: String
}

struct SystemAccessProbe: SystemAccessProbing, Sendable {
    private let fileSystem: any FileSystem
    private let directoryDetector: ActiveVideoDirectoryDetector
    private let storeEditor: WallpaperStoreEditor
    private let catalogURL: URL
    private let features: AerialFlowFeatures

    init(
        fileSystem: any FileSystem,
        directoryDetector: ActiveVideoDirectoryDetector,
        storeEditor: WallpaperStoreEditor,
        features: AerialFlowFeatures,
        catalogURL: URL = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/entries.json")
    ) {
        self.fileSystem = fileSystem
        self.directoryDetector = directoryDetector
        self.storeEditor = storeEditor
        self.features = features
        self.catalogURL = catalogURL
    }

    func probe(settings: AppSettings) -> SystemAccessReport {
        var items: [SystemAccessItem] = []

        items.append(catalogStatusItem())
        items.append(indexPlistStatusItem(indexPlistURL: settings.indexPlistURL))
        items.append(aerialConfigurationStatusItem(indexPlistURL: settings.indexPlistURL))
        items.append(videosDirectoryStatusItem())

        return SystemAccessReport(items: items)
    }

    private func catalogStatusItem() -> SystemAccessItem {
        let title = "Aerial catalog (entries.json)"

        guard fileSystem.fileExists(at: catalogURL) else {
            return SystemAccessItem(
                id: "catalog",
                title: title,
                state: .error,
                detail: "Missing at \(catalogURL.path). macOS normally provides this. If you haven’t enabled Aerials yet, open System Settings > Wallpaper and select Aerials."
            )
        }

        guard fileSystem.isReadable(at: catalogURL) else {
            return SystemAccessItem(
                id: "catalog",
                title: title,
                state: .error,
                detail: "Not readable at \(catalogURL.path). Check file permissions or security software, then try again."
            )
        }

        return SystemAccessItem(
            id: "catalog",
            title: title,
            state: .ok,
            detail: catalogURL.path
        )
    }

    private func indexPlistStatusItem(indexPlistURL: URL) -> SystemAccessItem {
        let title = "Wallpaper store (Index.plist)"

        guard fileSystem.fileExists(at: indexPlistURL) else {
            return SystemAccessItem(
                id: "indexPlist",
                title: title,
                state: .warning,
                detail: "Missing at \(indexPlistURL.path). Open System Settings > Wallpaper and select Aerials, then try again."
            )
        }

        if !fileSystem.isReadable(at: indexPlistURL) {
            return SystemAccessItem(
                id: "indexPlist",
                title: title,
                state: .error,
                detail: "Not readable at \(indexPlistURL.path)."
            )
        }

        if !fileSystem.isWritable(at: indexPlistURL) {
            return SystemAccessItem(
                id: "indexPlist",
                title: title,
                state: .error,
                detail: "Not writable at \(indexPlistURL.path)."
            )
        }

        return SystemAccessItem(
            id: "indexPlist",
            title: title,
            state: .ok,
            detail: indexPlistURL.path
        )
    }

    private func videosDirectoryStatusItem() -> SystemAccessItem {
        let title = "Aerial videos directory"

        let detection: ActiveVideoDirectoryDetector.Detection
        do {
            detection = try directoryDetector.detect()
        } catch {
            return SystemAccessItem(
                id: "videos",
                title: title,
                state: .error,
                detail: "Could not determine videos directory: \(error.localizedDescription)"
            )
        }

        let dir = detection.videoDirectory

        if features.movDownloadMode == .relyOnSystemCache_macos15,
           dir.path.hasPrefix("/Library/Application Support/com.apple.idleassetsd/Customer/") {
            return SystemAccessItem(
                id: "videos",
                title: title,
                state: .ok,
                detail: "\(dir.path) (system-managed on macOS 15; not writable by design)"
            )
        }

        // If the directory doesn't exist yet, we rely on writability of the parent to create it later.
        if !fileSystem.fileExists(at: dir) {
            let parent = dir.deletingLastPathComponent()
            if fileSystem.fileExists(at: parent), fileSystem.isWritable(at: parent) {
                return SystemAccessItem(
                    id: "videos",
                    title: title,
                    state: .warning,
                    detail: "Directory will be created when needed: \(dir.path)"
                )
            }

            return SystemAccessItem(
                id: "videos",
                title: title,
                state: .error,
                detail: "Directory does not exist and cannot be created (not writable): \(dir.path)"
            )
        }

        if !fileSystem.isWritable(at: dir) {
            return SystemAccessItem(
                id: "videos",
                title: title,
                state: .error,
                detail: "Not writable: \(dir.path)"
            )
        }

        return SystemAccessItem(
            id: "videos",
            title: title,
            state: .ok,
            detail: dir.path
        )
    }

    private func aerialConfigurationStatusItem(indexPlistURL: URL) -> SystemAccessItem {
        let title = "Aerials wallpaper configuration"

        let status: WallpaperStoreEditor.AerialConfigurationStatus
        do {
            status = try storeEditor.inspectAerialConfiguration(indexPlistURL: indexPlistURL)
        } catch {
            return SystemAccessItem(
                id: "aerialConfiguration",
                title: title,
                state: .error,
                detail: "Could not inspect Index.plist configuration: \(error.localizedDescription)"
            )
        }

        if status.issues.isEmpty {
            return SystemAccessItem(
                id: "aerialConfiguration",
                title: title,
                state: .ok,
                detail: "Configured for Aerials."
            )
        }

        // Prefer actionable guidance over enumerating low-level issues.
        if status.issues.contains(.indexPlistMissing) {
            return SystemAccessItem(
                id: "aerialConfiguration",
                title: title,
                state: .warning,
                detail: "Index.plist is missing, so configuration can’t be inspected yet. Open System Settings > Wallpaper and select Aerials once."
            )
        }

        if status.issues.contains(.noAerialProviderNodes) {
            return SystemAccessItem(
                id: "aerialConfiguration",
                title: title,
                state: .error,
                detail: "Aerials aren’t configured yet. Open System Settings > Wallpaper and select Aerials, then try again."
            )
        }

        return SystemAccessItem(
            id: "aerialConfiguration",
            title: title,
            state: .warning,
            detail: "Aerials wallpaper configuration is incomplete. Open System Settings > Wallpaper and select an Aerial (Shuffle or a specific Aerial)."
        )
    }
}


