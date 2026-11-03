import Foundation

/// The matched part of a search result's name, in bold (ADR-036 §2): found by the app with the
/// same case- and accent-insensitive comparison as the server, so « Éli » finds « éliott ».
enum SearchHighlight {
    /// Where the trimmed query first appears in `text`; nil when it does not, or is empty.
    static func match(of query: String, in text: String) -> Range<String.Index>? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        return text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive])
    }

    /// `text` with its match in bold.
    static func highlighted(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let match = match(of: query, in: text), let range = Range(match, in: attributed) {
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return attributed
    }
}
