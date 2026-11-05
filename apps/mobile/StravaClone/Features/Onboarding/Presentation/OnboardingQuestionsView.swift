import SwiftUI

/// The six questions (ADR-035 §1, prototype variant A): a round back button (on the first
/// screen, only when there is a Welcome to go back to) and a 6-segment progress bar on top, one question per page sliding in its direction,
/// and the orange button at the bottom, pale while the page is not valid.
struct OnboardingQuestionsView: View {
    @Bindable var store: OnboardingStore
    let isForward: Bool
    /// Whether the round back button shows: `store.canGoBack`, or a way out of the first screen.
    let canGoBack: Bool
    let next: () -> Void
    let back: () -> Void

    private enum Field { case firstName, lastName }

    @FocusState private var focus: Field?
    @State private var showsWheel = false
    /// Bumped on each choice, for its haptic.
    @State private var choices = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                page
                    .id(store.step)
                    .transition(.slide(forward: isForward))
            }
            .frame(maxHeight: .infinity, alignment: .top)
            .clipped()
            .animation(.snappy(duration: 0.35), value: store.step)

            Button(store.continueTitle, action: goForward)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!store.canContinue)
                .animation(.easeOut(duration: 0.2), value: store.canContinue)
                .accessibilityIdentifier("onboarding.continue")
                .padding(.horizontal, Theme.spacing)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .sensoryFeedback(.selection, trigger: choices)
        .onAppear(perform: focusName)
        .onChange(of: store.step) { _, step in
            if step == .name { focusName() }
            AccessibilityNotification.LayoutChanged(nil).post()
        }
    }

    // MARK: Navigation

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                if canGoBack {
                    Button(action: goBack) {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(OnboardingPressStyle())
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Retour")
                    .accessibilityIdentifier("onboarding.back")
                    .transition(.opacity)
                }
            }
            .frame(width: 36, height: 36)
            .animation(.easeOut(duration: 0.2), value: canGoBack)

            progressBar

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 8)
    }

    private var progressBar: some View {
        let index = OnboardingStep.questions.firstIndex(of: store.step) ?? 0
        return HStack(spacing: 5) {
            ForEach(OnboardingStep.questions.indices, id: \.self) { item in
                Capsule()
                    .fill(Color(.systemGray5))
                    .frame(height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(maxWidth: item <= index ? .infinity : 0)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.35), value: index)
        .accessibilityElement()
        .accessibilityLabel("Progression")
        .accessibilityValue("Étape \(index + 1) sur \(OnboardingStep.questions.count)")
    }

    private func goForward() {
        guard store.canContinue else { return }
        focus = nil
        showsWheel = false
        next()
    }

    private func goBack() {
        focus = nil
        showsWheel = false
        back()
    }

    /// The cursor lands in the first name (the last name once it is filled) after the slide.
    private func focusName() {
        guard store.step == .name else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            focus = store.firstName.isEmpty ? .firstName : .lastName
        }
    }

    private func choose(_ action: () -> Void) {
        action()
        choices += 1
    }

    // MARK: Page

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(store.step.title(firstName: store.firstName))
                    .font(.system(size: 30, weight: .bold))
                    .tracking(-0.4)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = store.step.subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }
                content
                    .padding(.top, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacing)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder private var content: some View {
        switch store.step {
        case .name: nameContent
        case .birthDate: birthDateContent
        case .gender:
            VStack(spacing: 10) {
                ForEach(Gender.allCases, id: \.self) { gender in
                    OnboardingChoiceRow(title: gender.label, isSelected: store.answers.gender == gender) {
                        choose { store.answers.gender = gender }
                    }
                    .accessibilityIdentifier("onboarding.gender.\(gender.rawValue)")
                }
                OnboardingNote(text: OnboardingCopy.genderMention, systemImage: "lock.fill")
                    .padding(.top, 6)
            }
        case .sports:
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(store.sportChoices, id: \.self) { sport in
                    OnboardingSportTile(sport: sport, isSelected: store.answers.sports.contains(sport)) {
                        choose { store.toggle(sport) }
                    }
                    .accessibilityIdentifier("onboarding.sport.\(sport.code)")
                }
            }
        case .goals:
            VStack(spacing: 10) {
                ForEach(Goal.allCases, id: \.self) { goal in
                    OnboardingChoiceRow(
                        title: goal.label,
                        detail: goal.detail,
                        revealsDetail: true,
                        isSelected: store.answers.goals.contains(goal)
                    ) {
                        choose { store.toggle(goal) }
                    }
                    .accessibilityIdentifier("onboarding.goal.\(goal.rawValue)")
                }
            }
        case .level:
            VStack(spacing: 10) {
                ForEach(AthleteLevel.allCases, id: \.self) { level in
                    OnboardingChoiceRow(title: level.label, detail: level.detail, isSelected: store.answers.level == level) {
                        choose { store.answers.level = level }
                    }
                    .accessibilityIdentifier("onboarding.level.\(level.rawValue)")
                }
            }
        case .showcase, .personalizing, .account:
            EmptyView()
        }
    }

    private var nameContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            OnboardingTextField(label: "Prénom", text: $store.answers.firstName, isFocused: focus == .firstName, identifier: "onboarding.firstName")
                .focused($focus, equals: .firstName)
                .textContentType(.givenName)
                .submitLabel(.next)
                .onSubmit { focus = .lastName }
            OnboardingTextField(label: "Nom", text: $store.answers.lastName, isFocused: focus == .lastName, identifier: "onboarding.lastName")
                .focused($focus, equals: .lastName)
                .textContentType(.familyName)
                .submitLabel(.continue)
                .onSubmit(goForward)
            OnboardingNote(text: OnboardingCopy.nameMention, systemImage: "eye")
        }
    }

    private var birthDateContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Date de naissance")
                .font(.subheadline.weight(.semibold))
            Button {
                store.unfoldBirthDateWheel()
                withAnimation(.snappy) { showsWheel.toggle() }
            } label: {
                HStack {
                    Text(store.answers.birthDate.map(Self.longDate) ?? "Choisir une date")
                        .foregroundStyle(store.answers.birthDate == nil ? .secondary : .primary)
                    Spacer()
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.systemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(showsWheel ? Color.primary : Color(.systemGray4), lineWidth: showsWheel ? 1.5 : 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Date de naissance")
            .accessibilityValue(store.answers.birthDate.map(Self.longDate) ?? "Aucune")
            .accessibilityHint(showsWheel ? "Referme le sélecteur de date" : "Ouvre le sélecteur de date")
            .accessibilityIdentifier("onboarding.birthDate")

            if showsWheel {
                DatePicker("Date de naissance", selection: birthDate, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "fr_FR"))
                    .frame(maxWidth: .infinity)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .accessibilityIdentifier("onboarding.birthDateWheel")
            }

            if store.isTooYoung {
                Label(OnboardingCopy.tooYoung, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .transition(.opacity)
                    .accessibilityIdentifier("onboarding.tooYoung")
                    .onAppear { AccessibilityNotification.Announcement(OnboardingCopy.tooYoung).post() }
            }
            OnboardingNote(text: OnboardingCopy.birthDateMention, systemImage: "lock.fill")
        }
        .animation(.snappy, value: store.isTooYoung)
    }

    private var birthDate: Binding<Date> {
        Binding(
            get: { store.answers.birthDate?.date() ?? .now },
            set: { store.answers.birthDate = CalendarDay($0) }
        )
    }

    private static func longDate(_ day: CalendarDay) -> String {
        day.date().formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "fr_FR")))
    }
}
