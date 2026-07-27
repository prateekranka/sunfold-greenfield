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

    func testMapIsSymmetricUnderHalfTurn() {
        let map = WorldMap.proofMap(seed: 20_260_726)
        let mirrors: [(RegionID, RegionID)] = [
            (.sunwovenHome, .gravemarkHome),
            (.sunwovenExpansion, .gravemarkExpansion),
            (.neutralOutcropNorth, .neutralOutcropSouth),
        ]
        for (left, right) in mirrors {
            let a = map.fragment(left), b = map.fragment(right)
            XCTAssertEqual(a.center.x, -b.center.x, accuracy: 0.001)
            XCTAssertEqual(a.center.y, -b.center.y, accuracy: 0.001)
            XCTAssertEqual(a.radius, b.radius, accuracy: 0.001, "Mirrored fragments must match in size.")
        }
        let dominion = map.fragment(.dominion)
        XCTAssertEqual(simd_length(dominion.center), 0, accuracy: 0.001, "Dominion must sit at the origin.")
    }

    func testFragmentsDoNotOverlap() {
        let map = WorldMap.proofMap(seed: 20_260_726)
        let all = RegionID.allCases.map { map.fragment($0) }
        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                let gap = simd_distance(all[i].center, all[j].center) - (all[i].radius + all[j].radius)
                XCTAssertGreaterThan(gap, 0, "\(all[i].id) and \(all[j].id) must be separated by void.")
            }
        }
    }

    /// A transport crossing is required to reach the first expansion, and a full
    /// land route to the enemy Core must exist once both Outposts are woven.
    func testHomeReachesExpansionOnlyByVoidUntilOutpostIsWoven() {
        let map = WorldMap.proofMap(seed: 20_260_726)

        let homeLink = map.causeways.first {
            ($0.from == .sunwovenHome && $0.to == .sunwovenExpansion)
                || ($0.from == .sunwovenExpansion && $0.to == .sunwovenHome)
        }
        XCTAssertEqual(homeLink?.wovenByOutpostOf, .sunwoven, "The home causeway must require the Outpost.")
        XCTAssertFalse(homeLink?.isAlwaysOpen ?? true)

        let lane = map.voidLanes.contains {
            ($0.from == .sunwovenHome && $0.to == .sunwovenExpansion)
                || ($0.from == .sunwovenExpansion && $0.to == .sunwovenHome)
        }
        XCTAssertTrue(lane, "The first crossing must have a legal void lane.")

        let spine = map.causeways.filter(\.isAlwaysOpen).map(\.to)
        XCTAssertTrue(spine.contains(.dominion), "The central land spine must reach the Dominion.")
    }

    func testStagingPointIsOnLandAndDockIsInVoid() {
        let map = WorldMap.proofMap(seed: 20_260_726)
        for (region, target) in [(RegionID.sunwovenHome, RegionID.sunwovenExpansion),
                                 (.gravemarkHome, .gravemarkExpansion)] {
            let staging = map.stagingPoint(on: region, facing: target)
            let dock = map.dockPoint(on: region, facing: target)
            XCTAssertTrue(map.contains(staging, in: region), "Boarding must stage on solid land.")
            XCTAssertFalse(map.contains(dock, in: region), "The hull must sit off the rim, in void.")
            XCTAssertNil(map.region(at: dock), "A dock must not land inside another fragment.")
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
