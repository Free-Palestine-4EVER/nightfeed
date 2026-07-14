import SpriteKit

/// Wave director + enemy AI. Owns per-frame enemy movement/separation/steering, timed spawning of the
/// regular swarm, the Nightmaw mini-boss cadence, and enemy-vs-player contact damage. Deliberately does
/// NOT use SKPhysicsBody/SKPhysicsContactDelegate — every check here is a manual distance test accelerated
/// by `SpatialGrid` so hundreds of concurrent enemies stay cheap (no O(n^2) all-pairs loops).
final class EnemySpawner {

    private(set) var totalKills: Int = 0
    private(set) var miniBossKills: Int = 0

    /// Rebuilt every `update()` call from `PoolManager.shared.activeEnemies`. Exposed for other systems
    /// that might want neighbor queries later; nothing outside this file currently reads it.
    let grid = SpatialGrid()

    /// Optional hook for GameScene to layer extra mini-boss-spawn spectacle (camera punch, warning banner,
    /// vignette flash, ...) on top of the world-layer shake this system already performs directly below
    /// (it owns a `worldLayer` reference for exactly that purpose).
    var onMiniBossSpawned: (() -> Void)?

    private let worldLayer: SKNode
    private let player: PlayerController

    private var spawnAccumulator: TimeInterval = 0
    private var nextMiniBossTime: TimeInterval = DifficultyConfig.miniBossInterval

    // MARK: - Tuning

    /// Neighbor radius used for the mild enemy-enemy separation nudge (spec range: ~40-50pt).
    private static let separationRadius: CGFloat = 46
    /// Keeps separation as a gentle "don't stack" nudge rather than true flocking — chasing the player
    /// always dominates because separation is capped to unit length before this weight is applied.
    private static let separationWeight: CGFloat = 0.6
    /// Bloodbat perpendicular wobble weight — a light weave, not a random walk.
    private static let wanderWeight: CGFloat = 0.55
    private static let wanderFrequency: Double = 3.4

    /// Half-width of the enemy's base 44x44 art at scale 1.0 (see Enemy.makeNode), used for contact-range
    /// hit-testing scaled by the enemy's current visual scale.
    private static let baseEnemyVisualRadius: CGFloat = 22

    /// Safety cap so a huge deltaTime spike (e.g. returning from background) can't spin the spawn loop
    /// for an unbounded number of iterations in a single update — see DifficultyConfig.maxSpawnsPerFrame.
    private static let maxDeltaTime: TimeInterval = 1.0 / 15.0

    private static let spawnMarginRange: ClosedRange<CGFloat> = 120...300

    private static let miniBossSpawnShakeMagnitude: CGFloat = 14
    private static let miniBossSpawnShakeDuration: TimeInterval = 0.4
    private static let miniBossDeathShakeMagnitude: CGFloat = 24
    private static let miniBossDeathShakeDuration: TimeInterval = 0.55

    init(worldLayer: SKNode, player: PlayerController) {
        self.worldLayer = worldLayer
        self.player = player
    }

    // MARK: - Per-frame update

    /// Call once per frame, BEFORE WeaponSystem.update(). `cameraPosition`/`viewSize` describe the current
    /// visible viewport in world coordinates.
    func update(deltaTime: TimeInterval, now: TimeInterval, runTime: TimeInterval,
                cameraPosition: CGPoint, viewSize: CGSize) {
        let clampedDelta = min(deltaTime, Self.maxDeltaTime)
        let dt = CGFloat(clampedDelta)
        let enemies = PoolManager.shared.activeEnemies

        // 1. Rebuild the spatial grid from every currently-active enemy.
        grid.clear()
        for enemy in enemies { grid.insert(enemy) }

        // 2. Move + separate + clamp every active enemy.
        let bounds = WorldConfig.bounds
        for enemy in enemies {
            move(enemy, deltaTime: dt, now: now, bounds: bounds)
        }

        // 3. Regular wave spawning.
        updateSpawning(deltaTime: clampedDelta, runTime: runTime, cameraPosition: cameraPosition, viewSize: viewSize)

        // 4. Mini-boss cadence.
        updateMiniBossTimer(runTime: runTime, cameraPosition: cameraPosition, viewSize: viewSize)

        // 5. Enemy-vs-player contact damage.
        applyContactDamage(enemies: enemies, now: now)
    }

    // MARK: - Defeat

    /// Called by the scene (wired from WeaponSystem.onEnemyDefeated) when an enemy's HP hits 0.
    /// Does NOT drop XP — the scene reads enemy.xpValue/position itself before calling this.
    func registerDefeat(_ enemy: Enemy) {
        // Defensive: prepareForReuse() hides the node, so a duplicate call on an already-retired enemy is a no-op.
        guard !enemy.isHidden else { return }

        let isBoss = enemy.isMiniBoss
        totalKills += 1
        if isBoss { miniBossKills += 1 }

        JuiceEffects.hitBurst(at: enemy.position, color: burstColor(for: enemy.kind), scale: isBoss ? 2.6 : 1.3)
        AudioManager.shared.playSFX(isBoss ? .miniBossDeath : .enemyDeath)

        if isBoss {
            AudioManager.shared.hapticNotification(.success)
            JuiceEffects.shake(node: worldLayer, magnitude: Self.miniBossDeathShakeMagnitude, duration: Self.miniBossDeathShakeDuration)
        }

        PoolManager.shared.enqueueEnemy(enemy)
    }

    // MARK: - Movement & separation

    private func move(_ enemy: Enemy, deltaTime: CGFloat, now: TimeInterval, bounds: CGRect) {
        let toPlayer = CGPoint(x: player.position.x - enemy.position.x, y: player.position.y - enemy.position.y)
        let distToPlayer = hypot(toPlayer.x, toPlayer.y)
        let seekDir: CGPoint = distToPlayer > 0.0001
            ? CGPoint(x: toPlayer.x / distToPlayer, y: toPlayer.y / distToPlayer)
            : .zero

        // Mild separation from nearby enemies, grid-accelerated (never a full nested loop over all enemies).
        var separation = CGPoint.zero
        let neighbors = grid.neighbors(around: enemy.position, radius: Self.separationRadius)
        for other in neighbors where other !== enemy {
            let dx = enemy.position.x - other.position.x
            let dy = enemy.position.y - other.position.y
            let dist = hypot(dx, dy)
            guard dist > 0.0001, dist < Self.separationRadius else { continue }
            let falloff = (Self.separationRadius - dist) / Self.separationRadius
            separation.x += (dx / dist) * falloff
            separation.y += (dy / dist) * falloff
        }
        let separationLen = hypot(separation.x, separation.y)
        if separationLen > 1 {
            separation.x /= separationLen
            separation.y /= separationLen
        }

        // Bloodbats weave with a light perpendicular sine wobble instead of flying dead straight.
        var wobble = CGPoint.zero
        if enemy.kind == .bloodbat {
            let perp = CGPoint(x: -seekDir.y, y: seekDir.x)
            let wave = CGFloat(sin(now * Self.wanderFrequency + Double(enemy.wanderSeed)))
            wobble = CGPoint(x: perp.x * wave, y: perp.y * wave)
        }

        var dir = CGPoint(
            x: seekDir.x + separation.x * Self.separationWeight + wobble.x * Self.wanderWeight,
            y: seekDir.y + separation.y * Self.separationWeight + wobble.y * Self.wanderWeight
        )
        let dirLen = hypot(dir.x, dir.y)
        if dirLen > 0.0001 {
            dir.x /= dirLen
            dir.y /= dirLen
        } else {
            dir = seekDir
        }

        var newPosition = CGPoint(
            x: enemy.position.x + dir.x * enemy.moveSpeed * deltaTime,
            y: enemy.position.y + dir.y * enemy.moveSpeed * deltaTime
        )
        newPosition.x = min(max(newPosition.x, bounds.minX), bounds.maxX)
        newPosition.y = min(max(newPosition.y, bounds.minY), bounds.maxY)
        enemy.position = newPosition

        // Face the direction of travel (the procedural art places each enemy's "eyes" toward local +Y).
        if dirLen > 0.0001 {
            enemy.zRotation = atan2(dir.y, dir.x) - .pi / 2
        }
    }

    // MARK: - Regular spawning

    /// `spawnAccumulator` holds fractional "seconds of spawn debt" scaled by the current spawn rate, so a
    /// whole enemy spawns exactly once the accumulator crosses 1.0 — this gives a perfectly smooth,
    /// frame-rate-independent ramp instead of coarse fixed-tick/integer-count jumps.
    private func updateSpawning(deltaTime: TimeInterval, runTime: TimeInterval, cameraPosition: CGPoint, viewSize: CGSize) {
        let rate = Balance.spawnRatePerSecond(runTime: runTime)
        spawnAccumulator += deltaTime * rate
        guard spawnAccumulator >= 1.0 else { return }

        // Weights only depend on runTime, not on which spawn this is — compute once per call, not once
        // per enemy (Balance.spawnWeights allocates a dictionary, so this matters at higher spawn rates).
        let minute = CGFloat(runTime / 60)
        let weights = Balance.spawnWeights(atMinute: minute)

        var spawned = 0
        while spawnAccumulator >= 1.0 && spawned < DifficultyConfig.maxSpawnsPerFrame {
            guard PoolManager.shared.activeEnemyCount < DifficultyConfig.maxActiveEnemies else {
                spawnAccumulator = 0 // at the population cap — drop the debt rather than let it queue up
                break
            }
            spawnAccumulator -= 1.0
            spawned += 1
            spawnOneEnemy(weights: weights, runTime: runTime, cameraPosition: cameraPosition, viewSize: viewSize)
        }
    }

    private func spawnOneEnemy(weights: [EnemyKind: Double], runTime: TimeInterval, cameraPosition: CGPoint, viewSize: CGSize) {
        guard let kind = weightedRandomKind(from: weights) else { return }
        let stats = Balance.enemyStats(kind, runTime: runTime)
        let position = randomSpawnPosition(cameraPosition: cameraPosition, viewSize: viewSize)
        let wanderSeed = CGFloat.random(in: 0..<(CGFloat.pi * 2))
        PoolManager.shared.dequeueEnemy().configure(kind: kind, stats: stats, position: position, wanderSeed: wanderSeed)
    }

    /// Weighted random pick among positive-weight entries. `Balance.spawnWeights` always zeroes out
    /// `.nightmaw` (spawned only via the explicit mini-boss timer below), so it never wins this roll.
    private func weightedRandomKind(from weights: [EnemyKind: Double]) -> EnemyKind? {
        let positive = weights.filter { $0.value > 0 }
        let total = positive.values.reduce(0, +)
        guard total > 0 else { return nil }
        var roll = Double.random(in: 0..<total)
        for (kind, weight) in positive {
            if roll < weight { return kind }
            roll -= weight
        }
        return positive.keys.first
    }

    /// Picks a point just outside the current viewport (120-300pt beyond a random edge), offset to world
    /// space by `cameraPosition`, then clamped inside the playable arena — enemies never visibly pop in.
    private func randomSpawnPosition(cameraPosition: CGPoint, viewSize: CGSize) -> CGPoint {
        let margin = CGFloat.random(in: Self.spawnMarginRange)
        let halfW = viewSize.width / 2
        let halfH = viewSize.height / 2
        var point: CGPoint
        switch Int.random(in: 0..<4) {
        case 0: point = CGPoint(x: CGFloat.random(in: -halfW...halfW), y: halfH + margin)       // top
        case 1: point = CGPoint(x: CGFloat.random(in: -halfW...halfW), y: -halfH - margin)      // bottom
        case 2: point = CGPoint(x: -halfW - margin, y: CGFloat.random(in: -halfH...halfH))      // left
        default: point = CGPoint(x: halfW + margin, y: CGFloat.random(in: -halfH...halfH))      // right
        }
        point.x += cameraPosition.x
        point.y += cameraPosition.y
        return clampToWorldBounds(point)
    }

    private func clampToWorldBounds(_ point: CGPoint) -> CGPoint {
        let bounds = WorldConfig.bounds
        return CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                        y: min(max(point.y, bounds.minY), bounds.maxY))
    }

    // MARK: - Mini-boss cadence

    private func updateMiniBossTimer(runTime: TimeInterval, cameraPosition: CGPoint, viewSize: CGSize) {
        while runTime >= nextMiniBossTime {
            nextMiniBossTime += DifficultyConfig.miniBossInterval
            spawnMiniBoss(runTime: runTime, cameraPosition: cameraPosition, viewSize: viewSize)
        }
    }

    private func spawnMiniBoss(runTime: TimeInterval, cameraPosition: CGPoint, viewSize: CGSize) {
        // Nightmaw ignores the normal weighted roll and the soft active-enemy cap — it's a scheduled,
        // guaranteed encounter, not part of the ambient swarm. PoolManager's hard cap is still respected
        // implicitly by dequeueEnemy() itself.
        let stats = Balance.enemyStats(.nightmaw, runTime: runTime)
        let position = randomSpawnPosition(cameraPosition: cameraPosition, viewSize: viewSize)
        PoolManager.shared.dequeueEnemy().configure(kind: .nightmaw, stats: stats, position: position, wanderSeed: 0)

        AudioManager.shared.playSFX(.miniBossSpawn)
        AudioManager.shared.hapticNotification(.warning)
        JuiceEffects.shake(node: worldLayer, magnitude: Self.miniBossSpawnShakeMagnitude, duration: Self.miniBossSpawnShakeDuration)
        onMiniBossSpawned?()
    }

    // MARK: - Player contact damage

    private func applyContactDamage(enemies: [Enemy], now: TimeInterval) {
        guard !player.isDead else { return }
        let playerRadius = PlayerConfig.radius
        for enemy in enemies {
            let enemyRadius = Self.baseEnemyVisualRadius * enemy.xScale
            let contactRange = enemyRadius + playerRadius
            let dx = enemy.position.x - player.position.x
            let dy = enemy.position.y - player.position.y
            guard dx * dx + dy * dy <= contactRange * contactRange else { continue }
            guard enemy.canTickContactDamage(now: now) else { continue }
            // PlayerController.takeContactDamage already plays .playerHit SFX + a heavy haptic and gates
            // itself on its own post-hit invulnerability window when the hit actually lands — nothing
            // further to trigger here.
            player.takeContactDamage(enemy.contactDamage, now: now)
        }
    }

    // MARK: - Palette

    private func burstColor(for kind: EnemyKind) -> SKColor {
        switch kind {
        case .swarmling: return SKColor(red: 0.72, green: 0.25, blue: 0.85, alpha: 1)   // deep violet
        case .bloodbat: return SKColor(red: 0.85, green: 0.10, blue: 0.18, alpha: 1)    // blood red
        case .hollowBrute: return SKColor(red: 0.85, green: 0.24, blue: 0.22, alpha: 1) // dull ember red
        case .nightmaw: return SKColor(red: 1.0, green: 0.55, blue: 0.16, alpha: 1)     // ember orange
        }
    }
}
