import SwiftUI

/// The full top chrome: economy left, faction emblem centre, speed right.
///
/// Concept 01 hangs this as one continuous bar from the bezel. Speed tiles drive
/// the presentation clock (`timeScale` / pause) — the fixed 20 Hz step is
/// unchanged; only how many steps a wall-clock frame buys moves.
struct TopBar: View {
    @Bindable var simulation: SkirmishSimulation
    var controller: WorldController?

    private var stock: ResourcePool { simulation.stock(for: simulation.playerFaction) }
    private var population: (used: Int, cap: Int) {
        simulation.population(for: simulation.playerFaction)
    }
    private var age: Age { simulation.age(for: simulation.playerFaction) }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ResourceRail(stock: stock, population: population, age: age)
            Spacer(minLength: 12)
            emblem
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                zoomCluster
                speedCluster
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The Sunwoven sunburst — the same mark the bible puts at top-centre.
    private var emblem: some View {
        ZStack {
            Circle()
                .stroke(HUDInk.friendly(for: simulation.playerFaction), lineWidth: 1.25)
                .frame(width: 36, height: 36)
            HUDGlyph(.sunburst)
                .fill(HUDInk.friendly(for: simulation.playerFaction), style: HUDGlyph.Kind.sunburst.fillStyle)
                .frame(width: 22, height: 22)
                .shadow(color: HUDInk.friendly(for: simulation.playerFaction).opacity(0.45), radius: 5)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel(simulation.playerFaction.displayName)
    }

    private var zoomCluster: some View {
        HStack(spacing: 5) {
            Button {
                guard let controller else { return }
                controller.zoom(to: controller.currentZoom * 1.18)
            } label: {
                Text("−")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(HUDInk.accent)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom out")

            Button {
                guard let controller else { return }
                controller.zoom(to: controller.currentZoom / 1.18)
            } label: {
                Text("+")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(HUDInk.accent)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom in")
        }
        .hudPanel(
            cut: 10,
            corners: .bottom,
            padding: EdgeInsets(top: 6, leading: 7, bottom: 6, trailing: 7)
        )
    }

    private var speedCluster: some View {
        HStack(spacing: 5) {
            HUDIconTile(
                glyph: .pause,
                size: 34,
                isPrimary: simulation.isPaused,
                name: "Pause",
                action: { simulation.setPaused(true) }
            )
            HUDIconTile(
                glyph: .play,
                size: 34,
                isPrimary: !simulation.isPaused && abs(simulation.timeScale - 1) < 0.01,
                name: "Normal speed",
                action: { setSpeed(1) }
            )
            HUDIconTile(
                glyph: .speed2,
                size: 34,
                isPrimary: !simulation.isPaused && abs(simulation.timeScale - 2) < 0.01,
                name: "Double speed",
                action: { setSpeed(2) }
            )
            HUDIconTile(
                glyph: .speed3,
                size: 34,
                isPrimary: !simulation.isPaused && abs(simulation.timeScale - 3) < 0.01,
                name: "Triple speed",
                action: { setSpeed(3) }
            )
        }
        .hudPanel(
            cut: 10,
            corners: .bottom,
            padding: EdgeInsets(top: 6, leading: 7, bottom: 6, trailing: 7)
        )
    }

    private func setSpeed(_ scale: Double) {
        simulation.setPaused(false)
        simulation.timeScale = scale
    }
}

/// Pinned control-group slots along the left edge, above the minimap.
///
/// Slots are visual chrome. Control groups are not wired in G1; empty wells
/// keep the concept layout so the theatre is not a blank left margin.
struct GroupRail: View {
    var slotCount: Int = 3

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<slotCount, id: \.self) { index in
                ZStack {
                    ChamferedRect(cut: HUDMetrics.tileCut)
                        .fill(HUDInk.well)
                    ChamferedRect(cut: HUDMetrics.tileCut)
                        .stroke(HUDInk.edge.opacity(0.85), lineWidth: 1)
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(HUDInk.textDim)
                }
                .frame(width: HUDMetrics.groupTile, height: HUDMetrics.groupTile)
                .accessibilityLabel("Control group \(index + 1), empty")
            }
        }
        .padding(7)
        .hudSurface(cut: 10, corners: [.topTrailing, .bottomTrailing], shadow: true)
    }
}
