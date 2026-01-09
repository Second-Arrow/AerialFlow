import Foundation
import Testing
@testable import AerialFlow

private actor RecordingBrightnessStore: AerialBrightnessStoring {
    private(set) var precomputeCallCount: Int = 0
    private(set) var lastPrecomputeAssetIDs: [String] = []
    private(set) var didObserveCancellation: Bool = false

    /// If set, `precompute` will stay busy for at least this duration unless cancelled.
    private let blockDurationNanoseconds: UInt64?

    init(blockDurationNanoseconds: UInt64? = nil) {
        self.blockDurationNanoseconds = blockDurationNanoseconds
    }

    func brightness(for asset: AerialAsset, timeout: TimeInterval) async throws -> Double {
        _ = asset
        _ = timeout
        return 0.5
    }

    func isDark(assetID: String, threshold: Double) async -> Bool? {
        _ = assetID
        _ = threshold
        return nil
    }

    func precompute(assets: [AerialAsset], timeout: TimeInterval, maxConcurrency: Int) async {
        precomputeCallCount += 1
        lastPrecomputeAssetIDs = assets.map(\.id)
        _ = timeout
        _ = maxConcurrency

        guard let blockDurationNanoseconds else { return }

        let deadline = DispatchTime.now().uptimeNanoseconds + blockDurationNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if Task.isCancelled {
                didObserveCancellation = true
                return
            }
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
        }
    }
}

private actor SequencedCatalog: AerialCataloging {
    enum Step: Sendable {
        case sleep(nanoseconds: UInt64)
        case returns(AerialCatalog.Snapshot)
    }

    private var steps: [Step]
    private(set) var loadCallCount: Int = 0

    init(steps: [Step]) {
        self.steps = steps
    }

    func loadSnapshot() async throws -> AerialCatalog.Snapshot {
        loadCallCount += 1
        guard !steps.isEmpty else {
            return AerialCatalog.Snapshot(assets: [], categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)
        }

        let next = steps.removeFirst()
        switch next {
        case .sleep(let nanoseconds):
            try await Task.sleep(nanoseconds: nanoseconds)
            // If we weren't cancelled, fall through to an empty snapshot.
            return AerialCatalog.Snapshot(assets: [], categories: [], fileURL: URL(fileURLWithPath: "/dev/null"), fileModificationDate: nil)
        case .returns(let snapshot):
            return snapshot
        }
    }
}

private func eventually(
    timeoutNanoseconds: UInt64,
    pollEveryNanoseconds: UInt64 = 20_000_000, // 20ms
    _ condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
    while DispatchTime.now().uptimeNanoseconds < deadline {
        if await condition() { return true }
        try? await Task.sleep(nanoseconds: pollEveryNanoseconds)
    }
    return await condition()
}

struct BrightnessPrecomputeCoordinatorTests {
    @Test func testStart_triggersPrecomputeAfterCatalogLoad() async {
        let assets = [
            AerialAsset(id: "a", categories: ["c1"], urlVariants: [:]),
            AerialAsset(id: "b", categories: ["c1"], urlVariants: [:])
        ]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: [],
            fileURL: URL(fileURLWithPath: "/tmp/test-entries.json"),
            fileModificationDate: nil
        )

        let catalog = SequencedCatalog(steps: [.returns(snapshot)])
        let store = RecordingBrightnessStore()

        let coordinator = await MainActor.run {
            BrightnessPrecomputeCoordinator(catalog: catalog, store: store)
        }
        await MainActor.run {
            coordinator.start()
        }

        let didPrecompute = await eventually(timeoutNanoseconds: 2_000_000_000) {
            await store.precomputeCallCount == 1
        }
        #expect(didPrecompute)
        #expect(await store.lastPrecomputeAssetIDs == ["a", "b"])
    }

    @Test func testStartTwice_cancelsPreviousTask_andOnlyPrecomputesOnce() async {
        let assets = [AerialAsset(id: "a", categories: ["c1"], urlVariants: [:])]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: [],
            fileURL: URL(fileURLWithPath: "/tmp/test-entries.json"),
            fileModificationDate: nil
        )

        // First load sleeps "forever" (or until cancelled). Second load returns immediately.
        let catalog = SequencedCatalog(steps: [
            .sleep(nanoseconds: 60_000_000_000), // 60s
            .returns(snapshot)
        ])
        let store = RecordingBrightnessStore()

        let coordinator = await MainActor.run {
            BrightnessPrecomputeCoordinator(catalog: catalog, store: store)
        }

        await MainActor.run { coordinator.start() }
        // Wait until the first detached task has actually entered `loadSnapshot` so the cancellation is deterministic.
        let didStartFirstLoad = await eventually(timeoutNanoseconds: 1_000_000_000) {
            await catalog.loadCallCount >= 1
        }
        #expect(didStartFirstLoad)

        await MainActor.run { coordinator.start() }

        let didPrecompute = await eventually(timeoutNanoseconds: 2_000_000_000) {
            await store.precomputeCallCount == 1
        }
        #expect(didPrecompute)
        #expect(await catalog.loadCallCount == 2)
    }

    @Test func testStop_cancelsInFlightPrecompute() async {
        let assets = [AerialAsset(id: "a", categories: ["c1"], urlVariants: [:])]
        let snapshot = AerialCatalog.Snapshot(
            assets: assets,
            categories: [],
            fileURL: URL(fileURLWithPath: "/tmp/test-entries.json"),
            fileModificationDate: nil
        )

        let catalog = SequencedCatalog(steps: [.returns(snapshot)])
        let store = RecordingBrightnessStore(blockDurationNanoseconds: 2_000_000_000) // 2s

        let coordinator = await MainActor.run {
            BrightnessPrecomputeCoordinator(catalog: catalog, store: store)
        }
        await MainActor.run { coordinator.start() }

        let didStart = await eventually(timeoutNanoseconds: 1_000_000_000) {
            await store.precomputeCallCount == 1
        }
        #expect(didStart)

        await MainActor.run { coordinator.stop() }

        let didCancel = await eventually(timeoutNanoseconds: 2_000_000_000) {
            await store.didObserveCancellation
        }
        #expect(didCancel)
    }
}

