import Foundation
import Network
import Observation

struct ConnectivityStatus: Equatable, Sendable {
    var isConnected: Bool
    var isExpensive: Bool
    var isConstrained: Bool

    static let unknown = ConnectivityStatus(isConnected: true, isExpensive: false, isConstrained: false)
}

/// NWPathMonitor wrapper (ADR-006): observable state for the UI and an AsyncStream
/// to trigger the sync queue. A network route does not mean the API is reachable.
@Observable
@MainActor
final class ConnectivityMonitor {
    private(set) var status = ConnectivityStatus.unknown

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private var continuations: [UUID: AsyncStream<ConnectivityStatus>.Continuation] = [:]

    func start() {
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let status = ConnectivityStatus(
                isConnected: path.status == .satisfied,
                isExpensive: path.isExpensive,
                isConstrained: path.isConstrained
            )
            Task { @MainActor [weak self] in self?.publish(status) }
        }
        monitor.start(queue: DispatchQueue(label: "fr.echimine.stravaclone.connectivity"))
    }

    func stop() {
        monitor.cancel()
    }

    func updates() -> AsyncStream<ConnectivityStatus> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ConnectivityStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.yield(status)
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { @MainActor [weak self] in self?.continuations[id] = nil }
        }
        continuations[id] = continuation
        return stream
    }

    private func publish(_ newStatus: ConnectivityStatus) {
        guard newStatus != status else { return }
        status = newStatus
        for continuation in continuations.values {
            continuation.yield(newStatus)
        }
    }
}
