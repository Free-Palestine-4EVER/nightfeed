import SpriteKit

/// The player's visual node plus its full combat/movement stat state. Not pooled (there is only ever
/// one), created once by GameScene via `makeNode()`. All derived stats (speed/damage/armor/crit/etc.)
/// are recomputed from scratch in `setPassiveLevel` on top of the meta-loadout baseline set once by
/// `applyMetaLoadout`, so passive stacking never drifts from double-application.
final class PlayerController: SKSpriteNode {

    // MARK: - Public state

    private(set) var currentHealth: CGFloat = PlayerConfig.baseMaxHealth
    private(set) var maxHealth: CGFloat = PlayerConfig.baseMaxHealth
    private(set) var isDead: Bool = false
    private(set) var moveSpeedMultiplier: CGFloat = 1.0
    private(set) var magnetRadius: CGFloat = PlayerConfig.baseMagnetRadius
    private(set) var armorFlat: CGFloat = 0
    private(set) var damageMultiplier: CGFloat = 1.0
    private(set) var fireRateMultiplier: CGFloat = 1.0
    private(set) var critChance: CGFloat = 0
    private(set) var critDamageBonus: CGFloat = 0
    private(set) var multishotLevel: Int = 0
    private(set) var healthRegenPerSecond: CGFloat = 0
    private(set) var lifestealFraction: CGFloat = 0
    private(set) var dodgeChance: CGFloat = 0
    private(set) var xpGainMultiplier: CGFloat = 1.0
    /// True while the Void Aegis potion buff is active — takeContactDamage no-ops entirely.
    private(set) var isInvulnerableFromBuff: Bool = false

    var currentMoveSpeed: CGFloat { PlayerConfig.baseMoveSpeed * moveSpeedMultiplier }

    // MARK: - Private state

    /// Baseline stats derived once from the meta loadout at run start; passive recomputation always
    /// starts from these, never from whatever the previous recompute left behind.
    private var baseline = MetaLoadout()
    private var passiveLevels: [PassiveKind: Int] = [:]
    /// Timed potion buffs, keyed by kind, value is the run-clock timestamp they expire at. Instant
    /// potions (PotionKind.isInstant) never enter this dict — GameScene applies their one-shot effect
    /// directly via XPSystem instead of routing through here.
    private var buffExpiry: [PotionKind: TimeInterval] = [:]
    /// Cached each frame in updateBuffs() from MetaProgressionStore.shared.isSpeedBoostActive — cached
    /// rather than read fresh inside applyBuffLayer() so a UserDefaults read only happens once/frame,
    /// and so we can detect the on->off transition (recompute is otherwise only driven by events).
    private var isSpeedBoostFromAdActive: Bool = false

    private var lastHitTime: TimeInterval = -999
    /// Second Wind: -infinity means "never procced yet this run", so the very first save is always
    /// available the instant the passive is picked up, regardless of the cooldown value.
    private var lastSecondWindTime: TimeInterval = -.greatestFiniteMagnitude
    private weak var bodySprite: SKSpriteNode?
    private weak var eyeGlowLeft: SKShapeNode?
    private weak var eyeGlowRight: SKShapeNode?

    // MARK: - Construction

    static func makeNode() -> PlayerController {
        let size = CGSize(width: 44, height: 44)
        let player = PlayerController(texture: nil, color: .clear, size: size)
        player.zPosition = ZPosition.player
        player.name = "player"

        // Soft ground shadow, matches the visual language established by Enemy.swift.
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 30, height: 12))
        shadow.fillColor = SKColor.black.withAlphaComponent(0.4)
        shadow.strokeColor = .clear
        shadow.position = CGPoint(x: 0, y: -19)
        shadow.zPosition = -1
        player.addChild(shadow)

        // Faint ember aura behind the body — reinforces the "feeds on the night" identity.
        let aura = SKSpriteNode(texture: ProceduralTextures.radialGlow(
            color: SKColor(red: 1.0, green: 0.45, blue: 0.18, alpha: 1), radius: 40))
        aura.size = CGSize(width: 80, height: 80)
        aura.zPosition = -0.5
        aura.blendMode = .add
        aura.alpha = 0.55
        player.addChild(aura)
        aura.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.12, duration: 1.1),
            SKAction.scale(to: 0.94, duration: 1.1)
        ])))

        let body = SKSpriteNode(texture: PlayerController.proceduralBodyTexture(), size: size)
        body.zPosition = 1
        player.addChild(body)
        player.bodySprite = body

        // Twin ember eyes, drawn as separate glow nodes so they can pulse independently of the hit-flash.
        let leftEye = SKShapeNode(circleOfRadius: 2.3)
        leftEye.fillColor = SKColor(red: 1, green: 0.62, blue: 0.22, alpha: 1)
        leftEye.strokeColor = .clear
        leftEye.glowWidth = 3
        leftEye.position = CGPoint(x: -6, y: 6)
        leftEye.zPosition = 2
        player.addChild(leftEye)
        player.eyeGlowLeft = leftEye

        let rightEye = SKShapeNode(circleOfRadius: 2.3)
        rightEye.fillColor = SKColor(red: 1, green: 0.62, blue: 0.22, alpha: 1)
        rightEye.strokeColor = .clear
        rightEye.glowWidth = 3
        rightEye.position = CGPoint(x: 6, y: 6)
        rightEye.zPosition = 2
        player.addChild(rightEye)
        player.eyeGlowRight = rightEye

        let emberPulse = SKAction.repeatForever(SKAction.sequence([
            SKAction.fadeAlpha(to: 0.55, duration: 0.6),
            SKAction.fadeAlpha(to: 1.0, duration: 0.6)
        ]))
        leftEye.run(emberPulse)
        rightEye.run(SKAction.sequence([SKAction.wait(forDuration: 0.3), emberPulse]))

        return player
    }

    /// Cloaked, ember-eyed humanoid silhouette: deep violet cloak, moonlight-white highlights, blood-red trim.
    private static func proceduralBodyTexture() -> SKTexture {
        ProceduralTextures.render(size: CGSize(width: 88, height: 88)) { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2

            // Cloak silhouette — wide at the hem, tapering toward the shoulders/hood.
            let cloak = CGMutablePath()
            cloak.move(to: CGPoint(x: cx, y: size.height - 12))
            cloak.addQuadCurve(to: CGPoint(x: size.width - 10, y: 6),
                                control: CGPoint(x: cx + 26, y: cy + 4))
            cloak.addLine(to: CGPoint(x: size.width - 22, y: 6))
            cloak.addQuadCurve(to: CGPoint(x: cx, y: cy - 6),
                                control: CGPoint(x: cx + 12, y: cy - 20))
            cloak.addQuadCurve(to: CGPoint(x: 22, y: 6),
                                control: CGPoint(x: cx - 12, y: cy - 20))
            cloak.addLine(to: CGPoint(x: 10, y: 6))
            cloak.addQuadCurve(to: CGPoint(x: cx, y: size.height - 12),
                                control: CGPoint(x: cx - 26, y: cy + 4))
            cloak.closeSubpath()

            ctx.setFillColor(SKColor(red: 0.16, green: 0.08, blue: 0.24, alpha: 1).cgColor)
            ctx.addPath(cloak)
            ctx.fillPath()

            ctx.setStrokeColor(SKColor(red: 0.78, green: 0.1, blue: 0.16, alpha: 0.85).cgColor)
            ctx.setLineWidth(2.4)
            ctx.addPath(cloak)
            ctx.strokePath()

            // Hood/head, moonlight-pale hint of a face lost in shadow.
            let hoodRect = CGRect(x: cx - 15, y: size.height - 34, width: 30, height: 28)
            ctx.setFillColor(SKColor(red: 0.1, green: 0.05, blue: 0.15, alpha: 1).cgColor)
            ctx.fillEllipse(in: hoodRect)

            let faceRect = CGRect(x: cx - 9, y: size.height - 26, width: 18, height: 15)
            ctx.setFillColor(SKColor(red: 0.86, green: 0.83, blue: 0.9, alpha: 0.35).cgColor)
            ctx.fillEllipse(in: faceRect)

            // Ember core glowing through the chest, the "feeds on night" motif.
            ctx.setFillColor(SKColor(red: 1.0, green: 0.5, blue: 0.2, alpha: 0.9).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 5, y: cy - 4, width: 10, height: 10))
        }
    }

    // MARK: - Meta loadout / passive stat computation

    func applyMetaLoadout(_ loadout: MetaLoadout) {
        baseline = loadout
        passiveLevels.removeAll(keepingCapacity: true)

        maxHealth = PlayerConfig.baseMaxHealth + loadout.startingHealthBonus
        currentHealth = maxHealth
        moveSpeedMultiplier = loadout.startingSpeedMultiplier
        damageMultiplier = loadout.startingDamageMultiplier
        magnetRadius = PlayerConfig.baseMagnetRadius + loadout.startingMagnetBonus
        armorFlat = loadout.startingArmorBonus
        critChance = loadout.startingCritBonus

        fireRateMultiplier = 1.0
        critDamageBonus = 0
        multishotLevel = 0
        healthRegenPerSecond = 0
        lifestealFraction = loadout.lifestealFraction
        dodgeChance = loadout.dodgeChance
        xpGainMultiplier = loadout.xpGainMultiplier
        isInvulnerableFromBuff = false
        buffExpiry.removeAll(keepingCapacity: true)
        isSpeedBoostFromAdActive = MetaProgressionStore.shared.isSpeedBoostActive
        if isSpeedBoostFromAdActive {
            moveSpeedMultiplier *= 2.0
            fireRateMultiplier = max(0.1, fireRateMultiplier * 0.5)
        }

        isDead = false
        lastHitTime = -999
        lastSecondWindTime = -.greatestFiniteMagnitude
    }

    func setPassiveLevel(_ kind: PassiveKind, level: Int) {
        passiveLevels[kind] = level
        recomputeDerivedStats()
    }

    private func recomputeDerivedStats() {
        let swiftFeetLevel = passiveLevels[.swiftFeet] ?? 0
        let bloodEdgeLevel = passiveLevels[.bloodEdge] ?? 0
        let rapidPulseLevel = passiveLevels[.rapidPulse] ?? 0
        let vitalityLevel = passiveLevels[.vitality] ?? 0
        let magnetHeartLevel = passiveLevels[.magnetHeart] ?? 0
        let ironHideLevel = passiveLevels[.ironHide] ?? 0
        let multishotLevelValue = passiveLevels[.multishot] ?? 0
        let critFocusLevel = passiveLevels[.critFocus] ?? 0
        let ashenWakeLevel = passiveLevels[.ashenWake] ?? 0

        let newMaxHealth = PlayerConfig.baseMaxHealth + baseline.startingHealthBonus + Balance.passiveValue(.vitality, level: vitalityLevel)
        let healthDelta = newMaxHealth - maxHealth
        maxHealth = newMaxHealth
        if healthDelta > 0 {
            currentHealth = min(maxHealth, currentHealth + healthDelta)
        } else {
            currentHealth = min(currentHealth, maxHealth)
        }

        moveSpeedMultiplier = baseline.startingSpeedMultiplier * (1 + Balance.passiveValue(.swiftFeet, level: swiftFeetLevel))
        damageMultiplier = baseline.startingDamageMultiplier * (1 + Balance.passiveValue(.bloodEdge, level: bloodEdgeLevel))

        // Lower interval multiplier = faster fire. Clamp so it never drifts to (or past) zero.
        let fireRateReduction = Balance.passiveValue(.rapidPulse, level: rapidPulseLevel)
        fireRateMultiplier = max(0.2, 1 - fireRateReduction)

        magnetRadius = PlayerConfig.baseMagnetRadius + baseline.startingMagnetBonus + Balance.passiveValue(.magnetHeart, level: magnetHeartLevel)
        armorFlat = baseline.startingArmorBonus + Balance.passiveValue(.ironHide, level: ironHideLevel)
        multishotLevel = Int(multishotLevelValue)
        healthRegenPerSecond = Balance.passiveValue(.ashenWake, level: ashenWakeLevel)

        critChance = min(0.85, baseline.startingCritBonus + Balance.critChance(level: critFocusLevel))
        critDamageBonus = Balance.critDamageBonus(level: critFocusLevel)

        applyBuffLayer()
    }

    /// Layers active timed potion buffs on top of the passive-derived stats just computed above.
    /// Called both from recomputeDerivedStats() (so a buff picked up mid-frame takes effect immediately
    /// alongside whatever passive triggered the recompute) and from updateBuffs() on expiry.
    private func applyBuffLayer() {
        if buffExpiry[.crimsonVigor] != nil { damageMultiplier *= Balance.potionVigorDamageMultiplier }
        if buffExpiry[.nightHaste] != nil {
            moveSpeedMultiplier *= Balance.potionHasteSpeedMultiplier
            fireRateMultiplier = max(0.12, fireRateMultiplier * Balance.potionHasteFireRateMultiplier)
        }
        if buffExpiry[.bloodFrenzy] != nil {
            critChance = 1.0
            critDamageBonus += Balance.potionFrenzyCritDamageBonus
        }
        if buffExpiry[.hungerSurge] != nil { magnetRadius *= Balance.potionHungerSurgeMagnetMultiplier }
        isInvulnerableFromBuff = buffExpiry[.voidAegis] != nil

        // Ad-gated "Double Time" boost (menu shop, 15-minute window) — literal 2x move speed + fire rate.
        if isSpeedBoostFromAdActive {
            moveSpeedMultiplier *= 2.0
            fireRateMultiplier = max(0.1, fireRateMultiplier * 0.5)
        }
    }

    // MARK: - Potion buffs

    /// Applies a timed (or instant-heal) potion buff, picked up mid-run. Instant-only potions
    /// (PotionKind.isInstant) are handled entirely by GameScene/XPSystem and never reach here.
    func applyPotionBuff(_ kind: PotionKind, now: TimeInterval) {
        guard !kind.isInstant else { return }
        if kind == .hungerSurge { heal(maxHealth * Balance.potionHungerSurgeHealFraction) }
        buffExpiry[kind] = now + Balance.potionDuration(kind)
        recomputeDerivedStats()
    }

    /// Called once per frame by GameScene. Cheap unless a potion buff expired or the ad-gated speed
    /// boost's on/off state actually flipped this frame — either triggers one recompute.
    func updateBuffs(now: TimeInterval) {
        var needsRecompute = false

        if !buffExpiry.isEmpty {
            let before = buffExpiry.count
            buffExpiry = buffExpiry.filter { $0.value > now }
            if buffExpiry.count != before { needsRecompute = true }
        }

        let speedBoostNow = MetaProgressionStore.shared.isSpeedBoostActive
        if speedBoostNow != isSpeedBoostFromAdActive {
            isSpeedBoostFromAdActive = speedBoostNow
            needsRecompute = true
        }

        if needsRecompute { recomputeDerivedStats() }
    }

    /// Passive health regeneration (Ashen Wake). GameScene calls this once per frame, right after move().
    func applyPassiveRegen(deltaTime: TimeInterval) {
        guard healthRegenPerSecond > 0, !isDead else { return }
        heal(healthRegenPerSecond * CGFloat(deltaTime))
    }

    // MARK: - Movement

    func move(direction: CGVector, deltaTime: TimeInterval) {
        let len = sqrt(direction.dx * direction.dx + direction.dy * direction.dy)
        guard len > 0 else { return }

        let magnitude = min(1, len)
        let unitX = direction.dx / len
        let unitY = direction.dy / len
        let travel = currentMoveSpeed * magnitude * CGFloat(deltaTime)

        var newPosition = CGPoint(x: position.x + unitX * travel, y: position.y + unitY * travel)

        let bounds = WorldConfig.bounds
        let inset = PlayerConfig.radius
        let minX = bounds.minX + inset
        let maxX = bounds.maxX - inset
        let minY = bounds.minY + inset
        let maxY = bounds.maxY - inset
        newPosition.x = min(max(newPosition.x, minX), maxX)
        newPosition.y = min(max(newPosition.y, minY), maxY)

        position = newPosition

        // Face movement direction by mirroring the body sprite (cheap, readable turn-to-face).
        if let body = bodySprite, abs(unitX) > 0.001 {
            body.xScale = unitX < 0 ? -abs(body.xScale) : abs(body.xScale)
        }
    }

    // MARK: - Damage / health

    @discardableResult
    func takeContactDamage(_ rawAmount: CGFloat, now: TimeInterval) -> Bool {
        guard !isDead, !isInvulnerableFromBuff else { return false }
        guard now - lastHitTime >= PlayerConfig.invulnerabilityAfterHit else { return false }
        guard dodgeChance <= 0 || CGFloat.random(in: 0...1) >= dodgeChance else {
            lastHitTime = now // still gate re-hits on the normal invulnerability window, just deal no damage
            return false
        }
        lastHitTime = now

        let damage = max(1, rawAmount - armorFlat)

        if currentHealth - damage <= 0, canProcSecondWind(now: now) {
            currentHealth = 1
            lastSecondWindTime = now
            flashHit()
            AudioManager.shared.playSFX(.revive)
            AudioManager.shared.hapticNotification(.success)
            return true
        }

        currentHealth -= damage
        flashHit()
        AudioManager.shared.playSFX(.playerHit)
        AudioManager.shared.hapticImpact(.heavy)

        if currentHealth <= 0 {
            currentHealth = 0
            isDead = true
        }
        return true
    }

    /// Second Wind: survives what would otherwise be a lethal hit, once per internal cooldown
    /// (Balance.passiveValue(.secondWind, level:) — shorter at higher levels).
    private func canProcSecondWind(now: TimeInterval) -> Bool {
        let level = passiveLevels[.secondWind] ?? 0
        guard level > 0 else { return false }
        let cooldown = TimeInterval(Balance.passiveValue(.secondWind, level: level))
        return now - lastSecondWindTime >= cooldown
    }

    private func flashHit() {
        removeAction(forKey: "hitFlash")
        guard let body = bodySprite else { return }
        body.removeAction(forKey: "hitFlash")
        body.colorBlendFactor = 1
        body.color = .white
        body.run(SKAction.sequence([
            SKAction.wait(forDuration: 0.08),
            SKAction.run { [weak body] in body?.colorBlendFactor = 0 }
        ]), withKey: "hitFlash")
    }

    func heal(_ amount: CGFloat) {
        guard amount > 0 else { return }
        currentHealth = min(maxHealth, currentHealth + amount)
    }

    func reviveWithHalfHealth(now: TimeInterval) {
        isDead = false
        currentHealth = maxHealth * 0.5
        lastHitTime = now
    }
}
