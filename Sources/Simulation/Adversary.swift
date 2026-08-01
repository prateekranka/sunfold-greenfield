import Foundation
import simd

/// The scheduled opponent — `Docs/Design/05-RESOLUTIONS-R1.md` §5 (B11).
///
/// **A schedule, not a planner.** Everything it does is a pure function of the
/// tick count and the world state, so two runs from one seed play the identical
/// match. It plays the same opening every time, which is correct for v0: a
/// legible opponent a player can learn to beat is worth more than a clever one
/// they cannot read.
///
/// **There are no random draws at all.** R1 fixed the schedule with no jitter,
/// so the `adversary` stream is tagged and reserved (`reservedStreamTag`) and
/// deliberately never drawn from — stated here so nobody later assumes it is
/// free to borrow without shifting every number below.
///
/// **It is granted nothing.** `plan` takes `stock` by value, so this type
/// *cannot* write to a resource pool: every unit it trains and every building it
/// places is charged through the same `SkirmishSimulation` entry points the
/// player uses. That is a compile-time guarantee rather than a test.
enum Adversary {

    /// Reserved and unused in v0. See the type comment.
    static let reservedStreamTag = "adversary"

    // MARK: - Schedule

    enum Schedule {
        /// Formation Yard is committed at 2:00 exactly, per R1 §5.
        static let formationYardTick: UInt64 = 2400
        /// A **second** Yard at 4:00, standing in for R1's "Lumen Spire at tick
        /// 4800" row.
        ///
        /// That row exists to open a second production line, and the measured
        /// consequence of skipping it is not cosmetic: one Yard produces about
        /// seven units in the 90 s between waves, so wave 5 came out *smaller*
        /// than wave 4 and the table stopped rising. The Spire itself cannot be
        /// built — `BuildingKind` has no case for it — so the schedule keeps the
        /// slot and spends it on the production building that does exist.
        static let secondYardTick: UInt64 = 4800
        static let maxFormationYards = 2
        /// Citizens are trained continuously up to this count.
        static let citizenTarget = 12
        /// Wave 1 leaves at 4:00; every wave after it 90 s later.
        static let firstWaveTick: UInt64 = 4800
        static let waveIntervalTicks: UInt64 = 1800
        /// Population headroom below which another Dwelling is committed.
        static let dwellingHeadroom = 2
        /// A ceiling on Dwellings, and a measured one rather than a guess.
        ///
        /// Housing competes directly with the army it houses: home Matter is
        /// finite (two 420-unit deposits, ~960 with the trickle), a Dwelling is
        /// 80 of it and a Vanguard 20. Four Dwellings is a cap of 42 against a
        /// ten-minute affordable army of roughly 21 soldiers and 12 citizens —
        /// so the population is never the wall and never eats the army either.
        /// At three the adversary jammed at 34/34 and dispatched wave 5 empty
        /// with 340 Matter still in the bank.
        static let maxDwellings = 4
        /// How many items a queue is kept topped up to. Two keeps production
        /// continuous without locking resources up in a long queue.
        static let queueDepth = 2

        static func dispatchTick(ofWave index: Int) -> UInt64 {
            firstWaveTick &+ UInt64(max(0, index - 1)) &* waveIntervalTicks
        }
    }

    /// One line of a wave's composition.
    struct WaveSlot: Sendable, Equatable {
        let kind: UnitKind
        let count: Int

        init(_ kind: UnitKind, _ count: Int) {
            self.kind = kind
            self.count = count
        }
    }

    /// R1 §5's wave table, expressed in the roster this build actually has.
    ///
    /// Three cells of that table name units that do not exist here: the Lancer
    /// (waves 3 and 4) and the Bastion Walker (wave 4). `UnitKind` has no
    /// `.lancer` case at all, and nothing trains `.bastionWalker` — it has no
    /// cost and no build time. Directive 3 forbids inventing either in Swift, so
    /// they are **dropped, not substituted**: waves 3 and 4 field fewer units
    /// than the table says, the omission is named in `deferredFromSpec`, and the
    /// wave that finally fields a Lancer will be a visible change rather than a
    /// silent one. Waves still escalate 3 → 6 → 7 → 9 → 11 …
    static func composition(ofWave index: Int) -> [WaveSlot] {
        switch index {
        case ..<1: []
        case 1: [WaveSlot(.vanguard, 3)]
        case 2: [WaveSlot(.vanguard, 4), WaveSlot(.ranged, 2)]
        case 3: [WaveSlot(.vanguard, 4), WaveSlot(.ranged, 3)]
        case 4: [WaveSlot(.vanguard, 5), WaveSlot(.ranged, 4)]
        default:
            // R1: every wave after the fourth is the previous one plus a
            // Vanguard and a Quarrel.
            [WaveSlot(.vanguard, 5 + (index - 4)), WaveSlot(.ranged, 4 + (index - 4))]
        }
    }

    /// Rows of R1 §5 this build cannot honour yet, recorded rather than fudged.
    static let deferredFromSpec: [String] = [
        "wave 3 · 2 Lancer — `UnitKind` has no `.lancer` case (CP-C5)",
        "wave 4 · 2 Lancer, 1 Bastion Walker — no `.lancer`; nothing trains `.bastionWalker` (CP-C5)",
        "tick 4800 · Lumen Spire — `BuildingKind` has no `.lumenSpire` case (CP-C5)",
        "tick 7200 · Dawn Loom, then Voyager when affordable — the building exists but the "
            + "research does not, so committing 130 Matter to it would only starve the waves (CP-C6)",
        "tick 9600 · Stride Yard — `BuildingKind` has no `.strideYard` case (CP-C7)",
    ]

    // MARK: - Intents

    /// What the adversary wants done this tick. The simulation executes these
    /// through the same order entry points the player's taps reach, so the
    /// adversary can never take a shortcut the player does not have.
    enum Intent: Sendable, Equatable {
        case gather(unit: EntityID, deposit: EntityID)
        case train(UnitKind, at: EntityID)
        case build(BuildingKind, at: WorldPoint)
        case march(unit: EntityID, to: WorldPoint)
        case setStance(unit: EntityID, to: CombatStance)
    }

    // MARK: - Planning

    struct Inputs {
        var tick: UInt64
        var units: [EntityID: Unit]
        var buildings: [EntityID: Building]
        var deposits: [EntityID: Deposit]
        var queues: [EntityID: ProductionQueue]
        var stock: [Faction: ResourcePool]
        var map: WorldMap
        var tuning: SkirmishTuning
    }

    static func plan(_ input: Inputs, state: inout AdversaryState) -> [Intent] {
        guard state.isEnabled else { return [] }

        var intents: [Intent] = []
        let faction = state.faction

        intents += planGathering(input, faction: faction)
        intents += planPopulation(input, faction: faction, state: &state)
        intents += planFormationYard(input, faction: faction, state: &state)
        intents += planCitizens(input, faction: faction)
        intents += planArmy(input, faction: faction, state: state)
        intents += planWaves(input, faction: faction, state: &state)

        return intents
    }

    // MARK: - Economy

    /// Puts every unassigned citizen on a node.
    ///
    /// The mix is a quota, not a preference: Provisions pays for citizens and
    /// Vanguards, Matter for buildings, Lumen for Quarrels, and an adversary
    /// that lets any one of the three run dry stops producing waves. Choosing by
    /// "which kind is furthest below its share" is a pure function of the
    /// current assignment counts, so it replays exactly.
    private static func planGathering(_ input: Inputs, faction: Faction) -> [Intent] {
        let home = homeRegion(of: faction)
        var assignedByKind: [ResourceKind: Int] = [:]
        var idle: [EntityID] = []

        for id in input.units.keys.sorted(by: { $0.raw < $1.raw }) {
            guard let unit = input.units[id], unit.faction == faction, unit.kind.canGather else { continue }
            guard !unit.isAboard, !unit.isBoarding else { continue }
            if case .constructing = unit.activity { continue }

            if let assignment = unit.assignment,
               let deposit = input.deposits[assignment],
               !deposit.isExhausted
            {
                assignedByKind[deposit.kind, default: 0] += 1
                continue
            }
            guard unit.cargo == nil else { continue }  // Let a full citizen walk its load home first.
            idle.append(id)
        }

        guard !idle.isEmpty else { return [] }

        var intents: [Intent] = []
        for id in idle {
            guard let unit = input.units[id] else { continue }
            guard let kind = neediestResource(assigned: assignedByKind, input: input, region: home) else { continue }
            guard let deposit = nearestDeposit(
                of: kind, to: unit.position, in: home, deposits: input.deposits
            ) else { continue }
            assignedByKind[kind, default: 0] += 1
            intents.append(.gather(unit: id, deposit: deposit))
        }
        return intents
    }

    /// Share of the workforce each resource should carry.
    ///
    /// Provisions gets half because it is the only renewable one and the largest
    /// sink (every Citizen and every Vanguard). Matter and Lumen split the rest:
    /// both are finite on the home fragment — 840 and 300 — so putting more
    /// bodies on them does not raise the ceiling, it only reaches it sooner.
    /// When a kind runs out, `neediestResource` stops offering it and the whole
    /// workforce falls back to what is left.
    private static let gatherQuota: [(kind: ResourceKind, share: Double)] = [
        (.provisions, 0.50),
        (.matter, 0.25),
        (.lumen, 0.25),
    ]

    private static func neediestResource(
        assigned: [ResourceKind: Int],
        input: Inputs,
        region: RegionID
    ) -> ResourceKind? {
        let total = gatherQuota.reduce(0) { $0 + (assigned[$1.kind] ?? 0) } + 1
        var best: (kind: ResourceKind, deficit: Double)?

        for entry in gatherQuota {
            // A kind with nothing left to dig cannot be the neediest.
            guard input.deposits.values.contains(where: {
                $0.kind == entry.kind && $0.region == region && !$0.isExhausted
            }) else { continue }

            let deficit = entry.share * Double(total) - Double(assigned[entry.kind] ?? 0)
            if let current = best {
                // Ties resolve by declaration order, which `gatherQuota` fixes.
                if deficit > current.deficit { best = (entry.kind, deficit) }
            } else {
                best = (entry.kind, deficit)
            }
        }
        return best?.kind
    }

    private static func nearestDeposit(
        of kind: ResourceKind,
        to origin: WorldPoint,
        in region: RegionID,
        deposits: [EntityID: Deposit]
    ) -> EntityID? {
        var best: (id: EntityID, distance: Float)?
        for (id, deposit) in deposits
        where deposit.kind == kind && deposit.region == region && !deposit.isExhausted {
            let distance = simd_distance(deposit.position, origin)
            if let current = best {
                if distance < current.distance || (distance == current.distance && id.raw < current.id.raw) {
                    best = (id, distance)
                }
            } else {
                best = (id, distance)
            }
        }
        return best?.id
    }

    /// Commits a Dwelling when the population is about to jam.
    ///
    /// R1's economy schedule does not mention housing, which is a hole in it: a
    /// cap of 10 cannot hold twelve citizens, let alone twelve and an army. This
    /// is the smallest rule that closes it, and it is still world state — not a
    /// plan.
    private static func planPopulation(
        _ input: Inputs,
        faction: Faction,
        state: inout AdversaryState
    ) -> [Intent] {
        let dwellings = input.buildings.values.filter { $0.faction == faction && $0.kind == .dwelling }
        guard dwellings.count < Schedule.maxDwellings else { return [] }
        // One at a time: two foundations at once split the builders and neither lands.
        guard !dwellings.contains(where: { !$0.isComplete }) else { return [] }

        let population = ProductionSystem.populationCommitment(
            faction: faction,
            units: input.units,
            queues: input.queues,
            buildings: input.buildings,
            tuning: input.tuning
        )
        guard population.cap - population.used <= Schedule.dwellingHeadroom else { return [] }

        let cost = input.tuning.cost(for: .dwelling)
        guard (input.stock[faction] ?? .zero).covers(cost) else { return [] }
        guard let point = site(for: .dwelling, faction: faction, input: input) else { return [] }

        state.record(input.tick, "Dwelling committed (population \(population.used)/\(population.cap))")
        return [.build(.dwelling, at: point)]
    }

    /// The Formation Yard at tick 2400 exactly, per R1 §5, and a second at 4800.
    /// If either cannot be afforded on its tick it is committed on the first
    /// tick it can be — deferring is honest, silently skipping the army is not.
    private static func planFormationYard(
        _ input: Inputs,
        faction: Faction,
        state: inout AdversaryState
    ) -> [Intent] {
        let yards = input.buildings.values.filter {
            $0.faction == faction && $0.kind == .formationYard
        }
        guard yards.count < Schedule.maxFormationYards else { return [] }
        // One foundation at a time: two at once splits the builders between them.
        guard !yards.contains(where: { !$0.isComplete }) else { return [] }

        let due: UInt64 = yards.isEmpty ? Schedule.formationYardTick : Schedule.secondYardTick
        guard input.tick >= due else { return [] }

        let cost = input.tuning.cost(for: .formationYard)
        guard (input.stock[faction] ?? .zero).covers(cost) else { return [] }
        guard let point = site(for: .formationYard, faction: faction, input: input) else { return [] }

        state.record(input.tick, "Formation Yard \(yards.count + 1) committed")
        return [.build(.formationYard, at: point)]
    }

    /// Trains Citizens continuously to twelve.
    private static func planCitizens(_ input: Inputs, faction: Faction) -> [Intent] {
        guard let core = building(of: faction, kind: .civilizationCore, in: input.buildings) else { return [] }
        let queue = input.queues[core] ?? ProductionQueue()
        guard queue.count < Schedule.queueDepth else { return [] }

        let live = input.units.values.filter { $0.faction == faction && $0.kind == .citizen }.count
        let queued = queuedCount(of: .citizen, faction: faction, input: input)
        guard live + queued < Schedule.citizenTarget else { return [] }

        guard (input.stock[faction] ?? .zero).covers(input.tuning.cost(for: .citizen)) else { return [] }
        let population = ProductionSystem.populationCommitment(
            faction: faction,
            units: input.units,
            queues: input.queues,
            buildings: input.buildings,
            tuning: input.tuning
        )
        guard population.used + UnitKind.citizen.populationCost <= population.cap else { return [] }

        return [.train(.citizen, at: core)]
    }

    /// Trains toward the *next* wave's composition and stops there.
    ///
    /// There is no per-wave enqueue bookkeeping: the target is "what the next
    /// wave asks for, minus what is already standing at home or in the queue",
    /// which retries by itself when a tick could not afford it and needs no
    /// state to survive a save or a replay.
    private static func planArmy(
        _ input: Inputs,
        faction: Faction,
        state: AdversaryState
    ) -> [Intent] {
        // Shortest queue first, so two Yards actually double throughput instead
        // of one taking every order. Ties resolve by ID, never by dictionary order.
        //
        // Built in annotated steps rather than one chain: the type checker gives
        // up on the fused version with `failed to type-check in reasonable time`,
        // which is the same cliff CP-05 hit in `CommandGrid`.
        var yards: [(id: EntityID, depth: Int)] = []
        for building in input.buildings.values
        where building.faction == faction && building.kind == .formationYard && building.isComplete {
            let depth: Int = (input.queues[building.id] ?? ProductionQueue()).count
            yards.append((id: building.id, depth: depth))
        }
        yards.sort { $0.depth == $1.depth ? $0.id.raw < $1.id.raw : $0.depth < $1.depth }

        guard let shortest = yards.first, shortest.depth < Schedule.queueDepth else { return [] }
        let yard = shortest.id

        let nextWave = state.wavesDispatched + 1
        var reserve: [UnitKind: Int] = [:]
        for (id, unit) in input.units
        where unit.faction == faction && unit.kind.isMilitary && state.waveOf[id] == nil {
            reserve[unit.kind, default: 0] += 1
        }
        for (buildingID, buildingQueue) in input.queues {
            guard input.buildings[buildingID]?.faction == faction else { continue }
            for item in buildingQueue.items where item.kind.isMilitary {
                reserve[item.kind, default: 0] += 1
            }
        }

        let population = ProductionSystem.populationCommitment(
            faction: faction,
            units: input.units,
            queues: input.queues,
            buildings: input.buildings,
            tuning: input.tuning
        )
        let pool = input.stock[faction] ?? .zero

        for slot in composition(ofWave: nextWave) {
            guard (reserve[slot.kind] ?? 0) < slot.count else { continue }
            guard input.buildings[yard]?.kind.trains.contains(slot.kind) == true else { continue }
            guard pool.covers(input.tuning.cost(for: slot.kind)) else { continue }
            guard population.used + slot.kind.populationCost <= population.cap else { continue }
            return [.train(slot.kind, at: yard)]
        }
        return []
    }

    // MARK: - Waves

    private static func planWaves(
        _ input: Inputs,
        faction: Faction,
        state: inout AdversaryState
    ) -> [Intent] {
        var intents: [Intent] = []

        // Dispatch, at the tick the table names.
        let nextWave = state.wavesDispatched + 1
        if input.tick >= Schedule.dispatchTick(ofWave: nextWave) {
            let ready = input.units.keys
                .filter { id in
                    guard let unit = input.units[id] else { return false }
                    return unit.faction == faction
                        && unit.kind.isMilitary
                        && state.waveOf[id] == nil
                        && !unit.isAboard
                }
                .sorted { $0.raw < $1.raw }

            let objective = target(forWave: nextWave, against: faction.opponent, input: input)
            for id in ready {
                state.waveOf[id] = nextWave
                intents.append(.setStance(unit: id, to: .aggressive))
            }
            state.waveTarget[nextWave] = objective
            state.wavesDispatched = nextWave

            let roster = ready.compactMap { input.units[$0]?.kind.displayName }
                .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
                .sorted { $0.key < $1.key }
                .map { "\($0.value) \($0.key)" }
                .joined(separator: ", ")
            state.record(
                input.tick,
                ready.isEmpty
                    ? "Wave \(nextWave) dispatched EMPTY — nothing was trained in time"
                    : "Wave \(nextWave) dispatched: \(roster) → \(describe(objective, input: input))"
            )
        }

        // March, every tick, for everything already committed.
        let enemyHome = homeRegion(of: faction.opponent)
        for id in state.waveOf.keys.sorted(by: { $0.raw < $1.raw }) {
            guard let waveIndex = state.waveOf[id] else { continue }
            guard let unit = input.units[id], !unit.isDead else { continue }

            // The moment a wave sets foot on the player's fragment is the one
            // the player experiences as "the attack", and it is what CP-C3's
            // arrival bar is measured against — not the tick it left home.
            if !state.wavesArrived.contains(waveIndex),
               input.map.region(at: unit.position) == enemyHome
            {
                state.wavesArrived.insert(waveIndex)
                state.record(input.tick, "Wave \(waveIndex) ARRIVED on \(faction.opponent.displayName) home ground")
            }
            // Combat owns a unit that has something to hit.
            guard unit.attackTarget == nil else { continue }

            var objective = state.waveTarget[waveIndex] ?? nil
            if objective == nil || input.buildings[objective!]?.isComplete != true {
                // R1: retarget by the same rule, evaluated once on target death.
                objective = target(forWave: waveIndex, against: faction.opponent, input: input)
                state.waveTarget[waveIndex] = objective
                if let objective {
                    state.record(input.tick, "Wave \(waveIndex) retargeted → \(describe(objective, input: input))")
                }
            }
            guard let objective, let destination = input.buildings[objective]?.position else { continue }

            guard unit.destination == nil else { continue }
            intents.append(.march(unit: id, to: waypoint(for: unit, toward: destination, input: input)))
        }

        return intents
    }

    /// Two legs, not one. `MovementSystem` slides along a coast rather than
    /// pathfinding around it, and the only route the map guarantees between two
    /// homes is the contiguous spine through the Dominion. A wave therefore
    /// walks to the Dominion centre first and only then at its objective, which
    /// is also how a player would read it: they come down the middle.
    static func waypoint(for unit: Unit, toward objective: WorldPoint, input: Inputs) -> WorldPoint {
        let home = input.map.fragment(homeRegion(of: unit.faction)).center
        let dominion = input.map.fragment(.dominion).center

        let axis = objective - home
        let length = simd_length(axis)
        guard length > 0.001 else { return objective }
        let heading = axis / length

        let progress = simd_dot(unit.position - home, heading)
        let handoff = simd_dot(dominion - home, heading)
        return progress < handoff ? dominion : objective
    }

    /// R1 §5's target column.
    static func target(
        forWave index: Int,
        against enemy: Faction,
        input: Inputs
    ) -> EntityID? {
        let core = input.map.fragment(homeRegion(of: enemy.opponent)).center

        func nearestToCore() -> EntityID? {
            var best: (id: EntityID, distance: Float)?
            for (id, building) in input.buildings
            where building.faction == enemy && building.isComplete && !building.isDead {
                let distance = simd_distance(building.position, core)
                if let current = best {
                    if distance < current.distance || (distance == current.distance && id.raw < current.id.raw) {
                        best = (id, distance)
                    }
                } else {
                    best = (id, distance)
                }
            }
            return best?.id
        }

        switch index {
        case 3:
            // Newest Expansion Outpost, else the nearest building.
            let outposts = input.buildings.values
                .filter { $0.faction == enemy && $0.kind == .expansionOutpost && $0.isComplete }
                .sorted { $0.id.raw < $1.id.raw }
            return outposts.last?.id ?? nearestToCore()
        case 4...:
            let enemyCore = input.buildings.values
                .filter { $0.faction == enemy && $0.kind == .civilizationCore && $0.isComplete }
                .sorted { $0.id.raw < $1.id.raw }
            return enemyCore.first?.id ?? nearestToCore()
        default:
            return nearestToCore()
        }
    }

    // MARK: - Placement

    /// A deterministic ring search for somewhere to stand a building.
    ///
    /// `ConstructionPlacement.isLegal` cannot be used here: it is hardcoded to
    /// `.sunwovenHome` and to three placeable kinds, which R1 §7 already records
    /// as real work owed. Rather than widen the player's placement path from
    /// inside this checkpoint, the adversary carries its own footprint test,
    /// which is the same three questions — on land, clear of buildings, clear of
    /// deposits — asked about its own fragment.
    static func site(for kind: BuildingKind, faction: Faction, input: Inputs) -> WorldPoint? {
        let region = homeRegion(of: faction)
        guard let core = input.buildings.values.first(where: {
            $0.faction == faction && $0.kind == .civilizationCore
        }) else { return nil }

        let radius = kind.footprintRadius
        let clearance: Float = 0.75
        let bearings = 12

        for ring in 1...6 {
            let distance = core.kind.footprintRadius + radius + 3 + Float(ring) * 4
            for slot in 0..<bearings {
                // Offset by half a step on odd rings so successive rings do not
                // all test the same twelve bearings.
                let turn = Float(slot) + (ring % 2 == 0 ? 0.5 : 0)
                let angle = turn / Float(bearings) * 2 * .pi
                let candidate = core.position + WorldPoint(sin(angle), cos(angle)) * distance

                guard input.map.isStandable(candidate, in: region, margin: radius + clearance) else { continue }
                guard !input.buildings.values.contains(where: {
                    simd_distance($0.position, candidate) < $0.kind.footprintRadius + radius + clearance
                }) else { continue }
                guard !input.deposits.values.contains(where: {
                    simd_distance($0.position, candidate) < Deposit.workRadius + radius + clearance
                }) else { continue }
                return candidate
            }
        }
        return nil
    }

    // MARK: - Helpers

    static func homeRegion(of faction: Faction) -> RegionID {
        faction == .sunwoven ? .sunwovenHome : .gravemarkHome
    }

    private static func building(
        of faction: Faction,
        kind: BuildingKind,
        in buildings: [EntityID: Building],
        completeOnly: Bool = false
    ) -> EntityID? {
        buildings.values
            .filter { $0.faction == faction && $0.kind == kind && (!completeOnly || $0.isComplete) }
            .min { $0.id.raw < $1.id.raw }?
            .id
    }

    private static func queuedCount(of kind: UnitKind, faction: Faction, input: Inputs) -> Int {
        var total = 0
        for (buildingID, queue) in input.queues {
            guard input.buildings[buildingID]?.faction == faction else { continue }
            total += queue.items.filter { $0.kind == kind }.count
        }
        return total
    }

    private static func describe(_ id: EntityID?, input: Inputs) -> String {
        guard let id, let building = input.buildings[id] else { return "no target" }
        let owner = building.faction?.displayName ?? "Neutral"
        return "\(owner) \(building.kind.displayName) #\(id.raw)"
    }
}

/// Everything the adversary remembers between ticks.
///
/// It lives on the simulation rather than in a singleton because it decides
/// outcomes, and anything that decides outcomes has to replay with the rest of
/// the world.
struct AdversaryState: Sendable, Equatable {
    var faction: Faction = .gravemark
    var isEnabled: Bool = true

    /// How many waves have left. The next wave is always this plus one.
    var wavesDispatched: Int = 0
    /// Which wave a unit marches with. A unit never changes wave and never
    /// retreats, per R1 §5.
    var waveOf: [EntityID: Int] = [:]
    /// The current objective of each dispatched wave.
    var waveTarget: [Int: EntityID?] = [:]
    /// Waves that have set foot on the player's home fragment.
    var wavesArrived: Set<Int> = []

    /// A timing record, for evidence. Bounded so a long match cannot grow it
    /// without limit. Not part of `WorldHash` — it is a readout, not truth.
    private(set) var events: [AdversaryEvent] = []

    static let maxEvents = 120

    init(faction: Faction = .gravemark, isEnabled: Bool = true) {
        self.faction = faction
        self.isEnabled = isEnabled
    }

    mutating func record(_ tick: UInt64, _ text: String) {
        events.append(AdversaryEvent(tick: tick, text: text))
        if events.count > Self.maxEvents { events.removeFirst(events.count - Self.maxEvents) }
    }

    /// Drops units that are no longer alive, so `waveOf` cannot grow forever.
    mutating func forget(_ ids: Set<EntityID>) {
        guard !ids.isEmpty else { return }
        for id in ids { waveOf[id] = nil }
    }
}

struct AdversaryEvent: Sendable, Equatable {
    let tick: UInt64
    let text: String

    /// `4:00` from tick 4800, at the fixed 20 Hz step.
    var timestamp: String {
        let seconds = Int(tick / 20)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    var line: String { "[\(timestamp)] \(text)" }
}
