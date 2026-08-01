import XCTest
import simd
@testable import SunfoldCore

/// Focused proof for FI-02. It covers one legal route and one rejected target
/// for each playable civilization without involving the renderer or simulator.
final class LightTransportVoyageTests: XCTestCase {

    func testOpeningTransportsAreVoidLegalAcrossSeeds() {
        let seeds: [UInt64] = [
            20_260_726, 20_260_727, 20_260_728, 20_260_729,
            20_260_730, 20_260_731, 20_260_732, 20_260_733
        ]
        let tuning = SkirmishTuning.baseline

        for seed in seeds {
            let map = WorldMap.proofMap(seed: seed)
            let populated = WorldPopulator.populate(map: map, tuning: tuning)

            for faction in Faction.allCases {
                guard let transport = openingTransport(
                    for: faction,
                    in: populated.units
                ) else {
                    return XCTFail("Missing opening Transport for \(faction) at seed \(seed).")
                }

                guard ObstacleNavigation.isVoidLegal(
                    transport.position,
                    for: transport,
                    map: map,
                    buildings: populated.buildings,
                    deposits: populated.deposits
                ) else {
                    return XCTFail(
                        "Opening \(faction) Transport is illegal at seed \(seed): \(transport.position)."
                    )
                }
            }
        }
    }

    func testLandOrderNeverProducesLandRouteOrFinalPosition() {
        let seed: UInt64 = 20_260_726
        let map = WorldMap.proofMap(seed: seed)
        let populated = WorldPopulator.populate(map: map, tuning: .baseline)

        for faction in Faction.allCases {
            guard let transport = openingTransport(for: faction, in: populated.units),
                  let core = populated.buildings.values.first(where: {
                      $0.kind == .civilizationCore && $0.faction == faction
                  })
            else {
                return XCTFail("Missing opening Transport or Core for \(faction).")
            }

            let route = MovementSystem.resolveOrder(
                core.position,
                for: transport,
                map: map,
                buildings: populated.buildings,
                deposits: populated.deposits
            )

            guard let route else {
                XCTAssertTrue(
                    ObstacleNavigation.isVoidLegal(
                        transport.position,
                        for: transport,
                        map: map,
                        buildings: populated.buildings,
                        deposits: populated.deposits
                    ),
                    "Rejected order must leave \(faction) Transport in legal water."
                )
                continue
            }

            XCTAssertTrue(
                route.waypoints.allSatisfy {
                    ObstacleNavigation.isVoidLegal(
                        $0,
                        for: transport,
                        map: map,
                        buildings: populated.buildings,
                        deposits: populated.deposits
                    )
                },
                "Land order produced an illegal waypoint for \(faction)."
            )
            let result = simulate(
                transport,
                route: route,
                map: map,
                buildings: populated.buildings,
                deposits: populated.deposits
            )
            XCTAssertTrue(
                result.samples.allSatisfy {
                    ObstacleNavigation.isVoidLegal(
                        $0,
                        for: transport,
                        map: map,
                        buildings: populated.buildings,
                        deposits: populated.deposits
                    )
                },
                "Land order crossed an illegal point for \(faction)."
            )
            XCTAssertTrue(
                ObstacleNavigation.isVoidLegal(
                    result.unit.position,
                    for: transport,
                    map: map,
                    buildings: populated.buildings,
                    deposits: populated.deposits
                ),
                "Land order ended illegally for \(faction)."
            )
        }
    }

    func testIllegalStartRejectsVoidOrderWithoutLandRecovery() {
        let seed: UInt64 = 20_260_726
        let map = WorldMap.proofMap(seed: seed)
        let populated = WorldPopulator.populate(map: map, tuning: .baseline)

        for faction in Faction.allCases {
            guard var transport = openingTransport(for: faction, in: populated.units),
                  let core = populated.buildings.values.first(where: {
                      $0.kind == .civilizationCore && $0.faction == faction
                  }),
                  let legalTransport = openingTransport(
                      for: faction,
                      in: populated.units
                  )
            else {
                return XCTFail("Missing opening Transport or Core for \(faction).")
            }

            transport.position = core.position
            transport.destination = nil
            transport.movementPath = []
            transport.movementPathTarget = nil
            transport.activity = .idle

            XCTAssertFalse(
                ObstacleNavigation.isVoidLegal(
                    transport.position,
                    for: transport,
                    map: map,
                    buildings: populated.buildings,
                    deposits: populated.deposits
                ),
                "Fixture must start illegally on land for \(faction)."
            )

            XCTAssertNil(
                MovementSystem.resolveOrder(
                    legalTransport.position,
                    for: transport,
                    map: map,
                    buildings: populated.buildings,
                    deposits: populated.deposits
                ),
                "An illegal-start \(faction) Transport must reject the order."
            )
        }
    }

    @MainActor
    func testRejectedTransportOrderLeavesVisibleDenialMarker() {
        let simulation = SkirmishSimulation(
            seed: 20_260_726,
            playerFaction: .sunwoven,
            adversaryEnabled: false
        )
        guard let transport = openingTransport(
            for: .sunwoven,
            in: simulation.units
        ),
        let core = simulation.buildings.values.first(where: {
            $0.kind == .civilizationCore && $0.faction == .sunwoven
        })
        else {
            return XCTFail("Missing Sunwoven opening Transport or Core.")
        }

        let selection = SelectionModel()
        selection.selectUnit(transport.id)
        selection.orderMove(to: core.position, in: simulation)

        XCTAssertEqual(
            selection.lastOrderMarker?.position,
            core.position,
            "Rejected orders must leave a marker at the tapped point."
        )
        XCTAssertNil(
            simulation.unit(transport.id)?.destination,
            "A rejected Transport order must not create movement state."
        )
    }

    func testOpeningTransportsFollowDeterministicVoidRouteAndRejectLandTarget() {
        let seed: UInt64 = 20_260_726
        let map = WorldMap.proofMap(seed: seed)
        let tuning = SkirmishTuning.baseline
        let populated = WorldPopulator.populate(map: map, tuning: tuning)
        let buildings = populated.buildings
        let deposits = populated.deposits

        for faction in Faction.allCases {
            guard let transport = populated.units.values
                .filter({ $0.faction == faction && $0.kind == .lightTransport })
                .sorted(by: { $0.id.raw < $1.id.raw })
                .first
            else {
                return XCTFail("The populated world must contain both opening Light Transports.")
            }

            XCTAssertTrue(
                map.isNavigableVoid(transport.position),
                "Each opening Transport must begin in legal void water; field=\(map.landField(at: transport.position))."
            )

            guard let fixture = firstReachableTarget(
                from: transport,
                map: map,
                buildings: buildings,
                deposits: deposits
            ) else {
                return XCTFail("Could not find a deterministic legal void target.")
            }

            let first = simulate(
                transport,
                route: fixture.route,
                map: map,
                buildings: buildings,
                deposits: deposits
            )
            let second = simulate(
                transport,
                route: fixture.route,
                map: map,
                buildings: buildings,
                deposits: deposits
            )

            let replayedRoute = MovementSystem.resolveOrder(
                fixture.target,
                for: transport,
                map: map,
                buildings: buildings,
                deposits: deposits
            )
            XCTAssertEqual(replayedRoute, fixture.route, "The legal route must be stable.")
            XCTAssertEqual(first.samples, second.samples, "The voyage must replay exactly.")
            XCTAssertNil(first.unit.destination, "The Transport must arrive cleanly.")
            XCTAssertEqual(first.unit.position, fixture.target)
            XCTAssertTrue(
                map.isNavigableVoid(first.unit.position),
                "The Transport must remain in legal void at arrival."
            )

            for sample in first.samples {
                XCTAssertTrue(
                    ObstacleNavigation.isVoidLegal(
                        sample,
                        for: transport,
                        map: map,
                        buildings: buildings,
                        deposits: deposits
                    ),
                    "The Transport must never cross land or an occupied structure."
                )
            }

            let core = buildings.values.first {
                $0.kind == .civilizationCore && $0.faction == faction
            }!
            XCTAssertNil(
                MovementSystem.resolveOrder(
                    core.position,
                    for: transport,
                    map: map,
                    buildings: buildings,
                    deposits: deposits
                ),
                "A Transport order onto its Core must be rejected."
            )
        }
    }

    private func firstReachableTarget(
        from transport: SunfoldCore.Unit,
        map: WorldMap,
        buildings: [EntityID: Building],
        deposits: [EntityID: Deposit]
    ) -> (target: WorldPoint, route: ObstacleNavigation.Route)? {
        for radius in stride(from: Float(14), through: 50, by: 6) {
            for sample in 0..<32 {
                let angle = Float(sample) / 32 * 2 * .pi
                let target = transport.position + WorldPoint(cos(angle), sin(angle)) * radius
                guard map.isNavigableVoid(target),
                      lineIsNavigable(
                          from: transport.position,
                          to: target,
                          map: map
                      ),
                      let route = MovementSystem.resolveOrder(
                          target,
                          for: transport,
                          map: map,
                          buildings: buildings,
                          deposits: deposits
                      ),
                      route.reachedRequestedDestination,
                      simd_distance(target, transport.position) > 10
                else { continue }
                return (target, route)
            }
        }
        return nil
    }

    private func openingTransport(
        for faction: Faction,
        in units: [EntityID: SunfoldCore.Unit]
    ) -> SunfoldCore.Unit? {
        units.values
            .filter { $0.faction == faction && $0.kind == .lightTransport }
            .sorted { $0.id.raw < $1.id.raw }
            .first
    }

    private func lineIsNavigable(
        from start: WorldPoint,
        to target: WorldPoint,
        map: WorldMap
    ) -> Bool {
        let distance = simd_distance(start, target)
        let samples = max(Int(ceil(distance / 0.3)), 1)
        for sample in 1...samples {
            let fraction = Float(sample) / Float(samples)
            guard map.isNavigableVoid(start + (target - start) * fraction) else {
                return false
            }
        }
        return true
    }

    private func simulate(
        _ original: SunfoldCore.Unit,
        route: ObstacleNavigation.Route,
        map: WorldMap,
        buildings: [EntityID: Building],
        deposits: [EntityID: Deposit]
    ) -> (samples: [WorldPoint], unit: SunfoldCore.Unit) {
        var transport = original
        transport.destination = route.destination
        transport.movementPath = route.waypoints
        transport.movementPathTarget = route.destination
        transport.activity = SunfoldCore.UnitActivity.moving

        var units = [transport.id: transport]
        var samples: [WorldPoint] = [transport.position]
        for _ in 0..<4_000 {
            MovementSystem.step(
                units: &units,
                map: map,
                buildings: buildings,
                deposits: deposits,
                deltaTime: 1.0 / 20.0
            )
            guard let current = units[transport.id] else { break }
            samples.append(current.position)
            if current.destination == nil { break }
        }
        return (samples, units[transport.id] ?? transport)
    }
}
