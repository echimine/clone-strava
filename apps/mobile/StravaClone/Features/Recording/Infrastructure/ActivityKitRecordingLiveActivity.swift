import ActivityKit
import Foundation

/// The Live Activity of a Recording through ActivityKit (ADR-031 §9, §15): local updates only,
/// drawn by the widget extension from `RecordingActivityAttributes`. Every failure is swallowed:
/// the Recording goes on without it.
///
/// Not an actor: `Activity` is not `Sendable`, so each call looks it up again by id from a
/// nonisolated context; the id sits behind a lock. Calls arrive one at a time from
/// `RecordingLiveActivityUpdater`.
final class ActivityKitRecordingLiveActivity: RecordingLiveActivity, @unchecked Sendable {
    private let lock = NSLock()
    private var _activityID: String?

    private var activityID: String? {
        get { lock.withLock { _activityID } }
        set { lock.withLock { _activityID = newValue } }
    }

    func endAll() async {
        let kept = activityID
        for leftover in Activity<RecordingActivityAttributes>.activities where leftover.id != kept {
            await leftover.end(nil, dismissalPolicy: .immediate)
        }
    }

    func start(_ content: RecordingLiveActivityContent, staleDate: Date) async -> Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        do {
            let activity = try Activity.request(
                attributes: RecordingActivityAttributes(content),
                content: ActivityContent(state: .init(content), staleDate: staleDate),
                pushType: nil
            )
            activityID = activity.id
            return true
        } catch {
            return false
        }
    }

    func update(_ content: RecordingLiveActivityContent, staleDate: Date) async {
        let id = activityID
        guard let activity = Activity<RecordingActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(ActivityContent(state: .init(content), staleDate: staleDate))
    }

    func end(final content: RecordingLiveActivityContent?) async {
        let id = activityID
        activityID = nil
        guard let activity = Activity<RecordingActivityAttributes>.activities.first(where: { $0.id == id }) else { return }
        if let content {
            await activity.end(ActivityContent(state: .init(content), staleDate: nil), dismissalPolicy: .default)
        } else {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

extension RecordingActivityAttributes {
    init(_ content: RecordingLiveActivityContent) {
        self.init(
            sportName: ActivityFormatters.sportLabel(content.sport.sportType),
            sportSymbol: ActivityFormatters.sportSymbol(content.sport.sportType),
            showsPace: content.sport.isOnFoot
        )
    }
}

extension RecordingActivityAttributes.ContentState {
    init(_ content: RecordingLiveActivityContent) {
        self.init(
            timerStart: content.timerStart,
            pausedAt: content.pausedAt,
            distanceM: content.distance.meters,
            averagePaceS: content.averagePace.map {
                Int((Double($0.components.seconds) + Double($0.components.attoseconds) / 1e18).rounded())
            },
            currentSpeedKmh: content.currentSpeedMs.map { $0 * 3.6 },
            averageSpeedKmh: content.averageSpeedMs * 3.6,
            itinerary: content.itinerary.map(RecordingActivityAttributes.Itinerary.init),
            isSaved: content.isSaved
        )
    }
}

extension RecordingActivityAttributes.Itinerary {
    init(_ itinerary: RecordingLiveActivityContent.Itinerary) {
        self.init(
            name: itinerary.name,
            remainingM: itinerary.remaining?.meters,
            fraction: itinerary.fraction,
            state: itinerary.state
        )
    }
}
