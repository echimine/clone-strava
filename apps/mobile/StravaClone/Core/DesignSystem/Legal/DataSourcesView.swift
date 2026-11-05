import SwiftUI

/// Réglages › « Sources des données » (ADR-039 §10): one section per source, its notices then
/// its links. Built by the app shell, which knows the API's address (ADR-007 rule 5).
struct DataSourcesView: View {
    let sources: [DataSource]

    var body: some View {
        List {
            ForEach(sources) { source in
                Section(source.name) {
                    ForEach(source.notices, id: \.self) { notice in
                        Text(notice)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(source.links, id: \.url) { link in
                        Link(destination: link.url) {
                            Label(link.title, systemImage: "arrow.up.right.square")
                        }
                        .accessibilityIdentifier("dataSources.link.\(link.url.absoluteString)")
                    }
                }
                .accessibilityIdentifier("dataSources.\(source.name)")
            }
        }
        .navigationTitle(DataSourcesView.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    static let title = "Sources des données"
}

#Preview {
    NavigationStack {
        DataSourcesView(sources: DataSource.all(apiBaseURL: URL(string: "https://api.example.com")!))
    }
}
