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

    /// Off: the text shrinks until all of it fits on screen (the original behavior).
    /// On: the text keeps a large size and moves across the screen.
    @AppStorage("scrollEnabled") var scrollEnabled = false
    @AppStorage("scrollMotion") var motion: ScrollMotion = .pan
    @AppStorage("panDirection") var panDirection: PanDirection = .rightToLeft
    @AppStorage("riseDirection") var riseDirection: RiseDirection = .bottomToTop
    /// Multiplier on the base scrolling speed; 1 is normal.
    @AppStorage("scrollSpeed") var scrollSpeed = 1.0
    /// Fraction of the largest text size that fits on screen while scrolling; 1 is the largest.
    @AppStorage("scrollTextSize") var scrollTextSize = 1.0

    static let scrollSpeedRange = 0.25...4.0
    static let scrollTextSizeRange = 0.2...1.0

    /// The way the text travels, combining the motion with that motion's direction.
    var scrollDirection: ScrollDirection {
        switch motion {
        case .pan: panDirection == .rightToLeft ? .left : .right
        case .rise: riseDirection == .bottomToTop ? .up : .down
        }
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
