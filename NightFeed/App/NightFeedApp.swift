import SwiftUI

@main
struct NightFeedApp: App {
    init() {
        FirebaseManager.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            GameRootView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
