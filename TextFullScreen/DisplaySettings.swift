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
    /// The color pad's saved-color squares, in order; nil is an empty square. Stored separated by ";".
    @AppStorage("colorSlots") private var colorSlotsRaw = ""
    /// Colors saved by an earlier version, which kept a plain list. Moved into the squares on first use.
    @AppStorage("savedColors") private var oldSavedColorsRaw = ""

    nonisolated static let colorSlotCount = 40

    var colorSlots: [TextColor?] {
        get {
            Self.colorSlots(from: colorSlotsRaw.isEmpty ? oldSavedColorsRaw : colorSlotsRaw)
        }
        nonmutating set {
            colorSlotsRaw = Self.rawValue(of: newValue)
            oldSavedColorsRaw = ""
        }
    }

    nonisolated static func colorSlots(from raw: String) -> [TextColor?] {
        var slots: [TextColor?] = raw.isEmpty
            ? []
            : raw.split(separator: ";", omittingEmptySubsequences: false).map { TextColor(rawValue: String($0)) }
        slots += Array(repeating: nil, count: max(0, colorSlotCount - slots.count))
        return Array(slots.prefix(colorSlotCount))
    }

    nonisolated static func rawValue(of slots: [TextColor?]) -> String {
        slots.prefix(colorSlotCount).map { $0?.rawValue ?? "" }.joined(separator: ";")
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
    /// Off: scrolling text uses the same Maximum size as fitted text. On: it has its own (`scrollTextSize`).
    @AppStorage("separateScrollSize") var separateScrollSize = false
    /// Pan: On keeps each row on its own line, all panning together. Off joins the rows into one line.
    @AppStorage("panKeepsRows") var panKeepsRows = false

    // MARK: Gradient

    /// On: the text is painted with the gradient below instead of the single text color.
    @AppStorage("gradientEnabled") var gradientEnabled = false
    @AppStorage("gradientStyle") var gradientStyle: GradientStyle = .whole
    @AppStorage("gradientAnchor") var gradientAnchor: GradientAnchor = .screen
    @AppStorage("gradientDirection") var gradientDirection: GradientDirection = .blend
    @AppStorage("gradientRepeats") var gradientRepeats = false
    @AppStorage("gradientShadesBetween") var gradientShadesBetween = 3
    /// The gradient's colors in order, stored like `colorSlots`. Empty means the default colors;
    /// "none" means every color was removed from the pad.
    @AppStorage("gradientColors") private var gradientColorsRaw = ""

    var gradientColors: [TextColor] {
        get { Self.gradientColors(from: gradientColorsRaw) }
        nonmutating set {
            gradientColorsRaw = newValue.isEmpty ? "none" : newValue.map(\.rawValue).joined(separator: ";")
        }
    }

    nonisolated static func gradientColors(from raw: String) -> [TextColor] {
        if raw == "none" { return [] }
        let colors = raw.split(separator: ";").compactMap { TextColor(rawValue: String($0)) }
        return colors.isEmpty ? TextGradient.defaultColors : colors
    }

    /// The color pad's dots, stored as JSON next to the colors they make.
    @AppStorage("gradientPad") private var gradientPadRaw = ""
    /// The pad's wave slider, 0...1.
    @AppStorage("gradientOpacity") var gradientOpacity = GradientOpacity.standard
    @AppStorage("gradientTexture") var gradientTexture: GradientTexture = .grain
    /// The texture dial, 0...1 in sixteenths. 0 shows no texture.
    @AppStorage("gradientTextureAmount") var gradientTextureAmount = 0.0
    /// The appearance buttons at the top of the pad.
    @AppStorage("appScheme") var appScheme: AppScheme = .auto

    /// The color pad. Writing it also writes the gradient's colors. When the stored colors were
    /// changed another way (an older version, a saved slot), the pad is rebuilt from them.
    var gradientPad: ColorPadState {
        get {
            let colors = gradientColors
            if let pad = ColorPadState.decode(gradientPadRaw), pad.colors.map(\.rawValue) == colors.map(\.rawValue) {
                return pad
            }
            return ColorPadState(colors: colors)
        }
        nonmutating set {
            gradientPadRaw = newValue.json
            gradientColors = newValue.colors
        }
    }

    /// The gradient to paint the text with, or nil while gradients are off.
    var gradient: TextGradient? {
        let pad = gradientPad
        let colors = pad.colors
        guard gradientEnabled, !colors.isEmpty else { return nil }
        return TextGradient(
            colors: colors, style: gradientStyle, anchor: gradientAnchor,
            direction: gradientDirection, repeats: gradientRepeats, shadesBetween: gradientShadesBetween,
            opacity: gradientOpacity, texture: gradientTexture, textureAmount: gradientTextureAmount,
            usesCustomColors: !pad.customColors.isEmpty
        )
    }

    /// The size scrolling text is drawn at, as a fraction of the largest that fits.
    var scrollSizeInUse: Double {
        separateScrollSize ? scrollTextSize : Double(fillPercent) / 100
    }

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
            scrollSpeed: scrollSpeed, scrollTextSize: scrollTextSize,
            separateScrollSize: separateScrollSize, panKeepsRows: panKeepsRows,
            colorSlots: Self.rawValue(of: colorSlots),
            gradientEnabled: gradientEnabled, gradientStyle: gradientStyle.rawValue,
            gradientAnchor: gradientAnchor.rawValue, gradientDirection: gradientDirection.rawValue,
            gradientRepeats: gradientRepeats, gradientShadesBetween: gradientShadesBetween,
            gradientColors: gradientColorsRaw,
            gradientPad: gradientPadRaw, gradientOpacity: gradientOpacity, gradientTexture: gradientTexture.rawValue,
            gradientTextureAmount: gradientTextureAmount, appScheme: appScheme.rawValue
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
        // Slots saved before this choice existed kept the two sizes apart
        separateScrollSize = saved.separateScrollSize ?? true
        panKeepsRows = saved.panKeepsRows ?? false
        // Slots saved before colors were included leave the saved colors as they are
        if let raw = saved.colorSlots { colorSlots = Self.colorSlots(from: raw) }
        // Slots saved before gradients existed had none
        gradientEnabled = saved.gradientEnabled ?? false
        if let value = saved.gradientStyle.flatMap(GradientStyle.init(rawValue:)) { gradientStyle = value }
        if let value = saved.gradientAnchor.flatMap(GradientAnchor.init(rawValue:)) { gradientAnchor = value }
        if let value = saved.gradientDirection.flatMap(GradientDirection.init(rawValue:)) { gradientDirection = value }
        if let value = saved.gradientRepeats { gradientRepeats = value }
        if let value = saved.gradientShadesBetween { gradientShadesBetween = value }
        if let value = saved.gradientColors { gradientColorsRaw = value }
        if let value = saved.gradientPad { gradientPadRaw = value }
        if let value = saved.gradientOpacity { gradientOpacity = value }
        if let value = saved.gradientTexture.flatMap(GradientTexture.init(rawValue:)) { gradientTexture = value }
        if let value = saved.gradientTextureAmount { gradientTextureAmount = value }
        if let value = saved.appScheme.flatMap(AppScheme.init(rawValue:)) { appScheme = value }
    }

    /// Puts every setting back to how the app first starts, and removes all saved colors.
    /// The saved-settings slots themselves are kept. Values match the declarations above.
    func loadDefaults() {
        font = .standard
        weight = .black
        color = .black
        colorSlots = Array(repeating: nil, count: Self.colorSlotCount)
        scrollEnabled = false
        fillPercent = 80
        motion = .pan
        panDirection = .rightToLeft
        riseDirection = .bottomToTop
        scrollSpeed = 1
        scrollTextSize = 1
        separateScrollSize = false
        panKeepsRows = false
        gradientEnabled = false
        gradientStyle = .whole
        gradientAnchor = .screen
        gradientDirection = .blend
        gradientRepeats = false
        gradientShadesBetween = 3
        gradientColorsRaw = ""
        gradientPadRaw = ""
        gradientOpacity = GradientOpacity.standard
        gradientTexture = .grain
        gradientTextureAmount = 0
        appScheme = .auto
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
    /// Nil in slots saved before this choice existed.
    var separateScrollSize: Bool?
    /// Nil in slots saved before this choice existed.
    var panKeepsRows: Bool?
    /// The saved colors, in the same form as `DisplaySettings.colorSlots`. Nil in slots saved
    /// before colors were included.
    var colorSlots: String?
    // Gradient settings; all nil in slots saved before gradients existed.
    var gradientEnabled: Bool?
    var gradientStyle: String?
    var gradientAnchor: String?
    var gradientDirection: String?
    var gradientRepeats: Bool?
    var gradientShadesBetween: Int?
    var gradientColors: String?
    var gradientPad: String?
    var gradientOpacity: Double?
    var gradientTexture: String?
    var gradientTextureAmount: Double?
    var appScheme: String?

    /// How many saved colors the slot holds, if it holds them.
    var savedColorCount: Int? {
        colorSlots.map { DisplaySettings.colorSlots(from: $0).compactMap { $0 }.count }
    }

    /// A short description for the slot's row, e.g. "SF Pro · Black · 80% · 3 colors".
    var summary: String {
        let fontName = TextFont(rawValue: font)?.displayName ?? "Font"
        let weightName = TextWeight(rawValue: weight)?.displayName ?? ""
        let layout = scrollEnabled
            ? (ScrollMotion(rawValue: motion)?.displayName ?? "Scroll")
            : "\(fillPercent)%"
        let colors = savedColorCount.map { $0 == 1 ? "1 color" : "\($0) colors" } ?? ""
        let gradient = gradientEnabled == true
            ? (GradientStyle(rawValue: gradientStyle ?? "")?.displayName ?? "Gradient") + " gradient"
            : ""
        return [fontName, weightName, layout, gradient, colors].filter { !$0.isEmpty }.joined(separator: " · ")
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

    // MARK: Hue, saturation and brightness (all 0...1)

    init(hue: Double, saturation: Double, brightness: Double) {
        let h = (hue.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * 6
        let s = min(max(saturation, 0), 1), v = min(max(brightness, 0), 1)
        let i = Int(h.rounded(.down)) % 6
        let f = h - h.rounded(.down)
        let p = v * (1 - s), q = v * (1 - s * f), t = v * (1 - s * (1 - f))
        switch i {
        case 0: self.init(red: v, green: t, blue: p)
        case 1: self.init(red: q, green: v, blue: p)
        case 2: self.init(red: p, green: v, blue: t)
        case 3: self.init(red: p, green: q, blue: v)
        case 4: self.init(red: t, green: p, blue: v)
        default: self.init(red: v, green: p, blue: q)
        }
    }

    var hsb: (hue: Double, saturation: Double, brightness: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue), delta = maxC - minC
        var hue = 0.0
        if delta > 0 {
            if maxC == red { hue = ((green - blue) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxC == green { hue = (blue - red) / delta + 2 }
            else { hue = (red - green) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxC == 0 ? 0 : delta / maxC, maxC)
    }

    // MARK: Hex

    /// Reads "#RRGGBB" or "RRGGBB".
    init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// e.g. "#FF8000"
    var hex: String {
        let byte = { (v: Double) in Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
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
