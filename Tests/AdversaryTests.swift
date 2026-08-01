import XCTest
import simd
@testable import SunfoldCore

/// CP-C3 adversary v0: determinism, the wave schedule, and the ledger.
///
/// Every test here drives a full `SkirmishSimulation` with **no player input**,
/// which is the only honest way to measure a schedule that is meant to play the
/// same match every time.
@MainActor
final class AdversaryTests: XCTestCase {

    private static let seed: UInt64 = 20_260_726
    private static let step = 1.0 / 20.0

    private func run(ticks: Int, adversaryEnabled: Bool = true) -> SkirmishSimulation {
        let simulation = SkirmishSimulation(seed: Self.seed, adversaryEnabled: adversaryEnabled)
        for _ in 0..<ticks { simulation.update(deltaTime: Self.step) }
        return simulation
    }

    // MARK: - The determinism bar

    /// **The CP-C3 bar.** Two no-input runs from seed `20260726` must produce an
    /// identical world hash for the whole match.
    ///
    /// The bar was originally written as "at tick 12000", ten minutes of
    /// simulated match. **CP-C4 made tick 12000 unreachable**: the match now
    /// *ends* when the adversary destroys the untouched player's Core, at tick
    /// 7192, and a finished simulation refuses to step. The determinism claim is
    /// unchanged and is now measured over the whole match instead of a fixed
    /// tick — both runs must stop on the same tick with the same fingerprint.
    func testTwoNoInputRunsShareOneWorldHashForTheWholeMatch() {
        let first = run(ticks: 12_000)
        let second = run(ticks: 12_000)

        XCTAssertTrue(first.isOver, "the match must resolve inside ten minutes")
        XCTAssertEqual(first.tick, second.tick, "the two runs ended on different ticks")
        XCTAssertEqual(first.outcome, second.outcome, "the two runs ended differently")
        XCTAssertEqual(
            first.worldHash, second.worldHash,
            "Two runs of one seed diverged — the adversary is not a pure function of tick and state."
        )
        XCTAssertEqual(
            first.adversary.events.map(\.line),
            second.adversary.events.map(\.line),
            "The two runs played different matches."
        )
    }

    /// A hash that never changes is not measuring anything. Different worlds must
    /// produce different hashes, or the bar above is satisfied by a constant.
    func testWorldHashSeparatesDifferentWorlds() {
        XCTAssertNotEqual(run(ticks: 600).worldHash, run(ticks: 1_200).worldHash)
        XCTAssertNotEqual(
            run(ticks: 3_000, adversaryEnabled: false).worldHash,
            run(ticks: 3_000).worldHash,
            "The adversary must actually change the world."
        )
    }

    // MARK: - The schedule

    func testFormationYardIsCommittedAtTwoMinutes() {
        let simulation = SkirmishSimulation(seed: Self.seed)
        var committedAt: UInt64?

        for _ in 0..<4_000 {
            simulation.update(deltaTime: Self.step)
            if committedAt == nil,
               simulation.buildings.values.contains(where: {
                   $0.faction == .gravemark && $0.kind == .formationYard
               })
            {
                committedAt = simulation.tick
            }
        }

        guard let committedAt else {
            return XCTFail("The adversary never committed a Formation Yard.")
        }
        XCTAssertGreaterThanOrEqual(
            committedAt, Adversary.Schedule.formationYardTick,
            "The Yard must not be committed before the schedule says 2:00."
        )
        XCTAssertLessThanOrEqual(
            committedAt, Adversary.Schedule.formationYardTick + 200,
            "The Yard landed at tick \(committedAt) — the adversary cannot afford its own schedule."
        )
        XCTAssertTrue(
            simulation.buildings.values.contains(where: {
                $0.faction == .gravemark && $0.kind == .formationYard && $0.isComplete
            }),
            "The Yard must be finished, not left as a foundation nobody builds."
        )
    }

    func testAdversaryGrowsItsEconomyTowardTwelveCitizens() {
        let simulation = run(ticks: 6_000)
        let citizens = simulation.units.values.filter {
            $0.faction == .gravemark && $0.kind == .citizen
        }.count
        XCTAssertGreaterThanOrEqual(
            citizens, 8,
            "Only \(citizens) Gravemark citizens by 5:00 — the economy schedule is not running."
        )
        XCTAssertLessThanOrEqual(citizens, Adversary.Schedule.citizenTarget, "It must stop at twelve.")
    }

    /// The wave table as a pure function: five waves, on the ticks R1 §5 names,
    /// each fielding what the table asks for and never smaller than the last.
    ///
    /// Split out from the live-match test below because **CP-C4 shortened the
    /// match**: the untouched player is wiped at 5:59, so waves 3 to 5 (7:00,
    /// 8:30, 10:00) no longer leave at all in a real game. The schedule is still
    /// specified for them, and a spec that only holds where it happens to run is
    /// not a spec, so it is asserted directly.
    func testTheWaveTableIsWhatTheSpecAsksForAllTheWayToWaveFive() {
        for wave in 1...5 {
            XCTAssertEqual(
                Adversary.Schedule.dispatchTick(ofWave: wave),
                UInt64(4_800 + (wave - 1) * 1_800),
                "Wave \(wave) is scheduled off R1 §5's 90-second cadence."
            )
            XCTAssertFalse(
                Adversary.composition(ofWave: wave).isEmpty,
                "Wave \(wave) has no composition at all."
            )
        }

        let sizes = (1...5).map { wave in
            Adversary.composition(ofWave: wave).reduce(0) { $0 + $1.count }
        }
        XCTAssertEqual(sizes, sizes.sorted(), "Waves must escalate, not shrink: \(sizes).")
    }

    /// The waves that actually leave in a real match do so on their scheduled
    /// tick, non-empty, fielding exactly the table's composition.
    ///
    /// Only waves 1 and 2 fit inside a match now — see the note above. That is
    /// the honest bound, and asserting more would be asserting a match that no
    /// longer exists.
    func testWavesLeaveOnScheduleAndFieldWhatTheTableAsksFor() {
        let simulation = SkirmishSimulation(seed: Self.seed)
        var dispatchTick: [Int: UInt64] = [:]
        var roster: [Int: [UnitKind: Int]] = [:]
        var seen = 0

        for _ in 0..<10_500 {
            simulation.update(deltaTime: Self.step)
            let dispatched = simulation.adversary.wavesDispatched
            guard dispatched > seen else { continue }
            seen = dispatched
            dispatchTick[dispatched] = simulation.tick

            var counts: [UnitKind: Int] = [:]
            for (id, wave) in simulation.adversary.waveOf where wave == dispatched {
                guard let kind = simulation.unit(id)?.kind else { continue }
                counts[kind, default: 0] += 1
            }
            roster[dispatched] = counts
        }

        XCTAssertTrue(simulation.isOver, "the match must resolve — CP-C4")

        for wave in 1...2 {
            guard let tick = dispatchTick[wave] else { return XCTFail("Wave \(wave) never left.") }
            XCTAssertEqual(
                tick, Adversary.Schedule.dispatchTick(ofWave: wave),
                "Wave \(wave) left at tick \(tick), off its scheduled tick."
            )

            let fielded = roster[wave] ?? [:]
            XCTAssertFalse(fielded.isEmpty, "Wave \(wave) was dispatched empty.")
            for slot in Adversary.composition(ofWave: wave) {
                XCTAssertEqual(
                    fielded[slot.kind] ?? 0, slot.count,
                    "Wave \(wave) fielded \(fielded[slot.kind] ?? 0) \(slot.kind.pluralName), "
                        + "not the \(slot.count) the table asks for."
                )
            }
        }

        let sizes = (1...2).map { (roster[$0] ?? [:]).values.reduce(0, +) }
        XCTAssertEqual(sizes, sizes.sorted(), "Waves must escalate, not shrink: \(sizes).")
    }

    // MARK: - The play bars

    /// **Arrival.** `04-IMPLEMENTATION-ORDER.md` puts the first wave on the
    /// player between 3:30 and 4:30. R1 §5 fixes its *departure* at 4:00, so
    /// arrival is the walk, and this is the test that the walk actually finishes
    /// rather than sliding along a coastline forever.
    func testFirstWaveArrivesOnThePlayersGroundInsideTheBar() {
        let simulation = SkirmishSimulation(seed: Self.seed)
        var contactTick: UInt64?

        for _ in 0..<9_000 {
            simulation.update(deltaTime: Self.step)
            let arrived = simulation.units.values.contains {
                $0.faction == .gravemark
                    && $0.kind.isMilitary
                    && simulation.map.region(at: $0.position) == .sunwovenHome
            }
            if arrived { contactTick = simulation.tick; break }
        }

        guard let contactTick else {
            return XCTFail("No Gravemark soldier ever set foot on the Sunwoven home fragment.")
        }
        XCTAssertGreaterThanOrEqual(contactTick, 4_200, "Arrival before 3:30 is earlier than the bar allows.")
        XCTAssertLessThanOrEqual(
            contactTick, 5_400,
            "First contact at tick \(contactTick) (\(contactTick / 20)s) is past the 4:30 bar."
        )
    }

    /// **The CP-C2′ bar, in the simulation.** Combat had 39 passing tests and had
    /// never once happened in a running match, because nothing ever walked into
    /// anything. It must now happen with no player input at all.
    func testTheWaveDrawsBloodWithoutAnyPlayerInput() {
        let simulation = SkirmishSimulation(seed: Self.seed)
        var damageTick: UInt64?
        var deathTick: UInt64?
        var sunwoven = simulation.units.values.filter { $0.faction == .sunwoven }.count

        for _ in 0..<7_200 {
            simulation.update(deltaTime: Self.step)

            if damageTick == nil,
               simulation.units.values.contains(where: { $0.life < $0.kind.maxLife - 0.001 })
            {
                damageTick = simulation.tick
            }
            let now = simulation.units.values.filter { $0.faction == .sunwoven }.count
            if now < sunwoven, deathTick == nil { deathTick = simulation.tick }
            sunwoven = now

            if damageTick != nil, deathTick != nil { break }
        }

        XCTAssertNotNil(damageTick, "Nothing was ever hit — combat is still unobserved in play.")
        XCTAssertNotNil(deathTick, "Nothing ever died — combat is still unobserved in play.")
        if let damageTick, let deathTick {
            XCTAssertLessThanOrEqual(damageTick, 5_700, "First blood at \(damageTick / 20)s is too late.")
            XCTAssertLessThanOrEqual(deathTick, 6_000, "First death at \(deathTick / 20)s is too late.")
        }
    }

    // MARK: - The ledger

    /// **The adversary is granted nothing.** Half of that is structural —
    /// `Adversary.plan` takes `stock` by value and cannot write to a pool — and
    /// this is the other half: its Matter balance must close against what its own
    /// deposits and the shared trickle produced, minus what it was charged.
    func testTheAdversaryMatterLedgerCloses() {
        let ticks = 4_000
        let simulation = run(ticks: ticks)
        let tuning = SkirmishTuning.baseline

        let dug = simulation.deposits.values
            .filter { $0.kind == .matter && $0.region == .gravemarkHome }
            .reduce(0.0) { $0 + (420 - max(0, $1.remaining)) }
        let inTransit = simulation.units.values
            .filter { $0.faction == .gravemark }
            .reduce(0.0) { total, unit in
                guard let cargo = unit.cargo, cargo.kind == .matter else { return total }
                return total + cargo.amount
            }
        let trickle = tuning.coreTrickle.matter * (Double(ticks) * tuning.stepDuration)
        let income = tuning.startingResources.matter + trickle + dug - inTransit

        var spent = 0.0
        for building in simulation.buildings.values where building.faction == .gravemark {
            spent += tuning.cost(for: building.kind).matter
        }
        let starting: [UnitKind: Int] = [.citizen: tuning.startingCitizens, .lightTransport: 1]
        var produced: [UnitKind: Int] = [:]
        for unit in simulation.units.values where unit.faction == .gravemark {
            produced[unit.kind, default: 0] += 1
        }
        for (kind, count) in produced.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            spent += tuning.cost(for: kind).matter * Double(count - (starting[kind] ?? 0))
        }
        for buildingID in simulation.buildings.keys where simulation.building(buildingID)?.faction == .gravemark {
            for item in simulation.productionQueue(for: buildingID).items {
                spent += tuning.cost(for: item.kind).matter
            }
        }

        XCTAssertGreaterThan(spent, 0, "The adversary never spent anything to check.")
        XCTAssertEqual(
            simulation.stock(for: .gravemark).matter, income - spent, accuracy: 0.5,
            "Gravemark holds Matter its deposits, the shared trickle and its bills cannot explain."
        )
    }

    func testDisabledAdversaryDoesNothingAtAll() {
        let simulation = run(ticks: 6_000, adversaryEnabled: false)
        let buildings = simulation.buildings.values.filter { $0.faction == .gravemark }
        XCTAssertEqual(buildings.count, 1, "A frozen adversary must still own only its Core.")
        XCTAssertEqual(simulation.adversary.wavesDispatched, 0)
        XCTAssertTrue(simulation.adversary.events.isEmpty)
        XCTAssertTrue(
            simulation.units.values.allSatisfy { $0.life >= $0.kind.maxLife - 0.001 },
            "Nothing may be hurt in a match with no adversary and no player."
        )
    }

    // MARK: - Evidence

    /// Not an assertion — the wave-timing log CP-C3 owes as evidence. Printed so
    /// `swift test` output *is* the artifact rather than a hand-written table.
    func testWaveTimingLogForTheRecord() {
        let simulation = SkirmishSimulation(seed: Self.seed)
        var combat: [(tick: UInt64, text: String)] = []
        var sawDamage = false
        var sunwoven = simulation.units.values.filter { $0.faction == .sunwoven }.count
        var coreLife = simulation.buildings.values
            .first { $0.faction == .sunwoven && $0.kind == .civilizationCore }?.life ?? 0
        var coreHurt = false
        var coreLost = false

        for _ in 0..<12_000 {
            simulation.update(deltaTime: Self.step)

            if !sawDamage,
               simulation.units.values.contains(where: { $0.life < $0.kind.maxLife - 0.001 })
            {
                sawDamage = true
                combat.append((simulation.tick, "First blood — a unit is below full life"))
            }
            let now = simulation.units.values.filter { $0.faction == .sunwoven }.count
            if now < sunwoven {
                combat.append((simulation.tick, "Sunwoven unit killed (\(sunwoven) → \(now))"))
            }
            sunwoven = now

            let core = simulation.buildings.values
                .first { $0.faction == .sunwoven && $0.kind == .civilizationCore }
            if let core {
                if !coreHurt, core.life < coreLife - 0.001 {
                    coreHurt = true
                    combat.append((simulation.tick, "Sunwoven Core under attack"))
                }
                coreLife = core.life
            } else if !coreLost {
                coreLost = true
                combat.append((simulation.tick, "Sunwoven Core DESTROYED"))
            }
        }

        let timeline = (simulation.adversary.events.map { (tick: $0.tick, text: $0.text) } + combat)
            .sorted { $0.tick == $1.tick ? $0.text < $1.text : $0.tick < $1.tick }

        print("=== CP-C3 adversary timing · seed \(Self.seed) · map riverlands · NO player input ===")
        for entry in timeline {
            let seconds = Int(entry.tick / 20)
            print(String(format: "[%d:%02d] %@", seconds / 60, seconds % 60, entry.text))
        }

        let population = simulation.population(for: .gravemark)
        let stock = simulation.stock(for: .gravemark)
        let military = simulation.units.values.filter { $0.faction == .gravemark && $0.kind.isMilitary }.count
        let citizens = simulation.units.values.filter { $0.faction == .gravemark && $0.kind == .citizen }.count
        // Labelled off the clock rather than the loop bound. This read "at
        // 10:00" and "at tick 12000" until CP-C4 ended the match at 5:59, at
        // which point both captions described a tick the run never reaches —
        // and this output gets pasted into STATUS docs as evidence.
        print("=== Gravemark at \(matchClock(simulation.elapsed)) ===")
        print("population \(population.used)/\(population.cap) · \(citizens) citizens · \(military) soldiers")
        print("stock \(stock.costSummary.isEmpty ? "empty" : stock.costSummary)")
        for kind in [ResourceKind.matter, .lumen] {
            let left = simulation.deposits.values
                .filter { $0.kind == kind && $0.region == .gravemarkHome }
                .reduce(0.0) { $0 + max(0, $1.remaining) }
            print("home \(kind.displayName) left in the ground: \(Int(left))")
        }
        print("=== world hash at tick \(simulation.tick): \(String(simulation.worldHash, radix: 16)) ===")
        print("=== deferred from R1 §5 (not shipped in this roster) ===")
        for line in Adversary.deferredFromSpec { print("· \(line)") }
        XCTAssertFalse(simulation.adversary.events.isEmpty)
    }
}
