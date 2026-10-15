import Foundation

/// One line of the journal (JSON Lines in Documents/journal.jsonl, exportable from the app).
/// `t` is when the app received the event, in seconds since 1970.
struct Event: Codable {
    var t: Double = Date().timeIntervalSince1970
    var kind: String // launch, session_start, session_stop, loc, update, motion, motion_hist, battery, marker, scene, note, error
    var appState: String?
    var sport: String?
    // loc / update
    var ts: Double? // CLLocation.timestamp
    var lat: Double?
    var lon: Double?
    var hAcc: Double?
    var spd: Double?
    var spdAcc: Double?
    var stationary: Bool? // isStationary (iOS 17 API)
    var flags: [String]? // iOS 18 CLLocationUpdate properties set to true
    // motion
    var activity: String?
    var confidence: Int? // 0 low, 1 medium, 2 high
    var start: Double? // CMMotionActivity.startDate
    // battery
    var level: Float?
    var batteryState: String?
    var thermal: String?
    // marker
    var mark: String? // stop / go
    var source: String? // écran / raccourci
    var text: String?

    var isMovingFix: Bool { kind == "loc" && (spd ?? -1) >= Summary.movingSpeed }
}

@MainActor
final class EventLog: ObservableObject {
    static let shared = EventLog()

    @Published private(set) var events: [Event] = []
    let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("journal.jsonl")
    private let encoder = JSONEncoder()

    private init() {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        events = text.split(separator: "\n").compactMap { try? decoder.decode(Event.self, from: Data($0.utf8)) }
    }

    func append(_ event: Event) {
        events.append(event)
        guard var line = try? encoder.encode(event) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    func note(_ text: String, kind: String = "note") {
        append(Event(kind: kind, appState: AppState.current, text: text))
    }

    func clear() {
        events = []
        try? FileManager.default.removeItem(at: url)
    }

    /// Events of the last session (from its `session_start`), or nothing before the first one.
    var currentSession: ArraySlice<Event> {
        guard let start = events.lastIndex(where: { $0.kind == "session_start" }) else { return [] }
        return events[start...]
    }
}

enum Clock {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.S"
        return f
    }()

    static func string(_ t: Double) -> String { formatter.string(from: Date(timeIntervalSince1970: t)) }
}
