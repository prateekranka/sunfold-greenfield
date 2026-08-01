import SwiftUI

/// Optional on-screen perf readout. Machine-readable output is always written to
/// the log and Documents when `-sunfoldPerf` is active; this is supplementary.
struct PerfOverlay: View {
    let harness: PerfHarness
    let controller: WorldController

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("PERF · \(PerfLaunchFlags.scenario)")
                .foregroundStyle(SunfoldPalette.hudAccent)
            if let stats = harness.latestStats {
                row("fps", String(format: "%.0f (%.1fms)", stats.fpsMean, stats.meanMs))
                row("p95/p99", String(format: "%.1f / %.1f ms", stats.p95Ms, stats.p99Ms))
                row("worst", String(format: "%.1f ms", stats.worstMs))
                row("drop/long", "\(stats.droppedFrameCount) / \(stats.longFrameCount)")
                row("sim/pres", String(
                    format: "%.2f / %.2f ms",
                    stats.simulationMeanMs,
                    stats.presentationMeanMs
                ))
            }
            row("target", "\(harness.displayMaxFPS) Hz · \(String(format: "%.2f", 1000.0 / Double(harness.displayMaxFPS))) ms")
            if let scale = harness.latestSceneScale {
                row("ents", "sim \(scale.simulationUnits + scale.simulationBuildings + scale.simulationDeposits) · scene \(scale.presentedEntities)")
            }
            row("n", "\(harness.latestStats?.sampleCount ?? 0) frames")
        }
        .font(.system(size: 10, weight: .medium, design: .monospaced))
        .foregroundStyle(SunfoldPalette.hudText)
        .padding(8)
        .background(SunfoldPalette.hudPanel.opacity(0.92), in: .rect(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8).stroke(SunfoldPalette.hudEdge, lineWidth: 1)
        )
        .frame(maxWidth: 220, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(SunfoldPalette.hudTextDim)
            Spacer(minLength: 4)
            Text(value)
        }
    }
}
