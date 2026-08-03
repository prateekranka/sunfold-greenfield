import Foundation
import XCTest
@testable import SunfoldCore

/// CP-C9's nine-minute economy bar.
///
/// The default test is a short replay smoke test. Full ten-minute runs are
/// opt-in because they are measurement harnesses, not the fast test path.
@MainActor
final class NineMinuteEconomyTests: XCTestCase {

    private static let longRunEnvironment = "SUNFOLD_RUN_LONG_ECONOMY_HARNESS"

    func testReferenceOpeningSmokeRunsByDefaultAndReplaysExactly() throws {
        let first = try NineMinuteEconomyHarness.run(
            mode: .economyCeiling,
            maxSeconds: 60
        )
        let second = try NineMinuteEconomyHarness.run(
            mode: .economyCeiling,
            maxSeconds: 60
        )
        let firstCSV = try Data(contentsOf: first.outputURL)
        let firstDenialCSV = try Data(contentsOf: first.denialOutputURL)

        XCTAssertEqual(first.samples.count, 7, "The smoke run must sample 0:00 through 1:00.")
        XCTAssertEqual(first.samples, second.samples)
        XCTAssertEqual(first.worldHash, second.worldHash)
        XCTAssertEqual(first.noChoiceStallSeconds, second.noChoiceStallSeconds, accuracy: 1e-12)
        XCTAssertEqual(first.affordabilityDelaySeconds, second.affordabilityDelaySeconds)
        XCTAssertEqual(first.denialEpisodes, second.denialEpisodes)
        XCTAssertEqual(first.outputURL, second.outputURL)
        XCTAssertEqual(first.denialOutputURL, second.denialOutputURL)
        XCTAssertEqual(firstCSV, try Data(contentsOf: second.outputURL))
        XCTAssertEqual(firstDenialCSV, try Data(contentsOf: second.denialOutputURL))
        let csv = try String(contentsOf: first.outputURL, encoding: .utf8)
        let firstLine = csv.split(separator: "\n", omittingEmptySubsequences: false)
            .first
            .map { String($0) }
        XCTAssertEqual(
            firstLine,
            NineMinuteEconomyHarness.csvHeader.joined(separator: ",")
        )
        let denialCSV = try String(contentsOf: first.denialOutputURL, encoding: .utf8)
        XCTAssertEqual(
            denialCSV.split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init),
            NineMinuteEconomyHarness.denialCSVHeader.joined(separator: ",")
        )
    }

    func testConfiguredOutputDirectoryKeepsModeAndDurationPathsDistinct() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sunfold-cp-c9-output-path-test", isDirectory: true)

        let short = try NineMinuteEconomyHarness.run(
            mode: .economyCeiling,
            maxSeconds: 20,
            outputDirectoryURL: directory
        )
        let long = try NineMinuteEconomyHarness.run(
            mode: .economyCeiling,
            maxSeconds: 30,
            outputDirectoryURL: directory
        )
        let contested = try NineMinuteEconomyHarness.run(
            mode: .contested,
            maxSeconds: 30,
            outputDirectoryURL: directory
        )

        XCTAssertEqual(short.outputURL.deletingLastPathComponent(), directory)
        XCTAssertEqual(long.outputURL.deletingLastPathComponent(), directory)
        XCTAssertEqual(contested.outputURL.deletingLastPathComponent(), directory)
        XCTAssertNotEqual(short.outputURL, long.outputURL)
        XCTAssertNotEqual(long.outputURL, contested.outputURL)
        XCTAssertNotEqual(short.denialOutputURL, long.denialOutputURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: short.outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: long.outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: contested.outputURL.path))

        let shortCSV = try Data(contentsOf: short.outputURL)
        _ = try NineMinuteEconomyHarness.run(
            mode: .economyCeiling,
            maxSeconds: 40,
            outputDirectoryURL: directory
        )
        XCTAssertEqual(shortCSV, try Data(contentsOf: short.outputURL))
    }

    func testEconomyCeilingMeetsNineMinuteBar() throws {
        try requireLongRun()

        let result = try NineMinuteEconomyHarness.run(mode: .economyCeiling)

        XCTAssertTrue(result.reachedTenMinutes)
        XCTAssertEqual(result.samples.count, 61, "The CSV must contain one row every 10 seconds, including 0:00 and 10:00.")

        guard let population = result.populationAtNineMinutes,
              let populationCap = result.populationCapAtNineMinutes,
              let dwellings = result.dwellingsAtNineMinutes
        else {
            return XCTFail("The economy-ceiling run did not reach the 9:00 sample.")
        }

        // The bar is a floor and a housing count, not a snapshot of today's
        // exact economy constants.
        XCTAssertGreaterThanOrEqual(population, 40, "Population at 9:00 is \(population), below the CP-C9 bar.")
        XCTAssertLessThanOrEqual(population, populationCap)
        XCTAssertEqual(dwellings, 4, "The reference player must complete four Dwellings by 9:00.")
        XCTAssertEqual(
            result.noChoiceStallSeconds,
            0,
            accuracy: 1e-9,
            "The reference player must not enter a no-choice economy stall."
        )
        XCTAssertEqual(
            Set(result.affordabilityDelaySeconds.keys),
            Set(ResourceKind.allCases),
            "Raw per-resource affordability delays must be reported for every resource kind. Delays: \(result.affordabilityDelaySeconds)"
        )
        XCTAssertTrue(
            result.affordabilityDelaySeconds.values.contains { $0 > 0 },
            "The raw affordability-pressure measurement must retain denied ticks. Delays: \(result.affordabilityDelaySeconds)"
        )
        XCTAssertEqual(
            result.affordabilityDelayTotalSeconds,
            result.affordabilityDelaySeconds.values.reduce(0, +),
            accuracy: 1e-9,
            "The raw total must equal the sum of its per-resource delays."
        )
        XCTAssertTrue(
            result.firstThreeMinutesUsefulAtEverySample,
            "The first useful-action gap was at \(result.firstUsefulnessFailureAt.map { String($0) } ?? "unknown") seconds."
        )

        let yardTick = result.structureCommitTicks[.formationYard]
        let spireTick = result.structureCommitTicks[.lumenSpire]
        XCTAssertNotNil(yardTick, "The reference opening must commit a Formation Yard.")
        XCTAssertNotNil(spireTick, "The reference opening must commit a Lumen Spire.")
        if let yardTick {
            XCTAssertGreaterThanOrEqual(yardTick, 2_400)
            XCTAssertLessThanOrEqual(yardTick, 2_400 + 200)
        }
        if let spireTick {
            XCTAssertGreaterThanOrEqual(spireTick, 4_800)
            XCTAssertLessThanOrEqual(spireTick, 4_800 + 200)
        }

        let delayReport = ResourceKind.allCases.map { kind in
            "\(kind.rawValue)=\(String(format: "%.3f", result.affordabilityDelaySeconds[kind] ?? 0))"
        }.joined(separator: ",")
        let unitReport = UnitKind.allCases.map { kind in
            "\(kind.rawValue)=\(result.unitCountsAtNineMinutes[kind] ?? 0)"
        }.joined(separator: ",")
        let exhaustionReport = ResourceKind.allCases.map { kind in
            "\(kind.rawValue)=\(result.homeResourceExhaustionReport[kind] ?? "missing")"
        }.joined(separator: ",")
        print(
            "CP-C9 economy measurements: noChoiceStallSeconds=\(String(format: "%.3f", result.noChoiceStallSeconds)); "
            + "affordabilityDelaySeconds={\(delayReport)}; "
            + "affordabilityDelayTotalSeconds=\(String(format: "%.3f", result.affordabilityDelayTotalSeconds)); "
            + "population=\(population); cap=\(populationCap); dwellings=\(dwellings); "
            + "units={\(unitReport)}; homeAtNineMinutes="
            + "matter:\(String(format: "%.3f", result.samples.first { $0.tick == 10_800 }?.homeYield.matter ?? 0)),"
            + "lumen:\(String(format: "%.3f", result.samples.first { $0.tick == 10_800 }?.homeYield.lumen ?? 0)); "
            + "exhaustion={\(exhaustionReport)}"
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: result.outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.denialOutputURL.path))
    }

    func testContestedReferenceOpeningIsDeterministicAndWritesEvidence() throws {
        try requireLongRun()

        let first = try NineMinuteEconomyHarness.run(mode: .contested)
        let second = try NineMinuteEconomyHarness.run(mode: .contested)

        XCTAssertEqual(first.samples, second.samples)
        XCTAssertEqual(first.worldHash, second.worldHash)
        XCTAssertEqual(first.homeResourceExhaustion, second.homeResourceExhaustion)
        XCTAssertEqual(first.homeResourceExhaustionReport, second.homeResourceExhaustionReport)
        XCTAssertEqual(first.affordabilityDelaySeconds, second.affordabilityDelaySeconds)
        XCTAssertEqual(first.affordabilityDelayTotalSeconds, second.affordabilityDelayTotalSeconds, accuracy: 1e-12)
        XCTAssertEqual(first.noChoiceStallSeconds, second.noChoiceStallSeconds, accuracy: 1e-12)
        XCTAssertEqual(first.denialEpisodes, second.denialEpisodes)
        XCTAssertEqual(first.endedAtSeconds, second.endedAtSeconds, accuracy: 1e-12)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.outputURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.denialOutputURL.path))

        // A contest may end before 9:00. If it reaches that sample, preserve
        // the same structural safety checks without inventing a contested target.
        if let population = first.populationAtNineMinutes,
           let populationCap = first.populationCapAtNineMinutes
        {
            XCTAssertLessThanOrEqual(population, populationCap)
        }
    }

    private func requireLongRun() throws {
        let value = ProcessInfo.processInfo.environment[Self.longRunEnvironment]?
            .lowercased()
        guard ["1", "true", "yes"].contains(value) else {
            throw XCTSkip(
                "Full CP-C9 harness tests are gated. Set \(Self.longRunEnvironment)=1 to run them."
            )
        }
    }
}
