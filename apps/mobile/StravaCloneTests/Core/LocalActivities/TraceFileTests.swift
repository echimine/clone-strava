import Foundation
import Testing
@testable import StravaClone

/// `trace.json.gz` v2 built from the stored points and Pauses (ADR-019 §3, ADR-031 §12).
struct TraceFileTests {
    private let start = Date(timeIntervalSince1970: 1_792_047_600)

    private func point(_ seconds: TimeInterval, accuracy: Double = 5, speed: Double? = nil, altitude: Double? = 210) -> LocationSample {
        LocationSample(
            coordinate: Coordinate(latitude: 45.764, longitude: 4.8357),
            altitude: altitude,
            horizontalAccuracy: accuracy,
            speed: speed,
            timestamp: start.addingTimeInterval(seconds)
        )
    }

    private func ms(_ seconds: TimeInterval) -> Int64 {
        start.addingTimeInterval(seconds).epochMilliseconds
    }

    /// The body of a gzip member: header and trailer stripped, raw DEFLATE inflated.
    private func gunzip(_ data: Data) throws -> (json: Data, crc: UInt32, size: UInt32) {
        #expect(Array(data.prefix(3)) == [0x1F, 0x8B, 0x08])
        let body = data.dropFirst(10).dropLast(8)
        let json = try (Data(body) as NSData).decompressed(using: .zlib) as Data
        let trailer = Array(data.suffix(8))
        let crc = trailer[0 ..< 4].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        let size = trailer[4 ..< 8].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
        return (json, crc, size)
    }

    @Test func theChecksumIsTheStandardCRC32() {
        // The CRC-32/ISO-HDLC check value.
        #expect(Gzip.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func theFileIsAGzippedTraceV2() throws {
        let data = try TraceFile.gzippedJSON(points: [point(0, speed: 3.2), point(1)], pauses: [])

        let (json, crc, size) = try gunzip(data)
        #expect(crc == Gzip.crc32(json))
        #expect(Int(size) == json.count)
        let object = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == 2)
        #expect((object["pauses"] as? [Any])?.isEmpty == true)
        let first = try #require((object["points"] as? [[String: Any]])?.first)
        #expect(first["timestampMs"] as? Int64 == ms(0))
        #expect(first["lat"] as? Double == 45.764)
        #expect(first["lon"] as? Double == 4.8357)
        #expect(first["elevationM"] as? Double == 210)
        #expect(first["horizontalAccuracyM"] as? Double == 5)
        #expect(first["speedMs"] as? Double == 3.2)
    }

    @Test func invalidReadingsAreLeftOut() {
        let trace = TraceFile.trace(points: [point(0, accuracy: -1, speed: -1, altitude: nil)], pauses: [])

        #expect(trace.points == [TraceFile.Point(timestampMs: ms(0), lat: 45.764, lon: 4.8357, elevationM: nil, horizontalAccuracyM: nil, speedMs: nil)])
    }

    @Test func aPauseBetweenTwoPointsIsSent() {
        let trace = TraceFile.trace(
            points: [point(0), point(10), point(70), point(80)],
            pauses: [TracePauseInterval(startMs: ms(10), endMs: ms(70))]
        )

        #expect(trace.pauses == [TraceFile.Pause(startMs: ms(10), endMs: ms(70))])
    }

    @Test func aPauseThatIsNotBetweenTwoPointsIsDropped() {
        let trace = TraceFile.trace(
            points: [point(20), point(30)],
            pauses: [
                TracePauseInterval(startMs: ms(5), endMs: ms(15)), // before the first point
                TracePauseInterval(startMs: ms(40), endMs: ms(50)), // after the last point
            ]
        )

        #expect(trace.pauses.isEmpty)
    }
}
