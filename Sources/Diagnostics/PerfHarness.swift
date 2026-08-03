import Foundation
import os
import UIKit

/// Frame-timing harness hooked from `WorldController.onRenderFrame`.
///
/// Off unless `-sunfoldPerf` is passed. When enabled, samples every frame,
/// writes structured lines to os_log/stdout, and flushes a JSON report to the
/// app Documents directory on demand or after `-sunfoldPerfDuration`.
@MainActor
final class PerfHarness {
    static let shared = PerfHarness()

    struct LaunchMetrics: Codable, Sendable {
        var processStartToFirstFrameMs: Double?
        var processStartToSceneAttachedMs: Double?
        var processStartToSceneStableMs: Double?
        var sceneAttachedToStableMs: Double?
    }

    struct ThermalSnapshot: Codable, Sendable {
        var elapsedSeconds: Double
        var state: String
    }

    struct FramePacingSnapshot: Codable, Sendable {
        var minimumFPS: Float
        var maximumFPS: Float
        var preferredFPS: Float
    }

    struct Report: Codable, Sendable {
        var schemaVersion: Int = 1
        var capturedAt: String
        var scenario: String
        var buildConfiguration: String
        var displayMaxFPS: Int
        var targetFrameBudgetMs: Double
        var deviceModel: String
        var isSimulator: Bool
        var mapID: String
        var framePacing: FramePacingSnapshot?
        var frameStats: FramePerfSampler.FrameStats?
        var launch: LaunchMetrics
        var sceneScale: SceneScaleSnapshot?
        var residentMemoryMB: Double?
        var thermalSnapshots: [ThermalSnapshot]?
        var thermalPeak: String?
        var note: String?
    }

    private let logger = Logger(subsystem: "com.sunfold.greenfield", category: "perf")
    private let processStart = CFAbsoluteTimeGetCurrent()

    private var sampler = FramePerfSampler()
    private var firstFrameTime: CFAbsoluteTime?
    private var sceneAttachedTime: CFAbsoluteTime?
    private var sceneStableTime: CFAbsoluteTime?
    private var stableFrameStreak = 0
    private var samplingStartTime: CFAbsoluteTime?
    private var autoReportScheduled = false
    private var reportWritten = false
    private var thermalSnapshots: [ThermalSnapshot] = []
    private var thermalPeak: ProcessInfo.ThermalState = .nominal
    private var lastThermalSampleTime: CFAbsoluteTime?

    /// Latest stats for the optional overlay.
    private(set) var latestStats: FramePerfSampler.FrameStats?
    private(set) var displayMaxFPS: Int = 60
    private(set) var latestSceneScale: SceneScaleSnapshot?

    private init() {
        displayMaxFPS = UIScreen.main.maximumFramesPerSecond
        if PerfLaunchFlags.isEnabled {
            let maxFPS = displayMaxFPS
            logger.info("[sunfold.perf] harness enabled scenario=\(PerfLaunchFlags.scenario, privacy: .public) maxFPS=\(maxFPS)")
            print("[sunfold.perf] harness enabled scenario=\(PerfLaunchFlags.scenario) maxFPS=\(maxFPS)")
        }
    }

    // MARK: - Lifecycle markers

    func markSceneAttached() {
        guard PerfLaunchFlags.isEnabled else { return }
        sceneAttachedTime = CFAbsoluteTimeGetCurrent()
        let ms = (sceneAttachedTime! - processStart) * 1000
        emitMarker("scene_attached", ms: ms)
    }

    // MARK: - Per-frame sampling

    func recordFrame(
        deltaTime: TimeInterval,
        simulationSeconds: Double,
        presentationSeconds: Double,
        sceneScale: SceneScaleSnapshot
    ) {
        guard PerfLaunchFlags.isEnabled, deltaTime > 0 else { return }

        if firstFrameTime == nil {
            firstFrameTime = CFAbsoluteTimeGetCurrent()
            let ms = (firstFrameTime! - processStart) * 1000
            emitMarker("first_frame", ms: ms)
            samplingStartTime = firstFrameTime
            scheduleAutoReportIfNeeded()
        }

        updateSceneStable(deltaTime: deltaTime)

        sampler.record(
            frameSeconds: deltaTime,
            simulationSeconds: simulationSeconds,
            presentationSeconds: presentationSeconds
        )
        latestSceneScale = sceneScale

        let budget = 1.0 / Double(displayMaxFPS)
        latestStats = sampler.statistics(budgetSeconds: budget)

        if let stats = latestStats, stats.sampleCount % 120 == 0 {
            emitPeriodic(stats)
            sampleThermalIfNeeded()
        }
    }

    private func sampleThermalIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        if let last = lastThermalSampleTime, now - last < 5 { return }
        lastThermalSampleTime = now
        let state = ProcessInfo.processInfo.thermalState
        if state.rawValue > thermalPeak.rawValue { thermalPeak = state }
        thermalSnapshots.append(
            ThermalSnapshot(
                elapsedSeconds: now - processStart,
                state: Self.thermalLabel(state)
            )
        )
    }

    private static func thermalLabel(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "nominal"
        case .fair: "fair"
        case .serious: "serious"
        case .critical: "critical"
        @unknown default: "unknown"
        }
    }

    private func updateSceneStable(deltaTime: TimeInterval) {
        guard sceneStableTime == nil else { return }
        let budget = 1.0 / Double(displayMaxFPS)
        if deltaTime <= budget * 2.5 {
            stableFrameStreak += 1
        } else {
            stableFrameStreak = 0
        }
        // Require 90 consecutive frames within 2.5× budget after first frame.
        if stableFrameStreak >= 90 {
            sceneStableTime = CFAbsoluteTimeGetCurrent()
            let ms = (sceneStableTime! - processStart) * 1000
            emitMarker("scene_stable", ms: ms)
            if let attached = sceneAttachedTime {
                let attachToStable = (sceneStableTime! - attached) * 1000
                emitMarker("attach_to_stable", ms: attachToStable)
            }
        }
    }

    // MARK: - Reporting

    func writeReportNow(reason: String = "manual") {
        guard PerfLaunchFlags.isEnabled, !reportWritten else { return }
        let report = buildReport(note: reason)
        reportWritten = true
        emitReport(report)
        persistReport(report)
    }

    private func scheduleAutoReportIfNeeded() {
        guard !autoReportScheduled, let duration = PerfLaunchFlags.autoReportAfterSeconds else { return }
        autoReportScheduled = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            self.writeReportNow(reason: "auto_duration_\(Int(duration))s")
        }
    }

    private func buildReport(note: String?) -> Report {
        let budget = 1.0 / Double(displayMaxFPS)
        let launch = LaunchMetrics(
            processStartToFirstFrameMs: elapsedMs(since: processStart, to: firstFrameTime),
            processStartToSceneAttachedMs: elapsedMs(since: processStart, to: sceneAttachedTime),
            processStartToSceneStableMs: elapsedMs(since: processStart, to: sceneStableTime),
            sceneAttachedToStableMs: sceneAttachedTime.flatMap { attached in
                elapsedMs(since: attached, to: sceneStableTime)
            }
        )

        sampleThermalIfNeeded()

        return Report(
            capturedAt: ISO8601DateFormatter().string(from: Date()),
            scenario: PerfLaunchFlags.scenario,
            buildConfiguration: PerfLaunchFlags.buildConfiguration,
            displayMaxFPS: displayMaxFPS,
            targetFrameBudgetMs: budget * 1000,
            deviceModel: Self.deviceDescription(),
            isSimulator: Self.isSimulator(),
            mapID: latestSceneScale?.mapID ?? "unknown",
            framePacing: FramePacingSnapshot(
                minimumFPS: FramePacing.frameRateRange.minimum ?? 30,
                maximumFPS: FramePacing.frameRateRange.maximum ?? FramePacing.targetFPS,
                preferredFPS: FramePacing.frameRateRange.preferred ?? FramePacing.targetFPS
            ),
            frameStats: sampler.statistics(budgetSeconds: budget),
            launch: launch,
            sceneScale: latestSceneScale,
            residentMemoryMB: Self.residentMemoryMB(),
            thermalSnapshots: thermalSnapshots.isEmpty ? nil : thermalSnapshots,
            thermalPeak: thermalSnapshots.isEmpty ? nil : Self.thermalLabel(thermalPeak),
            note: note
        )
    }

    private func emitReport(_ report: Report) {
        guard let data = try? JSONEncoder().encode(report),
              let json = String(data: data, encoding: .utf8)
        else { return }

        logger.info("[sunfold.perf] PERF_REPORT_READY \(json, privacy: .public)")
        print("[sunfold.perf] PERF_REPORT_READY \(json)")

        if let stats = report.frameStats {
            let summary = String(
                format: "mean=%.2fms p95=%.2fms p99=%.2fms worst=%.2fms fps=%.1f dropped=%d long=%d sim=%.3fms pres=%.3fms",
                stats.meanMs, stats.p95Ms, stats.p99Ms, stats.worstMs, stats.fpsMean,
                stats.droppedFrameCount, stats.longFrameCount,
                stats.simulationMeanMs, stats.presentationMeanMs
            )
            logger.info("[sunfold.perf] summary \(summary, privacy: .public)")
            print("[sunfold.perf] summary \(summary)")
        }
    }

    private func persistReport(_ report: Report) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        let name = "perf-\(PerfLaunchFlags.scenario)-\(PerfLaunchFlags.buildConfiguration.lowercased()).json"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
        try? data.write(to: url, options: .atomic)
        logger.info("[sunfold.perf] wrote \(url.path, privacy: .public)")
        print("[sunfold.perf] wrote \(url.path)")
    }

    private func emitMarker(_ name: String, ms: Double) {
        let line = String(format: "[sunfold.perf] marker %@ %.1fms", name, ms)
        logger.info("\(line, privacy: .public)")
        print(line)
    }

    private func emitPeriodic(_ stats: FramePerfSampler.FrameStats) {
        let line = String(
            format: "[sunfold.perf] tick mean=%.2fms p95=%.2fms fps=%.1f",
            stats.meanMs, stats.p95Ms, stats.fpsMean
        )
        logger.info("\(line, privacy: .public)")
        print(line)
    }

    private func elapsedMs(since start: CFAbsoluteTime, to end: CFAbsoluteTime?) -> Double? {
        guard let end else { return nil }
        return (end - start) * 1000
    }

    // MARK: - Environment

    private static func isSimulator() -> Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private static func deviceDescription() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
        return machine
    }

    private static func residentMemoryMB() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Double(info.resident_size) / (1024 * 1024)
    }
}
