import SwiftUI

/// The objective rail: how the match is going, and what to do about it.
///
/// This replaces `AlertStrip`, which printed the same seeded sentence — "Light
/// transport docked at home rim" — for the entire match whatever happened. Bar
/// B4c forbids lying chrome, and a strip that never changes teaches the eye to
/// stop reading it, which is worse than an empty one.
///
/// It answers the CP-C4 critic question — *at 6:00 into a match, can the player
/// tell how they are doing and what they should do about it?* — with the two win
/// paths side by side and a live alert line under them. Both Dominion timers are
/// shown, because knowing the enemy is 30 s into a 45 s hold is the difference
/// between a match you can still save and one you have already lost.
struct ObjectiveRail: View {
    @Bindable var simulation: SkirmishSimulation
    var viewer: Faction = .sunwoven
    var onNewGame: (() -> Void)? = nil

    @State private var confirmingResign = false

    private var requirement: Double { simulation.dominionRequirement }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            clock
            divider
            dominion
            divider
            cores
            Spacer(minLength: 8)
            latestAlert
            resign
            if let onNewGame {
                Button("NEW GAME", action: onNewGame)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(HUDInk.textDim)
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start a new game")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: 720, alignment: .leading)
        .hudSurface(
            cut: 8,
            corners: [.bottomLeading, .bottomTrailing],
            lineWidth: 0.75,
            shadow: false
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(HUDInk.edge.opacity(0.7))
            .frame(width: 1, height: 20)
    }

    // MARK: - Match clock

    private var clock: some View {
        Text(matchClock(simulation.elapsed))
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(HUDInk.text)
            .accessibilityLabel("Match time \(matchClock(simulation.elapsed))")
    }

    // MARK: - Dominion

    /// Two bars, mine over theirs, with the requirement spelled out so the
    /// escalation from 45 s to 20 s is visible rather than a surprise.
    private var dominion: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("DOMINION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(HUDInk.textDim)
                Text(holdLabel(for: viewer))
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(contested ? HUDInk.warning : HUDInk.text)
                if contested {
                    Text("CONTESTED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(HUDInk.warning)
                }
            }
            meter(
                fraction: simulation.dominionProgress(for: viewer),
                tint: HUDInk.friendly(for: viewer)
            )
            meter(
                fraction: simulation.dominionProgress(for: viewer.opponent),
                tint: HUDInk.hostile(for: viewer)
            )
        }
        .frame(width: 150, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dominionSpokenLabel)
    }

    private var contested: Bool { simulation.isDominionContested(for: viewer) }

    private func holdLabel(for faction: Faction) -> String {
        "\(Int(simulation.dominionHold(for: faction)))s / \(Int(requirement))s"
    }

    private var dominionSpokenLabel: String {
        let mine = Int(simulation.dominionHold(for: viewer))
        let theirs = Int(simulation.dominionHold(for: viewer.opponent))
        let state = contested ? ", contested" : ""
        return "Dominion: you \(mine) of \(Int(requirement)) seconds, enemy \(theirs)\(state)"
    }

    private func meter(fraction: Double, tint: Color) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(HUDInk.well)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
        .frame(height: 4)
    }

    // MARK: - Cores

    /// The Conquest readout. A Core at a quarter life is the loudest thing that
    /// can be true about a match, and until now it was only legible by selecting
    /// the building.
    private var cores: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("CORES")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(HUDInk.textDim)
            meter(fraction: simulation.coreLifeFraction(for: viewer), tint: coreTint)
            meter(
                fraction: simulation.coreLifeFraction(for: viewer.opponent),
                tint: HUDInk.hostile(for: viewer)
            )
        }
        .frame(width: 96, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Cores: yours \(Int(simulation.coreLifeFraction(for: viewer) * 100)) percent, "
                + "enemy \(Int(simulation.coreLifeFraction(for: viewer.opponent) * 100)) percent"
        )
    }

    private var coreTint: Color {
        simulation.coreLifeFraction(for: viewer) <= 0.25 ? HUDInk.warning : HUDInk.life
    }

    // MARK: - Alerts

    /// One line, the newest. A feed the player has to read during a fight is a
    /// feed they will not read.
    private var latestAlert: some View {
        Group {
            if let event = simulation.victory.events.last {
                HStack(spacing: 6) {
                    HUDGlyph(.alert)
                        .fill(
                            event.severity == .bad ? HUDInk.warning : HUDInk.friendly(for: viewer),
                            style: HUDGlyph.Kind.alert.fillStyle
                        )
                        .frame(width: 10, height: 10)
                    Text(event.text)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(HUDInk.text)
                        .lineLimit(1)
                }
                .accessibilityLabel("Alert: \(event.text)")
            }
        }
    }

    // MARK: - Resign

    /// Two taps, because a one-tap resign next to a live HUD is a trap. The
    /// spec puts this in a pause menu; there is no pause menu yet, and leaving
    /// `resign()` unreachable would make it dead code.
    private var resign: some View {
        Button {
            if confirmingResign {
                simulation.resign(as: viewer)
                confirmingResign = false
            } else {
                confirmingResign = true
            }
        } label: {
            Text(confirmingResign ? "CONFIRM" : "RESIGN")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(confirmingResign ? HUDInk.warning : HUDInk.textDim)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay {
                    ChamferedRect(cut: 4)
                        .stroke(
                            confirmingResign ? HUDInk.warning : HUDInk.edge,
                            lineWidth: 0.75
                        )
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(confirmingResign ? "Confirm resignation" : "Resign")
    }
}
