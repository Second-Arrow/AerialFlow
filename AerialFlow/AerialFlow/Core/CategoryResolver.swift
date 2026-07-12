import Foundation
import os

/// Resolves human-readable names from Apple's TVIdleScreenStrings bundle.
///
/// Implemented as an `actor` to ensure thread-safe caching of the loaded strings.
actor CategoryResolver {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "CategoryResolver")
    private let fileSystem: FileSystem
    private let candidateBundleRootURLs: [URL]
    private let stringsSource: AerialLocalizedStringsSource

    private var cachedStrings: [String: Set<String>]?
    private var cacheTimestamp: Date?

    init(
        fileSystem: FileSystem,
        bundleRootURL: URL
    ) {
        self.fileSystem = fileSystem
        self.candidateBundleRootURLs = [bundleRootURL]
        self.stringsSource = AerialLocalizedStringsSource(fileSystem: fileSystem)
    }

    init(
        fileSystem: FileSystem,
        homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.fileSystem = fileSystem
        self.candidateBundleRootURLs = AerialSystemPaths.candidateStringsBundleRootURLs(homeDirectoryURL: homeDirectoryURL)
        self.stringsSource = AerialLocalizedStringsSource(fileSystem: fileSystem)
    }

    /// Loads localized strings from Apple's `TVIdleScreenStrings` bundle.
    ///
    /// Supports both the macOS 26+ compiled `.loctable` format and the legacy per-locale
    /// `*.lproj/Localizable(.nocache).strings` format (see `AerialLocalizedStringsSource`).
    ///
    /// Important: we only load the best-matching localization (with fallbacks) so the UI shows
    /// the user's preferred language, rather than an arbitrary merged set across all locales.
    ///
    /// Results are cached and reused on subsequent calls.
    func loadAllLocalizedStrings() -> [String: Set<String>] {
        // Return cached result if available
        if let cachedStrings {
            return cachedStrings
        }

        guard let bundleRootURL = candidateBundleRootURLs.first(where: { fileSystem.fileExists(at: $0) && fileSystem.isReadable(at: $0) }) else {
            // Important: do not cache an empty result here.
            // The bundle may appear later after the user enables Aerials.
            return [:]
        }

        let merged = stringsSource.loadStrings(bundleRootURL: bundleRootURL)

        guard !merged.isEmpty else {
            // Do not cache an empty result: the strings may become readable later.
            return [:]
        }

        cachedStrings = merged
        cacheTimestamp = Date()
        logger.debug("Loaded localized strings: \(merged.count) keys")
        return merged
    }

    /// Clears the cache, forcing a reload on next access.
    func invalidateCache() {
        cachedStrings = nil
        cacheTimestamp = nil
    }

    /// Builds a map: categoryID -> possible display names (across locales).
    func categoryIDToNames(categories: [AerialCategory]) -> [String: Set<String>] {
        let strings = loadAllLocalizedStrings()
        var result: [String: Set<String>] = [:]
        result.reserveCapacity(categories.count)

        for category in categories {
            guard !category.id.isEmpty else { continue }
            var names: Set<String> = []
            if let key = category.localizedNameKey, let values = strings[key] {
                names.formUnion(values)
            }
            result[category.id] = names
        }
        return result
    }

    /// Resolves an Aerial asset ID (as found in `entries.json`) to a human-readable name, if available.
    ///
    /// The strings bundle typically stores the primary title under `"\(assetID)_NAME"`.
    func assetName(for assetID: String) -> String? {
        guard !assetID.isEmpty else { return nil }
        let strings = loadAllLocalizedStrings()

        let keysToTry = ["\(assetID)_NAME", assetID]
        for key in keysToTry {
            guard let values = strings[key], !values.isEmpty else { continue }
            return values
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .first
        }

        return nil
    }

    func assetName(for asset: AerialAsset) -> String? {
        let strings = loadAllLocalizedStrings()
        return resolveAssetName(for: asset, using: strings)
    }

    /// Resolves display names for many assets while loading the strings bundle only once.
    ///
    /// Applies the same fallback chain as `assetName(for:)`:
    /// `localizedNameKey -> shotID(_NAME) -> id(_NAME) -> accessibilityLabel`.
    /// Falls back to the asset ID when nothing resolves, so callers always get a usable value.
    func assetNames(for assets: [AerialAsset]) -> [String: String] {
        let strings = loadAllLocalizedStrings()
        var out: [String: String] = [:]
        out.reserveCapacity(assets.count)
        for asset in assets {
            guard !asset.id.isEmpty else { continue }
            out[asset.id] = resolveAssetName(for: asset, using: strings) ?? asset.id
        }
        return out
    }

    private func resolveAssetName(for asset: AerialAsset, using strings: [String: Set<String>]) -> String? {
        if let key = asset.localizedNameKey, !key.isEmpty,
           let name = bestName(forKeys: [key], in: strings) {
            return name
        }

        if let shotID = asset.shotID, !shotID.isEmpty,
           let name = bestName(forKeys: ["\(shotID)_NAME", shotID], in: strings) {
            return name
        }

        if !asset.id.isEmpty,
           let name = bestName(forKeys: ["\(asset.id)_NAME", asset.id], in: strings) {
            return name
        }

        // Last-resort: plain-text label present in newer catalogs (macOS 26+).
        if let label = asset.accessibilityLabel, !label.isEmpty {
            return label
        }

        return nil
    }

    private func bestName(forKeys keys: [String], in strings: [String: Set<String>]) -> String? {
        for key in keys {
            guard let values = strings[key], !values.isEmpty else { continue }
            return values
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .first
        }
        return nil
    }

    /// Resolves excluded category IDs by matching terms against any localized name (substring, case-insensitive) or exact category ID.
    ///
    /// `excludeTerms` may contain comma-separated lists and repeated terms.
    func resolveExcludedCategoryIDs(
        excludeTerms: [String],
        categories: [AerialCategory]
    ) -> (excludedIDs: Set<String>, debugLines: [String]) {
        let terms = excludeTerms
            .flatMap { $0.split(separator: ",").map(String.init) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let idToNames = categoryIDToNames(categories: categories)

        var excluded: Set<String> = []
        var debug: [String] = []

        for term in terms {
            let lower = term.lowercased()
            var matchedIDs: [String] = []

            for category in categories where !category.id.isEmpty {
                if category.id == term {
                    matchedIDs.append(category.id)
                    continue
                }
                let names = idToNames[category.id] ?? []
                if names.contains(where: { $0.lowercased().contains(lower) }) {
                    matchedIDs.append(category.id)
                }
            }

            if matchedIDs.isEmpty {
                debug.append("No match for exclude term: \(term)")
            } else {
                for id in matchedIDs {
                    excluded.insert(id)
                }
                debug.append("Exclude term '\(term)' matched: \(matchedIDs.sorted().joined(separator: ", "))")
            }
        }

        return (excluded, debug)
    }
}
