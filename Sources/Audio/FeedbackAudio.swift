import AudioToolbox
import Foundation

/// Short, non-looping cues for player-visible sim events.
///
/// G7 owns a real mix; until then these are deterministic system sounds so
/// completion is heard as well as seen.
enum FeedbackAudio {
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
