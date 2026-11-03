import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
@testable import StravaClone

/// Changing my Avatar (ADR-037 §2): the new photo shows at once with a spinner; on failure
/// the old one comes back with an alert; no network, no upload.
@MainActor
struct AvatarEditorTests {
    private let newURL = URL(string: "https://bucket.test/avatars/me/new.jpg?X-Amz-Signature=a")!

    private final class Changes {
        var urls: [URL?] = []
    }

    private func makeEditor(
        _ repository: FakeAvatarRepository = FakeAvatarRepository(),
        analytics: FakeAnalyticsClient = FakeAnalyticsClient(),
        online: Bool = true,
        changes: Changes = Changes()
    ) -> AvatarEditor {
        let editor = AvatarEditor(
            repository: repository,
            analytics: analytics,
            imageLoader: ImageLoader(cache: URLCache(memoryCapacity: 10_000_000, diskCapacity: 0)),
            isOnline: { online }
        )
        editor.changed = { changes.urls.append($0) }
        return editor
    }

    private func photo() throws -> AvatarSourceImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 600), format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return format
        }())
        let image = renderer.image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 900, height: 600))
        }
        return try #require(AvatarSourceImage(uiImage: image))
    }

    private let square = CGRect(x: 150, y: 0, width: 600, height: 600)

    @Test func theCroppedPhotoIsSentAsA512JPEGAndBecomesMyAvatar() async throws {
        let repository = FakeAvatarRepository()
        let analytics = FakeAnalyticsClient()
        let changes = Changes()
        let editor = makeEditor(repository, analytics: analytics, changes: changes)

        let stored = await editor.send(try photo(), cropping: square, source: .library, entry: .profile)

        #expect(stored)
        let jpeg = try #require(repository.uploads.first)
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 512)
        #expect(changes.urls == [newURL])
        #expect(editor.preview == nil)
        #expect(!editor.isBusy)
        #expect(editor.problem == nil)
        #expect(analytics.events == [.avatarChanged(source: .library, entry: .profile)])
    }

    @Test func theNewPhotoShowsAtOnceWithASpinnerWhileSending() async throws {
        let repository = FakeAvatarRepository()
        repository.holdsUploads = true
        let editor = makeEditor(repository)
        let photo = try photo()

        let sending = Task { await editor.send(photo, cropping: square, source: .camera, entry: .editProfile) }
        #expect(await eventually { repository.hasHeldUpload })

        #expect(editor.preview != nil)
        #expect(editor.isBusy)

        repository.release()
        #expect(await sending.value)
        #expect(editor.preview == nil)
    }

    @Test func aFailedUploadBringsTheOldPhotoBackWithAnAlert() async throws {
        let repository = FakeAvatarRepository()
        repository.uploadResult = .failure(.rejected(code: "avatar_too_large"))
        let analytics = FakeAnalyticsClient()
        let changes = Changes()
        let editor = makeEditor(repository, analytics: analytics, changes: changes)

        let stored = await editor.send(try photo(), cropping: square, source: .camera, entry: .editProfile)

        #expect(!stored)
        #expect(editor.preview == nil)
        #expect(!editor.isBusy)
        #expect(changes.urls.isEmpty)
        #expect(editor.problem == AvatarEditor.Problem(alert: .uploadFailed, entry: .editProfile))
        #expect(AvatarEditor.Alert.uploadFailed.title == "La photo n'a pas pu être envoyée")
        #expect(analytics.events == [.avatarUploadFailed(reason: .rejected)])
    }

    @Test func withoutNetworkNothingIsSentAndTheOldPhotoStays() async throws {
        let repository = FakeAvatarRepository()
        let analytics = FakeAnalyticsClient()
        let changes = Changes()
        let editor = makeEditor(repository, analytics: analytics, online: false, changes: changes)

        let stored = await editor.send(try photo(), cropping: square, source: .library, entry: .profile)

        #expect(!stored)
        #expect(repository.uploads.isEmpty)
        #expect(editor.preview == nil)
        #expect(changes.urls.isEmpty)
        #expect(editor.problem == AvatarEditor.Problem(alert: .offline, entry: .profile))
        #expect(analytics.events == [.avatarUploadFailed(reason: .offline)])
    }

    @Test func aConnectionLostOnTheWayIsAnOfflineFailure() async throws {
        let repository = FakeAvatarRepository()
        repository.uploadResult = .failure(.offline)
        let analytics = FakeAnalyticsClient()
        let editor = makeEditor(repository, analytics: analytics)

        _ = await editor.send(try photo(), cropping: square, source: .library, entry: .profile)

        #expect(editor.problem?.alert == .offline)
        #expect(analytics.events == [.avatarUploadFailed(reason: .offline)])
    }

    @Test func theSentPhotoIsShownEverywhereWithoutDownloadingIt() async throws {
        let loader = ImageLoader(session: .shared, cache: URLCache(memoryCapacity: 10_000_000, diskCapacity: 0))
        let editor = AvatarEditor(repository: FakeAvatarRepository(), analytics: FakeAnalyticsClient(), imageLoader: loader, isOnline: { true })

        _ = await editor.send(try photo(), cropping: square, source: .library, entry: .profile)

        let resigned = URL(string: "https://bucket.test/avatars/me/new.jpg?X-Amz-Signature=b")!
        #expect(await loader.load(resigned).image != nil)
    }

    @Test func removingMyPhotoShowsMyInitials() async {
        let repository = FakeAvatarRepository()
        let analytics = FakeAnalyticsClient()
        let changes = Changes()
        let editor = makeEditor(repository, analytics: analytics, changes: changes)

        let removed = await editor.remove(entry: .profile)

        #expect(removed)
        #expect(repository.removeCount == 1)
        #expect(changes.urls == [nil])
        #expect(analytics.events == [.avatarRemoved])
    }

    @Test func aFailedRemovalKeepsThePhotoAndSaysSo() async {
        let repository = FakeAvatarRepository()
        repository.removeResult = .failure(.network)
        let analytics = FakeAnalyticsClient()
        let changes = Changes()
        let editor = makeEditor(repository, analytics: analytics, changes: changes)

        let removed = await editor.remove(entry: .editProfile)

        #expect(!removed)
        #expect(changes.urls.isEmpty)
        #expect(editor.problem == AvatarEditor.Problem(alert: .removeFailed, entry: .editProfile))
        #expect(analytics.events.isEmpty)
    }

    @Test func removingWithoutNetworkKeepsThePhoto() async {
        let repository = FakeAvatarRepository()
        let editor = makeEditor(repository, online: false)

        let removed = await editor.remove(entry: .profile)

        #expect(!removed)
        #expect(repository.removeCount == 0)
        #expect(editor.problem?.alert == .offline)
    }

    @Test func theDeleteChoiceIsOfferedOnlyWithAPhoto() {
        #expect(AvatarMenuChoice.choices(hasPhoto: true, cameraAvailable: true) == [.camera, .library, .remove])
        #expect(AvatarMenuChoice.choices(hasPhoto: false, cameraAvailable: true) == [.camera, .library])
        #expect(AvatarMenuChoice.choices(hasPhoto: false, cameraAvailable: false) == [.library])
    }
}
