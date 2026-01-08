import Foundation
@preconcurrency import UserNotifications
import os

protocol NotificationPermissionServicing: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorizationIfNeeded() async -> Bool
    func requestAuthorization() async -> Bool
    func postErrorNotificationIfPossible(_ message: String) async
}

protocol UserNotificationCenter: Sendable {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
}

struct DefaultUserNotificationCenter: UserNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    func add(_ request: UNNotificationRequest) async throws {
        try await UNUserNotificationCenter.current().add(request)
    }
}

actor NotificationPermissionService: NotificationPermissionServicing {
    private let logger: Logger
    private let center: UserNotificationCenter
    private var didRequestAuthorization: Bool = false

    init(
        subsystem: String = Constants.loggerSubsystem,
        center: UserNotificationCenter = DefaultUserNotificationCenter()
    ) {
        self.logger = Logger(subsystem: subsystem, category: "NotificationPermissionService")
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.authorizationStatus()
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let status = await authorizationStatus()
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        case .notDetermined:
            guard !didRequestAuthorization else { return false }
            didRequestAuthorization = true
            return await requestAuthorization()
        @unknown default:
            return false
        }
    }

    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.debug("Notification authorization request failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    func postErrorNotificationIfPossible(_ message: String) async {
        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else { return }

        let content = UNMutableNotificationContent()
        content.title = "AerialFlow"
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            logger.debug("Posting notification failed: \(String(describing: error), privacy: .public)")
        }
    }
}


