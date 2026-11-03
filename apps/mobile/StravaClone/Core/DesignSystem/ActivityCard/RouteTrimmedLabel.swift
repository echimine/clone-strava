import SwiftUI

/// "Départ et arrivée masqués" on a map whose route the privacy zone trimmed (ADR-036 §5, §9).
struct RouteTrimmedLabel: View {
    var body: some View {
        Label(ActivityCardMessages.routeTrimmed, systemImage: "eye.slash")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassBackground(in: .capsule)
    }
}
