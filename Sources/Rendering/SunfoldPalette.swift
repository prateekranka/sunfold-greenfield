import Foundation
import SwiftUI
import UIKit

/// The locked colour identity, transcribed from the approved visual bible.
///
/// Warm sun-woven life against cool gravity distortion. Saturated red-black is
/// reserved for danger and contested alerts and appears nowhere else.
enum SunfoldPalette {
    // MARK: - Void

    /// Reads as black-indigo rather than pure black on a real panel; the darker
    /// value it replaced was indistinguishable from #000 in the rendered build.
    static let voidDeep = UIColor(red: 0.039, green: 0.045, blue: 0.105, alpha: 1)
    static let voidHorizon = UIColor(red: 0.055, green: 0.062, blue: 0.130, alpha: 1)
    static let starWarm = UIColor(red: 1.00, green: 0.95, blue: 0.86, alpha: 1)
    static let starCool = UIColor(red: 0.82, green: 0.88, blue: 1.00, alpha: 1)

    // MARK: - Sunwoven

    /// The warm stone family sits at **hue 34°**, not 40°.
    ///
    /// Measured off `cp05-hud-chrome.png` against concept 01, on hand-picked bare
    /// ground in both: the concept reads rgb(0.776, 0.655, 0.506) — hue 33.0° —
    /// and the build read rgb(0.757, 0.682, 0.506) — hue 42.2°. Red and blue
    /// already matched to within 2%; the entire 9° error was **green**, and it
    /// repeated on every lit surface in the frame (rim stone 41.8°, foliage
    /// 40.3°, the near-white transport hull 41.1°) against 32–35° for the same
    /// surfaces in the concept.
    ///
    /// One error on every surface is one cause, so the rotation is split between
    /// the two things every surface shares: these albedos and
    /// `LightingRig.Tuning.keyColor`. Neither is dragged far enough on its own to
    /// stop reading as what it is — the sand stays sand, the sun stays a warm
    /// gold spill — and the product lands where the concept is.
    ///
    /// Value and saturation were checked at the same time and are **not** wrong:
    /// 0.757 against 0.776 and 0.332 against 0.348. CP-03's exposure calibration
    /// holds. Do not reach for either.
    static let sunwovenSurface = UIColor(red: 0.855, green: 0.778, blue: 0.678, alpha: 1)
    static let sunwovenRock = UIColor(red: 0.612, green: 0.554, blue: 0.478, alpha: 1)
    static let sunwovenGold = UIColor(red: 0.855, green: 0.655, blue: 0.282, alpha: 1)
    static let sunwovenIvory = UIColor(red: 0.960, green: 0.933, blue: 0.878, alpha: 1)
    static let sunwovenTurquoise = UIColor(red: 0.294, green: 0.706, blue: 0.706, alpha: 1)

    // MARK: - Gravemark

    static let gravemarkSurface = UIColor(red: 0.302, green: 0.330, blue: 0.396, alpha: 1)
    static let gravemarkRock = UIColor(red: 0.208, green: 0.231, blue: 0.286, alpha: 1)
    static let gravemarkCopper = UIColor(red: 0.651, green: 0.400, blue: 0.220, alpha: 1)
    static let gravemarkMineral = UIColor(red: 0.353, green: 0.463, blue: 0.596, alpha: 1)

    // MARK: - Neutral

    static let neutralSurface = UIColor(red: 0.616, green: 0.600, blue: 0.573, alpha: 1)
    static let neutralRock = UIColor(red: 0.427, green: 0.416, blue: 0.400, alpha: 1)
    static let dominionStone = UIColor(red: 0.741, green: 0.729, blue: 0.702, alpha: 1)

    /// The colour that stands for each resource, wherever it appears — a carried
    /// load, a deposit's ground pool, the HUD rail. One source, so a player never
    /// has to learn the same resource twice.
    static func resourceTint(_ kind: ResourceKind) -> UIColor {
        switch kind {
        case .provisions: UIColor(red: 0.784, green: 0.612, blue: 0.290, alpha: 1)
        case .matter: UIColor(red: 0.620, green: 0.639, blue: 0.678, alpha: 1)
        case .lumen: UIColor(red: 0.949, green: 0.808, blue: 0.408, alpha: 1)
        case .aether: UIColor(red: 0.361, green: 0.749, blue: 0.729, alpha: 1)
        }
    }

    /// Surface and rock colours for a fragment, by who holds it at match start.
    static func fragmentColors(for region: RegionID) -> (surface: UIColor, rock: UIColor) {
        switch region {
        case .sunwovenHome, .sunwovenExpansion:
            (sunwovenSurface, sunwovenRock)
        case .gravemarkHome, .gravemarkExpansion:
            (gravemarkSurface, gravemarkRock)
        case .dominion:
            (dominionStone, neutralRock)
        case .neutralOutcropNorth, .neutralOutcropSouth:
            (neutralSurface, neutralRock)
        }
    }

    // MARK: - SwiftUI bridges for the HUD

    /// Fully opaque, and deeper than `voidDeep` rather than equal to it.
    ///
    /// Translucency was tried twice and failed both times. At 0.82 a starfield
    /// square landed inside the Lumen glyph; at 0.95 the same star was still
    /// visible — measured in the rendered build at rgb(21,23,32) against a panel
    /// of rgb(11,13,24), so a bright star bleeds through even 5% of alpha and
    /// reads as a chip out of the icon. A HUD panel has to be a clean surface.
    ///
    /// Going *darker* than the void is what keeps it reading as a panel once the
    /// alpha is gone: over the diorama it separates by value, and over open space
    /// it reads as an inset cut into the void with a gold edge, instead of
    /// vanishing into a background it happens to match.
    static var hudPanel: Color { Color(red: 0.020, green: 0.024, blue: 0.052) }
    static var hudEdge: Color { Color(red: 0.855, green: 0.655, blue: 0.282).opacity(0.45) }
    static var hudText: Color { Color(red: 0.945, green: 0.925, blue: 0.882) }
    static var hudTextDim: Color { Color(red: 0.945, green: 0.925, blue: 0.882).opacity(0.62) }
    static var hudAccent: Color { Color(sunwovenGold) }
}
