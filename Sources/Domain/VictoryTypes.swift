import Foundation

/// How a match was won.
///
/// `00-CONTENT-SPEC.md` §5 locks two win paths. Resignation is not a third path —
/// it is the player conceding one of the two — but the overlay has to name
/// something, and "you resigned" is more honest than reporting a Conquest that
/// never happened.
enum VictoryPath: String, Sendable, Equatable, CaseIterable {
    case conquest
    case dominion
    case resignation

    /// Sentence the end-of-match overlay puts under the verdict.
    func summary(winner: Faction) -> String {
        switch self {
        case .conquest:
            "\(winner.opponent.displayName)'s Civilization Core was destroyed."
        case .dominion:
            "\(winner.displayName) held the Dominion Spire."
        case .resignation:
            "\(winner.opponent.displayName) resigned."
        }
    }
}

/// The terminal state of a match.
///
/// Owned by `SkirmishSimulation`, never by the renderer — the HUD reads which
/// condition fired, it does not decide it. Its presence is what stops the clock:
/// once this is non-nil the simulation refuses to step.
struct MatchOutcome: Sendable, Equatable {
    let winner: Faction
    let path: VictoryPath
    /// Simulated seconds at the moment it resolved.
    let elapsed: Double
    /// The exact tick, so a replay can be cut at the same frame.
    let tick: UInt64

    func isVictory(for viewer: Faction) -> Bool { winner == viewer }

    /// "VICTORY" / "DEFEAT" from one side's chair.
    func verdict(for viewer: Faction) -> String {
        isVictory(for: viewer) ? "VICTORY" : "DEFEAT"
    }

    var summary: String { path.summary(winner: winner) }
}

/// Match time formatted the way the HUD and the logs both want it: `m:ss`.
///
/// Lives here rather than in the HUD because the victory tests assert on it and
/// the Domain layer cannot import SwiftUI.
func matchClock(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d", total / 60, total % 60)
}
