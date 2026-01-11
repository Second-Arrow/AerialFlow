import Foundation

/// Best-effort detection of the `Index.plist` structural shape relevant for Aerial provider edits.
///
/// This intentionally does **not** check the running OS version. It infers shape from the plist tree,
/// so it stays compatible across macOS versions and user configuration modes.
enum WallpaperStoreIndexPlistShape: Sendable, Equatable {
    enum ContainerMode: Sendable, Equatable {
        case linked
        case individualDesktopAndIdle

        var description: String {
            switch self {
            case .linked:
                return "linked"
            case .individualDesktopAndIdle:
                return "individual"
            }
        }
    }

    struct Summary: Sendable, Equatable {
        var allSpacesAndDisplays: ContainerMode?
        var systemDefault: ContainerMode?
        var hasLegacyRootDesktopOrIdle: Bool

        var description: String {
            var parts: [String] = []

            if let allSpacesAndDisplays {
                parts.append("AllSpacesAndDisplays: \(allSpacesAndDisplays.description)")
            }
            if let systemDefault {
                parts.append("SystemDefault: \(systemDefault.description)")
            }
            if parts.isEmpty, hasLegacyRootDesktopOrIdle {
                parts.append("Legacy (root Desktop/Idle)")
            }

            if parts.isEmpty {
                return "Unknown"
            }

            // If a legacy structure is present alongside newer containers, it can help debugging.
            if !parts.isEmpty, hasLegacyRootDesktopOrIdle, (allSpacesAndDisplays != nil || systemDefault != nil) {
                parts.append("Legacy also present")
            }

            return parts.joined(separator: ", ")
        }
    }

    static func summarize(root: Any) -> Summary {
        guard let dict = root as? [String: Any] else {
            return Summary(allSpacesAndDisplays: nil, systemDefault: nil, hasLegacyRootDesktopOrIdle: false)
        }

        let legacyRootDesktopOrIdle = dict["Desktop"] != nil || dict["Idle"] != nil

        return Summary(
            allSpacesAndDisplays: mode(in: dict, containerKey: "AllSpacesAndDisplays"),
            systemDefault: mode(in: dict, containerKey: "SystemDefault"),
            hasLegacyRootDesktopOrIdle: legacyRootDesktopOrIdle
        )
    }

    private static func mode(in root: [String: Any], containerKey: String) -> ContainerMode? {
        guard let container = root[containerKey] as? [String: Any] else { return nil }

        if let type = container["Type"] as? String {
            switch type {
            case "linked":
                return .linked
            case "individual":
                return .individualDesktopAndIdle
            default:
                break
            }
        }

        // Fallback: infer from presence of known section keys.
        if container["Linked"] is [String: Any] { return .linked }
        if container["Desktop"] is [String: Any] || container["Idle"] is [String: Any] {
            return .individualDesktopAndIdle
        }

        return nil
    }
}

