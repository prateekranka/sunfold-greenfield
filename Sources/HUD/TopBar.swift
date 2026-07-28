import SwiftUI

/// The full top chrome: economy left, faction emblem centre, speed right.
///
/// Concept 01 hangs this as one continuous bar from the bezel. The centre
/// emblem is the identity mark; the speed cluster is chrome only until a
/// clock control exists — buttons are present and labelled so the layout
/// matches the bar, but they do not advance simulation time.
struct TopBar: View {
    let stock: ResourcePool
    let population: (used: Int, cap: Int)
    let age: Age

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            ResourceRail(stock: stock, population: population, age: age)
            Spacer(minLength: 12)
            emblem
            Spacer(minLength: 12)
            speedCluster
        }
        .frame(maxWidth: .infinity)
    }

    /// The Sunwoven sunburst — the same mark the bible puts at top-centre.
    private var emblem: some View {
        ZStack {
            Circle()
                .stroke(HUDInk.edgeBright, lineWidth: 1.25)
                .frame(width: 36, height: 36)
            HUDGlyph(.sunburst)
                .fill(HUDInk.accent, style: HUDGlyph.Kind.sunburst.fillStyle)
                .frame(width: 22, height: 22)
                .shadow(color: HUDInk.accent.opacity(0.45), radius: 5)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("Sunwoven")
    }

    private var speedCluster: some View {
        HStack(spacing: 5) {
            HUDIconTile(glyph: .pause, size: 34, name: "Pause")
            HUDIconTile(glyph: .play, size: 34, isPrimary: true, name: "Normal speed")
            HUDIconTile(glyph: .speed2, size: 34, name: "Double speed")
            HUDIconTile(glyph: .speed3, size: 34, name: "Triple speed")
        }
        .hudPanel(
            cut: 10,
            corners: .bottom,
            padding: EdgeInsets(top: 6, leading: 7, bottom: 6, trailing: 7)
        )
    }
}

/// Contest / arrival cues under the top bar.
///
/// G2 has no live alert feed yet, so this shows the chrome geometry with one
/// quiet seed cue rather than an empty strip the eye learns to ignore.
struct AlertStrip: View {
    var body: some View {
        HStack(spacing: 8) {
            HUDGlyph(.alert)
                .fill(HUDInk.warning, style: HUDGlyph.Kind.alert.fillStyle)
                .frame(width: 11, height: 11)
            Text("Light transport docked at home rim")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(HUDInk.text)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: 420, alignment: .leading)
        .hudSurface(
            cut: 8,
            corners: [.bottomLeading, .bottomTrailing],
            lineWidth: 0.75,
            shadow: false
        )
        .accessibilityLabel("Alert: Light transport docked at home rim")
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
