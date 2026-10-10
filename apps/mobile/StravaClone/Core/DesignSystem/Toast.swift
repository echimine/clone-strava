import SwiftUI

extension View {
    /// Short message at the bottom of the screen, dismissed after `duration` or on tap.
    func toast(_ message: Binding<String?>, duration: Duration = .seconds(2.5)) -> some View {
        modifier(ToastModifier(message: message, duration: duration))
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var message: String?
    let duration: Duration

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, Theme.spacing)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(radius: 4)
                        .padding(.bottom, 24)
                        .onTapGesture { self.message = nil }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .accessibilityIdentifier("toast")
                        .task(id: message) {
                            try? await Task.sleep(for: duration)
                            guard !Task.isCancelled else { return }
                            self.message = nil
                        }
                }
            }
            .animation(.default, value: message)
    }
}
