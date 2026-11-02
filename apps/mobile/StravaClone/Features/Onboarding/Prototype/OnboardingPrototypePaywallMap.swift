#if DEBUG
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway (see OnboardingPrototypePaywall.swift). Variant C: the structure of
// Duolingo's paywall (https://mobbin.com/screens/97e9b0dc-f653-4422-96e8-53650ff9accd: a big
// visual on top, the free trial highlighted in the title, « we'll remind you », « Essayer pour
// 0,00 € » / « Non merci »), drawn in Nervo's look: the app's Outdoors map with a ride up the Col
// de la Forclaz (Mapbox cycling route), a trophy, a personal record and a segment leaderboard.

struct ProtoPaywallC: View {
    let c: ProtoPaywallContext

    private var zero: String {
        Decimal(0).formatted(.currency(code: c.selected.currencyCode).locale(Locale(identifier: "fr_FR")))
    }

    var body: some View {
        VStack(spacing: 0) {
            ProtoPaywallMapHero(firstName: c.firstName)
                .frame(height: 470)
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 36)
                }

            VStack(spacing: 10) {
                (Text("Allez plus loin avec ")
                    + Text("\(c.selected.trialDays ?? 0) jours gratuits").foregroundStyle(Theme.accent)
                    + Text(" de Premium"))
                    .font(.system(size: 28, weight: .bold)).tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Classements complets, itinéraires sur mesure, analyse de vos progrès et plus encore.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Label("Nous vous rappellerons avant la fin de votre essai", systemImage: "bell.fill")
                    .font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                ProtoPrimaryButton(title: c.isBusy ? "…" : "Essayer pour \(zero)", isEnabled: !c.isBusy, action: c.startTrial)
                Button("Non merci", action: c.skip)
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                    .frame(minHeight: 32)
                ProtoPaywallLegal(c: c)
            }
            .padding(.horizontal, Theme.spacing).padding(.bottom, 6)
        }
        .ignoresSafeArea(edges: .top)
    }
}

/// The ride on the real map, tilted, with what Premium shows about it.
private struct ProtoPaywallMapHero: View {
    let firstName: String

    @State private var isMapLoaded = false

    private var line: [CLLocationCoordinate2D] { Self.route }
    private var athlete: String { firstName.isEmpty ? "Vous" : firstName }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color(.tertiarySystemFill)
            // Bearing 45°: the ride, heading south-east, crosses the screen from left to right.
            Map(initialViewport: .camera(center: CLLocationCoordinate2D(latitude: 45.8235, longitude: 6.2125),
                                         zoom: 11.15, bearing: 45, pitch: 40)) {
                PolylineAnnotation(lineCoordinates: line)
                    .lineColor(.white)
                    .lineWidth(9)
                    .lineJoin(.round)
                PolylineAnnotation(lineCoordinates: line)
                    .lineColor(UIColor(Theme.accent))
                    .lineWidth(5)
                    .lineJoin(.round)
                MapViewAnnotation(coordinate: line[0]) {
                    Circle().fill(.green).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
                }
                MapViewAnnotation(coordinate: line[line.count * 2 / 3]) {
                    badge(symbol: "medal.fill", tint: Theme.accent, title: "Record perso")
                }
                .variableAnchors([ViewAnnotationAnchorConfig(anchor: .bottom, offsetY: 8)])
                .allowOverlap(true)
                MapViewAnnotation(coordinate: line[line.count - 1]) {
                    badge(symbol: "trophy.fill", tint: Color(red: 0.95, green: 0.7, blue: 0.1), title: "1er")
                }
                .variableAnchors([ViewAnnotationAnchorConfig(anchor: .bottom, offsetY: 8)])
                .allowOverlap(true)
            }
            .mapStyle(.outdoors)
            .ornamentOptions(OrnamentOptions(scaleBar: ScaleBarViewOptions(visibility: .hidden),
                                             compass: CompassViewOptions(visibility: .hidden)))
            .onMapLoaded { _ in withAnimation(.easeIn(duration: 0.3)) { isMapLoaded = true } }
            .allowsHitTesting(false)
            .opacity(isMapLoaded ? 1 : 0)

            leaderboard
                .padding(.leading, Theme.spacing).padding(.bottom, 44)
        }
        .overlay(alignment: .topTrailing) {
            Text("PREMIUM").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.accent))
                .padding(.trailing, Theme.spacing).padding(.top, 62)
        }
        .clipped()
    }

    private func badge(symbol: String, tint: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .frame(width: 26, height: 26).background(Circle().fill(tint))
            Text(title).font(.footnote.weight(.bold))
        }
        .padding(.leading, 4).padding(.trailing, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color(.systemBackground)).shadow(color: .black.opacity(0.18), radius: 6, y: 2))
        .foregroundStyle(.primary)
    }

    /// The segment's full leaderboard, a Premium feature, with the athlete on top.
    private var leaderboard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Col de la Forclaz · 4,2 km", systemImage: "flag.checkered")
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array([(athlete, "18:42"), ("Léo", "19:05"), ("Inès", "19:31")].enumerated()), id: \.offset) { index, row in
                HStack(spacing: 8) {
                    Text("\(index + 1)").font(.caption.weight(.heavy).monospacedDigit())
                        .foregroundStyle(index == 0 ? .white : .secondary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(index == 0 ? Color(red: 0.95, green: 0.7, blue: 0.1) : Color(.systemGray5)))
                    Text(row.0).font(.subheadline.weight(index == 0 ? .bold : .regular)).lineLimit(1)
                    Spacer(minLength: 16)
                    Text(row.1).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    if index == 0 { Image(systemName: "crown.fill").font(.caption).foregroundStyle(Color(red: 0.95, green: 0.7, blue: 0.1)) }
                }
            }
        }
        .padding(10)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(.systemBackground))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4))
    }

    /// Menthon-Saint-Bernard → Talloires → Col de la Forclaz, Mapbox Directions (cycling, simplified).
    static let route: [CLLocationCoordinate2D] = [
        .init(latitude: 45.86043, longitude: 6.19536),
        .init(latitude: 45.85756, longitude: 6.19796),
        .init(latitude: 45.85621, longitude: 6.19743),
        .init(latitude: 45.85502, longitude: 6.19890),
        .init(latitude: 45.85355, longitude: 6.20211),
        .init(latitude: 45.85316, longitude: 6.20461),
        .init(latitude: 45.84717, longitude: 6.21390),
        .init(latitude: 45.84660, longitude: 6.21414),
        .init(latitude: 45.84521, longitude: 6.21251),
        .init(latitude: 45.84424, longitude: 6.21387),
        .init(latitude: 45.84350, longitude: 6.21079),
        .init(latitude: 45.84228, longitude: 6.21470),
        .init(latitude: 45.84022, longitude: 6.21647),
        .init(latitude: 45.83964, longitude: 6.21658),
        .init(latitude: 45.83937, longitude: 6.21336),
        .init(latitude: 45.83770, longitude: 6.21458),
        .init(latitude: 45.83784, longitude: 6.21559),
        .init(latitude: 45.83686, longitude: 6.21703),
        .init(latitude: 45.83957, longitude: 6.21708),
        .init(latitude: 45.83990, longitude: 6.22142),
        .init(latitude: 45.84078, longitude: 6.22384),
        .init(latitude: 45.84035, longitude: 6.22483),
        .init(latitude: 45.83846, longitude: 6.22546),
        .init(latitude: 45.83798, longitude: 6.22983),
        .init(latitude: 45.83696, longitude: 6.23206),
        .init(latitude: 45.83467, longitude: 6.23386),
        .init(latitude: 45.83278, longitude: 6.24133),
        .init(latitude: 45.83182, longitude: 6.23914),
        .init(latitude: 45.82937, longitude: 6.23798),
        .init(latitude: 45.82704, longitude: 6.23864),
        .init(latitude: 45.82553, longitude: 6.23729),
        .init(latitude: 45.82300, longitude: 6.23710),
        .init(latitude: 45.82072, longitude: 6.23977),
        .init(latitude: 45.82355, longitude: 6.24186),
        .init(latitude: 45.81907, longitude: 6.24245),
        .init(latitude: 45.81687, longitude: 6.24443),
        .init(latitude: 45.81381, longitude: 6.24252),
        .init(latitude: 45.81201, longitude: 6.24261),
        .init(latitude: 45.80846, longitude: 6.24476),
        .init(latitude: 45.80952, longitude: 6.24551),
        .init(latitude: 45.80981, longitude: 6.24733),
        .init(latitude: 45.81111, longitude: 6.24466),
        .init(latitude: 45.81252, longitude: 6.24500),
        .init(latitude: 45.81281, longitude: 6.24607)
    ]
}
#endif
