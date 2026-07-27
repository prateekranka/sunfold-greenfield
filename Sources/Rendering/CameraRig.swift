import Foundation
import RealityKit
import simd

/// The orthographic high three-quarter camera, expressed as a yaw/zoom/focus rig.
///
/// Structure is deliberately three nested entities so yaw and pitch never fight:
///   root (focus position, yaw about Y) → pitch node (fixed tilt) → camera (pulled back)
@MainActor
final class CameraRig {
    let root = Entity()
    private let pitchNode = Entity()
    private let camera = Entity()

    private let tuning: SkirmishTuning
    private let bounds: WorldPoint
    /// The void card. Counter-scaled with zoom so stars hold a constant size on screen.
    private var sky: Entity?

    /// Focus point on the world plane. The camera always looks at this.
    private(set) var focus: WorldPoint
    /// Rotation about Y in radians. 0 is north-up.
    private(set) var yaw: Float = 0
    /// Vertical world extent visible, in metres. Smaller is closer in.
    private(set) var zoom: Float

    init(tuning: SkirmishTuning, map: WorldMap, focus: WorldPoint) {
        self.tuning = tuning
        self.bounds = map.bounds
        self.focus = focus
        self.zoom = tuning.cameraDefaultZoom

        var orthographic = OrthographicCameraComponent()
        orthographic.near = 0.5
        orthographic.far = tuning.cameraFarPlane
        // RealityKit's orthographic `scale` is the HALF vertical extent, while
        // `zoom` here means the full world height on screen. Measured against a
        // known-size fragment in the rendered build, not assumed from the docs.
        orthographic.scale = zoom * 0.5
        orthographic.scaleDirection = .vertical
        camera.components.set(orthographic)

        // A camera looks down its local -Z, so pulling it back along +Z leaves it
        // aimed straight through the pitch node's origin at the focus point.
        camera.position = [0, 0, tuning.cameraDistance]

        let pitch = tuning.cameraPitchDegrees * .pi / 180
        pitchNode.orientation = simd_quatf(angle: -pitch, axis: [1, 0, 0])

        pitchNode.addChild(camera)
        root.addChild(pitchNode)
        applyTransform()
    }

    // MARK: - Intents

    /// Pans by a world-space delta already resolved from the drag gesture.
    func pan(by delta: WorldPoint) {
        focus = clampToBounds(focus + delta)
        applyTransform()
    }

    func setFocus(_ point: WorldPoint) {
        focus = clampToBounds(point)
        applyTransform()
    }

    func setYaw(_ radians: Float) {
        yaw = radians.truncatingRemainder(dividingBy: 2 * .pi)
        applyTransform()
    }

    func setZoom(_ value: Float) {
        zoom = min(max(value, tuning.cameraMinZoom), tuning.cameraMaxZoom)
        var orthographic = camera.components[OrthographicCameraComponent.self] ?? OrthographicCameraComponent()
        orthographic.scale = zoom * 0.5
        camera.components.set(orthographic)
        applySkyScale()
    }

    /// Attaches the void card behind the world. It rides the rig because an
    /// orthographic projection cannot show a world-space sky (see StarfieldFactory).
    func attachSky(_ entity: Entity) {
        sky = entity
        pitchNode.addChild(entity)
        applySkyScale()
    }

    private func applySkyScale() {
        guard let sky else { return }
        let factor = zoom / tuning.cameraDefaultZoom
        sky.scale = [factor, factor, 1]
    }

    /// One-tap return to north, used by the compass control.
    func returnNorth() { setYaw(0) }


    /// Converts a screen-space drag into world-plane motion under the current yaw,
    /// so dragging always moves the world the way the finger moved.
    func worldDelta(forScreenDelta screenDelta: SIMD2<Float>, viewportHeight: Float) -> WorldPoint {
        guard viewportHeight > 0 else { return .zero }
        let metresPerPoint = zoom / viewportHeight
        let pitch = tuning.cameraPitchDegrees * .pi / 180

        // Screen-vertical motion is foreshortened by the tilt; screen-horizontal is not.
        let alongX = -screenDelta.x * metresPerPoint
        let alongZ = -screenDelta.y * metresPerPoint / max(sin(pitch), 0.2)

        // Rotate the camera-relative delta into world space.
        let cosine = cos(yaw), sine = sin(yaw)
        return [alongX * cosine + alongZ * sine, -alongX * sine + alongZ * cosine]
    }

    /// Unprojects a screen point onto the world ground plane (y = 0).
    ///
    /// Orthographic projection has no perspective divide, so every screen point
    /// maps to a parallel ray along the view direction; this intersects that ray
    /// with the ground. It is the single conversion used for selection, move
    /// orders and lasso hit-testing, so touch always agrees with what is drawn.
    func worldPoint(fromScreen point: SIMD2<Float>, viewportSize: SIMD2<Float>) -> WorldPoint? {
        guard viewportSize.x > 0, viewportSize.y > 0 else { return nil }
        let basis = cameraBasis()

        // Ground is never parallel to the view at the pitches this camera allows,
        // but guard anyway rather than dividing by a vanishing component.
        guard abs(basis.back.y) > 1e-5 else { return nil }

        let ndcX = (point.x / viewportSize.x) * 2 - 1
        let ndcY = 1 - (point.y / viewportSize.y) * 2
        let extent = viewExtent(viewportSize: viewportSize)

        let rayOrigin = cameraOrigin(basis)
            + basis.right * (ndcX * extent.halfWidth)
            + basis.up * (ndcY * extent.halfHeight)

        let travel = rayOrigin.y / basis.back.y
        let ground = rayOrigin - basis.back * travel
        return WorldPoint(ground.x, ground.z)
    }

    /// Projects a point on the world plane back to screen space.
    ///
    /// The exact inverse of `worldPoint(fromScreen:)`, sharing one basis so the
    /// two can never drift apart under yaw. Marquee selection needs this
    /// direction: unprojecting the four corners of a screen rectangle would give
    /// a *rotated* world quad to test against, whereas projecting each unit and
    /// testing a plain screen rectangle is both simpler and exactly what the
    /// player drew.
    ///
    /// There is no perspective divide, so this stays valid for points behind the
    /// focus and needs no w-clip.
    func screenPoint(forWorld point: WorldPoint, viewportSize: SIMD2<Float>) -> SIMD2<Float>? {
        guard viewportSize.x > 0, viewportSize.y > 0 else { return nil }
        let basis = cameraBasis()
        let extent = viewExtent(viewportSize: viewportSize)
        guard extent.halfWidth > 0, extent.halfHeight > 0 else { return nil }

        let relative = SIMD3<Float>(point.x, 0, point.y) - cameraOrigin(basis)
        let ndcX = simd_dot(relative, basis.right) / extent.halfWidth
        let ndcY = simd_dot(relative, basis.up) / extent.halfHeight

        return SIMD2<Float>(
            (ndcX + 1) * 0.5 * viewportSize.x,
            (1 - ndcY) * 0.5 * viewportSize.y
        )
    }

    /// Camera basis in world space, derived from the same yaw/pitch rig the
    /// renderer uses — not a second, drifting copy of the transform.
    private func cameraBasis() -> (right: SIMD3<Float>, up: SIMD3<Float>, back: SIMD3<Float>) {
        let pitch = tuning.cameraPitchDegrees * .pi / 180
        let sinPitch = sin(pitch), cosPitch = cos(pitch)
        let sinYaw = sin(yaw), cosYaw = cos(yaw)
        return (
            right: SIMD3<Float>(cosYaw, 0, -sinYaw),
            up: SIMD3<Float>(-sinPitch * sinYaw, cosPitch, -sinPitch * cosYaw),
            back: SIMD3<Float>(cosPitch * sinYaw, sinPitch, cosPitch * cosYaw)
        )
    }

    private func cameraOrigin(_ basis: (right: SIMD3<Float>, up: SIMD3<Float>, back: SIMD3<Float>)) -> SIMD3<Float> {
        SIMD3<Float>(focus.x, 0, focus.y) + basis.back * tuning.cameraDistance
    }

    private func viewExtent(viewportSize: SIMD2<Float>) -> (halfWidth: Float, halfHeight: Float) {
        let halfHeight = zoom * 0.5
        return (halfHeight * (viewportSize.x / viewportSize.y), halfHeight)
    }

    private func clampToBounds(_ point: WorldPoint) -> WorldPoint {
        [min(max(point.x, -bounds.x), bounds.x), min(max(point.y, -bounds.y), bounds.y)]
    }

    private func applyTransform() {
        root.position = [focus.x, 0, focus.y]
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }
}
