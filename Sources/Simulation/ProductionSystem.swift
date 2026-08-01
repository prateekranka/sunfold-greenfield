import Foundation
import simd

/// One unit waiting in a building's production FIFO.
struct ProductionItem: Sendable, Equatable {
    let kind: UnitKind
    /// Ticks elapsed on the front item only. Zero until production starts.
    var progressTicks: Int = 0
    /// True once the front item has received its first tick of progress.
    var hasStarted: Bool = false
}

/// Per-building production queue. Cost is charged on enqueue; refunds follow
/// `SkirmishTuning.cancelRefundFraction` when cancelled or the building is lost.
struct ProductionQueue: Sendable, Equatable {
    var items: [ProductionItem] = []

    var isEmpty: Bool { items.isEmpty }
    var count: Int { items.count }

    var front: ProductionItem? { items.first }

    var reservedPopulation: Int {
        items.reduce(0) { $0 + $1.kind.populationCost }
    }
}

enum ProductionEnqueueFailure: Sendable, Equatable, Error {
    case notTrainable
    case buildingIncomplete
    case queueFull
    case cannotAfford(String)
    case populationCap(used: Int, cap: Int)
}

/// Advances training queues and spawns completed units. Pure, tick-driven, and
/// deterministic — no wall-clock timing and no randomness.
enum ProductionSystem {

    // MARK: - Commands

    static func enqueue(
        _ kind: UnitKind,
        at buildingID: EntityID,
        queues: inout [EntityID: ProductionQueue],
        buildings: [EntityID: Building],
        stock: inout [Faction: ResourcePool],
        units: [EntityID: Unit],
        tuning: SkirmishTuning
    ) -> Result<Void, ProductionEnqueueFailure> {
        guard let building = buildings[buildingID] else {
            return .failure(.notTrainable)
        }
        // A neutral objective has no treasury and trains nothing.
        guard let owner = building.faction else {
            return .failure(.notTrainable)
        }
        guard building.isComplete else {
            return .failure(.buildingIncomplete)
        }
        guard building.kind.trains.contains(kind) else {
            return .failure(.notTrainable)
        }

        var queue = queues[buildingID, default: ProductionQueue()]
        guard queue.count < tuning.maxQueueLength else {
            return .failure(.queueFull)
        }

        let cost = tuning.cost(for: kind)
        let factionStock = stock[owner, default: .zero]
        guard factionStock.covers(cost) else {
            return .failure(.cannotAfford(missingCostSummary(needed: cost, have: factionStock)))
        }

        let pop = populationCommitment(
            faction: owner,
            units: units,
            queues: queues,
            buildings: buildings,
            tuning: tuning
        )
        let additional = kind.populationCost
        if pop.used + additional > pop.cap {
            return .failure(.populationCap(used: pop.used + additional, cap: pop.cap))
        }

        stock[owner, default: .zero] = factionStock - cost
        queue.items.append(ProductionItem(kind: kind))
        queues[buildingID] = queue
        return .success(())
    }

    @discardableResult
    static func cancelFront(
        at buildingID: EntityID,
        queues: inout [EntityID: ProductionQueue],
        buildings: [EntityID: Building],
        stock: inout [Faction: ResourcePool],
        tuning: SkirmishTuning
    ) -> Bool {
        guard var queue = queues[buildingID], !queue.items.isEmpty else { return false }
        guard let building = buildings[buildingID], let owner = building.faction else { return false }

        let item = queue.items.removeFirst()
        let cost = tuning.cost(for: item.kind)
        let fraction = item.hasStarted ? tuning.cancelRefundFraction : 1.0
        stock[owner, default: .zero] = stock[owner, default: .zero] + cost * fraction

        if queue.isEmpty {
            queues[buildingID] = nil
        } else {
            queues[buildingID] = queue
        }
        return true
    }

    /// Refunds the in-progress front item and discards the rest when a building
    /// is destroyed. Call before removing the building from simulation state.
    static func onBuildingDestroyed(
        _ buildingID: EntityID,
        queues: inout [EntityID: ProductionQueue],
        buildings: [EntityID: Building],
        stock: inout [Faction: ResourcePool],
        tuning: SkirmishTuning
    ) {
        guard var queue = queues[buildingID], !queue.isEmpty else {
            queues[buildingID] = nil
            return
        }
        guard let building = buildings[buildingID], let owner = building.faction else {
            queues[buildingID] = nil
            return
        }

        if let front = queue.items.first {
            let cost = tuning.cost(for: front.kind)
            let fraction = front.hasStarted ? tuning.cancelRefundFraction : 1.0
            stock[owner, default: .zero] = stock[owner, default: .zero] + cost * fraction
        }
        queues[buildingID] = nil
    }

    // MARK: - Stepping

    static func step(
        queues: inout [EntityID: ProductionQueue],
        units: inout [EntityID: Unit],
        buildings: [EntityID: Building],
        stock: inout [Faction: ResourcePool],
        map: WorldMap,
        tuning: SkirmishTuning,
        allocator: inout EntityIDAllocator
    ) {
        let buildingIDs = queues.keys.sorted(by: { $0.raw < $1.raw })
        for buildingID in buildingIDs {
            guard var queue = queues[buildingID], !queue.isEmpty else { continue }
            guard let building = buildings[buildingID],
                  let owner = building.faction,
                  building.isComplete,
                  !building.kind.trains.isEmpty
            else { continue }

            var front = queue.items[0]
            let totalTicks = tuning.buildTimeTicks(for: front.kind)
            guard totalTicks > 0 else { continue }

            if !front.hasStarted { front.hasStarted = true }
            front.progressTicks += 1
            queue.items[0] = front

            if front.progressTicks >= totalTicks {
                queue.items.removeFirst()
                if let spawn = spawnPosition(
                    for: front.kind,
                    near: building,
                    units: units,
                    buildings: buildings,
                    map: map
                ) {
                    let id = allocator.allocate()
                    units[id] = Unit(
                        id: id,
                        faction: owner,
                        kind: front.kind,
                        position: spawn.position,
                        facing: spawn.facing,
                        region: building.region
                    )
                }
            }

            if queue.isEmpty {
                queues[buildingID] = nil
            } else {
                queues[buildingID] = queue
            }
        }
    }

    // MARK: - Population

    static func populationCommitment(
        faction: Faction,
        units: [EntityID: Unit],
        queues: [EntityID: ProductionQueue],
        buildings: [EntityID: Building],
        tuning: SkirmishTuning
    ) -> (used: Int, cap: Int) {
        let live = units.values
            .filter { $0.faction == faction }
            .reduce(0) { $0 + $1.kind.populationCost }

        var queued = 0
        for (buildingID, queue) in queues {
            guard let building = buildings[buildingID], building.faction == faction else { continue }
            queued += queue.reservedPopulation
        }

        let granted = buildings.values
            .filter { $0.faction == faction && $0.isComplete }
            .reduce(0) { $0 + $1.kind.populationGrant }

        let cap = min(tuning.startingPopulationCap + granted, 200)
        return (live + queued, cap)
    }

    private struct SpawnResult: Sendable {
        var position: WorldPoint
        var facing: Float
    }

    /// Deterministic ring search beside the building. Slots are tried in a fixed
    /// order — ring 1 at six bearings, then ring 2 at twelve, and so on — so the
    /// same building always releases units to the same offsets with no RNG.
    private static func spawnPosition(
        for kind: UnitKind,
        near building: Building,
        units: [EntityID: Unit],
        buildings: [EntityID: Building],
        map: WorldMap
    ) -> SpawnResult? {
        let margin = kind.footprintRadius
        let clearance: Float = 0.6

        for ring in 1...4 {
            let slots = ring * 6
            for slot in 0..<slots {
                let angle = Float(slot) / Float(slots) * 2 * .pi
                let distance = building.kind.footprintRadius + margin + Float(ring) * 1.8
                let offset = WorldPoint(sin(angle), cos(angle)) * distance
                let candidate = building.position + offset

                guard map.isStandable(candidate, in: building.region, margin: margin) else {
                    continue
                }
                guard !overlapsStructure(
                    candidate,
                    radius: margin + clearance,
                    buildings: buildings,
                    excluding: building.id
                ) else { continue }
                guard !overlapsUnit(
                    candidate,
                    radius: margin + clearance,
                    units: units
                ) else { continue }

                return SpawnResult(position: candidate, facing: angle)
            }
        }

        // Last resort: clamp straight out from the building centre along +X.
        let fallback = building.position + WorldPoint(building.kind.footprintRadius + margin + 1.2, 0)
        let clamped = map.clampToLand(
            fallback,
            from: building.position,
            in: building.region,
            margin: margin
        )
        return SpawnResult(position: clamped, facing: 0)
    }

    private static func overlapsStructure(
        _ point: WorldPoint,
        radius: Float,
        buildings: [EntityID: Building],
        excluding: EntityID
    ) -> Bool {
        for building in buildings.values where building.id != excluding {
            let need = building.kind.footprintRadius + radius
            if simd_distance(building.position, point) < need { return true }
        }
        return false
    }

    private static func overlapsUnit(
        _ point: WorldPoint,
        radius: Float,
        units: [EntityID: Unit]
    ) -> Bool {
        for unit in units.values {
            let need = unit.kind.footprintRadius + radius
            if simd_distance(unit.position, point) < need { return true }
        }
        return false
    }

    private static func missingCostSummary(needed: ResourcePool, have: ResourcePool) -> String {
        ResourceKind.allCases.compactMap { kind in
            let shortfall = needed[kind] - have[kind]
            guard shortfall > 0.01 else { return nil }
            return "\(ResourcePool.displayAmount(shortfall)) \(kind.displayName)"
        }.joined(separator: " · ")
    }
}
