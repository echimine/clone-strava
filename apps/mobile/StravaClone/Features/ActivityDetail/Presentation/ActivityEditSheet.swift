import SwiftUI

/// The edit sheet (ADR-033 §7), styled like `ImportConfirmationSheet`: title, multi-line
/// description, sport, visibility; "Enregistrer" is disabled while the title is blank. After a
/// `422` it comes back with the athlete's input and the reason on top.
struct ActivityEditSheet: View {
    @State private var form: ActivityEditor.Form
    let onSave: (ActivityEditor.Form) -> Void
    let onCancel: () -> Void

    init(form: ActivityEditor.Form, onSave: @escaping (ActivityEditor.Form) -> Void, onCancel: @escaping () -> Void) {
        _form = State(initialValue: form)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        NavigationStack {
            Form {
                if let message = form.errorMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("activityEdit.error")
                    }
                }
                Section {
                    TextField(ActivityDetailMessages.titleField, text: $form.title)
                        .accessibilityIdentifier("activityEdit.title")
                    TextField(ActivityDetailMessages.descriptionField, text: $form.description, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .accessibilityIdentifier("activityEdit.description")
                }
                Section {
                    Picker(ActivityDetailMessages.sportField, selection: $form.sport) {
                        ForEach(form.sports, id: \.self) { sport in
                            Text(ActivityFormatters.sportLabel(sport)).tag(sport)
                        }
                    }
                    .accessibilityIdentifier("activityEdit.sport")
                    Picker(ActivityDetailMessages.visibilityField, selection: $form.visibility) {
                        ForEach(ActivityVisibility.allCases, id: \.self) { visibility in
                            Text(ActivityDetailMessages.visibilityLabel(visibility)).tag(visibility)
                        }
                    }
                    .accessibilityIdentifier("activityEdit.visibility")
                }
            }
            .navigationTitle(ActivityDetailMessages.editTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ActivityDetailMessages.cancel, action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(ActivityDetailMessages.save) { onSave(form) }
                        .disabled(!form.canSave)
                        .accessibilityIdentifier("activityEdit.save")
                }
            }
        }
    }
}

extension View {
    /// Presents `editor`'s sheet and its toast over this screen (ADR-033 §7).
    func activityEditing(_ editor: ActivityEditor) -> some View {
        modifier(ActivityEditingModifier(editor: editor))
    }
}

private struct ActivityEditingModifier: ViewModifier {
    @Bindable var editor: ActivityEditor

    func body(content: Content) -> some View {
        content
            .sheet(item: $editor.form) { form in
                ActivityEditSheet(
                    form: form,
                    onSave: { submitted in Task { await editor.save(submitted) } },
                    onCancel: editor.cancel
                )
            }
            .toast($editor.toast)
    }
}
