import PhotosUI
import SwiftUI

extension View {
    /// The photo menu (ADR-037 §2): "Prendre une photo", "Choisir dans la photothèque",
    /// "Supprimer la photo" (only when `hasPhoto`), then the crop screen, then the upload by
    /// `editor`. Opened by setting `isPresented`; any screen can offer it (the Profile header,
    /// "Modifier le profil", "Ajoute une photo de profil"). `entry` goes to `avatar_changed`,
    /// and only the screen whose menu started an action shows its alert.
    func avatarPicker(
        isPresented: Binding<Bool>,
        hasPhoto: Bool,
        editor: AvatarEditor,
        entry: AnalyticsEvent.AvatarEntry
    ) -> some View {
        modifier(AvatarPickerModifier(isPresented: isPresented, hasPhoto: hasPhoto, editor: editor, entry: entry))
    }
}

private struct AvatarPickerModifier: ViewModifier {
    /// The full-screen step: the camera then the crop, or the crop of a library photo.
    private struct Capture: Identifiable {
        let id = UUID()
        let source: AnalyticsEvent.AvatarSource
        var photo: AvatarSourceImage?
    }

    @Binding var isPresented: Bool
    let hasPhoto: Bool
    @Bindable var editor: AvatarEditor
    let entry: AnalyticsEvent.AvatarEntry

    @State private var isPickingFromLibrary = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var capture: Capture?
    @State private var isCameraDenied = false
    @State private var isUnreadable = false
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .confirmationDialog(AvatarMessages.menuTitle, isPresented: $isPresented, titleVisibility: .hidden) {
                ForEach(AvatarMenuChoice.choices(hasPhoto: hasPhoto, cameraAvailable: CameraAccess.isAvailable), id: \.self) { choice in
                    button(choice)
                }
                Button(AvatarMessages.cancel, role: .cancel) {}
            }
            .photosPicker(isPresented: $isPickingFromLibrary, selection: $libraryItem, matching: .images)
            .onChange(of: libraryItem) { _, item in
                guard let item else { return }
                libraryItem = nil
                Task { await open(item) }
            }
            .fullScreenCover(item: $capture) { capture in
                CaptureFlow(capture: capture, finish: { photo, crop in
                    self.capture = nil
                    guard let photo, let crop else { return }
                    Task { await editor.send(photo, cropping: crop, source: capture.source, entry: entry) }
                })
            }
            .alert(AvatarMessages.cameraDeniedTitle, isPresented: $isCameraDenied) {
                Button(AvatarMessages.openSettings) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                Button(AvatarMessages.chooseFromLibrary) { isPickingFromLibrary = true }
                Button(AvatarMessages.cancel, role: .cancel) {}
            } message: {
                Text(AvatarMessages.cameraDeniedMessage)
            }
            .alert(AvatarMessages.unreadablePhoto, isPresented: $isUnreadable) {
                Button(AvatarMessages.ok, role: .cancel) {}
            }
            .alert(editor.problem?.alert.title ?? "", isPresented: problemIsShown) {
                Button(AvatarMessages.ok, role: .cancel) {}
            }
    }

    private var problemIsShown: Binding<Bool> {
        Binding(
            get: { editor.problem?.entry == entry },
            set: { if !$0, editor.problem?.entry == entry { editor.problem = nil } }
        )
    }

    @ViewBuilder private func button(_ choice: AvatarMenuChoice) -> some View {
        switch choice {
        case .camera:
            Button(AvatarMessages.takePhoto) { Task { await openCamera() } }
        case .library:
            Button(AvatarMessages.chooseFromLibrary) { isPickingFromLibrary = true }
        case .remove:
            Button(AvatarMessages.removePhoto, role: .destructive) {
                Task { await editor.remove(entry: entry) }
            }
        }
    }

    private func openCamera() async {
        if await CameraAccess.request() {
            capture = Capture(source: .camera)
        } else {
            isCameraDenied = true
        }
    }

    private func open(_ item: PhotosPickerItem) async {
        let data = try? await item.loadTransferable(type: Data.self)
        let photo = await Task.detached(priority: .userInitiated) {
            data.flatMap(AvatarSourceImage.init(data:))
        }.value
        if let photo {
            capture = Capture(source: .library, photo: photo)
        } else {
            isUnreadable = true
        }
    }

    /// The camera, then the crop of its picture; or straight to the crop for a library photo.
    private struct CaptureFlow: View {
        let capture: Capture
        /// The photo and the square to send; nils when abandoned.
        let finish: (AvatarSourceImage?, CGRect?) -> Void

        @State private var taken: AvatarSourceImage?

        var body: some View {
            if let photo = capture.photo ?? taken {
                AvatarCropView(photo: photo, choose: { finish(photo, $0) }, cancel: { finish(nil, nil) })
            } else {
                CameraPicker { image in
                    if let image, let photo = AvatarSourceImage(uiImage: image) {
                        taken = photo
                    } else {
                        finish(nil, nil)
                    }
                }
                .ignoresSafeArea()
            }
        }
    }
}
