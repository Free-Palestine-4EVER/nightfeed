import SpriteKit

/// Starfleet Command upgrade screen — the player's persistent starship (hull/weapon/shield), its
/// drone crew, and the planet star map. Spends Crystals (EmpireStore), the second currency, as
/// opposed to MenuScene's Gold shop. Visual/interaction pattern deliberately mirrors MenuScene's
/// shop panel (Palette family, Self.makeButton, panel/row/tier-dot card styling, manual name-based
/// touch routing) so this reads as "another shop screen" in the same game. Pure SpriteKit UI: every
/// visual is code-drawn (SKShapeNode/SKLabelNode with ProceduralTextures-rendered icon textures), no
/// image assets. No physics world — manual name-based touch handling only, same as MenuScene.
final class StarshipHangarScene: SKScene {

    // MARK: - Palette (same family as MenuScene, + a crystal-cyan accent for this currency)

    private enum Palette {
        static let bgTop = SKColor(red: 0.05, green: 0.04, blue: 0.12, alpha: 1)
        static let bgBottom = SKColor(red: 0.015, green: 0.012, blue: 0.03, alpha: 1)
        static let violet = SKColor(red: 0.55, green: 0.12, blue: 0.66, alpha: 1)
        static let violetDim = SKColor(red: 0.30, green: 0.10, blue: 0.38, alpha: 1)
        static let ember = SKColor(red: 1.0, green: 0.45, blue: 0.16, alpha: 1)
        static let emberBright = SKColor(red: 1.0, green: 0.66, blue: 0.28, alpha: 1)
        static let moonlight = SKColor(red: 0.93, green: 0.91, blue: 1.0, alpha: 1)
        static let moonlightDim = SKColor(red: 0.93, green: 0.91, blue: 1.0, alpha: 0.55)
        static let blood = SKColor(red: 0.80, green: 0.10, blue: 0.18, alpha: 1)
        static let panelFill = SKColor(red: 0.08, green: 0.045, blue: 0.12, alpha: 0.93)
        static let panelStroke = SKColor(red: 0.52, green: 0.24, blue: 0.58, alpha: 0.55)
        static let rowFill = SKColor(red: 0.13, green: 0.08, blue: 0.18, alpha: 0.9)
        static let dim = SKColor(white: 1, alpha: 0.32)
        static let crystal = SKColor(red: 0.38, green: 0.86, blue: 0.95, alpha: 1)
        static let crystalDim = SKColor(red: 0.38, green: 0.86, blue: 0.95, alpha: 0.5)
        static let crystalText = SKColor(red: 0.03, green: 0.09, blue: 0.11, alpha: 1)
    }

    static func newScene() -> StarshipHangarScene {
        let scene = StarshipHangarScene(size: CGSize(width: 393, height: 852))
        scene.scaleMode = .resizeFill
        return scene
    }

    // MARK: - Layers

    private let backgroundLayer = SKNode()
    private let starLayer = SKNode()
    private let panelLayer = SKNode()
    private let shipTabLayer = SKNode()
    private let droneTabLayer = SKNode()
    private let planetTabLayer = SKNode()

    // MARK: - Background refs

    private var nebulaGlow: SKSpriteNode!
    private var crystalDustEmitter: SKEmitterNode!
    private var starFractions: [(CGPoint, CGFloat)] = []
    private var starNodes: [SKShapeNode] = []

    // MARK: - Header refs

    private var panelBG: SKShapeNode!
    private var titleLabel: SKLabelNode!
    private var closeButton: SKShapeNode!
    private var closeLabel: SKLabelNode!
    private var crystalIconNode: SKSpriteNode!
    private var crystalBalanceLabel: SKLabelNode!

    private var tabButtons: [SKShapeNode] = []
    private var tabLabels: [SKLabelNode] = []
    private var selectedTab = 0

    private var pressedNodeName: String?
    private var hasBuiltOnce = false

    // MARK: - Ship rows

    private static let shipStats: [EmpireStore.ShipStat] = [.hull, .weapon, .shield]

    private struct ShipRowNodes {
        let container: SKNode
        let background: SKShapeNode
        let icon: SKSpriteNode
        let nameLabel: SKLabelNode
        let levelLabel: SKLabelNode
        let flavorLabel: SKLabelNode
        let buyButton: SKShapeNode
        let buyLabel: SKLabelNode
        let maxedLabel: SKLabelNode
    }

    private var shipRows: [EmpireStore.ShipStat: ShipRowNodes] = [:]

    // MARK: - Drone rows

    private struct DroneRowNodes {
        let container: SKNode
        let background: SKShapeNode
        let icon: SKSpriteNode
        let nameLabel: SKLabelNode
        let statusLabel: SKLabelNode
        let flavorLabel: SKLabelNode
        let primaryButton: SKShapeNode
        let primaryLabel: SKLabelNode
        let maxedLabel: SKLabelNode
        let equipButton: SKShapeNode
        let equipLabel: SKLabelNode
    }

    private var droneRows: [DroneKind: DroneRowNodes] = [:]

    // MARK: - Planet rows

    private struct PlanetRowNodes {
        let container: SKNode
        let background: SKShapeNode
        let icon: SKSpriteNode
        let lockBadge: SKLabelNode
        let nameLabel: SKLabelNode
        let flavorLabel: SKLabelNode
        let costLabel: SKLabelNode
        let actionButton: SKShapeNode
        let actionLabel: SKLabelNode
    }

    private var planetRows: [PlanetKind: PlanetRowNodes] = [:]

    // MARK: - Row geometry

    private static let rowWidth: CGFloat = 320
    private static let shipRowHeight: CGFloat = 84
    private static let droneRowHeight: CGFloat = 100
    private static let planetRowHeight: CGFloat = 100
    private static let rowSpacing: CGFloat = 8
    private static let headerTotalHeight: CGFloat = 130
    private static let hangarTabTitles = ["SHIP", "DRONES", "STAR MAP"]

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.bgBottom

        if !hasBuiltOnce {
            addChild(backgroundLayer)
            addChild(starLayer)
            addChild(panelLayer)
            panelLayer.addChild(shipTabLayer)
            panelLayer.addChild(droneTabLayer)
            panelLayer.addChild(planetTabLayer)
            backgroundLayer.zPosition = ZPosition.menuUI - 5
            starLayer.zPosition = ZPosition.menuUI - 3
            panelLayer.zPosition = ZPosition.menuUI

            buildBackground()
            buildStars()
            buildPanelBackground()
            buildHeader()
            buildTabs()
            buildShipRows()
            buildDroneRows()
            buildPlanetRows()
            hasBuiltOnce = true
        }

        refreshAll()
        refreshTabVisibility()
        layout(size: size)

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

        let glow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.crystalDim, radius: 240))
        glow.name = "nebulaGlow"
        glow.alpha = 0.4
        glow.zPosition = 1
        glow.blendMode = .add
        backgroundLayer.addChild(glow)
        nebulaGlow = glow

        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 2.8),
            SKAction.fadeAlpha(to: 0.3, duration: 2.8)
        ])
        glow.run(SKAction.repeatForever(glowPulse))

        let emitter = SKEmitterNode()
        emitter.particleTexture = ProceduralTextures.radialGlow(color: Palette.crystal, radius: 6)
        emitter.particleBirthRate = 4
        emitter.particleLifetime = 8
        emitter.particleLifetimeRange = 3
        emitter.particleSpeed = 16
        emitter.particleSpeedRange = 10
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 8
        emitter.yAcceleration = 4
        emitter.particleAlpha = 0.0
        emitter.particleAlphaSequence = Self.dustAlphaSequence
        emitter.particleScale = 0.3
        emitter.particleScaleRange = 0.2
        emitter.particleScaleSpeed = -0.015
        emitter.particleColorBlendFactor = 1
        emitter.particleColor = Palette.crystal
        emitter.particleBlendMode = .add
        emitter.zPosition = 2
        backgroundLayer.addChild(emitter)
        crystalDustEmitter = emitter
    }

    private static let dustAlphaSequence: SKKeyframeSequence = {
        SKKeyframeSequence(keyframeValues: [0.0, 0.75, 0.5, 0.0], times: [0.0, 0.15, 0.7, 1.0])
    }()

    private func buildStars() {
        var rng = SystemRandomNumberGenerator()
        starFractions.removeAll()
        starNodes.removeAll()
        for _ in 0..<36 {
            let fx = CGFloat.random(in: 0...1, using: &rng)
            let fy = CGFloat.random(in: 0...1, using: &rng)
            let r = CGFloat.random(in: 0.6...1.5, using: &rng)
            starFractions.append((CGPoint(x: fx, y: fy), r))
            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor = Palette.moonlight
            dot.strokeColor = .clear
            dot.alpha = CGFloat.random(in: 0.12...0.5, using: &rng)
            starLayer.addChild(dot)
            starNodes.append(dot)
            let twinkle = SKAction.sequence([
                SKAction.fadeAlpha(to: dot.alpha * 0.3, duration: Double.random(in: 1.4...3.2)),
                SKAction.fadeAlpha(to: dot.alpha, duration: Double.random(in: 1.4...3.2))
            ])
            dot.run(SKAction.repeatForever(twinkle))
        }
    }

    // MARK: - Panel background

    private func buildPanelBackground() {
        let panel = SKShapeNode()
        panel.fillColor = Palette.panelFill
        panel.strokeColor = Palette.panelStroke
        panel.lineWidth = 1.5
        panel.zPosition = 1
        panel.name = "hangarPanelBG"
        panelLayer.addChild(panel)
        panelBG = panel
    }

    // MARK: - Header

    private func buildHeader() {
        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "STARSHIP HANGAR"
        title.fontSize = 21
        title.fontColor = Palette.moonlight
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.zPosition = 2
        panelLayer.addChild(title)
        titleLabel = title

        let (close, closeText) = Self.makeButton(text: "X", width: 40, height: 40,
                                                  fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                  textColor: Palette.moonlight, fontSize: 18, fontName: "AvenirNext-DemiBold")
        close.name = "hangarClose"
        closeText.name = "hangarClose"
        close.zPosition = 2
        closeText.zPosition = 3
        panelLayer.addChild(close)
        panelLayer.addChild(closeText)
        closeButton = close
        closeLabel = closeText

        let icon = SKSpriteNode(texture: Self.gemTexture(diameter: 20, color: Palette.crystal))
        icon.name = "crystalIcon"
        icon.zPosition = 2
        panelLayer.addChild(icon)
        crystalIconNode = icon

        let balance = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        balance.fontSize = 17
        balance.fontColor = Palette.crystal
        balance.horizontalAlignmentMode = .left
        balance.verticalAlignmentMode = .center
        balance.zPosition = 2
        panelLayer.addChild(balance)
        crystalBalanceLabel = balance
    }

    // MARK: - Tabs

    private func buildTabs() {
        for (index, title) in Self.hangarTabTitles.enumerated() {
            let (btn, label) = Self.makeButton(text: title, width: 100, height: 32,
                                                fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                textColor: Palette.moonlightDim, fontSize: 12.5, fontName: "AvenirNext-DemiBold")
            btn.name = "hangarTab_\(index)"
            label.name = "hangarTab_\(index)"
            btn.zPosition = 2
            label.zPosition = 3
            panelLayer.addChild(btn)
            panelLayer.addChild(label)
            tabButtons.append(btn)
            tabLabels.append(label)
        }
    }

    // MARK: - Ship rows (tab 0)

    private func buildShipRows() {
        for stat in Self.shipStats {
            let container = SKNode()
            container.zPosition = 2
            shipTabLayer.addChild(container)

            let bg = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.shipRowHeight), cornerRadius: 12)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            bg.lineWidth = 1
            container.addChild(bg)

            let icon = SKSpriteNode(texture: Self.shipStatIconTexture(stat, diameter: 30))
            icon.position = CGPoint(x: -Self.rowWidth / 2 + 30, y: Self.shipRowHeight / 2 - 20)
            container.addChild(icon)

            let name = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            name.text = Self.shipStatName(stat)
            name.fontSize = 15
            name.fontColor = Palette.moonlight
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: -Self.rowWidth / 2 + 54, y: Self.shipRowHeight / 2 - 20)
            container.addChild(name)

            let level = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            level.fontSize = 12
            level.fontColor = Palette.crystal
            level.horizontalAlignmentMode = .right
            level.verticalAlignmentMode = .center
            level.position = CGPoint(x: Self.rowWidth / 2 - 14, y: Self.shipRowHeight / 2 - 20)
            container.addChild(level)

            let flavor = SKLabelNode(fontNamed: "AvenirNext-Regular")
            flavor.text = Self.shipStatFlavor(stat)
            flavor.fontSize = 10.5
            flavor.fontColor = Palette.moonlightDim
            flavor.horizontalAlignmentMode = .left
            flavor.verticalAlignmentMode = .top
            flavor.numberOfLines = 2
            flavor.preferredMaxLayoutWidth = Self.rowWidth - 28
            flavor.lineBreakMode = .byWordWrapping
            flavor.position = CGPoint(x: -Self.rowWidth / 2 + 14, y: 0)
            container.addChild(flavor)

            let (buy, buyText) = Self.makeButton(text: "BUY", width: 92, height: 30,
                                                  fill: Palette.crystal, stroke: Palette.moonlight,
                                                  textColor: Palette.crystalText,
                                                  fontSize: 12, fontName: "AvenirNext-Heavy")
            buy.position = CGPoint(x: Self.rowWidth / 2 - 60, y: -Self.shipRowHeight / 2 + 18)
            buy.name = "upgradeShip_\(Self.shipStatKey(stat))"
            buyText.name = buy.name
            buyText.position = buy.position
            container.addChild(buy)
            container.addChild(buyText)

            let maxed = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            maxed.text = "MAXED"
            maxed.fontSize = 13
            maxed.fontColor = Palette.violet
            maxed.horizontalAlignmentMode = .center
            maxed.verticalAlignmentMode = .center
            maxed.position = buy.position
            maxed.isHidden = true
            container.addChild(maxed)

            shipRows[stat] = ShipRowNodes(container: container, background: bg, icon: icon, nameLabel: name,
                                           levelLabel: level, flavorLabel: flavor, buyButton: buy, buyLabel: buyText,
                                           maxedLabel: maxed)
        }
    }

    // MARK: - Drone rows (tab 1)

    private func buildDroneRows() {
        for kind in DroneKind.allCases {
            let container = SKNode()
            container.zPosition = 2
            droneTabLayer.addChild(container)

            let bg = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.droneRowHeight), cornerRadius: 12)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            bg.lineWidth = 1
            container.addChild(bg)

            let icon = SKSpriteNode(texture: Self.droneIconTexture(kind, diameter: 34))
            icon.position = CGPoint(x: -Self.rowWidth / 2 + 30, y: Self.droneRowHeight / 2 - 26)
            container.addChild(icon)

            let name = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            name.text = kind.displayName
            name.fontSize = 15
            name.fontColor = Palette.moonlight
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: -Self.rowWidth / 2 + 58, y: Self.droneRowHeight / 2 - 26)
            container.addChild(name)

            let status = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            status.fontSize = 12
            status.fontColor = Palette.moonlightDim
            status.horizontalAlignmentMode = .right
            status.verticalAlignmentMode = .center
            status.position = CGPoint(x: Self.rowWidth / 2 - 14, y: Self.droneRowHeight / 2 - 26)
            container.addChild(status)

            let flavor = SKLabelNode(fontNamed: "AvenirNext-Regular")
            flavor.text = kind.flavorText
            flavor.fontSize = 10.5
            flavor.fontColor = Palette.moonlightDim
            flavor.horizontalAlignmentMode = .left
            flavor.verticalAlignmentMode = .top
            flavor.numberOfLines = 2
            flavor.preferredMaxLayoutWidth = Self.rowWidth - 28
            flavor.lineBreakMode = .byWordWrapping
            flavor.position = CGPoint(x: -Self.rowWidth / 2 + 14, y: Self.droneRowHeight / 2 - 46)
            container.addChild(flavor)

            let (primary, primaryText) = Self.makeButton(text: "UNLOCK", width: 108, height: 30,
                                                           fill: Palette.crystal, stroke: Palette.moonlight,
                                                           textColor: Palette.crystalText,
                                                           fontSize: 11.5, fontName: "AvenirNext-Heavy")
            primary.position = CGPoint(x: 0, y: -Self.droneRowHeight / 2 + 18)
            primary.name = "unlockDrone_\(kind.rawValue)"
            primaryText.name = primary.name
            primaryText.position = primary.position
            container.addChild(primary)
            container.addChild(primaryText)

            let maxed = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            maxed.text = "MAXED"
            maxed.fontSize = 13
            maxed.fontColor = Palette.violet
            maxed.horizontalAlignmentMode = .center
            maxed.verticalAlignmentMode = .center
            maxed.position = CGPoint(x: -Self.rowWidth / 2 + 70, y: -Self.droneRowHeight / 2 + 18)
            maxed.isHidden = true
            container.addChild(maxed)

            let (equip, equipText) = Self.makeButton(text: "EQUIP", width: 116, height: 30,
                                                       fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                       textColor: Palette.moonlight,
                                                       fontSize: 11.5, fontName: "AvenirNext-Heavy")
            equip.position = CGPoint(x: Self.rowWidth / 2 - 64, y: -Self.droneRowHeight / 2 + 18)
            equip.name = "equipDrone_\(kind.rawValue)"
            equipText.name = equip.name
            equipText.position = equip.position
            equip.isHidden = true
            equipText.isHidden = true
            container.addChild(equip)
            container.addChild(equipText)

            droneRows[kind] = DroneRowNodes(container: container, background: bg, icon: icon, nameLabel: name,
                                             statusLabel: status, flavorLabel: flavor, primaryButton: primary,
                                             primaryLabel: primaryText, maxedLabel: maxed, equipButton: equip,
                                             equipLabel: equipText)
        }
    }

    // MARK: - Planet rows (tab 2)

    private func buildPlanetRows() {
        for kind in PlanetKind.unlockOrder {
            let container = SKNode()
            container.zPosition = 2
            planetTabLayer.addChild(container)

            let bg = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.planetRowHeight), cornerRadius: 12)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            bg.lineWidth = 1
            container.addChild(bg)

            let icon = SKSpriteNode(texture: Self.planetIconTexture(kind, diameter: 44))
            icon.position = CGPoint(x: -Self.rowWidth / 2 + 34, y: 6)
            container.addChild(icon)

            let lock = SKLabelNode(fontNamed: "AvenirNext-Bold")
            lock.text = "🔒"
            lock.fontSize = 13
            lock.horizontalAlignmentMode = .center
            lock.verticalAlignmentMode = .center
            lock.position = CGPoint(x: -Self.rowWidth / 2 + 46, y: -10)
            lock.isHidden = true
            container.addChild(lock)

            let name = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            name.text = kind.displayName
            name.fontSize = 15
            name.fontColor = Palette.moonlight
            name.horizontalAlignmentMode = .left
            name.verticalAlignmentMode = .center
            name.position = CGPoint(x: -Self.rowWidth / 2 + 70, y: 30)
            container.addChild(name)

            let flavor = SKLabelNode(fontNamed: "AvenirNext-Regular")
            flavor.text = kind.flavorText
            flavor.fontSize = 10
            flavor.fontColor = Palette.moonlightDim
            flavor.horizontalAlignmentMode = .left
            flavor.verticalAlignmentMode = .top
            flavor.numberOfLines = 2
            flavor.preferredMaxLayoutWidth = 148
            flavor.lineBreakMode = .byWordWrapping
            flavor.position = CGPoint(x: -Self.rowWidth / 2 + 70, y: 14)
            container.addChild(flavor)

            let cost = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            cost.fontSize = 11
            cost.fontColor = Palette.crystal
            cost.horizontalAlignmentMode = .center
            cost.verticalAlignmentMode = .center
            cost.position = CGPoint(x: Self.rowWidth / 2 - 52, y: 30)
            container.addChild(cost)

            let (action, actionText) = Self.makeButton(text: "UNLOCK", width: 100, height: 30,
                                                        fill: Palette.crystal, stroke: Palette.moonlight,
                                                        textColor: Palette.crystalText,
                                                        fontSize: 12, fontName: "AvenirNext-Heavy")
            action.position = CGPoint(x: Self.rowWidth / 2 - 52, y: -6)
            action.name = "unlockPlanet_\(kind.rawValue)"
            actionText.name = action.name
            actionText.position = action.position
            container.addChild(action)
            container.addChild(actionText)

            planetRows[kind] = PlanetRowNodes(container: container, background: bg, icon: icon, lockBadge: lock,
                                               nameLabel: name, flavorLabel: flavor, costLabel: cost,
                                               actionButton: action, actionLabel: actionText)
        }
    }

    // MARK: - Layout (called on didMove and every didChangeSize — resizeFill re-sizes the scene)

    private func layout(size: CGSize) {
        let w = size.width, h = size.height

        if let bg = backgroundLayer.childNode(withName: "bgGradient") as? SKSpriteNode {
            bg.size = CGSize(width: w, height: h)
            bg.position = CGPoint(x: w / 2, y: h / 2)
        }
        nebulaGlow.position = CGPoint(x: w * 0.5, y: h * 0.9)
        crystalDustEmitter.particlePosition = CGPoint(x: w / 2, y: -10)
        crystalDustEmitter.particlePositionRange = CGVector(dx: w * 1.1, dy: 0)

        for (i, node) in starNodes.enumerated() {
            let (fraction, _) = starFractions[i]
            node.position = CGPoint(x: fraction.x * w, y: fraction.y * h)
        }

        let listHeightMax = max(
            CGFloat(Self.shipStats.count) * Self.shipRowHeight + CGFloat(Self.shipStats.count - 1) * Self.rowSpacing,
            CGFloat(DroneKind.allCases.count) * Self.droneRowHeight + CGFloat(DroneKind.allCases.count - 1) * Self.rowSpacing,
            CGFloat(PlanetKind.unlockOrder.count) * Self.planetRowHeight + CGFloat(PlanetKind.unlockOrder.count - 1) * Self.rowSpacing
        )
        let panelWidth = min(w - 32, Self.rowWidth + 40)
        let panelHeight = min(h - 64, Self.headerTotalHeight + listHeightMax + 20)

        let panelRect = CGRect(x: -panelWidth / 2, y: -panelHeight / 2, width: panelWidth, height: panelHeight)
        panelBG.path = CGPath(roundedRect: panelRect, cornerWidth: 20, cornerHeight: 20, transform: nil)
        panelBG.position = CGPoint(x: w / 2, y: h / 2)

        let panelTop = panelBG.position.y + panelHeight / 2
        titleLabel.position = CGPoint(x: w / 2, y: panelTop - 30)
        closeButton.position = CGPoint(x: w / 2 + panelWidth / 2 - 32, y: panelTop - 30)
        closeLabel.position = closeButton.position

        layoutCrystalBalance(centerY: panelTop - 62, width: w)

        let tabsY = panelTop - 96
        let tabWidth: CGFloat = 100, tabGap: CGFloat = 8
        let totalTabsWidth = CGFloat(tabButtons.count) * tabWidth + CGFloat(max(0, tabButtons.count - 1)) * tabGap
        var tabX = w / 2 - totalTabsWidth / 2 + tabWidth / 2
        for i in 0..<tabButtons.count {
            tabButtons[i].position = CGPoint(x: tabX, y: tabsY)
            tabLabels[i].position = tabButtons[i].position
            tabX += tabWidth + tabGap
        }

        let listTop = panelTop - Self.headerTotalHeight
        layoutShipRows(topY: listTop, centerX: w / 2)
        layoutDroneRows(topY: listTop, centerX: w / 2)
        layoutPlanetRows(topY: listTop, centerX: w / 2)
    }

    private func layoutCrystalBalance(centerY: CGFloat, width w: CGFloat) {
        let text = crystalBalanceLabel.text ?? "0"
        let textWidth = Self.measureWidth(text, fontName: "AvenirNext-DemiBold", fontSize: 17)
        let totalWidth = textWidth + 26
        let iconX = w / 2 - totalWidth / 2 + 10
        let textX = iconX + 16
        crystalBalanceLabel.position = CGPoint(x: textX, y: centerY)
        crystalIconNode.position = CGPoint(x: iconX, y: centerY)
    }

    private func layoutShipRows(topY: CGFloat, centerX: CGFloat) {
        var rowY = topY
        for stat in Self.shipStats {
            guard let row = shipRows[stat] else { continue }
            row.container.position = CGPoint(x: centerX, y: rowY - Self.shipRowHeight / 2)
            rowY -= (Self.shipRowHeight + Self.rowSpacing)
        }
    }

    private func layoutDroneRows(topY: CGFloat, centerX: CGFloat) {
        var rowY = topY
        for kind in DroneKind.allCases {
            guard let row = droneRows[kind] else { continue }
            row.container.position = CGPoint(x: centerX, y: rowY - Self.droneRowHeight / 2)
            rowY -= (Self.droneRowHeight + Self.rowSpacing)
        }
    }

    private func layoutPlanetRows(topY: CGFloat, centerX: CGFloat) {
        var rowY = topY
        for kind in PlanetKind.unlockOrder {
            guard let row = planetRows[kind] else { continue }
            row.container.position = CGPoint(x: centerX, y: rowY - Self.planetRowHeight / 2)
            rowY -= (Self.planetRowHeight + Self.rowSpacing)
        }
    }

    // MARK: - Refresh

    private func refreshAll() {
        refreshCrystalBalance()
        for stat in Self.shipStats { refreshShipRow(stat) }
        for kind in DroneKind.allCases { refreshDroneRow(kind) }
        for kind in PlanetKind.unlockOrder { refreshPlanetRow(kind) }
    }

    private func refreshCrystalBalance() {
        crystalBalanceLabel.text = "\(EmpireStore.shared.crystals)"
        if hasBuiltOnce { layoutCrystalBalance(centerY: crystalBalanceLabel.position.y, width: size.width) }
    }

    private func refreshShipRow(_ stat: EmpireStore.ShipStat) {
        guard let row = shipRows[stat] else { return }
        let level = Self.shipStatLevel(stat)
        row.levelLabel.text = "LVL \(level)/\(EmpireStore.maxShipStatLevel)"

        if let cost = EmpireStore.shared.nextShipUpgradeCost(stat: stat) {
            let canAfford = EmpireStore.shared.crystals >= cost
            row.buyButton.isHidden = false
            row.buyLabel.isHidden = false
            row.maxedLabel.isHidden = true
            row.buyLabel.text = "\(cost) ✦"
            row.buyButton.alpha = canAfford ? 1.0 : 0.4
            row.buyLabel.alpha = canAfford ? 1.0 : 0.6
        } else {
            row.buyButton.isHidden = true
            row.buyLabel.isHidden = true
            row.maxedLabel.isHidden = false
        }
    }

    private func refreshDroneRow(_ kind: DroneKind) {
        guard let row = droneRows[kind] else { return }
        let owned = EmpireStore.shared.isDroneOwned(kind)
        let equipped = EmpireStore.shared.equippedDrones().contains(kind)

        if !owned {
            row.statusLabel.text = "LOCKED"
            row.maxedLabel.isHidden = true
            row.primaryButton.isHidden = false
            row.primaryLabel.isHidden = false
            row.primaryButton.name = "unlockDrone_\(kind.rawValue)"
            row.primaryLabel.name = row.primaryButton.name
            row.primaryLabel.text = "UNLOCK \(kind.unlockCost) ✦"
            row.primaryButton.position = CGPoint(x: 0, y: -Self.droneRowHeight / 2 + 18)
            row.primaryLabel.position = row.primaryButton.position
            let canAfford = EmpireStore.shared.crystals >= kind.unlockCost
            row.primaryButton.alpha = canAfford ? 1.0 : 0.4
            row.primaryLabel.alpha = canAfford ? 1.0 : 0.6
            row.equipButton.isHidden = true
            row.equipLabel.isHidden = true
        } else {
            let level = EmpireStore.shared.droneLevel(kind)
            row.statusLabel.text = "LVL \(level)/\(DroneKind.maxLevel)"
            let leftX = -Self.rowWidth / 2 + 70
            if let cost = EmpireStore.shared.nextDroneUpgradeCost(kind) {
                row.maxedLabel.isHidden = true
                row.primaryButton.isHidden = false
                row.primaryLabel.isHidden = false
                row.primaryButton.name = "upgradeDrone_\(kind.rawValue)"
                row.primaryLabel.name = row.primaryButton.name
                row.primaryLabel.text = "UPGRADE \(cost) ✦"
                row.primaryButton.position = CGPoint(x: leftX, y: -Self.droneRowHeight / 2 + 18)
                row.primaryLabel.position = row.primaryButton.position
                let canAfford = EmpireStore.shared.crystals >= cost
                row.primaryButton.alpha = canAfford ? 1.0 : 0.4
                row.primaryLabel.alpha = canAfford ? 1.0 : 0.6
            } else {
                row.primaryButton.isHidden = true
                row.primaryLabel.isHidden = true
                row.maxedLabel.isHidden = false
                row.maxedLabel.position = CGPoint(x: leftX, y: -Self.droneRowHeight / 2 + 18)
            }
            row.equipButton.isHidden = false
            row.equipLabel.isHidden = false
            row.equipButton.name = "equipDrone_\(kind.rawValue)"
            row.equipLabel.name = row.equipButton.name
            row.equipLabel.text = equipped ? "✓ EQUIPPED" : "EQUIP"
        }

        if equipped {
            row.background.fillColor = Palette.crystal.withAlphaComponent(0.20)
            row.background.strokeColor = Palette.crystal
            row.background.lineWidth = 2.0
            row.equipButton.fillColor = Palette.crystal
            row.equipButton.strokeColor = Palette.moonlight
            row.equipLabel.fontColor = Palette.crystalText
        } else {
            row.background.fillColor = Palette.rowFill
            row.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            row.background.lineWidth = 1
            row.equipButton.fillColor = Palette.rowFill
            row.equipButton.strokeColor = Palette.panelStroke
            row.equipLabel.fontColor = Palette.moonlight
        }
        row.container.alpha = owned ? 1.0 : 0.85
    }

    private func refreshPlanetRow(_ kind: PlanetKind) {
        guard let row = planetRows[kind] else { return }
        let unlocked = EmpireStore.shared.isPlanetUnlocked(kind)
        let selected = EmpireStore.shared.selectedPlanet == kind

        row.lockBadge.isHidden = unlocked
        if unlocked {
            row.costLabel.isHidden = true
            row.actionButton.name = "selectPlanet_\(kind.rawValue)"
            row.actionLabel.name = row.actionButton.name
            row.actionLabel.text = selected ? "✓ SELECTED" : "SELECT"
            row.actionButton.fillColor = selected ? Palette.crystal : Palette.rowFill
            row.actionButton.strokeColor = selected ? Palette.moonlight : Palette.panelStroke
            row.actionLabel.fontColor = selected ? Palette.crystalText : Palette.moonlight
        } else {
            row.costLabel.isHidden = false
            row.costLabel.text = "\(kind.unlockCrystalCost) ✦"
            row.actionButton.name = "unlockPlanet_\(kind.rawValue)"
            row.actionLabel.name = row.actionButton.name
            row.actionLabel.text = "UNLOCK"
            row.actionButton.fillColor = Palette.crystal
            row.actionButton.strokeColor = Palette.moonlight
            row.actionLabel.fontColor = Palette.crystalText
            let canAfford = EmpireStore.shared.crystals >= kind.unlockCrystalCost
            row.actionButton.alpha = canAfford ? 1.0 : 0.4
            row.actionLabel.alpha = canAfford ? 1.0 : 0.6
        }
        if unlocked { row.actionButton.alpha = 1.0; row.actionLabel.alpha = 1.0 }

        if selected {
            row.background.fillColor = Palette.crystal.withAlphaComponent(0.18)
            row.background.strokeColor = Palette.crystal
            row.background.lineWidth = 2.0
        } else if unlocked {
            row.background.fillColor = Palette.rowFill
            row.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            row.background.lineWidth = 1
        } else {
            row.background.fillColor = Palette.rowFill
            row.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.25)
            row.background.lineWidth = 1
        }
        row.container.alpha = unlocked ? 1.0 : 0.85
    }

    // MARK: - Tab visibility

    private func refreshTabVisibility() {
        shipTabLayer.isHidden = selectedTab != 0
        droneTabLayer.isHidden = selectedTab != 1
        planetTabLayer.isHidden = selectedTab != 2
        for (i, btn) in tabButtons.enumerated() {
            let active = i == selectedTab
            btn.fillColor = active ? Palette.crystal : Palette.rowFill
            btn.strokeColor = active ? Palette.moonlight : Palette.panelStroke
            tabLabels[i].fontColor = active ? Palette.crystalText : Palette.moonlightDim
        }
    }

    private func handleHangarTabTap(_ index: Int) {
        guard index != selectedTab, index >= 0, index < tabButtons.count else { return }
        AudioManager.shared.playSFX(.buttonTap)
        selectedTab = index
        refreshTabVisibility()
        let activeLayer: SKNode
        switch selectedTab {
        case 0: activeLayer = shipTabLayer
        case 1: activeLayer = droneTabLayer
        default: activeLayer = planetTabLayer
        }
        activeLayer.alpha = 0
        activeLayer.run(SKAction.fadeIn(withDuration: 0.15))
    }

    // MARK: - Touch handling (manual name-based routing, identical pattern to MenuScene — no physics)

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

    /// SpriteKit's `nodes(at:)` is a purely geometric query — it does NOT respect `isHidden`, so
    /// off-screen (hidden) tab content could still geometrically overlap and "steal" taps meant for
    /// the visible tab. Gate candidates explicitly by `selectedTab` instead of trusting node
    /// visibility — same reasoning/pattern as MenuScene.topInteractiveName(at:).
    private func topInteractiveName(at location: CGPoint) -> String? {
        let hit = nodes(at: location)
        let matched = hit.filter { node in
            guard let name = node.name else { return false }
            if name == "hangarClose" { return true }
            if name.hasPrefix("hangarTab_") { return true }
            if name.hasPrefix("upgradeShip_") { return selectedTab == 0 }
            if name.hasPrefix("unlockDrone_") || name.hasPrefix("upgradeDrone_") || name.hasPrefix("equipDrone_") {
                return selectedTab == 1
            }
            if name.hasPrefix("unlockPlanet_") || name.hasPrefix("selectPlanet_") { return selectedTab == 2 }
            return false
        }
        return matched.max(by: { $0.zPosition < $1.zPosition })?.name
    }

    private func setPressed(name: String, pressed: Bool) {
        let scale: CGFloat = pressed ? 0.94 : 1.0
        if name == "hangarClose" {
            closeButton.run(SKAction.scale(to: scale, duration: 0.08))
        } else if name.hasPrefix("hangarTab_") {
            if let idx = Int(name.dropFirst("hangarTab_".count)), idx < tabButtons.count {
                tabButtons[idx].run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("upgradeShip_") {
            if let stat = Self.shipStat(fromKey: String(name.dropFirst("upgradeShip_".count))) {
                shipRows[stat]?.buyButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("unlockDrone_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("unlockDrone_".count))) {
                droneRows[kind]?.primaryButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("upgradeDrone_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("upgradeDrone_".count))) {
                droneRows[kind]?.primaryButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("equipDrone_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("equipDrone_".count))) {
                droneRows[kind]?.equipButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("unlockPlanet_") {
            if let kind = PlanetKind(rawValue: String(name.dropFirst("unlockPlanet_".count))) {
                planetRows[kind]?.actionButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        } else if name.hasPrefix("selectPlanet_") {
            if let kind = PlanetKind(rawValue: String(name.dropFirst("selectPlanet_".count))) {
                planetRows[kind]?.actionButton.run(SKAction.scale(to: scale, duration: 0.08))
            }
        }
    }

    private func handleTap(name: String) {
        if name == "hangarClose" {
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.light)
            view?.presentScene(CommandDeckScene.newScene(), transition: .crossFade(withDuration: 0.4))
        } else if name.hasPrefix("hangarTab_") {
            if let idx = Int(name.dropFirst("hangarTab_".count)) { handleHangarTabTap(idx) }
        } else if name.hasPrefix("upgradeShip_") {
            if let stat = Self.shipStat(fromKey: String(name.dropFirst("upgradeShip_".count))) {
                handleUpgradeShip(stat)
            }
        } else if name.hasPrefix("unlockDrone_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("unlockDrone_".count))) {
                handleUnlockDrone(kind)
            }
        } else if name.hasPrefix("upgradeDrone_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("upgradeDrone_".count))) {
                handleUpgradeDrone(kind)
            }
        } else if name.hasPrefix("equipDrone_") {
            if let kind = DroneKind(rawValue: String(name.dropFirst("equipDrone_".count))) {
                handleEquipDrone(kind)
            }
        } else if name.hasPrefix("unlockPlanet_") {
            if let kind = PlanetKind(rawValue: String(name.dropFirst("unlockPlanet_".count))) {
                handleUnlockPlanet(kind)
            }
        } else if name.hasPrefix("selectPlanet_") {
            if let kind = PlanetKind(rawValue: String(name.dropFirst("selectPlanet_".count))) {
                handleSelectPlanet(kind)
            }
        }
    }

    // MARK: - Purchase / selection handlers

    private func handleUpgradeShip(_ stat: EmpireStore.ShipStat) {
        AudioManager.shared.playSFX(.buttonTap)
        let success = EmpireStore.shared.upgradeShip(stat: stat)
        // Refresh BEFORE flashing: flashSuccess snapshots the row's current (post-refresh) fillColor
        // as the color it restores to, so it doesn't clobber state-dependent styling with a stale value.
        refreshShipRow(stat)
        refreshCrystalBalance()
        if success {
            AudioManager.shared.hapticNotification(.success)
            if let row = shipRows[stat] { flashSuccess(background: row.background, container: row.container) }
        } else {
            AudioManager.shared.hapticImpact(.soft)
        }
    }

    private func handleUnlockDrone(_ kind: DroneKind) {
        AudioManager.shared.playSFX(.buttonTap)
        let success = EmpireStore.shared.unlockDrone(kind)
        // Refresh before flashing — see handleUpgradeShip's comment; matters here because a drone
        // row's background tint depends on equipped state, which the flash must not stomp on.
        refreshDroneRow(kind)
        refreshCrystalBalance()
        if success {
            AudioManager.shared.hapticNotification(.success)
            if let row = droneRows[kind] { flashSuccess(background: row.background, container: row.container) }
        } else {
            AudioManager.shared.hapticImpact(.soft)
        }
    }

    private func handleUpgradeDrone(_ kind: DroneKind) {
        AudioManager.shared.playSFX(.buttonTap)
        let success = EmpireStore.shared.upgradeDrone(kind)
        refreshDroneRow(kind)
        refreshCrystalBalance()
        if success {
            AudioManager.shared.hapticNotification(.success)
            if let row = droneRows[kind] { flashSuccess(background: row.background, container: row.container) }
        } else {
            AudioManager.shared.hapticImpact(.soft)
        }
    }

    /// Toggles `kind` in/out of the equipped fleet. Respects the 3-slot cap (EmpireStore.maxEquippedDrones)
    /// by evicting the oldest-equipped drone to make room rather than refusing the tap — same rotation
    /// pattern MenuScene uses for familiar (pet) slots.
    private func handleEquipDrone(_ kind: DroneKind) {
        guard EmpireStore.shared.isDroneOwned(kind) else { return }
        AudioManager.shared.playSFX(.buttonTap)
        var equipped = EmpireStore.shared.equippedDrones()
        if let idx = equipped.firstIndex(of: kind) {
            equipped.remove(at: idx)
        } else {
            equipped.append(kind)
            while equipped.count > EmpireStore.maxEquippedDrones {
                equipped.removeFirst()
            }
        }
        EmpireStore.shared.setEquippedDrones(equipped)
        AudioManager.shared.hapticImpact(.light)
        for k in DroneKind.allCases { refreshDroneRow(k) }
    }

    private func handleUnlockPlanet(_ kind: PlanetKind) {
        AudioManager.shared.playSFX(.buttonTap)
        let success = EmpireStore.shared.unlockPlanet(kind)
        // Refresh before flashing — see handleUpgradeShip's comment.
        refreshPlanetRow(kind)
        refreshCrystalBalance()
        if success {
            AudioManager.shared.hapticNotification(.success)
            if let row = planetRows[kind] { flashSuccess(background: row.background, container: row.container) }
        } else {
            AudioManager.shared.hapticImpact(.soft)
        }
    }

    private func handleSelectPlanet(_ kind: PlanetKind) {
        guard EmpireStore.shared.isPlanetUnlocked(kind), EmpireStore.shared.selectedPlanet != kind else { return }
        AudioManager.shared.playSFX(.buttonTap)
        EmpireStore.shared.selectedPlanet = kind
        AudioManager.shared.hapticImpact(.light)
        for k in PlanetKind.unlockOrder { refreshPlanetRow(k) }
    }

    private func flashSuccess(background: SKShapeNode, container: SKNode) {
        let originalFill = background.fillColor
        let flash = SKAction.sequence([
            SKAction.run { background.fillColor = Palette.crystal.withAlphaComponent(0.5) },
            SKAction.wait(forDuration: 0.12),
            SKAction.run { background.fillColor = originalFill }
        ])
        let pop = SKAction.sequence([SKAction.scale(to: 1.03, duration: 0.08), SKAction.scale(to: 1.0, duration: 0.1)])
        container.run(SKAction.group([flash, pop]))
    }

    // MARK: - Ship stat metadata (EmpireStore.ShipStat carries no display info of its own)

    private static func shipStatName(_ stat: EmpireStore.ShipStat) -> String {
        switch stat {
        case .hull: return "Hull Plating"
        case .weapon: return "Weapon Systems"
        case .shield: return "Shield Array"
        }
    }

    private static func shipStatFlavor(_ stat: EmpireStore.ShipStat) -> String {
        switch stat {
        case .hull: return "Reinforced plating — raises max hull integrity."
        case .weapon: return "Overcharged cannons — raises fleet attack power."
        case .shield: return "Deflector array — reduces incoming raid damage."
        }
    }

    private static func shipStatKey(_ stat: EmpireStore.ShipStat) -> String {
        switch stat {
        case .hull: return "hull"
        case .weapon: return "weapon"
        case .shield: return "shield"
        }
    }

    private static func shipStat(fromKey key: String) -> EmpireStore.ShipStat? {
        switch key {
        case "hull": return .hull
        case "weapon": return .weapon
        case "shield": return .shield
        default: return nil
        }
    }

    private static func shipStatLevel(_ stat: EmpireStore.ShipStat) -> Int {
        switch stat {
        case .hull: return EmpireStore.shared.hullLevel
        case .weapon: return EmpireStore.shared.weaponLevel
        case .shield: return EmpireStore.shared.shieldLevel
        }
    }

    // MARK: - Procedural icon textures (no image assets — see ProceduralTextures.swift for the pattern)

    private static func shipStatIconTexture(_ stat: EmpireStore.ShipStat, diameter: CGFloat) -> SKTexture {
        switch stat {
        case .hull: return hullIconTexture(diameter: diameter)
        case .weapon: return weaponIconTexture(diameter: diameter)
        case .shield: return shieldStatIconTexture(diameter: diameter)
        }
    }

    private static func droneIconTexture(_ kind: DroneKind, diameter: CGFloat) -> SKTexture {
        switch kind {
        case .interceptor: return interceptorIconTexture(diameter: diameter)
        case .aegis: return aegisIconTexture(diameter: diameter)
        case .harvester: return gemTexture(diameter: diameter, color: Palette.crystal)
        }
    }

    private static func planetIconTexture(_ kind: PlanetKind, diameter: CGFloat) -> SKTexture {
        let tint: SKColor
        switch kind {
        case .emberwatch: tint = Palette.ember
        case .voidreach: tint = Palette.violetDim
        case .lunahaven: tint = Palette.moonlight
        case .crimsonforge: tint = Palette.blood
        case .ashenveil: tint = Palette.violet
        }
        return planetSphereTexture(diameter: diameter, tint: tint)
    }

    private static func hullIconTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.12, dy: size.height * 0.08)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - rect.height * 0.28))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.36))
            path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.maxX, y: rect.minY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY + rect.height * 0.36), control: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - rect.height * 0.28))
            path.closeSubpath()
            ctx.setFillColor(Palette.moonlight.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(Palette.moonlightDim.cgColor)
            ctx.setLineWidth(1.4)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func weaponIconTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: w * 0.58, y: h * 0.95))
            path.addLine(to: CGPoint(x: w * 0.30, y: h * 0.48))
            path.addLine(to: CGPoint(x: w * 0.48, y: h * 0.48))
            path.addLine(to: CGPoint(x: w * 0.40, y: h * 0.05))
            path.addLine(to: CGPoint(x: w * 0.72, y: h * 0.56))
            path.addLine(to: CGPoint(x: w * 0.54, y: h * 0.56))
            path.closeSubpath()
            ctx.setFillColor(Palette.ember.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(Palette.emberBright.cgColor)
            ctx.setLineWidth(1.0)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func shieldStatIconTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = size.width * 0.42
            ctx.setStrokeColor(Palette.crystal.cgColor)
            ctx.setLineWidth(3)
            ctx.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            ctx.strokePath()
            let r2 = r * 0.5
            ctx.setFillColor(Palette.crystal.withAlphaComponent(0.4).cgColor)
            ctx.addEllipse(in: CGRect(x: center.x - r2, y: center.y - r2, width: r2 * 2, height: r2 * 2))
            ctx.fillPath()
        }
    }

    private static func interceptorIconTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.92))
            path.addLine(to: CGPoint(x: w * 0.86, y: h * 0.12))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.34))
            path.addLine(to: CGPoint(x: w * 0.14, y: h * 0.12))
            path.closeSubpath()
            ctx.setFillColor(Palette.blood.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(Palette.emberBright.cgColor)
            ctx.setLineWidth(1.2)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func aegisIconTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.95))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.72))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.30))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.05))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.30))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.72))
            path.closeSubpath()
            ctx.setFillColor(Palette.violet.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(Palette.moonlight.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1.4)
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    /// Faceted diamond shape — used for the Harvester drone icon and the header's Crystal currency icon.
    private static func gemTexture(diameter: CGFloat, color: SKColor) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            let path = CGMutablePath()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.96))
            path.addLine(to: CGPoint(x: w * 0.88, y: h * 0.54))
            path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.04))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.54))
            path.closeSubpath()
            ctx.setFillColor(color.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setStrokeColor(SKColor.white.withAlphaComponent(0.35).cgColor)
            ctx.setLineWidth(1.0)
            ctx.move(to: CGPoint(x: w * 0.5, y: h * 0.96))
            ctx.addLine(to: CGPoint(x: w * 0.5, y: h * 0.04))
            ctx.strokePath()
            ctx.move(to: CGPoint(x: w * 0.12, y: h * 0.54))
            ctx.addLine(to: CGPoint(x: w * 0.88, y: h * 0.54))
            ctx.strokePath()
        }
    }

    private static func planetSphereTexture(diameter: CGFloat, tint: SKColor) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.08, dy: size.width * 0.08)
            let colors = [tint.withAlphaComponent(1.0).cgColor, tint.withAlphaComponent(0.5).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.saveGState()
            ctx.addEllipse(in: rect)
            ctx.clip()
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: rect.minX + rect.width * 0.35, y: rect.maxY - rect.height * 0.35),
                                    startRadius: 0, endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width * 0.75, options: [])
            ctx.restoreGState()
            ctx.setStrokeColor(tint.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(1.2)
            ctx.strokeEllipse(in: rect)
        }
    }

    private static func gradientTexture(top: SKColor, bottom: SKColor, size: CGSize) -> SKTexture {
        ProceduralTextures.render(size: size, opaque: true) { ctx, size in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    // MARK: - Shared button helper (identical to MenuScene.makeButton)

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
        // parent and keep `label.position == shape.position` in sync (see refresh/layout functions
        // above). Nesting here would double-offset the label once the caller repositions it directly.
        return (shape, label)
    }

    private static func measureWidth(_ text: String, fontName: String, fontSize: CGFloat) -> CGFloat {
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        return label.frame.width
    }
}
