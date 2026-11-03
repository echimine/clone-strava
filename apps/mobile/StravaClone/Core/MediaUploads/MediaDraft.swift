import Foundation

/// What a screen needs to add Media to an Activity (ADR-037 §5): the board of the Media being
/// sent, and the queue's `enqueue`. Handed by the app shell to the edit sheet (and to the
/// finish screen, #185), so no feature imports another.
struct ActivityMediaUploads {
    let board: MediaUploadBoard
    let enqueue: @MainActor (_ picked: [(media: PickedMedia, position: Int)], _ activityID: ActivityID) async -> Void
}

/// The "Photos et vidéos" section while the sheet is open (ADR-037 §10): the Activity's Media
/// in carousel order (confirmed and still being sent), then those just picked. The phone stops
/// the athlete at 8, counting those being sent. #184 adds "Mettre en premier", "Supprimer" and
/// the order.
struct MediaDraft: Equatable {
    static let limit = 8

    /// One tile of the strip.
    enum Item: Identifiable, Hashable {
        /// Confirmed, or still being sent (`media.upload`).
        case existing(ActivityMedia)
        /// Picked during this session, sent at "Enregistrer".
        case added(PickedMedia)

        var id: UUID {
            switch self {
            case .existing(let media): media.id
            case .added(let picked): picked.id
            }
        }

        static func == (lhs: Item, rhs: Item) -> Bool {
            switch (lhs, rhs) {
            case (.existing(let left), .existing(let right)): left == right
            case (.added(let left), .added(let right)): left.id == right.id
            default: false
            }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    let hasMap: Bool
    var mediaFirst: Bool
    private(set) var items: [Item]

    init(media: [ActivityMedia], hasMap: Bool, mediaFirst: Bool) {
        self.hasMap = hasMap
        self.mediaFirst = mediaFirst
        items = media.map(Item.existing)
    }

    var count: Int { items.count }
    var remaining: Int { max(0, Self.limit - count) }

    /// The strip's tiles: the map (when there is one) at its place, then the Media.
    var slides: [ActivitySlide<Item>] {
        ActivitySlide.compose(hasMap: hasMap, media: items, mediaFirst: mediaFirst)
    }

    var added: [PickedMedia] {
        items.compactMap { if case .added(let picked) = $0 { picked } else { nil } }
    }

    var hasChanges: Bool { !added.isEmpty }

    /// The full order (`mediaOrder`), Media still being sent and just picked included.
    var order: [UUID] { items.map(\.id) }

    /// The Media to send, each at its index in `order` (its `position`).
    var queued: [(media: PickedMedia, position: Int)] {
        items.enumerated().compactMap { index, item in
            if case .added(let picked) = item { (picked, index) } else { nil }
        }
    }

    /// Appends the picked Media in their selection order, as many as the limit leaves.
    mutating func add(_ picked: [PickedMedia]) {
        items += picked.prefix(remaining).map(Item.added)
    }
}
