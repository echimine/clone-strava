#if DEBUG
import SwiftUI

// PROTOTYPE — throwaway (see OnboardingPrototype.swift).

// MARK: - B « 3 étapes »: grouped native forms (Vous / Vos sports / Vos objectifs)

struct ProtoVariantB: View {
    @Bindable var answers: ProtoAnswers
    let finish: () -> Void
    @State private var page = 0
    @State private var birth = protoDefaultBirthDate

    private let titles = ["Vous", "Vos sports", "Vos objectifs"]

    var body: some View {
        NavigationStack {
            Form {
                switch page {
                case 0: aboutYou
                case 1: sportsAndLevel
                default: goals
                }
            }
            .navigationTitle(titles[page])
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if page > 0 { Button("Retour") { page -= 1 } }
                }
                ToolbarItem(placement: .principal) {
                    Text("Étape \(page + 1) sur 3").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                ProtoPrimaryButton(title: page == 2 ? "Terminer" : "Continuer", isEnabled: canContinue) {
                    if page < 2 { page += 1 } else { finish() }
                }
                .padding(.horizontal, Theme.spacing).padding(.bottom, 8)
            }
        }
        .onAppear { if answers.birthDate == nil { answers.birthDate = birth } }
    }

    private var canContinue: Bool {
        switch page {
        case 0: answers.nameIsValid && answers.birthIsValid && answers.gender != nil
        case 1: !answers.sports.isEmpty && answers.level != nil
        default: true
        }
    }

    @ViewBuilder private var aboutYou: some View {
        Section {
            TextField("Prénom", text: $answers.firstName).textContentType(.givenName)
            TextField("Nom", text: $answers.lastName).textContentType(.familyName)
        } header: { Text(ProtoCopy.nameSubtitle) } footer: { Text(ProtoCopy.nameFootnote) }
        Section {
            DatePicker("Date de naissance", selection: Binding(
                get: { answers.birthDate ?? birth }, set: { answers.birthDate = $0 }
            ), in: ...Date.now, displayedComponents: .date)
            Picker("Genre", selection: $answers.gender) {
                Text("Choisir").tag(ProtoGender?.none)
                ForEach(ProtoGender.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
        } header: {
            Text("Pour vos performances et les classements")
        } footer: {
            if answers.isTooYoung {
                Text(ProtoCopy.tooYoung).foregroundStyle(.red)
            } else {
                Text("Ni votre âge ni votre genre n'apparaissent sur votre profil.")
            }
        }
    }

    @ViewBuilder private var sportsAndLevel: some View {
        Section(ProtoCopy.sportsTitle) {
            ForEach(protoSports, id: \.self) { sport in
                Button { answers.toggle(sport) } label: {
                    HStack {
                        Label(ActivityFormatters.sportLabel(sport), systemImage: ActivityFormatters.sportSymbol(sport))
                        Spacer()
                        if answers.sports.contains(sport) { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        Section {
            Picker("Niveau", selection: $answers.level) {
                ForEach(ProtoLevel.allCases) { Text($0.rawValue).tag(Optional($0)) }
            }
            .pickerStyle(.segmented)
        } header: { Text(ProtoCopy.levelTitle) } footer: {
            Text(answers.level?.detail ?? ProtoCopy.levelSubtitle)
        }
    }

    @ViewBuilder private var goals: some View {
        Section {
            ForEach(ProtoGoal.allCases) { goal in
                Toggle(goal.rawValue, isOn: Binding(get: { answers.goals.contains(goal) }, set: { _ in answers.toggle(goal) }))
            }
        } header: { Text(ProtoCopy.goalsTitle) } footer: { Text("Facultatif. " + ProtoCopy.goalsSubtitle) }
    }
}

// MARK: - C « Conversation »: one scrolling thread, answered questions collapse into bubbles

struct ProtoVariantC: View {
    enum Question: Int, CaseIterable { case name, birth, gender, sports, goals, level, done }

    @Bindable var answers: ProtoAnswers
    let finish: () -> Void
    @State private var current = Question.name
    @State private var birth = protoDefaultBirthDate

    var body: some View {
        VStack(spacing: 0) {
            ProgressView(value: Double(current.rawValue), total: Double(Question.allCases.count - 1))
                .tint(Theme.accent).padding(.horizontal, Theme.spacing).padding(.vertical, 8)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Question.allCases.filter { $0.rawValue <= current.rawValue }, id: \.self) { question in
                            turn(question).id(question)
                        }
                    }
                    .padding(Theme.spacing)
                }
                .onChange(of: current) { _, new in withAnimation { proxy.scrollTo(new, anchor: .top) } }
            }
        }
        .animation(.snappy, value: current)
    }

    private func advance(from question: Question) {
        if question == current, let next = Question(rawValue: question.rawValue + 1) { current = next }
    }

    @ViewBuilder private func turn(_ question: Question) -> some View {
        let isOpen = question == current
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                NervoMark().stroke(Theme.accent, style: NervoMark.strokeStyle(forSide: 28)).frame(width: 28, height: 28)
                Text(prompt(question)).font(isOpen ? .title3.bold() : .subheadline).foregroundStyle(isOpen ? .primary : .secondary)
            }
            if isOpen {
                input(question).padding(.leading, 38)
            } else if let answer = answerText(question) {
                Button { current = question } label: {
                    Text(answer).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Capsule().fill(Theme.accent))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    private func prompt(_ question: Question) -> String {
        switch question {
        case .name: "Bienvenue sur Nervo ! \(ProtoCopy.nameTitle)"
        case .birth: "Enchanté, \(answers.firstName). \(ProtoCopy.birthTitle) \(ProtoCopy.birthSubtitle)"
        case .gender: "\(ProtoCopy.genderTitle) \(ProtoCopy.genderSubtitle)"
        case .sports: ProtoCopy.sportsTitle
        case .goals: "\(ProtoCopy.goalsTitle) (facultatif)"
        case .level: ProtoCopy.levelTitle
        case .done: "Merci ! Créons maintenant votre compte pour garder tout ça."
        }
    }

    private func answerText(_ question: Question) -> String? {
        switch question {
        case .name: "\(answers.firstName) \(answers.lastName)"
        case .birth: answers.age.map { "\($0) ans" }
        case .gender: answers.gender?.rawValue
        case .sports: answers.sports.map(ActivityFormatters.sportLabel).joined(separator: ", ")
        case .goals: answers.goals.isEmpty ? "Aucun pour l'instant" : "\(answers.goals.count) objectif(s)"
        case .level: answers.level?.rawValue
        case .done: nil
        }
    }

    @ViewBuilder private func input(_ question: Question) -> some View {
        switch question {
        case .name:
            VStack(spacing: 10) {
                TextField("Prénom", text: $answers.firstName).textContentType(.givenName).textFieldStyle(.roundedBorder)
                TextField("Nom", text: $answers.lastName).textContentType(.familyName).textFieldStyle(.roundedBorder)
                Text(ProtoCopy.nameFootnote).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                ProtoPrimaryButton(title: "Valider", isEnabled: answers.nameIsValid) { advance(from: .name) }
            }
        case .birth:
            VStack(spacing: 6) {
                DatePicker("", selection: $birth, in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.wheel).labelsHidden()
                    .onChange(of: birth, initial: true) { _, new in answers.birthDate = new }
                Text(answers.isTooYoung ? ProtoCopy.tooYoung : ProtoCopy.birthFootnote)
                    .font(.caption).foregroundStyle(answers.isTooYoung ? .red : .secondary)
                ProtoPrimaryButton(title: "Valider", isEnabled: answers.birthIsValid) { advance(from: .birth) }
            }
        case .gender:
            VStack(spacing: 8) {
                ForEach(ProtoGender.allCases) { gender in
                    ProtoChoiceRow(title: gender.rawValue, isSelected: answers.gender == gender) {
                        answers.gender = gender
                        advance(from: .gender)
                    }
                }
            }
        case .sports:
            VStack(spacing: 10) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(protoSports, id: \.self) { sport in
                        ProtoSportTile(sport: sport, isSelected: answers.sports.contains(sport)) { answers.toggle(sport) }
                    }
                }
                ProtoPrimaryButton(title: "Valider", isEnabled: !answers.sports.isEmpty) { advance(from: .sports) }
            }
        case .goals:
            VStack(spacing: 8) {
                ForEach(ProtoGoal.allCases) { goal in
                    ProtoChoiceRow(title: goal.rawValue, isSelected: answers.goals.contains(goal)) { answers.toggle(goal) }
                }
                ProtoPrimaryButton(title: answers.goals.isEmpty ? "Passer" : "Valider", isEnabled: true) { advance(from: .goals) }
            }
        case .level:
            VStack(spacing: 8) {
                ForEach(ProtoLevel.allCases) { level in
                    ProtoChoiceRow(title: level.rawValue, detail: level.detail, isSelected: answers.level == level) {
                        answers.level = level
                        advance(from: .level)
                    }
                }
            }
        case .done:
            ProtoPrimaryButton(title: "Créer mon compte", isEnabled: true, action: finish)
        }
    }
}
#endif
