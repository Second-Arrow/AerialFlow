//
//  AerialFlowTests.swift
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

        let state = await MainActor.run { AppState(userDefaults: defaults) }
        let initial = await MainActor.run { state.isPaused }

        await MainActor.run { state.togglePaused() }
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

        let state = await MainActor.run { AppState(userDefaults: defaults) }
        let initial = await MainActor.run { state.isPaused }

        await MainActor.run {
            state.togglePaused()
            state.togglePaused()
        }
        let final = await MainActor.run { state.isPaused }

        #expect(final == initial)
    }
}
