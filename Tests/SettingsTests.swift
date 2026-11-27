import XCTest
@testable import Tagivy

@MainActor
final class SettingsTests: XCTestCase {
    func testBetaBuildShowsItsBetaNumberAndBuild() {
        let version = AppVersion(info: [
            "CFBundleShortVersionString": "1.0.18",
            "CFBundleVersion": "23",
            AppConfiguration.betaNumberInfoKey: "5",
        ])

        XCTAssertEqual(version.displayVersion, "1.0.18 Beta 5")
        XCTAssertEqual(version.build, "23")
        XCTAssertTrue(version.description.contains("1.0.18 Beta 5"))
        XCTAssertTrue(version.description.contains("23"))
    }

    func testReleaseBuildShowsOnlyItsVersion() {
        for info: [String: Any] in [
            ["CFBundleShortVersionString": "1.0.18", "CFBundleVersion": "24", AppConfiguration.betaNumberInfoKey: ""],
            ["CFBundleShortVersionString": "1.0.18", "CFBundleVersion": "24"],
        ] {
            let version = AppVersion(info: info)
            XCTAssertNil(version.betaNumber)
            XCTAssertEqual(version.displayVersion, "1.0.18")
            XCTAssertFalse(version.description.contains("Beta"))
        }
    }

    func testDevelopmentBuildIsNotABetaBuild() {
        XCTAssertNil(AppConfiguration.version.betaNumber)
        XCTAssertFalse(AppConfiguration.isBetaBuild)
    }

    func testSettingsReopenOnTheLastViewedPane() {
        let defaults = UserDefaults(suiteName: "SettingsTests-\(UUID().uuidString)")!

        let first = makeSettings(defaults: defaults)
        XCTAssertEqual(first.selectedPane, .importOptions)

        _ = first.view
        first.selectedTabViewItemIndex = SettingsPane.allCases.firstIndex(of: .updates)!

        XCTAssertEqual(makeSettings(defaults: defaults).selectedPane, .updates)
    }

    func testUnknownSavedPaneFallsBackToTheFirst() {
        XCTAssertEqual(SettingsPane.initial(saved: "about", in: SettingsPane.allCases), .importOptions)
        XCTAssertEqual(SettingsPane.initial(saved: nil, in: SettingsPane.allCases), .importOptions)
    }

    private func makeSettings(defaults: UserDefaults) -> SettingsTabViewController {
        SettingsTabViewController(
            panes: SettingsPane.allCases.map { pane in
                let controller = NSViewController()
                controller.view = NSView()
                return (pane, controller)
            },
            defaults: defaults
        )
    }

    func testWindowsOfferNoTabBar() {
        XCTAssertFalse(NSWindow.allowsAutomaticWindowTabbing)
    }
}
