//
//  EngineStateStoreTests.swift
//  AerialFlowTests
//
//  Created by Cursor.
//

import Foundation
import Testing
@testable import AerialFlow

struct EngineStateStoreTests {
    enum TestError: Error {
        case couldNotCreateUserDefaultsSuite
    }

    @Test func testLastAssetID_roundTrips() async throws {
        let suiteName = "AerialFlowTests.EngineStateStore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsEngineStateStore(userDefaults: defaults)
        await store.setLastAssetID("abc")
        let id = await store.getLastAssetID()
        #expect(id == "abc")

        await store.setLastAssetID(nil)
        let cleared = await store.getLastAssetID()
        #expect(cleared == nil)
    }

    @Test func testLastChange_roundTrips() async throws {
        let suiteName = "AerialFlowTests.EngineStateStore.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsEngineStateStore(userDefaults: defaults)
        let date = Date(timeIntervalSince1970: 1234)
        await store.setLastChange(date)
        let roundTrip = await store.getLastChange()
        #expect(roundTrip == date)

        await store.setLastChange(nil)
        let cleared = await store.getLastChange()
        #expect(cleared == nil)
    }
}


