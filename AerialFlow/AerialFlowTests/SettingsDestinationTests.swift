//
//  SettingsDestinationTests.swift
//  AerialFlowTests
//
//  Created by Cursor.
//

import Foundation
import Testing
@testable import AerialFlow

struct SettingsDestinationTests {
    @Test func testAllCases_orderingIsStable() async throws {
        #expect(AppState.SettingsDestination.allCases == [
            .general,
            .rotation,
            .filtering,
            .exclusions,
            .hotkeys,
            .diagnostics,
            .advanced,
            .about,
        ])
    }

    @Test func testAllCases_haveTitleIconAndSection() async throws {
        for destination in AppState.SettingsDestination.allCases {
            #expect(!destination.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!destination.systemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(!destination.sidebarSectionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

