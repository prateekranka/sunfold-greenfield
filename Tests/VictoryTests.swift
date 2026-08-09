import XCTest
import simd
@testable import SunfoldCore

/// CP-C4 — the match has to be able to end.
///
/// Spec: `00-CONTENT-SPEC.md` §5, overridden by `05-RESOLUTIONS-R1.md` §3 (B10).
/// Written against the rules rather than the implementation: each test names the
/// sentence of the spec it holds the code to.
///
/// The rule tests drive `VictorySystem` over hand-built worlds, the same idiom
/// `CombatTests` uses — no test-only mutators are added to `SkirmishSimulation`,
/// because a production class that carries a `debugKill` eventually gets one
/// called from production code.
@MainActor
final class VictoryTests: XCTestCase {

    private let tuning = SkirmishTuning.baseline
    private let map = WorldMap.map(.riverlands, seed: 20_260_726)

    // MARK: - Hand-built worlds

    private var spirePoint: WorldPoint { map.fragment(.dominion).center }

    private enum ID {
        static let sunwovenCore = EntityID(raw: 1)
        static let gravemarkCore = EntityID(raw: 2)
        static let spire = EntityID(raw: 3)
        static func unit(_ index: Int) -> EntityID { EntityID(raw: UInt32(100 + index)) }
    }

    /// Two Cores and the objective. Enough for either win path to be judged.
    private func world() -> [EntityID: Building] {
        [
            ID.sunwovenCore: Building(
                id: ID.sunwovenCore,
                faction: .sunwoven,
                kind: .civilizationCore,
                position: map.fragment(.sunwovenHome).center,
                region: .sunwovenHome
            ),
            ID.gravemarkCore: Building(
                id: ID.gravemarkCore,
                faction: .gravemark,
                kind: .civilizationCore,
                position: map.fragment(.gravemarkHome).center,
                region: .gravemarkHome
            ),
            ID.spire: Building(
                id: ID.spire,
                faction: nil,
                kind: .dominionSpire,
                position: spirePoint,
                region: .dominion
            ),
        ]
    }

    /// Units standing in the Spire ring. `index` keeps IDs distinct between calls.
    private func ring(
        _ faction: Faction,
        _ kind: UnitKind = .vanguard,
        count: Int = 1,
        from index: Int = 0,
        distance: Float = 6
    ) -> [EntityID: SunfoldCore.Unit] {
        var units: [EntityID: SunfoldCore.Unit] = [:]
        for offset in 0..<count {
            let id = ID.unit(index + offset)
            let angle = Float(index + offset) * 0.9
            units[id] = SunfoldCore.Unit(
                id: id,
                faction: faction,
                kind: kind,
                position: spirePoint + WorldPoint(sin(angle), cos(angle)) * distance,
                region: .dominion
            )
        }
        return units
    }

    /// Runs the victory rules for `seconds` of simulated time at the fixed step.
    @discardableResult
    private func run(
        _ state: inout VictoryState,
        seconds: Double,
        units: [EntityID: SunfoldCore.Unit],
        buildings: [EntityID: Building],
        startingAt elapsed: Double = 0
    ) -> Double {
        let step = tuning.stepDuration
        var now = elapsed
        var tick = UInt64((elapsed / step).rounded())
        let ticks = Int((seconds / step).rounded())
        for _ in 0..<ticks {
            now += step
            tick += 1
            VictorySystem.step(
                state: &state,
                input: VictorySystem.Inputs(
                    elapsed: now,
                    tick: tick,
                    units: units,
                    buildings: buildings,
                    tuning: tuning,
                    deltaTime: step
                )
            )
            if state.isOver { break }
        }
        return now
    }

    // MARK: - The objective exists

    func testTheDominionSpireStandsAtTheContestedCentreAndBelongsToNobody() {
        let simulation = SkirmishSimulation(seed: 20_260_726, adversaryEnabled: false)
        guard let spire = VictorySystem.spire(in: simulation.buildings) else {
            return XCTFail("no Dominion Spire was placed")
        }

        XCTAssertNil(spire.faction, "the Spire is neutral — it belongs to nobody")
        XCTAssertEqual(spire.region, .dominion)
        XCTAssertEqual(
            simd_distance(spire.position, simulation.map.fragment(.dominion).center),
            0,
            accuracy: 0.001,
            "the Spire sits on the one point both Cores are equidistant from"
        )
        XCTAssertEqual(spire.kind.maxLife, 1200, "R1 §3 (B10.1)")
        XCTAssertEqual(spire.kind.footprintRadius, 4.0, accuracy: 0.001)
        XCTAssertEqual(spire.kind.meleeArmor, 6)
        XCTAssertEqual(spire.kind.rangedArmor, 8)
        XCTAssertTrue(spire.kind.isNeutralObjective)

        // And nothing spawned underneath it.
        for deposit in simulation.deposits.values where deposit.region == .dominion {
            XCTAssertGreaterThan(
                simd_distance(deposit.position, spire.position),
                BuildingKind.dominionSpire.footprintRadius,
                "a \(deposit.kind) node is inside the objective"
            )
        }
    }

    /// "It is an objective, not a target — damage does not apply to it."
    func testTheSpireCannotBeDamagedEvenWhenOrderedAttackedPointBlank() {
        var buildings = world()
        var units = ring(.gravemark, count: 5)
        for id in units.keys {
            units[id]?.attackOrderTarget = ID.spire
            units[id]?.attackTarget = ID.spire
        }

        for _ in 0..<400 {  // 20 s of swinging
            _ = CombatSystem.step(units: &units, buildings: &buildings, map: map)
        }

        let spire = buildings[ID.spire]
        XCTAssertNotNil(spire, "the Spire must still exist")
        XCTAssertEqual(spire?.life, 1200, "damage does not apply to the objective")
        XCTAssertEqual(spire?.isDead, false)
    }

    /// A neutral building is nobody's enemy, so nothing auto-acquires it.
    func testNothingEverAcquiresTheSpireAsATarget() {
        var buildings = world()
        var units = ring(.gravemark, count: 3)
        units.merge(ring(.sunwoven, count: 3, from: 10)) { a, _ in a }

        for _ in 0..<200 {
            _ = CombatSystem.step(units: &units, buildings: &buildings, map: map)
            for unit in units.values {
                XCTAssertNotEqual(unit.attackTarget, ID.spire, "\(unit.kind) acquired the objective")
            }
        }
    }

    // MARK: - Dominion

    /// "Hold requirement: 45 s continuous." Uncontested, one Vanguard is enough.
    func testOneUncontestedVanguardWinsTheDominionInFortyFiveSeconds() {
        var state = VictoryState()
        let units = ring(.sunwoven)
        let buildings = world()

        run(&state, seconds: 44, units: units, buildings: buildings)
        XCTAssertNil(state.outcome, "the match ended early")
        XCTAssertEqual(state.hold(.sunwoven), 44, accuracy: 0.001)

        let ended = run(&state, seconds: 2, units: units, buildings: buildings, startingAt: 44)
        guard let outcome = state.outcome else {
            return XCTFail("45 s of uncontested hold did not end the match")
        }
        XCTAssertEqual(outcome.winner, .sunwoven)
        XCTAssertEqual(outcome.path, .dominion)
        XCTAssertEqual(outcome.elapsed, 45, accuracy: 0.06)
        XCTAssertEqual(ended, 45, accuracy: 0.06)
    }

    /// Citizens and Pathfinders are not on the capture list (R1 §3, B10.2).
    func testCitizensAndPathfindersCannotHoldTheDominion() {
        for kind in [UnitKind.citizen, .pathfinder] {
            var state = VictoryState()
            run(&state, seconds: 60, units: ring(.sunwoven, kind, count: 4), buildings: world())

            XCTAssertNil(state.outcome, "\(kind.displayName)s captured the Dominion")
            XCTAssertEqual(
                state.hold(.sunwoven), 0, accuracy: 0.001,
                "\(kind.displayName)s must not move the hold timer at all"
            )
        }
    }

    /// A passenger is not on the ground, so it holds nothing.
    func testAUnitAboardATransportHoldsNothing() {
        var state = VictoryState()
        var units = ring(.sunwoven, count: 2)
        for id in units.keys { units[id]?.activity = .aboard(transportID: ID.unit(99)) }

        run(&state, seconds: 60, units: units, buildings: world())
        XCTAssertEqual(state.hold(.sunwoven), 0, accuracy: 0.001)
        XCTAssertNil(state.outcome)
    }

    /// **The B10.3 rule.** Contested drains at half the fill rate rather than
    /// pausing, so mutual occupation always resolves.
    func testContestedProgressDecaysAtHalfTheFillRateRatherThanPausing() {
        var state = VictoryState()
        let buildings = world()
        let holders = ring(.sunwoven)

        run(&state, seconds: 20, units: holders, buildings: buildings)
        let banked = state.hold(.sunwoven)
        XCTAssertEqual(banked, 20, accuracy: 0.001)

        var contested = holders
        contested.merge(ring(.gravemark, from: 20)) { a, _ in a }
        run(&state, seconds: 10, units: contested, buildings: buildings, startingAt: 20)

        XCTAssertEqual(
            state.hold(.sunwoven), banked - 5, accuracy: 0.001,
            "10 s contested must drain 5 s — half the fill rate, not a pause"
        )
        XCTAssertLessThan(state.hold(.sunwoven), banked, "a pause rule would leave this unchanged")
        XCTAssertTrue(state.isContested(for: .sunwoven))
    }

    /// Both sides in the ring: both timers fall to zero. Nobody wins by standing
    /// still, which is what stops two schedules deadlocking forever.
    func testMutualOccupationDrainsBothSidesAndCannotDeadlock() {
        var state = VictoryState()
        let buildings = world()

        run(&state, seconds: 12, units: ring(.sunwoven), buildings: buildings)
        var both = ring(.sunwoven)
        both.merge(ring(.gravemark, from: 20)) { a, _ in a }

        run(&state, seconds: 60, units: both, buildings: buildings, startingAt: 12)

        XCTAssertEqual(state.hold(.sunwoven), 0, accuracy: 0.001)
        XCTAssertEqual(state.hold(.gravemark), 0, accuracy: 0.001)
        XCTAssertNil(state.outcome, "a contested ring resolves to nobody, not to a draw state")
    }

    /// "The timer resets to zero only if the holder has no military unit in the
    /// ring for 8 continuous seconds."
    func testProgressSurvivesABriefAbsenceAndIsLostAfterEight() {
        var state = VictoryState()
        let buildings = world()

        run(&state, seconds: 20, units: ring(.sunwoven), buildings: buildings)
        let banked = state.hold(.sunwoven)

        let away = ring(.sunwoven, distance: 40)  // well outside the 12 m ring
        run(&state, seconds: 6, units: away, buildings: buildings, startingAt: 20)
        XCTAssertEqual(
            state.hold(.sunwoven), banked, accuracy: 0.001,
            "six seconds away must cost nothing"
        )

        run(&state, seconds: 3, units: away, buildings: buildings, startingAt: 26)
        XCTAssertEqual(
            state.hold(.sunwoven), 0, accuracy: 0.001,
            "an empty ring past the grace window wipes the progress"
        )
    }

    /// The escalation ladder is a pure function of the clock (`00 §5`).
    func testTheHoldRequirementShortensAsTheMatchRunsLong() {
        XCTAssertEqual(tuning.dominionHoldRequirement(atElapsed: 0), 45)
        XCTAssertEqual(tuning.dominionHoldRequirement(atElapsed: 419), 45)
        XCTAssertEqual(tuning.dominionHoldRequirement(atElapsed: 420), 30, "7:00")
        XCTAssertEqual(tuning.dominionHoldRequirement(atElapsed: 539), 30)
        XCTAssertEqual(tuning.dominionHoldRequirement(atElapsed: 540), 20, "9:00")
        XCTAssertEqual(tuning.dominionHoldRequirement(atElapsed: 3600), 20)
    }

    /// The escalation is what stops a long match becoming a timeout: the same
    /// hold that is not enough at 5:00 wins at 9:00.
    func testTheSameHoldWinsLaterThanItWouldHaveEarlier() {
        var early = VictoryState()
        run(&early, seconds: 21, units: ring(.sunwoven), buildings: world(), startingAt: 300)
        XCTAssertNil(early.outcome, "21 s cannot win at 5:00, when 45 s is required")

        var late = VictoryState()
        run(&late, seconds: 21, units: ring(.sunwoven), buildings: world(), startingAt: 540)
        XCTAssertEqual(late.outcome?.path, .dominion, "21 s wins at 9:00, when 20 s is required")
    }

    /// Milestones at 15 s and 30 s, once each, on the way up only.
    func testDominionMilestonesAnnounceOnceEach() {
        var state = VictoryState()
        run(&state, seconds: 40, units: ring(.sunwoven), buildings: world())

        let milestones = state.events.filter { $0.text.contains("has held the Dominion") }
        XCTAssertEqual(milestones.count, 2, "expected exactly the 15 s and 30 s beats")
        XCTAssertTrue(milestones[0].text.contains("15s"))
        XCTAssertTrue(milestones[1].text.contains("30s"))
    }

    // MARK: - Conquest

    /// "Trigger: the Core reaches 0 HP." And the defeat mirror.
    func testDestroyingACoreEndsTheMatchByConquestBothWays() {
        for loser in Faction.allCases {
            var state = VictoryState()
            var buildings = world()
            run(&state, seconds: 1, units: [:], buildings: buildings)
            XCTAssertNil(state.outcome, "the match ended before anything happened")

            buildings[loser == .sunwoven ? ID.sunwovenCore : ID.gravemarkCore] = nil
            run(&state, seconds: 0.1, units: [:], buildings: buildings, startingAt: 1)

            guard let outcome = state.outcome else {
                return XCTFail("\(loser.displayName)'s Core fell and the match kept running")
            }
            XCTAssertEqual(outcome.winner, loser.opponent)
            XCTAssertEqual(outcome.path, .conquest)
            XCTAssertFalse(outcome.isVictory(for: loser))
            XCTAssertEqual(outcome.verdict(for: loser), "DEFEAT")
            XCTAssertEqual(outcome.verdict(for: loser.opponent), "VICTORY")
        }
    }

    /// A world with no Core at all must not resolve on its first tick — only a
    /// faction that *had* a Core can lose one.
    func testAWorldWithoutCoresNeverResolvesByConquest() {
        var state = VictoryState()
        let buildings: [EntityID: Building] = [
            ID.spire: Building(
                id: ID.spire, faction: nil, kind: .dominionSpire,
                position: spirePoint, region: .dominion
            ),
        ]
        run(&state, seconds: 30, units: [:], buildings: buildings)
        XCTAssertNil(state.outcome)
        XCTAssertTrue(state.contenders.isEmpty)
    }

    /// The structural-calamity beats at 75% / 50% / 25%, once each, downward only.
    func testCorePressureBeatsFireOnceEachOnTheWayDown() {
        var state = VictoryState()
        var buildings = world()
        var elapsed = 0.0

        for fraction in [0.9, 0.74, 0.74, 0.49, 0.24] {
            buildings[ID.sunwovenCore]?.life = BuildingKind.civilizationCore.maxLife * fraction
            elapsed = run(&state, seconds: 0.5, units: [:], buildings: buildings, startingAt: elapsed)
        }

        let beats = state.events.filter { $0.text.contains("Core at") }
        XCTAssertEqual(beats.map(\.text), [
            "Sunwoven Core at 75%",
            "Sunwoven Core at 50%",
            "Sunwoven Core at 25%",
        ])
    }

    // MARK: - The terminal state, on the real simulation

    /// "The simulation enters a terminal MatchOutcome state, stops stepping."
    func testAFinishedMatchStopsSteppingEntirely() {
        let simulation = SkirmishSimulation(seed: 20_260_726, adversaryEnabled: false)
        for _ in 0..<120 { simulation.update(deltaTime: 1.0 / 60.0) }
        simulation.resign()
        XCTAssertNotNil(simulation.outcome)

        let frozenTick = simulation.tick
        let frozenHash = simulation.worldHash
        for _ in 0..<300 { simulation.update(deltaTime: 1.0 / 60.0) }

        XCTAssertEqual(simulation.tick, frozenTick, "the world kept stepping behind the overlay")
        XCTAssertEqual(simulation.worldHash, frozenHash, "nothing may move after the verdict")
    }

    /// Resignation is a defeat, and is named as one rather than reported as a
    /// Conquest that never happened.
    func testResigningIsADefeatNamedHonestly() {
        let simulation = SkirmishSimulation(seed: 20_260_726, adversaryEnabled: false)
        for _ in 0..<60 { simulation.update(deltaTime: 1.0 / 60.0) }
        simulation.resign()

        guard let outcome = simulation.outcome else { return XCTFail("resigning did nothing") }
        XCTAssertEqual(outcome.winner, .gravemark)
        XCTAssertEqual(outcome.path, .resignation)
        XCTAssertEqual(outcome.verdict(for: .sunwoven), "DEFEAT")
        XCTAssertEqual(outcome.summary, "Sunwoven resigned.")
    }

    /// Play Again resets every deterministic system from the same seed.
    func testRestartRewindsTheMatchToItsOpeningState() {
        let simulation = SkirmishSimulation(seed: 20_260_726, adversaryEnabled: false)
        let openingHash = simulation.worldHash
        let openingUnits = simulation.units.count

        for _ in 0..<1800 { simulation.update(deltaTime: 1.0 / 60.0) }
        XCTAssertNotEqual(simulation.worldHash, openingHash)

        simulation.resign()
        simulation.restart()

        XCTAssertNil(simulation.outcome, "a restarted match is not over")
        XCTAssertEqual(simulation.tick, 0)
        XCTAssertEqual(simulation.elapsed, 0, accuracy: 0.0001)
        XCTAssertEqual(simulation.units.count, openingUnits)
        XCTAssertEqual(simulation.stock(for: .sunwoven), simulation.tuning.startingResources)
        XCTAssertEqual(simulation.dominionHold(for: .sunwoven), 0)
        XCTAssertEqual(
            simulation.worldHash, openingHash,
            "the same seed must rebuild the identical opening world"
        )
    }

    // MARK: - Determinism

    /// The victory rules are a pure function of the world, like everything else.
    func testTwoRunsReachTheSameVictoryStateFromOneSeed() {
        let a = SkirmishSimulation(seed: 20_260_726)
        let b = SkirmishSimulation(seed: 20_260_726)
        for _ in 0..<3000 {
            a.update(deltaTime: 1.0 / 20.0)
            b.update(deltaTime: 1.0 / 20.0)
        }

        XCTAssertEqual(a.worldHash, b.worldHash)
        XCTAssertEqual(a.victory, b.victory, "victory state must replay identically")
        XCTAssertEqual(a.victory.events.map(\.line), b.victory.events.map(\.line))
    }

    /// The point of the whole checkpoint: a real match against the real
    /// adversary, nobody touching the player, now **ends** — where before CP-C4
    /// it ran on over the corpse.
    func testAnUntouchedMatchAgainstTheAdversaryNowResolves() {
        let simulation = SkirmishSimulation(seed: 20_260_726)
        for _ in 0..<12_000 {
            simulation.update(deltaTime: 1.0 / 20.0)
            if simulation.isOver { break }
        }

        guard let outcome = simulation.outcome else {
            return XCTFail("ten minutes against the adversary and the match never ended")
        }
        XCTAssertEqual(outcome.winner, .gravemark, "the untouched player is wiped out")
        XCTAssertEqual(outcome.path, .conquest)
        XCTAssertLessThan(outcome.elapsed, 600)

        print("""

        CP-C4 · seed 20260726 · riverlands · no player input
          outcome : \(outcome.winner.displayName) wins by \(outcome.path.rawValue) at \
        \(matchClock(outcome.elapsed))  (tick \(outcome.tick))
          summary : \(outcome.summary)
          alerts  :
        \(simulation.victory.events.map { "    " + $0.line }.joined(separator: "\n"))

        """)
    }
}
