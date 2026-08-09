import SwiftUI

/// Shipping placement chrome while a Soft build ghost is active.
///
/// Shows the building's purpose, cost, and legal/illegal state so a first-time
/// player can decide without reading prototype debug copy.
struct PlacementPanel: View {
    let simulation: SkirmishSimulation
    let session: ConstructionPlacement.Session
    let onCancel: () -> Void

    private var cost: ResourcePool {
        simulation.tuning.cost(for: session.kind)
    }

    private var canAfford: Bool {
        simulation.stock(for: simulation.playerFaction).covers(cost)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                HUDGlyph(session.kind.glyph)
                    .fill(HUDInk.accent, style: session.kind.glyph.fillStyle)
                    .frame(width: 18, height: 18)
                Text(session.kind.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(SunfoldPalette.hudAccent)
                Spacer(minLength: 8)
                Text(session.isLegal ? "READY" : "BLOCKED")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(
                        session.isLegal ? HUDInk.friendly(for: simulation.playerFaction) : HUDInk.warning
                    )
            }

            Text(session.kind.purpose)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(SunfoldPalette.hudText)
                .frame(maxWidth: 220, alignment: .trailing)
                .multilineTextAlignment(.trailing)

            HStack(spacing: 6) {
                Text(cost.costSummary)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(canAfford ? SunfoldPalette.hudText : HUDInk.warning)
                if !canAfford {
                    Text("Need more Matter")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HUDInk.warning)
                }
            }

            Text(session.isLegal
                 ? "Drag to place · release to found · tap to cancel"
                 : "Move onto clear home ground")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(SunfoldPalette.hudTextDim)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HUDInk.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(ChamferedRect(cut: 6).fill(HUDInk.well))
                    .overlay(ChamferedRect(cut: 6).stroke(HUDInk.edge, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel placement")
        }
        .padding(12)
        .frame(width: 248, alignment: .trailing)
        .hudPanel(cut: 12, corners: [.topLeading, .topTrailing, .bottomLeading, .bottomTrailing])
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(session.kind.displayName). \(session.kind.purpose). \(cost.costSummary). \(session.isLegal ? "Legal" : "Illegal")."
        )
    }
}
