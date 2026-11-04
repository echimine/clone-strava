import AVFoundation
import CoreGraphics
import Foundation

/// A video's files (ADR-037 §3), made by AVFoundation: `original.mp4`, H.264 720p
/// (`AVAssetExportPreset1280x720`) with its sound, 1 min at most; `poster.jpg`, its first frame
/// at 1280 px, and `thumb.jpg`, 512 px, both JPEG at quality 0.8 without metadata. A longer video
/// is cut to its first minute ("Vidéo coupée à 1 min"). The location and other personal metadata
/// are left out of the MP4 (`forSharing`).
enum VideoExport {
    static let maxDuration = Duration.seconds(60)
    static let posterMaxPixelSize = 1_280
    static let thumbMaxPixelSize = 512
    /// The API's limits (`MEDIA_FILE_SPECS`): a larger file would be refused.
    static let originalMaxBytes = 60 * 1_048_576
    static let imageMaxBytes = 1_048_576

    enum Failure: Error, Equatable {
        case unreadable
        case encoding
        case tooLarge
    }

    struct Output: Hashable, Sendable {
        let media: ExportedMedia
        /// The original was longer than a minute: only its first minute was kept.
        let trimmed: Bool
    }

    /// A video of `duration` is cut at export.
    static func isTrimmed(_ duration: Duration) -> Bool {
        duration > maxDuration
    }

    /// Writes the three files into `directory`; returns the MP4's size in pixels, its duration
    /// and the files.
    static func export(_ movie: URL, into directory: URL) async throws(Failure) -> Output {
        let asset = AVURLAsset(url: movie)
        let duration: CMTime
        do {
            duration = try await asset.load(.duration)
            guard try await !asset.loadTracks(withMediaType: .video).isEmpty else { throw Failure.unreadable }
        } catch {
            throw .unreadable
        }
        let trimmed = isTrimmed(Self.duration(of: duration))
        let limit = CMTime(seconds: Double(maxDuration.components.seconds), preferredTimescale: 600)
        let original = directory.appendingPathComponent(MediaUploadFile.originalVideo)
        try await transcode(asset, range: CMTimeRange(start: .zero, duration: trimmed ? limit : duration), to: original)

        let output = AVURLAsset(url: original)
        let size: CGSize
        let written: CMTime
        do {
            guard let track = try await output.loadTracks(withMediaType: .video).first else { throw Failure.encoding }
            let (natural, transform) = try await track.load(.naturalSize, .preferredTransform)
            size = natural.applying(transform)
            written = try await output.load(.duration)
        } catch {
            throw .encoding
        }
        let posterData = try jpeg(await frame(of: output, maxPixelSize: posterMaxPixelSize))
        let thumbData = try jpeg(await frame(of: output, maxPixelSize: thumbMaxPixelSize))
        let originalBytes = (try? FileManager.default.attributesOfItem(atPath: original.path)[.size] as? Int) ?? 0
        guard originalBytes > 0 else { throw .encoding }
        guard originalBytes <= originalMaxBytes, posterData.count <= imageMaxBytes, thumbData.count <= imageMaxBytes else {
            throw .tooLarge
        }
        do {
            try posterData.write(to: directory.appendingPathComponent(MediaUploadFile.poster))
            try thumbData.write(to: directory.appendingPathComponent(MediaUploadFile.thumb))
        } catch {
            throw .encoding
        }
        let media = ExportedMedia(
            width: Int(abs(size.width).rounded()),
            height: Int(abs(size.height).rounded()),
            durationMs: Int((written.seconds * 1_000).rounded()),
            files: [
                MediaUploadFile(name: MediaUploadFile.originalVideo, contentType: "video/mp4", byteCount: originalBytes),
                MediaUploadFile(name: MediaUploadFile.poster, contentType: "image/jpeg", byteCount: posterData.count),
                MediaUploadFile(name: MediaUploadFile.thumb, contentType: "image/jpeg", byteCount: thumbData.count),
            ]
        )
        return Output(media: media, trimmed: trimmed)
    }

    static func duration(of time: CMTime) -> Duration {
        guard time.isNumeric else { return .zero }
        return .milliseconds(Int64((time.seconds * 1_000).rounded()))
    }

    /// The MP4 of `range`, its sound kept, never larger than the API takes.
    private static func transcode(_ asset: AVAsset, range: CMTimeRange, to url: URL) async throws(Failure) {
        try? FileManager.default.removeItem(at: url)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1280x720) else {
            throw .unreadable
        }
        session.timeRange = range
        session.shouldOptimizeForNetworkUse = true
        session.metadataItemFilter = .forSharing()
        session.fileLengthLimit = Int64(originalMaxBytes)
        do {
            if #available(iOS 18, *) {
                try await session.export(to: url, as: .mp4)
            } else {
                session.outputURL = url
                session.outputFileType = .mp4
                await session.export()
                guard session.status == .completed else { throw Failure.encoding }
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw .encoding
        }
    }

    private static func jpeg(_ image: CGImage) throws(Failure) -> Data {
        do {
            return try PhotoExport.jpeg(image)
        } catch {
            throw .encoding
        }
    }

    /// The first frame, oriented, its longest side at most `maxPixelSize`.
    private static func frame(of asset: AVAsset, maxPixelSize: Int) async throws(Failure) -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 10)
        do {
            return try await generator.image(at: .zero).image
        } catch {
            throw .encoding
        }
    }
}
