import Foundation

/// Builds the filesystem locations macOS uses for Aerial catalog + localized strings.
///
/// This is intentionally pure (no IO), so callers can decide how/when to check existence/readability.
enum AerialSystemPaths {
    /// Preferred catalog path on newer macOS versions (per-user wallpaper store).
    static func preferredCatalogURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("aerials", isDirectory: true)
            .appendingPathComponent("manifest", isDirectory: true)
            .appendingPathComponent("entries.json", isDirectory: false)
    }

    /// Legacy catalog path on older macOS versions (system-managed idleassetsd cache).
    static func legacyCatalogURL() -> URL {
        URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/entries.json")
    }

    static func candidateCatalogURLs(homeDirectoryURL: URL) -> [URL] {
        [
            preferredCatalogURL(homeDirectoryURL: homeDirectoryURL),
            legacyCatalogURL(),
        ]
    }

    /// Preferred localized strings bundle path on newer macOS versions (per-user wallpaper store).
    static func preferredStringsBundleRootURL(homeDirectoryURL: URL) -> URL {
        homeDirectoryURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
            .appendingPathComponent("aerials", isDirectory: true)
            .appendingPathComponent("manifest", isDirectory: true)
            .appendingPathComponent("TVIdleScreenStrings.bundle", isDirectory: true)
    }

    /// Legacy localized strings bundle path on older macOS versions (system-managed idleassetsd cache).
    static func legacyStringsBundleRootURL() -> URL {
        URL(
            fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/TVIdleScreenStrings.bundle",
            isDirectory: true
        )
    }

    static func candidateStringsBundleRootURLs(homeDirectoryURL: URL) -> [URL] {
        [
            preferredStringsBundleRootURL(homeDirectoryURL: homeDirectoryURL),
            legacyStringsBundleRootURL(),
        ]
    }
}

