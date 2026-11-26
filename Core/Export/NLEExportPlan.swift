import Foundation
import UniformTypeIdentifiers

/// What a person chose to export to an editing app.
enum NLEExportScope: Equatable, Sendable {
    case tag(TagRecord)
    case smartCollection(SmartCollectionRecord)
    case videos([VideoRecord])
}

/// Carries a scope through `NSMenuItem.representedObject`.
final class NLEExportScopeBox: NSObject {
    let scope: NLEExportScope

    init(_ scope: NLEExportScope) {
        self.scope = scope
    }
}

enum NLEExportFormat: String, CaseIterable, Sendable {
    /// Final Cut Pro 7 XML, which Premiere Pro and DaVinci Resolve import.
    case fcp7XML
    /// FCPXML, which Final Cut Pro and DaVinci Resolve import.
    case fcpXML

    var fileExtension: String {
        switch self {
        case .fcp7XML: "xml"
        case .fcpXML: "fcpxml"
        }
    }

    var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .xml
    }

    func data(for plan: NLEExportPlan) -> Data {
        switch self {
        case .fcp7XML: Data(FCP7XMLWriter.document(for: plan).utf8)
        case .fcpXML: Data(FCPXMLWriter.document(for: plan).utf8)
        }
    }
}

/// A video file as editing apps see it.
struct NLEExportClip: Equatable, Sendable {
    let id: String
    let name: String
    let url: URL
    let duration: Double?
    let frameRate: NLEFrameRate
    let width: Int?
    let height: Int?
    let hasAudio: Bool
    /// Every tag on the video, in tag tree order. Written where editors can search it.
    let tagNames: [String]
    /// Tags inside the exported tag group, in tag tree order. Final Cut Pro keywords.
    let keywords: [String]

    var frameCount: Int {
        guard let duration, duration.isFinite, duration > 0 else { return 0 }
        return Int((duration * frameRate.framesPerSecond).rounded())
    }
}

/// A bin in Premiere Pro or DaVinci Resolve; a keyword collection or folder in Final Cut Pro.
struct NLEExportBin: Equatable, Sendable {
    var name: String
    var bins: [NLEExportBin]
    var clipIDs: [String]
}

struct NLEExportPlan: Equatable, Sendable {
    var root: NLEExportBin
    let clips: [NLEExportClip]
    /// Videos in scope whose files cannot be reached, such as videos on a disconnected drive.
    let skippedCount: Int
    /// Whether the bins mirror a tag tree, or one bin holds every clip.
    let mirrorsTags: Bool

    func clip(id: String) -> NLEExportClip? {
        clips.first { $0.id == id }
    }
}

struct NLEFrameRate: Equatable, Sendable {
    /// Whole frames per second the editor counts in, such as 30 for 29.97.
    let timebase: Int
    /// Whether the real rate is timebase × 1000/1001.
    let isNTSC: Bool

    static let fallback = NLEFrameRate(timebase: 30, isNTSC: false)

    init(timebase: Int, isNTSC: Bool) {
        self.timebase = timebase
        self.isNTSC = isNTSC
    }

    init(_ framesPerSecond: Double?) {
        guard let rate = framesPerSecond, rate.isFinite, rate >= 1 else {
            self = .fallback
            return
        }
        let ntscBase = (rate * 1.001).rounded()
        if abs(rate - rate.rounded()) < 0.01 {
            self.init(timebase: Int(rate.rounded()), isNTSC: false)
        } else if abs(rate * 1.001 - ntscBase) < 0.01 {
            self.init(timebase: Int(ntscBase), isNTSC: true)
        } else {
            self.init(timebase: Int(rate.rounded()), isNTSC: false)
        }
    }

    var framesPerSecond: Double {
        isNTSC ? Double(timebase) * 1000 / 1001 : Double(timebase)
    }
}

enum NLEExportPlanBuilder {
    struct Video: Sendable {
        let record: VideoRecord
        let url: URL
    }

    /// - Parameters:
    ///   - name: Name of the outermost bin.
    ///   - rootTagID: The exported tag; nil puts every clip in one bin.
    static func plan(
        name: String,
        rootTagID: String?,
        tags: [TagRecord],
        relations: [VideoTagRelation],
        videos: [Video],
        skippedCount: Int
    ) -> NLEExportPlan {
        let childrenByParent = Dictionary(grouping: tags, by: \.parentID)
            .mapValues { $0.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) } }
        var treeOrder: [String: Int] = [:]
        func visit(_ parentID: String?) {
            for tag in childrenByParent[parentID] ?? [] {
                treeOrder[tag.id] = treeOrder.count
                visit(tag.id)
            }
        }
        visit(nil)

        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        var tagIDsByVideo: [String: [String]] = [:]
        for relation in relations where tagsByID[relation.tagID] != nil {
            tagIDsByVideo[relation.videoID, default: []].append(relation.tagID)
        }
        for (videoID, ids) in tagIDsByVideo {
            tagIDsByVideo[videoID] = Array(Set(ids)).sorted { (treeOrder[$0] ?? .max) < (treeOrder[$1] ?? .max) }
        }

        var subtreeIDs: Set<String> = []
        if let rootTagID {
            var pending = [rootTagID]
            while let id = pending.popLast() {
                subtreeIDs.insert(id)
                pending.append(contentsOf: (childrenByParent[id] ?? []).map(\.id))
            }
        }

        let clips = videos.map { video -> NLEExportClip in
            let record = video.record
            let tagIDs = tagIDsByVideo[record.id] ?? []
            return NLEExportClip(
                id: record.id,
                name: record.filename,
                url: video.url,
                duration: record.duration,
                frameRate: NLEFrameRate(record.mediaSourceInfo?.frameRate),
                width: record.width,
                height: record.height,
                hasAudio: record.mediaSourceInfo.map { $0.audioCodec != nil || $0.audioChannels != nil } ?? true,
                tagNames: tagIDs.compactMap { tagsByID[$0]?.name },
                keywords: tagIDs.filter(subtreeIDs.contains).compactMap { tagsByID[$0]?.name }
            )
        }

        guard let rootTagID, let rootTag = tagsByID[rootTagID] else {
            return NLEExportPlan(
                root: NLEExportBin(name: name, bins: [], clipIDs: clips.map(\.id)),
                clips: clips,
                skippedCount: skippedCount,
                mirrorsTags: false
            )
        }

        func bin(for tag: TagRecord) -> NLEExportBin? {
            let direct = clips.filter { tagIDsByVideo[$0.id]?.contains(tag.id) == true }.map(\.id)
            let children = (childrenByParent[tag.id] ?? []).compactMap(bin(for:))
            guard direct.isEmpty == false || children.isEmpty == false else { return nil }
            return NLEExportBin(name: tag.name, bins: children, clipIDs: direct)
        }
        var root = bin(for: rootTag) ?? NLEExportBin(name: rootTag.name, bins: [], clipIDs: [])
        root.name = name
        return NLEExportPlan(
            root: root,
            clips: clips,
            skippedCount: skippedCount,
            mirrorsTags: true
        )
    }
}
