import SwiftUI

/// The two greys of "Modifier le profil": the band behind the photo and section titles, and the
/// rows.
enum EditProfileColors {
    static let band = Color(.systemGroupedBackground)
    static let cell = Color(.secondarySystemGroupedBackground)
}

/// Dates and weights as the sheet shows them, in French.
enum EditProfileFormat {
    private static let french = Locale(identifier: "fr_FR")

    /// "2 mai 2006".
    static func birthDate(_ day: CalendarDay) -> String {
        day.date().formatted(.dateTime.day().month(.wide).year().locale(french))
    }

    /// "59" or "59,5".
    static func weight(_ kilograms: Double) -> String {
        kilograms.formatted(.number.precision(.fractionLength(0...1)).locale(french))
    }

    /// `.some(nil)` for an empty field, nil for something that is not a number.
    static func weightKg(from text: String) -> Double?? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .some(nil) }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return .some(value)
    }

    /// The country's French name in capitals, as Strava shows it: "FRANCE".
    static func country(_ code: String) -> String {
        (french.localizedString(forRegionCode: code) ?? code).uppercased(with: french)
    }
}

/// My photo with its orange ring, which opens the photo menu, next to first and last name.
struct EditProfileIdentity: View {
    let store: ProfileStore
    @Binding var firstName: String
    @Binding var lastName: String
    let changePhoto: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.spacing) {
            Button(action: changePhoto) {
                EditableAvatar(
                    name: store.profile?.athlete.displayName ?? "",
                    url: store.profile?.athlete.avatarURL,
                    editor: store.avatar,
                    size: 58
                )
                .padding(3)
                .overlay(Circle().stroke(Theme.accent, lineWidth: 1.5))
            }
            .disabled(store.avatar.isBusy)
            .accessibilityLabel(AvatarMessages.changePhoto)
            .accessibilityIdentifier("editProfile.changePhoto")
            VStack(spacing: 0) {
                TextField(ProfileMessages.firstName, text: $firstName)
                    .textContentType(.givenName)
                    .accessibilityIdentifier("editProfile.firstName")
                    .padding(.horizontal, 10)
                    .frame(height: 60)
                Divider()
                TextField(ProfileMessages.lastName, text: $lastName)
                    .textContentType(.familyName)
                    .accessibilityIdentifier("editProfile.lastName")
                    .padding(.horizontal, 10)
                    .frame(height: 60)
            }
            .background(EditProfileColors.cell)
        }
        .padding(Theme.spacing)
    }
}

/// A row's height and margins.
private struct EditProfileRowLayout: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Theme.spacing)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .contentShape(Rectangle())
    }
}

private extension View {
    func editProfileRow() -> some View { modifier(EditProfileRowLayout()) }
}

/// "Label ............ value": Sport principal, birth date, Sexe.
private struct EditProfileValueLabel: View {
    let title: String
    let value: String?

    var body: some View {
        HStack(spacing: 12) {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(value ?? ProfileMessages.notSet)
                .foregroundStyle(value == nil ? .secondary : .primary)
                .multilineTextAlignment(.trailing)
        }
        .editProfileRow()
    }
}

/// Bio and Ville: the placeholder is the label, the text is cut at `maxLength`.
struct EditProfileTextRow: View {
    let placeholder: String
    @Binding var text: String
    let maxLength: Int
    var axis: Axis = .horizontal

    var body: some View {
        TextField(placeholder, text: $text, axis: axis)
            .lineLimit(axis == .vertical ? 1...6 : 1...1)
            .onChange(of: text) { _, new in
                if new.count > maxLength { text = String(new.prefix(maxLength)) }
            }
            .editProfileRow()
    }
}

/// Pays: "FRANCE", or the placeholder; opens the country list.
struct EditProfileCountryRow: View {
    @Binding var countryCode: String?

    var body: some View {
        NavigationLink {
            CountryPickerView(selection: $countryCode)
        } label: {
            Text(countryCode.map(EditProfileFormat.country) ?? ProfileMessages.country)
                .foregroundStyle(countryCode == nil ? .tertiary : .primary)
                .editProfileRow()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editProfile.country")
    }
}

struct EditProfileSportRow: View {
    @Binding var sport: SportType?

    var body: some View {
        Menu {
            Picker(ProfileMessages.mainSport, selection: $sport) {
                ForEach(SportType.active, id: \.self) { sport in
                    Label(ActivityFormatters.sportLabel(sport), systemImage: ActivityFormatters.sportSymbol(sport))
                        .tag(Optional(sport))
                }
            }
        } label: {
            EditProfileValueLabel(title: ProfileMessages.mainSport, value: sport.map(ActivityFormatters.sportLabel))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editProfile.mainSport")
    }
}

/// "INFORMATIONS SUR L'ATHLÈTE" on the grey band.
struct EditProfileSectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased(with: Locale(identifier: "fr_FR")))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.spacing)
            .padding(.top, 28)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The date opens a wheel under the row; no one under 15 (ADR-035 §5).
struct EditProfileBirthDateRow: View {
    @Binding var birthDate: CalendarDay?
    @State private var isPicking = false

    private var latest: Date {
        Calendar.current.date(byAdding: .year, value: -OnboardingAnswers.minimumAge, to: .now) ?? .now
    }

    private var earliest: Date {
        CalendarDay(year: 1900, month: 1, day: 1).date()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { isPicking.toggle() }
            } label: {
                EditProfileValueLabel(title: ProfileMessages.birthDate, value: birthDate.map(EditProfileFormat.birthDate))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("editProfile.birthDate")
            if isPicking {
                DatePicker(
                    ProfileMessages.birthDate,
                    selection: Binding(
                        get: { birthDate?.date() ?? latest },
                        set: { birthDate = CalendarDay($0) }
                    ),
                    in: earliest...latest,
                    displayedComponents: .date
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: "fr_FR"))
                .frame(maxWidth: .infinity)
            }
        }
    }
}

struct EditProfileGenderRow: View {
    @Binding var gender: Gender?

    var body: some View {
        Menu {
            Picker(ProfileMessages.gender, selection: $gender) {
                ForEach(Gender.allCases, id: \.self) { gender in
                    Text(ProfileMessages.gender(gender)).tag(Optional(gender))
                }
            }
        } label: {
            EditProfileValueLabel(title: ProfileMessages.gender, value: gender.map(ProfileMessages.gender))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("editProfile.gender")
    }
}

struct EditProfileWeightRow: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Text(ProfileMessages.weight)
            Spacer(minLength: 8)
            TextField("", text: $text, prompt: Text("–"))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .accessibilityLabel(ProfileMessages.weight)
                .accessibilityIdentifier("editProfile.weight")
        }
        .editProfileRow()
    }
}
