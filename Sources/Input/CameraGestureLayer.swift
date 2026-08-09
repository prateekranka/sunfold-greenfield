import SwiftUI
import UIKit
import simd

/// Direct-touch camera control, built on explicit UIKit recognizers.
///
/// SwiftUI's composed gestures were tried first and do not work here: over a
/// RealityView, `MagnifyGesture` recognises but `RotateGesture` never fires,
/// whether the two are attached as separate `.simultaneousGesture` modifiers,
/// combined into one `SimultaneousGesture`, or made peers of the pan. Verified
/// three times in the rendered build — a two-finger twist changed zoom and left
/// yaw at 0°.
///
/// UIKit recognizers also give what the touch grammar needs later: explicit
/// finger counts, so a one-finger drag pans while two fingers pinch and twist,
/// and so a lasso can be added in G1 without overloading ordinary camera pan.
struct CameraGestureLayer: UIViewRepresentable {
    let controller: WorldController
    /// Explicit so SwiftUI re-runs `updateUIView` when placement starts/stops.
    /// Without this, the ghost pan recognizer stayed disabled after Farm was tapped.
    var ghostActive: Bool

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true

        // One finger pans; two fingers pinch and twist. Keeping pan at exactly one
        // touch is what will let a lasso share the surface in G1 without
        // overloading ordinary camera pan.
        let pan = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePan)
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1

        // Ghost placement: dedicated drag — separate from camera pan so
        // the two grammars never fight. Soft SwiftUI DragGesture overlays stole
        // hits without reliably driving the ghost; this recognizer owns placement.
        let ghostPan = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleGhostPan)
        )
        ghostPan.minimumNumberOfTouches = 1
        ghostPan.maximumNumberOfTouches = 1
        ghostPan.isEnabled = false

        // Stationary tap cancels. UIPan never fires without movement, so cancel
        // cannot ride on the ghost pan alone.
        let ghostTap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleGhostTap)
        )
        ghostTap.isEnabled = false

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePinch)
        )
        let rotate = UIRotationGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleRotate)
        )

        // Press-and-hold, then drag, draws a selection lasso. A plain drag has to
        // stay camera pan — on a touch RTS the player moves the camera constantly
        // and cannot afford a mode switch to do it — so the lasso is what the
        // hold buys. Movement tolerance is tight so a drag that was meant as a
        // pan never turns into a box under the finger.
        let lasso = UILongPressGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleLasso)
        )
        lasso.minimumPressDuration = 0.22
        lasso.allowableMovement = 10

        // A tap selects or orders. It must not fire when the finger was actually
        // dragging the camera or drawing a lasso, so both must fail first. This
        // adds no latency to an ordinary tap: lifting the finger fails the long
        // press immediately, well before its 0.22 s threshold.
        let tap = UITapGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handleTap)
        )
        tap.require(toFail: pan)
        tap.require(toFail: lasso)
        // Ghost tap owns the surface while placing; keep select-tap off then.
        ghostTap.require(toFail: ghostPan)

        context.coordinator.panRecognizer = pan
        context.coordinator.ghostPanRecognizer = ghostPan
        context.coordinator.ghostTapRecognizer = ghostTap
        context.coordinator.lassoRecognizer = lasso
        context.coordinator.tapRecognizer = tap

        for recognizer in [pan, ghostPan, ghostTap, pinch, rotate, lasso, tap] as [UIGestureRecognizer] {
            recognizer.delegate = context.coordinator
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.controller = controller
        context.coordinator.applyGhostGates(ghostActive)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var controller: WorldController

        private var zoomAnchor: Float?
        private var yawAnchor: Float?
        private var lastPanTranslation: CGPoint = .zero
        private var isLassoActive = false

        /// Stationary lift cancels; drag-then-release places.
        private let ghostTapSlop: CGFloat = 10

        var panRecognizer: UIPanGestureRecognizer?
        var ghostPanRecognizer: UIPanGestureRecognizer?
        var ghostTapRecognizer: UITapGestureRecognizer?
        var lassoRecognizer: UILongPressGestureRecognizer?
        var tapRecognizer: UITapGestureRecognizer?

        init(controller: WorldController) {
            self.controller = controller
        }

        func applyGhostGates(_ ghosting: Bool) {
            panRecognizer?.isEnabled = !ghosting
            ghostPanRecognizer?.isEnabled = ghosting
            ghostTapRecognizer?.isEnabled = ghosting
            lassoRecognizer?.isEnabled = !ghosting
            tapRecognizer?.isEnabled = !ghosting
        }

        func refreshGhostGestureGates() {
            applyGhostGates(controller.buildGhost != nil)
        }

        /// Pan, pinch and twist must all recognise together, or the first one to
        /// claim the touches starves the others.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        nonisolated func gestureRecognizerShouldBegin(
            _ gestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            MainActor.assumeIsolated {
                if controller.buildGhost != nil {
                    if gestureRecognizer === panRecognizer
                        || gestureRecognizer === lassoRecognizer
                        || gestureRecognizer === tapRecognizer {
                        return false
                    }
                } else if gestureRecognizer === ghostPanRecognizer
                    || gestureRecognizer === ghostTapRecognizer {
                    return false
                }
                return true
            }
        }

        // MARK: - Ghost pan (construction placement)

        @objc func handleGhostTap(_ recognizer: UITapGestureRecognizer) {
            guard controller.buildGhost != nil, recognizer.state == .ended else { return }
            controller.cancelBuildGhost()
            applyGhostGates(false)
        }

        @objc func handleGhostPan(_ recognizer: UIPanGestureRecognizer) {
            guard controller.buildGhost != nil, let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            moveGhost(to: location, in: view)

            switch recognizer.state {
            case .ended:
                let translation = recognizer.translation(in: view)
                let travel = hypot(translation.x, translation.y)
                if travel < ghostTapSlop {
                    // Prefer ghostTap for true stationary cancels; this is a
                    // safety net when the pan still recognized a tiny move.
                    controller.cancelBuildGhost()
                    applyGhostGates(false)
                } else {
                    controller.endBuildGhostDrag()
                    applyGhostGates(controller.buildGhost != nil)
                }
            case .cancelled, .failed:
                break
            default:
                break
            }
        }

        private func moveGhost(to location: CGPoint, in view: UIView) {
            let point = SIMD2<Float>(Float(location.x), Float(location.y))
            let viewport = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
            _ = controller.moveBuildGhost(atScreenPoint: point, viewportSize: viewport)
        }

        /// Draws the selection lasso. While it is live the camera must hold still,
        /// or the box and the world slide against each other and the player ends
        /// up selecting something they were not pointing at.
        @objc func handleLasso(_ recognizer: UILongPressGestureRecognizer) {
            guard controller.buildGhost == nil else { return }
            guard let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            let point = SIMD2<Float>(Float(location.x), Float(location.y))
            let viewport = SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))

            switch recognizer.state {
            case .began:
                isLassoActive = true
                controller.beginMarquee(at: point)
            case .changed:
                controller.updateMarquee(to: point, viewportSize: viewport)
            case .ended:
                isLassoActive = false
                controller.commitMarquee(viewportSize: viewport)
            case .cancelled, .failed:
                isLassoActive = false
                controller.cancelMarquee()
            default:
                break
            }
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard controller.buildGhost == nil else { return }
            guard let view = recognizer.view else { return }
            // The pan recognizer keeps running underneath a lasso; swallowing its
            // updates here is what keeps the camera anchored, and resetting the
            // translation baseline stops the camera jumping when the lasso ends.
            guard !isLassoActive else {
                lastPanTranslation = recognizer.translation(in: view)
                return
            }
            switch recognizer.state {
            case .began:
                lastPanTranslation = .zero
            case .changed:
                let translation = recognizer.translation(in: view)
                let delta = SIMD2<Float>(
                    Float(translation.x - lastPanTranslation.x),
                    Float(translation.y - lastPanTranslation.y)
                )
                lastPanTranslation = translation
                controller.pan(screenDelta: delta, viewportHeight: Float(view.bounds.height))
            case .ended, .cancelled, .failed:
                lastPanTranslation = .zero
            default:
                break
            }
        }

        @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
            switch recognizer.state {
            case .began:
                zoomAnchor = controller.currentZoom
            case .changed:
                let anchor = zoomAnchor ?? controller.currentZoom
                let scale = Float(recognizer.scale)
                guard scale > 0.01 else { return }
                // Pinching apart magnifies, which means showing less world.
                controller.zoom(to: anchor / scale)
            case .ended, .cancelled, .failed:
                zoomAnchor = nil
            default:
                break
            }
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard controller.buildGhost == nil else { return }
            guard recognizer.state == .ended, let view = recognizer.view else { return }
            let location = recognizer.location(in: view)
            controller.handleTap(
                atScreenPoint: SIMD2<Float>(Float(location.x), Float(location.y)),
                viewportSize: SIMD2<Float>(Float(view.bounds.width), Float(view.bounds.height))
            )
        }

        @objc func handleRotate(_ recognizer: UIRotationGestureRecognizer) {
            switch recognizer.state {
            case .began:
                yawAnchor = controller.currentYaw
            case .changed:
                let anchor = yawAnchor ?? controller.currentYaw
                controller.yaw(to: anchor + Float(recognizer.rotation))
            case .ended, .cancelled, .failed:
                yawAnchor = nil
            default:
                break
            }
        }
    }
}
