import SwiftUI

@main
struct NightFeedApp: App {
    var body: some Scene {
        WindowGroup {
            GameRootView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
        }
    }
}
