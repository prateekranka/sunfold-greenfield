import RealityKit
import SwiftUI

/// The world surface. Hosts the RealityKit scene and lets the gesture layer
/// translate raw touch into camera intents; it never issues game orders itself.
struct SunfoldRealityView: View {
    let controller: WorldController

    var body: some View {
        RealityView { content in
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
