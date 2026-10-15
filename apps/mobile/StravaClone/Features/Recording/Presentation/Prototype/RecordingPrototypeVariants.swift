// PROTOTYPE — throwaway (wayfinder #43, ticket #50 « Écran d'une Recording en cours »).
// A: stats full screen (Strava), map one tap away; Terminer only reachable in Pause.
// B: map always full screen, glass panel at the bottom, tab bar kept; Terminer by long press.
// C: fixed split, map on top and stats list below; Terminer behind a confirmation.

import SwiftUI

private let pauseTint = Color(red: 1, green: 0.78, blue: 0.2)

// MARK: - A · Stats d'abord, bascule carte

struct RecordingVariantA: View {
    let sim: RecordingPrototypeSimulation
    let onFinish: () -> Void
    @State private var showsMap = false

    var body: some View {
        ZStack {
            if showsMap {
                RecordingPrototypeMap(sim: sim).ignoresSafeArea()
                    .overlay(alignment: .top) { compactStrip.padding(.top, 48) }
            } else {
                statsPage
            }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .toolbar(.hidden, for: .tabBar)
        .animation(.snappy, value: sim.phase)
    }

    private var statsPage: some View {
        let stats = RecordingStat.all(sim)
        return VStack(spacing: 0) {
            HStack {
                Label(ActivityFormatters.sportLabel(sim.sport), systemImage: ActivityFormatters.sportSymbol(sim.sport))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                RecordingGPSChip(gps: sim.gps)
                if sim.hasItinerary {
                    Menu {
                        Button("Retirer l'Itinéraire", systemImage: "xmark", role: .destructive, action: { sim.removeItinerary() })
                    } label: {
                        Image(systemName: "ellipsis.circle").font(.title2)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 52)

            if let banner = sim.pauseBannerText {
                Text(banner.uppercased())
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(pauseTint)
                    .foregroundStyle(.black)
                    .padding(.top, 12)
            }

            Spacer()
            bigStat(stats[0], size: 60)
            Divider().padding(.horizontal, 40).padding(.vertical, 18)
            bigStat(stats[1], size: 88)
            Divider().padding(.horizontal, 40).padding(.vertical, 18)
            HStack {
                ForEach(stats.dropFirst(2)) { bigStat($0, size: 44).frame(maxWidth: .infinity) }
            }
            if sim.hasItinerary {
                Divider().padding(.horizontal, 40).padding(.vertical, 18)
                remaining
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(sim.isPaused ? pauseTint.opacity(0.12) : Color(.systemBackground))
    }

    private func bigStat(_ stat: RecordingStat, size: CGFloat) -> some View {
        VStack(spacing: 2) {
            Text(stat.value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(stat.unit.isEmpty ? stat.label : "\(stat.label) (\(stat.unit))")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    private var remaining: some View {
        VStack(spacing: 6) {
            Text("\(sim.remainingText) km")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(sim.itineraryCaption ?? "Restant sur l'Itinéraire")
                .font(.footnote.weight(.medium))
                .foregroundStyle(sim.itineraryCaption == nil ? .secondary : Color.orange)
            ProgressView(value: sim.itineraryProgress).tint(Theme.accent).padding(.horizontal, 60)
        }
    }

    private var compactStrip: some View {
        HStack(spacing: 18) {
            ForEach(RecordingStat.all(sim).prefix(3)) { stat in
                VStack(spacing: 0) {
                    Text(stat.value).font(.title3.weight(.bold)).monospacedDigit()
                    Text(stat.label).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if sim.hasItinerary {
                VStack(spacing: 0) {
                    Text(sim.remainingText).font(.title3.weight(.bold)).monospacedDigit()
                    Text(sim.itineraryCaption ?? "Restant").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassBackground(in: RoundedRectangle(cornerRadius: 18))
        .overlay(alignment: .bottom) {
            if let banner = sim.pauseBannerText {
                Text(banner).font(.caption.weight(.bold)).padding(6).background(pauseTint, in: Capsule())
                    .foregroundStyle(.black).offset(y: 26)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 20) {
            circleButton(showsMap ? "chart.bar.fill" : "map.fill") { showsMap.toggle() }
            if sim.isPaused {
                capsuleButton("Reprendre", fill: Theme.accent, action: { sim.resume() })
                capsuleButton("Terminer", fill: .black, action: onFinish)
            } else {
                Button { sim.pause() } label: {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 84, height: 84)
                        .background(Theme.accent, in: Circle())
                }
                circleButton("lock.fill") {}.opacity(0.4)
            }
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 56, height: 56)
                .glassBackground(in: Circle(), interactive: true)
        }
        .buttonStyle(.plain)
    }

    private func capsuleButton(_ title: String, fill: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 130, height: 60)
                .background(fill, in: Capsule())
        }
    }
}

// MARK: - B · Carte d'abord, panneau

struct RecordingVariantB: View {
    let sim: RecordingPrototypeSimulation
    let onFinish: () -> Void
    @State private var expanded = false
    @State private var confirmsRemoval = false
    @GestureState private var holding = false

    var body: some View {
        RecordingPrototypeMap(sim: sim)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                VStack(spacing: 8) {
                    HStack {
                        RecordingGPSChip(gps: sim.gps)
                        Spacer()
                    }
                    if let banner = sim.pauseBannerText {
                        statusChip(banner, symbol: "pause.circle.fill", color: pauseTint)
                    }
                    if let caption = sim.itineraryCaption {
                        statusChip(caption, symbol: "point.topleft.down.to.point.bottomright.curvepath", color: .orange)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 48)
            }
            .overlay(alignment: .bottom) { panel }
            .animation(.snappy, value: expanded)
            .animation(.snappy, value: sim.phase)
            .confirmationDialog("Retirer l'Itinéraire ?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                Button("Retirer", role: .destructive, action: { sim.removeItinerary() })
            } message: {
                Text("La Recording continue sans Itinéraire. Il ne pourra pas être remis.")
            }
    }

    private func statusChip(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color, in: Capsule())
    }

    private var panel: some View {
        let stats = RecordingStat.all(sim)
        return VStack(spacing: 14) {
            Capsule().fill(.secondary).frame(width: 40, height: 5)
                .onTapGesture { expanded.toggle() }
            if expanded {
                ForEach(stats) { stat in
                    VStack(spacing: 0) {
                        Text(stat.value).font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit()
                        Text(stat.unit.isEmpty ? stat.label : "\(stat.label) (\(stat.unit))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(alignment: .top) {
                    ForEach(stats) { stat in
                        VStack(spacing: 2) {
                            Text(stat.value).font(.title2.weight(.bold)).monospacedDigit()
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text(stat.unit.isEmpty ? stat.label : "\(stat.label) \(stat.unit)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            if sim.hasItinerary { itineraryRow }
            controls
        }
        .padding(16)
        .glassBackground(in: RoundedRectangle(cornerRadius: 28))
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
        .gesture(DragGesture().onEnded { value in expanded = value.translation.height < 0 })
    }

    private var itineraryRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(sim.remainingText) km restants").font(.subheadline.weight(.semibold)).monospacedDigit()
                ProgressView(value: sim.itineraryProgress).tint(Theme.accent)
            }
            Button { confirmsRemoval = true } label: {
                Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
            }
            .accessibilityLabel("Retirer l'Itinéraire")
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { sim.isPaused ? sim.resume() : sim.pause() } label: {
                Label(sim.isPaused ? "Reprendre" : "Pause", systemImage: sim.isPaused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(Theme.accent, in: Capsule())
            }
            holdToFinish
        }
    }

    /// Terminer needs a 1 s long press: the ring fills while holding.
    private var holdToFinish: some View {
        ZStack {
            Circle().fill(.black)
            Circle()
                .trim(from: 0, to: holding ? 1 : 0)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(holding ? .linear(duration: 1) : .default, value: holding)
            Image(systemName: "stop.fill").foregroundStyle(.white)
        }
        .frame(width: 54, height: 54)
        .gesture(
            LongPressGesture(minimumDuration: 1)
                .updating($holding) { value, state, _ in state = value }
                .onEnded { _ in onFinish() }
        )
        .overlay(alignment: .top) {
            Text("Maintenir").font(.caption2).foregroundStyle(.secondary).offset(y: -16)
        }
        .accessibilityLabel("Terminer (appui long)")
    }
}

// MARK: - C · Écran partagé fixe

struct RecordingVariantC: View {
    let sim: RecordingPrototypeSimulation
    let onFinish: () -> Void
    @State private var confirmsFinish = false

    var body: some View {
        VStack(spacing: 0) {
            RecordingPrototypeMap(sim: sim, zoom: 14.6)
                .frame(height: 300)
                .overlay(alignment: .bottom) { if sim.hasItinerary { itineraryBand } }
                .overlay(alignment: .topLeading) { RecordingGPSChip(gps: sim.gps).padding().padding(.top, 52) }
            statsList
            controls
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .tabBar)
        .animation(.snappy, value: sim.phase)
        .confirmationDialog("Terminer la Recording ?", isPresented: $confirmsFinish, titleVisibility: .visible) {
            Button("Terminer", action: onFinish)
            Button("Continuer", role: .cancel) {}
        }
    }

    private var itineraryBand: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sim.itineraryCaption ?? "Restant").font(.caption.weight(.semibold))
                    .foregroundStyle(sim.itineraryCaption == nil ? .secondary : Color.orange)
                Text("\(sim.remainingText) km").font(.title2.weight(.bold)).monospacedDigit()
            }
            ProgressView(value: sim.itineraryProgress).tint(Theme.accent)
            Button(action: { sim.removeItinerary() }) {
                Image(systemName: "xmark").font(.footnote.weight(.bold)).padding(8)
                    .glassBackground(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer l'Itinéraire")
        }
        .padding(12)
        .glassBackground(in: RoundedRectangle(cornerRadius: 16))
        .padding(10)
    }

    private var statsList: some View {
        let stats = RecordingStat.all(sim)
        return VStack(spacing: 0) {
            if let banner = sim.pauseBannerText {
                Label(banner, systemImage: "pause.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(pauseTint)
                    .foregroundStyle(.black)
            }
            ForEach(Array(stats.enumerated()), id: \.element.id) { index, stat in
                HStack(alignment: .firstTextBaseline) {
                    Text(stat.label).font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(stat.value)
                        .font(.system(size: index == 0 ? 54 : 36, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(stat.unit).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                if index < stats.count - 1 { Divider().padding(.leading, 20) }
            }
            Spacer(minLength: 0)
        }
        .opacity(sim.isPaused ? 0.6 : 1)
        .background(sim.isPaused ? pauseTint.opacity(0.1) : .clear)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button { sim.isPaused ? sim.resume() : sim.pause() } label: {
                Label(sim.isPaused ? "Reprendre" : "Pause", systemImage: sim.isPaused ? "play.fill" : "pause.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(sim.isPaused ? Color.green : Theme.accent, in: RoundedRectangle(cornerRadius: 16))
            }
            Button { confirmsFinish = true } label: {
                Text("Terminer")
                    .font(.headline)
                    .frame(width: 110, height: 60)
                    .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }
}
