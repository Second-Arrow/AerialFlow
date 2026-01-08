import Foundation
import os

/// Owns the scheduled rotation loop: sleep until due → trigger rotation.
///
/// Designed to be energy-efficient: it does *not* wake every minute; instead it sleeps until the next due date.
actor RotationController: Sendable {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "RotationController")

    private let stateStore: any AerialEngineStateStore
    private let onDue: @Sendable () async -> Void
    private let now: @Sendable () -> Date
    private let sleepNanoseconds: @Sendable (UInt64) async throws -> Void

    private var settings: AppSettings
    private var nextDueOverride: Date?

    // Hibernation state: when screens are off or the system sleeps, we store remaining time and stop scheduling entirely.
    private var isHibernating: Bool = false
    private var remainingTimeUntilNextDue: TimeInterval?
    private var task: Task<Void, Never>?

    /// Internal for unit tests: safely converts a seconds duration into nanoseconds for `Task.sleep`.
    /// Clamps to avoid `UInt64(...)` overflow traps for extremely large inputs.
    static func sleepNanosecondsClamped(seconds: TimeInterval) -> UInt64 {
        guard seconds.isFinite else { return Constants.oneHourNanoseconds }

        let clampedSeconds = max(1, seconds)
        let nanosDouble = clampedSeconds * 1_000_000_000

        // `UInt64(...)` traps if the value is out of range; clamp first.
        if nanosDouble >= Double(UInt64.max) {
            return UInt64.max
        }
        if nanosDouble <= 0 {
            return 1
        }
        return UInt64(nanosDouble)
    }

    init(
        stateStore: any AerialEngineStateStore,
        settings: AppSettings,
        onDue: @escaping @Sendable () async -> Void,
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

    func updateSettings(_ newSettings: AppSettings) {
        settings = newSettings
        nextDueOverride = nil
        // If we're hibernating, do not restart scheduling; we'll resume on wake/screen-on.
        guard !isHibernating else { return }
        restart()
    }

    /// Call this when an external event changes scheduling state (e.g., user-triggered Next updated lastChange).
    func notifyStateChanged() {
        nextDueOverride = nil
        guard !isHibernating else { return }
        restart()
    }

    func nextScheduledChangeDate() async -> Date? {
        let currentNow = now()
        if isHibernating, let remainingTimeUntilNextDue {
            return currentNow.addingTimeInterval(max(0, remainingTimeUntilNextDue))
        }
        return computeNextScheduledChangeDate(now: currentNow, lastChange: await stateStore.getLastChange())
    }

    /// Internal: exposed for unit tests via `@testable import`.
    func runCheckOnce() async {
        guard !isHibernating else { return }
        guard settings.isRotationEnabled else { return }

        let currentNow = now()
        let intervalSeconds = max(Constants.minimumRotationIntervalSeconds, settings.rotationIntervalSeconds)
        let interval = TimeInterval(intervalSeconds)

        let lastChange = await stateStore.getLastChange()
        guard let dueDate = computeNextScheduledChangeDate(now: currentNow, lastChange: lastChange) else { return }

        // If not due, do nothing.
        guard currentNow >= dueDate else { return }

        // Clear override before running; if it fails, we still back off (override below) to avoid tight retry loops.
        nextDueOverride = nil

        logger.info("Rotation check: rotation is due, triggering scheduled rotation.")
        await onDue()

        // Regardless of success/failure, back off to the next interval boundary to avoid tight loops
        // when `onDue` cannot update lastChange (e.g. errors or the app is busy).
        nextDueOverride = currentNow.addingTimeInterval(interval)
    }

    // MARK: - Hibernation

    /// Enter hibernation: store remaining time until next due rotation and stop scheduling entirely.
    func hibernate() async {
        guard !isHibernating else { return }

        let currentNow = now()
        if let next = computeNextScheduledChangeDate(now: currentNow, lastChange: await stateStore.getLastChange()) {
            remainingTimeUntilNextDue = max(0, next.timeIntervalSince(currentNow))
        } else {
            remainingTimeUntilNextDue = nil
        }
        isHibernating = true

        stop()
        logger.info("RotationController hibernated with remainingTimeUntilNextDue=\(String(describing: self.remainingTimeUntilNextDue), privacy: .public)")
    }

    /// Resume from hibernation using the selected behavior.
    func resume(behavior: AppSettings.SleepResumeBehavior) async {
        guard isHibernating else { return }

        isHibernating = false
        let currentNow = now()
        let intervalSeconds = max(Constants.minimumRotationIntervalSeconds, settings.rotationIntervalSeconds)
        let interval = TimeInterval(intervalSeconds)

        let remaining = remainingTimeUntilNextDue
        remainingTimeUntilNextDue = nil

        switch behavior {
        case .useOriginalTimeLeft:
            if let remaining {
                nextDueOverride = currentNow.addingTimeInterval(max(1, remaining))
            } else {
                nextDueOverride = nil
            }
            logger.info("RotationController resumed (useOriginalTimeLeft) nextDueOverride=\(String(describing: self.nextDueOverride), privacy: .public)")
            start()

        case .restartRotationTimer:
            nextDueOverride = currentNow.addingTimeInterval(interval)
            logger.info("RotationController resumed (restartRotationTimer) nextDueOverride=\(String(describing: self.nextDueOverride), privacy: .public)")
            start()

        case .immediatelyGoToNextAerial:
            guard settings.isRotationEnabled else {
                logger.info("RotationController resumed (immediatelyGoToNextAerial) but rotation is disabled; skipping immediate rotation.")
                start()
                return
            }
            nextDueOverride = nil
            logger.info("RotationController resumed (immediatelyGoToNextAerial) triggering rotation now.")
            start()
            await onDue()
            nextDueOverride = currentNow.addingTimeInterval(interval)
        }
    }

    // MARK: - Loop

    private func restart() {
        guard task != nil else { return }
        stop()
        start()
    }

    private func nextSleepNanosecondsForLoop() async -> UInt64 {
        await runCheckOnce()

        guard let nextDate = await nextScheduledChangeDate() else {
            // Rotation disabled. Sleep long; `updateSettings` cancels/restarts for responsiveness.
            return Constants.oneHourNanoseconds
        }

        let seconds = max(1, nextDate.timeIntervalSince(now()))
        return Self.sleepNanosecondsClamped(seconds: seconds)
    }

    private func sleepForLoop(nanoseconds: UInt64) async {
        try? await sleepNanoseconds(nanoseconds)
    }

    // MARK: - Scheduling math

    private func computeNextScheduledChangeDate(now: Date, lastChange: Date?) -> Date? {
        guard settings.isRotationEnabled else { return nil }

        if let nextDueOverride {
            return nextDueOverride
        }

        let intervalSeconds = max(Constants.minimumRotationIntervalSeconds, settings.rotationIntervalSeconds)
        let interval = TimeInterval(intervalSeconds)

        let dueDate = computeDueDate(now: now, lastChange: lastChange, interval: interval)
        return dueDate
    }

    private func computeDueDate(now: Date, lastChange: Date?, interval: TimeInterval) -> Date {
        // Per spec: if lastChange is missing, treat it as “just changed” and wait a full interval.
        let effectiveLastChange = lastChange ?? now
        return effectiveLastChange.addingTimeInterval(interval)
    }
}


