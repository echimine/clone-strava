import MapboxMaps
import SwiftUI

/// A medalled Segment on the Activity's map (ADR-039 §15): its ribbon at the Segment's start,
/// with the phrase (« Record personnel ») then its name.
struct SegmentMedalMark: Identifiable, Hashable, Sendable {
    let id: String
    let medal: Medal
    let phrase: String
    let name: String
    let coordinate: Coordinate

    /// The medalled Efforts, in trace order; a Segment without a Medal has no badge.
    static func marks(_ results: ActivityResults?) -> [SegmentMedalMark] {
        (results?.efforts ?? []).compactMap { effort in
            effort.medal.map {
                SegmentMedalMark(
                    id: effort.id,
                    medal: $0,
                    phrase: ActivityResultsMessages.segmentMedal($0),
                    name: effort.segmentName,
                    coordinate: effort.startPoint
                )
            }
        }
    }
}

/// The ribbons on a Mapbox map: on the trace, the label to the right without a background, with
/// a white outline. Labels that touch hide one another (`allowOverlap(false)`).
struct SegmentMedalMarksContent: MapContent {
    let marks: [SegmentMedalMark]

    var body: some MapContent {
        ForEvery(marks) { mark in
            MapViewAnnotation(coordinate: mark.coordinate.locationCoordinate) {
                SegmentMedalLabel(mark: mark)
            }
            .allowOverlap(false)
            .variableAnchors([ViewAnnotationAnchorConfig(anchor: .left, offsetX: -14)])
        }
    }
}

private struct SegmentMedalLabel: View {
    let mark: SegmentMedalMark

    var body: some View {
        HStack(spacing: 4) {
            MedalRibbon(mark.medal, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(mark.phrase)
                Text(mark.name).lineLimit(2)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(white: 0.15))
            .shadow(color: .white, radius: 1)
            .shadow(color: .white, radius: 1)
            .shadow(color: .white, radius: 2)
        }
        .frame(width: 190, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
