import AppKit
import Foundation

protocol SystemSettingsOpening: Sendable {
    @discardableResult func openSystemSettings() -> Bool
    @discardableResult func openNotificationsSettings() -> Bool
    @discardableResult func openLoginItemsSettings() -> Bool
    @discardableResult func openInputMonitoringSettings() -> Bool
    @discardableResult func openAccessibilitySettings() -> Bool
    @discardableResult func openWallpaperSettings() -> Bool
    @discardableResult func openScreenSaverSettings() -> Bool
}

struct SystemSettingsOpener: SystemSettingsOpening, Sendable {
    @discardableResult
    func openSystemSettings() -> Bool {
        let settingsApp = URL(fileURLWithPath: "/System/Applications/System Settings.app", isDirectory: true)
        return NSWorkspace.shared.open(settingsApp)
    }

    @discardableResult
    func openNotificationsSettings() -> Bool {
        openFirstMatch(urlStrings: [
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.notifications",
        ])
    }

    @discardableResult
    func openLoginItemsSettings() -> Bool {
        openFirstMatch(urlStrings: [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.users?LoginItems",
        ])
    }

    @discardableResult
    func openInputMonitoringSettings() -> Bool {
        openFirstMatch(urlStrings: [
            "x-apple.systempreferences:com.apple.PrivacySecurity-Settings.extension?Privacy_ListenEvent",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ])
    }

    @discardableResult
    func openAccessibilitySettings() -> Bool {
        openFirstMatch(urlStrings: [
            "x-apple.systempreferences:com.apple.PrivacySecurity-Settings.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        ])
    }

    @discardableResult
    func openWallpaperSettings() -> Bool {
        openFirstMatch(urlStrings: [
            // macOS 13+ System Settings (best-effort; exact ID may vary by OS version)
            "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension",
            // Legacy System Preferences (Desktop & Screen Saver)
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect",
        ])
    }

    @discardableResult
    func openScreenSaverSettings() -> Bool {
        openFirstMatch(urlStrings: [
            // macOS 13+ System Settings (best-effort; exact ID may vary by OS version)
            "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension",
            // Legacy System Preferences (Desktop & Screen Saver)
            "x-apple.systempreferences:com.apple.preference.desktopscreeneffect",
        ])
    }

    @discardableResult
    private func openFirstMatch(urlStrings: [String]) -> Bool {
        let workspace = NSWorkspace.shared

        for urlString in urlStrings {
            guard let url = URL(string: urlString) else { continue }
            if workspace.open(url) { return true }
        }

        // Fallback: open System Settings without a deep link.
        return openSystemSettings()
    }
}


