import SwiftUI
import CoreText
import Foundation

/// Shows text at a large, fixed size and moves it across the screen instead of shrinking it to fit.
///
/// Panning text runs along a single line, like a news ticker. Rising text wraps to the screen
/// width, like film credits. The text enters past one edge, travels until it has completely left
/// past the opposite edge, then starts over.
struct ScrollingTextView: View {
    let text: String
    let font: TextFont
    let weight: TextWeight
    let direction: ScrollDirection
    /// Multiplier on the base speed; 1 is normal.
    let speed: Double
    /// Fraction of the largest size that fits on screen; 1 is the largest.
    let sizeScale: Double
    /// Pan only: keep each row on its own line, all panning across together, instead of joining
    /// the rows into one long line.
    var keepsRows = false
    /// Paints the text with a gradient when set. The plain color comes from `foregroundColor`.
    var gradient: TextGradient? = nil

    @Environment(\.fontResolutionContext) private var fontContext
    /// The laid-out size of the moving text, which sets how far it travels before starting over.
    @State private var textSize: CGSize = .zero
    @State private var clock = ScrollClock()

    /// Space left on each side of rising text, as a fraction of the screen width.
    private let sideMargin: CGFloat = 0.03

    /// Base speed in font sizes (ems) per second. Panning is faster because only a few
    /// giant letters fit on screen at once.
    private var emsPerSecond: Double { direction.isHorizontal ? 2 : 1 }

    var body: some View {
        GeometryReader { proxy in
            let screen = proxy.size
            let fontSize = fittedFontSize(in: screen)
            let displayText = direction.isHorizontal && !keepsRows ? singleLine(text) : text
            let pointsPerSecond = speed * emsPerSecond * fontSize
            let loopLength = direction.isHorizontal
                ? screen.width + textSize.width
                : screen.height + textSize.height

            let styled = styledText(displayText)

            TimelineView(.animation) { timeline in
                let travelled = clock.distance(at: timeline.date, speed: pointsPerSecond, loopLength: loopLength)
                let placed = movingText(styled, fontSize: fontSize, screenWidth: screen.width)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { textSize = $0 }
                    .offset(offset(travelled: travelled, screen: screen))
                    .frame(width: screen.width, height: screen.height, alignment: frontEdge)

                if let gradient, gradient.style == .whole, gradient.anchor == .screen {
                    // A still gradient over the whole screen, seen only through the moving letters
                    GradientFillView(gradient: gradient)
                        .frame(width: screen.width, height: screen.height)
                        .mask { placed.foregroundStyle(.black) }
                        .opacity(gradient.alpha)
                } else {
                    placed
                }
            }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
    }

    /// The text with each character or word colored, if the gradient does that.
    private func styledText(_ string: String) -> Text {
        if let gradient, gradient.style != .whole {
            Text(gradient.attributedString(string))
        } else {
            Text(verbatim: string)
        }
    }

    @ViewBuilder
    private func movingText(_ text: Text, fontSize: CGFloat, screenWidth: CGFloat) -> some View {
        let font = font.font(size: fontSize, weight: weight)
        let laidOut = Group {
            if direction.isHorizontal {
                // Rows line up at the edge that enters first, so they arrive together
                text
                    .font(font)
                    .lineLimit(keepsRows ? nil : 1)
                    .multilineTextAlignment(direction == .right ? .trailing : .leading)
                    .fixedSize()
            } else {
                text
                    .font(font)
                    .multilineTextAlignment(.center)
                    .frame(width: screenWidth * (1 - 2 * sideMargin))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if let gradient, gradient.style != .whole || gradient.anchor == .text {
            // Stretched over the text itself, so it travels along with it (per character or word,
            // this adds the texture and strength)
            laidOut.textFill(gradient, plain: .primary)
        } else {
            laidOut
        }
    }

    // MARK: Position

    /// The edge of the text that enters the screen first. The text is laid out against this edge
    /// and then offset, so its position never depends on its measured size, and typing while it
    /// moves doesn't shift the part already on screen (for right-to-left and bottom-to-top).
    private var frontEdge: Alignment {
        switch direction {
        case .left: .leading
        case .right: .trailing
        case .up: .top
        case .down: .bottom
        }
    }

    /// At `travelled == 0` the text sits just past the edge it enters from.
    private func offset(travelled: CGFloat, screen: CGSize) -> CGSize {
        switch direction {
        case .left: CGSize(width: screen.width - travelled, height: 0)
        case .right: CGSize(width: travelled - screen.width, height: 0)
        case .up: CGSize(width: 0, height: screen.height - travelled)
        case .down: CGSize(width: 0, height: travelled - screen.height)
        }
    }

    // MARK: Size

    /// The largest font size that fits, scaled by `sizeScale`. Panning text fills the screen height,
    /// unless the screen is so narrow that only a sliver of a letter would show. Rising text also
    /// keeps its widest word within the screen width, so no word is split in two.
    private func fittedFontSize(in screen: CGSize) -> CGFloat {
        guard screen.width > 0, screen.height > 0 else { return 1 }

        let referenceSize: CGFloat = 100
        let reference = coreTextFont(size: referenceSize)
        let lineHeight = CTFontGetAscent(reference) + CTFontGetDescent(reference) + CTFontGetLeading(reference)
        // Kept rows share the screen height between them
        var largest = referenceSize * screen.height / (lineHeight * CGFloat(panRowCount))

        if direction.isHorizontal {
            // On an iPhone held upright, a line as tall as the screen makes each letter wider than
            // the screen. Keep at least a couple of letters across instead.
            let averageLetterWidth = width(of: "abcdefghijklmnopqrstuvwxyz", in: reference) / 26
            largest = min(largest, referenceSize * screen.width / (2.5 * averageLetterWidth))
        } else {
            let lineWidth = screen.width * (1 - 2 * sideMargin)
            largest = min(largest, sizeFittingWidestRun(within: lineWidth, reference: reference))
        }
        return max(1, largest * sizeScale)
    }

    private func sizeFittingWidestRun(within lineWidth: CGFloat, reference: CTFont) -> CGFloat {
        let widest = unbreakableRuns(in: text)
            .map { (run: $0, width: width(of: $0, in: reference)) }
            .sorted { $0.width > $1.width }
            .prefix(5)
        guard let first = widest.first, first.width > 0 else { return .infinity }

        var size = CTFontGetSize(reference) * lineWidth / first.width
        // Apple's system fonts change shape with size (optical sizing), so widths aren't exactly
        // proportional to size. Re-measure the widest runs at the estimated size and correct.
        for _ in 0..<2 {
            let font = coreTextFont(size: size)
            let widestAtSize = widest.map { width(of: $0.run, in: font) }.max() ?? 0
            guard widestAtSize > 0 else { break }
            size *= lineWidth / widestAtSize
        }
        // A little slack so rounding in layout never pushes a word onto two lines.
        return size * 0.98
    }

    /// The pieces of text a line can't be broken inside, found with the same Unicode line-breaking
    /// rules text layout uses: usually words, but single characters in Chinese and Japanese, and
    /// the parts between "/" and "-" in a web address.
    private func unbreakableRuns(in text: String) -> Set<String> {
        let string = text as NSString
        let range = CFRange(location: 0, length: string.length)
        guard let tokenizer = CFStringTokenizerCreate(nil, string, range, kCFStringTokenizerUnitLineBreak, nil) else { return [] }

        var runs = Set<String>()
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let run = string.substring(with: NSRange(location: tokenRange.location, length: tokenRange.length))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Skip freak runs, like a long code with nowhere to break. Shrinking all the text to
            // fit one would make everything tiny, so those are left to split instead.
            if !run.isEmpty, run.count <= 24 {
                runs.insert(run)
            }
        }
        return runs
    }

    /// The Core Text font SwiftUI will draw with, so measurements match what appears on screen.
    private func coreTextFont(size: CGFloat) -> CTFont {
        font.font(size: size, weight: weight).resolve(in: fontContext).ctFont
    }

    private func width(of string: String, in font: CTFont) -> CGFloat {
        let attributed = NSAttributedString(
            string: string,
            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
        )
        let line = CTLineCreateWithAttributedString(attributed as CFAttributedString)
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    /// How many lines panning text takes up: its rows when they're kept, otherwise one.
    private var panRowCount: Int {
        guard direction.isHorizontal, keepsRows else { return 1 }
        return max(1, text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count)
    }

    /// Panning text runs on one line, so line breaks become spaces.
    private func singleLine(_ string: String) -> String {
        string.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

/// Adds up how far the text has travelled, frame by frame. Because distance builds up from the
/// speed of each frame, rather than being worked out from the time since starting, changing the
/// speed never makes the text jump.
private final class ScrollClock {
    private var travelled: CGFloat = 0
    private var lastFrame: Date?

    func distance(at date: Date, speed: CGFloat, loopLength: CGFloat) -> CGFloat {
        if let lastFrame {
            // Cap the step so the text carries on smoothly after the window was hidden or stalled.
            let elapsed = min(max(date.timeIntervalSince(lastFrame), 0), 1.0 / 15)
            travelled += speed * elapsed
        }
        lastFrame = date
        if loopLength > 0, travelled >= loopLength {
            travelled = travelled.truncatingRemainder(dividingBy: loopLength)
        }
        return travelled
    }
}

#Preview("Pan") {
    ScrollingTextView(text: "Hello, world!", font: .standard, weight: .black, direction: .left, speed: 1, sizeScale: 1)
        .frame(width: 800, height: 500)
}

#Preview("Rise") {
    ScrollingTextView(text: "The quick brown fox jumps over the lazy dog", font: .standard, weight: .black, direction: .up, speed: 1, sizeScale: 1)
        .frame(width: 800, height: 500)
}
