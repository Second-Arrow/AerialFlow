import Foundation

/// Owns rotation scheduling (via `RotationController`) and provides rotation operations.
final class RotationCoordinator: Sendable {
    private let controller: RotationController
    private let engine: AerialEngine

    init(
        stateStore: any AerialEngineStateStore,
        engine: AerialEngine,
        initialSettings: AppSettings,
        onDue: @escaping @Sendable () async -> Void
    ) {
        self.engine = engine
        self.controller = RotationController(
            stateStore: stateStore,
            settings: initialSettings,
            onDue: onDue
        )
    }

    func start() async {
        await controller.start()
    }

    func updateSettings(_ settings: AppSettings) async {
        await controller.updateSettings(settings)
    }

    func notifyStateChanged() async {
        await controller.notifyStateChanged()
    }

    func nextScheduledChangeDate() async -> Date? {
        await controller.nextScheduledChangeDate()
    }

    func hibernate() async {
        await controller.hibernate()
    }

    func resume(behavior: AppSettings.SleepResumeBehavior) async {
        await controller.resume(behavior: behavior)
    }

    func next(settings: AppSettings) async throws -> AerialEngine.Report {
        try await engine.next(settings: settings)
    }

    func nextInSubcategory(settings: AppSettings, subcategoryID: String) async throws -> AerialEngine.Report {
        try await engine.nextInSubcategory(settings: settings, subcategoryID: subcategoryID)
    }
}

