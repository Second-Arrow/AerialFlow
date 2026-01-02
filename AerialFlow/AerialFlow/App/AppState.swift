import Combine
import Foundation

@MainActor
final class AppState: ObservableObject {
    private let userDefaults: UserDefaults
    private let isPausedKey = "AerialFlow.isPaused"

    @Published private(set) var isPaused: Bool

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isPaused = userDefaults.bool(forKey: isPausedKey)
    }

    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        isPaused = paused
        userDefaults.set(paused, forKey: isPausedKey)
    }

    func togglePaused() {
        setPaused(!isPaused)
    }
}

