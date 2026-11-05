import SwiftUI

/// "Ajoute une photo de profil" (ADR-037 §2), between the sign-in that ends the Onboarding and
/// the Paywall, for an account the email code has just created. "Choisir une photo" opens the
/// photo menu of the profile (same menu, same crop); the photo stored, `chosen` goes on to the
/// Paywall. "Plus tard" goes there without one. Both wait while a photo is being sent.
struct AvatarPromptView: View {
    let name: String
    let chosen: () -> Void
    let later: () -> Void

    @State private var editor: AvatarEditor
    @State private var isChoosingPhoto = false

    init(name: String, editor: AvatarEditor, chosen: @escaping () -> Void, later: @escaping () -> Void) {
        self.name = name
        self.chosen = chosen
        self.later = later
        _editor = State(initialValue: editor)
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            VStack(spacing: 28) {
                Button { isChoosingPhoto = true } label: {
                    EditableAvatar(name: name, url: nil, editor: editor, size: 132)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(Theme.accent, in: .circle)
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 3))
                                .opacity(editor.isBusy ? 0 : 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(editor.isBusy)
                .accessibilityLabel(AvatarMessages.myPhoto)
                .accessibilityIdentifier("avatarPrompt.avatar")

                VStack(spacing: 12) {
                    Text("Ajoute une photo de profil")
                        .font(.system(size: 32, weight: .bold))
                        .tracking(-0.4)
                        .accessibilityAddTraits(.isHeader)
                    Text("Vos amis vous reconnaîtront dans le fil, les kudos et les commentaires.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button("Choisir une photo") { isChoosingPhoto = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(editor.isBusy)
                    .accessibilityIdentifier("avatarPrompt.choose")
                Button("Plus tard", action: later)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                    .disabled(editor.isBusy)
                    .accessibilityIdentifier("avatarPrompt.later")
            }
            .padding(.horizontal, Theme.spacing)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .avatarPicker(isPresented: $isChoosingPhoto, hasPhoto: false, editor: editor, entry: .onboarding)
        .onAppear {
            editor.changed = { [chosen] _ in chosen() }
        }
    }
}

#if DEBUG
#Preview {
    AvatarPromptView(
        name: "Ada Lovelace",
        editor: .preview,
        chosen: {},
        later: {}
    )
    .tint(Theme.accent)
}
#endif
