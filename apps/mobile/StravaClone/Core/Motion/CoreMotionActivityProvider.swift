import CoreMotion
import Foundation

/// `MotionActivityProvider` on `CMMotionActivityManager` (ADR-031 §4, `NSMotionUsageDescription`).
/// Readings are only delivered while the app runs: none while it is suspended.
final class CoreMotionActivityProvider: MotionActivityProvider, @unchecked Sendable {
    // CMMotionActivityManager is not Sendable; it is only touched on `queue`'s callbacks
    // and through its own thread-safe start / stop calls.
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "CoreMotionActivityProvider"
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    func requestAuthorization() async -> Bool {
        guard CMMotionActivityManager.isActivityAvailable() else { return false }
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:
            return true
        case .notDetermined:
            // A first query shows the system prompt; the answer is known when it returns.
            let manager = CMMotionActivityManager()
            let now = Date()
            return await withCheckedContinuation { continuation in
                manager.queryActivityStarting(from: now.addingTimeInterval(-60), to: now, to: queue) { _, _ in
                    continuation.resume(returning: CMMotionActivityManager.authorizationStatus() == .authorized)
                }
            }
        default:
            return false
        }
    }

    func readings() async -> AsyncStream<MotionReading> {
        let (stream, continuation) = AsyncStream<MotionReading>.makeStream(bufferingPolicy: .unbounded)
        guard CMMotionActivityManager.isActivityAvailable() else {
            continuation.finish()
            return stream
        }
        let manager = ManagerBox()
        manager.value.startActivityUpdates(to: queue) { activity in
            guard let activity else { return }
            continuation.yield(MotionReading(activity))
        }
        continuation.onTermination = { _ in
            manager.value.stopActivityUpdates()
        }
        return stream
    }
}

private final class ManagerBox: @unchecked Sendable {
    let value = CMMotionActivityManager()
}

private extension MotionReading {
    init(_ activity: CMMotionActivity) {
        let kind: MotionActivity = if activity.running {
            .running
        } else if activity.walking {
            .walking
        } else if activity.stationary, !activity.automotive, !activity.cycling {
            .stationary
        } else {
            .other
        }
        let confidence: MotionConfidence = switch activity.confidence {
        case .high: .high
        case .medium: .medium
        default: .low
        }
        self.init(activity: kind, confidence: confidence, startDate: activity.startDate)
    }
}
