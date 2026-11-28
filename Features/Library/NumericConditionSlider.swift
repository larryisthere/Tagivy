import AppKit
import Foundation

/// A numeric filter condition, edited as values in the condition's stored unit
/// (days, seconds, bytes or pixel width) so saved smart filters keep their exact values.
/// Dates take a single "within last" value; the others take a min/max range.
enum NumericConditionKind: Equatable, Sendable {
    case addedWithinDays
    case createdWithinDays
    case duration
    case fileSize
    case resolution

    init?(_ condition: LibraryFilterCondition) {
        switch condition {
        case .addedWithinDays: self = .addedWithinDays
        case .createdWithinDays: self = .createdWithinDays
        case .durationRange: self = .duration
        case .fileSizeRange: self = .fileSize
        case .resolutionTierRange: self = .resolution
        case .tags, .untagged: return nil
        }
    }

    var isRange: Bool {
        switch self {
        case .addedWithinDays, .createdWithinDays: false
        case .duration, .fileSize, .resolution: true
        }
    }

    /// The value of a single-value (date) condition.
    static func value(of condition: LibraryFilterCondition) -> Double? {
        switch condition {
        case let .addedWithinDays(days), let .createdWithinDays(days): Double(days)
        case .durationRange, .fileSizeRange, .resolutionTierRange, .tags, .untagged: nil
        }
    }

    /// The bounds of a range condition; nil marks an open end.
    static func bounds(of condition: LibraryFilterCondition) -> (min: Double?, max: Double?)? {
        switch condition {
        case let .durationRange(low, high): (low, high)
        case let .fileSizeRange(low, high): (low.map(Double.init), high.map(Double.init))
        case let .resolutionTierRange(low, high): (low.map(Double.init), high.map(Double.init))
        case .addedWithinDays, .createdWithinDays, .tags, .untagged: nil
        }
    }

    func condition(with value: Double) -> LibraryFilterCondition {
        switch self {
        case .addedWithinDays: .addedWithinDays(Int(value.rounded()))
        case .createdWithinDays: .createdWithinDays(Int(value.rounded()))
        case .duration, .fileSize, .resolution: condition(min: value, max: nil)
        }
    }

    func condition(min low: Double?, max high: Double?) -> LibraryFilterCondition {
        switch self {
        case .addedWithinDays, .createdWithinDays: condition(with: low ?? high ?? 1)
        case .duration: .durationRange(min: low?.rounded(), max: high?.rounded()).normalized()
        case .fileSize:
            .fileSizeRange(min: low.map { Int64($0.rounded()) }, max: high.map { Int64($0.rounded()) }).normalized()
        case .resolution:
            .resolutionTierRange(min: low.map { Int($0.rounded()) }, max: high.map { Int($0.rounded()) }).normalized()
        }
    }

    var defaultCondition: LibraryFilterCondition {
        switch self {
        case .addedWithinDays: .addedWithinDays(30)
        case .createdWithinDays: .createdWithinDays(30)
        case .duration: .durationRange(min: 60, max: nil)
        case .fileSize: .fileSizeRange(min: 1_000_000_000, max: nil)
        case .resolution: .resolutionTierRange(min: 2160, max: nil)
        }
    }

    /// Chip text for a range condition: "Duration 1–5 min", "Size ≤ 2 GB", "Resolution ≥ 4K".
    static func label(for condition: LibraryFilterCondition) -> String? {
        guard let kind = NumericConditionKind(condition), kind.isRange,
              let bounds = bounds(of: condition) else { return nil }
        switch (bounds.min, bounds.max) {
        case let (low?, high?):
            let range = kind.formattedRange(low, high)
            return switch kind {
            case .duration: String(localized: "filter.durationRange", defaultValue: "Duration \(range)")
            case .fileSize: String(localized: "filter.fileSizeRange", defaultValue: "Size \(range)")
            default: String(localized: "filter.resolutionRange", defaultValue: "Resolution \(range)")
            }
        case let (low?, nil):
            let value = kind.formatted(low)
            return switch kind {
            case .duration: String(localized: "filter.durationAtLeast", defaultValue: "Duration ≥ \(value)")
            case .fileSize: String(localized: "filter.fileSize", defaultValue: "Size ≥ \(value)")
            default: String(localized: "filter.resolutionAtLeast", defaultValue: "Resolution ≥ \(value)")
            }
        case let (nil, high?):
            let value = kind.formatted(high)
            return switch kind {
            case .duration: String(localized: "filter.durationAtMost", defaultValue: "Duration ≤ \(value)")
            case .fileSize: String(localized: "filter.fileSizeAtMost", defaultValue: "Size ≤ \(value)")
            default: String(localized: "filter.resolutionAtMost", defaultValue: "Resolution ≤ \(value)")
            }
        case (nil, nil):
            return nil
        }
    }

    var scale: NumericConditionScale {
        switch self {
        case .addedWithinDays, .createdWithinDays:
            NumericConditionScale(mapping: .logarithmic(1...3650), detents: [1, 7, 30, 90, 180, 365])
        case .duration:
            NumericConditionScale(
                mapping: .logarithmic(5...14_400),
                detents: [30, 60, 120, 300, 600, 1800, 3600]
            )
        case .fileSize:
            NumericConditionScale(
                mapping: .logarithmic(1_000_000...100_000_000_000),
                detents: [100_000_000, 500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000, 10_000_000_000]
            )
        case .resolution:
            NumericConditionScale(
                mapping: .stepped,
                detents: Self.resolutionSteps.map { Double($0.tier) }
            )
        }
    }

    /// Named `ResolutionTier` values.
    static let resolutionSteps: [(tier: Int, name: String)] = Array(
        zip(ResolutionTier.named, ["720p", "1080p", "1440p", "4K", "8K"])
    )

    // MARK: Display units

    struct Unit: Sendable {
        let factor: Double
        let tokens: [String]
        let format: @Sendable (String) -> String
    }

    private static let dayUnit = Unit(factor: 1, tokens: ["d", "day", "days", "天"]) { number in
        String(localized: "filter.unit.days", defaultValue: "\(number) days")
    }
    private static let secondUnit = Unit(factor: 1, tokens: ["s", "sec", "secs", "second", "seconds", "秒"]) { number in
        String(localized: "filter.unit.seconds", defaultValue: "\(number) s")
    }
    private static let minuteUnit = Unit(factor: 60, tokens: ["m", "min", "mins", "minute", "minutes", "分", "分钟"]) { number in
        String(localized: "filter.unit.minutes", defaultValue: "\(number) min")
    }
    private static let hourUnit = Unit(factor: 3600, tokens: ["h", "hr", "hrs", "hour", "hours", "时", "小时"]) { number in
        String(localized: "filter.unit.hours", defaultValue: "\(number) hr")
    }
    private static let byteUnits: [Unit] = [
        Unit(factor: 1_000, tokens: ["k", "kb"]) { "\($0) KB" },
        Unit(factor: 1_000_000, tokens: ["m", "mb"]) { "\($0) MB" },
        Unit(factor: 1_000_000_000, tokens: ["g", "gb"]) { "\($0) GB" },
        Unit(factor: 1_000_000_000_000, tokens: ["t", "tb"]) { "\($0) TB" },
    ]

    private var units: [Unit] {
        switch self {
        case .addedWithinDays, .createdWithinDays: [Self.dayUnit]
        case .duration: [Self.secondUnit, Self.minuteUnit, Self.hourUnit]
        case .fileSize: Self.byteUnits
        case .resolution: []
        }
    }

    /// The unit a value is shown in: the largest unit that keeps the number at 1 or more.
    private func displayUnit(for value: Double) -> Unit? {
        let candidates = units.filter { $0.factor >= (self == .fileSize ? 1_000_000 : 1) }
        return candidates.last { value >= $0.factor } ?? candidates.first
    }

    /// Rounds to what the field can show, so dragging lands on readable values
    /// (37 min, 1.4 GB) and the field never displays a different value than is saved.
    func rounded(_ value: Double) -> Double {
        if case .resolution = self { return scale.nearestDetent(to: value) }
        let value = min(max(value, valueBounds.lowerBound), valueBounds.upperBound)
        guard let unit = displayUnit(for: value) else { return value }
        let number = value / unit.factor
        let significant = number >= 100 ? number.rounded() : Self.roundedToTwoSignificantDigits(number)
        return min(max((significant * unit.factor).rounded(), valueBounds.lowerBound), valueBounds.upperBound)
    }

    /// What a typed value may be: at least one of the smallest unit the field shows, and small
    /// enough to store, so the field always shows the saved value.
    var valueBounds: ClosedRange<Double> {
        switch self {
        case .addedWithinDays, .createdWithinDays: 1...36_500
        case .duration: 1...10_000_000
        case .fileSize: 1_000_000...1_000_000_000_000_000
        case .resolution: 1...100_000
        }
    }

    func formatted(_ value: Double) -> String {
        if case .resolution = self {
            let tier = Int(value.rounded())
            return Self.resolutionSteps.first { $0.tier == tier }?.name ?? "\(tier)p"
        }
        guard let unit = displayUnit(for: value) else { return "\(value)" }
        return unit.format(Self.numberText(value / unit.factor))
    }

    /// "1–5 min" when both ends share a unit, otherwise "30 s–5 min"; "1080p–4K".
    func formattedRange(_ low: Double, _ high: Double) -> String {
        if low == high { return formatted(low) }
        if let lowUnit = displayUnit(for: low), let highUnit = displayUnit(for: high),
           lowUnit.factor == highUnit.factor {
            return lowUnit.format("\(Self.numberText(low / lowUnit.factor))–\(Self.numberText(high / highUnit.factor))")
        }
        return "\(formatted(low))–\(formatted(high))"
    }

    /// Reads typed text such as "90", "1.5 GB", "2h", "45 秒" or "4K". A bare number keeps
    /// the unit the field currently shows. Returns nil for text that is not a positive value.
    func parse(_ text: String, currentValue: Double) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if case .resolution = self {
            if let step = Self.resolutionSteps.first(where: { $0.name.lowercased() == trimmed }) {
                return Double(step.tier)
            }
            if trimmed == "2k" { return 1440 }
            let digits = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789").inverted)
            guard let number = Double(digits), valueBounds.contains(number) else { return nil }
            if Self.resolutionSteps.contains(where: { Double($0.tier) == number }) { return number }
            // A familiar 16:9 width such as 1920 or 3840 means its tier.
            let byWidth = ResolutionTier.tier(forLegacyWidth: Int(number))
            if Self.resolutionSteps.contains(where: { $0.tier == byWidth }), Int(number) != byWidth {
                return Double(byWidth)
            }
            return scale.nearestDetent(to: number)
        }
        let numberPart = trimmed.prefix { $0.isNumber || $0 == "." || $0 == "," }
        let unitPart = trimmed.dropFirst(numberPart.count).trimmingCharacters(in: .whitespaces)
        guard let number = Self.number(from: String(numberPart)), number.isFinite, number > 0 else {
            return nil
        }
        let unit: Unit?
        if unitPart.isEmpty {
            unit = displayUnit(for: currentValue)
        } else {
            guard let match = units.first(where: { $0.tokens.contains(unitPart) }) else { return nil }
            unit = match
        }
        return rounded(number * (unit?.factor ?? 1))
    }

    enum RangeBoundInput: Equatable, Sendable {
        case any
        case value(Double)

        var value: Double? {
            if case let .value(value) = self { value } else { nil }
        }
    }

    /// Reads a range field: empty, "Any" or 0 leaves that end open; otherwise as `parse`.
    func parseRangeBound(_ text: String, anyText: String, currentValue: Double) -> RangeBoundInput? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty || [anyText.lowercased(), "any", "不限"].contains(trimmed) {
            return .any
        }
        let numberPart = trimmed.prefix { $0.isNumber || $0 == "." || $0 == "," }
        if Self.number(from: String(numberPart)) == 0 { return .any }
        return parse(text, currentValue: currentValue).map { .value($0) }
    }

    /// "1,000" is a thousands separator; any other comma ("1,5") is a decimal comma.
    private static func number(from text: String) -> Double? {
        let groups = text.split(separator: ",", omittingEmptySubsequences: false)
        let isGrouped = groups.count > 1 && groups.dropFirst().allSatisfy { $0.count == 3 && $0.allSatisfy(\.isNumber) }
        return Double(isGrouped ? text.replacingOccurrences(of: ",", with: "") : text.replacingOccurrences(of: ",", with: "."))
    }

    private static func roundedToTwoSignificantDigits(_ number: Double) -> Double {
        guard number > 0 else { return number }
        let magnitude = pow(10, floor(log10(number)) - 1)
        return (number / magnitude).rounded() * magnitude
    }

    private static func numberText(_ number: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 1
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}

/// Maps a value to a slider position in 0...1 and back. Detents pull a dragged knob
/// onto common values; elsewhere the knob moves freely.
struct NumericConditionScale: Equatable, Sendable {
    enum Mapping: Equatable, Sendable {
        case logarithmic(ClosedRange<Double>)
        /// Only the detents are selectable, spaced evenly.
        case stepped
    }

    static let snapRadius = 0.03

    let mapping: Mapping
    let detents: [Double]

    var detentPositions: [Double] { detents.map(position(for:)) }

    func position(for value: Double) -> Double {
        switch mapping {
        case let .logarithmic(range):
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            return (log(clamped) - log(range.lowerBound)) / (log(range.upperBound) - log(range.lowerBound))
        case .stepped:
            guard detents.count > 1,
                  let index = detents.firstIndex(of: nearestDetent(to: value)) else { return 0 }
            return Double(index) / Double(detents.count - 1)
        }
    }

    /// The value at a slider position, and whether it was pulled onto a detent.
    func value(at position: Double, snapping: Bool) -> (value: Double, detent: Double?) {
        let position = min(max(position, 0), 1)
        switch mapping {
        case let .logarithmic(range):
            if snapping,
               let nearest = detents.min(by: { abs(self.position(for: $0) - position) < abs(self.position(for: $1) - position) }),
               abs(self.position(for: nearest) - position) <= Self.snapRadius {
                return (nearest, nearest)
            }
            let value = exp(log(range.lowerBound) + position * (log(range.upperBound) - log(range.lowerBound)))
            return (value, nil)
        case .stepped:
            guard detents.isEmpty == false else { return (0, nil) }
            let detent = detents[Int((position * Double(detents.count - 1)).rounded())]
            return (detent, detent)
        }
    }

    func nearestDetent(to value: Double) -> Double {
        detents.min { abs($0 - value) < abs($1 - value) } ?? value
    }
}

/// Slider with magnetic detents plus an editable value field, kept in sync both ways.
@MainActor
final class NumericConditionSlider: NSView, NSTextFieldDelegate {
    private static let valueFieldWidth: CGFloat = 86

    private let kind: NumericConditionKind
    private let scale: NumericConditionScale
    private let slider = DetentSlider()
    private let valueField = NSTextField()
    private(set) var value: Double
    private var lastDetent: Double?
    var onChange: ((Double) -> Void)?

    init(kind: NumericConditionKind, value: Double) {
        self.kind = kind
        self.scale = kind.scale
        self.value = value
        super.init(frame: .zero)

        slider.detentPositions = scale.detentPositions
        slider.minValue = 0
        slider.maxValue = 1
        slider.isContinuous = true
        slider.controlSize = .small
        // The two end marks reserve room below the track; the detents are drawn between them.
        slider.numberOfTickMarks = 2
        slider.tickMarkPosition = .below
        slider.allowsTickMarkValuesOnly = false
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.setAccessibilityLabel(kind.formatted(value))

        valueField.controlSize = .small
        valueField.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueField.alignment = .right
        valueField.bezelStyle = .roundedBezel
        valueField.delegate = self
        valueField.target = self
        valueField.action = #selector(valueFieldCommitted(_:))
        valueField.cell?.sendsActionOnEndEditing = true
        valueField.cell?.isScrollable = true

        let row = NSStackView(views: [slider, valueField])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            valueField.widthAnchor.constraint(equalToConstant: Self.valueFieldWidth),
        ])
        slider.setContentHuggingPriority(.defaultLow, for: .horizontal)

        lastDetent = scale.detents.contains(value) ? value : nil
        display(value)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func display(_ value: Double) {
        slider.doubleValue = scale.position(for: value)
        valueField.stringValue = kind.formatted(value)
        slider.setAccessibilityValueDescription(kind.formatted(value))
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let snapping = NSEvent.modifierFlags.contains(.option) == false
        let result = scale.value(at: sender.doubleValue, snapping: snapping)
        let newValue = result.detent ?? kind.rounded(result.value)
        if let detent = result.detent {
            // Hold the knob on the detent while the pointer is within reach.
            sender.doubleValue = scale.position(for: detent)
            if detent != lastDetent {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
        }
        lastDetent = result.detent
        valueField.stringValue = kind.formatted(newValue)
        commit(newValue)
    }

    @objc private func valueFieldCommitted(_ sender: NSTextField) {
        guard let parsed = kind.parse(sender.stringValue, currentValue: value) else {
            display(value)
            return
        }
        lastDetent = scale.detents.contains(parsed) ? parsed : nil
        display(parsed)
        commit(parsed)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard commandSelector == #selector(NSResponder.moveUp(_:))
            || commandSelector == #selector(NSResponder.moveDown(_:)) else { return false }
        let detents = scale.detents
        let target = commandSelector == #selector(NSResponder.moveUp(_:))
            ? detents.first { $0 > value } ?? detents.last
            : detents.last { $0 < value } ?? detents.first
        guard let target else { return true }
        display(target)
        lastDetent = target
        commit(target)
        textView.selectAll(nil)
        return true
    }

    private func commit(_ newValue: Double) {
        guard newValue != value else { return }
        value = newValue
        onChange?(newValue)
    }
}

private final class DetentSlider: NSSlider {
    var detentPositions: [Double] = [] {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let cell = cell as? NSSliderCell, cell.numberOfTickMarks >= 2 else { return }
        let first = cell.rectOfTickMark(at: 0)
        let last = cell.rectOfTickMark(at: cell.numberOfTickMarks - 1)
        let knob = cell.knobRect(flipped: isFlipped)
        let diameter: CGFloat = 3
        NSColor.tertiaryLabelColor.setFill()
        for position in detentPositions where position > 0.001 && position < 0.999 {
            let dot = NSRect(
                x: first.midX + (last.midX - first.midX) * position - diameter / 2,
                y: first.midY - diameter / 2,
                width: diameter,
                height: diameter
            )
            guard dot.intersects(knob) == false else { continue }
            NSBezierPath(ovalIn: dot).fill()
        }
    }
}

/// Positions on a range slider's track. Each end of the track has a short open zone:
/// a knob pushed into it leaves that end of the range open ("Any"), so every value on
/// the scale, including its first and last, stays selectable.
struct NumericRangeTrack: Equatable, Sendable {
    static let openZone = 0.06

    let scale: NumericConditionScale

    func position(forMin value: Double?) -> Double {
        value.map { Self.openZone + scale.position(for: $0) * (1 - 2 * Self.openZone) } ?? 0
    }

    func position(forMax value: Double?) -> Double {
        value.map { Self.openZone + scale.position(for: $0) * (1 - 2 * Self.openZone) } ?? 1
    }

    /// The bound a knob at a track position stands for: nil inside its end's open zone,
    /// otherwise the scale value there and whether a detent pulled it in.
    func minBound(at position: Double, snapping: Bool) -> (value: Double?, detent: Double?) {
        guard position > Self.openZone / 2 else { return (nil, nil) }
        return scale.value(at: scalePosition(position), snapping: snapping)
    }

    func maxBound(at position: Double, snapping: Bool) -> (value: Double?, detent: Double?) {
        guard position < 1 - Self.openZone / 2 else { return (nil, nil) }
        return scale.value(at: scalePosition(position), snapping: snapping)
    }

    private func scalePosition(_ position: Double) -> Double {
        min(max((position - Self.openZone) / (1 - 2 * Self.openZone), 0), 1)
    }
}

/// Bounds of a range being edited. Keeps min ≤ max: an end that would pass the other stops on it.
struct NumericRangeBounds: Equatable, Sendable {
    enum End: Sendable { case min, max }

    private(set) var min: Double?
    private(set) var max: Double?

    init(min: Double?, max: Double?) {
        self.min = min
        self.max = max
    }

    mutating func set(_ end: End, to value: Double?) {
        switch end {
        case .min: min = value.map { value in max.map { Swift.min(value, $0) } ?? value }
        case .max: max = value.map { value in min.map { Swift.max(value, $0) } ?? value }
        }
    }

    /// The bound one detent further in a direction, with "Any" past the outermost detent.
    func stepped(_ end: End, up: Bool, detents: [Double]) -> Double? {
        let current = end == .min ? min : max
        switch (end, up) {
        case (.min, true):
            guard let current else { return detents.first }
            return detents.first { $0 > current } ?? current
        case (.min, false):
            guard let current else { return nil }
            return detents.last { $0 < current }
        case (.max, true):
            guard let current else { return nil }
            return detents.first { $0 > current }
        case (.max, false):
            guard let current else { return detents.last }
            return detents.last { $0 < current } ?? current
        }
    }
}

/// Two-knob slider with magnetic detents plus min and max fields, kept in sync both ways.
/// An empty field, or a knob pushed to its end of the track, leaves that end open.
@MainActor
final class NumericRangeSlider: NSView, NSTextFieldDelegate {
    private static let valueFieldWidth: CGFloat = 96

    private let kind: NumericConditionKind
    private let track: NumericRangeTrack
    private let trackView = RangeTrackView()
    private let minField = ClearableTextField()
    private let maxField = ClearableTextField()
    private(set) var rangeBounds: NumericRangeBounds
    private static let openEndSnap = -1.0
    private var lastSnap: [NumericRangeBounds.End: Double] = [:]
    var onChange: ((Double?, Double?) -> Void)?

    static let anyText = String(localized: "filter.range.any", defaultValue: "Any")

    var range: (min: Double?, max: Double?) { (rangeBounds.min, rangeBounds.max) }

    init(kind: NumericConditionKind, min: Double?, max: Double?, footnote: String? = nil) {
        self.kind = kind
        self.track = NumericRangeTrack(scale: kind.scale)
        self.rangeBounds = NumericRangeBounds(min: min, max: max)
        super.init(frame: .zero)

        let detentPositions = track.scale.detentPositions.map {
            NumericRangeTrack.openZone + $0 * (1 - 2 * NumericRangeTrack.openZone)
        }
        if kind == .resolution {
            trackView.detentMarks = zip(detentPositions, NumericConditionKind.resolutionSteps.map(\.name)).map {
                RangeTrackView.DetentMark(position: $0, title: $1)
            }
        } else {
            trackView.detentMarks = detentPositions.map { RangeTrackView.DetentMark(position: $0, title: nil) }
        }
        trackView.onDrag = { [weak self] end, position, snapping in
            self?.knobMoved(end, to: position, snapping: snapping)
        }
        trackView.onDragEnded = { [weak self] in self?.showRange() }
        trackView.onStep = { [weak self] end, up in self?.step(end, up: up) }

        let minLabel = Self.label(String(localized: "filter.range.min", defaultValue: "Min"))
        let maxLabel = Self.label(String(localized: "filter.range.max", defaultValue: "Max"))
        trackView.knobTitles = [.min: minLabel.stringValue, .max: maxLabel.stringValue]
        for (field, label, clearTitle) in [
            (minField, minLabel, String(localized: "filter.range.clearMin", defaultValue: "No Minimum")),
            (maxField, maxLabel, String(localized: "filter.range.clearMax", defaultValue: "No Maximum")),
        ] {
            field.controlSize = .small
            field.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            field.alignment = .right
            field.bezelStyle = .roundedBezel
            field.placeholderString = Self.anyText
            field.delegate = self
            field.target = self
            field.action = #selector(valueFieldCommitted(_:))
            field.cell?.sendsActionOnEndEditing = true
            field.cell?.isScrollable = true
            field.setAccessibilityLabel(label.stringValue)
            field.clearButtonTitle = clearTitle
            field.onClear = { [weak self, weak field] in
                guard let self, let field else { return }
                clearEnd(field === minField ? .min : .max)
            }
            field.widthAnchor.constraint(equalToConstant: Self.valueFieldWidth).isActive = true
        }

        let fields = NSView()
        for view in [minLabel, minField, maxLabel, maxField] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            fields.addSubview(view)
        }
        // The fields line up with the ends of the slider bar.
        let barInset = trackView.barInset
        NSLayoutConstraint.activate([
            minLabel.leadingAnchor.constraint(equalTo: fields.leadingAnchor, constant: barInset),
            minField.leadingAnchor.constraint(equalTo: minLabel.trailingAnchor, constant: 6),
            maxField.trailingAnchor.constraint(equalTo: fields.trailingAnchor, constant: -barInset),
            maxLabel.trailingAnchor.constraint(equalTo: maxField.leadingAnchor, constant: -6),
            maxLabel.leadingAnchor.constraint(greaterThanOrEqualTo: minField.trailingAnchor, constant: 12),
            minField.topAnchor.constraint(equalTo: fields.topAnchor),
            minField.bottomAnchor.constraint(equalTo: fields.bottomAnchor),
            maxField.centerYAnchor.constraint(equalTo: minField.centerYAnchor),
            minLabel.firstBaselineAnchor.constraint(equalTo: minField.firstBaselineAnchor),
            maxLabel.firstBaselineAnchor.constraint(equalTo: maxField.firstBaselineAnchor),
        ])

        var rows: [NSView] = [trackView, fields]
        if let footnote {
            let label = NSTextField(wrappingLabelWithString: footnote)
            label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            label.textColor = .secondaryLabelColor
            label.isSelectable = false
            label.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView()
            container.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: barInset),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -barInset),
                label.topAnchor.constraint(equalTo: container.topAnchor),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            rows.append(container)
        }
        let column = NSStackView(views: rows)
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.setCustomSpacing(11, after: trackView)
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            trackView.widthAnchor.constraint(equalTo: column.widthAnchor),
            fields.widthAnchor.constraint(equalTo: column.widthAnchor),
        ])
        rows.dropFirst(2).forEach { $0.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }

        lastSnap = [.min: rangeBounds.min ?? Self.openEndSnap, .max: rangeBounds.max ?? Self.openEndSnap]
        showRange()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func showRange() {
        trackView.minPosition = track.position(forMin: rangeBounds.min)
        trackView.maxPosition = track.position(forMax: rangeBounds.max)
        minField.showsClearButton = rangeBounds.min != nil
        maxField.showsClearButton = rangeBounds.max != nil
        minField.stringValue = rangeBounds.min.map(kind.formatted) ?? ""
        maxField.stringValue = rangeBounds.max.map(kind.formatted) ?? ""
        trackView.knobValues = [
            .min: rangeBounds.min.map(kind.formatted) ?? Self.anyText,
            .max: rangeBounds.max.map(kind.formatted) ?? Self.anyText,
        ]
    }

    private func knobMoved(_ end: NumericRangeBounds.End, to position: Double, snapping: Bool) {
        let result = end == .min
            ? track.minBound(at: position, snapping: snapping)
            : track.maxBound(at: position, snapping: snapping)
        let value = result.value.map { result.detent ?? kind.rounded($0) }
        var updated = rangeBounds
        updated.set(end, to: value)
        let snapped: Double? = value == nil ? Self.openEndSnap : result.detent
        if let snapped, lastSnap[end] != snapped {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        lastSnap[end] = snapped
        // The knob follows the pointer except where it is held: on a detent, on the other knob,
        // or at its open end.
        let held = value == nil || result.detent != nil
            || (end == .min ? updated.min : updated.max) != value
        let shownPosition = end == .min
            ? (held ? track.position(forMin: updated.min) : min(position, trackView.maxPosition))
            : (held ? track.position(forMax: updated.max) : max(position, trackView.minPosition))
        commit(updated)
        showRange()
        if end == .min { trackView.minPosition = shownPosition } else { trackView.maxPosition = shownPosition }
    }

    @objc private func valueFieldCommitted(_ sender: NSTextField) {
        let end: NumericRangeBounds.End = sender === minField ? .min : .max
        let current = end == .min ? rangeBounds.min : rangeBounds.max
        guard let input = kind.parseRangeBound(
            sender.stringValue,
            anyText: Self.anyText,
            currentValue: current ?? rangeBounds.min ?? rangeBounds.max ?? 1
        ) else {
            showRange()
            return
        }
        var updated = rangeBounds
        updated.set(end, to: input.value)
        commit(updated)
        showRange()
    }

    private func clearEnd(_ end: NumericRangeBounds.End) {
        var updated = rangeBounds
        updated.set(end, to: nil)
        commit(updated)
        showRange()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        let up = commandSelector == #selector(NSResponder.moveUp(_:))
        guard up || commandSelector == #selector(NSResponder.moveDown(_:)) else { return false }
        step(control === minField ? .min : .max, up: up)
        textView.selectAll(nil)
        return true
    }

    private func step(_ end: NumericRangeBounds.End, up: Bool) {
        var updated = rangeBounds
        updated.set(end, to: rangeBounds.stepped(end, up: up, detents: track.scale.detents))
        commit(updated)
        showRange()
    }

    private func commit(_ updated: NumericRangeBounds) {
        guard updated != rangeBounds else { return }
        rangeBounds = updated
        onChange?(updated.min, updated.max)
    }
}

/// The track of a range slider: the system slider bar and knobs, the selected span in the
/// accent color between the knobs (or from a knob to an open end), and dots for the detents.
/// Each knob is its own accessibility slider.
private final class RangeTrackView: NSView {
    private let cell: NSSliderCell = {
        let cell = NSSliderCell()
        cell.controlSize = .small
        cell.minValue = 0
        cell.maxValue = 1
        cell.doubleValue = 0
        return cell
    }()
    private lazy var knobElements: [NumericRangeBounds.End: RangeKnobAccessibilityElement] = [
        .min: RangeKnobAccessibilityElement(end: .min, track: self),
        .max: RangeKnobAccessibilityElement(end: .max, track: self),
    ]

    var minPosition: Double = 0 { didSet { needsDisplay = true } }
    var maxPosition: Double = 1 { didSet { needsDisplay = true } }
    struct DetentMark {
        let position: Double
        /// Drawn under the track in place of a dot.
        let title: String?
    }

    var detentMarks: [DetentMark] = [] {
        didSet {
            needsDisplay = true
            invalidateIntrinsicContentSize()
        }
    }
    var knobTitles: [NumericRangeBounds.End: String] = [:]
    var knobValues: [NumericRangeBounds.End: String] = [:]
    var onDrag: ((NumericRangeBounds.End, Double, Bool) -> Void)?
    var onDragEnded: (() -> Void)?
    var onStep: ((NumericRangeBounds.End, Bool) -> Void)?
    private var draggedEnd: NumericRangeBounds.End?

    override init(frame: NSRect) {
        super.init(frame: frame)
        cell.controlView = self
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static let markFont = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .mini))

    override var intrinsicContentSize: NSSize {
        let markHeight = detentMarks.contains { $0.title != nil } ? ceil(Self.markFont.boundingRectForFont.height) : 3
        return NSSize(width: NSView.noIntrinsicMetric, height: knobSize + 3 + markHeight)
    }

    /// Horizontal distance from the view's edge to the end of the slider bar.
    var barInset: CGFloat { knobSize / 2 }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var knobSize: CGFloat { ceil(cell.knobThickness) }
    private var trackMinX: CGFloat { bounds.minX + knobSize / 2 }
    private var trackWidth: CGFloat { max(bounds.width - knobSize, 1) }
    private var trackMidY: CGFloat { knobSize / 2 }

    private func x(for position: Double) -> CGFloat { trackMinX + trackWidth * position }
    private func position(for x: CGFloat) -> Double { min(max(Double((x - trackMinX) / trackWidth), 0), 1) }

    fileprivate func knobRect(_ end: NumericRangeBounds.End) -> NSRect {
        let center = x(for: end == .min ? minPosition : maxPosition)
        return NSRect(x: (center - knobSize / 2).rounded(), y: 0, width: knobSize, height: knobSize)
    }

    override func draw(_ dirtyRect: NSRect) {
        let barHeight: CGFloat = 4
        let bar = NSRect(x: trackMinX, y: trackMidY - barHeight / 2, width: trackWidth, height: barHeight)
        cell.drawBar(inside: bar, flipped: isFlipped)

        let selected = NSRect(
            x: x(for: minPosition), y: bar.minY,
            width: max(x(for: maxPosition) - x(for: minPosition), 0), height: barHeight
        )
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: selected, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

        let dotDiameter: CGFloat = 3
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: Self.markFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        NSColor.tertiaryLabelColor.setFill()
        for mark in detentMarks {
            if let title = mark.title {
                let size = (title as NSString).size(withAttributes: titleAttributes)
                let origin = NSPoint(x: (x(for: mark.position) - size.width / 2).rounded(), y: knobSize + 2)
                (title as NSString).draw(at: origin, withAttributes: titleAttributes)
            } else {
                let dot = NSRect(x: x(for: mark.position) - dotDiameter / 2, y: knobSize + 3, width: dotDiameter, height: dotDiameter)
                NSBezierPath(ovalIn: dot).fill()
            }
        }

        cell.drawKnob(knobRect(.min))
        cell.drawKnob(knobRect(.max))
    }

    override func mouseDown(with event: NSEvent) {
        let pointer = position(for: convert(event.locationInWindow, from: nil).x)
        let toMin = abs(pointer - minPosition)
        let toMax = abs(pointer - maxPosition)
        // Stacked knobs: the side clicked decides, so either can be pulled away.
        draggedEnd = toMin == toMax ? (pointer <= minPosition ? .min : .max) : (toMin < toMax ? .min : .max)
        drag(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        drag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        draggedEnd = nil
        onDragEnded?()
    }

    private func drag(with event: NSEvent) {
        guard let draggedEnd else { return }
        let pointer = position(for: convert(event.locationInWindow, from: nil).x)
        onDrag?(draggedEnd, pointer, event.modifierFlags.contains(.option) == false)
    }

    override func accessibilityChildren() -> [Any]? {
        [knobElements[.min], knobElements[.max]].compactMap { $0 }
    }
}

private final class RangeKnobAccessibilityElement: NSAccessibilityElement {
    private let end: NumericRangeBounds.End
    private weak var track: RangeTrackView?

    init(end: NumericRangeBounds.End, track: RangeTrackView) {
        self.end = end
        self.track = track
        super.init()
    }

    override func accessibilityRole() -> NSAccessibility.Role? { .slider }
    override func accessibilityParent() -> Any? { track }
    override func accessibilityLabel() -> String? { track?.knobTitles[end] }
    override func accessibilityValue() -> Any? { track?.knobValues[end] }

    override func accessibilityFrame() -> NSRect {
        guard let track else { return .zero }
        return NSAccessibility.screenRect(fromView: track, rect: track.knobRect(end))
    }

    override func accessibilityPerformIncrement() -> Bool {
        track?.onStep?(end, true)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        track?.onStep?(end, false)
        return true
    }
}

/// A text field with a trailing clear button inside its bezel, like a search field's.
private final class ClearableTextField: NSTextField {
    private static let buttonSize: CGFloat = 14

    private let clearButton = NSButton()
    var onClear: (() -> Void)?

    var clearButtonTitle = "" {
        didSet {
            clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: clearButtonTitle)
            clearButton.toolTip = clearButtonTitle
            clearButton.setAccessibilityLabel(clearButtonTitle)
        }
    }

    var showsClearButton = false {
        didSet {
            guard showsClearButton != oldValue else { return }
            clearButton.isHidden = showsClearButton == false
            (cell as? ClearableTextFieldCell)?.trailingInset = showsClearButton ? Self.buttonSize + 4 : 0
            needsDisplay = true
            // The field editor's frame is set when editing starts; restart editing to apply the new inset.
            if let editor = currentEditor() {
                let selection = editor.selectedRange
                abortEditing()
                selectText(nil)
                currentEditor()?.selectedRange = selection
            }
        }
    }

    override class var cellClass: AnyClass? {
        get { ClearableTextFieldCell.self }
        set {}
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clearButton.isBordered = false
        clearButton.imagePosition = .imageOnly
        clearButton.imageScaling = .scaleProportionallyDown
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.refusesFirstResponder = true
        clearButton.isHidden = true
        clearButton.target = self
        clearButton.action = #selector(clear(_:))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(clearButton)
        NSLayoutConstraint.activate([
            clearButton.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            clearButton.heightAnchor.constraint(equalToConstant: Self.buttonSize),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func clear(_ sender: NSButton) {
        onClear?()
    }
}

private final class ClearableTextFieldCell: NSTextFieldCell {
    var trailingInset: CGFloat = 0

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var drawing = super.drawingRect(forBounds: rect)
        drawing.size.width = max(drawing.width - trailingInset, 0)
        return drawing
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: insetForEditing(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(
            withFrame: insetForEditing(rect), in: controlView, editor: textObj,
            delegate: delegate, start: selStart, length: selLength
        )
    }

    private func insetForEditing(_ rect: NSRect) -> NSRect {
        var inset = rect
        inset.size.width = max(rect.width - trailingInset, 0)
        return inset
    }
}
