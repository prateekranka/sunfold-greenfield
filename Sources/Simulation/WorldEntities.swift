import Foundation
import simd

/// What a unit is currently doing. Presentation reads this to choose a pose;
/// it never infers activity from position deltas.
enum UnitActivity: Sendable, Equatable {
    case idle
    case moving
    case gathering(depositID: EntityID)
    case boarding(transportID: EntityID)
    case aboard(transportID: EntityID)
    case constructing(buildingID: EntityID)
    case attacking(targetID: EntityID)
}

/// A mobile entity. Identity is the durable `EntityID`, never an array index.
struct Unit: Sendable, Identifiable {
    let id: EntityID
    let faction: Faction
    let kind: UnitKind

    var position: WorldPoint
    /// Where the unit is walking to. Nil means it has arrived or was never ordered.
    var destination: WorldPoint?
    /// Spawn facing, in radians about Y. Live facing belongs to the presentation
    /// layer's `LocomotionState`, which applies the turn-rate limit and deadband
    /// that stop a unit shivering between adjacent headings. Keeping one owner
    /// avoids two copies of facing drifting apart.
    var facing: Float
    var activity: UnitActivity = .idle
    var life: Double

    /// Which region the unit is standing on. Nil only while aboard a transport.
    var region: RegionID?
    /// Passengers, for transports only.
    var carrying: [EntityID] = []

    /// What a citizen is holding. One resource kind at a time, so a load is
    /// never a mixture that would have to be split on delivery.
    var cargo: Cargo?
    /// The deposit this citizen keeps returning to. Persisting the assignment
    /// across the round trip is what makes gathering a *loop* rather than a
    /// single errand the player has to re-issue after every delivery.
    var assignment: EntityID?

    init(
        id: EntityID,
        faction: Faction,
        kind: UnitKind,
        position: WorldPoint,
        facing: Float = 0,
        region: RegionID?
    ) {
        self.id = id
        self.faction = faction
        self.kind = kind
        self.position = position
        self.facing = facing
        self.region = region
        self.life = kind.maxLife
    }

    var isAboard: Bool {
        if case .aboard = activity { return true }
        return false
    }
}

/// A fixed structure.
struct Building: Sendable, Identifiable {
    let id: EntityID
    let faction: Faction
    let kind: BuildingKind
    let position: WorldPoint
    let region: RegionID

    var life: Double
    /// 0...1 while under construction; 1 once complete.
    var constructionProgress: Double

    var isComplete: Bool { constructionProgress >= 1 }

    init(
        id: EntityID,
        faction: Faction,
        kind: BuildingKind,
        position: WorldPoint,
        region: RegionID,
        constructionProgress: Double = 1
    ) {
        self.id = id
        self.faction = faction
        self.kind = kind
        self.position = position
        self.region = region
        self.constructionProgress = constructionProgress
        self.life = kind.maxLife
    }
}

/// A gatherable resource node.
struct Deposit: Sendable, Identifiable {
    let id: EntityID
    let kind: ResourceKind
    let position: WorldPoint
    let region: RegionID

    /// Remaining yield. Renewable deposits are seeded with `.infinity` and never
    /// deplete, which keeps "is this exhausted?" a single uniform check.
    var remaining: Double

    var isExhausted: Bool { remaining <= 0 }

    /// How close a citizen must be to work this node.
    static let workRadius: Float = 2.4
}
