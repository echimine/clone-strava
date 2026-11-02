#if DEBUG
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway, never merged to main (wayfinder ticket « Écran Welcome », #116).
// Question: what does the first screen of someone without an account look like, right after the
// Nervo splash (ADR-032)? Three structurally different variants, switchable from the pill:
// A « Carrousel » (Strava: 3 swipeable pages, each an app mock-up), B « Orange Nervo » (the
// splash's N does not open a window: it rises and the Welcome settles on the orange), C « Carte »
// (one visual: the real Outdoors map, a ride drawing itself, the buttons on a dark gradient).
// On every « first launch » (↺ of the pill), the Measurement consent sheet (#113) opens on top;
// its copy is a placeholder, decided by « Données personnelles de l'Onboarding » (#117).
// No Apple button here: like Strava, it would sit on the account screen, above Google.

enum ProtoWelcomeVariant: String, CaseIterable {
    case a = "A", b = "B", c = "C"
    var name: String {
        switch self {
        case .a: "Carrousel"
        case .b: "Orange Nervo"
        case .c: "Carte"
        }
    }
    /// B plays its own hand-off from the splash; A and C sit under the real `SplashView`.
    var usesSplashOverlay: Bool { self != .b }
}

/// What the Welcome leads to: the Onboarding, or the account screen without it.
struct ProtoWelcomeActions {
    let createAccount: () -> Void
    let signIn: () -> Void
}

struct ProtoWelcome: View {
    let variant: ProtoWelcomeVariant
    let answers: ProtoAnswers
    let actions: ProtoWelcomeActions

    @State private var showsSplash: Bool
    @State private var showsConsent = false

    init(variant: ProtoWelcomeVariant, answers: ProtoAnswers, actions: ProtoWelcomeActions) {
        self.variant = variant
        self.answers = answers
        self.actions = actions
        _showsSplash = State(initialValue: variant.usesSplashOverlay)
    }

    var body: some View {
        Group {
            switch variant {
            case .a: ProtoWelcomeA(actions: actions)
            case .b: ProtoWelcomeB(actions: actions) { askConsent() }
            case .c: ProtoWelcomeC(actions: actions)
            }
        }
        .overlay {
            if showsSplash {
                SplashView(isSessionKnown: true) {
                    showsSplash = false
                    askConsent()
                }
            }
        }
        .sheet(isPresented: $showsConsent) {
            ProtoConsentSheet { accepted in
                answers.measurementConsent = accepted ? "Acceptée" : "Refusée"
                showsConsent = false
            }
            .presentationDetents([.height(360)])
            .presentationBackground(Color(.systemBackground))
            .interactiveDismissDisabled()
        }
    }

    /// First launch only: the choice is asked once, then lives in the settings (ADR-015).
    private func askConsent() {
        guard answers.measurementConsent == nil else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(500))
            showsConsent = true
        }
    }
}

// MARK: - Shared

private struct ProtoWordmark: View {
    var color: Color = .primary
    var markBackground: Color = Theme.accent
    var markColor: Color = .white

    var body: some View {
        HStack(spacing: 8) {
            NervoMark().stroke(markColor, style: NervoMark.strokeStyle(forSide: 22))
                .frame(width: 22, height: 22)
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(markBackground))
            Text("Nervo").font(.system(size: 22, weight: .heavy)).tracking(-0.5).foregroundStyle(color)
        }
    }
}

/// « Accepter » and « Refuser » at the same level (CNIL), nothing pre-selected.
private struct ProtoConsentSheet: View {
    let answer: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "chart.bar.xaxis").font(.title).foregroundStyle(Theme.accent)
            Text("Mesure d'audience").font(.title2.bold())
            Text("[Texte à décider dans « Données personnelles de l'Onboarding »] Nervo mesure comment l'app est utilisée pour l'améliorer. Ni votre nom, ni votre âge, ni votre email ne sont envoyés. Vous pourrez changer d'avis dans les réglages.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack(spacing: 12) {
                consentButton("Refuser") { answer(false) }
                consentButton("Accepter") { answer(true) }
            }
        }
        .padding(24)
    }

    private func consentButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.primary)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .contentShape(Capsule())
        }
        .buttonStyle(ProtoPressStyle())
    }
}

// MARK: - A. Carrousel (Strava)

private struct ProtoWelcomeA: View {
    let actions: ProtoWelcomeActions
    @State private var page = 0

    // Nothing shown again by « Voici ce qui vous attend » (recording, itinerary, feed,
    // leaderboard on phone cards): other features, as full-width scenes.
    private let pages = [
        "Suivez votre sortie sans déverrouiller.",
        "Chaque arrivée se fête.",
        "Retrouvez toutes vos anciennes sorties.",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ProtoWordmark().padding(.top, 8)

            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    VStack(spacing: 28) {
                        mock(index)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                            .padding(.horizontal, Theme.spacing).padding(.top, 12)
                        Text(pages[index])
                            .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule().fill(index == page ? Theme.accent : Color(.systemGray4))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }
            .animation(.snappy, value: page)
            .padding(.vertical, 18)

            VStack(spacing: 6) {
                ProtoPrimaryButton(title: "Créer un compte", isEnabled: true, action: actions.createAccount)
                Button("Se connecter", action: actions.signIn)
                    .font(.headline).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .padding(.horizontal, Theme.spacing).padding(.bottom, 4)
        }
        .sensoryFeedback(.selection, trigger: page)
        .task {
            // Auto-advance, like Strava's, until the person swipes.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.snappy) { page = (page + 1) % pages.count }
            }
        }
    }

    @ViewBuilder private func mock(_ index: Int) -> some View {
        switch index {
        case 0: ProtoLockScreenScene()
        case 1: ProtoCelebrationScene()
        default: ProtoImportScene()
        }
    }
}

/// Live Activity on the lock screen (ADR-031): the ride ticks on without unlocking.
private struct ProtoLockScreenScene: View {
    @State private var start = Date.now.addingTimeInterval(-32 * 60 - 15)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = context.date.timeIntervalSince(start)
            ZStack {
                LinearGradient(colors: [Color(red: 0.12, green: 0.16, blue: 0.3), Color(red: 0.35, green: 0.2, blue: 0.35)],
                               startPoint: .top, endPoint: .bottom)
                VStack(spacing: 4) {
                    Text("dimanche 8 novembre").font(.subheadline.weight(.semibold)).opacity(0.85)
                    Text("8:42").font(.system(size: 76, weight: .semibold, design: .rounded))
                    Spacer()
                    HStack(spacing: 12) {
                        NervoMark().stroke(.white, style: NervoMark.strokeStyle(forSide: 22))
                            .frame(width: 22, height: 22).padding(7)
                            .background(Circle().fill(Theme.accent))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Course à pied").font(.caption.weight(.semibold)).opacity(0.75)
                            Text(String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60))
                                .font(.title2.weight(.bold).monospacedDigit())
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(String(format: "%.2f km", elapsed / 310).replacingOccurrences(of: ".", with: ","))
                                .font(.headline.monospacedDigit())
                            Text("5:10 /km").font(.caption.monospacedDigit()).opacity(0.75)
                        }
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(.black.opacity(0.45)))
                    .padding(14)
                }
                .padding(.top, 28)
                .foregroundStyle(.white)
            }
        }
    }
}

/// The end-of-ride Celebration (spec #77): the N, the distance, a record.
private struct ProtoCelebrationScene: View {
    @State private var draw: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.accent
            ForEach(0..<14, id: \.self) { i in
                Circle().fill(.white.opacity(0.25))
                    .frame(width: CGFloat(6 + i % 4 * 3))
                    .offset(x: CGFloat((i * 53) % 260 - 130), y: CGFloat((i * 97) % 300 - 150))
            }
            VStack(spacing: 14) {
                NervoMark().trim(from: 0, to: draw)
                    .stroke(.white, style: NervoMark.strokeStyle(forSide: 110))
                    .frame(width: 110, height: 110)
                Text("10,0 km").font(.system(size: 44, weight: .heavy, design: .rounded))
                Label("Record perso sur 10 km", systemImage: "medal.fill")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(.white.opacity(0.2)))
            }
            .foregroundStyle(.white)
        }
        .task {
            while !Task.isCancelled {
                draw = 0
                withAnimation(.easeInOut(duration: 1.1)) { draw = 1 }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

/// Import from a file (ADR-028): years of rides land in Nervo.
private struct ProtoImportScene: View {
    @State private var count = 0

    private let rows: [(SportType, String, String, String)] = [
        (.ride, "Tour du lac", "14 juin 2023", "42,3 km"),
        (.run, "Sortie longue", "2 mars 2024", "18,1 km"),
        (.hike, "Col de la Forclaz", "9 août 2025", "11,6 km"),
    ]

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            VStack(spacing: 18) {
                HStack(spacing: 8) {
                    ForEach([".gpx", ".fit", ".tcx"], id: \.self) { ext in
                        Text(ext).font(.caption.weight(.bold).monospaced())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().strokeBorder(Color(.separator)))
                    }
                }
                ZStack {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        HStack(spacing: 12) {
                            Image(systemName: ActivityFormatters.sportSymbol(row.0)).font(.title3)
                                .foregroundStyle(Theme.accent).frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.1).font(.subheadline.weight(.semibold))
                                Text(row.2).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.3).font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 8, y: 3))
                        .rotationEffect(.degrees(Double(index - 1) * 3))
                        .offset(y: CGFloat(index) * 58 - 58)
                    }
                }
                .frame(height: 190)
                .padding(.horizontal, 28)
                Text("\(count) activités importées").font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
            }
        }
        .task {
            count = 0
            while count < 248, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(12))
                withAnimation(.snappy) { count += 4 }
            }
        }
    }
}

// MARK: - B. Orange Nervo (the splash's N rises)

private struct ProtoWelcomeB: View {
    let actions: ProtoWelcomeActions
    let settled: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawProgress: CGFloat = 0
    @State private var isRisen = false
    @State private var showsContent = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // The splash's resting N: 1.7 × the 100 box on a 320 pt wide screen.
            let splashSide = size.width * 1.7 / 320 * 100
            let side: CGFloat = isRisen ? 96 : splashSide
            ZStack {
                Theme.accent.ignoresSafeArea()

                NervoMark()
                    .trim(from: 0, to: drawProgress)
                    .stroke(.white, style: NervoMark.strokeStyle(forSide: side))
                    .frame(width: side, height: side)
                    .position(x: size.width / 2, y: isRisen ? size.height * 0.2 : size.height / 2)

                VStack(spacing: 0) {
                    Spacer().frame(height: size.height * 0.2 + 70)
                    VStack(spacing: 14) {
                        Text("Nervo").font(.system(size: 44, weight: .heavy)).tracking(-1)
                        Text("Courez, roulez, marchez.\nChaque sortie compte.")
                            .font(.title3.weight(.medium))
                            .multilineTextAlignment(.center)
                            .opacity(0.9)
                    }
                    .foregroundStyle(.white)
                    Spacer()
                    VStack(spacing: 10) {
                        Button(action: actions.createAccount) {
                            Text("Créer un compte").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                                .foregroundStyle(Theme.accent)
                                .background(Capsule().fill(.white))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(ProtoPressStyle())
                        Button(action: actions.signIn) {
                            Text("Se connecter").font(.headline).frame(maxWidth: .infinity, minHeight: 54)
                                .foregroundStyle(.white)
                                .overlay(Capsule().strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(ProtoPressStyle())
                    }
                    .padding(.horizontal, Theme.spacing).padding(.bottom, 8)
                }
                .opacity(showsContent ? 1 : 0)
                .offset(y: showsContent ? 0 : 24)
            }
        }
        .task { await play() }
    }

    /// The splash's first beats (draw the N), then the rise instead of the window.
    private func play() async {
        if reduceMotion {
            drawProgress = 1; isRisen = true; showsContent = true
            settled()
            return
        }
        withAnimation(.easeInOut(duration: 0.7)) { drawProgress = 1 }
        try? await Task.sleep(for: .milliseconds(1000))
        withAnimation(.spring(duration: 0.7, bounce: 0.15)) { isRisen = true }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.easeOut(duration: 0.5)) { showsContent = true }
        try? await Task.sleep(for: .milliseconds(400))
        settled()
    }
}

// MARK: - C. Carte (one live visual)

private struct ProtoWelcomeC: View {
    let actions: ProtoWelcomeActions

    @State private var viewport = Viewport.camera(center: CLLocationCoordinate2D(latitude: 45.835, longitude: 6.22),
                                                  zoom: 12.2, bearing: 20, pitch: 55)
    @State private var drawnCount = 2
    @State private var isMapLoaded = false

    private var route: [CLLocationCoordinate2D] { ProtoPaywallMapHero.route }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.tertiarySystemFill).ignoresSafeArea()
            Map(viewport: $viewport) {
                PolylineAnnotation(lineCoordinates: Array(route.prefix(drawnCount)))
                    .lineColor(.white).lineWidth(9).lineJoin(.round)
                PolylineAnnotation(lineCoordinates: Array(route.prefix(drawnCount)))
                    .lineColor(UIColor(Theme.accent)).lineWidth(5).lineJoin(.round)
                MapViewAnnotation(coordinate: route[drawnCount - 1]) {
                    Circle().fill(Theme.accent).frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                        .shadow(radius: 3)
                }
                .allowOverlap(true)
            }
            .mapStyle(.outdoors)
            .ornamentOptions(OrnamentOptions(scaleBar: ScaleBarViewOptions(visibility: .hidden),
                                             compass: CompassViewOptions(visibility: .hidden)))
            .onMapLoaded { _ in withAnimation(.easeIn(duration: 0.3)) { isMapLoaded = true } }
            .allowsHitTesting(false)
            .opacity(isMapLoaded ? 1 : 0)
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [.black.opacity(0), .black.opacity(0.55), .black.opacity(0.85)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 460)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                ProtoWordmark(color: .white)
                Text("Votre prochaine sortie commence ici.")
                    .font(.system(size: 34, weight: .bold)).tracking(-0.6)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 6) {
                    ProtoPrimaryButton(title: "Créer un compte", isEnabled: true, action: actions.createAccount)
                    Button("Se connecter", action: actions.signIn)
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, Theme.spacing).padding(.bottom, 4)
        }
        .task {
            withViewportAnimation(.easeInOut(duration: 40)) {
                viewport = .camera(center: CLLocationCoordinate2D(latitude: 45.822, longitude: 6.235),
                                   zoom: 12.6, bearing: 70, pitch: 60)
            }
            while drawnCount < route.count, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(140))
                drawnCount += 1
            }
        }
    }
}
#endif
