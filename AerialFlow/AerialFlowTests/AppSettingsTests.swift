//
//  AppSettingsTests.swift
//  AerialFlowTests
//
//  Created by Cursor.
//

import Foundation
import Testing
@testable import AerialFlow

struct AppSettingsTests {
    enum TestError: Error {
        case couldNotCreateUserDefaultsSuite
    }

    @Test func testDefaults_areStable() async throws {
        let suiteName = "AerialFlowTests.AppSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let loaded = AppSettings.load(from: defaults)
        #expect(loaded == AppSettings())
    }

    @Test func testQualityPreference_persists() async throws {
        let suiteName = "AerialFlowTests.AppSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.qualityPreference = .prefer4k
        settings.save(to: defaults)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.qualityPreference == .prefer4k)
    }

    @Test func testExcludedCategoryIDs_persists() async throws {
        let suiteName = "AerialFlowTests.AppSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.excludedCategoryIDs = ["Earth", "Underwater"]
        settings.save(to: defaults)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.excludedCategoryIDs == ["Earth", "Underwater"])
    }

    @Test func testRotationEnabled_persists() async throws {
        let suiteName = "AerialFlowTests.AppSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.isRotationEnabled = false
        settings.save(to: defaults)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.isRotationEnabled == false)
    }

    @Test func testRotationInterval_persists() async throws {
        let suiteName = "AerialFlowTests.AppSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.rotationIntervalSeconds = 1_200
        settings.save(to: defaults)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.rotationIntervalSeconds == 1_200)
    }

    @Test func testPauseMigration_mapsOldKey() async throws {
        let suiteName = "AerialFlowTests.AppSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Legacy key (Milestone 2): paused = true.
        defaults.set(true, forKey: "AerialFlow.isPaused")
        // Ensure new key is absent.
        defaults.removeObject(forKey: "AerialFlow.isRotationEnabled")

        let loaded = AppSettings.load(from: defaults)
        #expect(loaded.isRotationEnabled == false)
        #expect(defaults.object(forKey: "AerialFlow.isRotationEnabled") != nil)
    }
}


