import Combine
import Foundation
import Sparkle

/// SwiftUI-friendly wrapper around Sparkle's updater state.
final class UpdaterViewModel: ObservableObject {
    @Published var canCheckForUpdates: Bool = false

    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    @Published var updateCheckInterval: TimeInterval {
        didSet {
            controller.updater.updateCheckInterval = updateCheckInterval
        }
    }

    private let controller: SPUStandardUpdaterController
    private var subscriptions = Set<AnyCancellable>()

    init(controller: SPUStandardUpdaterController) {
        self.controller = controller
        self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        self.updateCheckInterval = controller.updater.updateCheckInterval

        controller.updater
            .publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
            .store(in: &subscriptions)

        controller.updater
            .publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, value != self.automaticallyChecksForUpdates else { return }
                self.automaticallyChecksForUpdates = value
            }
            .store(in: &subscriptions)

        controller.updater
            .publisher(for: \.updateCheckInterval)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, value != self.updateCheckInterval else { return }
                self.updateCheckInterval = value
            }
            .store(in: &subscriptions)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}


