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
    @StateObject private var appState: AppState

    init() {
        let dependencies = AppDependencies.live()
        _appState = StateObject(wrappedValue: AppState(dependencies: dependencies))
    }

    var body: some Scene {
        MenuBarExtra {
            Text(appState.statusLine)
                .font(.footnote)
                .foregroundStyle(
                    appState.lastErrorMessage == nil
                        ? AnyShapeStyle(.secondary)
                        : AnyShapeStyle(Color.red)
                )

            Divider()

            Button("Next Aerial") {
                Task { await appState.nextAerial() }
            }
            .disabled(appState.isBusy)

            Button(appState.isPaused ? "Continue" : "Pause") {
                appState.setRotationEnabled(appState.isPaused)
            }

            Divider()

            SettingsLink {
                Text("Open Settings")
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        } label: {
            let icon = appState.isPaused ? "pause.fill" : "airplane"
            Label("AerialFlow", systemImage: icon)
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
