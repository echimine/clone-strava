import AVFoundation
import Foundation
import ImageIO
import Testing
@testable import StravaClone

/// The video files of ADR-037 §3: `original.mp4` H.264 720p with its sound, 1 min at most,
/// `poster.jpg` (first frame, 1280 px) and `thumb.jpg` (512 px).
struct VideoExportTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("video-export-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func pixelSize(of url: URL) throws -> (Int?, Int?) {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "public.jpeg")
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        return (properties[kCGImagePropertyPixelWidth] as? Int, properties[kCGImagePropertyPixelHeight] as? Int)
    }

    private func size(_ url: URL) throws -> Int? {
        try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
    }

    @Test func aShortVideoBecomesA720pMP4WithItsSoundAPosterAndAThumb() async throws {
        let movie = try await TestMovie.make(seconds: 5, width: 1_920, height: 1_080)
        let directory = try folder()

        let exported = try await VideoExport.export(movie, into: directory)

        #expect(!exported.trimmed)
        #expect(exported.media.width == 1_280)
        #expect(exported.media.height == 720)
        #expect((4_500 ... 5_500).contains(try #require(exported.media.durationMs)))
        #expect(exported.media.files.map(\.name) == ["original.mp4", "poster.jpg", "thumb.jpg"])
        #expect(exported.media.files.map(\.contentType) == ["video/mp4", "image/jpeg", "image/jpeg"])
        for file in exported.media.files {
            #expect(try size(directory.appendingPathComponent(file.name)) == file.byteCount)
        }
        let original = directory.appendingPathComponent("original.mp4")
        let header = try [UInt8](Data(contentsOf: original).prefix(8))
        #expect(Array(header[4 ..< 8]) == Array("ftyp".utf8), "an MP4 starts with its ftyp box")
        let asset = AVURLAsset(url: original)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await video.load(.formatDescriptions).first?.mediaSubType == .h264)
        #expect(try await !asset.loadTracks(withMediaType: .audio).isEmpty, "the sound is kept")
        #expect(try pixelSize(of: directory.appendingPathComponent("poster.jpg")) == (1_280, 720))
        #expect(try pixelSize(of: directory.appendingPathComponent("thumb.jpg")) == (512, 288))
    }

    @Test func aVideoLongerThanAMinuteIsCutToItsFirstMinute() async throws {
        let movie = try await TestMovie.make(seconds: 75)
        let directory = try folder()

        let exported = try await VideoExport.export(movie, into: directory)

        #expect(exported.trimmed)
        let duration = try #require(exported.media.durationMs)
        #expect((59_000 ... 60_000).contains(duration))
        let written = try await AVURLAsset(url: directory.appendingPathComponent("original.mp4")).load(.duration)
        #expect(abs(written.seconds - 60) < 1)
    }

    @Test func aSmallVideoIsNotEnlarged() async throws {
        let exported = try await VideoExport.export(try await TestMovie.make(seconds: 2, audio: false), into: try folder())

        #expect(exported.media.width == 320)
        #expect(exported.media.height == 240)
    }

    @Test func aFileThatIsNotAMovieIsRefused() async throws {
        let notAMovie = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-movie-\(UUID()).mov")
        try Data("not a movie".utf8).write(to: notAMovie)

        await #expect(throws: VideoExport.Failure.unreadable) {
            try await VideoExport.export(notAMovie, into: try folder())
        }
    }

    @Test func theTrimIsDecidedByTheOriginalsDuration() {
        #expect(!VideoExport.isTrimmed(.seconds(60)))
        #expect(VideoExport.isTrimmed(.milliseconds(60_001)))
    }
}
