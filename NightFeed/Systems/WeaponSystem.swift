import SpriteKit

/// Owns and drives every weapon the player has acquired: firing cadence, projectile spawning, orbiter/whirl
/// rotation, AoE bursts, and all weapon-vs-enemy hit resolution. Collision is NOT SpriteKit-physics-based —
/// every hit test here is a manual distance check against `PoolManager.shared.activeEnemies`, per the
/// project-wide collision architecture (see GameConstants.swift).
///
/// Orbiters (Ember Orbit), whirl blades (Reaper Whirl / evolved Crimson Maelstrom) and the Nova Pulse
/// burst ring are small, persistent, directly-owned SKShapeNodes — never pooled (there are only ever a
/// handful alive at once). Straight/piercing/homing shots (Fang Bolt, Blood Lance, Bat Swarm, evolved
/// Moonfang Barrage) always go through `PoolManager.shared.dequeueProjectile()`.
final class WeaponSystem {

    // MARK: - Public state

    private(set) var weaponLevels: [WeaponKind: Int] = [:]
    private(set) var evolvedWeapons: Set<EvolvedWeaponKind> = []
    weak var player: PlayerController?

    /// Called with the just-defeated Enemy BEFORE it is retired to the pool. The closure owner (GameScene)
    /// reads enemy.xpValue/position/goldValue and is responsible for actually retiring the node —
    /// WeaponSystem never calls enemy.prepareForReuse() itself.
    var onEnemyDefeated: ((Enemy) -> Void)?

    /// WeaponSystem does not own a camera node, only the world layer its own visuals live in — and shaking
    /// that layer directly would fight any camera-follow logic GameScene/PlayerController implements by
    /// re-driving worldLayer.position every frame. So per the brief's fallback instruction, big-hit /
    /// mini-boss-death screen shake is exposed as a callback for the scene to wire to its actual camera:
    ///   weaponSystem.onShakeRequest = { [weak cameraNode] magnitude, duration in
    ///       guard let cameraNode else { return }
    ///       JuiceEffects.shake(node: cameraNode, magnitude: magnitude, duration: duration)
    ///   }
    var onShakeRequest: ((CGFloat, TimeInterval) -> Void)?

    // MARK: - Private world/visual state

    private let worldLayer: SKNode

    private var fireCountdown: [WeaponKind: TimeInterval] = [:]
    private var liveProjectiles: [Projectile] = []
    /// Star Shard fragments are tracked here so a fragment never fragments again (only original shards
    /// split on impact/expiry). Cleared as each fragment retires.
    private var fragmentProjectileIDs: Set<ObjectIdentifier> = []

    private var emberOrbiters: [SKShapeNode] = []
    private var emberAngle: CGFloat = 0
    private var emberRotationsCompleted: Int = 0
    private var emberHitCooldowns: [OrbitHitKey: TimeInterval] = [:]

    private var whirlBlades: [SKShapeNode] = []
    private var whirlAngle: CGFloat = 0
    private var whirlRotationsCompleted: Int = 0
    private var whirlHitCooldowns: [OrbitHitKey: TimeInterval] = [:]

    private var lastCritShakeTime: TimeInterval = -999

    private struct OrbitHitKey: Hashable {
        let orbiterIndex: Int
        let enemyID: ObjectIdentifier
    }

    // MARK: - Void Rift state

    private struct VoidRiftInstance {
        let node: SKShapeNode
        let position: CGPoint
        let radius: CGFloat
        let damage: CGFloat
        let pullStrength: CGFloat
        var remainingLifetime: TimeInterval
        var lastTickTimes: [ObjectIdentifier: TimeInterval] = [:]
    }
    private var activeRifts: [VoidRiftInstance] = []
    private static let voidRiftLifetime: TimeInterval = 2.6
    private static let voidRiftTickInterval: TimeInterval = 0.4

    // MARK: - Palette (dark nocturnal / ember / blood-and-moonlight, matching Enemy's procedural art)

    private let moonlightColor = SKColor(red: 0.65, green: 0.9, blue: 1.0, alpha: 1)
    private let bloodColor = SKColor(red: 0.85, green: 0.15, blue: 0.2, alpha: 1)
    private let violetColor = SKColor(red: 0.55, green: 0.2, blue: 0.75, alpha: 1)
    private let emberColor = SKColor(red: 1.0, green: 0.45, blue: 0.12, alpha: 1)
    private let novaColor = SKColor(red: 1.0, green: 0.55, blue: 0.2, alpha: 1)
    private let critColor = SKColor(red: 1.0, green: 0.85, blue: 0.25, alpha: 1)
    private let killFlashColor = SKColor(red: 1, green: 0.85, blue: 0.3, alpha: 1)

    // MARK: - Tunables not covered by Balance (small handful/melee hit radii, not weapon-curve data)

    private static let projectileHitRadius: CGFloat = 30
    private static let orbiterHitRadius: CGFloat = 30
    private static let critShakeDebounce: TimeInterval = 0.15

    // MARK: - Init

    init(player: PlayerController, worldLayer: SKNode) {
        self.player = player
        self.worldLayer = worldLayer
    }

    // MARK: - Ownership / leveling / evolution

    func level(of kind: WeaponKind) -> Int {
        weaponLevels[kind] ?? 0
    }

    func isMaxed(_ kind: WeaponKind) -> Bool {
        level(of: kind) >= WeaponKind.maxLevel
    }

    func ownedWeaponKinds() -> [WeaponKind] {
        WeaponKind.allCases.filter { (weaponLevels[$0] ?? 0) > 0 }
    }

    /// Sets level to 1 if not already owned (no-op if already owned).
    func acquire(_ kind: WeaponKind) {
        guard (weaponLevels[kind] ?? 0) == 0 else { return }
        weaponLevels[kind] = 1
        fireCountdown[kind] = 0 // fire almost immediately — satisfying feedback for a brand-new weapon

        guard let player = player else { return }
        switch kind {
        case .emberOrbit:
            let stats = Balance.weaponStats(.emberOrbit, level: 1)
            rebuildEmberOrbiters(count: stats.projectileCount + player.multishotLevel)
        case .reaperWhirl:
            let stats = Balance.weaponStats(.reaperWhirl, level: 1)
            rebuildWhirlBlades(count: stats.projectileCount + player.multishotLevel, evolved: false)
        default:
            break
        }
    }

    /// level += 1, capped at WeaponKind.maxLevel; rebuilds orbiter/whirl visuals if their count changed.
    func levelUp(_ kind: WeaponKind) {
        let current = weaponLevels[kind] ?? 0
        guard current > 0, current < WeaponKind.maxLevel else { return }
        let newLevel = current + 1
        weaponLevels[kind] = newLevel

        guard let player = player else { return }
        switch kind {
        case .emberOrbit:
            let stats = Balance.weaponStats(.emberOrbit, level: newLevel)
            let desired = stats.projectileCount + player.multishotLevel
            if emberOrbiters.count != desired { rebuildEmberOrbiters(count: desired) }
        case .reaperWhirl:
            guard !evolvedWeapons.contains(.crimsonMaelstrom) else { break }
            let stats = Balance.weaponStats(.reaperWhirl, level: newLevel)
            let desired = stats.projectileCount + player.multishotLevel
            if whirlBlades.count != desired { rebuildWhirlBlades(count: desired, evolved: false) }
        default:
            break
        }
    }

    /// Caller (UpgradeManager) already verified: kind is maxed AND its evolutionPassive is maxed AND not
    /// already evolved. This just performs the swap — no SFX/haptics here, since the evolution fanfare /
    /// announcement UI plausibly belongs to whichever system shows the upgrade-choice overlay.
    func evolve(_ kind: WeaponKind) {
        guard let evolvedForm = kind.evolvedForm, !evolvedWeapons.contains(evolvedForm) else { return }
        evolvedWeapons.insert(evolvedForm)

        switch kind {
        case .fangBolt:
            fireCountdown[.fangBolt] = 0 // let the first barrage volley fire immediately
        case .reaperWhirl:
            let stats = Balance.evolvedStats(.crimsonMaelstrom)
            rebuildWhirlBlades(count: stats.projectileCount, evolved: true)
        default:
            break
        }
    }

    // MARK: - Per-frame update

    /// Call once per frame AFTER PlayerController has moved and BEFORE XPSystem.update.
    func update(deltaTime: TimeInterval, now: TimeInterval) {
        guard let player = player, !player.isDead else { return }
        let enemies = PoolManager.shared.activeEnemies

        updateFangBoltFamily(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        updateBloodLance(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        updateBatSwarm(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        updateNovaPulse(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        updateEmberOrbit(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        updateReaperWhirlFamily(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        updateStarShard(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        updateVoidRift(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        stepProjectiles(deltaTime: deltaTime, now: now, enemies: enemies)
    }

    // MARK: - Fang Bolt / Moonfang Barrage (straight shot at nearest enemy, evolves to homing crit volley)

    private func updateFangBoltFamily(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        guard level(of: .fangBolt) > 0 else { return }
        if evolvedWeapons.contains(.moonfangBarrage) {
            updateMoonfangBarrage(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        } else {
            updateBaseFangBolt(deltaTime: deltaTime, now: now, player: player, enemies: enemies)
        }
    }

    private func updateBaseFangBolt(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        let lvl = level(of: .fangBolt)
        let stats = Balance.weaponStats(.fangBolt, level: lvl)
        var countdown = (fireCountdown[.fangBolt] ?? 0) - deltaTime
        if countdown <= 0 {
            if let target = nearestEnemy(to: player.position, in: enemies) {
                let baseDir = CGVector(dx: target.position.x - player.position.x, dy: target.position.y - player.position.y)
                let count = stats.projectileCount + player.multishotLevel
                fireSpreadVolley(kind: .fangBolt, count: count, baseDirection: baseDir, baseDamage: stats.damage,
                                  speed: stats.projectileSpeed, pierce: stats.pierce, range: stats.range,
                                  homing: false, origin: player.position, player: player)
                AudioManager.shared.playSFX(.weaponFire(.fangBolt))
            }
            countdown = effectiveInterval(baseInterval: stats.interval, player: player)
        }
        fireCountdown[.fangBolt] = countdown
    }

    /// Homing, guaranteed-crit multi-bolt volley. Reuses .fangBolt's texture/SFX (Projectile is only aware
    /// of WeaponKind, not EvolvedWeaponKind — the frozen spine defines no separate evolved-form assets).
    private func updateMoonfangBarrage(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        let stats = Balance.evolvedStats(.moonfangBarrage)
        var countdown = (fireCountdown[.fangBolt] ?? 0) - deltaTime
        if countdown <= 0 {
            if let target = nearestEnemy(to: player.position, in: enemies) {
                let baseDir = CGVector(dx: target.position.x - player.position.x, dy: target.position.y - player.position.y)
                for i in 0..<stats.projectileCount {
                    let spread: CGFloat = 0.14
                    let offset = (CGFloat(i) - CGFloat(stats.projectileCount - 1) / 2) * spread
                    let dir = rotate(baseDir, by: offset)
                    spawnProjectile(kind: .fangBolt, baseDamage: stats.damage, direction: dir, speed: stats.projectileSpeed,
                                     pierce: stats.pierce, range: stats.range, homing: true,
                                     homingTarget: { [weak target] in target }, origin: player.position, player: player,
                                     guaranteedCrit: true)
                }
                AudioManager.shared.playSFX(.weaponFire(.fangBolt))
            }
            countdown = effectiveInterval(baseInterval: stats.interval, player: player)
        }
        fireCountdown[.fangBolt] = countdown
    }

    // MARK: - Blood Lance (single piercing shot at nearest enemy)

    private func updateBloodLance(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        guard level(of: .bloodLance) > 0 else { return }
        let lvl = level(of: .bloodLance)
        let stats = Balance.weaponStats(.bloodLance, level: lvl)
        var countdown = (fireCountdown[.bloodLance] ?? 0) - deltaTime
        if countdown <= 0 {
            if let target = nearestEnemy(to: player.position, in: enemies) {
                let dir = CGVector(dx: target.position.x - player.position.x, dy: target.position.y - player.position.y)
                let pierce = stats.pierce + player.multishotLevel // multishot -> +1 pierce per level for Blood Lance
                spawnProjectile(kind: .bloodLance, baseDamage: stats.damage, direction: dir, speed: stats.projectileSpeed,
                                 pierce: pierce, range: stats.range, homing: false, homingTarget: nil,
                                 origin: player.position, player: player)
                AudioManager.shared.playSFX(.weaponFire(.bloodLance))
            }
            countdown = effectiveInterval(baseInterval: stats.interval, player: player)
        }
        fireCountdown[.bloodLance] = countdown
    }

    // MARK: - Bat Swarm (homing volley at nearest enemy)

    private func updateBatSwarm(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        guard level(of: .batSwarm) > 0 else { return }
        let lvl = level(of: .batSwarm)
        let stats = Balance.weaponStats(.batSwarm, level: lvl)
        var countdown = (fireCountdown[.batSwarm] ?? 0) - deltaTime
        if countdown <= 0 {
            if let target = nearestEnemy(to: player.position, in: enemies) {
                let baseDir = CGVector(dx: target.position.x - player.position.x, dy: target.position.y - player.position.y)
                let count = stats.projectileCount + player.multishotLevel
                for _ in 0..<count {
                    let spread = CGFloat.random(in: -0.7...0.7)
                    let dir = rotate(baseDir, by: spread)
                    spawnProjectile(kind: .batSwarm, baseDamage: stats.damage, direction: dir, speed: stats.projectileSpeed,
                                     pierce: stats.pierce, range: stats.range, homing: true,
                                     homingTarget: { [weak target] in target }, origin: player.position, player: player)
                }
                AudioManager.shared.playSFX(.weaponFire(.batSwarm))
            }
            countdown = effectiveInterval(baseInterval: stats.interval, player: player)
        }
        fireCountdown[.batSwarm] = countdown
    }

    // MARK: - Nova Pulse (periodic AoE burst centered on player)

    private func updateNovaPulse(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        guard level(of: .novaPulse) > 0 else { return }
        let lvl = level(of: .novaPulse)
        let stats = Balance.weaponStats(.novaPulse, level: lvl)
        var countdown = (fireCountdown[.novaPulse] ?? 0) - deltaTime
        if countdown <= 0 {
            triggerNovaBurst(stats: stats, now: now, player: player, enemies: enemies)
            countdown = effectiveInterval(baseInterval: stats.interval, player: player)
        }
        fireCountdown[.novaPulse] = countdown
    }

    private func triggerNovaBurst(stats: WeaponLevelStats, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        AudioManager.shared.playSFX(.weaponFire(.novaPulse))
        let origin = player.position
        let radiusSquared = stats.areaRadius * stats.areaRadius
        for enemy in enemies {
            guard enemy.isAlive else { continue }
            let dx = enemy.position.x - origin.x
            let dy = enemy.position.y - origin.y
            guard dx * dx + dy * dy <= radiusSquared else { continue }
            let (dmg, isCrit) = rollDamage(base: stats.damage, player: player)
            resolveHit(on: enemy, damage: dmg, isCrit: isCrit, hitColor: novaColor, weapon: .novaPulse, now: now)
        }
        spawnNovaRingVisual(at: origin, radius: stats.areaRadius)
        AudioManager.shared.hapticImpact(.medium)
    }

    private func spawnNovaRingVisual(at position: CGPoint, radius: CGFloat) {
        let startRadius: CGFloat = 14
        let ring = SKShapeNode(circleOfRadius: startRadius)
        ring.position = position
        ring.strokeColor = SKColor(red: 1, green: 0.5, blue: 0.18, alpha: 0.95)
        ring.lineWidth = 6
        ring.fillColor = .clear
        ring.glowWidth = 8
        ring.blendMode = .add
        ring.zPosition = ZPosition.weaponOrbiter
        ring.alpha = 1
        worldLayer.addChild(ring)

        let scaleAction = SKAction.scale(to: max(1.05, radius / startRadius), duration: 0.42)
        scaleAction.timingMode = .easeOut
        let fade = SKAction.sequence([SKAction.wait(forDuration: 0.08), SKAction.fadeOut(withDuration: 0.34)])
        ring.run(SKAction.group([scaleAction, fade])) { [weak ring] in
            ring?.removeFromParent()
        }
    }

    // MARK: - Ember Orbit (orbiting embers, continuous per-target-cooldown damage)

    private func updateEmberOrbit(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        guard level(of: .emberOrbit) > 0 else {
            if !emberOrbiters.isEmpty { clearEmberOrbiters() }
            return
        }
        let lvl = level(of: .emberOrbit)
        let stats = Balance.weaponStats(.emberOrbit, level: lvl)
        let desiredCount = stats.projectileCount + player.multishotLevel
        if emberOrbiters.count != desiredCount { rebuildEmberOrbiters(count: desiredCount) }
        guard !emberOrbiters.isEmpty else { return }

        emberAngle += stats.projectileSpeed * CGFloat(deltaTime)
        let rotations = Int(abs(emberAngle) / (2 * .pi))
        if rotations > emberRotationsCompleted {
            emberRotationsCompleted = rotations
            AudioManager.shared.playSFX(.weaponFire(.emberOrbit))
        }

        let radius = stats.areaRadius
        let hitInterval = effectiveInterval(baseInterval: stats.interval, player: player)
        let hitRadiusSquared = Self.orbiterHitRadius * Self.orbiterHitRadius

        for (index, orb) in emberOrbiters.enumerated() {
            let angle = emberAngle + (CGFloat(index) / CGFloat(emberOrbiters.count)) * (2 * .pi)
            let pos = CGPoint(x: player.position.x + cos(angle) * radius, y: player.position.y + sin(angle) * radius)
            orb.position = pos

            for enemy in enemies {
                guard enemy.isAlive else { continue }
                let dx = enemy.position.x - pos.x
                let dy = enemy.position.y - pos.y
                guard dx * dx + dy * dy <= hitRadiusSquared else { continue }
                let key = OrbitHitKey(orbiterIndex: index, enemyID: ObjectIdentifier(enemy))
                let last = emberHitCooldowns[key] ?? -.greatestFiniteMagnitude
                guard now - last >= hitInterval else { continue }
                emberHitCooldowns[key] = now
                let (dmg, isCrit) = rollDamage(base: stats.damage, player: player)
                resolveHit(on: enemy, damage: dmg, isCrit: isCrit, hitColor: emberColor, weapon: .emberOrbit, now: now)
            }
        }
    }

    private func rebuildEmberOrbiters(count: Int) {
        clearEmberOrbiters()
        for _ in 0..<max(0, count) {
            emberOrbiters.append(makeEmberOrbNode())
        }
        emberHitCooldowns.removeAll(keepingCapacity: true)
    }

    private func clearEmberOrbiters() {
        for node in emberOrbiters { node.removeFromParent() }
        emberOrbiters.removeAll()
    }

    private func makeEmberOrbNode() -> SKShapeNode {
        let node = SKShapeNode(circleOfRadius: 9)
        node.fillColor = emberColor
        node.strokeColor = SKColor(red: 1, green: 0.78, blue: 0.42, alpha: 1)
        node.lineWidth = 1.5
        node.glowWidth = 6
        node.blendMode = .add
        node.zPosition = ZPosition.weaponOrbiter
        worldLayer.addChild(node)
        return node
    }

    // MARK: - Reaper Whirl / Crimson Maelstrom (melee blades, continuous per-target-cooldown damage)

    private func updateReaperWhirlFamily(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        guard level(of: .reaperWhirl) > 0 else {
            if !whirlBlades.isEmpty { clearWhirlBlades() }
            return
        }
        let evolved = evolvedWeapons.contains(.crimsonMaelstrom)
        let stats: WeaponLevelStats
        let desiredCount: Int
        if evolved {
            stats = Balance.evolvedStats(.crimsonMaelstrom)
            desiredCount = stats.projectileCount
        } else {
            let lvl = level(of: .reaperWhirl)
            stats = Balance.weaponStats(.reaperWhirl, level: lvl)
            desiredCount = stats.projectileCount + player.multishotLevel
        }
        if whirlBlades.count != desiredCount { rebuildWhirlBlades(count: desiredCount, evolved: evolved) }
        guard !whirlBlades.isEmpty else { return }

        whirlAngle += stats.projectileSpeed * CGFloat(deltaTime)
        let rotations = Int(abs(whirlAngle) / (2 * .pi))
        if rotations > whirlRotationsCompleted {
            whirlRotationsCompleted = rotations
            AudioManager.shared.playSFX(.weaponFire(.reaperWhirl))
        }

        let radius = stats.areaRadius
        let hitInterval = effectiveInterval(baseInterval: stats.interval, player: player)
        let hitRadiusSquared = Self.orbiterHitRadius * Self.orbiterHitRadius

        for (index, blade) in whirlBlades.enumerated() {
            let angle = whirlAngle + (CGFloat(index) / CGFloat(whirlBlades.count)) * (2 * .pi)
            let pos = CGPoint(x: player.position.x + cos(angle) * radius, y: player.position.y + sin(angle) * radius)
            blade.position = pos
            blade.zRotation = angle

            for enemy in enemies {
                guard enemy.isAlive else { continue }
                let dx = enemy.position.x - pos.x
                let dy = enemy.position.y - pos.y
                guard dx * dx + dy * dy <= hitRadiusSquared else { continue }
                let key = OrbitHitKey(orbiterIndex: index, enemyID: ObjectIdentifier(enemy))
                let last = whirlHitCooldowns[key] ?? -.greatestFiniteMagnitude
                guard now - last >= hitInterval else { continue }
                whirlHitCooldowns[key] = now
                let (dmg, isCrit) = rollDamage(base: stats.damage, player: player)
                resolveHit(on: enemy, damage: dmg, isCrit: isCrit, hitColor: bloodColor, weapon: .reaperWhirl, now: now)
                if evolved {
                    player.heal(Balance.crimsonMaelstromLifestealFraction * dmg)
                }
            }
        }
    }

    private func rebuildWhirlBlades(count: Int, evolved: Bool) {
        clearWhirlBlades()
        for _ in 0..<max(0, count) {
            whirlBlades.append(makeWhirlBladeNode(evolved: evolved))
        }
        whirlHitCooldowns.removeAll(keepingCapacity: true)
    }

    private func clearWhirlBlades() {
        for node in whirlBlades { node.removeFromParent() }
        whirlBlades.removeAll()
    }

    private func makeWhirlBladeNode(evolved: Bool) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -6, y: 0))
        path.addQuadCurve(to: CGPoint(x: 30, y: 11), control: CGPoint(x: 16, y: 24))
        path.addQuadCurve(to: CGPoint(x: -6, y: 0), control: CGPoint(x: 16, y: -5))
        path.closeSubpath()
        let node = SKShapeNode(path: path)
        node.fillColor = evolved ? SKColor(red: 0.95, green: 0.05, blue: 0.12, alpha: 1) : bloodColor
        node.strokeColor = SKColor(red: 0.97, green: 0.94, blue: 1.0, alpha: 0.9)
        node.lineWidth = evolved ? 1.8 : 1.2
        node.glowWidth = evolved ? 6 : 3
        node.blendMode = .alpha
        node.zPosition = ZPosition.meleeWhirl
        worldLayer.addChild(node)
        return node
    }

    // MARK: - Star Shard (single shot at nearest enemy; fragments into two more on impact or expiry)

    private func updateStarShard(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        guard level(of: .starShard) > 0 else { return }
        let lvl = level(of: .starShard)
        let stats = Balance.weaponStats(.starShard, level: lvl)
        var countdown = (fireCountdown[.starShard] ?? 0) - deltaTime
        if countdown <= 0 {
            if let target = nearestEnemy(to: player.position, in: enemies) {
                let baseDir = CGVector(dx: target.position.x - player.position.x, dy: target.position.y - player.position.y)
                let count = stats.projectileCount + player.multishotLevel
                fireSpreadVolley(kind: .starShard, count: count, baseDirection: baseDir, baseDamage: stats.damage,
                                  speed: stats.projectileSpeed, pierce: stats.pierce, range: stats.range,
                                  homing: false, origin: player.position, player: player)
                AudioManager.shared.playSFX(.weaponFire(.starShard))
            }
            countdown = effectiveInterval(baseInterval: stats.interval, player: player)
        }
        fireCountdown[.starShard] = countdown
    }

    /// Spawns two smaller fragments diverging from the parent shard's final direction. Fragments never
    /// fragment again — tracked via `fragmentProjectileIDs` — and inherit the parent's already-resolved
    /// damage/crit (scaled down), so no second crit roll or double damage-multiplier application.
    private func spawnStarShardFragments(from parent: Projectile) {
        let stats = Balance.weaponStats(.starShard, level: level(of: .starShard))
        let fragmentDamage = parent.damage * 0.55
        let fragmentRange = max(120, stats.range * 0.55)
        for offset: CGFloat in [0.55, -0.55] {
            let dir = rotate(parent.velocity, by: offset)
            let fragment = PoolManager.shared.dequeueProjectile()
            fragment.configure(kind: .starShard, damage: fragmentDamage, isCrit: parent.isCrit,
                                position: parent.position, direction: dir, speed: stats.projectileSpeed,
                                pierce: 0, maxRange: fragmentRange, homing: false, homingTarget: nil)
            fragmentProjectileIDs.insert(ObjectIdentifier(fragment))
            liveProjectiles.append(fragment)
        }
    }

    // MARK: - Void Rift (curse zone: pulls enemies in, burns them over time, then fades)

    private func updateVoidRift(deltaTime: TimeInterval, now: TimeInterval, player: PlayerController, enemies: [Enemy]) {
        // 1. Fire timer: spawn a new rift centered on a random nearby enemy, if any exist to curse.
        if level(of: .voidRift) > 0 {
            let lvl = level(of: .voidRift)
            let stats = Balance.weaponStats(.voidRift, level: lvl)
            var countdown = (fireCountdown[.voidRift] ?? 0) - deltaTime
            if countdown <= 0 {
                if let target = enemies.filter({ $0.isAlive }).randomElement() {
                    spawnVoidRift(at: target.position, stats: stats)
                    AudioManager.shared.playSFX(.weaponFire(.voidRift))
                }
                countdown = effectiveInterval(baseInterval: stats.interval, player: player)
            }
            fireCountdown[.voidRift] = countdown
        }

        // 2. Advance every active rift: pull + tick-damage anything inside, then expire.
        guard !activeRifts.isEmpty else { return }
        var index = 0
        while index < activeRifts.count {
            activeRifts[index].remainingLifetime -= deltaTime
            if activeRifts[index].remainingLifetime <= 0 {
                activeRifts[index].node.removeFromParent()
                activeRifts.remove(at: index)
                continue
            }

            let rift = activeRifts[index]
            let radiusSquared = rift.radius * rift.radius
            for enemy in enemies {
                guard enemy.isAlive else { continue }
                let dx = rift.position.x - enemy.position.x
                let dy = rift.position.y - enemy.position.y
                let distSq = dx * dx + dy * dy
                guard distSq <= radiusSquared else { continue }

                let dist = max(1, sqrt(distSq))
                let pull = rift.pullStrength * CGFloat(deltaTime)
                enemy.position = CGPoint(x: enemy.position.x + dx / dist * pull, y: enemy.position.y + dy / dist * pull)

                let enemyID = ObjectIdentifier(enemy)
                let last = activeRifts[index].lastTickTimes[enemyID] ?? -.greatestFiniteMagnitude
                guard now - last >= Self.voidRiftTickInterval else { continue }
                activeRifts[index].lastTickTimes[enemyID] = now
                let (dmg, isCrit) = rollDamage(base: rift.damage, player: player)
                resolveHit(on: enemy, damage: dmg, isCrit: isCrit, hitColor: violetColor, weapon: .voidRift, now: now)
            }
            index += 1
        }
    }

    private func spawnVoidRift(at position: CGPoint, stats: WeaponLevelStats) {
        let node = SKShapeNode(circleOfRadius: stats.areaRadius)
        node.position = position
        node.fillColor = violetColor.withAlphaComponent(0.22)
        node.strokeColor = violetColor.withAlphaComponent(0.9)
        node.lineWidth = 3
        node.glowWidth = 10
        node.blendMode = .alpha
        node.zPosition = ZPosition.weaponOrbiter
        node.alpha = 0
        worldLayer.addChild(node)
        node.run(SKAction.fadeAlpha(to: 1.0, duration: 0.18))
        node.run(SKAction.repeatForever(SKAction.sequence([
            SKAction.scale(to: 1.08, duration: 0.5),
            SKAction.scale(to: 0.96, duration: 0.5)
        ])))

        activeRifts.append(VoidRiftInstance(node: node, position: position, radius: stats.areaRadius,
                                             damage: stats.damage, pullStrength: stats.projectileSpeed,
                                             remainingLifetime: Self.voidRiftLifetime))
    }

    // MARK: - Projectile spawning / stepping (Fang Bolt, Blood Lance, Bat Swarm, Moonfang Barrage, Star Shard)

    private func spawnProjectile(kind: WeaponKind, baseDamage: CGFloat, direction: CGVector, speed: CGFloat,
                                  pierce: Int, range: CGFloat, homing: Bool, homingTarget: (() -> Enemy?)?,
                                  origin: CGPoint, player: PlayerController, guaranteedCrit: Bool = false) {
        let (dmg, isCrit) = rollDamage(base: baseDamage, player: player, guaranteedCrit: guaranteedCrit)
        let projectile = PoolManager.shared.dequeueProjectile()
        projectile.configure(kind: kind, damage: dmg, isCrit: isCrit, position: origin, direction: direction,
                              speed: speed, pierce: pierce, maxRange: range, homing: homing, homingTarget: homingTarget)
        liveProjectiles.append(projectile)
    }

    /// Fires `count` projectiles at the single nearest-enemy direction, fanned across a small spread arc so
    /// multishot copies don't perfectly overlap. (fangBolt's brief specifies targeting THE nearest enemy —
    /// extra multishot copies stay on that same target rather than picking distinct targets.)
    private func fireSpreadVolley(kind: WeaponKind, count: Int, baseDirection: CGVector, baseDamage: CGFloat,
                                   speed: CGFloat, pierce: Int, range: CGFloat, homing: Bool,
                                   origin: CGPoint, player: PlayerController) {
        let spreadStep: CGFloat = 0.09
        let startOffset = -spreadStep * CGFloat(count - 1) / 2
        for i in 0..<count {
            let offset = startOffset + spreadStep * CGFloat(i)
            let dir = rotate(baseDirection, by: offset)
            spawnProjectile(kind: kind, baseDamage: baseDamage, direction: dir, speed: speed, pierce: pierce,
                             range: range, homing: homing, homingTarget: nil, origin: origin, player: player)
        }
    }

    private func stepProjectiles(deltaTime: TimeInterval, now: TimeInterval, enemies: [Enemy]) {
        guard !liveProjectiles.isEmpty else { return }
        var index = 0
        while index < liveProjectiles.count {
            let projectile = liveProjectiles[index]
            guard projectile.isActive else {
                liveProjectiles.remove(at: index)
                continue
            }

            let expired = projectile.step(deltaTime: deltaTime)
            var shouldRetire = expired

            if !shouldRetire {
                let hitRadiusSquared = Self.projectileHitRadius * Self.projectileHitRadius
                for enemy in enemies {
                    guard enemy.isAlive else { continue }
                    let dx = enemy.position.x - projectile.position.x
                    let dy = enemy.position.y - projectile.position.y
                    guard dx * dx + dy * dy <= hitRadiusSquared else { continue }
                    guard projectile.registerHit(on: enemy) else { continue }
                    resolveHit(on: enemy, damage: projectile.damage, isCrit: projectile.isCrit,
                               hitColor: projectileHitColor(for: projectile.weaponKind),
                               weapon: projectile.weaponKind, now: now)
                    if projectile.isOutOfPierce {
                        shouldRetire = true
                        break
                    }
                }
            }

            if shouldRetire {
                let id = ObjectIdentifier(projectile)
                if projectile.weaponKind == .starShard, !fragmentProjectileIDs.contains(id) {
                    spawnStarShardFragments(from: projectile)
                } else {
                    fragmentProjectileIDs.remove(id)
                }
                PoolManager.shared.enqueueProjectile(projectile)
                liveProjectiles.remove(at: index)
            } else {
                index += 1
            }
        }
    }

    private func projectileHitColor(for kind: WeaponKind) -> SKColor {
        switch kind {
        case .fangBolt: return moonlightColor
        case .bloodLance: return bloodColor
        case .batSwarm: return violetColor
        case .emberOrbit: return emberColor
        case .novaPulse: return novaColor
        case .reaperWhirl: return bloodColor
        case .starShard: return moonlightColor
        case .voidRift: return violetColor // unused (Void Rift has no traveling Projectile), kept for exhaustiveness
        }
    }

    // MARK: - Shared hit resolution

    private func rollDamage(base: CGFloat, player: PlayerController, guaranteedCrit: Bool = false) -> (damage: CGFloat, isCrit: Bool) {
        let isCrit = guaranteedCrit || CGFloat.random(in: 0...1) < player.critChance
        let dmg = base * player.damageMultiplier * (isCrit ? 1 + player.critDamageBonus : 1)
        return (dmg, isCrit)
    }

    private func resolveHit(on enemy: Enemy, damage: CGFloat, isCrit: Bool, hitColor: SKColor, weapon: WeaponKind, now: TimeInterval) {
        let killed = enemy.takeDamage(damage)
        let dmgInt = max(1, Int(damage.rounded()))
        JuiceEffects.hitBurst(at: enemy.position, color: isCrit ? critColor : hitColor, scale: isCrit ? 1.7 : 1.0)
        JuiceEffects.damageNumber(dmgInt, isCrit: isCrit, at: enemy.position)
        AudioManager.shared.playSFX(.enemyHit)
        if isCrit { requestCritShake(now: now) }
        if let player = player, player.lifestealFraction > 0 { player.heal(damage * player.lifestealFraction) }
        if killed { handleKill(enemy: enemy, weapon: weapon) }
    }

    private func handleKill(enemy: Enemy, weapon: WeaponKind) {
        JuiceEffects.hitBurst(at: enemy.position, color: killFlashColor, scale: enemy.isMiniBoss ? 3.2 : 1.8)
        if enemy.isMiniBoss {
            AudioManager.shared.playSFX(.miniBossDeath)
            AudioManager.shared.hapticNotification(.success)
            onShakeRequest?(20, 0.5)
        } else {
            AudioManager.shared.playSFX(.enemyDeath)
        }
        onEnemyDefeated?(enemy)
    }

    private func requestCritShake(now: TimeInterval) {
        guard now - lastCritShakeTime >= Self.critShakeDebounce else { return }
        lastCritShakeTime = now
        onShakeRequest?(4, 0.12)
    }

    // MARK: - Small math helpers

    private func nearestEnemy(to point: CGPoint, in enemies: [Enemy]) -> Enemy? {
        var best: Enemy?
        var bestDistSq = CGFloat.greatestFiniteMagnitude
        for enemy in enemies {
            guard enemy.isAlive else { continue }
            let dx = enemy.position.x - point.x
            let dy = enemy.position.y - point.y
            let distSq = dx * dx + dy * dy
            if distSq < bestDistSq {
                bestDistSq = distSq
                best = enemy
            }
        }
        return best
    }

    private func rotate(_ v: CGVector, by angle: CGFloat) -> CGVector {
        let cosA = cos(angle), sinA = sin(angle)
        return CGVector(dx: v.dx * cosA - v.dy * sinA, dy: v.dx * sinA + v.dy * cosA)
    }

    private func effectiveInterval(baseInterval: TimeInterval, player: PlayerController) -> TimeInterval {
        max(0.12, baseInterval * TimeInterval(player.fireRateMultiplier))
    }
}
