import Foundation
import Testing

@testable import AerialFlow

struct AerialLocalizedStringsSourceTests {
    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }

    private func stringsPlistXML(_ dict: [String: String]) -> Data {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        """
        for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
            xml += "<key>\(esc(k))</key><string>\(esc(v))</string>"
        }
        xml += "</dict></plist>"
        return Data(xml.utf8)
    }

    /// Builds a compiled-loctable-shaped plist: `{ locale: { key: value } }`.
    private func loctableXML(_ byLocale: [String: [String: String]]) -> Data {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        """
        for (locale, table) in byLocale.sorted(by: { $0.key < $1.key }) {
            xml += "<key>\(esc(locale))</key><dict>"
            for (k, v) in table.sorted(by: { $0.key < $1.key }) {
                xml += "<key>\(esc(k))</key><string>\(esc(v))</string>"
            }
            xml += "</dict>"
        }
        xml += "</dict></plist>"
        return Data(xml.utf8)
    }

    private func resourcesDir(_ bundleRoot: URL) -> URL {
        bundleRoot
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
    }

    @Test func testLoctable_nestedInContentsResources_resolvesPreferredLocale() throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let resources = resourcesDir(bundleRoot)
        try fs.createDirectory(at: resources)

        let loctableURL = resources.appendingPathComponent("Localizable.nocache.loctable")
        try fs.writeData(
            loctableXML([
                "en": ["TA_L_002_NAME": "Tahoe Day", "MAC_WP_PPL_NAME": "Mac Purple"],
                "nl": ["TA_L_002_NAME": "Tahoe Dag"],
            ]),
            to: loctableURL,
            options: [.atomic]
        )

        let source = AerialLocalizedStringsSource(fileSystem: fs, locale: Locale(identifier: "en_US"))
        let strings = source.loadStrings(bundleRootURL: bundleRoot)

        #expect(strings["TA_L_002_NAME"]?.contains("Tahoe Day") == true)
        #expect(strings["MAC_WP_PPL_NAME"]?.contains("Mac Purple") == true)
        // Should only load the preferred locale, not the Dutch value.
        #expect(strings["TA_L_002_NAME"]?.contains("Tahoe Dag") == false)
    }

    @Test func testLoctable_skipsNonLocaleMetadataKeys() throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let resources = resourcesDir(bundleRoot)
        try fs.createDirectory(at: resources)

        // `LocProvenance` metadata should never be selected as a locale.
        let loctableURL = resources.appendingPathComponent("Localizable.nocache.loctable")
        try fs.writeData(
            loctableXML([
                "en": ["K": "Value"],
                "LocProvenance": ["ignored": "meta"],
            ]),
            to: loctableURL,
            options: [.atomic]
        )

        let source = AerialLocalizedStringsSource(fileSystem: fs, locale: Locale(identifier: "en_US"))
        let strings = source.loadStrings(bundleRootURL: bundleRoot)

        #expect(strings["K"]?.contains("Value") == true)
        #expect(strings["ignored"] == nil)
    }

    @Test func testLegacyLprojStrings_atBundleRoot_stillResolve() throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        try fs.writeData(
            stringsPlistXML(["A001_C001_NAME": "North Atlantic"]),
            to: en.appendingPathComponent("Localizable.nocache.strings"),
            options: [.atomic]
        )

        let source = AerialLocalizedStringsSource(fileSystem: fs, locale: Locale(identifier: "en_US"))
        let strings = source.loadStrings(bundleRootURL: bundleRoot)

        #expect(strings["A001_C001_NAME"]?.contains("North Atlantic") == true)
    }

    @Test func testLoctable_preferredOverEmptyLproj() throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let resources = resourcesDir(bundleRoot)
        let emptyEn = resources.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: resources)
        try fs.createDirectory(at: emptyEn) // empty .lproj, as on macOS 26

        try fs.writeData(
            loctableXML(["en": ["K": "FromLoctable"]]),
            to: resources.appendingPathComponent("Localizable.nocache.loctable"),
            options: [.atomic]
        )

        let source = AerialLocalizedStringsSource(fileSystem: fs, locale: Locale(identifier: "en_US"))
        let strings = source.loadStrings(bundleRootURL: bundleRoot)

        #expect(strings["K"]?.contains("FromLoctable") == true)
    }

    @Test func testEmptyBundle_returnsEmpty() throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)

        let source = AerialLocalizedStringsSource(fileSystem: fs, locale: Locale(identifier: "en_US"))
        let strings = source.loadStrings(bundleRootURL: bundleRoot)

        #expect(strings.isEmpty)
    }
}
