import Foundation
import os

/// Owns the scheduled rotation loop: sleep until due → check gates → trigger rotation.
///
/// Designed to be energy-efficient: it does *not* wake every minute; instead it sleeps until the next due date.
actor RotationController: Sendable {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "RotationController")

    private let stateStore: any AerialEngineStateStore
    private let runGuard: any RunGuarding
    private let onDue: @Sendable () async -> Void
    private let now: @Sendable () -> Date
    private let sleepNanoseconds: @Sendable (UInt64) async throws -> Void

    private var settings: AppSettings
    private var snoozedUntil: Date?
    private var task: Task<Void, Never>?

    init(
        stateStore: any AerialEngineStateStore,
        runGuard: any RunGuarding,
        settings: AppSettings,
        onDue: @escaping @Sendable () async -> Void,
        now: @escaping @Sendable () -> Date = Date.init,
        sleepNanoseconds: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.stateStore = stateStore
        self.runGuard = runGuard
        self.settings = settings
        self.onDue = onDue
        self.now = now
        self.sleepNanoseconds = sleepNanoseconds
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            // `actor` instances are reference types; weak capture avoids accidentally extending lifetime.
            guard let self else { return }
            await self.runLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        snoozedUntil = nil
        restart()
    }

    /// Call this when an external event changes scheduling state (e.g., user-triggered Next updated lastChange).
    func notifyStateChanged() {
        snoozedUntil = nil
        restart()
    }

    func nextScheduledChangeDate() async -> Date? {
        computeNextScheduledChangeDate(now: now(), lastChange: await stateStore.getLastChange())
    }

    /// Internal: exposed for unit tests via `@testable import`.
    func runCheckOnce() async {
        guard settings.isRotationEnabled else { return }

        let currentNow = now()
        let intervalSeconds = max(Constants.minimumRotationIntervalSeconds, settings.rotationIntervalSeconds)
        let interval = TimeInterval(intervalSeconds)

        let lastChange = await stateStore.getLastChange()
        let dueDate = computeDueDate(now: currentNow, lastChange: lastChange, interval: interval)

        // If not due, do nothing.
        guard currentNow >= dueDate else { return }

        if !runGuard.shouldRunNow(settings: settings) {
            // Per spec: when due but blocked, skip this due rotation and wait until the next full interval.
            snoozedUntil = currentNow.addingTimeInterval(interval)
            return
        }

        logger.debug("Scheduled rotation is due; triggering next.")
        await onDue()
    }

    // MARK: - Loop

    private func restart() {
        guard task != nil else { return }
        stop()
        start()
    }

    private func runLoop() async {
        while !Task.isCancelled {
            await runCheckOnce()

            if Task.isCancelled { return }

            guard let nextDate = await nextScheduledChangeDate() else {
                // Rotation disabled. Sleep long; `updateSettings` cancels/restarts for responsiveness.
                try? await sleepNanoseconds(Constants.oneHourNanoseconds)
                continue
            }

            let seconds = max(1, nextDate.timeIntervalSince(now()))
            let nanos = UInt64(seconds * 1_000_000_000)
            try? await sleepNanoseconds(nanos)
        }
    }

    // MARK: - Scheduling math

    private func computeNextScheduledChangeDate(now: Date, lastChange: Date?) -> Date? {
        guard settings.isRotationEnabled else { return nil }
        let intervalSeconds = max(Constants.minimumRotationIntervalSeconds, settings.rotationIntervalSeconds)
        let interval = TimeInterval(intervalSeconds)

        let dueDate = computeDueDate(now: now, lastChange: lastChange, interval: interval)

        if let snoozedUntil {
            return max(dueDate, snoozedUntil)
        }
        return dueDate
    }

    private func computeDueDate(now: Date, lastChange: Date?, interval: TimeInterval) -> Date {
        // Per spec: if lastChange is missing, treat it as “just changed” and wait a full interval.
        let effectiveLastChange = lastChange ?? now
        return effectiveLastChange.addingTimeInterval(interval)
    }
}


