import Combine
import Foundation
import UserNotifications

@MainActor
final class AppUIState: ObservableObject {
    @Published var selectedSettingsDestination: AppState.SettingsDestination = .general

    @Published var isBusy: Bool
    @Published var statusLine: String
    @Published var lastErrorMessage: String?
    @Published var launchAtLoginErrorMessage: String?
    @Published var isCleaningExcludedAerials: Bool
    @Published var systemAccessReport: SystemAccessReport?
    @Published var notificationAuthorizationStatus: UNAuthorizationStatus?
    @Published var onboardingRequested: Bool

    init(
        isBusy: Bool = false,
        statusLine: String = "Ready",
        lastErrorMessage: String? = nil,
        launchAtLoginErrorMessage: String? = nil,
        isCleaningExcludedAerials: Bool = false,
        systemAccessReport: SystemAccessReport? = nil,
        notificationAuthorizationStatus: UNAuthorizationStatus? = nil,
        onboardingRequested: Bool = false
    ) {
        self.isBusy = isBusy
        self.statusLine = statusLine
        self.lastErrorMessage = lastErrorMessage
        self.launchAtLoginErrorMessage = launchAtLoginErrorMessage
        self.isCleaningExcludedAerials = isCleaningExcludedAerials
        self.systemAccessReport = systemAccessReport
        self.notificationAuthorizationStatus = notificationAuthorizationStatus
        self.onboardingRequested = onboardingRequested
    }
}

