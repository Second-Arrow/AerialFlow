import Foundation
import os

/// Owns excluded-aerial auto-cleanup scheduling and provides manual cleanup operations.
final class ExcludedAerialsCleanupCoordinator: Sendable {
    private let controller: ExcludedAerialsCleanupController
    private let cleaner: ExcludedAerialsCleaner

    init(
        stateStore: any ExcludedAerialsCleanupStateStoring,
        cleaner: ExcludedAerialsCleaner,
        initialSettings: AppSettings,
        settingsProvider: @escaping @Sendable () async -> AppSettings
    ) {
        let logger = Logger(subsystem: Constants.loggerSubsystem, category: "ExcludedAerialsCleanupCoordinator")

        self.cleaner = cleaner
        self.controller = ExcludedAerialsCleanupController(
            stateStore: stateStore,
            settings: initialSettings,
            onDue: {
                let settings = await settingsProvider()
                do {
                    let report = try await cleaner.cleanExcludedMovFiles(settings: settings)
                    if report.failures.isEmpty { return true }
                    logger.error("Scheduled excluded-aerial cleanup had failures: failed=\(report.failures.count, privacy: .public)")
                    return false
                } catch {
                    logger.error("Scheduled excluded-aerial cleanup failed: \(String(describing: error), privacy: .public)")
                    return false
                }
            }
        )
    }

    func startIfEnabled() async {
        await controller.start()
    }

    func updateSettings(_ settings: AppSettings) async {
        await controller.updateSettings(settings)
    }

    func hibernate() async {
        await controller.hibernate()
    }

    func resume() async {
        await controller.resume()
    }

    /// Manual, user-initiated cleanup.
    func cleanNow(settings: AppSettings) async throws -> ExcludedAerialsCleanupReport {
        try await cleaner.cleanExcludedMovFiles(settings: settings)
    }
}

