import Foundation
import os

/// Owns the excluded-aerial auto-cleanup loop: sleep until due → trigger cleanup.
///
/// Designed to be energy-efficient: it does *not* wake periodically; it sleeps until the next due date,
/// and fully hibernates (no scheduled wakeups) when the system sleeps or screens turn off.
actor ExcludedAerialsCleanupController: Sendable {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "ExcludedAerialsCleanupController")

    private static let cleanupIntervalSeconds: TimeInterval = 60 * 60 * 24
    private static let failureBackoffSeconds: TimeInterval = 60 * 60

    private let stateStore: any ExcludedAerialsCleanupStateStoring
    private let onDue: @Sendable () async -> Bool
    private let now: @Sendable () -> Date
    private let sleepNanoseconds: @Sendable (UInt64) async throws -> Void

    private var settings: AppSettings

    private var nextDueOverride: Date?

    // Hibernation state.
    private var isHibernating: Bool = false
    private var remainingTimeUntilNextDue: TimeInterval?
    private var task: Task<Void, Never>?

    init(
        stateStore: any ExcludedAerialsCleanupStateStoring,
        settings: AppSettings,
        onDue: @escaping @Sendable () async -> Bool,
        now: @escaping @Sendable () -> Date = Date.init,
        sleepNanoseconds: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.stateStore = stateStore
        self.settings = settings
        self.onDue = onDue
        self.now = now
        self.sleepNanoseconds = sleepNanoseconds
    }

    func start() {
        guard !isHibernating else { return }
        guard task == nil else { return }
        guard settings.isExcludedAerialCleanupEnabled else { return }

        task = Task { [weak self] in
            // Avoid a strong self-reference that would keep this controller alive forever
            // if its owner is released (important for unit tests that create many AppStates).
            while let self, !Task.isCancelled {
                let nanos = await self.nextSleepNanosecondsForLoop()
                if Task.isCancelled { return }
                await self.sleepForLoop(nanoseconds: nanos)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func updateSettings(_ newSettings: AppSettings) async {
        let wasEnabled = settings.isExcludedAerialCleanupEnabled
        settings = newSettings
        nextDueOverride = nil

        let isEnabled = newSettings.isExcludedAerialCleanupEnabled
        if isEnabled, !wasEnabled {
            // First run should be ~24h after enabling (not immediate).
            await stateStore.setAutoCleanupEnabledSince(now())
            // Reset last-run timestamp so re-enabling always waits ~24h before the next auto-run.
            await stateStore.setLastAutoCleanupRunDate(nil)
        }

        if !isEnabled {
            stop()
            return
        }

        // If we're hibernating, do not restart scheduling; we'll resume on wake/screen-on.
        guard !isHibernating else { return }

        if task == nil {
            start()
        } else {
            restart()
        }
    }

    /// Internal: exposed for unit tests via `@testable import`.
    func runCheckOnce() async {
        guard !isHibernating else { return }
        guard settings.isExcludedAerialCleanupEnabled else { return }

        let currentNow = now()
        guard let dueDate = await computeNextDueDate(now: currentNow) else { return }

        guard currentNow >= dueDate else { return }

        nextDueOverride = nil

        logger.info("Excluded Aerial cleanup: due, triggering cleanup.")
        let success = await onDue()

        if success {
            await stateStore.setLastAutoCleanupRunDate(currentNow)
            nextDueOverride = currentNow.addingTimeInterval(Self.cleanupIntervalSeconds)
        } else {
            nextDueOverride = currentNow.addingTimeInterval(Self.failureBackoffSeconds)
        }
    }

    // MARK: - Hibernation

    func hibernate() async {
        guard !isHibernating else { return }

        let currentNow = now()
        if let next = await computeNextDueDate(now: currentNow) {
            remainingTimeUntilNextDue = next.timeIntervalSince(currentNow)
        } else {
            remainingTimeUntilNextDue = nil
        }
        isHibernating = true

        stop()
        logger.info("ExcludedAerialsCleanupController hibernated with remainingTimeUntilNextDue=\(String(describing: self.remainingTimeUntilNextDue), privacy: .public)")
    }

    func resume() async {
        guard isHibernating else { return }

        isHibernating = false
        let currentNow = now()
        let remaining = remainingTimeUntilNextDue
        remainingTimeUntilNextDue = nil

        guard settings.isExcludedAerialCleanupEnabled else { return }

        if let remaining, remaining <= 0 {
            // Timer went off during sleep; run once immediately on wake.
            nextDueOverride = nil
            start()
            let success = await onDue()
            if success {
                await stateStore.setLastAutoCleanupRunDate(currentNow)
                nextDueOverride = currentNow.addingTimeInterval(Self.cleanupIntervalSeconds)
            } else {
                nextDueOverride = currentNow.addingTimeInterval(Self.failureBackoffSeconds)
            }
            return
        }

        if let remaining {
            nextDueOverride = currentNow.addingTimeInterval(max(1, remaining))
        } else {
            nextDueOverride = nil
        }
        start()
    }

    // MARK: - Loop

    private func restart() {
        guard task != nil else { return }
        stop()
        start()
    }

    private func nextSleepNanosecondsForLoop() async -> UInt64 {
        await runCheckOnce()

        guard let nextDate = await nextScheduledCleanupDate() else {
            // Disabled. Sleep long; `updateSettings` cancels/restarts for responsiveness.
            return Constants.oneHourNanoseconds
        }

        let seconds = max(1, nextDate.timeIntervalSince(now()))
        return RotationController.sleepNanosecondsClamped(seconds: seconds)
    }

    private func sleepForLoop(nanoseconds: UInt64) async {
        try? await sleepNanoseconds(nanoseconds)
    }

    private func nextScheduledCleanupDate() async -> Date? {
        let currentNow = now()
        if isHibernating, let remainingTimeUntilNextDue {
            return currentNow.addingTimeInterval(remainingTimeUntilNextDue)
        }
        return await computeNextDueDate(now: currentNow)
    }

    private func computeNextDueDate(now: Date) async -> Date? {
        guard settings.isExcludedAerialCleanupEnabled else { return nil }

        if let nextDueOverride {
            return nextDueOverride
        }

        let lastAutoRun = await stateStore.getLastAutoCleanupRunDate()
        let enabledSince = await stateStore.getAutoCleanupEnabledSince()

        // First run should be ~24h after enabling; if no last run is present, use enable time as base.
        let base = lastAutoRun ?? enabledSince ?? now
        return base.addingTimeInterval(Self.cleanupIntervalSeconds)
    }
}


