import XCTest
import simd
@testable import SunfoldGreenfield

/// Narrow tests for rules where a focused check is the cheapest proof.
/// These do not stand in for playing the rendered build.
final class DeterminismTests: XCTestCase {

    // MARK: - Seeded randomness

    func testSameSeedReplaysIdentically() {
        var first = DeterministicRandom(seed: 20_260_726)
        var second = DeterministicRandom(seed: 20_260_726)
        let a = (0..<64).map { _ in first.next() }
        let b = (0..<64).map { _ in second.next() }
        XCTAssertEqual(a, b, "A seed must replay the identical sequence.")
    }

    func testDifferentSeedsDiverge() {
        var first = DeterministicRandom(seed: 1)
        var second = DeterministicRandom(seed: 2)
        let a = (0..<32).map { _ in first.next() }
        let b = (0..<32).map { _ in second.next() }
        XCTAssertNotEqual(a, b)
    }

    func testZeroSeedIsNotDegenerate() {
        var generator = DeterministicRandom(seed: 0)
        let values = Set((0..<32).map { _ in generator.next() })
        XCTAssertEqual(values.count, 32, "Seed 0 must not collapse to a constant stream.")
    }

    func testUnitFloatStaysInRange() {
        var generator = DeterministicRandom(seed: 99)
        for _ in 0..<4096 {
            let value = generator.unitFloat()
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThan(value, 1)
        }
    }

    /// Subsystems must draw from independent streams, so adding a call in one
    /// place cannot shift every other system's numbers.
    func testTaggedStreamsAreIndependent() {
        var stars = DeterministicRandom.stream(seed: 7, tag: "starfield")
        var fragment = DeterministicRandom.stream(seed: 7, tag: "fragment.dominion")
        XCTAssertNotEqual(stars.next(), fragment.next())

        var repeated = DeterministicRandom.stream(seed: 7, tag: "starfield")
        var again = DeterministicRandom.stream(seed: 7, tag: "starfield")
        XCTAssertEqual(repeated.next(), again.next(), "A tagged stream must be reproducible.")
    }

    // MARK: - Fixed timestep

    func testClockRunsFixedStepsRegardlessOfFrameRate() {
        let tuning = SkirmishTuning.baseline
        var steady = SimulationClock(tuning: tuning)
        var erratic = SimulationClock(tuning: tuning)

        // One second delivered as 60 even frames.
        for _ in 0..<60 { _ = steady.advance(by: 1.0 / 60.0) }
        // The same second delivered as 10 uneven frames.
        for delta in [0.05, 0.2, 0.017, 0.13, 0.09, 0.21, 0.033, 0.15, 0.06, 0.064] {
            _ = erratic.advance(by: delta)
        }

        XCTAssertEqual(steady.tick, UInt64(tuning.simulationHz))
        XCTAssertEqual(erratic.tick, steady.tick, "Frame pacing must not change step count.")
        XCTAssertEqual(erratic.elapsed, steady.elapsed, accuracy: 1e-9)
    }

    func testClockDropsBacklogInsteadOfFastForwarding() {
        let tuning = SkirmishTuning.baseline
        var clock = SimulationClock(tuning: tuning)
        // A long suspension must not replay as a burst of catch-up steps.
        let steps = clock.advance(by: 30)
        XCTAssertEqual(steps, tuning.maxStepsPerFrame)
        XCTAssertEqual(clock.accumulator, 0, "Surplus time must be discarded, not banked.")
    }

    // MARK: - Map contract

    /// The Dominion anchors the map, and neither side may be handed materially
    /// more ground than the other.
    ///
    /// This used to assert that every plate had an exact mirror. It does not any
    /// more (user direction, 2026-07-28) — the layouts are asymmetric on purpose.
    /// Dropping the mirror does not drop the balance question, though: it moves it
    /// from "are the two sides congruent" to "are they comparable", which is a
    /// looser rule but the one that actually decides whether a match is fair.
    func testNeitherSideIsHandedMoreGround() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)
            XCTAssertEqual(
                simd_length(map.fragment(.dominion).center), 0, accuracy: 0.001,
                "\(id): the Dominion must sit at the origin."
            )

            func territory(_ regions: [RegionID]) -> Int {
                var cells = 0
                let step: Float = 1.5
                var y = -map.bounds.y
                while y <= map.bounds.y {
                    var x = -map.bounds.x
                    while x <= map.bounds.x {
                        if let owner = map.region(at: WorldPoint(x, y)), regions.contains(owner) {
                            cells += 1
                        }
                        x += step
                    }
                    y += step
                }
                return cells
            }
            let sunwoven = territory([.sunwovenHome, .sunwovenExpansion])
            let gravemark = territory([.gravemarkHome, .gravemarkExpansion])
            let skew = Float(abs(sunwoven - gravemark)) / Float(max(sunwoven, gravemark))
            XCTAssertLessThan(
                skew, 0.20,
                "\(id): one side holds \(sunwoven) cells and the other \(gravemark) — too lopsided to be a fair start."
            )
        }
    }

    /// Contiguous maps pack plates so tops merge; every region must still reach
    /// every other through overlapping contacts (gap ≤ 0).
    func testLandmassIsContiguous() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)
            XCTAssertTrue(
                map.isContiguousLandmass,
                "\(id): fragments must overlap into one connected landmass."
            )
        }
    }

    /// Fairness, whole. As of the user's direction on 2026-07-28 that is one
    /// property and not seven: **both Cores the same distance from the Dominion.**
    ///
    /// The maps used to be exact half-turns of themselves and this file tested
    /// that. They are deliberately not any more — a mirrored map reads as one shape
    /// printed twice — so the old assertion would now fail on purpose, which is the
    /// worst kind of test. What is left is the rule that actually decides matches,
    /// and it is checked two ways: as the crow flies, and as a unit walks. A Core
    /// that has to go round a lake is further away than the ruler says.
    func testCoresAreEquidistantFromTheDominion() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)
            let dominion = map.fragment(.dominion).center
            let sunwoven = map.fragment(.sunwovenHome).center
            let gravemark = map.fragment(.gravemarkHome).center

            XCTAssertEqual(
                simd_distance(sunwoven, dominion),
                simd_distance(gravemark, dominion),
                accuracy: 0.5,
                "\(id): the two Cores must be the same distance from the Dominion."
            )

            // Void crossed on the straight approach. Equal distance over unequal
            // ground is not equal, and this is the half that a coordinate check
            // cannot see.
            func voidOnApproach(from home: WorldPoint) -> Float {
                let steps = 400
                let step = simd_distance(home, dominion) / Float(steps)
                var wet: Float = 0
                for index in 0...steps {
                    let point = home + (dominion - home) * (Float(index) / Float(steps))
                    if !map.isLand(point) { wet += step }
                }
                return wet
            }
            XCTAssertEqual(
                voidOnApproach(from: sunwoven),
                voidOnApproach(from: gravemark),
                accuracy: 6,
                "\(id): one side's approach to the Dominion crosses far more void than the other's."
            )
        }
    }

    /// Nothing may be stranded: every landmass must carry a plate centre.
    ///
    /// This replaces a per-region connectivity test. That test asserted each
    /// region's own ground was in one piece, which stopped being the right question
    /// once ``LandErosion`` arrived: erosion can hand a plate a fringe reachable
    /// only by stepping through the neighbour's territory, and that is fine —
    /// movement clamps to *land*, not to a region, so a unit walks there without
    /// noticing. Several landmasses is also fine, and deliberate: an outcrop
    /// reached only by transport is what the void lanes are for.
    ///
    /// What is never fine is a piece of land with no plate centre on it. Nothing
    /// docks there and nothing spawns there, but `WorldPopulator` will still place
    /// a deposit on it — a resource visibly on the map that no citizen can ever
    /// reach, and no error anywhere to say why.
    func testEveryLandmassCarriesAPlateCentre() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)
            let step: Float = 1.5
            let columns = Int(map.bounds.x * 2 / step) + 1
            let rows = Int(map.bounds.y * 2 / step) + 1
            func point(_ column: Int, _ row: Int) -> WorldPoint {
                WorldPoint(-map.bounds.x + Float(column) * step, -map.bounds.y + Float(row) * step)
            }

            var land = Set<Int>()
            for row in 0..<rows {
                for column in 0..<columns where map.isLand(point(column, row)) {
                    land.insert(row * columns + column)
                }
            }
            XCTAssertFalse(land.isEmpty, "\(id): the map has no land at all.")

            var remaining = land
            while let start = remaining.first {
                var cells: [Int] = []
                var queue = [start]
                remaining.remove(start)
                while let current = queue.popLast() {
                    cells.append(current)
                    let row = current / columns, column = current % columns
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nextColumn = column + dx, nextRow = row + dy
                        guard nextColumn >= 0, nextColumn < columns,
                              nextRow >= 0, nextRow < rows else { continue }
                        let neighbour = nextRow * columns + nextColumn
                        if remaining.contains(neighbour) {
                            remaining.remove(neighbour)
                            queue.append(neighbour)
                        }
                    }
                }
                // Two cells is a shoreline rounding artefact, not an island.
                guard cells.count > 2 else { continue }
                let occupied = cells.contains { cell in
                    let where_ = point(cell % columns, cell / columns)
                    return RegionID.allCases.contains { region in
                        simd_distance(map.fragment(region).center, where_) < step
                    }
                }
                let centre = cells.reduce(WorldPoint.zero) { $0 + point($1 % columns, $1 / columns) }
                    / Float(cells.count)
                XCTAssertTrue(
                    occupied,
                    "\(id): \(cells.count) cells of land around \(centre) have no plate centre — nothing can reach them."
                )
            }
        }
    }

    /// A Core stands at its plate's centre and `crossing` marches out from there,
    /// so a centre under water breaks the opening state and every dock on it.
    func testPlateCentresAreDryLand() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)
            for region in RegionID.allCases {
                XCTAssertEqual(
                    map.region(at: map.fragment(region).center), region,
                    "\(id)/\(region): a plate's own centre must be dry land it owns."
                )
            }
        }
    }

    /// The transport-first rule should be visible on the ground, not only in the
    /// lane table: there must be real water between a home and its expansion.
    func testTransportCrossingsHaveWaterToCross() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)
            for (home, expansion) in [(RegionID.sunwovenHome, RegionID.sunwovenExpansion),
                                      (.gravemarkHome, .gravemarkExpansion)] {
                let from = map.fragment(home).center
                let to = map.fragment(expansion).center
                let steps = 240
                var wet: Float = 0
                for step in 0...steps {
                    let point = from + (to - from) * (Float(step) / Float(steps))
                    if map.isSubmerged(point) { wet += simd_distance(from, to) / Float(steps) }
                }
                XCTAssertGreaterThan(
                    wet, 4,
                    "\(id): \(home)→\(expansion) crosses only \(wet) m of void — the transport rule has nothing behind it."
                )
            }
        }
    }

    /// The coastline the minimap draws must close into loops and enclose area.
    func testCoastlineTracesClosedLoops() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)
            let contour = LandContour.trace(map, resolution: 160)
            XCTAssertFalse(contour.loops.isEmpty, "\(id): the coastline traced to nothing.")
            for loop in contour.loops {
                XCTAssertGreaterThan(loop.count, 3, "\(id): a coastline loop is degenerate.")
            }
        }
    }

    /// Land should fill most of the playable map (camera ``bounds``), with void
    /// water remaining as readable rivers/lakes/inlets — not dominating the
    /// theatre and not vanishing into a solid slab. Tuned to 75–80%.
    func testLandCoversMostOfThePlayableMap() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)
            let coverage = map.landCoverage(step: 1.0)
            XCTAssertGreaterThanOrEqual(
                coverage, 0.75,
                "\(id): land covers only \(String(format: "%.1f", coverage * 100))% of the playable map — below the 75% floor."
            )
            XCTAssertLessThanOrEqual(
                coverage, 0.80,
                "\(id): land covers \(String(format: "%.1f", coverage * 100))% of the playable map — above the 80% ceiling (water may no longer read)."
            )
        }
    }

    /// A transport crossing is required to reach the first expansion, and a full
    /// land route to the enemy Core must exist once both Outposts are woven.
    func testHomeReachesExpansionOnlyByVoidUntilOutpostIsWoven() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)

            let homeLink = map.causeways.first {
                ($0.from == .sunwovenHome && $0.to == .sunwovenExpansion)
                    || ($0.from == .sunwovenExpansion && $0.to == .sunwovenHome)
            }
            XCTAssertEqual(homeLink?.wovenByOutpostOf, .sunwoven, "\(id): home causeway must require the Outpost.")
            XCTAssertFalse(homeLink?.isAlwaysOpen ?? true)

            let lane = map.voidLanes.contains {
                ($0.from == .sunwovenHome && $0.to == .sunwovenExpansion)
                    || ($0.from == .sunwovenExpansion && $0.to == .sunwovenHome)
            }
            XCTAssertTrue(lane, "\(id): first crossing must have a legal void lane.")

            let spine = map.causeways.filter(\.isAlwaysOpen).map(\.to)
            XCTAssertTrue(spine.contains(.dominion), "\(id): central land spine must reach the Dominion.")
        }
    }

    func testStagingPointIsOnLandAndDockIsInVoid() {
        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: 20_260_726)
            for (region, target) in [(RegionID.sunwovenHome, RegionID.sunwovenExpansion),
                                     (.gravemarkHome, .gravemarkExpansion)] {
                let staging = map.stagingPoint(on: region, facing: target)
                let dock = map.dockPoint(on: region, facing: target)
                XCTAssertTrue(map.contains(staging, in: region), "\(id): boarding must stage on solid land.")
                XCTAssertFalse(map.contains(dock, in: region), "\(id): hull must sit off the rim, in void.")
                XCTAssertNil(map.region(at: dock), "\(id): a dock must not land inside another fragment.")
            }
        }
    }

    // MARK: - Economy accounting

    @MainActor
    func testBothFactionsReceiveTheIdenticalCoreTrickle() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        let start = simulation.stock(for: .sunwoven)
        for _ in 0..<60 { simulation.update(deltaTime: 1.0 / 60.0) }

        let sunwoven = simulation.stock(for: .sunwoven)
        let gravemark = simulation.stock(for: .gravemark)
        XCTAssertEqual(sunwoven, gravemark, "The AI must never receive hidden income.")

        let gained = sunwoven.provisions - start.provisions
        XCTAssertEqual(gained, SkirmishTuning.baseline.coreTrickle.provisions, accuracy: 0.02)
    }

    @MainActor
    func testPauseStopsSimulatedTime() {
        let simulation = SkirmishSimulation(seed: 1)
        simulation.setPaused(true)
        for _ in 0..<60 { simulation.update(deltaTime: 1.0 / 60.0) }
        XCTAssertEqual(simulation.tick, 0)
        XCTAssertEqual(simulation.elapsed, 0)
    }
}
