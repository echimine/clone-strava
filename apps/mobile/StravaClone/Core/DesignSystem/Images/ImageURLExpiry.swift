import SwiftUI

/// Turns the `403`s of expired pre-signed image URLs (ADR-037 §1) into one reload of the
/// screen: the signals of every image of the screen collapse into a single reload, and a
/// new reload waits for a cooldown, so URLs that still answer `403` once fresh cannot make
/// the screen reload in a loop.
@MainActor
final class ImageURLExpiryReloader {
    private let cooldown: TimeInterval
    private let now: () -> Date
    private var lastReload: Date?
    private var reload: Task<Void, Never>?

    init(cooldown: TimeInterval = 30, now: @escaping () -> Date = Date.init) {
        self.cooldown = cooldown
        self.now = now
    }

    /// Runs `perform` unless a reload is running or started less than `cooldown` ago.
    func imageURLExpired(perform: @escaping @MainActor () async -> Void) {
        guard reload == nil else { return }
        if let lastReload, now().timeIntervalSince(lastReload) < cooldown { return }
        lastReload = now()
        reload = Task {
            await perform()
            reload = nil
        }
    }

    /// Waits for the running reload, if any (tests).
    func waitForReload() async {
        await reload?.value
    }
}

/// What `RemoteImage` calls when its URL answers `403`. Set by `onImageURLExpired`.
struct ImageURLExpiredAction {
    fileprivate let handler: @MainActor () -> Void

    @MainActor func callAsFunction() {
        handler()
    }
}

extension EnvironmentValues {
    /// No-op outside a screen that handles expired image URLs.
    @Entry var imageURLExpired = ImageURLExpiredAction(handler: {})
}

extension View {
    /// Reloads the screen when one of the `RemoteImage`s inside answers `403` (expired
    /// pre-signed URL, ADR-037 §1), so it gets fresh URLs. Several expired images reload
    /// once; the innermost screen handling it wins.
    func onImageURLExpired(perform reload: @escaping @MainActor () async -> Void) -> some View {
        modifier(ImageURLExpiryModifier(reload: reload))
    }
}

private struct ImageURLExpiryModifier: ViewModifier {
    let reload: @MainActor () async -> Void
    @State private var reloader = ImageURLExpiryReloader()

    func body(content: Content) -> some View {
        let reloader = reloader
        let reload = reload
        content.environment(\.imageURLExpired, ImageURLExpiredAction {
            reloader.imageURLExpired(perform: reload)
        })
    }
}
