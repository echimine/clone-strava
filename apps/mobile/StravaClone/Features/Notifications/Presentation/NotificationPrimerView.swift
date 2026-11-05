import SwiftUI

/// Nervo's notification priming screen (ADR-035 §7), after the Paywall of the Onboarding path:
/// a fake iOS banner of what a notification looks like, "Ne manquez rien", then "Activer les
/// notifications" (iOS's prompt) or "Plus tard" (home, without spending it).
struct NotificationPrimerView: View {
    let isRequesting: Bool
    let enable: () -> Void
    let later: () -> Void

    @State private var isBannerShown = false

    var body: some View {
        VStack(spacing: 0) {
            NotificationBannerSample()
                .padding(.horizontal, Theme.spacing)
                .padding(.top, 24)
                .offset(y: isBannerShown ? 0 : -140)
                .opacity(isBannerShown ? 1 : 0)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Exemple de notification")

            Spacer(minLength: 24)

            VStack(spacing: 28) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.accent, .primary)
                    .accessibilityHidden(true)
                Text("Ne manquez rien")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 18) {
                    reason("Kudos et commentaires sur vos activités", systemImage: "hand.thumbsup.fill")
                    reason("Un rappel avant la fin de votre essai gratuit", systemImage: "calendar.badge.clock")
                }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button("Activer les notifications", action: enable)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(isRequesting)
                    .accessibilityIdentifier("notificationPrimer.enable")
                Button("Plus tard", action: later)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .disabled(isRequesting)
                    .accessibilityIdentifier("notificationPrimer.later")
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear { AccessibilityNotification.ScreenChanged(nil).post() }
        .task {
            withAnimation(.spring(duration: 0.6, bounce: 0.25).delay(0.3)) { isBannerShown = true }
        }
    }

    private func reason(_ text: String, systemImage: String) -> some View {
        Label {
            Text(text)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
        }
    }
}

/// A notification as iOS shows it on the lock screen, drawn by hand: what "Activer" brings.
private struct NotificationBannerSample: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NervoMark()
                .stroke(.white, style: NervoMark.strokeStyle(forSide: 22))
                .frame(width: 22, height: 22)
                .padding(8)
                .background(Theme.accent, in: .rect(cornerRadius: 9))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Nervo").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("maintenant").font(.caption).foregroundStyle(.secondary)
                }
                Text("Léa a donné un kudos à votre Sortie du matin")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 6)
    }
}

#Preview {
    NotificationPrimerView(isRequesting: false, enable: {}, later: {})
}
