import SpriteKit

/// Drives the rare in-run potion pickup loop: a pooled Potion spawns at a random distance from the
/// player on a jittered timer (faster with the Alchemist's Eye meta upgrade), idles/expires on its own,
/// and gets collected the instant the player walks within PotionConfig.pickupRadius of it. GameScene owns
/// this object, calls `update(deltaTime:now:playerPosition:)` once per frame (after XPSystem.update()),
/// and reacts to `onPotionCollected` by applying the actual per-kind effect via
/// PlayerController/XPSystem — this system deliberately has no reference to either beyond construction.
final class PotionSystem {
    /// Fired the instant a potion is collected, AFTER it's already been retired to the pool and any
    /// pickup juice/SFX played.
    var onPotionCollected: ((PotionKind) -> Void)?

    private weak var worldLayer: SKNode?
    private let player: PlayerController
    private var livePotions: [Potion] = []
    private var timeUntilNextSpawn: TimeInterval

    init(worldLayer: SKNode, player: PlayerController) {
        self.worldLayer = worldLayer
        self.player = player
        self.timeUntilNextSpawn = PotionSystem.rollSpawnInterval()
    }

    /// Call once per frame, after XPSystem.update(). Advances the spawn timer, updates/expires every
    /// live potion, and checks pickup distance against the player.
    func update(deltaTime: TimeInterval, now: TimeInterval, playerPosition: CGPoint) {
        guard deltaTime > 0, worldLayer != nil else { return }

        timeUntilNextSpawn -= deltaTime
        if timeUntilNextSpawn <= 0 {
            spawnPotion(near: playerPosition)
            timeUntilNextSpawn = PotionSystem.rollSpawnInterval()
        }

        guard !livePotions.isEmpty else { return }
        let pickupRadiusSq = PotionConfig.pickupRadius * PotionConfig.pickupRadius

        var i = 0
        while i < livePotions.count {
            let potion = livePotions[i]
            let expired = potion.update(deltaTime: deltaTime)
            if expired {
                retireExpired(potion, at: i)
                continue // array shrank in place — re-check the same index
            }

            let dx = playerPosition.x - potion.position.x
            let dy = playerPosition.y - potion.position.y
            if dx * dx + dy * dy <= pickupRadiusSq {
                collect(potion, at: i)
                continue // array shrank in place — re-check the same index
            }

            i += 1
        }
    }

    // MARK: - Spawning

    private func spawnPotion(near playerPosition: CGPoint) {
        // Defensive cap mirroring PoolManager's own hardPotionCap — keeps this system from ever asking
        // the pool for more concurrent potions than it can actually back with distinct nodes.
        guard livePotions.count < PoolConfig.hardPotionCap else { return }
        guard let kind = PotionKind.allCases.randomElement() else { return }

        let potion = PoolManager.shared.dequeuePotion()
        potion.configure(kind: kind, at: randomSpawnPosition(near: playerPosition))
        livePotions.append(potion)
    }

    private func randomSpawnPosition(near playerPosition: CGPoint) -> CGPoint {
        let angle = CGFloat.random(in: 0..<(2 * .pi))
        let distance = CGFloat.random(in: PotionConfig.spawnDistanceMin...PotionConfig.spawnDistanceMax)
        var point = CGPoint(x: playerPosition.x + cos(angle) * distance,
                             y: playerPosition.y + sin(angle) * distance)

        let bounds = WorldConfig.bounds
        let inset = PotionConfig.visualRadius
        point.x = min(max(point.x, bounds.minX + inset), bounds.maxX - inset)
        point.y = min(max(point.y, bounds.minY + inset), bounds.maxY - inset)
        return point
    }

    /// Average PotionConfig.baseSpawnInterval seconds between spawns, +/- spawnIntervalJitter rolled
    /// fresh per interval, tightened per Alchemist's Eye (potionLuck) tier, floored at a sane minimum so
    /// even max luck can never spawn absurdly fast.
    private static func rollSpawnInterval() -> TimeInterval {
        let luckTier = MetaProgressionStore.shared.tier(for: .potionLuck)
        let reduction = 1.0 - Double(luckTier) * PotionConfig.luckIntervalReductionPerTier
        let base = PotionConfig.baseSpawnInterval * max(0.1, reduction)
        let jitter = TimeInterval.random(in: -PotionConfig.spawnIntervalJitter...PotionConfig.spawnIntervalJitter)
        return max(6, base + jitter)
    }

    // MARK: - Retirement

    /// O(1) removal — potion order doesn't matter, so swap the last element into this slot (mirrors
    /// XPSystem.liveGems). A quick fade plays before the node actually returns to the pool.
    private func retireExpired(_ potion: Potion, at index: Int) {
        livePotions.swapAt(index, livePotions.count - 1)
        livePotions.removeLast()
        potion.removeAllActions()
        potion.run(SKAction.fadeOut(withDuration: 0.25)) {
            PoolManager.shared.enqueuePotion(potion)
        }
    }

    private func collect(_ potion: Potion, at index: Int) {
        let kind = potion.kind
        let position = potion.position

        livePotions.swapAt(index, livePotions.count - 1)
        livePotions.removeLast()
        potion.removeAllActions()
        PoolManager.shared.enqueuePotion(potion)

        playPickupJuice(kind: kind, at: position)
        onPotionCollected?(kind)
    }

    private func playPickupJuice(kind: PotionKind, at position: CGPoint) {
        JuiceEffects.hitBurst(at: position, color: Potion.accentColor(for: kind), scale: kind == .risingMoon ? 2.0 : 1.4)
        switch kind {
        case .risingMoon:
            AudioManager.shared.playSFX(.levelUp) // it IS a free level
        case .voidMagnet, .bloodFrenzy:
            AudioManager.shared.playSFX(.evolution)
        default:
            AudioManager.shared.playSFX(.gemPickup)
        }
    }
}
