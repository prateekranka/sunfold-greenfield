import XCTest
import simd
@testable import SunfoldCore

/// FI-05: placement must stop before a complete building footprint reaches a Core.
@MainActor
final class FullFootprintPlacementTests: XCTestCase {

    func testEveryPlaceableFootprintHasLegalAndBlockedCoreEdgesForBothFactions() {
        for faction in Faction.allCases {
            let simulation = SkirmishSimulation(
                seed: 20_260_801,
                playerFaction: faction,
                adversaryEnabled: false
            )
            guard let core = simulation.buildings.values.first(where: {
                $0.faction == faction && $0.kind == .civilizationCore
            }) else {
                return XCTFail("Missing " + faction.displayName + " Core.")
            }

            for kind in ConstructionPlacement.placeableKinds {
                let candidateExtent = ConstructionPlacement.halfExtents(for: kind)?.x
                    ?? kind.footprintRadius
                let boundary = core.kind.footprintRadius
                    + candidateExtent
                    + ConstructionPlacement.placementClearance

                guard let direction = edgeDirection(
                    for: kind,
                    core: core,
                    at: boundary,
                    in: simulation
                ) else {
                    return XCTFail(
                        "No clear home-land edge for "
                            + faction.displayName + " " + kind.displayName + "."
                    )
                }

                let legal = core.position + direction * (boundary + 0.02)
                let blocked = core.position + direction * (boundary - 0.02)

                XCTAssertTrue(
                    ConstructionPlacement.isLegal(kind: kind, at: legal, in: simulation),
                    faction.displayName + " " + kind.displayName
                        + " should be legal just outside the Core boundary."
                )
                XCTAssertFalse(
                    ConstructionPlacement.isLegal(kind: kind, at: blocked, in: simulation),
                    faction.displayName + " " + kind.displayName
                        + " should be blocked just inside the Core boundary."
                )
            }
        }
    }

    private func edgeDirection(
        for kind: BuildingKind,
        core: Building,
        at boundary: Float,
        in simulation: SkirmishSimulation
    ) -> WorldPoint? {
        for index in 0..<72 {
            let angle = Float(index) / 72 * 2 * .pi
            let direction = WorldPoint(cos(angle), sin(angle))
            let legal = core.position + direction * (boundary + 0.02)
            guard simulation.map.region(at: legal) == simulation.playerFaction.homeRegion,
                  simulation.map.landField(at: legal) > 0.2,
                  ConstructionPlacement.isLegal(kind: kind, at: legal, in: simulation)
            else { continue }
            return direction
        }
        return nil
    }
}
