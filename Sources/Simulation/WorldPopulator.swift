import Foundation
import simd

/// Seeds the authored starting state: Cores, citizens, transports and deposits.
///
/// Placement is deterministic and symmetric — whatever the Sunwoven receive on
/// their home fragment, the Gravemark receive the mirrored equivalent on theirs.
/// Nothing here grants either side an advantage.
enum WorldPopulator {

    struct Result {
        var units: [EntityID: Unit] = [:]
        var buildings: [EntityID: Building] = [:]
        var deposits: [EntityID: Deposit] = [:]
        var allocator: EntityIDAllocator
    }

    /// What each fragment carries at match start.
    private static func depositPlan(for region: RegionID) -> [ResourceKind] {
        switch region {
        case .sunwovenHome, .gravemarkHome:
            [.provisions, .provisions, .matter, .matter, .lumen]
        case .sunwovenExpansion, .gravemarkExpansion:
            [.matter, .lumen, .provisions, .aether]
        case .dominion:
            [.aether, .lumen]
        case .neutralOutcropNorth, .neutralOutcropSouth:
            [.matter, .aether]
        }
    }

    private static func startingYield(for kind: ResourceKind) -> Double {
        switch kind {
        case .provisions: .infinity  // Renewable forage never runs dry.
        case .matter: 420
        case .lumen: 300
        case .aether: 180
        }
    }

    static func populate(map: WorldMap, tuning: SkirmishTuning) -> Result {
        var result = Result(allocator: EntityIDAllocator())

        for faction in Faction.allCases {
            let home: RegionID = faction == .sunwoven ? .sunwovenHome : .gravemarkHome
            placeHome(faction: faction, region: home, map: map, tuning: tuning, into: &result)
        }

        for region in RegionID.allCases {
            placeDeposits(region: region, map: map, into: &result)
        }

        return result
    }

    // MARK: - Home fragment

    private static func placeHome(
        faction: Faction,
        region: RegionID,
        map: WorldMap,
        tuning: SkirmishTuning,
        into result: inout Result
    ) {
        let fragment = map.fragment(region)

        // The Core anchors the fragment centre — the visual anchor in concept 01.
        let coreID = result.allocator.allocate()
        result.buildings[coreID] = Building(
            id: coreID,
            faction: faction,
            kind: .civilizationCore,
            position: fragment.center,
            region: region
        )

        // Citizens stand in a loose arc in front of the Core, not a rigid ring.
        var random = DeterministicRandom.stream(seed: map.seed, tag: "start.\(faction.rawValue)")
        let expansion: RegionID = faction == .sunwoven ? .sunwovenExpansion : .gravemarkExpansion
        let outward = simd_normalize(map.fragment(expansion).center - fragment.center)
        let baseAngle = atan2(outward.x, outward.y)

        for index in 0..<tuning.startingCitizens {
            let spread = (Float(index) - Float(tuning.startingCitizens - 1) / 2) * 0.34
            let angle = baseAngle + spread + random.float(in: -0.06...0.06)
            let distance = BuildingKind.civilizationCore.footprintRadius + random.float(in: 3.0...6.5)
            let wanted = fragment.center + WorldPoint(sin(angle), cos(angle)) * distance
            // The arc faces the expansion, which since CP-14 is the direction the
            // water is in. Clamping keeps the opening line-up on the near bank.
            let position = map.clampToLand(
                wanted,
                from: fragment.center,
                in: region,
                margin: UnitKind.citizen.footprintRadius
            )

            let id = result.allocator.allocate()
            result.units[id] = Unit(
                id: id,
                faction: faction,
                kind: .citizen,
                position: position,
                facing: angle,
                region: region
            )
        }

        // The transport waits at the rim dock facing this side's expansion.
        let transportID = result.allocator.allocate()
        result.units[transportID] = Unit(
            id: transportID,
            faction: faction,
            kind: .lightTransport,
            position: map.dockPoint(on: region, facing: expansion),
            facing: baseAngle,
            region: nil  // A hull sits in the void, not on land.
        )
    }

    // MARK: - Deposits

    private static func placeDeposits(
        region: RegionID,
        map: WorldMap,
        into result: inout Result
    ) {
        let fragment = map.fragment(region)
        let plan = depositPlan(for: region)
        var random = DeterministicRandom.stream(seed: map.seed, tag: "deposits.\(region.rawValue)")

        // Keep deposits off the Core footprint and off each other, and on ground a
        // gathering citizen can actually reach — which since CP-14 means clear of
        // the map's rivers and lakes as well as inside the coast. `outerLimit` is
        // measured per bearing off the authored outline; a fixed radius would put
        // deposits in the void wherever the coast cuts in.
        let innerLimit = region.isHome ? BuildingKind.civilizationCore.footprintRadius + 6 : 3.0
        var placed: [WorldPoint] = []

        for (index, kind) in plan.enumerated() {
            var position = fragment.center
            // A bounded search: spread deposits around the fragment by index, then
            // jitter, retrying if the pick lands on water, off the plate, or on
            // top of an earlier one.
            for attempt in 0..<48 {
                let sector = Float(index) / Float(plan.count) * 2 * .pi
                let angle = sector + random.float(in: -0.5...0.5) + Float(attempt) * 0.31
                let heading = WorldPoint(sin(angle), cos(angle))
                let outerLimit = fragment.radius(toward: fragment.center + heading) - 4.5
                let distance = random.float(in: innerLimit...max(innerLimit + 1, outerLimit))
                let candidate = fragment.center + heading * distance

                // `workRadius` clearance, so a citizen can stand anywhere in the
                // gathering ring without standing in a river.
                guard map.isStandable(candidate, in: region, margin: Deposit.workRadius) else {
                    continue
                }
                position = candidate
                if placed.allSatisfy({ simd_distance($0, candidate) > 5.0 }) { break }
            }
            placed.append(position)

            let id = result.allocator.allocate()
            result.deposits[id] = Deposit(
                id: id,
                kind: kind,
                position: position,
                region: region,
                remaining: startingYield(for: kind)
            )
        }
    }
}
