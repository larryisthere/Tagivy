import AppKit

enum TagSortMode: String, CaseIterable {
    case custom
    case name
    case count

    var title: String {
        switch self {
        case .custom: String(localized: .tagSortCustom)
        case .name: String(localized: .tagSortName)
        case .count: String(localized: .tagSortCount)
        }
    }

    func orders(_ left: TagRecord, before right: TagRecord) -> Bool {
        switch self {
        case .custom:
            if left.sortOrder != right.sortOrder { return left.sortOrder < right.sortOrder }
        case .name:
            break
        case .count:
            if left.videoCount != right.videoCount { return left.videoCount > right.videoCount }
        }

        let nameOrder = left.name.localizedStandardCompare(right.name)
        if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
        return left.id < right.id
    }
}

enum LibraryFilter: Equatable, Sendable {
    case all
    case untagged
    case recent
    case unavailable
    case tag(String)
    case tags([String])

    static let recentlyAddedInterval: TimeInterval = 30 * 24 * 60 * 60
}

struct SidebarFilterCounts: Equatable, Sendable {
    let all: Int
    let untagged: Int
    let recent: Int
    let unavailable: Int

    init(all: Int, untagged: Int, recent: Int, unavailable: Int = 0) {
        self.all = all
        self.untagged = untagged
        self.recent = recent
        self.unavailable = unavailable
    }

    static let zero = SidebarFilterCounts(all: 0, untagged: 0, recent: 0, unavailable: 0)
}

enum SidebarGroupKind {
    case scanResults
    case library
    case smartCollections
    case tags
}

final class ScanResultsNode {
    let videoCount: Int

    init(videoCount: Int) {
        self.videoCount = videoCount
    }
}

final class SidebarGroupNode {
    let kind: SidebarGroupKind
    let title: String
    var children: [Any]

    init(kind: SidebarGroupKind, title: String, children: [Any]) {
        self.kind = kind
        self.title = title
        self.children = children
    }
}

final class SidebarFilterNode {
    let title: String
    let systemImageName: String
    let filter: LibraryFilter
    let videoCount: Int

    var shortcutHint: String? {
        switch filter {
        case .all: "⌘1"
        case .recent: "⌘2"
        case .untagged: "⌘3"
        case .unavailable: "⌘4"
        case .tag, .tags: nil
        }
    }

    init(title: String, systemImageName: String, filter: LibraryFilter, videoCount: Int) {
        self.title = title
        self.systemImageName = systemImageName
        self.filter = filter
        self.videoCount = videoCount
    }
}

final class SidebarPlaceholderNode {
    let title: String

    init(title: String) {
        self.title = title
    }
}

final class SidebarDraftTagNode {}

final class SmartCollectionNode {
    let collection: SmartCollectionRecord

    init(collection: SmartCollectionRecord) {
        self.collection = collection
    }
}

final class TagNode {
    let tag: TagRecord
    var children: [TagNode] = []

    init(tag: TagRecord) {
        self.tag = tag
    }
}

/// What the Delete key removes from the sidebar selection: tags (a selected tag's descendants go with it,
/// so they are not listed again) or a single smart collection. Any other selection deletes nothing.
enum SidebarDeletion: Equatable {
    case tags([TagRecord])
    case smartCollection(SmartCollectionRecord)

    init?(selectedItems: [Any], allTags: [TagRecord]) {
        if selectedItems.count == 1, let node = selectedItems.first as? SmartCollectionNode {
            self = .smartCollection(node.collection)
            return
        }
        let selectedTags = selectedItems.compactMap { ($0 as? TagNode)?.tag }
        guard selectedTags.isEmpty == false, selectedTags.count == selectedItems.count else { return nil }
        self = .tags(SidebarTargets.topLevelTags(from: selectedTags, allTags: allTags))
    }
}

/// Delete and Command-Delete (and Forward Delete) remove the sidebar selection, as in Finder.
enum SidebarDeleteKey {
    static let deleteKeyCode: UInt16 = 51
    static let forwardDeleteKeyCode: UInt16 = 117

    static func matches(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch event.keyCode {
        case deleteKeyCode: return modifiers.isEmpty || modifiers == [.command]
        case forwardDeleteKeyCode: return modifiers.isEmpty
        default: return false
        }
    }
}

/// Which way a sidebar count rolls when it changes: a larger number comes up from below,
/// a smaller one drops in from above, like a counter wheel.
enum CountRoll: Equatable {
    case up
    case down

    init?(from oldText: String?, to newText: String?) {
        guard let old = oldText.flatMap({ Int($0) }),
              let new = newText.flatMap({ Int($0) }),
              old != new else { return nil }
        self = new > old ? .up : .down
    }
}

/// A tag or smart collection row in the sidebar that a drag or the context menu can act on.
enum SidebarTargetItem: Equatable {
    case tag(TagRecord)
    case smartCollection(SmartCollectionRecord)
}

/// The tags and smart collections a drag or context menu acts on.
struct SidebarTargets: Equatable {
    /// The rows acted on, including nested tags that `tags` leaves out.
    let items: [SidebarTargetItem]
    /// Tags whose ancestor is also a target are left out; the ancestor already includes their videos.
    let tags: [TagRecord]
    let smartCollections: [SmartCollectionRecord]

    /// A clicked row inside the selection acts on the whole selection; otherwise only on the clicked row.
    init(clicked: SidebarTargetItem, selection: [SidebarTargetItem], allTags: [TagRecord]) {
        self.init(items: selection.contains(clicked) ? selection : [clicked], allTags: allTags)
    }

    init(items: [SidebarTargetItem], allTags: [TagRecord]) {
        var tags: [TagRecord] = []
        var smartCollections: [SmartCollectionRecord] = []
        for item in items {
            switch item {
            case let .tag(tag) where tags.contains(where: { $0.id == tag.id }) == false:
                tags.append(tag)
            case let .smartCollection(collection)
                where smartCollections.contains(where: { $0.id == collection.id }) == false:
                smartCollections.append(collection)
            default:
                break
            }
        }
        self.items = items
        self.tags = Self.topLevelTags(from: tags, allTags: allTags)
        self.smartCollections = smartCollections
    }

    var isEmpty: Bool { tags.isEmpty && smartCollections.isEmpty }

    func actsOnSameVideos(as other: SidebarTargets) -> Bool {
        Set(tags.map(\.id)) == Set(other.tags.map(\.id))
            && Set(smartCollections.map(\.id)) == Set(other.smartCollections.map(\.id))
    }

    var scopes: [VideoScope] {
        (tags.isEmpty ? [] : [.tags(tags)]) + smartCollections.map { .smartCollection($0) }
    }

    static func topLevelTags(from candidates: [TagRecord], allTags: [TagRecord]) -> [TagRecord] {
        let candidateIDs = Set(candidates.map(\.id))
        let parentIDByID = Dictionary(allTags.map { ($0.id, $0.parentID) }, uniquingKeysWith: { first, _ in first })
        return candidates.filter { tag in
            var ancestorID = tag.parentID
            var visited: Set<String> = []
            while let currentID = ancestorID, visited.insert(currentID).inserted {
                if candidateIDs.contains(currentID) { return false }
                ancestorID = parentIDByID[currentID] ?? nil
            }
            return true
        }
    }
}
