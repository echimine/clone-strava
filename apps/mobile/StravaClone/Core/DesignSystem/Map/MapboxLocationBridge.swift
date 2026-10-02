import Combine
import MapboxMaps

/// Feeds the Mapbox puck from our `LocationProvider` (ADR-027 §3), so Mapbox never
/// starts its own `AppleLocationProvider`: the puck shows exactly the fixes Recording uses.
/// Updates are published on the main actor, as `LocationDataModel` requires.
@MainActor
final class MapboxLocationBridge {
    private let locations = CurrentValueSubject<[Location], Never>([])
    private let headings = PassthroughSubject<Heading, Never>()

    private(set) lazy var dataModel = LocationDataModel(
        location: locations.filter { !$0.isEmpty }.eraseToAnyPublisher(),
        heading: headings.eraseToAnyPublisher()
    )

    /// Forwards the provider's streams until the calling task is cancelled
    /// (SwiftUI `.task`: the map leaves the screen and the GPS can stop).
    func run(provider: any LocationProvider) async {
        let samples = await provider.samples()
        let headingStream = await provider.headings()
        let headingForwarding = Task { [weak self] in
            for await direction in headingStream {
                self?.headings.send(Heading(direction: direction, accuracy: 0))
            }
        }
        defer { headingForwarding.cancel() }
        for await sample in samples {
            locations.send([Location(sample)])
        }
    }
}

private extension Location {
    convenience init(_ sample: LocationSample) {
        self.init(
            coordinate: CLLocationCoordinate2D(latitude: sample.coordinate.latitude, longitude: sample.coordinate.longitude),
            timestamp: sample.timestamp,
            altitude: sample.altitude,
            horizontalAccuracy: sample.horizontalAccuracy >= 0 ? sample.horizontalAccuracy : nil,
            bearing: sample.course
        )
    }
}
