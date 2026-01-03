import Foundation
import Testing
@testable import AerialFlow

struct RotationControllerTests {
    private actor StateStore: AerialEngineStateStore {
        private var lastChange: Date?

        init(lastChange: Date?) {
            self.lastChange = lastChange
        }

        func getLastAssetID() async -> String? { nil }
        func setLastAssetID(_ id: String?) async { _ = id }
        func getLastChange() async -> Date? { lastChange }
        func setLastChange(_ date: Date?) async { lastChange = date }
    }

    private struct AlwaysRunGuard: RunGuarding {
        func shouldRunNow(settings: any RunGuardSettings) -> Bool {
            _ = settings
            return true
        }
    }

    private struct NeverRunGuard: RunGuarding {
        func shouldRunNow(settings: any RunGuardSettings) -> Bool {
            _ = settings
            return false
        }
    }

    @Test func testDue_invokesOnDue() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastChange = now.addingTimeInterval(-600)
        let store = StateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            runGuard: AlwaysRunGuard(),
            settings: AppSettings(isRotationEnabled: true, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.runCheckOnce()
        #expect(await counter.value == 1)
    }

    @Test func testNotDue_doesNotInvokeOnDue() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastChange = now.addingTimeInterval(-100)
        let store = StateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            runGuard: AlwaysRunGuard(),
            settings: AppSettings(isRotationEnabled: true, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.runCheckOnce()
        #expect(await counter.value == 0)
    }

    @Test func testRotationDisabled_doesNotInvokeOnDue() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastChange = now.addingTimeInterval(-10_000)
        let store = StateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            runGuard: AlwaysRunGuard(),
            settings: AppSettings(isRotationEnabled: false, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.runCheckOnce()
        #expect(await counter.value == 0)
    }

    @Test func testRunGuardFalse_doesNotInvokeOnDue() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastChange = now.addingTimeInterval(-10_000)
        let store = StateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            runGuard: NeverRunGuard(),
            settings: AppSettings(isRotationEnabled: true, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.runCheckOnce()
        #expect(await counter.value == 0)

        // Due-but-blocked => scheduler skips until next full interval.
        let next = await controller.nextScheduledChangeDate()
        #expect(next == now.addingTimeInterval(600))
    }

    @Test func testLastChangeNil_waitsFullInterval() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = StateStore(lastChange: nil)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            runGuard: AlwaysRunGuard(),
            settings: AppSettings(isRotationEnabled: true, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.runCheckOnce()
        #expect(await counter.value == 0)

        let next = await controller.nextScheduledChangeDate()
        #expect(next == now.addingTimeInterval(600))
    }
}

private actor Counter {
    private(set) var value: Int = 0
    func increment() { value += 1 }
}


