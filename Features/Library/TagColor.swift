import AppKit

/// The colors a tag can have. The raw value is what the database stores; no color is stored as nil.
enum TagColor: String, CaseIterable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple

    init?(storedValue: String?) {
        guard let storedValue else { return nil }
        self.init(rawValue: storedValue)
    }

    var title: String {
        switch self {
        case .red: String(localized: .colorRed)
        case .orange: String(localized: .colorOrange)
        case .yellow: String(localized: .colorYellow)
        case .green: String(localized: .colorGreen)
        case .blue: String(localized: .colorBlue)
        case .purple: String(localized: .colorPurple)
        }
    }

    var color: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .blue: .systemBlue
        case .purple: .systemPurple
        }
    }

    /// A filled circle with a thin outline, like the tag colors in Finder's menus. Drawn when shown, so
    /// the system color and the outline follow the menu's appearance. No color is an empty outlined circle.
    static func menuSwatch(for color: TagColor?, diameter: CGFloat = 12) -> NSImage {
        let size = NSSize(width: diameter, height: diameter)
        let image = NSImage(size: size, flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            if let color {
                color.color.setFill()
                circle.fill()
            }
            NSColor.labelColor.withAlphaComponent(color == nil ? 0.5 : 0.25).setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = color?.title ?? String(localized: .colorNone)
        return image
    }

    /// The Color submenu: None first, then each color with its swatch. Each item's represented object is
    /// made by `representedObject` from the stored value ("" for none); the shared color gets a checkmark.
    static func menu(
        sharedStoredValue: String?,
        action: Selector,
        target: AnyObject?,
        representedObject: (String) -> Any?
    ) -> NSMenu {
        let menu = NSMenu()
        let options: [TagColor?] = [nil] + allCases
        for option in options {
            let storedValue = option?.rawValue ?? ""
            let item = NSMenuItem(
                title: option?.title ?? String(localized: .colorNone),
                action: action,
                keyEquivalent: ""
            )
            item.target = target
            item.image = menuSwatch(for: option)
            item.representedObject = representedObject(storedValue)
            item.state = sharedStoredValue == storedValue ? .on : .off
            menu.addItem(item)
        }
        return menu
    }
}
