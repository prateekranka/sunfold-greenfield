import SwiftUI

/// First-class debug surface. Deterministic seed, clock, camera state and any
/// fail-closed warnings are always inspectable in the rendered build — evidence
/// comes from what the game actually shows, not from what the code intends.
struct DebugOverlay: View {
    let controller: WorldController
    @Binding var isExpanded: Bool

    private var simulation: SkirmishSimulation { controller.simulation }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if isExpanded {
                Divider().overlay(SunfoldPalette.hudEdge)
                readouts
                if !DebugLog.warnings.isEmpty {
                    Divider().overlay(SunfoldPalette.hudEdge)
                    warnings
                }
                Divider().overlay(SunfoldPalette.hudEdge)
                controls
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundStyle(SunfoldPalette.hudText)
        .padding(10)
        .background(SunfoldPalette.hudPanel, in: .rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(SunfoldPalette.hudEdge, lineWidth: 1)
        )
        .frame(maxWidth: 260, alignment: .leading)
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                Text("DEBUG · G0")
                Spacer()
                Text(String(format: "%.0f fps", controller.smoothedFPS))
                    .foregroundStyle(SunfoldPalette.hudTextDim)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse debug panel" : "Expand debug panel")
    }

    private var readouts: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("seed", "\(simulation.seed)")
            row("tick", "\(simulation.tick)")
            row("elapsed", String(format: "%.1fs", simulation.elapsed))
            row("age", simulation.age(for: .sunwoven).displayName)
            row("yaw", String(format: "%.0f°", controller.currentYaw * 180 / .pi))
            row("zoom", String(format: "%.0fm", controller.currentZoom))
            row("focus", String(format: "%.0f, %.0f", controller.currentFocus.x, controller.currentFocus.y))
            let stock = simulation.stock(for: .sunwoven)
            row("prov/mat", String(format: "%.0f / %.0f", stock.provisions, stock.matter))
            row("lum/aeth", String(format: "%.0f / %.0f", stock.lumen, stock.aether))
        }
    }

    private var warnings: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("WARNINGS (\(DebugLog.warnings.count))")
                .foregroundStyle(SunfoldPalette.hudAccent)
            ForEach(Array(DebugLog.warnings.enumerated()), id: \.offset) { _, warning in
                Text(warning)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SunfoldPalette.hudTextDim)
                    .lineLimit(2)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button("north") { controller.returnNorth() }
            Button(simulation.isPaused ? "run" : "pause") {
                simulation.setPaused(!simulation.isPaused)
            }
            Button(String(format: "%.0f×", simulation.timeScale)) {
                simulation.timeScale = simulation.timeScale >= 4 ? 1 : simulation.timeScale * 2
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.mini)
        .tint(SunfoldPalette.hudEdge)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: 6) {
            Text(label).foregroundStyle(SunfoldPalette.hudTextDim)
            Spacer(minLength: 8)
            Text(value)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(value)")
    }
}
