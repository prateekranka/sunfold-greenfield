import Foundation

/// How an attacker's damage is classified for armour resolution.
enum DamageType: String, Sendable {
    case melee
    case ranged
    case siege
}

/// What kind of plating the defender carries. Bonus damage keys on this.
enum ArmorClass: String, Sendable, Hashable {
    case worker
    case infantry
    case mounted
    case siege
    case building
    case hull
}

/// Offensive profile for a unit or armed structure.
struct AttackProfile: Sendable, Equatable {
    let damageType: DamageType
    let base: Int
    /// Bonus keyed on the target's `ArmorClass`, applied before armour subtraction.
    let bonuses: [ArmorClass: Int]
    let range: Float
    let cooldownTicks: Int
}

/// How a military unit pursues auto-acquired targets.
enum CombatStance: String, Sendable, CaseIterable {
    case aggressive
    case guardStance
    case hold

    var displayName: String {
        switch self {
        case .aggressive: "Aggressive"
        case .guardStance: "Guard"
        case .hold: "Hold"
        }
    }
}

/// Resolves effective damage per `05-RESOLUTIONS-R1.md` §1.
enum CombatDamage {

    /// Minimum damage floor of 1 — nothing is invulnerable.
    static func effective(
        attacker: AttackProfile,
        targetMeleeArmor: Int,
        targetRangedArmor: Int,
        targetArmorClass: ArmorClass
    ) -> Int {
        let bonus = attacker.bonuses[targetArmorClass] ?? 0
        let armor = armorValue(
            damageType: attacker.damageType,
            meleeArmor: targetMeleeArmor,
            rangedArmor: targetRangedArmor
        )
        return max(1, attacker.base + bonus - armor)
    }

    static func armorValue(
        damageType: DamageType,
        meleeArmor: Int,
        rangedArmor: Int
    ) -> Int {
        switch damageType {
        case .melee: meleeArmor
        case .ranged: rangedArmor
        case .siege: meleeArmor
        }
    }
}
