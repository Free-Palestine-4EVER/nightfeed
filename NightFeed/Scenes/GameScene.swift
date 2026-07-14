import SpriteKit

/// The run itself. Owns every gameplay system and drives them in a fixed per-frame order, owns the
/// camera-follow, the HUD, the level-up / revive / pause overlays, and the transition into GameOverScene.
///
/// Layering: `worldLayer` holds everything in world space (ground, player, enemies, projectiles, weapon
/// visuals) and is what JuiceEffects.shake actually displaces. `cameraNode` tracks the player's world
/// position every frame; `hudLayer`/`overlayLayer` are children of the camera, so they are effectively
/// screen-space and never move relative to the device screen. Collision is NOT SpriteKit-physics-based —
/// every system does its own distance/spatial-grid checks (see GameConstants.swift).
final class GameScene: SKScene {

    static func newScene() -> GameScene {
        let scene = GameScene(size: CGSize(width: 393, height: 852))
        scene.scaleMode = .resizeFill
        return scene
    }

    // MARK: - Palette (matches MenuScene/GameOverScene)

    private enum Palette {
        static let groundBase = SKColor(red: 0.05, green: 0.03, blue: 0.075, alpha: 1)
        static let groundLine = SKColor(red: 0.11, green: 0.06, blue: 0.15, alpha: 1)
        static let violet = SKColor(red: 0.55, green: 0.12, blue: 0.66, alpha: 1)
        static let ember = SKColor(red: 1.0, green: 0.45, blue: 0.16, alpha: 1)
        static let emberBright = SKColor(red: 1.0, green: 0.66, blue: 0.28, alpha: 1)
        static let moonlight = SKColor(red: 0.93, green: 0.91, blue: 1.0, alpha: 1)
        static let blood = SKColor(red: 0.80, green: 0.10, blue: 0.18, alpha: 1)
        static let panelFill = SKColor(red: 0.08, green: 0.045, blue: 0.12, alpha: 0.93)
        static let panelStroke = SKColor(red: 0.52, green: 0.24, blue: 0.58, alpha: 0.55)
        static let healthGreen = SKColor(red: 0.35, green: 0.85, blue: 0.4, alpha: 1)
        static let healthAmber = SKColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 1)
        static let healthRed = SKColor(red: 0.88, green: 0.16, blue: 0.2, alpha: 1)
        static let xpFill = SKColor(red: 0.55, green: 0.85, blue: 1.0, alpha: 1)
    }

    // MARK: - Layers

    private let worldLayer = SKNode()
    private let hudLayer = SKNode()
    private let overlayLayer = SKNode()
    private var cameraNode: SKCameraNode!

    // MARK: - Systems

    private var player: PlayerController!
    private var weaponSystem: WeaponSystem!
    private var enemySpawner: EnemySpawner!
    private var xpSystem: XPSystem!
    private var upgradeManager: UpgradeManager!
    private var joystick: VirtualJoystick!
    private var pets: [PetCompanion] = []
    private var potionSystem: PotionSystem!

    // MARK: - Run state

    private var runStartTime: TimeInterval = 0
    private var lastUpdateTime: TimeInterval = 0
    private var hasStartedClock = false
    private var isPausedByMenu = false
    private var isShowingUpgradeOverlay = false
    private var isShowingRevivePrompt = false
    private var isGameOver = false
    private var accumulatedEnemyGold = 0
    /// Whether the joystick currently owns the one active touch. Multi-touch is disabled on the
    /// hosting SKView (see GameRootView), so at most one physical touch can ever exist — this flag,
    /// not UITouch object identity, is the single source of truth for joystick ownership.
    private var isJoystickTracking = false
    private var hasBuiltHUD = false
    /// When any modal overlay first became active, for the recovery watchdog below. nil whenever none is showing.
    private var modalStuckSince: TimeInterval?
    /// "Undying Oath" meta upgrade: free automatic revives left this run, consumed in beginDeathSequence.
    private var freeRevivesRemaining = 0

    private static let maxFrameDelta: TimeInterval = 1.0 / 15.0
    private static let movementZoneXFraction: CGFloat = 0.62   // left 62% of the screen...
    private static let movementZoneYFraction: CGFloat = 0.48   // ...or bottom 48% counts as the joystick zone
    private static let modalWatchdogTimeout: TimeInterval = 60

    // MARK: - HUD nodes

    private var healthTrack: SKShapeNode!
    private var healthFill: SKShapeNode!
    private var healthLabel: SKLabelNode!
    private var xpTrack: SKShapeNode!
    private var xpFill: SKShapeNode!
    private var levelBadge: SKLabelNode!
    private var timerLabel: SKLabelNode!
    private var killLabel: SKLabelNode!
    private var pauseButton: SKShapeNode!

    private static let healthBarWidth: CGFloat = 190
    private static let xpBarWidth: CGFloat = 240

    // MARK: - Overlays (transient)

    private var levelUpOverlay: LevelUpOverlay?
    private var pendingUpgradeChoices: [UpgradeChoice] = []
    private var revivePromptNode: SKNode?
    private var pauseMenuNode: SKNode?
    private var miniBossBanner: SKNode?
    private var potionBanner: SKNode?

    // MARK: - Lifecycle

    override func didMove(to view: SKView) {
        backgroundColor = Palette.groundBase

        addChild(worldLayer)
        cameraNode = SKCameraNode()
        addChild(cameraNode)
        camera = cameraNode
        cameraNode.addChild(hudLayer)
        cameraNode.addChild(overlayLayer)
        hudLayer.zPosition = ZPosition.hud
        overlayLayer.zPosition = ZPosition.levelUpOverlay

        buildGroundTileMap()

        player = PlayerController.makeNode()
        player.applyMetaLoadout(MetaProgressionStore.shared.currentLoadout())
        player.position = .zero
        worldLayer.addChild(player)
        cameraNode.position = .zero

        // Every pooled entity (enemies/projectiles/gems/damage labels/hit emitters) is rebuilt fresh
        // against THIS run's worldLayer — see PoolManager.prewarm's doc comment for why that matters.
        PoolManager.shared.prewarm(worldLayer: worldLayer)

        weaponSystem = WeaponSystem(player: player, worldLayer: worldLayer)
        enemySpawner = EnemySpawner(worldLayer: worldLayer, player: player)
        xpSystem = XPSystem(worldLayer: worldLayer, player: player)
        upgradeManager = UpgradeManager(weaponSystem: weaponSystem, player: player)
        wireSystemCallbacks()

        // Starting kit: one weapon already in hand so the opening seconds aren't helpless.
        weaponSystem.acquire(.fangBolt)

        // "First Strike" meta upgrade: the starting weapon begins two levels ahead.
        if MetaProgressionStore.shared.tier(for: .weaponMastery) > 0 {
            weaponSystem.levelUp(.fangBolt)
            weaponSystem.levelUp(.fangBolt)
        }

        // "Blood Ritual" meta upgrade: free levels (with their upgrade-choice cards) right at run start.
        let headStartLevels = MetaProgressionStore.shared.tier(for: .headStart)
        if headStartLevels > 0 { xpSystem.grantBonusLevels(headStartLevels) }

        // "Undying Oath" meta upgrade: free automatic revives this run.
        freeRevivesRemaining = MetaProgressionStore.shared.tier(for: .reviveCharge)

        // "Potion Mastery" meta upgrade: chosen potion buffs already active from the first frame.
        for kind in MetaProgressionStore.shared.selectedStartingPotions() {
            player.applyPotionBuff(kind, now: 0)
        }

        // Familiars: whichever pet(s) are owned + currently selected (1 normally, 2 with the "Second
        // Familiar" meta upgrade) join the run — see MetaProgressionStore.activePetKinds().
        for (index, kind) in MetaProgressionStore.shared.activePetKinds().enumerated() {
            let companion = PetCompanion.makeNode(kind: kind, slotIndex: index)
            companion.position = player.position
            worldLayer.addChild(companion)
            pets.append(companion)
        }

        potionSystem = PotionSystem(worldLayer: worldLayer, player: player)
        potionSystem.onPotionCollected = { [weak self] kind in
            guard let self else { return }
            switch kind {
            case .voidMagnet: self.xpSystem.collectAllGems()
            case .risingMoon: self.xpSystem.grantBonusLevels(1)
            default: self.player.applyPotionBuff(kind, now: self.lastUpdateTime)
            }
            self.showPotionBanner(kind)
        }

        joystick = VirtualJoystick.make()
        hudLayer.addChild(joystick)

        buildHUD()
        hasBuiltHUD = true
        layoutHUD(size: size)

        AudioManager.shared.startMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // SpriteKit can fire didChangeSize as part of initial presentation, before didMove(to:) has run
        // buildHUD() — the HUD nodes layoutHUD touches are implicitly-unwrapped optionals, so guard here
        // the same way MenuScene/GameOverScene guard their own didChangeSize against building too early.
        guard hasBuiltHUD else { return }
        layoutHUD(size: size)
    }

    /// A kill is resolved in three steps, in this exact order: read the loot off the enemy (XP + a gold
    /// bonus on top of the run-summary formula), THEN hand it to EnemySpawner.registerDefeat, which is
    /// what actually retires the node back to the pool. Shared by WeaponSystem's kills and the pet's.
    private func handleEnemyDefeated(_ enemy: Enemy) {
        xpSystem.dropGem(xpValue: enemy.xpValue, at: enemy.position)
        accumulatedEnemyGold += enemy.goldValue
        enemySpawner.registerDefeat(enemy)
    }

    private func wireSystemCallbacks() {
        weaponSystem.onEnemyDefeated = { [weak self] enemy in
            self?.handleEnemyDefeated(enemy)
        }

        // WeaponSystem asks for shake via a closure (it owns no camera reference) — GameScene re-drives
        // cameraNode.position every frame, so shaking the camera itself would just be overwritten; the
        // correct target is worldLayer (the same node EnemySpawner/XPSystem already shake directly).
        weaponSystem.onShakeRequest = { [weak self] magnitude, duration in
            guard let self else { return }
            JuiceEffects.shake(node: self.worldLayer, magnitude: magnitude, duration: duration)
        }

        enemySpawner.onMiniBossSpawned = { [weak self] in
            self?.showMiniBossWarning()
        }

        xpSystem.onLevelUp = { [weak self] in
            self?.presentUpgradeChoices()
        }
    }

    // MARK: - Ground

    private func buildGroundTileMap() {
        let tileSize = CGSize(width: WorldConfig.backgroundTileSize, height: WorldConfig.backgroundTileSize)
        let texture = Self.groundTileTexture(size: tileSize)
        let definition = SKTileDefinition(texture: texture, size: tileSize)
        let group = SKTileGroup(tileDefinition: definition)
        let tileSet = SKTileSet(tileGroups: [group])

        let columns = Int(ceil(WorldConfig.bounds.width / tileSize.width)) + 1
        let rows = Int(ceil(WorldConfig.bounds.height / tileSize.height)) + 1
        let map = SKTileMapNode(tileSet: tileSet, columns: columns, rows: rows, tileSize: tileSize)
        map.fill(with: group)
        map.position = .zero
        map.zPosition = ZPosition.background
        worldLayer.addChild(map)

        // Faint arena-edge marker so the player can feel the bounds coming without a hard wall.
        let border = SKShapeNode(rect: WorldConfig.bounds.insetBy(dx: 6, dy: 6), cornerRadius: 24)
        border.strokeColor = Palette.violet.withAlphaComponent(0.35)
        border.lineWidth = 6
        border.fillColor = .clear
        border.zPosition = ZPosition.groundDecor
        worldLayer.addChild(border)
    }

    private static func groundTileTexture(size: CGSize) -> SKTexture {
        ProceduralTextures.render(size: size, opaque: true) { ctx, size in
            ctx.setFillColor(Palette.groundBase.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))

            ctx.setStrokeColor(Palette.groundLine.cgColor)
            ctx.setLineWidth(1)
            ctx.stroke(CGRect(origin: .zero, size: size).insetBy(dx: 0.5, dy: 0.5))

            var seed: UInt64 = 424242
            func rnd() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1
                return CGFloat((seed >> 33) & 0xFFFFFF) / CGFloat(0xFFFFFF)
            }
            for _ in 0..<5 {
                let r = 1.2 + rnd() * 2.2
                let x = rnd() * size.width
                let y = rnd() * size.height
                ctx.setFillColor(SKColor(red: 0.16, green: 0.09, blue: 0.2, alpha: 0.5).cgColor)
                ctx.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            }
        }
    }

    // MARK: - Update loop

    override func update(_ currentTime: TimeInterval) {
        if !hasStartedClock {
            hasStartedClock = true
            runStartTime = currentTime
            lastUpdateTime = currentTime
        }
        let rawDelta = currentTime - lastUpdateTime
        lastUpdateTime = currentTime

        // Self-heal every frame: if a modal flag is set but its overlay node isn't actually on screen
        // (parent == nil), the state desynced somewhere — clear the flag rather than leave input
        // (the joystick included, since it's gated by these same flags) blocked forever.
        if isShowingUpgradeOverlay && levelUpOverlay?.parent == nil { isShowingUpgradeOverlay = false }
        if isShowingRevivePrompt && revivePromptNode?.parent == nil { isShowingRevivePrompt = false }
        if isPausedByMenu && pauseMenuNode?.parent == nil { isPausedByMenu = false }

        // Self-heal for the joystick too: our flag and the node's own isDragging must always agree.
        // Should be unreachable given how beginDrag()/endDrag() are called below, but costs nothing
        // to guarantee instead of assume.
        if isJoystickTracking != joystick.isDragging {
            joystick.endDrag()
            isJoystickTracking = false
        }

        // Hard watchdog, layered on top of the check above: covers a desync that check can't see (the
        // node is present and correctly parented, but something upstream — most plausibly an ad SDK's
        // window/view hierarchy not fully releasing control after present/dismiss — is silently
        // swallowing every touch before it ever reaches this scene). Generous enough to never interrupt
        // a real player actually reading the cards, but guarantees the run recovers on its own instead
        // of being stuck until the app is force-quit.
        let anyModalShowing = isShowingUpgradeOverlay || isShowingRevivePrompt || isPausedByMenu
        if anyModalShowing {
            if modalStuckSince == nil { modalStuckSince = currentTime }
            if currentTime - modalStuckSince! > Self.modalWatchdogTimeout {
                forceRecoverFromStuckModal(currentTime: currentTime)
            }
        } else {
            modalStuckSince = nil
        }

        guard !isPausedByMenu, !isShowingUpgradeOverlay, !isShowingRevivePrompt, !isGameOver else { return }

        let deltaTime = min(rawDelta, Self.maxFrameDelta)
        let runTime = currentTime - runStartTime

        player.move(direction: joystick.currentVector, deltaTime: deltaTime)
        player.applyPassiveRegen(deltaTime: deltaTime)
        player.updateBuffs(now: currentTime)
        cameraNode.position = player.position

        enemySpawner.update(deltaTime: deltaTime, now: currentTime, runTime: runTime,
                             cameraPosition: cameraNode.position, viewSize: size)
        weaponSystem.update(deltaTime: deltaTime, now: currentTime)
        if !pets.isEmpty {
            let activeEnemies = PoolManager.shared.activeEnemies
            for companion in pets {
                companion.update(deltaTime: deltaTime, now: currentTime, playerPosition: player.position, player: player,
                                  enemies: activeEnemies, worldLayer: worldLayer) { [weak self] enemy in
                    self?.handleEnemyDefeated(enemy)
                }
            }
        }
        xpSystem.update(deltaTime: deltaTime, playerPosition: player.position)
        potionSystem.update(deltaTime: deltaTime, now: currentTime, playerPosition: player.position)

        refreshHUD(runTime: runTime)

        if player.isDead {
            beginDeathSequence(now: currentTime, runTime: runTime)
        }
    }

    // MARK: - HUD

    private func buildHUD() {
        healthTrack = SKShapeNode(rectOf: CGSize(width: Self.healthBarWidth, height: 16), cornerRadius: 6)
        healthTrack.fillColor = SKColor.black.withAlphaComponent(0.55)
        healthTrack.strokeColor = Palette.panelStroke
        healthTrack.lineWidth = 1.5
        hudLayer.addChild(healthTrack)

        healthFill = SKShapeNode(rectOf: CGSize(width: Self.healthBarWidth - 4, height: 12), cornerRadius: 5)
        healthFill.fillColor = Palette.healthGreen
        healthFill.strokeColor = .clear
        healthFill.zPosition = 0.1
        healthTrack.addChild(healthFill)

        healthLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        healthLabel.fontSize = 11
        healthLabel.fontColor = .white
        healthLabel.verticalAlignmentMode = .center
        healthLabel.zPosition = 0.2
        healthTrack.addChild(healthLabel)

        xpTrack = SKShapeNode(rectOf: CGSize(width: Self.xpBarWidth, height: 8), cornerRadius: 4)
        xpTrack.fillColor = SKColor.black.withAlphaComponent(0.5)
        xpTrack.strokeColor = Palette.panelStroke
        xpTrack.lineWidth = 1
        hudLayer.addChild(xpTrack)

        xpFill = SKShapeNode(rectOf: CGSize(width: Self.xpBarWidth - 3, height: 5), cornerRadius: 2.5)
        xpFill.fillColor = Palette.xpFill
        xpFill.strokeColor = .clear
        xpFill.zPosition = 0.1
        xpTrack.addChild(xpFill)

        levelBadge = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        levelBadge.fontSize = 13
        levelBadge.fontColor = Palette.emberBright
        levelBadge.verticalAlignmentMode = .center
        hudLayer.addChild(levelBadge)

        timerLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
        timerLabel.fontSize = 18
        timerLabel.fontColor = Palette.moonlight
        timerLabel.horizontalAlignmentMode = .center
        hudLayer.addChild(timerLabel)

        killLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
        killLabel.fontSize = 13
        killLabel.fontColor = SKColor(white: 1, alpha: 0.75)
        killLabel.horizontalAlignmentMode = .center
        hudLayer.addChild(killLabel)

        pauseButton = SKShapeNode(circleOfRadius: 18)
        pauseButton.name = "pauseButton"
        pauseButton.fillColor = SKColor.black.withAlphaComponent(0.45)
        pauseButton.strokeColor = Palette.panelStroke
        pauseButton.lineWidth = 1.5
        let bar1 = SKShapeNode(rectOf: CGSize(width: 3.5, height: 12), cornerRadius: 1.5)
        bar1.name = "pauseButton"
        bar1.fillColor = .white
        bar1.strokeColor = .clear
        bar1.position = CGPoint(x: -4, y: 0)
        pauseButton.addChild(bar1)
        let bar2 = SKShapeNode(rectOf: CGSize(width: 3.5, height: 12), cornerRadius: 1.5)
        bar2.name = "pauseButton"
        bar2.fillColor = .white
        bar2.strokeColor = .clear
        bar2.position = CGPoint(x: 4, y: 0)
        pauseButton.addChild(bar2)
        hudLayer.addChild(pauseButton)
    }

    private func layoutHUD(size: CGSize) {
        // Top clearance generous enough to clear the Dynamic Island / notch cutout on every iPhone size —
        // the scene renders edge-to-edge with the status bar hidden, so nothing else reserves that space.
        let topRow: CGFloat = size.height / 2 - 54
        let healthRow: CGFloat = topRow - 30
        let killRow: CGFloat = healthRow - 22

        xpTrack.position = CGPoint(x: 0, y: topRow)
        levelBadge.position = CGPoint(x: -Self.xpBarWidth / 2 - 24, y: topRow)
        pauseButton.position = CGPoint(x: size.width / 2 - 32, y: topRow)

        healthTrack.position = CGPoint(x: -size.width / 2 + Self.healthBarWidth / 2 + 20, y: healthRow)
        healthLabel.position = .zero
        timerLabel.position = CGPoint(x: 0, y: healthRow)
        killLabel.position = CGPoint(x: 0, y: killRow)

        // Fixed bottom-left anchor, comfortably clear of the home indicator / thumb-reachable, and well
        // clear of every other HUD element (all of which live in the top half).
        joystick.place(at: CGPoint(x: -size.width / 2 + 110, y: -size.height / 2 + 140))
    }

    private func refreshHUD(runTime: TimeInterval) {
        let healthFraction = max(0, min(1, player.currentHealth / max(1, player.maxHealth)))
        healthFill.xScale = max(0.001, healthFraction)
        healthFill.position = CGPoint(x: -(Self.healthBarWidth - 4) / 2 * (1 - healthFraction), y: 0)
        healthFill.fillColor = healthFraction > 0.5 ? Palette.healthGreen : (healthFraction > 0.22 ? Palette.healthAmber : Palette.healthRed)
        healthLabel.text = "\(max(0, Int(player.currentHealth.rounded())))/\(Int(player.maxHealth.rounded()))"

        let xpFraction = max(0, min(1, xpSystem.progressFraction))
        xpFill.xScale = max(0.001, xpFraction)
        xpFill.position = CGPoint(x: -(Self.xpBarWidth - 3) / 2 * (1 - xpFraction), y: 0)
        levelBadge.text = "Lv \(xpSystem.currentLevel)"

        timerLabel.text = Self.formatTime(runTime)
        killLabel.text = "\(enemySpawner.totalKills) kills"
    }

    private static func formatTime(_ time: TimeInterval) -> String {
        let total = max(0, Int(time))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    // MARK: - Mini-boss warning banner

    private func showMiniBossWarning() {
        miniBossBanner?.removeFromParent()
        let node = SKNode()
        node.zPosition = ZPosition.hud + 1
        node.alpha = 0

        let bg = SKShapeNode(rectOf: CGSize(width: 260, height: 40), cornerRadius: 10)
        bg.fillColor = Palette.blood.withAlphaComponent(0.85)
        bg.strokeColor = Palette.emberBright
        bg.lineWidth = 1.5
        node.addChild(bg)

        let label = SKLabelNode(text: "⚠ THE NIGHTMAW STIRS ⚠")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 15
        label.fontColor = .white
        label.verticalAlignmentMode = .center
        node.addChild(label)

        node.position = CGPoint(x: 0, y: size.height * 0.18)
        hudLayer.addChild(node)
        miniBossBanner = node

        node.setScale(0.85)
        node.run(SKAction.sequence([
            SKAction.group([SKAction.fadeIn(withDuration: 0.2), SKAction.scale(to: 1.0, duration: 0.22)]),
            SKAction.wait(forDuration: 2.2),
            SKAction.fadeOut(withDuration: 0.4),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Potion pickup banner

    /// A brief, unmissable callout naming exactly what was just picked up — potions are rare and their
    /// effect isn't otherwise obvious mid-combat, so this exists purely for clarity, not juice.
    private func showPotionBanner(_ kind: PotionKind) {
        potionBanner?.removeFromParent()
        let node = SKNode()
        node.zPosition = ZPosition.hud + 1
        node.alpha = 0
        node.setScale(0.85)

        let color = Potion.accentColor(for: kind)
        let bg = SKShapeNode(rectOf: CGSize(width: 280, height: 44), cornerRadius: 12)
        bg.fillColor = SKColor.black.withAlphaComponent(0.82)
        bg.strokeColor = color
        bg.lineWidth = 2
        bg.glowWidth = 2
        node.addChild(bg)

        let label = SKLabelNode(text: "✦ \(kind.displayName.uppercased()) ✦")
        label.fontName = "AvenirNext-Heavy"
        label.fontSize = 16
        label.fontColor = color
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: 7)
        node.addChild(label)

        let sub = SKLabelNode(text: kind.flavorText)
        sub.fontName = "AvenirNext-Medium"
        sub.fontSize = 11
        sub.fontColor = SKColor(white: 1, alpha: 0.75)
        sub.verticalAlignmentMode = .center
        sub.preferredMaxLayoutWidth = 256
        sub.numberOfLines = 1
        sub.lineBreakMode = .byTruncatingTail
        sub.position = CGPoint(x: 0, y: -11)
        node.addChild(sub)

        node.position = CGPoint(x: 0, y: size.height * 0.30)
        hudLayer.addChild(node)
        potionBanner = node

        node.run(SKAction.sequence([
            SKAction.group([SKAction.fadeIn(withDuration: 0.15), SKAction.scale(to: 1.0, duration: 0.15)]),
            SKAction.wait(forDuration: 1.8),
            SKAction.fadeOut(withDuration: 0.35),
            SKAction.removeFromParent()
        ]))
    }

    // MARK: - Level-up overlay

    /// XPSystem.onLevelUp can fire more than once in the same frame (a single big XP gain crossing
    /// multiple level thresholds at once — very possible from a Nightmaw's 60-XP gem). Presenting a
    /// second overlay while the first is still showing used to stack two overlapping, identically-named
    /// card overlays and permanently leak the first one into overlayLayer. Extra level-ups now queue and
    /// present one at a time instead.
    private var queuedLevelUps = 0

    private func presentUpgradeChoices() {
        queuedLevelUps += 1
        presentNextQueuedUpgradeIfNeeded()
    }

    private func presentNextQueuedUpgradeIfNeeded() {
        guard !isShowingUpgradeOverlay, queuedLevelUps > 0 else { return }
        queuedLevelUps -= 1
        isShowingUpgradeOverlay = true
        // "Third Eye" meta upgrade: +1 upgrade card offered per tier.
        let choiceCount = 3 + MetaProgressionStore.shared.tier(for: .extraChoices)
        let choices = upgradeManager.rollChoices(count: choiceCount)
        guard !choices.isEmpty else {
            // Nothing eligible at all (fully maxed roster) — nothing to show; try the next queued
            // level-up (if any), since a maxed roster now will still be maxed for the rest of the run.
            isShowingUpgradeOverlay = false
            presentNextQueuedUpgradeIfNeeded()
            return
        }
        pendingUpgradeChoices = choices
        let overlay = LevelUpOverlay.make(choices: choices, screenSize: size)
        overlayLayer.addChild(overlay)
        levelUpOverlay = overlay
        AudioManager.shared.hapticImpact(.medium)
    }

    private func selectUpgrade(index: Int) {
        guard isShowingUpgradeOverlay, let overlay = levelUpOverlay, index >= 0, index < pendingUpgradeChoices.count else { return }
        let choice = pendingUpgradeChoices[index]

        // Clear the "there's a live overlay to tap" state immediately, before the dismiss animation
        // even starts. A fast double-tap on a card (or a second card) landing during the ~0.16s fade
        // used to re-enter this method — levelUpOverlay being nil now makes the guard above reject
        // that re-entry outright, instead of double-applying the choice and double-firing the
        // completion closure below (which was desyncing isShowingUpgradeOverlay from reality and
        // silently swallowing all further input, joystick included).
        levelUpOverlay = nil
        pendingUpgradeChoices = []

        overlay.flashSelected(index: index)
        upgradeManager.apply(choice)
        AudioManager.shared.playSFX(.buttonTap)

        overlay.dismiss { [weak self] in
            guard let self else { return }
            self.isShowingUpgradeOverlay = false
            self.presentNextQueuedUpgradeIfNeeded()
        }
    }

    // MARK: - Death / revive / game over

    private func beginDeathSequence(now: TimeInterval, runTime: TimeInterval) {
        guard !isShowingRevivePrompt, !isGameOver else { return }

        // "Undying Oath" meta upgrade: free automatic revives, no ad required. Consumed before ever
        // showing the ad-gated prompt below.
        if freeRevivesRemaining > 0 {
            freeRevivesRemaining -= 1
            player.reviveWithHalfHealth(now: now)
            AudioManager.shared.playSFX(.revive)
            AudioManager.shared.hapticNotification(.success)
            JuiceEffects.hitBurst(at: player.position, color: Palette.emberBright, scale: 2.0)
            return
        }

        // A pre-banked Auto-Revive charge (watched 1 ad from the menu, 20 min cooldown between banks —
        // see MetaProgressionStore) also auto-triggers instantly, no in-the-moment ad required.
        if MetaProgressionStore.shared.consumeAutoRevive() {
            player.reviveWithHalfHealth(now: now)
            AudioManager.shared.playSFX(.revive)
            AudioManager.shared.hapticNotification(.success)
            JuiceEffects.hitBurst(at: player.position, color: Palette.moonlight, scale: 2.0)
            return
        }

        isShowingRevivePrompt = true
        presentRevivePrompt(runTime: runTime)
    }

    private func presentRevivePrompt(runTime: TimeInterval) {
        let node = SKNode()
        node.zPosition = ZPosition.levelUpOverlay

        let dim = SKShapeNode(rectOf: CGSize(width: size.width * 1.6, height: size.height * 1.6))
        dim.fillColor = SKColor.black.withAlphaComponent(0.8)
        dim.strokeColor = .clear
        dim.alpha = 0
        node.addChild(dim)

        let title = SKLabelNode(text: "YOU HAVE FALLEN")
        title.fontName = "AvenirNext-Heavy"
        title.fontSize = 26
        title.fontColor = Palette.blood
        title.position = CGPoint(x: 0, y: 90)
        node.addChild(title)

        let reviveButton = SKShapeNode(rectOf: CGSize(width: 260, height: 56), cornerRadius: 14)
        reviveButton.name = "reviveButton"
        reviveButton.fillColor = Palette.ember
        reviveButton.strokeColor = Palette.emberBright
        reviveButton.lineWidth = 2
        reviveButton.position = CGPoint(x: 0, y: 10)
        node.addChild(reviveButton)

        let reviveLabel = SKLabelNode(text: "▶ WATCH AD TO REVIVE")
        reviveLabel.name = "reviveButton"
        reviveLabel.fontName = "AvenirNext-Bold"
        reviveLabel.fontSize = 16
        reviveLabel.fontColor = .black
        reviveLabel.verticalAlignmentMode = .center
        reviveLabel.position = reviveButton.position
        node.addChild(reviveLabel)

        let declineButton = SKShapeNode(rectOf: CGSize(width: 200, height: 40), cornerRadius: 10)
        declineButton.name = "declineReviveButton"
        declineButton.fillColor = SKColor.black.withAlphaComponent(0.4)
        declineButton.strokeColor = Palette.panelStroke
        declineButton.lineWidth = 1.5
        declineButton.position = CGPoint(x: 0, y: -48)
        node.addChild(declineButton)

        let declineLabel = SKLabelNode(text: "No thanks")
        declineLabel.name = "declineReviveButton"
        declineLabel.fontName = "AvenirNext-Medium"
        declineLabel.fontSize = 14
        declineLabel.fontColor = SKColor(white: 1, alpha: 0.8)
        declineLabel.verticalAlignmentMode = .center
        declineLabel.position = declineButton.position
        node.addChild(declineLabel)

        overlayLayer.addChild(node)
        revivePromptNode = node

        // Dim fades in as a flat backdrop; title and both buttons pop in staggered on top of it —
        // this used to be a single flat whole-node fade with zero motion for a screen meant to land
        // with real weight ("YOU HAVE FALLEN").
        dim.run(SKAction.fadeIn(withDuration: 0.25))
        JuiceEffects.popIn(title, delay: 0.04, distance: 16)
        JuiceEffects.popIn(reviveButton, delay: 0.12)
        JuiceEffects.popIn(reviveLabel, delay: 0.12)
        JuiceEffects.popIn(declineButton, delay: 0.2, distance: 8)
        JuiceEffects.popIn(declineLabel, delay: 0.2, distance: 8)

        // Auto-decline after a countdown so a dead run never hangs waiting on the player.
        node.run(SKAction.sequence([
            SKAction.wait(forDuration: 6.0),
            SKAction.run { [weak self] in self?.declineRevive(runTime: runTime) }
        ]), withKey: "reviveTimeout")
    }

    private func acceptRevive(runTime: TimeInterval) {
        revivePromptNode?.removeAction(forKey: "reviveTimeout")

        // Safety net: if the ad SDK's completion callback never fires (a real, if rare, SDK edge case),
        // isShowingRevivePrompt would otherwise stay true forever — and since GameScene.update() gates
        // its entire body on that flag, the whole run would freeze permanently, not just the joystick.
        // This guarantees the prompt always resolves one way or another within a bounded time.
        revivePromptNode?.run(SKAction.sequence([
            SKAction.wait(forDuration: 20.0),
            SKAction.run { [weak self] in self?.declineRevive(runTime: runTime) }
        ]), withKey: "adWatchTimeout")

        AdsManager.shared.showRewarded { [weak self] earned in
            // If the timeout above already resolved this (or a duplicate callback arrives late),
            // isShowingRevivePrompt is already false — ignore the stale callback rather than reviving
            // into a run that has already ended.
            guard let self, self.isShowingRevivePrompt else { return }
            self.revivePromptNode?.removeAction(forKey: "adWatchTimeout")
            if earned {
                self.player.reviveWithHalfHealth(now: self.lastUpdateTime)
                AudioManager.shared.playSFX(.revive)
                AudioManager.shared.hapticNotification(.success)
                self.dismissRevivePrompt()
                self.isShowingRevivePrompt = false
            } else {
                // Ad unavailable or declined mid-flow — fall through to game over.
                self.dismissRevivePrompt()
                self.declineRevive(runTime: runTime)
            }
        }
    }

    private func declineRevive(runTime: TimeInterval) {
        guard isShowingRevivePrompt else { return }
        revivePromptNode?.removeAction(forKey: "reviveTimeout")
        dismissRevivePrompt()
        isShowingRevivePrompt = false
        endRun(runTime: runTime)
    }

    private func dismissRevivePrompt() {
        revivePromptNode?.removeFromParent()
        revivePromptNode = nil
    }

    private func endRun(runTime: TimeInterval) {
        guard !isGameOver else { return }
        isGameOver = true

        let kills = enemySpawner.totalKills
        let miniBossKills = enemySpawner.miniBossKills
        let loadout = MetaProgressionStore.shared.currentLoadout()
        let baseGold = Balance.goldEarned(survivalTime: runTime, kills: kills, miniBossKills: miniBossKills)
        let totalGold = Int(CGFloat(baseGold + accumulatedEnemyGold) * loadout.goldGainMultiplier)

        MetaProgressionStore.shared.addGold(totalGold)
        MetaProgressionStore.shared.recordRunCompleted(survivalTime: runTime)
        AudioManager.shared.stopMusic()

        let gameOver = GameOverScene.newScene(survivalTime: runTime, kills: kills, miniBossKills: miniBossKills, goldEarned: totalGold)
        view?.presentScene(gameOver, transition: .fade(withDuration: 0.7))
    }

    // MARK: - Pause menu

    private func togglePauseMenu() {
        // pauseButton previously had zero tap feedback of any kind (unlike every other tappable
        // element in the game) — a quick overshoot bounce marks the tap without altering when/whether
        // the pause menu itself opens or closes below.
        JuiceEffects.releaseBounce(pauseButton)
        if isPausedByMenu {
            resumeFromPauseMenu()
        } else {
            isPausedByMenu = true
            AudioManager.shared.playSFX(.buttonTap)
            presentPauseMenu()
        }
    }

    private func presentPauseMenu() {
        let node = SKNode()
        node.zPosition = ZPosition.levelUpOverlay

        let dim = SKShapeNode(rectOf: CGSize(width: size.width * 1.6, height: size.height * 1.6))
        dim.fillColor = SKColor.black.withAlphaComponent(0.72)
        dim.strokeColor = .clear
        dim.alpha = 0
        node.addChild(dim)

        let title = SKLabelNode(text: "PAUSED")
        title.fontName = "AvenirNext-Heavy"
        title.fontSize = 26
        title.fontColor = Palette.moonlight
        title.position = CGPoint(x: 0, y: 70)
        node.addChild(title)

        let resumeButton = SKShapeNode(rectOf: CGSize(width: 220, height: 52), cornerRadius: 14)
        resumeButton.name = "resumeButton"
        resumeButton.fillColor = Palette.violet
        resumeButton.strokeColor = SKColor(white: 1, alpha: 0.4)
        resumeButton.lineWidth = 1.5
        resumeButton.position = CGPoint(x: 0, y: 0)
        node.addChild(resumeButton)

        let resumeLabel = SKLabelNode(text: "Resume")
        resumeLabel.name = "resumeButton"
        resumeLabel.fontName = "AvenirNext-Bold"
        resumeLabel.fontSize = 16
        resumeLabel.fontColor = .white
        resumeLabel.verticalAlignmentMode = .center
        resumeLabel.position = resumeButton.position
        node.addChild(resumeLabel)

        let quitButton = SKShapeNode(rectOf: CGSize(width: 220, height: 44), cornerRadius: 12)
        quitButton.name = "quitButton"
        quitButton.fillColor = SKColor.black.withAlphaComponent(0.4)
        quitButton.strokeColor = Palette.panelStroke
        quitButton.lineWidth = 1.5
        quitButton.position = CGPoint(x: 0, y: -62)
        node.addChild(quitButton)

        let quitLabel = SKLabelNode(text: "Quit to Menu")
        quitLabel.name = "quitButton"
        quitLabel.fontName = "AvenirNext-Medium"
        quitLabel.fontSize = 14
        quitLabel.fontColor = SKColor(white: 1, alpha: 0.85)
        quitLabel.verticalAlignmentMode = .center
        quitLabel.position = quitButton.position
        node.addChild(quitLabel)

        overlayLayer.addChild(node)
        pauseMenuNode = node

        // Dim fades in as a flat backdrop; the actual menu content pops in staggered on top of it —
        // this used to be a single flat whole-node fade with zero motion.
        dim.run(SKAction.fadeIn(withDuration: 0.18))
        JuiceEffects.popIn(title, delay: 0.03, distance: 12)
        JuiceEffects.popIn(resumeButton, delay: 0.08)
        JuiceEffects.popIn(resumeLabel, delay: 0.08)
        JuiceEffects.popIn(quitButton, delay: 0.13)
        JuiceEffects.popIn(quitLabel, delay: 0.13)
    }

    private func resumeFromPauseMenu() {
        isPausedByMenu = false
        AudioManager.shared.playSFX(.buttonTap)
        pauseMenuNode?.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.15), SKAction.removeFromParent()]))
        pauseMenuNode = nil
        // Re-baseline the clock so the paused interval isn't counted as elapsed run/frame time.
        hasStartedClock = false
    }

    private func quitToMenu() {
        AudioManager.shared.playSFX(.buttonTap)
        AudioManager.shared.stopMusic()
        view?.presentScene(MenuScene.newScene(), transition: .fade(withDuration: 0.5))
    }

    // MARK: - Stuck-modal recovery watchdog

    /// Last-resort recovery: tears down whichever modal has been showing continuously for longer than
    /// `modalWatchdogTimeout`, regardless of why it got stuck (an ad SDK not fully releasing touch
    /// delivery, some desync the lighter parent-nil check above didn't catch, or anything else). This
    /// exists purely so the run — and the joystick, since it's gated behind these same flags — can
    /// never be permanently unresponsive; a real player is never plausibly still deciding a minute later.
    private func forceRecoverFromStuckModal(currentTime: TimeInterval) {
        modalStuckSince = nil

        if isShowingUpgradeOverlay {
            levelUpOverlay?.removeFromParent()
            levelUpOverlay = nil
            pendingUpgradeChoices = []
            queuedLevelUps = 0
            isShowingUpgradeOverlay = false
        }

        if isShowingRevivePrompt {
            revivePromptNode?.removeAction(forKey: "reviveTimeout")
            revivePromptNode?.removeAction(forKey: "adWatchTimeout")
            revivePromptNode?.removeFromParent()
            revivePromptNode = nil
            let wasDead = player.isDead
            isShowingRevivePrompt = false
            // Treat an unresolved revive decision as declined so the run concludes cleanly rather than
            // leaving an ambiguous half-dead state — calling endRun directly since declineRevive's own
            // guard would now see isShowingRevivePrompt already false and no-op.
            if wasDead {
                endRun(runTime: currentTime - runStartTime)
            }
        }

        if isPausedByMenu {
            pauseMenuNode?.removeFromParent()
            pauseMenuNode = nil
            isPausedByMenu = false
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: self)

        if isShowingUpgradeOverlay {
            if let name = tappedName(at: location, in: overlayLayer), name.hasPrefix("upgradeCard_"),
               let index = Int(name.dropFirst("upgradeCard_".count)) {
                selectUpgrade(index: index)
            }
            return
        }

        if isShowingRevivePrompt {
            if let name = tappedName(at: location, in: overlayLayer) {
                if name == "reviveButton" {
                    AudioManager.shared.playSFX(.buttonTap)
                    acceptRevive(runTime: lastUpdateTime - runStartTime)
                } else if name == "declineReviveButton" {
                    AudioManager.shared.playSFX(.buttonTap)
                    declineRevive(runTime: lastUpdateTime - runStartTime)
                }
            }
            return
        }

        if isPausedByMenu {
            if let name = tappedName(at: location, in: overlayLayer) {
                if name == "resumeButton" {
                    resumeFromPauseMenu()
                } else if name == "quitButton" {
                    quitToMenu()
                }
            }
            return
        }

        if let name = tappedName(at: location, in: hudLayer), name == "pauseButton" {
            togglePauseMenu()
            return
        }

        if isInMovementZone(location) {
            joystick.beginDrag()
            joystick.updateDrag(touchLocation: touch.location(in: hudLayer))
            isJoystickTracking = true
        }
    }

    // Multi-touch is disabled on the hosting SKView (see GameRootView) — `touches.first` is always
    // THE touch, never one of several, so there is nothing to match against a stored reference here.
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isJoystickTracking, let touch = touches.first else { return }
        joystick.updateDrag(touchLocation: touch.location(in: hudLayer))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isJoystickTracking else { return }
        joystick.endDrag()
        isJoystickTracking = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isJoystickTracking else { return }
        joystick.endDrag()
        isJoystickTracking = false
    }

    private func tappedName(at sceneLocation: CGPoint, in layer: SKNode) -> String? {
        let localPoint = convert(sceneLocation, to: layer)
        for node in layer.nodes(at: localPoint) {
            if let name = node.name { return name }
        }
        return nil
    }

    private func isInMovementZone(_ sceneLocation: CGPoint) -> Bool {
        // Scene-space origin is the screen center, so "left half" / "bottom half" are both x/y < 0 checks
        // shifted by the configured fractions of the half-width/half-height.
        let leftBoundary = -size.width / 2 + size.width * Self.movementZoneXFraction
        let bottomBoundary = -size.height / 2 + size.height * Self.movementZoneYFraction
        return sceneLocation.x <= leftBoundary || sceneLocation.y <= bottomBoundary
    }
}
