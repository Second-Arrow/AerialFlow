//
//  AerialFlowApp.swift
//  AerialFlow
//
//  Created by Floris Robbemont on 02/01/2026.
//

import SwiftUI
import AppKit

@main
struct AerialFlowApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("AerialFlow", systemImage: "sparkles.tv") {
            Button("Next Aerial") {
                // UI-only scaffolding for now.
            }
            .disabled(true)

            Button(appState.isPaused ? "Continue" : "Pause") {
                appState.togglePaused()
            }

            Divider()

            SettingsLink {
                Text("Open Settings")
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
