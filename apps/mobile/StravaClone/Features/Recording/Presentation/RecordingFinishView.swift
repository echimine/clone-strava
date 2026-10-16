import SwiftUI

/// Finish screen (ADR-031 §11): full screen, left only through Save, Resume or Delete.
/// Title prefilled with the server's formula (back to it when emptied), visibility preselected
/// on `defaultVisibility`; neither is saved with the Recording. Mini-map and the sport's final
/// stats, without a "provisional" label. Save is disabled below the sport's minimum duration or
/// with fewer than 2 points, with the explanation.
/// It opens with the celebration (ADR-032 §5) when the Recording is eligible, unless Reduce
/// Motion is on; Resume then finish again plays it again (a new finish screen).
struct RecordingFinishView: View {
    let store: RecordingStore
    let snapshot: RecordingSnapshot
    /// After Save: the app shell switches to the top of the feed.
    var onSaved: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var celebrationSpace
    @State private var celebration: CelebrationPhase
    @State private var confirmsDelete = false
    @State private var title = ""
    @State private var visibility = ActivityVisibility.public
    @FocusState private var editsTitle: Bool

    init(store: RecordingStore, snapshot: RecordingSnapshot, onSaved: @escaping () -> Void = {}) {
        self.store = store
        self.snapshot = snapshot
        self.onSaved = onSaved
        _celebration = State(initialValue: CelebrationEligibility.allows(snapshot) ? .playing : .over)
    }

    private var showsCelebration: Bool {
        celebration != .over && !reduceMotion
    }

    private var hidesForm: Bool {
        celebration == .playing && !reduceMotion
    }

    private var canSave: Bool {
        snapshot.saveBlocker == nil && !store.isBusy
    }

    var body: some View {
        ZStack {
            form
                .opacity(hidesForm ? 0 : 1)
                .accessibilityHidden(hidesForm)
                .allowsHitTesting(!hidesForm)
            if showsCelebration {
                RecordingCelebration(stats: snapshot.finalStats, namespace: celebrationSpace, phase: $celebration) { frame in
                    CelebrationMapBackground(trace: snapshot.trace, frame: frame)
                }
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .interactiveDismissDisabled()
        .onAppear {
            title = store.defaultTitle
            visibility = store.defaultVisibility
        }
        .confirmationDialog(RecordingMessages.deleteTitle, isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Supprimer", role: .destructive) { Task { await store.delete() } }
        } message: {
            Text(RecordingMessages.deleteMessage)
        }
    }

    private var form: some View {
        VStack(spacing: 20) {
            Label(
                RecordingFormatters.sportLabel(snapshot.recording.sport),
                systemImage: RecordingFormatters.sportSymbol(snapshot.recording.sport)
            )
            .font(.title3.weight(.bold))
            .padding(.top, 8)

            TextField(store.defaultTitle, text: $title)
                .font(.headline)
                .padding(12)
                .background(Color(.secondarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                .focused($editsTitle)
                .submitLabel(.done)
                .accessibilityIdentifier("recordingTitleField")
                .onChange(of: editsTitle) { _, editing in
                    if !editing, title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        title = store.defaultTitle
                    }
                }

            Picker("Visibilité", selection: $visibility) {
                ForEach(ActivityVisibility.allCases, id: \.self) { visibility in
                    Text(Self.label(visibility)).tag(visibility)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("recordingVisibilityPicker")

            CelebrationMiniMap(trace: snapshot.trace, namespace: celebrationSpace, isCelebrating: hidesForm)

            HStack(alignment: .top) {
                ForEach(FinishStatsCountUp.items(snapshot.finalStats, progress: 1)) { item in
                    VStack(spacing: 2) {
                        Text(item.value).font(.title2.weight(.bold)).monospacedDigit()
                        Text(item.caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            Spacer()

            if let message = store.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
            if let blocker = snapshot.saveBlocker {
                Text(RecordingMessages.saveBlocker(blocker, sport: snapshot.recording.sport))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("recordingSaveBlocker")
            }
            Button {
                editsTitle = false
                Task {
                    if await store.save(title: title, visibility: visibility) {
                        onSaved()
                    }
                }
            } label: {
                Text("Enregistrer")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.4)
            .accessibilityIdentifier("recordingSaveButton")

            HStack(spacing: 12) {
                Button("Reprendre") { Task { await store.reopen() } }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(.secondarySystemFill), in: Capsule())
                    .accessibilityIdentifier("recordingReopenButton")
                Button("Supprimer", role: .destructive) { confirmsDelete = true }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color(.secondarySystemFill), in: Capsule())
                    .accessibilityIdentifier("recordingDeleteButton")
            }
            .font(.headline)
            .buttonStyle(.plain)
        }
        .padding(Theme.spacing)
    }

    static func label(_ visibility: ActivityVisibility) -> String {
        switch visibility {
        case .public: "Tout le monde"
        case .followers: "Abonnés"
        case .private: "Moi uniquement"
        }
    }
}
