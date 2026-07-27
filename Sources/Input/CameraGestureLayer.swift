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

    func makeCoordinator() -> Coordinator { Coordinator(controller: controller) }

    func makeUIView(context: Context) -> UIView {
        let view = TouchPassthroughView()
        view.backgroundColor = .clear

        // One finger pans; two fingers pinch and twist. Keeping pan at exactly one
        // touch is what will let a lasso share the surface in G1 without
        // overloading ordinary camera pan.
        let pan = UIPanGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.handlePan)
        )
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1

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

        for recognizer in [pan, pinch, rotate, lasso, tap] as [UIGestureRecognizer] {
            recognizer.delegate = context.coordinator
            view.addGestureRecognizer(recognizer)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.controller = controller
    }

    /// Lets touches reach the RealityView beneath while still feeding recognizers.
    private final class TouchPassthroughView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { true }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var controller: WorldController

        private var zoomAnchor: Float?
        private var yawAnchor: Float?
        private var lastPanTranslation: CGPoint = .zero
        private var isLassoActive = false

        init(controller: WorldController) {
            self.controller = controller
        }

        /// Pan, pinch and twist must all recognise together, or the first one to
        /// claim the touches starves the others.
        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        /// Draws the selection lasso. While it is live the camera must hold still,
        /// or the box and the world slide against each other and the player ends
        /// up selecting something they were not pointing at.
        @objc func handleLasso(_ recognizer: UILongPressGestureRecognizer) {
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
