import Foundation
import Testing

@testable import AerialFlow

struct WallpaperStoreIndexPlistShapeTests {
    @Test func testSummary_legacyRootDesktopIdle() {
        let root: [String: Any] = [
            "Desktop": ["Choice": ["Foo": "Bar"]],
        ]

        let summary = WallpaperStoreIndexPlistShape.summarize(root: root)
        #expect(summary.description.contains("Legacy"))
    }

    @Test func testSummary_allSpacesAndDisplays_linked() {
        let root: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Type": "linked",
                "Linked": [
                    "Content": [
                        "Choices": [
                            ["Provider": "default", "Configuration": Data()]
                        ]
                    ]
                ],
            ]
        ]

        let summary = WallpaperStoreIndexPlistShape.summarize(root: root)
        #expect(summary.description.contains("AllSpacesAndDisplays: linked"))
    }

    @Test func testSummary_allSpacesAndDisplays_individual() {
        let root: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Type": "individual",
                "Desktop": ["Content": ["Choices": [["Foo": "Bar"]]]],
                "Idle": ["Content": ["Choices": [["Foo": "Bar"]]]],
            ]
        ]

        let summary = WallpaperStoreIndexPlistShape.summarize(root: root)
        #expect(summary.description.contains("AllSpacesAndDisplays: individual"))
    }

    @Test func testSummary_reportsBothContainersWhenPresent() {
        let root: [String: Any] = [
            "AllSpacesAndDisplays": [
                "Type": "linked",
                "Linked": [:],
            ],
            "SystemDefault": [
                "Type": "individual",
                "Desktop": [:],
                "Idle": [:],
            ],
        ]

        let summary = WallpaperStoreIndexPlistShape.summarize(root: root)
        #expect(summary.description.contains("AllSpacesAndDisplays: linked"))
        #expect(summary.description.contains("SystemDefault: individual"))
    }
}

