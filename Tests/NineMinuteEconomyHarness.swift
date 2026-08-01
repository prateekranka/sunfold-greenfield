import Foundation
import simd
@testable import SunfoldCore

/// CP-C9's deterministic player and recorder.
///
/// This file is test instrumentation. It never writes simulation state directly.
/// Every player action goes through the same order methods used by the app.
@MainActor
enum NineMinuteEconomyHarness {

    enum Mode: String, CaseIterable, Equatable {
        case economyCeiling = "economy-ceiling"
        case contested
    }

    /// The CSV is intentionally numeric and stable. The file name carries the
    /// mode, seed and duration, while each row carries one ten-second world readout.
    static let csvHeader = [
        "tick",
        "match_time_seconds",
        "stock_provisions",
        "stock_matter",
        "stock_lumen",
        "stock_aether",
        "population_used",
        "population_cap",
        "completed_dwellings",
        "citizen_count",
        "pathfinder_count",
        "vanguard_count",
        "quarrel_count",
        "army_count",
        "trained_army_count",
        "idle_citizens",
        "home_provisions_remaining",
        "home_matter_remaining",
        "home_lumen_remaining",
        "home_aether_remaining",
        "useful_action_available",
    ]

    static let denialCSVHeader = [
        "start_time_seconds",
        "end_time_seconds",
        "duration_seconds",
        "denied_resources",
        "requested_action",
        "productive_action_available_for_whole_episode",
    ]

    static let outputEnvironmentVariable = "SUNFOLD_NINE_MINUTE_ECONOMY_CSV_DIR"
    static let defaultSeed: UInt64 = 20_260_726
    static let fullRunSeconds = 10.0 * 60.0
    static let sampleIntervalSeconds = 10.0
    static let firstThreeMinutesSeconds = 3.0 * 60.0

    struct Sample: Equatable {
        let tick: UInt64
        let matchTimeSeconds: Double
        let stock: ResourcePool
        let populationUsed: Int
        let populationCap: Int
        let completedDwellings: Int
        let citizenCount: Int
        let pathfinderCount: Int
        let vanguardCount: Int
        let quarrelCount: Int
        let armyCount: Int
        let trainedArmyCount: Int
        let idleCitizens: Int
        let homeYield: ResourcePool
        let usefulActionAvailable: Bool
    }

    enum RequestedAction: Equatable {
        case build(BuildingKind)
        case train(UnitKind)

        var csvValue: String {
            switch self {
            case .build(let kind): "build:\(kind.rawValue)"
            case .train(let kind): "train:\(kind.rawValue)"
            }
        }
    }

    struct Denial: Equatable {
        let resources: [ResourceKind]
        let action: RequestedAction
    }

    struct DenialEpisode: Equatable {
        let deniedResources: [ResourceKind]
        let requestedAction: RequestedAction
        let startTimeSeconds: Double
        let endTimeSeconds: Double
        let durationSeconds: Double
        let productiveActionAvailableForWholeEpisode: Bool
    }

    enum HomeResourceExhaustion: Equatable {
        case absent
        case exhausted(at: Double)
        case neverExhausted

        var report: String {
            switch self {
            case .absent:
                return "absent"
            case .exhausted(let seconds):
                return "exhausted(at: \(String(format: "%.3f", seconds)))"
            case .neverExhausted:
                return "neverExhausted"
            }
        }

        var exhaustionTime: Double? {
            guard case .exhausted(let seconds) = self else { return nil }
            return seconds
        }
    }

    struct RunResult {
        let mode: Mode
        let seed: UInt64
        let samples: [Sample]
        let outputURL: URL
        let denialOutputURL: URL
        let populationAtNineMinutes: Int?
        let populationCapAtNineMinutes: Int?
        let dwellingsAtNineMinutes: Int?
        let unitCountsAtNineMinutes: [UnitKind: Int]
        let homeResourceExhaustion: [ResourceKind: HomeResourceExhaustion]
        let homeResourceExhaustionReport: [ResourceKind: String]
        let affordabilityDelaySeconds: [ResourceKind: Double]
        let affordabilityDelayTotalSeconds: Double
        let noChoiceStallSeconds: Double
        let denialEpisodes: [DenialEpisode]
        let firstThreeMinutesUsefulAtEverySample: Bool
        let firstUsefulnessFailureAt: Double?
        let structureCommitTicks: [BuildingKind: UInt64]
        let endedAtSeconds: Double
        let reachedTenMinutes: Bool
        let worldHash: UInt64
    }

    enum HarnessError: Error, CustomStringConvertible {
        case csvWriteFailed(URL, Error)

        var description: String {
            switch self {
            case .csvWriteFailed(let url, let error):
                return "Could not write the CP-C9 CSV at \(url.path): \(error)"
            }
        }
    }

    /// Runs one deterministic opening. `maxSeconds` is injectable for the
    /// default smoke test; the CP-C9 bar uses the ten-minute default.
    static func run(
        mode: Mode,
        seed: UInt64 = defaultSeed,
        maxSeconds: Double = fullRunSeconds,
        outputURL: URL? = nil,
        outputDirectoryURL: URL? = nil
    ) throws -> RunResult {
        precondition(maxSeconds >= 0)

        let simulation = SkirmishSimulation(
            seed: seed,
            adversaryEnabled: mode == .contested
        )
        let player = ReferenceOpening(simulation: simulation)
        let recorder = Recorder(simulation: simulation)
        recorder.recordInitial(player: player)

        let targetTick = UInt64((maxSeconds * simulation.tuning.simulationHz).rounded())
        while simulation.tick < targetTick, !simulation.isOver {
            let denial = player.act()
            recorder.recordAttempt(
                denial: denial,
                player: player
            )

            // One call is exactly one fixed simulation tick. Do not replace this
            // with a larger delta or a wall-clock loop.
            simulation.update(deltaTime: simulation.tuning.stepDuration)
            recorder.recordAfterStep(player: player)
        }
        recorder.finish()

        let url = outputURL ?? resolvedOutputURL(
            mode: mode,
            seed: seed,
            maxSeconds: maxSeconds,
            outputDirectoryURL: outputDirectoryURL
        )
        let denialURL = denialOutputURL(for: url)
        do {
            try writeCSV(recorder.samples, to: url)
        } catch {
            throw HarnessError.csvWriteFailed(url, error)
        }
        do {
            try writeDenialCSV(recorder.denialEpisodes, to: denialURL)
        } catch {
            throw HarnessError.csvWriteFailed(denialURL, error)
        }

        let nineMinuteTick = UInt64(
            (9.0 * 60.0 * simulation.tuning.simulationHz).rounded()
        )
        let nineMinuteSample = recorder.samples.first { $0.tick == nineMinuteTick }
        let homeResourceExhaustion = recorder.finalizedHomeResourceExhaustion()
        let exhaustionReport = homeResourceExhaustion.reduce(into: [ResourceKind: String]()) {
            report,
            entry in
            report[entry.key] = entry.value.report
        }
        let unitCounts: [UnitKind: Int] = nineMinuteSample == nil
            ? [:]
            : UnitKind.allCases.reduce(into: [UnitKind: Int]()) { counts, kind in
                counts[kind] = simulation.units(of: .sunwoven)
                    .filter { $0.kind == kind }
                    .count
            }

        return RunResult(
            mode: mode,
            seed: seed,
            samples: recorder.samples,
            outputURL: url,
            denialOutputURL: denialURL,
            populationAtNineMinutes: nineMinuteSample?.populationUsed,
            populationCapAtNineMinutes: nineMinuteSample?.populationCap,
            dwellingsAtNineMinutes: nineMinuteSample?.completedDwellings,
            unitCountsAtNineMinutes: unitCounts,
            homeResourceExhaustion: homeResourceExhaustion,
            homeResourceExhaustionReport: exhaustionReport,
            affordabilityDelaySeconds: recorder.affordabilityDelaySeconds,
            affordabilityDelayTotalSeconds: recorder.affordabilityDelayTotalSeconds,
            noChoiceStallSeconds: recorder.noChoiceStallSeconds,
            denialEpisodes: recorder.denialEpisodes,
            firstThreeMinutesUsefulAtEverySample: recorder.firstThreeMinutesUsefulAtEverySample,
            firstUsefulnessFailureAt: recorder.firstUsefulnessFailureAt,
            structureCommitTicks: player.structureCommitTicks,
            endedAtSeconds: Double(simulation.tick) / simulation.tuning.simulationHz,
            reachedTenMinutes: simulation.tick >= targetTick,
            worldHash: simulation.worldHash
        )
    }

    // MARK: - CSV

    private static func resolvedOutputURL(
        mode: Mode,
        seed: UInt64,
        maxSeconds: Double,
        outputDirectoryURL: URL?
    ) -> URL {
        let duration = Int(maxSeconds.rounded())
        let name = "sunfold-nine-minute-economy-\(mode.rawValue)-\(seed)-\(duration)s.csv"
        let directory = outputDirectoryURL ?? ProcessInfo.processInfo.environment[
            outputEnvironmentVariable
        ].flatMap { value in
            value.isEmpty ? nil : URL(fileURLWithPath: value, isDirectory: true)
        }
        if let directory {
            return directory.appendingPathComponent(name)
        }

        // The default is always outside the repository. No Date is used, so a
        // repeated seed and mode replace one deterministic artifact.
        return FileManager.default.temporaryDirectory.appendingPathComponent(name)
    }

    private static func denialOutputURL(for sampleURL: URL) -> URL {
        let extensionSuffix = sampleURL.pathExtension.isEmpty
            ? ""
            : ".\(sampleURL.pathExtension)"
        let name = sampleURL.deletingPathExtension().lastPathComponent
            + "-denials"
            + extensionSuffix
        return sampleURL.deletingLastPathComponent().appendingPathComponent(name)
    }

    private static func writeCSV(_ samples: [Sample], to url: URL) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        var lines = [csvHeader.joined(separator: ",")]
        lines.reserveCapacity(samples.count + 1)
        for sample in samples {
            lines.append([
                String(sample.tick),
                csvNumber(sample.matchTimeSeconds),
                csvNumber(sample.stock.provisions),
                csvNumber(sample.stock.matter),
                csvNumber(sample.stock.lumen),
                csvNumber(sample.stock.aether),
                String(sample.populationUsed),
                String(sample.populationCap),
                String(sample.completedDwellings),
                String(sample.citizenCount),
                String(sample.pathfinderCount),
                String(sample.vanguardCount),
                String(sample.quarrelCount),
                String(sample.armyCount),
                String(sample.trainedArmyCount),
                String(sample.idleCitizens),
                csvNumber(sample.homeYield.provisions),
                csvNumber(sample.homeYield.matter),
                csvNumber(sample.homeYield.lumen),
                csvNumber(sample.homeYield.aether),
                sample.usefulActionAvailable ? "true" : "false",
            ].joined(separator: ","))
        }

        try (lines.joined(separator: "\n") + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func writeDenialCSV(
        _ episodes: [DenialEpisode],
        to url: URL
    ) throws {
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )

        var lines = [denialCSVHeader.joined(separator: ",")]
        lines.reserveCapacity(episodes.count + 1)
        for episode in episodes {
            lines.append([
                csvNumber(episode.startTimeSeconds),
                csvNumber(episode.endTimeSeconds),
                csvNumber(episode.durationSeconds),
                episode.deniedResources.map(\.rawValue).joined(separator: "+"),
                episode.requestedAction.csvValue,
                episode.productiveActionAvailableForWholeEpisode ? "true" : "false",
            ].joined(separator: ","))
        }

        try (lines.joined(separator: "\n") + "\n").write(
            to: url,
            atomically: true,
            encoding: .utf8
        )
    }

    private static func csvNumber(_ value: Double) -> String {
        guard value.isFinite else {
            return value.sign == .minus ? "-infinity" : "infinity"
        }
        return String(format: "%.6f", value)
    }

    // MARK: - Recorder

    @MainActor
    private final class Recorder {
        let simulation: SkirmishSimulation
        let sampleIntervalTicks: UInt64
        let firstThreeMinutesTick: UInt64
        let homeResourceKinds: Set<ResourceKind>

        var samples: [Sample] = []
        var nextSampleTick: UInt64 = 0
        var homeResourceExhaustion: [ResourceKind: HomeResourceExhaustion] = [:]
        var affordabilityDelaySeconds: [ResourceKind: Double]
        var noChoiceStallSeconds: Double = 0
        var denialEpisodes: [DenialEpisode] = []
        var firstThreeMinutesUsefulAtEverySample = true
        var firstUsefulnessFailureAt: Double?

        private struct OpenDenial {
            let deniedResources: [ResourceKind]
            let requestedAction: RequestedAction
            let startTimeSeconds: Double
            var lastTick: UInt64
            var productiveActionAvailableForWholeEpisode: Bool
        }

        private var openDenial: OpenDenial?

        init(simulation: SkirmishSimulation) {
            self.simulation = simulation
            let hz = simulation.tuning.simulationHz
            self.sampleIntervalTicks = UInt64((sampleIntervalSeconds * hz).rounded())
            self.firstThreeMinutesTick = UInt64((firstThreeMinutesSeconds * hz).rounded())
            self.homeResourceKinds = Set(
                simulation.deposits.values
                    .filter { $0.region == .sunwovenHome }
                    .map(\.kind)
            )
            self.affordabilityDelaySeconds = Dictionary(
                uniqueKeysWithValues: ResourceKind.allCases.map { ($0, 0) }
            )
        }

        func recordInitial(player: ReferenceOpening) {
            for kind in ResourceKind.allCases where !homeResourceKinds.contains(kind) {
                homeResourceExhaustion[kind] = .absent
            }
            detectExhaustion()
            recordSample(player: player)
            nextSampleTick = sampleIntervalTicks
        }

        func recordAfterStep(player: ReferenceOpening) {
            detectExhaustion()
            guard simulation.tick == nextSampleTick else { return }
            recordSample(player: player)
            nextSampleTick += sampleIntervalTicks
        }

        func recordAttempt(
            denial: Denial?,
            player: ReferenceOpening
        ) {
            guard let denial else {
                closeDenial(atTick: simulation.tick)
                return
            }

            let usefulActionAvailable = player.usefulActionAvailable()
            let activeDeniedResources = denial.resources.filter {
                player.hasActiveGatherer(for: $0)
            }

            // This is the raw affordability-pressure measurement. It retains the
            // old active-gatherer gate, but records every denied resource kind.
            for kind in activeDeniedResources {
                affordabilityDelaySeconds[kind, default: 0] += simulation.tuning.stepDuration
            }

            // This is the CP-C9 bar. A denied purchase counts only when the
            // player has no other capability at that same fixed-timestep tick.
            if !activeDeniedResources.isEmpty, !usefulActionAvailable {
                noChoiceStallSeconds += simulation.tuning.stepDuration
            }

            recordDenialEpisode(
                denial,
                usefulActionAvailable: usefulActionAvailable,
                atTick: simulation.tick
            )
        }

        func finish() {
            closeDenial(atTick: simulation.tick)
        }

        var affordabilityDelayTotalSeconds: Double {
            affordabilityDelaySeconds.values.reduce(0, +)
        }

        func finalizedHomeResourceExhaustion() -> [ResourceKind: HomeResourceExhaustion] {
            var result = homeResourceExhaustion
            for kind in ResourceKind.allCases where result[kind] == nil {
                result[kind] = .neverExhausted
            }
            return result
        }

        private func detectExhaustion() {
            for kind in ResourceKind.allCases {
                guard homeResourceKinds.contains(kind), homeResourceExhaustion[kind] == nil else {
                    continue
                }
                let remaining = homeYield(for: kind)
                if remaining <= 0 {
                    homeResourceExhaustion[kind] =
                        .exhausted(at: Double(simulation.tick) / simulation.tuning.simulationHz)
                }
            }
        }

        private func recordDenialEpisode(
            _ denial: Denial,
            usefulActionAvailable: Bool,
            atTick tick: UInt64
        ) {
            let startTime = time(for: tick)
            if var openDenial,
               openDenial.deniedResources == denial.resources,
               openDenial.requestedAction == denial.action,
               openDenial.lastTick + 1 == tick
            {
                openDenial.lastTick = tick
                openDenial.productiveActionAvailableForWholeEpisode =
                    openDenial.productiveActionAvailableForWholeEpisode
                    && usefulActionAvailable
                self.openDenial = openDenial
                return
            }

            closeDenial(atTick: tick)
            openDenial = OpenDenial(
                deniedResources: denial.resources,
                requestedAction: denial.action,
                startTimeSeconds: startTime,
                lastTick: tick,
                productiveActionAvailableForWholeEpisode: usefulActionAvailable
            )
        }

        private func closeDenial(atTick tick: UInt64) {
            guard let openDenial else { return }
            let endTime = time(for: tick)
            denialEpisodes.append(
                DenialEpisode(
                    deniedResources: openDenial.deniedResources,
                    requestedAction: openDenial.requestedAction,
                    startTimeSeconds: openDenial.startTimeSeconds,
                    endTimeSeconds: endTime,
                    durationSeconds: endTime - openDenial.startTimeSeconds,
                    productiveActionAvailableForWholeEpisode:
                        openDenial.productiveActionAvailableForWholeEpisode
                )
            )
            self.openDenial = nil
        }

        private func time(for tick: UInt64) -> Double {
            Double(tick) / simulation.tuning.simulationHz
        }

        private func recordSample(player: ReferenceOpening) {
            let stock = simulation.stock(for: .sunwoven)
            let population = simulation.population(for: .sunwoven)
            let units = simulation.units(of: .sunwoven)
            let sample = Sample(
                tick: simulation.tick,
                matchTimeSeconds: Double(simulation.tick) / simulation.tuning.simulationHz,
                stock: stock,
                populationUsed: population.used,
                populationCap: population.cap,
                completedDwellings: simulation.buildings(of: .sunwoven)
                    .filter { $0.kind == .dwelling && $0.isComplete }
                    .count,
                citizenCount: units.filter { $0.kind == .citizen }.count,
                pathfinderCount: units.filter { $0.kind == .pathfinder }.count,
                vanguardCount: units.filter { $0.kind == .vanguard }.count,
                quarrelCount: units.filter { $0.kind == .quarrel }.count,
                // `isMilitary` is the combat classification. It deliberately
                // excludes Pathfinder; use `trainedArmyCount` for the opening's
                // complete Pathfinder/Vanguard/Quarrel training figure.
                armyCount: units.filter { $0.kind.isMilitary }.count,
                trainedArmyCount: units.filter {
                    switch $0.kind {
                    case .pathfinder, .vanguard, .quarrel: true
                    default: false
                    }
                }.count,
                idleCitizens: units.filter {
                    $0.kind == .citizen && isIdle($0)
                }.count,
                homeYield: ResourcePool(
                    provisions: homeYield(for: .provisions),
                    matter: homeYield(for: .matter),
                    lumen: homeYield(for: .lumen),
                    aether: homeYield(for: .aether)
                ),
                usefulActionAvailable: player.usefulActionAvailable()
            )
            samples.append(sample)

            guard sample.tick <= firstThreeMinutesTick else { return }
            if !sample.usefulActionAvailable {
                firstThreeMinutesUsefulAtEverySample = false
                if firstUsefulnessFailureAt == nil {
                    firstUsefulnessFailureAt = sample.matchTimeSeconds
                }
            }
        }

        private func homeYield(for kind: ResourceKind) -> Double {
            simulation.deposits.values
                .filter { $0.region == .sunwovenHome && $0.kind == kind }
                .sorted { $0.id.raw < $1.id.raw }
                .reduce(0) { $0 + $1.remaining }
        }

        private func isIdle(_ unit: SunfoldCore.Unit) -> Bool {
            if case .idle = unit.activity { return true }
            return false
        }
    }

    // MARK: - Reference opening

    /// A deliberately boring, deterministic economy player. It has no access to
    /// `stock` mutation, entity allocation, or production internals.
    @MainActor
    private final class ReferenceOpening {
        private enum ActionAttempt {
            case committed
            case denied(Denial)
            case unavailable
        }

        private struct GatherQuota {
            let kind: ResourceKind
            let share: Double
        }

        private let simulation: SkirmishSimulation
        private let faction: Faction = .sunwoven

        /// This is a working target, not a population ceiling. After this count
        /// the player changes the Core queue to a mixed army queue.
        private let workingCitizenTarget = 12
        private let maxDwellings = 4
        private let dwellingHeadroom = 2
        private let queueDepth = 2
        private let armyKinds: [UnitKind] = [.pathfinder, .vanguard, .quarrel]
        private let gatherQuotas = [
            GatherQuota(kind: .provisions, share: 0.50),
            GatherQuota(kind: .matter, share: 0.25),
            GatherQuota(kind: .lumen, share: 0.25),
        ]

        private var nextArmyKindIndex = 0
        private var ralliedArmyIDs: Set<EntityID> = []
        private(set) var structureCommitTicks: [BuildingKind: UInt64] = [:]

        init(simulation: SkirmishSimulation) {
            self.simulation = simulation
        }

        /// Returns the failed affordability order with both its resources and action.
        @discardableResult
        func act() -> Denial? {
            assignIdleCitizens()
            rallyNewArmy()

            // Policy: this scripted reference player chooses one foundation at a
            // time. This is a player choice, not a game capability restriction.
            if !policyWaitsForFoundation {
                if !hasBuilding(.formationYard), simulation.tick >= tick(for: 120) {
                    switch attemptBuild(.formationYard) {
                    case .committed: return nil
                    case .denied(let denial): return denial
                    case .unavailable: break
                    }
                }

                let hasCompletedYard = hasCompletedBuilding(.formationYard)
                if hasCompletedYard,
                   !hasBuilding(.lumenSpire),
                   simulation.tick >= tick(for: 240)
                {
                    switch attemptBuild(.lumenSpire) {
                    case .committed: return nil
                    case .denied(let denial): return denial
                    case .unavailable: break
                    }
                }

                if shouldBuildDwelling {
                    switch attemptBuild(.dwelling) {
                    case .committed: return nil
                    case .denied(let denial): return denial
                    case .unavailable: break
                    }
                }
            }

            if shouldTrainCitizens {
                switch attemptTrainCitizen() {
                case .committed: return nil
                case .denied(let denial): return denial
                case .unavailable: break
                }
            }

            guard shouldTrainArmy else { return nil }
            switch attemptTrainMixedArmy() {
            case .committed: return nil
            case .denied(let denial): return denial
            case .unavailable: return nil
            }
        }

        /// Used by the recorder for the honest stall definition.
        func hasActiveGatherer(for kind: ResourceKind) -> Bool {
            let liveDeposits = homeDeposits(of: kind).filter { !$0.isExhausted }
            guard !liveDeposits.isEmpty else { return false }
            let liveIDs = Set(liveDeposits.map(\.id))

            return simulation.units(of: faction).contains { unit in
                guard unit.kind == .citizen,
                      !unit.isAboard,
                      !unit.isBoarding,
                      let assignment = unit.assignment,
                      liveIDs.contains(assignment)
                else { return false }
                if case .constructing = unit.activity { return false }
                return true
            }
        }

        /// Capability: an action the player could issue now, not merely a
        /// resource balance. The recorder evaluates this at ten-second samples
        /// and at denied-order ticks during the first three minutes.
        func usefulActionAvailable() -> Bool {
            if hasIdleCitizenWithHomeDeposit { return true }

            for kind in usefulBuildingKinds {
                guard canIssueBuilding(kind) else { continue }
                return true
            }

            if hasAffordableTrainableUnit { return true }
            return false
        }

        // MARK: Planning

        private var shouldBuildDwelling: Bool {
            let dwellings = simulation.buildings(of: faction)
                .filter { $0.kind == .dwelling }
            guard dwellings.count < maxDwellings,
                  !dwellings.contains(where: { !$0.isComplete })
            else { return false }

            let population = simulation.population(for: faction)
            return population.cap - population.used <= dwellingHeadroom
        }

        private var shouldTrainCitizens: Bool {
            guard let core = building(of: .civilizationCore) else { return false }
            let live = simulation.units(of: faction).filter { $0.kind == .citizen }.count
            let queued = simulation.productionQueue(for: core.id).items
                .filter { $0.kind == .citizen }
                .count
            return live + queued < workingCitizenTarget
        }

        private var shouldTrainArmy: Bool {
            !shouldTrainCitizens && !armyKinds.isEmpty
        }

        /// Policy only. The simulation permits multiple foundations; this player
        /// chooses to finish one before committing another.
        private var policyWaitsForFoundation: Bool {
            simulation.buildings(of: faction).contains {
                $0.kind != .civilizationCore && !$0.isComplete
            }
        }

        private var hasIdleCitizenWithHomeDeposit: Bool {
            let hasDeposit = ResourceKind.allCases.contains {
                !homeDeposits(of: $0).allSatisfy { $0.isExhausted }
            }
            guard hasDeposit else { return false }

            return simulation.units(of: faction).contains { unit in
                guard unit.kind == .citizen, unit.cargo == nil else { return false }
                if unit.isAboard || unit.isBoarding { return false }
                if case .constructing = unit.activity { return false }
                if case .idle = unit.activity { return true }
                return false
            }
        }

        private let usefulBuildingKinds: [BuildingKind] = [
            .farm,
            .matterExtractor,
            .dwelling,
            .formationYard,
            .lumenSpire,
        ]

        /// Capability only. This deliberately ignores the reference player's
        /// citizen target, army target and shallow queue policy.
        private var hasAffordableTrainableUnit: Bool {
            let population = simulation.population(for: faction)

            if let core = building(of: .civilizationCore),
               simulation.productionQueue(for: core.id).count < simulation.tuning.maxQueueLength,
               simulation.stock(for: faction).covers(simulation.tuning.cost(for: .citizen)),
               population.used + UnitKind.citizen.populationCost <= population.cap
            {
                return true
            }

            for kind in armyKinds {
                guard let trainer = trainer(
                    for: kind,
                    queueLimit: simulation.tuning.maxQueueLength
                ),
                      simulation.productionQueue(for: trainer).count < simulation.tuning.maxQueueLength,
                      population.used + kind.populationCost <= population.cap,
                      simulation.stock(for: faction).covers(simulation.tuning.cost(for: kind))
                else { continue }
                return true
            }
            return false
        }

        /// Capability only. No reference-player construction policy belongs here.
        private func canIssueBuilding(_ kind: BuildingKind) -> Bool {
            guard simulation.buildBlocker(for: kind, faction: faction) == nil else { return false }
            return site(for: kind) != nil
        }

        // MARK: Gathering

        private func assignIdleCitizens() {
            var assignedByKind: [ResourceKind: Int] = [:]
            var idle: [EntityID] = []

            for unit in simulation.units(of: faction) where unit.kind == .citizen {
                guard !unit.isAboard, !unit.isBoarding else { continue }
                if case .constructing = unit.activity { continue }

                if let assignment = unit.assignment,
                   let deposit = simulation.deposit(assignment),
                   !deposit.isExhausted
                {
                    assignedByKind[deposit.kind, default: 0] += 1
                    continue
                }

                // A citizen carrying a final load must deliver it before the
                // player changes its assignment.
                guard unit.cargo == nil else { continue }
                if case .idle = unit.activity {
                    idle.append(unit.id)
                }
            }

            for id in idle {
                guard let unit = simulation.unit(id),
                      let kind = neediestResource(assignedByKind: assignedByKind),
                      let deposit = nearestDeposit(of: kind, to: unit.position)
                else { continue }

                assignedByKind[kind, default: 0] += 1
                simulation.orderGather([id], from: deposit.id)
            }
        }

        private func neediestResource(
            assignedByKind: [ResourceKind: Int]
        ) -> ResourceKind? {
            let assignedTotal = gatherQuotas.reduce(0) {
                $0 + (assignedByKind[$1.kind] ?? 0)
            }
            let total = assignedTotal + 1
            var best: (kind: ResourceKind, deficit: Double)?

            for quota in gatherQuotas {
                guard homeDeposits(of: quota.kind).contains(where: { !$0.isExhausted }) else {
                    continue
                }
                let deficit = quota.share * Double(total)
                    - Double(assignedByKind[quota.kind] ?? 0)
                if let current = best {
                    if deficit > current.deficit {
                        best = (quota.kind, deficit)
                    }
                } else {
                    best = (quota.kind, deficit)
                }
            }
            return best?.kind
        }

        private func homeDeposits(of kind: ResourceKind) -> [Deposit] {
            simulation.deposits.values
                .filter { $0.region == .sunwovenHome && $0.kind == kind }
                .sorted { $0.id.raw < $1.id.raw }
        }

        private func nearestDeposit(of kind: ResourceKind, to origin: WorldPoint) -> Deposit? {
            homeDeposits(of: kind).filter { !$0.isExhausted }.min {
                let left = simd_distance($0.position, origin)
                let right = simd_distance($1.position, origin)
                return left == right ? $0.id.raw < $1.id.raw : left < right
            }
        }

        // MARK: Buildings

        private func attemptBuild(_ kind: BuildingKind) -> ActionAttempt {
            let blocker = simulation.buildBlocker(for: kind, faction: faction)
            if let blocker {
                if case .unaffordable(let missing) = blocker {
                    // The call is intentional. It proves that the denial came
                    // from the public placement order, without changing state.
                    _ = simulation.placeBuilding(
                        kind,
                        at: simulation.map.fragment(.sunwovenHome).center,
                        for: faction
                    )
                    return .denied(
                        Denial(
                            resources: missingResources(in: missing),
                            action: .build(kind)
                        )
                    )
                }
                return .unavailable
            }
            guard let point = site(for: kind) else { return .unavailable }

            guard let id = simulation.placeBuilding(
                kind,
                at: point,
                for: faction,
                preferredBuilders: preferredBuilderIDs
            ) else {
                return .unavailable
            }
            structureCommitTicks[kind] = structureCommitTicks[kind] ?? simulation.tick
            _ = id
            return .committed
        }

        private func site(for kind: BuildingKind) -> WorldPoint? {
            guard let core = building(of: .civilizationCore) else { return nil }
            let bearings = 16

            for ring in 1...12 {
                let distance = core.kind.footprintRadius
                    + kind.footprintRadius
                    + 3
                    + Float(ring) * 3.5
                for slot in 0..<bearings {
                    let turn = Float(slot) + (ring.isMultiple(of: 2) ? 0.5 : 0)
                    let angle = turn / Float(bearings) * 2 * .pi
                    let candidate = core.position
                        + WorldPoint(sin(angle), cos(angle)) * distance
                    guard ConstructionPlacement.isLegal(
                        kind: kind,
                        at: candidate,
                        in: simulation
                    ) else { continue }
                    return candidate
                }
            }
            return nil
        }

        private var preferredBuilderIDs: [EntityID] {
            simulation.units(of: faction)
                .filter { unit in
                    guard unit.canBeAssignedToConstruction else { return false }
                    if case .constructing = unit.activity { return false }
                    return true
                }
                .sorted { $0.id.raw < $1.id.raw }
                .map(\.id)
        }

        // MARK: Production

        private func attemptTrainCitizen() -> ActionAttempt {
            guard let core = building(of: .civilizationCore),
                  simulation.productionQueue(for: core.id).count < queueDepth
            else { return .unavailable }
            return attemptTrain(.citizen, at: core.id)
        }

        private func attemptTrainMixedArmy() -> ActionAttempt {
            let population = simulation.population(for: faction)
            guard population.used < population.cap else { return .unavailable }

            let count = armyKinds.count
            let start = nextArmyKindIndex
            for offset in 0..<count {
                let index = (start + offset) % count
                let kind = armyKinds[index]
                guard let trainer = trainer(for: kind),
                      population.used + kind.populationCost <= population.cap,
                      simulation.stock(for: faction).covers(simulation.tuning.cost(for: kind))
                else { continue }

                let attempt = attemptTrain(kind, at: trainer)
                if case .committed = attempt {
                    nextArmyKindIndex = (index + 1) % count
                }
                return attempt
            }

            // Keep one round-robin demand pending when no kind is affordable.
            // This is the only path that records an affordability denial for the
            // army, and it still requires an open trainer queue and pop room.
            for offset in 0..<count {
                let index = (start + offset) % count
                let kind = armyKinds[index]
                guard let trainer = trainer(for: kind),
                      population.used + kind.populationCost <= population.cap
                else { continue }
                return attemptTrain(kind, at: trainer)
            }
            return .unavailable
        }

        private func trainer(for kind: UnitKind, queueLimit: Int? = nil) -> EntityID? {
            let limit = queueLimit ?? self.queueDepth
            return simulation.buildings(of: faction)
                .filter { building in
                    building.isComplete
                        && building.kind.trains.contains(kind)
                        && simulation.productionQueue(for: building.id).count < limit
                }
                .sorted { $0.id.raw < $1.id.raw }
                .first?
                .id
        }

        private func attemptTrain(_ kind: UnitKind, at buildingID: EntityID) -> ActionAttempt {
            let before = simulation.stock(for: faction)
            switch simulation.enqueueUnit(kind, at: buildingID) {
            case .success:
                return .committed
            case .failure(.cannotAfford):
                return .denied(
                    Denial(
                        resources: missingResources(
                            in: simulation.tuning.cost(for: kind),
                            comparedTo: before
                        ),
                        action: .train(kind)
                    )
                )
            case .failure:
                return .unavailable
            }
        }

        private func missingResources(in missing: ResourcePool) -> [ResourceKind] {
            ResourceKind.allCases.filter { missing[$0] > 1e-9 }
        }

        private func missingResources(
            in cost: ResourcePool,
            comparedTo have: ResourcePool
        ) -> [ResourceKind] {
            ResourceKind.allCases.filter { cost[$0] > have[$0] + 1e-9 }
        }

        // MARK: Rally orders

        private func rallyNewArmy() {
            let rallyPoint = armyRallyPoint()
            for unit in simulation.units(of: faction)
            where unit.kind.isMilitary && !ralliedArmyIDs.contains(unit.id)
            {
                simulation.order(unit.id, moveTo: rallyPoint)
                ralliedArmyIDs.insert(unit.id)
            }
        }

        private func armyRallyPoint() -> WorldPoint {
            let home = simulation.map.fragment(.sunwovenHome).center
            let candidates = [
                home + WorldPoint(12, 0),
                home + WorldPoint(-12, 0),
                home + WorldPoint(0, 12),
                home + WorldPoint(0, -12),
            ]
            if let point = candidates.first(where: {
                simulation.map.isStandable($0, margin: UnitKind.vanguard.footprintRadius)
            }) {
                return point
            }
            return home
        }

        // MARK: Read helpers

        private func building(of kind: BuildingKind) -> Building? {
            simulation.buildings(of: faction).first { $0.kind == kind }
        }

        private func hasBuilding(_ kind: BuildingKind) -> Bool {
            building(of: kind) != nil
        }

        private func hasCompletedBuilding(_ kind: BuildingKind) -> Bool {
            simulation.buildings(of: faction).contains {
                $0.kind == kind && $0.isComplete
            }
        }

        private func tick(for seconds: Double) -> UInt64 {
            UInt64((seconds * simulation.tuning.simulationHz).rounded())
        }
    }
}
