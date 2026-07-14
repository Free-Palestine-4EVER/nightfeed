import SpriteKit

/// Death screen — a dramatic "YOU DIED" moment, the run's stats, a rewarded Double-Gold hook and
/// the way back to the menu. Pure SpriteKit UI: every visual is code-drawn (SKShapeNode/SKLabelNode/
/// SKEmitterNode with ProceduralTextures-rendered textures), no image assets. Manual name-based
/// touch handling — this scene has no physics world and no need for one.
final class GameOverScene: SKScene {

    // MARK: - Palette (deep violet-black nights, blood-red death accent, ember-orange gold, moonlight-white)

    private enum Palette {
        static let bgTop = SKColor(red: 0.06, green: 0.02, blue: 0.04, alpha: 1)
        static let bgBottom = SKColor(red: 0.015, green: 0.008, blue: 0.02, alpha: 1)
        static let blood = SKColor(red: 0.80, green: 0.10, blue: 0.18, alpha: 1)
        static let bloodDeep = SKColor(red: 0.42, green: 0.03, blue: 0.08, alpha: 1)
        static let bloodDim = SKColor(red: 0.30, green: 0.05, blue: 0.10, alpha: 1)
        static let ember = SKColor(red: 1.0, green: 0.45, blue: 0.16, alpha: 1)
        static let emberBright = SKColor(red: 1.0, green: 0.66, blue: 0.28, alpha: 1)
        static let moonlight = SKColor(red: 0.93, green: 0.91, blue: 1.0, alpha: 1)
        static let moonlightDim = SKColor(red: 0.93, green: 0.91, blue: 1.0, alpha: 0.55)
        static let panelFill = SKColor(red: 0.09, green: 0.035, blue: 0.05, alpha: 0.92)
        static let panelStroke = SKColor(red: 0.55, green: 0.14, blue: 0.20, alpha: 0.55)
        static let rowFill = SKColor(red: 0.14, green: 0.05, blue: 0.07, alpha: 0.85)
        static let ash = SKColor(red: 0.55, green: 0.45, blue: 0.45, alpha: 1)
    }

    static func newScene(survivalTime: TimeInterval, kills: Int, miniBossKills: Int, goldEarned: Int) -> GameOverScene {
        let scene = GameOverScene(size: CGSize(width: 393, height: 852), survivalTime: survivalTime,
                                   kills: kills, miniBossKills: miniBossKills, goldEarned: goldEarned)
        scene.scaleMode = .resizeFill
        return scene
    }

    // MARK: - Run data

    private let survivalTime: TimeInterval
    private let kills: Int
    private let miniBossKills: Int
    private let baseGoldEarned: Int
    private var displayedGoldEarned: Int
    private var doubleGoldClaimed = false
    private var doubleGoldPending = false

    private init(size: CGSize, survivalTime: TimeInterval, kills: Int, miniBossKills: Int, goldEarned: Int) {
        self.survivalTime = survivalTime
        self.kills = kills
        self.miniBossKills = miniBossKills
        self.baseGoldEarned = goldEarned
        self.displayedGoldEarned = goldEarned
        super.init(size: size)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("GameOverScene does not support NSCoding")
    }

    // MARK: - Layers

    private let backgroundLayer = SKNode()
    private let ashLayer = SKNode()
    private let contentLayer = SKNode()

    // MARK: - Content refs

    private var vignette: SKSpriteNode!
    private var ashEmitter: SKEmitterNode!
    private var titleLabel: SKLabelNode!
    private var titleShadow: SKLabelNode!
    private var subtitleLabel: SKLabelNode!

    private var statsPanel: SKShapeNode!
    private var survivalValueLabel: SKLabelNode!
    private var killsValueLabel: SKLabelNode!
    private var miniBossValueLabel: SKLabelNode!
    private var goldValueLabel: SKLabelNode!
    private var goldDoubledTag: SKLabelNode!

    private var doubleGoldButton: SKShapeNode!
    private var doubleGoldTextLabel: SKLabelNode!
    private var menuButton: SKShapeNode!
    private var menuLabel: SKLabelNode!

    private var pressedNodeName: String?
    private var hasBuiltOnce = false

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.bgBottom

        let isFirstPresentation = !hasBuiltOnce
        if !hasBuiltOnce {
            addChild(backgroundLayer)
            addChild(ashLayer)
            addChild(contentLayer)
            backgroundLayer.zPosition = ZPosition.menuUI - 5
            ashLayer.zPosition = ZPosition.menuUI - 3
            contentLayer.zPosition = ZPosition.menuUI

            buildBackground()
            buildTitle()
            buildStatsPanel()
            buildButtons()
            hasBuiltOnce = true
        }

        layout(size: size)
        AudioManager.shared.hapticNotification(.error)

        // A fresh GameOverScene instance is created every death (see GameOverScene.newScene()), so
        // this always plays exactly once for the moment the death screen actually appears.
        if isFirstPresentation {
            playEntranceAnimation()
        }
    }

    /// Staggers the "YOU DIED" moment's weight in on purpose: title/subtitle first, then the stats
    /// panel settling in, then its four rows cascading below it, then the two action buttons —
    /// instead of the whole screen just materializing at once. Channels a node's own continuous
    /// ambient action already drives (title's alpha-breathe, DOUBLE GOLD's alpha glow-pulse) are
    /// skipped here so the two never fight over the same property — see JuiceEffects.popIn.
    private func playEntranceAnimation() {
        JuiceEffects.popIn(titleShadow, delay: 0.0, distance: 14)
        JuiceEffects.popIn(titleLabel, delay: 0.0, distance: 14, fade: false)
        JuiceEffects.popIn(subtitleLabel, delay: 0.1, distance: 10)

        JuiceEffects.popIn(statsPanel, delay: 0.18, distance: 16)
        let rowNames = ["row_survival", "row_kills", "row_boss", "row_gold"]
        for (index, name) in rowNames.enumerated() {
            JuiceEffects.popIn(contentLayer.childNode(withName: name), delay: 0.26 + Double(index) * 0.06, distance: 10)
        }

        JuiceEffects.popIn(doubleGoldButton, delay: 0.52, fade: false)
        JuiceEffects.popIn(doubleGoldTextLabel, delay: 0.52, fade: false)
        JuiceEffects.popIn(menuButton, delay: 0.58)
        JuiceEffects.popIn(menuLabel, delay: 0.58)
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

        let glow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.bloodDeep, radius: 320))
        glow.name = "bloodGlow"
        glow.alpha = 0.55
        glow.zPosition = 1
        glow.blendMode = .add
        backgroundLayer.addChild(glow)

        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.75, duration: 1.8),
            SKAction.fadeAlpha(to: 0.4, duration: 1.8)
        ])
        glow.run(SKAction.repeatForever(pulse))

        let vig = SKSpriteNode(texture: Self.vignetteTexture(size: CGSize(width: 256, height: 256), color: Palette.blood))
        vig.name = "vignette"
        vig.zPosition = 2
        vig.alpha = 0.5
        vig.blendMode = .alpha
        backgroundLayer.addChild(vig)
        vignette = vig

        // Falling ash/embers — the dying light of the fight, drifting down.
        let emitter = SKEmitterNode()
        emitter.particleTexture = ProceduralTextures.radialGlow(color: Palette.ash, radius: 6)
        emitter.particleBirthRate = 8
        emitter.particleLifetime = 6.5
        emitter.particleLifetimeRange = 2.5
        emitter.particleSpeed = 26
        emitter.particleSpeedRange = 14
        emitter.emissionAngle = -.pi / 2
        emitter.emissionAngleRange = .pi / 8
        emitter.yAcceleration = -4
        emitter.particleAlpha = 0.0
        emitter.particleAlphaSequence = Self.ashAlphaSequence
        emitter.particleScale = 0.3
        emitter.particleScaleRange = 0.2
        emitter.particleColorBlendFactor = 1
        emitter.particleColor = Palette.ash
        emitter.particleColorSequence = Self.ashColorSequence
        emitter.particleBlendMode = .add
        ashLayer.addChild(emitter)
        ashEmitter = emitter
    }

    private static let ashAlphaSequence: SKKeyframeSequence = {
        SKKeyframeSequence(keyframeValues: [0.0, 0.55, 0.35, 0.0], times: [0.0, 0.2, 0.7, 1.0])
    }()

    private static let ashColorSequence: SKKeyframeSequence = {
        SKKeyframeSequence(keyframeValues: [Palette.ember, Palette.ash, Palette.ash], times: [0.0, 0.5, 1.0])
    }()

    // MARK: - Title

    private func buildTitle() {
        let shadow = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        shadow.text = "YOU DIED"
        shadow.fontSize = 54
        shadow.fontColor = Palette.bloodDeep
        shadow.horizontalAlignmentMode = .center
        shadow.verticalAlignmentMode = .center
        shadow.zPosition = 0
        contentLayer.addChild(shadow)
        titleShadow = shadow

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "YOU DIED"
        title.fontSize = 54
        title.fontColor = Palette.blood
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.zPosition = 1
        contentLayer.addChild(title)
        titleLabel = title

        let breathe = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.78, duration: 1.4),
            SKAction.fadeAlpha(to: 1.0, duration: 1.4)
        ])
        title.run(SKAction.repeatForever(breathe))

        let sub = SKLabelNode(fontNamed: "AvenirNext-Medium")
        sub.text = Self.letterSpaced("THE NIGHT CLAIMS ANOTHER")
        sub.fontSize = 13
        sub.fontColor = Palette.moonlightDim
        sub.horizontalAlignmentMode = .center
        sub.verticalAlignmentMode = .center
        sub.zPosition = 1
        contentLayer.addChild(sub)
        subtitleLabel = sub
    }

    // MARK: - Stats panel

    private func buildStatsPanel() {
        let panel = SKShapeNode()
        panel.fillColor = Palette.panelFill
        panel.strokeColor = Palette.panelStroke
        panel.lineWidth = 1.5
        panel.zPosition = 0
        contentLayer.addChild(panel)
        statsPanel = panel

        let (survivalRow, survivalValue) = buildStatRow(label: "SURVIVED", icon: .clock)
        let (killsRow, killsValue) = buildStatRow(label: "KILLS", icon: .fang)
        let (bossRow, bossValue) = buildStatRow(label: "MINI-BOSSES", icon: .skull)
        let (goldRow, goldValue) = buildStatRow(label: "GOLD EARNED", icon: .coin)

        survivalRow.name = "row_survival"
        killsRow.name = "row_kills"
        bossRow.name = "row_boss"
        goldRow.name = "row_gold"
        contentLayer.addChild(survivalRow)
        contentLayer.addChild(killsRow)
        contentLayer.addChild(bossRow)
        contentLayer.addChild(goldRow)

        survivalValueLabel = survivalValue
        killsValueLabel = killsValue
        miniBossValueLabel = bossValue
        goldValueLabel = goldValue

        survivalValueLabel.text = Self.formatTime(survivalTime)
        killsValueLabel.text = "\(kills)"
        miniBossValueLabel.text = "\(miniBossKills)"
        goldValueLabel.text = "\(displayedGoldEarned)"
        goldValueLabel.fontColor = Palette.emberBright

        let tag = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        tag.text = "×2"
        tag.fontSize = 13
        tag.fontColor = Palette.emberBright
        tag.horizontalAlignmentMode = .left
        tag.verticalAlignmentMode = .center
        tag.isHidden = true
        tag.zPosition = 1
        goldRow.addChild(tag)
        goldDoubledTag = tag
    }

    private enum StatIcon { case clock, fang, skull, coin }

    private func buildStatRow(label text: String, icon: StatIcon) -> (SKNode, SKLabelNode) {
        let row = SKNode()

        let iconSprite = SKSpriteNode(texture: Self.iconTexture(for: icon))
        iconSprite.position = CGPoint(x: -Self.statRowWidth / 2 + 16, y: 0)
        row.addChild(iconSprite)

        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = text
        label.fontSize = 14
        label.fontColor = Palette.moonlightDim
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: -Self.statRowWidth / 2 + 38, y: 0)
        row.addChild(label)

        let value = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        value.fontSize = 18
        value.fontColor = Palette.moonlight
        value.horizontalAlignmentMode = .right
        value.verticalAlignmentMode = .center
        value.position = CGPoint(x: Self.statRowWidth / 2 - 16, y: 0)
        row.addChild(value)

        return (row, value)
    }

    private static let statRowWidth: CGFloat = 300
    private static let statRowHeight: CGFloat = 40

    // MARK: - Buttons

    private func buildButtons() {
        let (gold, goldText) = Self.makeButton(text: "DOUBLE GOLD", width: 260, height: 60,
                                                fill: Palette.ember, stroke: Palette.emberBright,
                                                textColor: SKColor(red: 0.12, green: 0.03, blue: 0.02, alpha: 1),
                                                fontSize: 20, fontName: "AvenirNext-Heavy")
        gold.name = "doubleGold"
        goldText.name = "doubleGold"
        contentLayer.addChild(gold)
        contentLayer.addChild(goldText)
        doubleGoldButton = gold
        doubleGoldTextLabel = goldText

        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.6, duration: 1.0),
            SKAction.fadeAlpha(to: 0.95, duration: 1.0)
        ])
        gold.run(SKAction.repeatForever(glowPulse))

        let (menu, menuText) = Self.makeButton(text: "MENU", width: 260, height: 52,
                                                fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                textColor: Palette.moonlight,
                                                fontSize: 19, fontName: "AvenirNext-DemiBold")
        menu.name = "menu"
        menuText.name = "menu"
        contentLayer.addChild(menu)
        contentLayer.addChild(menuText)
        menuButton = menu
        menuLabel = menuText
    }

    // MARK: - Layout

    private func layout(size: CGSize) {
        let w = size.width, h = size.height

        if let bg = backgroundLayer.childNode(withName: "bgGradient") as? SKSpriteNode {
            bg.size = CGSize(width: w, height: h)
            bg.position = CGPoint(x: w / 2, y: h / 2)
        }
        (backgroundLayer.childNode(withName: "bloodGlow") as? SKSpriteNode)?.position = CGPoint(x: w / 2, y: h * 0.62)
        vignette.size = CGSize(width: w, height: h)
        vignette.position = CGPoint(x: w / 2, y: h / 2)

        ashEmitter.particlePosition = CGPoint(x: w / 2, y: h + 10)
        ashEmitter.particlePositionRange = CGVector(dx: w * 1.1, dy: 0)

        titleShadow.position = CGPoint(x: w / 2 + 2, y: h * 0.74 - 3)
        titleLabel.position = CGPoint(x: w / 2, y: h * 0.74)
        subtitleLabel.position = CGPoint(x: w / 2, y: h * 0.74 - 36)

        let panelCenter = CGPoint(x: w / 2, y: h * 0.47)
        let panelWidth = min(w - 40, Self.statRowWidth + 40)
        let rowCount: CGFloat = 4
        let panelHeight = rowCount * Self.statRowHeight + 40
        let panelRect = CGRect(x: -panelWidth / 2, y: -panelHeight / 2, width: panelWidth, height: panelHeight)
        statsPanel.path = CGPath(roundedRect: panelRect, cornerWidth: 18, cornerHeight: 18, transform: nil)
        statsPanel.position = panelCenter

        let rowNames = ["row_survival", "row_kills", "row_boss", "row_gold"]
        let top = panelCenter.y + panelHeight / 2 - 30
        for (i, name) in rowNames.enumerated() {
            guard let row = contentLayer.childNode(withName: name) else { continue }
            row.position = CGPoint(x: panelCenter.x, y: top - CGFloat(i) * Self.statRowHeight)
        }
        goldDoubledTag.position = CGPoint(x: Self.statRowWidth / 2 - 16 - (goldValueLabel.frame.width) - 8, y: 0)

        doubleGoldButton.position = CGPoint(x: w / 2, y: h * 0.17)
        doubleGoldTextLabel.position = doubleGoldButton.position
        menuButton.position = CGPoint(x: w / 2, y: h * 0.17 - 68)
        menuLabel.position = menuButton.position
    }

    // MARK: - Touch handling

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

    private func topInteractiveName(at location: CGPoint) -> String? {
        let hit = nodes(at: location)
        let matched = hit.filter { node in
            guard let name = node.name else { return false }
            return name == "doubleGold" || name == "menu"
        }
        return matched.max(by: { $0.zPosition < $1.zPosition })?.name
    }

    private func setPressed(name: String, pressed: Bool) {
        func apply(_ node: SKNode) {
            if pressed { JuiceEffects.pressDown(node) } else { JuiceEffects.releaseBounce(node) }
        }
        switch name {
        case "doubleGold":
            guard !doubleGoldClaimed, !doubleGoldPending else { return }
            apply(doubleGoldButton)
        case "menu":
            apply(menuButton)
        default:
            break
        }
    }

    private func handleTap(name: String) {
        switch name {
        case "doubleGold":
            handleDoubleGold()
        case "menu":
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.light)
            AdsManager.shared.showInterstitialIfDue()
            // Menu rises back in over the death screen like moonlight returning, rather than a flat
            // cross-dissolve — distinct from GameScene's own fade-to-black transitions.
            view?.presentScene(MenuScene.newScene(), transition: .reveal(with: .down, duration: 0.5))
        default:
            break
        }
    }

    private func handleDoubleGold() {
        guard !doubleGoldClaimed, !doubleGoldPending else { return }
        AudioManager.shared.playSFX(.buttonTap)
        doubleGoldPending = true
        setDoubleGoldVisual(pending: true)
        AdsManager.shared.showRewarded { [weak self] earned in
            guard let self else { return }
            DispatchQueue.main.async {
                self.doubleGoldPending = false
                if earned {
                    self.doubleGoldClaimed = true
                    MetaProgressionStore.shared.addGold(self.baseGoldEarned)
                    self.displayedGoldEarned = self.baseGoldEarned * 2
                    self.goldValueLabel.text = "\(self.displayedGoldEarned)"
                    self.goldDoubledTag.isHidden = false
                    self.goldDoubledTag.position = CGPoint(
                        x: Self.statRowWidth / 2 - 16 - self.goldValueLabel.frame.width - 8, y: 0)
                    AudioManager.shared.hapticNotification(.success)
                    self.setDoubleGoldVisual(pending: false, claimed: true)
                    let pop = SKAction.sequence([SKAction.scale(to: 1.06, duration: 0.1), SKAction.scale(to: 1.0, duration: 0.12)])
                    self.goldValueLabel.parent?.run(pop)
                } else {
                    AudioManager.shared.hapticImpact(.soft)
                    self.setDoubleGoldVisual(pending: false, claimed: false)
                }
            }
        }
    }

    private func setDoubleGoldVisual(pending: Bool, claimed: Bool = false) {
        if claimed {
            doubleGoldButton.removeAllActions()
            doubleGoldButton.alpha = 0.35
            doubleGoldButton.setScale(1.0)
            doubleGoldTextLabel.text = "GOLD DOUBLED"
            doubleGoldTextLabel.fontSize = 16
        } else if pending {
            doubleGoldButton.alpha = 0.6
            doubleGoldTextLabel.text = "..."
        } else {
            doubleGoldButton.alpha = 1.0
            doubleGoldTextLabel.text = "DOUBLE GOLD"
            doubleGoldTextLabel.fontSize = 20
        }
    }

    // MARK: - Procedural textures & helpers

    private static func gradientTexture(top: SKColor, bottom: SKColor, size: CGSize) -> SKTexture {
        ProceduralTextures.render(size: size, opaque: true) { ctx, size in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    /// Transparent center, colored edges — a creeping-in vignette of danger for the death screen.
    private static func vignetteTexture(size: CGSize, color: SKColor) -> SKTexture {
        ProceduralTextures.render(size: size) { ctx, size in
            let colors = [color.withAlphaComponent(0.0).cgColor, color.withAlphaComponent(0.85).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width * 0.72
            ctx.drawRadialGradient(gradient, startCenter: center, startRadius: radius * 0.35,
                                    endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
        }
    }

    private static func iconTexture(for icon: StatIcon) -> SKTexture {
        let size = CGSize(width: 20, height: 20)
        return ProceduralTextures.render(size: size) { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let cx = size.width / 2, cy = size.height / 2
            switch icon {
            case .clock:
                ctx.setStrokeColor(Palette.moonlight.cgColor)
                ctx.setLineWidth(1.6)
                ctx.strokeEllipse(in: rect.insetBy(dx: 1.5, dy: 1.5))
                ctx.move(to: CGPoint(x: cx, y: cy))
                ctx.addLine(to: CGPoint(x: cx, y: cy - 6))
                ctx.move(to: CGPoint(x: cx, y: cy))
                ctx.addLine(to: CGPoint(x: cx + 4, y: cy))
                ctx.strokePath()
            case .fang:
                ctx.setFillColor(Palette.moonlight.cgColor)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: cx - 5, y: cy + 7))
                path.addLine(to: CGPoint(x: cx, y: cy - 8))
                path.addLine(to: CGPoint(x: cx + 5, y: cy + 7))
                path.addLine(to: CGPoint(x: cx, y: cy + 3))
                path.closeSubpath()
                ctx.addPath(path)
                ctx.fillPath()
            case .skull:
                ctx.setFillColor(Palette.blood.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - 7, y: cy - 3, width: 14, height: 12))
                ctx.fill(CGRect(x: cx - 5, y: cy - 9, width: 10, height: 7))
                ctx.setFillColor(Palette.bgBottom.cgColor)
                ctx.fillEllipse(in: CGRect(x: cx - 5, y: cy - 1, width: 4, height: 4))
                ctx.fillEllipse(in: CGRect(x: cx + 1, y: cy - 1, width: 4, height: 4))
            case .coin:
                let colors = [Palette.emberBright.cgColor, Palette.ember.cgColor] as CFArray
                guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
                ctx.saveGState()
                let coinRect = rect.insetBy(dx: 1.5, dy: 1.5)
                ctx.addEllipse(in: coinRect)
                ctx.clip()
                ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: cx, y: cy), startRadius: 0,
                                        endCenter: CGPoint(x: cx, y: cy), endRadius: coinRect.width / 2, options: [])
                ctx.restoreGState()
                ctx.setStrokeColor(SKColor(red: 0.55, green: 0.22, blue: 0.06, alpha: 1).cgColor)
                ctx.setLineWidth(1.2)
                ctx.strokeEllipse(in: coinRect)
            }
        }
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
        // Intentionally NOT parented under `shape` — callers add both as siblings to the same
        // parent and keep `label.position == shape.position` in sync (see layout()).
        return (shape, label)
    }

    private static func letterSpaced(_ text: String) -> String {
        text.map(String.init).joined(separator: "\u{200A}")
    }

    private static func formatTime(_ t: TimeInterval) -> String {
        let total = max(0, Int(t.rounded()))
        let m = total / 60
        let s = total % 60
        return String(format: "%02d:%02d", m, s)
    }
}
