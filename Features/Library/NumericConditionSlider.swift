import AppKit
import Foundation

/// A numeric filter condition, edited as a value in the condition's stored unit
/// (days, seconds, bytes or pixel width) so saved smart filters keep their exact values.
enum NumericConditionKind: Equatable, Sendable {
    case addedWithinDays
    case createdWithinDays
    case durationAtLeast
    case fileSizeAtLeast
    case resolutionWidthAtLeast

    init?(_ condition: LibraryFilterCondition) {
        switch condition {
        case .addedWithinDays: self = .addedWithinDays
        case .createdWithinDays: self = .createdWithinDays
        case .durationAtLeast: self = .durationAtLeast
        case .fileSizeAtLeast: self = .fileSizeAtLeast
        case .resolutionWidthAtLeast: self = .resolutionWidthAtLeast
        case .tags, .untagged: return nil
        }
    }

    static func value(of condition: LibraryFilterCondition) -> Double? {
        switch condition {
        case let .addedWithinDays(days), let .createdWithinDays(days): Double(days)
        case let .durationAtLeast(seconds): seconds
        case let .fileSizeAtLeast(bytes): Double(bytes)
        case let .resolutionWidthAtLeast(width): Double(width)
        case .tags, .untagged: nil
        }
    }

    func condition(with value: Double) -> LibraryFilterCondition {
        switch self {
        case .addedWithinDays: .addedWithinDays(Int(value.rounded()))
        case .createdWithinDays: .createdWithinDays(Int(value.rounded()))
        case .durationAtLeast: .durationAtLeast(value.rounded())
        case .fileSizeAtLeast: .fileSizeAtLeast(Int64(value.rounded()))
        case .resolutionWidthAtLeast: .resolutionWidthAtLeast(Int(value.rounded()))
        }
    }

    var defaultCondition: LibraryFilterCondition {
        switch self {
        case .addedWithinDays: .addedWithinDays(30)
        case .createdWithinDays: .createdWithinDays(30)
        case .durationAtLeast: .durationAtLeast(60)
        case .fileSizeAtLeast: .fileSizeAtLeast(1_000_000_000)
        case .resolutionWidthAtLeast: .resolutionWidthAtLeast(3840)
        }
    }

    var scale: NumericConditionScale {
        switch self {
        case .addedWithinDays, .createdWithinDays:
            NumericConditionScale(mapping: .logarithmic(1...3650), detents: [1, 7, 30, 90, 180, 365])
        case .durationAtLeast:
            NumericConditionScale(
                mapping: .logarithmic(5...14_400),
                detents: [30, 60, 120, 300, 600, 1800, 3600]
            )
        case .fileSizeAtLeast:
            NumericConditionScale(
                mapping: .logarithmic(10_000_000...100_000_000_000),
                detents: [100_000_000, 500_000_000, 1_000_000_000, 2_000_000_000, 5_000_000_000, 10_000_000_000]
            )
        case .resolutionWidthAtLeast:
            NumericConditionScale(
                mapping: .stepped,
                detents: Self.resolutionSteps.map { Double($0.width) }
            )
        }
    }

    static let resolutionSteps: [(width: Int, name: String)] = [
        (1280, "720p"), (1920, "1080p"), (2560, "1440p"), (3840, "4K"), (7680, "8K"),
    ]

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
        case .durationAtLeast: [Self.secondUnit, Self.minuteUnit, Self.hourUnit]
        case .fileSizeAtLeast: Self.byteUnits
        case .resolutionWidthAtLeast: []
        }
    }

    /// The unit a value is shown in: the largest unit that keeps the number at 1 or more.
    private func displayUnit(for value: Double) -> Unit? {
        let candidates = units.filter { $0.factor >= (self == .fileSizeAtLeast ? 1_000_000 : 1) }
        return candidates.last { value >= $0.factor } ?? candidates.first
    }

    /// Rounds to what the field can show, so dragging lands on readable values
    /// (37 min, 1.4 GB) and the field never displays a different value than is saved.
    func rounded(_ value: Double) -> Double {
        if case .resolutionWidthAtLeast = self { return scale.nearestDetent(to: value) }
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
        case .durationAtLeast: 1...10_000_000
        case .fileSizeAtLeast: 1_000_000...1_000_000_000_000_000
        case .resolutionWidthAtLeast: 1...100_000
        }
    }

    func formatted(_ value: Double) -> String {
        if case .resolutionWidthAtLeast = self {
            let width = Int(value.rounded())
            return Self.resolutionSteps.first { $0.width == width }?.name ?? "\(width) px"
        }
        guard let unit = displayUnit(for: value) else { return "\(value)" }
        return unit.format(Self.numberText(value / unit.factor))
    }

    /// Reads typed text such as "90", "1.5 GB", "2h", "45 秒" or "4K". A bare number keeps
    /// the unit the field currently shows. Returns nil for text that is not a positive value.
    func parse(_ text: String, currentValue: Double) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if case .resolutionWidthAtLeast = self {
            if let step = Self.resolutionSteps.first(where: { $0.name.lowercased() == trimmed }) {
                return Double(step.width)
            }
            if trimmed == "2k" { return 2560 }
            let digits = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "0123456789").inverted)
            guard let number = Double(digits), number.isFinite, number > 0 else { return nil }
            let byHeight = Self.resolutionSteps.first { $0.name == "\(Int(number))p" }
            return byHeight.map { Double($0.width) } ?? scale.nearestDetent(to: number)
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
