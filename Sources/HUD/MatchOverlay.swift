import SwiftUI

/// The end of a match.
///
/// It names the verdict, the condition that fired and the time it took, and
/// offers the one thing a player wants next. Nothing is running behind it: the
/// simulation refuses to step once `MatchOutcome` is set, so this is a stopped
/// world rather than a panel over a live one — which is the CP-C4 bar.
///
/// The renderer decides none of this. `outcome.path` is read, not inferred.
struct MatchOverlay: View {
    let outcome: MatchOutcome
    var viewer: Faction = .sunwoven
    let onPlayAgain: () -> Void
    let onNewGame: () -> Void

    private var won: Bool { outcome.isVictory(for: viewer) }

    var body: some View {
        ZStack {
            // Dim rather than hide. The last frame of the match is information —
            // where the fight ended, what was left standing — and a solid
            // curtain throws it away.
            Color.black.opacity(0.55)
                .ignoresSafeArea()

            VStack(spacing: 14) {
                Text(outcome.verdict(for: viewer))
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .tracking(6)
                    .foregroundStyle(won ? HUDInk.accent : HUDInk.hostile(for: viewer))
                    .shadow(color: (won ? HUDInk.accent : HUDInk.hostile(for: viewer)).opacity(0.45), radius: 14)

                Text(condition)
                    .font(.system(size: 13, weight: .bold))
                    .tracking(1.6)
                    .foregroundStyle(HUDInk.textDim)

                Text(outcome.summary)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HUDInk.text)
                    .multilineTextAlignment(.center)

                Text("Match time \(matchClock(outcome.elapsed))")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(HUDInk.textDim)

                HStack(spacing: 12) {
                    Button(action: onPlayAgain) {
                        Text("PLAY AGAIN")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(HUDInk.accent)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .overlay {
                                ChamferedRect(cut: 8)
                                    .stroke(HUDInk.edgeBright, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play again")

                    Button(action: onNewGame) {
                        Text("NEW GAME")
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(HUDInk.textDim)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 11)
                            .overlay {
                                ChamferedRect(cut: 8)
                                    .stroke(HUDInk.edge, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start a new game")
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 52)
            .padding(.vertical, 34)
            .hudSurface(cut: 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(outcome.verdict(for: viewer)) by \(condition). \(outcome.summary)")
        }
        .transition(.opacity)
    }

    /// The win path, spelled the way the spec names it.
    private var condition: String {
        switch outcome.path {
        case .conquest: "CONQUEST"
        case .dominion: "DOMINION"
        case .resignation: "RESIGNATION"
        }
    }
}
