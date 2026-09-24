import SwiftUI

@main
struct StravaCloneApp: App {
    private let di: Di

    init() {
        do {
            di = try Di.live()
        } catch {
            fatalError("Unable to open the local database: \(error)")
        }
        di.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(recordingStore: di.makeRecordingStore())
                .tint(Theme.accent)
        }
    }
}

struct RootView: View {
    @State var recordingStore: RecordingStore

    var body: some View {
        TabView {
            FeedView()
                .tabItem { Label("Fil", systemImage: "house") }
            RecordingView(store: recordingStore)
                .tabItem { Label("Enregistrer", systemImage: "record.circle") }
            SegmentsView()
                .tabItem { Label("Segments", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
            ProfileView()
                .tabItem { Label("Profil", systemImage: "person") }
            AuthView()
                .tabItem { Label("Compte", systemImage: "person.badge.key") }
        }
    }
}
