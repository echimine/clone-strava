import Foundation

/// File formats accepted by the import (ADR-028).
enum ImportFormat: String, Codable, Sendable, CaseIterable {
    case gpx, tcx, fit

    init?(fileName: String) {
        self.init(rawValue: (fileName as NSString).pathExtension.lowercased())
    }
}

/// `activity_import.status` (ADR-028 §2).
enum ImportStatus: String, Codable, Sendable {
    case pending, processing, imported, duplicate, failed

    var isFinal: Bool {
        self == .imported || self == .duplicate || self == .failed
    }
}

/// An import as returned by `/v1/activity-imports` (ADR-028 §3).
struct ActivityImport: Equatable, Sendable {
    let id: UUID
    let format: ImportFormat
    let fileName: String
    let status: ImportStatus
    /// Created activity (`imported`) or existing one (`duplicate`).
    let activityId: String?
    /// Error code (ADR-028 §7) when `failed`, e.g. `no_gps_data`.
    let errorCode: String?
}

/// A picked file, copied into the app's temporary directory before the upload.
struct ImportFile: Equatable, Sendable {
    let localURL: URL
    let fileName: String
    let format: ImportFormat
    let sizeBytes: Int
}

/// Sports the user can force (codes of `sport_type`, ADR-017).
enum ImportSport: String, CaseIterable, Sendable, Identifiable {
    case run, ride, swim, walk, hike

    var id: String { rawValue }
}

/// `activity.visibility` (ADR-017).
enum ImportVisibility: String, CaseIterable, Sendable, Identifiable {
    case everyone = "public"
    case followers
    case onlyMe = "private"

    var id: String { rawValue }
}

/// Overrides chosen on the confirmation sheet; `nil` lets the server use the file / profile.
struct ImportOptions: Equatable, Sendable {
    var sport: ImportSport?
    var title: String?
    var visibility: ImportVisibility?
}

/// Pre-signed `PUT` URL of the bucket (ADR-028 §3).
struct UploadTarget: Equatable, Sendable {
    let url: URL
    let expiresAt: Date
}

/// Upper bound checked before any network call (ADR-028 §11).
let importMaxFileBytes = 25 * 1024 * 1024
