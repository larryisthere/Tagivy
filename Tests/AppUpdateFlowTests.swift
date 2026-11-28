import XCTest
@testable import Tagivy

final class AppUpdateFlowTests: XCTestCase {
    func testBackgroundCheckWithoutUpdateOrWithErrorShowsNothing() {
        var flow = AppUpdateFlow()
        flow.noUpdateFound()
        XCTAssertEqual(flow.status, .idle)

        flow.failed()
        XCTAssertEqual(flow.status, .idle)
    }

    func testUserCheckReportsUpToDateThenGoesAway() {
        var flow = AppUpdateFlow()
        flow.userCheckStarted()
        XCTAssertEqual(flow.status, .checking)

        flow.noUpdateFound()
        XCTAssertEqual(flow.status, .upToDate)
        XCTAssertTrue(flow.status.dismissesAutomatically)

        flow.acknowledged()
        XCTAssertEqual(flow.status, .idle)
    }

    func testUserCheckReportsFailure() {
        var flow = AppUpdateFlow()
        flow.userCheckStarted()
        flow.failed()
        XCTAssertEqual(flow.status, .failed)
    }

    func testSilentDownloadOffersRelaunchThatSurvivesSessionEnd() {
        var flow = AppUpdateFlow()
        flow.readyToInstallOnQuit(version: "1.0.19")
        XCTAssertEqual(flow.status, .readyToRelaunch(version: "1.0.19"))

        flow.dismissed(canStillRelaunch: true)
        XCTAssertEqual(flow.status, .readyToRelaunch(version: "1.0.19"))

        XCTAssertTrue(flow.userChoseToInstall())
    }

    func testRelaunchIsNotOfferedOnceSparkleCanNoLongerPerformIt() {
        var flow = AppUpdateFlow()
        flow.updateFound(version: "1.0.19", stage: .downloaded)
        flow.dismissed(canStillRelaunch: false)
        XCTAssertEqual(flow.status, .idle)
    }

    func testFoundUpdateIsOfferedByStage() {
        var flow = AppUpdateFlow()
        flow.updateFound(version: "1.0.19", stage: .notDownloaded)
        XCTAssertEqual(flow.status, .available(version: "1.0.19"))

        flow.updateFound(version: "1.0.19", stage: .downloaded)
        XCTAssertEqual(flow.status, .readyToRelaunch(version: "1.0.19"))

        flow.updateFound(version: "1.0.19", stage: .installing)
        XCTAssertEqual(flow.status, .readyToRelaunch(version: "1.0.19"))
    }

    func testOneClickDownloadsThenInstallsWithoutAskingAgain() {
        var flow = AppUpdateFlow()
        flow.updateFound(version: "1.0.19 Beta 1", stage: .notDownloaded)
        XCTAssertTrue(flow.userChoseToInstall())

        flow.downloadStarted()
        XCTAssertEqual(flow.status, .downloading(version: "1.0.19 Beta 1", fraction: nil))
        flow.downloadExpectedLength(200)
        flow.downloadReceived(50)
        XCTAssertEqual(flow.status, .downloading(version: "1.0.19 Beta 1", fraction: 0.25))
        flow.downloadReceived(500)
        XCTAssertEqual(flow.status, .downloading(version: "1.0.19 Beta 1", fraction: 1))

        flow.extractionStarted()
        XCTAssertEqual(flow.status, .preparing(version: "1.0.19 Beta 1"))
        XCTAssertTrue(flow.readyToInstall())
    }

    func testDownloadReadyWithoutClickWaitsForRelaunchButton() {
        var flow = AppUpdateFlow()
        flow.downloadStarted()
        XCTAssertFalse(flow.readyToInstall())
        XCTAssertEqual(flow.status, .readyToRelaunch(version: ""))
    }

    func testFailedDownloadAfterClickIsReported() {
        var flow = AppUpdateFlow()
        flow.updateFound(version: "1.0.19", stage: .notDownloaded)
        XCTAssertTrue(flow.userChoseToInstall())
        flow.downloadStarted()
        flow.failed()
        XCTAssertEqual(flow.status, .failed)
    }

    func testClickWithNothingToInstallDoesNothing() {
        var flow = AppUpdateFlow()
        XCTAssertFalse(flow.userChoseToInstall())
        flow.userCheckStarted()
        XCTAssertFalse(flow.userChoseToInstall())
    }

    func testAppMenuInstallsOnlyOnceAnUpdateIsReadyToRelaunch() {
        XCTAssertEqual(AppUpdateStatus.readyToRelaunch(version: "1.0.19").menuCommand, .relaunchToInstall)
        let others: [AppUpdateStatus] = [
            .idle, .checking, .upToDate, .available(version: "1.0.19"),
            .downloading(version: "1.0.19", fraction: 0.5), .preparing(version: "1.0.19"), .installing, .failed,
        ]
        for status in others {
            XCTAssertEqual(status.menuCommand, .checkForUpdates, "\(status)")
        }
    }
}
