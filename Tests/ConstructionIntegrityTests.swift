import XCTest
import simd
@testable import SunfoldGreenfield

/// CP-G2a-R2 construction integrity: builder assignment, boarding exclusion,
/// carried-resource disposition, and exact fractional cancel refunds.
@MainActor
final class ConstructionIntegrityTests: XCTestCase {

    private func legalFarmPoint(in simulation: SkirmishSimulation) -> WorldPoint {
        let home = simulation.map.fragment(.sunwovenHome).center
        let candidates: [WorldPoint] = [
            home + WorldPoint(14, 0),
            home + WorldPoint(-14, 0),
            home + WorldPoint(0, 14),
            home + WorldPoint(0, -14),
            home + WorldPoint(12, 12),
            home + WorldPoint(-12, 12),
        ]
        for point in candidates where ConstructionPlacement.isLegal(kind: .farm, at: point, in: simulation) {
            return point
        }
        XCTFail("No legal Farm placement on home land.")
        return home
    }

    private func sunwovenCitizens(in simulation: SkirmishSimulation) -> [EntityID] {
        simulation.units.values
            .filter { $0.faction == .sunwoven && $0.kind == .citizen }
            .map(\.id)
            .sorted { $0.raw < $1.raw }
    }

    // MARK: - Builder assignment

    func testBuildersStayAssignedUntilFoundationCompletes() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        let citizens = sunwovenCitizens(in: simulation)
        XCTAssertGreaterThanOrEqual(citizens.count, 2)

        let point = legalFarmPoint(in: simulation)
        guard let buildingID = simulation.placeBuilding(
            .farm, at: point, for: .sunwoven, preferredBuilders: Array(citizens.prefix(2))
        ) else {
            return XCTFail("Farm placement failed.")
        }

        for _ in 0..<40 { simulation.update(deltaTime: 0.05) }

        let assigned = simulation.units.values.filter {
            if case .constructing(buildingID) = $0.activity { return true }
            return false
        }
        XCTAssertEqual(assigned.count, 2, "Assigned builders must stay on the job while incomplete.")

        guard let building = simulation.building(buildingID) else {
            return XCTFail("Building missing.")
        }
        XCTAssertFalse(building.isComplete)
    }

    func testStalledFoundationAcceptsBuildersAgain() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        let citizens = sunwovenCitizens(in: simulation)
        XCTAssertGreaterThanOrEqual(citizens.count, 2)

        let point = legalFarmPoint(in: simulation)
        guard let buildingID = simulation.placeBuilding(
            .farm, at: point, for: .sunwoven, preferredBuilders: [citizens[0]]
        ) else {
            return XCTFail("Farm placement failed.")
        }

        simulation.order(citizens[0], moveTo: simulation.unit(citizens[0])!.position)
        for _ in 0..<10 { simulation.update(deltaTime: 0.05) }

        let stalled = simulation.units.values.filter {
            if case .constructing(buildingID) = $0.activity { return true }
            return false
        }
        XCTAssertEqual(stalled.count, 0, "Stopped citizen should leave the foundation.")

        simulation.orderConstruct([citizens[1]], on: buildingID)
        let resumed = simulation.units.values.filter {
            if case .constructing(buildingID) = $0.activity { return true }
            return false
        }
        XCTAssertEqual(resumed.count, 1, "A stalled foundation must accept new builders.")
    }

    // MARK: - Boarding exclusion

    func testBoardingAndAboardCitizensCannotBeAssigned() {
        let transportID = EntityID(raw: 99)
        var citizen = Unit(
            id: EntityID(raw: 1),
            faction: .sunwoven,
            kind: .citizen,
            position: .zero,
            region: .sunwovenHome
        )

        citizen.activity = .boarding(transportID: transportID)
        XCTAssertFalse(citizen.canBeAssignedToConstruction)

        citizen.activity = .aboard(transportID: transportID)
        XCTAssertFalse(citizen.canBeAssignedToConstruction)

        citizen.activity = .idle
        XCTAssertTrue(citizen.canBeAssignedToConstruction)
    }

    // MARK: - Carried resources

    func testConstructionAssignmentDepositsCarriedLoadToStock() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        let citizens = sunwovenCitizens(in: simulation)
        let citizenID = citizens[0]

        guard let depositID = simulation.deposits.values
            .first(where: { $0.kind == .matter && $0.region == .sunwovenHome })
            .map(\.id)
        else {
            return XCTFail("Missing home Matter node.")
        }

        simulation.orderGather([citizenID], from: depositID)
        for _ in 0..<80 { simulation.update(deltaTime: 0.05) }
        guard let carried = simulation.unit(citizenID)?.cargo, carried.amount > 0 else {
            return XCTFail("Citizen should be carrying Matter before construction.")
        }

        let matterBefore = simulation.stock(for: .sunwoven).matter
        let point = legalFarmPoint(in: simulation)
        guard simulation.placeBuilding(
            .farm, at: point, for: .sunwoven, preferredBuilders: [citizenID]
        ) != nil else {
            return XCTFail("Farm placement failed.")
        }

        let matterAfter = simulation.stock(for: .sunwoven).matter
        XCTAssertEqual(
            matterAfter - matterBefore,
            carried.amount - simulation.tuning.farmCost.matter,
            accuracy: 1e-6,
            "Carried Matter must credit stock when construction starts — no silent loss."
        )
        XCTAssertNil(simulation.unit(citizenID)?.cargo)
    }

    // MARK: - Fractional cancel refund

    func testCancelRefundUsesExactFractionalMatter() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        let point = legalFarmPoint(in: simulation)
        let matterBefore = simulation.stock(for: .sunwoven).matter

        guard let buildingID = simulation.placeBuilding(.farm, at: point, for: .sunwoven) else {
            return XCTFail("Farm placement failed.")
        }
        XCTAssertTrue(simulation.cancelConstruction(buildingID))

        let expectedRefund = simulation.tuning.farmCost.matter * simulation.tuning.cancelRefundFraction
        XCTAssertEqual(expectedRefund, 52.5, accuracy: 1e-9)

        let matterAfter = simulation.stock(for: .sunwoven).matter
        XCTAssertEqual(
            matterAfter - matterBefore,
            expectedRefund - simulation.tuning.farmCost.matter,
            accuracy: 1e-6,
            "Stock refund must match the exact fractional sim truth."
        )
    }

    func testRefundLabelPreservesFractionalMatter() {
        let refund = SkirmishTuning.baseline.farmCost.matter * SkirmishTuning.baseline.cancelRefundFraction
        XCTAssertEqual(ResourcePool.displayAmount(refund), "52.5")
    }
}
