import Foundation

/// Mapbox Static Images URL of an activity route (ADR-029): Outdoors style, orange path,
/// green start and red finish pins, retina. Built without the Mapbox SDK, so any view
/// can show it as a plain cached image.
enum StaticMapURL {
    /// Mapbox's URL length limit.
    static let maxLength = 8_192

    /// Only RFC 3986 unreserved characters stay as is: polyline characters such as
    /// `?`, `@`, `[`, `\`, `` ` `` or `|` must be percent-encoded inside the path.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    /// `nil` without a token, for an empty route, or when the URL would be too long.
    static func make(
        route: EncodedPolyline,
        size: CGSize,
        accessToken: String,
        accent: String = "FC5200"
    ) -> URL? {
        guard !accessToken.isEmpty, size.width >= 1, size.height >= 1 else { return nil }
        let coordinates = route.decode()
        guard let start = coordinates.first, let end = coordinates.last, coordinates.count >= 2,
              let polyline = route.value.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { return nil }

        // Mapbox caps static images at 1280 px per side (before @2x).
        let width = min(1_280, Int(size.width.rounded()))
        let height = min(1_280, Int(size.height.rounded()))
        let overlays = [
            "path-4+\(accent)-1(\(polyline))",
            "pin-s+2ECC71(\(pin(start)))",
            "pin-s+E74C3C(\(pin(end)))",
        ].joined(separator: ",")
        let string = "https://api.mapbox.com/styles/v1/mapbox/outdoors-v12/static/\(overlays)/auto/"
            + "\(width)x\(height)@2x?padding=40&access_token=\(accessToken)"
        guard string.count <= maxLength else { return nil }
        return URL(string: string)
    }

    private static func pin(_ coordinate: Coordinate) -> String {
        String(format: "%.5f,%.5f", coordinate.longitude, coordinate.latitude)
    }
}
