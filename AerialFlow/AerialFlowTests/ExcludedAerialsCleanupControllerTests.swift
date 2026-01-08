import Foundation
import Testing
@testable import AerialFlow

struct ExcludedAerialsCleanupControllerTests {
    /// Thread-safe mutable clock for `@Sendable () -> Date`.
    final class TestNow: @unchecked Sendable {
        private let lock = NSLock()
        private var _value: Date

        init(_ value: Date) { self._value = value }

        func set(_ newValue: Date) {
            lock.lock()
            _value = newValue
            lock.unlock()
        }

        func get() -> Date {
            lock.lock()
            let v = _value
            lock.unlock()
            return v
        }
    }

    @Test func testNotDue_doesNotInvokeOnDue() async {
        let nowBox = TestNow(Date(timeIntervalSince1970: 1_000))
        let store = FakeExcludedAerialsCleanupStateStore(
            autoCleanupEnabledSince: nowBox.get(), // just enabled
            lastAutoCleanupRunDate: nil
        )

        let counter = Counter()
        let controller = ExcludedAerialsCleanupController(
            stateStore: store,
            settings: AppSettings(isExcludedAerialCleanupEnabled: true),
            onDue: {
                await counter.increment()
                return true
            },
            now: { nowBox.get() }
        )

        await controller.runCheckOnce()
        #expect(await counter.value == 0)
    }

    @Test func testDue_invokesOnDue_andStoresLastAutoRun() async {
        let now = Date(timeIntervalSince1970: 10_000)
        let enabledSince = now.addingTimeInterval(-(60 * 60 * 24 + 1))
        let store = FakeExcludedAerialsCleanupStateStore(
            autoCleanupEnabledSince: enabledSince,
            lastAutoCleanupRunDate: nil
        )

        let counter = Counter()
        let controller = ExcludedAerialsCleanupController(
            stateStore: store,
            settings: AppSettings(isExcludedAerialCleanupEnabled: true),
            onDue: {
                await counter.increment()
                return true
            },
            now: { now }
        )

        await controller.runCheckOnce()
        #expect(await counter.value == 1)
        #expect(await store.getLastAutoCleanupRunDate() == now)
    }

    @Test func testHibernate_thenWake_runsIfDuePassedDuringSleep() async {
        let nowBox = TestNow(Date(timeIntervalSince1970: 1_000))
        let enabledSince = nowBox.get().addingTimeInterval(-60 * 60 * 24)
        let store = FakeExcludedAerialsCleanupStateStore(
            autoCleanupEnabledSince: enabledSince,
            lastAutoCleanupRunDate: nil
        )

        let counter = Counter()
        let controller = ExcludedAerialsCleanupController(
            stateStore: store,
            settings: AppSettings(isExcludedAerialCleanupEnabled: true),
            onDue: {
                await counter.increment()
                return true
            },
            now: { nowBox.get() }
        )

        // At time = enabledSince + 24h, cleanup is due. Hibernate will store remaining time (<= 0).
        await controller.hibernate()
        // Simulate wake slightly later.
        nowBox.set(nowBox.get().addingTimeInterval(10))
        await controller.resume()

        #expect(await counter.value == 1)
        #expect(await store.getLastAutoCleanupRunDate() == nowBox.get())
    }

    @Test func testUpdateSettings_enablingSetsEnabledSince_andDelaysFirstRun() async {
        let now = Date(timeIntervalSince1970: 2_000)
        let store = FakeExcludedAerialsCleanupStateStore()
        let counter = Counter()

        let controller = ExcludedAerialsCleanupController(
            stateStore: store,
            settings: AppSettings(isExcludedAerialCleanupEnabled: false),
            onDue: {
                await counter.increment()
                return true
            },
            now: { now }
        )

        await controller.updateSettings(AppSettings(isExcludedAerialCleanupEnabled: true))
        #expect(await store.getAutoCleanupEnabledSince() == now)

        await controller.runCheckOnce()
        #expect(await counter.value == 0)
    }
}


