import XCTest
import simd
@testable import SunfoldCore

/// CP-G2a-R2 construction integrity: builder assignment, boarding exclusion,
/// carried-resource disposition, and exact fractional cancel refunds.
@MainActor
final class ConstructionIntegrityTests: XCTestCase {

    private func legalFarmPoints(in simulation: SkirmishSimulation, count: Int) -> [WorldPoint] {
        let home = simulation.map.fragment(.sunwovenHome).center
        let candidates: [WorldPoint] = [
            home + WorldPoint(14, 0),
            home + WorldPoint(-14, 0),
            home + WorldPoint(0, 14),
            home + WorldPoint(0, -14),
            home + WorldPoint(12, 12),
            home + WorldPoint(-12, 12),
            home + WorldPoint(12, -12),
            home + WorldPoint(-12, -12),
            home + WorldPoint(18, 6),
            home + WorldPoint(-18, 6),
            home + WorldPoint(6, 18),
            home + WorldPoint(-6, 18),
        ]
        var found: [WorldPoint] = []
        for point in candidates where ConstructionPlacement.isLegal(kind: .farm, at: point, in: simulation) {
            found.append(point)
            if found.count == count { return found }
        }
        return found
    }

    private func legalFarmPoint(in simulation: SkirmishSimulation) -> WorldPoint {
        let points = legalFarmPoints(in: simulation, count: 1)
        guard let point = points.first else {
            XCTFail("No legal Farm placement on home land.")
            return simulation.map.fragment(.sunwovenHome).center
        }
        return point
    }

    private func sunwovenCitizens(in simulation: SkirmishSimulation) -> [EntityID] {
        simulation.units.values
            .filter { $0.faction == .sunwoven && $0.kind == .citizen }
            .map(\.id)
            .sorted { $0.raw < $1.raw }
    }

    private func sunwovenLightTransport(in simulation: SkirmishSimulation) -> EntityID? {
        simulation.units.values
            .first { $0.faction == .sunwoven && $0.kind == .lightTransport }?
            .id
    }

    private func builders(on buildingID: EntityID, in simulation: SkirmishSimulation) -> [EntityID] {
        simulation.units.values
            .compactMap { unit -> EntityID? in
                if case .constructing(buildingID) = unit.activity { return unit.id }
                return nil
            }
            .sorted { $0.raw < $1.raw }
    }

    /// Walks a citizen onto a Matter node until cargo is present.
    private func ensureCarryingMatter(
        citizenID: EntityID,
        in simulation: SkirmishSimulation
    ) -> Cargo? {
        let citizenPosition = simulation.unit(citizenID)?.position ?? .zero
        let homeMatter = simulation.deposits.values
            .filter { $0.kind == .matter && $0.region == .sunwovenHome && !$0.isExhausted }
            .sorted {
                simd_distance(citizenPosition, $0.position) < simd_distance(citizenPosition, $1.position)
            }
        guard let deposit = homeMatter.first else {
            XCTFail("Missing reachable home Matter node.")
            return nil
        }

        // Seed reachability: walk to the station ring before gathering.
        let station = GatheringSystem.workStation(at: deposit, for: simulation.unit(citizenID)!)
        simulation.order(citizenID, moveTo: station)
        var reached = false
        for _ in 0..<240 {
            simulation.update(deltaTime: 0.05)
            if let unit = simulation.unit(citizenID),
               simd_distance(unit.position, station) <= 1.2
            {
                reached = true
                break
            }
        }
        XCTAssertTrue(reached, "Citizen must reach Matter station before gather.")

        simulation.orderGather([citizenID], from: deposit.id)

        var sawGathering = false
        for _ in 0..<320 {
            simulation.update(deltaTime: 0.05)
            guard let unit = simulation.unit(citizenID) else { break }
            if case .gathering = unit.activity { sawGathering = true }
            if let cargo = unit.cargo, cargo.kind == .matter, cargo.amount > 0 {
                XCTAssertTrue(sawGathering, "Gather activity should precede cargo.")
                return cargo
            }
        }
        XCTFail("Citizen should be carrying Matter after gather (gathering seen: \(sawGathering)).")
        return nil
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

        let assigned = builders(on: buildingID, in: simulation)
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

        XCTAssertEqual(builders(on: buildingID, in: simulation).count, 0, "Stopped citizen should leave the foundation.")

        simulation.orderConstruct([citizens[1]], on: buildingID)
        XCTAssertEqual(
            builders(on: buildingID, in: simulation).count,
            1,
            "A stalled foundation must accept new builders."
        )
    }

    func testTwoFoundationsHaveIndependentBuilderCaps() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        let citizens = sunwovenCitizens(in: simulation)
        XCTAssertGreaterThanOrEqual(citizens.count, 4)

        let points = legalFarmPoints(in: simulation, count: 2)
        XCTAssertEqual(points.count, 2, "Need two legal Farm footprints.")

        guard let firstID = simulation.placeBuilding(
            .farm, at: points[0], for: .sunwoven, preferredBuilders: Array(citizens.prefix(2))
        ) else {
            return XCTFail("First Farm placement failed.")
        }
        guard let secondID = simulation.placeBuilding(
            .farm, at: points[1], for: .sunwoven, preferredBuilders: Array(citizens.suffix(2))
        ) else {
            return XCTFail("Second Farm placement failed.")
        }

        XCTAssertEqual(builders(on: firstID, in: simulation).count, 2)
        XCTAssertEqual(builders(on: secondID, in: simulation).count, 2)
        XCTAssertEqual(SkirmishSimulation.maxBuildersPerSite, 4)

        // Each site still has independent headroom under the per-site cap.
        let firstSlotsLeft = SkirmishSimulation.maxBuildersPerSite - builders(on: firstID, in: simulation).count
        let secondSlotsLeft = SkirmishSimulation.maxBuildersPerSite - builders(on: secondID, in: simulation).count
        XCTAssertEqual(firstSlotsLeft, 2)
        XCTAssertEqual(secondSlotsLeft, 2)
        XCTAssertNotEqual(firstID, secondID)
    }

    func testAddingBuildersDoesNotDropAlreadyAssignedOnSameSite() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        let citizens = sunwovenCitizens(in: simulation)
        XCTAssertGreaterThanOrEqual(citizens.count, 3)

        let point = legalFarmPoint(in: simulation)
        guard let buildingID = simulation.placeBuilding(
            .farm, at: point, for: .sunwoven, preferredBuilders: [citizens[0]]
        ) else {
            return XCTFail("Farm placement failed.")
        }

        let firstWave = Set(builders(on: buildingID, in: simulation))
        XCTAssertEqual(firstWave, [citizens[0]])

        let assigned = simulation.orderConstruct([citizens[1], citizens[2]], on: buildingID)
        XCTAssertEqual(assigned, 2)

        let after = Set(builders(on: buildingID, in: simulation))
        XCTAssertTrue(after.isSuperset(of: firstWave), "Original builders must remain assigned.")
        XCTAssertEqual(after.count, 3)
        XCTAssertTrue(after.contains(citizens[1]))
        XCTAssertTrue(after.contains(citizens[2]))
    }

    // MARK: - Selection / inspection

    func testLightTransportOnlySelectionInspectsIncompleteFarm() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        guard let transportID = sunwovenLightTransport(in: simulation) else {
            return XCTFail("Missing Light Transport.")
        }
        XCTAssertFalse(simulation.unit(transportID)!.canBeAssignedToConstruction)

        let point = legalFarmPoint(in: simulation)
        guard let buildingID = simulation.placeBuilding(.farm, at: point, for: .sunwoven) else {
            return XCTFail("Farm placement failed.")
        }

        let selection = SelectionModel()
        selection.selectUnit(transportID)
        XCTAssertEqual(selection.selectedUnits, [transportID])
        XCTAssertNil(selection.selectedBuilding)

        let markerBefore = selection.lastOrderMarker
        selection.respondToIncompleteFoundation(buildingID, in: simulation)

        XCTAssertEqual(selection.selectedBuilding, buildingID, "Light Transport-only tap must inspect Farm.")
        XCTAssertTrue(selection.selectedUnits.isEmpty)
        XCTAssertEqual(selection.lastOrderMarker, markerBefore, "Inspection must not plant an order marker.")
        XCTAssertEqual(
            builders(on: buildingID, in: simulation).filter { $0 == transportID }.count,
            0
        )
    }

    func testOrderConstructSetsMarkerOnlyWhenBuildersAssigned() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        guard let transportID = sunwovenLightTransport(in: simulation) else {
            return XCTFail("Missing Light Transport.")
        }

        let point = legalFarmPoint(in: simulation)
        guard let buildingID = simulation.placeBuilding(.farm, at: point, for: .sunwoven) else {
            return XCTFail("Farm placement failed.")
        }

        let selection = SelectionModel()
        selection.selectUnit(transportID)
        selection.orderConstruct(on: buildingID, in: simulation)
        XCTAssertNil(selection.lastOrderMarker, "Zero builders assigned → no order marker.")
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

        guard let carried = ensureCarryingMatter(citizenID: citizenID, in: simulation) else { return }
        XCTAssertEqual(carried.kind, .matter)
        XCTAssertGreaterThan(carried.amount, 0)

        // Pause Core trickle so Matter delta is only cargo credit minus Farm cost.
        simulation.setPaused(true)
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
            "G2a disposition: carried Matter credits stock once on construct; cargo cleared."
        )
        XCTAssertNil(simulation.unit(citizenID)?.cargo, "Cargo must be cleared once — no duplicate drop-off.")
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

    /// **If it has a price, a citizen can put it down.**
    ///
    /// Found on device during CP-C4: the Formation Yard, Expansion Outpost and
    /// Dawn Loom had been given command tiles by CP-C1 — lit, priced, and
    /// tappable — while `placeableKinds` still listed only the three G2 kinds.
    /// `beginBuildGhost` bounced off that list silently, so all three tiles did
    /// nothing at all. Because the Formation Yard is the only building that
    /// trains a military unit, the player could reach *neither* win path: no
    /// Vanguard means no Conquest and no Dominion.
    ///
    /// A tile that costs 110 Matter and does nothing is the exact failure this
    /// project keeps meeting. The rule that catches it is this one.
    func testEveryBuildingWithAPriceCanActuallyBePlaced() {
        let tuning = SkirmishTuning.baseline
        for kind in BuildingKind.allCases where tuning.cost(for: kind) != .zero {
            XCTAssertTrue(
                ConstructionPlacement.placeableKinds.contains(kind),
                "\(kind.displayName) costs \(tuning.cost(for: kind)) and cannot be placed."
            )
        }
    }

    /// And the mirror: nothing free is placeable, so a stray addition to the
    /// list cannot hand the player a free Civilization Core or the objective.
    func testNothingFreeIsPlaceable() {
        let tuning = SkirmishTuning.baseline
        for kind in ConstructionPlacement.placeableKinds {
            XCTAssertNotEqual(
                tuning.cost(for: kind), .zero,
                "\(kind.displayName) is placeable and free."
            )
        }
    }
}
