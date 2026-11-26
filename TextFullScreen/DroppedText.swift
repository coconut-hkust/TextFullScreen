import Foundation
import UniformTypeIdentifiers
import CoreTransferable

// MARK: - Dropped text

/// Text dragged onto the main window from another app: a selection, or a text or Markdown file.
nonisolated struct DroppedText: Transferable {
    var text: String
    /// True when it came from a file named .md, .markdown and the like.
    var isMarkdownFile = false

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdtext"]

    static var transferRepresentation: some TransferRepresentation {
        // A file (from Finder, Files…), so its name can tell whether it's Markdown
        FileRepresentation(importedContentType: .plainText) { received in
            let data = try Data(contentsOf: received.file)
            return DroppedText(
                text: decode(data),
                isMarkdownFile: markdownExtensions.contains(received.file.pathExtension.lowercased())
            )
        }
        // Selected text dragged out of another app
        ProxyRepresentation(importing: { (string: String) in DroppedText(text: string) })
    }

    /// Reads UTF-8 (or UTF-16 with a byte-order mark), falling back to Latin-1 so nothing is refused.
    static func decode(_ data: Data) -> String {
        if let string = String(data: data, encoding: .utf8) { return string }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let string = String(data: data, encoding: .utf16) { return string }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Markdown to plain text

/// Turns Markdown into the plain text it reads as: the symbols that only change how text looks
/// (# headings, **bold**, *italic*, `code`, > quotes, list bullets, [links](…), fences, rules)
/// are removed, and the words are kept. Symbols escaped with a backslash, and everything inside
/// code blocks, are kept as written.
nonisolated enum MarkdownText {
    /// Whether the text looks like Markdown: a heading, emphasis, a link, a code fence, a quote,
    /// or a couple of list items.
    static func looksLikeMarkdown(_ text: String) -> Bool {
        let strongSignals = [
            #"(?m)^\s{0,3}#{1,6}\s+\S"#,          // # Heading
            #"(\*\*|__)\S(.*?\S)?\1"#,             // **bold**
            #"!?\[[^\]\n]+\]\([^)\n]+\)"#,         // [link](url)
            #"(?m)^\s{0,3}(```|~~~)"#,             // code fence
            #"(?m)^\s{0,3}>\s"#,                   // > quote
            #"(?<![\w*])\*(?=\S)[^*\n]+(?<=\S)\*(?![\w*])"#, // *italic*
            #"~~\S(.*?\S)?~~"#,                    // ~~strike~~
            #"`[^`\n]+`"#,                         // `code`
        ]
        if strongSignals.contains(where: { matches($0, in: text) }) { return true }
        return count(#"(?m)^\s{0,3}([-*+]|\d{1,3}[.)])\s+\S"#, in: text) >= 2
    }

    static func plainText(from markdown: String) -> String {
        var output: [String] = []
        var inFence = false
        var fenceMarker = ""
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Code fences: drop the ``` lines, keep what's between them as it is
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let marker = String(trimmed.prefix(3))
                if !inFence {
                    inFence = true
                    fenceMarker = marker
                    continue
                } else if marker == fenceMarker {
                    inFence = false
                    continue
                }
            }
            if inFence {
                output.append(line)
                continue
            }

            // Horizontal rules (---, ***, ___) and setext heading underlines (=== or --- under a line)
            if matches(#"^\s{0,3}([-*_])(\s*\1){2,}\s*$"#, in: line) || matches(#"^\s{0,3}=+\s*$"#, in: line) {
                let previousHasText = index > 0 && !lines[index - 1].trimmingCharacters(in: .whitespaces).isEmpty
                if previousHasText || !matches(#"^\s{0,3}=+\s*$"#, in: line) { continue }
            }

            // Reference-style link definitions: [id]: https://…
            if matches(#"^\s{0,3}\[[^\]]+\]:\s+\S+"#, in: line) { continue }

            var text = line
            text = replace(#"^\s{0,3}#{1,6}(\s+|$)"#, in: text, with: "")             // # Heading
            text = replace(#"\s+#+\s*$"#, in: text, with: "", onlyIf: line != text)    // closing #s of a heading
            text = replace(#"^\s{0,3}(>\s?)+"#, in: text, with: "")                    // > quote
            text = replace(#"^(\s*)[-*+]\s+(\[[ xX]\]\s+)?"#, in: text, with: "$1")    // - bullet, - [x] task
            text = replace(#"^(\s*)(\d{1,9}[.)])\s+\[[ xX]\]\s+"#, in: text, with: "$1$2 ") // 1. [ ] task
            output.append(inline(text))
        }

        // At most one blank line in a row, none at the ends
        let joined = output.joined(separator: "\n")
        return replace(#"\n{3,}"#, in: joined, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes the inline formatting from one line.
    private static func inline(_ line: String) -> String {
        // Hide escaped symbols (\*) so they aren't read as formatting, then bring them back as plain symbols
        var placeholders: [String] = []
        var text = replaceEach(#"\\([\\`*_{}\[\]()#+\-.!>~|<])"#, in: line) { groups in
            placeholders.append(groups[1])
            return "\u{E000}\(placeholders.count - 1)\u{E001}"
        }

        // Inline code first, keeping its contents exactly
        var codes: [String] = []
        text = replaceEach(#"(`+)(.+?)\1"#, in: text) { groups in
            codes.append(groups[2].trimmingCharacters(in: .whitespaces))
            return "\u{E002}\(codes.count - 1)\u{E003}"
        }

        text = replace(#"!\[([^\]]*)\]\([^)]*\)"#, in: text, with: "$1")       // ![alt](image)
        text = replace(#"\[([^\]]+)\]\([^)]*\)"#, in: text, with: "$1")        // [text](url)
        text = replace(#"\[([^\]]+)\]\[[^\]]*\]"#, in: text, with: "$1")       // [text][ref]
        text = replace(#"<((?:https?|mailto):[^>\s]+)>"#, in: text, with: "$1") // <https://…>
        text = replace(#"</?[A-Za-z][A-Za-z0-9-]*(\s[^<>]*)?/?>"#, in: text, with: "") // <b>, </span>, <br/>
        text = replace(#"(\*\*\*|___)(?=\S)(.+?)(?<=\S)\1"#, in: text, with: "$2") // ***bold italic***
        text = replace(#"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#, in: text, with: "$2")    // **bold**
        text = replace(#"(?<![\w*])\*(?=\S)(.+?)(?<=\S)\*(?![\w*])"#, in: text, with: "$1") // *italic*
        text = replace(#"(?<![\w_])_(?=\S)(.+?)(?<=\S)_(?![\w_])"#, in: text, with: "$1")   // _italic_ (not snake_case)
        text = replace(#"~~(?=\S)(.+?)(?<=\S)~~"#, in: text, with: "$1")         // ~~strike~~
        text = replace(#"==(?=\S)(.+?)(?<=\S)=="#, in: text, with: "$1")         // ==highlight==

        text = replaceEach("\u{E002}(\\d+)\u{E003}", in: text) { codes[Int($0[1]) ?? 0] }
        text = replaceEach("\u{E000}(\\d+)\u{E001}", in: text) { placeholders[Int($0[1]) ?? 0] }
        return text
    }

    // MARK: Regular expressions

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static func matches(_ pattern: String, in text: String) -> Bool {
        regex(pattern)?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func count(_ pattern: String, in text: String) -> Int {
        regex(pattern)?.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
    }

    private static func replace(_ pattern: String, in text: String, with template: String, onlyIf condition: Bool = true) -> String {
        guard condition, let regex = regex(pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    /// Replaces each match with what `transform` returns for its groups (0 is the whole match).
    private static func replaceEach(_ pattern: String, in text: String, _ transform: ([String]) -> String) -> String {
        guard let regex = regex(pattern) else { return text }
        var result = ""
        var last = text.startIndex
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range, in: text) else { continue }
            result += text[last..<range.lowerBound]
            let groups = (0..<match.numberOfRanges).map { i in
                Range(match.range(at: i), in: text).map { String(text[$0]) } ?? ""
            }
            result += transform(groups)
            last = range.upperBound
        }
        result += text[last...]
        return result
    }
}
