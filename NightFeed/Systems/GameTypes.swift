import CoreGraphics
import Foundation

/// Frozen shared vocabulary. WeaponSystem, UpgradeManager, EnemySpawner and the HUD all key off these.

enum WeaponKind: String, CaseIterable, Codable {
    case fangBolt     // straight shot — fires a bolt at the nearest enemy
    case emberOrbit   // orbiting embers around the player
    case novaPulse    // periodic AoE burst centered on the player
    case bloodLance   // long piercing lance through multiple enemies
    case batSwarm     // homing bats that steer toward the nearest enemy
    case reaperWhirl  // melee scythes whirling close around the player
    case voidRift     // a curse zone that pulls enemies in and burns them over time
    case starShard    // a shard that fragments into two more on impact or expiry

    var displayName: String {
        switch self {
        case .fangBolt: return "Fang Bolt"
        case .emberOrbit: return "Ember Orbit"
        case .novaPulse: return "Nova Pulse"
        case .bloodLance: return "Blood Lance"
        case .batSwarm: return "Bat Swarm"
        case .reaperWhirl: return "Reaper Whirl"
        case .voidRift: return "Void Rift"
        case .starShard: return "Star Shard"
        }
    }

    var flavorText: String {
        switch self {
        case .fangBolt: return "Fires a piercing fang at the nearest foe."
        case .emberOrbit: return "Embers orbit you, scorching anything they touch."
        case .novaPulse: return "Unleashes a shockwave that scorches everything nearby."
        case .bloodLance: return "A long lance skewers everything in its path."
        case .batSwarm: return "Bats hunt down the nearest enemy on their own."
        case .reaperWhirl: return "Twin scythes spin around you, cutting all who draw near."
        case .voidRift: return "Tears open a curse zone that drags foes in and burns them."
        case .starShard: return "A shard that splits into two more on impact."
        }
    }

    /// Which passive, when both are at max level, unlocks this weapon's evolution.
    var evolutionPassive: PassiveKind? {
        switch self {
        case .fangBolt: return .critFocus
        case .reaperWhirl: return .vitality
        default: return nil
        }
    }

    var evolvedForm: EvolvedWeaponKind? {
        switch self {
        case .fangBolt: return .moonfangBarrage
        case .reaperWhirl: return .crimsonMaelstrom
        default: return nil
        }
    }

    static let maxLevel = 20
}

enum EvolvedWeaponKind: String, Codable {
    case moonfangBarrage // evolved Fang Bolt + Crit Focus
    case crimsonMaelstrom // evolved Reaper Whirl + Vitality

    var displayName: String {
        switch self {
        case .moonfangBarrage: return "Moonfang Barrage"
        case .crimsonMaelstrom: return "Crimson Maelstrom"
        }
    }

    var flavorText: String {
        switch self {
        case .moonfangBarrage: return "A homing volley of moonlit fangs that always finds its mark."
        case .crimsonMaelstrom: return "A wider, bleeding whirl that feeds your health back to you."
        }
    }

    var baseWeapon: WeaponKind {
        switch self {
        case .moonfangBarrage: return .fangBolt
        case .crimsonMaelstrom: return .reaperWhirl
        }
    }
}

enum PassiveKind: String, CaseIterable, Codable {
    case swiftFeet    // move speed
    case bloodEdge    // damage
    case rapidPulse   // fire rate / attack speed
    case vitality     // max health
    case magnetHeart  // XP pickup radius
    case ironHide     // armor (flat damage reduction on contact hits)
    case multishot    // +projectile per applicable weapon
    case critFocus    // crit chance + crit damage
    case ashenWake    // passive health regeneration
    case secondWind   // survive a lethal hit at 1 HP, on a per-run cooldown

    var displayName: String {
        switch self {
        case .swiftFeet: return "Swift Feet"
        case .bloodEdge: return "Blood Edge"
        case .rapidPulse: return "Rapid Pulse"
        case .vitality: return "Vitality"
        case .magnetHeart: return "Magnet Heart"
        case .ironHide: return "Iron Hide"
        case .multishot: return "Multishot"
        case .critFocus: return "Crit Focus"
        case .ashenWake: return "Ashen Wake"
        case .secondWind: return "Second Wind"
        }
    }

    var flavorText: String {
        switch self {
        case .swiftFeet: return "Move faster to weave through the swarm."
        case .bloodEdge: return "Every weapon cuts deeper."
        case .rapidPulse: return "Every weapon fires faster."
        case .vitality: return "Raises your maximum health."
        case .magnetHeart: return "Pulls XP gems from further away."
        case .ironHide: return "Blunts the damage of every hit you take."
        case .multishot: return "Applicable weapons fire an extra projectile."
        case .critFocus: return "Raises critical hit chance and critical damage."
        case .ashenWake: return "Slowly mends your wounds as you fight."
        case .secondWind: return "Cheat death once, then again after a cooldown."
        }
    }

    static let maxLevel = 20
}

enum EnemyKind: String, CaseIterable, Codable {
    case swarmling   // basic weak swarmer, spawns in high volume
    case bloodbat    // fast, low HP, erratic flight path
    case hollowBrute // slow, tanky, high contact damage
    case nightmaw    // periodic mini-boss

    var displayName: String {
        switch self {
        case .swarmling: return "Swarmling"
        case .bloodbat: return "Bloodbat"
        case .hollowBrute: return "Hollow Brute"
        case .nightmaw: return "Nightmaw"
        }
    }

    var isMiniBoss: Bool { self == .nightmaw }
}

/// Temporary in-run buffs, dropped as a rare world pickup (see PotionConfig/PotionSystem). Distinct
/// from PassiveKind (permanent per-run upgrades picked on level-up) and MetaUpgradeKind (permanent
/// cross-run shop purchases) — these expire after a short duration, `hungerSurge` excepted (part
/// instant heal, part short buff).
enum PotionKind: String, CaseIterable, Codable {
    case crimsonVigor  // temporary damage boost
    case nightHaste    // temporary move speed + fire rate boost
    case voidAegis     // brief full invulnerability
    case hungerSurge   // instant heal + temporary magnet burst
    case bloodFrenzy   // guaranteed crits + bonus crit damage, temporarily
    case voidMagnet    // instant — collects every XP gem currently on the field
    case risingMoon    // instant — a free level-up, cards and all

    var displayName: String {
        switch self {
        case .crimsonVigor: return "Crimson Vigor"
        case .nightHaste: return "Night Haste"
        case .voidAegis: return "Void Aegis"
        case .hungerSurge: return "Hunger Surge"
        case .bloodFrenzy: return "Blood Frenzy"
        case .voidMagnet: return "Void Magnet"
        case .risingMoon: return "Rising Moon"
        }
    }

    var flavorText: String {
        switch self {
        case .crimsonVigor: return "Every weapon hits harder for a short while."
        case .nightHaste: return "Faster feet, faster weapons, for a short while."
        case .voidAegis: return "Nothing can touch you — briefly."
        case .hungerSurge: return "An instant feast, and gems come running to you."
        case .bloodFrenzy: return "Every hit lands a devastating critical."
        case .voidMagnet: return "Every gem on the field rushes straight to you."
        case .risingMoon: return "An instant surge of power — a free level, right now."
        }
    }

    /// True for potions whose entire effect fires once on pickup (no timed buff to track).
    var isInstant: Bool {
        switch self {
        case .voidMagnet, .risingMoon: return true
        default: return false
        }
    }
}

/// The pet familiars unlockable via the shop (see MetaUpgradeKind's `pet*` cases). GameScene reads
/// `MetaProgressionStore.activePetKinds` to decide which PetCompanion node(s) to spawn each run.
enum PetKind: String, CaseIterable, Codable {
    case emberWisp    // ranged: zaps the nearest enemy on its own
    case boneHound    // melee: dashes in for a heavy bite on a longer cooldown
    case stormSprite  // ranged: chain lightning that arcs to nearby enemies
    case graveMoth    // support: periodic healing pulse, no direct damage

    var displayName: String {
        switch self {
        case .emberWisp: return "Ember Wisp"
        case .boneHound: return "Bone Hound"
        case .stormSprite: return "Storm Sprite"
        case .graveMoth: return "Grave Moth"
        }
    }

    var flavorText: String {
        switch self {
        case .emberWisp: return "A wisp familiar zaps the nearest foe on its own."
        case .boneHound: return "A loyal hound lunges in for a heavy bite."
        case .stormSprite: return "A crackling sprite arcs lightning between foes."
        case .graveMoth: return "A pale moth mends your wounds as it circles you."
        }
    }

    /// Which MetaUpgradeKind purchase unlocks this pet.
    var unlockKind: MetaUpgradeKind {
        switch self {
        case .emberWisp: return .petCompanion
        case .boneHound: return .petBoneHound
        case .stormSprite: return .petStormSprite
        case .graveMoth: return .petGraveMoth
        }
    }
}

/// Permanent meta-progression upgrades bought with gold in MenuScene's shop, persisted via UserDefaults.
/// IMPORTANT: never rename or remove an existing case's rawValue — MetaProgressionStore persists tier
/// via `"nightfeed.tier." + rawValue`, so a rename silently resets anyone's already-purchased tier to 0.
enum MetaUpgradeKind: String, CaseIterable, Codable {
    case startingHealth
    case startingSpeed
    case startingDamage
    case startingMagnet
    case goldGain
    case startingArmor
    case startingCrit
    case headStart
    case petCompanion
    case petBoneHound
    case petStormSprite
    case petGraveMoth
    case secondPetSlot
    case lifesteal
    case dodgeChance
    case xpGainBonus
    case potionLuck
    case reviveCharge
    case weaponMastery
    case extraChoices

    var displayName: String {
        switch self {
        case .startingHealth: return "Vitality Shrine"
        case .startingSpeed: return "Swift Blessing"
        case .startingDamage: return "Sharpened Fangs"
        case .startingMagnet: return "Hungry Heart"
        case .goldGain: return "Golden Tithe"
        case .startingArmor: return "Iron Will"
        case .startingCrit: return "Lucky Star"
        case .headStart: return "Blood Ritual"
        case .petCompanion: return "Ember Wisp"
        case .petBoneHound: return "Bone Hound"
        case .petStormSprite: return "Storm Sprite"
        case .petGraveMoth: return "Grave Moth"
        case .secondPetSlot: return "Second Familiar"
        case .lifesteal: return "Crimson Pact"
        case .dodgeChance: return "Shadow Step"
        case .xpGainBonus: return "Wisdom of Night"
        case .potionLuck: return "Alchemist's Eye"
        case .reviveCharge: return "Undying Oath"
        case .weaponMastery: return "First Strike"
        case .extraChoices: return "Third Eye"
        }
    }

    var flavorText: String {
        switch self {
        case .startingHealth: return "+10 starting max health per tier."
        case .startingSpeed: return "+3% starting move speed per tier."
        case .startingDamage: return "+4% starting damage per tier."
        case .startingMagnet: return "+15 starting XP magnet radius per tier."
        case .goldGain: return "+10% gold earned per run, per tier."
        case .startingArmor: return "+1 starting armor per tier."
        case .startingCrit: return "+3% starting crit chance per tier."
        case .headStart: return "Begin every run one level higher, with a free upgrade pick already waiting."
        case .petCompanion: return "A wisp familiar joins every run, zapping the nearest foe on its own."
        case .petBoneHound: return "A hound familiar joins every run, lunging in for heavy bites."
        case .petStormSprite: return "A sprite familiar joins every run, arcing lightning between foes."
        case .petGraveMoth: return "A moth familiar joins every run, mending your wounds as it circles."
        case .secondPetSlot: return "Bring two familiars into every run instead of one."
        case .lifesteal: return "+2.5% of all damage dealt returns as healing, per tier."
        case .dodgeChance: return "+4% chance to completely dodge a contact hit, per tier."
        case .xpGainBonus: return "+8% XP gained from every gem, per tier."
        case .potionLuck: return "Vials appear noticeably more often, per tier."
        case .reviveCharge: return "+1 free automatic revive per run, per tier — no ad needed."
        case .weaponMastery: return "Your first weapon each run starts two levels ahead."
        case .extraChoices: return "+1 upgrade choice offered on every level-up, per tier."
        }
    }

    var maxTier: Int {
        switch self {
        case .startingHealth, .startingDamage, .startingSpeed: return 5
        case .startingMagnet, .goldGain, .startingArmor, .startingCrit: return 3
        case .headStart: return 4
        case .petCompanion, .petBoneHound, .petStormSprite, .petGraveMoth: return 1
        case .secondPetSlot: return 1
        case .lifesteal: return 5
        case .dodgeChance: return 4
        case .xpGainBonus: return 5
        case .potionLuck: return 3
        case .reviveCharge: return 2
        case .weaponMastery: return 1
        case .extraChoices: return 2
        }
    }

    /// Gold cost to purchase the given tier (tier is 1-based, the tier being bought).
    func cost(forTier tier: Int) -> Int {
        let base: Int
        switch self {
        case .startingHealth: base = 40
        case .startingSpeed: base = 55
        case .startingDamage: base = 60
        case .startingMagnet: base = 45
        case .goldGain: base = 80
        case .startingArmor: base = 65
        case .startingCrit: base = 70
        case .headStart: base = 150
        case .petCompanion: base = 200
        case .petBoneHound: base = 220
        case .petStormSprite: base = 260
        case .petGraveMoth: base = 220
        case .secondPetSlot: base = 350
        case .lifesteal: base = 90
        case .dodgeChance: base = 85
        case .xpGainBonus: base = 70
        case .potionLuck: base = 100
        case .reviveCharge: base = 250
        case .weaponMastery: base = 180
        case .extraChoices: base = 220
        }
        return Int(Double(base) * pow(1.6, Double(tier - 1)))
    }
}
