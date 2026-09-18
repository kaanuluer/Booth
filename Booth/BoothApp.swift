import SwiftUI

@main
struct BoothApp: App {
    @StateObject private var store = EpisodeStore()

    var body: some Scene {
        WindowGroup {
            LibraryView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(BoothTheme.accent)
        }
    }
}
