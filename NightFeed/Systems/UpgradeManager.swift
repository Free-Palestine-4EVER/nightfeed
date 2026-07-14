import Foundation

/// One row of the 3-card level-up UI (built elsewhere, in GameScene). Purely data — no SpriteKit here.
struct UpgradeChoice {
    enum Kind {
        case newWeapon(WeaponKind)
        case weaponLevelUp(WeaponKind)
        case newPassive(PassiveKind)
        case passiveLevelUp(PassiveKind)
        case evolution(EvolvedWeaponKind)
    }

    let kind: Kind
    /// Weapon/passive/evolution displayName.
    let title: String
    /// Flavor text, or a "Level N -> N+1" / "NEW WEAPON" / "NEW PASSIVE" / "EVOLUTION" style detail line.
    let subtitle: String
}

/// Builds the eligible upgrade pool on every level-up and applies whichever card the player taps.
/// Owns the authoritative passive-level table — WeaponSystem owns weapon levels/evolutions itself.
final class UpgradeManager {
    private(set) var passiveLevels: [PassiveKind: Int] = [:]
    weak var weaponSystem: WeaponSystem?
    weak var player: PlayerController?

    init(weaponSystem: WeaponSystem, player: PlayerController) {
        self.weaponSystem = weaponSystem
        self.player = player
    }

    // MARK: - Rolling choices

    /// Builds up to `count` distinct, always-valid choices. Any weapon/passive evolution that has become
    /// eligible (base weapon maxed + its evolution passive maxed + not already evolved) is GUARANTEED to
    /// appear, occupying one of the slots outright rather than competing in the random pool. The remaining
    /// slots are filled by weighted random draw from every other eligible (never dead-end) choice.
    func rollChoices(count: Int = 3) -> [UpgradeChoice] {
        guard let weaponSystem = weaponSystem, count > 0 else { return [] }

        // Early game leans toward offering new weapons/passives; once most of the roster is owned,
        // level-ups and evolutions naturally dominate since there's less left to unlock.
        let totalSlots = WeaponKind.allCases.count + PassiveKind.allCases.count
        let ownedSlots = weaponSystem.ownedWeaponKinds().count + passiveLevels.values.filter { $0 > 0 }.count
        let ownedFraction = totalSlots > 0 ? Double(ownedSlots) / Double(totalSlots) : 0
        let newItemWeight = max(0.35, 1.5 - ownedFraction * 1.1)
        let levelUpWeight = 0.7 + ownedFraction * 1.3

        var weightedPool: [(choice: UpgradeChoice, weight: Double)] = []

        // New weapons: anything not yet owned. (There are exactly 6 WeaponKinds, so "owns fewer than 6
        // total" is automatically satisfied whenever this loop finds any unowned kind.)
        for kind in WeaponKind.allCases where weaponSystem.level(of: kind) == 0 {
            weightedPool.append((
                UpgradeChoice(kind: .newWeapon(kind), title: kind.displayName, subtitle: "NEW WEAPON — \(kind.flavorText)"),
                newItemWeight
            ))
        }

        // Weapon level-ups: owned, not maxed, and not superseded by an already-evolved form.
        for kind in weaponSystem.ownedWeaponKinds() {
            guard !weaponSystem.isMaxed(kind) else { continue }
            if let evolvedForm = kind.evolvedForm, weaponSystem.evolvedWeapons.contains(evolvedForm) { continue }
            let level = weaponSystem.level(of: kind)
            weightedPool.append((
                UpgradeChoice(kind: .weaponLevelUp(kind), title: kind.displayName, subtitle: "Level \(level) → \(level + 1)"),
                levelUpWeight
            ))
        }

        // New passives: not yet owned (absent or level 0).
        for kind in PassiveKind.allCases where (passiveLevels[kind] ?? 0) == 0 {
            weightedPool.append((
                UpgradeChoice(kind: .newPassive(kind), title: kind.displayName, subtitle: "NEW PASSIVE — \(kind.flavorText)"),
                newItemWeight
            ))
        }

        // Passive level-ups: owned and not maxed.
        for kind in PassiveKind.allCases {
            let level = passiveLevels[kind] ?? 0
            guard level > 0, level < PassiveKind.maxLevel else { continue }
            weightedPool.append((
                UpgradeChoice(kind: .passiveLevelUp(kind), title: kind.displayName, subtitle: "Level \(level) → \(level + 1)"),
                levelUpWeight
            ))
        }

        // Evolutions: guaranteed whenever eligible, not left to chance.
        var results: [UpgradeChoice] = []
        for kind in WeaponKind.allCases {
            guard results.count < count else { break }
            guard weaponSystem.isMaxed(kind),
                  let evolutionPassive = kind.evolutionPassive,
                  (passiveLevels[evolutionPassive] ?? 0) >= PassiveKind.maxLevel,
                  let evolvedForm = kind.evolvedForm,
                  !weaponSystem.evolvedWeapons.contains(evolvedForm)
            else { continue }
            results.append(UpgradeChoice(kind: .evolution(evolvedForm), title: evolvedForm.displayName, subtitle: "EVOLUTION — \(evolvedForm.flavorText)"))
        }

        // Fill remaining slots via weighted random draw, without replacement.
        var remaining = count - results.count
        var candidates = weightedPool
        while remaining > 0, !candidates.isEmpty {
            let totalWeight = candidates.reduce(0) { $0 + $1.weight }
            guard totalWeight > 0 else { break }
            var roll = Double.random(in: 0..<totalWeight)
            var pickedIndex = candidates.count - 1
            for (index, entry) in candidates.enumerated() {
                roll -= entry.weight
                if roll <= 0 {
                    pickedIndex = index
                    break
                }
            }
            results.append(candidates[pickedIndex].choice)
            candidates.remove(at: pickedIndex)
            remaining -= 1
        }

        return results
    }

    // MARK: - Applying a choice

    /// Applies the tapped card: mutates WeaponSystem and/or the passive-level table, then syncs
    /// PlayerController's derived stats for any passive whose level changed.
    func apply(_ choice: UpgradeChoice) {
        guard let weaponSystem = weaponSystem else { return }
        switch choice.kind {
        case .newWeapon(let kind):
            weaponSystem.acquire(kind)

        case .weaponLevelUp(let kind):
            weaponSystem.levelUp(kind)

        case .newPassive(let kind):
            setPassiveLevel(kind, to: 1)

        case .passiveLevelUp(let kind):
            let newLevel = (passiveLevels[kind] ?? 0) + 1
            setPassiveLevel(kind, to: newLevel)

        case .evolution(let evolvedForm):
            weaponSystem.evolve(evolvedForm.baseWeapon)
            AudioManager.shared.playSFX(.evolution)
        }
    }

    private func setPassiveLevel(_ kind: PassiveKind, to level: Int) {
        passiveLevels[kind] = level
        player?.setPassiveLevel(kind, level: level)
    }
}
