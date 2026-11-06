import Foundation

/// A source of the app's data, credited in Réglages › « Sources des données » (ADR-039 §10):
/// OpenStreetMap (ODbL, the open file of the Segments), Copernicus (its two mandatory notices),
/// IGN and Mapbox.
struct DataSource: Identifiable, Equatable, Sendable {
    struct Link: Equatable, Sendable {
        let title: String
        let url: URL
    }

    let name: String
    /// What it gives the app, then the notices it requires, word for word.
    let notices: [String]
    let links: [Link]

    var id: String { name }

    /// `apiBaseURL` serves the open file of every Segment (`GET /v1/open-data/segments.ndjson.gz`).
    static func all(apiBaseURL: URL) -> [DataSource] {
        [
            DataSource(
                name: "OpenStreetMap",
                notices: [
                    "Les routes, les chemins et les noms des Segments créés par Nervo viennent d'OpenStreetMap.",
                    "© les contributeurs d'OpenStreetMap. Données disponibles sous la licence Open Database License (ODbL).",
                    "Tous les Segments sont offerts sous ODbL, sans leurs créateurs ni les Efforts.",
                ],
                links: [
                    Link(title: "openstreetmap.org/copyright", url: URL(string: "https://www.openstreetmap.org/copyright")!),
                    Link(title: "Licence ODbL", url: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!),
                    Link(
                        title: "Télécharger les Segments (ODbL)",
                        url: apiBaseURL.appending(path: "v1/open-data/segments.ndjson.gz")
                    ),
                ]
            ),
            DataSource(
                name: "Copernicus",
                notices: [
                    "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved",
                    "The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30",
                ],
                links: []
            ),
            DataSource(
                name: "IGN",
                notices: [
                    "Altitudes en France : RGE ALTI® de l'IGN, sous Licence Ouverte Etalab 2.0.",
                ],
                links: [
                    Link(title: "Licence Ouverte Etalab 2.0", url: URL(string: "https://www.etalab.gouv.fr/licence-ouverte-open-licence/")!),
                ]
            ),
            DataSource(
                name: "Mapbox",
                notices: [
                    "Fonds de carte et itinéraires : © Mapbox, © les contributeurs d'OpenStreetMap.",
                ],
                links: [
                    Link(title: "mapbox.com/about/maps", url: URL(string: "https://www.mapbox.com/about/maps/")!),
                ]
            ),
        ]
    }
}
