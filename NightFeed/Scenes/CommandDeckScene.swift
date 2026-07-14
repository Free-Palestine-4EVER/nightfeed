import SpriteKit

/// The Starfleet Command home base — the app's new front door. Shows the player's persistent
/// starship (EmpireStore-backed hull/drones), Crystal currency, harvester passive-income collection,
/// and routes into Survival Run (existing MenuScene/GameScene loop), the Fleet hangar, the Star Map,
/// Alliance (stubbed), and the Crystal Shop. Pure SpriteKit UI: every visual is code-drawn
/// (SKShapeNode/SKLabelNode/SKEmitterNode with ProceduralTextures-rendered textures), no image
/// assets. Manual name-based touch handling, no physics world — same interaction model as MenuScene.
final class CommandDeckScene: SKScene {

    // MARK: - Palette (deep-space navy-black, cyan crystal-tech glow, steel hull, ember engine trail —
    // a sci-fi fleet-command reskin that still shares NIGHTFEED's ember/moonlight night-vampiric DNA)

    private enum Palette {
        static let bgTop = SKColor(red: 0.03, green: 0.05, blue: 0.10, alpha: 1)
        static let bgBottom = SKColor(red: 0.01, green: 0.012, blue: 0.03, alpha: 1)
        static let nebulaViolet = SKColor(red: 0.30, green: 0.14, blue: 0.46, alpha: 1)
        static let nebulaCyan = SKColor(red: 0.08, green: 0.28, blue: 0.38, alpha: 1)
        static let starWhite = SKColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1)
        static let crystalCyan = SKColor(red: 0.35, green: 0.92, blue: 0.95, alpha: 1)
        static let crystalCyanBright = SKColor(red: 0.62, green: 1.0, blue: 1.0, alpha: 1)
        static let hullSteel = SKColor(red: 0.66, green: 0.74, blue: 0.84, alpha: 1)
        static let hullSteelDim = SKColor(red: 0.30, green: 0.36, blue: 0.46, alpha: 1)
        static let engineEmber = SKColor(red: 1.0, green: 0.5, blue: 0.22, alpha: 1)
        static let engineEmberBright = SKColor(red: 1.0, green: 0.72, blue: 0.35, alpha: 1)
        static let panelFill = SKColor(red: 0.05, green: 0.07, blue: 0.12, alpha: 0.93)
        static let panelStroke = SKColor(red: 0.32, green: 0.55, blue: 0.62, alpha: 0.55)
        static let rowFill = SKColor(red: 0.08, green: 0.11, blue: 0.17, alpha: 0.92)
        static let moonlightDim = SKColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 0.55)
        static let alertAmber = SKColor(red: 1.0, green: 0.75, blue: 0.25, alpha: 1)
    }

    static func newScene() -> CommandDeckScene {
        let scene = CommandDeckScene(size: CGSize(width: 393, height: 852))
        scene.scaleMode = .resizeFill
        return scene
    }

    // MARK: - Layers

    private let backgroundLayer = SKNode()
    private let starLayerFar = SKNode()
    private let starLayerNear = SKNode()
    private let shipLayer = SKNode()
    private let contentLayer = SKNode()
    private let toastLayer = SKNode()

    // MARK: - Background refs

    private var nebulaGlowA: SKSpriteNode!
    private var nebulaGlowB: SKSpriteNode!
    private var dustEmitter: SKEmitterNode!
    private var starFractionsFar: [(CGPoint, CGFloat)] = []
    private var starNodesFar: [SKShapeNode] = []
    private var starFractionsNear: [(CGPoint, CGFloat)] = []
    private var starNodesNear: [SKShapeNode] = []

    // MARK: - Starship refs

    private var shipOuter: SKNode!   // entrance target (alpha/scale pop)
    private var shipInner: SKNode!   // ambient hover bob
    private var shipGlowSprite: SKSpriteNode!
    private var shipSprite: SKSpriteNode!
    private var orbitPivot: SKNode!
    private var engineEmitter: SKEmitterNode!
    private var droneBadgeNodes: [SKNode] = []

    // MARK: - Header refs

    private var titleShadow: SKLabelNode!
    private var titleLabel: SKLabelNode!
    private var subtitleLabel: SKLabelNode!
    private var crystalGlow: SKSpriteNode!
    private var crystalChipBG: SKShapeNode!
    private var crystalIcon: SKSpriteNode!
    private var crystalLabel: SKLabelNode!
    private var selectedPlanetDot: SKShapeNode!
    private var selectedPlanetLabel: SKLabelNode!

    // MARK: - Collect Harvester refs

    private var collectContainer: SKNode!
    private var collectGlow: SKSpriteNode!
    private var collectButton: SKShapeNode!
    private var collectLabel: SKLabelNode!
    private var isHarvesterCollectVisible = false

    // MARK: - Navigation refs

    private var survivalButton: SKShapeNode!
    private var survivalLabel: SKLabelNode!

    private struct NavChip {
        let container: SKShapeNode
        let icon: SKNode
        let label: SKLabelNode
    }
    private var navChips: [String: NavChip] = [:]

    private static let navChipOrder: [(name: String, title: String)] = [
        ("goFleet", "FLEET"),
        ("goStarMap", "STAR MAP"),
        ("goAlliance", "ALLIANCE"),
        ("goCoinShop", "SHOP"),
        ("goMarketplace", "MARKET")
    ]
    private static let chipSize: CGFloat = 72
    private static let chipGap: CGFloat = 10

    // MARK: - Toast refs

    private var toastContainer: SKNode!
    private var toastLabel: SKLabelNode!

    // MARK: - State

    private var pressedNodeName: String?
    private var hasBuiltOnce = false

    private static let interactiveNames: Set<String> = ["goSurvival", "goFleet", "goStarMap", "goAlliance", "goCoinShop", "goMarketplace"]

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.bgBottom

        if !hasBuiltOnce {
            addChild(backgroundLayer)
            addChild(starLayerFar)
            addChild(starLayerNear)
            addChild(shipLayer)
            addChild(contentLayer)
            addChild(toastLayer)
            backgroundLayer.zPosition = ZPosition.menuUI - 6
            starLayerFar.zPosition = ZPosition.menuUI - 5
            starLayerNear.zPosition = ZPosition.menuUI - 4
            shipLayer.zPosition = ZPosition.menuUI - 1
            contentLayer.zPosition = ZPosition.menuUI
            toastLayer.zPosition = ZPosition.menuUI + 60

            buildBackground()
            buildStars()
            buildStarship()
            buildHeader()
            buildPlanetReadout()
            buildCollectHarvester()
            buildPrimaryButton()
            buildNavChips()
            buildToast()

            refreshHarvesterCollect(animated: false)

            hasBuiltOnce = true
            layout(size: size)
            playEntranceAnimations()

            run(SKAction.repeatForever(SKAction.sequence([
                SKAction.wait(forDuration: 1.0),
                SKAction.run { [weak self] in self?.refreshHarvesterCollect(animated: true) }
            ])), withKey: "harvesterPoll")
        } else {
            layout(size: size)
        }

        AudioManager.shared.startMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        guard hasBuiltOnce else { return }
        layout(size: size)
    }

    // MARK: - Background

    private func buildBackground() {
        let bg = SKSpriteNode(texture: Self.gradientTexture(top: Palette.bgTop, bottom: Palette.bgBottom, size: CGSize(width: 4, height: 512)))
        bg.name = "bgGradient"
        bg.zPosition = 0
        backgroundLayer.addChild(bg)

        let glowA = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.nebulaViolet, radius: 220))
        glowA.alpha = 0.32
        glowA.blendMode = .add
        glowA.zPosition = 1
        backgroundLayer.addChild(glowA)
        nebulaGlowA = glowA

        let glowB = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.nebulaCyan, radius: 260))
        glowB.alpha = 0.28
        glowB.blendMode = .add
        glowB.zPosition = 1
        backgroundLayer.addChild(glowB)
        nebulaGlowB = glowB

        let breatheA = SKAction.sequence([SKAction.fadeAlpha(to: 0.48, duration: 4.2), SKAction.fadeAlpha(to: 0.24, duration: 4.2)])
        breatheA.timingMode = .easeInEaseOut
        glowA.run(SKAction.repeatForever(breatheA))
        let breatheB = SKAction.sequence([SKAction.fadeAlpha(to: 0.42, duration: 5.0), SKAction.fadeAlpha(to: 0.18, duration: 5.0)])
        breatheB.timingMode = .easeInEaseOut
        glowB.run(SKAction.repeatForever(breatheB))

        let dust = SKEmitterNode()
        dust.particleTexture = ProceduralTextures.radialGlow(color: Palette.crystalCyan, radius: 6)
        dust.particleBirthRate = 4
        dust.particleLifetime = 9
        dust.particleLifetimeRange = 4
        dust.particleSpeed = 14
        dust.particleSpeedRange = 10
        dust.emissionAngle = .pi / 2
        dust.emissionAngleRange = .pi / 6
        dust.yAcceleration = 4
        dust.particleAlpha = 0.0
        dust.particleAlphaSequence = Self.dustAlphaSequence
        dust.particleScale = 0.3
        dust.particleScaleRange = 0.2
        dust.particleColorBlendFactor = 1
        dust.particleColor = Palette.crystalCyan
        dust.particleBlendMode = .add
        dust.zPosition = 2
        backgroundLayer.addChild(dust)
        dustEmitter = dust
    }

    private static let dustAlphaSequence: SKKeyframeSequence = {
        SKKeyframeSequence(keyframeValues: [0.0, 0.55, 0.35, 0.0], times: [0.0, 0.2, 0.7, 1.0])
    }()

    private func buildStars() {
        var rng = SystemRandomNumberGenerator()
        starFractionsFar.removeAll()
        starNodesFar.removeAll()
        for _ in 0..<40 {
            let fx = CGFloat.random(in: 0...1, using: &rng)
            let fy = CGFloat.random(in: 0...1, using: &rng)
            let r = CGFloat.random(in: 0.5...1.1, using: &rng)
            starFractionsFar.append((CGPoint(x: fx, y: fy), r))
            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor = Palette.starWhite
            dot.strokeColor = .clear
            dot.alpha = CGFloat.random(in: 0.12...0.4, using: &rng)
            starLayerFar.addChild(dot)
            starNodesFar.append(dot)
            let twinkle = SKAction.sequence([
                SKAction.fadeAlpha(to: dot.alpha * 0.3, duration: Double.random(in: 2.0...4.0)),
                SKAction.fadeAlpha(to: dot.alpha, duration: Double.random(in: 2.0...4.0))
            ])
            dot.run(SKAction.repeatForever(twinkle))
        }

        starFractionsNear.removeAll()
        starNodesNear.removeAll()
        for _ in 0..<26 {
            let fx = CGFloat.random(in: 0...1, using: &rng)
            let fy = CGFloat.random(in: 0...1, using: &rng)
            let r = CGFloat.random(in: 1.0...2.0, using: &rng)
            starFractionsNear.append((CGPoint(x: fx, y: fy), r))
            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor = Palette.starWhite
            dot.strokeColor = .clear
            dot.alpha = CGFloat.random(in: 0.3...0.75, using: &rng)
            starLayerNear.addChild(dot)
            starNodesNear.append(dot)
            let twinkle = SKAction.sequence([
                SKAction.fadeAlpha(to: dot.alpha * 0.25, duration: Double.random(in: 1.2...2.6)),
                SKAction.fadeAlpha(to: dot.alpha, duration: Double.random(in: 1.2...2.6))
            ])
            dot.run(SKAction.repeatForever(twinkle))
        }

        // Subtle two-speed parallax drift — far layer barely sways, near layer sways more.
        let outFar = SKAction.moveBy(x: -5, y: 0, duration: 14); outFar.timingMode = .easeInEaseOut
        let backFar = SKAction.moveBy(x: 5, y: 0, duration: 14); backFar.timingMode = .easeInEaseOut
        starLayerFar.run(SKAction.repeatForever(SKAction.sequence([outFar, backFar])))

        let outNear = SKAction.moveBy(x: -14, y: 0, duration: 10); outNear.timingMode = .easeInEaseOut
        let backNear = SKAction.moveBy(x: 14, y: 0, duration: 10); backNear.timingMode = .easeInEaseOut
        starLayerNear.run(SKAction.repeatForever(SKAction.sequence([outNear, backNear])))
    }

    // MARK: - Starship

    private func buildStarship() {
        let hullLevel = EmpireStore.shared.hullLevel
        let texture = Self.shipTexture(hullLevel: hullLevel)

        let outer = SKNode()
        shipLayer.addChild(outer)
        shipOuter = outer

        let inner = SKNode()
        outer.addChild(inner)
        shipInner = inner

        let glow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.crystalCyan, radius: 190))
        glow.blendMode = .add
        glow.alpha = 0.42
        glow.zPosition = 0
        inner.addChild(glow)
        shipGlowSprite = glow

        let sprite = SKSpriteNode(texture: texture)
        sprite.zPosition = 1
        inner.addChild(sprite)
        shipSprite = sprite

        let pivot = SKNode()
        pivot.zPosition = 2
        inner.addChild(pivot)
        orbitPivot = pivot

        let emitter = SKEmitterNode()
        emitter.particleTexture = ProceduralTextures.radialGlow(color: Palette.engineEmberBright, radius: 10)
        emitter.particleBirthRate = 40
        emitter.particleLifetime = 0.5
        emitter.particleLifetimeRange = 0.2
        emitter.particleSpeed = 70
        emitter.particleSpeedRange = 30
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = .pi / 14
        emitter.particleAlpha = 0.9
        emitter.particleAlphaSpeed = -2.2
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.5
        emitter.particleColorBlendFactor = 1
        emitter.particleColor = Palette.engineEmber
        emitter.particleBlendMode = .add
        emitter.position = CGPoint(x: 0, y: -sprite.size.height * 0.40)
        emitter.targetNode = shipLayer
        emitter.zPosition = 0
        inner.addChild(emitter)
        engineEmitter = emitter

        buildDroneBadges(around: sprite.size)
    }

    /// Small orbiting badges for whichever drones are currently equipped (EmpireStore.equippedDrones()).
    /// Nodes only — fade/scale-in handled by playEntranceAnimations(), rotation by startShipAmbientMotion(),
    /// so both the parent orbit and the child counter-rotation start on the same clock and stay in sync.
    private func buildDroneBadges(around shipSize: CGSize) {
        orbitPivot.removeAllChildren()
        droneBadgeNodes.removeAll()
        let drones = EmpireStore.shared.equippedDrones()
        guard !drones.isEmpty else { return }

        let radius = shipSize.width * 0.66
        let angleStep = (CGFloat.pi * 2) / CGFloat(max(drones.count, 3))
        for (i, kind) in drones.enumerated() {
            let angle = -CGFloat.pi / 2 + angleStep * CGFloat(i)
            let badge = SKNode()
            badge.position = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            badge.zPosition = 5
            badge.alpha = 0
            badge.setScale(0.3)

            let bg = SKShapeNode(circleOfRadius: 15)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Self.droneColor(kind)
            bg.lineWidth = 2
            badge.addChild(bg)

            let glyph = SKShapeNode(path: Self.droneGlyphPath(kind, radius: 7), centered: true)
            glyph.fillColor = Self.droneColor(kind)
            glyph.strokeColor = .clear
            badge.addChild(glyph)

            orbitPivot.addChild(badge)
            droneBadgeNodes.append(badge)
        }
    }

    private static func droneColor(_ kind: DroneKind) -> SKColor {
        switch kind {
        case .interceptor: return SKColor(red: 1.0, green: 0.45, blue: 0.32, alpha: 1)
        case .aegis: return SKColor(red: 0.42, green: 0.68, blue: 1.0, alpha: 1)
        case .harvester: return Palette.crystalCyan
        }
    }

    /// Triangle = offense, shield-pentagon = defense, diamond = economy — matches DroneKind's role.
    private static func droneGlyphPath(_ kind: DroneKind, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        switch kind {
        case .interceptor:
            path.move(to: CGPoint(x: 0, y: radius))
            path.addLine(to: CGPoint(x: radius * 0.86, y: -radius * 0.7))
            path.addLine(to: CGPoint(x: -radius * 0.86, y: -radius * 0.7))
            path.closeSubpath()
        case .aegis:
            path.move(to: CGPoint(x: 0, y: radius))
            path.addLine(to: CGPoint(x: radius * 0.85, y: radius * 0.25))
            path.addLine(to: CGPoint(x: radius * 0.55, y: -radius * 0.85))
            path.addLine(to: CGPoint(x: -radius * 0.55, y: -radius * 0.85))
            path.addLine(to: CGPoint(x: -radius * 0.85, y: radius * 0.25))
            path.closeSubpath()
        case .harvester:
            path.move(to: CGPoint(x: 0, y: radius))
            path.addLine(to: CGPoint(x: radius * 0.72, y: 0))
            path.addLine(to: CGPoint(x: 0, y: -radius))
            path.addLine(to: CGPoint(x: -radius * 0.72, y: 0))
            path.closeSubpath()
        }
        return path
    }

    /// Continuous ambient motion — hover bob, sway, glow pulse, drone orbit — kicked off once the
    /// entrance pop-in has finished so it never fights the one-shot entrance actions on the same nodes.
    private func startShipAmbientMotion() {
        let bobUp = SKAction.moveBy(x: 0, y: 8, duration: 2.4); bobUp.timingMode = .easeInEaseOut
        let bobDown = SKAction.moveBy(x: 0, y: -8, duration: 2.4); bobDown.timingMode = .easeInEaseOut
        shipInner.run(SKAction.repeatForever(SKAction.sequence([bobUp, bobDown])), withKey: "shipBob")

        let swayA = SKAction.rotate(byAngle: 0.035, duration: 3.0); swayA.timingMode = .easeInEaseOut
        let swayB = SKAction.rotate(byAngle: -0.07, duration: 6.0); swayB.timingMode = .easeInEaseOut
        let swayC = SKAction.rotate(byAngle: 0.035, duration: 3.0); swayC.timingMode = .easeInEaseOut
        shipSprite.run(SKAction.repeatForever(SKAction.sequence([swayA, swayB, swayC])), withKey: "shipSway")

        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 1.8),
            SKAction.fadeAlpha(to: 0.35, duration: 1.8)
        ])
        shipGlowSprite.run(SKAction.repeatForever(glowPulse), withKey: "shipGlowPulse")

        orbitPivot.run(SKAction.repeatForever(SKAction.rotate(byAngle: .pi * 2, duration: 22)), withKey: "orbitSpin")
        for badge in droneBadgeNodes {
            badge.run(SKAction.repeatForever(SKAction.rotate(byAngle: -.pi * 2, duration: 22)), withKey: "badgeCounterSpin")
        }
    }

    /// Procedural starfighter silhouette — a dart hull with swept wings, twin engine notches, a
    /// cockpit glow and spine plating whose density scales with hullLevel (more seams/struts at
    /// higher hull tiers, plus a modest size increase). Tasteful, capped growth — not garish.
    private static func shipTexture(hullLevel: Int) -> SKTexture {
        let clamped = max(0, min(hullLevel, EmpireStore.maxShipStatLevel))
        let growth = CGFloat(clamped) / CGFloat(EmpireStore.maxShipStatLevel)
        let size = CGSize(width: 210 + 50 * growth, height: 260 + 64 * growth)
        let platingCount = 3 + Int(growth * 6)

        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            func p(_ fx: CGFloat, _ fy: CGFloat) -> CGPoint { CGPoint(x: fx * w, y: fy * h) }

            let path = CGMutablePath()
            path.move(to: p(0.50, 0.02))
            path.addLine(to: p(0.62, 0.20))
            path.addLine(to: p(0.97, 0.60))
            path.addLine(to: p(0.72, 0.55))
            path.addLine(to: p(0.60, 0.74))
            path.addLine(to: p(0.66, 0.94))
            path.addLine(to: p(0.54, 0.87))
            path.addLine(to: p(0.50, 0.79))
            path.addLine(to: p(0.46, 0.87))
            path.addLine(to: p(0.34, 0.94))
            path.addLine(to: p(0.40, 0.74))
            path.addLine(to: p(0.28, 0.55))
            path.addLine(to: p(0.03, 0.60))
            path.addLine(to: p(0.38, 0.20))
            path.closeSubpath()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let colors = [Palette.hullSteel.cgColor, Palette.hullSteelDim.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: p(0.5, 0.0), end: p(0.5, 1.0), options: [])
            }
            ctx.restoreGState()

            ctx.addPath(path)
            ctx.setStrokeColor(Palette.crystalCyan.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(2.0)
            ctx.strokePath()

            // Spine plating seams — density rises with hull level.
            ctx.setStrokeColor(Palette.hullSteelDim.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1.2)
            for i in 0..<platingCount {
                let t = CGFloat(i + 1) / CGFloat(platingCount + 1)
                let y = 0.22 + t * 0.5
                let spread: CGFloat = 0.05 + t * 0.02
                ctx.move(to: p(0.5 - spread, y))
                ctx.addLine(to: p(0.5 + spread, y))
                ctx.strokePath()
            }
            // Extra wing struts only appear once hull plating is dense enough.
            if platingCount > 4 {
                ctx.setStrokeColor(Palette.hullSteelDim.withAlphaComponent(0.7).cgColor)
                ctx.move(to: p(0.40, 0.30)); ctx.addLine(to: p(0.20, 0.52)); ctx.strokePath()
                ctx.move(to: p(0.60, 0.30)); ctx.addLine(to: p(0.80, 0.52)); ctx.strokePath()
            }

            // Cockpit glow.
            let cockpitCenter = p(0.5, 0.16)
            let cockpitColors = [Palette.crystalCyanBright.cgColor, Palette.crystalCyan.withAlphaComponent(0.15).cgColor] as CFArray
            if let cg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cockpitColors, locations: [0, 1]) {
                ctx.drawRadialGradient(cg, startCenter: cockpitCenter, startRadius: 0, endCenter: cockpitCenter, endRadius: w * 0.07, options: [])
            }

            // Engine ports (the emitter/glow that anchors here live as separate scene nodes).
            ctx.setFillColor(SKColor(white: 0.05, alpha: 1).cgColor)
            let leftPort = p(0.34, 0.90)
            let rightPort = p(0.66, 0.90)
            ctx.fillEllipse(in: CGRect(x: leftPort.x - w * 0.05, y: leftPort.y - h * 0.025, width: w * 0.10, height: h * 0.05))
            ctx.fillEllipse(in: CGRect(x: rightPort.x - w * 0.05, y: rightPort.y - h * 0.025, width: w * 0.10, height: h * 0.05))
        }
    }

    // MARK: - Header

    private func buildHeader() {
        let shadow = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        shadow.text = "STARFLEET COMMAND"
        shadow.fontSize = 27
        shadow.fontColor = Palette.crystalCyan.withAlphaComponent(0.45)
        shadow.horizontalAlignmentMode = .center
        shadow.verticalAlignmentMode = .center
        shadow.zPosition = 0
        contentLayer.addChild(shadow)
        titleShadow = shadow

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "STARFLEET COMMAND"
        title.fontSize = 27
        title.fontColor = Palette.starWhite
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.zPosition = 1
        contentLayer.addChild(title)
        titleLabel = title

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.02, duration: 2.0),
            SKAction.scale(to: 1.0, duration: 2.0)
        ])
        pulse.timingMode = .easeInEaseOut
        title.run(SKAction.repeatForever(pulse))

        let sub = SKLabelNode(fontNamed: "AvenirNext-Medium")
        sub.text = Self.letterSpaced("NIGHTFEED · HOME BASE")
        sub.fontSize = 11.5
        sub.fontColor = Palette.crystalCyan
        sub.horizontalAlignmentMode = .center
        sub.verticalAlignmentMode = .center
        sub.zPosition = 1
        contentLayer.addChild(sub)
        subtitleLabel = sub

        // Crystal currency readout — glowing procedural gem icon + live count in a rounded chip.
        let glow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.crystalCyan, radius: 60))
        glow.blendMode = .add
        glow.alpha = 0.5
        glow.zPosition = 1
        contentLayer.addChild(glow)
        crystalGlow = glow

        let chip = SKShapeNode()
        chip.fillColor = Palette.rowFill
        chip.strokeColor = Palette.panelStroke
        chip.lineWidth = 1.4
        chip.zPosition = 2
        contentLayer.addChild(chip)
        crystalChipBG = chip

        let icon = SKSpriteNode(texture: Self.crystalIconTexture(diameter: 22))
        icon.zPosition = 3
        contentLayer.addChild(icon)
        crystalIcon = icon

        let count = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        count.text = "\(EmpireStore.shared.crystals)"
        count.fontSize = 18
        count.fontColor = Palette.crystalCyanBright
        count.verticalAlignmentMode = .center
        count.zPosition = 3
        contentLayer.addChild(count)
        crystalLabel = count

        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.75, duration: 1.6),
            SKAction.fadeAlpha(to: 0.35, duration: 1.6)
        ])
        glow.run(SKAction.repeatForever(glowPulse))
    }

    private func refreshCrystalLabel() {
        crystalLabel.text = "\(EmpireStore.shared.crystals)"
    }

    // MARK: - Selected planet readout (purely informational for now)

    private func buildPlanetReadout() {
        let dot = SKShapeNode(circleOfRadius: 4)
        dot.fillColor = Palette.engineEmberBright
        dot.strokeColor = .clear
        dot.zPosition = 1
        contentLayer.addChild(dot)
        selectedPlanetDot = dot

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = "ORBITING: \(EmpireStore.shared.selectedPlanet.displayName.uppercased())"
        label.fontSize = 12
        label.fontColor = Palette.moonlightDim
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        contentLayer.addChild(label)
        selectedPlanetLabel = label
    }

    // MARK: - Collect Harvester

    private func buildCollectHarvester() {
        let container = SKNode()
        container.isHidden = true
        contentLayer.addChild(container)
        collectContainer = container

        let glow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.crystalCyan, radius: 90))
        glow.blendMode = .add
        glow.alpha = 0.5
        glow.zPosition = 0
        container.addChild(glow)
        collectGlow = glow

        let (btn, label) = Self.makeButton(text: "COLLECT", width: 210, height: 46,
                                            fill: Palette.rowFill, stroke: Palette.crystalCyanBright,
                                            textColor: Palette.crystalCyanBright,
                                            fontSize: 16, fontName: "AvenirNext-Heavy")
        btn.name = "collectHarvester"
        label.name = "collectHarvester"
        btn.zPosition = 1
        label.zPosition = 2
        container.addChild(btn)
        container.addChild(label)
        collectButton = btn
        collectLabel = label
    }

    /// `animated == false` is used for the very first (silent) sync at scene build time — the
    /// staggered pop-in for a visible button is instead handled by playEntranceAnimations() so it
    /// stays in lockstep with everything else's entrance timing. `animated == true` is the ongoing
    /// runtime path (the 1s poll loop, and right after a collect), where show/hide really do animate.
    private func refreshHarvesterCollect(animated: Bool) {
        let pending = EmpireStore.shared.pendingHarvesterIncome()
        let shouldShow = pending > 0
        collectLabel.text = "COLLECT +\(pending) ⬥"

        guard shouldShow != isHarvesterCollectVisible else { return }
        isHarvesterCollectVisible = shouldShow

        if !animated {
            collectContainer.isHidden = !shouldShow
            collectContainer.alpha = shouldShow ? 1 : 0
            collectContainer.setScale(1.0)
            if shouldShow { startCollectPulse() }
            return
        }

        if shouldShow {
            collectContainer.isHidden = false
            collectContainer.alpha = 0
            collectContainer.setScale(0.6)
            collectContainer.run(SKAction.group([SKAction.fadeIn(withDuration: 0.3), SKAction.scale(to: 1.0, duration: 0.4)]))
            startCollectPulse()
        } else {
            collectButton.removeAction(forKey: "collectPulse")
            collectGlow.removeAction(forKey: "collectGlowPulse")
            collectContainer.run(SKAction.sequence([
                SKAction.group([SKAction.fadeOut(withDuration: 0.25), SKAction.scale(to: 0.8, duration: 0.25)]),
                SKAction.run { [weak self] in self?.collectContainer.isHidden = true }
            ]))
        }
    }

    private func startCollectPulse() {
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.04, duration: 0.9),
            SKAction.scale(to: 1.0, duration: 0.9)
        ])
        collectButton.run(SKAction.repeatForever(pulse), withKey: "collectPulse")
        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.8, duration: 1.1),
            SKAction.fadeAlpha(to: 0.35, duration: 1.1)
        ])
        collectGlow.run(SKAction.repeatForever(glowPulse), withKey: "collectGlowPulse")
    }

    private func handleCollectHarvester() {
        guard isHarvesterCollectVisible else { return }
        let amount = EmpireStore.shared.claimHarvesterIncome()
        guard amount > 0 else { refreshHarvesterCollect(animated: true); return }
        AudioManager.shared.playSFX(.buttonTap)
        AudioManager.shared.hapticNotification(.success)
        spawnCrystalBurst(at: collectContainer.position, in: contentLayer)
        spawnFloatingGain(text: "+\(amount) ⬥", at: CGPoint(x: collectContainer.position.x, y: collectContainer.position.y + 26), in: contentLayer)
        refreshCrystalLabel()
        refreshHarvesterCollect(animated: true)
    }

    private func spawnCrystalBurst(at position: CGPoint, in parent: SKNode) {
        let emitter = SKEmitterNode()
        emitter.particleTexture = ProceduralTextures.radialGlow(color: Palette.crystalCyanBright, radius: 10)
        emitter.particlePosition = position
        emitter.particleBirthRate = 500
        emitter.numParticlesToEmit = 26
        emitter.particleLifetime = 0.55
        emitter.particleLifetimeRange = 0.2
        emitter.particleSpeed = 180
        emitter.particleSpeedRange = 90
        emitter.emissionAngle = 0
        emitter.emissionAngleRange = .pi * 2
        emitter.particleAlpha = 1
        emitter.particleAlphaSpeed = -1.8
        emitter.particleScale = 0.5
        emitter.particleScaleRange = 0.3
        emitter.particleScaleSpeed = -0.4
        emitter.particleColorBlendFactor = 1
        emitter.particleColor = Palette.crystalCyan
        emitter.particleBlendMode = .add
        emitter.zPosition = 60
        parent.addChild(emitter)
        emitter.run(SKAction.sequence([SKAction.wait(forDuration: 1.0), SKAction.removeFromParent()]))
    }

    private func spawnFloatingGain(text: String, at position: CGPoint, in parent: SKNode) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 20
        label.fontColor = Palette.crystalCyanBright
        label.position = position
        label.zPosition = 61
        parent.addChild(label)
        let move = SKAction.moveBy(x: 0, y: 46, duration: 0.9)
        move.timingMode = .easeOut
        label.run(SKAction.sequence([
            SKAction.group([move, SKAction.fadeOut(withDuration: 0.9)]),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Primary button (Survival Run)

    private func buildPrimaryButton() {
        let (btn, label) = Self.makeButton(text: "SURVIVAL RUN", width: 250, height: 66,
                                            fill: Palette.engineEmber, stroke: Palette.engineEmberBright,
                                            textColor: SKColor(red: 0.08, green: 0.03, blue: 0.02, alpha: 1),
                                            fontSize: 21, fontName: "AvenirNext-Heavy")
        btn.name = "goSurvival"
        label.name = "goSurvival"
        contentLayer.addChild(btn)
        contentLayer.addChild(label)
        survivalButton = btn
        survivalLabel = label

        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 1.1),
            SKAction.fadeAlpha(to: 0.92, duration: 1.1)
        ])
        btn.run(SKAction.repeatForever(SKAction.sequence([SKAction.wait(forDuration: 0.3), glowPulse])))
    }

    // MARK: - Bottom nav chips (Fleet / Star Map / Alliance / Crystal Shop)

    private func buildNavChips() {
        for (name, title) in Self.navChipOrder {
            let bg = SKShapeNode(rectOf: CGSize(width: Self.chipSize, height: Self.chipSize), cornerRadius: 16)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke
            bg.lineWidth = 1.4
            bg.name = name
            contentLayer.addChild(bg)

            let icon = Self.makeNavIcon(name)
            icon.name = name
            icon.position = CGPoint(x: 0, y: 9)
            icon.zPosition = 1
            bg.addChild(icon)

            let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
            label.text = title
            label.fontSize = 9.5
            label.fontColor = Palette.moonlightDim
            label.position = CGPoint(x: 0, y: -Self.chipSize / 2 + 10)
            label.zPosition = 1
            label.name = name
            bg.addChild(label)

            navChips[name] = NavChip(container: bg, icon: icon, label: label)
        }
    }

    private static func makeNavIcon(_ name: String) -> SKNode {
        let node = SKNode()
        switch name {
        case "goFleet":
            let ship = SKShapeNode(path: Self.miniShipPath(radius: 13), centered: true)
            ship.fillColor = Palette.hullSteel
            ship.strokeColor = Palette.crystalCyan
            ship.lineWidth = 1
            node.addChild(ship)
        case "goStarMap":
            let ring = SKShapeNode(ellipseOf: CGSize(width: 30, height: 14))
            ring.strokeColor = Palette.crystalCyan
            ring.lineWidth = 1.4
            ring.fillColor = .clear
            node.addChild(ring)
            let dot = SKShapeNode(circleOfRadius: 5)
            dot.fillColor = Palette.crystalCyanBright
            dot.strokeColor = .clear
            node.addChild(dot)
            let star = SKShapeNode(path: Self.sparklePath(radius: 5), centered: true)
            star.fillColor = Palette.starWhite
            star.strokeColor = .clear
            star.position = CGPoint(x: 11, y: 8)
            node.addChild(star)
        case "goAlliance":
            let left = SKShapeNode(circleOfRadius: 9)
            left.strokeColor = Palette.crystalCyan
            left.lineWidth = 1.6
            left.fillColor = .clear
            left.position = CGPoint(x: -6, y: 0)
            node.addChild(left)
            let right = SKShapeNode(circleOfRadius: 9)
            right.strokeColor = Palette.engineEmberBright
            right.lineWidth = 1.6
            right.fillColor = .clear
            right.position = CGPoint(x: 6, y: 0)
            node.addChild(right)
        case "goCoinShop":
            let gem = SKShapeNode(path: Self.gemPath(radius: 12), centered: true)
            gem.fillColor = Palette.crystalCyan
            gem.strokeColor = Palette.crystalCyanBright
            gem.lineWidth = 1.2
            node.addChild(gem)
        case "goMarketplace":
            // Two gems trading hands — distinct from the single-gem Shop icon above.
            let gemA = SKShapeNode(path: Self.gemPath(radius: 8), centered: true)
            gemA.fillColor = Palette.crystalCyan
            gemA.strokeColor = Palette.crystalCyanBright
            gemA.lineWidth = 1
            gemA.position = CGPoint(x: -7, y: 3)
            node.addChild(gemA)
            let gemB = SKShapeNode(path: Self.gemPath(radius: 8), centered: true)
            gemB.fillColor = Palette.engineEmberBright
            gemB.strokeColor = Palette.engineEmber
            gemB.lineWidth = 1
            gemB.position = CGPoint(x: 7, y: -3)
            node.addChild(gemB)
        default:
            break
        }
        return node
    }

    // MARK: - Toast ("coming soon" for Alliance)

    private func buildToast() {
        let container = SKNode()
        container.isHidden = true
        container.zPosition = 2
        toastLayer.addChild(container)
        toastContainer = container

        let bg = SKShapeNode(rectOf: CGSize(width: 300, height: 54), cornerRadius: 14)
        bg.fillColor = Palette.panelFill
        bg.strokeColor = Palette.alertAmber
        bg.lineWidth = 1.4
        container.addChild(bg)

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.fontSize = 13
        label.fontColor = Palette.alertAmber
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.numberOfLines = 2
        label.preferredMaxLayoutWidth = 270
        container.addChild(label)
        toastLabel = label
    }

    private func showComingSoonToast() {
        toastLabel.text = "ALLIANCE COMMAND — COMING SOON"
        toastContainer.removeAllActions()
        toastContainer.isHidden = false
        toastContainer.alpha = 0
        toastContainer.setScale(0.9)
        toastContainer.run(SKAction.sequence([
            SKAction.group([SKAction.fadeIn(withDuration: 0.25), SKAction.scale(to: 1.0, duration: 0.25)]),
            SKAction.wait(forDuration: 1.4),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.run { [weak self] in self?.toastContainer.isHidden = true }
        ]))
    }

    // MARK: - Layout (called on didMove and every didChangeSize — resizeFill re-sizes the scene)

    private func layout(size: CGSize) {
        let w = size.width, h = size.height

        if let bg = backgroundLayer.childNode(withName: "bgGradient") as? SKSpriteNode {
            bg.size = CGSize(width: w, height: h)
            bg.position = CGPoint(x: w / 2, y: h / 2)
        }
        nebulaGlowA.position = CGPoint(x: w * 0.20, y: h * 0.82)
        nebulaGlowB.position = CGPoint(x: w * 0.86, y: h * 0.34)
        dustEmitter.particlePosition = CGPoint(x: w / 2, y: -10)
        dustEmitter.particlePositionRange = CGVector(dx: w * 1.1, dy: 0)

        for (i, node) in starNodesFar.enumerated() {
            let (fraction, _) = starFractionsFar[i]
            node.position = CGPoint(x: fraction.x * w, y: fraction.y * h)
        }
        for (i, node) in starNodesNear.enumerated() {
            let (fraction, _) = starFractionsNear[i]
            node.position = CGPoint(x: fraction.x * w, y: fraction.y * h)
        }

        titleShadow.position = CGPoint(x: w / 2 + 1.5, y: h * 0.95 - 2)
        titleLabel.position = CGPoint(x: w / 2, y: h * 0.95)
        subtitleLabel.position = CGPoint(x: w / 2, y: h * 0.95 - 24)

        layoutPlanetReadout(centerY: h * 0.95 - 46, width: w)
        layoutCrystalChip(w: w, h: h)

        shipOuter.position = CGPoint(x: w / 2, y: h * 0.58)

        collectContainer.position = CGPoint(x: w / 2, y: h * 0.335)

        survivalButton.position = CGPoint(x: w / 2, y: max(150, h * 0.205))
        survivalLabel.position = survivalButton.position

        layoutNavChips(width: w, y: max(64, h * 0.085))

        toastContainer.position = CGPoint(x: w / 2, y: h * 0.82)
    }

    private func layoutPlanetReadout(centerY: CGFloat, width w: CGFloat) {
        let text = selectedPlanetLabel.text ?? ""
        let textWidth = Self.measureWidth(text, fontName: "AvenirNext-DemiBold", fontSize: 12)
        let totalWidth = textWidth + 18
        let startX = w / 2 - totalWidth / 2
        let dotX = startX + 6
        selectedPlanetDot.position = CGPoint(x: dotX, y: centerY)
        selectedPlanetLabel.horizontalAlignmentMode = .left
        selectedPlanetLabel.position = CGPoint(x: dotX + 10, y: centerY)
    }

    private func layoutCrystalChip(w: CGFloat, h: CGFloat) {
        let text = crystalLabel.text ?? "0"
        let textWidth = Self.measureWidth(text, fontName: "AvenirNext-Heavy", fontSize: 18)
        let chipWidth = textWidth + 52
        let chipHeight: CGFloat = 40
        let chipX = w - chipWidth / 2 - 16
        let chipY = h * 0.955

        crystalChipBG.position = CGPoint(x: chipX, y: chipY)
        crystalChipBG.path = CGPath(roundedRect: CGRect(x: -chipWidth / 2, y: -chipHeight / 2, width: chipWidth, height: chipHeight),
                                     cornerWidth: chipHeight / 2, cornerHeight: chipHeight / 2, transform: nil)
        crystalGlow.position = crystalChipBG.position
        crystalIcon.position = CGPoint(x: chipX - chipWidth / 2 + 22, y: chipY)
        crystalLabel.horizontalAlignmentMode = .left
        crystalLabel.position = CGPoint(x: chipX - chipWidth / 2 + 38, y: chipY)
    }

    private func layoutNavChips(width w: CGFloat, y: CGFloat) {
        let count = CGFloat(Self.navChipOrder.count)
        let totalWidth = count * Self.chipSize + (count - 1) * Self.chipGap
        var x = w / 2 - totalWidth / 2 + Self.chipSize / 2
        for (name, _) in Self.navChipOrder {
            navChips[name]?.container.position = CGPoint(x: x, y: y)
            x += Self.chipSize + Self.chipGap
        }
    }

    // MARK: - Entrance animations

    private func playEntranceAnimations() {
        entrance(titleShadow, delay: 0.0, dy: 14)
        entrance(titleLabel, delay: 0.0, dy: 14)
        entrance(subtitleLabel, delay: 0.08, dy: 10)
        entrance(selectedPlanetDot, delay: 0.14, dy: 8)
        entrance(selectedPlanetLabel, delay: 0.14, dy: 8)
        entrance(crystalChipBG, delay: 0.1, dy: -10, scaleFrom: 0.7)
        entrance(crystalIcon, delay: 0.1, dy: -10, scaleFrom: 0.7)
        entrance(crystalLabel, delay: 0.1, dy: -10, scaleFrom: 0.7)
        crystalGlow.alpha = 0
        crystalGlow.run(SKAction.sequence([SKAction.wait(forDuration: 0.1), SKAction.fadeAlpha(to: 0.5, duration: 0.4)]))

        shipOuter.alpha = 0
        shipOuter.setScale(0.72)
        shipOuter.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.25),
            SKAction.group([SKAction.fadeIn(withDuration: 0.55), SKAction.scale(to: 1.0, duration: 0.65)])
        ]))

        for (i, badge) in droneBadgeNodes.enumerated() {
            badge.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.75 + Double(i) * 0.12),
                SKAction.group([SKAction.fadeIn(withDuration: 0.35), SKAction.scale(to: 1.0, duration: 0.4)])
            ]))
        }

        if isHarvesterCollectVisible {
            collectContainer.alpha = 0
            collectContainer.setScale(0.6)
            collectContainer.run(SKAction.sequence([
                SKAction.wait(forDuration: 0.9),
                SKAction.group([SKAction.fadeIn(withDuration: 0.35), SKAction.scale(to: 1.0, duration: 0.45)])
            ]))
            startCollectPulse()
        }

        entrance(survivalButton, delay: 0.55, dy: 22)
        entrance(survivalLabel, delay: 0.55, dy: 22)

        for (i, entry) in Self.navChipOrder.enumerated() {
            if let chip = navChips[entry.name] {
                entrance(chip.container, delay: 0.65 + Double(i) * 0.08, dy: 22)
            }
        }

        // Continuous ambient loops start once the ship's one-shot entrance pop has finished, so they
        // never compete with it for the same node/property in the same time window.
        run(SKAction.sequence([
            SKAction.wait(forDuration: 0.95),
            SKAction.run { [weak self] in self?.startShipAmbientMotion() }
        ]))
    }

    /// Generic staggered fade+slide (and optional scale-pop) entrance for a node already positioned
    /// by layout() — captures `node.position` as the animation target, then animates in from an offset.
    private func entrance(_ node: SKNode, delay: TimeInterval, dy: CGFloat = 16, scaleFrom: CGFloat? = nil, duration: TimeInterval = 0.45) {
        let target = node.position
        node.alpha = 0
        node.position = CGPoint(x: target.x, y: target.y - dy)
        if let s = scaleFrom { node.setScale(s) }

        let fade = SKAction.fadeIn(withDuration: duration)
        let move = SKAction.move(to: target, duration: duration)
        move.timingMode = .easeOut
        var group: [SKAction] = [fade, move]
        if scaleFrom != nil {
            let scaleAction = SKAction.scale(to: 1.0, duration: duration)
            scaleAction.timingMode = .easeOut
            group.append(scaleAction)
        }
        node.run(SKAction.sequence([SKAction.wait(forDuration: delay), SKAction.group(group)]))
    }

    // MARK: - Touch handling (manual name-based routing — no UIKit gestures, no physics)

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        if let name = topInteractiveName(at: location) {
            pressedNodeName = name
            setPressed(name: name, pressed: true)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let pressed = pressedNodeName else { return }
        let location = touch.location(in: self)
        let stillOver = topInteractiveName(at: location) == pressed
        setPressed(name: pressed, pressed: stillOver)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)
        guard let pressed = pressedNodeName else { return }
        setPressed(name: pressed, pressed: false)
        pressedNodeName = nil
        guard topInteractiveName(at: location) == pressed else { return }
        handleTap(name: pressed)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let pressed = pressedNodeName { setPressed(name: pressed, pressed: false) }
        pressedNodeName = nil
    }

    /// SpriteKit's `nodes(at:)` is a purely geometric query — it does NOT respect `isHidden`, so the
    /// collect button must be gated explicitly by `isHarvesterCollectVisible` rather than trusting
    /// node visibility (same reasoning as MenuScene's shop-row gating).
    private func topInteractiveName(at location: CGPoint) -> String? {
        let hit = nodes(at: location)
        let matched = hit.filter { node in
            guard let name = node.name else { return false }
            if name == "collectHarvester" { return isHarvesterCollectVisible }
            return Self.interactiveNames.contains(name)
        }
        return matched.max(by: { $0.zPosition < $1.zPosition })?.name
    }

    private func setPressed(name: String, pressed: Bool) {
        let scale: CGFloat = pressed ? 0.94 : 1.0
        switch name {
        case "goSurvival":
            survivalButton.run(SKAction.scale(to: scale, duration: 0.08))
        case "collectHarvester":
            collectButton.run(SKAction.scale(to: scale, duration: 0.08))
        default:
            if let chip = navChips[name] {
                chip.container.run(SKAction.scale(to: scale, duration: 0.08))
            }
        }
    }

    private func handleTap(name: String) {
        switch name {
        case "goSurvival":
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.medium)
            view?.presentScene(MenuScene.newScene(), transition: .crossFade(withDuration: 0.5))
        case "goFleet":
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.light)
            view?.presentScene(StarshipHangarScene.newScene(), transition: .crossFade(withDuration: 0.5))
        case "goStarMap":
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.light)
            // Star map lives inside the same hangar/command hub screen for this pass.
            view?.presentScene(StarshipHangarScene.newScene(), transition: .crossFade(withDuration: 0.5))
        case "goAlliance":
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.soft)
            showComingSoonToast()
        case "goCoinShop":
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.light)
            view?.presentScene(CoinShopScene.newScene(), transition: .crossFade(withDuration: 0.4))
        case "goMarketplace":
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.light)
            view?.presentScene(MarketplaceScene.newScene(), transition: .crossFade(withDuration: 0.4))
        case "collectHarvester":
            handleCollectHarvester()
        default:
            break
        }
    }

    // MARK: - Procedural textures & shared vector paths

    /// UIGraphicsImageRenderer's CGContext has its origin at the top-left with y increasing
    /// downward; the resulting SKTexture displays the image the same way it looks as a UIImage,
    /// so y=0 here is the visual TOP of the sprite (same convention as MenuScene's helpers).
    private static func gradientTexture(top: SKColor, bottom: SKColor, size: CGSize) -> SKTexture {
        ProceduralTextures.render(size: size, opaque: true) { ctx, size in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    /// Faceted gem icon for the Crystal currency readout — gradient fill, glow-ready edge stroke,
    /// plus a couple of specular facet lines. This is the "glowing crystal icon" the header displays;
    /// the actual glow comes from the separate additive-blend radialGlow sprite placed behind it.
    private static func crystalIconTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.03))
            path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.38))
            path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.97))
            path.addLine(to: CGPoint(x: w * 0.32, y: h * 0.97))
            path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.38))
            path.closeSubpath()

            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            let colors = [Palette.crystalCyanBright.cgColor, Palette.crystalCyan.cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.drawLinearGradient(gradient, start: CGPoint(x: w * 0.5, y: 0), end: CGPoint(x: w * 0.5, y: h), options: [])
            }
            ctx.restoreGState()

            ctx.addPath(path)
            ctx.setStrokeColor(Palette.crystalCyanBright.cgColor)
            ctx.setLineWidth(1.4)
            ctx.strokePath()

            ctx.setStrokeColor(SKColor.white.withAlphaComponent(0.55).cgColor)
            ctx.setLineWidth(1.0)
            ctx.move(to: CGPoint(x: w * 0.5, y: h * 0.03)); ctx.addLine(to: CGPoint(x: w * 0.5, y: h * 0.97)); ctx.strokePath()
            ctx.move(to: CGPoint(x: w * 0.08, y: h * 0.38)); ctx.addLine(to: CGPoint(x: w * 0.92, y: h * 0.38)); ctx.strokePath()
        }
    }

    /// Vector diamond silhouette (SpriteKit's y-up local space) — used for the small Crystal Shop
    /// nav-chip icon, distinct from the CoreGraphics-rendered header crystalIconTexture above.
    private static func gemPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: radius))
        path.addLine(to: CGPoint(x: radius * 0.62, y: radius * 0.15))
        path.addLine(to: CGPoint(x: radius * 0.36, y: -radius))
        path.addLine(to: CGPoint(x: -radius * 0.36, y: -radius))
        path.addLine(to: CGPoint(x: -radius * 0.62, y: radius * 0.15))
        path.closeSubpath()
        return path
    }

    private static func sparklePath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: radius))
        path.addLine(to: CGPoint(x: radius * 0.25, y: radius * 0.25))
        path.addLine(to: CGPoint(x: radius, y: 0))
        path.addLine(to: CGPoint(x: radius * 0.25, y: -radius * 0.25))
        path.addLine(to: CGPoint(x: 0, y: -radius))
        path.addLine(to: CGPoint(x: -radius * 0.25, y: -radius * 0.25))
        path.addLine(to: CGPoint(x: -radius, y: 0))
        path.addLine(to: CGPoint(x: -radius * 0.25, y: radius * 0.25))
        path.closeSubpath()
        return path
    }

    private static func miniShipPath(radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: radius))
        path.addLine(to: CGPoint(x: radius * 0.8, y: -radius * 0.5))
        path.addLine(to: CGPoint(x: 0, y: -radius * 0.15))
        path.addLine(to: CGPoint(x: -radius * 0.8, y: -radius * 0.5))
        path.closeSubpath()
        return path
    }

    private static func makeButton(text: String, width: CGFloat, height: CGFloat,
                                    fill: SKColor, stroke: SKColor, textColor: SKColor,
                                    fontSize: CGFloat, fontName: String) -> (SKShapeNode, SKLabelNode) {
        let shape = SKShapeNode(rectOf: CGSize(width: width, height: height), cornerRadius: height / 2.6)
        shape.fillColor = fill
        shape.strokeColor = stroke
        shape.lineWidth = 1.6
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        label.fontColor = textColor
        label.horizontalAlignmentMode = .center
        label.verticalAlignmentMode = .center
        label.zPosition = 1
        // Intentionally NOT parented under `shape` — callers keep label.position in sync with the
        // shape (see layout()), same convention as MenuScene.makeButton.
        return (shape, label)
    }

    private static func letterSpaced(_ text: String) -> String {
        text.map(String.init).joined(separator: "\u{200A}")
    }

    private static func measureWidth(_ text: String, fontName: String, fontSize: CGFloat) -> CGFloat {
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        return label.frame.width
    }
}
