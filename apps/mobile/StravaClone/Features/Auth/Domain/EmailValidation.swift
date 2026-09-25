import Foundation

/// Basic client-side email shape check (ADR-022): catches obvious typos before a
/// network round-trip, not a substitute for the backend's own validation.
enum EmailValidation {
    static func isValid(_ email: String) -> Bool {
        (try? /^[^\s@]+@[^\s@]+\.[^\s@]+$/.wholeMatch(in: email)) != nil
    }
}
