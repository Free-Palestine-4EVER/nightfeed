import Foundation
import CoreGraphics

/// Derived starting-run bonuses computed from purchased meta upgrades. PlayerController applies this once at run start.
struct MetaLoadout {
    var startingHealthBonus: CGFloat = 0
    var startingSpeedMultiplier: CGFloat = 1.0
    var startingDamageMultiplier: CGFloat = 1.0
    var startingMagnetBonus: CGFloat = 0
    var goldGainMultiplier: CGFloat = 1.0
    var startingArmorBonus: CGFloat = 0
    var startingCritBonus: CGFloat = 0
    var lifestealFraction: CGFloat = 0
    var dodgeChance: CGFloat = 0
    var xpGainMultiplier: CGFloat = 1.0
}

/// Persistent cross-run progression: gold, permanent meta upgrades, best survival time, run count, and
/// the ad-gated "Gold Rush" temporary boost. Backed by UserDefaults — this is the only persistence
/// NightFeed needs.
final class MetaProgressionStore {
    static let shared = MetaProgressionStore()
    private let defaults = UserDefaults.standard

    private enum Key {
        static let gold = "nightfeed.gold"
        static let bestSurvival = "nightfeed.bestSurvivalTime"
        static let runsCompleted = "nightfeed.runsCompleted"
        static let tierPrefix = "nightfeed.tier."
        static let hasRequestedATT = "nightfeed.hasRequestedATT"
        static let hasSeenMenu = "nightfeed.hasSeenMenu"
        static let goldRushTier = "nightfeed.goldRushTier"
        static let goldRushExpiry = "nightfeed.goldRushExpiry"
        static let goldRushAdsWatched = "nightfeed.goldRushAdsWatched"
        static let autoReviveBanked = "nightfeed.autoReviveBanked"
        static let autoReviveCooldownUntil = "nightfeed.autoReviveCooldownUntil"
        static let speedBoostExpiry = "nightfeed.speedBoostExpiry"
    }

    private init() {}

    private(set) var gold: Int {
        get { defaults.integer(forKey: Key.gold) }
        set { defaults.set(max(0, newValue), forKey: Key.gold) }
    }

    private(set) var bestSurvivalTime: TimeInterval {
        get { defaults.double(forKey: Key.bestSurvival) }
        set { defaults.set(newValue, forKey: Key.bestSurvival) }
    }

    private(set) var runsCompleted: Int {
        get { defaults.integer(forKey: Key.runsCompleted) }
        set { defaults.set(newValue, forKey: Key.runsCompleted) }
    }

    var hasRequestedATT: Bool {
        get { defaults.bool(forKey: Key.hasRequestedATT) }
        set { defaults.set(newValue, forKey: Key.hasRequestedATT) }
    }

    func tier(for kind: MetaUpgradeKind) -> Int {
        defaults.integer(forKey: Key.tierPrefix + kind.rawValue)
    }

    private func setTier(_ tier: Int, for kind: MetaUpgradeKind) {
        defaults.set(tier, forKey: Key.tierPrefix + kind.rawValue)
    }

    func nextTierCost(for kind: MetaUpgradeKind) -> Int? {
        let current = tier(for: kind)
        guard current < kind.maxTier else { return nil }
        return kind.cost(forTier: current + 1)
    }

    @discardableResult
    func purchaseNextTier(_ kind: MetaUpgradeKind) -> Bool {
        guard let cost = nextTierCost(for: kind), gold >= cost else { return false }
        gold -= cost
        setTier(tier(for: kind) + 1, for: kind)
        return true
    }

    func addGold(_ amount: Int) {
        gold += max(0, amount)
    }

    func recordRunCompleted(survivalTime: TimeInterval) {
        runsCompleted += 1
        if survivalTime > bestSurvivalTime { bestSurvivalTime = survivalTime }
    }

    /// True on every 3rd completed run — GameOverScene checks this to decide whether to show an interstitial.
    func shouldShowInterstitial() -> Bool {
        runsCompleted > 0 && runsCompleted % 3 == 0
    }

    // MARK: - Gold Rush (ad-gated temporary gold multiplier)

    private var goldRushTierRaw: Int {
        get { defaults.integer(forKey: Key.goldRushTier) }
        set { defaults.set(newValue, forKey: Key.goldRushTier) }
    }

    private var goldRushExpiry: TimeInterval {
        get { defaults.double(forKey: Key.goldRushExpiry) }
        set { defaults.set(newValue, forKey: Key.goldRushExpiry) }
    }

    /// Ads watched toward unlocking tier 1 (0..<3). Only meaningful while `goldRushActiveTier == 0`.
    private(set) var goldRushAdsWatched: Int {
        get { defaults.integer(forKey: Key.goldRushAdsWatched) }
        set { defaults.set(newValue, forKey: Key.goldRushAdsWatched) }
    }

    /// 0 = inactive, 1 = 2x gold, 2 = 4x gold. Resets to 0 automatically once the window has elapsed —
    /// checked on every read against the stored expiry, no separate "prune" step required.
    var goldRushActiveTier: Int {
        Date().timeIntervalSince1970 < goldRushExpiry ? goldRushTierRaw : 0
    }

    var goldRushTimeRemaining: TimeInterval {
        max(0, goldRushExpiry - Date().timeIntervalSince1970)
    }

    var currentGoldRushMultiplier: Double {
        switch goldRushActiveTier {
        case 1: return 2.0
        case 2: return 4.0
        default: return 1.0
        }
    }

    /// Called after a rewarded ad completes successfully. Advances the Gold Rush ladder: watch 3 ads to
    /// unlock a 1-hour 2x-gold window; watch 1 more ad to upgrade that window to 4x (refreshing the full
    /// hour). Once at 4x, further ads simply refresh/extend the hour rather than escalating further.
    func recordGoldRushAdWatched() {
        let now = Date().timeIntervalSince1970
        switch goldRushActiveTier {
        case 0:
            let progress = goldRushAdsWatched + 1
            if progress >= 3 {
                goldRushTierRaw = 1
                goldRushExpiry = now + 3600
                goldRushAdsWatched = 0
            } else {
                goldRushAdsWatched = progress
            }
        case 1:
            goldRushTierRaw = 2
            goldRushExpiry = now + 3600
        default:
            goldRushExpiry = now + 3600
        }
    }

    // MARK: - Auto-Revive (ad-gated: watch 1 ad to bank a free revive, 20 min cooldown between banks)

    /// True once an ad has been watched and the charge hasn't been used (or expired) yet.
    var autoReviveAvailable: Bool {
        defaults.bool(forKey: Key.autoReviveBanked)
    }

    var autoReviveCooldownRemaining: TimeInterval {
        max(0, defaults.double(forKey: Key.autoReviveCooldownUntil) - Date().timeIntervalSince1970)
    }

    /// Whether the player is currently allowed to watch an ad to bank a new charge — false while one is
    /// already banked, or while on cooldown from having just used/banked one.
    var canWatchAdForAutoRevive: Bool {
        !autoReviveAvailable && autoReviveCooldownRemaining <= 0
    }

    /// Called after a rewarded ad completes successfully — banks one free automatic revive.
    func recordAutoReviveAdWatched() {
        defaults.set(true, forKey: Key.autoReviveBanked)
    }

    /// Called by GameScene the moment a banked charge is actually spent on a death. Starts the 20-minute
    /// cooldown before another one can be banked. Returns false (and changes nothing) if none was banked.
    @discardableResult
    func consumeAutoRevive() -> Bool {
        guard autoReviveAvailable else { return false }
        defaults.set(false, forKey: Key.autoReviveBanked)
        defaults.set(Date().timeIntervalSince1970 + 20 * 60, forKey: Key.autoReviveCooldownUntil)
        return true
    }

    // MARK: - Speed Boost (ad-gated: watch 1 ad for 2x move speed + fire rate for 15 minutes)

    var speedBoostTimeRemaining: TimeInterval {
        max(0, defaults.double(forKey: Key.speedBoostExpiry) - Date().timeIntervalSince1970)
    }

    var isSpeedBoostActive: Bool { speedBoostTimeRemaining > 0 }

    /// Called after a rewarded ad completes successfully. Always usable — watching again while already
    /// active just refreshes the full 15-minute window, same as Gold Rush's top tier.
    func recordSpeedBoostAdWatched() {
        defaults.set(Date().timeIntervalSince1970 + 15 * 60, forKey: Key.speedBoostExpiry)
    }

    func currentLoadout() -> MetaLoadout {
        var loadout = MetaLoadout()
        loadout.startingHealthBonus = CGFloat(tier(for: .startingHealth)) * 10
        loadout.startingSpeedMultiplier = 1.0 + CGFloat(tier(for: .startingSpeed)) * 0.03
        loadout.startingDamageMultiplier = 1.0 + CGFloat(tier(for: .startingDamage)) * 0.04
        loadout.startingMagnetBonus = CGFloat(tier(for: .startingMagnet)) * 15
        loadout.startingArmorBonus = CGFloat(tier(for: .startingArmor)) * 1
        loadout.startingCritBonus = CGFloat(tier(for: .startingCrit)) * 0.03
        loadout.goldGainMultiplier = (1.0 + CGFloat(tier(for: .goldGain)) * 0.10) * CGFloat(currentGoldRushMultiplier)
        loadout.lifestealFraction = CGFloat(tier(for: .lifesteal)) * 0.025
        loadout.dodgeChance = CGFloat(tier(for: .dodgeChance)) * 0.04
        loadout.xpGainMultiplier = 1.0 + CGFloat(tier(for: .xpGainBonus)) * 0.08
        return loadout
    }

    // MARK: - Pets

    private enum PetKey {
        static let activePets = "nightfeed.activePetKinds"
    }

    /// Every pet kind currently unlocked via the shop, in PetKind.allCases order.
    func ownedPetKinds() -> [PetKind] {
        PetKind.allCases.filter { tier(for: $0.unlockKind) > 0 }
    }

    /// Which pet(s) actually join the run: up to 1, or up to 2 with the "Second Familiar" upgrade.
    /// Falls back to whatever's owned (in a stable order) if the saved selection references a pet
    /// that's no longer owned or nothing was ever explicitly selected.
    func activePetKinds() -> [PetKind] {
        let owned = ownedPetKinds()
        guard !owned.isEmpty else { return [] }
        let slots = tier(for: .secondPetSlot) > 0 ? 2 : 1
        let saved = (defaults.array(forKey: PetKey.activePets) as? [String] ?? [])
            .compactMap { PetKind(rawValue: $0) }
            .filter { owned.contains($0) }
        var selection = saved.isEmpty ? owned : saved
        if selection.count > slots { selection = Array(selection.prefix(slots)) }
        return selection
    }

    func setActivePetKinds(_ kinds: [PetKind]) {
        defaults.set(kinds.map { $0.rawValue }, forKey: PetKey.activePets)
    }

    // MARK: - Skins

    private enum SkinKey {
        static let selectedSkin = "nightfeed.selectedSkin"
    }

    func isSkinOwned(_ kind: PlayerSkinKind) -> Bool {
        switch kind {
        case .nightCloak: return true
        case .crimsonFang: return tier(for: .skinCrimsonFang) > 0
        case .moonlitVeil: return tier(for: .skinMoonlitVeil) > 0
        case .voidReaper: return tier(for: .skinVoidReaper) > 0
        case .emberSovereign: return tier(for: .skinEmberSovereign) > 0
        }
    }

    /// Falls back to the free default if the saved selection references a skin that's no longer owned.
    var selectedSkin: PlayerSkinKind {
        get {
            let raw = defaults.string(forKey: SkinKey.selectedSkin) ?? PlayerSkinKind.nightCloak.rawValue
            let kind = PlayerSkinKind(rawValue: raw) ?? .nightCloak
            return isSkinOwned(kind) ? kind : .nightCloak
        }
        set {
            guard isSkinOwned(newValue) else { return }
            defaults.set(newValue.rawValue, forKey: SkinKey.selectedSkin)
        }
    }

    // MARK: - Starting potions ("Potion Mastery" meta upgrade)

    private enum PotionKey {
        static let startingPotions = "nightfeed.startingPotions"
    }

    var startingPotionSlots: Int { tier(for: .potionMastery) }

    /// Which potion kinds actually start pre-applied each run — capped by startingPotionSlots.
    /// Instant kinds (voidMagnet/risingMoon) are excluded: "start the run with a free level-up
    /// already applied" isn't a coherent starting-buff choice the way a timed buff is.
    func selectedStartingPotions() -> [PotionKind] {
        let saved = (defaults.array(forKey: PotionKey.startingPotions) as? [String] ?? [])
            .compactMap { PotionKind(rawValue: $0) }
            .filter { !$0.isInstant }
        return Array(saved.prefix(startingPotionSlots))
    }

    func setSelectedStartingPotions(_ kinds: [PotionKind]) {
        let capped = Array(kinds.filter { !$0.isInstant }.prefix(startingPotionSlots))
        defaults.set(capped.map { $0.rawValue }, forKey: PotionKey.startingPotions)
    }

    // MARK: - Reset

    /// Wipes ALL NightFeed progress — gold, every meta upgrade tier, best time, run count, gold rush/
    /// auto-revive/speed-boost state, and skin/pet/potion selections. Irreversible — the caller
    /// (MenuScene) is responsible for a confirmation step before calling this.
    func resetAll() {
        let all = defaults.dictionaryRepresentation()
        for key in all.keys where key.hasPrefix("nightfeed.") {
            defaults.removeObject(forKey: key)
        }
    }
}
