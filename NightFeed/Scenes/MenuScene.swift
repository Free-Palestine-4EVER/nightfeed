import SpriteKit

/// Main menu — title moment, best-run stats, PLAY entry point and the permanent meta-upgrade shop.
/// Pure SpriteKit UI: every visual is code-drawn (SKShapeNode/SKLabelNode/SKEmitterNode with
/// ProceduralTextures-rendered textures), no image assets. Manual name-based touch handling —
/// this scene has no physics world and no need for one.
final class MenuScene: SKScene {

    // MARK: - Palette (deep violet-black nights, ember-orange embers, moonlight-white, blood-red danger)

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
    }

    static func newScene() -> MenuScene {
        let scene = MenuScene(size: CGSize(width: 393, height: 852))
        scene.scaleMode = .resizeFill
        return scene
    }

    // MARK: - Layers

    private let backgroundLayer = SKNode()
    private let starLayer = SKNode()
    private let contentLayer = SKNode()
    private let shopLayer = SKNode()

    // MARK: - Content refs (rebuilt-in-place on resize via layout())

    private var moonNode: SKSpriteNode!
    private var moonGlow: SKSpriteNode!
    private var emberEmitter: SKEmitterNode!
    private var titleLabel: SKLabelNode!
    private var titleShadow: SKLabelNode!
    private var subtitleLabel: SKLabelNode!
    private var bestTimeLabel: SKLabelNode!
    private var goldLabel: SKLabelNode!
    private var playButton: SKShapeNode!
    private var playLabel: SKLabelNode!
    private var shopButton: SKShapeNode!
    private var shopLabel: SKLabelNode!
    private var goldRushCard: SKShapeNode!
    private var goldRushTitleLabel: SKLabelNode!
    private var goldRushSubLabel: SKLabelNode!
    private var autoReviveCard: SKShapeNode!
    private var autoReviveTitleLabel: SKLabelNode!
    private var speedBoostCard: SKShapeNode!
    private var speedBoostTitleLabel: SKLabelNode!
    private var footerLabel: SKLabelNode!

    private var shopOverlay: SKShapeNode!
    private var shopPanel: SKShapeNode!
    private var shopTitleLabel: SKLabelNode!
    private var shopCloseButton: SKShapeNode!
    private var shopCloseLabel: SKLabelNode!
    private var shopGoldLabel: SKLabelNode!

    private var starFractions: [(CGPoint, CGFloat)] = []
    private var starNodes: [SKShapeNode] = []
    private var shopRows: [MetaUpgradeKind: ShopRowNodes] = [:]

    // Shop category tabs — swap which subset of the 20 shopRows is visible/interactive inside
    // the same fixed panel bounds, rather than scrolling. See buildShopTabs()/refreshShopTabVisibility().
    private var shopTabButtons: [SKShapeNode] = []
    private var shopTabIconLabels: [SKLabelNode] = []
    private var shopTabLabels: [SKLabelNode] = []
    private var selectedShopTab = 0

    // Familiar (pet) selector chips — only meaningful inside the Familiars tab.
    private var petSelectorHintLabel: SKLabelNode!
    private var petChipNodes: [PetKind: PetChipNodes] = [:]

    // Skin picker chips (single-select radio) — only meaningful inside the Skins tab.
    private var skinSelectorHintLabel: SKLabelNode!
    private var skinChipNodes: [PlayerSkinKind: SkinChipNodes] = [:]

    // Starting-potion picker chips (multi-select up to startingPotionSlots) — Potions tab only.
    private var potionSelectorHintLabel: SKLabelNode!
    private var potionChipNodes: [PotionKind: PotionChipNodes] = [:]

    // Soft violet glow behind the shop title, purely decorative.
    private var shopTitleGlow: SKSpriteNode!

    // Low-prominence destructive control at the very bottom of the shop panel + its confirm modal.
    private var resetLink: SKLabelNode!
    private var resetConfirmModal: SKNode!
    private var resetConfirmConfirmButton: SKShapeNode!
    private var resetConfirmCancelButton: SKShapeNode!

    private var isShopOpen = false
    private var isResetConfirmOpen = false
    private var pressedNodeName: String?
    private var hasBuiltOnce = false

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.bgBottom

        let isFirstPresentation = !hasBuiltOnce
        if !hasBuiltOnce {
            addChild(backgroundLayer)
            addChild(starLayer)
            addChild(contentLayer)
            addChild(shopLayer)
            backgroundLayer.zPosition = ZPosition.menuUI - 5
            starLayer.zPosition = ZPosition.menuUI - 3
            contentLayer.zPosition = ZPosition.menuUI
            shopLayer.zPosition = ZPosition.menuUI + 50
            shopLayer.isHidden = true

            buildBackground()
            buildStars()
            buildTitle()
            buildStatsRow()
            buildButtons()
            buildGoldRushCard()
            buildFooter()
            buildShopPanel()
            hasBuiltOnce = true
        }

        refreshStats()
        layout(size: size)

        // Every presentation of MenuScene is a freshly-created instance (see MenuScene.newScene()),
        // so `isFirstPresentation` is effectively "did this scene instance just appear" — the
        // staggered reveal replays every time you land back on the menu (after a run, after quitting),
        // which is exactly when a moment of "arrival" polish reads best.
        if isFirstPresentation {
            playEntranceAnimation()
        }

        AudioManager.shared.startMusic()
        AdsManager.shared.configure()
        // Passed explicitly (rather than relying on a default parameter value) so this compiles
        // whether or not AdsManager's `completion` parameter ends up with a default — fire-and-forget.
        AdsManager.shared.requestTrackingIfNeeded(completion: nil)
    }

    /// One-shot staggered reveal: title → subtitle → stats chips → PLAY → SHOP → Gold Rush card →
    /// footer, each popping in from just below its final resting spot with a short overshoot-settle.
    /// Channels that a node's own continuous ambient action already drives (title's scale-breathe,
    /// PLAY's alpha glow-pulse) are skipped here so the two never fight over the same property —
    /// see JuiceEffects.popIn's doc comment.
    private func playEntranceAnimation() {
        JuiceEffects.popIn(titleShadow, delay: 0.0, distance: 10)
        JuiceEffects.popIn(titleLabel, delay: 0.0, distance: 10, scale: false)
        JuiceEffects.popIn(subtitleLabel, delay: 0.08, distance: 8)

        if let bestIcon = contentLayer.childNode(withName: "bestIcon") {
            JuiceEffects.popIn(bestIcon, delay: 0.16, distance: 6) {
                JuiceEffects.idleBreathe(bestIcon, amplitude: 0.07, period: 1.7, phase: 0)
            }
        }
        JuiceEffects.popIn(bestTimeLabel, delay: 0.16, distance: 6)
        if let coinIcon = contentLayer.childNode(withName: "coinIcon") {
            JuiceEffects.popIn(coinIcon, delay: 0.2, distance: 6) {
                JuiceEffects.idleBreathe(coinIcon, amplitude: 0.09, period: 1.5, phase: 0.4)
            }
        }
        JuiceEffects.popIn(goldLabel, delay: 0.2, distance: 6)

        JuiceEffects.popIn(playButton, delay: 0.26, fade: false)
        JuiceEffects.popIn(playLabel, delay: 0.26, fade: false)
        JuiceEffects.popIn(shopButton, delay: 0.32)
        JuiceEffects.popIn(shopLabel, delay: 0.32)
        JuiceEffects.popIn(goldRushCard, delay: 0.38)
        JuiceEffects.popIn(footerLabel, delay: 0.46, distance: 6)
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

        let glow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.violetDim, radius: 260))
        glow.name = "moonGlow"
        glow.alpha = 0.5
        glow.zPosition = 1
        glow.blendMode = .add
        backgroundLayer.addChild(glow)
        moonGlow = glow

        let moon = SKSpriteNode(texture: Self.crescentTexture(diameter: 96, color: Palette.moonlight))
        moon.name = "moon"
        moon.zPosition = 2
        backgroundLayer.addChild(moon)
        moonNode = moon

        let breathe = SKAction.sequence([
            SKAction.scale(to: 1.06, duration: 3.2),
            SKAction.scale(to: 1.0, duration: 3.2)
        ])
        breathe.timingMode = .easeInEaseOut
        moon.run(SKAction.repeatForever(breathe))
        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.7, duration: 2.6),
            SKAction.fadeAlpha(to: 0.4, duration: 2.6)
        ])
        glow.run(SKAction.repeatForever(glowPulse))

        let emitter = SKEmitterNode()
        emitter.particleTexture = ProceduralTextures.radialGlow(color: Palette.ember, radius: 8)
        emitter.particleBirthRate = 6
        emitter.particleLifetime = 7
        emitter.particleLifetimeRange = 3
        emitter.particleSpeed = 22
        emitter.particleSpeedRange = 14
        emitter.emissionAngle = .pi / 2
        emitter.emissionAngleRange = .pi / 10
        emitter.yAcceleration = 6
        emitter.particleAlpha = 0.0
        emitter.particleAlphaSequence = Self.emberAlphaSequence
        emitter.particleScale = 0.35
        emitter.particleScaleRange = 0.25
        emitter.particleScaleSpeed = -0.02
        emitter.particleColorBlendFactor = 1
        emitter.particleColor = Palette.ember
        emitter.particleBlendMode = .add
        emitter.zPosition = 3
        backgroundLayer.addChild(emitter)
        emberEmitter = emitter
    }

    private static let emberAlphaSequence: SKKeyframeSequence = {
        let seq = SKKeyframeSequence(keyframeValues: [0.0, 0.85, 0.6, 0.0], times: [0.0, 0.15, 0.7, 1.0])
        return seq
    }()

    private func buildStars() {
        var rng = SystemRandomNumberGenerator()
        starFractions.removeAll()
        starNodes.removeAll()
        for _ in 0..<46 {
            let fx = CGFloat.random(in: 0...1, using: &rng)
            let fy = CGFloat.random(in: 0.45...1, using: &rng)
            let r = CGFloat.random(in: 0.6...1.6, using: &rng)
            starFractions.append((CGPoint(x: fx, y: fy), r))
            let dot = SKShapeNode(circleOfRadius: r)
            dot.fillColor = Palette.moonlight
            dot.strokeColor = .clear
            dot.alpha = CGFloat.random(in: 0.15...0.6, using: &rng)
            starLayer.addChild(dot)
            starNodes.append(dot)
            let twinkle = SKAction.sequence([
                SKAction.fadeAlpha(to: dot.alpha * 0.3, duration: Double.random(in: 1.4...3.2)),
                SKAction.fadeAlpha(to: dot.alpha, duration: Double.random(in: 1.4...3.2))
            ])
            dot.run(SKAction.repeatForever(twinkle))
        }
    }

    // MARK: - Title

    private func buildTitle() {
        let shadow = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        shadow.text = "NIGHTFEED"
        shadow.fontSize = 58
        shadow.fontColor = Palette.blood.withAlphaComponent(0.55)
        shadow.horizontalAlignmentMode = .center
        shadow.verticalAlignmentMode = .center
        shadow.zPosition = 0
        contentLayer.addChild(shadow)
        titleShadow = shadow

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "NIGHTFEED"
        title.fontSize = 58
        title.fontColor = Palette.moonlight
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.zPosition = 1
        contentLayer.addChild(title)
        titleLabel = title

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.03, duration: 1.8),
            SKAction.scale(to: 1.0, duration: 1.8)
        ])
        pulse.timingMode = .easeInEaseOut
        title.run(SKAction.repeatForever(pulse))

        let sub = SKLabelNode(fontNamed: "AvenirNext-Medium")
        sub.text = Self.letterSpaced("A NOCTURNAL SURVIVAL RITE")
        sub.fontSize = 13
        sub.fontColor = Palette.emberBright
        sub.horizontalAlignmentMode = .center
        sub.verticalAlignmentMode = .center
        sub.zPosition = 1
        contentLayer.addChild(sub)
        subtitleLabel = sub
    }

    // MARK: - Stats row

    private func buildStatsRow() {
        let bestIcon = SKSpriteNode(texture: Self.crescentTexture(diameter: 20, color: Palette.moonlight))
        bestIcon.name = "bestIcon"
        contentLayer.addChild(bestIcon)

        let best = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        best.fontSize = 17
        best.fontColor = Palette.moonlight
        best.horizontalAlignmentMode = .left
        best.verticalAlignmentMode = .center
        best.name = "bestTimeLabel"
        contentLayer.addChild(best)
        bestTimeLabel = best

        let coinIcon = SKSpriteNode(texture: Self.coinTexture(diameter: 20))
        coinIcon.name = "coinIcon"
        contentLayer.addChild(coinIcon)

        let gold = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        gold.fontSize = 17
        gold.fontColor = Palette.emberBright
        gold.horizontalAlignmentMode = .left
        gold.verticalAlignmentMode = .center
        gold.name = "goldLabel"
        contentLayer.addChild(gold)
        goldLabel = gold
    }

    // MARK: - Buttons

    private func buildButtons() {
        let (play, playText) = Self.makeButton(text: "PLAY", width: 220, height: 68,
                                                fill: Palette.ember, stroke: Palette.emberBright,
                                                textColor: SKColor(red: 0.12, green: 0.03, blue: 0.02, alpha: 1),
                                                fontSize: 26, fontName: "AvenirNext-Heavy")
        play.name = "play"
        playText.name = "play"
        contentLayer.addChild(play)
        contentLayer.addChild(playText)
        playButton = play
        playLabel = playText

        let glowPulse = SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 1.1),
            SKAction.fadeAlpha(to: 0.9, duration: 1.1)
        ])
        play.run(SKAction.repeatForever(SKAction.sequence([SKAction.wait(forDuration: 0.3), glowPulse])))

        let (shop, shopText) = Self.makeButton(text: "SHOP", width: 220, height: 52,
                                                fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                textColor: Palette.moonlight,
                                                fontSize: 19, fontName: "AvenirNext-DemiBold")
        shop.name = "shopToggle"
        shopText.name = "shopToggle"
        contentLayer.addChild(shop)
        contentLayer.addChild(shopText)
        shopButton = shop
        shopLabel = shopText
    }

    // MARK: - Gold Rush card

    private func buildGoldRushCard() {
        let card = SKShapeNode(rectOf: CGSize(width: 280, height: 54), cornerRadius: 14)
        card.name = "goldRushAction"
        card.fillColor = Palette.rowFill
        card.strokeColor = Palette.ember.withAlphaComponent(0.7)
        card.lineWidth = 1.5
        contentLayer.addChild(card)
        goldRushCard = card

        let title = SKLabelNode(fontNamed: "AvenirNext-Bold")
        title.name = "goldRushAction"
        title.fontSize = 12.5
        title.fontColor = Palette.emberBright
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 9)
        card.addChild(title)
        goldRushTitleLabel = title

        let sub = SKLabelNode(fontNamed: "AvenirNext-Medium")
        sub.name = "goldRushAction"
        sub.fontSize = 11.5
        sub.fontColor = Palette.moonlightDim
        sub.verticalAlignmentMode = .center
        sub.position = CGPoint(x: 0, y: -10)
        card.addChild(sub)
        goldRushSubLabel = sub

        card.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.run { [weak self] in self?.refreshGoldRushCard() }
        ])))
    }

    private func refreshGoldRushCard() {
        guard let title = goldRushTitleLabel, let sub = goldRushSubLabel, let card = goldRushCard else { return }
        let store = MetaProgressionStore.shared
        switch store.goldRushActiveTier {
        case 0:
            title.text = "🔥 GOLD RUSH — 3 ads for 2x gold"
            sub.text = "\(store.goldRushAdsWatched)/3 ads watched · tap to watch"
            card.strokeColor = Palette.ember.withAlphaComponent(0.7)
        case 1:
            title.text = "🔥 2x GOLD — \(Self.formatMinutes(store.goldRushTimeRemaining)) left"
            sub.text = "Tap to watch 1 more ad for 4x!"
            card.strokeColor = Palette.emberBright
        default:
            title.text = "🔥🔥 4x GOLD — \(Self.formatMinutes(store.goldRushTimeRemaining)) left"
            sub.text = "Tap to refresh the timer"
            card.strokeColor = Palette.emberBright
        }
    }

    private func handleGoldRushTap() {
        AudioManager.shared.playSFX(.buttonTap)
        AdsManager.shared.showRewarded { [weak self] earned in
            guard let self else { return }
            if earned {
                MetaProgressionStore.shared.recordGoldRushAdWatched()
                AudioManager.shared.hapticNotification(.success)
                self.refreshGoldRushCard()
            } else {
                AudioManager.shared.hapticImpact(.soft)
            }
        }
    }

    // MARK: - Auto-Revive card (compact single-line strip, lives in the shop panel header — the
    // main-menu row budget below PLAY/SHOP/Gold Rush is already tight down to small-screen devices)

    private static let autoReviveCardHeight: CGFloat = 34

    private func buildAutoReviveCard() {
        let card = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.autoReviveCardHeight), cornerRadius: 10)
        card.name = "autoReviveAction"
        card.fillColor = Palette.rowFill
        card.strokeColor = Palette.moonlight.withAlphaComponent(0.5)
        card.lineWidth = 1.5
        card.zPosition = 2
        shopLayer.addChild(card)
        autoReviveCard = card

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.name = "autoReviveAction"
        title.fontSize = 12.5
        title.fontColor = Palette.moonlight
        title.verticalAlignmentMode = .center
        title.zPosition = 3
        card.addChild(title)
        autoReviveTitleLabel = title

        card.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.run { [weak self] in self?.refreshAutoReviveCard() }
        ])))
    }

    private func refreshAutoReviveCard() {
        guard let title = autoReviveTitleLabel, let card = autoReviveCard else { return }
        let store = MetaProgressionStore.shared
        if store.autoReviveAvailable {
            title.text = "🌙 Auto-Revive banked — next death"
            card.strokeColor = Palette.moonlight
        } else if store.autoReviveCooldownRemaining > 0 {
            title.text = "🌙 Auto-Revive cooldown: \(Self.formatMinutes(store.autoReviveCooldownRemaining))"
            card.strokeColor = Palette.moonlight.withAlphaComponent(0.3)
        } else {
            title.text = "🌙 Watch 1 ad: bank a free revive"
            card.strokeColor = Palette.moonlight.withAlphaComponent(0.5)
        }
    }

    private func handleAutoReviveTap() {
        guard MetaProgressionStore.shared.canWatchAdForAutoRevive else {
            AudioManager.shared.hapticImpact(.soft)
            return
        }
        AudioManager.shared.playSFX(.buttonTap)
        AdsManager.shared.showRewarded { [weak self] earned in
            guard let self else { return }
            if earned {
                MetaProgressionStore.shared.recordAutoReviveAdWatched()
                AudioManager.shared.hapticNotification(.success)
                self.refreshAutoReviveCard()
            } else {
                AudioManager.shared.hapticImpact(.soft)
            }
        }
    }

    // MARK: - Speed Boost card (compact single-line strip, same pattern as Auto-Revive)

    private func buildSpeedBoostCard() {
        let card = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.autoReviveCardHeight), cornerRadius: 10)
        card.name = "speedBoostAction"
        card.fillColor = Palette.rowFill
        card.strokeColor = SKColor(red: 0.4, green: 0.85, blue: 1.0, alpha: 0.5)
        card.lineWidth = 1.5
        card.zPosition = 2
        shopLayer.addChild(card)
        speedBoostCard = card

        let title = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        title.name = "speedBoostAction"
        title.fontSize = 12.5
        title.fontColor = SKColor(red: 0.55, green: 0.9, blue: 1.0, alpha: 1)
        title.verticalAlignmentMode = .center
        title.zPosition = 3
        card.addChild(title)
        speedBoostTitleLabel = title

        card.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.wait(forDuration: 1.0),
            SKAction.run { [weak self] in self?.refreshSpeedBoostCard() }
        ])))
    }

    private func refreshSpeedBoostCard() {
        guard let title = speedBoostTitleLabel, let card = speedBoostCard else { return }
        let store = MetaProgressionStore.shared
        if store.isSpeedBoostActive {
            title.text = "⚡ 2x Speed — \(Self.formatMinutes(store.speedBoostTimeRemaining)) left"
            card.strokeColor = SKColor(red: 0.55, green: 0.9, blue: 1.0, alpha: 1)
        } else {
            title.text = "⚡ Watch 1 ad: 2x speed for 15m"
            card.strokeColor = SKColor(red: 0.4, green: 0.85, blue: 1.0, alpha: 0.5)
        }
    }

    private func handleSpeedBoostTap() {
        AudioManager.shared.playSFX(.buttonTap)
        AdsManager.shared.showRewarded { [weak self] earned in
            guard let self else { return }
            if earned {
                MetaProgressionStore.shared.recordSpeedBoostAdWatched()
                AudioManager.shared.hapticNotification(.success)
                self.refreshSpeedBoostCard()
            } else {
                AudioManager.shared.hapticImpact(.soft)
            }
        }
    }

    private static func formatMinutes(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(0, Int(seconds / 60))
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func buildFooter() {
        let footer = SKLabelNode(fontNamed: "AvenirNext-Medium")
        footer.text = Self.letterSpaced("SURVIVE THE NIGHT")
        footer.fontSize = 11
        footer.fontColor = Palette.moonlightDim
        footer.horizontalAlignmentMode = .center
        footer.verticalAlignmentMode = .center
        contentLayer.addChild(footer)
        footerLabel = footer
    }

    // MARK: - Shop panel

    private func buildShopPanel() {
        let overlay = SKShapeNode(rectOf: CGSize(width: 4000, height: 4000))
        overlay.fillColor = SKColor.black.withAlphaComponent(0.62)
        overlay.strokeColor = .clear
        overlay.name = "shopOverlay"
        overlay.alpha = 0
        overlay.zPosition = 0
        shopLayer.addChild(overlay)
        shopOverlay = overlay

        let panel = SKShapeNode()
        panel.fillColor = Palette.panelFill
        panel.strokeColor = Palette.panelStroke
        panel.lineWidth = 1.5
        panel.zPosition = 1
        panel.name = "shopPanelBG"
        shopLayer.addChild(panel)
        shopPanel = panel

        // Purely decorative soft glow that sits behind the title, giving the header a bit of
        // "shrine altar" presence — no name, so it's invisible to hit-testing.
        let titleGlow = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: Palette.violet, radius: 100))
        titleGlow.alpha = 0.3
        titleGlow.zPosition = 1.5
        titleGlow.blendMode = .add
        shopLayer.addChild(titleGlow)
        shopTitleGlow = titleGlow

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "THE SHRINE"
        title.fontSize = 24
        title.fontColor = Palette.moonlight
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.zPosition = 2
        shopLayer.addChild(title)
        shopTitleLabel = title

        let (close, closeText) = Self.makeButton(text: "X", width: 40, height: 40,
                                                  fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                  textColor: Palette.moonlight, fontSize: 18, fontName: "AvenirNext-DemiBold")
        close.name = "shopClose"
        closeText.name = "shopClose"
        close.zPosition = 2
        closeText.zPosition = 3
        shopLayer.addChild(close)
        shopLayer.addChild(closeText)
        shopCloseButton = close
        shopCloseLabel = closeText

        let goldRow = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        goldRow.fontSize = 15
        goldRow.fontColor = Palette.emberBright
        goldRow.horizontalAlignmentMode = .center
        goldRow.verticalAlignmentMode = .center
        goldRow.zPosition = 2
        shopLayer.addChild(goldRow)
        shopGoldLabel = goldRow

        buildAutoReviveCard()
        buildSpeedBoostCard()

        buildShopTabs()
        buildPetChips()
        buildSkinChips()
        buildPotionChips()
        buildResetProgressLink()
        buildResetConfirmModal()

        for (index, kind) in MetaUpgradeKind.allCases.enumerated() {
            shopRows[kind] = buildShopRow(for: kind, index: index)
        }

        refreshShopTabVisibility()
    }

    private struct ShopRowNodes {
        let container: SKNode
        let background: SKShapeNode
        let nameLabel: SKLabelNode
        let tierLabel: SKLabelNode
        let flavorLabel: SKLabelNode
        let buyButton: SKShapeNode
        let buyLabel: SKLabelNode
        let maxedLabel: SKLabelNode
    }

    /// Cheap-to-premium visual tiers, derived from each kind's base (tier-1) gold cost. Higher rarity
    /// gets a bolder stroke + a touch of glow so the pricier shrine offerings (skins, familiars, the
    /// second pet slot) read as more special at a glance, not just another identical row.
    private enum ShopRarity {
        case common, uncommon, rare, legendary

        var accentColor: SKColor {
            switch self {
            case .common: return Palette.violet
            case .uncommon: return SKColor(red: 0.4, green: 0.75, blue: 0.95, alpha: 1)
            case .rare: return Palette.ember
            case .legendary: return SKColor(red: 1.0, green: 0.86, blue: 0.4, alpha: 1)
            }
        }
        var strokeAlpha: CGFloat {
            switch self {
            case .common: return 0.35
            case .uncommon: return 0.55
            case .rare: return 0.8
            case .legendary: return 0.95
            }
        }
        var lineWidth: CGFloat {
            switch self {
            case .common: return 1
            case .uncommon: return 1.4
            case .rare: return 1.8
            case .legendary: return 2.2
            }
        }
        var glowWidth: CGFloat {
            switch self {
            case .common, .uncommon: return 0
            case .rare: return 2
            case .legendary: return 4
            }
        }
    }

    private static func rarity(for kind: MetaUpgradeKind) -> ShopRarity {
        switch kind.cost(forTier: 1) {
        case ..<100: return .common
        case 100..<200: return .uncommon
        case 200..<350: return .rare
        default: return .legendary
        }
    }

    /// A soft top-to-bottom sheen shared by every row card (cheap: rendered once, reused everywhere)
    /// — sits just above the card fill and just below every label, giving the flat fill a hint of
    /// glassy depth without a new texture per row.
    private static let rowSheenTexture: SKTexture =
        alphaGradientTexture(topAlpha: 0.07, bottomAlpha: 0.0, size: CGSize(width: 4, height: 128))

    private func buildShopRow(for kind: MetaUpgradeKind, index: Int) -> ShopRowNodes {
        let container = SKNode()
        container.zPosition = 2
        shopLayer.addChild(container)

        let tier = Self.rarity(for: kind)

        // Card fill + sheen + rarity accent bar are all pushed to negative local zPositions so they
        // sit behind every label/button below (which keep their default zPosition 0) without having
        // to touch every existing label's zPosition.
        let bg = SKShapeNode(rectOf: CGSize(width: Self.rowWidth, height: Self.rowHeight), cornerRadius: 14)
        bg.fillColor = Palette.rowFill
        bg.strokeColor = tier.accentColor.withAlphaComponent(tier.strokeAlpha)
        bg.lineWidth = tier.lineWidth
        bg.glowWidth = tier.glowWidth
        bg.zPosition = -1
        container.addChild(bg)

        let sheen = SKSpriteNode(texture: Self.rowSheenTexture)
        sheen.size = CGSize(width: Self.rowWidth - 24, height: Self.rowHeight - 18)
        sheen.zPosition = -0.5
        container.addChild(sheen)

        let accentBar = SKShapeNode(rectOf: CGSize(width: 4, height: Self.rowHeight - 18), cornerRadius: 2)
        accentBar.fillColor = tier.accentColor
        accentBar.strokeColor = .clear
        accentBar.alpha = 0.85
        accentBar.position = CGPoint(x: -Self.rowWidth / 2 + 9, y: 0)
        accentBar.zPosition = -0.3
        container.addChild(accentBar)

        let name = SKLabelNode(fontNamed: "AvenirNext-Bold")
        name.text = kind.displayName
        name.fontSize = 16
        name.fontColor = Palette.moonlight
        name.horizontalAlignmentMode = .left
        name.verticalAlignmentMode = .center
        name.position = CGPoint(x: -Self.rowWidth / 2 + 18, y: Self.rowHeight / 2 - 16)
        container.addChild(name)

        let tierPill = SKShapeNode(rectOf: CGSize(width: 58, height: 18), cornerRadius: 9)
        tierPill.fillColor = tier.accentColor.withAlphaComponent(0.14)
        tierPill.strokeColor = tier.accentColor.withAlphaComponent(0.45)
        tierPill.lineWidth = 1
        tierPill.position = CGPoint(x: Self.rowWidth / 2 - 14 - 29, y: Self.rowHeight / 2 - 16)
        tierPill.zPosition = -0.2
        container.addChild(tierPill)

        let tierLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        tierLabel.fontSize = 11.5
        tierLabel.fontColor = Palette.emberBright
        tierLabel.horizontalAlignmentMode = .right
        tierLabel.verticalAlignmentMode = .center
        tierLabel.position = CGPoint(x: Self.rowWidth / 2 - 14, y: Self.rowHeight / 2 - 16)
        container.addChild(tierLabel)

        let flavor = SKLabelNode(fontNamed: "AvenirNext-Regular")
        flavor.text = kind.flavorText
        flavor.fontSize = 11.5
        flavor.fontColor = Palette.moonlightDim
        flavor.horizontalAlignmentMode = .left
        flavor.verticalAlignmentMode = .top
        flavor.numberOfLines = 2
        flavor.preferredMaxLayoutWidth = Self.rowWidth - 104
        flavor.lineBreakMode = .byWordWrapping
        flavor.position = CGPoint(x: -Self.rowWidth / 2 + 18, y: Self.rowHeight / 2 - 35)
        container.addChild(flavor)

        let (buy, buyText) = Self.makeButton(text: "BUY", width: 74, height: 32,
                                              fill: Palette.ember, stroke: Palette.emberBright,
                                              textColor: SKColor(red: 0.12, green: 0.03, blue: 0.02, alpha: 1),
                                              fontSize: 13, fontName: "AvenirNext-Heavy")
        buy.position = CGPoint(x: Self.rowWidth / 2 - 44, y: -Self.rowHeight / 2 + 20)
        buy.name = "buy_\(kind.rawValue)"
        buyText.name = "buy_\(kind.rawValue)"
        buyText.position = buy.position
        container.addChild(buy)
        container.addChild(buyText)

        let maxed = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        maxed.text = "MAXED"
        maxed.fontSize = 13
        maxed.fontColor = Palette.violet
        maxed.horizontalAlignmentMode = .right
        maxed.verticalAlignmentMode = .center
        maxed.position = CGPoint(x: Self.rowWidth / 2 - 14, y: -Self.rowHeight / 2 + 20)
        maxed.isHidden = true
        container.addChild(maxed)

        return ShopRowNodes(container: container, background: bg, nameLabel: name, tierLabel: tierLabel,
                             flavorLabel: flavor, buyButton: buy, buyLabel: buyText, maxedLabel: maxed)
    }

    // MARK: - Shop category tabs

    private static let statsCategory: [MetaUpgradeKind] = [
        .startingHealth, .startingSpeed, .startingDamage, .startingMagnet,
        .goldGain, .startingArmor, .startingCrit, .headStart
    ]
    private static let familiarsCategory: [MetaUpgradeKind] = [
        .petCompanion, .petBoneHound, .petStormSprite, .petGraveMoth, .secondPetSlot
    ]
    private static let powersCategory: [MetaUpgradeKind] = [
        .lifesteal, .dodgeChance, .xpGainBonus, .potionLuck, .reviveCharge, .weaponMastery, .extraChoices
    ]
    private static let skinsCategory: [MetaUpgradeKind] = [
        .skinCrimsonFang, .skinMoonlitVeil, .skinVoidReaper, .skinEmberSovereign
    ]
    private static let potionsCategory: [MetaUpgradeKind] = [.potionMastery]
    private static let shopCategories: [[MetaUpgradeKind]] = [
        statsCategory, familiarsCategory, powersCategory, skinsCategory, potionsCategory
    ]
    private static let shopTabTitles = ["STATS", "PETS", "POWERS", "SKINS", "POTIONS"]
    private static let shopTabIcons = ["⚔️", "🐾", "✨", "🧥", "🧪"]
    private static let familiarsTabIndex = 1
    private static let skinsTabIndex = 3
    private static let potionsTabIndex = 4
    private static let maxCategoryRowCount = max(statsCategory.count, familiarsCategory.count, powersCategory.count,
                                                  skinsCategory.count, potionsCategory.count)
    /// Total vertical space consumed above the item list: title + close + gold label + tab row.
    private static let shopHeaderTotalHeight: CGFloat = 200

    private static func category(for kind: MetaUpgradeKind) -> Int {
        if statsCategory.contains(kind) { return 0 }
        if familiarsCategory.contains(kind) { return familiarsTabIndex }
        if skinsCategory.contains(kind) { return skinsTabIndex }
        if potionsCategory.contains(kind) { return potionsTabIndex }
        return 2
    }

    /// Two-line tab buttons (icon on top, short label below) rather than a single icon+text line —
    /// with 5 tabs squeezed into the same panel width the old 3-tab single-row style used, a single
    /// line would force either a tiny illegible font or clipped text.
    private static let shopTabWidth: CGFloat = 63
    private static let shopTabHeight: CGFloat = 40

    private func buildShopTabs() {
        for (index, title) in Self.shopTabTitles.enumerated() {
            let (btn, label) = Self.makeButton(text: title, width: Self.shopTabWidth, height: Self.shopTabHeight,
                                                fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                textColor: Palette.moonlightDim, fontSize: 8.5, fontName: "AvenirNext-DemiBold")
            btn.name = "shopTab_\(index)"
            label.name = "shopTab_\(index)"
            label.position = CGPoint(x: 0, y: -9)
            btn.zPosition = 2
            label.zPosition = 3
            shopLayer.addChild(btn)
            shopLayer.addChild(label)
            shopTabButtons.append(btn)
            shopTabLabels.append(label)

            let icon = SKLabelNode(text: Self.shopTabIcons[index])
            icon.name = "shopTab_\(index)"
            icon.fontSize = 15
            icon.verticalAlignmentMode = .center
            icon.position = CGPoint(x: 0, y: 8)
            icon.zPosition = 3
            shopLayer.addChild(icon)
            shopTabIconLabels.append(icon)
        }
    }

    // MARK: - Familiar (pet) selector

    private struct PetChipNodes {
        let container: SKNode
        let background: SKShapeNode
        let label: SKLabelNode
        let statusLabel: SKLabelNode
    }

    private static let petChipWidth: CGFloat = 72
    private static let petChipHeight: CGFloat = 56

    private func buildPetChips() {
        let hint = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        hint.text = Self.letterSpaced("YOUR FAMILIARS")
        hint.fontSize = 11
        hint.fontColor = Palette.moonlightDim
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.zPosition = 2
        shopLayer.addChild(hint)
        petSelectorHintLabel = hint

        for kind in PetKind.allCases {
            let container = SKNode()
            container.zPosition = 2
            shopLayer.addChild(container)

            let bg = SKShapeNode(rectOf: CGSize(width: Self.petChipWidth, height: Self.petChipHeight), cornerRadius: 10)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            bg.lineWidth = 1.5
            bg.name = "petChip_\(kind.rawValue)"
            container.addChild(bg)

            let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            label.text = kind.displayName
            label.fontSize = 10
            label.fontColor = Palette.moonlight
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.numberOfLines = 2
            label.preferredMaxLayoutWidth = Self.petChipWidth - 10
            label.lineBreakMode = .byWordWrapping
            label.position = CGPoint(x: 0, y: 6)
            label.name = "petChip_\(kind.rawValue)"
            container.addChild(label)

            let status = SKLabelNode(fontNamed: "AvenirNext-Bold")
            status.fontSize = 8.5
            status.fontColor = Palette.moonlightDim
            status.horizontalAlignmentMode = .center
            status.verticalAlignmentMode = .center
            status.position = CGPoint(x: 0, y: -Self.petChipHeight / 2 + 10)
            status.name = "petChip_\(kind.rawValue)"
            container.addChild(status)

            petChipNodes[kind] = PetChipNodes(container: container, background: bg, label: label, statusLabel: status)
        }
    }

    // MARK: - Skin picker (single-select — equipping one deselects all others)

    private struct SkinChipNodes {
        let container: SKNode
        let background: SKShapeNode
        let swatch: SKSpriteNode
        let label: SKLabelNode
        let statusLabel: SKLabelNode
    }

    private static let skinChipWidth: CGFloat = 94
    private static let skinChipHeight: CGFloat = 78

    private func buildSkinChips() {
        let hint = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        hint.text = Self.letterSpaced("YOUR LOOK")
        hint.fontSize = 11
        hint.fontColor = Palette.moonlightDim
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.zPosition = 2
        shopLayer.addChild(hint)
        skinSelectorHintLabel = hint

        for kind in PlayerSkinKind.allCases {
            let container = SKNode()
            container.zPosition = 2
            shopLayer.addChild(container)

            let bg = SKShapeNode(rectOf: CGSize(width: Self.skinChipWidth, height: Self.skinChipHeight), cornerRadius: 12)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            bg.lineWidth = 1.5
            bg.name = "selectSkin_\(kind.rawValue)"
            container.addChild(bg)

            let palette = Self.skinSwatchPalette(for: kind)
            let swatch = SKSpriteNode(texture: Self.skinSwatchTexture(cloak: palette.cloak, trim: palette.trim, core: palette.core, diameter: 34))
            swatch.position = CGPoint(x: 0, y: 17)
            swatch.name = "selectSkin_\(kind.rawValue)"
            container.addChild(swatch)

            let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            label.text = kind.displayName
            label.fontSize = 9.5
            label.fontColor = Palette.moonlight
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.numberOfLines = 2
            label.preferredMaxLayoutWidth = Self.skinChipWidth - 8
            label.lineBreakMode = .byWordWrapping
            label.position = CGPoint(x: 0, y: -9)
            label.name = "selectSkin_\(kind.rawValue)"
            container.addChild(label)

            let status = SKLabelNode(fontNamed: "AvenirNext-Bold")
            status.fontSize = 8
            status.fontColor = Palette.moonlightDim
            status.horizontalAlignmentMode = .center
            status.verticalAlignmentMode = .center
            status.position = CGPoint(x: 0, y: -Self.skinChipHeight / 2 + 9)
            status.name = "selectSkin_\(kind.rawValue)"
            container.addChild(status)

            skinChipNodes[kind] = SkinChipNodes(container: container, background: bg, swatch: swatch, label: label, statusLabel: status)
        }
    }

    // MARK: - Starting potion picker (multi-select up to startingPotionSlots, oldest drops out)

    private struct PotionChipNodes {
        let container: SKNode
        let background: SKShapeNode
        let icon: SKSpriteNode
        let label: SKLabelNode
        let statusLabel: SKLabelNode
    }

    private static let potionChipWidth: CGFloat = 74
    private static let potionChipHeight: CGFloat = 66

    private func buildPotionChips() {
        let hint = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        hint.fontSize = 10.5
        hint.fontColor = Palette.moonlightDim
        hint.horizontalAlignmentMode = .center
        hint.verticalAlignmentMode = .center
        hint.numberOfLines = 2
        hint.preferredMaxLayoutWidth = Self.rowWidth - 20
        hint.lineBreakMode = .byWordWrapping
        hint.zPosition = 2
        shopLayer.addChild(hint)
        potionSelectorHintLabel = hint

        for kind in PotionKind.allCases {
            let container = SKNode()
            container.zPosition = 2
            shopLayer.addChild(container)

            let bg = SKShapeNode(rectOf: CGSize(width: Self.potionChipWidth, height: Self.potionChipHeight), cornerRadius: 12)
            bg.fillColor = Palette.rowFill
            bg.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
            bg.lineWidth = 1.5
            bg.name = "selectPotion_\(kind.rawValue)"
            container.addChild(bg)

            let icon = SKSpriteNode(texture: Self.potionIconTexture(color: Potion.accentColor(for: kind), diameter: 26))
            icon.position = CGPoint(x: 0, y: 14)
            icon.name = "selectPotion_\(kind.rawValue)"
            container.addChild(icon)

            let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            label.text = kind.displayName
            label.fontSize = 8.5
            label.fontColor = Palette.moonlight
            label.horizontalAlignmentMode = .center
            label.verticalAlignmentMode = .center
            label.numberOfLines = 2
            label.preferredMaxLayoutWidth = Self.potionChipWidth - 6
            label.lineBreakMode = .byWordWrapping
            label.position = CGPoint(x: 0, y: -8)
            label.name = "selectPotion_\(kind.rawValue)"
            container.addChild(label)

            let status = SKLabelNode(fontNamed: "AvenirNext-Bold")
            status.fontSize = 7
            status.fontColor = Palette.moonlightDim
            status.horizontalAlignmentMode = .center
            status.verticalAlignmentMode = .center
            status.position = CGPoint(x: 0, y: -Self.potionChipHeight / 2 + 8)
            status.name = "selectPotion_\(kind.rawValue)"
            container.addChild(status)

            potionChipNodes[kind] = PotionChipNodes(container: container, background: bg, icon: icon, label: label, statusLabel: status)
        }
    }

    // MARK: - Reset All Progress (destructive, low-prominence link + confirm modal)

    private func buildResetProgressLink() {
        let link = SKLabelNode(fontNamed: "AvenirNext-Medium")
        link.text = "Reset All Progress"
        link.fontSize = 10.5
        link.fontColor = Palette.dim
        link.horizontalAlignmentMode = .center
        link.verticalAlignmentMode = .center
        link.name = "resetProgressLink"
        link.zPosition = 2
        shopLayer.addChild(link)
        resetLink = link
    }

    /// A small in-scene modal (SpriteKit has no native alert) — dim backdrop + danger card + CONFIRM/
    /// CANCEL, mirroring GameScene's revive-prompt convention (dim + staggered pop-in buttons). Built
    /// once as a single self-contained node so layout only ever needs to reposition its root each
    /// resize, unlike the sibling-node shop panel above.
    private func buildResetConfirmModal() {
        let modal = SKNode()
        modal.zPosition = 30
        modal.alpha = 0
        modal.isHidden = true
        shopLayer.addChild(modal)
        resetConfirmModal = modal

        let dim = SKShapeNode(rectOf: CGSize(width: 4000, height: 4000))
        dim.name = "resetConfirmCancel"
        dim.fillColor = SKColor.black.withAlphaComponent(0.72)
        dim.strokeColor = .clear
        dim.zPosition = 0
        modal.addChild(dim)

        let card = SKShapeNode(rectOf: CGSize(width: 292, height: 214), cornerRadius: 20)
        card.fillColor = Palette.panelFill
        card.strokeColor = Palette.blood.withAlphaComponent(0.85)
        card.lineWidth = 2
        card.glowWidth = 4
        card.zPosition = 1
        modal.addChild(card)

        let warnIcon = SKLabelNode(text: "⚠️")
        warnIcon.fontSize = 28
        warnIcon.verticalAlignmentMode = .center
        warnIcon.position = CGPoint(x: 0, y: 70)
        warnIcon.zPosition = 2
        modal.addChild(warnIcon)

        let title = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        title.text = "RESET ALL PROGRESS?"
        title.fontSize = 16.5
        title.fontColor = Palette.blood
        title.horizontalAlignmentMode = .center
        title.verticalAlignmentMode = .center
        title.position = CGPoint(x: 0, y: 40)
        title.zPosition = 2
        modal.addChild(title)

        let message = SKLabelNode(fontNamed: "AvenirNext-Medium")
        message.text = "Wipes your gold, every upgrade tier, pets, skins and potions. This cannot be undone."
        message.fontSize = 12
        message.fontColor = Palette.moonlightDim
        message.horizontalAlignmentMode = .center
        message.verticalAlignmentMode = .center
        message.numberOfLines = 3
        message.preferredMaxLayoutWidth = 246
        message.lineBreakMode = .byWordWrapping
        message.position = CGPoint(x: 0, y: 6)
        message.zPosition = 2
        modal.addChild(message)

        let (confirmBtn, confirmLabel) = Self.makeButton(text: "RESET EVERYTHING", width: 236, height: 44,
                                                           fill: Palette.blood, stroke: SKColor(red: 1, green: 0.3, blue: 0.35, alpha: 1),
                                                           textColor: Palette.moonlight, fontSize: 13.5, fontName: "AvenirNext-Heavy")
        confirmBtn.name = "resetConfirmConfirm"
        confirmLabel.name = "resetConfirmConfirm"
        confirmBtn.position = CGPoint(x: 0, y: -44)
        confirmLabel.position = confirmBtn.position
        confirmBtn.zPosition = 2
        confirmLabel.zPosition = 3
        modal.addChild(confirmBtn)
        modal.addChild(confirmLabel)
        resetConfirmConfirmButton = confirmBtn

        let (cancelBtn, cancelLabel) = Self.makeButton(text: "CANCEL", width: 170, height: 34,
                                                         fill: Palette.rowFill, stroke: Palette.panelStroke,
                                                         textColor: Palette.moonlight, fontSize: 12.5, fontName: "AvenirNext-DemiBold")
        cancelBtn.name = "resetConfirmCancel"
        cancelLabel.name = "resetConfirmCancel"
        cancelBtn.position = CGPoint(x: 0, y: -86)
        cancelLabel.position = cancelBtn.position
        cancelBtn.zPosition = 2
        cancelLabel.zPosition = 3
        modal.addChild(cancelBtn)
        modal.addChild(cancelLabel)
        resetConfirmCancelButton = cancelBtn
    }

    private static let rowWidth: CGFloat = 320
    private static let rowHeight: CGFloat = 68
    private static let rowSpacing: CGFloat = 8

    // MARK: - Layout (called on didMove and every didChangeSize — resizeFill re-sizes the scene)

    private func layout(size: CGSize) {
        let w = size.width, h = size.height

        if let bg = backgroundLayer.childNode(withName: "bgGradient") as? SKSpriteNode {
            bg.size = CGSize(width: w, height: h)
            bg.position = CGPoint(x: w / 2, y: h / 2)
        }

        let moonPos = CGPoint(x: w * 0.80, y: h * 0.87)
        moonNode.position = moonPos
        moonGlow.position = moonPos

        emberEmitter.particlePosition = CGPoint(x: w / 2, y: -10)
        emberEmitter.particlePositionRange = CGVector(dx: w * 1.1, dy: 0)

        for (i, node) in starNodes.enumerated() {
            let (fraction, _) = starFractions[i]
            node.position = CGPoint(x: fraction.x * w, y: fraction.y * h)
        }

        titleShadow.position = CGPoint(x: w / 2 + 2, y: h * 0.70 - 3)
        titleLabel.position = CGPoint(x: w / 2, y: h * 0.70)
        subtitleLabel.position = CGPoint(x: w / 2, y: h * 0.70 - 40)

        let statsY = h * 0.70 - 78
        layoutStatsChips(centerY: statsY, width: w)

        playButton.position = CGPoint(x: w / 2, y: h * 0.24)
        playLabel.position = playButton.position
        shopButton.position = CGPoint(x: w / 2, y: h * 0.24 - 66)
        shopLabel.position = shopButton.position
        goldRushCard.position = CGPoint(x: w / 2, y: h * 0.24 - 128)

        footerLabel.position = CGPoint(x: w / 2, y: max(28, h * 0.05))

        layoutShopPanel(size: size)
    }

    private func layoutStatsChips(centerY: CGFloat, width w: CGFloat) {
        // Two chips: [moon icon] mm:ss   [coin icon] gold — centered as a pair with fixed gutter.
        let bestText = bestTimeLabel.text ?? "--"
        let goldText = goldLabel.text ?? "0"
        let bestWidth = Self.measureWidth(bestText, fontName: "AvenirNext-DemiBold", fontSize: 17) + 26
        let goldWidth = Self.measureWidth(goldText, fontName: "AvenirNext-DemiBold", fontSize: 17) + 26
        let gutter: CGFloat = 34
        let totalWidth = bestWidth + goldWidth + gutter
        let startX = w / 2 - totalWidth / 2

        let bestIconX = startX + 10
        let bestTextX = bestIconX + 16
        bestTimeLabel.horizontalAlignmentMode = .left
        bestTimeLabel.position = CGPoint(x: bestTextX, y: centerY)
        (contentLayer.childNode(withName: "bestIcon") as? SKSpriteNode)?.position = CGPoint(x: bestIconX, y: centerY)

        let goldIconX = startX + bestWidth + gutter
        let goldTextX = goldIconX + 16
        goldLabel.horizontalAlignmentMode = .left
        goldLabel.position = CGPoint(x: goldTextX, y: centerY)
        (contentLayer.childNode(withName: "coinIcon") as? SKSpriteNode)?.position = CGPoint(x: goldIconX, y: centerY)
    }

    private func layoutShopPanel(size: CGSize) {
        let w = size.width, h = size.height
        let panelWidth = min(w - 32, Self.rowWidth + 40)
        let listHeight = CGFloat(Self.maxCategoryRowCount) * Self.rowHeight + CGFloat(Self.maxCategoryRowCount - 1) * Self.rowSpacing
        // +34 (rather than the old +28) reserves just enough extra room at the very bottom of the
        // panel for the small "Reset All Progress" link — deliberately tight/low-prominence, not a
        // full extra row.
        let panelHeight = min(h - 96, Self.shopHeaderTotalHeight + listHeight + 34)

        let panelRect = CGRect(x: -panelWidth / 2, y: -panelHeight / 2, width: panelWidth, height: panelHeight)
        shopPanel.path = CGPath(roundedRect: panelRect, cornerWidth: 20, cornerHeight: 20, transform: nil)
        shopPanel.position = CGPoint(x: w / 2, y: h / 2)

        shopOverlay.position = CGPoint(x: w / 2, y: h / 2)
        resetConfirmModal.position = CGPoint(x: w / 2, y: h / 2)

        let panelTop = shopPanel.position.y + panelHeight / 2
        let panelBottom = shopPanel.position.y - panelHeight / 2
        shopTitleLabel.position = CGPoint(x: w / 2, y: panelTop - 34)
        shopTitleGlow.position = shopTitleLabel.position
        shopCloseButton.position = CGPoint(x: w / 2 + panelWidth / 2 - 32, y: panelTop - 30)
        shopCloseLabel.position = shopCloseButton.position
        shopGoldLabel.position = CGPoint(x: w / 2, y: panelTop - 62)
        autoReviveCard.position = CGPoint(x: w / 2, y: panelTop - 92)
        speedBoostCard.position = CGPoint(x: w / 2, y: panelTop - 126)

        let tabsY = panelTop - 165
        let tabWidth = Self.shopTabWidth, tabGap: CGFloat = 6
        let totalTabsWidth = CGFloat(shopTabButtons.count) * tabWidth + CGFloat(max(0, shopTabButtons.count - 1)) * tabGap
        var tabX = w / 2 - totalTabsWidth / 2 + tabWidth / 2
        for i in 0..<shopTabButtons.count {
            let tabPos = CGPoint(x: tabX, y: tabsY)
            shopTabButtons[i].position = tabPos
            shopTabLabels[i].position = CGPoint(x: tabPos.x, y: tabPos.y - 9)
            shopTabIconLabels[i].position = CGPoint(x: tabPos.x, y: tabPos.y + 8)
            tabX += tabWidth + tabGap
        }

        let listTop = panelTop - Self.shopHeaderTotalHeight
        for (categoryIndex, category) in Self.shopCategories.enumerated() {
            var rowY = listTop
            for kind in category {
                guard let row = shopRows[kind] else { continue }
                row.container.position = CGPoint(x: w / 2, y: rowY - Self.rowHeight / 2)
                rowY -= (Self.rowHeight + Self.rowSpacing)
            }
            if categoryIndex == Self.familiarsTabIndex {
                layoutPetChips(topY: rowY, centerX: w / 2)
            } else if categoryIndex == Self.skinsTabIndex {
                layoutSkinChips(topY: rowY, centerX: w / 2)
            } else if categoryIndex == Self.potionsTabIndex {
                layoutPotionChips(topY: rowY, centerX: w / 2)
            }
        }

        resetLink.position = CGPoint(x: w / 2, y: panelBottom + 17)
    }

    private func layoutPetChips(topY: CGFloat, centerX: CGFloat) {
        let headerY = topY - 4
        petSelectorHintLabel.position = CGPoint(x: centerX, y: headerY)

        let chipsRowY = headerY - 32
        let chipWidth = Self.petChipWidth, chipGap: CGFloat = 8
        let count = CGFloat(PetKind.allCases.count)
        let totalWidth = count * chipWidth + max(0, count - 1) * chipGap
        var x = centerX - totalWidth / 2 + chipWidth / 2
        for kind in PetKind.allCases {
            guard let chip = petChipNodes[kind] else { continue }
            chip.container.position = CGPoint(x: x, y: chipsRowY)
            x += chipWidth + chipGap
        }
    }

    private func layoutSkinChips(topY: CGFloat, centerX: CGFloat) {
        let headerY = topY - 12
        skinSelectorHintLabel.position = CGPoint(x: centerX, y: headerY)
        let gridTop = headerY - 24
        Self.layoutGrid(items: PlayerSkinKind.allCases, chipWidth: Self.skinChipWidth, chipHeight: Self.skinChipHeight,
                         gapX: 10, gapY: 10, perRow: 3, topY: gridTop, centerX: centerX) { kind, position in
            self.skinChipNodes[kind]?.container.position = position
        }
    }

    private func layoutPotionChips(topY: CGFloat, centerX: CGFloat) {
        let headerY = topY - 16
        potionSelectorHintLabel.position = CGPoint(x: centerX, y: headerY)
        let gridTop = headerY - 26
        Self.layoutGrid(items: PotionKind.allCases, chipWidth: Self.potionChipWidth, chipHeight: Self.potionChipHeight,
                         gapX: 8, gapY: 8, perRow: 4, topY: gridTop, centerX: centerX) { kind, position in
            self.potionChipNodes[kind]?.container.position = position
        }
    }

    /// Wraps `items` into left-to-right, top-to-bottom rows of at most `perRow`, each row independently
    /// centered on `centerX` — shared by the skin and potion pickers (pet chips keep their own simpler
    /// single-row layout above, unchanged from before this redesign).
    private static func layoutGrid<T>(items: [T], chipWidth: CGFloat, chipHeight: CGFloat, gapX: CGFloat, gapY: CGFloat,
                                       perRow: Int, topY: CGFloat, centerX: CGFloat, place: (T, CGPoint) -> Void) {
        var index = 0
        var y = topY
        while index < items.count {
            let itemsInRow = min(perRow, items.count - index)
            let rowWidth = CGFloat(itemsInRow) * chipWidth + CGFloat(max(0, itemsInRow - 1)) * gapX
            var x = centerX - rowWidth / 2 + chipWidth / 2
            for _ in 0..<itemsInRow {
                place(items[index], CGPoint(x: x, y: y - chipHeight / 2))
                x += chipWidth + gapX
                index += 1
            }
            y -= (chipHeight + gapY)
        }
    }

    // MARK: - Stats refresh

    private func refreshStats() {
        let best = MetaProgressionStore.shared.bestSurvivalTime
        bestTimeLabel.text = best > 0 ? Self.formatTime(best) : "--"
        goldLabel.text = "\(MetaProgressionStore.shared.gold)"
        for kind in MetaUpgradeKind.allCases {
            refreshShopRow(kind)
        }
        refreshPetChips()
        refreshSkinChips()
        refreshPotionChips()
        shopGoldLabel.text = "YOUR GOLD:  \(MetaProgressionStore.shared.gold)"
        refreshGoldRushCard()
        refreshAutoReviveCard()
        refreshSpeedBoostCard()
    }

    private func refreshShopRow(_ kind: MetaUpgradeKind) {
        guard let row = shopRows[kind] else { return }
        let tier = MetaProgressionStore.shared.tier(for: kind)
        row.tierLabel.text = "TIER \(tier)/\(kind.maxTier)"

        if let cost = MetaProgressionStore.shared.nextTierCost(for: kind) {
            let canAfford = MetaProgressionStore.shared.gold >= cost
            row.buyButton.isHidden = false
            row.buyLabel.isHidden = false
            row.maxedLabel.isHidden = true
            row.buyLabel.text = "\(cost)g"
            row.buyButton.alpha = canAfford ? 1.0 : 0.4
            row.buyLabel.alpha = canAfford ? 1.0 : 0.6
            // A small glow kicks in once you can actually afford it — a cheap, constantly-updating
            // affordance cue on top of the existing alpha dim/undim.
            row.buyButton.glowWidth = canAfford ? 2.5 : 0
            row.buyButton.name = "buy_\(kind.rawValue)"
            row.buyLabel.name = "buy_\(kind.rawValue)"
        } else {
            row.buyButton.isHidden = true
            row.buyLabel.isHidden = true
            row.maxedLabel.isHidden = false
        }
    }

    /// Restyles each pet chip: dimmed/locked if not yet owned, highlighted border+status if it's one
    /// of the currently active familiars (see MetaProgressionStore.activePetKinds()), plain otherwise.
    private func refreshPetChips() {
        let store = MetaProgressionStore.shared
        let owned = Set(store.ownedPetKinds())
        let active = Set(store.activePetKinds())
        for kind in PetKind.allCases {
            guard let chip = petChipNodes[kind] else { continue }
            let isOwned = owned.contains(kind)
            let isActive = isOwned && active.contains(kind)
            chip.container.alpha = isOwned ? 1.0 : 0.5
            if isActive {
                chip.background.fillColor = Palette.ember.withAlphaComponent(0.35)
                chip.background.strokeColor = Palette.emberBright
                chip.background.lineWidth = 2.0
                chip.statusLabel.text = "✓ ACTIVE"
                chip.statusLabel.fontColor = Palette.emberBright
                chip.label.fontColor = Palette.moonlight
            } else if isOwned {
                chip.background.fillColor = Palette.rowFill
                chip.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.4)
                chip.background.lineWidth = 1
                chip.statusLabel.text = "tap to select"
                chip.statusLabel.fontColor = Palette.moonlightDim
                chip.label.fontColor = Palette.moonlight
            } else {
                chip.background.fillColor = Palette.rowFill
                chip.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.25)
                chip.background.lineWidth = 1
                chip.statusLabel.text = "locked"
                chip.statusLabel.fontColor = Palette.dim
                chip.label.fontColor = Palette.moonlightDim
            }
        }
    }

    /// Restyles each skin chip: dimmed/locked if not owned, ember-highlighted if it's the one
    /// currently equipped (single-select — see MetaProgressionStore.selectedSkin), plain otherwise.
    private func refreshSkinChips() {
        let store = MetaProgressionStore.shared
        let selected = store.selectedSkin
        for kind in PlayerSkinKind.allCases {
            guard let chip = skinChipNodes[kind] else { continue }
            let owned = store.isSkinOwned(kind)
            let isSelected = owned && kind == selected
            chip.container.alpha = owned ? 1.0 : 0.55
            chip.swatch.alpha = owned ? 1.0 : 0.5
            if isSelected {
                chip.background.fillColor = Palette.ember.withAlphaComponent(0.30)
                chip.background.strokeColor = Palette.emberBright
                chip.background.lineWidth = 2.2
                chip.background.glowWidth = 3
                chip.statusLabel.text = "✓ EQUIPPED"
                chip.statusLabel.fontColor = Palette.emberBright
                chip.label.fontColor = Palette.moonlight
            } else if owned {
                chip.background.fillColor = Palette.rowFill
                chip.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.5)
                chip.background.lineWidth = 1.5
                chip.background.glowWidth = 0
                chip.statusLabel.text = "tap to equip"
                chip.statusLabel.fontColor = Palette.moonlightDim
                chip.label.fontColor = Palette.moonlight
            } else {
                chip.background.fillColor = Palette.rowFill
                chip.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.25)
                chip.background.lineWidth = 1
                chip.background.glowWidth = 0
                chip.statusLabel.text = "locked"
                chip.statusLabel.fontColor = Palette.dim
                chip.label.fontColor = Palette.moonlightDim
            }
        }
    }

    /// Restyles each potion chip: dimmed+"instant only" for kinds that can never be a starting potion
    /// (see MetaProgressionStore.selectedStartingPotions' filter), dimmed+"locked" while no Potion
    /// Mastery tier has been bought yet, highlighted if currently selected, plain otherwise. Also
    /// updates the hint label above the grid, including the "buy Potion Mastery first" nudge.
    private func refreshPotionChips() {
        let store = MetaProgressionStore.shared
        let slots = store.startingPotionSlots
        let selected = Set(store.selectedStartingPotions())
        if slots > 0 {
            potionSelectorHintLabel.text = "STARTING VIALS · \(selected.count)/\(slots) SELECTED"
            potionSelectorHintLabel.fontColor = Palette.moonlightDim
        } else {
            potionSelectorHintLabel.text = "Buy Potion Mastery to select starting potions."
            potionSelectorHintLabel.fontColor = Palette.dim
        }
        for kind in PotionKind.allCases {
            guard let chip = potionChipNodes[kind] else { continue }
            let eligible = !kind.isInstant
            let unlocked = eligible && slots > 0
            let isSelected = unlocked && selected.contains(kind)
            chip.container.alpha = !eligible ? 0.4 : (slots > 0 ? 1.0 : 0.5)
            if isSelected {
                let accent = Potion.accentColor(for: kind)
                chip.background.fillColor = accent.withAlphaComponent(0.28)
                chip.background.strokeColor = accent
                chip.background.lineWidth = 2.2
                chip.background.glowWidth = 3
                chip.statusLabel.text = "✓ selected"
                chip.statusLabel.fontColor = Palette.moonlight
            } else if unlocked {
                chip.background.fillColor = Palette.rowFill
                chip.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.5)
                chip.background.lineWidth = 1.5
                chip.background.glowWidth = 0
                chip.statusLabel.text = "tap to select"
                chip.statusLabel.fontColor = Palette.moonlightDim
            } else if !eligible {
                chip.background.fillColor = Palette.rowFill
                chip.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.3)
                chip.background.lineWidth = 1
                chip.background.glowWidth = 0
                chip.statusLabel.text = "instant only"
                chip.statusLabel.fontColor = Palette.dim
            } else {
                chip.background.fillColor = Palette.rowFill
                chip.background.strokeColor = Palette.panelStroke.withAlphaComponent(0.25)
                chip.background.lineWidth = 1
                chip.background.glowWidth = 0
                chip.statusLabel.text = "locked"
                chip.statusLabel.fontColor = Palette.dim
            }
        }
    }

    // MARK: - Shop open/close

    /// Shows only the rows/chips belonging to `selectedShopTab`, hiding the rest. Hiding here is
    /// belt-and-suspenders visual correctness — topInteractiveName() below is what actually gates
    /// touches, since nodes(at:) ignores isHidden.
    private func refreshShopTabVisibility() {
        for kind in MetaUpgradeKind.allCases {
            shopRows[kind]?.container.isHidden = Self.category(for: kind) != selectedShopTab
        }
        let familiarsVisible = selectedShopTab == Self.familiarsTabIndex
        petSelectorHintLabel.isHidden = !familiarsVisible
        for chip in petChipNodes.values {
            chip.container.isHidden = !familiarsVisible
        }

        let skinsVisible = selectedShopTab == Self.skinsTabIndex
        skinSelectorHintLabel.isHidden = !skinsVisible
        for chip in skinChipNodes.values {
            chip.container.isHidden = !skinsVisible
        }

        let potionsVisible = selectedShopTab == Self.potionsTabIndex
        potionSelectorHintLabel.isHidden = !potionsVisible
        for chip in potionChipNodes.values {
            chip.container.isHidden = !potionsVisible
        }

        for (i, btn) in shopTabButtons.enumerated() {
            let active = i == selectedShopTab
            btn.fillColor = active ? Palette.ember : Palette.rowFill
            btn.strokeColor = active ? Palette.emberBright : Palette.panelStroke
            btn.lineWidth = active ? 2.2 : 1.4
            btn.glowWidth = active ? 3 : 0
            shopTabLabels[i].fontColor = active ? SKColor(red: 0.12, green: 0.03, blue: 0.02, alpha: 1) : Palette.moonlightDim
            shopTabIconLabels[i].alpha = active ? 1.0 : 0.6
        }
    }

    private func setShopOpen(_ open: Bool) {
        guard open != isShopOpen else { return }
        isShopOpen = open
        AudioManager.shared.playSFX(.buttonTap)
        if open {
            refreshStats()
            refreshShopTabVisibility()
            shopOverlay.alpha = 0
            shopPanel.alpha = 0
            shopPanel.setScale(0.92)
            shopLayer.isHidden = false
            let fadeIn = SKAction.fadeAlpha(to: 1, duration: 0.22)
            shopOverlay.run(fadeIn)
            shopPanel.run(SKAction.group([fadeIn, SKAction.scale(to: 1.0, duration: 0.26)]))
            for kind in MetaUpgradeKind.allCases {
                shopRows[kind]?.container.alpha = 0
                shopRows[kind]?.container.run(SKAction.sequence([SKAction.wait(forDuration: 0.05), SKAction.fadeIn(withDuration: 0.2)]))
            }
            for kind in PetKind.allCases {
                petChipNodes[kind]?.container.alpha = 0
                petChipNodes[kind]?.container.run(SKAction.sequence([SKAction.wait(forDuration: 0.05), SKAction.fadeIn(withDuration: 0.2)]))
            }
            petSelectorHintLabel.alpha = 0
            petSelectorHintLabel.run(SKAction.sequence([SKAction.wait(forDuration: 0.05), SKAction.fadeIn(withDuration: 0.2)]))
            for kind in PlayerSkinKind.allCases {
                skinChipNodes[kind]?.container.alpha = 0
                skinChipNodes[kind]?.container.run(SKAction.sequence([SKAction.wait(forDuration: 0.05), SKAction.fadeIn(withDuration: 0.2)]))
            }
            skinSelectorHintLabel.alpha = 0
            skinSelectorHintLabel.run(SKAction.sequence([SKAction.wait(forDuration: 0.05), SKAction.fadeIn(withDuration: 0.2)]))
            for kind in PotionKind.allCases {
                potionChipNodes[kind]?.container.alpha = 0
                potionChipNodes[kind]?.container.run(SKAction.sequence([SKAction.wait(forDuration: 0.05), SKAction.fadeIn(withDuration: 0.2)]))
            }
            potionSelectorHintLabel.alpha = 0
            potionSelectorHintLabel.run(SKAction.sequence([SKAction.wait(forDuration: 0.05), SKAction.fadeIn(withDuration: 0.2)]))
            resetLink.alpha = 0
            resetLink.run(SKAction.sequence([SKAction.wait(forDuration: 0.05), SKAction.fadeIn(withDuration: 0.2)]))
        } else {
            // Safety net: the reset-confirm modal can't normally still be open when the shop closes
            // (topInteractiveName blocks shopClose/shopOverlay taps while it's up), but snap it shut
            // instantly rather than animated in case some other path ever gets here with it showing.
            if isResetConfirmOpen {
                isResetConfirmOpen = false
                resetConfirmModal.removeAllActions()
                resetConfirmModal.alpha = 0
                resetConfirmModal.isHidden = true
            }
            let fadeOut = SKAction.fadeOut(withDuration: 0.18)
            shopOverlay.run(fadeOut)
            shopPanel.run(SKAction.group([fadeOut, SKAction.scale(to: 0.94, duration: 0.18)])) { [weak self] in
                self?.shopLayer.isHidden = true
            }
        }
    }

    private func setResetConfirmOpen(_ open: Bool) {
        guard open != isResetConfirmOpen else { return }
        isResetConfirmOpen = open
        AudioManager.shared.playSFX(.buttonTap)
        if open {
            AudioManager.shared.hapticNotification(.warning)
            resetConfirmModal.removeAllActions()
            resetConfirmModal.alpha = 0
            resetConfirmModal.setScale(0.92)
            resetConfirmModal.isHidden = false
            resetConfirmModal.run(SKAction.group([SKAction.fadeIn(withDuration: 0.18), SKAction.scale(to: 1.0, duration: 0.2)]))
        } else {
            resetConfirmModal.removeAllActions()
            resetConfirmModal.run(SKAction.group([SKAction.fadeOut(withDuration: 0.15), SKAction.scale(to: 0.94, duration: 0.15)])) { [weak self] in
                self?.resetConfirmModal.isHidden = true
            }
        }
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

    /// SpriteKit's `nodes(at:)` is a purely geometric query — it does NOT respect `isHidden`,
    /// so an off-screen (hidden) shop panel's buttons could still geometrically overlap and
    /// "steal" taps meant for PLAY/SHOP underneath. Gate candidates explicitly by `isShopOpen`
    /// instead of trusting node visibility.
    private func topInteractiveName(at location: CGPoint) -> String? {
        let hit = nodes(at: location)
        let matched = hit.filter { node in
            guard let name = node.name else { return false }
            // The reset-confirm modal is a full-screen-blocking overlay on top of the shop panel —
            // while it's up, nothing behind it (shop tabs, rows, close button...) is reachable.
            if isResetConfirmOpen {
                return name == "resetConfirmCancel" || name == "resetConfirmConfirm"
            }
            if isShopOpen {
                if name == "shopOverlay" || name == "shopClose" || name == "autoReviveAction" || name == "speedBoostAction" || name == "resetProgressLink" { return true }
                if name.hasPrefix("shopTab_") { return true }
                if name.hasPrefix("buy_") {
                    // Rows from the non-selected tab still exist at overlapping positions (only one
                    // tab is ever isHidden == false), so gate touches by category explicitly — same
                    // reasoning as the isHidden note above.
                    guard let kind = MetaUpgradeKind(rawValue: String(name.dropFirst("buy_".count))) else { return false }
                    return Self.category(for: kind) == selectedShopTab
                }
                if name.hasPrefix("petChip_") {
                    return selectedShopTab == Self.familiarsTabIndex
                }
                if name.hasPrefix("selectSkin_") {
                    return selectedShopTab == Self.skinsTabIndex
                }
                if name.hasPrefix("selectPotion_") {
                    return selectedShopTab == Self.potionsTabIndex
                }
                return false
            } else {
                return name == "play" || name == "shopToggle" || name == "goldRushAction"
            }
        }
        return matched.max(by: { $0.zPosition < $1.zPosition })?.name
    }

    /// Press-down is a plain quick scale; release adds JuiceEffects' small overshoot bounce on top of
    /// the flat snap-back so every tap on this screen resolves with a bit more life, not just a mirror
    /// of the press. Both stay well under the ~150-200ms responsiveness budget.
    private func setPressed(name: String, pressed: Bool) {
        func apply(_ node: SKNode) {
            if pressed { JuiceEffects.pressDown(node) } else { JuiceEffects.releaseBounce(node) }
        }
        switch name {
        case "play":
            apply(playButton)
        case "shopToggle":
            apply(shopButton)
        case "shopClose":
            apply(shopCloseButton)
        case "goldRushAction":
            apply(goldRushCard)
        case "autoReviveAction":
            apply(autoReviveCard)
        case "speedBoostAction":
            apply(speedBoostCard)
        case "resetProgressLink":
            apply(resetLink)
        case "resetConfirmCancel":
            apply(resetConfirmCancelButton)
        case "resetConfirmConfirm":
            apply(resetConfirmConfirmButton)
        default:
            if name.hasPrefix("buy_") {
                let kindRaw = String(name.dropFirst("buy_".count))
                if let kind = MetaUpgradeKind(rawValue: kindRaw), let button = shopRows[kind]?.buyButton {
                    apply(button)
                }
            } else if name.hasPrefix("shopTab_") {
                if let idx = Int(name.dropFirst("shopTab_".count)), idx < shopTabButtons.count {
                    apply(shopTabButtons[idx])
                }
            } else if name.hasPrefix("petChip_") {
                let kindRaw = String(name.dropFirst("petChip_".count))
                if let kind = PetKind(rawValue: kindRaw), let chip = petChipNodes[kind]?.container {
                    apply(chip)
                }
            } else if name.hasPrefix("selectSkin_") {
                let kindRaw = String(name.dropFirst("selectSkin_".count))
                if let kind = PlayerSkinKind(rawValue: kindRaw), let chip = skinChipNodes[kind]?.container {
                    apply(chip)
                }
            } else if name.hasPrefix("selectPotion_") {
                let kindRaw = String(name.dropFirst("selectPotion_".count))
                if let kind = PotionKind(rawValue: kindRaw), let chip = potionChipNodes[kind]?.container {
                    apply(chip)
                }
            }
        }
    }

    private func handleTap(name: String) {
        switch name {
        case "play":
            AudioManager.shared.playSFX(.buttonTap)
            AudioManager.shared.hapticImpact(.medium)
            // A doorway-open reads as "stepping out into the night" rather than a flat cross-dissolve —
            // fitting for the moment PLAY actually commits you to a run.
            view?.presentScene(GameScene.newScene(), transition: .doorway(withDuration: 0.6))
        case "shopToggle":
            setShopOpen(true)
        case "shopClose", "shopOverlay":
            setShopOpen(false)
        case "goldRushAction":
            handleGoldRushTap()
        case "autoReviveAction":
            handleAutoReviveTap()
        case "speedBoostAction":
            handleSpeedBoostTap()
        case "resetProgressLink":
            setResetConfirmOpen(true)
        case "resetConfirmCancel":
            setResetConfirmOpen(false)
        case "resetConfirmConfirm":
            // Re-entrancy guard mirroring LevelUpOverlay.dismiss's hasDismissed pattern (and
            // GameScene.selectUpgrade's early levelUpOverlay = nil): flip the "confirm is live"
            // state to false synchronously, before performing the irreversible action, so this
            // can't fire resetAll() twice — instead of relying solely on topInteractiveName's
            // isResetConfirmOpen gate at the call site.
            guard isResetConfirmOpen else { return }
            AudioManager.shared.hapticNotification(.warning)
            setResetConfirmOpen(false)
            MetaProgressionStore.shared.resetAll()
            refreshStats()
        default:
            if name.hasPrefix("buy_") {
                let kindRaw = String(name.dropFirst("buy_".count))
                if let kind = MetaUpgradeKind(rawValue: kindRaw) {
                    handleBuy(kind: kind)
                }
            } else if name.hasPrefix("shopTab_") {
                if let idx = Int(name.dropFirst("shopTab_".count)) {
                    handleShopTabTap(idx)
                }
            } else if name.hasPrefix("petChip_") {
                let kindRaw = String(name.dropFirst("petChip_".count))
                if let kind = PetKind(rawValue: kindRaw) {
                    handlePetChipTap(kind)
                }
            } else if name.hasPrefix("selectSkin_") {
                let kindRaw = String(name.dropFirst("selectSkin_".count))
                if let kind = PlayerSkinKind(rawValue: kindRaw) {
                    handleSkinChipTap(kind)
                }
            } else if name.hasPrefix("selectPotion_") {
                let kindRaw = String(name.dropFirst("selectPotion_".count))
                if let kind = PotionKind(rawValue: kindRaw) {
                    handlePotionChipTap(kind)
                }
            }
        }
    }

    private func handleShopTabTap(_ index: Int) {
        guard index != selectedShopTab, index >= 0, index < shopTabButtons.count else { return }
        AudioManager.shared.playSFX(.buttonTap)
        selectedShopTab = index
        refreshShopTabVisibility()
        for kind in MetaUpgradeKind.allCases where Self.category(for: kind) == selectedShopTab {
            shopRows[kind]?.container.alpha = 0
            shopRows[kind]?.container.run(SKAction.fadeIn(withDuration: 0.15))
        }
        if selectedShopTab == Self.familiarsTabIndex {
            for kind in PetKind.allCases {
                petChipNodes[kind]?.container.alpha = 0
                petChipNodes[kind]?.container.run(SKAction.fadeIn(withDuration: 0.15))
            }
            petSelectorHintLabel.alpha = 0
            petSelectorHintLabel.run(SKAction.fadeIn(withDuration: 0.15))
        } else if selectedShopTab == Self.skinsTabIndex {
            for kind in PlayerSkinKind.allCases {
                skinChipNodes[kind]?.container.alpha = 0
                skinChipNodes[kind]?.container.run(SKAction.fadeIn(withDuration: 0.15))
            }
            skinSelectorHintLabel.alpha = 0
            skinSelectorHintLabel.run(SKAction.fadeIn(withDuration: 0.15))
        } else if selectedShopTab == Self.potionsTabIndex {
            for kind in PotionKind.allCases {
                potionChipNodes[kind]?.container.alpha = 0
                potionChipNodes[kind]?.container.run(SKAction.fadeIn(withDuration: 0.15))
            }
            potionSelectorHintLabel.alpha = 0
            potionSelectorHintLabel.run(SKAction.fadeIn(withDuration: 0.15))
        }
    }

    /// Toggles `kind` in/out of the active familiar selection. Unowned pets are a locked preview —
    /// tapping does nothing to selection. Respects the slot limit (1, or 2 with secondPetSlot) by
    /// evicting the oldest-selected pet to make room rather than refusing the tap.
    private func handlePetChipTap(_ kind: PetKind) {
        let store = MetaProgressionStore.shared
        guard store.ownedPetKinds().contains(kind) else { return }
        AudioManager.shared.playSFX(.buttonTap)
        var active = store.activePetKinds()
        if let idx = active.firstIndex(of: kind) {
            active.remove(at: idx)
        } else {
            let slots = store.tier(for: .secondPetSlot) > 0 ? 2 : 1
            active.append(kind)
            while active.count > slots {
                active.removeFirst()
            }
        }
        store.setActivePetKinds(active)
        AudioManager.shared.hapticImpact(.light)
        refreshPetChips()
    }

    /// Single-select equip: locked (unowned) skins are a preview-only tap-no-op; owned skins simply
    /// become the new selection, deselecting whatever was equipped before (MetaProgressionStore.
    /// selectedSkin is a single value, not a list).
    private func handleSkinChipTap(_ kind: PlayerSkinKind) {
        let store = MetaProgressionStore.shared
        guard store.isSkinOwned(kind) else {
            AudioManager.shared.hapticImpact(.soft)
            return
        }
        guard store.selectedSkin != kind else { return }
        AudioManager.shared.playSFX(.buttonTap)
        store.selectedSkin = kind
        AudioManager.shared.hapticImpact(.light)
        refreshSkinChips()
    }

    /// Toggles `kind` in/out of the starting-potion selection. No-ops (soft haptic only) for instant
    /// kinds (voidMagnet/risingMoon — never eligible, see MetaProgressionStore.selectedStartingPotions'
    /// doc comment) and while no Potion Mastery tier has been purchased yet (0 slots). Respects the
    /// slot cap by evicting the oldest-selected potion, same rotation as handlePetChipTap above.
    private func handlePotionChipTap(_ kind: PotionKind) {
        let store = MetaProgressionStore.shared
        guard !kind.isInstant, store.startingPotionSlots > 0 else {
            AudioManager.shared.hapticImpact(.soft)
            return
        }
        AudioManager.shared.playSFX(.buttonTap)
        var selected = store.selectedStartingPotions()
        if let idx = selected.firstIndex(of: kind) {
            selected.remove(at: idx)
        } else {
            selected.append(kind)
            while selected.count > store.startingPotionSlots {
                selected.removeFirst()
            }
        }
        store.setSelectedStartingPotions(selected)
        AudioManager.shared.hapticImpact(.light)
        refreshPotionChips()
    }

    private func handleBuy(kind: MetaUpgradeKind) {
        AudioManager.shared.playSFX(.buttonTap)
        let success = MetaProgressionStore.shared.purchaseNextTier(kind)
        if success {
            AudioManager.shared.hapticNotification(.success)
            if let row = shopRows[kind] {
                let flash = SKAction.sequence([
                    SKAction.run { row.background.fillColor = Palette.ember.withAlphaComponent(0.5) },
                    SKAction.wait(forDuration: 0.12),
                    SKAction.run { row.background.fillColor = Palette.rowFill }
                ])
                let pop = SKAction.sequence([SKAction.scale(to: 1.03, duration: 0.08), SKAction.scale(to: 1.0, duration: 0.1)])
                row.container.run(SKAction.group([flash, pop]))
            }
        } else {
            AudioManager.shared.hapticImpact(.soft)
        }
        refreshStats()
        // Gold just changed (spent on the purchase) — punch both places it's displayed so the spend
        // reads as an event rather than the number silently snapping down.
        if success {
            JuiceEffects.numberPunch(goldLabel)
            JuiceEffects.numberPunch(shopGoldLabel)
        }
    }

    // MARK: - Procedural textures & helpers

    /// UIGraphicsImageRenderer's CGContext has its origin at the top-left with y increasing
    /// downward (matches UIKit view drawing); the resulting SKTexture displays the image the
    /// same way it looks as a UIImage, so y=0 here is the visual TOP of the sprite.
    private static func gradientTexture(top: SKColor, bottom: SKColor, size: CGSize) -> SKTexture {
        ProceduralTextures.render(size: size, opaque: true) { ctx, size in
            let colors = [top.cgColor, bottom.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    private static func crescentTexture(diameter: CGFloat, color: SKColor) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let outerRect = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 0.06, dy: size.width * 0.06)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: outerRect)
            ctx.setBlendMode(.clear)
            let biteDiameter = size.width * 0.86
            let biteRect = CGRect(x: outerRect.midX - biteDiameter * 0.32, y: outerRect.midY - biteDiameter * 0.06,
                                   width: biteDiameter, height: biteDiameter)
            ctx.fillEllipse(in: biteRect)
            ctx.setBlendMode(.normal)
        }
    }

    /// Like gradientTexture above but with real alpha transparency (that one hardcodes `opaque: true`,
    /// which would bake translucent colors onto an opaque backing instead of actually blending) — used
    /// for the subtle "glassy" sheen overlay on every shop row card.
    private static func alphaGradientTexture(topAlpha: CGFloat, bottomAlpha: CGFloat, size: CGSize) -> SKTexture {
        ProceduralTextures.render(size: size, opaque: false) { ctx, size in
            let colors = [SKColor(white: 1, alpha: topAlpha).cgColor, SKColor(white: 1, alpha: bottomAlpha).cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: size.height), options: [])
        }
    }

    private struct SkinSwatchPalette {
        let cloak: SKColor
        let trim: SKColor
        let core: SKColor
    }

    /// Mirrors PlayerController's private `palette(for:)` RGB values exactly, so the shop's preview
    /// swatch actually matches what the skin looks like in-game. PlayerController's copy is private
    /// (by design — it's an implementation detail of the player sprite), so this is a manually
    /// synced duplicate rather than a shared call; if PlayerController's palette ever changes, this
    /// one needs to change with it.
    private static func skinSwatchPalette(for kind: PlayerSkinKind) -> SkinSwatchPalette {
        switch kind {
        case .nightCloak:
            return SkinSwatchPalette(cloak: SKColor(red: 0.16, green: 0.08, blue: 0.24, alpha: 1),
                                      trim: SKColor(red: 0.78, green: 0.1, blue: 0.16, alpha: 0.85),
                                      core: SKColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 0.9))
        case .crimsonFang:
            return SkinSwatchPalette(cloak: SKColor(red: 0.06, green: 0.02, blue: 0.03, alpha: 1),
                                      trim: SKColor(red: 0.85, green: 0.08, blue: 0.14, alpha: 0.95),
                                      core: SKColor(red: 1.0, green: 0.8, blue: 0.25, alpha: 0.95))
        case .moonlitVeil:
            return SkinSwatchPalette(cloak: SKColor(red: 0.62, green: 0.63, blue: 0.72, alpha: 1),
                                      trim: SKColor(red: 0.35, green: 0.85, blue: 0.95, alpha: 0.9),
                                      core: SKColor(red: 0.9, green: 0.98, blue: 1.0, alpha: 0.95))
        case .voidReaper:
            return SkinSwatchPalette(cloak: SKColor(red: 0.03, green: 0.02, blue: 0.05, alpha: 1),
                                      trim: SKColor(red: 0.55, green: 0.2, blue: 0.85, alpha: 0.9),
                                      core: SKColor(red: 0.65, green: 0.25, blue: 0.95, alpha: 0.95))
        case .emberSovereign:
            return SkinSwatchPalette(cloak: SKColor(red: 0.32, green: 0.2, blue: 0.04, alpha: 1),
                                      trim: SKColor(red: 1.0, green: 0.95, blue: 0.75, alpha: 0.95),
                                      core: SKColor(red: 1.0, green: 0.98, blue: 0.9, alpha: 1))
        }
    }

    /// Small circular preview badge: cloak-colored fill, trim-colored ring, a soft core-colored glow
    /// at the center — a simplified stand-in for the full hooded silhouette PlayerController draws,
    /// using the exact same three colors so the shop preview reads as "the same look".
    private static func skinSwatchTexture(cloak: SKColor, trim: SKColor, core: SKColor, diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            ctx.setFillColor(cloak.cgColor)
            ctx.fillEllipse(in: rect)
            ctx.setStrokeColor(trim.cgColor)
            ctx.setLineWidth(2.4)
            ctx.strokeEllipse(in: rect.insetBy(dx: 1, dy: 1))

            let coreCenter = CGPoint(x: rect.midX, y: rect.midY)
            let coreRadius = size.width * 0.16
            let glowColors = [core.withAlphaComponent(0.85).cgColor, core.withAlphaComponent(0).cgColor] as CFArray
            if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1]) {
                ctx.drawRadialGradient(glow, startCenter: coreCenter, startRadius: 0, endCenter: coreCenter, endRadius: coreRadius * 2.2, options: [])
            }
            ctx.setFillColor(core.cgColor)
            ctx.fillEllipse(in: CGRect(x: coreCenter.x - coreRadius / 2, y: coreCenter.y - coreRadius / 2, width: coreRadius, height: coreRadius))
        }
    }

    /// Small vial glyph tinted by a single color — deliberately reuses only `Potion.accentColor(for:)`
    /// (the same per-kind color already established for in-run pickups) rather than inventing a new
    /// palette, so the shop's starting-potion picker stays visually consistent with what you find
    /// mid-run.
    private static func potionIconTexture(color: SKColor, diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let glowColors = [color.withAlphaComponent(0.55).cgColor, color.withAlphaComponent(0).cgColor] as CFArray
            if let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: glowColors, locations: [0, 1]) {
                ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width * 0.48, options: [])
            }
            let bulbRect = CGRect(x: center.x - size.width * 0.20, y: center.y - size.height * 0.30,
                                   width: size.width * 0.40, height: size.height * 0.46)
            ctx.setFillColor(color.withAlphaComponent(0.92).cgColor)
            ctx.fillEllipse(in: bulbRect)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1.4)
            ctx.strokeEllipse(in: bulbRect)

            let neckRect = CGRect(x: center.x - size.width * 0.07, y: bulbRect.maxY - 1,
                                   width: size.width * 0.14, height: size.height * 0.16)
            ctx.setFillColor(SKColor(white: 0.85, alpha: 0.9).cgColor)
            ctx.fill(neckRect)
            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(neckRect)
        }
    }

    private static func coinTexture(diameter: CGFloat) -> SKTexture {
        let size = CGSize(width: diameter, height: diameter)
        return ProceduralTextures.render(size: size) { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let colors = [Palette.emberBright.cgColor, Palette.ember.cgColor] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) else { return }
            ctx.saveGState()
            ctx.addEllipse(in: rect)
            ctx.clip()
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: rect.midX, y: rect.midY), startRadius: 0,
                                    endCenter: CGPoint(x: rect.midX, y: rect.midY), endRadius: rect.width / 2, options: [])
            ctx.restoreGState()
            ctx.setStrokeColor(SKColor(red: 0.55, green: 0.22, blue: 0.06, alpha: 1).cgColor)
            ctx.setLineWidth(1.4)
            ctx.strokeEllipse(in: rect.insetBy(dx: 1.5, dy: 1.5))
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
        // parent and keep `label.position == shape.position` in sync (see layout()/layoutShopPanel()).
        // Nesting here would double-offset the label once the caller also repositions it directly.
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

    private static func measureWidth(_ text: String, fontName: String, fontSize: CGFloat) -> CGFloat {
        let label = SKLabelNode(fontNamed: fontName)
        label.text = text
        label.fontSize = fontSize
        return label.frame.width
    }
}
