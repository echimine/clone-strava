import Foundation

/// The two legal texts embedded in the app as Markdown (ADR-035 §9): they work offline and
/// need no hosting. Shown in a `LegalSheet`, opened from `LegalLinks`.
enum LegalDocument: String, CaseIterable, Identifiable, Sendable {
    case termsOfUse = "terms-of-use"
    case privacyPolicy = "privacy-policy"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .termsOfUse: "Conditions d'utilisation"
        case .privacyPolicy: "Politique de confidentialité"
        }
    }

    struct NotFound: Error {
        let resource: String
    }

    /// Reads the `.md` file from `bundle`: XcodeGen copies `.md` sources into the app resources.
    func load(from bundle: Bundle = .main) throws -> LegalContent {
        guard let url = bundle.url(forResource: rawValue, withExtension: "md") else {
            throw NotFound(resource: "\(rawValue).md")
        }
        return LegalContent(markdown: try String(contentsOf: url, encoding: .utf8))
    }
}

/// A legal text cut into the blocks the sheet draws. SwiftUI's `Text` renders inline Markdown
/// (bold, links) but ignores headings and lists, so blocks are split here and each block's
/// inline Markdown is left for `Text` to render.
///
/// Supported: `#`/`##`/`###` headings, `- ` bullets, paragraphs separated by a blank line
/// (lines of one paragraph are joined with a space).
struct LegalContent: Equatable, Sendable {
    enum Block: Equatable, Sendable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(String)
    }

    let blocks: [Block]

    init(markdown: String) {
        var blocks: [Block] = []
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        for rawLine in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flushParagraph()
            } else if let heading = Self.heading(line) {
                flushParagraph()
                blocks.append(heading)
            } else if line.hasPrefix("- ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2))))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        self.blocks = blocks
    }

    var headings: [String] {
        blocks.compactMap { if case .heading(_, let text) = $0 { text } else { nil } }
    }

    /// Every block's text, one per line, Markdown markers included.
    var plainText: String {
        blocks.map {
            switch $0 {
            case .heading(_, let text), .paragraph(let text), .bullet(let text): text
            }
        }
        .joined(separator: "\n")
    }

    private static func heading(_ line: String) -> Block? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...3).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return .heading(level: hashes, text: line.dropFirst(hashes + 1).trimmingCharacters(in: .whitespaces))
    }
}
