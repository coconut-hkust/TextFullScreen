import SwiftUI
import Foundation

// MARK: - Gradient options

/// How the gradient is laid over the text.
nonisolated enum GradientStyle: String, CaseIterable, Identifiable, Sendable {
    /// One giant gradient behind all the text. It only shows where a letter is drawn over it.
    case whole
    /// Each character gets one solid color, stepping through the gradient.
    case perCharacter
    /// Each word gets one solid color, stepping through the gradient.
    case perWord

    var id: Self { self }

    var displayName: String {
        switch self {
        case .whole: "Whole Text"
        case .perCharacter: "Per Character"
        case .perWord: "Per Word"
        }
    }
}

/// For a whole-text gradient: whether it stays put on the screen or travels with the text.
nonisolated enum GradientAnchor: String, CaseIterable, Identifiable, Sendable {
    /// The gradient fills the screen and stays still; letters show whatever part they're over.
    case screen
    /// The gradient is stretched over the text itself and moves along with it.
    case text

    var id: Self { self }

    var displayName: String {
        switch self {
        case .screen: "Fixed to Screen"
        case .text: "Moves with Text"
        }
    }
}

/// The way a whole-text gradient runs.
nonisolated enum GradientDirection: String, CaseIterable, Identifiable, Sendable {
    /// The first two colors blend across the diagonal and the third fades in from the top.
    case blend
    case horizontal, vertical, diagonal

    var id: Self { self }

    var displayName: String {
        switch self {
        case .blend: "Blend"
        case .horizontal: "→"
        case .vertical: "↓"
        case .diagonal: "↘"
        }
    }

    var accessibilityName: String {
        switch self {
        case .blend: "Blend: two colors across, the third from the top"
        case .horizontal: "Left to right"
        case .vertical: "Top to bottom"
        case .diagonal: "Diagonal"
        }
    }

    /// Start and end as unit points, with y growing downward.
    var unitPoints: (start: UnitPoint, end: UnitPoint) {
        switch self {
        case .horizontal: (.leading, .trailing)
        case .vertical: (.top, .bottom)
        case .diagonal, .blend: (.topLeading, .bottomTrailing)
        }
    }
}

/// One layer of a whole-text gradient: a straight gradient between two points. Layers are drawn in
/// order, each over the last.
nonisolated struct GradientLayer: Hashable, Sendable {
    struct Stop: Hashable, Sendable {
        var color: TextColor
        var location: Double
    }

    var stops: [Stop]
    var start: UnitPoint
    var end: UnitPoint

    var swiftUI: LinearGradient {
        LinearGradient(stops: stops.map { .init(color: $0.color.color, location: $0.location) }, startPoint: start, endPoint: end)
    }
}

// MARK: - The gradient

/// Everything needed to paint text with a gradient, read from the settings.
nonisolated struct TextGradient: Hashable, Sendable {
    var colors: [TextColor]
    var style: GradientStyle
    var anchor: GradientAnchor
    var direction: GradientDirection
    /// Per character or word: whether the colors cycle round instead of spreading once over all the text.
    var repeats: Bool
    /// When repeating: how many in-between shades sit between one chosen color and the next.
    var shadesBetween: Int
    /// The wave slider, 0...1: how opaque the gradient text is.
    var opacity: Double = GradientOpacity.standard
    var texture: GradientTexture = .none
    /// The texture dial, 0...1 in sixteenths.
    var textureAmount: Double = 0
    /// True when the pad has custom colors; then a blend becomes a plain slanted gradient of all the colors.
    var usesCustomColors = false

    /// How opaque the whole text is drawn.
    var alpha: Double { GradientOpacity.alpha(opacity) }

    /// How strongly the texture is drawn over the letters, 0 for none.
    var textureOpacity: Double { texture == .none ? 0 : texture.alpha * textureAmount }

    /// Blue with its split complements (red and yellow), as placed on the color pad.
    static let defaultColors = ColorPadState.standard.colors
    static let shadesBetweenRange = 0...99

    var swiftUIGradient: Gradient {
        Gradient(colors: colors.map(\.color))
    }

    /// The layers of a whole-text gradient.
    var layers: [GradientLayer] {
        guard let first = colors.first else { return [] }
        let steps = 12 // Enough stops that the OKLab mix shows through SwiftUI's own blending
        func spread(start: UnitPoint, end: UnitPoint) -> GradientLayer {
            GradientLayer(
                stops: (0..<steps).map { i in
                    let t = Double(i) / Double(steps - 1)
                    return .init(color: color(at: t), location: t)
                },
                start: start, end: end
            )
        }

        guard direction == .blend else {
            let points = direction.unitPoints
            return [spread(start: points.start, end: points.end)]
        }
        if colors.count == 1 {
            return [GradientLayer(stops: [.init(color: first, location: 0), .init(color: first, location: 1)], start: .top, end: .bottom)]
        }
        if usesCustomColors || colors.count > 3 {
            // With custom colors, all of them run in a plain gradient, slanted up to the left
            return [spread(start: UnitPoint(x: 0.75, y: 0.933), end: UnitPoint(x: 0.25, y: 0.067))]
        }
        // The first color blends into the second over the first 75% of the diagonal...
        var layers = [GradientLayer(
            stops: (0..<steps).map { i in
                let t = Double(i) / Double(steps - 1)
                return .init(color: colors[0].mixed(with: colors[1], by: min(t / 0.75, 1)), location: t)
            },
            start: .topLeading, end: .bottomTrailing
        )]
        // ...and the third fades in from the top, to 90% at the bottom
        if colors.count == 3 {
            var clear = colors[2]
            clear.opacity = 0
            var strong = colors[2]
            strong.opacity *= 0.9
            layers.append(GradientLayer(stops: [.init(color: clear, location: 0), .init(color: strong, location: 1)], start: .top, end: .bottom))
        }
        return layers
    }

    // MARK: Colors for each character or word

    /// The color of piece `index` (a character or word) out of `count` pieces.
    func color(ofPiece index: Int, count: Int) -> TextColor {
        guard let first = colors.first else { return .black }
        guard colors.count > 1 else { return first }

        if repeats {
            // Each chosen color is `shadesBetween + 1` pieces from the next, and after the last
            // color the gradient runs back into the first, so the pattern loops without a jump.
            let step = Double(shadesBetween + 1)
            let position = Double(index) / step
            let segment = Int(position.rounded(.down))
            let fraction = position - position.rounded(.down)
            let from = colors[segment % colors.count]
            let to = colors[(segment + 1) % colors.count]
            return from.mixed(with: to, by: fraction)
        } else {
            // Spread once over all the text: the first piece has the first color, the last piece the last.
            let t = count <= 1 ? 0 : Double(index) / Double(count - 1)
            return color(at: t)
        }
    }

    /// The color at `t` along the gradient (0 is the first color, 1 the last), with the colors evenly spaced.
    func color(at t: Double) -> TextColor {
        guard let first = colors.first else { return .black }
        guard colors.count > 1 else { return first }
        let scaled = min(max(t, 0), 1) * Double(colors.count - 1)
        let segment = min(Int(scaled.rounded(.down)), colors.count - 2)
        return colors[segment].mixed(with: colors[segment + 1], by: scaled - Double(segment))
    }

    /// One color for every character of `text` (by `Character`, so an emoji or accented letter is one
    /// piece), or nil for a whole-text gradient. Spaces and line breaks don't use up a color.
    func characterColors(for text: String) -> [TextColor?]? {
        switch style {
        case .whole:
            return nil
        case .perCharacter:
            let characters = Array(text)
            let count = characters.filter { !$0.isWhitespace }.count
            var piece = 0
            return characters.map { character in
                guard !character.isWhitespace else { return nil }
                defer { piece += 1 }
                return color(ofPiece: piece, count: count)
            }
        case .perWord:
            let pieces = Self.wordIndexes(in: text)
            let count = (pieces.compactMap { $0 }.max() ?? -1) + 1
            return pieces.map { $0.map { color(ofPiece: $0, count: count) } }
        }
    }

    /// For each character, which word it belongs to (counting from 0), or nil for spaces. Words are
    /// found with the system's word rules, so Chinese and Japanese split into words too. Punctuation
    /// takes the word just before it ("Hello," is one color).
    static func wordIndexes(in text: String) -> [Int?] {
        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        // Which character each word starts at
        var wordStarts = Set<Int>()
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .substringNotRequired]) { _, range, _, _ in
            wordStarts.insert(text.distance(from: text.startIndex, to: range.lowerBound))
        }

        var result: [Int?] = []
        result.reserveCapacity(characters.count)
        var current = -1
        var previousWasSpace = true
        for (offset, character) in characters.enumerated() {
            if character.isWhitespace {
                result.append(nil)
                previousWasSpace = true
                continue
            }
            // A new word starts at a word boundary, or at anything after a space (e.g. a lone "—")
            if wordStarts.contains(offset) || previousWasSpace || current < 0 {
                current += 1
            }
            result.append(current)
            previousWasSpace = false
        }
        return result
    }

    /// `text` with each character or word colored, for SwiftUI `Text`.
    func attributedString(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let colors = characterColors(for: text) else { return attributed }
        var index = attributed.startIndex
        for color in colors {
            guard index < attributed.endIndex else { break }
            let next = attributed.characters.index(after: index)
            if let color { attributed[index..<next].foregroundColor = color.color }
            index = next
        }
        return attributed
    }
}

extension TextColor {
    /// A color part of the way to `other`; `fraction` 0 is this color and 1 is `other`. Mixed in
    /// OKLab, so the colors in between stay bright instead of muddy.
    nonisolated func mixed(with other: TextColor, by fraction: Double) -> TextColor {
        let f = min(max(fraction, 0), 1)
        let a = oklab, b = other.oklab
        return TextColor(
            oklab: (a.l + (b.l - a.l) * f, a.a + (b.a - a.a) * f, a.b + (b.b - a.b) * f),
            opacity: opacity + (other.opacity - opacity) * f
        )
    }

    nonisolated var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: opacity)
    }
}

// MARK: - Painting SwiftUI text

/// A whole-text gradient's layers, with the texture over them. Fills whatever space it's given.
struct GradientFillView: View {
    let gradient: TextGradient

    var body: some View {
        ZStack {
            ForEach(Array(gradient.layers.enumerated()), id: \.offset) { _, layer in
                Rectangle().fill(layer.swiftUI)
            }
            TextureView(gradient: gradient)
        }
    }
}

/// The texture tiled over everything, at the strength set on the dial. Nothing when there's none.
struct TextureView: View {
    let gradient: TextGradient

    var body: some View {
        if gradient.textureOpacity > 0, let image = gradient.texture.image {
            Image(decorative: image, scale: CGFloat(image.width) / gradient.texture.tileSize)
                .resizable(resizingMode: .tile)
                .interpolation(gradient.texture.isPixelated ? .none : .medium)
                .opacity(gradient.textureOpacity)
                .allowsHitTesting(false)
        }
    }
}

extension View {
    /// Colors text with the gradient when there is one, or the plain color otherwise. A whole-text
    /// gradient is stretched over this view's own frame; to keep it fixed to the screen, mask a
    /// full-screen `GradientFillView` with the text instead (see `ScrollingTextView`). The texture is
    /// laid over the letters either way.
    @ViewBuilder
    func textFill(_ gradient: TextGradient?, plain color: Color) -> some View {
        if let gradient {
            if gradient.style == .whole {
                self.foregroundStyle(.black)
                    .hidden()
                    .overlay { GradientFillView(gradient: gradient).mask { self.foregroundStyle(.black) } }
                    .opacity(gradient.alpha)
            } else {
                self.overlay { TextureView(gradient: gradient).mask { self.foregroundStyle(.black) } }
                    .opacity(gradient.alpha)
            }
        } else {
            self.foregroundStyle(color)
        }
    }
}
