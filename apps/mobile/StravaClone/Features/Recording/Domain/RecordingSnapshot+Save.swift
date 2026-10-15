import Foundation

extension RecordingSnapshot {
    /// The local Activity saved from the finish screen (ADR-031 §11): same UUID, sport and
    /// Start; `endedAt` = start of the final Pause, which is not sent; provisional values
    /// (distance, timer as moving time, total time), no elevation gain. An empty title falls
    /// back to the default one. `nil` while Save is disabled.
    func localActivity(title: String, visibility: ActivityVisibility, timeZone: TimeZone = .current) -> LocalActivity? {
        guard saveBlocker == nil, let endedAt = recording.endedAt else { return nil }
        let moving = recording.elapsed(at: endedAt)
        let movingSeconds = Double(moving.components.seconds) + Double(moving.components.attoseconds) / 1e18
        return LocalActivity(
            id: recording.id,
            sport: recording.sport.sportType,
            title: DefaultActivityTitle.resolve(title, sport: recording.sport, startedAt: recording.startedAt, timeZone: timeZone),
            visibility: visibility,
            startedAt: recording.startedAt,
            endedAt: endedAt,
            distance: distance,
            movingTimeS: Int(movingSeconds.rounded()),
            elapsedTimeS: Int(endedAt.timeIntervalSince(recording.startedAt).rounded())
        )
    }
}
