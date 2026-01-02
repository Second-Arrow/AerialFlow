import Foundation
import Testing

@testable import AerialFlow

struct CategoryResolverTests {
    private func stringsPlistXML(_ dict: [String: String]) -> Data {
        // Minimal XML plist for PropertyListSerialization.
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        """
        for (k, v) in dict.sorted(by: { $0.key < $1.key }) {
            let ek = k.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            let ev = v.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            xml += "<key>\(ek)</key><string>\(ev)</string>"
        }
        xml += """
        </dict>
        </plist>
        """
        return Data(xml.utf8)
    }

    @Test func testResolveExcludedCategoryIDs_commaSplittingAndSubstringMatch() throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        let en = bundleRoot.appendingPathComponent("en.lproj", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)
        try fs.createDirectory(at: en)

        let stringsURL = en.appendingPathComponent("Localizable.strings")
        try fs.writeData(stringsPlistXML(["EarthKey": "Earth", "UnderwaterKey": "Underwater"]), to: stringsURL, options: [.atomic])

        let categories = [
            AerialCategory(id: "earth-id", localizedNameKey: "EarthKey"),
            AerialCategory(id: "underwater-id", localizedNameKey: "UnderwaterKey"),
        ]

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let result = resolver.resolveExcludedCategoryIDs(excludeTerms: ["Earth, Under"], categories: categories)

        #expect(result.excludedIDs.contains("earth-id"))
        #expect(result.excludedIDs.contains("underwater-id"))
    }

    @Test func testResolveExcludedCategoryIDs_matchesByExactID() throws {
        let fs = InMemoryFileSystem()
        let bundleRoot = URL(fileURLWithPath: "/Bundle", isDirectory: true)
        try fs.createDirectory(at: bundleRoot)

        let categories = [
            AerialCategory(id: "earth-id", localizedNameKey: nil),
            AerialCategory(id: "underwater-id", localizedNameKey: nil),
        ]

        let resolver = CategoryResolver(fileSystem: fs, bundleRootURL: bundleRoot)
        let result = resolver.resolveExcludedCategoryIDs(excludeTerms: ["underwater-id"], categories: categories)

        #expect(result.excludedIDs == ["underwater-id"])
    }
}


