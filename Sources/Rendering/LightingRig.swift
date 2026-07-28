import CoreGraphics
import Foundation
import RealityKit
import UIKit
import simd

/// The whole lighting model for the world, in one place.
///
/// Three directional lights and one procedurally generated image-based light:
///
/// - **Warm key** — the only shadow caster. High and to the camera's left, raking
///   slightly toward the viewer so cast shadows fall screen-right and a touch
///   down-screen. This is the "soft directional key from above-camera" of the
///   visual bible, and the Sunwoven Lumen warm gold spill.
/// - **Cool fill** — opposite hemisphere, shadowless. The Gravemark cool mineral
///   fill. It only has to keep the shadowed side off black; the environment now
///   carries most of the ambient, so it is deliberately weak.
/// - **Rim** — low and behind the subject relative to the camera, so fragment
///   edges and unit silhouettes separate from the void.
/// - **Environment** — a float16 HDR equirectangular map built in code (no
///   shipped `.exr`/`.skybox`): deep indigo below and around, a warm lobe up
///   where the key is, a faint cool counter-lobe where the rim is. This is what
///   replaces "ambient is a single flat fill" with real directional colour.
///
/// ## Why the environment is wired as a component rather than `content.environment`
///
/// `RealityViewCameraContent.environment = .skybox(...)` is the simpler iOS hook,
/// but it also *paints* the map as the view background, which would fight
/// `StarfieldFactory`'s void card and the starfield drawn on it. The
/// `ImageBasedLightComponent` / `ImageBasedLightReceiverComponent` pair lights the
/// scene and draws nothing, which is what this build needs. It also keeps the
/// whole rig inside this one file — nothing outside has to be edited to wire it.
///
/// ## Why there is a `System`
///
/// Two things have to be applied to entities this type does not build:
///
/// 1. Receivers must carry `ImageBasedLightReceiverComponent`; an IBL host with no
///    referrers is a silent no-op.
/// 2. Self-luminous geometry must be kept *out* of the shadow map. The void card
///    is a 300 m unlit plane and every glow seam is unlit geometry — all of them
///    rasterize into the shadow map and would blacken the scene the moment the
///    key light gained a `Shadow`. `DynamicLightShadowComponent` does not inherit
///    down a hierarchy, so it has to be set per model entity.
///
/// `LightingRigSystem` does both, once per entity, for entities that exist at
/// build time and for units the presenter spawns later. Nothing it does touches
/// simulation state or consumes randomness.
@MainActor
enum LightingRig {

    // MARK: - Tuning
    //
    // Every number the look depends on lives here. Assign `LightingRig.tuning`
    // before `WorldScene.build` to change the rig; it is read once per build.

    struct Tuning {

        // MARK: Exposure

        /// One multiplier over every *light* in the rig — key, fill, rim and the
        /// IBL together. The individual intensities below are the art direction
        /// (their ratios are what model the form); this is the exposure.
        ///
        /// Measured, not chosen. At 1.0 the rendered frame's sunlit regolith sat
        /// at a median **0.540 linear** luminance against concept 01's **0.397**,
        /// i.e. the ground was 36% too bright. That single fact caused three
        /// separate symptoms:
        ///
        /// 1. Nothing glowed. Emissive seams are authored independently of the
        ///    lights, so an over-bright ground closes the gap the glow needs —
        ///    the Core's turquoise glazing measured 0.744 linear against sand at
        ///    0.672, a margin too small to read as light.
        /// 2. Bloom became a flat haze. 15% of the frame cleared
        ///    `SunfoldPostProcess.Tuning.threshold`, nearly all of it ground, so
        ///    the bright pass returned the terrain rather than the emitters.
        /// 3. The frame read chalky. ACES rolls off what it is given; feeding it
        ///    an over-bright midtone desaturates it (measured mean saturation
        ///    0.301 against the concept's 0.345).
        ///
        /// 0.67 is the solution of the actual composite chain — tonemap, grade,
        /// saturation and vignette, inverted numerically — for a sunlit-regolith
        /// median of 0.397. Lowering the lights rather than the post-process
        /// `exposure` is deliberate: it moves lit surfaces *only*, leaving unlit
        /// stars and emissive seams where they are, which is what opens the gap
        /// between ground and glow instead of sliding the whole frame down.
        var exposureScale: Float = 0.67

        // MARK: Key (warm, shadow-casting)

        /// Sunwoven Lumen: warm gold spill, not white.
        var keyColor = UIColor(red: 1.00, green: 0.935, blue: 0.815, alpha: 1)
        /// Lux. The old rig ran 2700 with no environment; with an IBL underneath
        /// the key can carry more of the contrast without crushing the fill side.
        var keyIntensity: Float = 3200
        /// Position the key is aimed *from*, toward the origin. Only the resulting
        /// orientation matters — a directional light's position is not used for
        /// lighting. Elevation here is ~52 degrees, which gives shadows long
        /// enough to read as contact without smearing across a whole fragment.
        var keyFrom = SIMD3<Float>(-150, 200, -40)

        // MARK: Shadow

        var shadowEnabled = true

        /// **The single most important number in this file.**
        ///
        /// `.automatic` fits the shadow volume to the camera frustum, and the range
        /// is measured *from the camera*, not from the light. This camera sits
        /// `cameraDistance` = 260 m back at a 57-degree pitch, so every caster is
        /// 205–315 m away in view depth. The SDK default of 5 m renders zero
        /// shadows here — not subtly wrong, entirely absent.
        ///
        /// Derivation: on-screen vertical extent is `zoom` metres, so the ground
        /// depth span is `zoom / sin(57°)` = 1.192 · zoom, i.e. ±0.325 · zoom about
        /// the focus in view depth. At the 165 m zoom ceiling that is 206…314 m.
        /// 380 clears that plus tall structures and terrain relief at every zoom in
        /// the 34–165 band, while staying well inside the 420 m void card (which is
        /// excluded from the map anyway).
        ///
        /// Raise if shadows vanish when zoomed out; lower for crisper contact
        /// shadows, since depth precision is spread across this whole range.
        var shadowMaximumDistance: Float = 380

        /// Default 1.0 is far too low across a 380 m depth range and stripes badly.
        /// Raise toward 8 if shadows are striped (acne); lower toward 2 if they
        /// detach from their caster (peter-panning).
        var shadowDepthBias: Float = 4.0

        /// Escape hatch. `.automatic` is documented as fitting "the camera
        /// frustum", and an orthographic frustum is a box rather than a pyramid —
        /// the one behaviour that cannot be confirmed without a rendered frame. If
        /// `.automatic` yields nothing under the orthographic camera, flip this and
        /// the rig uses an explicit volume instead. The fixed volume is anchored on
        /// the key light entity, which sits at the world origin, so
        /// `shadowFixedOrthographicScale` has to cover the playfield, not the
        /// viewport — expect softer shadows on this path.
        // Verified in the rendered build on 2026-07-27: `.automatic` yields no
        // shadows at all under this orthographic camera. The fixed volume does.
        var shadowUsesFixedProjection = true
        var shadowFixedNear: Float = 1
        var shadowFixedFar: Float = 600
        var shadowFixedOrthographicScale: Float = 220

        // MARK: Fill (cool, shadowless)

        /// Gravemark: cool mineral fill.
        var fillColor = UIColor(red: 0.545, green: 0.675, blue: 0.975, alpha: 1)
        /// Pulled well down from the old 850. The environment supplies the ambient
        /// now; leaving the fill high flattens everything the key just modelled.
        var fillIntensity: Float = 520
        var fillFrom = SIMD3<Float>(160, 90, 130)

        // MARK: Rim (grazing back light)

        var rimColor = UIColor(red: 0.700, green: 0.850, blue: 1.000, alpha: 1)
        var rimIntensity: Float = 1150
        /// Low and behind the subject relative to the camera. The grazing angle is
        /// what puts a lit edge on fragment rims against the void.
        var rimFrom = SIMD3<Float>(40, 35, -210)

        // MARK: Environment (procedural IBL)

        var environmentEnabled = true
        /// Equirect width; height is half. 512×256 is ample for an ambient wash at
        /// this camera pitch and costs a fraction of 1024×512 at scene build.
        var environmentWidth = 512
        /// Runtime dial on the whole environment. 0 is the baked radiance below;
        /// each +1 doubles it.
        var environmentIntensityExponent: Float = 0

        /// Linear radiance, not sRGB. The void colours stay well under 1.0; the key
        /// lobe deliberately goes far above it, because that ratio is the entire
        /// point of an HDR environment.
        var voidZenith = SIMD3<Float>(0.016, 0.021, 0.068)
        var voidHorizon = SIMD3<Float>(0.042, 0.036, 0.088)
        var voidNadir = SIMD3<Float>(0.006, 0.007, 0.020)

        /// Warm lobe, aimed to agree with the key light so the environment
        /// highlight and the specular highlight land on the same facets.
        var environmentKeyRadiance = SIMD3<Float>(11.0, 8.6, 5.6)
        /// Higher is a tighter sun disc; lower is a broader sky glow.
        var environmentKeyTightness: Float = 42
        /// Fraction of the key radiance spread as a wide warm bloom.
        var environmentKeyBloom: Float = 0.045

        /// Cool counter-lobe, aimed with the rim light.
        var environmentRimRadiance = SIMD3<Float>(0.90, 1.50, 2.60)
        var environmentRimStrength: Float = 0.030
        var environmentRimTightness: Float = 6

        init() {}
    }

    /// Read once per `makeLighting()`. Mutate before `WorldScene.build` to retune.
    static var tuning = Tuning()

    // MARK: - Build

    /// The complete lighting subtree: key (with shadow), fill, rim, IBL host.
    ///
    /// Attach it anywhere under the world root with an identity transform. It must
    /// not be parented under the camera rig — the environment would then swing
    /// with the camera.
    static func makeLighting() -> Entity {
        let tuning = Self.tuning

        let root = Entity()
        root.name = "world.lighting"

        root.addChild(makeKey(tuning))
        root.addChild(
            makeDirectional(
                named: "world.lighting.fill",
                color: tuning.fillColor,
                intensity: tuning.fillIntensity * tuning.exposureScale,
                from: tuning.fillFrom
            )
        )
        root.addChild(
            makeDirectional(
                named: "world.lighting.rim",
                color: tuning.rimColor,
                intensity: tuning.rimIntensity * tuning.exposureScale,
                from: tuning.rimFrom
            )
        )

        if tuning.environmentEnabled, let resource = environmentResource(tuning) {
            let host = Entity()
            host.name = "world.lighting.environment"
            // `intensityExponent` is a log2 dial, so the rig's linear exposure
            // scale enters here as its logarithm. Scaling the exponent rather
            // than the baked radiances keeps the environment image itself —
            // and therefore its expensive cubemap convolution — cacheable.
            var ibl = ImageBasedLightComponent(
                source: .single(resource),
                intensityExponent: tuning.environmentIntensityExponent
                    + log2(max(tuning.exposureScale, 1e-4))
            )
            // The host sits at identity under the world root, but say it out loud:
            // an inherited rotation would drag the whole sky around with the scene.
            ibl.inheritsRotation = false
            host.components.set(ibl)
            root.addChild(host)
            environmentHost = host
        } else {
            environmentHost = nil
        }

        registerSystemIfNeeded()

        DebugLog.info(
            "Lighting: key \(Int(tuning.keyIntensity * tuning.exposureScale)) lux"
                + " (exposure \(tuning.exposureScale))"
                + (tuning.shadowEnabled ? " +shadow(\(Int(tuning.shadowMaximumDistance))m)" : "")
                + ", fill \(Int(tuning.fillIntensity * tuning.exposureScale))"
                + ", rim \(Int(tuning.rimIntensity * tuning.exposureScale)), "
                + (environmentHost == nil ? "no IBL" : "procedural IBL")
        )
        return root
    }

    private static func makeKey(_ tuning: Tuning) -> Entity {
        let key = Entity()
        key.name = "world.lighting.key"

        var light = DirectionalLightComponent(
            color: tuning.keyColor,
            intensity: tuning.keyIntensity * tuning.exposureScale
        )
        light.isRealWorldProxy = false

        if tuning.shadowEnabled {
            var shadow = DirectionalLightComponent.Shadow()
            shadow.shadowProjection = tuning.shadowUsesFixedProjection
                ? .fixed(
                    zNear: tuning.shadowFixedNear,
                    zFar: tuning.shadowFixedFar,
                    orthographicScale: tuning.shadowFixedOrthographicScale
                )
                : .automatic(maximumDistance: tuning.shadowMaximumDistance)
            shadow.depthBias = tuning.shadowDepthBias
            // Both faces are rasterized into the shadow map. Every material in this
            // project sets `faceCulling = .none` and several meshes are genuinely
            // single-sided planes; culling back faces would drop their shadows
            // entirely. The cost is acne, which `depthBias` pays for.
            //
            // Spelled out in full on purpose: a bare `.none` here resolves to
            // `Optional.none` — i.e. nil, i.e. the default — and silently does
            // nothing.
            shadow.cullModeOverride = DirectionalLightComponent.Shadow.ShadowMapCullMode.none
            key.components.set([light, shadow])
        } else {
            key.components.set(light)
        }

        key.look(at: .zero, from: tuning.keyFrom, relativeTo: nil)
        return key
    }

    private static func makeDirectional(
        named name: String,
        color: UIColor,
        intensity: Float,
        from: SIMD3<Float>
    ) -> Entity {
        let entity = Entity()
        entity.name = name
        var light = DirectionalLightComponent(color: color, intensity: intensity)
        light.isRealWorldProxy = false
        entity.components.set(light)
        entity.look(at: .zero, from: from, relativeTo: nil)
        return entity
    }

    // MARK: - Environment host

    /// The entity carrying `ImageBasedLightComponent`, if one was built.
    /// `LightingRigSystem` points every receiver at it.
    private(set) static weak var environmentHost: Entity?

    /// Building the resource runs a GPU cubemap convolution on the main actor, so
    /// it is done exactly once per process and shared across rebuilds.
    private static var cachedEnvironment: EnvironmentResource?

    private static func environmentResource(_ tuning: Tuning) -> EnvironmentResource? {
        if let cached = cachedEnvironment { return cached }
        guard let image = equirectangularHDR(tuning) else {
            DebugLog.warn("Procedural environment image could not be built; IBL disabled.")
            return nil
        }
        do {
            let resource = try EnvironmentResource(
                equirectangular: image,
                withName: "sunfold.cosmic"
            )
            cachedEnvironment = resource
            return resource
        } catch {
            DebugLog.warn("EnvironmentResource generation failed (\(error)); IBL disabled.")
            return nil
        }
    }

    // MARK: - Procedural environment map

    /// A float16, extended-linear-sRGB equirectangular map.
    ///
    /// It has to be genuine HDR float. `EnvironmentResource(equirectangular:)`
    /// imports with an HDR-colour semantic and treats the pixels as *linear
    /// radiance*; an 8-bit sRGB image clamps every channel at 1.0, so the warm
    /// lobe could never exceed the ambient and the result would be exactly the
    /// flat wash this rig exists to remove. So: 16-bit float, linear values, no
    /// gamma encoding, key lobe well above 1.0.
    ///
    /// Pure trigonometry — it consumes no randomness and cannot perturb any
    /// `DeterministicRandom` stream.
    private static func equirectangularHDR(_ tuning: Tuning) -> CGImage? {
        let width = max(32, tuning.environmentWidth)
        let height = width / 2
        guard height > 0 else { return nil }

        let keyDirection = normalized(tuning.keyFrom, fallback: SIMD3<Float>(0, 1, 0))
        let rimDirection = normalized(tuning.rimFrom, fallback: SIMD3<Float>(0, 0, -1))

        var pixels = [UInt16](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            // theta measured from +Y down to -Y.
            let theta = (Float(y) + 0.5) / Float(height) * .pi
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            for x in 0..<width {
                let phi = ((Float(x) + 0.5) / Float(width) * 2 - 1) * .pi
                let direction = SIMD3<Float>(
                    sinTheta * sin(phi),
                    cosTheta,
                    sinTheta * cos(phi)
                )

                // Vertical gradient: indigo overhead, slightly warmer violet at the
                // horizon, near-black underneath so undersides stay heavy.
                let up = max(0, direction.y)
                let down = max(0, -direction.y)
                var colour = tuning.voidHorizon
                colour += (tuning.voidZenith - tuning.voidHorizon) * pow(up, 0.7)
                colour += (tuning.voidNadir - tuning.voidHorizon) * pow(down, 0.6)

                // Warm key lobe: a tight core plus a broad bloom, so there is no
                // hard disc edge in the reflection of a rough surface.
                let key = max(0, simd_dot(direction, keyDirection))
                colour += tuning.environmentKeyRadiance * pow(key, tuning.environmentKeyTightness)
                colour += tuning.environmentKeyRadiance * tuning.environmentKeyBloom * pow(key, 4)

                // Cool counter-lobe so the shadow side reads as mineral rather than
                // dead.
                let rim = max(0, simd_dot(direction, rimDirection))
                colour += tuning.environmentRimRadiance
                    * tuning.environmentRimStrength
                    * pow(rim, tuning.environmentRimTightness)

                let index = (y * width + x) * 4
                pixels[index] = halfBits(colour.x)
                pixels[index + 1] = halfBits(colour.y)
                pixels[index + 2] = halfBits(colour.z)
                pixels[index + 3] = halfBits(1)
            }
        }

        let data = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        else { return nil }

        let bitmapInfo: CGBitmapInfo = [
            CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            .floatComponents,
            .byteOrder16Little
        ]

        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 16,
            bitsPerPixel: 64,
            bytesPerRow: width * 8,
            space: space,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    /// IEEE-754 binary32 to binary16, truncating the mantissa.
    ///
    /// Written out rather than using `Float16` so the file compiles for any
    /// simulator architecture, not just arm64. Rounding is irrelevant at the
    /// precision an environment map is sampled with.
    private static func halfBits(_ value: Float) -> UInt16 {
        let bits = value.bitPattern
        let sign = UInt16((bits >> 16) & 0x8000)
        let rawExponent = Int((bits >> 23) & 0xFF)
        let mantissa = bits & 0x007F_FFFF

        // Zero, subnormal float32, NaN and infinity all resolve to a finite half:
        // the generator never produces them, and clamping is safer than emitting
        // an infinity into a cubemap convolution.
        if rawExponent == 0 { return sign }
        if rawExponent == 0xFF { return sign | 0x7BFF }

        let exponent = rawExponent - 127 + 15
        if exponent >= 0x1F { return sign | 0x7BFF }
        if exponent <= 0 {
            let shift = 14 - exponent
            if shift > 24 { return sign }
            let implicit = mantissa | 0x0080_0000
            return sign | UInt16(truncatingIfNeeded: implicit >> UInt32(shift))
        }
        return sign | UInt16(exponent << 10) | UInt16(mantissa >> 13)
    }

    private static func normalized(
        _ vector: SIMD3<Float>,
        fallback: SIMD3<Float>
    ) -> SIMD3<Float> {
        let lengthSquared = simd_length_squared(vector)
        return lengthSquared > 1e-12 ? vector / sqrt(lengthSquared) : fallback
    }

    // MARK: - Per-entity wiring

    private static var systemRegistered = false

    private static func registerSystemIfNeeded() {
        guard !systemRegistered else { return }
        systemRegistered = true
        LightingRigSystem.registerSystem()
    }

    /// Geometry that must stay out of the shadow map.
    ///
    /// Two families, both of which would blacken the frame if they cast:
    ///
    /// - Anything under `void.*` — the 300 m unlit backdrop card, the star quads
    ///   and the distant celestial body. All of them ride the camera rig at 420 m
    ///   behind the focus and would sit squarely between the key light and the
    ///   playfield.
    /// - Anything whose materials are entirely `UnlitMaterial` — every glow seam,
    ///   lumen accent, drive wash and causeway rail. They are self-luminous by
    ///   definition; a self-luminous surface casting a hard shadow is a lie.
    static func suppressesShadowCasting(_ entity: Entity) -> Bool {
        var node: Entity? = entity
        while let current = node {
            if current.name.hasPrefix("void.") { return true }
            node = current.parent
        }
        guard let model = entity.components[ModelComponent.self] else { return false }
        return !model.materials.isEmpty && model.materials.allSatisfy { $0 is UnlitMaterial }
    }
}

/// Marks an entity `LightingRigSystem` has already wired, so the pass is one-shot
/// per entity rather than per frame.
struct LightingRigWiredComponent: Component {
    init() {}
}

/// Applies the two per-entity pieces of the rig that `LightingRig` cannot set at
/// build time: the IBL receiver, and shadow-cast suppression for self-luminous
/// geometry. Runs over entities the presenter spawns later as well as those
/// present at scene build.
///
/// Presentation only. It reads no simulation state, writes none, and draws no
/// randomness.
struct LightingRigSystem: System {

    private static let modelQuery = EntityQuery(where: .has(ModelComponent.self))

    init(scene: Scene) {}

    func update(context: SceneUpdateContext) {
        let host = LightingRig.environmentHost

        for entity in context.entities(
            matching: Self.modelQuery,
            updatingSystemWhen: .rendering
        ) {
            guard !entity.components.has(LightingRigWiredComponent.self) else { continue }
            entity.components.set(LightingRigWiredComponent())

            if LightingRig.suppressesShadowCasting(entity) {
                entity.components.set(DynamicLightShadowComponent(castsShadow: false))
            }
            if let host {
                entity.components.set(ImageBasedLightReceiverComponent(imageBasedLight: host))
            }
        }
    }
}
