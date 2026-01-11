import Foundation
import Testing

@testable import AerialFlow

struct WallpaperStoreEditorTests {
    @Test func testApply_updatesAllProviderNodes_andCreatesBackup() throws {
        let fs = InMemoryFileSystem()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000) // deterministic stamp
        let editor = WallpaperStoreEditor(fileSystem: fs, now: { fixedDate })

        let storeDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try fs.createDirectory(at: storeDir)
        let indexURL = storeDir.appendingPathComponent("Index.plist")

        // Build a minimal tree with two provider nodes, one under Desktop and one under Idle.
        func configData(assetID: String) throws -> Data {
            try PropertyListSerialization.data(
                fromPropertyList: ["assetID": assetID],
                format: .binary,
                options: 0
            )
        }

        let root: [String: Any] = [
            "Desktop": [
                "LastSet": Date(timeIntervalSince1970: 0),
                "Choice": [
                    "Provider": "com.apple.wallpaper.choice.aerials",
                    "Configuration": try configData(assetID: "OLD-1"),
                ],
            ],
            "Idle": [
                "LastUse": Date(timeIntervalSince1970: 0),
                "Nodes": [
                    [
                        "Provider": "com.apple.wallpaper.choice.aerials",
                        "Configuration": try configData(assetID: "OLD-2"),
                    ]
                ]
            ],
        ]

        let originalData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(originalData, to: indexURL, options: [.atomic])

        let result = try editor.applyAerialAssetID("NEW", indexPlistURL: indexURL, backupRetentionCount: 10)
        #expect(result.updatedProviderNodeCount == 2)
        #expect(fs.fileExists(at: result.backupURL))

        let updatedData = try fs.readData(from: indexURL)
        let updatedAny = try PropertyListSerialization.propertyList(from: updatedData, options: [], format: nil)
        let updatedRoot = try #require(updatedAny as? [String: Any])

        let desktop = try #require(updatedRoot["Desktop"] as? [String: Any])
        #expect(desktop["LastSet"] as? Date == fixedDate)
        let desktopChoice = try #require(desktop["Choice"] as? [String: Any])
        let desktopCfgData = try #require(desktopChoice["Configuration"] as? Data)
        let desktopCfgAny = try PropertyListSerialization.propertyList(from: desktopCfgData, options: [], format: nil)
        let desktopCfg = try #require(desktopCfgAny as? [String: Any])
        #expect(desktopCfg["assetID"] as? String == "NEW")

        let idle = try #require(updatedRoot["Idle"] as? [String: Any])
        #expect(idle["LastUse"] as? Date == fixedDate)
        let idleNodes = try #require(idle["Nodes"] as? [Any])
        let idleNode0 = try #require(idleNodes.first as? [String: Any])
        let idleCfgData = try #require(idleNode0["Configuration"] as? Data)
        let idleCfgAny = try PropertyListSerialization.propertyList(from: idleCfgData, options: [], format: nil)
        let idleCfg = try #require(idleCfgAny as? [String: Any])
        #expect(idleCfg["assetID"] as? String == "NEW")
    }

    @Test func testInspectConfiguration_reportsConfigured_whenDesktopAndIdleNodesPresent() throws {
        let fs = InMemoryFileSystem()
        let editor = WallpaperStoreEditor(fileSystem: fs)

        let storeDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try fs.createDirectory(at: storeDir)
        let indexURL = storeDir.appendingPathComponent("Index.plist")

        func configData(assetID: String) throws -> Data {
            try PropertyListSerialization.data(
                fromPropertyList: ["assetID": assetID],
                format: .binary,
                options: 0
            )
        }

        let root: [String: Any] = [
            "Desktop": [
                "Choice": [
                    "Provider": "com.apple.wallpaper.choice.aerials",
                    "Configuration": try configData(assetID: "A"),
                ],
            ],
            "Idle": [
                "Nodes": [
                    [
                        "Provider": "com.apple.wallpaper.choice.aerials",
                        "Configuration": try configData(assetID: "B"),
                    ]
                ]
            ],
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(data, to: indexURL, options: [.atomic])

        let status = try editor.inspectAerialConfiguration(indexPlistURL: indexURL)
        #expect(status.isLikelyConfigured == true)
        #expect(status.totalProviderNodes == 2)
        #expect(status.desktopProviderNodes == 1)
        #expect(status.idleProviderNodes == 1)
    }

    @Test func testRepairConfiguration_upsertsProviderNodes_whenSafeContainersExist() throws {
        let fs = InMemoryFileSystem()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let editor = WallpaperStoreEditor(fileSystem: fs, now: { fixedDate })

        let storeDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try fs.createDirectory(at: storeDir)
        let indexURL = storeDir.appendingPathComponent("Index.plist")

        // No provider nodes, but safe containers exist (Desktop.Choice, Idle.Nodes[0]).
        let root: [String: Any] = [
            "Desktop": [
                "LastSet": Date(timeIntervalSince1970: 0),
                "Choice": [
                    "SomeOtherKey": "value"
                ],
            ],
            "Idle": [
                "LastUse": Date(timeIntervalSince1970: 0),
                "Nodes": [
                    [
                        "SomeOtherKey": "value"
                    ]
                ]
            ],
        ]

        let originalData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(originalData, to: indexURL, options: [.atomic])

        let repair = try editor.repairAerialConfiguration(desiredAssetID: "NEW", indexPlistURL: indexURL, backupRetentionCount: 10)
        #expect(repair.didUpsertProviderNodes == true)
        #expect(repair.updatedProviderNodeCount == 2)
        #expect(fs.fileExists(at: repair.backupURL))

        let status = try editor.inspectAerialConfiguration(indexPlistURL: indexURL)
        #expect(status.totalProviderNodes == 2)

        let updatedData = try fs.readData(from: indexURL)
        let updatedAny = try PropertyListSerialization.propertyList(from: updatedData, options: [], format: nil)
        let updatedRoot = try #require(updatedAny as? [String: Any])

        let desktop = try #require(updatedRoot["Desktop"] as? [String: Any])
        #expect(desktop["LastSet"] as? Date == fixedDate)
        let desktopChoice = try #require(desktop["Choice"] as? [String: Any])
        #expect(desktopChoice["Provider"] as? String == "com.apple.wallpaper.choice.aerials")
        let desktopCfgData = try #require(desktopChoice["Configuration"] as? Data)
        let desktopCfgAny = try PropertyListSerialization.propertyList(from: desktopCfgData, options: [], format: nil)
        let desktopCfg = try #require(desktopCfgAny as? [String: Any])
        #expect(desktopCfg["assetID"] as? String == "NEW")

        let idle = try #require(updatedRoot["Idle"] as? [String: Any])
        #expect(idle["LastUse"] as? Date == fixedDate)
        let idleNodes = try #require(idle["Nodes"] as? [Any])
        let idleNode0 = try #require(idleNodes.first as? [String: Any])
        #expect(idleNode0["Provider"] as? String == "com.apple.wallpaper.choice.aerials")
        let idleCfgData = try #require(idleNode0["Configuration"] as? Data)
        let idleCfgAny = try PropertyListSerialization.propertyList(from: idleCfgData, options: [], format: nil)
        let idleCfg = try #require(idleCfgAny as? [String: Any])
        #expect(idleCfg["assetID"] as? String == "NEW")
    }

    @Test func testRepairConfiguration_upsertsProviderNodes_whenSafeContainersExist_macos15IndividualShape() throws {
        let fs = InMemoryFileSystem()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let editor = WallpaperStoreEditor(fileSystem: fs, now: { fixedDate })

        let storeDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try fs.createDirectory(at: storeDir)
        let indexURL = storeDir.appendingPathComponent("Index.plist")

        // macOS 15 shape: provider nodes live in Section.Content.Choices[0].
        // Start with safe containers but no Aerial provider nodes configured.
        let makeChoice0: [String: Any] = [
            "SomeOtherKey": "value"
        ]
        let makeSection: [String: Any] = [
            "LastSet": Date(timeIntervalSince1970: 0),
            "LastUse": Date(timeIntervalSince1970: 0),
            "Content": [
                "Choices": [makeChoice0],
                "Shuffle": "$null",
            ],
        ]

        let root: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Type": "individual",
                "Desktop": makeSection,
                "Idle": makeSection,
            ],
            "SystemDefault": [
                "Type": "individual",
                "Desktop": makeSection,
                "Idle": makeSection,
            ],
        ]

        let originalData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(originalData, to: indexURL, options: [.atomic])

        let repair = try editor.repairAerialConfiguration(desiredAssetID: "NEW", indexPlistURL: indexURL, backupRetentionCount: 10)
        #expect(repair.didUpsertProviderNodes == true)
        // Desktop+Idle in 2 containers.
        #expect(repair.updatedProviderNodeCount == 4)
        #expect(fs.fileExists(at: repair.backupURL))

        let updatedData = try fs.readData(from: indexURL)
        let updatedAny = try PropertyListSerialization.propertyList(from: updatedData, options: [], format: nil)
        let updatedRoot = try #require(updatedAny as? [String: Any])

        func readAssetID(containerKey: String, sectionKey: String) throws -> String {
            let container = try #require(updatedRoot[containerKey] as? [String: Any])
            let section = try #require(container[sectionKey] as? [String: Any])
            #expect(section["LastSet"] as? Date == fixedDate)
            #expect(section["LastUse"] as? Date == fixedDate)
            let content = try #require(section["Content"] as? [String: Any])
            let choices = try #require(content["Choices"] as? [Any])
            let choice0 = try #require(choices.first as? [String: Any])
            #expect(choice0["Provider"] as? String == "com.apple.wallpaper.choice.aerials")
            let cfgData = try #require(choice0["Configuration"] as? Data)
            let cfgAny = try PropertyListSerialization.propertyList(from: cfgData, options: [], format: nil)
            let cfg = try #require(cfgAny as? [String: Any])
            return try #require(cfg["assetID"] as? String)
        }

        #expect(try readAssetID(containerKey: "AllSpacesAndDisplays", sectionKey: "Desktop") == "NEW")
        #expect(try readAssetID(containerKey: "AllSpacesAndDisplays", sectionKey: "Idle") == "NEW")
        #expect(try readAssetID(containerKey: "SystemDefault", sectionKey: "Desktop") == "NEW")
        #expect(try readAssetID(containerKey: "SystemDefault", sectionKey: "Idle") == "NEW")
    }

    @Test func testApply_touchesTimestampsForLinkedShape_macos15() throws {
        let fs = InMemoryFileSystem()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let editor = WallpaperStoreEditor(fileSystem: fs, now: { fixedDate })

        let storeDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try fs.createDirectory(at: storeDir)
        let indexURL = storeDir.appendingPathComponent("Index.plist")

        func configData(assetID: String) throws -> Data {
            try PropertyListSerialization.data(
                fromPropertyList: ["assetID": assetID],
                format: .binary,
                options: 0
            )
        }

        let linkedSection: [String: Any] = [
            "LastSet": Date(timeIntervalSince1970: 0),
            "LastUse": Date(timeIntervalSince1970: 0),
            "Content": [
                "Choices": [
                    [
                        "Provider": "com.apple.wallpaper.choice.aerials",
                        "Configuration": try configData(assetID: "OLD"),
                    ]
                ]
            ]
        ]

        let root: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Type": "linked",
                "Linked": linkedSection,
            ]
        ]

        let originalData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(originalData, to: indexURL, options: [.atomic])

        let result = try editor.applyAerialAssetID("NEW", indexPlistURL: indexURL, backupRetentionCount: 10)
        #expect(result.updatedProviderNodeCount == 1)

        let updatedData = try fs.readData(from: indexURL)
        let updatedAny = try PropertyListSerialization.propertyList(from: updatedData, options: [], format: nil)
        let updatedRoot = try #require(updatedAny as? [String: Any])
        let all = try #require(updatedRoot["AllSpacesAndDisplays"] as? [String: Any])
        let linked = try #require(all["Linked"] as? [String: Any])
        #expect(linked["LastSet"] as? Date == fixedDate)
        #expect(linked["LastUse"] as? Date == fixedDate)
    }

    @Test func testRepairConfiguration_throwsWhenUnsupportedShape() throws {
        let fs = InMemoryFileSystem()
        let editor = WallpaperStoreEditor(fileSystem: fs)

        let storeDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try fs.createDirectory(at: storeDir)
        let indexURL = storeDir.appendingPathComponent("Index.plist")

        // No Desktop/Idle container: we refuse to insert new structure.
        let root: [String: Any] = [
            "SomethingElse": [
                "Choice": ["Foo": "Bar"]
            ]
        ]

        let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(data, to: indexURL, options: [.atomic])

        do {
            _ = try editor.repairAerialConfiguration(desiredAssetID: "NEW", indexPlistURL: indexURL, backupRetentionCount: 10)
            #expect(Bool(false))
        } catch let error as WallpaperStoreEditor.EditorError {
            switch error {
            case .unsupportedPlistShapeForUpsert:
                #expect(Bool(true))
            default:
                #expect(Bool(false))
            }
        } catch {
            #expect(Bool(false))
        }
    }

    @Test func testApply_prunesOldBackups_keepsMostRecentN() throws {
        let fs = InMemoryFileSystem()
        let date1 = Date(timeIntervalSince1970: 1_700_000_000)
        let editor = WallpaperStoreEditor(fileSystem: fs, now: { date1 })

        let storeDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try fs.createDirectory(at: storeDir)
        let indexURL = storeDir.appendingPathComponent("Index.plist")

        func configData(assetID: String) throws -> Data {
            try PropertyListSerialization.data(
                fromPropertyList: ["assetID": assetID],
                format: .binary,
                options: 0
            )
        }

        let root: [String: Any] = [
            "Desktop": [
                "Choice": [
                    "Provider": "com.apple.wallpaper.choice.aerials",
                    "Configuration": try configData(assetID: "OLD"),
                ],
            ],
        ]

        let originalData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(originalData, to: indexURL, options: [.atomic])

        // Create 12 backups with deterministic timestamps (newest should be kept).
        for i in 0..<12 {
            let stampDate = date1.addingTimeInterval(TimeInterval(i))
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let stamp = formatter.string(from: stampDate)
            let backupURL = storeDir.appendingPathComponent("Index.plist.\(stamp).bak")
            try fs.writeData(Data("b\(i)".utf8), to: backupURL, options: [.atomic])
        }

        _ = try editor.applyAerialAssetID("NEW", indexPlistURL: indexURL, backupRetentionCount: 10)

        let files = try fs.listFiles(in: storeDir)
        let backups = files.filter { $0.lastPathComponent.hasPrefix("Index.plist.") && $0.lastPathComponent.hasSuffix(".bak") }
        #expect(backups.count == 10)
    }

    @Test func testApply_throwsConfigDecodeFailed_whenConfigurationPlistIsNotDictionary() throws {
        let fs = InMemoryFileSystem()
        let editor = WallpaperStoreEditor(fileSystem: fs)

        let storeDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try fs.createDirectory(at: storeDir)
        let indexURL = storeDir.appendingPathComponent("Index.plist")

        // This is a valid plist, but not a dictionary shape.
        let nonDictionaryConfig = try PropertyListSerialization.data(
            fromPropertyList: ["assetID"],
            format: .binary,
            options: 0
        )

        let root: [String: Any] = [
            "Desktop": [
                "Choice": [
                    "Provider": "com.apple.wallpaper.choice.aerials",
                    "Configuration": nonDictionaryConfig,
                ],
            ],
        ]

        let originalData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(originalData, to: indexURL, options: [.atomic])

        do {
            _ = try editor.applyAerialAssetID("NEW", indexPlistURL: indexURL, backupRetentionCount: 10)
            #expect(Bool(false))
        } catch let error as WallpaperStoreEditor.EditorError {
            switch error {
            case .configDecodeFailed:
                #expect(Bool(true))
            default:
                #expect(Bool(false))
            }
        } catch {
            #expect(Bool(false))
        }
    }

    @Test func testApply_throwsNoProviderNodesFound_whenNoProviderNodesExist() throws {
        let fs = InMemoryFileSystem()
        let editor = WallpaperStoreEditor(fileSystem: fs)

        let storeDir = URL(fileURLWithPath: "/Users/test/Library/Application Support/com.apple.wallpaper/Store", isDirectory: true)
        try fs.createDirectory(at: storeDir)
        let indexURL = storeDir.appendingPathComponent("Index.plist")

        // Containers exist, but no matching provider nodes.
        let root: [String: Any] = [
            "Desktop": [
                "Choice": [
                    "Provider": "some.other.provider",
                    "Configuration": Data("not-a-plist".utf8),
                ],
            ],
            "Idle": [
                "Nodes": [
                    [
                        "Provider": "some.other.provider",
                        "Configuration": Data("not-a-plist".utf8),
                    ]
                ]
            ],
        ]

        let originalData = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
        try fs.writeData(originalData, to: indexURL, options: [.atomic])

        do {
            _ = try editor.applyAerialAssetID("NEW", indexPlistURL: indexURL, backupRetentionCount: 10)
            #expect(Bool(false))
        } catch let error as WallpaperStoreEditor.EditorError {
            switch error {
            case .noProviderNodesFound:
                #expect(Bool(true))
            default:
                #expect(Bool(false))
            }
        } catch {
            #expect(Bool(false))
        }
    }
}


