import Foundation
import os

/// Resolves human-readable category names from Apple's TVIdleScreenStrings bundle.
struct CategoryResolver: Sendable {
    private let logger = Logger(subsystem: "com.secondarrow.AerialFlow", category: "CategoryResolver")
    private let fileSystem: FileSystem
    private let bundleRootURL: URL

    init(
        fileSystem: FileSystem = DefaultFileSystem(),
        bundleRootURL: URL = URL(fileURLWithPath: "/Library/Application Support/com.apple.idleassetsd/Customer/TVIdleScreenStrings.bundle", isDirectory: true)
    ) {
        self.fileSystem = fileSystem
        self.bundleRootURL = bundleRootURL
    }

    /// Loads localized strings from `*.lproj/Localizable(.nocache).strings` files.
    func loadAllLocalizedStrings() -> [String: Set<String>] {
        guard fileSystem.fileExists(at: bundleRootURL) else { return [:] }

        var merged: [String: Set<String>] = [:]

        let lprojDirs: [URL]
        do {
            lprojDirs = try fileSystem.listFiles(in: bundleRootURL).filter { $0.pathExtension == "lproj" }
        } catch {
            logger.debug("Failed to list bundle root: \(String(describing: error), privacy: .public)")
            return [:]
        }

        for lproj in lprojDirs {
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

        return merged
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
}


