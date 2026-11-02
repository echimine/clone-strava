#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (see OnboardingPrototype.swift).
// A « Strava fidèle », retained: one question per screen, segmented progress, round back
// button, directional slide between screens, haptics on every choice.

struct ProtoVariantA: View {
    enum Step: Int, CaseIterable { case name, birth, gender, sports, goals, level }
    private enum Field { case first, last }

    @Bindable var answers: ProtoAnswers
    let finish: () -> Void
    @State private var step = Step.name
    @State private var forward = true
    @State private var showsWheel = false
    @State private var taps = 0
    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                page.id(step).transition(.asymmetric(
                    insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)
                ))
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            ProtoPrimaryButton(title: buttonTitle, isEnabled: canContinue, action: goForward)
                .padding(.horizontal, Theme.spacing).padding(.top, 8).padding(.bottom, 10)
        }
        .sensoryFeedback(.selection, trigger: taps)
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        .onAppear { focusFirstField() }
    }

    // MARK: Navigation

    private var header: some View {
        HStack(spacing: 14) {
            Button(action: goBack) {
                Image(systemName: "chevron.left").font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.secondarySystemBackground)))
            }
            .buttonStyle(ProtoPressStyle())
            .foregroundStyle(.primary)
            .opacity(step == .name ? 0 : 1)
            .disabled(step == .name)
            .accessibilityLabel("Retour")

            HStack(spacing: 5) {
                ForEach(Step.allCases, id: \.self) { item in
                    Capsule().fill(Color(.systemGray5)).frame(height: 4)
                        .overlay(alignment: .leading) {
                            Capsule().fill(Theme.accent).frame(maxWidth: item.rawValue <= step.rawValue ? .infinity : 0)
                        }
                }
            }
            .animation(.easeInOut(duration: 0.35), value: step)
            .accessibilityElement()
            .accessibilityLabel("Étape \(step.rawValue + 1) sur \(Step.allCases.count)")

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, Theme.spacing).padding(.vertical, 8)
    }

    private func goForward() {
        guard canContinue else { return }
        guard let next = Step(rawValue: step.rawValue + 1) else { return finish() }
        focus = nil
        showsWheel = false
        forward = true
        withAnimation(.snappy(duration: 0.35)) { step = next }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        focus = nil
        showsWheel = false
        forward = false
        withAnimation(.snappy(duration: 0.35)) { step = previous }
        if previous == .name { focusFirstField() }
    }

    private func focusFirstField() {
        guard step == .name else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            focus = answers.firstName.isEmpty ? .first : .last
        }
    }

    private var buttonTitle: String {
        step == .goals && answers.goals.isEmpty ? "Passer" : "Continuer"
    }

    private var canContinue: Bool {
        switch step {
        case .name: answers.nameIsValid
        case .birth: answers.birthIsValid
        case .gender: answers.gender != nil
        case .sports: !answers.sports.isEmpty
        case .goals: true
        case .level: answers.level != nil
        }
    }

    // MARK: Page

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 30, weight: .bold)).tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                content.padding(.top, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacing).padding(.top, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    private var title: String {
        switch step {
        case .name: ProtoCopy.nameTitle
        case .birth:
            answers.firstName.isEmpty ? ProtoCopy.birthTitle
                : "Bienvenue, \(answers.firstName.trimmingCharacters(in: .whitespaces)) ! \(ProtoCopy.birthTitle)"
        case .gender: ProtoCopy.genderTitle
        case .sports: ProtoCopy.sportsTitle
        case .goals: ProtoCopy.goalsTitle
        case .level: ProtoCopy.levelTitle
        }
    }

    private var subtitle: String {
        switch step {
        case .name: ProtoCopy.nameSubtitle
        case .birth: ProtoCopy.birthSubtitle
        case .gender: ProtoCopy.genderSubtitle
        case .sports: ProtoCopy.sportsSubtitle
        case .goals: ProtoCopy.goalsSubtitle
        case .level: ProtoCopy.levelSubtitle
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .name:
            VStack(alignment: .leading, spacing: 18) {
                ProtoTextField(label: "Prénom", text: $answers.firstName, isFocused: focus == .first)
                    .focused($focus, equals: .first)
                    .textContentType(.givenName).submitLabel(.next)
                    .onSubmit { focus = .last }
                ProtoTextField(label: "Nom", text: $answers.lastName, isFocused: focus == .last)
                    .focused($focus, equals: .last)
                    .textContentType(.familyName).submitLabel(.continue)
                    .onSubmit(goForward)
                ProtoNote(text: ProtoCopy.nameFootnote, systemImage: "eye")
            }
        case .birth:
            birthContent
        case .gender:
            VStack(spacing: 10) {
                ForEach(ProtoGender.allCases) { gender in
                    ProtoChoiceRow(title: gender.rawValue, isSelected: answers.gender == gender) {
                        answers.gender = gender
                        taps += 1
                    }
                }
                ProtoNote(text: ProtoCopy.genderFootnote, systemImage: "lock.fill").padding(.top, 6)
            }
        case .sports:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(protoSports, id: \.self) { sport in
                    ProtoSportTile(sport: sport, isSelected: answers.sports.contains(sport)) {
                        answers.toggle(sport)
                        taps += 1
                    }
                }
            }
        case .goals:
            VStack(spacing: 10) {
                ForEach(ProtoGoal.allCases) { goal in
                    ProtoChoiceRow(title: goal.rawValue, detail: goal.detail, revealsDetail: true,
                                   isSelected: answers.goals.contains(goal)) {
                        answers.toggle(goal)
                        taps += 1
                    }
                }
            }
        case .level:
            VStack(spacing: 10) {
                ForEach(ProtoLevel.allCases) { level in
                    ProtoChoiceRow(title: level.rawValue, detail: level.detail, isSelected: answers.level == level) {
                        answers.level = level
                        taps += 1
                    }
                }
            }
        }
    }

    private var birthContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date de naissance").font(.subheadline.weight(.semibold))
            Button {
                if answers.birthDate == nil { answers.birthDate = protoDefaultBirthDate }
                withAnimation(.snappy) { showsWheel.toggle() }
            } label: {
                HStack {
                    Text(answers.birthDate.map(Self.longDate) ?? "Choisir une date")
                        .foregroundStyle(answers.birthDate == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "calendar").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(showsWheel ? Color.primary : Color(.systemGray4), lineWidth: showsWheel ? 1.5 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showsWheel {
                DatePicker("", selection: Binding(
                    get: { answers.birthDate ?? protoDefaultBirthDate },
                    set: { answers.birthDate = $0 }
                ), in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden()
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .frame(maxWidth: .infinity)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            if answers.isTooYoung {
                Label(ProtoCopy.tooYoung, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(.red)
                    .transition(.opacity)
            }
            ProtoNote(text: ProtoCopy.birthFootnote, systemImage: "lock.fill")
        }
        .animation(.snappy, value: answers.isTooYoung)
    }

    private static func longDate(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR")))
    }
}

/// Label above, 54 pt field, darker border while focused (Strava's name fields).
private struct ProtoTextField: View {
    let label: String
    @Binding var text: String
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline.weight(.semibold))
            TextField("", text: $text)
                .autocorrectionDisabled()
                .padding(.horizontal, 16).frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemBackground)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isFocused ? Color.primary : Color(.systemGray4), lineWidth: isFocused ? 1.5 : 1))
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

/// Small grey reassurance line, with an icon saying who sees the data.
private struct ProtoNote: View {
    let text: String
    let systemImage: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: systemImage).imageScale(.small)
        }
        .font(.footnote).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
