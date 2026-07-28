import SwiftUI
import simd

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
    /// The viewing faction. Its things are turquoise, the opponent's copper.
    var viewer: Faction = .sunwoven

    /// Width of the map well, in points. Sized so the smallest fragment — a
    /// 9 m outcrop — still lands on more than a single pixel.
    private static let width: CGFloat = 192

    /// Breathing room around the outermost rock, as a fraction of the land's
    /// own half-extent. Without it the far outcrops are cut in half by the well.
    private static let margin: Float = 1.07

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            // Width-pinned to the map. A `Spacer` in a column that has no width
            // of its own makes the whole column greedy, and the panel stretches
            // across the frame instead of sitting in its corner.
            HStack(spacing: 6) {
                Text("Theatre").hudTitle()
                Spacer(minLength: 0)
                Text(compassReading).hudLabel()
            }
            .frame(width: Self.width)
            Canvas(rendersAsynchronously: false) { context, size in
                draw(into: context, size: size)
            }
            .frame(width: wellSize.width, height: wellSize.height)
            .hudWell()
            tools
        }
        .hudPanel(corners: [.topLeading, .topTrailing, .bottomTrailing])
    }

    // MARK: - Fit

    /// Half-extent of the **land**, which is not `WorldMap.bounds`.
    ///
    /// `bounds` is a camera limit and is deliberately wider than the rock, so a
    /// well fitted to it leaves the map floating in dead space — measured at
    /// 80% × 47% of a square well, with the whole theatre pushed off-centre.
    /// What the player reads here is where the ground is, so the ground is what
    /// the well is fitted to.
    private var landExtent: WorldPoint {
        var extent = WorldPoint.zero
        for id in RegionID.allCases {
            let fragment = simulation.map.fragment(id)
            extent.x = max(extent.x, abs(fragment.center.x) + fragment.radius)
            extent.y = max(extent.y, abs(fragment.center.y) + fragment.radius)
        }
        return extent * Self.margin
    }

    /// The well takes the land's own aspect rather than a forced square. A
    /// square showing a 1.7:1 theatre can only ever be half empty, and the
    /// bible allows a rounded rectangle here.
    private var wellSize: CGSize {
        let extent = landExtent
        guard extent.x > 0, extent.y > 0 else {
            return CGSize(width: Self.width, height: Self.width)
        }
        let height = Self.width * CGFloat(extent.y / extent.x)
        return CGSize(width: Self.width, height: height.rounded())
    }

    // MARK: - Tools

    /// The map's own controls, in the same tile the command grid uses so the
    /// player learns one control and gets four.
    private var tools: some View {
        HStack(spacing: 5) {
            HUDIconTile(glyph: .compass, size: HUDMetrics.toolTile, name: "Face north")
            HUDIconTile(glyph: .coreMark, size: HUDMetrics.toolTile, name: "Go to Core")
            HUDIconTile(glyph: .pin, size: HUDMetrics.toolTile, name: "Place marker")
            HUDIconTile(glyph: .expand, size: HUDMetrics.toolTile, name: "Expand map")
        }
    }

    private var compassReading: String {
        guard let rig else { return "N" }
        // Yaw is measured about +Y with north at -Z, and the rig turns the world
        // under a fixed camera, so the heading the player is facing is the
        // negation of the rig's yaw.
        let degrees = (-rig.yaw * 180 / .pi).truncatingRemainder(dividingBy: 360)
        let wrapped = degrees < 0 ? degrees + 360 : degrees
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int((wrapped / 45).rounded()) % points.count
        return "\(points[index]) · \(Int(wrapped.rounded()))°"
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
        let scale = scale(for: size)
        return { point in
            CGPoint(
                x: size.width / 2 + CGFloat(point.x) * scale,
                y: size.height / 2 + CGFloat(point.y) * scale
            )
        }
    }

    private func draw(into context: GraphicsContext, size: CGSize) {
        let project = projector(size: size)
        let scale = scale(for: size)

        drawCauseways(context, project: project)
        drawFragments(context, project: project)
        drawDeposits(context, project: project)
        drawBuildings(context, project: project)
        drawUnits(context, project: project)
        drawViewport(context, project: project, scale: scale)
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

    private func drawFragments(
        _ context: GraphicsContext,
        project: (WorldPoint) -> CGPoint
    ) {
        for id in RegionID.allCases {
            let fragment = simulation.map.fragment(id)
            // Irregular silhouette matching the drawn rim — concept 01's map is
            // island-shaped, and a circle reads as a placeholder.
            let outline = FragmentMeshFactory.rimOutline(
                fragment: fragment,
                seed: simulation.map.seed,
                samples: 28
            )
            guard let first = outline.first else { continue }
            var land = Path()
            land.move(to: project(first))
            for point in outline.dropFirst() {
                land.addLine(to: project(point))
            }
            land.closeSubpath()
            context.fill(land, with: .color(fill(for: id)))
            context.stroke(land, with: .color(HUDInk.edge.opacity(0.7)), lineWidth: 0.75)
        }
    }

    /// A fragment is tinted by who holds it, so ownership is legible before any
    /// unit is drawn on top. Neutral ground stays the ground's own colour.
    private func fill(for id: RegionID) -> Color {
        switch id.startingOwner {
        case .some(let owner) where owner == viewer: HUDInk.friendly.opacity(0.42)
        case .some: HUDInk.hostile.opacity(0.42)
        case .none: Color(SunfoldPalette.neutralSurface).opacity(0.40)
        }
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
            let tint = building.faction == viewer ? HUDInk.friendly : HUDInk.hostile
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
            let tint = unit.faction == viewer ? HUDInk.friendly : HUDInk.hostile
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
        scale: CGFloat
    ) {
        guard let rig else { return }

        let halfHeight = rig.zoom / 2
        // The on-screen vertical extent is `zoom` metres, but the ground it
        // covers runs back by `zoom / sin(pitch)` because the camera looks along
        // a slope rather than straight down.
        let pitch = simulation.tuning.cameraPitchDegrees * .pi / 180
        let halfDepth = halfHeight / max(sin(pitch), 0.001)
        let halfWidth = halfHeight * Float(4.0 / 3.0)

        let corners: [SIMD2<Float>] = [
            [-halfWidth, -halfDepth], [halfWidth, -halfDepth],
            [halfWidth, halfDepth], [-halfWidth, halfDepth]
        ]
        let cosine = cos(rig.yaw), sine = sin(rig.yaw)
        var path = Path()
        for (index, corner) in corners.enumerated() {
            let rotated = SIMD2<Float>(
                corner.x * cosine - corner.y * sine,
                corner.x * sine + corner.y * cosine
            )
            let point = project(rig.focus + rotated)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()

        context.stroke(path, with: .color(HUDInk.text.opacity(0.85)), lineWidth: 1)
        context.fill(path, with: .color(.white.opacity(0.045)))
    }
}
