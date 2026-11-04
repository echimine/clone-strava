import AVFoundation
import Foundation

/// A video picked in the library (ADR-037 §3, §5): copied once out of Photos into a temporary
/// file, read by the strip's tile (poster, duration, "Vidéo coupée à 1 min") and by the export.
/// The copy lives as long as this object: the draft and the queue drop it once the video is
/// exported or the sheet is closed, and its file goes with it.
actor PickedMovie {
    /// Where the copies are written; emptied at launch (`deleteLeftovers`).
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("PickedMovies", isDirectory: true)

    private let load: @Sendable () async throws -> URL
    private var loading: Task<URL, any Error>?
    private var loaded: URL?

    /// `load` copies the movie into a file this object then owns (it deletes it).
    init(load: @escaping @Sendable () async throws -> URL) {
        self.load = load
    }

    deinit {
        if let loaded {
            try? FileManager.default.removeItem(at: loaded)
        }
    }

    /// The movie's file, copied at the first call; a failed copy is tried again at the next.
    func file() async throws -> URL {
        let task = loading ?? Task { try await load() }
        loading = task
        do {
            let url = try await task.value
            loaded = url
            return url
        } catch {
            if loading == task { loading = nil }
            throw error
        }
    }

    /// The original's duration, before any cut.
    func duration() async throws -> Duration {
        VideoExport.duration(of: try await AVURLAsset(url: file()).load(.duration))
    }

    /// Longer than a minute: only its first minute will be sent.
    func isTrimmed() async -> Bool {
        guard let duration = try? await duration() else { return false }
        return VideoExport.isTrimmed(duration)
    }

    /// The copies of a previous run: no picked video outlives the app.
    static func deleteLeftovers() {
        try? FileManager.default.removeItem(at: root)
    }

    /// A new file name under `root`, keeping the original's extension (AVFoundation reads it).
    static func destination(extension pathExtension: String) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(UUID().uuidString).appendingPathExtension(pathExtension.isEmpty ? "mov" : pathExtension)
    }
}

extension MediaSource {
    /// A picked video: its file is copied from the library at the first read.
    static func video(_ movie: PickedMovie) -> MediaSource {
        MediaSource(kind: .video, movie: movie) { .movie(try await movie.file()) }
    }
}

extension PickedMedia {
    /// A video longer than a minute, cut at export: counted in `videosTrimmed`
    /// (`activity_media_saved`, ADR-037 §13) and shown on its tile.
    func isTrimmed() async -> Bool {
        await source.movie?.isTrimmed() ?? false
    }
}
