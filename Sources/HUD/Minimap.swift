import SwiftUI
import simd
import UIKit

/// The whole battlefield at a glance: every fragment, the routes between them,
/// what stands on them, and where the camera is looking.
///
/// This is the one surface that shows the player something the diorama cannot.
/// The camera holds two fragments at most; the map holds all seven, so it is
/// where the answer to "where is the enemy" and "where have I not been" lives.
///
/// It renders from `WorldMap` and the live simulation rather than from a baked
/// image, so it can never disagree with the world — a minimap that drifts out of
/// step with the terrain is worse than none, because the player trusts it.
struct Minimap: View {
    let simulation: SkirmishSimulation
    let rig: CameraRig?
    /// The viewing faction. Its units/buildings are turquoise, the opponent's
    /// copper. Landmasses themselves are never faction-tinted.
    var viewer: Faction = .sunwoven

    /// Width of the map well, in points. Sized so the smallest fragment — a
    /// 9 m outcrop — still lands on more than a single pixel.
    private static let baseWidth: CGFloat = 192
    private static let expandedWidth: CGFloat = 320

    /// Breathing room around the outermost rock, as a fraction of the land's
    /// own half-extent. Without it the far outcrops are cut in half by the well.
    private static let margin: Float = 1.07

    /// Toggled by "Expand map" for the rest of the session.
    @State private var isExpanded = false

    private var wellWidth: CGFloat {
        isExpanded ? Self.expandedWidth : Self.baseWidth
    }

    var body: some View {
        // Read rig state in the body so the Canvas redraws when the camera moves.
        let rigFocus = rig?.focus
        let rigYaw = rig?.yaw
        let rigZoom = rig?.zoom

        VStack(alignment: .leading, spacing: 7) {
            // Width-pinned to the map. A `Spacer` in a column that has no width
            // of its own makes the whole column greedy, and the panel stretches
            // across the frame instead of sitting in its corner.
            HStack(spacing: 6) {
                Text("Theatre").hudTitle()
                Spacer(minLength: 0)
                Text(compassReading(yaw: rigYaw)).hudLabel()
            }
            .frame(width: wellWidth)
            Canvas(rendersAsynchronously: false) { context, size in
                draw(
                    into: context,
                    size: size,
                    rigFocus: rigFocus,
                    rigYaw: rigYaw,
                    rigZoom: rigZoom
                )
            }
            .frame(width: wellSize.width, height: wellSize.height)
            .contentShape(Rectangle())
            .gesture(minimapNavigationGesture)
            .hudWell()
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("minimap")
            .accessibilityLabel("Minimap, \(viewer.displayName) perspective")
            .accessibilityValue(accessibilityCameraValue)
            .accessibilityHint("Tap or drag to move the camera. Adjust up or down to pan north or south.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment:
                    moveCamera(for: .north)
                case .decrement:
                    moveCamera(for: .south)
                @unknown default:
                    break
                }
            }
            .accessibilityAction(named: Text("Move camera west")) {
                moveCamera(for: .west)
            }
            .accessibilityAction(named: Text("Move camera east")) {
                moveCamera(for: .east)
            }
            tools
        }
        .hudPanel(corners: [.topLeading, .topTrailing, .bottomTrailing])
    }

    // MARK: - Fit

    /// The traced coastline, cached per map.
    ///
    /// Marching a 220-square grid is far too much to redo on every SwiftUI redraw
    /// — and this view redraws whenever a unit moves — but the coastline only
    /// changes when the map does. Keying the cache on identity and seed means a
    /// map switch invalidates it and nothing else does.
    private var contour: LandContour.Result {
        Self.contourCache.value(for: simulation.map)
    }

    private static let contourCache = ContourCache()

    /// Half-extent of the **land**, which is not `WorldMap.bounds`.
    ///
    /// `bounds` is a camera limit and is deliberately wider than the rock, so a
    /// well fitted to it leaves the map floating in dead space — measured at
    /// 80% × 47% of a square well, with the whole theatre pushed off-centre.
    /// What the player reads here is where the ground is, so the ground is what
    /// the well is fitted to.
    private var landExtent: WorldPoint {
        contour.extent * Self.margin
    }

    /// The well takes the land's own aspect rather than a forced square. A
    /// square showing a 1.7:1 theatre can only ever be half empty, and the
    /// bible allows a rounded rectangle here.
    private var wellSize: CGSize {
        let extent = landExtent
        guard extent.x > 0, extent.y > 0 else {
            return CGSize(width: wellWidth, height: wellWidth)
        }
        let height = wellWidth * CGFloat(extent.y / extent.x)
        return CGSize(width: wellWidth, height: height.rounded())
    }

    // MARK: - Tools

    /// The map's own controls, in the same tile the command grid uses so the
    /// player learns one control and gets four.
    private var tools: some View {
        HStack(spacing: 5) {
            HUDIconTile(
                glyph: .compass,
                size: HUDMetrics.toolTile,
                name: "Face north",
                action: faceNorth
            )
            HUDIconTile(
                glyph: .coreMark,
                size: HUDMetrics.toolTile,
                name: "Go to Core",
                action: goToCore
            )
            HUDIconTile(
                glyph: .pin,
                size: HUDMetrics.toolTile,
                isEnabled: false,
                name: "Place marker unavailable"
            )
            HUDIconTile(
                glyph: .expand,
                size: HUDMetrics.toolTile,
                name: isExpanded ? "Collapse map" : "Expand map",
                action: { isExpanded.toggle() }
            )
        }
    }

    private func compassReading(yaw: Float?) -> String {
        guard let yaw else { return "N" }
        // Yaw is measured about +Y with north at -Z, and the rig turns the world
        // under a fixed camera, so the heading the player is facing is the
        // negation of the rig's yaw.
        let degrees = (-yaw * 180 / .pi).truncatingRemainder(dividingBy: 360)
        let wrapped = degrees < 0 ? degrees + 360 : degrees
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((wrapped / 45).rounded()) % points.count
        return "\(points[index]) · \(Int(wrapped.rounded()))°"
    }

    // MARK: - Navigation

    private enum AccessibilityPanDirection {
        case north
        case south
        case west
        case east

        var delta: WorldPoint {
            switch self {
            case .north: [0, -1]
            case .south: [0, 1]
            case .west: [-1, 0]
            case .east: [1, 0]
            }
        }
    }

    private var accessibilityCameraValue: String {
        guard let focus = rig?.focus else {
            return "Camera unavailable"
        }
        return "Camera at \(mapPositionDescription(focus)); \(compassReading(yaw: rig?.yaw))"
    }

    private func mapPositionDescription(_ focus: WorldPoint) -> String {
        let bounds = simulation.map.bounds
        let horizontal = relativePosition(
            focus.x,
            limit: bounds.x,
            negative: "west",
            positive: "east"
        )
        let vertical = relativePosition(
            focus.y,
            limit: bounds.y,
            negative: "north",
            positive: "south"
        )

        switch (vertical, horizontal) {
        case ("center", "center"):
            return "the map center"
        case ("center", _):
            return "the \(horizontal) side"
        case (_, "center"):
            return "the \(vertical) side"
        default:
            return "the \(vertical) \(horizontal)"
        }
    }

    private func relativePosition(
        _ value: Float,
        limit: Float,
        negative: String,
        positive: String
    ) -> String {
        guard limit > 0 else { return "center" }
        let fraction = value / limit
        if fraction < -0.25 { return negative }
        if fraction > 0.25 { return positive }
        return "center"
    }

    private func moveCamera(for direction: AccessibilityPanDirection) {
        guard let rig else { return }
        let step = max(rig.zoom * 0.5, 1)
        rig.pan(by: direction.delta * step)
    }

    /// Tap-to-jump and drag-to-scrub share one gesture: `minimumDistance` of zero
    /// fires on first contact and keeps updating while the finger moves.
    private var minimapNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                focusCamera(at: value.location)
            }
    }

    private func focusCamera(at location: CGPoint) {
        guard let rig else { return }
        rig.setFocus(unproject(location, in: wellSize))
    }

    private func faceNorth() {
        rig?.returnNorth()
    }

    private func goToCore() {
        guard let rig,
              let core = simulation.buildings.values.first(where: {
                  $0.kind == .civilizationCore && $0.faction == viewer
              })
        else { return }
        rig.setFocus(core.position)
    }

    // MARK: - Drawing

    /// World metres to map points.
    ///
    /// One scale for both axes, taken from whichever axis binds first. A
    /// per-axis fit would stretch the fragments into ellipses and break the one
    /// promise this surface makes, which is that it is the same shape as the
    /// world. The well is already cut to the land's aspect, so in practice the
    /// two axes agree and nothing is left over.
    private func scale(for size: CGSize) -> CGFloat {
        let extent = landExtent
        guard extent.x > 0, extent.y > 0 else { return 1 }
        return min(
            size.width / CGFloat(extent.x * 2),
            size.height / CGFloat(extent.y * 2)
        )
    }

    private func projector(size: CGSize) -> (WorldPoint) -> CGPoint {
        mapTransform(for: size).project
    }

    /// The exact inverse of `projector`. One `scale(for:)` feeds both directions
    /// so hit-testing and drawing can never drift apart.
    private func unproject(_ point: CGPoint, in size: CGSize) -> WorldPoint {
        mapTransform(for: size).unproject(point)
    }

    private func mapTransform(for size: CGSize) -> (
        project: (WorldPoint) -> CGPoint,
        unproject: (CGPoint) -> WorldPoint
    ) {
        let scale = scale(for: size)
        return (
            project: { world in
                CGPoint(
                    x: size.width / 2 + CGFloat(world.x) * scale,
                    y: size.height / 2 + CGFloat(world.y) * scale
                )
            },
            unproject: { screen in
                WorldPoint(
                    Float((screen.x - size.width / 2) / scale),
                    Float((screen.y - size.height / 2) / scale)
                )
            }
        )
    }

    private func draw(
        into context: GraphicsContext,
        size: CGSize,
        rigFocus: WorldPoint?,
        rigYaw: Float?,
        rigZoom: Float?
    ) {
        let project = projector(size: size)
        let scale = scale(for: size)

        drawCauseways(context, project: project)
        drawFragments(context, project: project)
        drawDeposits(context, project: project)
        drawBuildings(context, project: project)
        drawUnits(context, project: project)
        drawViewport(
            context,
            project: project,
            scale: scale,
            focus: rigFocus,
            yaw: rigYaw,
            zoom: rigZoom
        )
    }

    /// Routes first and underneath: they are context for the fragments, not
    /// objects in their own right.
    private func drawCauseways(_ context: GraphicsContext, project: (WorldPoint) -> CGPoint) {
        for causeway in simulation.map.causeways {
            var path = Path()
            path.move(to: project(simulation.map.fragment(causeway.from).center))
            path.addLine(to: project(simulation.map.fragment(causeway.to).center))
            context.stroke(
                path,
                with: .color(HUDInk.accent.opacity(causeway.isAlwaysOpen ? 0.34 : 0.15)),
                style: StrokeStyle(
                    lineWidth: 1,
                    // A causeway that has to be woven first is drawn as a dashed
                    // intention rather than a road, because it is not one yet.
                    dash: causeway.isAlwaysOpen ? [] : [2.5, 3]
                )
            )
        }
    }

    /// The landmass, as one filled shape with its lakes punched out of it.
    ///
    /// Every loop goes into a single `Path` and is filled once with the non-zero
    /// rule. That is the whole trick: outer coasts and lake holes come out of
    /// `LandContour` wound opposite ways, so the holes cancel and the coasts do
    /// not, and — the part that matters here — **no edge is drawn inside the
    /// land**. Drawing a plate at a time put a stroked circle across the middle of
    /// the continent seven times over, which is what the theatre actually looked
    /// like: overlapping circles.
    private func drawFragments(
        _ context: GraphicsContext,
        project: (WorldPoint) -> CGPoint
    ) {
        var land = Path()
        for loop in contour.loops {
            guard let first = loop.first else { continue }
            land.move(to: project(first))
            for point in loop.dropFirst() {
                land.addLine(to: project(point))
            }
            land.closeSubpath()
        }
        guard !land.isEmpty else { return }

        // Landmasses share one neutral ground fill. Ownership is read from the
        // buildings and units drawn on top — not from painting the rock itself
        // friendly/hostile (user constraint 2026-07-28).
        context.fill(land, with: .color(Color(SunfoldPalette.landSurface).opacity(0.48)))
        context.stroke(land, with: .color(HUDInk.edge.opacity(0.7)), lineWidth: 0.75)
    }

    private func drawDeposits(_ context: GraphicsContext, project: (WorldPoint) -> CGPoint) {
        for deposit in simulation.deposits.values {
            let point = project(deposit.position)
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 1, y: point.y - 1, width: 2, height: 2)),
                with: .color(HUDInk.accent.opacity(0.55))
            )
        }
    }

    /// Structures read as squares and units as dots. Shape carries the
    /// distinction rather than colour, because colour is already spent on
    /// telling the two sides apart.
    private func drawBuildings(_ context: GraphicsContext, project: (WorldPoint) -> CGPoint) {
        for building in simulation.buildings.values {
            let point = project(building.position)
            let side: CGFloat = 4.5
            let rect = CGRect(
                x: point.x - side / 2,
                y: point.y - side / 2,
                width: side,
                height: side
            )
            // Neutral is neither: painting the objective in the enemy's copper
            // would read as "they hold it", which is the one thing the minimap
            // must not lie about.
            let tint: Color
            switch building.faction {
            case viewer: tint = HUDInk.friendly(for: viewer)
            case nil: tint = HUDInk.textDim
            default: tint = HUDInk.hostile(for: viewer)
            }
            context.fill(Path(rect), with: .color(tint))
            context.stroke(Path(rect), with: .color(.black.opacity(0.65)), lineWidth: 0.75)
        }
    }

    private func drawUnits(_ context: GraphicsContext, project: (WorldPoint) -> CGPoint) {
        for unit in simulation.units.values where !unit.isAboard {
            let point = project(unit.position)
            let radius: CGFloat = 1.8
            let dot = Path(
                ellipseIn: CGRect(
                    x: point.x - radius,
                    y: point.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            let tint = unit.faction == viewer
                ? HUDInk.friendly(for: viewer)
                : HUDInk.hostile(for: viewer)
            context.fill(dot, with: .color(tint))
        }
    }

    /// The camera's footprint, drawn as the quadrilateral it actually covers.
    ///
    /// An axis-aligned rectangle would be a lie the moment the player yaws the
    /// camera, and yaw is a control this game ships. The corners are rotated by
    /// the rig's yaw and stretched along Z by the camera pitch, which is what
    /// makes the shape agree with what is on screen.
    private func drawViewport(
        _ context: GraphicsContext,
        project: (WorldPoint) -> CGPoint,
        scale: CGFloat,
        focus: WorldPoint?,
        yaw: Float?,
        zoom: Float?
    ) {
        guard let focus, let yaw, let zoom else { return }

        let halfHeight = zoom / 2
        // The on-screen vertical extent is `zoom` metres, but the ground it
        // covers runs back by `zoom / sin(pitch)` because the camera looks along
        // a slope rather than straight down.
        let pitch = simulation.tuning.cameraPitchDegrees * .pi / 180
        let halfDepth = halfHeight / max(sin(pitch), 0.001)
        // Match the panel aspect (landscape width / height), not a hardcoded 4:3.
        // 13-inch Air is 1.333; 11-inch A16 is 1.439 — a fixed ratio mis-draws
        // the viewport on every non-Air device.
        let screenBounds = UIScreen.main.bounds
        let panelAspect = Float(max(screenBounds.width, screenBounds.height)
            / min(screenBounds.width, screenBounds.height))
        let halfWidth = halfHeight * panelAspect

        let corners: [SIMD2<Float>] = [
            [-halfWidth, -halfDepth], [halfWidth, -halfDepth],
            [halfWidth, halfDepth], [-halfWidth, halfDepth]
        ]
        let cosine = cos(yaw), sine = sin(yaw)
        var path = Path()
        for (index, corner) in corners.enumerated() {
            let rotated = SIMD2<Float>(
                corner.x * cosine - corner.y * sine,
                corner.x * sine + corner.y * cosine
            )
            let point = project(focus + rotated)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()

        context.stroke(path, with: .color(HUDInk.text.opacity(0.85)), lineWidth: 1)
        context.fill(path, with: .color(.white.opacity(0.045)))
    }
}

/// Holds the traced coastline for the map currently loaded.
///
/// One entry, not a dictionary: only one map is on screen at a time, and a cache
/// that grows for the life of the process to hold maps nobody is looking at is a
/// leak with extra steps.
private final class ContourCache: @unchecked Sendable {
    private let lock = NSLock()
    private var key: (WorldMapID, UInt64)?
    private var cached: LandContour.Result?

    func value(for map: WorldMap) -> LandContour.Result {
        lock.lock()
        defer { lock.unlock() }
        if let key, key == (map.id, map.seed), let cached { return cached }
        let traced = LandContour.trace(map)
        key = (map.id, map.seed)
        cached = traced
        return traced
    }
}
