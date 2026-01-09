import Foundation

/// Listens to system power/screen events and forwards them to provided handlers.
@MainActor
final class PowerEventCoordinator {
    private let observer: any PowerEventObserving
    private var task: Task<Void, Never>?

    init(observer: any PowerEventObserving) {
        self.observer = observer
    }

    func start(onEvent: @escaping @MainActor (PowerEvent) async -> Void) {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            for await event in observer.events() {
                await onEvent(event)
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

