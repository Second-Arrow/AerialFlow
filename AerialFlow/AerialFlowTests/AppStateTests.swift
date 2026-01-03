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

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(userDefaults: defaultsForMainActor)
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
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

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(userDefaults: defaultsForMainActor)
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }
        let initial = await MainActor.run { state.isPaused }

        await MainActor.run {
            state.setRotationEnabled(state.isPaused)
            state.setRotationEnabled(state.isPaused)
        }
        let final = await MainActor.run { state.isPaused }

        #expect(final == initial)
    }

    @Test func testSelectedSettingsTab_defaultsToGeneral_andCanChange() async throws {
        let suiteName = "AerialFlowTests.AppState.SettingsTab.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw TestError.couldNotCreateUserDefaultsSuite
        }

        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let state = await MainActor.run { [suiteName] in
            // `MainActor.run` takes a `@Sendable` closure; avoid capturing `UserDefaults` (non-Sendable).
            let defaultsForMainActor = UserDefaults(suiteName: suiteName)!
            let dependencies = AppDependencies.live(userDefaults: defaultsForMainActor)
            return AppState(dependencies: dependencies, userDefaults: defaultsForMainActor)
        }

        let initial = await MainActor.run { state.selectedSettingsTab }
        #expect(initial == .general)

        await MainActor.run { state.selectedSettingsTab = .about }
        let updated = await MainActor.run { state.selectedSettingsTab }
        #expect(updated == .about)
    }

    @Test func testCalculateStorageUsed_emptyDirectory_returnsZero() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        try fileSystem.createDirectory(at: videoDir)

        let result = AppState.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        #expect(result == 0)
    }

    @Test func testCalculateStorageUsed_multipleMovFiles_sumsCorrectly() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        try fileSystem.createDirectory(at: videoDir)

        // Create multiple .mov files with different sizes
        let file1 = videoDir.appendingPathComponent("asset1.mov")
        let file2 = videoDir.appendingPathComponent("asset2.mov")
        let file3 = videoDir.appendingPathComponent("asset3.mov")

        let data1 = Data(repeating: 0, count: 1000)
        let data2 = Data(repeating: 0, count: 2000)
        let data3 = Data(repeating: 0, count: 3000)

        try fileSystem.writeData(data1, to: file1, options: [])
        try fileSystem.writeData(data2, to: file2, options: [])
        try fileSystem.writeData(data3, to: file3, options: [])

        let result = AppState.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        #expect(result == 6000) // 1000 + 2000 + 3000
    }

    @Test func testCalculateStorageUsed_directoryDoesNotExist_returnsNil() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        // Don't create the directory

        let result = AppState.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        #expect(result == nil)
    }

    @Test func testCalculateStorageUsed_excludesPartFiles() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        try fileSystem.createDirectory(at: videoDir)

        // Create a .mov file and a .part file
        let movFile = videoDir.appendingPathComponent("asset1.mov")
        let partFile = videoDir.appendingPathComponent(".asset2.mov.part")

        let movData = Data(repeating: 0, count: 1000)
        let partData = Data(repeating: 0, count: 5000)

        try fileSystem.writeData(movData, to: movFile, options: [])
        try fileSystem.writeData(partData, to: partFile, options: [])

        let result = AppState.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        // Should only count the .mov file, not the .part file
        #expect(result == 1000)
    }

    @Test func testCalculateStorageUsed_excludesHiddenMovFiles() throws {
        let fileSystem = InMemoryFileSystem()
        let videoDir = URL(fileURLWithPath: "/test/videos")
        try fileSystem.createDirectory(at: videoDir)

        // Create a regular .mov file and a hidden .mov file (starting with .)
        let movFile = videoDir.appendingPathComponent("asset1.mov")
        let hiddenMovFile = videoDir.appendingPathComponent(".asset2.mov")

        let movData = Data(repeating: 0, count: 1000)
        let hiddenData = Data(repeating: 0, count: 5000)

        try fileSystem.writeData(movData, to: movFile, options: [])
        try fileSystem.writeData(hiddenData, to: hiddenMovFile, options: [])

        let result = AppState.calculateStorageUsed(fileSystem: fileSystem, videoDirectory: videoDir)
        // Should only count the non-hidden .mov file
        #expect(result == 1000)
    }
}

