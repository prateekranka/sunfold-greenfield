import Foundation
import XCTest
import simd
@testable import SunfoldCore

/// CP-C5 military roster breadth, prerequisite truth, ledger correctness, and
/// production completion safety.
@MainActor
final class RosterTests: XCTestCase {

    private let seed: UInt64 = 20_260_726

    // MARK: - Roster values

    func testLumenSpireCostAndBuildTime() {
        let tuning = SkirmishTuning.baseline

        XCTAssertEqual(
            tuning.cost(for: .lumenSpire),
            ResourcePool(matter: 90, lumen: 45)
        )
        XCTAssertEqual(tuning.buildTime(for: .lumenSpire), 18)
        XCTAssertEqual(BuildingKind.lumenSpire.displayName, "Lumen Spire")
        XCTAssertEqual(BuildingKind.lumenSpire.purpose, "Trains Quarrels")
        XCTAssertEqual(BuildingKind.lumenSpire.maxLife, 210)
        XCTAssertEqual(BuildingKind.lumenSpire.footprintRadius, 3.0)
        XCTAssertFalse(BuildingKind.lumenSpire.acceptsDropOff)
        XCTAssertEqual(BuildingKind.lumenSpire.populationGrant, 0)
        XCTAssertFalse(BuildingKind.lumenSpire.isNeutralObjective)
    }

    func testFormationYardCostUsesTwentyLumen() {
        XCTAssertEqual(
            SkirmishTuning.baseline.cost(for: .formationYard),
            ResourcePool(matter: 110, lumen: 20)
        )
    }

    func testFormationYardAndLumenSpireTrainingRosters() {
        XCTAssertEqual(BuildingKind.formationYard.trains, [.pathfinder, .vanguard])
        XCTAssertFalse(BuildingKind.formationYard.trains.contains(.quarrel))
        XCTAssertEqual(BuildingKind.lumenSpire.trains, [.quarrel])
    }

    func testQuarrelProfileMatchesRoster() {
        let profile = UnitKind.quarrel.attackProfile

        XCTAssertEqual(UnitKind.quarrel.maxLife, 50)
        XCTAssertEqual(profile?.damageType, .ranged)
        XCTAssertEqual(profile?.base, 6)
        XCTAssertEqual(profile?.bonuses[.infantry] ?? 0, 4)
        XCTAssertEqual(profile?.range, 9.0)
        XCTAssertEqual(profile?.cooldownTicks, 28)
        XCTAssertEqual(UnitKind.quarrel.speed, 3.2)
        XCTAssertEqual(UnitKind.quarrel.sightRange, 13)
        XCTAssertEqual(UnitKind.quarrel.populationCost, 1)
        XCTAssertEqual(UnitKind.quarrel.armorClass, .infantry)
    }

    func testVanguardProfileIncludesOnlyRequiredBonuses() {
        let profile = UnitKind.vanguard.attackProfile

        XCTAssertEqual(profile?.base, 7)
        XCTAssertEqual(profile?.bonuses[.mounted] ?? 0, 10)
        XCTAssertEqual(profile?.bonuses[.siege] ?? 0, 8)
        XCTAssertNil(profile?.bonuses[.building])
    }

    func testQuarrelAndVanguardCounterDamageUsesCombatSystem() {
        XCTAssertEqual(combatDamage(attacker: .quarrel, target: .vanguard), 10)
        XCTAssertEqual(combatDamage(attacker: .vanguard, target: .quarrel), 7)
    }

    func testDominionCaptureUsesExplicitUnitList() {
        XCTAssertTrue(UnitKind.quarrel.canCaptureDominion)
        XCTAssertFalse(UnitKind.pathfinder.canCaptureDominion)

        let explicitCapturers = UnitKind.allCases.filter { $0.canCaptureDominion }
        XCTAssertEqual(explicitCapturers, [.vanguard, .quarrel, .bastionWalker])
    }

    // MARK: - Prerequisite gating

    func testLumenSpireRequiresCompletedSameFactionFormationYard() {
        let noYard = makeResourceRichSimulation()
        XCTAssertEqual(
            noYard.buildBlocker(for: .lumenSpire, faction: .sunwoven),
            .missingPrerequisite(.formationYard)
        )

        let foundation = makeResourceRichSimulation()
        guard let foundationID = placeFormationYard(for: .sunwoven, in: foundation) else {
            return XCTFail("Formation Yard foundation placement failed.")
        }
        XCTAssertFalse(foundation.building(foundationID)?.isComplete ?? true)
        XCTAssertEqual(
            foundation.buildBlocker(for: .lumenSpire, faction: .sunwoven),
            .missingPrerequisite(.formationYard)
        )

        let enemyYard = makeResourceRichSimulation()
        guard let enemyYardID = placeFormationYard(for: .gravemark, in: enemyYard) else {
            return XCTFail("Enemy Formation Yard placement failed.")
        }
        guard complete(enemyYardID, in: enemyYard) else {
            return XCTFail("Enemy Formation Yard did not complete.")
        }
        XCTAssertEqual(
            enemyYard.buildBlocker(for: .lumenSpire, faction: .sunwoven),
            .missingPrerequisite(.formationYard)
        )

        let sameFaction = makeResourceRichSimulation()
        guard let sameFactionYardID = placeFormationYard(for: .sunwoven, in: sameFaction) else {
            return XCTFail("Formation Yard placement failed.")
        }
        guard complete(sameFactionYardID, in: sameFaction) else {
            return XCTFail("Formation Yard did not complete.")
        }
        XCTAssertNil(sameFaction.buildBlocker(for: .lumenSpire, faction: .sunwoven))
    }

    func testPlaceBuildingRefusesLumenSpireWithoutPrerequisite() {
        let simulation = makeResourceRichSimulation()
        let point = legalPoint(for: .lumenSpire, in: simulation)
        let before = simulation.stock(for: .sunwoven)

        XCTAssertNil(simulation.placeBuilding(.lumenSpire, at: point, for: .sunwoven))
        XCTAssertEqual(simulation.stock(for: .sunwoven), before)
        XCTAssertFalse(simulation.buildings.contains { $0.value.kind == .lumenSpire })
    }

    func testPlacingLumenSpireDeductsExactLedger() {
        let simulation = makeResourceRichSimulation()
        guard let yardID = placeFormationYard(for: .sunwoven, in: simulation) else {
            return XCTFail("Formation Yard placement failed.")
        }
        guard complete(yardID, in: simulation) else {
            return XCTFail("Formation Yard did not complete.")
        }

        let point = legalPoint(for: .lumenSpire, in: simulation)
        let before = simulation.stock(for: .sunwoven)
        guard simulation.placeBuilding(.lumenSpire, at: point, for: .sunwoven) != nil else {
            return XCTFail("Completed same-faction Formation Yard should unlock Lumen Spire.")
        }

        let deducted = before - simulation.stock(for: .sunwoven)
        XCTAssertEqual(deducted.matter, 90, accuracy: 1e-9)
        XCTAssertEqual(deducted.lumen, 45, accuracy: 1e-9)
        XCTAssertEqual(deducted.provisions, 0, accuracy: 1e-9)
        XCTAssertEqual(deducted.aether, 0, accuracy: 1e-9)
    }

    // MARK: - Production completion safety

    func testCompletedProductionItemHoldsAtPopulationCapThenSpawnsWhenCapRises() {
        let tuning = SkirmishTuning.baseline
        let map = WorldMap.map(.riverlands, seed: seed)
        let home = map.fragment(.sunwovenHome).center
        let yardID = EntityID(raw: 200)
        let dwellingID = EntityID(raw: 201)
        let yard = Building(
            id: yardID,
            faction: .sunwoven,
            kind: .formationYard,
            position: home,
            region: .sunwovenHome
        )
        var buildings: [EntityID: Building] = [yardID: yard]

        var units: [EntityID: SunfoldCore.Unit] = [:]
        for index in 0..<tuning.startingPopulationCap {
            let id = EntityID(raw: UInt32(100 + index))
            units[id] = SunfoldCore.Unit(
                id: id,
                faction: .sunwoven,
                kind: .citizen,
                position: home,
                region: .sunwovenHome
            )
        }

        let totalTicks = tuning.buildTimeTicks(for: .vanguard)
        var queues: [EntityID: ProductionQueue] = [
            yardID: ProductionQueue(items: [
                ProductionItem(
                    kind: .vanguard,
                    progressTicks: totalTicks,
                    hasStarted: true
                ),
            ]),
        ]
        var stock: [Faction: ResourcePool] = [
            .sunwoven: tuning.startingResources - tuning.vanguardCost,
        ]
        let chargedStock = stock[.sunwoven]
        var allocator = EntityIDAllocator()

        ProductionSystem.step(
            queues: &queues,
            units: &units,
            buildings: buildings,
            stock: &stock,
            map: map,
            tuning: tuning,
            allocator: &allocator
        )

        guard let held = queues[yardID] else {
            return XCTFail("Completed item must stay in the queue at the cap.")
        }
        XCTAssertEqual(held.front?.progressTicks, totalTicks)
        XCTAssertEqual(held.heldReason, .populationCap)
        XCTAssertEqual(held.count, 1)
        XCTAssertEqual(stock[.sunwoven], chargedStock)
        XCTAssertEqual(units.values.filter { $0.kind == .vanguard }.count, 0)

        buildings[dwellingID] = Building(
            id: dwellingID,
            faction: .sunwoven,
            kind: .dwelling,
            position: home + WorldPoint(20, 0),
            region: .sunwovenHome
        )

        ProductionSystem.step(
            queues: &queues,
            units: &units,
            buildings: buildings,
            stock: &stock,
            map: map,
            tuning: tuning,
            allocator: &allocator
        )

        XCTAssertNil(queues[yardID])
        XCTAssertEqual(units.values.filter { $0.kind == .vanguard }.count, 1)
        XCTAssertEqual(stock[.sunwoven], chargedStock)
    }

    // MARK: - Fixtures

    private func combatDamage(attacker: UnitKind, target: UnitKind) -> Int {
        let targetID = EntityID(raw: 1)
        let targetUnit = SunfoldCore.Unit(
            id: targetID,
            faction: .gravemark,
            kind: target,
            position: .zero,
            region: .gravemarkHome
        )
        return CombatSystem.damage(
            profile: attacker.attackProfile!,
            against: targetID,
            units: [targetID: targetUnit],
            buildings: [:]
        )
    }

    private func makeResourceRichSimulation() -> SkirmishSimulation {
        var tuning = SkirmishTuning.baseline
        tuning.startingResources.matter += tuning.formationYardCost.matter + tuning.lumenSpireCost.matter
        tuning.startingResources.lumen += tuning.formationYardCost.lumen + tuning.lumenSpireCost.lumen
        return SkirmishSimulation(
            seed: seed,
            tuning: tuning,
            adversaryEnabled: false
        )
    }

    private func legalPoint(for kind: BuildingKind, in simulation: SkirmishSimulation) -> WorldPoint {
        let home = simulation.map.fragment(.sunwovenHome).center
        let candidates: [WorldPoint] = [
            home + WorldPoint(14, 0),
            home + WorldPoint(-14, 0),
            home + WorldPoint(0, 14),
            home + WorldPoint(0, -14),
            home + WorldPoint(18, 6),
            home + WorldPoint(-18, 6),
            home + WorldPoint(6, 18),
            home + WorldPoint(-6, 18),
            home + WorldPoint(22, 0),
            home + WorldPoint(-22, 0),
        ]
        if let point = candidates.first(where: {
            ConstructionPlacement.isLegal(kind: kind, at: $0, in: simulation)
        }) {
            return point
        }
        XCTFail("No legal " + kind.displayName + " placement on home land.")
        return home + WorldPoint(14, 0)
    }

    private func placeFormationYard(
        for faction: Faction,
        in simulation: SkirmishSimulation
    ) -> EntityID? {
        let region: RegionID = faction == .sunwoven ? .sunwovenHome : .gravemarkHome
        let home = simulation.map.fragment(region).center
        let point = home + WorldPoint(14, 0)
        let builders = simulation.units.values
            .filter { $0.faction == faction && $0.kind == .citizen }
            .sorted { $0.id.raw < $1.id.raw }
            .prefix(2)
            .map(\.id)
        return simulation.placeBuilding(
            .formationYard,
            at: point,
            for: faction,
            preferredBuilders: Array(builders)
        )
    }

    private func complete(_ buildingID: EntityID, in simulation: SkirmishSimulation) -> Bool {
        let buildTicks = Int(
            ceil(simulation.tuning.buildTime(for: .formationYard) * simulation.tuning.simulationHz)
        )
        for _ in 0..<(buildTicks + 240) {
            if simulation.building(buildingID)?.isComplete == true { return true }
            simulation.update(deltaTime: simulation.tuning.stepDuration)
        }
        return simulation.building(buildingID)?.isComplete == true
    }
}
