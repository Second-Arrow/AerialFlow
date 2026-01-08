import Foundation
import Testing
@testable import AerialFlow

struct RotationControllerTests {
    @Test func testDue_invokesOnDue() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastChange = now.addingTimeInterval(-600)
        let store = FakeEngineStateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
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
        let store = FakeEngineStateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
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
        let store = FakeEngineStateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            settings: AppSettings(isRotationEnabled: false, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.runCheckOnce()
        #expect(await counter.value == 0)
    }

    @Test func testLastChangeNil_waitsFullInterval() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let store = FakeEngineStateStore(lastChange: nil)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            settings: AppSettings(isRotationEnabled: true, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.runCheckOnce()
        #expect(await counter.value == 0)

        let next = await controller.nextScheduledChangeDate()
        #expect(next == now.addingTimeInterval(600))
    }

    @Test func testHibernate_storesRemainingTime_andStopsRunningChecks() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastChange = now.addingTimeInterval(-100)
        let store = FakeEngineStateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            settings: AppSettings(isRotationEnabled: true, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.hibernate()

        // While hibernating, checks should be ignored.
        await controller.runCheckOnce()
        #expect(await counter.value == 0)

        // Next date should be projected based on stored remaining time.
        let next = await controller.nextScheduledChangeDate()
        #expect(next == now.addingTimeInterval(500))
    }

    @Test func testResume_useOriginalTimeLeft_usesStoredRemainingTime() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastChange = now.addingTimeInterval(-100)
        let store = FakeEngineStateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            settings: AppSettings(isRotationEnabled: true, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.hibernate()
        await controller.resume(behavior: .useOriginalTimeLeft)

        // Not due yet with 500 seconds remaining.
        await controller.runCheckOnce()
        #expect(await counter.value == 0)
    }

    @Test func testResume_restartRotationTimer_restartsIntervalFromWake() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastChange = now.addingTimeInterval(-590)
        let store = FakeEngineStateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            settings: AppSettings(isRotationEnabled: true, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.hibernate()
        await controller.resume(behavior: .restartRotationTimer)

        // Would have been due soon based on lastChange, but restart should delay it.
        await controller.runCheckOnce()
        #expect(await counter.value == 0)
        let next = await controller.nextScheduledChangeDate()
        #expect(next == now.addingTimeInterval(600))
    }

    @Test func testResume_immediatelyGoToNextAerial_triggersOnDue() async {
        let now = Date(timeIntervalSince1970: 1_000)
        let lastChange = now.addingTimeInterval(-100)
        let store = FakeEngineStateStore(lastChange: lastChange)

        let counter = Counter()
        let controller = RotationController(
            stateStore: store,
            settings: AppSettings(isRotationEnabled: true, rotationIntervalSeconds: 600),
            onDue: { await counter.increment() },
            now: { now }
        )

        await controller.hibernate()
        await controller.resume(behavior: .immediatelyGoToNextAerial)

        #expect(await counter.value == 1)
    }

    @Test func testSleepNanosecondsClamped_doesNotOverflow_forHugeIntervals() async {
        // A value that would overflow when multiplied by 1e9 and converted to UInt64.
        let hugeSeconds = TimeInterval(Double(UInt64.max) / 1_000_000_000) * 10
        let nanos = RotationController.sleepNanosecondsClamped(seconds: hugeSeconds)
        #expect(nanos == UInt64.max)
    }
}

