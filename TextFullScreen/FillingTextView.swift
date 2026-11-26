import SwiftUI
import CoreText
import Foundation

/// Draws text as large as it can go while all of it stays on screen.
///
/// Fitting `Text` with `minimumScaleFactor` sizes the text by its line boxes, which hold space for
/// tall ascenders, low descenders and the gap between lines. Most characters use only part of that
/// space (a "2" covers about 60% of the line height), so the screen was left mostly empty. This view
/// instead sizes and centers the text by the outlines of the glyphs it actually draws.
struct FillingTextView: View {
    let text: String
    let font: TextFont
    let weight: TextWeight
    /// The share of the screen's width and height the text may fill at most; 1 is all of it.
    var fill: CGFloat = 1
    var color: Color = .black
    /// Paints the text with a gradient instead of `color` when set.
    var gradient: TextGradient? = nil
    /// The text grows no larger than this font size, even when the screen has room; nil for no limit.
    var maxFontSize: CGFloat? = nil

    @Environment(\.fontResolutionContext) private var fontContext

    var body: some View {
        Canvas { context, size in
            let fill = min(max(fill, 0.1), 1)
            guard let layout = FittedLayout(
                text: text,
                in: CGSize(width: size.width * fill, height: size.height * fill),
                characterColors: gradient?.characterColors(for: text),
                maxFontSize: maxFontSize,
                makeFont: { font.font(size: $0, weight: weight).resolve(in: fontContext).ctFont }
            ) else { return }
            context.withCGContext { cg in
                if let gradient {
                    layout.draw(in: cg, canvasSize: size, gradient: gradient)
                } else {
                    layout.draw(in: cg, canvasSize: size, color: cgColor)
                }
            }
        }
        .opacity(gradient?.alpha ?? 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    private var cgColor: CGColor {
        #if os(macOS)
        NSColor(color).cgColor
        #else
        UIColor(color).cgColor
        #endif
    }
}

// MARK: - Layout

/// Text in centered rows at the largest size whose drawn glyphs fit the screen. Rows break only
/// where the text has a line break: a row that's too wide makes all the text smaller, it never
/// wraps onto another row.
private struct FittedLayout {
    struct Line {
        let ctLine: CTLine
        /// Position of the line's baseline start, in layout space (y grows upward).
        let origin: CGPoint
    }

    let lines: [Line]
    /// The union of the glyph outlines, in layout space.
    let inkBounds: CGRect

    /// - Parameter characterColors: a color for each `Character` of `text` (nil keeps the drawing
    ///   color), or nil to draw all of it in the drawing color.
    init?(text: String, in screen: CGSize, characterColors: [TextColor?]? = nil,
          maxFontSize: CGFloat? = nil, makeFont: (CGFloat) -> CTFont) {
        guard screen.width > 1, screen.height > 1 else { return nil }

        let paragraphs = Self.paragraphs(of: text, colors: characterColors)

        // The drawn size grows with the font size, so find the largest one that fits by bisection.
        var low: CGFloat = 1
        var high: CGFloat = max(screen.width, screen.height) * 4
        if let maxFontSize { high = min(high, maxFontSize + 0.25) }
        var best: FittedLayout?
        for _ in 0..<26 {
            let size = (low + high) / 2
            let font = makeFont(size)
            if let candidate = Self.layout(paragraphs, font: font, screen: screen) {
                best = candidate
                low = size
            } else {
                high = size
            }
            if high - low < 0.25 { break }
        }
        guard let best else { return nil }
        self = best
    }

    private init(lines: [Line], inkBounds: CGRect) {
        self.lines = lines
        self.inkBounds = inkBounds
    }

    /// `text` split at line breaks, each piece carrying its characters' colors. Characters without
    /// a color take the drawing color.
    private static func paragraphs(of text: String, colors: [TextColor?]?) -> [NSAttributedString] {
        let fromContext = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)

        var result: [NSAttributedString] = []
        var current = NSMutableAttributedString()
        for (offset, character) in text.enumerated() {
            if character.isNewline {
                result.append(current)
                current = NSMutableAttributedString()
                continue
            }
            let attributes: [NSAttributedString.Key: Any]
            if let colors, offset < colors.count, let color = colors[offset] {
                attributes = [colorKey: color.cgColor]
            } else {
                attributes = [fromContext: true]
            }
            current.append(NSAttributedString(string: String(character), attributes: attributes))
        }
        result.append(current)
        return result
    }

    /// Lays the text out at `font`, one row per line of text, or returns nil if it doesn't fit on screen.
    private static func layout(_ paragraphs: [NSAttributedString], font: CTFont, screen: CGSize) -> FittedLayout? {
        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)

        var lines: [Line] = []
        var ink = CGRect.null
        var baseline: CGFloat = 0

        for paragraph in paragraphs {
            let withFont = NSMutableAttributedString(attributedString: paragraph)
            withFont.addAttribute(fontKey, value: font, range: NSRange(location: 0, length: withFont.length))
            let ctLine = CTLineCreateWithAttributedString(withFont as CFAttributedString)
            let advance = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(ctLine))
            let origin = CGPoint(x: -advance / 2, y: baseline) // Centered on x = 0
            lines.append(Line(ctLine: ctLine, origin: origin))

            let glyphs = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
            if !glyphs.isNull, !glyphs.isEmpty {
                ink = ink.union(glyphs.offsetBy(dx: origin.x, dy: origin.y))
            }
            baseline -= lineHeight
        }

        guard !ink.isNull else { return nil } // Only whitespace: nothing to draw
        guard ink.width <= screen.width, ink.height <= screen.height else { return nil }
        return FittedLayout(lines: lines, inkBounds: ink)
    }

    func draw(in cg: CGContext, canvasSize: CGSize, color: CGColor) {
        drawText(in: cg, canvasSize: canvasSize, color: color)
    }

    /// Draws the text with `gradient`. A whole-text gradient only shows where there's a letter;
    /// per character or word, the letters already carry their colors. The texture goes over the letters.
    func draw(in cg: CGContext, canvasSize: CGSize, gradient: TextGradient) {
        // Spread over the whole screen, or over just the drawn text (centered like the text is)
        let area = gradient.anchor == .screen
            ? CGRect(origin: .zero, size: canvasSize)
            : CGRect(x: (canvasSize.width - inkBounds.width) / 2, y: (canvasSize.height - inkBounds.height) / 2,
                     width: inkBounds.width, height: inkBounds.height)
        func point(_ unit: UnitPoint) -> CGPoint {
            CGPoint(x: area.minX + unit.x * area.width, y: area.minY + unit.y * area.height)
        }

        // Everything is drawn into one layer, so each step only paints where the letters are,
        // keeping their smooth edges
        cg.beginTransparencyLayer(auxiliaryInfo: nil)
        drawText(in: cg, canvasSize: canvasSize, color: CGColor(gray: 0, alpha: 1))

        if gradient.style == .whole, let flow = gradient.flowDirection {
            drawFlowingGradient(gradient, flow: flow, in: cg, area: area)
        } else if gradient.style == .whole {
            for (index, layer) in gradient.layers.enumerated() {
                guard let cgGradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                    colors: layer.stops.map(\.color.cgColor) as CFArray,
                    locations: layer.stops.map { CGFloat($0.location) }
                ) else { continue }
                // The first layer replaces the black letters; later ones go over it
                cg.setBlendMode(index == 0 ? .sourceIn : .sourceAtop)
                cg.drawLinearGradient(cgGradient, start: point(layer.start), end: point(layer.end),
                                      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
        }

        if gradient.textureOpacity > 0, let image = gradient.texture.image {
            cg.saveGState()
            cg.setBlendMode(.sourceAtop)
            cg.setAlpha(gradient.textureOpacity)
            cg.interpolationQuality = gradient.texture.isPixelated ? .none : .medium
            let tile = gradient.texture.tileSize
            cg.draw(image, in: CGRect(x: area.minX, y: area.minY, width: tile, height: tile), byTiling: true)
            cg.restoreGState()
        }
        cg.endTransparencyLayer()
    }

    /// A gradient running through every color and back to the first, along the way it flows,
    /// repeated end to end and slid along by how far it has flowed. Draws over the black letters
    /// in the open transparency layer.
    private func drawFlowingGradient(_ gradient: TextGradient, flow: ScrollDirection, in cg: CGContext, area: CGRect) {
        let stops = gradient.loopingStops
        guard area.width > 0, area.height > 0, let cgGradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map(\.color.cgColor) as CFArray,
            locations: stops.map { CGFloat($0.location) }
        ) else { return }

        let horizontal = flow.isHorizontal
        let length = horizontal ? area.width : area.height
        // Toward the left or the top, the tiles slide back; the other way, forward
        let towardStart = flow == .left || flow == .up
        let shift = CGFloat(gradient.flowFraction) * length * (towardStart ? -1 : 1)
        // One tile before the area and one after, so the area is always covered
        for tile in -1...1 {
            let start = CGFloat(tile) * length + shift
            let rect = horizontal
                ? CGRect(x: area.minX + start, y: area.minY, width: length, height: area.height)
                : CGRect(x: area.minX, y: area.minY + start, width: area.width, height: length)
            cg.saveGState()
            cg.clip(to: rect)
            cg.setBlendMode(.sourceIn)
            cg.drawLinearGradient(
                cgGradient,
                start: CGPoint(x: rect.minX, y: rect.minY),
                end: horizontal ? CGPoint(x: rect.maxX, y: rect.minY) : CGPoint(x: rect.minX, y: rect.maxY),
                options: []
            )
            cg.restoreGState()
        }
    }

    private func drawText(in cg: CGContext, canvasSize: CGSize, color: CGColor) {
        cg.saveGState()
        // Put the middle of the glyphs in the middle of the screen, and flip to Core Text's
        // upward y axis.
        cg.translateBy(x: canvasSize.width / 2, y: canvasSize.height / 2)
        cg.scaleBy(x: 1, y: -1)
        cg.translateBy(x: -inkBounds.midX, y: -inkBounds.midY)
        cg.textMatrix = .identity
        cg.setFillColor(color)
        for line in lines {
            cg.textPosition = line.origin
            CTLineDraw(line.ctLine, cg)
        }
        cg.restoreGState()
    }
}

#Preview("Single character") {
    FillingTextView(text: "2", font: .standard, weight: .black)
        .frame(width: 1000, height: 625)
        .background(.white)
}

#Preview("Gradient") {
    FillingTextView(
        text: "The quick brown fox jumps over the lazy dog", font: .standard, weight: .black,
        gradient: TextGradient(colors: TextGradient.defaultColors, style: .perWord, anchor: .screen,
                               direction: .horizontal, repeats: false, shadesBetween: 3)
    )
    .frame(width: 1000, height: 625)
    .background(.white)
}

#Preview("Sentence") {
    FillingTextView(text: "The quick brown fox jumps over the lazy dog", font: .standard, weight: .black)
        .frame(width: 1000, height: 625)
        .background(.white)
}
