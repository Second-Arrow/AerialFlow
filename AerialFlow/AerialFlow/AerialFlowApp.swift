//
//  AerialFlowApp.swift
//  AerialFlow
//
//  Created by Floris Robbemont on 02/01/2026.
//

import SwiftUI
import AppKit

private struct MenuBarContents: View {
    @Environment(\.openSettings) private var openSettings
    @ObservedObject var appState: AppState

    var body: some View {
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

        Button("About") {
            appState.selectedSettingsTab = .about
            openSettings()
        }

        SettingsLink {
            Text("Open Settings")
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct SupportCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About AerialFlow") {
                NSApplication.shared.orderFrontStandardAboutPanel(nil)
            }
        }

        CommandMenu("Support") {
            Button("Support Development…") {
                openWindow(id: "supportDevelopment")
            }
        }
    }
}

@main
struct AerialFlowApp: App {
    @StateObject private var appState: AppState

    init() {
        let dependencies = AppDependencies.live()
        _appState = StateObject(wrappedValue: AppState(dependencies: dependencies))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContents(appState: appState)
        } label: {
            let icon = appState.isPaused ? "pause.fill" : "airplane"
            Label("AerialFlow", systemImage: icon)
        }
        .commands {
            SupportCommands()
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        Window("Support Development", id: "supportDevelopment") {
            TipJarView(
                purchaser: appState.tipJarPurchaser,
                productIDs: [
                    "com.secondarrow.AerialFlow.tip.small",
                    "com.secondarrow.AerialFlow.tip.coffee",
                    "com.secondarrow.AerialFlow.tip.lunch",
                    "com.secondarrow.AerialFlow.tip.bigThanks"
                ]
            )
        }
    }
}
