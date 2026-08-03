import Foundation
import XCTest
@testable import SunfoldCore

/// CP-C9 Slice B — deposit yields are selected by authored region.
@MainActor
final class EconomyTuningTests: XCTestCase {

    private let seed: UInt64 = 20_260_726

    func testDwellingCostAndBuildTimeMatchApprovedEconomy() {
        let tuning = SkirmishTuning.baseline

        XCTAssertEqual(tuning.cost(for: .dwelling), ResourcePool(matter: 55))
        XCTAssertEqual(tuning.buildTime(for: .dwelling), 14, accuracy: 1e-9)
    }

    func testFourDwellingsReachApprovedPopulationCap() {
        let tuning = SkirmishTuning.baseline

        XCTAssertEqual(BuildingKind.dwelling.populationGrant, 8)
        XCTAssertEqual(tuning.startingPopulationCap, 10)
        XCTAssertEqual(
            tuning.startingPopulationCap + 4 * BuildingKind.dwelling.populationGrant,
            42
        )
    }

    func testBothHomeRegionsUseApprovedMatterAndLumenYields() {
        let populated = populateBaselineWorld()

        for region in [RegionID.sunwovenHome, .gravemarkHome] {
            let deposits = deposits(in: region, from: populated)
            let matter = deposits.filter { $0.kind == .matter }
            let lumen = deposits.filter { $0.kind == .lumen }

            XCTAssertFalse(matter.isEmpty, "Expected Matter deposits in \(region.rawValue).")
            XCTAssertFalse(lumen.isEmpty, "Expected Lumen deposits in \(region.rawValue).")
            XCTAssertTrue(matter.allSatisfy { $0.remaining == 700 })
            XCTAssertTrue(lumen.allSatisfy { $0.remaining == 550 })
            XCTAssertEqual(
                matter.reduce(0) { $0 + $1.remaining },
                700 * Double(matter.count),
                accuracy: 1e-9
            )
            XCTAssertEqual(
                lumen.reduce(0) { $0 + $1.remaining },
                550 * Double(lumen.count),
                accuracy: 1e-9
            )
        }
    }

    func testRepresentativeOffHomeRegionsUseEstablishedYields() {
        let populated = populateBaselineWorld()
        let nonHomeMatter = populated.deposits.values.filter {
            !$0.region.isHome && $0.kind == .matter
        }

        XCTAssertFalse(nonHomeMatter.isEmpty, "Non-home Matter coverage must not be vacuous.")

        let representativeRegions: [RegionID] = [
            .sunwovenExpansion,
            .gravemarkExpansion,
            .neutralOutcropNorth,
            .neutralOutcropSouth,
            .dominion,
        ]
        let expectedYields: [(ResourceKind, Double)] = [
            (.matter, 420),
            (.lumen, 300),
            (.aether, 180),
        ]

        for region in representativeRegions {
            for (kind, expected) in expectedYields {
                let deposits = deposits(in: region, kind: kind, from: populated)
                guard !deposits.isEmpty else { continue }
                XCTAssertTrue(
                    deposits.allSatisfy { $0.remaining == expected },
                    "Unexpected \(kind) yield in \(region.rawValue)."
                )
            }
        }
    }

    func testAetherAndProvisionsRemainSharedAcrossRegions() {
        let tuning = SkirmishTuning.baseline
        let populated = populateBaselineWorld()

        for region in RegionID.allCases {
            XCTAssertEqual(tuning.depositYield(for: .aether, in: region), 180, accuracy: 1e-9)
            XCTAssertTrue(tuning.depositYield(for: .provisions, in: region).isInfinite)

            let regionDeposits = deposits(in: region, from: populated)
            XCTAssertTrue(
                regionDeposits
                    .filter { $0.kind == .aether }
                    .allSatisfy { $0.remaining == 180 }
            )
            XCTAssertTrue(
                regionDeposits
                    .filter { $0.kind == .provisions }
                    .allSatisfy { $0.remaining.isInfinite }
            )
        }
    }

    func testMutatingHomeMatterYieldLeavesOffHomeMatterAtEstablishedValue() {
        var tuning = SkirmishTuning.baseline
        tuning.homeDepositYields[.matter] = 731
        let populated = populateWorld(tuning: tuning)

        let homeMatter = populated.deposits.values.filter {
            $0.region.isHome && $0.kind == .matter
        }
        let offHomeMatter = populated.deposits.values.filter {
            !$0.region.isHome && $0.kind == .matter
        }

        XCTAssertTrue(homeMatter.allSatisfy { $0.remaining == 731 })
        XCTAssertTrue(offHomeMatter.allSatisfy { $0.remaining == 420 })
        XCTAssertEqual(
            homeMatter.reduce(0) { $0 + $1.remaining },
            731 * Double(homeMatter.count),
            accuracy: 1e-9
        )
        XCTAssertEqual(
            offHomeMatter.reduce(0) { $0 + $1.remaining },
            420 * Double(offHomeMatter.count),
            accuracy: 1e-9
        )
    }

    func testMutatingOffHomeMatterYieldLeavesHomeMatterAtApprovedValue() {
        var tuning = SkirmishTuning.baseline
        tuning.offHomeDepositYields[.matter] = 517
        let populated = populateWorld(tuning: tuning)

        let homeMatter = populated.deposits.values.filter {
            $0.region.isHome && $0.kind == .matter
        }
        let offHomeMatter = populated.deposits.values.filter {
            !$0.region.isHome && $0.kind == .matter
        }

        XCTAssertTrue(homeMatter.allSatisfy { $0.remaining == 700 })
        XCTAssertTrue(offHomeMatter.allSatisfy { $0.remaining == 517 })
        XCTAssertEqual(
            homeMatter.reduce(0) { $0 + $1.remaining },
            700 * Double(homeMatter.count),
            accuracy: 1e-9
        )
        XCTAssertEqual(
            offHomeMatter.reduce(0) { $0 + $1.remaining },
            517 * Double(offHomeMatter.count),
            accuracy: 1e-9
        )
    }

    func testDepositPlacementIsDeterministicAndIndependentOfYield() {
        let first = populateBaselineWorld()
        let second = populateBaselineWorld()

        var changedTuning = SkirmishTuning.baseline
        changedTuning.homeDepositYields[.matter] = 731
        changedTuning.offHomeDepositYields[.matter] = 517
        let changed = populateWorld(tuning: changedTuning)

        XCTAssertEqual(first.deposits.count, second.deposits.count)
        XCTAssertEqual(first.deposits.count, changed.deposits.count)
        for deposit in first.deposits.values {
            XCTAssertEqual(second.deposits[deposit.id]?.position, deposit.position)
            XCTAssertEqual(changed.deposits[deposit.id]?.position, deposit.position)
        }
    }

    func testWorldPopulatorDoesNotOwnDepositYieldLiterals() throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Simulation/WorldPopulator.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        XCTAssertTrue(source.contains("remaining: tuning.depositYield(for: kind, in: region)"))
        XCTAssertFalse(source.contains("startingYield"))
        XCTAssertFalse(source.contains("case .matter: 420"))
        XCTAssertFalse(source.contains("case .lumen: 300"))
        XCTAssertFalse(source.contains("case .aether: 180"))
        for literal in ["420", "300", "180", "700", "550"] {
            XCTAssertFalse(source.contains(literal), "WorldPopulator owns tuning literal \(literal).")
        }
    }

    private func populateBaselineWorld() -> WorldPopulator.Result {
        populateWorld(tuning: .baseline)
    }

    private func populateWorld(tuning: SkirmishTuning) -> WorldPopulator.Result {
        WorldPopulator.populate(
            map: WorldMap.map(.riverlands, seed: seed),
            tuning: tuning
        )
    }

    private func deposits(
        in region: RegionID,
        kind: ResourceKind? = nil,
        from populated: WorldPopulator.Result
    ) -> [Deposit] {
        populated.deposits.values.filter { deposit in
            deposit.region == region && (kind == nil || deposit.kind == kind)
        }
    }
}
