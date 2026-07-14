import SpriteKit

/// Fixed-position on-screen joystick: touch anywhere on the left/bottom of the screen to drag it, the
/// knob tracks your finger's direction relative to the joystick's fixed anchor. GameScene calls
/// `place(at:)` once (and again whenever the HUD re-lays-out) to set the anchor, `beginDrag()` on
/// touch-down, `updateDrag(touchLocation:)` on every touch-moved, and `endDrag()` on touch-up/cancel.
/// Purely a direction-vector producer — it does not move the player itself.
///
/// Always visible (dimmed when idle, full brightness while dragging) rather than appearing/disappearing
/// per touch — this followed repeated "stuck after lifting finger" reports that survived several
/// targeted patches on the old floating/show-hide design. Making it permanently on-screen at a fixed
/// anchor removes the entire activate/deactivate visibility state machine that kept being the site of
/// the bug: there is no longer a "hidden" state for anything to get stuck in, and every gameplay-facing
/// state change (currentVector, isDragging) happens instantly and synchronously — any cosmetic
/// SKAction (fade/knob-recenter) is layered on top afterward and can be interrupted or dropped entirely
/// without affecting correctness.
final class VirtualJoystick: SKNode {

    /// Normalized direction, each axis roughly -1...1, magnitude 0...1 (0 when idle/dead-zoned).
    private(set) var currentVector: CGVector = .zero
    private(set) var isDragging: Bool = false

    private var knobNode: SKShapeNode!

    private static let idleAlpha: CGFloat = 0.4
    private static let draggingAlpha: CGFloat = 1.0

    static func make() -> VirtualJoystick {
        let joystick = VirtualJoystick()
        joystick.zPosition = ZPosition.hud
        joystick.alpha = idleAlpha
        joystick.isHidden = false
        joystick.isUserInteractionEnabled = false // GameScene routes touches into it; it doesn't hit-test itself

        let base = SKShapeNode(circleOfRadius: JoystickConfig.baseRadius)
        base.fillColor = SKColor(red: 0.08, green: 0.05, blue: 0.12, alpha: 0.35)
        base.strokeColor = SKColor(red: 0.85, green: 0.55, blue: 0.95, alpha: 0.5)
        base.lineWidth = 2
        base.glowWidth = 1.5
        base.zPosition = 0
        joystick.addChild(base)

        // Faint ember ring accent to tie into the NightFeed palette.
        let accentRing = SKShapeNode(circleOfRadius: JoystickConfig.baseRadius - 4)
        accentRing.fillColor = .clear
        accentRing.strokeColor = SKColor(red: 1.0, green: 0.45, blue: 0.2, alpha: 0.25)
        accentRing.lineWidth = 1
        accentRing.zPosition = 0.5
        joystick.addChild(accentRing)
        // Otherwise this ring sits completely still on screen for the entire run — a slow, very
        // subtle breathing scale keeps the always-visible idle joystick from reading as dead chrome,
        // without ever competing with beginDrag()/endDrag()'s own alpha fades (different property).
        JuiceEffects.idleBreathe(accentRing, amplitude: 0.06, period: 2.4)

        let knob = SKShapeNode(circleOfRadius: JoystickConfig.knobRadius)
        knob.fillColor = SKColor(red: 0.55, green: 0.18, blue: 0.7, alpha: 0.85)
        knob.strokeColor = SKColor(red: 1.0, green: 0.85, blue: 0.95, alpha: 0.8)
        knob.lineWidth = 1.5
        knob.glowWidth = 2
        knob.zPosition = 1
        joystick.addChild(knob)
        joystick.knobNode = knob

        return joystick
    }

    /// Sets the joystick's fixed on-screen anchor (in the coordinate space of whatever layer it's a
    /// child of). Safe to call at any time, including mid-drag — GameScene calls this from layoutHUD.
    func place(at point: CGPoint) {
        position = point
    }

    /// Begins tracking a new drag. Always resets to a clean state rather than assuming anything about
    /// prior state — safe to call even if already dragging.
    func beginDrag() {
        removeAllActions()
        currentVector = .zero
        knobNode.position = .zero
        isDragging = true
        run(SKAction.fadeAlpha(to: Self.draggingAlpha, duration: 0.1))
    }

    /// point is the live touch location in the same coordinate space; the knob is clamped to
    /// baseRadius from the fixed anchor, currentVector updates continuously.
    func updateDrag(touchLocation: CGPoint) {
        guard isDragging else { return }

        let dx = touchLocation.x - position.x
        let dy = touchLocation.y - position.y
        let dist = sqrt(dx * dx + dy * dy)

        let clampedDist = min(dist, JoystickConfig.baseRadius)
        if dist > 0 {
            knobNode.position = CGPoint(x: dx / dist * clampedDist, y: dy / dist * clampedDist)
        } else {
            knobNode.position = .zero
        }

        let rawMagnitude = min(1, dist / JoystickConfig.baseRadius)
        if rawMagnitude < JoystickConfig.deadZone || dist == 0 {
            currentVector = .zero
        } else {
            // Rescale so magnitude ramps from 0 right at the dead-zone edge instead of jumping.
            let adjusted = (rawMagnitude - JoystickConfig.deadZone) / (1 - JoystickConfig.deadZone)
            currentVector = CGVector(dx: (dx / dist) * adjusted, dy: (dy / dist) * adjusted)
        }
    }

    /// Ends the drag. currentVector/isDragging change instantly and synchronously — the knob easing
    /// back to center and the fade to idle alpha below are purely cosmetic and can't desync gameplay
    /// even if interrupted by a new beginDrag() a moment later (which removeAllActions()s them anyway).
    func endDrag() {
        isDragging = false
        currentVector = .zero

        removeAllActions()
        knobNode.run(SKAction.move(to: .zero, duration: 0.1))
        run(SKAction.fadeAlpha(to: Self.idleAlpha, duration: 0.15))
    }
}
