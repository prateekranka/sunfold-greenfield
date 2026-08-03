import QuartzCore
import SwiftUI
import UIKit

/// Deliberate 60 fps render cadence for the RealityKit scene.
///
/// Without an explicit target, Core Animation follows the panel's maximum refresh
/// — 120 Hz on ProMotion iPads — and the game chases an 8.33 ms budget it was
/// never sized for. Capping at 60 keeps the frame budget at 16.67 ms on every
/// device and avoids the harsher judder of missing 120.
///
/// The simulation stays on a fixed 20 Hz step (`SimulationClock`); this only
/// declares a render cadence preference, never how many steps run.
enum FramePacing {
    /// Product target until a future high-refresh opt-in exists.
    static let targetFPS: Float = 60

    /// Steady 60 fps with room to dip under load without fighting ProMotion.
    static let frameRateRange = CAFrameRateRange(
        minimum: 30,
        maximum: targetFPS,
        preferred: targetFPS
    )

    static let targetFrameBudgetSeconds: Double = 1.0 / Double(targetFPS)
}

extension View {
    /// Pins the hosting run loop to the product 60 fps cadence.
    func sunfoldFramePacing() -> some View {
        background(FramePacingHost())
    }
}

/// Keeps a `CADisplayLink` alive for the scene window with `preferredFrameRateRange`.
private struct FramePacingHost: UIViewRepresentable {
    func makeUIView(context: Context) -> FramePacingView {
        FramePacingView()
    }

    func updateUIView(_ uiView: FramePacingView, context: Context) {}
}

private final class FramePacingView: UIView {
    private var displayLink: CADisplayLink?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            stopDisplayLink()
        } else {
            startDisplayLinkIfNeeded()
        }
    }

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil, window != nil else { return }

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = FramePacing.frameRateRange
        link.add(to: .main, forMode: .common)
        displayLink = link

        if ProcessInfo.processInfo.arguments.contains("-sunfoldPerf"),
           let panelMax = window?.windowScene?.screen.maximumFramesPerSecond {
            print("[sunfold.perf] frame_pacing displayLink panelMaxFPS=\(panelMax) target=60")
        }
    }

    private func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        // No-op: declares cadence via `preferredFrameRateRange`; RealityKit owns updates.
    }
}
