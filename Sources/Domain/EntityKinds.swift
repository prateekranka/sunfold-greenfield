import Foundation

/// Every mobile thing the simulation can own.
enum UnitKind: String, CaseIterable, Sendable {
    case citizen
    case pathfinder
    case vanguard
    case ranged
    case lightTransport
    case bastionWalker

    var displayName: String {
        switch self {
        case .citizen: "Citizen"
        case .pathfinder: "Pathfinder"
        case .vanguard: "Vanguard"
        case .ranged: "Ranged"
        case .lightTransport: "Light Transport"
        case .bastionWalker: "Bastion Walker"
        }
    }

    /// Written out rather than derived by appending "s", because "Ranged" is
    /// already plural and a naive rule would print "Rangeds" in the one place
    /// the player reads a group at a glance.
    var pluralName: String {
        switch self {
        case .citizen: "Citizens"
        case .pathfinder: "Pathfinders"
        case .vanguard: "Vanguards"
        case .ranged: "Ranged"
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
        case .ranged: 3.2
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
        case .vanguard, .ranged, .bastionWalker: true
        default: false
        }
    }

    var populationCost: Int {
        switch self {
        case .citizen, .pathfinder, .vanguard, .ranged: 1
        case .bastionWalker: 3
        case .lightTransport: 0
        }
    }

    var maxLife: Double {
        switch self {
        case .citizen: 40
        case .pathfinder: 55
        case .vanguard: 110
        case .ranged: 70
        case .lightTransport: 140
        case .bastionWalker: 190
        }
    }

    /// Radius used for selection hit-testing, formation spacing and the margin a
    /// unit keeps from a fragment's rim.
    ///
    /// These carry `SkirmishTuning.unitVisualScale` already folded in, because a
    /// unit that is *drawn* 1.25× life-size must also be *tapped*, spaced and
    /// kept off the rim at 1.25×. Splitting the two produced a unit whose
    /// silhouette and hit area disagreed.
    var footprintRadius: Float {
        switch self {
        case .citizen, .pathfinder, .ranged: 1.15
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
    case expansionOutpost
    case dawnLoom

    var displayName: String {
        switch self {
        case .civilizationCore: "Civilization Core"
        case .farm: "Farm"
        case .matterExtractor: "Matter Extractor"
        case .dwelling: "Dwelling"
        case .formationYard: "Formation Yard"
        case .expansionOutpost: "Expansion Outpost"
        case .dawnLoom: "Dawn Loom"
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
        case .expansionOutpost: "Claims an expansion fragment"
        case .dawnLoom: "Channels the Voyager age"
        }
    }

    var maxLife: Double {
        switch self {
        case .civilizationCore: 600
        case .farm: 120
        case .matterExtractor: 160
        case .dwelling: 180
        case .formationYard: 260
        case .expansionOutpost: 240
        case .dawnLoom: 320
        }
    }

    /// Radius used for placement legality, selection and unit avoidance.
    var footprintRadius: Float {
        switch self {
        case .civilizationCore: 5.0
        case .farm: 3.6
        case .matterExtractor: 2.6
        case .dwelling: 2.6
        case .formationYard: 4.0
        case .expansionOutpost: 3.0
        case .dawnLoom: 4.4
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

    /// Which production this building offers, if any.
    var trains: [UnitKind] {
        switch self {
        case .civilizationCore: [.citizen]
        case .formationYard: [.pathfinder, .vanguard, .ranged]
        default: []
        }
    }
}
