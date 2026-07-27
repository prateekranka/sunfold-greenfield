import Foundation
import simd

/// What a citizen is carrying home.
struct Cargo: Sendable, Equatable {
    var kind: ResourceKind
    var amount: Double
}

/// Runs the gather → carry → deliver → return cycle.
///
/// Pure and deterministic, like `MovementSystem`: it reads state and a step
/// duration and writes state. It never touches presentation and never reads
/// frame timing.
///
/// The cycle has no explicit phase field. Which leg a citizen is on is *derived*
/// from whether it is carrying a full load, so there is no phase enum that can
/// fall out of step with the cargo it describes. The one persistent decision —
/// which node this citizen works — lives on the unit as `assignment`.
enum GatheringSystem {

    /// Advances every citizen with a gather assignment.
    static func step(
        units: inout [EntityID: Unit],
        buildings: [EntityID: Building],
        deposits: inout [EntityID: Deposit],
        stock: inout [Faction: ResourcePool],
        map: WorldMap,
        tuning: SkirmishTuning,
        deltaTime: Double
    ) {
        // Sorted keys, so two runs of the same seed resolve a contested node in
        // the same order.
        for id in units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id], let assignment = unit.assignment else { continue }
            guard unit.kind.canGather, !unit.isAboard else { continue }

            advance(
                &unit,
                assignment: assignment,
                buildings: buildings,
                deposits: &deposits,
                stock: &stock,
                map: map,
                tuning: tuning,
                deltaTime: deltaTime
            )
            units[id] = unit
        }
    }

    private static func advance(
        _ unit: inout Unit,
        assignment: EntityID,
        buildings: [EntityID: Building],
        deposits: inout [EntityID: Deposit],
        stock: inout [Faction: ResourcePool],
        map: WorldMap,
        tuning: SkirmishTuning,
        deltaTime: Double
    ) {
        // A node that has been exhausted or removed ends the assignment, but not
        // the trip: a citizen holding a load still walks it home first.
        guard let deposit = deposits[assignment], !deposit.isExhausted else {
            if unit.cargo == nil {
                unit.assignment = nil
                unit.activity = .idle
            } else {
                deliverLeg(&unit, buildings: buildings, stock: &stock, map: map, tuning: tuning)
            }
            return
        }

        if isFull(unit, tuning: tuning) {
            deliverLeg(&unit, buildings: buildings, stock: &stock, map: map, tuning: tuning)
        } else {
            gatherLeg(&unit, deposit: deposit, deposits: &deposits, map: map, tuning: tuning, deltaTime: deltaTime)
        }
    }

    // MARK: - Legs

    /// Walk to this citizen's station on the node, then extract.
    private static func gatherLeg(
        _ unit: inout Unit,
        deposit: Deposit,
        deposits: inout [EntityID: Deposit],
        map: WorldMap,
        tuning: SkirmishTuning,
        deltaTime: Double
    ) {
        unit.activity = .gathering(depositID: deposit.id)

        // Resolving up front means a station clamped off the fragment's edge
        // becomes a reachable point rather than a destination the citizen walks
        // at forever.
        let station = MovementSystem.resolveDestination(
            workStation(at: deposit, for: unit), for: unit, map: map
        ) ?? deposit.position

        guard simd_distance(unit.position, station) <= arrivalTolerance else {
            unit.destination = station
            return
        }

        unit.destination = nil

        // Standing at a station always satisfies this; the slack only matters
        // when a station was clamped, and it is still unambiguously "at the
        // rock" rather than reaching the node from across the fragment.
        guard simd_distance(unit.position, deposit.position) <= Deposit.workRadius + arrivalTolerance
        else { return }

        let carried = unit.cargo?.amount ?? 0
        let room = tuning.carryCapacity - carried
        let extracted = min(tuning.gatherRates[deposit.kind] * deltaTime, room, deposit.remaining)
        guard extracted > 0 else { return }

        // Carrying one kind at a time. Switching nodes mid-load would silently
        // convert what is already on a citizen's back, so a partial load of the
        // wrong kind is delivered before the new node is worked.
        if let existing = unit.cargo, existing.kind != deposit.kind { return }

        unit.cargo = Cargo(kind: deposit.kind, amount: carried + extracted)
        deposits[deposit.id]?.remaining -= extracted
    }

    /// Walk the load to the nearest accepting building and hand it over.
    private static func deliverLeg(
        _ unit: inout Unit,
        buildings: [EntityID: Building],
        stock: inout [Faction: ResourcePool],
        map: WorldMap,
        tuning: SkirmishTuning
    ) {
        guard let target = nearestDropOff(for: unit, in: buildings) else {
            // Nowhere to deliver. Hold the load rather than deleting it, so the
            // resource is never silently destroyed — it becomes deliverable again
            // the moment a drop-off exists.
            unit.destination = nil
            unit.activity = .idle
            return
        }

        let reach = target.kind.footprintRadius + Deposit.workRadius
        guard simd_distance(unit.position, target.position) <= reach else {
            let approach = approachPoint(
                to: target.position,
                from: unit.position,
                standOff: reach * 0.85
            )
            unit.destination = MovementSystem.resolveDestination(approach, for: unit, map: map)
            return
        }

        guard let cargo = unit.cargo else { return }
        var pool = stock[unit.faction] ?? .zero
        pool[cargo.kind] += cargo.amount
        stock[unit.faction] = pool
        unit.cargo = nil
        unit.destination = nil
    }

    // MARK: - Work stations

    /// How many distinct standing positions a node offers.
    ///
    /// Six, because a citizen's footprint is 1.15 m and six stations on a 2.28 m
    /// ring sit 2.4 m apart — just clear of each other. More slots would let
    /// workers interpenetrate, which is what a single shared approach point was
    /// already doing.
    static let stationCount = 6

    /// Roughly a footprint. Tight enough that a citizen visibly *stands* at its
    /// station rather than stopping wherever it first came into range.
    private static let arrivalTolerance: Float = 0.9

    /// The fixed spot this citizen works this node from.
    ///
    /// A pure function of the node and the unit's durable ID, which buys two
    /// things at once. Workers fan out around the rock instead of converging on
    /// one point and standing inside each other — the previous approach walked
    /// every citizen to a stand-off computed from its *own* position, so four
    /// citizens sent from the same place all arrived at the same place. And
    /// because the station never moves, a citizen returning from a delivery
    /// walks back to the spot it left, which reads as its own working position
    /// rather than a scramble for the nearest gap.
    static func workStation(at deposit: Deposit, for unit: Unit) -> WorldPoint {
        let slot = unit.id.raw % UInt32(stationCount)
        let angle = Float(slot) / Float(stationCount) * 2 * .pi
        let radius = Deposit.workRadius * 0.95
        return deposit.position + WorldPoint(sin(angle), cos(angle)) * radius
    }

    // MARK: - Helpers

    static func isFull(_ unit: Unit, tuning: SkirmishTuning) -> Bool {
        (unit.cargo?.amount ?? 0) >= tuning.carryCapacity - 1e-6
    }

    /// The nearest complete, drop-off-accepting building of the unit's faction.
    private static func nearestDropOff(
        for unit: Unit,
        in buildings: [EntityID: Building]
    ) -> Building? {
        buildings.values
            .filter { $0.faction == unit.faction && $0.isComplete && $0.kind.acceptsDropOff }
            // Distance first, then ID: two equidistant Cores must resolve the
            // same way on every replay.
            .min {
                let left = simd_distance($0.position, unit.position)
                let right = simd_distance($1.position, unit.position)
                return left == right ? $0.id.raw < $1.id.raw : left < right
            }
    }

    /// A point `standOff` metres short of `target`, on the line from `from`.
    private static func approachPoint(
        to target: WorldPoint,
        from origin: WorldPoint,
        standOff: Float
    ) -> WorldPoint {
        let away = origin - target
        let length = simd_length(away)
        guard length > 1e-4 else { return target }
        return target + (away / length) * standOff
    }
}
