import SwiftUI
import SpriteKit
import UIKit

struct GameRootView: View {
    var body: some View {
        SpriteKitContainer()
            .ignoresSafeArea()
            .statusBarHidden(true)
    }
}

/// SwiftUI's `SpriteView` bridges touches through its own gesture-recognizer layer, which has
/// real-world reports of intermittently dropping/never-delivering a `touchesEnded` to the scene
/// (the joystick "stuck after lifting finger" symptom). A raw `SKView` inside `UIViewRepresentable`
/// is the classic UIKit template path — UIKit delivers touches to the view/scene directly, with no
/// SwiftUI gesture arbitration in between.
private struct SpriteKitContainer: UIViewRepresentable {
    func makeUIView(context: Context) -> SKView {
        let view = SKView(frame: UIScreen.main.bounds)
        view.ignoresSiblingOrder = true
        view.preferredFramesPerSecond = 60
        view.showsFPS = false
        view.showsNodeCount = false
        view.isMultipleTouchEnabled = false
        view.presentScene(MenuScene.newScene())
        return view
    }

    func updateUIView(_ uiView: SKView, context: Context) {}
}
