import Foundation

/// `APIClient` adapter of `ItineraryMetricsPreviewer`: `POST /v1/itineraries/metrics-preview`
/// (ADR-030 §6), with the types generated from the OpenAPI document (ADR-026).
struct APIItineraryMetricsPreviewer: ItineraryMetricsPreviewer {
    private typealias Body = Components.Schemas.ItineraryMetricsPreviewRequestDto
    private typealias Answer = Components.Schemas.ItineraryMetricsDto_Output

    let apiClient: APIClient

    func metrics(for request: ItineraryMetricsRequest) async throws(ItineraryMetricsError) -> ItineraryMetrics {
        let answer: Answer
        do {
            answer = try await apiClient.send(method: "POST", path: "/v1/itineraries/metrics-preview", body: Self.body(of: request))
        } catch .offline {
            throw .offline
        } catch {
            throw .unavailable
        }
        return ItineraryMetrics(
            distance: Distance(meters: answer.distanceM),
            elevationGain: answer.elevationGainM,
            elevationSource: Self.source(answer.elevationSource)
        )
    }

    private static func body(of request: ItineraryMetricsRequest) -> Body {
        Body(
            waypoints: request.waypoints.map { .init(lat: $0.latitude, lon: $0.longitude) },
            legs: request.legs.map { leg in
                switch leg {
                case .follow(let polyline): .case1(.init(mode: .follow, polyline6: polyline.value))
                case .straight: .case2(.init(mode: .straight))
                }
            }
        )
    }

    private static func source(_ source: Answer.elevationSourcePayload) -> ElevationSource {
        switch source {
        case .ign: .ign
        case .mixed: .mixed
        case .open_meteo: .openMeteo
        }
    }
}
