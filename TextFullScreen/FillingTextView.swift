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
    var color: Color = .black

    @Environment(\.fontResolutionContext) private var fontContext

    var body: some View {
        Canvas { context, size in
            guard let layout = FittedLayout(
                text: text,
                in: size,
                makeFont: { font.font(size: $0, weight: weight).resolve(in: fontContext).ctFont }
            ) else { return }
            context.withCGContext { cg in
                layout.draw(in: cg, canvasSize: size, color: cgColor)
            }
        }
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

/// Text broken into centered lines at the largest size whose drawn glyphs fit the screen.
private struct FittedLayout {
    struct Line {
        let ctLine: CTLine
        /// Position of the line's baseline start, in layout space (y grows upward).
        let origin: CGPoint
    }

    let lines: [Line]
    /// The union of the glyph outlines, in layout space.
    let inkBounds: CGRect

    init?(text: String, in screen: CGSize, makeFont: (CGFloat) -> CTFont) {
        guard screen.width > 1, screen.height > 1 else { return nil }

        let paragraphs = text.components(separatedBy: .newlines)
        let runs = Self.widestUnbreakableRuns(in: text, font: makeFont(100))

        // The drawn size grows with the font size, so find the largest one that fits by bisection.
        var low: CGFloat = 1
        var high: CGFloat = max(screen.width, screen.height) * 4
        var best: FittedLayout?
        for _ in 0..<26 {
            let size = (low + high) / 2
            let font = makeFont(size)
            if let candidate = Self.layout(paragraphs, runs: runs, font: font, screen: screen) {
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

    /// Lays the text out at `font`, or returns nil if it doesn't fit on screen.
    private static func layout(_ paragraphs: [String], runs: [String], font: CTFont, screen: CGSize) -> FittedLayout? {
        // Never split a word across lines just to make the text larger.
        for run in runs where width(of: run, in: font) > screen.width {
            return nil
        }

        let lineHeight = CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]

        var lines: [Line] = []
        var ink = CGRect.null
        var baseline: CGFloat = 0

        for paragraph in paragraphs {
            let attributed = NSAttributedString(string: paragraph, attributes: attributes) as CFAttributedString
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let length = (paragraph as NSString).length
            var start = 0
            repeat {
                let count = length == 0 ? 0 : CTTypesetterSuggestLineBreak(typesetter, start, Double(screen.width))
                let ctLine = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                let advance = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil)) - CGFloat(CTLineGetTrailingWhitespaceWidth(ctLine))
                let origin = CGPoint(x: -advance / 2, y: baseline) // Centered on x = 0
                lines.append(Line(ctLine: ctLine, origin: origin))

                let glyphs = CTLineGetBoundsWithOptions(ctLine, .useGlyphPathBounds)
                if !glyphs.isNull, !glyphs.isEmpty {
                    ink = ink.union(glyphs.offsetBy(dx: origin.x, dy: origin.y))
                }
                baseline -= lineHeight
                start += max(count, 1)
            } while start < length
        }

        guard !ink.isNull else { return nil } // Only whitespace: nothing to draw
        guard ink.width <= screen.width, ink.height <= screen.height else { return nil }
        return FittedLayout(lines: lines, inkBounds: ink)
    }

    func draw(in cg: CGContext, canvasSize: CGSize, color: CGColor) {
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

    // MARK: Measuring

    /// The widest pieces of text a line can't be broken inside (usually words), measured at
    /// `font`. Only the few widest matter for whether the text fits.
    private static func widestUnbreakableRuns(in text: String, font: CTFont) -> [String] {
        let string = text as NSString
        let range = CFRange(location: 0, length: string.length)
        guard let tokenizer = CFStringTokenizerCreate(nil, string, range, kCFStringTokenizerUnitLineBreak, nil) else { return [] }

        var runs = Set<String>()
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let run = string.substring(with: NSRange(location: tokenRange.location, length: tokenRange.length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !run.isEmpty { runs.insert(run) }
        }
        return runs
            .map { (run: $0, width: width(of: $0, in: font)) }
            .sorted { $0.width > $1.width }
            .prefix(5)
            .map(\.run)
    }

    private static func width(of string: String, in font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }
}

#Preview("Single character") {
    FillingTextView(text: "2", font: .standard, weight: .black)
        .frame(width: 1000, height: 625)
        .background(.white)
}

#Preview("Sentence") {
    FillingTextView(text: "The quick brown fox jumps over the lazy dog", font: .standard, weight: .black)
        .frame(width: 1000, height: 625)
        .background(.white)
}
