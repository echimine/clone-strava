import MapboxMaps
import SwiftUI

/// Itinerary editor (ADR-030 §2): centered on the athlete (ADR-027), each tap on the map
/// adds a Waypoint at the end. Waypoints are dragged, a Leg's middle handle is pulled to
/// insert one, a tap opens a bubble (remove a Waypoint, switch a Leg's mode), and every
/// gesture can be undone. The stats card shows the sport, which can be changed, the distance
/// and the elevation gain measured by the API on release (ADR-030 §3). Routing failures leave
/// Legs pending, requested again when the network comes back, while editing goes on.
struct ItineraryEditorView: View {
    @State var store: ItineraryEditorStore
    let onClose: () -> Void

    @State private var viewport: Viewport = .followUser
    /// Screen point where the current drag started, in the map's coordinates.
    @State private var dragStart: CGPoint?

    var body: some View {
        MapReader { proxy in
            AppMap(viewport: $viewport) {
                mapContent(proxy: proxy)
            }
        }
        // Identifier on the map only: on the whole screen it would hide the overlays'.
        .accessibilityIdentifier("itineraryEditor")
        .overlay(alignment: .top) { header }
        .safeAreaInset(edge: .bottom) { statsCard }
        .task { await store.retryPendingLegsOnReconnection() }
        .onAppear(perform: frameReopenedItinerary)
    }

    /// "Modifier" reopens a saved Itinerary: the map frames it rather than the athlete.
    private func frameReopenedItinerary() {
        let line = store.lines.flatMap(\.coordinates).map(\.locationCoordinate)
        guard line.count >= 2 else { return }
        viewport = .overview(
            geometry: LineString(line),
            geometryPadding: EdgeInsets(top: 120, leading: 40, bottom: 220, trailing: 40)
        )
    }

    // MARK: Map

    @MapContentBuilder
    private func mapContent(proxy: MapProxy) -> some MapContent {
        PolylineAnnotationGroup(store.lines.filter { !$0.isProvisional }) { line in
            PolylineAnnotation(lineCoordinates: line.coordinates.map(\.locationCoordinate))
                .lineColor(UIColor(Theme.accent))
                .lineWidth(5)
                .onTapGesture { context in
                    store.tapLeg(line.id, at: Coordinate(context.coordinate))
                    return true
                }
        }
        .lineCap(.round)
        .lineJoin(.round)

        PolylineAnnotationGroup(store.lines.filter(\.isProvisional)) { line in
            PolylineAnnotation(lineCoordinates: line.coordinates.map(\.locationCoordinate))
                .lineColor(UIColor(Theme.accent).withAlphaComponent(0.7))
                .lineWidth(4)
                .onTapGesture { context in
                    store.tapLeg(line.id, at: Coordinate(context.coordinate))
                    return true
                }
        }
        .lineDashArray([1, 1.5])

        if let connector = store.snapConnector {
            PolylineAnnotation(lineCoordinates: connector.map(\.locationCoordinate))
                .lineColor(UIColor(Theme.accent).withAlphaComponent(0.7))
                .lineWidth(2)
        }

        ForEvery(store.insertionHandles, id: \.id) { handle in
            MapViewAnnotation(coordinate: handle.coordinate.locationCoordinate) {
                InsertionHandleView()
                    .opacity(store.showsInsertionHandles ? 1 : 0)
                    .gesture(dragGesture(from: handle.coordinate, proxy: proxy) { start in
                        store.beginInsertion(intoLeg: handle.id, at: handle.coordinate, point: start)
                    })
            }
            .allowOverlap(true)
            .priority(0)
        }

        ForEvery(store.markers, id: \.id) { marker in
            MapViewAnnotation(coordinate: marker.coordinate.locationCoordinate) {
                WaypointMarkerView(role: marker.role, isSelected: store.selection == .waypoint(marker.id))
                    .onTapGesture { store.tapWaypoint(marker.id) }
                    .gesture(dragGesture(from: marker.coordinate, proxy: proxy) { start in
                        store.beginDrag(marker.id, at: start)
                    })
            }
            .allowOverlap(true)
            .priority(1)
        }

        if let bubble = bubble {
            MapViewAnnotation(coordinate: bubble.coordinate.locationCoordinate) {
                bubble.content
            }
            .allowOverlap(true)
            .priority(2)
            .variableAnchors([ViewAnnotationAnchorConfig(anchor: .bottom, offsetY: 18)])
        }

        TapInteraction { context in
            store.tap(at: Coordinate(context.coordinate))
            return true
        }
    }

    /// Drag in screen space, converted to map coordinates through the map itself: the
    /// translation is added to where the dragged item was when the finger landed.
    private func dragGesture(
        from coordinate: Coordinate,
        proxy: MapProxy,
        onBegin: @escaping (CGPoint) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard let map = proxy.map else { return }
                let start = dragStart ?? map.point(for: coordinate.locationCoordinate)
                if dragStart == nil {
                    dragStart = start
                    onBegin(start)
                }
                let point = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                store.drag(to: Coordinate(map.coordinate(for: point)), at: point)
            }
            .onEnded { value in
                guard let map = proxy.map, let start = dragStart else { return }
                dragStart = nil
                let point = CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height)
                store.endDrag(at: Coordinate(map.coordinate(for: point)), point: point)
            }
    }

    private var bubble: (coordinate: Coordinate, content: AnyView)? {
        switch store.selection {
        case .waypoint(let id):
            guard let marker = store.markers.first(where: { $0.id == id }) else { return nil }
            return (marker.coordinate, AnyView(WaypointBubble(onRemove: store.removeSelectedWaypoint)))
        case .leg(_, let coordinate):
            guard let mode = store.selectedLegMode else { return nil }
            return (coordinate, AnyView(LegModeBubble(mode: mode, onSelect: store.setSelectedLegMode)))
        case nil:
            return nil
        }
    }

    // MARK: Overlays

    private var header: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                headerButton("arrow.uturn.backward", label: "Annuler", identifier: "undoItineraryEdit", action: store.undo)
                    .disabled(!store.canUndo)
                headerButton("arrow.uturn.forward", label: "Rétablir", identifier: "redoItineraryEdit", action: store.redo)
                    .disabled(!store.canRedo)
                Spacer()
                headerButton("xmark", label: "Fermer l'éditeur", identifier: "closeItineraryEditor", action: onClose)
            }

            if let message = store.message {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                    Text(message)
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if store.canRetryPendingLegs {
                        Button("Réessayer", action: store.retryPendingLegs)
                            .font(.footnote.bold())
                            .accessibilityIdentifier("retryPendingLegs")
                    }
                    Button("OK", action: store.dismissMessage)
                        .font(.footnote.bold())
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("itineraryEditorMessage")
            } else if let hint = store.hint {
                Text(hint)
                    .font(.footnote)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal, Theme.spacing)
        .padding(.top, 8)
        .animation(.default, value: store.message)
    }

    private func headerButton(
        _ symbol: String,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: Circle())
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var statsCard: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: Theme.spacing) {
                sportMenu
                Spacer()
                stat(store.distanceText, label: "Distance", isStale: store.isDistanceStale, identifier: "itineraryDistance")
                if store.isElevationUnavailable {
                    elevationUnavailable
                } else {
                    stat(store.elevationText, label: "D+", isStale: store.isElevationStale, identifier: "itineraryElevationGain")
                }
            }
            if let source = store.elevationSourceText {
                Text(source)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("itineraryElevationSource")
            }
        }
        .padding(Theme.spacing)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, Theme.spacing)
        .padding(.bottom, 8)
        .animation(.default, value: store.distanceText)
        .animation(.default, value: store.elevationText)
    }

    /// The sport can change while editing: in another category, the Legs are recomputed.
    private var sportMenu: some View {
        Menu {
            Picker("Sport", selection: Binding(get: { store.sport }, set: { store.changeSport(to: $0) })) {
                ForEach(ItinerarySport.allCases, id: \.self) { sport in
                    Label(
                        ActivityFormatters.sportLabel(sport.sportType),
                        systemImage: ActivityFormatters.sportSymbol(sport.sportType)
                    )
                    .tag(sport)
                    .accessibilityIdentifier("itineraryEditorSport.\(sport.rawValue)")
                }
            }
        } label: {
            HStack(spacing: 4) {
                Label(store.sportLabel, systemImage: store.sportSymbol)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .accessibilityLabel("Sport : \(store.sportLabel)")
        .accessibilityHint("Changer le sport de l'itinéraire")
        .accessibilityIdentifier("itinerarySportMenu")
    }

    private func stat(_ value: String, label: String, isStale: Bool, identifier: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(isStale ? .secondary : .primary)
                .contentTransition(.numericText())
                .accessibilityIdentifier(identifier)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// The preview failed: editing goes on, and the gain can be asked again.
    private var elevationUnavailable: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("D+ indisponible")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Réessayer", action: store.retryElevation)
                .font(.caption.bold())
                .accessibilityIdentifier("retryItineraryElevationGain")
        }
    }
}
