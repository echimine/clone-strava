import Foundation

/// The raw trace of a local Activity, `trace.json.gz` v2 (ADR-019 §3, ADR-031 §12): built from
/// the GRDB points and Pauses just before `upload_trace`, never at Save, so it can be rebuilt.
enum TraceFile {
    static let schemaVersion = 2

    struct Point: Codable, Equatable, Sendable {
        let timestampMs: Int64
        let lat: Double
        let lon: Double
        let elevationM: Double?
        let horizontalAccuracyM: Double?
        let speedMs: Double?
    }

    struct Pause: Codable, Equatable, Sendable {
        let startMs: Int64
        let endMs: Int64
    }

    struct Trace: Codable, Equatable, Sendable {
        let schemaVersion: Int
        let points: [Point]
        let pauses: [Pause]
    }

    /// The trace v2 of these points and Pauses. A Pause must lie between two points (contract):
    /// one before the first point or after the last is dropped, as is an empty or overlapping one.
    static func trace(points samples: [LocationSample], pauses intervals: [TracePauseInterval]) -> Trace {
        let points = samples.map { sample in
            Point(
                timestampMs: sample.timestamp.epochMilliseconds,
                lat: sample.coordinate.latitude,
                lon: sample.coordinate.longitude,
                elevationM: sample.altitude,
                horizontalAccuracyM: sample.horizontalAccuracy >= 0 ? sample.horizontalAccuracy : nil,
                speedMs: sample.speed.flatMap { $0 >= 0 ? $0 : nil }
            )
        }
        var pauses: [Pause] = []
        for interval in intervals.sorted(by: { $0.startMs < $1.startMs }) where interval.startMs < interval.endMs {
            let hasPointBefore = points.contains { $0.timestampMs <= interval.startMs }
            let hasPointAfter = points.contains { $0.timestampMs >= interval.endMs }
            let hasPointInside = points.contains { $0.timestampMs > interval.startMs && $0.timestampMs < interval.endMs }
            let overlaps = pauses.last.map { interval.startMs < $0.endMs } ?? false
            guard hasPointBefore, hasPointAfter, !hasPointInside, !overlaps else { continue }
            pauses.append(Pause(startMs: interval.startMs, endMs: interval.endMs))
        }
        return Trace(schemaVersion: schemaVersion, points: points, pauses: pauses)
    }

    /// The gzipped JSON sent to the bucket (`application/gzip`).
    static func gzippedJSON(points: [LocationSample], pauses: [TracePauseInterval]) throws -> Data {
        try Gzip.compress(JSONEncoder().encode(trace(points: points, pauses: pauses)))
    }
}

/// Gzip (RFC 1952) over Foundation's raw DEFLATE (`NSData.compressed(using: .zlib)`, RFC 1951).
enum Gzip {
    static func compress(_ data: Data) throws -> Data {
        let deflated = try (data as NSData).compressed(using: .zlib) as Data
        var output = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03])
        output.append(deflated)
        output.append(littleEndian: crc32(data))
        output.append(littleEndian: UInt32(truncatingIfNeeded: data.count))
        return output
    }

    private static let table: [UInt32] = (0 ..< 256).map { index in
        var value = UInt32(index)
        for _ in 0 ..< 8 {
            value = value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1
        }
        return value
    }

    /// CRC-32 (ISO-HDLC), the checksum of the gzip trailer.
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(littleEndian value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
