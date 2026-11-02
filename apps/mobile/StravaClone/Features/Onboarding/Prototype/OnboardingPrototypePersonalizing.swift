#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (see OnboardingPrototype.swift).
// End of the Onboarding: on the Nervo orange of the splash (ADR-032), the N draws itself inside a
// progress ring while lines built from the answers tick one by one; then « Tout est prêt » and
// the button to create the account.

struct ProtoPersonalizing: View {
    let answers: ProtoAnswers
    let createAccount: () -> Void

    @State private var markDrawn: CGFloat = 0
    @State private var ring: CGFloat = 0
    @State private var checked = 0
    @State private var ready = false
    @State private var breathe = false

    private var name: String { answers.firstName.trimmingCharacters(in: .whitespaces) }

    private var lines: [String] {
        let sports = answers.sports.map(ActivityFormatters.sportLabel)
        // « le vélo », but « la course, la natation, la marche, la randonnée ».
        let feminine = !answers.sports.contains(.ride)
        let sportLine = switch sports.count {
        case 0: "Vos sports ajoutés"
        case 1: "\(sports[0]) ajouté\(feminine ? "e" : "") à vos sports"
        default: "\(sports.dropLast().joined(separator: ", ")) et \(sports.last!) ajouté\(feminine ? "e" : "")s"
        }
        return [
            name.isEmpty ? "Profil préparé" : "Profil de \(name) préparé",
            sportLine,
            "Classements adaptés au niveau \((answers.level ?? .beginner).rawValue.lowercased())",
            answers.goals.isEmpty ? "Fil d'actualité prêt" : "Vos \(answers.goals.count) objectif\(answers.goals.count > 1 ? "s" : "") enregistré\(answers.goals.count > 1 ? "s" : "")",
        ]
    }

    var body: some View {
        ZStack {
            Theme.accent.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                ZStack {
                    Circle().stroke(.white.opacity(0.25), lineWidth: 6)
                    Circle().trim(from: 0, to: ring)
                        .stroke(.white, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    NervoMark().trim(from: 0, to: markDrawn)
                        .stroke(.white, style: NervoMark.strokeStyle(forSide: 96))
                        .frame(width: 96, height: 96)
                }
                .frame(width: 150, height: 150)
                .scaleEffect(ready ? (breathe ? 1.06 : 1) : 1)

                Text(ready ? (name.isEmpty ? "Tout est prêt !" : "Tout est prêt, \(name) !") : "On prépare votre Nervo…")
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .foregroundStyle(.white).multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .padding(.top, 36)

                VStack(alignment: .leading, spacing: 14) {
                    ForEach(lines.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            ZStack {
                                Circle().stroke(.white.opacity(0.4), lineWidth: 2)
                                if index < checked {
                                    Circle().fill(.white)
                                    Image(systemName: "checkmark").font(.caption.weight(.heavy)).foregroundStyle(Theme.accent)
                                        .transition(.scale.combined(with: .opacity))
                                }
                            }
                            .frame(width: 24, height: 24)
                            Text(lines[index]).font(.callout.weight(.medium)).foregroundStyle(.white)
                                .opacity(index < checked ? 1 : 0.55)
                        }
                    }
                }
                .padding(.top, 28)
                .frame(maxWidth: 320, alignment: .leading)

                Spacer()

                VStack(spacing: 10) {
                    Button(action: createAccount) {
                        Text("Créer mon compte").font(.headline).foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 54)
                            .background(Capsule().fill(.white))
                    }
                    .buttonStyle(ProtoPressStyle())
                    Text("Pour garder vos réponses et retrouver vos activités partout.")
                        .font(.footnote).foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, Theme.spacing).padding(.bottom, 10)
                .opacity(ready ? 1 : 0)
                .offset(y: ready ? 0 : 30)
            }
            .padding(.horizontal, Theme.spacing)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: checked)
        .sensoryFeedback(.success, trigger: ready)
        .task { await play() }
    }

    private func play() async {
        withAnimation(.easeInOut(duration: 0.9)) { markDrawn = 1 }
        withAnimation(.easeInOut(duration: 3.6)) { ring = 1 }
        for index in 1...lines.count {
            try? await Task.sleep(for: .milliseconds(index == 1 ? 700 : 850))
            withAnimation(.spring(duration: 0.4, bounce: 0.4)) { checked = index }
        }
        try? await Task.sleep(for: .milliseconds(500))
        withAnimation(.spring(duration: 0.6, bounce: 0.3)) { ready = true }
        withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathe = true }
    }
}

/// Stand-in for the next screen, owned by the ticket « Parcours de création de compte et de
/// connexion par code ».
struct ProtoAccountStub: View {
    let restart: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus").font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text("Création du compte").font(.title.bold())
            Text("Hors prototype : Google ou email + code, puis envoi des réponses d'onboarding.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Spacer()
            ProtoPrimaryButton(title: "Recommencer l'Onboarding", isEnabled: true, action: restart)
        }
        .padding(Theme.spacing)
    }
}
#endif
