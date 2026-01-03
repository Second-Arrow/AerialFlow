import Foundation
import os

/// Resolves human-readable names from Apple's TVIdleScreenStrings bundle.
///
/// Implemented as an `actor` to ensure thread-safe caching of the loaded strings.
actor CategoryResolver {
    private let logger = Logger(subsystem: Constants.loggerSubsystem, category: "CategoryResolver")
    private let fileSystem: FileSystem
    private let bundleRootURL: URL

    private var cachedStrings: [String: Set<String>]?
    private var cacheTimestamp: Date?

    init(
        fileSystem: FileSystem,
        bundleRootURL: URL = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/TVIdleScreenStrings.bundle", isDirectory: true)
    ) {
        self.fileSystem = fileSystem
        self.bundleRootURL = bundleRootURL
    }

    /// Loads localized strings from `*.lproj/Localizable(.nocache).strings` files.
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

        guard fileSystem.fileExists(at: bundleRootURL) else {
            cachedStrings = [:]
            return [:]
        }

        let lprojDirs: [URL]
        do {
            lprojDirs = try fileSystem.listFiles(in: bundleRootURL).filter { $0.pathExtension == "lproj" }
        } catch {
            logger.debug("Failed to list bundle root: \(String(describing: error), privacy: .public)")
            cachedStrings = [:]
            return [:]
        }

        let selected = selectPreferredLprojDirs(from: lprojDirs)
        var merged: [String: Set<String>] = [:]

        for lproj in selected {
            let files: [URL]
            do {
                files = try fileSystem.listFiles(in: lproj)
            } catch {
                continue
            }

            for file in files {
                let name = file.lastPathComponent
                guard name == "Localizable.strings" || name == "Localizable.nocache.strings" else { continue }

                guard let dict = try? readStringsFile(url: file) else { continue }
                for (key, value) in dict {
                    merged[key, default: []].insert(value)
                }
            }
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

        if let key = asset.localizedNameKey, !key.isEmpty,
           let values = strings[key], !values.isEmpty {
            return values
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .first
        }

        if let shotID = asset.shotID, !shotID.isEmpty {
            let keysToTry = ["\(shotID)_NAME", shotID]
            for key in keysToTry {
                guard let values = strings[key], !values.isEmpty else { continue }
                return values
                    .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                    .first
            }
        }

        return assetName(for: asset.id)
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

    private func readStringsFile(url: URL) throws -> [String: String] {
        let data = try fileSystem.readData(from: url)
        let any = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        if let dict = any as? [String: String] { return dict }
        if let dict = any as? [String: Any] {
            var out: [String: String] = [:]
            for (k, v) in dict {
                if let s = v as? String { out[k] = s }
            }
            return out
        }
        return [:]
    }

    private func selectPreferredLprojDirs(from lprojDirs: [URL]) -> [URL] {
        // Map: "en_GB.lproj" -> "en_GB"
        let available: [String: URL] = Dictionary(
            uniqueKeysWithValues: lprojDirs.compactMap { url in
                let tag = url.deletingPathExtension().lastPathComponent
                guard !tag.isEmpty else { return nil }
                return (tag, url)
            }
        )

        let locale = Locale.current
        let identifier = locale.identifier // e.g. "en_US"
        let language = locale.language.languageCode?.identifier // e.g. "en"

        var candidates: [String] = []
        if !identifier.isEmpty { candidates.append(identifier) }
        if let language, !language.isEmpty { candidates.append(language) }
        candidates.append("en")

        for tag in candidates {
            if let exact = available[tag] {
                return [exact]
            }
        }

        // Fallback: if we couldn't match locale tags, load English if present, else load all.
        if let en = available["en"] { return [en] }
        return lprojDirs
    }
}
