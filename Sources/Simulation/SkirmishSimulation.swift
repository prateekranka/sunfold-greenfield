import Foundation
import Observation
import simd

/// Owns all game truth. The renderer projects this state and sends intents back;
/// it never decides a rule.
@MainActor
@Observable
final class SkirmishSimulation {
    let tuning: SkirmishTuning
    let map: WorldMap
    let seed: UInt64
    let mapID: WorldMapID

    private(set) var clock: SimulationClock
    private(set) var stock: [Faction: ResourcePool]
    private(set) var age: [Faction: Age]
    private(set) var isPaused: Bool = false

    private(set) var units: [EntityID: Unit]
    private(set) var buildings: [EntityID: Building]
    private(set) var deposits: [EntityID: Deposit]

    private var allocator: EntityIDAllocator

    /// Presentation clock scale. 1.0 is real time; the fixed 20 Hz step size is
    /// unchanged — this only decides how many steps a wall-clock frame buys.
    var timeScale: Double = 1.0

    init(
        seed: UInt64,
        mapID: WorldMapID = .default,
        tuning: SkirmishTuning = .baseline
    ) {
        self.seed = seed
        self.mapID = mapID
        self.tuning = tuning
        let map = WorldMap.map(mapID, seed: seed)
        self.map = map
        self.clock = SimulationClock(tuning: tuning)
        self.stock = [
            .sunwoven: tuning.startingResources,
            .gravemark: tuning.startingResources,
        ]
        self.age = [.sunwoven: .foundation, .gravemark: .foundation]

        let populated = WorldPopulator.populate(map: map, tuning: tuning)
        self.units = populated.units
        self.buildings = populated.buildings
        self.deposits = populated.deposits
        self.allocator = populated.allocator
    }

    // MARK: - Readouts

    var elapsed: Double { clock.elapsed }
    var tick: UInt64 { clock.tick }

    func stock(for faction: Faction) -> ResourcePool { stock[faction] ?? .zero }
    func age(for faction: Faction) -> Age { age[faction] ?? .foundation }

    func units(of faction: Faction) -> [Unit] {
        units.values.filter { $0.faction == faction }.sorted { $0.id.raw < $1.id.raw }
    }

    func buildings(of faction: Faction) -> [Building] {
        buildings.values.filter { $0.faction == faction }.sorted { $0.id.raw < $1.id.raw }
    }

    func unit(_ id: EntityID) -> Unit? { units[id] }
    func building(_ id: EntityID) -> Building? { buildings[id] }
    func deposit(_ id: EntityID) -> Deposit? { deposits[id] }

    /// Population in use versus the cap granted by Dwellings and Outposts.
    func population(for faction: Faction) -> (used: Int, cap: Int) {
        let used = units.values
            .filter { $0.faction == faction }
            .reduce(0) { $0 + $1.kind.populationCost }
        let granted = buildings.values
            .filter { $0.faction == faction && $0.isComplete }
            .reduce(0) { $0 + $1.kind.populationGrant }
        return (used, min(tuning.startingPopulationCap + granted, 200))
    }

    // MARK: - Orders

    /// Orders a unit to walk somewhere. The destination is clamped to somewhere
    /// the unit may legally stand, so an imprecise tap still produces a sensible
    /// move rather than being silently dropped.
    func order(_ id: EntityID, moveTo point: WorldPoint) {
        guard var unit = units[id] else { return }
        guard let destination = MovementSystem.resolveDestination(point, for: unit, map: map) else { return }
        unit.assignment = nil
        unit.destination = destination
        unit.activity = .moving
        units[id] = unit
    }

    func orderMove(_ ids: [EntityID], to point: WorldPoint) {
        // Ordering several units to one point spreads them so they do not pile
        // onto a single coordinate. Slots derive from durable IDs, never from
        // collection order, so the same unit keeps the same slot every time.
        let ordered = ids.sorted { $0.raw < $1.raw }
        for (index, id) in ordered.enumerated() {
            units[id].map { _ in
                let offset = formationOffset(index: index, count: ordered.count)
                order(id, moveTo: point + offset)
            }
        }
    }

    /// A stable, outward-growing ring so groups arrive as a readable cluster.
    private func formationOffset(index: Int, count: Int) -> WorldPoint {
        guard count > 1, index > 0 else { return .zero }
        let ring = Int((Double(index) / 6.0).rounded(.down)) + 1
        let slotsInRing = ring * 6
        let slot = (index - 1) % slotsInRing
        let angle = Float(slot) / Float(slotsInRing) * 2 * .pi
        let radius = Float(ring) * 2.2
        return WorldPoint(sin(angle), cos(angle)) * radius
    }

    /// Assigns citizens to work a deposit. Anything in the selection that cannot
    /// gather is given a plain move order to the node instead, so a mixed
    /// selection does something sensible rather than half-ignoring the tap.
    func orderGather(_ ids: [EntityID], from depositID: EntityID) {
        guard let deposit = deposits[depositID], !deposit.isExhausted else { return }

        var escorts: [EntityID] = []
        for id in ids.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id] else { continue }
            guard unit.kind.canGather else {
                escorts.append(id)
                continue
            }
            unit.assignment = depositID
            unit.activity = .gathering(depositID: depositID)
            units[id] = unit
        }
        if !escorts.isEmpty { orderMove(escorts, to: deposit.position) }
    }

    /// Clears any gather assignment. A move order is the player overriding the
    /// loop, so it must stop the loop — otherwise the citizen walks where it was
    /// told and then immediately turns around.
    private func clearAssignment(_ id: EntityID) {
        guard var unit = units[id], unit.assignment != nil else { return }
        unit.assignment = nil
        units[id] = unit
    }

    func setPaused(_ paused: Bool) { isPaused = paused }

    // MARK: - Stepping

    /// Advances simulated time by a frame's worth of real time.
    func update(deltaTime: Double) {
        guard !isPaused else { return }
        let steps = clock.advance(by: deltaTime * timeScale)
        guard steps > 0 else { return }
        for _ in 0..<steps { step() }
    }

    /// One fixed simulation step. Everything rule-bearing happens here.
    private func step() {
        let seconds = tuning.stepDuration

        // Both sides receive the identical Core trickle. The AI is never granted
        // hidden income; difficulty changes planning, not accounting.
        for faction in Faction.allCases {
            stock[faction, default: .zero] = stock(for: faction) + tuning.coreTrickle * seconds
        }

        // Gathering decides where citizens want to be; movement then carries them
        // there. Running it first means a citizen that finishes a load this step
        // starts walking home in the same step rather than idling for one tick.
        GatheringSystem.step(
            units: &units,
            buildings: buildings,
            deposits: &deposits,
            stock: &stock,
            map: map,
            tuning: tuning,
            deltaTime: seconds
        )
        MovementSystem.step(units: &units, map: map, deltaTime: seconds)
    }
}
