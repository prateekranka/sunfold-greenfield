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
    private(set) var productionQueues: [EntityID: ProductionQueue] = [:]
    private(set) var adversary: AdversaryState
    private(set) var victory = VictoryState()

    private var allocator: EntityIDAllocator
    /// Held so `restart()` can repopulate the same world it started with.
    private let perfDensity: Int?

    /// Presentation clock scale. 1.0 is real time; the fixed 20 Hz step size is
    /// unchanged — this only decides how many steps a wall-clock frame buys.
    var timeScale: Double = 1.0

    init(
        seed: UInt64,
        mapID: WorldMapID = .default,
        tuning: SkirmishTuning = .baseline,
        perfDensity: Int? = nil,
        adversaryEnabled: Bool = true
    ) {
        self.seed = seed
        self.mapID = mapID
        self.tuning = tuning
        self.perfDensity = perfDensity
        self.adversary = AdversaryState(faction: .gravemark, isEnabled: adversaryEnabled)
        let map = WorldMap.map(mapID, seed: seed)
        self.map = map
        self.clock = SimulationClock(tuning: tuning)
        self.stock = [
            .sunwoven: tuning.startingResources,
            .gravemark: tuning.startingResources,
        ]
        self.age = [.sunwoven: .foundation, .gravemark: .foundation]

        let populated = WorldPopulator.populate(
            map: map, tuning: tuning, perfDensity: perfDensity
        )
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
    /// Queued units count toward used population because cost is charged on enqueue.
    func population(for faction: Faction) -> (used: Int, cap: Int) {
        ProductionSystem.populationCommitment(
            faction: faction,
            units: units,
            queues: productionQueues,
            buildings: buildings,
            tuning: tuning
        )
    }

    func productionQueue(for buildingID: EntityID) -> ProductionQueue {
        productionQueues[buildingID] ?? ProductionQueue()
    }

    /// Canonical fingerprint of the whole world, per `05-RESOLUTIONS-R1.md` §6.13.
    /// Two runs of one seed that agree here played the same match.
    var worldHash: UInt64 {
        WorldHash.value(tick: clock.tick, stock: stock, units: units, buildings: buildings)
    }

    /// Front-item progress as 0…1 for HUD readout.
    func productionProgress(for buildingID: EntityID) -> Double {
        guard let front = productionQueues[buildingID]?.front else { return 0 }
        let total = tuning.buildTimeTicks(for: front.kind)
        guard total > 0 else { return 0 }
        return Double(front.progressTicks) / Double(total)
    }

    // MARK: - Orders

    /// Orders a unit to walk somewhere. The destination is clamped to somewhere
    /// the unit may legally stand, so an imprecise tap still produces a sensible
    /// move rather than being silently dropped.
    func order(_ id: EntityID, moveTo point: WorldPoint) {
        guard var unit = units[id] else { return }
        guard let destination = MovementSystem.resolveDestination(point, for: unit, map: map) else { return }
        unit.assignment = nil
        unit.attackOrderTarget = nil
        unit.attackTarget = nil
        unit.guardAnchor = nil
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

    /// Sends citizens to an incomplete foundation. Keeps builders already on the
    /// job and fills remaining slots up to the per-site cap.
    /// Returns how many citizens were newly assigned this call.
    @discardableResult
    func orderConstruct(_ ids: [EntityID], on buildingID: EntityID) -> Int {
        guard let building = buildings[buildingID],
              let owner = building.faction,
              !building.isComplete
        else { return 0 }
        return assignBuilders(to: buildingID, faction: owner, preferred: ids)
    }

    /// Maximum citizens that may work one foundation at once.
    static let maxBuildersPerSite = 4

    func orderBoard(_ ids: [EntityID], onto transportID: EntityID) {
        guard var transport = units[transportID],
              transport.kind == .lightTransport
        else { return }

        var seats = tuning.transportCapacity - transport.carrying.count
        guard seats > 0 else { return }

        for id in ids.sorted(by: { $0.raw < $1.raw }) {
            guard seats > 0 else { break }
            guard var unit = units[id] else { continue }
            guard unit.faction == transport.faction,
                  unit.kind.canGather,
                  !unit.isAboard,
                  !unit.isBoarding
            else { continue }

            unit.assignment = nil
            unit.boardingProgress = 0
            unit.activity = .boarding(transportID: transportID)
            // First leg: walk toward the hull; land clamping stops at the bank.
            unit.destination = MovementSystem.resolveDestination(
                transport.position, for: unit, map: map
            )
            units[id] = unit
            seats -= 1
        }
    }

    /// Orders military units to attack a hostile entity. Citizens may attack when
    /// explicitly commanded; they never auto-acquire on their own.
    func orderAttack(_ units: [EntityID], target: EntityID) {
        CombatSystem.orderAttack(units, target: target, units: &self.units)
    }

    /// Commits a foundation at `point`. Deducts cost, spawns an incomplete
    /// building, and sends preferred (or nearest idle) citizens to construct.
    /// Caller must already have validated footprint legality.
    /// Returns the new building id, or nil when stock or region refuse.
    @discardableResult
    func placeBuilding(
        _ kind: BuildingKind,
        at point: WorldPoint,
        for faction: Faction,
        preferredBuilders: [EntityID] = []
    ) -> EntityID? {
        guard let region = map.region(at: point) else { return nil }

        let cost = tuning.cost(for: kind)
        guard stock(for: faction).covers(cost) else { return nil }

        stock[faction, default: .zero] = stock(for: faction) - cost

        let id = allocator.allocate()
        buildings[id] = Building(
            id: id,
            faction: faction,
            kind: kind,
            position: point,
            region: region,
            constructionProgress: 0
        )
        assignBuilders(
            to: id,
            faction: faction,
            preferred: preferredBuilders
        )
        DebugLog.info(
            "Placed \(kind.displayName) #\(id.raw) at \(point)"
        )
        return id
    }

    /// Tears down an incomplete foundation and refunds a fraction of its cost.
    /// Completed buildings cannot be cancelled this way.
    @discardableResult
    func cancelConstruction(_ buildingID: EntityID) -> Bool {
        guard let building = buildings[buildingID],
              let owner = building.faction,
              !building.isComplete
        else { return false }
        let cost = tuning.cost(for: building.kind)
        let refund = cost * tuning.cancelRefundFraction
        stock[owner, default: .zero] = stock(for: owner) + refund

        for id in units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id] else { continue }
            guard case .constructing(buildingID) = unit.activity else { continue }
            unit.activity = .idle
            unit.destination = nil
            units[id] = unit
        }

        ProductionSystem.onBuildingDestroyed(
            buildingID,
            queues: &productionQueues,
            buildings: buildings,
            stock: &stock,
            tuning: tuning
        )

        buildings[buildingID] = nil
        DebugLog.info(
            "Cancelled \(building.kind.displayName) #\(buildingID.raw); refunded \(refund.matter) Matter"
        )
        return true
    }

    // MARK: - Production

    @discardableResult
    func enqueueUnit(_ kind: UnitKind, at buildingID: EntityID) -> Result<Void, ProductionEnqueueFailure> {
        ProductionSystem.enqueue(
            kind,
            at: buildingID,
            queues: &productionQueues,
            buildings: buildings,
            stock: &stock,
            units: units,
            tuning: tuning
        )
    }

    @discardableResult
    func cancelProduction(at buildingID: EntityID) -> Bool {
        ProductionSystem.cancelFront(
            at: buildingID,
            queues: &productionQueues,
            buildings: buildings,
            stock: &stock,
            tuning: tuning
        )
    }

    /// Sends citizens to an incomplete building. Prefers the caller's selection,
    /// then nearest idle gatherers of the same faction. Existing builders stay
    /// assigned until the foundation completes or is cancelled.
    /// Returns how many citizens were newly assigned.
    @discardableResult
    private func assignBuilders(
        to buildingID: EntityID,
        faction: Faction,
        preferred: [EntityID]
    ) -> Int {
        guard let building = buildings[buildingID], !building.isComplete else { return 0 }

        let alreadyAssigned = Set(units.values.compactMap { unit -> EntityID? in
            if case .constructing(buildingID) = unit.activity { return unit.id }
            return nil
        })
        var slots = max(0, Self.maxBuildersPerSite - alreadyAssigned.count)
        guard slots > 0 else { return 0 }

        var toAssign: [EntityID] = []
        for id in preferred.sorted(by: { $0.raw < $1.raw }) {
            guard slots > 0 else { break }
            guard let unit = units[id],
                  unit.faction == faction,
                  unit.canBeAssignedToConstruction,
                  !alreadyAssigned.contains(id)
            else { continue }
            toAssign.append(id)
            slots -= 1
        }

        if toAssign.isEmpty, preferred.isEmpty, slots > 0 {
            let idle = units.values
                .filter {
                    $0.faction == faction
                        && $0.canBeAssignedToConstruction
                        && !alreadyAssigned.contains($0.id)
                        && ($0.activity == .idle || isGathering($0))
                }
                .sorted {
                    simd_distance($0.position, building.position)
                        < simd_distance($1.position, building.position)
                }
            toAssign = Array(idle.prefix(min(slots, 2)).map(\.id))
        }

        for id in toAssign {
            sendToConstruction(id, buildingID: buildingID, building: building)
        }
        return toAssign.count
    }

    /// G2a carry disposition: credit carried load to faction stock once, then
    /// clear cargo. Construction is not a second drop-off — no duplicate credit.
    private func sendToConstruction(
        _ id: EntityID,
        buildingID: EntityID,
        building: Building
    ) {
        guard var unit = units[id], unit.canBeAssignedToConstruction else { return }

        if let cargo = unit.cargo {
            var pool = stock[unit.faction] ?? .zero
            pool[cargo.kind] += cargo.amount
            stock[unit.faction] = pool
            unit.cargo = nil
        }

        unit.assignment = nil
        unit.activity = .constructing(buildingID: buildingID)
        let delta = unit.position - building.position
        let length = simd_length(delta)
        let approach = min(
            building.kind.footprintRadius + 1.4,
            ConstructionSystem.workRadius(for: building.kind) * 0.85
        )
        let offset: WorldPoint = length < 0.01
            ? WorldPoint(approach, 0)
            : (delta / length) * approach
        unit.destination = MovementSystem.resolveDestination(
            building.position + offset, for: unit, map: map
        )
        units[id] = unit
    }

    private func isGathering(_ unit: Unit) -> Bool {
        if case .gathering = unit.activity { return true }
        return false
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

    // MARK: - Match state

    var outcome: MatchOutcome? { victory.outcome }
    var isOver: Bool { victory.outcome != nil }

    /// Seconds of Dominion hold required right now. Shrinks as the match runs
    /// long so a stalemate becomes a fight rather than a timeout.
    var dominionRequirement: Double {
        tuning.dominionHoldRequirement(atElapsed: clock.elapsed)
    }

    func dominionHold(for faction: Faction) -> Double { victory.hold(faction) }
    func dominionProgress(for faction: Faction) -> Double {
        let requirement = dominionRequirement
        guard requirement > 0 else { return 0 }
        return min(1, victory.hold(faction) / requirement)
    }
    func isDominionContested(for faction: Faction) -> Bool { victory.isContested(for: faction) }
    func coreLifeFraction(for faction: Faction) -> Double {
        VictorySystem.coreLifeFraction(faction, in: buildings)
    }

    /// The player concedes. A defeat, recorded as one.
    func resign(as faction: Faction = .sunwoven) {
        victory.resign(faction, tick: clock.tick, elapsed: clock.elapsed)
    }

    /// Plays the same match again from the same seed.
    ///
    /// Rebuilds in place rather than handing back a new object, because the
    /// renderer holds this simulation by a `let` and diffs the world by entity
    /// ID every frame — a fresh populate simply reads as "every old entity left,
    /// every new one arrived", which is exactly what a restart is.
    func restart() {
        clock = SimulationClock(tuning: tuning)
        stock = [
            .sunwoven: tuning.startingResources,
            .gravemark: tuning.startingResources,
        ]
        age = [.sunwoven: .foundation, .gravemark: .foundation]
        productionQueues = [:]
        victory = VictoryState()
        adversary = AdversaryState(faction: adversary.faction, isEnabled: adversary.isEnabled)
        isPaused = false

        let populated = WorldPopulator.populate(map: map, tuning: tuning, perfDensity: perfDensity)
        units = populated.units
        buildings = populated.buildings
        deposits = populated.deposits
        allocator = populated.allocator
    }

    // MARK: - Stepping

    /// Advances simulated time by a frame's worth of real time.
    ///
    /// A finished match does not step. The overlay is not a pause on top of a
    /// running world — the world is genuinely stopped behind it, which is the
    /// bar `04-IMPLEMENTATION-ORDER.md` §5 sets.
    func update(deltaTime: Double) {
        guard !isPaused, !isOver else { return }
        let steps = clock.advance(by: deltaTime * timeScale)
        guard steps > 0 else { return }
        for _ in 0..<steps {
            step()
            if isOver { break }
        }
    }

    /// One fixed simulation step. Everything rule-bearing happens here.
    private func step() {
        let seconds = tuning.stepDuration

        // Both sides receive the identical Core trickle. The AI is never granted
        // hidden income; difficulty changes planning, not accounting.
        for faction in Faction.allCases {
            stock[faction, default: .zero] = stock(for: faction) + tuning.coreTrickle * seconds
        }

        // The adversary decides first, then spends the tick like everyone else.
        // It reads end-of-previous-tick state and issues orders through the same
        // entry points a tap reaches, so it can take no shortcut the player lacks.
        stepAdversary()

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
        ConstructionSystem.step(
            units: &units,
            buildings: &buildings,
            map: map,
            tuning: tuning,
            deltaTime: seconds
        )
        MovementSystem.step(units: &units, map: map, deltaTime: seconds)
        let combatResult = CombatSystem.step(
            units: &units,
            buildings: &buildings,
            map: map
        )
        applyCombatDeaths(combatResult)
        ProductionSystem.step(
            queues: &productionQueues,
            units: &units,
            buildings: buildings,
            stock: &stock,
            map: map,
            tuning: tuning,
            allocator: &allocator
        )
        BoardingSystem.step(
            units: &units,
            map: map,
            tuning: tuning,
            deltaTime: seconds
        )

        // Last, because it judges the world every other system just produced.
        // A Core that fell to this tick's combat ends the match on this tick.
        VictorySystem.step(
            state: &victory,
            input: VictorySystem.Inputs(
                elapsed: clock.elapsed,
                tick: clock.tick,
                units: units,
                buildings: buildings,
                tuning: tuning,
                deltaTime: seconds
            )
        )
    }

    // MARK: - Adversary

    /// Runs the scheduled opponent and executes what it asked for.
    ///
    /// Planning and execution are separate on purpose: `Adversary.plan` receives
    /// `stock` by value and cannot write to it, so every cost the adversary pays
    /// is charged here, by the same methods the player's taps call.
    private func stepAdversary() {
        guard adversary.isEnabled else { return }

        let intents = Adversary.plan(
            Adversary.Inputs(
                tick: clock.tick,
                units: units,
                buildings: buildings,
                deposits: deposits,
                queues: productionQueues,
                stock: stock,
                map: map,
                tuning: tuning
            ),
            state: &adversary
        )

        for intent in intents {
            switch intent {
            case .gather(let unitID, let depositID):
                orderGather([unitID], from: depositID)

            case .train(let kind, let buildingID):
                _ = enqueueUnit(kind, at: buildingID)

            case .build(let kind, let point):
                placeBuilding(kind, at: point, for: adversary.faction)

            case .march(let unitID, let point):
                order(unitID, moveTo: point)

            case .setStance(let unitID, let stance):
                setStance(unitID, to: stance)
            }
        }
    }

    /// Sets a unit's pursuit stance. Attack waves march aggressive so they
    /// engage what they walk into instead of leashing to where they spawned.
    func setStance(_ id: EntityID, to stance: CombatStance) {
        guard var unit = units[id] else { return }
        unit.stance = stance
        unit.guardAnchor = nil
        units[id] = unit
    }

    /// Removes entities killed this tick and clears stale references elsewhere.
    private func applyCombatDeaths(_ result: CombatSystem.TickResult) {
        guard !result.deadUnits.isEmpty || !result.deadBuildings.isEmpty else { return }

        var deadUnits = Set(result.deadUnits)
        let deadBuildings = Set(result.deadBuildings)

        for unitID in result.deadUnits {
            if let transport = units[unitID], transport.kind == .lightTransport {
                for passengerID in transport.carrying {
                    deadUnits.insert(passengerID)
                }
            }
        }

        for buildingID in result.deadBuildings {
            ProductionSystem.onBuildingDestroyed(
                buildingID,
                queues: &productionQueues,
                buildings: buildings,
                stock: &stock,
                tuning: tuning
            )
            releaseBuilders(of: buildingID)
            buildings[buildingID] = nil
        }

        for unitID in deadUnits.sorted(by: { $0.raw < $1.raw }) {
            units[unitID] = nil
        }
        adversary.forget(deadUnits)

        for id in units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id] else { continue }

            if let target = unit.attackTarget, deadUnits.contains(target) || deadBuildings.contains(target) {
                unit.attackTarget = nil
            }
            if let ordered = unit.attackOrderTarget, deadUnits.contains(ordered) || deadBuildings.contains(ordered) {
                unit.attackOrderTarget = nil
            }

            if case .boarding(let transportID) = unit.activity, deadUnits.contains(transportID) {
                unit.activity = .idle
                unit.boardingProgress = 0
                unit.destination = nil
            }
            if case .aboard(let transportID) = unit.activity, deadUnits.contains(transportID) {
                units[id] = nil
                continue
            }
            if case .constructing(let buildingID) = unit.activity, deadBuildings.contains(buildingID) {
                unit.activity = .idle
                unit.destination = nil
            }
            if case .attacking(let targetID) = unit.activity,
               deadUnits.contains(targetID) || deadBuildings.contains(targetID)
            {
                unit.activity = .idle
                unit.attackTarget = nil
            }

            if unit.kind == .lightTransport {
                unit.carrying.removeAll { deadUnits.contains($0) }
            }

            units[id] = unit
        }

        for id in buildings.keys.sorted(by: { $0.raw < $1.raw }) {
            guard var building = buildings[id] else { continue }
            if let target = building.attackTarget,
               deadUnits.contains(target) || deadBuildings.contains(target)
            {
                building.attackTarget = nil
                buildings[id] = building
            }
        }
    }

    private func releaseBuilders(of buildingID: EntityID) {
        for id in units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard var unit = units[id] else { continue }
            guard case .constructing(buildingID) = unit.activity else { continue }
            unit.activity = .idle
            unit.destination = nil
            units[id] = unit
        }
    }
}
