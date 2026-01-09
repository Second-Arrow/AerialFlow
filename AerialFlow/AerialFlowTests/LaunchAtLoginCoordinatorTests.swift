import Testing
import Foundation
@testable import AerialFlow

private final class FakeLaunchAtLoginManager: LaunchAtLoginManaging, @unchecked Sendable {
    enum FakeError: Error, LocalizedError {
        case failed
        var errorDescription: String? { "Registration failed" }
    }

    var statusValue: LaunchAtLoginStatus
    var registerError: Error?
    var unregisterError: Error?

    /// If set, `register()` will update `statusValue` to this value (defaults to `.enabled`).
    var statusAfterRegister: LaunchAtLoginStatus = .enabled

    init(status: LaunchAtLoginStatus = .disabled) {
        self.statusValue = status
    }

    func status() -> LaunchAtLoginStatus { statusValue }

    func register() throws {
        if let registerError { throw registerError }
        statusValue = statusAfterRegister
    }

    func unregister() throws {
        if let unregisterError { throw unregisterError }
        statusValue = .disabled
    }
}

struct LaunchAtLoginCoordinatorTests {
    @Test func testEnable_success_setsEnabled_andNoError() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        manager.statusAfterRegister = .enabled
        let coordinator = LaunchAtLoginCoordinator(manager: manager)

        let update = coordinator.setLaunchAtLoginEnabled(true, previousSettingValue: false)

        #expect(update.launchAtLoginEnabled == true)
        #expect(update.errorMessage == nil)
    }

    @Test func testEnable_failure_reverts_andReturnsError() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        manager.registerError = FakeLaunchAtLoginManager.FakeError.failed
        let coordinator = LaunchAtLoginCoordinator(manager: manager)

        let update = coordinator.setLaunchAtLoginEnabled(true, previousSettingValue: false)

        #expect(update.launchAtLoginEnabled == false)
        #expect(update.errorMessage != nil)
    }

    @Test func testEnable_requiresApproval_reverts_andReturnsApprovalMessage() {
        let manager = FakeLaunchAtLoginManager(status: .disabled)
        manager.statusAfterRegister = .requiresApproval
        let coordinator = LaunchAtLoginCoordinator(manager: manager)

        let update = coordinator.setLaunchAtLoginEnabled(true, previousSettingValue: false)

        #expect(update.launchAtLoginEnabled == false)
        #expect(update.errorMessage == "macOS requires approval. Enable AerialFlow in System Settings > General > Login Items.")
    }
}

