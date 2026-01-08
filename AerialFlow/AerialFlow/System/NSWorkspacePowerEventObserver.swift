import AppKit
import Foundation

struct NSWorkspacePowerEventObserver: PowerEventObserving, Sendable {
    init() {}

    func events() -> AsyncStream<PowerEvent> {
        AsyncStream { continuation in
            let notificationCenter = NSWorkspace.shared.notificationCenter

            let tokens: [any NSObjectProtocol] = [
                notificationCenter.addObserver(
                    forName: NSWorkspace.willSleepNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    continuation.yield(.willSleep)
                },
                notificationCenter.addObserver(
                    forName: NSWorkspace.didWakeNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    continuation.yield(.didWake)
                },
                notificationCenter.addObserver(
                    forName: NSWorkspace.screensDidSleepNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    continuation.yield(.screensDidSleep)
                },
                notificationCenter.addObserver(
                    forName: NSWorkspace.screensDidWakeNotification,
                    object: nil,
                    queue: nil
                ) { _ in
                    continuation.yield(.screensDidWake)
                }
            ]

            continuation.onTermination = { _ in
                for token in tokens {
                    notificationCenter.removeObserver(token)
                }
            }
        }
    }
}


