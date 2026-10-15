import SwiftUI

struct ContentView: View {
    @ObservedObject private var probe = Probe.shared
    @ObservedObject private var log = EventLog.shared
    @State private var confirmClear = false

    var body: some View {
        NavigationStack {
            List {
                sessionSection
                markerSection
                liveSection
                resultsSection
                journalSection
            }
            .navigationTitle("Pause Probe")
        }
    }

    private var sessionSection: some View {
        Section("Session (liveUpdates .fitness + CLBackgroundActivitySession)") {
            Picker("Sport", selection: $probe.sport) {
                ForEach(Sport.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(probe.isRunning)
            Button(probe.isRunning ? "Arrêter la session" : "Démarrer la session") {
                probe.isRunning ? probe.stop() : probe.start()
            }
            .font(.headline)
            if let start = log.currentSession.first, probe.isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("Durée : \(Self.duration(context.date.timeIntervalSince1970 - start.t))")
                        .monospacedDigit()
                }
            }
            if let battery = Summary.battery(in: log.currentSession) {
                Text(String(format: "Batterie : %.0f %% → %.0f %% en %.2f h", battery.startLevel * 100,
                            battery.lastLevel * 100, battery.hours)
                     + (battery.percentPerHour.map { String(format: " · %.1f %%/h", $0) } ?? ""))
                    .font(.callout)
            }
        }
    }

    private var markerSection: some View {
        Section("Marqueurs (vérité terrain)") {
            HStack(spacing: 12) {
                markerButton("Je m'arrête", mark: "stop", color: .red)
                markerButton("Je repars", mark: "go", color: .green)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            Text("Aussi via le bouton Action ou « Toucher le dos » : raccourci « Marquer arrêt / reprise ».")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func markerButton(_ title: String, mark: String, color: Color) -> some View {
        Button { probe.mark(mark, source: "écran") } label: {
            Text(title)
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 80)
                .background(color.opacity(probe.lastMark == mark ? 0.25 : 0.8))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(!probe.isRunning)
    }

    private var liveSection: some View {
        Section("En direct") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 4) {
                    if let update = probe.lastUpdate {
                        let age = context.date.timeIntervalSince1970 - update.t
                        Text(String(format: "Dernière mise à jour il y a %.0f s", age))
                        Text("isStationary : \(update.stationary == true ? "OUI" : "non")"
                             + (update.flags.map { " · \($0.joined(separator: ", "))" } ?? ""))
                        if let speed = update.spd, let accuracy = update.hAcc {
                            Text(String(format: "Vitesse %.1f m/s · précision %.0f m", speed, accuracy))
                        }
                    } else {
                        Text("Aucune mise à jour de position")
                    }
                    Text("Core Motion : " + (probe.lastMotion.map {
                        "\($0.activity ?? "?") (confiance \($0.confidence ?? -1))"
                    } ?? "—"))
                }
                .font(.callout.monospacedDigit())
            }
        }
    }

    private var resultsSection: some View {
        Section("Délais depuis chaque marqueur (session en cours)") {
            let results = Summary.markers(in: log.currentSession)
            if results.isEmpty { Text("Aucun marqueur").foregroundStyle(.secondary) }
            ForEach(results.reversed()) { result in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(result.mark == "stop" ? "■ Arrêt" : "▶ Reprise") à \(Clock.string(result.t))")
                        .font(.subheadline.bold())
                    ForEach(result.rows) { row in
                        HStack {
                            Text(row.label)
                            Spacer()
                            Text(row.seconds.map { String(format: "%+.1f s", $0) } ?? "—")
                        }
                        .font(.caption.monospacedDigit())
                    }
                }
            }
        }
    }

    private var journalSection: some View {
        Section {
            ForEach(Array(log.events.suffix(40).reversed().enumerated()), id: \.offset) { _, event in
                Text(Self.line(event)).font(.caption2.monospaced())
            }
        } header: {
            HStack {
                Text("Journal (\(log.events.count))")
                Spacer()
                ShareLink("Exporter", item: log.url)
                Button("Effacer", role: .destructive) { confirmClear = true }
                    .disabled(probe.isRunning)
            }
        }
        .confirmationDialog("Effacer tout le journal ?", isPresented: $confirmClear) {
            Button("Effacer", role: .destructive) { log.clear() }
        }
    }

    private static func line(_ e: Event) -> String {
        var parts = [Clock.string(e.t), e.kind, e.appState ?? ""]
        switch e.kind {
        case "loc", "update":
            if let spd = e.spd { parts.append(String(format: "%.1f m/s ±%.0f m", spd, e.hAcc ?? -1)) }
            if e.stationary == true { parts.append("STATIONARY") }
            if let flags = e.flags { parts.append(flags.joined(separator: ",")) }
        case "motion", "motion_hist":
            parts.append("\(e.activity ?? "?") c\(e.confidence ?? -1) depuis \(e.start.map(Clock.string) ?? "?")")
        case "battery":
            parts.append(String(format: "%.0f %% %@ %@", (e.level ?? -1) * 100, e.batteryState ?? "", e.thermal ?? ""))
        case "marker":
            parts.append("\(e.mark ?? "?") (\(e.source ?? "?"))")
        default:
            if let sport = e.sport { parts.append(sport) }
            if let text = e.text { parts.append(text) }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func duration(_ seconds: Double) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
    }
}
