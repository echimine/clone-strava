import SwiftUI

/// Opens an athlete's profile from wherever an athlete is shown (ADR-036 §10): a card's or a
/// detail's author, a row of the Kudos and comments lists. The app shell sets one per tab's
/// `NavigationStack`, so the profile is pushed in that stack, or the Profile tab opens for the
/// viewer themself (ADR-007 rule 5: features never open each other's screens).
struct OpenAthleteAction {
    let action: @MainActor (String) -> Void

    @MainActor func callAsFunction(_ athleteId: String) {
        action(athleteId)
    }
}

extension EnvironmentValues {
    /// Nil where no profile can be opened (previews): athletes are then not tappable.
    @Entry var openAthlete: OpenAthleteAction?
}

/// An athlete's avatar or name that opens their profile; a plain label where none can be opened.
struct AthleteButton<Label: View>: View {
    let athlete: ActivityAuthor
    @ViewBuilder let label: () -> Label

    @Environment(\.openAthlete) private var openAthlete

    var body: some View {
        if let openAthlete {
            Button { openAthlete(athlete.id) } label: { label() }
                .buttonStyle(.plain)
                .accessibilityLabel(athlete.displayName)
                .accessibilityHint(Text("Ouvre le profil"))
        } else {
            label()
        }
    }
}
