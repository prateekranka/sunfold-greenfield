import Foundation

/// Every mobile thing the simulation can own.
enum UnitKind: String, CaseIterable, Sendable {
    case citizen
    case pathfinder
    case vanguard
    case quarrel
    case lightTransport
    case bastionWalker

    var displayName: String {
        switch self {
        case .citizen: "Citizen"
        case .pathfinder: "Pathfinder"
        case .vanguard: "Vanguard"
        case .quarrel: "Quarrel"
        case .lightTransport: "Light Transport"
        case .bastionWalker: "Bastion Walker"
        }
    }

    /// Unit names are written explicitly so roster terminology stays intentional.
    var pluralName: String {
        switch self {
        case .citizen: "Citizens"
        case .pathfinder: "Pathfinders"
        case .vanguard: "Vanguards"
        case .quarrel: "Quarrels"
        case .lightTransport: "Light Transports"
        case .bastionWalker: "Bastion Walkers"
        }
    }

    /// Metres per second on open land.
    var speed: Float {
        switch self {
        case .citizen: 3.4
        case .pathfinder: 4.6
        case .vanguard: 3.0
        case .quarrel: 3.2
        case .lightTransport: 5.2
        case .bastionWalker: 2.6
        }
    }

    /// Transports travel void lanes; everything else is bound to land and
    /// causeways. Keeping this on the kind means no system has to special-case
    /// hull movement by name.
    var travelsVoid: Bool { self == .lightTransport }

    var canGather: Bool { self == .citizen }

    var isMilitary: Bool {
        switch self {
        case .vanguard, .quarrel, .bastionWalker: true
        default: false
        }
    }

    /// Who may capture or contest the Dominion Spire.
    ///
    /// Deliberately its own list rather than `isMilitary`, per
    /// `05-RESOLUTIONS-R1.md` §3 (B10.2). The two are identical today, and that
    /// is exactly the trap: `isMilitary` is a combat question, and reusing it
    /// would silently answer a *victory* question every time a unit is added.
    /// The spec's set is Vanguard, Quarrel, Lancer, Bastion Walker, Sunlance and
    /// Ironsworn — the last four of which do not exist yet, so this list grows
    /// as the roster does. A Pathfinder can see the Dominion and cannot hold it,
    /// which is the right shape for a scout; Citizens neither capture nor contest.
    var canCaptureDominion: Bool {
        switch self {
        case .vanguard, .quarrel, .bastionWalker: true
        case .citizen, .pathfinder, .lightTransport: false
        }
    }

    var populationCost: Int {
        switch self {
        case .citizen, .pathfinder, .vanguard, .quarrel: 1
        case .bastionWalker: 3
        case .lightTransport: 0
        }
    }

    var maxLife: Double {
        switch self {
        case .citizen: 40
        case .pathfinder: 45
        case .vanguard: 75
        case .quarrel: 50
        case .lightTransport: 140
        case .bastionWalker: 190
        }
    }

    var armorClass: ArmorClass {
        switch self {
        case .citizen: .worker
        case .pathfinder, .vanguard, .quarrel: .infantry
        case .bastionWalker: .siege
        case .lightTransport: .hull
        }
    }

    var meleeArmor: Int {
        switch self {
        case .citizen, .pathfinder, .quarrel: 0
        case .vanguard: 1
        case .bastionWalker: 3
        case .lightTransport: 2
        }
    }

    var rangedArmor: Int {
        switch self {
        case .citizen, .pathfinder, .vanguard, .quarrel: 0
        case .bastionWalker: 4
        case .lightTransport: 2
        }
    }

    /// Metres. Always greater than weapons range for military units.
    var sightRange: Float {
        switch self {
        case .citizen: 9
        case .pathfinder: 20
        case .vanguard: 11
        case .quarrel: 13
        case .lightTransport: 14
        case .bastionWalker: 10
        }
    }

    /// Nil when the kind cannot attack (e.g. Light Transport).
    var attackProfile: AttackProfile? {
        switch self {
        case .citizen:
            AttackProfile(
                damageType: .melee,
                base: 3,
                bonuses: [.building: 3],
                range: 0.8,
                cooldownTicks: 30
            )
        case .pathfinder:
            AttackProfile(
                damageType: .melee,
                base: 4,
                bonuses: [.worker: 5],
                range: 0.9,
                cooldownTicks: 26
            )
        case .vanguard:
            AttackProfile(
                damageType: .melee,
                base: 7,
                bonuses: [.mounted: 10, .siege: 8],
                range: 0.9,
                cooldownTicks: 24
            )
        case .quarrel:
            AttackProfile(
                damageType: .ranged,
                base: 6,
                bonuses: [.infantry: 4],
                range: 9.0,
                cooldownTicks: 28
            )
        case .bastionWalker:
            AttackProfile(
                damageType: .siege,
                base: 20,
                bonuses: [.building: 45],
                range: 9.0,
                cooldownTicks: 60
            )
        case .lightTransport:
            nil
        }
    }

    var canAttack: Bool { attackProfile != nil }

    /// Radius used for selection hit-testing, formation spacing and the margin a
    /// unit keeps from a fragment's rim.
    ///
    /// These carry `SkirmishTuning.unitVisualScale` already folded in, because a
    /// unit that is *drawn* 1.25× life-size must also be *tapped*, spaced and
    /// kept off the rim at 1.25×. Splitting the two produced a unit whose
    /// silhouette and hit area disagreed.
    var footprintRadius: Float {
        switch self {
        case .citizen, .pathfinder, .quarrel: 1.15
        case .vanguard: 1.4
        case .lightTransport: 4.0
        case .bastionWalker: 2.25
        }
    }
}

/// Every fixed structure the simulation can own.
enum BuildingKind: String, CaseIterable, Sendable {
    case civilizationCore
    case farm
    case matterExtractor
    case dwelling
    case formationYard
    case lumenSpire
    case expansionOutpost
    case dawnLoom
    /// Neutral, pre-placed, indestructible. The fifteenth building and the only
    /// one nobody builds — it is the Dominion objective, not a structure.
    case dominionSpire

    var displayName: String {
        switch self {
        case .civilizationCore: "Civilization Core"
        case .farm: "Farm"
        case .matterExtractor: "Matter Extractor"
        case .dwelling: "Dwelling"
        case .formationYard: "Formation Yard"
        case .lumenSpire: "Lumen Spire"
        case .expansionOutpost: "Expansion Outpost"
        case .dawnLoom: "Dawn Loom"
        case .dominionSpire: "Dominion Spire"
        }
    }

    /// One-line purpose shown while placing or inspecting.
    var purpose: String {
        switch self {
        case .civilizationCore: "Heart of the Hearth"
        case .farm: "Grows Provisions for the Hearth"
        case .matterExtractor: "Pulls Matter from nearby deposits"
        case .dwelling: "Raises the population cap"
        case .formationYard: "Trains Pathfinders and Vanguards"
        case .lumenSpire: "Trains Quarrels"
        case .expansionOutpost: "Claims an expansion fragment"
        case .dawnLoom: "Channels the Voyager age"
        case .dominionSpire: "Hold it to claim the Dominion"
        }
    }

    var maxLife: Double {
        switch self {
        case .civilizationCore: 600
        case .farm: 120
        case .matterExtractor: 160
        case .dwelling: 180
        case .formationYard: 260
        case .lumenSpire: 210
        case .expansionOutpost: 240
        case .dawnLoom: 320
        // Specified by R1 §3 (B10.1) and inert: the Spire is indestructible, so
        // nothing ever reads this down. Kept at the specified number rather than
        // dropped, so the day it becomes destructible the value is already right.
        case .dominionSpire: 1200
        }
    }

    /// Radius used for placement legality, selection and unit avoidance.
    ///
    /// The Core value is the larger authored base radius of the two faction
    /// meshes, plus a small visual margin: Sunwoven reaches 5.40 m and
    /// Gravemark reaches 5.35 m. Keeping one conservative value here preserves
    /// the shared circular obstacle truth used by movement and placement.
    var footprintRadius: Float {
        switch self {
        case .civilizationCore: 5.5
        case .farm: 3.6
        case .matterExtractor: 2.6
        case .dwelling: 2.6
        case .formationYard: 4.0
        case .lumenSpire: 3.0
        case .expansionOutpost: 3.0
        case .dawnLoom: 4.4
        case .dominionSpire: 4.0
        }
    }

    /// Whether a citizen may hand a load over here.
    ///
    /// The Core alone would work, but forcing every delivery back to the centre
    /// of the fragment makes a distant node feel punishing rather than distant.
    /// The two resource buildings accept as well, which is what gives placing
    /// them near a node a point.
    var acceptsDropOff: Bool {
        switch self {
        case .civilizationCore, .farm, .matterExtractor: true
        default: false
        }
    }

    var populationGrant: Int {
        switch self {
        case .dwelling: 8
        case .expansionOutpost: 2
        default: 0
        }
    }

    var armorClass: ArmorClass { .building }

    var meleeArmor: Int {
        switch self {
        case .farm: 0
        case .dominionSpire: 6
        default: 4
        }
    }

    var rangedArmor: Int {
        switch self {
        case .farm: 0
        case .dominionSpire: 8
        default: 6
        }
    }

    /// Neutral objectives belong to nobody, cannot be built, cannot be selected
    /// and cannot be damaged. `Building.faction` is `nil` for exactly these.
    var isNeutralObjective: Bool { self == .dominionSpire }

    /// Armed structures only. None of the shipped building kinds attack yet.
    var attackProfile: AttackProfile? { nil }

    /// Which production this building offers, if any.
    var trains: [UnitKind] {
        switch self {
        case .civilizationCore: [.citizen]
        case .formationYard: [.pathfinder, .vanguard]
        case .lumenSpire: [.quarrel]
        default: []
        }
    }
}
