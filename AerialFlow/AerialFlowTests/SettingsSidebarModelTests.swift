import Testing
@testable import AerialFlow

struct SettingsSidebarModelTests {
    @Test func testSections_matchSettingsViewSidebarOrderAndGrouping() async throws {
        #expect(SettingsSidebarModel.sections.map(\.title) == ["Settings", "Tools", "Other"])

        #expect(SettingsSidebarModel.sections[0].destinations == [.general, .rotation, .filtering, .exclusions, .hotkeys])
        #expect(SettingsSidebarModel.sections[1].destinations == [.diagnostics])
        #expect(SettingsSidebarModel.sections[2].destinations == [.advanced, .about])
    }
}

