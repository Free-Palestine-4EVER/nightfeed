import CoreGraphics
import Foundation

/// Shared vocabulary for the new "Starfleet Command" meta-layer: a persistent starship you upgrade
/// between survival runs, drones you crew it with, and a star map of planets to unlock — funded by
/// Crystals (a second currency, earned in small amounts from survival runs and purchasable via IAP).
/// This layer is deliberately independent of the NIGHTFEED survival mode's own Gold/MetaUpgradeKind
/// shop (GameTypes.swift) — different currency, different progression, same account.

enum DroneKind: String, CaseIterable, Codable {
    case interceptor // offense: raises attack power in PvP resolution
    case aegis       // defense: raises shield strength, reduces incoming raid damage
    case harvester   // economy: passively generates Crystals over real time, claimed on return

    var displayName: String {
        switch self {
        case .interceptor: return "Interceptor Drone"
        case .aegis: return "Aegis Drone"
        case .harvester: return "Harvester Drone"
        }
    }

    var flavorText: String {
        switch self {
        case .interceptor: return "Fast, aggressive — bolsters your fleet's raw attack power."
        case .aegis: return "Reinforced plating — bolsters your starship's shields against raids."
        case .harvester: return "Mines ambient crystal fields — generates Crystals while you're away."
        }
    }

    static let maxLevel = 10
    /// Base Crystal cost to unlock this drone at level 1.
    var unlockCost: Int {
        switch self {
        case .interceptor: return 150
        case .aegis: return 150
        case .harvester: return 220
        }
    }
}

enum PlanetKind: String, CaseIterable, Codable {
    case emberwatch
    case voidreach
    case lunahaven
    case crimsonforge
    case ashenveil

    var displayName: String {
        switch self {
        case .emberwatch: return "Emberwatch"
        case .voidreach: return "Voidreach"
        case .lunahaven: return "Lunahaven"
        case .crimsonforge: return "Crimsonforge"
        case .ashenveil: return "Ashenveil"
        }
    }

    var flavorText: String {
        switch self {
        case .emberwatch: return "A scorched outpost world, first foothold of the fleet."
        case .voidreach: return "A dead moon at the edge of known space."
        case .lunahaven: return "A pale, silent world bathed in permanent twilight."
        case .crimsonforge: return "An industrial forge-world, veins of raw crystal beneath its crust."
        case .ashenveil: return "The deep frontier — claimed by whoever holds it longest."
        }
    }

    /// Order they appear/unlock in on the star map — index 0 is free/owned from the start.
    static let unlockOrder: [PlanetKind] = [.emberwatch, .voidreach, .lunahaven, .crimsonforge, .ashenveil]

    var unlockCrystalCost: Int {
        switch self {
        case .emberwatch: return 0
        case .voidreach: return 300
        case .lunahaven: return 700
        case .crimsonforge: return 1500
        case .ashenveil: return 3000
        }
    }
}

/// A purchasable (real-money, via StoreKit) or earnable bundle of Crystals.
enum CrystalPackage: String, CaseIterable, Codable {
    case pouch
    case satchel
    case chest
    case hoard
    case vault

    /// StoreKit product identifier — TODO before shipping: register these exact IDs as real
    /// Consumable in-app purchases in App Store Connect (Apple's API cannot create IAP products
    /// either, same limitation as app-record creation — see RELEASE.md).
    var productID: String { "com.loom.nightfeed.crystals.\(rawValue)" }

    var crystalAmount: Int {
        switch self {
        case .pouch: return 100
        case .satchel: return 550   // +10% bonus over linear
        case .chest: return 1200    // +20% bonus
        case .hoard: return 2600    // +30% bonus
        case .vault: return 7000    // +40% bonus
        }
    }

    var displayName: String {
        switch self {
        case .pouch: return "Crystal Pouch"
        case .satchel: return "Crystal Satchel"
        case .chest: return "Crystal Chest"
        case .hoard: return "Crystal Hoard"
        case .vault: return "Crystal Vault"
        }
    }
}
