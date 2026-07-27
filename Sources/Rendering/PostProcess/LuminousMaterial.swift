import Foundation
import RealityKit
import UIKit

/// The emissive half of the bloom contract.
///
/// The public RealityView API on iOS 26.5 exposes no HDR render path
/// (`RealityViewDynamicRange` has only `.default` and `.standard`, and the HDR
/// switch behind it is internal), so the frame the post pass receives is
/// display-referred and everything in it is clamped to 1.0. A physical
/// bright-pass keyed on nits is therefore impossible; bloom has to be keyed on
/// *relative* luminance, and that only separates luminous surfaces from lit ones
/// if the luminous surfaces are actually authored bright.
///
/// The locked palette is not: `sunwovenGold` is (0.855, 0.655, 0.282), whose
/// linear luminance is 0.43 — below a lit regolith facet. Rendered as-is, a glow
/// seam is dimmer than the ground it sits on, and no threshold can pick it out.
///
/// `luminous` fixes that without inventing a hue. It normalises the colour so its
/// brightest channel reaches 1.0 — which preserves the channel *ratios*, i.e. the
/// hue, exactly — and then mixes a small amount of white in for the core, the way
/// a real emitter clips toward white at its centre. Gold stays gold; it just
/// stops pretending to be a diffuse paint chip.
@MainActor
enum LuminousMaterial {

    /// How far the normalised colour is pushed toward white. Gold and copper have
    /// a low blue channel, so without a little whitening their linear luminance
    /// stays under the bloom threshold even at full saturation.
    static let defaultWhiten: Float = 0.25

    /// Hue-preserving lift of a palette colour to emitter brightness.
    ///
    /// - Parameters:
    ///   - color: any colour from `SunfoldPalette`.
    ///   - strength: 0 leaves the colour alone, 1 takes its brightest channel to
    ///     full. Values in between are for accents that should read as lit rather
    ///     than as sources.
    ///   - whiten: how much white is mixed into the result afterwards.
    static func luminous(
        _ color: UIColor,
        strength: Float = 1.0,
        whiten: Float = defaultWhiten
    ) -> UIColor {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return color }

        let peak = max(max(red, green), blue)
        guard peak > 0.001 else { return color }

        // Scaling every channel by the same factor is what keeps the hue fixed.
        let normalise = 1 + (1 / peak - 1) * CGFloat(max(0, min(1, strength)))
        let mix = CGFloat(max(0, min(1, whiten)))
        func lift(_ channel: CGFloat) -> CGFloat {
            let scaled = min(channel * normalise, 1)
            return min(scaled + (1 - scaled) * mix, 1)
        }

        return UIColor(red: lift(red), green: lift(green), blue: lift(blue), alpha: alpha)
    }

    /// An `UnlitMaterial` for something that is genuinely a light source.
    ///
    /// `applyPostProcessToneMap: false` is deliberate. RealityKit's own tone
    /// mapping would pull the authored colour back down before our pass ever sees
    /// it, which is exactly the wrong order — the seam would be darkened for being
    /// bright, and then fail the bright-pass it was darkened out of. Opting out
    /// means the value we author is the value in the framebuffer, which is what
    /// makes `SunfoldPostProcess.Tuning.threshold` a number that can be reasoned
    /// about instead of guessed.
    static func unlit(
        _ color: UIColor,
        strength: Float = 1.0,
        whiten: Float = defaultWhiten,
        opacity: CGFloat = 1.0
    ) -> UnlitMaterial {
        var material = UnlitMaterial(
            color: luminous(color, strength: strength, whiten: whiten),
            applyPostProcessToneMap: false
        )
        material.faceCulling = .none
        // An alpha on the tint alone does not make an UnlitMaterial translucent;
        // it renders opaque until `blending` says otherwise.
        if opacity < 1 {
            material.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))
        }
        return material
    }
}
