import XCTest
@testable import SunfoldCore

/// Focused proof for the new-match lifecycle and the player-faction perspective.
@MainActor
final class LifecycleFactionTests: XCTestCase {
    private let seed: UInt64 = 20_260_726

    func testGravemarkPlayerUsesSunwovenAsTheAdversary() {
        let simulation = SkirmishSimulation(
            seed: seed,
            playerFaction: .gravemark,
            adversaryEnabled: true
        )

        XCTAssertEqual(simulation.playerFaction, .gravemark)
        XCTAssertEqual(simulation.adversary.faction, .sunwoven)
        XCTAssertTrue(
            simulation.buildings.values.contains {
                $0.kind == .civilizationCore
                    && $0.faction == .gravemark
                    && $0.region == .gravemarkHome
            }
        )
        XCTAssertTrue(
            simulation.buildings.values.contains {
                $0.kind == .civilizationCore
                    && $0.faction == .sunwoven
                    && $0.region == .sunwovenHome
            }
        )
    }

    func testGravemarkDefeatRestartPreservesTheChosenPerspective() {
        let simulation = SkirmishSimulation(
            seed: seed,
            playerFaction: .gravemark,
            adversaryEnabled: false
        )
        let openingHash = simulation.worldHash

        simulation.resign()
        XCTAssertEqual(simulation.outcome?.winner, .sunwoven)
        XCTAssertEqual(simulation.outcome?.verdict(for: .gravemark), "DEFEAT")

        simulation.restart()

        XCTAssertNil(simulation.outcome)
        XCTAssertEqual(simulation.playerFaction, .gravemark)
        XCTAssertEqual(simulation.adversary.faction, .sunwoven)
        XCTAssertEqual(simulation.worldHash, openingHash)
    }

    func testGravemarkVictoryRestartAlsoRewindsTheMatch() {
        let simulation = SkirmishSimulation(
            seed: seed,
            playerFaction: .gravemark,
            adversaryEnabled: false
        )

        simulation.resign(as: .sunwoven)
        XCTAssertEqual(simulation.outcome?.winner, .gravemark)
        XCTAssertEqual(simulation.outcome?.verdict(for: .gravemark), "VICTORY")

        simulation.restart()

        XCTAssertNil(simulation.outcome)
        XCTAssertEqual(simulation.tick, 0)
        XCTAssertTrue(
            simulation.buildings.values.contains {
                $0.kind == .civilizationCore
                    && $0.faction == simulation.playerFaction
            }
        )
    }
}
