import Foundation

/// Launch-argument gate for the performance harness. Parsed once at process
/// start so the render loop pays nothing when perf is off.
enum PerfLaunchFlags {
    /// Pass `-sunfoldPerf` to enable frame sampling and structured reporting.
    static let isEnabled: Bool = ProcessInfo.processInfo.arguments.contains("-sunfoldPerf")

    /// Optional on-screen readout (machine-readable output is always written).
    static let showsOverlay: Bool = {
        guard isEnabled else { return false }
        return ProcessInfo.processInfo.arguments.contains("-sunfoldPerfOverlay")
    }()

    /// Scenario tag echoed in reports (`idle`, `camera_pan`, …).
    static let scenario: String = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-sunfoldPerfScenario"),
              args.index(after: index) < args.endIndex
        else { return "unspecified" }
        return args[args.index(after: index)]
    }()

    /// Wall-clock seconds after which a report is flushed automatically.
    static let autoReportAfterSeconds: Double? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-sunfoldPerfDuration"),
              args.index(after: index) < args.endIndex,
              let value = Double(args[args.index(after: index)])
        else { return nil }
        return value
    }()

    /// Build configuration label for reports (`Debug` / `Release`).
    static let buildConfiguration: String = {
        #if DEBUG
        "Debug"
        #else
        "Release"
        #endif
    }()

    /// Optional perf density: spawn citizens until `units.count` reaches N.
    /// Pass `-sunfoldDensity 80` at launch. Inert when absent — no gameplay effect.
    static let perfDensity: Int? = {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-sunfoldDensity"),
              args.index(after: index) < args.endIndex,
              let value = Int(args[args.index(after: index)])
        else { return nil }
        return max(0, value)
    }()
}
