import Foundation
import Testing
@testable import StravaClone

struct SearchHighlightTests {
    /// The parts of `text` shown in bold.
    private func bold(_ text: AttributedString) -> [String] {
        text.runs
            .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map { String(text[$0.range].characters) }
    }

    @Test func findsTheQueryWhateverItsCaseAndAccents() {
        let range = SearchHighlight.match(of: "Éli", in: "éliott Martin")

        #expect(range.map { String("éliott Martin"[$0]) } == "éli")
    }

    @Test func boldsOnlyTheMatchedPart() {
        let name = SearchHighlight.highlighted("Léa Bernard", query: "bern")

        #expect(bold(name) == ["Bern"])
        #expect(String(name.characters) == "Léa Bernard")
    }

    @Test func ignoresTheSpacesAroundTheQuery() {
        #expect(bold(SearchHighlight.highlighted("Hugo Petit", query: "  hugo ")) == ["Hugo"])
    }

    @Test func boldsNothingWithoutAMatch() {
        #expect(bold(SearchHighlight.highlighted("Hugo Petit", query: "zoé")).isEmpty)
        #expect(bold(SearchHighlight.highlighted("Hugo Petit", query: "")).isEmpty)
    }
}
