import XCTest
@testable import Tagivy

final class NumericConditionSliderTests: XCTestCase {
    func testEarlierPresetsAreDetentsSoSavedFiltersLandOnThem() {
        let saved: [(NumericConditionKind, [Double])] = [
            (.addedWithinDays, [7, 30, 90]),
            (.createdWithinDays, [7, 30, 90]),
            (.duration, [60, 120, 300]),
            (.fileSize, [500_000_000, 1_000_000_000, 2_000_000_000]),
            (.resolutionWidth, [1920, 3840]),
        ]
        for (kind, values) in saved {
            for value in values {
                XCTAssertTrue(kind.scale.detents.contains(value), "\(kind) \(value)")
                XCTAssertEqual(kind.rounded(value), value, "\(kind) \(value)")
            }
        }
    }

    func testDraggingNearADetentSnapsAndElsewhereMovesFreely() {
        let scale = NumericConditionKind.duration.scale
        let fiveMinutes = scale.position(for: 300)
        XCTAssertEqual(scale.value(at: fiveMinutes + 0.02, snapping: true).detent, 300)
        XCTAssertNil(scale.value(at: fiveMinutes + 0.02, snapping: false).detent)
        let between = scale.value(at: (scale.position(for: 600) + scale.position(for: 1800)) / 2, snapping: true)
        XCTAssertNil(between.detent)
        XCTAssertGreaterThan(between.value, 600)
        XCTAssertLessThan(between.value, 1800)
    }

    func testLogarithmicPositionRoundTrips() {
        let scale = NumericConditionKind.fileSize.scale
        for value in [20_000_000.0, 750_000_000, 3_300_000_000, 80_000_000_000] {
            XCTAssertEqual(scale.value(at: scale.position(for: value), snapping: false).value, value, accuracy: value * 1e-9)
        }
        XCTAssertEqual(scale.position(for: 1), 0)
        XCTAssertEqual(scale.position(for: 1e15), 1)
    }

    func testResolutionOnlyStopsAtNamedSteps() {
        let scale = NumericConditionKind.resolutionWidth.scale
        XCTAssertEqual(scale.value(at: 0.3, snapping: false).value, 1920)
        XCTAssertEqual(scale.position(for: 3840), 0.75)
        XCTAssertEqual(NumericConditionKind.resolutionWidth.formatted(2560), "1440p")
    }

    func testDraggedValuesRoundToWhatTheFieldShows() {
        XCTAssertEqual(NumericConditionKind.duration.rounded(2_247), 2_220)
        XCTAssertEqual(NumericConditionKind.duration.rounded(47.3), 47)
        XCTAssertEqual(NumericConditionKind.fileSize.rounded(1_437_000_000), 1_400_000_000)
        XCTAssertEqual(NumericConditionKind.fileSize.rounded(743_400_000), 743_000_000)
        XCTAssertEqual(NumericConditionKind.addedWithinDays.rounded(123.4), 123)
        XCTAssertEqual(NumericConditionKind.addedWithinDays.rounded(0.2), 1)
    }

    func testTypedValuesAcceptUnitsAndKeepTheShownUnitForBareNumbers() {
        let size = NumericConditionKind.fileSize
        XCTAssertEqual(size.parse("1.5 GB", currentValue: 1_000_000_000), 1_500_000_000)
        XCTAssertEqual(size.parse("750mb", currentValue: 1_000_000_000), 750_000_000)
        XCTAssertEqual(size.parse("3", currentValue: 1_000_000_000), 3_000_000_000)
        XCTAssertEqual(size.parse("300", currentValue: 500_000_000), 300_000_000)

        let duration = NumericConditionKind.duration
        XCTAssertEqual(duration.parse("90 s", currentValue: 60), 90)
        XCTAssertEqual(duration.parse("2h", currentValue: 60), 7_200)
        XCTAssertEqual(duration.parse("45 秒", currentValue: 60), 45)
        XCTAssertEqual(duration.parse("1.5 小时", currentValue: 60), 5_400)
        XCTAssertEqual(duration.parse("12", currentValue: 300), 720)

        XCTAssertEqual(NumericConditionKind.addedWithinDays.parse("14 天", currentValue: 30), 14)
        XCTAssertEqual(NumericConditionKind.resolutionWidth.parse("4k", currentValue: 1920), 3840)
        XCTAssertEqual(NumericConditionKind.resolutionWidth.parse("1080", currentValue: 3840), 1920)
    }

    func testTypedValuesBeyondTheSliderRangeAreKept() {
        XCTAssertEqual(NumericConditionKind.duration.parse("8 h", currentValue: 60), 28_800)
        XCTAssertEqual(NumericConditionKind.addedWithinDays.parse("5000", currentValue: 30), 5_000)
    }

    func testHugeOrTinyTypedValuesStayWithinWhatCanBeStoredAndShown() {
        let size = NumericConditionKind.fileSize
        let huge = size.parse("99999999999 tb", currentValue: 1_000_000_000)
        XCTAssertEqual(huge, size.valueBounds.upperBound)
        XCTAssertEqual(huge.map { size.condition(with: $0) }, .fileSizeRange(min: 1_000_000_000_000_000, max: nil))
        XCTAssertEqual(size.parse("500 kb", currentValue: 1_000_000_000), 1_000_000)
        XCTAssertEqual(
            NumericConditionKind.addedWithinDays.parse("99999999999999999999", currentValue: 30),
            36_500
        )
        XCTAssertNil(NumericConditionKind.duration.parse(String(repeating: "9", count: 400), currentValue: 60))
        XCTAssertNil(NumericConditionKind.resolutionWidth.parse("99999999999999999999", currentValue: 3840))
        XCTAssertNil(NumericConditionKind.resolutionWidth.parse(String(repeating: "9", count: 400), currentValue: 3840))
    }

    func testCommaIsAThousandsSeparatorOnlyBeforeThreeDigits() {
        let size = NumericConditionKind.fileSize
        XCTAssertEqual(size.parse("1,000 MB", currentValue: 1_000_000_000), 1_000_000_000)
        XCTAssertEqual(size.parse("1,5 GB", currentValue: 1_000_000_000), 1_500_000_000)
    }

    func testTwoKMeansFourteenForty() {
        XCTAssertEqual(NumericConditionKind.resolutionWidth.parse("2K", currentValue: 3840), 2560)
    }

    func testInvalidTextIsRejected() {
        XCTAssertNil(NumericConditionKind.fileSize.parse("big", currentValue: 1_000_000_000))
        XCTAssertNil(NumericConditionKind.duration.parse("0", currentValue: 60))
        XCTAssertNil(NumericConditionKind.duration.parse("5 GB", currentValue: 60))
    }

    func testConditionKeepsItsStoredUnit() {
        XCTAssertEqual(NumericConditionKind.duration.condition(with: 90), .durationRange(min: 90, max: nil))
        XCTAssertEqual(NumericConditionKind.fileSize.condition(with: 1_500_000_000), .fileSizeRange(min: 1_500_000_000, max: nil))
        XCTAssertEqual(NumericConditionKind.value(of: .createdWithinDays(14)), 14)
    }

    func testLegacyLowerBoundFiltersDecodeAsOpenEndedRanges() throws {
        let saved = Data(#"""
        {"requiredTagIDs":[],"requiredConditions":[{"durationAtLeast":{"_0":60}}],"filenameContains":[],
        "matchMode":"all","conditions":[{"fileSizeAtLeast":{"_0":1000000000}},{"resolutionWidthAtLeast":{"_0":3840}},
        {"addedWithinDays":{"_0":30}},{"untagged":{}},{"tags":{"operator":"any","tagIDs":["t"]}}],
        "sort":{"key":"filename","direction":"ascending"}}
        """#.utf8)
        let rule = try JSONDecoder().decode(LibraryQueryRule.self, from: saved)
        XCTAssertEqual(rule.requiredConditions, [.durationRange(min: 60, max: nil)])
        XCTAssertEqual(rule.conditions, [
            .fileSizeRange(min: 1_000_000_000, max: nil),
            .resolutionWidthRange(min: 3840, max: nil),
            .addedWithinDays(30),
            .untagged,
            .tags(operator: .any, tagIDs: ["t"]),
        ])
    }

    func testRangesRoundTripAndOmitOpenEnds() throws {
        let conditions: [LibraryFilterCondition] = [
            .durationRange(min: nil, max: 10),
            .fileSizeRange(min: 1_000_000_000, max: 5_000_000_000),
            .resolutionWidthRange(min: 1920, max: nil),
        ]
        let data = try JSONEncoder().encode(conditions)
        XCTAssertEqual(try JSONDecoder().decode([LibraryFilterCondition].self, from: data), conditions)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#"{"durationRange":{"max":10}}"#))
    }

    func testRangeWithoutBoundsIsRejectedAndSwappedBoundsAreOrdered() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(LibraryFilterCondition.self, from: Data(#"{"durationRange":{}}"#.utf8)))
        let swapped = try JSONDecoder().decode(
            LibraryFilterCondition.self,
            from: Data(#"{"fileSizeRange":{"min":9,"max":3}}"#.utf8)
        )
        XCTAssertEqual(swapped, .fileSizeRange(min: 3, max: 9))
        XCTAssertEqual(NumericConditionKind.duration.condition(min: 300, max: 60), .durationRange(min: 60, max: 300))
        XCTAssertEqual(
            LibraryQueryRule(conditions: [.resolutionWidthRange(min: 3840, max: 1920)]).normalized().conditions,
            [.resolutionWidthRange(min: 1920, max: 3840)]
        )
    }

    func testNewRangeConditionsStartAtTheEarlierDefaultWithNoMaximum() {
        XCTAssertEqual(NumericConditionKind.duration.defaultCondition, .durationRange(min: 60, max: nil))
        XCTAssertEqual(NumericConditionKind.fileSize.defaultCondition, .fileSizeRange(min: 1_000_000_000, max: nil))
        XCTAssertEqual(NumericConditionKind.resolutionWidth.defaultCondition, .resolutionWidthRange(min: 3840, max: nil))
        XCTAssertFalse(NumericConditionKind.addedWithinDays.isRange)
        XCTAssertTrue(NumericConditionKind.duration.isRange)
    }

    func testChipTextShowsBothBoundsOrTheOneThatIsSet() throws {
        let minute = NumericConditionKind.duration.formatted(60)
        let tenSeconds = NumericConditionKind.duration.formatted(10)
        let durationBoth = try XCTUnwrap(NumericConditionKind.label(for: .durationRange(min: 60, max: 300)))
        let durationMax = try XCTUnwrap(NumericConditionKind.label(for: .durationRange(min: nil, max: 10)))
        let durationMin = try XCTUnwrap(NumericConditionKind.label(for: .durationRange(min: 60, max: nil)))
        XCTAssertTrue(durationBoth.hasSuffix(NumericConditionKind.duration.formattedRange(60, 300)), durationBoth)
        XCTAssertTrue(durationMax.hasSuffix("≤ \(tenSeconds)"), durationMax)
        XCTAssertTrue(durationMin.hasSuffix("≥ \(minute)"), durationMin)

        XCTAssertEqual(NumericConditionKind.fileSize.formattedRange(1_000_000_000, 5_000_000_000), "1–5 GB")
        XCTAssertEqual(NumericConditionKind.fileSize.formattedRange(500_000_000, 2_000_000_000), "500 MB–2 GB")
        XCTAssertEqual(NumericConditionKind.resolutionWidth.formattedRange(1920, 3840), "1080p–4K")
        XCTAssertEqual(NumericConditionKind.resolutionWidth.formattedRange(3840, 3840), "4K")
        let sizeBoth = try XCTUnwrap(NumericConditionKind.label(for: .fileSizeRange(min: 1_000_000_000, max: 5_000_000_000)))
        let sizeMax = try XCTUnwrap(NumericConditionKind.label(for: .fileSizeRange(min: nil, max: 2_000_000_000)))
        let resolutionBoth = try XCTUnwrap(NumericConditionKind.label(for: .resolutionWidthRange(min: 1920, max: 3840)))
        let resolutionMin = try XCTUnwrap(NumericConditionKind.label(for: .resolutionWidthRange(min: 3840, max: nil)))
        XCTAssertTrue(sizeBoth.hasSuffix(" 1–5 GB"), sizeBoth)
        XCTAssertTrue(sizeMax.hasSuffix(" ≤ 2 GB"), sizeMax)
        XCTAssertTrue(resolutionBoth.hasSuffix(" 1080p–4K"), resolutionBoth)
        XCTAssertTrue(resolutionMin.hasSuffix(" ≥ 4K"), resolutionMin)
        XCTAssertNil(NumericConditionKind.label(for: .addedWithinDays(7)))
    }

    func testRangeKnobsOpenTheirEndOnlyAtTheTrackEnd() {
        let track = NumericRangeTrack(scale: NumericConditionKind.duration.scale)
        XCTAssertEqual(track.position(forMin: nil), 0)
        XCTAssertEqual(track.position(forMax: nil), 1)
        XCTAssertNil(track.minBound(at: 0, snapping: true).value)
        XCTAssertNil(track.maxBound(at: 1, snapping: true).value)
        XCTAssertEqual(track.minBound(at: NumericRangeTrack.openZone, snapping: false).value ?? 0, 5, accuracy: 1e-6)
        XCTAssertEqual(track.maxBound(at: 1 - NumericRangeTrack.openZone, snapping: false).value ?? 0,
                       14_400, accuracy: 1e-6)
        let fiveMinutes = track.position(forMax: 300)
        XCTAssertEqual(track.maxBound(at: fiveMinutes, snapping: true).detent, 300)
        XCTAssertEqual(track.position(forMin: 300), fiveMinutes)

        let resolution = NumericRangeTrack(scale: NumericConditionKind.resolutionWidth.scale)
        XCTAssertEqual(resolution.minBound(at: NumericRangeTrack.openZone, snapping: true).value, 1280)
        XCTAssertEqual(resolution.maxBound(at: 1 - NumericRangeTrack.openZone, snapping: true).value, 7680)
    }

    func testRangeBoundsCannotCrossButBothEndsCanOpen() {
        var bounds = NumericRangeBounds(min: 60, max: 300)
        bounds.set(.min, to: 600)
        XCTAssertEqual(bounds, NumericRangeBounds(min: 300, max: 300))
        bounds.set(.max, to: 30)
        XCTAssertEqual(bounds, NumericRangeBounds(min: 300, max: 300))
        bounds.set(.max, to: nil)
        bounds.set(.min, to: nil)
        XCTAssertEqual(bounds, NumericRangeBounds(min: nil, max: nil))
        bounds.set(.max, to: 90)
        XCTAssertEqual(bounds, NumericRangeBounds(min: nil, max: 90))
    }

    func testEmptyAnyOrZeroLeavesARangeEndOpen() {
        let size = NumericConditionKind.fileSize
        for text in ["", "  ", "Any", "any", "不限", "0", "0 MB", "0.0", "0,0 GB"] {
            XCTAssertEqual(size.parseRangeBound(text, anyText: "Any", currentValue: 1_000_000_000), .any, text)
        }
        XCTAssertEqual(size.parseRangeBound("2 GB", anyText: "Any", currentValue: 1_000_000_000), .value(2_000_000_000))
        XCTAssertNil(size.parseRangeBound("big", anyText: "Any", currentValue: 1_000_000_000))
        XCTAssertEqual(
            NumericConditionKind.duration.parseRangeBound("0 s", anyText: "不限", currentValue: 60),
            .any
        )
    }

    func testFileSizeSliderStartsAtOneMegabyte() {
        let track = NumericRangeTrack(scale: NumericConditionKind.fileSize.scale)
        let lowest = track.minBound(at: NumericRangeTrack.openZone, snapping: false).value
        XCTAssertEqual(lowest ?? 0, 1_000_000, accuracy: 1e-3)
        XCTAssertEqual(NumericConditionKind.fileSize.rounded(lowest ?? 0), 1_000_000)
    }

    func testRangeOpenAtBothEndsIsDroppedAndNeverSaved() throws {
        let rule = LibraryQueryRule(
            requiredConditions: [.durationRange(min: nil, max: nil)],
            conditions: [.fileSizeRange(min: nil, max: nil), .resolutionWidthRange(min: 1920, max: nil)]
        )
        XCTAssertEqual(
            rule.removingUnboundedRanges(),
            LibraryQueryRule(conditions: [.resolutionWidthRange(min: 1920, max: nil)])
        )
        let decoded = try JSONDecoder().decode(LibraryQueryRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded, rule.removingUnboundedRanges())
        XCTAssertTrue(LibraryFilterCondition.fileSizeRange(min: nil, max: nil).isUnboundedRange)
        XCTAssertFalse(LibraryFilterCondition.fileSizeRange(min: nil, max: 1).isUnboundedRange)
    }

    func testArrowKeysStepThroughDetentsWithAnyPastTheEnds() {
        let detents: [Double] = [30, 60, 300]
        let bounds = NumericRangeBounds(min: 30, max: nil)
        XCTAssertNil(bounds.stepped(.min, up: false, detents: detents))
        XCTAssertEqual(bounds.stepped(.min, up: true, detents: detents), 60)
        XCTAssertEqual(bounds.stepped(.max, up: false, detents: detents), 300)
        XCTAssertNil(NumericRangeBounds(min: nil, max: 300).stepped(.max, up: true, detents: detents))
        XCTAssertEqual(NumericRangeBounds(min: nil, max: 300).stepped(.min, up: true, detents: detents), 30)
    }
}
