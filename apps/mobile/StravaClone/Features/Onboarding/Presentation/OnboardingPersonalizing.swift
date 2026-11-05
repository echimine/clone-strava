import SwiftUI

/// The personalised loading at the end of the Onboarding (ADR-035 §1), purely visual (~4 s): on
/// the Nervo orange, the N draws itself inside a progress ring while 4 lines built from the
/// answers tick, then "Tout est prêt, <Prénom> !" and the white "Créer mon compte".
struct OnboardingPersonalizing: View {
    let answers: OnboardingAnswers
    let firstName: String
    let createAccount: () -> Void

    @State private var markDrawn: CGFloat = 0
    @State private var ring: CGFloat = 0
    @State private var checked = 0
    @State private var isReady = false
    @State private var breathes = false

    private var lines: [String] {
        let sports = answers.sports.map(ActivityFormatters.sportLabel)
        // "le vélo", but "la course, la natation, la marche, la randonnée".
        let feminine = !answers.sports.contains(.ride)
        let sportLine = switch sports.count {
        case 0: "Vos sports ajoutés"
        case 1: "\(sports[0]) ajouté\(feminine ? "e" : "") à vos sports"
        default: "\(sports.dropLast().joined(separator: ", ")) et \(sports[sports.count - 1]) ajouté\(feminine ? "e" : "")s"
        }
        let goals = answers.goals.count
        return [
            firstName.isEmpty ? "Profil préparé" : "Profil de \(firstName) préparé",
            sportLine,
            "Classements adaptés au niveau \((answers.level ?? .beginner).label.lowercased())",
            goals == 0 ? "Fil d'actualité prêt" : "Vos \(goals) objectif\(goals > 1 ? "s" : "") enregistré\(goals > 1 ? "s" : "")",
        ]
    }

    var body: some View {
        ZStack {
            Theme.accent.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 6)
                    Circle()
                        .trim(from: 0, to: ring)
                        .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    NervoMark()
                        .trim(from: 0, to: markDrawn)
                        .stroke(.white, style: NervoMark.strokeStyle(forSide: 96))
                        .frame(width: 96, height: 96)
                }
                .frame(width: 150, height: 150)
                .scaleEffect(isReady && breathes ? 1.06 : 1)
                .accessibilityHidden(true)

                Text(title)
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .padding(.top, 36)
                    .accessibilityAddTraits(.isHeader)

                checklist
                    .padding(.top, 28)
                    .frame(maxWidth: 320, alignment: .leading)

                Spacer()

                ZStack {
                    if isReady {
                        createAccountButton
                            .transition(.opacity.combined(with: .offset(y: 30)))
                    }
                }
                // The room is kept, so nothing moves when the button arrives.
                .frame(minHeight: 100, alignment: .bottom)
                .padding(.bottom, 10)
            }
            .padding(.horizontal, Theme.spacing)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: checked)
        .sensoryFeedback(.success, trigger: isReady)
        .task { await play() }
        .onChange(of: isReady) { _, ready in
            if ready { AccessibilityNotification.Announcement(title).post() }
        }
    }

    private var createAccountButton: some View {
        VStack(spacing: 10) {
            Button(action: createAccount) {
                Text("Créer mon compte")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Capsule().fill(.white))
                    .contentShape(Capsule())
            }
            .buttonStyle(OnboardingPressStyle())
            .accessibilityIdentifier("onboarding.createAccount")
            Text("Pour garder vos réponses et retrouver vos activités partout.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
        }
    }

    private var title: String {
        guard isReady else { return "On prépare votre Nervo…" }
        return firstName.isEmpty ? "Tout est prêt !" : "Tout est prêt, \(firstName) !"
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(lines.indices, id: \.self) { index in
                HStack(spacing: 12) {
                    ZStack {
                        Circle().stroke(.white.opacity(0.4), lineWidth: 2)
                        if index < checked {
                            Circle().fill(.white)
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.heavy))
                                .foregroundStyle(Theme.accent)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
                    Text(lines[index])
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .opacity(index < checked ? 1 : 0.55)
                        .accessibilityValue(index < checked ? "Terminé" : "En cours")
                }
            }
        }
    }

    private func play() async {
        withAnimation(.easeInOut(duration: 0.9)) { markDrawn = 1 }
        withAnimation(.easeInOut(duration: 3.6)) { ring = 1 }
        for index in 1 ... lines.count {
            try? await Task.sleep(for: .milliseconds(index == 1 ? 700 : 850))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.4, bounce: 0.4)) { checked = index }
        }
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        withAnimation(.spring(duration: 0.6, bounce: 0.3)) { isReady = true }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathes = true }
    }
}

#if DEBUG
#Preview {
    var answers = OnboardingAnswers()
    answers.sports = [.run, .ride]
    answers.goals = [.health]
    answers.level = .intermediate
    return OnboardingPersonalizing(answers: answers, firstName: "Camille") {}
}
#endif
