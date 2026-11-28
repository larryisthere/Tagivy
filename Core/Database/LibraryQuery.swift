import Foundation

enum LibraryFilterMatchMode: String, Codable, CaseIterable, Sendable {
    case all
    case any
}

enum LibraryTagConditionOperator: String, Codable, CaseIterable, Sendable {
    case all
    case any
    case exclude
}

/// Range cases hold inclusive bounds; a nil bound is open. At least one bound is set.
enum LibraryFilterCondition: Codable, Equatable, Sendable {
    case tags(operator: LibraryTagConditionOperator, tagIDs: [String])
    case untagged
    case addedWithinDays(Int)
    case createdWithinDays(Int)
    case durationRange(min: Double?, max: Double?)
    case fileSizeRange(min: Int64?, max: Int64?)
    case resolutionTierRange(min: Int?, max: Int?)

    /// A range with both ends open, possible only while its editor is open; it filters nothing
    /// and is dropped when the editor closes.
    var isUnboundedRange: Bool {
        switch self {
        case .durationRange(nil, nil), .fileSizeRange(nil, nil), .resolutionTierRange(nil, nil): true
        default: false
        }
    }

    /// The same condition with range bounds in order (min ≤ max).
    func normalized() -> LibraryFilterCondition {
        switch self {
        case let .durationRange(low, high):
            let bounds = Self.ordered(low, high)
            return .durationRange(min: bounds.min, max: bounds.max)
        case let .fileSizeRange(low, high):
            let bounds = Self.ordered(low, high)
            return .fileSizeRange(min: bounds.min, max: bounds.max)
        case let .resolutionTierRange(low, high):
            let bounds = Self.ordered(low, high)
            return .resolutionTierRange(min: bounds.min, max: bounds.max)
        case .tags, .untagged, .addedWithinDays, .createdWithinDays:
            return self
        }
    }

    private static func ordered<Value: Comparable>(_ low: Value?, _ high: Value?) -> (min: Value?, max: Value?) {
        guard let low, let high, low > high else { return (low, high) }
        return (high, low)
    }

    /// Mirrors the synthesized coding of every case this enum has had, so the stored JSON
    /// keeps its shape and smart filters saved with a single lower bound still load.
    private enum Stored: Codable {
        case tags(operator: LibraryTagConditionOperator, tagIDs: [String])
        case untagged
        case addedWithinDays(Int)
        case createdWithinDays(Int)
        case durationRange(min: Double?, max: Double?)
        case fileSizeRange(min: Int64?, max: Int64?)
        case resolutionTierRange(min: Int?, max: Int?)
        case durationAtLeast(Double)
        case fileSizeAtLeast(Int64)
        case resolutionWidthAtLeast(Int)
        case resolutionWidthRange(min: Int?, max: Int?)
    }

    init(from decoder: Decoder) throws {
        switch try Stored(from: decoder) {
        case let .tags(tagOperator, tagIDs): self = .tags(operator: tagOperator, tagIDs: tagIDs)
        case .untagged: self = .untagged
        case let .addedWithinDays(days): self = .addedWithinDays(days)
        case let .createdWithinDays(days): self = .createdWithinDays(days)
        case let .durationRange(low, high): self = .durationRange(min: low, max: high)
        case let .fileSizeRange(low, high): self = .fileSizeRange(min: low, max: high)
        case let .resolutionTierRange(low, high): self = .resolutionTierRange(min: low, max: high)
        case let .durationAtLeast(seconds): self = .durationRange(min: seconds, max: nil)
        case let .fileSizeAtLeast(bytes): self = .fileSizeRange(min: bytes, max: nil)
        case let .resolutionWidthAtLeast(width):
            self = .resolutionTierRange(min: ResolutionTier.tier(forLegacyWidth: width), max: nil)
        case let .resolutionWidthRange(low, high):
            self = .resolutionTierRange(
                min: low.map(ResolutionTier.tier(forLegacyWidth:)),
                max: high.map(ResolutionTier.tier(forLegacyWidth:))
            )
        }
        if isUnboundedRange {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Range without bounds")
            )
        }
        self = normalized()
    }

    func encode(to encoder: Encoder) throws {
        let stored: Stored = switch self {
        case let .tags(tagOperator, tagIDs): .tags(operator: tagOperator, tagIDs: tagIDs)
        case .untagged: .untagged
        case let .addedWithinDays(days): .addedWithinDays(days)
        case let .createdWithinDays(days): .createdWithinDays(days)
        case let .durationRange(low, high): .durationRange(min: low, max: high)
        case let .fileSizeRange(low, high): .fileSizeRange(min: low, max: high)
        case let .resolutionTierRange(low, high): .resolutionTierRange(min: low, max: high)
        }
        try stored.encode(to: encoder)
    }
}

/// A frame's resolution tier: the 16:9 height (720, 1080, 2160 …) of the smallest 16:9 frame
/// that holds it, in either orientation. A portrait 1080×1920 video is 1080p, and a
/// widescreen 3840×1608 video is 4K rather than its 1608-pixel short edge.
enum ResolutionTier {
    static func value(width: Int, height: Int) -> Double {
        max(Double(min(width, height)), Double(max(width, height)) * 9 / 16)
    }

    /// The same value computed by SQLite; NULL when either dimension is unknown.
    static let sql = "MAX(MIN(videos.width, videos.height), MAX(videos.width, videos.height) * 9.0 / 16)"

    static let named = [720, 1080, 1440, 2160, 4320]

    /// What "at most `max`" admits. A named tier covers every frame below the next tier, so a
    /// DCI 4096×2160 frame (2304) is still "≤ 4K"; above the top tier there is no limit (nil).
    /// Any other value is an exact inclusive limit.
    static func upperLimit(forMax max: Int) -> (value: Double, isInclusive: Bool)? {
        guard let index = named.firstIndex(of: max) else { return (Double(max), true) }
        let next = named.index(after: index)
        return next < named.endIndex ? (Double(named[next]), false) : nil
    }

    /// Earlier builds filtered on a 16:9 width; read those as the matching tier.
    static func tier(forLegacyWidth width: Int) -> Int {
        let tiers = [1280: 720, 1920: 1080, 2560: 1440, 3840: 2160, 7680: 4320]
        return tiers[width] ?? Int((Double(width) * 9 / 16).rounded())
    }
}

enum LibraryVideoSortKey: String, Codable, CaseIterable, Sendable {
    case filename
    case added
    case created
    case modified
    case duration
    case fileSize
    case resolution
}

enum LibraryVideoSortDirection: String, Codable, CaseIterable, Sendable {
    case ascending
    case descending
}

struct LibraryVideoSort: Codable, Equatable, Sendable {
    let key: LibraryVideoSortKey
    let direction: LibraryVideoSortDirection

    static let standard = LibraryVideoSort(key: .filename, direction: .ascending)
    static let recentlyAdded = LibraryVideoSort(key: .added, direction: .descending)
}

extension LibraryFilter {
    var presetSort: LibraryVideoSort? {
        switch self {
        case .recent: .recentlyAdded
        case .all, .untagged, .unavailable, .tag, .tags: nil
        }
    }
}

struct LibraryQueryRule: Codable, Equatable, Sendable {
    var requiredTagIDs: [String]
    var requiredConditions: [LibraryFilterCondition]
    var filenameContains: [String]
    var matchMode: LibraryFilterMatchMode
    var conditions: [LibraryFilterCondition]
    var sort: LibraryVideoSort

    init(
        requiredTagIDs: [String] = [],
        requiredConditions: [LibraryFilterCondition] = [],
        filenameContains: [String] = [],
        matchMode: LibraryFilterMatchMode = .all,
        conditions: [LibraryFilterCondition] = [],
        sort: LibraryVideoSort = .standard
    ) {
        self.requiredTagIDs = requiredTagIDs
        self.requiredConditions = requiredConditions
        self.filenameContains = filenameContains
        self.matchMode = matchMode
        self.conditions = conditions
        self.sort = sort
    }

    static let standard = LibraryQueryRule()

    var isStandard: Bool {
        normalized() == .standard
    }

    func normalized() -> LibraryQueryRule {
        var copy = self
        copy.requiredTagIDs = uniqueNonempty(copy.requiredTagIDs)
        copy.requiredConditions = normalizedConditions(copy.requiredConditions)
        copy.filenameContains = uniqueNonempty(
            copy.filenameContains.map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        copy.conditions = normalizedConditions(copy.conditions)
        return copy
    }

    func removingUnboundedRanges() -> LibraryQueryRule {
        var copy = self
        copy.requiredConditions.removeAll(where: \.isUnboundedRange)
        copy.conditions.removeAll(where: \.isUnboundedRange)
        return copy
    }

    var referencedTagIDs: [String] {
        requiredTagIDs + (requiredConditions + conditions).flatMap { condition in
            guard case let .tags(_, tagIDs) = condition else { return [String]() }
            return tagIDs
        }
    }

    private func normalizedConditions(
        _ conditions: [LibraryFilterCondition]
    ) -> [LibraryFilterCondition] {
        conditions.map { condition in
            guard case let .tags(tagOperator, tagIDs) = condition else { return condition.normalized() }
            return .tags(operator: tagOperator, tagIDs: uniqueNonempty(tagIDs))
        }
    }

    private func uniqueNonempty(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            value.isEmpty == false && seen.insert(value).inserted
        }
    }

    private enum CodingKeys: String, CodingKey {
        case requiredTagIDs
        case requiredConditions
        case filenameContains
        case matchMode
        case conditions
        case sort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requiredTagIDs = try container.decodeIfPresent([String].self, forKey: .requiredTagIDs) ?? []
        requiredConditions = try container.decodeIfPresent(
            [LibraryFilterCondition].self,
            forKey: .requiredConditions
        ) ?? []
        filenameContains = try container.decodeIfPresent([String].self, forKey: .filenameContains) ?? []
        matchMode = try container.decodeIfPresent(
            LibraryFilterMatchMode.self,
            forKey: .matchMode
        ) ?? .all
        conditions = try container.decodeIfPresent(
            [LibraryFilterCondition].self,
            forKey: .conditions
        ) ?? []
        sort = try container.decodeIfPresent(LibraryVideoSort.self, forKey: .sort) ?? .standard
    }

    func encode(to encoder: Encoder) throws {
        let rule = removingUnboundedRanges()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requiredTagIDs, forKey: .requiredTagIDs)
        try container.encode(rule.requiredConditions, forKey: .requiredConditions)
        try container.encode(filenameContains, forKey: .filenameContains)
        try container.encode(matchMode, forKey: .matchMode)
        try container.encode(rule.conditions, forKey: .conditions)
        try container.encode(sort, forKey: .sort)
    }
}

struct LibraryQueryRequest: Equatable, Sendable {
    let baseFilter: LibraryFilter
    let temporaryFilenameSearch: String
    let rule: LibraryQueryRule
}

struct SmartCollectionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let libraryID: String
    var name: String
    var rule: LibraryQueryRule
    let sortOrder: Int
    let createdAt: Date
    var updatedAt: Date
    var videoCount: Int? = nil
}

func normalizedSmartCollectionName(_ name: String) -> String {
    name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
