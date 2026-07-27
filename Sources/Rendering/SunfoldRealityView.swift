import RealityKit
import SwiftUI

/// The world surface. Hosts the RealityKit scene and lets the gesture layer
/// translate raw touch into camera intents; it never issues game orders itself.
struct SunfoldRealityView: View {
    let controller: WorldController

    var body: some View {
        RealityView { content in
            // Every procedural map the scene will ask for, generated once before
            // anything is built.
            //
            // Without this the first structure of each material class pays the
            // generation cost inline on the main actor — measured at ~570 ms per
            // recipe in a Debug build, six recipes, scattered through scene
            // assembly as a series of hitches. `RealityView`'s make closure is
            // `async` (verified against `_RealityKit_SwiftUI.swiftinterface`), so
            // the whole warm-up runs on a detached task before the first entity
            // exists, and every `MaterialLibrary.material(...)` below is a cache
            // hit. The placeholder shown while it runs is the void colour the
            // view already sits on.
            await MaterialLibrary.preload()
            controller.attach(to: &content)
        }
        .overlay(CameraGestureLayer(controller: controller))
        // Above the gesture layer and in the same coordinate space, so the lasso
        // is drawn exactly where the finger drew it.
        .overlay(MarqueeOverlay(rect: controller.marquee?.rect, hitCount: controller.marqueeHitCount))
        .background(Color(SunfoldPalette.voidDeep))
        .ignoresSafeArea()
    }
}
