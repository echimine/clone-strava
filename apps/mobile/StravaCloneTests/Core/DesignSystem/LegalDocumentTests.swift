import Foundation
import Testing
@testable import StravaClone

/// The Terms of use and the Privacy Policy embedded in the app (ADR-035 §9), with the outline
/// spec #120 fixes. The unit tests run hosted in the app, so the documents come from the app bundle.
struct LegalDocumentTests {
    @Test func theTermsOfUseLoadWithTheirOutline() throws {
        let content = try LegalDocument.termsOfUse.load()
        #expect(content.headings.contains("Conditions d'utilisation"))
        for heading in ["Le service", "Votre compte", "Abonnement et essai", "Résiliation"] {
            #expect(content.headings.contains(heading), "missing section \(heading)")
        }
    }

    @Test func thePrivacyPolicyLoadsWithItsOutline() throws {
        let content = try LegalDocument.privacyPolicy.load()
        #expect(content.headings.contains("Politique de confidentialité"))
        for heading in [
            "Données collectées",
            "Finalités et bases légales",
            "Conservation",
            "Destinataires",
            "Vos droits et contact",
        ] {
            #expect(content.headings.contains(heading), "missing section \(heading)")
        }
    }

    @Test func thePrivacyPolicyNamesEveryRecipient() throws {
        let text = try LegalDocument.privacyPolicy.load().plainText
        for recipient in ["Resend", "PostHog", "Mapbox", "RevenueCat", "OVH"] {
            #expect(text.contains(recipient), "missing recipient \(recipient)")
        }
    }

    @Test(arguments: LegalDocument.allCases)
    func eachDocumentIsMarkedAsADraftWithAContactPlaceholder(document: LegalDocument) throws {
        let content = try document.load()
        guard case .paragraph(let first)? = content.blocks.dropFirst().first else {
            Issue.record("the draft notice must follow the title")
            return
        }
        #expect(first.contains("Brouillon, à faire relire avant publication"))
        #expect(content.plainText.contains("[adresse de contact à compléter]"))
    }

    @Test func markdownIsSplitIntoHeadingsParagraphsAndBullets() {
        let content = LegalContent(markdown: """
        # Titre

        Premier paragraphe
        sur deux lignes.

        ## Section

        - un
        - **deux**
        """)
        #expect(content.blocks == [
            .heading(level: 1, text: "Titre"),
            .paragraph("Premier paragraphe sur deux lignes."),
            .heading(level: 2, text: "Section"),
            .bullet("un"),
            .bullet("**deux**"),
        ])
    }
}
