import XCTest
@testable import Tagivy

final class NumericConditionSliderTests: XCTestCase {
    func testEarlierPresetsAreDetentsSoSavedFiltersLandOnThem() {
        let saved: [(NumericConditionKind, [Double])] = [
            (.addedWithinDays, [7, 30, 90]),
            (.createdWithinDays, [7, 30, 90]),
            (.durationAtLeast, [60, 120, 300]),
            (.fileSizeAtLeast, [500_000_000, 1_000_000_000, 2_000_000_000]),
            (.resolutionWidthAtLeast, [1920, 3840]),
        ]
        for (kind, values) in saved {
            for value in values {
                XCTAssertTrue(kind.scale.detents.contains(value), "\(kind) \(value)")
                XCTAssertEqual(kind.rounded(value), value, "\(kind) \(value)")
            }
        }
    }

    func testDraggingNearADetentSnapsAndElsewhereMovesFreely() {
        let scale = NumericConditionKind.durationAtLeast.scale
        let fiveMinutes = scale.position(for: 300)
        XCTAssertEqual(scale.value(at: fiveMinutes + 0.02, snapping: true).detent, 300)
        XCTAssertNil(scale.value(at: fiveMinutes + 0.02, snapping: false).detent)
        let between = scale.value(at: (scale.position(for: 600) + scale.position(for: 1800)) / 2, snapping: true)
        XCTAssertNil(between.detent)
        XCTAssertGreaterThan(between.value, 600)
        XCTAssertLessThan(between.value, 1800)
    }

    func testLogarithmicPositionRoundTrips() {
        let scale = NumericConditionKind.fileSizeAtLeast.scale
        for value in [20_000_000.0, 750_000_000, 3_300_000_000, 80_000_000_000] {
            XCTAssertEqual(scale.value(at: scale.position(for: value), snapping: false).value, value, accuracy: value * 1e-9)
        }
        XCTAssertEqual(scale.position(for: 1), 0)
        XCTAssertEqual(scale.position(for: 1e15), 1)
    }

    func testResolutionOnlyStopsAtNamedSteps() {
        let scale = NumericConditionKind.resolutionWidthAtLeast.scale
        XCTAssertEqual(scale.value(at: 0.3, snapping: false).value, 1920)
        XCTAssertEqual(scale.position(for: 3840), 0.75)
        XCTAssertEqual(NumericConditionKind.resolutionWidthAtLeast.formatted(2560), "1440p")
    }

    func testDraggedValuesRoundToWhatTheFieldShows() {
        XCTAssertEqual(NumericConditionKind.durationAtLeast.rounded(2_247), 2_220)
        XCTAssertEqual(NumericConditionKind.durationAtLeast.rounded(47.3), 47)
        XCTAssertEqual(NumericConditionKind.fileSizeAtLeast.rounded(1_437_000_000), 1_400_000_000)
        XCTAssertEqual(NumericConditionKind.fileSizeAtLeast.rounded(743_400_000), 743_000_000)
        XCTAssertEqual(NumericConditionKind.addedWithinDays.rounded(123.4), 123)
        XCTAssertEqual(NumericConditionKind.addedWithinDays.rounded(0.2), 1)
    }

    func testTypedValuesAcceptUnitsAndKeepTheShownUnitForBareNumbers() {
        let size = NumericConditionKind.fileSizeAtLeast
        XCTAssertEqual(size.parse("1.5 GB", currentValue: 1_000_000_000), 1_500_000_000)
        XCTAssertEqual(size.parse("750mb", currentValue: 1_000_000_000), 750_000_000)
        XCTAssertEqual(size.parse("3", currentValue: 1_000_000_000), 3_000_000_000)
        XCTAssertEqual(size.parse("300", currentValue: 500_000_000), 300_000_000)

        let duration = NumericConditionKind.durationAtLeast
        XCTAssertEqual(duration.parse("90 s", currentValue: 60), 90)
        XCTAssertEqual(duration.parse("2h", currentValue: 60), 7_200)
        XCTAssertEqual(duration.parse("45 秒", currentValue: 60), 45)
        XCTAssertEqual(duration.parse("1.5 小时", currentValue: 60), 5_400)
        XCTAssertEqual(duration.parse("12", currentValue: 300), 720)

        XCTAssertEqual(NumericConditionKind.addedWithinDays.parse("14 天", currentValue: 30), 14)
        XCTAssertEqual(NumericConditionKind.resolutionWidthAtLeast.parse("4k", currentValue: 1920), 3840)
        XCTAssertEqual(NumericConditionKind.resolutionWidthAtLeast.parse("1080", currentValue: 3840), 1920)
    }

    func testTypedValuesBeyondTheSliderRangeAreKept() {
        XCTAssertEqual(NumericConditionKind.durationAtLeast.parse("8 h", currentValue: 60), 28_800)
        XCTAssertEqual(NumericConditionKind.addedWithinDays.parse("5000", currentValue: 30), 5_000)
    }

    func testHugeOrTinyTypedValuesStayWithinWhatCanBeStoredAndShown() {
        let size = NumericConditionKind.fileSizeAtLeast
        let huge = size.parse("99999999999 tb", currentValue: 1_000_000_000)
        XCTAssertEqual(huge, size.valueBounds.upperBound)
        XCTAssertEqual(huge.map { size.condition(with: $0) }, .fileSizeAtLeast(1_000_000_000_000_000))
        XCTAssertEqual(size.parse("500 kb", currentValue: 1_000_000_000), 1_000_000)
        XCTAssertEqual(
            NumericConditionKind.addedWithinDays.parse("99999999999999999999", currentValue: 30),
            36_500
        )
        XCTAssertNil(NumericConditionKind.durationAtLeast.parse(String(repeating: "9", count: 400), currentValue: 60))
    }

    func testCommaIsAThousandsSeparatorOnlyBeforeThreeDigits() {
        let size = NumericConditionKind.fileSizeAtLeast
        XCTAssertEqual(size.parse("1,000 MB", currentValue: 1_000_000_000), 1_000_000_000)
        XCTAssertEqual(size.parse("1,5 GB", currentValue: 1_000_000_000), 1_500_000_000)
    }

    func testTwoKMeansFourteenForty() {
        XCTAssertEqual(NumericConditionKind.resolutionWidthAtLeast.parse("2K", currentValue: 3840), 2560)
    }

    func testInvalidTextIsRejected() {
        XCTAssertNil(NumericConditionKind.fileSizeAtLeast.parse("big", currentValue: 1_000_000_000))
        XCTAssertNil(NumericConditionKind.durationAtLeast.parse("0", currentValue: 60))
        XCTAssertNil(NumericConditionKind.durationAtLeast.parse("5 GB", currentValue: 60))
    }

    func testConditionKeepsItsStoredUnit() {
        XCTAssertEqual(NumericConditionKind.durationAtLeast.condition(with: 90), .durationAtLeast(90))
        XCTAssertEqual(NumericConditionKind.fileSizeAtLeast.condition(with: 1_500_000_000), .fileSizeAtLeast(1_500_000_000))
        XCTAssertEqual(NumericConditionKind.value(of: .createdWithinDays(14)), 14)
    }
}
