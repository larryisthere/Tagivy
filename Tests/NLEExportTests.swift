import XCTest
@testable import Tagivy

final class NLEExportTests: XCTestCase {
    // 旅行 ─┬─ 海边
    //       └─ 城市
    // 人物
    private let tags = [
        tag("travel", "旅行", order: 0),
        tag("coast", "海边", parent: "travel", order: 0),
        tag("city", "城市", parent: "travel", order: 1),
        tag("people", "人物", order: 1),
    ]

    func testTagGroupBecomesNestedBinsAndSkipsEmptyChildren() {
        let plan = makePlan(rootTagID: "travel", relations: [
            ("sunset", "travel"), ("sunset", "coast"), ("sunset", "people"),
            ("waves", "coast"),
        ])

        XCTAssertTrue(plan.rootIsTag)
        XCTAssertEqual(plan.root.name, "旅行")
        XCTAssertEqual(plan.root.clipIDs, ["sunset"])
        XCTAssertEqual(plan.root.bins.map(\.name), ["海边"], "城市 has no videos, so it has no bin")
        XCTAssertEqual(plan.root.bins[0].clipIDs, ["sunset", "waves"])
    }

    func testVideoInSeveralChildTagsAppearsInEachBin() {
        let plan = makePlan(rootTagID: "travel", relations: [("ferry", "coast"), ("ferry", "city")])

        XCTAssertEqual(plan.root.bins.map(\.name), ["海边", "城市"])
        XCTAssertEqual(plan.root.bins.map(\.clipIDs), [["ferry"], ["ferry"]])
        XCTAssertEqual(plan.clips.map(\.id), ["ferry"])
    }

    func testClipCarriesAllTagsInTreeOrderAndKeywordsOnlyFromExportedGroup() throws {
        let plan = makePlan(rootTagID: "travel", relations: [
            ("sunset", "people"), ("sunset", "city"), ("sunset", "travel"),
        ])
        let clip = try XCTUnwrap(plan.clip(id: "sunset"))

        XCTAssertEqual(clip.tagNames, ["旅行", "城市", "人物"])
        XCTAssertEqual(clip.keywords, ["旅行", "城市"])
    }

    func testSmartCollectionOrSelectionFollowsTheTagsItsVideosCarry() throws {
        let plan = makePlan(rootTagID: nil, relations: [
            ("sunset", "coast"), ("waves", "people"), ("plain", nil),
        ])

        XCTAssertFalse(plan.rootIsTag)
        XCTAssertEqual(plan.root.name, "导出")
        XCTAssertTrue(plan.root.clipIDs.isEmpty)
        XCTAssertEqual(plan.root.bins.map(\.name), ["旅行", "人物", "未打标签"], "城市 has no videos here, so it has no bin")
        XCTAssertEqual(plan.root.bins[0].bins.map(\.name), ["海边"])
        XCTAssertEqual(plan.root.bins[2].clipIDs, ["plain"])
        XCTAssertEqual(plan.tagBins.map(\.name), ["旅行", "人物"], "Untagged videos get a bin, not a keyword collection")
        XCTAssertEqual(try XCTUnwrap(plan.clip(id: "sunset")).keywords, ["海边"])
    }

    func testSeveralTagsBecomeSiblingBinsAndNestedChoicesAreNotRepeated() throws {
        let plan = makePlan(rootTagIDs: ["people", "travel", "coast"], relations: [
            ("sunset", "coast"), ("family", "people"),
        ])

        XCTAssertEqual(plan.root.name, "导出")
        XCTAssertEqual(plan.root.bins.map(\.name), ["旅行", "人物"], "海边 sits inside 旅行, so it is not a bin of its own")
        XCTAssertEqual(plan.tagBins.map(\.name), ["旅行", "人物"])

        let document = try XMLDocument(xmlString: FCPXMLWriter.document(for: plan))
        XCTAssertEqual(try document.nodes(forXPath: "/fcpxml/library/event/@name").first?.stringValue, "导出")
        XCTAssertEqual(try document.nodes(forXPath: "//collection-folder/@name").map(\.stringValue), ["旅行"])
        XCTAssertEqual(
            try document.nodes(forXPath: "/fcpxml/library/event/keyword-collection/@name").map(\.stringValue),
            ["人物"]
        )
    }

    func testFrameRates() {
        XCTAssertEqual(NLEFrameRate(29.97), NLEFrameRate(timebase: 30, isNTSC: true))
        XCTAssertEqual(NLEFrameRate(23.976), NLEFrameRate(timebase: 24, isNTSC: true))
        XCTAssertEqual(NLEFrameRate(59.94), NLEFrameRate(timebase: 60, isNTSC: true))
        XCTAssertEqual(NLEFrameRate(25), NLEFrameRate(timebase: 25, isNTSC: false))
        XCTAssertEqual(NLEFrameRate(nil), NLEFrameRate(timebase: 30, isNTSC: false))
        XCTAssertEqual(FCPXMLWriter.frameDuration(NLEFrameRate(timebase: 30, isNTSC: true)), "1001/30000s")
        XCTAssertEqual(FCPXMLWriter.frameDuration(NLEFrameRate(timebase: 25, isNTSC: false)), "100/2500s")
        XCTAssertEqual(FCPXMLWriter.time(frames: 300, rate: NLEFrameRate(timebase: 30, isNTSC: true)), "300300/30000s")
    }

    func testFCP7XMLDescribesEachFileOnceAndWritesLogNote() throws {
        let plan = makePlan(rootTagID: "travel", relations: [("ferry", "coast"), ("ferry", "city")])
        let text = FCP7XMLWriter.document(for: plan)
        let document = try XMLDocument(xmlString: text)

        let bins = try document.nodes(forXPath: "/xmeml/bin/children/bin/name").map(\.stringValue)
        XCTAssertEqual(bins, ["海边", "城市"])
        XCTAssertEqual(try document.nodes(forXPath: "//file[pathurl]").count, 1)
        XCTAssertEqual(try document.nodes(forXPath: "//file[not(*)]").count, 1)
        XCTAssertEqual(
            try document.nodes(forXPath: "//pathurl").first?.stringValue,
            "file://localhost/Volumes/Footage/A%20%E6%B5%B7/ferry.mov"
        )
        XCTAssertEqual(try document.nodes(forXPath: "(//lognote)[1]").first?.stringValue, "海边, 城市")
        XCTAssertEqual(try document.nodes(forXPath: "(//clip/duration)[1]").first?.stringValue, "300")
    }

    func testFCPXMLBuildsKeywordFoldersForTagGroups() throws {
        let plan = makePlan(rootTagID: "travel", relations: [("sunset", "travel"), ("ferry", "coast"), ("ferry", "city")])
        let document = try XMLDocument(xmlString: FCPXMLWriter.document(for: plan))

        XCTAssertEqual(try document.nodes(forXPath: "/fcpxml/library/event/@name").first?.stringValue, "旅行")
        XCTAssertEqual(try document.nodes(forXPath: "//asset").count, 2)
        XCTAssertEqual(try document.nodes(forXPath: "//collection-folder/@name").map(\.stringValue), ["旅行"])
        XCTAssertEqual(
            try document.nodes(forXPath: "//collection-folder/keyword-collection/@name").map(\.stringValue),
            ["旅行", "海边", "城市"]
        )
        XCTAssertEqual(
            try document.nodes(forXPath: "//asset-clip[@name='ferry.mov']/keyword/@value").first?.stringValue,
            "海边, 城市"
        )
        XCTAssertEqual(
            try document.nodes(forXPath: "//media-rep/@src").first?.stringValue,
            "file:///Volumes/Footage/A%20%E6%B5%B7/sunset.mov"
        )
    }

    func testFCPXMLForSelectedVideosKeywordsEveryTagAndSkipsUntagged() throws {
        let plan = makePlan(rootTagID: nil, relations: [("sunset", "coast"), ("plain", nil)])
        let document = try XMLDocument(xmlString: FCPXMLWriter.document(for: plan))

        XCTAssertEqual(try document.nodes(forXPath: "//asset-clip[@name='sunset.mov']/keyword/@value").first?.stringValue, "海边")
        XCTAssertEqual(try document.nodes(forXPath: "//asset-clip[@name='plain.mov']/*").count, 0)
        XCTAssertEqual(try document.nodes(forXPath: "//keyword-collection/@name").map(\.stringValue), ["海边"])
        XCTAssertEqual(try document.nodes(forXPath: "//note").first?.stringValue, "海边")
    }

    func testCapCutExportAddsATimelineOfEveryClipEndToEnd() throws {
        let plan = makePlan(rootTagID: nil, relations: [("sunset", "coast"), ("waves", "people")])
        let document = try XMLDocument(xmlString: String(decoding: NLEExportFormat.capCut.data(for: plan), as: UTF8.self))

        XCTAssertEqual(try document.nodes(forXPath: "/fcpxml/library/event/project/@name").first?.stringValue, "导出")
        XCTAssertEqual(try document.nodes(forXPath: "//spine/asset-clip/@offset").map(\.stringValue), ["0s", "300300/30000s"])
        XCTAssertEqual(try document.nodes(forXPath: "//sequence/@duration").first?.stringValue, "600600/30000s")
        XCTAssertEqual(try document.nodes(forXPath: "//keyword-collection").count, 2, "The tag collections stay alongside the timeline")
        XCTAssertEqual(try XMLDocument(xmlString: FCPXMLWriter.document(for: plan)).nodes(forXPath: "//project").count, 0)
    }

    func testVideosWithoutAKnownLengthAreLeftOutAndCounted() {
        let plan = makePlan(rootTagID: nil, relations: [("sunset", "coast"), ("pending", "coast")], unknownDuration: ["pending"])

        XCTAssertEqual(plan.clips.map(\.id), ["sunset"])
        XCTAssertEqual(plan.skippedCount, 1)
    }

    func testNamesAreEscaped() throws {
        var plan = makePlan(rootTagID: nil, relations: [])
        plan.root.name = "A & B <\"cut\">"
        let document = try XMLDocument(xmlString: FCP7XMLWriter.document(for: plan))

        XCTAssertEqual(try document.nodes(forXPath: "/xmeml/bin/name").first?.stringValue, "A & B <\"cut\">")
    }

    /// No root tag exports the way a smart filter or a video selection does.
    private func makePlan(
        rootTagID: String?,
        relations: [(String, String?)],
        unknownDuration: Set<String> = []
    ) -> NLEExportPlan {
        makePlan(
            name: rootTagID.flatMap { id in tags.first { $0.id == id }?.name } ?? "导出",
            grouping: rootTagID.map { .chosenTags([$0]) } ?? .videoTags(untaggedName: "未打标签"),
            relations: relations,
            unknownDuration: unknownDuration
        )
    }

    private func makePlan(rootTagIDs: [String], relations: [(String, String?)]) -> NLEExportPlan {
        makePlan(name: "导出", grouping: .chosenTags(rootTagIDs), relations: relations)
    }

    private func makePlan(
        name: String,
        grouping: NLEExportGrouping,
        relations: [(String, String?)],
        unknownDuration: Set<String> = []
    ) -> NLEExportPlan {
        let videoIDs = relations.map(\.0).reduce(into: [String]()) { ids, id in
            if ids.contains(id) == false { ids.append(id) }
        }
        let videos = (videoIDs.isEmpty ? ["sunset", "waves"] : videoIDs).map { id in
            NLEExportPlanBuilder.Video(
                record: video(id, duration: unknownDuration.contains(id) ? nil : 10.01),
                url: URL(fileURLWithPath: "/Volumes/Footage/A 海/\(id).mov")
            )
        }
        return NLEExportPlanBuilder.plan(
            name: name,
            grouping: grouping,
            tags: tags,
            relations: relations.compactMap { videoID, tagID in tagID.map { VideoTagRelation(videoID: videoID, tagID: $0) } },
            videos: videos,
            skippedCount: 0
        )
    }

    private func video(_ id: String, duration: Double?) -> VideoRecord {
        VideoRecord(
            id: id,
            libraryID: LibraryRecord.primaryID,
            relativePath: "\(id).mov",
            filename: "\(id).mov",
            fileExtension: "mov",
            fileSize: 1,
            creationDate: nil,
            modificationDate: nil,
            duration: duration,
            width: 3840,
            height: 2160,
            thumbnailID: nil,
            metadataStatus: .completed,
            thumbnailStatus: .completed,
            firstIndexedAt: Date(timeIntervalSince1970: 0),
            availability: .available,
            mediaSourceInfo: MediaSourceInfo(frameRate: 29.97, audioCodec: "aac")
        )
    }
}

private func tag(_ id: String, _ name: String, parent: String? = nil, order: Int) -> TagRecord {
    TagRecord(
        id: id,
        libraryID: LibraryRecord.primaryID,
        name: name,
        parentID: parent,
        color: nil,
        sortOrder: order,
        source: "user",
        videoCount: 0
    )
}
