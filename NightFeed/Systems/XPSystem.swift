import SpriteKit

/// Drives the level-up loop: gems are dropped by kills, drift/magnet toward the player, get collected,
/// and feed a level curve defined once in GameConstants (XPConfig.xpToNextLevel). GameScene owns this
/// object, calls `update(deltaTime:playerPosition:)` once per frame (after WeaponSystem.update() so
/// this-frame kills have already dropped their gems), and reacts to `onLevelUp` by pausing gameplay and
/// presenting the 3-card upgrade UI (built elsewhere, driven by UpgradeManager).
final class XPSystem {
    private(set) var currentLevel: Int = 1
    private(set) var currentXP: Int = 0

    /// XP required to reach `currentLevel + 1` from `currentLevel`, per the frozen curve in GameConstants.
    var xpToNext: Int { XPConfig.xpToNextLevel(currentLevel) }

    /// Progress within the current level, for a HUD bar. 0 when a level was just entered, approaches 1 near the next level.
    var progressFraction: CGFloat {
        let next = xpToNext
        guard next > 0 else { return 0 }
        return CGFloat(currentXP) / CGFloat(next)
    }

    /// Fired once per level gained (in order, possibly more than once from a single update() call if a
    /// big XP gain crosses multiple thresholds). The scene pauses gameplay and shows the upgrade cards in response.
    var onLevelUp: (() -> Void)?

    private weak var worldLayer: SKNode?
    private let player: PlayerController
    private var liveGems: [XPGem] = []

    init(worldLayer: SKNode, player: PlayerController) {
        self.worldLayer = worldLayer
        self.player = player
    }

    /// Spawns a pooled XPGem at the given world position. Called by whatever system kills an enemy
    /// (WeaponSystem, contact damage, etc.) with that enemy's xpValue.
    func dropGem(xpValue: Int, at position: CGPoint) {
        let gem = PoolManager.shared.dequeueGem()
        gem.configure(xpValue: xpValue, at: position)
        liveGems.append(gem)
    }

    /// Call once per frame, after WeaponSystem.update(). Advances every live gem toward the player
    /// (magnetized once inside `player.magnetRadius`) and collects any that arrive.
    func update(deltaTime: TimeInterval, playerPosition: CGPoint) {
        guard !liveGems.isEmpty else { return }
        let magnetRadius = player.magnetRadius

        var i = 0
        while i < liveGems.count {
            let gem = liveGems[i]
            let collected = gem.update(deltaTime: deltaTime, playerPosition: playerPosition, magnetRadius: magnetRadius)
            if collected {
                let xpValue = gem.xpValue
                PoolManager.shared.enqueueGem(gem)
                addXP(xpValue)
                AudioManager.shared.playSFX(.gemPickup)
                // O(1) removal — gem order doesn't matter, so swap the last element into this slot.
                liveGems.swapAt(i, liveGems.count - 1)
                liveGems.removeLast()
            } else {
                i += 1
            }
        }
    }

    /// Instantly collects every gem currently live in the world (the "Void Magnet" potion) — grants
    /// their combined XP in one shot rather than waiting for them to drift in individually.
    func collectAllGems() {
        guard !liveGems.isEmpty else { return }
        var total = 0
        for gem in liveGems {
            total += gem.xpValue
            PoolManager.shared.enqueueGem(gem)
        }
        liveGems.removeAll(keepingCapacity: true)
        AudioManager.shared.playSFX(.gemPickup)
        addXP(total)
    }

    // MARK: - Meta "head start" bonus levels

    /// Grants free levels at run start (the "Blood Ritual" meta upgrade) — bypasses the XP curve entirely
    /// and fires onLevelUp once per bonus level, so the run opens with that many upgrade-choice cards
    /// queued up front, exactly like earning them normally.
    func grantBonusLevels(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            currentLevel += 1
            onLevelUp?()
        }
    }

    // MARK: - XP / leveling

    private func addXP(_ amount: Int) {
        guard amount > 0 else { return }
        currentXP += Int((CGFloat(amount) * player.xpGainMultiplier).rounded())
        while currentXP >= xpToNext {
            let threshold = xpToNext // pre-increment threshold; remainder carries forward into the new level
            currentXP -= threshold
            currentLevel += 1
            AudioManager.shared.playSFX(.levelUp)
            AudioManager.shared.hapticNotification(.success)
            celebrateLevelUp()
            onLevelUp?()
        }
    }

    /// A level-up is one of the biggest positive-feedback moments in the run — JuiceEffects.swift's own
    /// doc comment names "XP system on level-up" as a canonical call site, so this fires a bright burst
    /// at the player plus a light world shake (worldLayer is the "world reference" this system owns).
    private func celebrateLevelUp() {
        let moonlightGold = SKColor(red: 1.0, green: 0.92, blue: 0.55, alpha: 1)
        JuiceEffects.hitBurst(at: player.position, color: moonlightGold, scale: 2.2)
        if let layer = worldLayer {
            JuiceEffects.shake(node: layer, magnitude: 8, duration: 0.22)
        }
    }
}
