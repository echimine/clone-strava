import Foundation

/// Polls `condition` until it holds or about two seconds have passed (a red test must not hang
/// the run).
@MainActor
func eventually(_ condition: () async throws -> Bool) async rethrows -> Bool {
    for _ in 0 ..< 200 {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return try await condition()
}
