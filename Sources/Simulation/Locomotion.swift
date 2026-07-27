import Foundation
import simd

/// Ground-unit movement feel: distance-driven walk phase, movement-state
/// hysteresis, and rate-limited facing with a deadband.
///
/// Deliberately renderer-independent — Foundation and simd only. The simulation
/// owns movement truth, so the rules that decide *whether a unit is walking* and
/// *which way it is looking* have to live here, not in the RealityKit layer.
/// Presentation reads `phase`, `facing` and `pose` and applies them to the mesh
/// rig; it never decides any of them.
///
/// Everything in this file is deterministic and free of global state: the same
/// `EntityID` and the same sequence of `update` calls always produce the same
/// numbers, on any machine, in any replay.

// MARK: - Movement state

/// Coarse movement state.
///
/// Deliberately two-valued. The walk cycle only needs to know whether feet are
/// carrying the unit, and every additional state is one more boundary that can
/// flicker while a unit eases onto its destination.
enum MovementState: String, Sendable {
    case idle
    case walking
}

// MARK: - Tuning

/// Every locomotion constant, in one place.
///
/// These are feel values, not balance values, which is why they are not in
/// `SkirmishTuning` — changing them cannot change who wins. They are still
/// gathered into a struct so a designer can retune the whole gait from one
/// place and so tests can drive edge cases without touching the defaults.
struct LocomotionTuning: Sendable {
    static let baseline = LocomotionTuning()

    // MARK: Movement state

    /// Speed at which a unit commits to walking, and the lower speed at which it
    /// gives walking up. The gap between them is the hysteresis band: a unit
    /// decelerating onto a destination crosses it once instead of oscillating
    /// around a single threshold and stuttering between idle and walk.
    var walkEnterSpeed: Float = 0.35
    var walkExitSpeed: Float = 0.15

    /// Time constant of the speed low-pass, in seconds. One noisy step of the
    /// pathing solver must not be able to flip the state machine on its own.
    var speedSmoothing: Float = 0.10

    /// Seconds for the gait to fade fully in or out. The hysteresis stops the
    /// *state* flickering; this stops the *visual* popping when it does change.
    var gaitBlend: Float = 0.18

    // MARK: Gait

    /// Ground distance covered by one full two-step cycle, in metres. The phase
    /// advances with distance travelled and never with elapsed time, which is
    /// what keeps feet from skating when a unit accelerates or is slowed.
    var strideLength: Float = 1.30

    /// Speed the swing amplitudes are authored against. A unit moving slower
    /// than this leans and swings proportionally less.
    var referenceSpeed: Float = 1.60

    /// Peak swing of a leg about its hip, in radians (~26°).
    var legSwing: Float = 0.46
    /// Peak swing of an arm about its shoulder, in radians (~18°).
    var armSwing: Float = 0.32
    /// Forward lean of the chest at full speed, in radians (~6°).
    var torsoLean: Float = 0.11
    /// Shoulder counter-rotation against the hips, in radians (~3°).
    var torsoCounterSwing: Float = 0.055
    /// Vertical rise of the body between footfalls, in metres.
    var bobHeight: Float = 0.035

    /// How much of the gait survives under reduced motion. Not zero: a unit that
    /// slides with frozen feet reads as broken, and the player still needs to see
    /// at a glance which units are moving.
    var reducedMotionScale: Float = 0.40

    // MARK: Facing

    /// Heading change required before a unit re-aims, in radians (12°). Below
    /// this the unit keeps its current aim, so path noise and the sideways
    /// shuffle of crowd avoidance cannot make it swivel.
    var facingDeadband: Float = 12 * .pi / 180

    /// Upper bound on turn speed, in radians per second (~344°/s). Facing is
    /// always integrated toward the target at this rate, never snapped.
    var maxTurnRate: Float = 6

    /// Below this speed the movement direction is noise rather than intent, so
    /// steering is suspended and the unit keeps looking where it was looking.
    var steerMinimumSpeed: Float = 0.12

    /// Longest step the integrator will honour, in seconds. A frame hitch must
    /// not be able to whip a unit a third of a turn in one update.
    var maxDeltaTime: Float = 0.25
}

// MARK: - Limb pose

/// One frame of the walk cycle, as angles to apply to the mesh rig built by
/// `UnitMeshes`.
///
/// Every angle is in radians **about the part's own local X axis** and is
/// applied directly — `simd_quatf(angle: pose.legLeftPitch, axis: [1, 0, 0])` —
/// with no sign flipping at the call site.
///
/// Because a positive rotation about +X carries local −Z upward, the sign reads
/// differently depending on where a part's mass sits relative to its pivot:
/// for legs and arms, which hang below their pivot, positive swings the foot or
/// hand forward; for the torso, whose mass is above its pivot, a forward lean is
/// negative. `torsoPitch` already carries that sign, so callers just apply it.
struct LimbPose: Sendable, Equatable {
    /// Front legs. On a quadruped these are the fore pair.
    var legLeftPitch: Float = 0
    var legRightPitch: Float = 0
    /// Rear legs of a quadruped, in a diagonal trot against the front pair.
    /// Bipeds ignore these.
    var rearLegLeftPitch: Float = 0
    var rearLegRightPitch: Float = 0
    /// Arms counter-swing against the leg on the same side.
    var armLeftPitch: Float = 0
    var armRightPitch: Float = 0
    /// Forward lean plus a small stride bounce. Already signed for direct use.
    var torsoPitch: Float = 0
    /// Shoulder counter-rotation about the part's local Y axis. Optional garnish;
    /// a renderer may apply only `torsoPitch` and still look correct.
    var torsoYaw: Float = 0
    /// Vertical rise of the torso above its rest height, in metres. Never
    /// negative, so a unit cannot sink through the ground it stands on.
    var bob: Float = 0

    /// The neutral standing pose.
    static let rest = LimbPose()
}

// MARK: - Pure math

/// Small pure helpers, exposed so they can be tested directly.
enum LocomotionMath {
    static let twoPi: Float = 2 * .pi

    static func clamp(_ value: Float, _ lower: Float, _ upper: Float) -> Float {
        min(max(value, lower), upper)
    }

    /// Wraps an angle into `[0, 2π)`.
    static func wrapPositive(_ angle: Float) -> Float {
        let wrapped = angle.truncatingRemainder(dividingBy: twoPi)
        return wrapped < 0 ? wrapped + twoPi : wrapped
    }

    /// Wraps an angle into `(-π, π]`.
    static func wrapSigned(_ angle: Float) -> Float {
        var wrapped = angle.truncatingRemainder(dividingBy: twoPi)
        if wrapped > .pi { wrapped -= twoPi }
        if wrapped <= -.pi { wrapped += twoPi }
        return wrapped
    }

    /// Signed shortest rotation from `from` to `to`, in `(-π, π]`.
    static func shortestAngle(from: Float, to: Float) -> Float {
        wrapSigned(to - from)
    }

    /// Yaw, in radians about +Y, that points a unit along `direction` on the
    /// world plane. Zero is north (−Z), matching `WorldMap`'s north-up contract.
    ///
    /// A yaw of θ carries the default forward (0, 0, −1) to (−sin θ, 0, −cos θ),
    /// which is the inverse this solves.
    static func heading(of direction: WorldPoint) -> Float {
        atan2(-direction.x, -direction.y)
    }

    /// Unit forward vector on the world plane for a yaw.
    static func forward(for yaw: Float) -> WorldPoint {
        WorldPoint(-sin(yaw), -cos(yaw))
    }

    /// The unit's fixed offset into the walk cycle, in radians.
    ///
    /// Derived from durable identity rather than spawn order or array position,
    /// so four citizens ordered to the same place arrive out of step with each
    /// other and stay that way across a save, a replay and a rejoin.
    static func phaseOffset(for id: EntityID) -> Float {
        var random = DeterministicRandom.stream(seed: UInt64(id.raw), tag: "locomotion.phase")
        return random.float(in: 0...twoPi)
    }

    /// Per-unit stride multiplier.
    ///
    /// A fixed phase offset alone still leaves a group in a fixed pattern — the
    /// same beat, permanently rotated. Slightly different stride lengths make
    /// the pattern drift, which is what actually kills the lockstep read.
    static func strideScale(for id: EntityID) -> Float {
        var random = DeterministicRandom.stream(seed: UInt64(id.raw), tag: "locomotion.stride")
        return random.float(in: 0.94...1.06)
    }

    /// The walk cycle for one instant, as rig angles.
    ///
    /// Pure: no state, no time. Given the same inputs it always returns the same
    /// pose, which makes the whole gait testable without stepping a simulation.
    ///
    /// - Parameters:
    ///   - phase: Cycle position in radians. Advances with distance, not time.
    ///   - gait: 0…1 blend into the walk cycle, so entering and leaving a walk
    ///     fades rather than pops.
    ///   - speedFraction: Speed relative to `tuning.referenceSpeed`, 0…1.
    ///   - reducedMotion: Simplifies the gait — smaller swing, no bob, no
    ///     counter-rotation — while keeping the legs moving.
    static func pose(
        phase: Float,
        gait: Float,
        speedFraction: Float,
        reducedMotion: Bool,
        tuning: LocomotionTuning = .baseline
    ) -> LimbPose {
        let blend = clamp(gait, 0, 1)
        let amplitude = blend * (reducedMotion ? tuning.reducedMotionScale : 1)

        let swing = sin(phase)
        // Feet strike the ground twice per cycle, so the bounce runs at 2x.
        let bounce = cos(phase * 2)

        let leg = swing * tuning.legSwing * amplitude
        let arm = swing * tuning.armSwing * amplitude
        // Negative pitches the chest forward; see `LimbPose`.
        let lean = -tuning.torsoLean * clamp(speedFraction, 0, 1) * blend
        let counter = reducedMotion ? 0 : swing * tuning.torsoCounterSwing * amplitude
        let bounceLean = reducedMotion ? 0 : 0.35 * tuning.torsoCounterSwing * bounce * amplitude

        return LimbPose(
            legLeftPitch: leg,
            legRightPitch: -leg,
            // Diagonal trot: each rear leg matches the opposite front leg.
            rearLegLeftPitch: -leg,
            rearLegRightPitch: leg,
            armLeftPitch: -arm,
            armRightPitch: arm,
            torsoPitch: lean - bounceLean,
            torsoYaw: -counter,
            bob: reducedMotion ? 0 : (0.5 - 0.5 * bounce) * tuning.bobHeight * amplitude
        )
    }
}

// MARK: - Locomotion state

/// Distance-driven walk phase with a per-unit offset, plus movement-state and
/// facing hysteresis so units never flicker between idle and walk or between
/// adjacent facing sectors.
///
/// One of these rides alongside each mobile unit. It is fed the unit's authored
/// position every step and derives everything else — it never moves anything
/// itself, so pathing, steering and collision stay the mover's business.
///
/// Usage:
/// ```swift
/// var walk = LocomotionState(id: unit.id, position: unit.position)
/// walk.update(deltaTime: tuning.stepDuration, position: unit.position)
/// entity.orientation = simd_quatf(angle: walk.facing, axis: [0, 1, 0])
/// let pose = walk.pose  // apply to legL / legR / torso
/// ```
struct LocomotionState: Sendable {

    // MARK: Identity-derived constants

    /// Fixed offset into the walk cycle for this unit.
    let phaseOffset: Float
    /// Per-unit stride multiplier, so a group's cadence drifts apart.
    let strideScale: Float

    // MARK: Configuration

    var tuning: LocomotionTuning
    /// Simplifies the gait without freezing it; see `LocomotionMath.pose`.
    var reducedMotion: Bool

    // MARK: Integrated state

    /// Last position fed in, on the world plane.
    private(set) var position: WorldPoint
    /// Current yaw in radians about +Y. Zero is north (−Z).
    private(set) var facing: Float
    /// Yaw the unit is turning toward. Only re-latched outside the deadband.
    private(set) var targetFacing: Float
    /// Smoothed ground speed in metres per second.
    private(set) var speed: Float = 0
    /// Walk-cycle position in radians, wrapped to `[0, 2π)`.
    private(set) var phase: Float
    private(set) var movement: MovementState = .idle
    /// 0…1 blend into the walk cycle. Follows `movement` at a bounded rate.
    private(set) var gait: Float = 0

    /// - Parameters:
    ///   - id: Durable unit identity. The only thing the phase offset is drawn
    ///     from, so it survives replays and reordering.
    ///   - facing: Initial yaw. Defaults to north, matching the mesh rig's
    ///     authored orientation.
    init(
        id: EntityID,
        position: WorldPoint,
        facing: Float = 0,
        tuning: LocomotionTuning = .baseline,
        reducedMotion: Bool = false
    ) {
        self.phaseOffset = LocomotionMath.phaseOffset(for: id)
        self.strideScale = LocomotionMath.strideScale(for: id)
        self.tuning = tuning
        self.reducedMotion = reducedMotion
        self.position = position
        let start = LocomotionMath.wrapSigned(facing)
        self.facing = start
        self.targetFacing = start
        self.phase = phaseOffset
    }

    // MARK: Derived

    /// Distance covered by one full cycle for this unit, in metres.
    var strideLength: Float { max(tuning.strideLength * strideScale, 0.001) }

    /// Forward direction on the world plane.
    var forwardPlanar: WorldPoint { LocomotionMath.forward(for: facing) }

    /// Forward direction in world space, for the renderer.
    var forward: SIMD3<Float> {
        let planar = forwardPlanar
        return SIMD3<Float>(planar.x, 0, planar.y)
    }

    var isWalking: Bool { movement == .walking }

    /// The rig angles for this instant.
    var pose: LimbPose {
        LocomotionMath.pose(
            phase: phase,
            gait: gait,
            speedFraction: speed / max(tuning.referenceSpeed, 0.001),
            reducedMotion: reducedMotion,
            tuning: tuning
        )
    }

    // MARK: Integration

    /// Advances the walk cycle, movement state and facing from a new position.
    ///
    /// Call once per simulation step with the unit's authored position for that
    /// step. Expects a fixed step; a hitch longer than `tuning.maxDeltaTime` is
    /// clamped so one long update cannot snap a unit's facing round.
    mutating func update(deltaTime: Double, position newPosition: WorldPoint) {
        let step = LocomotionMath.clamp(Float(deltaTime), 0, tuning.maxDeltaTime)
        guard step > 0 else { return }

        let delta = newPosition - position
        let travelled = simd_length(delta)
        position = newPosition

        advanceSpeed(travelled: travelled, deltaTime: step)
        advanceMovementState()
        advanceGait(deltaTime: step)
        advancePhase(travelled: travelled)
        advanceFacing(delta: delta, travelled: travelled, deltaTime: step)
    }

    /// Convenience for callers holding a world-space position. Y is ignored:
    /// units walk on the world plane and the gait is driven by ground distance.
    mutating func update(deltaTime: Double, position newPosition: SIMD3<Float>) {
        update(deltaTime: deltaTime, position: WorldPoint(newPosition.x, newPosition.z))
    }

    /// Places the unit without walking it there — spawn, transport unload, or any
    /// discontinuity that must not spin the walk cycle or whip the facing.
    ///
    /// Passing `nil` for `facing` keeps the current aim, which is the rule
    /// everywhere: a unit never resets to a default orientation.
    mutating func teleport(to newPosition: WorldPoint, facing newFacing: Float? = nil) {
        position = newPosition
        speed = 0
        movement = .idle
        gait = 0
        if let newFacing {
            let wrapped = LocomotionMath.wrapSigned(newFacing)
            facing = wrapped
            targetFacing = wrapped
        }
    }

    // MARK: - Steps

    /// Low-passed speed. Hysteresis handles sustained changes; this handles the
    /// single-step spikes that would otherwise reach the state machine at all.
    private mutating func advanceSpeed(travelled: Float, deltaTime: Float) {
        let instant = travelled / deltaTime
        let alpha = 1 - exp(-deltaTime / max(tuning.speedSmoothing, 0.0001))
        speed += (instant - speed) * alpha
    }

    /// Two thresholds, not one: entering a walk costs more than staying in it.
    private mutating func advanceMovementState() {
        switch movement {
        case .idle:
            if speed >= tuning.walkEnterSpeed { movement = .walking }
        case .walking:
            if speed <= tuning.walkExitSpeed { movement = .idle }
        }
    }

    private mutating func advanceGait(deltaTime: Float) {
        let target: Float = movement == .walking ? 1 : 0
        let rate = deltaTime / max(tuning.gaitBlend, 0.0001)
        gait += LocomotionMath.clamp(target - gait, -rate, rate)
        gait = LocomotionMath.clamp(gait, 0, 1)
    }

    /// Distance-driven, never timer-driven: the feet advance exactly as far as
    /// the ground the unit covered, so they cannot skate under it.
    private mutating func advancePhase(travelled: Float) {
        guard travelled > 0 else { return }
        phase = LocomotionMath.wrapPositive(
            phase + travelled / strideLength * LocomotionMath.twoPi
        )
    }

    /// Facing follows movement, but only re-aims outside a deadband and always
    /// turns at a bounded rate.
    ///
    /// The deadband is measured against `targetFacing`, not against the current
    /// facing. Once a turn is committed the target holds still while the body
    /// catches up, so a unit crossing the boundary cannot latch a new target
    /// every step and shiver between two adjacent sectors.
    private mutating func advanceFacing(delta: WorldPoint, travelled: Float, deltaTime: Float) {
        if travelled > 1e-5, travelled / deltaTime >= tuning.steerMinimumSpeed {
            let heading = LocomotionMath.heading(of: delta)
            let offTarget = LocomotionMath.shortestAngle(from: targetFacing, to: heading)
            if abs(offTarget) > tuning.facingDeadband {
                targetFacing = LocomotionMath.wrapSigned(heading)
            }
        }

        // Runs whether or not the unit is moving, so a turn already under way
        // finishes instead of freezing part-done when the unit stops.
        let toTarget = LocomotionMath.shortestAngle(from: facing, to: targetFacing)
        let limit = tuning.maxTurnRate * deltaTime
        facing = LocomotionMath.wrapSigned(
            facing + LocomotionMath.clamp(toTarget, -limit, limit)
        )
    }
}
