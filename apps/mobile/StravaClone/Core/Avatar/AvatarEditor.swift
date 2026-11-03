import CoreGraphics
import Foundation
import Observation
import UIKit

/// Changing or removing my Avatar (ADR-037 §2), for every screen that offers it: the Profile
/// header, "Modifier le profil" and "Ajoute une photo de profil". The new photo shows at once
/// (`preview`) with a spinner (`isBusy`); on failure the old one comes back with an alert.
/// Network required: without it nothing is sent and a message says so (no offline queue).
@Observable
@MainActor
final class AvatarEditor {
    /// What went wrong, as the alert says it.
    enum Alert: Equatable, Sendable {
        case uploadFailed, removeFailed, offline

        var title: String {
            switch self {
            case .uploadFailed: AvatarMessages.uploadFailed
            case .removeFailed: AvatarMessages.removeFailed
            case .offline: AvatarMessages.offline
            }
        }
    }

    /// An alert, and the screen whose menu started the action: only that screen shows it.
    struct Problem: Equatable, Sendable {
        let alert: Alert
        let entry: AnalyticsEvent.AvatarEntry
    }

    /// The cropped photo being sent; nil otherwise.
    private(set) var preview: UIImage?
    /// A photo is being sent or removed.
    private(set) var isBusy = false
    var problem: Problem?

    /// Told the new Avatar URL once stored, nil once removed: the owner updates its athlete.
    @ObservationIgnored var changed: (@MainActor (URL?) -> Void)?

    @ObservationIgnored private let repository: any AvatarRepository
    @ObservationIgnored private let analytics: any AnalyticsClient
    @ObservationIgnored private let imageLoader: ImageLoader
    @ObservationIgnored private let isOnline: @MainActor () -> Bool
    @ObservationIgnored private var generation = 0

    init(
        repository: any AvatarRepository,
        analytics: any AnalyticsClient,
        imageLoader: ImageLoader,
        isOnline: @escaping @MainActor () -> Bool
    ) {
        self.repository = repository
        self.analytics = analytics
        self.imageLoader = imageLoader
        self.isOnline = isOnline
    }

    /// "Choisir" on the crop screen: encodes `crop` of `photo`, shows it, sends it. True once
    /// it is my Avatar.
    @discardableResult
    func send(
        _ photo: AvatarSourceImage,
        cropping crop: CGRect,
        source: AnalyticsEvent.AvatarSource,
        entry: AnalyticsEvent.AvatarEntry
    ) async -> Bool {
        guard !isBusy else { return false }
        guard isOnline() else {
            fail(.offline, entry: entry, reason: .offline)
            return false
        }
        isBusy = true
        let current = generation
        let jpeg = await Task.detached(priority: .userInitiated) {
            AvatarJPEG.encode(photo.image, cropping: crop)
        }.value
        guard current == generation else { return false }
        guard let jpeg else {
            isBusy = false
            fail(.uploadFailed, entry: entry, reason: .encoding)
            return false
        }
        preview = UIImage(data: jpeg)
        do {
            let url = try await repository.upload(jpeg)
            if let url {
                await imageLoader.store(jpeg, for: url)
            }
            guard current == generation else { return false }
            changed?(url)
            analytics.capture(.avatarChanged(source: source, entry: entry))
            finish()
            return true
        } catch {
            guard current == generation else { return false }
            finish()
            fail(error == .offline ? .offline : .uploadFailed, entry: entry, reason: Self.reason(for: error))
            return false
        }
    }

    /// "Supprimer la photo": true once I show my initials.
    @discardableResult
    func remove(entry: AnalyticsEvent.AvatarEntry) async -> Bool {
        guard !isBusy else { return false }
        guard isOnline() else {
            problem = Problem(alert: .offline, entry: entry)
            return false
        }
        isBusy = true
        let current = generation
        do {
            try await repository.remove()
            guard current == generation else { return false }
            changed?(nil)
            analytics.capture(.avatarRemoved)
            finish()
            return true
        } catch {
            guard current == generation else { return false }
            finish()
            problem = Problem(alert: error == .offline ? .offline : .removeFailed, entry: entry)
            return false
        }
    }

    /// Sign-out: forgets a photo being sent; its answer is ignored.
    func reset() {
        generation += 1
        finish()
        problem = nil
    }

    private func finish() {
        preview = nil
        isBusy = false
    }

    private func fail(_ alert: Alert, entry: AnalyticsEvent.AvatarEntry, reason: AnalyticsEvent.AvatarUploadFailure) {
        problem = Problem(alert: alert, entry: entry)
        analytics.capture(.avatarUploadFailed(reason: reason))
    }

    private static func reason(for error: AvatarError) -> AnalyticsEvent.AvatarUploadFailure {
        switch error {
        case .offline: .offline
        case .network: .network
        case .rejected: .rejected
        case .unauthorized, .server: .server
        }
    }
}

/// The choices of the photo menu (ADR-037 §2), in order.
enum AvatarMenuChoice: Equatable, Sendable {
    case camera, library, remove

    /// "Supprimer la photo" only when there is a photo; "Prendre une photo" only with a camera.
    static func choices(hasPhoto: Bool, cameraAvailable: Bool) -> [AvatarMenuChoice] {
        (cameraAvailable ? [.camera] : []) + [.library] + (hasPhoto ? [.remove] : [])
    }
}
