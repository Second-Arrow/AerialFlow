//
//  AerialFlowApp.swift
//  AerialFlow
//
//  Created by Floris Robbemont on 02/01/2026.
//

import SwiftUI
import AppKit

private struct MenuBarIcon: View {
    @ObservedObject var appState: AppState

    private var icon: NSImage {
        let size = NSSize(width: 26, height: 26)
        let image = NSImage(size: size, flipped: false) { rect in
            let windSize: CGFloat = appState.isPaused ? 22 : 24;

            // Draw wind icon (slightly smaller, centered)
            if let windSymbol = NSImage(systemSymbolName: "wind", accessibilityDescription: nil) {
                let windConfig = NSImage.SymbolConfiguration(pointSize: windSize, weight: .regular)
                let configuredWind = windSymbol.withSymbolConfiguration(windConfig) ?? windSymbol
                let inset: CGFloat = appState.isPaused ? 5 : 3;
                let windRect = rect.insetBy(dx: inset, dy: inset)
                configuredWind.draw(in: windRect)
            }

            // Draw forbidden overlay when paused (fills the full frame)
            if appState.isPaused,
               let nosignSymbol = NSImage(systemSymbolName: "nosign", accessibilityDescription: nil) {
                let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .regular)
                if let configured = nosignSymbol.withSymbolConfiguration(config) {
                    configured.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.85)
                }
            }

            return true
        }
        image.isTemplate = true
        return image
    }

    var body: some View {
        Image(nsImage: icon)
    }
}

private struct MenuBarContents: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var appState: AppState

    var body: some View {
        Text("AerialFlow")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .task {
                if appState.consumeOnboardingRequest() {
                    openWindow(id: "onboarding")
                }
            }
            .onChange(of: appState.onboardingRequested) { _, _ in
                if appState.consumeOnboardingRequest() {
                    openWindow(id: "onboarding")
                }
            }

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
            Text("Settings")
        }
        
        Button("Setup…") {
            openWindow(id: "onboarding")
        }

        Button("About") {
            openWindow(id: "about")
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

private struct SupportCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About") {
                openWindow(id: "about")
            }
        }

        CommandMenu("Support") {
            Button("Support Development…") {
                guard let url = Constants.supportURL else { return }
                openURL(url)
            }
        }
    }
}

@main
struct AerialFlowApp: App {
    private let dependencies: AppDependencies
    @StateObject private var appState: AppState

    init() {
        let deps = AppDependencies.live()
        self.dependencies = deps
        _appState = StateObject(wrappedValue: AppState(dependencies: deps))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContents(appState: appState)
        } label: {
            MenuBarIcon(appState: appState)
        }
        .commands {
            SupportCommands()
        }

        Settings {
            SettingsView(
                catalog: dependencies.catalog,
                catalogPresentation: dependencies.catalogPresentation,
                stateStore: dependencies.stateStore,
                systemSettingsOpener: dependencies.systemSettingsOpener
            )
                .environmentObject(appState)
                .environmentObject(appState.updaterViewModel)
        }

        Window("About AerialFlow", id: "about") {
            AboutWindowView()
        }
        .windowResizability(.contentSize)

        Window("AerialFlow Setup", id: "onboarding") {
            OnboardingWindowView()
                .environmentObject(appState)
        }
        .windowResizability(.contentSize)
    }
}
