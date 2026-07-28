import Foundation
import Metal
import RealityKit
// RealityViewCameraContent is vended through RealityKit's SwiftUI overlay, so
// SwiftUI must be in scope even though this file builds no views.
import SwiftUI
import simd

/// The final-image pass: bloom, filmic tonemap, split-tone grade, vignette and
/// edge chromatic aberration, run on the rendered frame before SwiftUI draws the
/// HUD over it.
///
/// This is the *real* hook, not an approximation. iOS 26.0 shipped
/// `RealityFoundation.PostProcessEffect` together with
/// `RealityViewCameraContent.renderingEffects.customPostProcessing`, and the app's
/// deployment target is already 26.0, so no `if #available` guard is needed and no
/// migration away from `RealityView` to the older `ARView.renderCallbacks` path is
/// required. `WorldController.attach(to:)` already takes an
/// `inout RealityViewCameraContent`, so installation is one call.
///
/// Concurrency: `postProcess(context:)` is `nonisolated` and runs on RealityKit's
/// render thread, never the main actor. All mutable GPU state therefore lives in
/// `SunfoldPostProcessCore`, a reference box behind a lock, so the value-type
/// copies RealityKit makes of this struct all address the same pipelines and
/// scratch textures.
///
/// Determinism: this pass is presentation-only. It reads no simulation state,
/// writes none back, and draws no randomness. `context.time` is deliberately
/// ignored — a time-driven shimmer would be a frame-rate-dependent input, and
/// nothing here should be able to differ between two runs of the same seed.
struct SunfoldPostProcess: PostProcessEffect {

    // MARK: - Tuning

    /// Every knob in the pass, in one place.
    ///
    /// Values are LINEAR-light unless noted. The frame RealityKit hands over is
    /// display-referred (the public API exposes no HDR path — `dynamicRange` has
    /// only `.default` and `.standard`, and `_hdrRendering` is internal), so the
    /// bright pass is an LDR bright-pass keyed on relative luminance rather than
    /// on physical nits. That is why `threshold` is set by eye against the
    /// palette rather than derived.
    struct Tuning: Sendable, Equatable {
        /// Linear luminance above which a pixel starts contributing to bloom.
        ///
        /// Measured off the rendered frame, not estimated from the palette. The
        /// previous value of 0.58 came with a note claiming lit regolith lands at
        /// 0.45–0.55 linear; in the actual frame it landed at a **median 0.540
        /// and a p95 of 0.672**, so the terrain — 15% of the whole frame — was
        /// clearing the bar. A bright pass that returns the ground produces an
        /// even haze, not a halo, which is exactly what the frame showed: no
        /// visible glow anywhere despite the pass running correctly.
        ///
        /// With `LightingRig.Tuning.exposureScale` at 0.67 the ground drops to a
        /// median 0.397 / p95 0.530, while emissive seams and unlit stars — which
        /// do not scale with the lights — stay at 0.744 and 0.84. 0.62 sits in
        /// the gap that opens up: above every lit surface, below every emitter.
        var threshold: Float = 0.62
        /// Width of the quadratic knee below `threshold`. A hard cut pops as a
        /// seam crosses it during a camera pan; the knee fades it in.
        ///
        /// The knee is what actually sets where bloom begins — contribution
        /// starts at `threshold - softKnee`, not at `threshold`. At the old 0.30
        /// that onset was 0.32, far below the ground. 0.16 puts it at 0.46:
        /// clear of the regolith median, still wide enough that a seam fades in
        /// across a pan rather than popping.
        var softKnee: Float = 0.16
        /// How much of the blurred bright pass is added back.
        ///
        /// Above 1 on purpose. A Gaussian blur conserves energy, so the peak of
        /// the halo it returns falls as `1/σ²` — and the emitters in this scene
        /// are small. Measured by rendering the frame twice, once at 0.72 and
        /// once at 0, and differencing: the pass was landing a mean lift of
        /// **+0.002** display luminance in the ring around the Core's glazing.
        /// Correctly placed (28× stronger next to an emitter than away from one)
        /// and about ten times too faint to see — half a code value out of 255.
        ///
        /// The usual fix is an HDR source where an emitter is authored at 10× and
        /// carries the energy itself. `RealityView` exposes no HDR path, so the
        /// frame arrives clamped to 1.0 and the amplification has to happen here
        /// instead. 3.2 is that missing headroom, not a taste dial. It costs the
        /// ground nothing: with `threshold` above every lit surface, the lift far
        /// from any emitter measures +0.00007.
        var bloomIntensity: Float = 3.2
        /// Second blur round's stride multiplier. The two rounds together give a
        /// wide, soft halo for the cost of a narrow kernel.
        var wideBlurStride: Float = 2.6

        /// Linear gain applied before the film curve.
        var exposure: Float = 1.0
        /// Blend between the clamped original (0) and full ACES (1).
        var tonemapStrength: Float = 0.85

        /// Multiplier applied to the toe of the curve. Leans indigo, matching the
        /// void the fragments float in.
        var shadowTint: SIMD3<Float> = [0.88, 0.94, 1.14]
        /// Multiplier applied to the shoulder. Leans to Sunwoven gold.
        var highlightTint: SIMD3<Float> = [1.08, 1.02, 0.90]
        /// Overall strength of the split-tone.
        var gradeStrength: Float = 0.38
        /// Luminance at which the grade has fully crossed from shadow to
        /// highlight tint.
        var gradePivot: Float = 0.72
        var saturation: Float = 1.06

        /// 0 disables the vignette entirely.
        var vignetteStrength: Float = 0.30
        /// Distance from centre, in NDC units, where the vignette is fully dark.
        /// Screen corners sit at `sqrt(2) ≈ 1.414`.
        var vignetteRadius: Float = 1.44
        /// How far inside `vignetteRadius` the falloff begins.
        var vignetteSoftness: Float = 0.74

        /// Radial channel separation at the frame edge, in normalised UV units.
        /// Roughly 2.5 px on the long edge of an iPad Air 13 frame at the corner,
        /// and exactly zero at the centre. 0 disables it (and saves two taps).
        ///
        /// Measured down from 0.0022 in the rendered build. This scene is mostly
        /// small bright elements on pure black — stars, rim seams, the far
        /// fragment — and that is the worst case for channel separation: every one
        /// of them fringed red/cyan and four independent art-direction reviews
        /// read it as a rendering bug rather than a lens effect. Keep it far below
        /// where it becomes nameable.
        var aberration: Float = 0.0006

        /// Divisor for the bloom chain's resolution. 4 keeps the whole chain
        /// under a megapixel of work on a 2732×2048 frame.
        var downsample: Int = 4

        /// Whether to ask RealityKit for 4x MSAA alongside the pass.
        ///
        /// This is the single largest cost the pass adds — the bloom chain and
        /// the composite together are a fraction of it. It is on because bloom
        /// widens an aliased edge into a crawling halo, which looks worse than
        /// the aliasing did. Turn it off first if the frame budget is tight.
        var antialiasing: Bool = true

        init() {}
    }

    /// Read once per `install(into:)`. Assign before the `RealityView` is built.
    nonisolated(unsafe) static var tuning = Tuning()

    // MARK: - Installation

    private let core: SunfoldPostProcessCore

    private init(core: SunfoldPostProcessCore) {
        self.core = core
    }

    /// Installs the pass on `content`, or leaves the frame untouched and returns
    /// `false` if the Metal library or pipelines could not be built.
    ///
    /// Validating up front matters: a `PostProcessEffect` that fails to write
    /// `targetColorTexture` produces an undefined — in practice black — frame.
    /// Refusing to install is the only fallback that cannot look broken.
    @MainActor
    @discardableResult
    static func install(into content: inout RealityViewCameraContent) -> Bool {
        let tuning = Self.tuning
        let core = SunfoldPostProcessCore(tuning: tuning)
        guard core.warmUp() else {
            DebugLog.warn("Post-processing unavailable (no Metal library or pipeline); frame left ungraded.")
            return false
        }
        content.renderingEffects.customPostProcessing = .effect(SunfoldPostProcess(core: core))
        if tuning.antialiasing {
            content.renderingEffects.antialiasing = .multisample4X
        }
        return true
    }

    // MARK: - PostProcessEffect

    func prepare(for device: any MTLDevice) {
        core.build(with: device)
    }

    func postProcess(context: borrowing PostProcessEffectContext<any MTLCommandBuffer>) {
        // PostProcessEffectContext is ~Copyable and passed borrowing, so nothing
        // may escape this call. Read what is needed into locals first.
        core.encode(
            commandBuffer: context.commandBuffer,
            device: context.device,
            source: context.sourceColorTexture,
            target: context.targetColorTexture
        )
    }
}

// MARK: - GPU state

/// Owns everything the pass allocates. Reference semantics on purpose: RealityKit
/// stores the effect by value and may copy it, and the render thread calls into it
/// without any actor isolation.
final class SunfoldPostProcessCore: @unchecked Sendable {

    private let lock = NSLock()
    private let tuning: SunfoldPostProcess.Tuning

    private var device: (any MTLDevice)?
    private var library: (any MTLLibrary)?
    private var brightPass: (any MTLComputePipelineState)?
    private var blur: (any MTLComputePipelineState)?
    /// Keyed by target pixel format: the composite is a render pass, and a render
    /// pipeline state is bound to its colour attachment format.
    private var composites: [UInt: any MTLRenderPipelineState] = [:]
    private var supportsNonUniformThreadgroups = false
    private var libraryUnavailable = false

    private var bloomPing: (any MTLTexture)?
    private var bloomPong: (any MTLTexture)?
    private var bloomWidth = 0
    private var bloomHeight = 0

    private var warnedOnce = false

    init(tuning: SunfoldPostProcess.Tuning) {
        self.tuning = tuning
    }

    // MARK: Setup

    /// Builds the device, library and the two compute pipelines on the main actor
    /// before the effect is installed, so a missing `default.metallib` is caught
    /// while there is still the option of not installing at all.
    func warmUp() -> Bool {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        lock.lock()
        defer { lock.unlock() }
        buildLocked(with: device)
        return brightPass != nil && blur != nil && library != nil
    }

    func build(with device: any MTLDevice) {
        lock.lock()
        defer { lock.unlock() }
        buildLocked(with: device)
    }

    /// Caller must hold `lock`.
    private func buildLocked(with device: any MTLDevice) {
        // `warmUp` builds against the system default device; RealityKit may hand a
        // different one to `prepare`. Rebuilding on a mismatch is what stops a
        // pipeline compiled for one device from being bound on another.
        if self.device === device {
            guard library == nil, !libraryUnavailable else { return }
        } else {
            library = nil
            brightPass = nil
            blur = nil
            composites.removeAll()
            bloomPing = nil
            bloomPong = nil
            bloomWidth = 0
            bloomHeight = 0
            libraryUnavailable = false
            self.device = device
        }

        // Never `makeDefaultLibrary()` with no arguments — in some contexts that
        // resolves against the calling framework's bundle, not the app's.
        guard let library = try? device.makeDefaultLibrary(bundle: .main) else {
            // Latch the failure: retrying a throwing call every frame is worse
            // than being ungraded.
            libraryUnavailable = true
            return
        }
        self.library = library

        brightPass = Self.computePipeline(device: device, library: library, named: "sunfoldBrightPass")
        blur = Self.computePipeline(device: device, library: library, named: "sunfoldBlur")
        supportsNonUniformThreadgroups = device.supportsFamily(.apple4)
    }

    private static func computePipeline(
        device: any MTLDevice,
        library: any MTLLibrary,
        named name: String
    ) -> (any MTLComputePipelineState)? {
        guard let function = library.makeFunction(name: name) else { return nil }
        return try? device.makeComputePipelineState(function: function)
    }

    private func compositePipeline(
        device: any MTLDevice,
        format: MTLPixelFormat
    ) -> (any MTLRenderPipelineState)? {
        if let cached = composites[format.rawValue] { return cached }
        guard let library,
              let vertexFunction = library.makeFunction(name: "sunfoldFullscreenVertex"),
              let fragmentFunction = library.makeFunction(name: "sunfoldCompositeFragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = format
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        composites[format.rawValue] = pipeline
        return pipeline
    }

    // MARK: Encoding

    func encode(
        commandBuffer: any MTLCommandBuffer,
        device: any MTLDevice,
        source: any MTLTexture,
        target: any MTLTexture
    ) {
        lock.lock()
        defer { lock.unlock() }

        buildLocked(with: device)

        guard let brightPass,
              let blur,
              let composite = compositePipeline(device: device, format: target.pixelFormat)
        else {
            fallbackLocked(commandBuffer: commandBuffer, source: source, target: target)
            return
        }

        let width = max(1, source.width / max(1, tuning.downsample))
        let height = max(1, source.height / max(1, tuning.downsample))
        guard ensureScratchLocked(device: device, width: width, height: height),
              let ping = bloomPing,
              let pong = bloomPong
        else {
            fallbackLocked(commandBuffer: commandBuffer, source: source, target: target)
            return
        }

        let decodeMode = Self.needsManualTransfer(source.pixelFormat) ? Float(1) : Float(0)
        let encodeMode = Self.needsManualTransfer(target.pixelFormat) ? Float(1) : Float(0)

        var params = SunfoldPostParams(tuning: tuning, decodeMode: decodeMode, encodeMode: encodeMode)

        // 1. Bright pass: full-res source -> quarter-res ping.
        params.dstTexel = SIMD2(1 / Float(width), 1 / Float(height))
        params.srcTexel = SIMD2(1 / Float(source.width), 1 / Float(source.height))
        dispatchLocked(
            commandBuffer: commandBuffer,
            pipeline: brightPass,
            params: params,
            source: source,
            destination: ping
        )

        // 2. Two separable rounds at widening stride. Both operate entirely at
        //    quarter res, so src and dst texel sizes are the same from here on.
        params.srcTexel = params.dstTexel
        let rounds: [(direction: SIMD2<Float>, stride: Float, from: any MTLTexture, to: any MTLTexture)] = [
            ([1, 0], 1.0, ping, pong),
            ([0, 1], 1.0, pong, ping),
            ([1, 0], tuning.wideBlurStride, ping, pong),
            ([0, 1], tuning.wideBlurStride, pong, ping)
        ]
        for round in rounds {
            params.blurDirection = round.direction
            params.blurStride = round.stride
            dispatchLocked(
                commandBuffer: commandBuffer,
                pipeline: blur,
                params: params,
                source: round.from,
                destination: round.to
            )
        }

        // 3. Composite at full res, as a render pass into RealityKit's target.
        params.dstTexel = SIMD2(1 / Float(target.width), 1 / Float(target.height))
        params.srcTexel = SIMD2(1 / Float(source.width), 1 / Float(source.height))

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        // Every texel is written by the full-screen triangle, so there is nothing
        // to preserve from whatever was in the target before.
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            fallbackLocked(commandBuffer: commandBuffer, source: source, target: target)
            return
        }
        encoder.label = "Sunfold post composite"
        encoder.setRenderPipelineState(composite)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentTexture(ping, index: 1)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SunfoldPostParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func dispatchLocked(
        commandBuffer: any MTLCommandBuffer,
        pipeline: any MTLComputePipelineState,
        params: SunfoldPostParams,
        source: any MTLTexture,
        destination: any MTLTexture
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        var params = params
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(destination, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<SunfoldPostParams>.stride, index: 0)

        let threadgroup = MTLSize(width: 8, height: 8, depth: 1)
        if supportsNonUniformThreadgroups {
            encoder.dispatchThreads(
                MTLSize(width: destination.width, height: destination.height, depth: 1),
                threadsPerThreadgroup: threadgroup
            )
        } else {
            // The kernels bounds-check, so an over-dispatch is safe.
            encoder.dispatchThreadgroups(
                MTLSize(
                    width: (destination.width + threadgroup.width - 1) / threadgroup.width,
                    height: (destination.height + threadgroup.height - 1) / threadgroup.height,
                    depth: 1
                ),
                threadsPerThreadgroup: threadgroup
            )
        }
        encoder.endEncoding()
    }

    /// Scratch is `rgba16Float` regardless of what RealityKit is rendering into:
    /// the bright pass output is linear light with values that can exceed 1, and
    /// an 8-bit intermediate would band visibly across a wide, soft halo.
    private func ensureScratchLocked(device: any MTLDevice, width: Int, height: Int) -> Bool {
        if bloomWidth == width, bloomHeight == height, bloomPing != nil, bloomPong != nil {
            return true
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let ping = device.makeTexture(descriptor: descriptor),
              let pong = device.makeTexture(descriptor: descriptor)
        else { return false }
        ping.label = "Sunfold bloom ping"
        pong.label = "Sunfold bloom pong"
        bloomPing = ping
        bloomPong = pong
        bloomWidth = width
        bloomHeight = height
        return true
    }

    /// Something failed after RealityKit already committed to us writing the
    /// frame. Get the source across untouched if the formats allow a blit; if
    /// they do not, clear to the void colour rather than leaving the target
    /// undefined, which shows as garbage.
    private func fallbackLocked(
        commandBuffer: any MTLCommandBuffer,
        source: any MTLTexture,
        target: any MTLTexture
    ) {
        if !warnedOnce {
            warnedOnce = true
            DebugLog.warn("Post-processing pass could not encode; falling back to a passthrough frame.")
        }

        if source.pixelFormat == target.pixelFormat,
           source.width == target.width,
           source.height == target.height,
           let blit = commandBuffer.makeBlitCommandEncoder() {
            blit.copy(from: source, to: target)
            blit.endEncoding()
            return
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0.039, green: 0.045, blue: 0.105, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }

    /// True when the format carries display-encoded values that the hardware will
    /// not convert for us: plain 8-bit unorm. sRGB-tagged formats are converted on
    /// sample and on write; float formats are linear already.
    private static func needsManualTransfer(_ format: MTLPixelFormat) -> Bool {
        switch format {
        case .rgba8Unorm, .bgra8Unorm, .rgb10a2Unorm:
            true
        default:
            false
        }
    }
}

// MARK: - Uniforms

/// Mirrors `SunfoldPostParams` in SunfoldPostProcess.metal byte for byte.
///
/// The two `SIMD4<Float>`s lead and the scalars are padded to exactly sixteen, so
/// the struct is 128 bytes with no padding either compiler has to infer. Changing
/// the order here without changing the shader silently corrupts every knob.
private struct SunfoldPostParams {
    var shadowTint: SIMD4<Float>
    var highlightTint: SIMD4<Float>
    var dstTexel: SIMD2<Float> = .zero
    var srcTexel: SIMD2<Float> = .zero
    var blurDirection: SIMD2<Float> = [1, 0]
    var pad0: SIMD2<Float> = .zero

    var threshold: Float
    var softKnee: Float
    var bloomIntensity: Float
    var exposure: Float
    var tonemapStrength: Float
    var vignetteStrength: Float
    var vignetteRadius: Float
    var vignetteSoftness: Float
    var aberration: Float
    var saturation: Float
    var decodeMode: Float
    var encodeMode: Float
    var blurStride: Float = 1
    var pad1: Float = 0
    var pad2: Float = 0
    var pad3: Float = 0

    init(tuning: SunfoldPostProcess.Tuning, decodeMode: Float, encodeMode: Float) {
        shadowTint = SIMD4(
            tuning.shadowTint.x, tuning.shadowTint.y, tuning.shadowTint.z, tuning.gradeStrength
        )
        highlightTint = SIMD4(
            tuning.highlightTint.x, tuning.highlightTint.y, tuning.highlightTint.z, tuning.gradePivot
        )
        threshold = tuning.threshold
        softKnee = tuning.softKnee
        bloomIntensity = tuning.bloomIntensity
        exposure = tuning.exposure
        tonemapStrength = tuning.tonemapStrength
        vignetteStrength = tuning.vignetteStrength
        vignetteRadius = tuning.vignetteRadius
        vignetteSoftness = tuning.vignetteSoftness
        aberration = tuning.aberration
        saturation = tuning.saturation
        self.decodeMode = decodeMode
        self.encodeMode = encodeMode
    }
}
