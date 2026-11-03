import SwiftUI

/// "12 abonnés • 8 abonnements" on a profile's header (ADR-036 §3): each counter opens its
/// list (ADR-036 §1). Plain text when no list can be opened.
struct FollowCounters: View {
    /// "12 abonnés".
    let followers: String
    /// "8 abonnements".
    let following: String
    var open: ((AthleteFollowsRequest.List) -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            counter(followers, .followers)
            Text("•").accessibilityHidden(true)
            counter(following, .following)
        }
        .font(.subheadline)
        .monospacedDigit()
    }

    @ViewBuilder private func counter(_ label: String, _ list: AthleteFollowsRequest.List) -> some View {
        if let open {
            Button(label) { open(list) }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .accessibilityHint(Text("Ouvre la liste"))
                .accessibilityIdentifier(list == .followers ? "followCounters.followers" : "followCounters.following")
        } else {
            Text(label)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        FollowCounters(followers: "12 abonnés", following: "8 abonnements") { _ in }
        FollowCounters(followers: "1 abonné", following: "0 abonnement")
    }
    .padding()
}
