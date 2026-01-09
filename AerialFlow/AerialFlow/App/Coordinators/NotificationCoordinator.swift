import Foundation
import UserNotifications

/// Owns notification permission queries and error-notification posting task lifecycle.
@MainActor
final class NotificationCoordinator {
    private let service: any NotificationPermissionServicing
    private var postTask: Task<Void, Never>?

    init(service: any NotificationPermissionServicing) {
        self.service = service
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await service.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        await service.requestAuthorization()
    }

    /// Posts an error notification (if permitted) and then runs `onStatusUpdated` with the latest status.
    func postErrorNotificationAndRefreshStatusIfPossible(
        _ message: String,
        onStatusUpdated: @escaping @MainActor (UNAuthorizationStatus) -> Void
    ) {
        postTask?.cancel()
        postTask = Task { [weak self] in
            guard let self else { return }
            await self.service.postErrorNotificationIfPossible(message)
            let status = await self.service.authorizationStatus()
            onStatusUpdated(status)
        }
    }

    deinit {
        postTask?.cancel()
    }
}

