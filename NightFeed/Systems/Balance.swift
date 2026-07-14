import CoreGraphics
import Foundation

/// Frozen numeric tuning. WeaponSystem/EnemySpawner/UpgradeManager read stats from here — do not
/// hardcode alternate numbers in a subsystem file. All formulas are deterministic (level/time in, stats out).

struct WeaponLevelStats {
    let damage: CGFloat
    let interval: TimeInterval       // seconds between attacks, or per-target re-hit cooldown for continuous weapons
    let projectileCount: Int         // discrete projectiles/orbiters/blades before Multishot passive
    let projectileSpeed: CGFloat     // points/sec, unused by pure-AoE weapons
    let areaRadius: CGFloat          // orbit radius / burst radius / whirl reach
    let pierce: Int                  // extra enemies a single projectile can pass through
    let range: CGFloat               // max travel distance before despawn (straight/piercing/homing shots)
}

struct EnemyLevelStats {
    let hp: CGFloat
    let moveSpeed: CGFloat
    let contactDamage: CGFloat
    let xpValue: Int
    let goldValue: Int
    let visualScale: CGFloat
}

enum Balance {

    // MARK: - Weapons

    private struct WeaponCurve {
        let baseDamage: CGFloat, damagePerLevel: CGFloat
        let baseInterval: TimeInterval, intervalPerLevel: TimeInterval, minInterval: TimeInterval
        let baseCount: Int, countLevels: Set<Int>   // levels at which +1 projectile/orbiter is granted
        let baseSpeed: CGFloat
        let baseRadius: CGFloat, radiusPerLevel: CGFloat
        let basePierce: Int, pierceEveryLevels: Int
        let baseRange: CGFloat
    }

    // Tuned for a 20-level arc (WeaponKind.maxLevel): milestone projectile/orbiter/blade counts are
    // spread across the full range instead of front-loaded by level 7, and per-level damage is scaled
    // down from the old 8-level curves so a level-20 weapon is meaningfully stronger without becoming
    // absurd once Blood Edge/Multishot/crit stack on top.
    private static let curves: [WeaponKind: WeaponCurve] = [
        .fangBolt: WeaponCurve(baseDamage: 10, damagePerLevel: 2.6,
                                baseInterval: 0.85, intervalPerLevel: 0.05, minInterval: 0.35,
                                baseCount: 1, countLevels: [4, 7, 11, 15, 19],
                                baseSpeed: 620,
                                baseRadius: 0, radiusPerLevel: 0,
                                basePierce: 0, pierceEveryLevels: 0,
                                baseRange: 900),
        .emberOrbit: WeaponCurve(baseDamage: 6, damagePerLevel: 1.3,
                                  baseInterval: 0.5, intervalPerLevel: 0, minInterval: 0.5,
                                  baseCount: 2, countLevels: [3, 5, 7, 10, 13, 16, 19],
                                  baseSpeed: 1.6,
                                  baseRadius: 90, radiusPerLevel: 4,
                                  basePierce: 0, pierceEveryLevels: 0,
                                  baseRange: 0),
        .novaPulse: WeaponCurve(baseDamage: 14, damagePerLevel: 3,
                                 baseInterval: 2.6, intervalPerLevel: 0.12, minInterval: 1.2,
                                 baseCount: 1, countLevels: [],
                                 baseSpeed: 0,
                                 baseRadius: 140, radiusPerLevel: 9,
                                 basePierce: 0, pierceEveryLevels: 0,
                                 baseRange: 0),
        .bloodLance: WeaponCurve(baseDamage: 22, damagePerLevel: 5,
                                  baseInterval: 1.3, intervalPerLevel: 0.05, minInterval: 0.7,
                                  baseCount: 1, countLevels: [],
                                  baseSpeed: 760,
                                  baseRadius: 0, radiusPerLevel: 0,
                                  basePierce: 3, pierceEveryLevels: 2,
                                  baseRange: 1200),
        .batSwarm: WeaponCurve(baseDamage: 7, damagePerLevel: 1.8,
                                baseInterval: 1.0, intervalPerLevel: 0.04, minInterval: 0.55,
                                baseCount: 1, countLevels: [3, 5, 7, 10, 13, 16, 19],
                                baseSpeed: 420,
                                baseRadius: 0, radiusPerLevel: 0,
                                basePierce: 0, pierceEveryLevels: 0,
                                baseRange: 1400),
        .reaperWhirl: WeaponCurve(baseDamage: 5, damagePerLevel: 1.3,
                                   baseInterval: 0.35, intervalPerLevel: 0, minInterval: 0.35,
                                   baseCount: 2, countLevels: [4, 6, 9, 12, 15, 18],
                                   baseSpeed: 3.2,
                                   baseRadius: 80, radiusPerLevel: 3,
                                   basePierce: 0, pierceEveryLevels: 0,
                                   baseRange: 0),
        // baseSpeed is repurposed as pull strength (points/sec dragged toward the rift's center) — this
        // weapon has no traveling projectile, so range/pierce/countLevels are unused (baseRange: 0).
        .voidRift: WeaponCurve(baseDamage: 7, damagePerLevel: 1.8,
                                baseInterval: 3.4, intervalPerLevel: 0.15, minInterval: 1.8,
                                baseCount: 1, countLevels: [],
                                baseSpeed: 90,
                                baseRadius: 75, radiusPerLevel: 5,
                                basePierce: 0, pierceEveryLevels: 0,
                                baseRange: 0),
        .starShard: WeaponCurve(baseDamage: 9, damagePerLevel: 2.2,
                                 baseInterval: 1.1, intervalPerLevel: 0.04, minInterval: 0.6,
                                 baseCount: 1, countLevels: [4, 7, 11, 15, 19],
                                 baseSpeed: 680,
                                 baseRadius: 0, radiusPerLevel: 0,
                                 basePierce: 0, pierceEveryLevels: 0,
                                 baseRange: 1000),
    ]

    static func weaponStats(_ kind: WeaponKind, level: Int) -> WeaponLevelStats {
        let c = curves[kind]!
        let lvl = max(1, min(level, WeaponKind.maxLevel))
        let l = CGFloat(lvl - 1)
        let damage = c.baseDamage + c.damagePerLevel * l
        let interval = max(c.minInterval, c.baseInterval - c.intervalPerLevel * Double(lvl - 1))
        let extraCount = c.countLevels.filter { $0 <= lvl }.count
        let pierce = c.pierceEveryLevels > 0 ? c.basePierce + (lvl - 1) / c.pierceEveryLevels : c.basePierce
        return WeaponLevelStats(damage: damage, interval: interval,
                                 projectileCount: c.baseCount + extraCount, projectileSpeed: c.baseSpeed,
                                 areaRadius: c.baseRadius + c.radiusPerLevel * l, pierce: pierce, range: c.baseRange)
    }

    static func evolvedStats(_ kind: EvolvedWeaponKind) -> WeaponLevelStats {
        switch kind {
        case .moonfangBarrage:
            return WeaponLevelStats(damage: 40, interval: 0.5, projectileCount: 3, projectileSpeed: 700,
                                     areaRadius: 0, pierce: 2, range: 1100)
        case .crimsonMaelstrom:
            return WeaponLevelStats(damage: 16, interval: 0.25, projectileCount: 3, projectileSpeed: 4.0,
                                     areaRadius: 150, pierce: 0, range: 0)
        }
    }

    static let crimsonMaelstromLifestealFraction: CGFloat = 0.12

    // MARK: - Passives

    /// level 0 (not yet owned) always yields zero bonus — only clamp the upper bound. Tuned for a
    /// 20-level arc (PassiveKind.maxLevel); several curves intentionally scale slower per-level than
    /// the old 5-level versions since they now have 4x the levels to grow across.
    static func passiveValue(_ kind: PassiveKind, level: Int) -> CGFloat {
        guard level > 0 else { return 0 }
        let lvl = CGFloat(min(level, PassiveKind.maxLevel))
        switch kind {
        case .swiftFeet: return 0.035 * lvl          // +% move speed (max +70% at lvl20)
        case .bloodEdge: return 0.055 * lvl          // +% damage (max +110% at lvl20)
        case .rapidPulse: return 0.035 * lvl         // +% attack speed (max +70%, self-limited by minInterval anyway)
        case .vitality: return 20 * lvl               // + flat max HP (max +400 at lvl20)
        case .magnetHeart: return 18 * lvl            // + flat magnet radius (max +360 at lvl20)
        case .ironHide: return 1.5 * lvl              // + flat damage reduction (max +30 at lvl20)
        // Stepped/diminishing rather than 1:1 with level — a flat +1 count per level would mean +20
        // extra projectiles per weapon at max level, which is both a balance and a perf problem
        // (every applicable weapon spawning 20 extra pooled projectiles per shot). Caps at +6.
        case .multishot: return CGFloat(min(6, (Int(lvl) + 2) / 3))
        case .critFocus: return lvl                    // vestigial — critChance/critDamageBonus below read raw level directly
        case .ashenWake: return 0.5 * lvl              // + flat HP/sec regeneration (max 10/sec at lvl20)
        case .secondWind: return max(12, 100 - lvl * 5) // seconds of cooldown before another life-saving proc
        }
    }

    static func critChance(level: Int) -> CGFloat { min(0.30, 0.06 * CGFloat(level)) }
    /// Capped — uncapped 0.25/level would reach +500% (6x damage) at level 20. Capped at +200% (3x).
    static func critDamageBonus(level: Int) -> CGFloat { min(2.0, 0.12 * CGFloat(level)) }

    // MARK: - Potions (temporary in-run buffs — see PotionKind/PotionSystem)

    static func potionDuration(_ kind: PotionKind) -> TimeInterval {
        switch kind {
        case .crimsonVigor: return 15
        case .nightHaste: return 15
        case .voidAegis: return 5
        case .hungerSurge: return 6
        case .bloodFrenzy: return 10
        case .voidMagnet, .risingMoon: return 0 // instant — no timed buff, see PotionKind.isInstant
        }
    }

    static let potionVigorDamageMultiplier: CGFloat = 1.6
    static let potionHasteSpeedMultiplier: CGFloat = 1.5
    static let potionHasteFireRateMultiplier: CGFloat = 0.65 // multiplies fireRateMultiplier (lower = faster)
    static let potionHungerSurgeHealFraction: CGFloat = 0.25 // of max HP, applied instantly
    static let potionHungerSurgeMagnetMultiplier: CGFloat = 3.0
    static let potionFrenzyCritDamageBonus: CGFloat = 1.0

    // MARK: - Enemies

    private struct EnemyCurve {
        let baseHP: CGFloat, hpGrowthPerMin: CGFloat
        let moveSpeed: CGFloat
        let contactDamage: CGFloat, damageGrowthPerMin: CGFloat
        let xpValue: Int
        let goldValue: Int
        let visualScale: CGFloat
    }

    private static let enemyCurves: [EnemyKind: EnemyCurve] = [
        .swarmling: EnemyCurve(baseHP: 12, hpGrowthPerMin: 0.14, moveSpeed: 150,
                                contactDamage: 6, damageGrowthPerMin: 0.04, xpValue: 1, goldValue: 1, visualScale: 0.85),
        .bloodbat: EnemyCurve(baseHP: 8, hpGrowthPerMin: 0.16, moveSpeed: 230,
                               contactDamage: 5, damageGrowthPerMin: 0.04, xpValue: 2, goldValue: 1, visualScale: 0.7),
        .hollowBrute: EnemyCurve(baseHP: 70, hpGrowthPerMin: 0.18, moveSpeed: 80,
                                  contactDamage: 16, damageGrowthPerMin: 0.05, xpValue: 6, goldValue: 3, visualScale: 1.4),
        .nightmaw: EnemyCurve(baseHP: 900, hpGrowthPerMin: 0.22, moveSpeed: 95,
                               contactDamage: 28, damageGrowthPerMin: 0.05, xpValue: 60, goldValue: 25, visualScale: 2.6),
    ]

    static func enemyStats(_ kind: EnemyKind, runTime: TimeInterval) -> EnemyLevelStats {
        let c = enemyCurves[kind]!
        let minutes = CGFloat(runTime / 60)
        let hp = c.baseHP * (1 + c.hpGrowthPerMin * minutes)
        let dmg = c.contactDamage * (1 + c.damageGrowthPerMin * minutes)
        return EnemyLevelStats(hp: hp, moveSpeed: c.moveSpeed, contactDamage: dmg,
                                xpValue: c.xpValue, goldValue: c.goldValue, visualScale: c.visualScale)
    }

    /// Relative spawn weights at a given run minute — shifts from mostly swarmlings to a tougher mix.
    static func spawnWeights(atMinute minute: CGFloat) -> [EnemyKind: Double] {
        let m: Double = Double(minute)
        let swarmlingWeight: Double = max(0.35, 1.0 - m * 0.045)
        let bloodbatWeight: Double = min(0.4, 0.12 + m * 0.02)
        let hollowBruteWeight: Double = min(0.32, 0.05 + m * 0.018)
        var weights: [EnemyKind: Double] = [:]
        weights[.swarmling] = swarmlingWeight
        weights[.bloodbat] = bloodbatWeight
        weights[.hollowBrute] = hollowBruteWeight
        weights[.nightmaw] = 0.0 // spawned explicitly on the mini-boss timer, never via weighted roll
        return weights
    }

    /// Enemies spawned per second, smoothly ramping from a gentle opening to a challenging late-game
    /// swarm across the run's ENTIRE target duration (DifficultyConfig.runDurationTarget) — deliberately
    /// NOT front-loaded, so pressure builds progressively over ~18 minutes instead of maxing out in the
    /// first few. Smoothstep-eased so both ends of the ramp feel gentle and the middle carries the climb.
    static func spawnRatePerSecond(runTime: TimeInterval) -> Double {
        let progress = min(1.0, runTime / DifficultyConfig.runDurationTarget)
        let eased = progress * progress * (3 - 2 * progress)
        return 1.6 + eased * 6.4 // ~1.6/sec at run start -> ~8/sec at run end
    }

    // MARK: - Gold / meta

    static func goldEarned(survivalTime: TimeInterval, kills: Int, miniBossKills: Int) -> Int {
        Int(survivalTime / 3) + kills + miniBossKills * 15
    }
}
