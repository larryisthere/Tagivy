import XCTest
@testable import Tagivy

@MainActor
final class PreferencesStoreTests: XCTestCase {
    func testAuthenticationDefaultsToDisabled() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        XCTAssertFalse(store.authenticationEnabled)
        XCTAssertEqual(store.idleLockInterval, .never)
    }

    func testAuthenticationPreferencePersists() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        store.setAuthenticationEnabled(true)

        XCTAssertTrue(PreferencesStore(defaults: defaults).authenticationEnabled)
    }

    func testIdleLockIntervalPersists() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)
        store.idleLockInterval = .fiveMinutes

        XCTAssertEqual(PreferencesStore(defaults: defaults).idleLockInterval, .fiveMinutes)
    }

    func testFolderImportPreferencesDefaultAndPersist() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults)

        XCTAssertEqual(store.folderImportPreference, .ask)
        XCTAssertFalse(store.includeSelectedFolderAsRootTag)

        store.folderImportPreference = .folderTags
        store.includeSelectedFolderAsRootTag = true

        let restored = PreferencesStore(defaults: defaults)
        XCTAssertEqual(restored.folderImportPreference, .folderTags)
        XCTAssertTrue(restored.includeSelectedFolderAsRootTag)
    }

    func testUnknownFolderImportPreferenceFallsBackToAsk() {
        let defaults = makeDefaults()
        defaults.set("future-value", forKey: PreferencesStore.Key.folderImportPreference)

        XCTAssertEqual(
            PreferencesStore(defaults: defaults).folderImportPreference,
            .ask
        )
    }

    func testBetaUpdatesDefaultOffInReleaseBuildsAndPersist() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults, isBetaBuild: false)
        XCTAssertFalse(store.receivesBetaUpdates)

        store.receivesBetaUpdates = true

        XCTAssertTrue(PreferencesStore(defaults: defaults, isBetaBuild: false).receivesBetaUpdates)
    }

    func testBetaBuildsReceiveBetasUntilTheUserOptsOut() {
        let defaults = makeDefaults()
        let store = PreferencesStore(defaults: defaults, isBetaBuild: true)
        XCTAssertTrue(store.receivesBetaUpdates)

        store.receivesBetaUpdates = false

        XCTAssertFalse(PreferencesStore(defaults: defaults, isBetaBuild: true).receivesBetaUpdates)
    }

    func testTesterKeepsReceivingBetasAfterUpdatingToARelease() {
        let defaults = makeDefaults()
        _ = PreferencesStore(defaults: defaults, isBetaBuild: true)

        XCTAssertTrue(PreferencesStore(defaults: defaults, isBetaBuild: false).receivesBetaUpdates)
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PreferencesStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

final class ProductDefaultsTests: XCTestCase {
    func testRecentlyAddedCoversThirtyDays() {
        XCTAssertEqual(LibraryFilter.recentlyAddedInterval, 30 * 24 * 60 * 60)
    }

    func testThumbnailCacheDefaultsToTwoGigabytes() {
        XCTAssertEqual(MediaProcessingService.defaultMaximumCacheBytes, 2 * 1_024 * 1_024 * 1_024)
    }

    @MainActor
    func testVideoGridDefaultsToOneHundredEightyPointThumbnails() throws {
        let suiteName = "ProductDefaultsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(VideoGridViewController.defaultGridItemWidth, 180)
        XCTAssertEqual(VideoGridViewController.persistedGridItemWidth(defaults: defaults), 180)
    }
}
