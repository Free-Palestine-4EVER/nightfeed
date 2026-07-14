import Foundation

/// Persistent state for the Starfleet Command meta-layer: Crystals, starship hull/weapon/shield levels,
/// owned/equipped drones, and unlocked planets. UserDefaults-backed for now (same local-first pattern as
/// MetaProgressionStore) — FirebaseSync (added once the backend exists) mirrors this same state to
/// Firestore so it survives reinstalls and is visible to other players for PvP/alliance features.
final class EmpireStore {
    static let shared = EmpireStore()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let crystals = "nightfeed.empire.crystals"
        static let hullLevel = "nightfeed.empire.hullLevel"
        static let weaponLevel = "nightfeed.empire.weaponLevel"
        static let shieldLevel = "nightfeed.empire.shieldLevel"
        static let ownedDronePrefix = "nightfeed.empire.droneOwned."
        static let droneLevelPrefix = "nightfeed.empire.droneLevel."
        static let equippedDrones = "nightfeed.empire.equippedDrones"
        static let unlockedPlanetPrefix = "nightfeed.empire.planetUnlocked."
        static let selectedPlanet = "nightfeed.empire.selectedPlanet"
        static let harvesterClaimedAt = "nightfeed.empire.harvesterClaimedAt"
    }

    private init() {
        // Emberwatch is the starting world, always unlocked.
        if !defaults.bool(forKey: Key.unlockedPlanetPrefix + PlanetKind.emberwatch.rawValue) {
            defaults.set(true, forKey: Key.unlockedPlanetPrefix + PlanetKind.emberwatch.rawValue)
        }
        if defaults.string(forKey: Key.selectedPlanet) == nil {
            defaults.set(PlanetKind.emberwatch.rawValue, forKey: Key.selectedPlanet)
        }
        if defaults.double(forKey: Key.harvesterClaimedAt) == 0 {
            defaults.set(Date().timeIntervalSince1970, forKey: Key.harvesterClaimedAt)
        }
    }

    // MARK: - Crystals

    private(set) var crystals: Int {
        get { defaults.integer(forKey: Key.crystals) }
        set { defaults.set(max(0, newValue), forKey: Key.crystals) }
    }

    func addCrystals(_ amount: Int) {
        guard amount > 0 else { return }
        crystals += amount
    }

    @discardableResult
    func spendCrystals(_ amount: Int) -> Bool {
        guard amount > 0, crystals >= amount else { return false }
        crystals -= amount
        return true
    }

    // MARK: - Starship hull / weapon / shield

    static let maxShipStatLevel = 20

    var hullLevel: Int { defaults.integer(forKey: Key.hullLevel) }
    var weaponLevel: Int { defaults.integer(forKey: Key.weaponLevel) }
    var shieldLevel: Int { defaults.integer(forKey: Key.shieldLevel) }

    /// Cost to go from the current level to current+1, for whichever stat. Same escalating-cost shape
    /// as the survival-mode meta shop (MetaUpgradeKind.cost(forTier:)), scaled for Crystals instead of Gold.
    func nextShipUpgradeCost(stat: ShipStat) -> Int? {
        let current = level(for: stat)
        guard current < Self.maxShipStatLevel else { return nil }
        let base = 80
        return Int(Double(base) * pow(1.45, Double(current)))
    }

    @discardableResult
    func upgradeShip(stat: ShipStat) -> Bool {
        guard let cost = nextShipUpgradeCost(stat: stat), spendCrystals(cost) else { return false }
        defaults.set(level(for: stat) + 1, forKey: key(for: stat))
        return true
    }

    enum ShipStat { case hull, weapon, shield }

    private func level(for stat: ShipStat) -> Int {
        switch stat {
        case .hull: return hullLevel
        case .weapon: return weaponLevel
        case .shield: return shieldLevel
        }
    }

    private func key(for stat: ShipStat) -> String {
        switch stat {
        case .hull: return Key.hullLevel
        case .weapon: return Key.weaponLevel
        case .shield: return Key.shieldLevel
        }
    }

    /// Combined PvP attack/defense rating, read by the (future) Cloud Functions attack resolver and
    /// mirrored here for client-side preview. Simple weighted sum — tune once real PvP data exists.
    var attackPower: CGFloatCompat {
        let weaponContribution: Double = Double(weaponLevel) * 12
        let interceptorCount: Double = Double(equippedDrones().filter { $0 == .interceptor }.count)
        return weaponContribution + interceptorCount * 40
    }

    var defensePower: CGFloatCompat {
        let shieldContribution: Double = Double(shieldLevel) * 10
        let hullContribution: Double = Double(hullLevel) * 6
        let aegisCount: Double = Double(equippedDrones().filter { $0 == .aegis }.count)
        return shieldContribution + hullContribution + aegisCount * 35
    }

    // MARK: - Drones

    func isDroneOwned(_ kind: DroneKind) -> Bool {
        defaults.bool(forKey: Key.ownedDronePrefix + kind.rawValue)
    }

    func droneLevel(_ kind: DroneKind) -> Int {
        defaults.integer(forKey: Key.droneLevelPrefix + kind.rawValue)
    }

    @discardableResult
    func unlockDrone(_ kind: DroneKind) -> Bool {
        guard !isDroneOwned(kind), spendCrystals(kind.unlockCost) else { return false }
        defaults.set(true, forKey: Key.ownedDronePrefix + kind.rawValue)
        defaults.set(1, forKey: Key.droneLevelPrefix + kind.rawValue)
        return true
    }

    func nextDroneUpgradeCost(_ kind: DroneKind) -> Int? {
        guard isDroneOwned(kind) else { return nil }
        let level = droneLevel(kind)
        guard level < DroneKind.maxLevel else { return nil }
        return Int(Double(kind.unlockCost) * 0.4 * pow(1.35, Double(level - 1)))
    }

    @discardableResult
    func upgradeDrone(_ kind: DroneKind) -> Bool {
        guard let cost = nextDroneUpgradeCost(kind), spendCrystals(cost) else { return false }
        defaults.set(droneLevel(kind) + 1, forKey: Key.droneLevelPrefix + kind.rawValue)
        return true
    }

    /// Up to 3 drone slots active at once. Order in the array has no meaning beyond membership.
    static let maxEquippedDrones = 3

    func equippedDrones() -> [DroneKind] {
        (defaults.array(forKey: Key.equippedDrones) as? [String] ?? []).compactMap { DroneKind(rawValue: $0) }
    }

    func setEquippedDrones(_ kinds: [DroneKind]) {
        let capped = Array(kinds.prefix(Self.maxEquippedDrones))
        defaults.set(capped.map { $0.rawValue }, forKey: Key.equippedDrones)
    }

    // MARK: - Planets / star map

    func isPlanetUnlocked(_ kind: PlanetKind) -> Bool {
        defaults.bool(forKey: Key.unlockedPlanetPrefix + kind.rawValue)
    }

    @discardableResult
    func unlockPlanet(_ kind: PlanetKind) -> Bool {
        guard !isPlanetUnlocked(kind), spendCrystals(kind.unlockCrystalCost) else { return false }
        defaults.set(true, forKey: Key.unlockedPlanetPrefix + kind.rawValue)
        return true
    }

    var selectedPlanet: PlanetKind {
        get { PlanetKind(rawValue: defaults.string(forKey: Key.selectedPlanet) ?? "") ?? .emberwatch }
        set { defaults.set(newValue.rawValue, forKey: Key.selectedPlanet) }
    }

    // MARK: - Harvester passive income (real-time accrual, claimed on return to the Command Deck)

    private static let harvesterRatePerHourPerLevel: Double = 8
    private static let harvesterMaxAccrualHours: Double = 12 // caps offline accrual, same idea as most idle games

    /// Crystals accrued since the last claim, ready to collect. Does not mutate state — call
    /// claimHarvesterIncome() to actually award and reset the clock.
    func pendingHarvesterIncome() -> Int {
        guard isDroneOwned(.harvester) else { return 0 }
        let elapsedHours = min(Self.harvesterMaxAccrualHours,
                                (Date().timeIntervalSince1970 - defaults.double(forKey: Key.harvesterClaimedAt)) / 3600)
        guard elapsedHours > 0 else { return 0 }
        let rate = Self.harvesterRatePerHourPerLevel * Double(max(1, droneLevel(.harvester)))
        return Int(elapsedHours * rate)
    }

    @discardableResult
    func claimHarvesterIncome() -> Int {
        let amount = pendingHarvesterIncome()
        if amount > 0 { addCrystals(amount) }
        defaults.set(Date().timeIntervalSince1970, forKey: Key.harvesterClaimedAt)
        return amount
    }
}

/// CoreGraphics' CGFloat, aliased so this file doesn't need to import CoreGraphics just for two
/// lightweight rating computations above.
typealias CGFloatCompat = Double
