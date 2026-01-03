import Foundation
import Testing
@testable import AerialFlow

private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
    enum FakeError: Error, LocalizedError {
        case failed

        var errorDescription: String? { "Registration failed" }
    }

    private(set) var statusValue: LaunchAtLoginStatus
    var registerError: Error?
    var unregisterError: Error?

    init(status: LaunchAtLoginStatus = .disabled) {
        self.statusValue = status
    }

    func status() -> LaunchAtLoginStatus { statusValue }

    func register() throws {
        if let registerError { throw registerError }
        statusValue = .enabled
    }

    func unregister() throws {
        if let unregisterError { throw unregisterError }
        statusValue = .disabled
    }
}

struct AppStateLaunchAtLoginTests {
    enum TestError: Error {
        case couldNotCreateUserDefaultsSuite
    }

    @Test func testEnableLaunchAtLogin_success_persistsAndClearsError() async throws {
        let suiteName = "AerialFlowTests.AppStateLaunchAtLogin.Success.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = FakeLaunchAtLoginManager(status: .disabled)

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(
                userDefaults: defaultsForMainActor,
                launchAtLoginManager: manager
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }

        await MainActor.run {
            state.setLaunchAtLoginEnabled(true)
        }

        let enabled = await MainActor.run { state.settings.launchAtLogin }
        let message = await MainActor.run { state.launchAtLoginErrorMessage }
        #expect(enabled == true)
        #expect(message == nil)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.launchAtLogin == true)
    }

    @Test func testEnableLaunchAtLogin_failure_revertsAndShowsError() async throws {
        let suiteName = "AerialFlowTests.AppStateLaunchAtLogin.Failure.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = FakeLaunchAtLoginManager(status: .disabled)
        manager.registerError = FakeLaunchAtLoginManager.FakeError.failed

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(
                userDefaults: defaultsForMainActor,
                launchAtLoginManager: manager
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }

        await MainActor.run {
            state.setLaunchAtLoginEnabled(true)
        }

        let enabled = await MainActor.run { state.settings.launchAtLogin }
        let message = await MainActor.run { state.launchAtLoginErrorMessage }
        #expect(enabled == false)
        #expect(message != nil)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.launchAtLogin == false)
    }
}


