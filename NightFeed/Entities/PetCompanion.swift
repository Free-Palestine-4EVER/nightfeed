import SpriteKit

/// Familiar node for any of the four `PetKind`s (unlocked via their one-time shop upgrades). Fully
/// self-contained: follows the player with a light trailing lag, and independently acts on its own
/// cadence — the Ember Wisp zaps, the Bone Hound bites, the Storm Sprite chain-lightnings, the Grave
/// Moth heals. Not pooled — GameScene creates one instance per active pet slot (1 or 2, see the
/// "Second Familiar" shop upgrade) once per run, same as PlayerController. Deliberately does not use a
/// pooled Projectile; every attack resolves instantly (an instant zap/bite/bolt), matching how Nova
/// Pulse/Void Rift also skip the projectile pool for their own low-frequency effects. `slotIndex` (0 or
/// 1) only affects the follow offset, mirrored left/right, so two simultaneous familiars don't overlap.
final class PetCompanion: SKSpriteNode {
    private var kind: PetKind = .emberWisp
    private var slotIndex: Int = 0

    private var followOffset: CGPoint = .zero
    private var followLerp: CGFloat = 3.2

    /// Shared attack/ability cooldown, meaning varies per kind (fire timer, bite timer, heal timer).
    private var fireCountdown: TimeInterval = 0
    /// True for the ~0.18s the Bone Hound's dash is physically travelling — while true the normal
    /// follow-lerp is suspended so the SKAction.move owns `position` exclusively; once it clears, the
    /// follow-lerp naturally eases the hound back to its follow point, i.e. "returns to following".
    private var isLunging = false
    private var pendingBite: PendingBite?

    private weak var bodySprite: SKSpriteNode?

    private struct PendingBite {
        weak var target: Enemy?
        let damage: CGFloat
        let isCrit: Bool
        let readyTime: TimeInterval
    }

    // MARK: - Ember Wisp tuning (unchanged from the original single-pet implementation)

    private static let wispFireInterval: TimeInterval = 1.6
    private static let wispDetectionRadius: CGFloat = 240
    private static let wispBaseDamage: CGFloat = 6
    private static let wispZapColor = SKColor(red: 0.85, green: 0.55, blue: 1.0, alpha: 1)

    // MARK: - Bone Hound tuning

    private static let houndAttackInterval: TimeInterval = 2.2
    private static let houndLungeRange: CGFloat = 130
    private static let houndLungeDuration: TimeInterval = 0.18
    private static let houndBaseDamage: CGFloat = 14
    private static let houndAccentColor = SKColor(red: 0.64, green: 0.44, blue: 0.86, alpha: 1)
    private static let houndBoneColor = SKColor(red: 0.88, green: 0.86, blue: 0.9, alpha: 1)

    // MARK: - Storm Sprite tuning

    private static let spriteFireInterval: TimeInterval = 2.4
    private static let spriteDetectionRadius: CGFloat = 240
    private static let spriteChainRadius: CGFloat = 110
    /// Base damage for each successive hop of the chain: first target, then up to 2 more, diminishing.
    private static let spriteChainDamageValues: [CGFloat] = [4, 3, 2]
    private static let spriteBoltColor = SKColor(red: 0.35, green: 0.85, blue: 1.0, alpha: 1)

    // MARK: - Grave Moth tuning

    private static let mothHealInterval: TimeInterval = 6.0
    private static let mothHealAmount: CGFloat = 8
    private static let mothGlowColor = SKColor(red: 0.68, green: 0.92, blue: 0.78, alpha: 1)

    // MARK: - Per-kind follow tuning + aura appearance

    private struct Tuning {
        let followOffset: CGPoint
        let followLerp: CGFloat
        let auraColor: SKColor
        let auraRadius: CGFloat
        let auraSize: CGSize
        let auraAlpha: CGFloat
    }

    private static func tuning(for kind: PetKind) -> Tuning {
        switch kind {
        case .emberWisp:
            return Tuning(followOffset: CGPoint(x: -34, y: -30), followLerp: 3.2,
                          auraColor: wispZapColor, auraRadius: 22, auraSize: CGSize(width: 44, height: 44), auraAlpha: 0.6)
        case .boneHound:
            return Tuning(followOffset: CGPoint(x: -48, y: -36), followLerp: 2.6,
                          auraColor: houndAccentColor, auraRadius: 20, auraSize: CGSize(width: 38, height: 38), auraAlpha: 0.4)
        case .stormSprite:
            return Tuning(followOffset: CGPoint(x: -28, y: -22), followLerp: 4.4,
                          auraColor: spriteBoltColor, auraRadius: 22, auraSize: CGSize(width: 42, height: 42), auraAlpha: 0.55)
        case .graveMoth:
            return Tuning(followOffset: CGPoint(x: -30, y: 40), followLerp: 2.0,
                          auraColor: mothGlowColor, auraRadius: 26, auraSize: CGSize(width: 50, height: 50), auraAlpha: 0.35)
        }
    }

    // MARK: - Construction

    static func makeNode(kind: PetKind, slotIndex: Int) -> PetCompanion {
        let pet = PetCompanion(texture: nil, color: .clear, size: CGSize(width: 26, height: 26))
        pet.kind = kind
        pet.slotIndex = slotIndex
        pet.zPosition = ZPosition.player - 0.5

        let t = Self.tuning(for: kind)
        // Slot 0 sits slightly behind-left of the player (the offset as authored below); slot 1 mirrors
        // it to sit behind-right, so two simultaneous familiars visually separate instead of overlapping.
        pet.followOffset = slotIndex == 1 ? CGPoint(x: -t.followOffset.x, y: t.followOffset.y) : t.followOffset
        pet.followLerp = t.followLerp

        let aura = SKSpriteNode(texture: ProceduralTextures.radialGlow(color: t.auraColor, radius: t.auraRadius))
        aura.size = t.auraSize
        aura.blendMode = .add
        aura.alpha = t.auraAlpha
        pet.addChild(aura)
        aura.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.15, duration: 0.9),
            SKAction.scale(to: 0.9, duration: 0.9)
        ])))

        let body = SKSpriteNode(texture: Self.texture(for: kind))
        pet.addChild(body)
        pet.bodySprite = body
        Self.applyIdleAnimation(kind: kind, pet: pet, body: body)

        return pet
    }

    // MARK: - Procedural textures

    private static func texture(for kind: PetKind) -> SKTexture {
        switch kind {
        case .emberWisp: return wispTexture()
        case .boneHound: return houndTexture()
        case .stormSprite: return stormSpriteTexture()
        case .graveMoth: return mothTexture()
        }
    }

    private static func wispTexture() -> SKTexture {
        ProceduralTextures.render(size: CGSize(width: 26, height: 26)) { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            let star = CGMutablePath()
            star.move(to: CGPoint(x: cx, y: 2))
            star.addQuadCurve(to: CGPoint(x: size.width - 2, y: cy), control: CGPoint(x: cx + 4, y: cy - 4))
            star.addQuadCurve(to: CGPoint(x: cx, y: size.height - 2), control: CGPoint(x: cx + 4, y: cy + 4))
            star.addQuadCurve(to: CGPoint(x: 2, y: cy), control: CGPoint(x: cx - 4, y: cy + 4))
            star.addQuadCurve(to: CGPoint(x: cx, y: 2), control: CGPoint(x: cx - 4, y: cy - 4))
            star.closeSubpath()
            ctx.setFillColor(SKColor(red: 0.95, green: 0.85, blue: 1.0, alpha: 1).cgColor)
            ctx.addPath(star)
            ctx.fillPath()
            ctx.setFillColor(wispZapColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 3, y: cy - 3, width: 6, height: 6))
        }
    }

    /// Small four-legged beast silhouette: bone-white body, violet ears/legs/tail, a violet eye-glow.
    private static func houndTexture() -> SKTexture {
        ProceduralTextures.render(size: CGSize(width: 32, height: 24)) { ctx, size in
            let cy = size.height / 2

            // Legs, drawn first so the body overlaps their tops.
            ctx.setFillColor(houndAccentColor.cgColor)
            ctx.fill(CGRect(x: 9, y: 1, width: 4, height: 10))
            ctx.fill(CGRect(x: 20, y: 1, width: 4, height: 10))

            // Body.
            ctx.setFillColor(houndBoneColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: 6, y: cy - 7, width: 21, height: 13))

            // Snout.
            let snout = CGMutablePath()
            snout.move(to: CGPoint(x: size.width - 7, y: cy + 2))
            snout.addLine(to: CGPoint(x: size.width - 1, y: cy - 1))
            snout.addLine(to: CGPoint(x: size.width - 7, y: cy - 4))
            snout.closeSubpath()
            ctx.addPath(snout)
            ctx.fillPath()

            // Ear.
            ctx.setFillColor(houndAccentColor.cgColor)
            let ear = CGMutablePath()
            ear.move(to: CGPoint(x: 9, y: cy + 5))
            ear.addLine(to: CGPoint(x: 6, y: size.height - 1))
            ear.addLine(to: CGPoint(x: 14, y: cy + 5))
            ear.closeSubpath()
            ctx.addPath(ear)
            ctx.fillPath()

            // Tail.
            ctx.setStrokeColor(houndAccentColor.cgColor)
            ctx.setLineWidth(3)
            ctx.move(to: CGPoint(x: 6, y: cy - 4))
            ctx.addQuadCurve(to: CGPoint(x: 0, y: cy + 5), control: CGPoint(x: 0, y: cy - 5))
            ctx.strokePath()

            // Eye-glow.
            ctx.setFillColor(SKColor(red: 0.75, green: 0.4, blue: 0.98, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: size.width - 11, y: cy + 1, width: 3.5, height: 3.5))
        }
    }

    /// Jagged spark-bolt silhouette with a hot white core, cyan/electric-blue body.
    private static func stormSpriteTexture() -> SKTexture {
        ProceduralTextures.render(size: CGSize(width: 24, height: 26)) { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            let bolt = CGMutablePath()
            bolt.move(to: CGPoint(x: cx - 2, y: size.height - 2))
            bolt.addLine(to: CGPoint(x: cx + 6, y: cy + 4))
            bolt.addLine(to: CGPoint(x: cx + 1, y: cy + 3))
            bolt.addLine(to: CGPoint(x: cx + 8, y: 2))
            bolt.addLine(to: CGPoint(x: cx - 6, y: cy - 1))
            bolt.addLine(to: CGPoint(x: cx - 1, y: cy - 2))
            bolt.addLine(to: CGPoint(x: cx - 9, y: size.height - 6))
            bolt.closeSubpath()
            ctx.setFillColor(SKColor(red: 0.55, green: 0.92, blue: 1.0, alpha: 1).cgColor)
            ctx.addPath(bolt)
            ctx.fillPath()
            ctx.setFillColor(SKColor(red: 0.14, green: 0.5, blue: 0.82, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 3.5, y: cy - 3.5, width: 7, height: 7))
            ctx.setFillColor(SKColor.white.withAlphaComponent(0.95).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 1.5, y: cy - 1.5, width: 3, height: 3))
        }
    }

    /// Symmetric pale moth wings with soft sage-green accent spots and a slender body.
    private static func mothTexture() -> SKTexture {
        ProceduralTextures.render(size: CGSize(width: 34, height: 22)) { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            let paleColor = SKColor(red: 0.9, green: 0.96, blue: 0.92, alpha: 0.92)
            let accentColor = SKColor(red: 0.6, green: 0.83, blue: 0.7, alpha: 0.9)

            let leftWing = CGMutablePath()
            leftWing.move(to: CGPoint(x: cx, y: cy))
            leftWing.addQuadCurve(to: CGPoint(x: 2, y: cy + 3), control: CGPoint(x: cx - 17, y: size.height - 1))
            leftWing.addQuadCurve(to: CGPoint(x: cx - 3, y: cy - 7), control: CGPoint(x: 7, y: 1))
            leftWing.closeSubpath()
            ctx.setFillColor(paleColor.cgColor)
            ctx.addPath(leftWing)
            ctx.fillPath()

            let rightWing = CGMutablePath()
            rightWing.move(to: CGPoint(x: cx, y: cy))
            rightWing.addQuadCurve(to: CGPoint(x: size.width - 2, y: cy + 3), control: CGPoint(x: cx + 17, y: size.height - 1))
            rightWing.addQuadCurve(to: CGPoint(x: cx + 3, y: cy - 7), control: CGPoint(x: size.width - 7, y: 1))
            rightWing.closeSubpath()
            ctx.addPath(rightWing)
            ctx.fillPath()

            ctx.setFillColor(accentColor.cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 12, y: cy, width: 5, height: 5))
            ctx.fillEllipse(in: CGRect(x: cx + 7, y: cy, width: 5, height: 5))

            ctx.setFillColor(SKColor(red: 0.8, green: 0.86, blue: 0.82, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: cx - 2.5, y: cy - 9, width: 5, height: 16))

            ctx.setStrokeColor(accentColor.cgColor)
            ctx.setLineWidth(1.2)
            ctx.move(to: CGPoint(x: cx - 1, y: cy + 6))
            ctx.addLine(to: CGPoint(x: cx - 4, y: cy + 10))
            ctx.move(to: CGPoint(x: cx + 1, y: cy + 6))
            ctx.addLine(to: CGPoint(x: cx + 4, y: cy + 10))
            ctx.strokePath()
        }
    }

    /// Idle motion, distinct per kind: the wisp bobs, the hound has a light padding trot, the sprite
    /// crackles with a fast alpha flicker, the moth does a slow, lazy wing-flutter + gentle sway.
    private static func applyIdleAnimation(kind: PetKind, pet: PetCompanion, body: SKSpriteNode) {
        switch kind {
        case .emberWisp:
            body.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: 5, duration: 0.6),
                SKAction.moveBy(x: 0, y: -5, duration: 0.6)
            ])))
        case .boneHound:
            body.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.moveBy(x: 0, y: 3, duration: 0.32),
                SKAction.moveBy(x: 0, y: -3, duration: 0.32)
            ])))
        case .stormSprite:
            body.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.fadeAlpha(to: 0.65, duration: 0.07),
                SKAction.fadeAlpha(to: 1.0, duration: 0.07),
                SKAction.wait(forDuration: 0.4)
            ])))
        case .graveMoth:
            body.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.scaleX(to: 0.74, duration: 0.85),
                SKAction.scaleX(to: 1.0, duration: 0.85)
            ])))
            pet.run(SKAction.repeatForever(SKAction.sequence([
                SKAction.rotate(byAngle: 0.08, duration: 1.3),
                SKAction.rotate(byAngle: -0.16, duration: 1.3),
                SKAction.rotate(byAngle: 0.08, duration: 1.3)
            ])))
        }
    }

    // MARK: - Per-frame update

    /// Called once per frame by GameScene, after WeaponSystem.update(). Same call every frame regardless
    /// of kind — branches internally on the stored kind. `onEnemyDefeated` mirrors WeaponSystem's
    /// contract: called with the just-defeated Enemy before it is retired.
    func update(deltaTime: TimeInterval, now: TimeInterval, playerPosition: CGPoint, player: PlayerController,
                enemies: [Enemy], worldLayer: SKNode, onEnemyDefeated: (Enemy) -> Void) {
        updateFollow(deltaTime: deltaTime, playerPosition: playerPosition)

        switch kind {
        case .emberWisp:
            updateEmberWisp(deltaTime: deltaTime, player: player, enemies: enemies, worldLayer: worldLayer, onEnemyDefeated: onEnemyDefeated)
        case .boneHound:
            updateBoneHound(deltaTime: deltaTime, now: now, player: player, enemies: enemies, onEnemyDefeated: onEnemyDefeated)
        case .stormSprite:
            updateStormSprite(deltaTime: deltaTime, player: player, enemies: enemies, worldLayer: worldLayer, onEnemyDefeated: onEnemyDefeated)
        case .graveMoth:
            updateGraveMoth(deltaTime: deltaTime, playerPosition: playerPosition, player: player, worldLayer: worldLayer)
        }
    }

    private func updateFollow(deltaTime: TimeInterval, playerPosition: CGPoint) {
        // While a Bone Hound dash is in flight, the SKAction.move it's running owns `position`
        // exclusively; resuming the lerp here too would fight it. Clearing `isLunging` (once the dash
        // settles) is what lets this same lerp smoothly ease the hound back to its follow point.
        guard !isLunging else { return }
        let targetPosition = CGPoint(x: playerPosition.x + followOffset.x, y: playerPosition.y + followOffset.y)
        let t = CGFloat(min(1, followLerp * deltaTime))
        position = CGPoint(x: position.x + (targetPosition.x - position.x) * t,
                            y: position.y + (targetPosition.y - position.y) * t)
    }

    private func nearestEnemy(in enemies: [Enemy], from origin: CGPoint, maxRadius: CGFloat, excluding: [Enemy] = []) -> Enemy? {
        var best: Enemy?
        var bestDistSq = maxRadius * maxRadius
        for enemy in enemies {
            guard enemy.isAlive else { continue }
            if !excluding.isEmpty, excluding.contains(where: { $0 === enemy }) { continue }
            let dx = enemy.position.x - origin.x
            let dy = enemy.position.y - origin.y
            let distSq = dx * dx + dy * dy
            if distSq < bestDistSq {
                bestDistSq = distSq
                best = enemy
            }
        }
        return best
    }

    // MARK: - Ember Wisp: ranged zapper (unchanged behavior)

    private func updateEmberWisp(deltaTime: TimeInterval, player: PlayerController, enemies: [Enemy],
                                  worldLayer: SKNode, onEnemyDefeated: (Enemy) -> Void) {
        var countdown = fireCountdown - deltaTime
        if countdown <= 0 {
            if let target = nearestEnemy(in: enemies, from: position, maxRadius: Self.wispDetectionRadius) {
                fireWispZap(at: target, player: player, worldLayer: worldLayer, onEnemyDefeated: onEnemyDefeated)
            }
            countdown = Self.wispFireInterval
        }
        fireCountdown = countdown
    }

    private func fireWispZap(at target: Enemy, player: PlayerController, worldLayer: SKNode, onEnemyDefeated: (Enemy) -> Void) {
        let isCrit = CGFloat.random(in: 0...1) < player.critChance
        let damage = Self.wispBaseDamage * player.damageMultiplier * (isCrit ? 1 + player.critDamageBonus : 1)

        let beam = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: position)
        path.addLine(to: target.position)
        beam.path = path
        beam.strokeColor = Self.wispZapColor
        beam.lineWidth = 2.5
        beam.glowWidth = 4
        beam.alpha = 0.9
        beam.zPosition = ZPosition.projectile
        worldLayer.addChild(beam)
        beam.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.16), SKAction.removeFromParent()]))

        AudioManager.shared.playSFX(.weaponFire(.batSwarm))
        let killed = target.takeDamage(damage)
        JuiceEffects.hitBurst(at: target.position, color: Self.wispZapColor, scale: isCrit ? 1.3 : 0.9)
        JuiceEffects.damageNumber(max(1, Int(damage.rounded())), isCrit: isCrit, at: target.position)
        if killed {
            AudioManager.shared.playSFX(.enemyDeath)
            onEnemyDefeated(target)
        }
    }

    // MARK: - Bone Hound: melee lunge-and-bite

    private func updateBoneHound(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController,
                                  enemies: [Enemy], onEnemyDefeated: (Enemy) -> Void) {
        // Resolve a bite whose dash has finished travelling before considering a new one.
        if let pending = pendingBite, now >= pending.readyTime {
            pendingBite = nil
            isLunging = false
            if let target = pending.target, target.isAlive {
                resolveBite(target: target, damage: pending.damage, isCrit: pending.isCrit, onEnemyDefeated: onEnemyDefeated)
            }
        }

        guard !isLunging else { return }

        var countdown = fireCountdown - deltaTime
        if countdown <= 0 {
            if let target = nearestEnemy(in: enemies, from: position, maxRadius: Self.houndLungeRange) {
                beginLunge(at: target, player: player, now: now)
            }
            countdown = Self.houndAttackInterval
        }
        fireCountdown = countdown
    }

    private func beginLunge(at target: Enemy, player: PlayerController, now: TimeInterval) {
        isLunging = true

        if let body = bodySprite {
            let dx = target.position.x - position.x
            if abs(dx) > 0.001 {
                body.xScale = dx < 0 ? -abs(body.xScale) : abs(body.xScale)
            }
        }
        run(SKAction.move(to: target.position, duration: Self.houndLungeDuration), withKey: "lunge")

        // Damage/crit is rolled now, at commit time (same pattern the wisp uses), but only actually
        // lands once the dash arrives — see updateBoneHound's pendingBite check above.
        let isCrit = CGFloat.random(in: 0...1) < player.critChance
        let damage = Self.houndBaseDamage * player.damageMultiplier * (isCrit ? 1 + player.critDamageBonus : 1)
        pendingBite = PendingBite(target: target, damage: damage, isCrit: isCrit, readyTime: now + Self.houndLungeDuration)
    }

    private func resolveBite(target: Enemy, damage: CGFloat, isCrit: Bool, onEnemyDefeated: (Enemy) -> Void) {
        AudioManager.shared.playSFX(.weaponFire(.reaperWhirl))
        let killed = target.takeDamage(damage)
        JuiceEffects.hitBurst(at: target.position, color: Self.houndAccentColor, scale: isCrit ? 1.3 : 1.0)
        JuiceEffects.damageNumber(max(1, Int(damage.rounded())), isCrit: isCrit, at: target.position)
        if killed {
            AudioManager.shared.playSFX(.enemyDeath)
            onEnemyDefeated(target)
        }
    }

    // MARK: - Storm Sprite: chain lightning

    private func updateStormSprite(deltaTime: TimeInterval, player: PlayerController, enemies: [Enemy],
                                    worldLayer: SKNode, onEnemyDefeated: (Enemy) -> Void) {
        var countdown = fireCountdown - deltaTime
        if countdown <= 0 {
            if let target = nearestEnemy(in: enemies, from: position, maxRadius: Self.spriteDetectionRadius) {
                chainZap(from: target, player: player, enemies: enemies, worldLayer: worldLayer, onEnemyDefeated: onEnemyDefeated)
            }
            countdown = Self.spriteFireInterval
        }
        fireCountdown = countdown
    }

    /// Zaps `firstTarget`, then arcs to up to `spriteChainDamageValues.count - 1` more enemies, each
    /// hop originating from the previous target and searching only within `spriteChainRadius`, skipping
    /// every enemy already hit this chain so it can't loop back on the same target.
    private func chainZap(from firstTarget: Enemy, player: PlayerController, enemies: [Enemy],
                           worldLayer: SKNode, onEnemyDefeated: (Enemy) -> Void) {
        var hitEnemies: [Enemy] = []
        var beamOrigin = position
        var currentTarget: Enemy? = firstTarget
        var hopIndex = 0

        while let target = currentTarget, hopIndex < Self.spriteChainDamageValues.count {
            hitEnemies.append(target)
            strikeBolt(from: beamOrigin, to: target, baseDamage: Self.spriteChainDamageValues[hopIndex],
                       player: player, worldLayer: worldLayer, onEnemyDefeated: onEnemyDefeated)
            beamOrigin = target.position
            hopIndex += 1
            currentTarget = nearestEnemy(in: enemies, from: target.position, maxRadius: Self.spriteChainRadius, excluding: hitEnemies)
        }
    }

    private func strikeBolt(from origin: CGPoint, to target: Enemy, baseDamage: CGFloat, player: PlayerController,
                             worldLayer: SKNode, onEnemyDefeated: (Enemy) -> Void) {
        let isCrit = CGFloat.random(in: 0...1) < player.critChance
        let damage = baseDamage * player.damageMultiplier * (isCrit ? 1 + player.critDamageBonus : 1)

        let beam = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: origin)
        path.addLine(to: target.position)
        beam.path = path
        beam.strokeColor = Self.spriteBoltColor
        beam.lineWidth = 2.0
        beam.glowWidth = 5
        beam.alpha = 0.9
        beam.zPosition = ZPosition.projectile
        worldLayer.addChild(beam)
        beam.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.14), SKAction.removeFromParent()]))

        AudioManager.shared.playSFX(.weaponFire(.starShard))
        let killed = target.takeDamage(damage)
        JuiceEffects.hitBurst(at: target.position, color: Self.spriteBoltColor, scale: isCrit ? 1.2 : 0.8)
        JuiceEffects.damageNumber(max(1, Int(damage.rounded())), isCrit: isCrit, at: target.position)
        if killed {
            AudioManager.shared.playSFX(.enemyDeath)
            onEnemyDefeated(target)
        }
    }

    // MARK: - Grave Moth: support healer, no direct damage

    private func updateGraveMoth(deltaTime: TimeInterval, playerPosition: CGPoint, player: PlayerController, worldLayer: SKNode) {
        var countdown = fireCountdown - deltaTime
        if countdown <= 0 {
            if player.currentHealth < player.maxHealth {
                player.heal(Self.mothHealAmount)
                spawnHealPulse(at: playerPosition, worldLayer: worldLayer)
                AudioManager.shared.playSFX(.gemPickup)
            }
            countdown = Self.mothHealInterval
        }
        fireCountdown = countdown
    }

    private func spawnHealPulse(at position: CGPoint, worldLayer: SKNode) {
        let ring = SKShapeNode(circleOfRadius: 10)
        ring.position = position
        ring.strokeColor = Self.mothGlowColor
        ring.lineWidth = 3
        ring.glowWidth = 6
        ring.fillColor = .clear
        ring.alpha = 0.85
        ring.zPosition = ZPosition.worldUI
        worldLayer.addChild(ring)
        ring.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 4.5, duration: 0.6),
                SKAction.fadeOut(withDuration: 0.6)
            ]),
            SKAction.removeFromParent()
        ]))
        JuiceEffects.hitBurst(at: position, color: Self.mothGlowColor, scale: 0.7)
    }
}
