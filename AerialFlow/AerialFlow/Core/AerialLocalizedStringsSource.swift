import Foundation

/// Loads Aerial localized display names from Apple's `TVIdleScreenStrings` bundle.
///
/// The on-disk format changed across macOS versions, so this source understands both:
/// - **macOS 26+**: a single compiled `Localizable(.nocache).loctable` (binary plist shaped
///   `{ locale: { key: value } }`) located under `<bundle>/Contents/Resources/`. The `.lproj`
///   directories exist but are empty.
/// - **Legacy (macOS 15 and earlier)**: per-locale `*.lproj/Localizable(.nocache).strings` files
///   located directly under the bundle root.
///
/// Pure and testable: all IO goes through the injected `FileSystem`.
struct AerialLocalizedStringsSource: Sendable {
    private let fileSystem: FileSystem
    private let locale: Locale

    init(fileSystem: FileSystem, locale: Locale = .current) {
        self.fileSystem = fileSystem
        self.locale = locale
    }

    /// Loads localized strings (best-matching locale) for the given bundle root.
    ///
    /// Returns a map of key -> possible values. Values are wrapped in a `Set` to preserve the
    /// resolver contract; there is typically a single value per key for the selected locale.
    /// Returns an empty map when nothing can be read.
    func loadStrings(bundleRootURL: URL) -> [String: Set<String>] {
        if let loctable = loadFromLoctable(bundleRootURL: bundleRootURL), !loctable.isEmpty {
            return loctable
        }
        return loadFromLprojStrings(bundleRootURL: bundleRootURL)
    }

    // MARK: - loctable (macOS 26+)

    private func loadFromLoctable(bundleRootURL: URL) -> [String: Set<String>]? {
        guard let url = firstLoctableURL(bundleRootURL: bundleRootURL) else { return nil }

        guard let data = try? fileSystem.readData(from: url),
              let any = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let byLocale = any as? [String: Any] else {
            return nil
        }

        // Keep only entries whose value is a key->value table (drops metadata like `LocProvenance`).
        let tablesByLocale: [String: [String: Any]] = byLocale.compactMapValues { $0 as? [String: Any] }
        guard !tablesByLocale.isEmpty else { return nil }

        let selectedTag = preferredLocaleTags().first(where: { tablesByLocale[$0] != nil })
            ?? tablesByLocale.keys.sorted().first
        guard let selectedTag, let table = tablesByLocale[selectedTag] else { return nil }

        var result: [String: Set<String>] = [:]
        result.reserveCapacity(table.count)
        for (key, value) in table {
            guard let string = value as? String else { continue }
            result[key, default: []].insert(string)
        }
        return result
    }

    private func firstLoctableURL(bundleRootURL: URL) -> URL? {
        for dir in resourceSearchDirs(bundleRootURL) {
            guard fileSystem.fileExists(at: dir) else { continue }
            let files = (try? fileSystem.listFiles(in: dir)) ?? []
            let loctables = files
                .filter { $0.pathExtension == "loctable" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            if let match = loctables.first { return match }
        }
        return nil
    }

    // MARK: - lproj/.strings (legacy)

    private func loadFromLprojStrings(bundleRootURL: URL) -> [String: Set<String>] {
        for dir in resourceSearchDirs(bundleRootURL) {
            guard fileSystem.fileExists(at: dir) else { continue }
            let lprojDirs = ((try? fileSystem.listFiles(in: dir)) ?? [])
                .filter { $0.pathExtension == "lproj" }
            guard !lprojDirs.isEmpty else { continue }

            let selected = selectPreferredLprojDirs(from: lprojDirs)
            var merged: [String: Set<String>] = [:]

            for lproj in selected {
                let files = (try? fileSystem.listFiles(in: lproj)) ?? []
                for file in files {
                    let name = file.lastPathComponent
                    guard name == "Localizable.strings" || name == "Localizable.nocache.strings" else { continue }
                    guard let dict = try? readStringsFile(url: file) else { continue }
                    for (key, value) in dict {
                        merged[key, default: []].insert(value)
                    }
                }
            }

            if !merged.isEmpty { return merged }
        }
        return [:]
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

    // MARK: - Locale selection

    private func resourceSearchDirs(_ bundleRootURL: URL) -> [URL] {
        [
            bundleRootURL
                .appendingPathComponent("Contents", isDirectory: true)
                .appendingPathComponent("Resources", isDirectory: true),
            bundleRootURL,
        ]
    }

    /// Ordered locale tags to try: full identifier (e.g. `en_US`) -> language (`en`) -> `en`.
    private func preferredLocaleTags() -> [String] {
        let identifier = locale.identifier
        let language = locale.language.languageCode?.identifier

        var candidates: [String] = []
        if !identifier.isEmpty { candidates.append(identifier) }
        if let language, !language.isEmpty { candidates.append(language) }
        candidates.append("en")
        return candidates
    }

    private func selectPreferredLprojDirs(from lprojDirs: [URL]) -> [URL] {
        // Map: "en_GB.lproj" -> "en_GB"
        let available: [String: URL] = Dictionary(
            lprojDirs.compactMap { url -> (String, URL)? in
                let tag = url.deletingPathExtension().lastPathComponent
                guard !tag.isEmpty else { return nil }
                return (tag, url)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for tag in preferredLocaleTags() {
            if let exact = available[tag] { return [exact] }
        }

        // Fallback: English if present, else load all.
        if let en = available["en"] { return [en] }
        return lprojDirs
    }
}
