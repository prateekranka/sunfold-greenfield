import Foundation
import simd

/// Decides when a match is over.
///
/// Spec: `00-CONTENT-SPEC.md` §5, overridden where they disagree by
/// `05-RESOLUTIONS-R1.md` §3 (B10). Two win paths — Conquest and Dominion — and
/// no draw state, no hard match timer.
///
/// Pure and deterministic like every other system here: it reads world state and
/// a delta, and returns the same answer for the same inputs every time. It never
/// moves a unit or spends a resource; the only thing it can do is end the match.
enum VictorySystem {

    // MARK: - Inputs

    struct Inputs: Sendable {
        let elapsed: Double
        let tick: UInt64
        let units: [EntityID: Unit]
        let buildings: [EntityID: Building]
        let tuning: SkirmishTuning
        let deltaTime: Double
        let playerFaction: Faction

        init(
            elapsed: Double,
            tick: UInt64,
            units: [EntityID: Unit],
            buildings: [EntityID: Building],
            tuning: SkirmishTuning,
            deltaTime: Double,
            playerFaction: Faction = .sunwoven
        ) {
            self.elapsed = elapsed
            self.tick = tick
            self.units = units
            self.buildings = buildings
            self.tuning = tuning
            self.deltaTime = deltaTime
            self.playerFaction = playerFaction
        }
    }

    // MARK: - Step

    /// Advances the Dominion timers and tests both win conditions.
    ///
    /// Order is fixed and documented because two conditions can come true on the
    /// same tick: Conquest is judged first, then Dominion, each in
    /// `Faction.allCases` order. A coin flip here would be a determinism hole.
    static func step(state: inout VictoryState, input: Inputs) {
        guard state.outcome == nil else { return }

        state.noteContenders(in: input.buildings)
        stepDominion(state: &state, input: input)
        noteCorePressure(state: &state, input: input)

        if let outcome = conquest(state: state, input: input) {
            state.finish(outcome, playerFaction: input.playerFaction)
            return
        }
        if let outcome = dominion(state: state, input: input) {
            state.finish(outcome, playerFaction: input.playerFaction)
        }
    }

    // MARK: - Conquest

    /// A contender whose Civilization Core is gone has lost.
    ///
    /// Judged only for factions that *had* a Core, so a hand-built test world
    /// without one does not resolve on its first tick.
    private static func conquest(state: VictoryState, input: Inputs) -> MatchOutcome? {
        for faction in Faction.allCases where state.contenders.contains(faction) {
            guard !hasLivingCore(faction, in: input.buildings) else { continue }
            return MatchOutcome(
                winner: faction.opponent,
                path: .conquest,
                elapsed: input.elapsed,
                tick: input.tick
            )
        }
        return nil
    }

    static func hasLivingCore(_ faction: Faction, in buildings: [EntityID: Building]) -> Bool {
        buildings.values.contains {
            $0.faction == faction && $0.kind == .civilizationCore && !$0.isDead
        }
    }

    /// Life fraction of a faction's Core, or 0 once it is gone. Drives the
    /// structural-calamity beats and the HUD readout.
    static func coreLifeFraction(_ faction: Faction, in buildings: [EntityID: Building]) -> Double {
        let cores = buildings.values.filter {
            $0.faction == faction && $0.kind == .civilizationCore && !$0.isDead
        }
        guard let core = cores.min(by: { $0.id.raw < $1.id.raw }) else { return 0 }
        return max(0, min(1, core.life / core.kind.maxLife))
    }

    // MARK: - Dominion

    private static func dominion(state: VictoryState, input: Inputs) -> MatchOutcome? {
        let requirement = input.tuning.dominionHoldRequirement(atElapsed: input.elapsed)
        for faction in Faction.allCases where state.hold(faction) >= requirement {
            return MatchOutcome(
                winner: faction,
                path: .dominion,
                elapsed: input.elapsed,
                tick: input.tick
            )
        }
        return nil
    }

    /// Fills, drains and resets each faction's hold timer.
    ///
    /// The three rules, in the order they apply:
    ///
    /// 1. **Contested drains.** Any enemy capturer in the ring pulls the holder's
    ///    timer down at half the fill rate, whether or not the holder is also
    ///    standing there. Mutual occupation therefore always resolves — it turns
    ///    the ring into a fight rather than a stalemate.
    /// 2. **Uncontested fills**, capped at the hold currently required, so the
    ///    HUD bar never reads past full and the escalation cannot be banked.
    /// 3. **An empty ring resets** after `dominionVacancyReset` seconds. Walking
    ///    away for a moment costs nothing; leaving costs everything.
    private static func stepDominion(state: inout VictoryState, input: Inputs) {
        guard let spire = spire(in: input.buildings) else {
            state.spireID = nil
            return
        }
        state.spireID = spire.id
        state.spirePosition = spire.position

        let radius = input.tuning.dominionCaptureRadius
        var occupancy: [Faction: Int] = [:]
        for unit in input.units.values where canHold(unit) {
            guard simd_distance(unit.position, spire.position) <= radius else { continue }
            occupancy[unit.faction, default: 0] += 1
        }
        state.occupancy = occupancy

        let requirement = input.tuning.dominionHoldRequirement(atElapsed: input.elapsed)
        let dt = input.deltaTime

        for faction in Faction.allCases {
            let mine = occupancy[faction] ?? 0
            let theirs = occupancy[faction.opponent] ?? 0
            let before = state.hold(faction)

            if theirs > 0 {
                state.setHold(faction, max(0, before - dt * input.tuning.dominionContestDecay))
                if mine > 0 {
                    state.noteContested(
                        faction,
                        tick: input.tick,
                        elapsed: input.elapsed,
                        playerFaction: input.playerFaction
                    )
                }
            } else {
                state.clearContestNotice(faction)
                if mine > 0 { state.setHold(faction, min(requirement, before + dt)) }
            }

            if mine > 0 {
                state.setVacancy(faction, 0)
            } else {
                let vacant = state.vacancy(faction) + dt
                state.setVacancy(faction, vacant)
                if vacant >= input.tuning.dominionVacancyReset && state.hold(faction) > 0 {
                    state.setHold(faction, 0)
                    state.abandonDominion(
                        faction,
                        tick: input.tick,
                        elapsed: input.elapsed,
                        playerFaction: input.playerFaction
                    )
                }
            }

            noteMilestones(
                faction,
                from: before,
                to: state.hold(faction),
                requirement: requirement,
                state: &state,
                input: input
            )
        }
    }

    /// The Spire is neutral, so it is found by kind rather than by owner.
    static func spire(in buildings: [EntityID: Building]) -> Building? {
        buildings.values
            .filter { $0.kind == .dominionSpire }
            .min { $0.id.raw < $1.id.raw }
    }

    /// Who counts as standing on the objective. A passenger riding a transport
    /// is not on the ground, so it holds nothing even while its position is
    /// inside the ring.
    static func canHold(_ unit: Unit) -> Bool {
        unit.kind.canCaptureDominion && !unit.isDead && !unit.isAboard
    }

    // MARK: - Alerts

    private static func noteMilestones(
        _ faction: Faction,
        from before: Double,
        to after: Double,
        requirement: Double,
        state: inout VictoryState,
        input: Inputs
    ) {
        guard after > before else { return }
        for milestone in input.tuning.dominionMilestones
        where milestone < requirement && before < milestone && after >= milestone {
            state.record(
                MatchEvent(
                    tick: input.tick,
                    elapsed: input.elapsed,
                    severity: faction == input.playerFaction ? .good : .bad,
                    text: "\(faction.displayName) has held the Dominion \(Int(milestone))s"
                )
            )
        }
    }

    /// Structural calamity beats at 75% / 50% / 25% of a Core's life, once each,
    /// on the way down only.
    private static func noteCorePressure(state: inout VictoryState, input: Inputs) {
        for faction in Faction.allCases where state.contenders.contains(faction) {
            let fraction = coreLifeFraction(faction, in: input.buildings)
            guard fraction > 0 else { continue }
            var fired = state.corePressureFired[faction] ?? 0
            for threshold in input.tuning.corePressureThresholds {
                guard fraction <= threshold else { continue }
                let step = (input.tuning.corePressureThresholds.firstIndex(of: threshold) ?? 0) + 1
                guard step > fired else { continue }
                fired = step
                state.record(
                    MatchEvent(
                        tick: input.tick,
                        elapsed: input.elapsed,
                severity: faction == input.playerFaction ? .bad : .good,
                        text: "\(faction.displayName) Core at \(Int(threshold * 100))%"
                    )
                )
            }
            state.corePressureFired[faction] = fired
        }
    }
}

// MARK: - State

/// Everything the victory rules remember between ticks.
///
/// Lives on `SkirmishSimulation` beside the world, not in the renderer: the HUD
/// reads which condition is close, it never decides one.
struct VictoryState: Sendable, Equatable {
    /// Seconds each faction has held the Dominion.
    private(set) var holdSeconds: [Faction: Double] = [:]
    /// Seconds each faction has had nobody in the ring.
    private(set) var vacancySeconds: [Faction: Double] = [:]
    /// Capturing units in the ring at the last step, per faction. HUD readout.
    var occupancy: [Faction: Int] = [:]
    /// How many core-pressure beats have fired for each faction.
    var corePressureFired: [Faction: Int] = [:]
    /// Factions that owned a Civilization Core when the match began. Only these
    /// can lose by Conquest.
    private(set) var contenders: Set<Faction> = []
    private(set) var outcome: MatchOutcome?

    var spireID: EntityID?
    var spirePosition: WorldPoint = .zero

    /// Rolling alert feed for the HUD. Newest last, oldest dropped.
    private(set) var events: [MatchEvent] = []
    static let maxEvents = 40

    /// Guards the one-shot "contested" alert so a fight in the ring does not
    /// print a line every tick.
    private var contestAnnounced: Set<Faction> = []

    init() {}

    func hold(_ faction: Faction) -> Double { holdSeconds[faction] ?? 0 }
    func vacancy(_ faction: Faction) -> Double { vacancySeconds[faction] ?? 0 }
    func occupants(_ faction: Faction) -> Int { occupancy[faction] ?? 0 }

    /// True when an enemy capturer is standing in the ring draining this
    /// faction's progress.
    func isContested(for faction: Faction) -> Bool { occupants(faction.opponent) > 0 }

    var isOver: Bool { outcome != nil }

    mutating func setHold(_ faction: Faction, _ value: Double) { holdSeconds[faction] = value }
    mutating func setVacancy(_ faction: Faction, _ value: Double) { vacancySeconds[faction] = value }

    mutating func noteContenders(in buildings: [EntityID: Building]) {
        guard contenders.isEmpty else { return }
        for faction in Faction.allCases
        where VictorySystem.hasLivingCore(faction, in: buildings) {
            contenders.insert(faction)
        }
    }

    mutating func noteContested(
        _ faction: Faction,
        tick: UInt64,
        elapsed: Double,
        playerFaction: Faction
    ) {
        guard faction == playerFaction, !contestAnnounced.contains(faction) else { return }
        contestAnnounced.insert(faction)
        record(
            MatchEvent(
                tick: tick,
                elapsed: elapsed,
                severity: .bad,
                text: "The Dominion is contested — clear the ring"
            )
        )
    }

    /// Re-arms the contested alert once the ring is clear, so a second push is
    /// announced as loudly as the first.
    mutating func clearContestNotice(_ faction: Faction) {
        contestAnnounced.remove(faction)
    }

    mutating func abandonDominion(
        _ faction: Faction,
        tick: UInt64,
        elapsed: Double,
        playerFaction: Faction
    ) {
        contestAnnounced.remove(faction)
        guard faction == playerFaction else { return }
        record(
            MatchEvent(
                tick: tick,
                elapsed: elapsed,
                severity: .bad,
                text: "Dominion progress lost — the ring stood empty"
            )
        )
    }

    mutating func record(_ event: MatchEvent) {
        events.append(event)
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
    }

    mutating func finish(_ outcome: MatchOutcome, playerFaction: Faction = .sunwoven) {
        self.outcome = outcome
        record(
            MatchEvent(
                tick: outcome.tick,
                elapsed: outcome.elapsed,
                severity: outcome.winner == playerFaction ? .good : .bad,
                text: "\(outcome.winner.displayName) wins by \(outcome.path.rawValue.capitalized)"
            )
        )
    }

    /// Ends the match by concession. Not a third win path — the resigning side
    /// simply stops, and the overlay says so rather than reporting a Conquest
    /// that never happened.
    mutating func resign(
        _ faction: Faction,
        tick: UInt64,
        elapsed: Double,
        playerFaction: Faction = .sunwoven
    ) {
        guard outcome == nil else { return }
        finish(
            MatchOutcome(
                winner: faction.opponent,
                path: .resignation,
                elapsed: elapsed,
                tick: tick
            ),
            playerFaction: playerFaction
        )
    }
}

/// One line in the HUD's alert feed.
///
/// Deliberately **not** `Identifiable`: the obvious id would fold `text.hashValue`
/// in, and Swift's string hashing is seeded per process, which is precisely the
/// kind of value that must never get near a deterministic simulation. The HUD
/// enumerates instead.
struct MatchEvent: Sendable, Equatable {
    enum Severity: Sendable, Equatable {
        case good
        case bad
    }

    let tick: UInt64
    let elapsed: Double
    let severity: Severity
    let text: String

    var timestamp: String { matchClock(elapsed) }
    var line: String { "[\(timestamp)] \(text)" }
}
