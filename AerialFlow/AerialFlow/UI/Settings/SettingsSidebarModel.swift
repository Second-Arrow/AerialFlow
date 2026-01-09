import Foundation

struct SettingsSidebarModel: Sendable {
    struct Section: Hashable, Sendable {
        let title: String
        let destinations: [AppState.SettingsDestination]
    }

    static let sections: [Section] = [
        Section(title: "Settings", destinations: [.general, .rotation, .filtering, .exclusions, .hotkeys]),
        Section(title: "Tools", destinations: [.diagnostics]),
        Section(title: "Other", destinations: [.advanced, .about]),
    ]
}

