import Foundation
import Sparkle

/// Thin wrapper around Sparkle's updater controller.
///
/// Constructed in `AppDependencies` and shared for the lifetime of the app.
final class AutoUpdateManager: NSObject, SPUUpdaterDelegate {
    lazy var controller: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()

    private let startingUpdater: Bool

    init(startingUpdater: Bool = true) {
        self.startingUpdater = startingUpdater
        super.init()
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        Constants.sparkleFeedURLString
    }
}


