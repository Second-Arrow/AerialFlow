import Foundation
import os

@MainActor
final class AppUserActions {
    private enum NextAerialError: LocalizedError {
        case busy

        var errorDescription: String? {
            switch self {
            case .busy:
                return "AerialFlow is busy."
            }
        }
    }

    private enum NextInSubcategoryError: LocalizedError {
        case busy
        case noCurrentSubcategory
        case noEligibleAssetsInSubcategory

        var errorDescription: String? {
            switch self {
            case .busy:
                return "AerialFlow is busy."
            case .noCurrentSubcategory:
                return "No current subcategory is available for the active Aerial."
            case .noEligibleAssetsInSubcategory:
                return "No eligible Aerial assets are available in the current subcategory."
            }
        }
    }

    private let logger: Logger

    private let ui: AppUIState
    private let settingsStore: AppSettingsStore
    private let stateStore: any AerialEngineStateStore
    private let rotationCoordinator: RotationCoordinator
    private let excludedAerialsCleanupCoordinator: ExcludedAerialsCleanupCoordinator
    private let catalogPresentation: CatalogPresentationService
    private let screensaverLauncher: any ScreensaverLaunching
    private let systemSettingsOpener: any SystemSettingsOpening
    private let notificationCoordinator: NotificationCoordinator

    private var excludedAerialsCleanupTask: Task<Void, Never>?

    init(
        ui: AppUIState,
        settingsStore: AppSettingsStore,
        stateStore: any AerialEngineStateStore,
        rotationCoordinator: RotationCoordinator,
        excludedAerialsCleanupCoordinator: ExcludedAerialsCleanupCoordinator,
        catalogPresentation: CatalogPresentationService,
        screensaverLauncher: any ScreensaverLaunching,
        systemSettingsOpener: any SystemSettingsOpening,
        notificationCoordinator: NotificationCoordinator,
        logger: Logger = Logger(subsystem: Constants.loggerSubsystem, category: "AppUserActions")
    ) {
        self.ui = ui
        self.settingsStore = settingsStore
        self.stateStore = stateStore
        self.rotationCoordinator = rotationCoordinator
        self.excludedAerialsCleanupCoordinator = excludedAerialsCleanupCoordinator
        self.catalogPresentation = catalogPresentation
        self.screensaverLauncher = screensaverLauncher
        self.systemSettingsOpener = systemSettingsOpener
        self.notificationCoordinator = notificationCoordinator
        self.logger = logger
    }

    var isRotationEnabled: Bool { settingsStore.settings.isRotationEnabled }
    var isPaused: Bool { !settingsStore.settings.isRotationEnabled }

    func setRotationEnabled(_ enabled: Bool) {
        guard settingsStore.settings.isRotationEnabled != enabled else { return }
        settingsStore.settings.isRotationEnabled = enabled
    }

    func nextAerial() async {
        _ = await performNextAerial(isUserInitiated: true, logContext: "Next Aerial")
    }

    func scheduledNextAerial() async {
        _ = await performNextAerial(isUserInitiated: false, logContext: "Scheduled rotation")
    }

    func nextInSubcategory() async {
        guard !ui.isBusy else {
            await handleUserInitiatedError(NextInSubcategoryError.busy, logContext: "Next In Subcategory")
            return
        }

        ui.isBusy = true
        ui.lastErrorMessage = nil
        ui.statusLine = "Applying next in subcategory…"
        defer { ui.isBusy = false }

        let lastAssetID = await stateStore.getLastAssetID()
        let subcategoryIDs = await catalogPresentation.subcategoryIDs(for: lastAssetID)
        guard let primarySubcategoryID = subcategoryIDs.sorted().first else {
            await handleUserInitiatedError(NextInSubcategoryError.noCurrentSubcategory, logContext: "Next In Subcategory")
            return
        }

        do {
            let report = try await rotationCoordinator.nextInSubcategory(
                settings: settingsStore.settings,
                subcategoryID: primarySubcategoryID
            )
            let displayName = await catalogPresentation.assetDisplayName(for: report.chosenAssetID) ?? report.chosenAssetID
            ui.statusLine = displayName
            await rotationCoordinator.notifyStateChanged()
        } catch {
            let isNoEligibleAssets: Bool
            if let pickerError = error as? AssetPicker.PickerError, case .noEligibleAssets = pickerError {
                isNoEligibleAssets = true
            } else {
                isNoEligibleAssets = (error.localizedDescription == AssetPicker.PickerError.noEligibleAssets.localizedDescription)
            }

            if isNoEligibleAssets {
                await handleUserInitiatedError(NextInSubcategoryError.noEligibleAssetsInSubcategory, logContext: "Next In Subcategory")
            } else {
                await handleUserInitiatedError(error, logContext: "Next In Subcategory")
            }
        }
    }

    /// Applies a specific Aerial immediately, bypassing rotation selection.
    func applySpecificAsset(id assetID: String) async {
        guard !ui.isBusy else {
            await handleUserInitiatedError(NextAerialError.busy, logContext: "Apply Aerial")
            return
        }

        ui.isBusy = true
        ui.lastErrorMessage = nil
        ui.statusLine = "Applying Aerial…"
        defer { ui.isBusy = false }

        do {
            let report = try await rotationCoordinator.apply(assetID: assetID, settings: settingsStore.settings)
            let displayName = await catalogPresentation.assetDisplayName(for: report.chosenAssetID) ?? report.chosenAssetID
            ui.statusLine = displayName
            await rotationCoordinator.notifyStateChanged()
        } catch {
            await handleUserInitiatedError(error, logContext: "Apply Aerial")
        }
    }

    func excludeCurrentSubcategoryAndNext() async {
        guard !ui.isBusy else { return }

        let previous = settingsStore.settings.excludedAssetIDs
        if let currentAssetID = await stateStore.getLastAssetID(), !currentAssetID.isEmpty {
            var updated = settingsStore.settings.excludedAssetIDs
            updated.insert(currentAssetID)
            settingsStore.settings.excludedAssetIDs = updated
        }

        let result = await performNextAerial(isUserInitiated: true, logContext: "Exclude current aerial + Next")
        if case .failure(let error) = result {
            let isNoEligibleAssets: Bool
            if let pickerError = error as? AssetPicker.PickerError, case .noEligibleAssets = pickerError {
                isNoEligibleAssets = true
            } else {
                // Be resilient to error type wrapping/bridging while still keying off the specific condition.
                isNoEligibleAssets = (error.localizedDescription == AssetPicker.PickerError.noEligibleAssets.localizedDescription)
            }

            if isNoEligibleAssets {
                settingsStore.settings.excludedAssetIDs = previous
            }
        }
    }

    func goToScreensaver() {
        do {
            try screensaverLauncher.start()
        } catch {
            let message = error.localizedDescription
            ui.lastErrorMessage = message
            ui.statusLine = "Error: \(message)"
            logger.error("Go To Screensaver failed: \(message, privacy: .public)")
        }
    }

    func openWallpaperSettings() {
        _ = systemSettingsOpener.openWallpaperSettings()
    }

    func openScreenSaverSettings() {
        _ = systemSettingsOpener.openScreenSaverSettings()
    }

    func cleanExcludedAerialsNow() {
        excludedAerialsCleanupTask?.cancel()
        excludedAerialsCleanupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.runUserInitiatedExcludedAerialCleanup()
        }
    }

    func cancelCleanupTask() {
        excludedAerialsCleanupTask?.cancel()
    }

    // MARK: - Internals

    private func handleUserInitiatedError(_ error: Error, logContext: String) async {
        let message = error.localizedDescription
        ui.lastErrorMessage = message
        ui.statusLine = "Error: \(message)"
        logger.error("\(logContext) failed: \(message, privacy: .public)")
        scheduleErrorNotificationIfPossible(message)
    }

    /// Advances to the next Aerial.
    /// - Parameters:
    ///   - isUserInitiated: If true, clears error state beforehand and posts notifications on failure.
    ///   - logContext: Context string for error logging (e.g., "Next Aerial" or "Scheduled rotation").
    private func performNextAerial(isUserInitiated: Bool, logContext: String) async -> Result<AerialEngine.Report, Error> {
        guard !ui.isBusy else { return .failure(NextAerialError.busy) }

        ui.isBusy = true
        if isUserInitiated {
            ui.lastErrorMessage = nil
            ui.statusLine = "Applying next Aerial…"
        }
        defer { ui.isBusy = false }

        do {
            let report = try await rotationCoordinator.next(settings: settingsStore.settings)
            let displayName = await catalogPresentation.assetDisplayName(for: report.chosenAssetID) ?? report.chosenAssetID
            ui.statusLine = displayName
            await rotationCoordinator.notifyStateChanged()
            return .success(report)
        } catch {
            let message = error.localizedDescription
            ui.lastErrorMessage = message
            ui.statusLine = "Error: \(message)"
            logger.error("\(logContext) failed: \(message, privacy: .public)")
            if isUserInitiated {
                scheduleErrorNotificationIfPossible(message)
            }
            return .failure(error)
        }
    }

    private func runUserInitiatedExcludedAerialCleanup() async {
        guard !ui.isCleaningExcludedAerials else { return }

        ui.isCleaningExcludedAerials = true
        ui.lastErrorMessage = nil
        ui.statusLine = "Cleaning excluded Aerials…"
        defer { ui.isCleaningExcludedAerials = false }

        do {
            let report = try await excludedAerialsCleanupCoordinator.cleanNow(settings: settingsStore.settings)
            if !report.failures.isEmpty {
                let message = "Cleaned: removed \(report.removedCount) file(s), failed \(report.failures.count)."
                ui.lastErrorMessage = message
                ui.statusLine = "Error: \(message)"
                logger.error("Clean Now failed for some files: \(message, privacy: .public)")
                scheduleErrorNotificationIfPossible(message)
            } else if report.removedCount == 0 {
                ui.statusLine = "No excluded files to remove."
            } else {
                ui.statusLine = "Removed \(report.removedCount) excluded file(s)."
            }
        } catch {
            await handleUserInitiatedError(error, logContext: "Clean Now")
        }
    }

    private func scheduleErrorNotificationIfPossible(_ message: String) {
        notificationCoordinator.postErrorNotificationAndRefreshStatusIfPossible(message) { [weak ui] status in
            ui?.notificationAuthorizationStatus = status
        }
    }
}

