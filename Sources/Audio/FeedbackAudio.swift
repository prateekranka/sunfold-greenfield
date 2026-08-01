import AudioToolbox
import Foundation

/// Short, non-looping cues for player-visible sim events.
///
/// G7 owns a real mix; until then these are deterministic system sounds so
/// completion is heard as well as seen.
enum FeedbackAudio {
    /// A quiet selection tick. Selection is common, so it must not compete with
    /// movement and arrival cues.
    static func unitSelected() {
        AudioServicesPlaySystemSound(1103)
    }

    /// A short order confirmation for a legal move.
    static func movementOrdered() {
        AudioServicesPlaySystemSound(1104)
    }

    /// A soft denial for an illegal or unreachable movement order.
    static func movementDenied() {
        AudioServicesPlaySystemSound(1053)
    }

    /// A restrained settle when a moving unit reaches its destination.
    static func movementArrived() {
        AudioServicesPlaySystemSound(1111)
    }

    /// A distinct low-key cue when a transport finishes at a shore berth.
    static func transportDocked() {
        AudioServicesPlaySystemSound(1105)
    }

    /// Soft confirm when a foundation commits.
    static func constructionPlaced() {
        AudioServicesPlaySystemSound(1104)
    }

    /// Bright settle when citizens finish a building.
    static func constructionComplete() {
        AudioServicesPlaySystemSound(1111)
    }

    /// Soft refuse when a place attempt is illegal or unaffordable.
    static func constructionDenied() {
        AudioServicesPlaySystemSound(1053)
    }
}
