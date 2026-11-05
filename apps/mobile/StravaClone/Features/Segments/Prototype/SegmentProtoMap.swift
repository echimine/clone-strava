#if DEBUG
import Charts
import MapboxMaps
import SwiftUI

// PROTOTYPE — throwaway (voir SegmentProto.swift).
// La trace de l'Activité découpée : zone de confidentialité grisée en pointillés, reste de la trace
// gris, portion choisie en orange, Pause marquée.

struct ProtoTrackContent: MapContent {
    let track: ProtoTrack
    let range: ClosedRange<Int>

    var body: some MapContent {
        let coordinates = track.coordinates
        PolylineAnnotationGroup(lines(coordinates), id: \.id) { line in
            PolylineAnnotation(lineCoordinates: line.coordinates)
                .lineColor(line.color)
                .lineWidth(line.width)
                .lineSortKey(line.sortKey)
        }
        .lineCap(.round)
        .lineJoin(.round)
        if let privateRange = track.privateRange {
            MapViewAnnotation(coordinate: coordinates[privateRange.lowerBound]) {
                Image(systemName: "eye.slash.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(Color(.systemGray), in: Circle())
            }
            .allowOverlap(true)
        }
        ForEvery(track.gapIndices, id: \.self) { index in
            MapViewAnnotation(coordinate: coordinates[index]) {
                Image(systemName: "pause.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(Color.orange, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 2))
            }
            .allowOverlap(true)
        }
    }
}

private struct ProtoLine {
    let id: String
    let coordinates: [CLLocationCoordinate2D]
    let color: UIColor
    let width: Double
    let sortKey: Double
}

extension ProtoTrackContent {
    /// Zone de confidentialité pâle, reste de la trace gris, portion choisie orange par-dessus.
    fileprivate func lines(_ coordinates: [CLLocationCoordinate2D]) -> [ProtoLine] {
        var lines: [ProtoLine] = []
        if let privateRange = track.privateRange {
            lines.append(ProtoLine(
                id: "private",
                coordinates: Array(coordinates[privateRange.lowerBound...min(privateRange.upperBound + 1, coordinates.count - 1)]),
                color: UIColor.systemGray3, width: 4, sortKey: 0
            ))
        }
        lines.append(ProtoLine(id: "rest", coordinates: Array(coordinates[track.firstAllowed...]), color: UIColor.darkGray.withAlphaComponent(0.75), width: 4, sortKey: 1))
        lines.append(ProtoLine(id: "selected-\(range)", coordinates: Array(coordinates[range]), color: UIColor(Theme.accent), width: 6, sortKey: 2))
        return lines
    }
}

extension ProtoTrack {
    func overview(padding: SwiftUI.EdgeInsets = SwiftUI.EdgeInsets(top: 60, leading: 40, bottom: 60, trailing: 40)) -> Viewport {
        .overview(geometry: LineString(coordinates), geometryPadding: padding)
    }
}

// MARK: - Profil d'altitude de toute l'Activité avec la portion

struct ProtoRangeProfile: View {
    let track: ProtoTrack
    @Binding var range: ClosedRange<Int>
    /// Variante A : poignées déplaçables sur le profil.
    var isInteractive = false

    @State private var draggedHandle: Handle?
    private enum Handle { case start, finish }

    var body: some View {
        let kilometers = track.cumulative.map { $0 / 1_000 }
        Chart {
            if let privateRange = track.privateRange {
                RectangleMark(
                    xStart: .value("km", kilometers[privateRange.lowerBound]),
                    xEnd: .value("km", kilometers[privateRange.upperBound + 1])
                )
                .foregroundStyle(Color(.systemGray4).opacity(0.6))
                .annotation(position: .top, alignment: .leading) {
                    Image(systemName: "eye.slash").font(.caption2).foregroundStyle(.secondary)
                }
            }
            ForEach(track.points.indices, id: \.self) { index in
                AreaMark(
                    x: .value("km", kilometers[index]),
                    yStart: .value("Altitude", yDomain.lowerBound),
                    yEnd: .value("Altitude", track.points[index].altitude),
                    series: .value("s", "all")
                )
                .foregroundStyle(Color(.systemGray5))
            }
            ForEach(Array(range), id: \.self) { index in
                AreaMark(
                    x: .value("km", kilometers[index]),
                    yStart: .value("Altitude", yDomain.lowerBound),
                    yEnd: .value("Altitude", track.points[index].altitude),
                    series: .value("s", "selected")
                )
                .foregroundStyle(Theme.accent.opacity(0.45))
            }
            ForEach(track.gapIndices, id: \.self) { index in
                RuleMark(x: .value("km", kilometers[index]))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .annotation(position: .top) {
                        Image(systemName: "pause.circle.fill").font(.caption).foregroundStyle(.orange)
                    }
            }
            RuleMark(x: .value("km", kilometers[range.lowerBound]))
                .foregroundStyle(RouteEndpoint.start.color)
                .lineStyle(StrokeStyle(lineWidth: isInteractive ? 3 : 2))
            RuleMark(x: .value("km", kilometers[range.upperBound]))
                .foregroundStyle(RouteEndpoint.finish.color)
                .lineStyle(StrokeStyle(lineWidth: isInteractive ? 3 : 2))
        }
        .chartYScale(domain: yDomain)
        .chartXScale(domain: 0...(kilometers.last ?? 1))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel { if let meters = value.as(Double.self) { Text(ActivityFormatters.elevation(meters)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine()
                AxisValueLabel { if let km = value.as(Double.self) { Text("\(Int(km)) km") } }
            }
        }
        .chartOverlay { proxy in
            if isInteractive {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Rectangle().fill(.clear).contentShape(Rectangle())
                            .gesture(drag(proxy: proxy, geometry: geometry))
                        handle(.start, proxy: proxy, geometry: geometry)
                        handle(.finish, proxy: proxy, geometry: geometry)
                    }
                }
            }
        }
    }

    private func handle(_ which: Handle, proxy: ChartProxy, geometry: GeometryProxy) -> some View {
        let index = which == .start ? range.lowerBound : range.upperBound
        let plot = geometry[proxy.plotFrame!]
        let x = (proxy.position(forX: track.cumulative[index] / 1_000) ?? 0) + plot.minX
        let endpoint: RouteEndpoint = which == .start ? .start : .finish
        return RouteEndpointMarker(endpoint: endpoint)
            .scaleEffect(draggedHandle == which ? 1.3 : 1)
            .position(x: x, y: plot.maxY + 2)
            .allowsHitTesting(false)
    }

    /// Le doigt prend la poignée la plus proche puis la promène ; la portion garde au moins un point.
    private func drag(proxy: ChartProxy, geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let plot = geometry[proxy.plotFrame!]
                guard let km: Double = proxy.value(atX: value.location.x - plot.minX) else { return }
                let index = max(track.index(atMeters: km * 1_000), track.firstAllowed)
                if draggedHandle == nil {
                    let toStart = abs(index - range.lowerBound)
                    let toFinish = abs(index - range.upperBound)
                    draggedHandle = toStart <= toFinish ? .start : .finish
                }
                switch draggedHandle {
                case .start: range = min(index, range.upperBound - 1)...range.upperBound
                case .finish: range = range.lowerBound...max(index, range.lowerBound + 1)
                case nil: break
                }
            }
            .onEnded { _ in draggedHandle = nil }
    }

    private var yDomain: ClosedRange<Double> {
        let altitudes = track.points.map(\.altitude)
        let low = altitudes.min() ?? 0
        let high = altitudes.max() ?? 100
        return (low - (high - low) * 0.1)...(high + (high - low) * 0.15)
    }
}

// MARK: - Stats d'une portion

struct ProtoPortionStats: View {
    let portion: ProtoPortion
    var compact = false

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            GridRow {
                stat(ProtoFormat.distance(portion.meters), "Distance")
                stat(ActivityFormatters.elevation(portion.elevationGain), "D+")
                stat(ProtoFormat.grade(portion.averageGrade), "Pente moy.")
                if !compact {
                    stat(portion.category ?? "—", "Catégorie")
                }
            }
            if !compact {
                GridRow {
                    stat(ProtoFormat.grade(portion.maxGrade), "Pente max")
                    stat(ActivityFormatters.elevation(portion.lowest), "Alt. basse")
                    stat(ActivityFormatters.elevation(portion.highest), "Alt. haute")
                    Color.clear.frame(height: 1)
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline).monospacedDigit().contentTransition(.numericText())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Tracé de la portion seule, non touchable : l'aperçu avant de nommer.
struct ProtoPortionMiniMap: View {
    let coordinates: [Coordinate]

    var body: some View {
        let line = coordinates.map(\.locationCoordinate)
        Map(initialViewport: .overview(geometry: LineString(line), geometryPadding: EdgeInsets(top: 30, leading: 30, bottom: 30, trailing: 30))) {
            PolylineAnnotation(lineCoordinates: line)
                .lineColor(UIColor(Theme.accent))
                .lineWidth(5)
                .lineJoin(.round)
            RouteEndpointsContent(coordinates: line)
        }
        .mapStyle(.outdoors)
        .gestureOptions(GestureOptions(panEnabled: false, pinchEnabled: false, rotateEnabled: false, pitchEnabled: false, doubleTapToZoomInEnabled: false, doubleTouchToZoomOutEnabled: false, quickZoomEnabled: false))
    }
}
#endif
