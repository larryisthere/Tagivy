import Foundation
import UniformTypeIdentifiers

/// Carries an export choice through `NSMenuItem.representedObject`.
final class NLEExportMenuChoice: NSObject {
    /// Nil when the scope is read when the item is chosen, such as the current video selection.
    let scope: VideoScope?
    let format: NLEExportFormat

    init(scope: VideoScope?, format: NLEExportFormat) {
        self.scope = scope
        self.format = format
    }
}

enum NLEExportFormat: String, CaseIterable, Sendable {
    /// Final Cut Pro 7 XML, which Premiere Pro and DaVinci Resolve import.
    case fcp7XML
    /// FCPXML, which Final Cut Pro and DaVinci Resolve import.
    case fcpXML
    /// FCPXML with a timeline of every clip end to end, because CapCut imports only timelines.
    case capCut

    var fileExtension: String {
        switch self {
        case .fcp7XML: "xml"
        case .fcpXML, .capCut: "fcpxml"
        }
    }

    var contentType: UTType {
        UTType(filenameExtension: fileExtension) ?? .xml
    }

    func data(for plan: NLEExportPlan) -> Data {
        switch self {
        case .fcp7XML: Data(FCP7XMLWriter.document(for: plan).utf8)
        case .fcpXML: Data(FCPXMLWriter.document(for: plan).utf8)
        case .capCut: Data(FCPXMLWriter.document(for: plan, includesTimeline: true).utf8)
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
    /// Nil when the library has not recorded it.
    let audioChannels: Int?
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
    /// Whether the outermost bin is the one exported tag, so it keeps that tag's name
    /// instead of taking the name of the saved file.
    let rootIsTag: Bool
    /// The bin of each exported tag; Final Cut Pro keyword collections are built from these.
    let tagBins: [NLEExportBin]

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

/// How exported clips are sorted into bins. Every export follows the tag tree; only the starting tags differ.
enum NLEExportGrouping: Equatable, Sendable {
    /// Bins for the tags a person chose, holding the videos in those tags.
    case chosenTags([String])
    /// Bins for every top-level tag the videos carry, plus one bin for videos without tags.
    case videoTags(untaggedName: String)
}

enum NLEExportPlanBuilder {
    /// - Parameter name: Name of the outermost bin.
    static func plan(
        name: String,
        grouping: NLEExportGrouping,
        tags: [TagRecord],
        relations: [VideoTagRelation],
        videos: [ResolvedVideo],
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

        func subtree(_ id: String) -> Set<String> {
            var ids: Set<String> = []
            var pending = [id]
            while let next = pending.popLast() {
                ids.insert(next)
                pending.append(contentsOf: (childrenByParent[next] ?? []).map(\.id))
            }
            return ids
        }
        func topLevel(_ id: String) -> String {
            var current = id
            var visited: Set<String> = []
            while let parent = tagsByID[current]?.parentID, tagsByID[parent] != nil, visited.insert(current).inserted {
                current = parent
            }
            return current
        }
        let requestedRoots: [String] = switch grouping {
        case let .chosenTags(ids):
            ids.filter { tagsByID[$0] != nil }
        case .videoTags:
            Array(Set(videos.flatMap { tagIDsByVideo[$0.record.id] ?? [] }.map(topLevel)))
        }
        // A chosen tag inside another chosen tag already appears in that tag's bin.
        let rootIDs = requestedRoots
            .filter { id in requestedRoots.contains { $0 != id && subtree($0).contains(id) } == false }
            .sorted { (treeOrder[$0] ?? .max) < (treeOrder[$1] ?? .max) }
        let subtreeIDs = rootIDs.reduce(into: Set<String>()) { $0.formUnion(subtree($1)) }

        // Editing apps need a clip's length; a video whose length is not known yet is left out like an unavailable one.
        let timedVideos = videos.filter { $0.record.duration.map { $0.isFinite && $0 > 0 } == true }
        let leftOutCount = skippedCount + videos.count - timedVideos.count
        let clips = timedVideos.map { video -> NLEExportClip in
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
                audioChannels: record.mediaSourceInfo?.audioChannels,
                tagNames: tagIDs.compactMap { tagsByID[$0]?.name },
                keywords: tagIDs.filter(subtreeIDs.contains).compactMap { tagsByID[$0]?.name }
            )
        }

        func bin(for tag: TagRecord) -> NLEExportBin? {
            let direct = clips.filter { tagIDsByVideo[$0.id]?.contains(tag.id) == true }.map(\.id)
            let children = (childrenByParent[tag.id] ?? []).compactMap(bin(for:))
            guard direct.isEmpty == false || children.isEmpty == false else { return nil }
            return NLEExportBin(name: tag.name, bins: children, clipIDs: direct)
        }
        let tagBins = rootIDs.compactMap { tagsByID[$0] }.compactMap(bin(for:))
        let root: NLEExportBin
        let rootIsTag: Bool
        switch grouping {
        case .chosenTags where tagBins.count == 1:
            var tagBin = tagBins[0]
            tagBin.name = name
            root = tagBin
            rootIsTag = true
        case .chosenTags:
            root = NLEExportBin(name: name, bins: tagBins, clipIDs: [])
            rootIsTag = false
        case let .videoTags(untaggedName):
            let untagged = clips.filter { tagIDsByVideo[$0.id, default: []].isEmpty }.map(\.id)
            let untaggedBins = untagged.isEmpty ? [] : [NLEExportBin(name: untaggedName, bins: [], clipIDs: untagged)]
            root = NLEExportBin(name: name, bins: tagBins + untaggedBins, clipIDs: [])
            rootIsTag = false
        }
        return NLEExportPlan(
            root: root,
            clips: clips,
            skippedCount: leftOutCount,
            rootIsTag: rootIsTag,
            tagBins: tagBins
        )
    }
}
