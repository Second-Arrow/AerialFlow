import Foundation
import os

/// Starts a background task that precomputes brightness for catalog assets.
@MainActor
final class BrightnessPrecomputeCoordinator {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "BrightnessPrecompute")

    private let catalog: any AerialCataloging
    private let store: any AerialBrightnessStoring
    private var task: Task<Void, Never>?

    init(catalog: any AerialCataloging, store: any AerialBrightnessStoring) {
        self.catalog = catalog
        self.store = store
    }

    func start() {
        task?.cancel()

        let catalog = self.catalog
        let store = self.store
        let logger = self.logger
        task = Task.detached(priority: .background) {
            guard !Task.isCancelled else { return }
            do {
                let snapshot = try await catalog.loadSnapshot()
                guard !Task.isCancelled else { return }
                await store.precompute(assets: snapshot.assets, timeout: 2, maxConcurrency: 4)
            } catch {
                logger.debug("Brightness precompute skipped: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

