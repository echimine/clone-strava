import SwiftUI

/// A country of "Modifier le profil"'s Pays: its ISO 3166-1 alpha-2 code and French name.
struct Country: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    var id: String { code }

    /// Every two-letter ISO region with a French name, in French alphabetical order.
    static let all: [Country] = {
        let french = Locale(identifier: "fr_FR")
        return Locale.Region.isoRegions
            .map(\.identifier)
            .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
            .compactMap { code in french.localizedString(forRegionCode: code).map { Country(code: code, name: $0) } }
            .sorted { $0.name.compare($1.name, options: [.caseInsensitive, .diacriticInsensitive], locale: french) == .orderedAscending }
    }()
}

/// Pays, pushed from the sheet: a searchable list; "Aucun" clears the country.
struct CountryPickerView: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var countries: [Country] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Country.all }
        return Country.all.filter { $0.name.localizedStandardContains(trimmed) }
    }

    var body: some View {
        List {
            if query.isEmpty {
                row(ProfileMessages.noCountry, code: nil)
            }
            ForEach(countries) { country in
                row(country.name, code: country.code)
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: ProfileMessages.searchCountry)
        .navigationTitle(ProfileMessages.country)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
    }

    private func row(_ name: String, code: String?) -> some View {
        Button {
            selection = code
            dismiss()
        } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if selection == code {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
