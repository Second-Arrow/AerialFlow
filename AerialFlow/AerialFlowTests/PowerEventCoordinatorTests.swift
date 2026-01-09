import Testing
@testable import AerialFlow

private actor PowerEventRecorder {
    private(set) var events: [PowerEvent] = []
    func append(_ event: PowerEvent) { events.append(event) }
}

struct PowerEventCoordinatorTests {
    @Test func testStart_forwardsEventsInOrder() async {
        let observer = SequencePowerEventObserver(eventsToEmit: [.willSleep, .didWake])
        let recorder = PowerEventRecorder()

        let coordinator = await MainActor.run {
            PowerEventCoordinator(observer: observer)
        }

        await MainActor.run {
            coordinator.start { event in
                await recorder.append(event)
            }
        }

        // Wait briefly for the coordinator's task to consume the stream.
        for _ in 0..<100 {
            if await recorder.events.count == 2 { break }
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }

        let events = await recorder.events
        #expect(events == [.willSleep, .didWake])
    }
}

