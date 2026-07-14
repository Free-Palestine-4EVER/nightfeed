import SpriteKit

/// Central object pool. Enemies, projectiles, XP gems, damage-number labels and hit-particle emitters
/// are allocated once at prewarm and recycled for the rest of the app's lifetime — never allocated or
/// deallocated per spawn, per the performance requirement of hundreds of concurrent entities at 60fps.
///
/// Enemy/Projectile/Gem dequeue is O(1): a small "free stack" holds exactly the currently-available
/// objects, popped on dequeue and pushed back by `enqueue*` on retirement. (An earlier version searched
/// the whole pool with `first(where:)` on every single spawn — cheap at a handful of entities, but a
/// real per-spawn cost once hundreds of enemies are alive and the free slots are sparse among them; that
/// showed up as visible stutter under heavy waves.) Damage labels and hit emitters keep the simpler
/// linear-scan dequeue since their pools are small (≤24) and self-retire via their own SKAction
/// completions rather than an explicit "defeated" call site — not worth the extra plumbing at that scale.
final class PoolManager {
    static let shared = PoolManager()
    private init() {}

    private var enemyPool: [Enemy] = []
    private var freeEnemies: [Enemy] = []

    private var projectilePool: [Projectile] = []
    private var freeProjectiles: [Projectile] = []

    private var gemPool: [XPGem] = []
    private var freeGems: [XPGem] = []

    private var potionPool: [Potion] = []
    private var freePotions: [Potion] = []

    private var damageLabelPool: [SKLabelNode] = []
    private var emitterPool: [SKEmitterNode] = []

    private(set) weak var worldLayer: SKNode?

    /// Call once every time GameScene is set up (i.e. once per run). Each run gets a brand new `worldLayer`
    /// node (a fresh SKScene is presented per run), so pooled nodes from a previous run — still parented to
    /// that now-discarded worldLayer — would otherwise never appear in the new scene. Rather than track
    /// cross-run re-parenting, this simply rebuilds every pool fresh against the new layer: a one-time cost
    /// at run-start (scene setup), never during gameplay, which is exactly what the pooling requirement
    /// actually guards against (allocation spikes mid-run, not a handful of allocations at load time).
    func prewarm(worldLayer: SKNode) {
        self.worldLayer = worldLayer

        enemyPool.forEach { $0.removeFromParent() }
        projectilePool.forEach { $0.removeFromParent() }
        gemPool.forEach { $0.removeFromParent() }
        potionPool.forEach { $0.removeFromParent() }
        damageLabelPool.forEach { $0.removeFromParent() }
        emitterPool.forEach { $0.removeFromParent() }

        enemyPool.removeAll(keepingCapacity: true)
        freeEnemies.removeAll(keepingCapacity: true)
        projectilePool.removeAll(keepingCapacity: true)
        freeProjectiles.removeAll(keepingCapacity: true)
        gemPool.removeAll(keepingCapacity: true)
        freeGems.removeAll(keepingCapacity: true)
        potionPool.removeAll(keepingCapacity: true)
        freePotions.removeAll(keepingCapacity: true)
        damageLabelPool.removeAll(keepingCapacity: true)
        emitterPool.removeAll(keepingCapacity: true)

        for _ in 0..<PoolConfig.initialEnemyCount {
            let e = makeEnemy(in: worldLayer)
            enemyPool.append(e)
            freeEnemies.append(e)
        }
        for _ in 0..<PoolConfig.initialProjectileCount {
            let p = makeProjectile(in: worldLayer)
            projectilePool.append(p)
            freeProjectiles.append(p)
        }
        for _ in 0..<PoolConfig.initialGemCount {
            let g = makeGem(in: worldLayer)
            gemPool.append(g)
            freeGems.append(g)
        }
        for _ in 0..<PoolConfig.initialPotionCount {
            let p = makePotion(in: worldLayer)
            potionPool.append(p)
            freePotions.append(p)
        }
        for _ in 0..<PoolConfig.initialDamageLabelCount { damageLabelPool.append(makeDamageLabel(in: worldLayer)) }
        for _ in 0..<PoolConfig.initialEmitterCount { emitterPool.append(makeEmitter(in: worldLayer)) }
    }

    private func makeEnemy(in layer: SKNode) -> Enemy {
        let e = Enemy.makeNode()
        e.prepareForReuse()
        layer.addChild(e)
        return e
    }

    private func makeProjectile(in layer: SKNode) -> Projectile {
        let p = Projectile.makeNode()
        p.prepareForReuse()
        layer.addChild(p)
        return p
    }

    private func makeGem(in layer: SKNode) -> XPGem {
        let g = XPGem.makeNode()
        g.prepareForReuse()
        layer.addChild(g)
        return g
    }

    private func makePotion(in layer: SKNode) -> Potion {
        let p = Potion.makeNode()
        p.prepareForReuse()
        layer.addChild(p)
        return p
    }

    private func makeDamageLabel(in layer: SKNode) -> SKLabelNode {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.fontSize = 22
        label.zPosition = ZPosition.damageNumber
        label.isHidden = true
        label.verticalAlignmentMode = .center
        layer.addChild(label)
        return label
    }

    private func makeEmitter(in layer: SKNode) -> SKEmitterNode {
        let emitter = JuiceEffects.makeHitBurstTemplate()
        emitter.isHidden = true
        emitter.zPosition = ZPosition.hitParticle
        layer.addChild(emitter)
        return emitter
    }

    // MARK: - Enemy dequeue / enqueue (O(1))

    func dequeueEnemy() -> Enemy {
        if let existing = freeEnemies.popLast() { return existing }
        guard enemyPool.count < PoolConfig.hardEnemyCap, let layer = worldLayer else {
            // Pool exhausted at the hard cap — reuse the oldest enemy outright rather than drop the spawn.
            return enemyPool.first { !$0.isAlive } ?? enemyPool[0]
        }
        let e = makeEnemy(in: layer)
        enemyPool.append(e)
        return e
    }

    /// Retires an enemy back to the pool. Callers must use this instead of calling
    /// `enemy.prepareForReuse()` directly, so the free stack stays in sync for O(1) future dequeues.
    func enqueueEnemy(_ enemy: Enemy) {
        enemy.prepareForReuse()
        freeEnemies.append(enemy)
    }

    // MARK: - Projectile dequeue / enqueue (O(1))

    func dequeueProjectile() -> Projectile {
        if let existing = freeProjectiles.popLast() { return existing }
        guard projectilePool.count < PoolConfig.hardProjectileCap, let layer = worldLayer else {
            return projectilePool.first { !$0.isActive } ?? projectilePool[0]
        }
        let p = makeProjectile(in: layer)
        projectilePool.append(p)
        return p
    }

    func enqueueProjectile(_ projectile: Projectile) {
        projectile.prepareForReuse()
        freeProjectiles.append(projectile)
    }

    // MARK: - Gem dequeue / enqueue (O(1))

    func dequeueGem() -> XPGem {
        if let existing = freeGems.popLast() { return existing }
        guard gemPool.count < PoolConfig.hardGemCap, let layer = worldLayer else {
            return gemPool.first { !$0.isActive } ?? gemPool[0]
        }
        let g = makeGem(in: layer)
        gemPool.append(g)
        return g
    }

    func enqueueGem(_ gem: XPGem) {
        gem.prepareForReuse()
        freeGems.append(gem)
    }

    // MARK: - Potion dequeue / enqueue (O(1))

    func dequeuePotion() -> Potion {
        if let existing = freePotions.popLast() { return existing }
        guard potionPool.count < PoolConfig.hardPotionCap, let layer = worldLayer else {
            return potionPool.first { !$0.isActive } ?? potionPool[0]
        }
        let p = makePotion(in: layer)
        potionPool.append(p)
        return p
    }

    func enqueuePotion(_ potion: Potion) {
        potion.prepareForReuse()
        freePotions.append(potion)
    }

    // MARK: - Damage labels / hit emitters (small pools, self-retiring, linear scan is fine)

    func dequeueDamageLabel() -> SKLabelNode {
        if let existing = damageLabelPool.first(where: { $0.isHidden }) {
            return existing
        }
        guard let layer = worldLayer else { return damageLabelPool[0] }
        let l = makeDamageLabel(in: layer)
        damageLabelPool.append(l)
        return l
    }

    func dequeueEmitter() -> SKEmitterNode {
        if let existing = emitterPool.first(where: { $0.isHidden }) {
            return existing
        }
        guard let layer = worldLayer else { return emitterPool[0] }
        let e = makeEmitter(in: layer)
        emitterPool.append(e)
        return e
    }

    // MARK: - Queries

    /// Every active enemy currently live in the world (used by targeting/spatial queries). O(n) — this is
    /// unavoidable live-iteration work (something has to visit every enemy to move/target it), not pool
    /// overhead; the O(1) fix above is specifically about the free-slot *search*, not this iteration.
    var activeEnemies: [Enemy] { enemyPool.filter { $0.isAlive } }
    /// O(1): total pool size minus the free stack, no scan.
    var activeEnemyCount: Int { enemyPool.count - freeEnemies.count }
}
