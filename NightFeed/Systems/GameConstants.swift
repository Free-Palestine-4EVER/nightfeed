import CoreGraphics
import Foundation

/// Frozen engine-wide constants. Every subsystem reads from here — do not duplicate magic numbers elsewhere.
/// Collision is deliberately NOT SpriteKit-physics-based: every hit test is a manual spatial-grid /
/// distance query (see SpatialGrid.swift) run directly by the system that needs it (WeaponSystem for
/// weapon-vs-enemy, EnemySpawner for enemy-vs-player and enemy-vs-enemy separation). This keeps each
/// system self-contained instead of funnelling every collision through a shared contact delegate.
enum ZPosition {
    static let background: CGFloat     = -100
    static let groundDecor: CGFloat    = -50
    static let xpGem: CGFloat          = 0
    static let enemyShadow: CGFloat    = 5
    static let enemy: CGFloat          = 10
    static let miniBoss: CGFloat       = 12
    static let projectile: CGFloat     = 15
    static let weaponOrbiter: CGFloat  = 16
    static let player: CGFloat         = 20
    static let meleeWhirl: CGFloat     = 21
    static let damageNumber: CGFloat   = 30
    static let hitParticle: CGFloat    = 35
    static let worldUI: CGFloat        = 40
    static let hud: CGFloat            = 100
    static let levelUpOverlay: CGFloat = 200
    static let menuUI: CGFloat         = 10
}

enum WorldConfig {
    /// Half-extent of the playable arena; player and enemies are clamped to [-halfExtent, halfExtent].
    static let halfExtent: CGFloat = 2200
    static var bounds: CGRect {
        CGRect(x: -halfExtent, y: -halfExtent, width: halfExtent * 2, height: halfExtent * 2)
    }
    static let backgroundTileSize: CGFloat = 256
}

enum JoystickConfig {
    static let baseRadius: CGFloat = 60
    static let knobRadius: CGFloat = 28
    static let deadZone: CGFloat = 0.08
    static let activationTouchAreaFraction: CGFloat = 1.0 // whole screen is draggable
}

enum PlayerConfig {
    static let baseMoveSpeed: CGFloat = 260 // points/sec
    static let baseMaxHealth: CGFloat = 100
    static let baseMagnetRadius: CGFloat = 70
    static let invulnerabilityAfterHit: TimeInterval = 0.5
    static let contactDamageInterval: TimeInterval = 0.35 // enemy touching player re-ticks damage this often
    static let radius: CGFloat = 22
}

enum XPConfig {
    /// XP required to go from level N to N+1, index 0 = level 1 -> 2.
    static func xpToNextLevel(_ level: Int) -> Int {
        // gentle early curve, steep late curve so a 15-20 min run has ~25-35 level-ups
        let l = Double(level)
        return Int(6 + l * 4.4 + pow(l, 1.55) * 1.6)
    }
    static let gemMagnetSpeed: CGFloat = 520
    static let gemBaseValue: Int = 1
}

enum DifficultyConfig {
    /// Run length target ~18 minutes.
    static let runDurationTarget: TimeInterval = 18 * 60
    static let miniBossInterval: TimeInterval = 150 // every 2.5 min
    /// Hard safety valve: even if the spawn-rate accumulator backs up (e.g. a frame-time spike), never
    /// spawn more than this many enemies in a single update() call.
    static let maxSpawnsPerFrame: Int = 6
    static let maxActiveEnemies: Int = 260
}

enum PoolConfig {
    static let initialEnemyCount = 120
    static let initialProjectileCount = 160
    static let initialGemCount = 200
    static let initialDamageLabelCount = 24
    static let initialEmitterCount = 16
    static let hardEnemyCap = DifficultyConfig.maxActiveEnemies + 40
    static let hardProjectileCap = 400
    static let hardGemCap = 320
    static let initialPotionCount = 6
    static let hardPotionCap = 12
}

/// World-pickup potions (see PotionKind/PotionSystem) — a rare, timed floor spawn near the player,
/// distinct from XP gems (which drop from every kill) and the meta shop (permanent, cross-run).
enum PotionConfig {
    static let baseSpawnInterval: TimeInterval = 26   // average seconds between spawns
    static let spawnIntervalJitter: TimeInterval = 8  // +/- randomness applied on top of the base
    /// Reduces the effective interval per Alchemist's Eye (potionLuck) shop tier, e.g. 0.18 = -18%/tier.
    static let luckIntervalReductionPerTier: Double = 0.18
    static let spawnDistanceMin: CGFloat = 260
    static let spawnDistanceMax: CGFloat = 480
    static let pickupRadius: CGFloat = 34
    static let lifetime: TimeInterval = 20 // despawns if not collected in time
    static let visualRadius: CGFloat = 20
}
