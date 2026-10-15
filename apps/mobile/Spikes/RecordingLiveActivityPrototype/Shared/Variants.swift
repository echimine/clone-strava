// PROTOTYPE — throwaway (wayfinder #43, ticket #53). Never merged.
// A: like Strava, no control, three stats in a row; tapping opens the app.
// B: mirrors the Recording screen (big chrono, one round Pause / Reprendre button via LiveActivityIntent).
// C: the Itinerary first (remaining distance and progress), distance-first without one; no control.
// Shared by the widget (real Live Activity) and the app (side-by-side gallery).

import AppIntents
import SwiftUI

typealias LAState = RecordingActivityAttributes.ContentState

/// Every presentation of every variant, picked by `variant`.
enum Parts {
    @ViewBuilder static func lock(_ v: ProtoVariant, _ sport: ProtoSport, _ s: LAState) -> some View {
        switch v.source(.lock) {
        case .A: VariantA.Lock(sport: sport, s: s)
        case .B: VariantB.Lock(sport: sport, s: s)
        case .C: VariantC.Lock(sport: sport, s: s)
        }
    }

    @ViewBuilder static func compactLeading(_ v: ProtoVariant, _ sport: ProtoSport, _ s: LAState) -> some View {
        switch v.source(.compact) {
        case .A:
            Image(systemName: s.isPaused ? "pause.fill" : sport.symbol)
                .foregroundStyle(s.isPaused ? Fmt.pause : Fmt.accent)
        case .B:
            Text("\(Fmt.kmShort(s.distanceMeters)) km").font(.caption.bold().monospacedDigit())
                .foregroundStyle(Fmt.accent)
        case .C:
            if let it = s.itinerary {
                Ring(fraction: it.fraction)
            } else {
                Image(systemName: sport.symbol).foregroundStyle(Fmt.accent)
            }
        }
    }

    @ViewBuilder static func compactTrailing(_ v: ProtoVariant, _ sport: ProtoSport, _ s: LAState) -> some View {
        switch v.source(.compact) {
        case .A, .B:
            Chrono(s: s).frame(maxWidth: 56).multilineTextAlignment(.trailing)
                .foregroundStyle(s.isPaused ? Fmt.pause : .white)
        case .C:
            Group {
                if let it = s.itinerary, it.status != .notYetSnapped {
                    Text("\(Fmt.kmShort(it.remainingMeters)) km")
                } else if s.itinerary != nil {
                    Text("—")
                } else {
                    Text("\(Fmt.kmShort(s.distanceMeters)) km")
                }
            }
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(s.isPaused ? Fmt.pause : .white)
        }
    }

    @ViewBuilder static func minimal(_ v: ProtoVariant, _ sport: ProtoSport, _ s: LAState) -> some View {
        switch v.source(.compact) {
        case .A:
            Image(systemName: s.isPaused ? "pause.fill" : sport.symbol)
                .foregroundStyle(s.isPaused ? Fmt.pause : Fmt.accent)
        case .B:
            Image(systemName: s.isPaused ? "pause.fill" : "record.circle")
                .foregroundStyle(s.isPaused ? Fmt.pause : Fmt.accent)
        case .C:
            if let it = s.itinerary {
                Ring(fraction: it.fraction, size: 16)
            } else {
                Image(systemName: sport.symbol).foregroundStyle(Fmt.accent)
            }
        }
    }

    @ViewBuilder static func expandedLeading(_ v: ProtoVariant, _ sport: ProtoSport, _ s: LAState) -> some View {
        switch v.source(.expanded) {
        case .A:
            VStack(alignment: .leading) {
                Text("Temps").font(.caption2).foregroundStyle(.secondary)
                Chrono(s: s).font(.title2.bold())
            }
        case .B:
            Chrono(s: s).font(.system(size: 30, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(s.isPaused ? Fmt.pause : .white)
        case .C:
            EmptyView()
        }
    }

    @ViewBuilder static func expandedTrailing(_ v: ProtoVariant, _ sport: ProtoSport, _ s: LAState) -> some View {
        switch v.source(.expanded) {
        case .A:
            VStack(alignment: .trailing) {
                Text("Distance").font(.caption2).foregroundStyle(.secondary)
                Text("\(Fmt.km(s.distanceMeters)) km").font(.title2.bold().monospacedDigit())
            }
        case .B:
            VariantB.PauseButton(isPaused: s.isPaused, size: 44)
        case .C:
            EmptyView()
        }
    }

    @ViewBuilder static func expandedCenter(_ v: ProtoVariant, _ sport: ProtoSport, _ s: LAState) -> some View {
        switch v.source(.expanded) {
        case .A, .B:
            EmptyView()
        case .C:
            if let it = s.itinerary {
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        RemainingText(it: it).font(.title.bold().monospacedDigit())
                        Text(it.status == .onTrack ? "restants" : remainingCaption(it))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    VariantC.Track(fraction: it.fraction, symbol: sport.symbol, dimmed: it.status == .offTrack)
                }
                .padding(.horizontal, 12)
            } else {
                Text("\(Fmt.km(s.distanceMeters)) km").font(.title.bold().monospacedDigit())
            }
        }
    }

    @ViewBuilder static func expandedBottom(_ v: ProtoVariant, _ sport: ProtoSport, _ s: LAState) -> some View {
        let stat = SportStat(sport: sport, s: s)
        switch v.source(.expanded) {
        case .A:
            HStack {
                Text("\(stat.label) \(stat.value) \(stat.unit)").font(.caption.monospacedDigit())
                Spacer()
                if let it = s.itinerary {
                    Text(remainingCaption(it)).font(.caption2).foregroundStyle(.secondary)
                    RemainingText(it: it).font(.caption.bold().monospacedDigit())
                }
                if s.isPaused { PausePill() }
            }
        case .B:
            HStack {
                Text("\(Fmt.km(s.distanceMeters)) km · \(stat.value) \(stat.unit)").font(.callout.monospacedDigit())
                Spacer()
                if let it = s.itinerary {
                    RemainingText(it: it).font(.caption.bold().monospacedDigit())
                    Text("restants").font(.caption2).foregroundStyle(.secondary)
                }
            }
        case .C:
            HStack {
                Chrono(s: s).frame(maxWidth: 80, alignment: .leading)
                Spacer()
                if s.itinerary != nil { Text("\(Fmt.km(s.distanceMeters)) km") }
                Spacer()
                Text("\(stat.value) \(stat.unit)")
                if s.isPaused { PausePill() }
            }
            .font(.callout.monospacedDigit())
            // Keeps the chrono and the unit clear of the island's rounded corners.
            .padding(.horizontal, 12)
        }
    }

    static func lockTint(_ s: LAState) -> Color {
        if s.variant == .B && s.isPaused && s.ending == nil { return Color(red: 0.25, green: 0.22, blue: 0.05) }
        return Color.black.opacity(0.85)
    }
}

// MARK: - A · Façon Strava, sans bouton

enum VariantA {
    struct Lock: View {
        let sport: ProtoSport
        let s: LAState

        var body: some View {
            let stat = SportStat(sport: sport, s: s)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: sport.symbol).foregroundStyle(Fmt.accent)
                    Text(sport.label).font(.caption.bold())
                    Spacer()
                    if s.isPaused { PausePill() }
                }
                HStack(alignment: .top) {
                    column("Temps") { Chrono(s: s) }
                    column("Distance") { Text("\(Fmt.km(s.distanceMeters)) km") }
                    column(stat.label) { Text("\(stat.value) \(stat.unit)") }
                }
                if let it = s.itinerary {
                    HStack(spacing: 8) {
                        Text(remainingCaption(it)).font(.caption2).foregroundStyle(.white.opacity(0.7))
                        RemainingText(it: it).font(.caption.bold().monospacedDigit())
                        ProgressView(value: it.fraction).tint(Fmt.accent)
                    }
                }
            }
        }

        private func column(_ label: String, @ViewBuilder value: () -> some View) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption2).foregroundStyle(.white.opacity(0.7))
                value().font(.title3.bold().monospacedDigit()).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - B · Miroir de l'écran + bouton Pause

enum VariantB {
    struct Lock: View {
        let sport: ProtoSport
        let s: LAState

        var body: some View {
            let stat = SportStat(sport: sport, s: s)
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if s.isPaused {
                        Text("EN PAUSE").font(.caption.bold()).foregroundStyle(Fmt.pause)
                    } else {
                        Label(sport.label, systemImage: sport.symbol).font(.caption.bold()).foregroundStyle(Fmt.accent)
                    }
                    Chrono(s: s).font(.system(size: 40, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.6)
                    Text("\(Fmt.km(s.distanceMeters)) km · \(stat.value) \(stat.unit)")
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
                    if let it = s.itinerary {
                        HStack(spacing: 4) {
                            RemainingText(it: it).font(.caption.bold().monospacedDigit())
                            Text(it.status == .onTrack ? "restants" : "· \(remainingCaption(it))")
                                .font(.caption).foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                Spacer(minLength: 0)
                PauseButton(isPaused: s.isPaused, size: 64)
            }
        }
    }

    struct PauseButton: View {
        let isPaused: Bool
        let size: CGFloat

        var body: some View {
            Button(intent: TogglePauseIntent()) {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: size, height: size)
                    .background(Circle().fill(isPaused ? Fmt.pause : Fmt.accent))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPaused ? "Reprendre" : "Pause")
        }
    }
}

// MARK: - C · Itinéraire d'abord

enum VariantC {
    struct Lock: View {
        let sport: ProtoSport
        let s: LAState

        var body: some View {
            let stat = SportStat(sport: sport, s: s)
            VStack(alignment: .leading, spacing: 8) {
                if let it = s.itinerary {
                    HStack {
                        Text(it.status == .onTrack ? it.name : remainingCaption(it))
                            .font(.caption.bold())
                            .foregroundStyle(it.status == .offTrack ? Fmt.pause : .white.opacity(0.8))
                        Spacer()
                        if s.isPaused { PausePill() }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        RemainingText(it: it).font(.system(size: 38, weight: .heavy).monospacedDigit())
                        Text("restants").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                    }
                    Track(fraction: it.fraction, symbol: sport.symbol, dimmed: it.status == .offTrack)
                } else {
                    HStack {
                        Label(sport.label, systemImage: sport.symbol).font(.caption.bold()).foregroundStyle(Fmt.accent)
                        Spacer()
                        if s.isPaused { PausePill() }
                    }
                    Text("\(Fmt.km(s.distanceMeters)) km").font(.system(size: 38, weight: .heavy).monospacedDigit())
                }
                HStack(spacing: 14) {
                    Chrono(s: s).frame(maxWidth: 80, alignment: .leading)
                    if s.itinerary != nil { Text("\(Fmt.km(s.distanceMeters)) km") }
                    Text("\(stat.value) \(stat.unit)")
                }
                .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
            }
        }
    }

    /// Start-to-finish bar with the athlete's sport icon at their progression.
    struct Track: View {
        let fraction: Double
        let symbol: String
        let dimmed: Bool

        var body: some View {
            GeometryReader { geo in
                let x = max(10, min(geo.size.width - 10, geo.size.width * fraction))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2)).frame(height: 6)
                    Capsule().fill(dimmed ? Color.gray : Fmt.accent).frame(width: x, height: 6)
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(dimmed ? Fmt.pause : .white))
                        .position(x: x, y: 10)
                    Image(systemName: "flag.checkered").font(.caption2)
                        .position(x: geo.size.width - 6, y: -4)
                }
            }
            .frame(height: 20)
        }
    }
}

// MARK: - Shared pieces

/// Running variant, or the shared stale / ended renderings (only the running layout is being compared).
struct LockScreenContent: View {
    let sport: ProtoSport
    let s: LAState
    let isStale: Bool

    var body: some View {
        Group {
            if let ending = s.ending {
                EndedView(sport: sport, s: s, ending: ending)
            } else if isStale {
                StaleView(sport: sport, s: s)
            } else {
                Parts.lock(s.variant, sport, s)
            }
        }
        .foregroundStyle(.white)
    }
}

struct Chrono: View {
    let s: LAState
    var body: some View {
        Text(timerInterval: s.chronoStart...Date.distantFuture, pauseTime: s.pausedAt, countsDown: false, showsHours: true)
            .monospacedDigit()
    }
}

/// Allure moyenne on foot, current speed on a bike (« Stats affichées pendant une Recording selon le sport »).
struct SportStat {
    let label: String
    let value: String
    let unit: String

    init(sport: ProtoSport, s: LAState) {
        if sport.isOnFoot {
            label = "Allure moy."; value = Fmt.pace(s.avgPaceSecondsPerKm); unit = "/km"
        } else {
            label = "Vitesse"; value = Fmt.speed(s.currentSpeedKmh); unit = "km/h"
        }
    }
}

struct PausePill: View {
    var body: some View {
        Text("EN PAUSE")
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(Fmt.pause))
            .foregroundStyle(.black)
    }
}

struct RemainingText: View {
    let it: RecordingActivityAttributes.ItineraryProgress
    var body: some View {
        if it.status == .notYetSnapped {
            Text("—")
        } else {
            Text("\(Fmt.km(it.remainingMeters)) km")
        }
    }
}

/// « Restant sur l'Itinéraire », replaced by the state wording when there is one (screen variant A, #50).
func remainingCaption(_ it: RecordingActivityAttributes.ItineraryProgress) -> String {
    switch it.status {
    case .onTrack: "Restant sur l'Itinéraire"
    case .notYetSnapped: "Pas encore sur l'Itinéraire"
    case .offTrack: "Hors Itinéraire"
    case .rerouted: "Chemin recalculé"
    case .finished: "Itinéraire terminé"
    }
}

struct Ring: View {
    let fraction: Double
    var size: CGFloat = 18
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.25), lineWidth: 3)
            Circle().trim(from: 0, to: fraction)
                .stroke(Fmt.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
    }
}

struct StaleView: View {
    let sport: ProtoSport
    let s: LAState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text("Enregistrement interrompu").font(.headline)
            }
            Text("\(sport.label) · \(Fmt.km(s.distanceMeters)) km au dernier point")
                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            Text("Ouvre l'app pour reprendre ta Recording.").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EndedView: View {
    let sport: ProtoSport
    let s: LAState
    let ending: RecordingActivityAttributes.Ending
    var body: some View {
        let stat = SportStat(sport: sport, s: s)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("\(sport.label) enregistrée").font(.headline)
            }
            Text("\(Fmt.duration(ending.movingSeconds)) · \(Fmt.km(s.distanceMeters)) km · \(stat.value) \(stat.unit)")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.white.opacity(0.85))
            Text("Envoi en cours, elle apparaîtra dans ton flux.").font(.caption).foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
