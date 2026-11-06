import Foundation
import Testing
@testable import StravaClone

/// « Sources des données » in Réglages (ADR-039 §10): OpenStreetMap under ODbL with its copyright
/// page and the open file of the Segments, Copernicus with its two mandatory notices, IGN, Mapbox.
struct DataSourcesTests {
    private let api = URL(string: "https://api.nervo.test")!

    @Test func listsTheFourSourcesInOrder() {
        #expect(DataSource.all(apiBaseURL: api).map(\.name) == ["OpenStreetMap", "Copernicus", "IGN", "Mapbox"])
    }

    @Test func creditsOpenStreetMapUnderODbLWithItsCopyrightPageAndTheOpenFile() throws {
        let osm = try #require(DataSource.all(apiBaseURL: api).first { $0.name == "OpenStreetMap" })

        #expect(osm.notices.joined(separator: " ").contains("© les contributeurs d'OpenStreetMap"))
        #expect(osm.notices.joined(separator: " ").contains("ODbL"))
        #expect(osm.links.map(\.url) == [
            URL(string: "https://www.openstreetmap.org/copyright")!,
            URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!,
            URL(string: "https://api.nervo.test/v1/open-data/segments.ndjson.gz")!,
        ])
    }

    @Test func carriesCopernicusTwoMandatoryNotices() throws {
        let copernicus = try #require(DataSource.all(apiBaseURL: api).first { $0.name == "Copernicus" })

        #expect(copernicus.notices == [
            "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved",
            "The organisations in charge of the Copernicus programme by law or by delegation do not incur any liability for any use of the Copernicus WorldDEM-30",
        ])
    }

    @Test func creditsIGNAndMapbox() throws {
        let sources = DataSource.all(apiBaseURL: api)
        let ign = try #require(sources.first { $0.name == "IGN" })
        let mapbox = try #require(sources.first { $0.name == "Mapbox" })

        #expect(ign.notices.joined(separator: " ").contains("RGE ALTI"))
        #expect(ign.notices.joined(separator: " ").contains("Etalab 2.0"))
        #expect(mapbox.notices.joined(separator: " ").contains("© Mapbox"))
        #expect(mapbox.links.map(\.url).contains(URL(string: "https://www.mapbox.com/about/maps/")!))
    }
}
