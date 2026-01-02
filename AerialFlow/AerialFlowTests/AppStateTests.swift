//
//  AppStateTests.swift
//  AerialFlowTests
//
//  Created by Floris Robbemont on 02/01/2026.
//

import Testing
import Foundation
@testable import AerialFlow

struct AppStateTests {
    enum TestError: Error {
        case couldNotCreateUserDefaultsSuite
    }

    @Test func testTogglePaused_flipsState() async throws {
        let suiteName = "AerialFlowTests.AppState.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }

        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = await MainActor.run {
            // Safe: we successfully created this suite above.
            AppState(userDefaults: UserDefaults(suiteName: suiteName)!)
        }
        let initial = await MainActor.run { state.isPaused }

        await MainActor.run { state.setRotationEnabled(state.isPaused) }
        let toggled = await MainActor.run { state.isPaused }

        #expect(toggled != initial)
    }

    @Test func testTogglePaused_twice_returnsToOriginal() async throws {
        let suiteName = "AerialFlowTests.AppState.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }

        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = await MainActor.run {
            // Safe: we successfully created this suite above.
            AppState(userDefaults: UserDefaults(suiteName: suiteName)!)
        }
        let initial = await MainActor.run { state.isPaused }

        await MainActor.run {
            state.setRotationEnabled(state.isPaused)
            state.setRotationEnabled(state.isPaused)
        }
        let final = await MainActor.run { state.isPaused }

        #expect(final == initial)
    }
}

