import SwiftUI
import CoreText

// MARK: - Stored Settings

/// The user's display preferences, saved in UserDefaults.
///
/// Add one to any view with `private var settings = DisplaySettings()`. Every copy reads and
/// writes the same stored values, so the Settings window and the main window stay in sync.
struct DisplaySettings: nonisolated DynamicProperty {
    @AppStorage("textFont") var font: TextFont = .standard
    @AppStorage("textWeight") var weight: TextWeight = .black
    @AppStorage("textColor") var color: TextColor = .black
    /// The user's own colors to pick from, oldest first, separated by ";".
    @AppStorage("savedColors") private var savedColorsRaw = ""

    static let maxSavedColors = 16

    var savedColors: [TextColor] {
        get { savedColorsRaw.split(separator: ";").compactMap { TextColor(rawValue: String($0)) } }
        nonmutating set { savedColorsRaw = newValue.prefix(Self.maxSavedColors).map(\.rawValue).joined(separator: ";") }
    }

    /// Off: the text shrinks until all of it fits on screen (the original behavior).
    /// On: the text keeps a large size and moves across the screen.
    @AppStorage("scrollEnabled") var scrollEnabled = false
    /// While scrolling is off: how much of the screen the text may fill at most, in percent.
    @AppStorage("fillPercent") var fillPercent = 80
    @AppStorage("scrollMotion") var motion: ScrollMotion = .pan
    @AppStorage("panDirection") var panDirection: PanDirection = .rightToLeft
    @AppStorage("riseDirection") var riseDirection: RiseDirection = .bottomToTop
    /// Multiplier on the base scrolling speed; 1 is normal.
    @AppStorage("scrollSpeed") var scrollSpeed = 1.0
    /// Fraction of the largest text size that fits on screen while scrolling; 1 is the largest.
    @AppStorage("scrollTextSize") var scrollTextSize = 1.0

    static let fillPercentRange = 80...100
    static let scrollSpeedRange = 0.25...4.0
    static let scrollTextSizeRange = 0.2...1.0

    /// The way the text travels, combining the motion with that motion's direction.
    var scrollDirection: ScrollDirection {
        switch motion {
        case .pan: panDirection == .rightToLeft ? .left : .right
        case .rise: riseDirection == .bottomToTop ? .up : .down
        }
    }

    // MARK: Saved slots

    static let slotCount = 3

    /// The settings saved in a slot (numbered from 1), or nil if it's empty.
    func saved(inSlot slot: Int) -> SavedSettings? {
        guard let json = slotJSON(slot) else { return nil }
        return try? JSONDecoder().decode(SavedSettings.self, from: Data(json.utf8))
    }

    /// Saves the current settings into a slot, replacing what was there.
    func save(toSlot slot: Int) {
        let current = SavedSettings(
            font: font.rawValue, weight: weight.rawValue, color: color.rawValue,
            fillPercent: fillPercent, scrollEnabled: scrollEnabled, motion: motion.rawValue,
            panDirection: panDirection.rawValue, riseDirection: riseDirection.rawValue,
            scrollSpeed: scrollSpeed, scrollTextSize: scrollTextSize
        )
        guard let data = try? JSONEncoder().encode(current) else { return }
        setSlotJSON(String(decoding: data, as: UTF8.self), slot)
    }

    /// Makes the settings in a slot the current ones. Anything the slot can't restore is left as it is.
    func load(fromSlot slot: Int) {
        guard let saved = saved(inSlot: slot) else { return }
        if let value = TextFont(rawValue: saved.font) { font = value }
        if let value = TextWeight(rawValue: saved.weight) { weight = value }
        if let value = TextColor(rawValue: saved.color) { color = value }
        fillPercent = min(max(saved.fillPercent, Self.fillPercentRange.lowerBound), Self.fillPercentRange.upperBound)
        scrollEnabled = saved.scrollEnabled
        if let value = ScrollMotion(rawValue: saved.motion) { motion = value }
        if let value = PanDirection(rawValue: saved.panDirection) { panDirection = value }
        if let value = RiseDirection(rawValue: saved.riseDirection) { riseDirection = value }
        scrollSpeed = saved.scrollSpeed
        scrollTextSize = saved.scrollTextSize
    }

    func clear(slot: Int) {
        setSlotJSON(nil, slot)
    }

    // Each slot holds its settings as JSON. Kept in AppStorage so views update when a slot changes.
    @AppStorage("savedSettings1") private var slot1: String?
    @AppStorage("savedSettings2") private var slot2: String?
    @AppStorage("savedSettings3") private var slot3: String?

    private func slotJSON(_ slot: Int) -> String? {
        switch slot {
        case 1: slot1
        case 2: slot2
        default: slot3
        }
    }

    private func setSlotJSON(_ json: String?, _ slot: Int) {
        switch slot {
        case 1: slot1 = json
        case 2: slot2 = json
        default: slot3 = json
        }
    }
}

/// A snapshot of every display setting, as kept in a saved slot.
nonisolated struct SavedSettings: Codable, Sendable {
    var font: String
    var weight: String
    var color: String
    var fillPercent: Int
    var scrollEnabled: Bool
    var motion: String
    var panDirection: String
    var riseDirection: String
    var scrollSpeed: Double
    var scrollTextSize: Double

    /// A short description for the slot's row, e.g. "SF Pro · Black · 80%".
    var summary: String {
        let fontName = TextFont(rawValue: font)?.displayName ?? "Font"
        let weightName = TextWeight(rawValue: weight)?.displayName ?? ""
        let layout = scrollEnabled
            ? (ScrollMotion(rawValue: motion)?.displayName ?? "Scroll")
            : "\(fillPercent)%"
        return [fontName, weightName, layout].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - Color

/// The color of the big text, stored as sRGB components.
nonisolated struct TextColor: Hashable, Sendable, RawRepresentable {
    var red: Double
    var green: Double
    var blue: Double
    var opacity: Double = 1

    static let black = TextColor(red: 0, green: 0, blue: 0)

    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity) }

    init(red: Double, green: Double, blue: Double, opacity: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.opacity = opacity
    }

    init(_ color: Color) {
        let resolved = color.resolve(in: EnvironmentValues())
        self.init(red: Double(resolved.red), green: Double(resolved.green), blue: Double(resolved.blue), opacity: Double(resolved.opacity))
    }

    /// e.g. "0.000,0.478,1.000,1.000"
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        self.init(red: parts[0], green: parts[1], blue: parts[2], opacity: parts[3])
    }

    var rawValue: String {
        [red, green, blue, opacity].map { String(format: "%.3f", min(max($0, 0), 1)) }.joined(separator: ",")
    }
}

// MARK: - Font

/// Apple's own system typefaces.
nonisolated enum SystemTypeface: String, CaseIterable, Identifiable, Sendable {
    case sfPro, sfProRounded, newYork, sfMono

    var id: Self { self }

    var displayName: String {
        switch self {
        case .sfPro: "SF Pro (Default)"
        case .sfProRounded: "SF Pro Rounded"
        case .newYork: "New York"
        case .sfMono: "SF Mono"
        }
    }

    var design: Font.Design {
        switch self {
        case .sfPro: .default
        case .sfProRounded: .rounded
        case .newYork: .serif
        case .sfMono: .monospaced
        }
    }
}

/// The typeface the big text is drawn in: one of Apple's system typefaces or any installed font family.
nonisolated enum TextFont: Hashable, Sendable, RawRepresentable {
    case system(SystemTypeface)
    case family(String)

    /// SF Pro, the font the app has always used.
    static let standard = TextFont.system(.sfPro)

    init?(rawValue: String) {
        if rawValue.hasPrefix("system:") {
            guard let typeface = SystemTypeface(rawValue: String(rawValue.dropFirst("system:".count))) else { return nil }
            self = .system(typeface)
        } else if rawValue.hasPrefix("family:") {
            self = .family(String(rawValue.dropFirst("family:".count)))
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .system(let typeface): "system:\(typeface.rawValue)"
        case .family(let name): "family:\(name)"
        }
    }

    var displayName: String {
        switch self {
        case .system(let typeface): typeface.displayName
        case .family(let name): name
        }
    }

    /// A font at exactly `size` points. For an installed family, SwiftUI picks the family's face
    /// closest to `weight`, e.g. Times New Roman has no Black face, so Black gives its Bold.
    func font(size: CGFloat, weight: TextWeight) -> Font {
        switch self {
        case .system(let typeface):
            .system(size: size, weight: weight.fontWeight, design: typeface.design)
        case .family(let name):
            .custom(name, fixedSize: size).weight(weight.fontWeight)
        }
    }
}

nonisolated enum TextWeight: String, CaseIterable, Identifiable, Sendable {
    case regular, medium, semibold, bold, heavy, black

    var id: Self { self }

    var displayName: String { rawValue.capitalized }

    var fontWeight: Font.Weight {
        switch self {
        case .regular: .regular
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        case .heavy: .heavy
        case .black: .black
        }
    }
}

/// Font families installed on this device.
nonisolated enum FontLibrary {
    /// Every visible font family, sorted for display.
    static let allFamilies: [String] = {
        let names = CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
        return names.filter { !$0.hasPrefix(".") }
    }()

    /// Well-known families that ship with macOS, iPadOS and iOS, limited to those installed here.
    static let classicFamilies: [String] = {
        let installed = Set(allFamilies)
        return [
            "Times New Roman", "Helvetica Neue", "Arial", "Avenir Next", "Futura", "Gill Sans",
            "Optima", "Georgia", "Baskerville", "Didot", "Palatino", "American Typewriter",
            "Courier New", "Marker Felt", "Chalkboard SE", "Noteworthy",
        ].filter(installed.contains)
    }()
}

// MARK: - Scrolling

/// Pan moves the text sideways on a single line; rise moves it vertically, like film credits.
nonisolated enum ScrollMotion: String, CaseIterable, Identifiable, Sendable {
    case pan, rise

    var id: Self { self }

    var displayName: String {
        switch self {
        case .pan: "Pan"
        case .rise: "Rise"
        }
    }
}

nonisolated enum PanDirection: String, CaseIterable, Identifiable, Sendable {
    case rightToLeft, leftToRight

    var id: Self { self }

    var displayName: String {
        switch self {
        case .rightToLeft: "← Right to Left"
        case .leftToRight: "→ Left to Right"
        }
    }
}

nonisolated enum RiseDirection: String, CaseIterable, Identifiable, Sendable {
    case bottomToTop, topToBottom

    var id: Self { self }

    var displayName: String {
        switch self {
        case .bottomToTop: "↑ Bottom to Top"
        case .topToBottom: "↓ Top to Bottom"
        }
    }
}

/// The way scrolling text travels across the screen.
nonisolated enum ScrollDirection: Hashable, Sendable {
    case left, right, up, down

    var isHorizontal: Bool { self == .left || self == .right }
}
