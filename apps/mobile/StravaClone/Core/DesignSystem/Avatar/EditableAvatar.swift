import SwiftUI

/// My avatar where I can change it (ADR-037 §2): the photo being sent shows at once, under a
/// spinner, until the API has stored it; otherwise `AvatarView` (photo or initials).
struct EditableAvatar: View {
    let name: String
    let url: URL?
    let editor: AvatarEditor
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            if let preview = editor.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
            } else {
                AvatarView(name: name, url: url, size: size)
            }
            if editor.isBusy {
                Circle().fill(.black.opacity(0.35))
                ProgressView()
                    .tint(.white)
                    .accessibilityLabel(AvatarMessages.sending)
            }
        }
        .frame(width: size, height: size)
    }
}
