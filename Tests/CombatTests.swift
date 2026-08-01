import XCTest
import simd
@testable import SunfoldCore

/// CP-C2 combat: damage formula, death, determinism, and production refunds.
@MainActor
final class CombatTests: XCTestCase {

    private let map = WorldMap.map(.riverlands, seed: 20_260_726)
    private let home = WorldMap.map(.riverlands, seed: 20_260_726).fragment(.sunwovenHome).center

    // MARK: - Damage formula

    func testDamageFormulaStandardMatchup() {
        let vanguard = UnitKind.vanguard.attackProfile!
        let damage = CombatSystem.damage(
            profile: vanguard,
            against: EntityID(raw: 1),
            units: [
                EntityID(raw: 1): SunfoldCore.Unit(
                    id: EntityID(raw: 1),
                    faction: .gravemark,
                    kind: .quarrel,
                    position: .zero,
                    region: .gravemarkHome
                ),
            ],
            buildings: [:]
        )
        XCTAssertEqual(damage, 7)
    }

    func testDamageFormulaBonusDamagePair() {
        let quarrel = UnitKind.quarrel.attackProfile!
        let damage = CombatSystem.damage(
            profile: quarrel,
            against: EntityID(raw: 1),
            units: [
                EntityID(raw: 1): SunfoldCore.Unit(
                    id: EntityID(raw: 1),
                    faction: .gravemark,
                    kind: .vanguard,
                    position: .zero,
                    region: .gravemarkHome
                ),
            ],
            buildings: [:]
        )
        XCTAssertEqual(damage, 10)
    }

    func testDamageFormulaMinimumFloor() {
        let quarrel = UnitKind.quarrel.attackProfile!
        let damage = CombatSystem.damage(
            profile: quarrel,
            against: EntityID(raw: 1),
            units: [:],
            buildings: [
                EntityID(raw: 1): Building(
                    id: EntityID(raw: 1),
                    faction: .gravemark,
                    kind: .civilizationCore,
                    position: .zero,
                    region: .gravemarkHome
                ),
            ]
        )
        XCTAssertEqual(damage, 1)
    }

    func testCombatDamageHelperMatchesSpec() {
        let profile = AttackProfile(
            damageType: .melee,
            base: 7,
            bonuses: [.mounted: 10],
            range: 0.9,
            cooldownTicks: 24
        )
        let effective = CombatDamage.effective(
            attacker: profile,
            targetMeleeArmor: 2,
            targetRangedArmor: 2,
            targetArmorClass: .mounted
        )
        XCTAssertEqual(effective, 15)
    }

    // MARK: - Death and population

    func testUnitDeathFreesPopulation() {
        let targetID = EntityID(raw: 2)
        let attackerID = EntityID(raw: 1)
        var units: [EntityID: SunfoldCore.Unit] = [
            attackerID: SunfoldCore.Unit(
                id: attackerID,
                faction: .sunwoven,
                kind: .vanguard,
                position: home,
                region: .sunwovenHome
            ),
            targetID: SunfoldCore.Unit(
                id: targetID,
                faction: .gravemark,
                kind: .vanguard,
                position: home + WorldPoint(0.5, 0),
                region: .sunwovenHome
            ),
        ]
        units[attackerID]?.attackOrderTarget = targetID
        units[attackerID]?.attackTarget = targetID
        units[attackerID]?.attackCooldownRemaining = 0
        units[targetID]?.life = 1

        var buildings: [EntityID: Building] = [:]
        let popBefore = ProductionSystem.populationCommitment(
            faction: .gravemark,
            units: units,
            queues: [:],
            buildings: buildings,
            tuning: .baseline
        ).used

        let result = CombatSystem.step(units: &units, buildings: &buildings, map: map)
        XCTAssertTrue(result.deadUnits.contains(targetID))
        units[targetID] = nil

        let popAfter = ProductionSystem.populationCommitment(
            faction: .gravemark,
            units: units,
            queues: [:],
            buildings: buildings,
            tuning: .baseline
        ).used
        XCTAssertEqual(popAfter, popBefore - 1)
    }

    // MARK: - Determinism

    func testCombatDeterminismWithIdenticalOrders() {
        let ticks = 120

        func run() -> (lifeTotal: Double, survivors: Set<UInt32>) {
            var units = makeSkirmishPair()
            var buildings: [EntityID: Building] = [:]
            CombatSystem.orderAttack(
                [EntityID(raw: 1)],
                target: EntityID(raw: 2),
                units: &units
            )
            CombatSystem.orderAttack(
                [EntityID(raw: 2)],
                target: EntityID(raw: 1),
                units: &units
            )

            for _ in 0..<ticks {
                _ = CombatSystem.step(units: &units, buildings: &buildings, map: map)
                units = units.filter { !$0.value.isDead }
            }

            let life = units.values.reduce(0.0) { $0 + $1.life }
            return (life, Set(units.keys.map(\.raw)))
        }

        let first = run()
        let second = run()
        XCTAssertEqual(first.lifeTotal, second.lifeTotal, accuracy: 1e-9)
        XCTAssertEqual(first.survivors, second.survivors)
    }

    func testCombatFrameRateIndependence() {
        let totalTicks = 200

        func run(frameDelta: Double) -> (lifeTotal: Double, survivors: Set<UInt32>) {
            let simulation = SkirmishSimulation(seed: 99_001)
            let attackers = simulation.units.values
                .filter { $0.faction == .sunwoven && $0.kind == .citizen }
                .prefix(1)
                .map(\.id)
            guard let target = simulation.units.values
                .first(where: { $0.faction == .gravemark && $0.kind == .citizen })?.id
            else {
                XCTFail("Need opposing citizens.")
                return (0, [])
            }

            simulation.orderAttack(Array(attackers), target: target)

            var stepped = 0
            while stepped < totalTicks {
                simulation.update(deltaTime: frameDelta)
                stepped = Int(simulation.tick)
            }

            let life = simulation.units.values.reduce(0.0) { $0 + $1.life }
            return (life, Set(simulation.units.keys.map(\.raw)))
        }

        let steady = run(frameDelta: 1.0 / 60.0)
        let erratic = run(frameDelta: 0.033)
        XCTAssertEqual(steady.lifeTotal, erratic.lifeTotal, accuracy: 1e-9)
        XCTAssertEqual(steady.survivors, erratic.survivors)
    }

    // MARK: - Building destruction refund

    func testDestroyedProductionBuildingRefundsQueue() {
        let tuning = SkirmishTuning.baseline
        let buildingID = EntityID(raw: 5)
        let building = Building(
            id: buildingID,
            faction: .sunwoven,
            kind: .civilizationCore,
            position: .zero,
            region: .sunwovenHome
        )
        let buildings = [buildingID: building]
        var queues = [buildingID: ProductionQueue(items: [
            ProductionItem(kind: .citizen, progressTicks: 1, hasStarted: true),
        ])]
        var stock: [Faction: ResourcePool] = [.sunwoven: ResourcePool(provisions: 100)]

        ProductionSystem.onBuildingDestroyed(
            buildingID,
            queues: &queues,
            buildings: buildings,
            stock: &stock,
            tuning: tuning
        )

        XCTAssertNil(queues[buildingID])
        let expected = 100 + tuning.citizenCost.provisions * tuning.cancelRefundFraction
        XCTAssertEqual(stock[.sunwoven]?.provisions ?? 0, expected, accuracy: 1e-6)
    }

    // MARK: - Fixtures

    private func makeSkirmishPair() -> [EntityID: SunfoldCore.Unit] {
        [
            EntityID(raw: 1): SunfoldCore.Unit(
                id: EntityID(raw: 1),
                faction: .sunwoven,
                kind: .vanguard,
                position: home,
                region: .sunwovenHome
            ),
            EntityID(raw: 2): SunfoldCore.Unit(
                id: EntityID(raw: 2),
                faction: .gravemark,
                kind: .vanguard,
                position: home + WorldPoint(0.8, 0),
                region: .sunwovenHome
            ),
        ]
    }
}
