import Foundation

/// Small lock-protected box for a value mutated from inside a `@Sendable` closure in a
/// test (ADR-025 §3) — e.g. asserting a fake's handler was called.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        get { lock.withLock { _value } }
        set { lock.withLock { _value = newValue } }
    }
}
