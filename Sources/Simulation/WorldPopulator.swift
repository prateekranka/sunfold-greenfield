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

    static func populate(map: WorldMap, tuning: SkirmishTuning, perfDensity: Int? = nil) -> Result {
        var result = Result(allocator: EntityIDAllocator())

        for faction in Faction.allCases {
            let home: RegionID = faction == .sunwoven ? .sunwovenHome : .gravemarkHome
            placeHome(faction: faction, region: home, map: map, tuning: tuning, into: &result)
        }

        placeDominionSpire(map: map, into: &result)

        for region in RegionID.allCases {
            placeDeposits(region: region, map: map, tuning: tuning, into: &result)
        }

        if let target = perfDensity, result.units.count < target {
            inflateToDensity(target, map: map, into: &result)
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

        // The transport waits in the coastal channel facing the expansion —
        // bow aligned with locomotion's heading convention (not atan2(x,y)).
        let transportID = result.allocator.allocate()
        result.units[transportID] = Unit(
            id: transportID,
            faction: faction,
            kind: .lightTransport,
            position: map.dockPoint(on: region, facing: expansion),
            facing: LocomotionMath.heading(of: outward),
            region: nil  // A hull sits in the void, not on land.
        )
    }

    // MARK: - The objective

    /// The Dominion Spire stands at the exact centre of the contested fragment,
    /// which is the one point both Cores are equidistant from — the map's only
    /// fairness contract. Placed before deposits so nothing spawns under it.
    ///
    /// It belongs to nobody (`faction: nil`), so it is never trained from, never
    /// targeted, never counted as anyone's building, and cannot be destroyed.
    private static func placeDominionSpire(map: WorldMap, into result: inout Result) {
        let id = result.allocator.allocate()
        result.buildings[id] = Building(
            id: id,
            faction: nil,
            kind: .dominionSpire,
            position: map.fragment(.dominion).center,
            region: .dominion
        )
    }

    // MARK: - Deposits

    private static func placeDeposits(
        region: RegionID,
        map: WorldMap,
        tuning: SkirmishTuning,
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
        // The Dominion's centre is no longer empty ground: the Spire stands on it,
        // so deposits there start outside its footprint plus a citizen's working
        // ring. Without this a Matter node can sit *inside* the objective, and the
        // one piece of ground the whole match is fought over becomes a mine.
        let innerLimit: Float
        switch region {
        case _ where region.isHome:
            innerLimit = BuildingKind.civilizationCore.footprintRadius + 6
        case .dominion:
            innerLimit = BuildingKind.dominionSpire.footprintRadius + Deposit.workRadius + 1
        default:
            innerLimit = 3.0
        }
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
                remaining: tuning.depositYield(for: kind, in: region)
            )
        }
    }

    // MARK: - Perf density

    /// Spawns additional citizens until `units.count` reaches `target`. Used only
    /// when `-sunfoldDensity N` is passed at launch; draws from a tagged RNG
    /// stream that does not shift gameplay randomness when the flag is absent.
    private static func inflateToDensity(
        _ target: Int,
        map: WorldMap,
        into result: inout Result
    ) {
        var random = DeterministicRandom.stream(seed: map.seed, tag: "perf.density")
        var factionIndex = 0

        while result.units.count < target {
            let faction = Faction.allCases[factionIndex % Faction.allCases.count]
            factionIndex += 1
            let region: RegionID = faction == .sunwoven ? .sunwovenHome : .gravemarkHome
            let fragment = map.fragment(region)
            let expansion: RegionID = faction == .sunwoven ? .sunwovenExpansion : .gravemarkExpansion
            let outward = simd_normalize(map.fragment(expansion).center - fragment.center)

            var placed = false
            for attempt in 0..<64 {
                let angle = random.float(in: 0...(2 * .pi)) + Float(attempt) * 0.17
                let distance = random.float(in: 6...min(fragment.radius * 0.75, 42))
                let heading = WorldPoint(sin(angle), cos(angle))
                let wanted = fragment.center + heading * distance
                let position = map.clampToLand(
                    wanted,
                    from: fragment.center,
                    in: region,
                    margin: UnitKind.citizen.footprintRadius
                )
                guard map.isStandable(
                    position, in: region, margin: UnitKind.citizen.footprintRadius
                ) else { continue }

                let id = result.allocator.allocate()
                result.units[id] = Unit(
                    id: id,
                    faction: faction,
                    kind: .citizen,
                    position: position,
                    facing: LocomotionMath.heading(of: outward),
                    region: region
                )
                placed = true
                break
            }
            if !placed { break }
        }
    }
}
