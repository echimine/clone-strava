import Foundation
@testable import StravaClone

/// Fake `SubscriberIdentity` (ADR-025 §3): records who RevenueCat was told about.
final class FakeSubscriberIdentity: SubscriberIdentity, @unchecked Sendable {
    enum Call: Equatable {
        case logIn(userId: String)
        case logOut
    }

    private let recorded = Locked<[Call]>([])
    var calls: [Call] { recorded.value }

    func logIn(userId: String) {
        recorded.value.append(.logIn(userId: userId))
    }

    func logOut() {
        recorded.value.append(.logOut)
    }
}
