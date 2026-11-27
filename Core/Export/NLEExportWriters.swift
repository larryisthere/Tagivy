import Foundation

/// Final Cut Pro 7 XML (xmeml), read by Premiere Pro and DaVinci Resolve.
///
/// Laid out the way Premiere Pro writes a project: a `project` whose children are bins and
/// master clips, each master clip holding its file in one video track and one audio track per channel.
/// Premiere Pro refuses master clips that hold their `file` directly.
enum FCP7XMLWriter {
    /// - Parameter includesTimeline: Adds a sequence of every clip end to end after the bins,
    ///   because DaVinci Resolve imports an XML file only as a timeline.
    static func document(for plan: NLEExportPlan, includesTimeline: Bool = false) -> String {
        var writer = Writer()
        writer.xml.line("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        writer.xml.line("<!DOCTYPE xmeml>")
        writer.xml.open("xmeml", attributes: [("version", "4")])
        writer.xml.open("project")
        writer.xml.element("name", plan.root.name)
        // The editing app puts what it imports in a bin named after the file, so the outermost bin's
        // contents go straight into the project instead of nesting a second bin of the same name.
        writer.xml.open("children")
        writer.writeContents(of: plan.root, plan: plan)
        if includesTimeline, let first = plan.clips.first {
            writer.writeSequence(plan, rate: first.frameRate, width: first.width, height: first.height)
        }
        writer.xml.close("children")
        writer.xml.close("project")
        writer.xml.close("xmeml")
        return writer.xml.text
    }

    private struct Writer {
        var xml = XMLText()
        var describedFiles: Set<String> = []
        /// The first master clip written for each video, which timeline clip items point back to.
        var masterIDs: [String: String] = [:]

        mutating func writeContents(of bin: NLEExportBin, plan: NLEExportPlan) {
            for child in bin.bins {
                xml.open("bin")
                xml.element("name", child.name)
                xml.open("children")
                writeContents(of: child, plan: plan)
                xml.close("children")
                xml.close("bin")
            }
            for clip in bin.clipIDs.compactMap(plan.clip(id:)) {
                writeMasterClip(clip)
            }
        }

        mutating func writeMasterClip(_ clip: NLEExportClip) {
            let masterID = "masterclip-\(xml.nextID())"
            if masterIDs[clip.id] == nil { masterIDs[clip.id] = masterID }
            xml.open("clip", attributes: [("id", masterID), ("explodedTracks", "true")])
            xml.element("masterclipid", masterID)
            xml.element("ismasterclip", "TRUE")
            xml.element("duration", String(clip.frameCount))
            FCP7XMLWriter.writeRate(clip.frameRate, into: &xml)
            xml.element("name", clip.name)
            xml.open("media")
            let items = Placement(clip: clip, masterID: masterID, rate: clip.frameRate, start: 0, length: clip.frameCount)
                .items(ids: &xml)
            xml.open("video")
            xml.open("track")
            writeItem(items, at: 0)
            xml.close("track")
            xml.close("video")
            if items.count > 1 {
                xml.open("audio")
                for index in 1..<items.count {
                    xml.open("track")
                    writeItem(items, at: index)
                    xml.close("track")
                }
                xml.close("audio")
            }
            xml.close("media")
            if clip.tagNames.isEmpty == false {
                xml.open("logginginfo")
                xml.element("lognote", clip.tagNames.joined(separator: ", "))
                xml.close("logginginfo")
            }
            xml.close("clip")
        }

        /// Every clip once, end to end, timed in the first clip's frame rate.
        mutating func writeSequence(_ plan: NLEExportPlan, rate: NLEFrameRate, width: Int?, height: Int?) {
            var start = 0
            var placed: [[Item]] = []
            for clip in plan.clips {
                let length = Int(((Double(clip.frameCount) / clip.frameRate.framesPerSecond) * rate.framesPerSecond).rounded())
                guard length > 0 else { continue }
                let placement = Placement(clip: clip, masterID: masterIDs[clip.id], rate: rate, start: start, length: length)
                placed.append(placement.items(ids: &xml))
                start += length
            }
            // Each clip item's link names its position among the clip items in its track.
            let audioTrackCount = placed.map { $0.count - 1 }.max() ?? 0
            var positions = Array(repeating: 0, count: audioTrackCount + 1)
            for index in placed.indices {
                for track in placed[index].indices {
                    positions[track] += 1
                    placed[index][track].clipIndex = positions[track]
                }
            }

            xml.open("sequence", attributes: [("id", "sequence-\(xml.nextID())")])
            xml.element("name", plan.root.name)
            xml.element("duration", String(start))
            FCP7XMLWriter.writeRate(rate, into: &xml)
            xml.open("media")
            xml.open("video")
            xml.open("format")
            xml.open("samplecharacteristics")
            FCP7XMLWriter.writeRate(rate, into: &xml)
            if let width { xml.element("width", String(width)) }
            if let height { xml.element("height", String(height)) }
            xml.close("samplecharacteristics")
            xml.close("format")
            xml.open("track")
            for items in placed { writeItem(items, at: 0) }
            xml.close("track")
            xml.close("video")
            if audioTrackCount > 0 {
                xml.open("audio")
                for track in 1...audioTrackCount {
                    xml.open("track")
                    for items in placed where items.count > track { writeItem(items, at: track) }
                    xml.close("track")
                }
                xml.close("audio")
            }
            xml.close("media")
            xml.open("timecode")
            FCP7XMLWriter.writeRate(rate, into: &xml)
            xml.element("string", "00:00:00:00")
            xml.element("frame", "0")
            xml.element("displayformat", "NDF")
            xml.close("timecode")
            xml.close("sequence")
        }

        /// The video clip item at index 0 holds the file; audio clip items reference it by id.
        mutating func writeItem(_ items: [Item], at index: Int) {
            let item = items[index]
            let placement = item.placement
            let clip = placement.clip
            let fileID = "file-\(clip.id)"
            xml.open("clipitem", attributes: [("id", item.id)])
            if let masterID = placement.masterID { xml.element("masterclipid", masterID) }
            xml.element("name", clip.name)
            xml.element("duration", String(placement.length))
            FCP7XMLWriter.writeRate(placement.rate, into: &xml)
            // Required on every clip item by Apple's xmeml reference.
            xml.element("start", String(placement.start))
            xml.element("end", String(placement.start + placement.length))
            xml.element("in", "0")
            xml.element("out", String(placement.length))
            if index == 0 {
                FCP7XMLWriter.writeFile(clip, id: fileID, audioTracks: items.count - 1, into: &xml, describedFiles: &describedFiles)
            } else {
                xml.empty("file", attributes: [("id", fileID)])
                xml.open("sourcetrack")
                xml.element("mediatype", "audio")
                xml.element("trackindex", String(index))
                xml.close("sourcetrack")
            }
            // Apple's xmeml reference warns a track index on video-only media may fail the import.
            if items.count > 1 {
                for (track, linked) in items.enumerated() {
                    xml.open("link")
                    xml.element("linkclipref", linked.id)
                    xml.element("mediatype", track == 0 ? "video" : "audio")
                    xml.element("trackindex", String(max(track, 1)))
                    xml.element("clipindex", String(linked.clipIndex))
                    if track > 0 { xml.element("groupindex", "1") }
                    xml.close("link")
                }
            }
            xml.close("clipitem")
        }
    }

    /// Where one clip sits: its whole file, from `start` for `length` frames at `rate`.
    private struct Placement {
        let clip: NLEExportClip
        let masterID: String?
        let rate: NLEFrameRate
        let start: Int
        let length: Int

        /// One video clip item plus one audio clip item per channel.
        func items(ids xml: inout XMLText) -> [Item] {
            let audioTracks = clip.hasAudio ? max(clip.audioChannels ?? 2, 1) : 0
            return (0...audioTracks).map { _ in Item(id: "clipitem-\(xml.nextID())", placement: self) }
        }
    }

    private struct Item {
        let id: String
        let placement: Placement
        var clipIndex = 1
    }

    /// A file is described in full where it first appears and referenced by id after that.
    private static func writeFile(
        _ clip: NLEExportClip,
        id fileID: String,
        audioTracks: Int,
        into xml: inout XMLText,
        describedFiles: inout Set<String>
    ) {
        guard describedFiles.insert(fileID).inserted else {
            xml.empty("file", attributes: [("id", fileID)])
            return
        }
        xml.open("file", attributes: [("id", fileID)])
        xml.element("name", clip.name)
        xml.element("pathurl", pathURL(clip.url))
        writeRate(clip.frameRate, into: &xml)
        xml.element("duration", String(clip.frameCount))
        xml.open("media")
        xml.open("video")
        xml.open("samplecharacteristics")
        writeRate(clip.frameRate, into: &xml)
        if let width = clip.width { xml.element("width", String(width)) }
        if let height = clip.height { xml.element("height", String(height)) }
        xml.close("samplecharacteristics")
        xml.close("video")
        if audioTracks > 0 {
            xml.open("audio")
            xml.element("channelcount", String(audioTracks))
            xml.close("audio")
        }
        xml.close("media")
        xml.close("file")
    }

    private static func writeRate(_ rate: NLEFrameRate, into xml: inout XMLText) {
        xml.open("rate")
        xml.element("timebase", String(rate.timebase))
        xml.element("ntsc", rate.isNTSC ? "TRUE" : "FALSE")
        xml.close("rate")
    }

    /// Premiere Pro expects the `file://localhost/` form.
    static func pathURL(_ url: URL) -> String {
        let absolute = url.standardizedFileURL.absoluteString
        guard absolute.hasPrefix("file:///") else { return absolute }
        return "file://localhost/" + absolute.dropFirst("file:///".count)
    }
}

/// FCPXML 1.9, read by Final Cut Pro 10.5 and later and DaVinci Resolve.
enum FCPXMLWriter {
    static func document(for plan: NLEExportPlan, includesTimeline: Bool = false) -> String {
        var xml = XMLText()
        var formatIDs: [String: String] = [:]
        var formatLines: [(id: String, rate: NLEFrameRate, width: Int?, height: Int?)] = []
        var assetIDs: [String: String] = [:]
        for clip in plan.clips {
            let key = "\(clip.frameRate.timebase)/\(clip.frameRate.isNTSC)/\(clip.width ?? 0)x\(clip.height ?? 0)"
            if formatIDs[key] == nil {
                let id = "r\(formatIDs.count + 1)"
                formatIDs[key] = id
                formatLines.append((id, clip.frameRate, clip.width, clip.height))
            }
            assetIDs[clip.id] = "a\(assetIDs.count + 1)"
        }
        func formatID(_ clip: NLEExportClip) -> String {
            formatIDs["\(clip.frameRate.timebase)/\(clip.frameRate.isNTSC)/\(clip.width ?? 0)x\(clip.height ?? 0)"] ?? "r1"
        }

        xml.line("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        xml.line("<!DOCTYPE fcpxml>")
        xml.open("fcpxml", attributes: [("version", "1.9")])
        xml.open("resources")
        for format in formatLines {
            var attributes = [("id", format.id), ("frameDuration", frameDuration(format.rate))]
            if let width = format.width { attributes.append(("width", String(width))) }
            if let height = format.height { attributes.append(("height", String(height))) }
            xml.empty("format", attributes: attributes)
        }
        for clip in plan.clips {
            xml.open("asset", attributes: [
                ("id", assetIDs[clip.id] ?? ""),
                ("name", clip.name),
                ("start", "0s"),
                ("duration", time(frames: clip.frameCount, rate: clip.frameRate)),
                ("hasVideo", "1"),
                ("hasAudio", clip.hasAudio ? "1" : "0"),
                ("format", formatID(clip)),
            ])
            xml.empty("media-rep", attributes: [("kind", "original-media"), ("src", clip.url.standardizedFileURL.absoluteString)])
            xml.close("asset")
        }
        xml.close("resources")
        xml.open("library")
        xml.open("event", attributes: [("name", plan.root.name)])
        for clip in plan.clips {
            let duration = time(frames: clip.frameCount, rate: clip.frameRate)
            xml.open("asset-clip", attributes: [
                ("ref", assetIDs[clip.id] ?? ""),
                ("name", clip.name),
                ("duration", duration),
                ("format", formatID(clip)),
            ])
            if clip.tagNames.isEmpty == false {
                xml.element("note", clip.tagNames.joined(separator: ", "))
            }
            if clip.keywords.isEmpty == false {
                xml.empty("keyword", attributes: [
                    ("start", "0s"),
                    ("duration", duration),
                    ("value", clip.keywords.joined(separator: ", ")),
                ])
            }
            xml.close("asset-clip")
        }
        for bin in plan.tagBins {
            writeCollections(bin, into: &xml)
        }
        if includesTimeline, let first = plan.clips.first {
            writeTimeline(plan, rate: first.frameRate, format: formatID(first), assetIDs: assetIDs, into: &xml)
        }
        xml.close("event")
        xml.close("library")
        xml.close("fcpxml")
        return xml.text
    }

    /// Every clip once, end to end, timed in the first clip's frame rate.
    private static func writeTimeline(
        _ plan: NLEExportPlan,
        rate: NLEFrameRate,
        format: String,
        assetIDs: [String: String],
        into xml: inout XMLText
    ) {
        let lengths = plan.clips.map { clip in
            Int(((Double(clip.frameCount) / clip.frameRate.framesPerSecond) * rate.framesPerSecond).rounded())
        }
        let total = lengths.reduce(0, +)
        xml.open("project", attributes: [("name", plan.root.name)])
        xml.open("sequence", attributes: [
            ("format", format),
            ("duration", time(frames: total, rate: rate)),
            ("tcStart", "0s"),
            ("tcFormat", "NDF"),
        ])
        xml.open("spine")
        var offset = 0
        for (clip, length) in zip(plan.clips, lengths) where length > 0 {
            xml.empty("asset-clip", attributes: [
                ("ref", assetIDs[clip.id] ?? ""),
                ("offset", time(frames: offset, rate: rate)),
                ("name", clip.name),
                ("duration", time(frames: length, rate: rate)),
            ])
            offset += length
        }
        xml.close("spine")
        xml.close("sequence")
        xml.close("project")
    }

    /// A tag with child tags becomes a folder holding its own keyword collection and its children's.
    private static func writeCollections(_ bin: NLEExportBin, into xml: inout XMLText) {
        guard bin.bins.isEmpty == false else {
            xml.empty("keyword-collection", attributes: [("name", bin.name)])
            return
        }
        xml.open("collection-folder", attributes: [("name", bin.name)])
        if bin.clipIDs.isEmpty == false {
            xml.empty("keyword-collection", attributes: [("name", bin.name)])
        }
        for child in bin.bins {
            writeCollections(child, into: &xml)
        }
        xml.close("collection-folder")
    }

    static func frameDuration(_ rate: NLEFrameRate) -> String {
        rate.isNTSC ? "1001/\(rate.timebase * 1000)s" : "100/\(rate.timebase * 100)s"
    }

    static func time(frames: Int, rate: NLEFrameRate) -> String {
        guard frames > 0 else { return "0s" }
        return rate.isNTSC
            ? "\(frames * 1001)/\(rate.timebase * 1000)s"
            : "\(frames * 100)/\(rate.timebase * 100)s"
    }
}

struct XMLText {
    private(set) var text = ""
    private var depth = 0
    private var idCounter = 0

    mutating func nextID() -> Int {
        idCounter += 1
        return idCounter
    }

    mutating func line(_ content: String) {
        text += String(repeating: "  ", count: depth) + content + "\n"
    }

    mutating func open(_ name: String, attributes: [(String, String)] = []) {
        line("<\(name)\(Self.attributes(attributes))>")
        depth += 1
    }

    mutating func close(_ name: String) {
        depth -= 1
        line("</\(name)>")
    }

    mutating func empty(_ name: String, attributes: [(String, String)]) {
        line("<\(name)\(Self.attributes(attributes))/>")
    }

    mutating func element(_ name: String, _ value: String) {
        line("<\(name)>\(Self.escape(value))</\(name)>")
    }

    private static func attributes(_ pairs: [(String, String)]) -> String {
        pairs.map { " \($0.0)=\"\(escape($0.1))\"" }.joined()
    }

    static func escape(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.count)
        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default:
                if let scalar = character.unicodeScalars.first,
                   character.unicodeScalars.count == 1,
                   scalar.value < 0x20, scalar != "\t", scalar != "\n", scalar != "\r" {
                    continue
                }
                result.append(character)
            }
        }
        return result
    }
}
