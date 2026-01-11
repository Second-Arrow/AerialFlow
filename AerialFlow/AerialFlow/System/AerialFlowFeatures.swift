import Foundation

/// Centralized feature flags / behavioral switches for OS-conditional behavior.
///
/// Construct this once in the composition root (`AppDependencies`) and inject it into services.
struct AerialFlowFeatures: Sendable, Equatable {
    enum MovDownloadMode: Sendable, Equatable {
        /// AerialFlow downloads `.mov` files directly into the detected videos directory.
        case directToVideoDirectory
        /// macOS 15.* uses a system-managed (root-owned) `idleassetsd` cache for Aerial videos.
        /// In this mode, AerialFlow should not attempt to write `.mov` files; it relies on macOS to cache them.
        case relyOnSystemCache_macos15
    }

    let movDownloadMode: MovDownloadMode

    static func live(processInfo: ProcessInfo = .processInfo) -> AerialFlowFeatures {
        let major = processInfo.operatingSystemVersion.majorVersion
        if major == 15 {
            return AerialFlowFeatures(movDownloadMode: .relyOnSystemCache_macos15)
        }
        return AerialFlowFeatures(movDownloadMode: .directToVideoDirectory)
    }
}

