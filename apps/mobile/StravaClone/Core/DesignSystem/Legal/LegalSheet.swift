import SwiftUI

/// Reading sheet for a `LegalDocument` (ADR-035 §9): its title, its rendered Markdown, and "OK".
/// Present it with `.sheet(item:)`, or through `LegalLinks`.
struct LegalSheet: View {
    let document: LegalDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(document.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("OK") { dismiss() }
                    }
                }
        }
        .accessibilityIdentifier("legalSheet.\(document.rawValue)")
    }

    @ViewBuilder private var content: some View {
        if let legal = try? document.load() {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // The navigation bar already shows the document's title (its top heading).
                    ForEach(Array(legal.blocks.enumerated()), id: \.offset) { index, block in
                        if !(index == 0 && block == .heading(level: 1, text: document.title)) {
                            LegalBlockView(block: block)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.spacing)
            }
        } else {
            ContentUnavailableView(document.title, systemImage: "doc.text",
                                   description: Text("Ce document n'a pas pu être ouvert."))
        }
    }
}

private struct LegalBlockView: View {
    let block: LegalContent.Block

    var body: some View {
        switch block {
        case .heading(let level, let text):
            Text(Self.inline(text))
                .font(level == 1 ? .title2.bold() : level == 2 ? .headline : .subheadline.bold())
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        case .paragraph(let text):
            Text(Self.inline(text))
                .font(.body)
        case .bullet(let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(Self.inline(text))
            }
            .font(.body)
        }
    }

    /// Inline Markdown (bold, italic, code, links); the raw text if it does not parse.
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

#Preview("Conditions, clair") {
    LegalSheet(document: .termsOfUse)
        .preferredColorScheme(.light)
}

#Preview("Conditions, sombre") {
    LegalSheet(document: .termsOfUse)
        .preferredColorScheme(.dark)
}

#Preview("Confidentialité, clair") {
    LegalSheet(document: .privacyPolicy)
        .preferredColorScheme(.light)
}

#Preview("Confidentialité, sombre") {
    LegalSheet(document: .privacyPolicy)
        .preferredColorScheme(.dark)
}
