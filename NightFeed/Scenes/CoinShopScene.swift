import SpriteKit

/// Crystal purchase shop — reached from the Starfleet Command meta-layer (CommandDeckScene) whenever
/// the player wants to top up Crystals with real money via StoreKit. Pure SpriteKit UI, following
/// MenuScene's exact pattern: every visual is code-drawn (SKShapeNode/SKLabelNode/SKSpriteNode with
/// ProceduralTextures-rendered textures), manual name-based touch routing, no physics world, no UIKit
/// gestures.
///
/// IAPManager (Systems/IAPManager.swift) is `@MainActor`; every read/write against it from here is
/// funnelled through `Task { @MainActor in ... }` blocks that extract plain values before handing them
/// back to this scene's own (non-isolated, same as MenuScene) methods — this scene's touch-handling
/// overrides stay identical in shape to MenuScene's and never need their own actor annotation.
final class CoinShopScene: SKScene {

    // MARK: - Palette (same deep violet-black nights as MenuScene, plus a crystal-cyan accent for this
    // currency specifically — kept visually distinct from the ember/gold of the survival-mode shop).

    private enum Palette {
        static let bgTop = SKColor(red: 0.07, green: 0.04, blue: 0.11, alpha: 1)
        static let bgBottom = SKColor(red: 0.02, green: 0.012, blue: 0.03, alpha: 1)
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
        static let crystalCyan = SKColor(red: 0.42, green: 0.86, blue: 0.95, alpha: 1)
        static let crystalDeep = SKColor(red: 0.22, green: 0.40, blue: 0.90, alpha: 1)
        static let successGreen = SKColor(red: 0.36, green: 0.86, blue: 0.5, alpha: 1)
        static let ink = SKColor(red: 0.03, green: 0.08, blue: 0.13, alpha: 1)
    }

    static func newScene() -> CoinShopScene {
        let scene = CoinShopScene(size: CGSize(width: 393, height: 852))
        scene.scaleMode = .resizeFill
        return scene
    }

    // MARK: - Layers

    private let backgroundLayer = SKNode()
    private let starLayer = SKNode()
    private let contentLayer = SKNode()

    // MARK: - Content refs

    private var titleLabel: SKLabelNode!
    private var subtitleLabel: SKLabelNode!
    private var balancePill: SKShapeNode!
    private var balanceIcon: SKSpriteNode!
    private var balanceLabel: SKLabelNode!
    private var closeButton: SKShapeNode!
    private var closeLabel: SKLabelNode!
    private var restoreLabel: SKLabelNode!
    private var footerLabel: SKLabelNode!

    private var starFractions: [(CGPoint, CGFloat)] = []
    private var starNodes: [SKShapeNode] = []
    private var cardRows: [CrystalPackage: CardNodes] = [:]

    private var pressedNodeName: String?
    private var hasBuiltOnce = false

    /// Which package (if any) currently has a purchase Task in flight — gates buy taps on every card,
    /// not just the pressed one, so a second tap can never fire a second overlapping StoreKit sheet.
    private var pendingPurchase: CrystalPackage?

    /// Locally cached real price strings, filled in once IAPManager's products finish loading. Falls
    /// back to "BUY" per-card until a given package's entry lands here — see applyPrices(_:).
    private var loadedPrices: [CrystalPackage: String] = [:]

    // MARK: - Card model

    private struct CardNodes {
        let container: SKNode
        let background: SKShapeNode
        let buyButton: SKShapeNode
        let buyLabel: SKLabelNode
    }

    private static let fallbackBuyText = "BUY"
    private static let iconDiameters: [CGFloat] = [38, 44, 52, 60, 70] // pouch -> vault, ascending

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.bgBottom

        if !hasBuiltOnce {
            addChild(backgroundLayer)
            addChild(starLayer)
            addChild(contentLayer)
            backgroundLayer.zPosition = ZPosition.menuUI - 5
            starLayer.zPosition = ZPosition.menuUI - 3
            contentLayer.zPosition = ZPosition.menuUI

            buildBackground()
            buildStars()
            buildHeader()
            buildCards()
            buildFooter()
            hasBuiltOnce = true
        }

        refreshBalance()
        layout(size: size)
        loadAndApplyPrices()
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

        let glow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.crystalDeep, radius: 240))
        glow.name = "shopGlow"
        glow.alpha = 0.35
        glow.zPosition = 1
        glow.blendMode = .add
        backgroundLayer.addChild(glow)

        let pulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 2.8),
            SKAction.fadeAlpha(to: 0.3, duration: 2.8)
        ])
        glow.run(SKAction.repeatForever(pulse))
    }

    private func buildStars() {
        var rng = SystemRandomNumberGenerator()
        starFractions.removeAll()
        starNodes.removeAll()
        for _ in 0..<30 {
            let fx = CGFloat.random(in: 0...1, using: &rng)
            let fy = CGFloat.random(in: 0...1, using: &rng)
            let r = CGFloat.random(in: 0.6...1.5, using: &rng)
            starFractions.append((CGPoint(x: fx, y: fy), r))
            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor = Palette.moonlight
            dot.strokeColor = .clear
            dot.alpha = CGFloat.random(in: 0.1...0.5, using: &rng)
            starLayer.addChild(dot)
            starNodes.append(dot)
            let twinkle = SKAction.sequence([
                SKAction.fadeAlpha(to: dot.alpha * 0.3, duration: Double.random(in: 1.6...3.4)),
                SKAction.fadeAlpha(to: dot.alpha, duration: Double.random(in: 1.6...3.4))
            ])
            dot.run(SKAction.repeatForever(twinkle))
        }
    }

    // MARK: - Header

    private func buildHeader() {
        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "CRYSTAL SHOP"
        title.fontSize = 30
        title.fontColor = Palette.moonlight
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.zPosition = 2
        contentLayer.addChild(title)
        titleLabel = title

        let sub = SKLabelNode(fontNamed: "AvenirNext-Medium")
        sub.text = Self.letterSpaced("FUEL YOUR STARFLEET")
        sub.fontSize = 12
        sub.fontColor = Palette.crystalCyan
        sub.horizontalAlignmentMode = .center
        sub.verticalAlignmentMode = .center
        sub.zPosition = 2
        contentLayer.addChild(sub)
        subtitleLabel = sub

        let pill = SKShapeNode(rectOf: CGSize(width: 196, height: 44), cornerRadius: 22)
        pill.fillColor = Palette.rowFill
        pill.strokeColor = Palette.crystalCyan.withAlphaComponent(0.6)
        pill.lineWidth = 1.5
        pill.zPosition = 2
        contentLayer.addChild(pill)
        balancePill = pill

        let icon = SKSpriteNode(texture: Self.crystalTexture(diameter: 26, tint: Palette.crystalCyan))
        icon.zPosition = 3
        contentLayer.addChild(icon)
        balanceIcon = icon

        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.fontSize = 19
        label.fontColor = Palette.moonlight
        label.horizontalAlignmentMode = .left
        label.verticalAlignmentMode = .center
        label.zPosition = 3
        contentLayer.addChild(label)
        balanceLabel = label

        let (close, closeText) = Self.makeButton(text: "\u{2715}", width: 40, height: 40,
                                                  fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                  textColor: Palette.moonlight, fontSize: 17, fontName: "AvenirNext-DemiBold")
        close.name = "coinShopClose"
        closeText.name = "coinShopClose"
        close.zPosition = 2
        closeText.zPosition = 3
        contentLayer.addChild(close)
        contentLayer.addChild(closeText)
        closeButton = close
        closeLabel = closeText

        let restore = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        restore.text = "Restore Purchases"
        restore.fontSize = 12.5
        restore.fontColor = Palette.moonlightDim
        restore.horizontalAlignmentMode = .center
        restore.verticalAlignmentMode = .center
        restore.name = "coinShopRestore"
        restore.zPosition = 2
        contentLayer.addChild(restore)
        restoreLabel = restore
    }

    private func buildFooter() {
        let footer = SKLabelNode(fontNamed: "AvenirNext-Medium")
        footer.text = "Crystals never expire \u{2022} spend them at the Starship, Drones, or Star Map"
        footer.fontSize = 10.5
        footer.fontColor = Palette.moonlightDim
        footer.horizontalAlignmentMode = .center
        footer.verticalAlignmentMode = .center
        footer.numberOfLines = 2
        footer.preferredMaxLayoutWidth = 320
        footer.lineBreakMode = .byWordWrapping
        footer.zPosition = 2
        contentLayer.addChild(footer)
        footerLabel = footer
    }

    // MARK: - Cards

    private static let rowWidth: CGFloat = 336
    private static let rowHeight: CGFloat = 100
    private static let rowSpacing: CGFloat = 14

    private func buildCards() {
        for (index, package) in CrystalPackage.allCases.enumerated() {
            cardRows[package] = buildCard(for: package, index: index)
        }
    }

    private func buildCard(for package: CrystalPackage, index: Int) -> CardNodes {
        let cardName = "buyCrystals_\(package.rawValue)"

        let container = SKNode()
        container.zPosition = 2
        contentLayer.addChild(container)

        let bg = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.rowHeight), cornerRadius: 16)
        bg.fillColor = Palette.rowFill
        bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.45)
        bg.lineWidth = 1.5
        bg.name = cardName
        container.addChild(bg)

        let diameter = Self.iconDiameters[min(index, Self.iconDiameters.count - 1)]
        if index >= 3 {
            // Hoard/Vault get a soft glow halo behind the gem — a small premium-tier flourish.
            let glow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.crystalCyan, radius: diameter))
            glow.alpha = 0.5
            glow.blendMode = .add
            glow.position = CGPoint(x: -Self.rowWidth / 2 + 48, y: 0)
            container.addChild(glow)
        }

        let icon = SKSpriteNode(texture: Self.crystalTexture(diameter: diameter, tint: Palette.crystalCyan))
        icon.name = cardName
        icon.position = CGPoint(x: -Self.rowWidth / 2 + 48, y: 0)
        container.addChild(icon)

        let nameLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        nameLabel.text = package.displayName
        nameLabel.fontSize = 16.5
        nameLabel.fontColor = Palette.moonlight
        nameLabel.horizontalAlignmentMode = .left
        nameLabel.verticalAlignmentMode = .center
        nameLabel.name = cardName
        nameLabel.position = CGPoint(x: -Self.rowWidth / 2 + 92, y: 16)
        container.addChild(nameLabel)

        let amountLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
        amountLabel.text = "+\(package.crystalAmount) Crystals"
        amountLabel.fontSize = 13
        amountLabel.fontColor = Palette.crystalCyan
        amountLabel.horizontalAlignmentMode = .left
        amountLabel.verticalAlignmentMode = .center
        amountLabel.name = cardName
        amountLabel.position = CGPoint(x: -Self.rowWidth / 2 + 92, y: -10)
        container.addChild(amountLabel)

        let (buy, buyLabel) = Self.makeButton(text: Self.fallbackBuyText, width: 92, height: 42,
                                               fill: Palette.crystalCyan, stroke: Palette.crystalDeep,
                                               textColor: Palette.ink, fontSize: 15, fontName: "AvenirNext-Heavy")
        buy.position = CGPoint(x: Self.rowWidth / 2 - 58, y: 0)
        buyLabel.position = buy.position
        buy.name = cardName
        buyLabel.name = cardName
        buy.zPosition = 1
        buyLabel.zPosition = 2
        container.addChild(buy)
        container.addChild(buyLabel)

        return CardNodes(container: container, background: bg, buyButton: buy, buyLabel: buyLabel)
    }

    // MARK: - Layout

    private func layout(size: CGSize) {
        let w = size.width, h = size.height

        if let bg = backgroundLayer.childNode(withName: "bgGradient") as? SKSpriteNode {
            bg.size = CGSize(width: w, height: h)
            bg.position = CGPoint(x: w / 2, y: h / 2)
        }
        backgroundLayer.childNode(withName: "shopGlow")?.position = CGPoint(x: w / 2, y: h * 0.82)

        for (i, node) in starNodes.enumerated() {
            let (fraction, _) = starFractions[i]
            node.position = CGPoint(x: fraction.x * w, y: fraction.y * h)
        }

        let topInset: CGFloat = max(56, h * 0.075)
        titleLabel.position = CGPoint(x: w / 2, y: h - topInset)
        subtitleLabel.position = CGPoint(x: w / 2, y: h - topInset - 26)

        let pillY = h - topInset - 76
        balancePill.position = CGPoint(x: w / 2, y: pillY)
        balanceIcon.position = CGPoint(x: w / 2 - 52, y: pillY)
        balanceLabel.position = CGPoint(x: w / 2 - 30, y: pillY)

        closeButton.position = CGPoint(x: w - 34, y: h - 42)
        closeLabel.position = closeButton.position

        let listTop = pillY - 56
        var rowY = listTop
        for package in CrystalPackage.allCases {
            guard let row = cardRows[package] else { continue }
            row.container.position = CGPoint(x: w / 2, y: rowY - Self.rowHeight / 2)
            rowY -= (Self.rowHeight + Self.rowSpacing)
        }

        restoreLabel.position = CGPoint(x: w / 2, y: max(66, rowY + 18))
        footerLabel.position = CGPoint(x: w / 2, y: max(26, rowY - 10))
    }

    // MARK: - Balance / price refresh

    private func refreshBalance() {
        balanceLabel.text = "\(EmpireStore.shared.crystals)"
    }

    /// Kicks off a StoreKit product (re)load and, once it resolves, updates every card's button with
    /// the real localized price -- cards that still have no matching product (dev/sandbox without real
    /// App Store Connect IDs registered yet, see IAPManager's doc comment) simply keep showing "BUY"
    /// next to their crystalAmount, which is already always visible on the card.
    private func loadAndApplyPrices() {
        Task { @MainActor in
            await IAPManager.shared.loadProducts()
            var prices: [CrystalPackage: String] = [:]
            for package in CrystalPackage.allCases {
                if let price = IAPManager.shared.priceString(for: package) {
                    prices[package] = price
                }
            }
            self.applyPrices(prices)
        }
    }

    private func applyPrices(_ prices: [CrystalPackage: String]) {
        loadedPrices = prices
        for (package, row) in cardRows where pendingPurchase != package {
            row.buyLabel.text = prices[package] ?? Self.fallbackBuyText
        }
    }

    // MARK: - Purchase flow

    private func handleBuy(package: CrystalPackage) {
        guard pendingPurchase == nil else { return }
        AudioManager.shared.playSFX(.buttonTap)
        pendingPurchase = package
        setCardPending(package, pending: true)
        Task { @MainActor in
            let success = await IAPManager.shared.purchase(package)
            self.finishPurchase(package: package, success: success)
        }
    }

    private func finishPurchase(package: CrystalPackage, success: Bool) {
        pendingPurchase = nil
        setCardPending(package, pending: false)
        if success {
            AudioManager.shared.hapticNotification(.success)
            refreshBalance()
            flashCardSuccess(package)
        } else {
            AudioManager.shared.hapticImpact(.soft)
            shakeCardFailure(package)
        }
    }

    private func handleRestore() {
        AudioManager.shared.playSFX(.buttonTap)
        restoreLabel.text = "Restoring\u{2026}"
        Task { @MainActor in
            await IAPManager.shared.restorePurchases()
            self.finishRestore()
        }
    }

    private func finishRestore() {
        refreshBalance()
        restoreLabel.text = "Restore Purchases"
        AudioManager.shared.hapticImpact(.light)
    }

    // MARK: - Card feedback animations

    private func setCardPending(_ package: CrystalPackage, pending: Bool) {
        guard let row = cardRows[package] else { return }
        row.buyLabel.text = pending ? "\u{22EF}" : (loadedPrices[package] ?? Self.fallbackBuyText)
        row.container.alpha = pending ? 0.65 : 1.0
    }

    private func flashCardSuccess(_ package: CrystalPackage) {
        guard let row = cardRows[package] else { return }
        let flash = SKAction.sequence([
            SKAction.run { row.background.fillColor = Palette.successGreen.withAlphaComponent(0.35) },
            SKAction.wait(forDuration: 0.16),
            SKAction.run { row.background.fillColor = Palette.rowFill }
        ])
        let pop = SKAction.sequence([SKAction.scale(to: 1.04, duration: 0.09), SKAction.scale(to: 1.0, duration: 0.12)])
        row.container.run(SKAction.group([flash, pop]))
    }

    private func shakeCardFailure(_ package: CrystalPackage) {
        guard let row = cardRows[package] else { return }
        let shake = SKAction.sequence([
            SKAction.moveBy(x: -8, y: 0, duration: 0.05),
            SKAction.moveBy(x: 16, y: 0, duration: 0.06),
            SKAction.moveBy(x: -12, y: 0, duration: 0.06),
            SKAction.moveBy(x: 8, y: 0, duration: 0.05),
            SKAction.moveBy(x: -4, y: 0, duration: 0.04)
        ])
        row.container.run(shake)
        let strokeFlash = SKAction.sequence([
            SKAction.run { row.background.strokeColor = Palette.blood },
            SKAction.wait(forDuration: 0.3),
            SKAction.run { row.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.45) }
        ])
        row.background.run(strokeFlash)
    }

    // MARK: - Touch handling (identical routing pattern to MenuScene)

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

    /// Same reasoning as MenuScene.topInteractiveName: nodes(at:) is purely geometric, so gate
    /// candidates explicitly rather than relying on visibility. Buy taps are additionally gated by
    /// `pendingPurchase` so a purchase already in flight can't be double-triggered from any card.
    private func topInteractiveName(at location: CGPoint) -> String? {
        let hit = nodes(at: location)
        let matched = hit.filter { node in
            guard let name = node.name else { return false }
            if name == "coinShopClose" || name == "coinShopRestore" { return true }
            if name.hasPrefix("buyCrystals_") { return pendingPurchase == nil }
            return false
        }
        return matched.max(by: { $0.zPosition < $1.zPosition })?.name
    }

    private func setPressed(name: String, pressed: Bool) {
        let scale: CGFloat = pressed ? 0.95 : 1.0
        switch name {
        case "coinShopClose":
            closeButton.run(SKAction.scale(to: scale, duration: 0.08))
        case "coinShopRestore":
            restoreLabel.run(SKAction.scale(to: scale, duration: 0.08))
        default:
            if name.hasPrefix("buyCrystals_"), let package = CrystalPackage(rawValue: String(name.dropFirst("buyCrystals_".count))) {
                cardRows[package]?.container.run(SKAction.scale(to: scale, duration: 0.08))
            }
        }
    }

    private func handleTap(name: String) {
        switch name {
        case "coinShopClose":
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.light)
            view?.presentScene(CommandDeckScene.newScene(), transition: .crossFade(withDuration: 0.4))
        case "coinShopRestore":
            handleRestore()
        default:
            if name.hasPrefix("buyCrystals_"), let package = CrystalPackage(rawValue: String(name.dropFirst("buyCrystals_".count))) {
                handleBuy(package: package)
            }
        }
    }

    // MARK: - Procedural textures & helpers

    /// Faceted-gem icon, code-drawn (no image assets) and tinted per call site. Diameter drives the
    /// visible package "size" tier in buildCard(_:index:).
    private static func crystalTexture(diameter: CGFloat, tint: SKColor) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let w = size.width, h = size.height
            let top = CGPoint(x: w * 0.5, y: h * 0.04)
            let bottom = CGPoint(x: w * 0.5, y: h * 0.97)
            let leftMid = CGPoint(x: w * 0.04, y: h * 0.36)
            let rightMid = CGPoint(x: w * 0.96, y: h * 0.36)
            let leftLow = CGPoint(x: w * 0.2, y: h * 0.5)
            let rightLow = CGPoint(x: w * 0.8, y: h * 0.5)
            let center = CGPoint(x: w * 0.5, y: h * 0.5)

            let path = CGMutablePath()
            path.move(to: top)
            path.addLine(to: rightMid)
            path.addLine(to: rightLow)
            path.addLine(to: bottom)
            path.addLine(to: leftLow)
            path.addLine(to: leftMid)
            path.closeSubpath()

            let colors = [tint.withAlphaComponent(1.0).cgColor, tint.withAlphaComponent(0.5).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.drawLinearGradient(gradient, start: CGPoint(x: w * 0.2, y: 0), end: CGPoint(x: w * 0.8, y: h), options: [])
            ctx.restoreGState()

            ctx.setStrokeColor(SKColor.white.withAlphaComponent(0.5).cgColor)
            ctx.setLineWidth(max(1, diameter * 0.02))
            for facetStart in [top, leftMid, rightMid] {
                ctx.move(to: facetStart)
                ctx.addLine(to: center)
                ctx.strokePath()
            }

            ctx.setStrokeColor(tint.withAlphaComponent(0.9).cgColor)
            ctx.setLineWidth(max(1.2, diameter * 0.025))
            ctx.addPath(path)
            ctx.strokePath()
        }
    }

    private static func gradientTexture(top: SKColor, bottom: SKColor, size: CGSize) -> SKTexture {
        ProceduralTextures.render(size: size, opaque: true) { ctx, size in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
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
        // Intentionally NOT parented under `shape` — callers add both as siblings to the same parent
        // and keep `label.position == shape.position` in sync, same convention as MenuScene.makeButton.
        return (shape, label)
    }

    private static func letterSpaced(_ text: String) -> String {
        text.map(String.init).joined(separator: "\u{200A}")
    }
}
