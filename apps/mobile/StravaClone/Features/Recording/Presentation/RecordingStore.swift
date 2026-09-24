import Foundation
import Observation

@Observable
@MainActor
final class RecordingStore {
    enum State: Equatable {
        case idle
        case recording(ActiveRecording)
        case failed(String)
    }

    private(set) var state = State.idle

    @ObservationIgnored private let service: RecordingService
    @ObservationIgnored private var observation: Task<Void, Never>?

    init(service: RecordingService) {
        self.service = service
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    func start() async {
        do {
            let updates = try await service.start()
            observation = Task { [weak self] in
                for await recording in updates {
                    self?.state = .recording(recording)
                }
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func stop() async {
        observation?.cancel()
        observation = nil
        do {
            try await service.stop()
            state = .idle
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
