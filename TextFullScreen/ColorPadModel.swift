import SwiftUI
import CoreGraphics

/// The color pad's model: dots placed on a wheel, color harmonies, swatches and textures. It works
/// like the gradient pickers in the Arc and Zen browsers, written for this app.

// MARK: - Light and dark

/// The three appearance buttons at the top of the pad.
nonisolated enum AppScheme: String, CaseIterable, Identifiable, Sendable {
    /// Follows the system's Light or Dark Mode, full screen included.
    case auto
    case light
    case dark

    var id: Self { self }

    var symbol: String {
        switch self {
        case .auto: "sparkles"
        case .light: "sun.max"
        case .dark: "moon.stars"
        }
    }

    var displayName: String {
        switch self {
        case .auto: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// The appearance to force, or nil to follow the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension View {
    /// Shows the app in the chosen appearance. On the Mac it's set for the whole app, which also
    /// reliably goes back to following the system when Automatic is chosen again.
    func appAppearance(_ scheme: AppScheme) -> some View {
        #if os(macOS)
        onAppear { NSApplication.shared.appearance = scheme.nsAppearance }
            .onChange(of: scheme) { _, new in NSApplication.shared.appearance = new.nsAppearance }
        #else
        preferredColorScheme(scheme.colorScheme)
        #endif
    }
}

#if os(macOS)
import AppKit

extension AppScheme {
    var nsAppearance: NSAppearance? {
        switch self {
        case .auto: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
#endif

// MARK: - Harmonies

/// How the other dots are placed around the main one, as angles on the wheel.
nonisolated enum ColorHarmony: String, CaseIterable, Identifiable, Codable, Sendable {
    case floating, complementary, singleAnalogous, splitComplementary, analogous, triadic

    var id: Self { self }

    /// Degrees added to the main dot's angle for each other dot, in order.
    var offsets: [Double] {
        switch self {
        case .floating: []
        case .complementary: [180]
        case .singleAnalogous: [310]
        case .splitComplementary: [150, 210]
        case .analogous: [50, 310]
        case .triadic: [120, 240]
        }
    }

    var displayName: String {
        switch self {
        case .floating: "Single"
        case .complementary: "Complementary"
        case .singleAnalogous, .analogous: "Analogous"
        case .splitComplementary: "Split complementary"
        case .triadic: "Triadic"
        }
    }

    /// The harmonies that place exactly `count` dots, in the order the harmony button steps through them.
    static func options(for count: Int) -> [ColorHarmony] {
        allCases.filter { $0.offsets.count + 1 == count }
    }
}

// MARK: - The pad

/// Everything on the color pad: the dots, plus any custom colors added by hex.
///
/// Only the main dot is placed by hand; the others follow it by the harmony, at the same distance
/// from the middle. What the distance means depends on the dots' kind (see `Kind`).
nonisolated struct ColorPadState: Codable, Equatable, Sendable {
    /// What a dot's distance from the middle means.
    enum Kind: String, Codable, Sendable {
        /// Angle is hue; distance is lightness, black in the middle to white at the edge.
        case standard
        /// Set by a color swatch: lightness is fixed and distance takes the color toward white.
        case explicitLightness
        /// Set by the gray swatches: distance is the gray, black in the middle.
        case blackWhite
    }

    static let maxDots = 3

    /// The main dot's angle in degrees, clockwise from the right (0..<360).
    var hue: Double
    /// The main dot's distance from the middle, from 0 (middle) to 1 (edge).
    var distance: Double
    var harmony: ColorHarmony
    /// How many dots there are, from 0 to `maxDots`.
    var count: Int
    var kind: Kind = .standard
    /// For `explicitLightness`: the fixed lightness, 0...1.
    var lightness: Double = 0.5
    /// Exact colors read back from somewhere else (an older version or a saved slot), shown until a
    /// dot is moved. Stored as `TextColor` raw values.
    var exactColors: [String]? = nil
    /// Colors typed in or picked under Custom Colors, added after the dots' colors.
    var customColors: [String] = []

    /// Blue with its split complements, as the gradient first appears.
    static let standard = ColorPadState(hue: 210, distance: 0.5, harmony: .splitComplementary, count: 3)

    /// The angle of each dot, main dot first.
    var hues: [Double] {
        guard count > 0 else { return [] }
        return ([0] + harmony.offsets.prefix(count - 1)).map { (hue + $0).truncatingRemainder(dividingBy: 360) }
    }

    /// The dots' colors, main dot first.
    var dotColors: [TextColor] {
        if let exactColors, exactColors.count == count {
            let colors = exactColors.compactMap(TextColor.init(rawValue:))
            if colors.count == count { return colors }
        }
        return hues.map { color(hue: $0) }
    }

    var custom: [TextColor] { customColors.compactMap(TextColor.init(rawValue:)) }

    /// Every color of the gradient, in order: the dots, then the custom colors.
    var colors: [TextColor] { dotColors + custom }

    /// The color a dot at `hue` (at the main dot's distance) has.
    func color(hue: Double) -> TextColor {
        let d = min(max(distance, 0), 1)
        switch kind {
        case .standard:
            return TextColor(hue: hue / 360, saturation: 0.9 + 0.1 * d, lightness: d)
        case .explicitLightness:
            return TextColor(hue: hue / 360, saturation: 1 - d, brightness: lightness)
        case .blackWhite:
            return TextColor(red: d, green: d, blue: d)
        }
    }

    // MARK: Editing

    /// Moves the main dot; the others follow.
    mutating func moveMain(hue newHue: Double?, distance newDistance: Double) {
        if count == 0 { count = 1; harmony = .floating }
        if let newHue { hue = newHue }
        distance = min(max(newDistance, 0), 1)
        exactColors = nil
    }

    /// Adds a dot, moving to a harmony with one more dot.
    mutating func addDot() {
        guard count < Self.maxDots else { return }
        if count == 0 { distance = 0.5 }
        count += 1
        harmony = ColorHarmony.options(for: count).first ?? .floating
        exactColors = nil
    }

    /// Removes dot `index` (the last one when nil). Removing the main dot makes the next one the main dot.
    mutating func removeDot(_ index: Int? = nil) {
        guard count > 0 else { return }
        let index = min(index ?? count - 1, count - 1)
        if index == 0, count > 1 { hue = hues[1] }
        let wasAnalogous = harmony == .analogous
        count -= 1
        // Three analogous dots become two analogous ones
        harmony = wasAnalogous && count == 2 ? .singleAnalogous : (ColorHarmony.options(for: count).first ?? .floating)
        exactColors = nil
    }

    /// Makes dot `index` the main dot; the others are placed around it again by the harmony.
    mutating func makeMain(_ index: Int) {
        guard index > 0, index < count else { return }
        hue = hues[index]
        exactColors = nil
    }

    /// Steps to the next harmony for this many dots.
    mutating func nextHarmony() {
        let options = ColorHarmony.options(for: count)
        guard options.count > 1 else { return }
        let index = options.firstIndex(of: harmony) ?? -1
        harmony = options[(index + 1) % options.count]
        exactColors = nil
    }

    /// Sets up the dots from a swatch. Custom colors are kept.
    mutating func apply(_ preset: Preset) {
        hue = preset.hue
        distance = preset.distance
        kind = preset.kind
        lightness = preset.lightness
        count = preset.count
        harmony = preset.harmony
        exactColors = nil
    }

    // MARK: Reading back

    /// The pad that gives `colors`, for colors that weren't made on this pad (an older version's,
    /// or a saved slot's). The dots match the first three colors as closely as the pad allows and keep
    /// them exactly until moved; any more become custom colors.
    init(colors: [TextColor]) {
        let dots = Array(colors.prefix(Self.maxDots))
        guard let first = dots.first else {
            self.init(hue: 210, distance: 0.5, harmony: .floating, count: 0)
            return
        }
        let main = first.hsl
        let offsets = dots.dropFirst().map { color -> Double in
            let h = (color.hsl.hue - main.hue) * 360
            return (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        }
        func gap(_ a: Double, _ b: Double) -> Double {
            let d = abs(a - b).truncatingRemainder(dividingBy: 360)
            return min(d, 360 - d)
        }
        let best = ColorHarmony.options(for: dots.count).min { a, b in
            zip(a.offsets, offsets).map(gap).reduce(0, +) < zip(b.offsets, offsets).map(gap).reduce(0, +)
        } ?? .floating
        self.init(hue: main.hue * 360, distance: main.lightness, harmony: best, count: dots.count)
        exactColors = dots.map(\.rawValue)
        customColors = colors.dropFirst(Self.maxDots).map(\.rawValue)
    }

    init(hue: Double, distance: Double, harmony: ColorHarmony, count: Int) {
        self.hue = hue
        self.distance = distance
        self.harmony = harmony
        self.count = count
    }

    var json: String {
        (try? JSONEncoder().encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    static func decode(_ json: String) -> ColorPadState? {
        guard !json.isEmpty else { return nil }
        return try? JSONDecoder().decode(ColorPadState.self, from: Data(json.utf8))
    }
}

// MARK: - Swatches

/// A swatch below the pad. Each one sets up the whole pad: where the main dot goes, what kind of
/// dots, how many and in which harmony.
nonisolated struct Preset: Sendable {
    var hue: Double
    var distance: Double
    var kind: ColorPadState.Kind = .standard
    var lightness: Double = 0.5
    var harmony: ColorHarmony = .floating
    var count = 1

    /// The pad this swatch sets up, and so the colors it shows.
    var state: ColorPadState {
        var state = ColorPadState(hue: 0, distance: 0, harmony: .floating, count: 0)
        state.apply(self)
        return state
    }

    private static let hues: [Double] = [0, 25, 45, 90, 145, 175, 205, 250, 300]

    /// Seven pages of nine: vivid, pastel and deep colors, each alone and then as a three-color
    /// harmony, and a page of grays.
    static let pages: [[Preset]] = [
        hues.map { Preset(hue: $0, distance: 0.5) },
        hues.map { Preset(hue: $0, distance: 0.5, harmony: .analogous, count: 3) },
        hues.map { Preset(hue: $0, distance: 0.72, kind: .explicitLightness, lightness: 0.97) },
        hues.map { Preset(hue: $0, distance: 0.72, kind: .explicitLightness, lightness: 0.97, harmony: .triadic, count: 3) },
        hues.map { Preset(hue: $0, distance: 0.3) },
        hues.map { Preset(hue: $0, distance: 0.3, harmony: .splitComplementary, count: 3) },
        (0..<9).map { Preset(hue: 0, distance: 1 - Double($0) / 8, kind: .blackWhite) },
    ]
}

// MARK: - Opacity

/// The wave slider: how strongly the gradient colors show, 0...1. At 0 the text is faint, at 1 solid.
nonisolated enum GradientOpacity {
    static let range = 0.0...1.0
    static let standard = 1.0

    /// How opaque the gradient text is drawn. Eased, so the slider changes little near full strength.
    static func alpha(_ value: Double) -> Double {
        let v = min(max(value, 0), 1)
        return 0.3 + 0.7 * v * v
    }
}

// MARK: - Texture

/// Textures laid over the letters, chosen by clicking the dial. The dial's 16 steps set how strong it is.
nonisolated enum GradientTexture: String, CaseIterable, Identifiable, Codable, Sendable {
    case none, grain, sand, denim, tweed

    var id: Self { self }

    var displayName: String { rawValue.capitalized }

    /// The strength a texture starts at when it's first turned on.
    static let defaultAmount = 10.0 / 16

    /// How strong the texture is at full amount.
    var alpha: Double {
        switch self {
        case .none: 0
        case .grain: 0.6
        case .sand: 0.45
        case .denim, .tweed: 0.7
        }
    }

    /// How big one tile of the texture is drawn, in points.
    var tileSize: CGFloat { 128 }

    var isPixelated: Bool { self == .grain || self == .sand }

    func next(_ step: Int = 1) -> GradientTexture {
        let all = Self.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + step + all.count) % all.count]
    }

    /// The texture tile, drawn once and kept.
    var image: CGImage? { Self.cache[self] ?? nil }

    private static let cache: [GradientTexture: CGImage?] = {
        var images: [GradientTexture: CGImage?] = [:]
        for texture in allCases where texture != .none { images[texture] = texture.draw() }
        return images
    }()

    /// Draws a 256-pixel tile (128 points at 2×). Seeded, so it looks the same every time.
    private func draw() -> CGImage? {
        let size = 256
        guard let context = CGContext(
            data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        var random = SeededRandom(seed: rawValue.utf8.reduce(7) { $0 &* 31 &+ UInt64($1) })
        let full = CGFloat(size)

        func dot(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, white: Bool, alpha: CGFloat) {
            context.setFillColor(gray: white ? 1 : 0, alpha: alpha)
            context.fill(CGRect(x: x, y: y, width: w, height: h))
        }

        switch self {
        case .none:
            return nil
        case .grain:
            // Every pixel a little lighter or darker
            for y in 0..<size {
                for x in 0..<size {
                    let v = random.next()
                    dot(CGFloat(x), CGFloat(y), 1, 1, white: v > 0.5, alpha: CGFloat(abs(v - 0.5)) * 0.5)
                }
            }
        case .sand:
            // Scattered specks of two sizes
            for _ in 0..<5200 {
                let s: CGFloat = random.next() < 0.8 ? 1 : 2
                dot(CGFloat(random.next()) * full, CGFloat(random.next()) * full, s, s,
                    white: random.next() < 0.45, alpha: 0.18 + CGFloat(random.next()) * 0.3)
            }
        case .denim:
            // Diagonal twill lines with uneven threads
            context.setLineCap(.round)
            let spacing: CGFloat = 4
            var offset = -full
            while offset < full * 2 {
                let alpha = 0.12 + CGFloat(random.next()) * 0.18
                context.setStrokeColor(gray: random.next() < 0.5 ? 0 : 1, alpha: alpha)
                context.setLineWidth(1.4)
                context.move(to: CGPoint(x: offset, y: 0))
                context.addLine(to: CGPoint(x: offset + full, y: full))
                context.strokePath()
                offset += spacing
            }
            for _ in 0..<1800 {
                dot(CGFloat(random.next()) * full, CGFloat(random.next()) * full, 1, 1, white: true, alpha: 0.25)
            }
        case .tweed:
            // Short flecks in two directions, like woven wool
            context.setLineCap(.round)
            for _ in 0..<1400 {
                let x = CGFloat(random.next()) * full, y = CGFloat(random.next()) * full
                let length = 3 + CGFloat(random.next()) * 6
                let across = random.next() < 0.5
                context.setStrokeColor(gray: random.next() < 0.5 ? 0 : 1, alpha: 0.15 + CGFloat(random.next()) * 0.3)
                context.setLineWidth(1 + CGFloat(random.next()))
                context.move(to: CGPoint(x: x, y: y))
                context.addLine(to: across ? CGPoint(x: x + length, y: y + length * 0.3) : CGPoint(x: x + length * 0.3, y: y + length))
                context.strokePath()
            }
        }
        return context.makeImage()
    }
}

/// A small repeatable random number source, so the textures come out the same on every launch.
private nonisolated struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }

    /// A number in 0..<1.
    mutating func next() -> Double {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Double(state >> 11) / Double(1 << 53)
    }
}

// MARK: - OKLab

extension TextColor {
    /// The color in OKLab (Björn Ottosson's published formulas), where mixes between colors stay even and bright.
    nonisolated var oklab: (l: Double, a: Double, b: Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let r = linear(red), g = linear(green), b = linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (
            0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        )
    }

    nonisolated init(oklab: (l: Double, a: Double, b: Double), opacity: Double = 1) {
        let l = pow(oklab.l + 0.3963377774 * oklab.a + 0.2158037573 * oklab.b, 3)
        let m = pow(oklab.l - 0.1055613458 * oklab.a - 0.0638541728 * oklab.b, 3)
        let s = pow(oklab.l - 0.0894841775 * oklab.a - 1.291485548 * oklab.b, 3)
        func gamma(_ c: Double) -> Double {
            let v = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
            return min(max(v, 0), 1)
        }
        self.init(
            red: gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            green: gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            blue: gamma(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
            opacity: opacity
        )
    }
}

// MARK: - Hue, saturation and lightness

extension TextColor {
    /// Hue, saturation and lightness, all 0...1.
    nonisolated init(hue: Double, saturation: Double, lightness: Double) {
        let l = min(max(lightness, 0), 1), s = min(max(saturation, 0), 1)
        let brightness = l + s * min(l, 1 - l)
        let hsbSaturation = brightness == 0 ? 0 : 2 * (1 - l / brightness)
        self.init(hue: hue, saturation: hsbSaturation, brightness: brightness)
    }

    nonisolated var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let hsb = self.hsb
        let l = hsb.brightness * (1 - hsb.saturation / 2)
        let s = (l == 0 || l == 1) ? 0 : (hsb.brightness - l) / min(l, 1 - l)
        return (hsb.hue, s, l)
    }
}
