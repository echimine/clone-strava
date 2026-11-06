import SwiftUI

/// Creating a Segment, in full screen (ADR-039 §15): the sport first, then the Itinerary
/// editor with the live figures, then the preview with the name, then « On cherche tes
/// passages… ».
struct SegmentCreationView: View {
    let makeCanvas: @MainActor (SegmentSport, _ onClose: @escaping () -> Void) -> SegmentDrawingCanvas
    let makeDrawingStore: @MainActor (SegmentSport) -> SegmentDrawingStore
    let makeCreateStore: @MainActor (SegmentCandidate) -> SegmentCreateStore
    /// The existing Segment's sheet, from the duplicate's link.
    let destinations: AppDestinations
    let onShowMySegments: () -> Void
    let onClose: () -> Void

    @State private var drawingStore: SegmentDrawingStore?
    @State private var canvas: SegmentDrawingCanvas?

    var body: some View {
        NavigationStack {
            if let drawingStore, let canvas {
                SegmentDrawingView(store: drawingStore, canvas: canvas)
                    .navigationDestination(item: Bindable(drawingStore).next) { candidate in
                        SegmentPreviewView(
                            candidate: candidate,
                            makeStore: makeCreateStore,
                            onShowMySegments: onShowMySegments,
                            onDone: onClose
                        )
                    }
                    .registerAppDestinations(destinations)
            } else {
                SegmentSportPicker(onPick: start, onCancel: onClose)
            }
        }
    }

    private func start(_ sport: SegmentSport) {
        canvas = makeCanvas(sport, onClose)
        drawingStore = makeDrawingStore(sport)
    }
}

/// The sport of the new Segment, with each sport's minimum length.
struct SegmentSportPicker: View {
    let onPick: (SegmentSport) -> Void
    let onCancel: () -> Void

    var body: some View {
        List {
            Section {
                ForEach(SegmentSport.allCases, id: \.self) { sport in
                    Button {
                        onPick(sport)
                    } label: {
                        HStack {
                            Label(
                                ActivityFormatters.sportLabel(sport.sportType),
                                systemImage: ActivityFormatters.sportSymbol(sport.sportType)
                            )
                            Spacer()
                            Text(SegmentMessages.minimum(sport))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("segmentSport.\(sport.rawValue)")
                }
            } header: {
                Text("Pour quel sport ?")
            } footer: {
                Text(SegmentMessages.oneSportOnly)
            }
        }
        .navigationTitle("Nouveau Segment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", action: onCancel)
            }
        }
    }
}

/// The editor, and under it the live figures and « Continuer ».
struct SegmentDrawingView: View {
    @Bindable var store: SegmentDrawingStore
    let canvas: SegmentDrawingCanvas

    var body: some View {
        canvas.view
            .safeAreaInset(edge: .bottom) { card }
            .toolbar(.hidden, for: .navigationBar)
            // Read in the body: Observation follows the editor's path through the closure.
            .onChange(of: canvas.drawing(), initial: true) { _, drawing in
                store.update(drawing)
            }
            .onChange(of: store.message) { _, message in
                if let message { AccessibilityNotification.Announcement(message).post() }
            }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: Theme.spacing) {
                Label(
                    ActivityFormatters.sportLabel(store.sport.sportType),
                    systemImage: ActivityFormatters.sportSymbol(store.sport.sportType)
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                stat(store.distanceText, label: "Distance", identifier: "segmentDistance")
                stat(store.elevationGainText, label: "D+", identifier: "segmentElevationGain")
                stat(store.averageGradeText, label: "Pente moy.", identifier: "segmentAverageGrade")
            }
            if let notice = store.message ?? store.blocker {
                SegmentNotice(text: notice)
                    .accessibilityIdentifier("segmentDrawingNotice")
            }
            Button {
                Task { await store.continueTapped() }
            } label: {
                Group {
                    if store.isContinuing {
                        ProgressView()
                    } else {
                        Text("Continuer")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canContinue)
            .accessibilityIdentifier("segmentContinue")
        }
        .padding(Theme.spacing)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .animation(.default, value: store.distanceText)
    }

    private func stat(_ value: String, label: String, identifier: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(store.isMeasuring ? .secondary : .primary)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label == "D+" ? "Dénivelé positif" : label)
        .accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }
}

/// An orange banner: a broken rule, a refusal, « Connexion requise ».
struct SegmentNotice: View {
    let text: String
    var systemImage = "exclamationmark.triangle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(text)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
    }
}
