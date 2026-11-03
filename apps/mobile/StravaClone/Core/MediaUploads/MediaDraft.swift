import Foundation

/// The "Photos et vidéos" section while the sheet is open (ADR-037 §10): the Activity's Media
/// in carousel order (confirmed and still being sent), then those just picked. The phone stops
/// the athlete at 8, counting those being sent. "Mettre en premier", "Supprimer" and "Modifier
/// l'ordre" only change this value; "Enregistrer" applies it (`ActivityMediaUploads.save`).
///
/// The map is always 1st or 2nd: only the first Media may go before it (`mediaFirst`).
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

    /// What a tap on a Media tile offers.
    enum Action: Hashable {
        /// "Mettre en premier": the Media at the head, the map right after.
        case putFirst
        /// "Remettre la carte en premier", on the Media already before the map.
        case putMapFirst
        /// "Supprimer".
        case remove
    }

    let hasMap: Bool
    var mediaFirst: Bool
    private(set) var items: [Item]
    /// Confirmed or still being sent, "Supprimer" in this session: deleted at "Enregistrer".
    private(set) var removed: [ActivityMedia] = []
    private let initialOrder: [UUID]
    private let initialMediaFirst: Bool

    init(media: [ActivityMedia], hasMap: Bool, mediaFirst: Bool) {
        self.hasMap = hasMap
        self.mediaFirst = mediaFirst
        items = media.map(Item.existing)
        initialOrder = media.map(\.id)
        initialMediaFirst = mediaFirst
    }

    var count: Int { items.count }
    var remaining: Int { max(0, Self.limit - count) }
    /// "Modifier l'ordre", from 2 Media.
    var canReorder: Bool { count >= 2 }

    /// The strip's tiles: the map (when there is one) at its place, then the Media.
    var slides: [ActivitySlide<Item>] {
        ActivitySlide.compose(hasMap: hasMap, media: items, mediaFirst: mediaFirst)
    }

    var added: [PickedMedia] {
        items.compactMap { if case .added(let picked) = $0 { picked } else { nil } }
    }

    /// Whether the map comes after the first Media (only with a map and Media).
    var showsMediaFirst: Bool { hasMap && mediaFirst && !items.isEmpty }

    /// Something to send at "Enregistrer": a Media added or removed, or another order.
    var hasChanges: Bool {
        !added.isEmpty || !removed.isEmpty || order != initialOrder
            || showsMediaFirst != (hasMap && initialMediaFirst && !initialOrder.isEmpty)
    }

    /// The full order (`mediaOrder`), Media still being sent and just picked included.
    var order: [UUID] { items.map(\.id) }

    /// The Media to send, each at its index in `order` (its `position`).
    var queued: [(media: PickedMedia, position: Int)] {
        items.enumerated().compactMap { index, item in
            if case .added(let picked) = item { (picked, index) } else { nil }
        }
    }

    /// `activity_media_saved` (ADR-037 §13); nil for a session that changed nothing. Async for
    /// `videosTrimmed`: it reads the picked videos' durations (their copies, made for the tiles).
    func saved() async -> ActivityMediaSaved? {
        guard hasChanges else { return nil }
        return ActivityMediaSaved(
            photosAdded: added.count { $0.kind == .photo },
            videosAdded: added.count { $0.kind == .video },
            videosTrimmed: await videosTrimmed(),
            mediaRemoved: removed.count,
            mediaFirst: showsMediaFirst,
            mediaCount: count
        )
    }

    /// The videos picked during this session that are cut at their first minute ("Vidéo coupée
    /// à 1 min").
    func videosTrimmed() async -> Int {
        var count = 0
        for picked in added where await picked.isTrimmed() {
            count += 1
        }
        return count
    }

    /// The tap menu of the Media `id`.
    func actions(for id: UUID) -> [Action] {
        let isHead = items.first?.id == id
        if hasMap {
            return [mediaFirst && isHead ? .putMapFirst : .putFirst, .remove]
        }
        return isHead ? [.remove] : [.putFirst, .remove]
    }

    /// Appends the picked Media in their selection order, as many as the limit leaves.
    mutating func add(_ picked: [PickedMedia]) {
        items += picked.prefix(remaining).map(Item.added)
    }

    /// "Mettre en premier": at the head, before the map when there is one.
    mutating func putFirst(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.insert(items.remove(at: index), at: 0)
        if hasMap { mediaFirst = true }
    }

    /// "Remettre la carte en premier".
    mutating func putMapFirst() {
        mediaFirst = false
    }

    /// "Supprimer". The Media before the map gone, the map is first again (as the server does
    /// on `DELETE`).
    mutating func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        if case .existing(let media) = items.remove(at: index) {
            removed.append(media)
        }
        if index == 0 || items.isEmpty { mediaFirst = false }
    }

    /// A Media gone outside the session ("Retirer" on a failed tile): dropped, not counted as
    /// removed.
    mutating func discard(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)
        if index == 0 || items.isEmpty { mediaFirst = false }
    }

    /// "Modifier l'ordre": the Media alone, the map keeps its place after the first one.
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().map { items[$0] }
        for index in source.sorted(by: >) {
            items.remove(at: index)
        }
        let insertion = destination - source.count { $0 < destination }
        items.insert(contentsOf: moving, at: min(max(insertion, 0), items.count))
    }
}

/// The properties of `activity_media_saved` (ADR-037 §13): what one session changed, and the
/// Activity's Media once saved. No id, no image data.
struct ActivityMediaSaved: Equatable, Sendable {
    var photosAdded: Int
    var videosAdded: Int
    var videosTrimmed: Int
    var mediaRemoved: Int
    /// The first Media goes before the map.
    var mediaFirst: Bool
    var mediaCount: Int
}
