import Foundation
import Sparkle

/// Thin wrapper around Sparkle's updater controller.
///
/// Constructed in `AppDependencies` and shared for the lifetime of the app.
final class AutoUpdateManager: NSObject {
    let controller: SPUStandardUpdaterController

    init(startingUpdater: Bool = true) {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }
}


