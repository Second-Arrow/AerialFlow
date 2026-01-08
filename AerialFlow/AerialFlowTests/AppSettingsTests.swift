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

    @Test func testExcludedSubcategoryIDs_persists() async throws {
        let suiteName = "AerialFlowTests.AppSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.excludedSubcategoryIDs = ["sub-1", "sub-2"]
        settings.save(to: defaults)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.excludedSubcategoryIDs == ["sub-1", "sub-2"])
    }

    @Test func testExcludedAssetIDs_persists() async throws {
        let suiteName = "AerialFlowTests.AppSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.excludedAssetIDs = ["009BA758-7060-4479-8EE8-FB9B40C8FB97", "1088217C-1410-4CF7-BDE9-8F573A4DBCD9"]
        settings.save(to: defaults)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.excludedAssetIDs == ["009BA758-7060-4479-8EE8-FB9B40C8FB97", "1088217C-1410-4CF7-BDE9-8F573A4DBCD9"])
    }

    @Test func testExcludedAerialCleanupEnabled_defaultsToOff() async throws {
        let suiteName = "AerialFlowTests.AppSettings.ExcludedAerialCleanupEnabledDefault.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let loaded = AppSettings.load(from: defaults)
        #expect(loaded.isExcludedAerialCleanupEnabled == false)
    }

    @Test func testExcludedAerialCleanupEnabled_persists() async throws {
        let suiteName = "AerialFlowTests.AppSettings.ExcludedAerialCleanupEnabledPersists.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.isExcludedAerialCleanupEnabled = true
        settings.save(to: defaults)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.isExcludedAerialCleanupEnabled == true)
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

    @Test func testSleepResumeBehavior_defaultsToUseOriginalTimeLeft() async throws {
        let suiteName = "AerialFlowTests.AppSettings.SleepResumeBehaviorDefault.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let loaded = AppSettings.load(from: defaults)
        #expect(loaded.sleepResumeBehavior == .useOriginalTimeLeft)
    }

    @Test func testSleepResumeBehavior_persists() async throws {
        let suiteName = "AerialFlowTests.AppSettings.SleepResumeBehaviorPersists.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.sleepResumeBehavior = .restartRotationTimer
        settings.save(to: defaults)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.sleepResumeBehavior == .restartRotationTimer)
    }

    @Test func testLegacyRunGuardKeys_areIgnored_andNotWritten() async throws {
        let suiteName = "AerialFlowTests.AppSettings.LegacyRunGuardKeys.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(false, forKey: "AerialFlow.skipWhenDisplayOff")
        defaults.set(false, forKey: "AerialFlow.skipWhenScreensaverActive")
        defaults.set(false, forKey: "AerialFlow.skipAtLoginWindow")

        let loaded = AppSettings.load(from: defaults)
        #expect(loaded.sleepResumeBehavior == .useOriginalTimeLeft)

        AppSettings().save(to: defaults)
        #expect(defaults.object(forKey: "AerialFlow.skipWhenDisplayOff") == nil)
        #expect(defaults.object(forKey: "AerialFlow.skipWhenScreensaverActive") == nil)
        #expect(defaults.object(forKey: "AerialFlow.skipAtLoginWindow") == nil)
    }

    @Test func testBackupRetentionCount_persists() async throws {
        let suiteName = "AerialFlowTests.AppSettings.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var settings = AppSettings()
        settings.backupRetentionCount = 25
        settings.save(to: defaults)

        let reloaded = AppSettings.load(from: defaults)
        #expect(reloaded.backupRetentionCount == 25)
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


