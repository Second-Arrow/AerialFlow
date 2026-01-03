import Foundation
import Testing
import KeyboardShortcuts
@testable import AerialFlow

/// `HotkeyBinding` is `Sendable`, but this test fake has internal mutable state guarded by `NSLock`,
/// so we use `@unchecked Sendable` to silence strict Swift 6 Sendable checking.
private final class FakeHotkeyBinder: HotkeyBinding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var registeredNames: [KeyboardShortcuts.Name] = []
    private var handlers: [KeyboardShortcuts.Name: @Sendable () -> Void] = [:]

    func onKeyUp(for name: KeyboardShortcuts.Name, action: @escaping @Sendable () -> Void) {
        lock.lock()
        registeredNames.append(name)
        handlers[name] = action
        lock.unlock()
    }

    func trigger(_ name: KeyboardShortcuts.Name) {
        lock.lock()
        let handler = handlers[name]
        lock.unlock()
        handler?()
    }
}

/// `ScreensaverLaunching` is `Sendable`, but this test fake has internal mutable state guarded by `NSLock`,
/// so we use `@unchecked Sendable` to silence strict Swift 6 Sendable checking.
private final class FakeScreensaverLauncher: ScreensaverLaunching, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var startCallCount: Int = 0

    func start() throws {
        lock.lock()
        startCallCount += 1
        lock.unlock()
    }
}

struct AppStateHotkeyBindingTests {
    enum TestError: Error {
        case couldNotCreateUserDefaultsSuite
    }

    @Test func testInit_registersAllHotkeyHandlers() async throws {
        let suiteName = "AerialFlowTests.AppStateHotkeys.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let binder = FakeHotkeyBinder()
        let launcher = FakeScreensaverLauncher()

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(
                userDefaults: defaultsForMainActor,
                screensaverLauncher: launcher,
                hotkeyBinder: binder
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        let names = Set(binder.registeredNames)
        #expect(names.contains(.nextAerial))
        #expect(names.contains(.togglePause))
        #expect(names.contains(.goToScreensaver))
        #expect(names.count == 3)
    }

    @Test func testGoToScreensaverHotkey_invokesLauncher() async throws {
        let suiteName = "AerialFlowTests.AppStateGoToScreensaver.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let binder = FakeHotkeyBinder()
        let launcher = FakeScreensaverLauncher()

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(
                userDefaults: defaultsForMainActor,
                screensaverLauncher: launcher,
                hotkeyBinder: binder
            )
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        _ = state

        binder.trigger(.goToScreensaver)
        // The handler schedules work onto MainActor; wait briefly for it to run.
        for _ in 0..<50 {
            if launcher.startCallCount == 1 { break }
            try? await Task.sleep(nanoseconds: 2_000_000) // 2ms
        }

        #expect(launcher.startCallCount == 1)
    }
}


