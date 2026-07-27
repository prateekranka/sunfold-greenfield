import Foundation
import Observation
import RealityKit
// RealityViewCameraContent is vended through RealityKit's SwiftUI overlay,
// so SwiftUI must be in scope even though this file builds no views.
import SwiftUI
import simd

/// Bridges the render loop to the simulation, and owns the presentation-side
/// objects (camera rig, subscriptions) that must outlive a single view update.
@MainActor
@Observable
final class WorldController {
    let simulation: SkirmishSimulation
    let selection = SelectionModel()
    private(set) var rig: CameraRig?
    private var presenter: EntityPresenter?

    /// Mirrors the system Reduced Motion setting. Simplifies gait and camera
    /// easing without freezing gameplay feedback, which would read as broken.
    var reducedMotion: Bool = false

    /// Smoothed frames-per-second, shown in the debug overlay. This is a live
    /// reading of the render loop, not a performance claim.
    private(set) var smoothedFPS: Double = 0

    /// The lasso the player is currently dragging, in view points. Nil when no
    /// lasso is in progress; the HUD draws it straight from here.
    private(set) var marquee: Marquee?

    struct Marquee: Equatable {
        var origin: SIMD2<Float>
        var current: SIMD2<Float>

        var rect: CGRect {
            CGRect(
                x: CGFloat(min(origin.x, current.x)),
                y: CGFloat(min(origin.y, current.y)),
                width: CGFloat(abs(current.x - origin.x)),
                height: CGFloat(abs(current.y - origin.y))
            )
        }
    }

    private var updateSubscription: EventSubscription?

    /// The previous tap, for detecting a double-tap without making every single
    /// tap wait for a double-tap to fail. In an RTS the single tap is the verb
    /// the player uses hundreds of times; adding 300 ms to it to support a
    /// convenience gesture would be the wrong trade.
    private var lastTap: (time: TimeInterval, point: SIMD2<Float>, unit: EntityID)?

    init(simulation: SkirmishSimulation) {
        self.simulation = simulation
    }

    /// Builds the scene into `content` and starts driving the simulation from
    /// the render loop. Safe to call once per RealityView lifetime.
    func attach(to content: inout RealityViewCameraContent) {
        content.camera = .virtual

        let (root, rig) = WorldScene.build(
            map: simulation.map,
            tuning: simulation.tuning,
            keepClear: TerrainDressing.keepClear(for: simulation)
        )
        self.rig = rig

        let presenter = EntityPresenter(seed: simulation.seed, tuning: simulation.tuning)
        self.presenter = presenter
        root.addChild(presenter.root)

        content.add(root)

        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            // SceneEvents.Update is delivered on the main actor by RealityKit.
            MainActor.assumeIsolated {
                self?.onRenderFrame(deltaTime: event.deltaTime)
            }
        }
    }

    private func onRenderFrame(deltaTime: TimeInterval) {
        guard deltaTime > 0 else { return }
        // The simulation consumes real time through a fixed-step accumulator, so
        // frame rate changes never change game outcomes.
        simulation.update(deltaTime: deltaTime)

        // Selection is player-side state pointing at simulation entities, so it
        // must be reconciled every frame rather than trusted to stay valid.
        selection.prune(against: simulation)
        selection.expireOrderMarker(after: 2.5, now: simulation.elapsed)

        // Presentation is reconciled after the simulation has stepped, so a frame
        // never shows a mix of this tick's positions and last tick's entities.
        presenter?.sync(
            simulation: simulation,
            selection: selection,
            deltaTime: deltaTime,
            reducedMotion: reducedMotion
        )

        let instantaneous = 1.0 / deltaTime
        smoothedFPS = smoothedFPS == 0 ? instantaneous : smoothedFPS * 0.9 + instantaneous * 0.1
    }

    // MARK: - Touch intents

    /// Resolves a tap to a selection change or an order.
    ///
    /// The grammar is deliberately simple: tapping a thing selects it; tapping
    /// elsewhere with units selected moves them; tapping empty ground with nothing
    /// selected clears. Advanced orders wait until the basic loop is proven.
    func handleTap(atScreenPoint screenPoint: SIMD2<Float>, viewportSize: SIMD2<Float>) {
        guard let rig,
              let worldPoint = rig.worldPoint(fromScreen: screenPoint, viewportSize: viewportSize)
        else { return }

        switch WorldPicker.pick(at: worldPoint, in: simulation) {
        case .unit(let id):
            // Only the player's own units are commandable; tapping a Gravemark
            // unit inspects it rather than selecting it as yours.
            guard let unit = simulation.unit(id), unit.faction == .sunwoven else {
                lastTap = nil
                return
            }
            if isDoubleTap(on: id, at: screenPoint) {
                selectAllVisible(ofKind: unit.kind, viewportSize: viewportSize)
                lastTap = nil
            } else {
                selection.selectUnit(id)
                lastTap = (ProcessInfo.processInfo.systemUptime, screenPoint, id)
            }

        case .building(let id):
            lastTap = nil
            selection.selectBuilding(id)

        case .deposit(let id):
            lastTap = nil
            // Tapping a node with citizens selected is the whole economy verb.
            // With nothing selected the same tap is a question about the node,
            // so it inspects instead.
            if selection.selectedUnits.isEmpty {
                selection.selectDeposit(id)
            } else {
                selection.orderGather(from: id, in: simulation)
            }

        case .ground:
            lastTap = nil
            if selection.selectedUnits.isEmpty {
                selection.clear()
            } else {
                selection.orderMove(to: worldPoint, in: simulation)
            }
        }
    }

    /// A second tap on the same unit, close enough in time and space to be one
    /// gesture rather than two decisions.
    private func isDoubleTap(on id: EntityID, at point: SIMD2<Float>) -> Bool {
        guard let last = lastTap, last.unit == id else { return false }
        let elapsed = ProcessInfo.processInfo.systemUptime - last.time
        return elapsed <= 0.35 && simd_distance(last.point, point) <= 44
    }

    /// Double-tapping a unit takes every unit of that kind the player can
    /// currently see. Scoping it to the viewport rather than the whole map is
    /// deliberate: pulling in citizens from a fragment the player is not looking
    /// at would silently abandon whatever they were doing there.
    private func selectAllVisible(ofKind kind: UnitKind, viewportSize: SIMD2<Float>) {
        guard let rig else { return }
        let ids = simulation.units.values
            .filter { $0.faction == .sunwoven && $0.kind == kind }
            .filter { unit in
                guard let point = rig.screenPoint(forWorld: unit.position, viewportSize: viewportSize)
                else { return false }
                return point.x >= 0 && point.x <= viewportSize.x
                    && point.y >= 0 && point.y <= viewportSize.y
            }
            .map(\.id)
            .sorted { $0.raw < $1.raw }
        guard !ids.isEmpty else { return }
        selection.selectUnits(ids)
    }

    // MARK: - Marquee selection

    /// How many units the lasso currently covers. Shown while dragging so the
    /// player can see the box working before they commit to it.
    private(set) var marqueeHitCount: Int = 0

    func beginMarquee(at point: SIMD2<Float>) {
        marquee = Marquee(origin: point, current: point)
        marqueeHitCount = 0
    }

    func updateMarquee(to point: SIMD2<Float>, viewportSize: SIMD2<Float>) {
        marquee?.current = point
        marqueeHitCount = unitsInMarquee(viewportSize: viewportSize).count
    }

    func cancelMarquee() {
        marquee = nil
        marqueeHitCount = 0
    }

    /// Commits the lasso to a selection.
    ///
    /// Units are projected to screen space and tested against the rectangle the
    /// player actually drew, rather than unprojecting the rectangle into a
    /// rotated world quad. Under a yawed camera those two are not the same
    /// shape, and only the first one matches what was on screen.
    func commitMarquee(viewportSize: SIMD2<Float>) {
        defer {
            marquee = nil
            marqueeHitCount = 0
        }
        guard let marquee else { return }

        // Smaller than a fingertip is a slipped press, not an intent to clear.
        let rect = marquee.rect
        guard rect.width >= 14 || rect.height >= 14 else { return }

        let hits = unitsInMarquee(viewportSize: viewportSize)
        // An empty box is a real instruction — the player drew over open ground
        // to let go of what they had.
        if hits.isEmpty { selection.clear() } else { selection.selectUnits(hits) }
    }

    private func unitsInMarquee(viewportSize: SIMD2<Float>) -> [EntityID] {
        guard let marquee, let rig else { return [] }
        let rect = marquee.rect
        return simulation.units.values
            .filter { $0.faction == .sunwoven }
            .filter { unit in
                guard let point = rig.screenPoint(forWorld: unit.position, viewportSize: viewportSize)
                else { return false }
                return rect.contains(CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)))
            }
            .map(\.id)
            .sorted { $0.raw < $1.raw }
    }

    // MARK: - Camera intents

    func pan(screenDelta: SIMD2<Float>, viewportHeight: Float) {
        guard let rig else { return }
        rig.pan(by: rig.worldDelta(forScreenDelta: screenDelta, viewportHeight: viewportHeight))
    }

    func zoom(to value: Float) { rig?.setZoom(value) }
    func yaw(to radians: Float) { rig?.setYaw(radians) }
    func returnNorth() { rig?.returnNorth() }

    var currentZoom: Float { rig?.zoom ?? simulation.tuning.cameraDefaultZoom }
    var currentYaw: Float { rig?.yaw ?? 0 }
    var currentFocus: WorldPoint { rig?.focus ?? .zero }
}
