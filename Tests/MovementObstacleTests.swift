import XCTest
import simd
@testable import SunfoldCore

/// Focused proof for FI-03. This intentionally tests one Citizen at a time;
/// group avoidance and formation state belong to FI-04.
final class MovementObstacleTests: XCTestCase {

    @MainActor
    func testGatheringDoesNotInvokeObstaclePlannerPerTick() {
        let simulation = SkirmishSimulation(
            seed: 20_260_801,
            adversaryEnabled: false
        )
        guard let citizen = simulation.units.values
            .filter({ $0.faction == .sunwoven && $0.kind == .citizen })
            .sorted(by: { $0.id.raw < $1.id.raw })
            .first,
              let deposit = simulation.deposits.values
                  .sorted(by: { $0.id.raw < $1.id.raw })
                  .first
        else {
            return XCTFail("The populated test world must contain a Citizen and deposit.")
        }

        simulation.orderGather([citizen.id], from: deposit.id)
        ObstacleNavigation.resetPlanInvocationCount()

        let tickCount = 120
        for _ in 0..<tickCount {
            simulation.update(deltaTime: simulation.tuning.stepDuration)
        }

        XCTAssertEqual(simulation.tick, UInt64(tickCount))
        XCTAssertEqual(
            ObstacleNavigation.planInvocationCount,
            0,
            "Gathering must not invoke explicit-order A* on the 20 Hz path."
        )
    }

    func testCitizenRoutesDeterministicallyAroundCoreAndDepositInBothHomes() {
        let seed: UInt64 = 20_260_801

        for (region, faction) in [
            (RegionID.sunwovenHome, Faction.sunwoven),
            (.gravemarkHome, .gravemark),
        ] {
            let map = WorldMap.map(.riverlands, seed: seed)
            let corePosition = map.fragment(region).center
            let candidates: [(WorldPoint, WorldPoint, WorldPoint)] = [
                (corePosition + [-16, 0], corePosition + [16, 0], corePosition + [8, 0]),
                (corePosition + [0, -16], corePosition + [0, 16], corePosition + [0, 8]),
                (corePosition + [-12, -10], corePosition + [12, 10], corePosition + [6, 5]),
            ]
            guard let fixture = candidates.first(where: { start, goal, deposit in
                map.isTraversable(start, margin: UnitKind.citizen.footprintRadius)
                    && map.isTraversable(goal, margin: UnitKind.citizen.footprintRadius)
                    && map.isStandable(deposit, margin: 0.2)
            }) else {
                return XCTFail("Could not find a grounded FI-03 fixture in \(region.rawValue).")
            }

            let core = Building(
                id: EntityID(raw: region == .sunwovenHome ? 100 : 200),
                faction: faction,
                kind: .civilizationCore,
                position: corePosition,
                region: region
            )
            let deposit = Deposit(
                id: EntityID(raw: region == .sunwovenHome ? 101 : 201),
                kind: .matter,
                position: fixture.2,
                region: region,
                remaining: 100
            )
            let obstacles = [core.id: core]
            let deposits = [deposit.id: deposit]

            func makeUnit() -> SunfoldCore.Unit {
                SunfoldCore.Unit(
                    id: EntityID(raw: region == .sunwovenHome ? 1 : 2),
                    faction: faction,
                    kind: .citizen,
                    position: fixture.0,
                    region: region
                )
            }

            func run() -> (route: [WorldPoint], samples: [WorldPoint], unit: SunfoldCore.Unit) {
                var unit = makeUnit()
                guard let order = MovementSystem.resolveOrder(
                    fixture.1,
                    for: unit,
                    map: map,
                    buildings: obstacles,
                    deposits: deposits
                ) else {
                    return ([], [], unit)
                }
                XCTAssertTrue(
                    order.reachedRequestedDestination,
                    "The \(region.rawValue) route should reach its legal requested point."
                )
                unit.destination = order.destination
                unit.movementPath = order.waypoints
                unit.movementPathTarget = order.destination
                unit.activity = .moving

                var units = [unit.id: unit]
                var samples: [WorldPoint] = [unit.position]
                let stepDuration = 1.0 / 20.0
                for _ in 0..<4_000 {
                    MovementSystem.step(
                        units: &units,
                        map: map,
                        buildings: obstacles,
                        deposits: deposits,
                        deltaTime: stepDuration
                    )
                    guard let current = units[unit.id] else { break }
                    samples.append(current.position)
                    if current.destination == nil { break }
                }
                return (order.waypoints, samples, units[unit.id] ?? unit)
            }

            let first = run()
            let second = run()
            XCTAssertEqual(first.route, second.route, "The route must replay exactly.")
            XCTAssertEqual(first.samples, second.samples, "The movement trace must replay exactly.")
            XCTAssertNil(first.unit.destination, "The Citizen must arrive or stop at a legal endpoint.")
            XCTAssertTrue(
                map.isTraversable(first.unit.position, margin: UnitKind.citizen.footprintRadius),
                "The final point must remain grounded in \(region.rawValue)."
            )
            XCTAssertLessThan(
                simd_distance(first.unit.position, fixture.1),
                MovementSystem.arrivalRadius + 0.05,
                "The route must reach the requested legal destination."
            )

            let maximumStep = UnitKind.citizen.speed * Float(1.0 / 20.0) + 0.001
            for pair in zip(first.samples, first.samples.dropFirst()) {
                XCTAssertLessThanOrEqual(
                    simd_distance(pair.0, pair.1),
                    maximumStep,
                    "Movement must not teleport."
                )
                XCTAssertGreaterThanOrEqual(
                    simd_distance(pair.1, core.position),
                    core.kind.footprintRadius + UnitKind.citizen.footprintRadius + 0.24,
                    "The Citizen must keep clear of the Core."
                )
                XCTAssertGreaterThanOrEqual(
                    simd_distance(pair.1, deposit.position),
                    Deposit.workRadius - 0.16,
                    "The Citizen must keep clear of the deposit cluster."
                )
            }
        }
    }
}
