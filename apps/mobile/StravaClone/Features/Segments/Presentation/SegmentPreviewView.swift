import MapboxMaps
import SwiftUI

/// The preview of a drawn Segment (ADR-039 §15): mini-map, full figures, profile, the name with
/// its counter and « Créer le Segment »; the duplicate (with a link) and the quota show here.
/// Once created, « On cherche tes passages… ».
struct SegmentPreviewView: View {
    @State private var store: SegmentCreateStore
    let onShowMySegments: () -> Void
    let onDone: () -> Void

    @FocusState private var isNameFocused: Bool

    init(
        candidate: SegmentCandidate,
        makeStore: @MainActor (SegmentCandidate) -> SegmentCreateStore,
        onShowMySegments: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        _store = State(initialValue: makeStore(candidate))
        self.onShowMySegments = onShowMySegments
        self.onDone = onDone
    }

    var body: some View {
        if let created = store.created {
            SegmentCreatedView(
                created: created,
                figures: store.preview.figures,
                onShowMySegments: onShowMySegments,
                onDone: onDone
            )
        } else {
            form
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                SegmentTrackMap(track: store.preview.track)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Label(
                    ActivityFormatters.sportLabel(store.sport.sportType),
                    systemImage: ActivityFormatters.sportSymbol(store.sport.sportType)
                )
                .font(.subheadline.weight(.semibold))
                SegmentFiguresGrid(figures: store.preview.figures)
                ElevationProfileChart(profile: store.preview.profile)
                    .frame(height: 120)
                    .accessibilityLabel("Profil d'altitude")
                nameField
                refusals
                Text(SegmentMessages.publicNotice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(Theme.spacing)
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Nouveau Segment")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { createButton }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nom du Segment")
                .font(.headline)
            TextField("Ex. : Montée du col de la Forclaz", text: $store.name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .submitLabel(.done)
                .accessibilityIdentifier("segmentName")
            HStack {
                Text(store.nameHint ?? " ")
                    .foregroundStyle(.orange)
                Spacer()
                Text(store.counterText)
                    .foregroundStyle(store.nameHint == nil ? Color.secondary : Color.orange)
                    .monospacedDigit()
                    .accessibilityLabel("\(store.counterText) caractères")
            }
            .font(.caption)
        }
    }

    @ViewBuilder private var refusals: some View {
        if let duplicate = store.duplicate {
            VStack(alignment: .leading, spacing: 6) {
                Label(SegmentMessages.duplicateTitle, systemImage: "square.on.square")
                    .font(.subheadline.bold())
                Text(SegmentMessages.duplicate(duplicate))
                    .font(.footnote)
                NavigationLink(value: SegmentRequest(segmentID: duplicate.id)) {
                    Text("Voir « \(duplicate.name) »")
                        .font(.footnote.bold())
                }
                .accessibilityIdentifier("segmentDuplicateLink")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("segmentDuplicate")
        }
        if let message = store.message {
            SegmentNotice(text: message, systemImage: store.isQuotaReached ? "hourglass" : "exclamationmark.triangle.fill")
                .accessibilityIdentifier("segmentCreateMessage")
        }
    }

    private var createButton: some View {
        Button {
            isNameFocused = false
            Task { await store.create() }
        } label: {
            Group {
                if store.isCreating {
                    ProgressView()
                } else {
                    Text("Créer le Segment")
                }
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!store.canCreate)
        .padding(Theme.spacing)
        .background(.bar)
        .accessibilityIdentifier("createSegment")
    }
}

/// Distance, D+, grades, altitudes and category, two per row.
struct SegmentFiguresGrid: View {
    let figures: SegmentFigures

    var body: some View {
        let items: [(String, String)] = [
            ("Distance", ActivityFormatters.distance(figures.distance)),
            ("Dénivelé positif", ActivityFormatters.elevation(figures.elevationGain)),
            ("Pente moyenne", SegmentMessages.grade(figures.averageGrade)),
            ("Pente max.", SegmentMessages.grade(figures.maxGrade)),
            ("Altitude basse", ActivityFormatters.elevation(figures.lowestAltitude)),
            ("Altitude haute", ActivityFormatters.elevation(figures.highestAltitude)),
            ("Catégorie", figures.climbCategory?.label ?? "–"),
        ]
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], spacing: 12) {
            ForEach(items, id: \.0) { label, value in
                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.title3.bold())
                        .monospacedDigit()
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(label)
                .accessibilityValue(value)
            }
        }
    }
}

/// « Segment créé »: the retro-matching runs in the background (ADR-039 §7).
struct SegmentCreatedView: View {
    let created: SegmentRef
    let figures: SegmentFigures
    let onShowMySegments: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: Theme.spacing) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.accent)
                .accessibilityHidden(true)
            Text("Segment créé")
                .font(.title2.bold())
            Text("« \(created.name) »")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(summary)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ProgressView()
                Text(SegmentMessages.searchingEfforts)
                    .font(.footnote)
            }
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .combine)
            Spacer()
            Button(action: onShowMySegments) {
                Text("Voir mes Segments")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("showMySegments")
            Button(action: onDone) {
                Text("Terminé")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("segmentCreatedDone")
        }
        .padding(Theme.spacing)
        .navigationBarBackButtonHidden()
        .onAppear {
            AccessibilityNotification.Announcement("Segment créé. \(SegmentMessages.searchingEfforts)").post()
        }
    }

    private var summary: String {
        ([ActivityFormatters.distance(figures.distance), SegmentMessages.grade(figures.averageGrade)]
            + (figures.climbCategory.map { [$0.label] } ?? [])).joined(separator: " · ")
    }
}

/// The resampled path on an Outdoors map, framed on it, with its start and finish markers;
/// gestures off, the map sits in a scrolling page.
struct SegmentTrackMap: View {
    let track: [Coordinate]

    var body: some View {
        let line = track.map(\.locationCoordinate)
        Map(initialViewport: .overview(
            geometry: LineString(line),
            geometryPadding: EdgeInsets(top: 32, leading: 32, bottom: 32, trailing: 32)
        )) {
            PolylineAnnotation(lineCoordinates: line)
                .lineColor(UIColor(Theme.accent))
                .lineWidth(4)
                .lineJoin(.round)
            RouteEndpointsContent(coordinates: line)
        }
        .mapStyle(.outdoors)
        .gestureOptions(GestureOptions(
            panEnabled: false,
            pinchEnabled: false,
            rotateEnabled: false,
            simultaneousRotateAndPinchZoomEnabled: false,
            pinchZoomEnabled: false,
            pinchPanEnabled: false,
            pitchEnabled: false,
            doubleTapToZoomInEnabled: false,
            doubleTouchToZoomOutEnabled: false,
            quickZoomEnabled: false
        ))
        .accessibilityElement()
        .accessibilityLabel("Carte du Segment")
    }
}
