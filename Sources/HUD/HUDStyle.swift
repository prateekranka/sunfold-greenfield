import SwiftUI

// MARK: - Metrics

/// Every dimension the tactical HUD uses.
///
/// One table, because six panels that each invent their own inset read as six
/// pieces of software stapled together. The frame around the play field only
/// holds if every edge of it lands on the same grid.
enum HUDMetrics {
    /// Distance a panel keeps from the screen edge. Panels that hang off the
    /// bezel (the top bar, the group rail) deliberately ignore it.
    static let edgeInset: CGFloat = 16
    static let topBarHeight: CGFloat = 46
    static let alertHeight: CGFloat = 27

    /// The single corner cut. Everything in the HUD is chamfered by the same
    /// amount so no panel reads as being from a different set.
    static let cut: CGFloat = 12
    static let tileCut: CGFloat = 7

    static let commandTile: CGFloat = 52
    static let toolTile: CGFloat = 31
    static let groupTile: CGFloat = 42
    static let portraitTile: CGFloat = 50
}

// MARK: - Ink

/// The HUD's colour language, derived from the locked palette rather than
/// re-hued: a dark field, a thin warm gold edge, ivory text, and turquoise used
/// only where the world already uses it — on the player's own selection.
enum HUDInk {
    static var field: Color { SunfoldPalette.hudPanel }
    /// A shade lighter than `field`, for wells cut *into* a panel (tile
    /// interiors, the minimap's void) so the HUD has two depths, not one.
    static var well: Color { Color(red: 0.043, green: 0.049, blue: 0.086) }
    static var edge: Color { SunfoldPalette.hudEdge }
    static var edgeBright: Color { Color(SunfoldPalette.sunwovenGold).opacity(0.80) }
    static var accent: Color { SunfoldPalette.hudAccent }
    static var text: Color { SunfoldPalette.hudText }
    static var textDim: Color { SunfoldPalette.hudTextDim }
    /// The player's own things. Same turquoise as the selection rings in world.
    static var friendly: Color { Color(SunfoldPalette.sunwovenTurquoise) }
    /// Restrained, per the bible: the enemy is marked in their own copper, not
    /// in alarm red. Saturated red stays reserved for genuine pressure.
    static var hostile: Color { Color(SunfoldPalette.gravemarkCopper) }
    /// Life. Green because the approved concept frame draws it green, held well
    /// down in saturation so it never competes with the gold.
    static var life: Color { Color(red: 0.404, green: 0.714, blue: 0.416) }
    static var warning: Color { Color(red: 0.867, green: 0.545, blue: 0.239) }

    /// The top-lit sheen every panel carries. A flat fill reads as a hole in the
    /// screen; a panel lit from the same direction as the diorama's key reads as
    /// a physical plate laid over it.
    static var sheen: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.075), location: 0.0),
                .init(color: .white.opacity(0.020), location: 0.18),
                .init(color: .clear, location: 0.55),
                .init(color: .black.opacity(0.22), location: 1.0),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Shape

/// Panel geometry for the tactical HUD.
///
/// The diorama is built entirely from flat-shaded facets and the Civilization
/// Core is an octagon, so the HUD **cuts** its corners rather than rounding
/// them. A rounded rectangle reads as generic app chrome laid on top of the
/// world; a chamfer reads as another object cut from the same material.
///
/// Corners are selectable because a panel anchored to a screen edge should only
/// cut the corners that face into the play area. Cutting all four makes the
/// panel float; cutting the two inner ones makes it read as attached to the
/// bezel, which keeps the player's attention on the world.
struct ChamferedRect: Shape {
    struct Corners: OptionSet, Sendable {
        let rawValue: Int
        init(rawValue: Int) { self.rawValue = rawValue }

        static let topLeading = Corners(rawValue: 1 << 0)
        static let topTrailing = Corners(rawValue: 1 << 1)
        static let bottomTrailing = Corners(rawValue: 1 << 2)
        static let bottomLeading = Corners(rawValue: 1 << 3)

        static let all: Corners = [.topLeading, .topTrailing, .bottomTrailing, .bottomLeading]
        static let bottom: Corners = [.bottomLeading, .bottomTrailing]
        static let top: Corners = [.topLeading, .topTrailing]
        static let leading: Corners = [.topLeading, .bottomLeading]
        static let trailing: Corners = [.topTrailing, .bottomTrailing]
    }

    var cut: CGFloat = 10
    var corners: Corners = .all

    func path(in rect: CGRect) -> Path {
        let cut = min(self.cut, min(rect.width, rect.height) / 2)
        let tl = corners.contains(.topLeading) ? cut : 0
        let tt = corners.contains(.topTrailing) ? cut : 0
        let bt = corners.contains(.bottomTrailing) ? cut : 0
        let bl = corners.contains(.bottomLeading) ? cut : 0

        var path = Path()
        path.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - tt, y: rect.minY))
        if tt > 0 { path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + tt)) }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bt))
        if bt > 0 { path.addLine(to: CGPoint(x: rect.maxX - bt, y: rect.maxY)) }
        path.addLine(to: CGPoint(x: rect.minX + bl, y: rect.maxY))
        if bl > 0 { path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - bl)) }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        if tl > 0 { path.addLine(to: CGPoint(x: rect.minX + tl, y: rect.minY)) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Surfaces

extension View {
    /// The one panel treatment every HUD surface uses. Centralised so no screen
    /// can quietly invent its own chrome.
    ///
    /// Three layers, and all three earn their place over the diorama: an opaque
    /// field so a star can never bleed through a glyph, a top-lit sheen so the
    /// plate has a direction, and a cast shadow so it sits *above* the world
    /// instead of being painted onto it. Without the shadow every panel reads as
    /// a hole punched in the frame.
    func hudSurface(
        cut: CGFloat = HUDMetrics.cut,
        corners: ChamferedRect.Corners = .all,
        edge: Color? = nil,
        fill: Color? = nil,
        lineWidth: CGFloat = 1,
        shadow: Bool = true
    ) -> some View {
        let shape = ChamferedRect(cut: cut, corners: corners)
        return self
            .background {
                shape
                    .fill(fill ?? HUDInk.field)
                    .overlay { shape.fill(HUDInk.sheen) }
                    .shadow(color: .black.opacity(shadow ? 0.55 : 0), radius: 13, x: 0, y: 4)
            }
            // Two strokes: the warm gold outer edge that identifies the set, and
            // a hairline inner highlight that gives the cut a bevel instead of a
            // printed outline.
            .overlay { shape.stroke(edge ?? HUDInk.edge, lineWidth: lineWidth) }
            .overlay {
                shape
                    .stroke(Color.white.opacity(0.055), lineWidth: 1)
                    .padding(1.5)
            }
            .compositingGroup()
    }

    /// Convenience for content that wants padding and the surface in one step.
    func hudPanel(
        cut: CGFloat = HUDMetrics.cut,
        corners: ChamferedRect.Corners = .all,
        padding: EdgeInsets = EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12)
    ) -> some View {
        self.padding(padding).hudSurface(cut: cut, corners: corners)
    }

    /// A well: an area that reads as recessed into its parent panel. Used for
    /// the minimap's void and for a tile's interior.
    func hudWell(cut: CGFloat = HUDMetrics.tileCut) -> some View {
        let shape = ChamferedRect(cut: cut)
        return self
            .background { shape.fill(HUDInk.well) }
            .overlay { shape.stroke(Color.black.opacity(0.55), lineWidth: 1) }
            .overlay {
                // A single lit line along the bottom inner edge is what makes an
                // area read as sunk rather than raised.
                shape.stroke(Color.white.opacity(0.05), lineWidth: 1).padding(1)
            }
            .clipShape(shape)
    }
}

// MARK: - Text

/// Small-caps label styling for the HUD's secondary text.
extension Text {
    func hudLabel() -> some View {
        self
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(HUDInk.textDim)
    }

    /// The heading voice: gold, tracked out, used once per panel.
    func hudTitle() -> some View {
        self
            .font(.system(size: 11, weight: .bold))
            .tracking(1.5)
            .foregroundStyle(HUDInk.accent)
    }

    /// Numbers the player reads at a glance. Monospaced digits so a counter
    /// ticking up never shifts the layout beside it.
    func hudNumber(size: CGFloat = 16) -> some View {
        self
            .font(.system(size: size, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(HUDInk.text)
    }
}

// MARK: - Meter

/// A thin horizontal meter. Used for construction progress, damage and a
/// citizen's carried load, so all three read as the same kind of statement.
struct HUDMeter: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.black.opacity(0.55))
                Capsule().stroke(Color.white.opacity(0.07), lineWidth: 0.5)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    .shadow(color: tint.opacity(0.55), radius: 2.5)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Tiles

/// One command / tool cell.
///
/// A tile is the HUD's only interactive primitive: the command grid, the map
/// tools, the transport controls and the group slots are all made of it, which
/// is why a player who learns one learns all four.
struct HUDIconTile: View {
    let glyph: HUDGlyph.Kind
    var size: CGFloat = HUDMetrics.commandTile
    var isEnabled: Bool = true
    /// The one action a context most wants. Marked with the player's own
    /// turquoise — the same colour that means "this is yours" in world.
    var isPrimary: Bool = false
    var badge: String?
    var name: String
    var action: (() -> Void)?

    var body: some View {
        Group {
            if let action, isEnabled {
                Button(action: action) { face }.buttonStyle(.plain)
            } else {
                face.opacity(0.42)
            }
        }
        .accessibilityLabel(name)
    }

    private var face: some View {
        ZStack {
            HUDGlyph(glyph)
                .fill(isPrimary ? HUDInk.friendly : HUDInk.accent, style: glyph.fillStyle)
                .frame(width: size * 0.52, height: size * 0.52)
                .shadow(color: (isPrimary ? HUDInk.friendly : HUDInk.accent).opacity(0.35), radius: 4)
        }
        .frame(width: size, height: size)
        .background {
            ChamferedRect(cut: HUDMetrics.tileCut)
                .fill(HUDInk.well)
                .overlay { ChamferedRect(cut: HUDMetrics.tileCut).fill(HUDInk.sheen) }
        }
        .overlay {
            ChamferedRect(cut: HUDMetrics.tileCut)
                .stroke(isPrimary ? HUDInk.friendly.opacity(0.85) : HUDInk.edge, lineWidth: 1)
        }
        .overlay(alignment: .bottomTrailing) {
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(HUDInk.text)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(Color.black.opacity(0.6), in: ChamferedRect(cut: 3))
                    .padding(3)
            }
        }
    }
}

// MARK: - Glyphs

/// The whole icon set, drawn as vectors in one place.
///
/// Icon-first is a locked art direction, and a game that mixes hand-drawn game
/// glyphs with system symbols reads as a prototype. Every mark the HUD shows —
/// resource, unit, structure, command, control — is authored here in a unit
/// square, so they share weight, optical size and corner language.
struct HUDGlyph: Shape {
    enum Kind: Hashable, Sendable {
        // Controls
        case sunburst, pause, play, speed2, speed3
        case compass, reticle, coreMark, expand, pin, alert
        // Commands
        case move, stop, guardStance, rally, gather
        // Structures
        case farm, extractor, dwelling, formationYard, outpost, loom
        // Units
        case citizen, pathfinder, vanguard, ranged, transport, walker
        // Readouts
        case life, population

        /// Glyphs built as an outline with something punched out of it.
        var usesEvenOdd: Bool {
            switch self {
            case .sunburst, .compass, .reticle, .alert, .stop, .loom, .farm, .expand: true
            default: false
            }
        }

        var fillStyle: FillStyle { FillStyle(eoFill: usesEvenOdd) }
    }

    let kind: Kind

    init(_ kind: Kind) { self.kind = kind }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        draw(&path)
        let side = min(rect.width, rect.height)
        let transform = CGAffineTransform(scaleX: side, y: side)
            .concatenating(CGAffineTransform(
                translationX: rect.midX - side / 2,
                y: rect.midY - side / 2
            ))
        return path.applying(transform)
    }

    // MARK: Drawing, all in a 1×1 unit square with y pointing down

    private func draw(_ p: inout Path) {
        switch kind {
        case .sunburst:
            star(&p, points: 12, outer: 0.50, inner: 0.19)
            p.addEllipse(in: CGRect(x: 0.37, y: 0.37, width: 0.26, height: 0.26))
        case .pause:
            p.addRect(CGRect(x: 0.26, y: 0.18, width: 0.16, height: 0.64))
            p.addRect(CGRect(x: 0.58, y: 0.18, width: 0.16, height: 0.64))
        case .play:
            triangle(&p, x: 0.30, width: 0.42)
        case .speed2:
            triangle(&p, x: 0.10, width: 0.38)
            triangle(&p, x: 0.50, width: 0.38)
        case .speed3:
            triangle(&p, x: 0.04, width: 0.30)
            triangle(&p, x: 0.35, width: 0.30)
            triangle(&p, x: 0.66, width: 0.30)

        case .compass:
            ring(&p, outer: 0.50, inner: 0.415)
            // A north needle: the filled half points up, the hollow half down.
            poly(&p, [(0.5, 0.14), (0.62, 0.5), (0.5, 0.44), (0.38, 0.5)])
            poly(&p, [(0.5, 0.86), (0.42, 0.54), (0.5, 0.58), (0.58, 0.54)])
        case .reticle:
            ring(&p, outer: 0.50, inner: 0.40)
            ring(&p, outer: 0.17, inner: 0.09)
            p.addRect(CGRect(x: 0.47, y: 0.0, width: 0.06, height: 0.16))
            p.addRect(CGRect(x: 0.47, y: 0.84, width: 0.06, height: 0.16))
            p.addRect(CGRect(x: 0.0, y: 0.47, width: 0.16, height: 0.06))
            p.addRect(CGRect(x: 0.84, y: 0.47, width: 0.16, height: 0.06))
        case .coreMark:
            regular(&p, sides: 8, radius: 0.46)
        case .expand:
            // Four corner brackets: "show me more of the map".
            for (dx, dy) in [(0.0, 0.0), (1.0, 0.0), (0.0, 1.0), (1.0, 1.0)] {
                let x = dx == 0 ? 0.04 : 0.66
                let y = dy == 0 ? 0.04 : 0.66
                p.addRect(CGRect(x: x, y: y, width: 0.30, height: 0.08))
                p.addRect(CGRect(x: dx == 0 ? x : x + 0.22, y: y, width: 0.08, height: 0.30))
            }
        case .pin:
            poly(&p, [(0.24, 0.06), (0.76, 0.06), (0.76, 0.94), (0.50, 0.70), (0.24, 0.94)])
        case .alert:
            poly(&p, [(0.5, 0.06), (0.97, 0.90), (0.03, 0.90)])
            p.addRect(CGRect(x: 0.45, y: 0.36, width: 0.10, height: 0.28))
            p.addRect(CGRect(x: 0.45, y: 0.70, width: 0.10, height: 0.10))

        case .move:
            // Four-way arrow, drawn as a cross plus four heads; overlapping
            // subpaths union cleanly under the non-zero rule.
            p.addRect(CGRect(x: 0.42, y: 0.16, width: 0.16, height: 0.68))
            p.addRect(CGRect(x: 0.16, y: 0.42, width: 0.68, height: 0.16))
            poly(&p, [(0.50, 0.02), (0.68, 0.24), (0.32, 0.24)])
            poly(&p, [(0.50, 0.98), (0.32, 0.76), (0.68, 0.76)])
            poly(&p, [(0.02, 0.50), (0.24, 0.32), (0.24, 0.68)])
            poly(&p, [(0.98, 0.50), (0.76, 0.68), (0.76, 0.32)])
        case .stop:
            regular(&p, sides: 8, radius: 0.48)
            regular(&p, sides: 8, radius: 0.34)
        case .guardStance:
            p.move(to: CGPoint(x: 0.5, y: 0.04))
            p.addLine(to: CGPoint(x: 0.90, y: 0.22))
            p.addCurve(
                to: CGPoint(x: 0.5, y: 0.96),
                control1: CGPoint(x: 0.90, y: 0.62),
                control2: CGPoint(x: 0.72, y: 0.86)
            )
            p.addCurve(
                to: CGPoint(x: 0.10, y: 0.22),
                control1: CGPoint(x: 0.28, y: 0.86),
                control2: CGPoint(x: 0.10, y: 0.62)
            )
            p.closeSubpath()
        case .rally:
            p.addRect(CGRect(x: 0.20, y: 0.04, width: 0.09, height: 0.92))
            poly(&p, [(0.29, 0.08), (0.88, 0.26), (0.29, 0.48)])
        case .gather:
            // An open hand closing over a load: two fingers and a palm.
            p.move(to: CGPoint(x: 0.5, y: 0.02))
            p.addQuadCurve(to: CGPoint(x: 0.20, y: 0.62), control: CGPoint(x: 0.02, y: 0.24))
            p.addQuadCurve(to: CGPoint(x: 0.80, y: 0.62), control: CGPoint(x: 0.5, y: 0.88))
            p.addQuadCurve(to: CGPoint(x: 0.5, y: 0.02), control: CGPoint(x: 0.98, y: 0.24))
            p.closeSubpath()

        case .farm:
            // A tilled plot in perspective, with three furrows punched out.
            poly(&p, [(0.06, 0.34), (0.62, 0.10), (0.94, 0.62), (0.38, 0.90)])
            for index in 0..<3 {
                let t = 0.22 + Double(index) * 0.22
                poly(&p, [
                    (0.06 + 0.56 * t, 0.34 - 0.24 * t),
                    (0.12 + 0.56 * t, 0.34 - 0.24 * t + 0.03),
                    (0.44 + 0.56 * t, 0.86 - 0.24 * t),
                    (0.38 + 0.56 * t, 0.86 - 0.24 * t - 0.03),
                ])
            }
        case .extractor:
            // A faceted block with a cutting head driven into it.
            poly(&p, [(0.06, 0.40), (0.40, 0.14), (0.74, 0.32), (0.66, 0.80), (0.20, 0.88)])
            poly(&p, [(0.56, 0.20), (0.96, 0.44), (0.86, 0.60), (0.50, 0.40)])
        case .dwelling:
            // A canopy: a soft tent with a woven ridge, not a house.
            p.move(to: CGPoint(x: 0.5, y: 0.06))
            p.addQuadCurve(to: CGPoint(x: 0.96, y: 0.78), control: CGPoint(x: 0.74, y: 0.52))
            p.addLine(to: CGPoint(x: 0.04, y: 0.78))
            p.addQuadCurve(to: CGPoint(x: 0.5, y: 0.06), control: CGPoint(x: 0.26, y: 0.52))
            p.closeSubpath()
            p.addRect(CGRect(x: 0.10, y: 0.82, width: 0.80, height: 0.10))
        case .formationYard:
            star(&p, points: 8, outer: 0.44, inner: 0.17, centerY: 0.42)
            p.addRect(CGRect(x: 0.12, y: 0.86, width: 0.76, height: 0.10))
        case .outpost:
            poly(&p, [(0.34, 0.20), (0.66, 0.20), (0.76, 0.94), (0.24, 0.94)])
            poly(&p, [(0.44, 0.02), (0.56, 0.02), (0.56, 0.20), (0.44, 0.20)])
            p.addRect(CGRect(x: 0.22, y: 0.20, width: 0.56, height: 0.08))
        case .loom:
            // The Dawn Loom: an arch of woven light.
            p.move(to: CGPoint(x: 0.06, y: 0.96))
            p.addLine(to: CGPoint(x: 0.06, y: 0.46))
            p.addQuadCurve(to: CGPoint(x: 0.94, y: 0.46), control: CGPoint(x: 0.5, y: -0.16))
            p.addLine(to: CGPoint(x: 0.94, y: 0.96))
            p.addLine(to: CGPoint(x: 0.78, y: 0.96))
            p.addLine(to: CGPoint(x: 0.78, y: 0.46))
            p.addQuadCurve(to: CGPoint(x: 0.22, y: 0.46), control: CGPoint(x: 0.5, y: 0.16))
            p.addLine(to: CGPoint(x: 0.22, y: 0.96))
            p.closeSubpath()

        case .citizen:
            biped(&p, shoulder: 0.20, hem: 0.30, headRadius: 0.115)
        case .pathfinder:
            biped(&p, shoulder: 0.15, hem: 0.23, headRadius: 0.100)
            // The sensor mast that names the silhouette at a glance.
            poly(&p, [(0.66, 0.06), (0.74, 0.06), (0.80, 0.52), (0.72, 0.52)])
        case .vanguard:
            biped(&p, shoulder: 0.20, hem: 0.28, headRadius: 0.110)
            poly(&p, [(0.06, 0.34), (0.30, 0.28), (0.30, 0.74), (0.06, 0.64)])
        case .ranged:
            biped(&p, shoulder: 0.17, hem: 0.25, headRadius: 0.105)
            p.move(to: CGPoint(x: 0.80, y: 0.16))
            p.addQuadCurve(to: CGPoint(x: 0.80, y: 0.86), control: CGPoint(x: 1.06, y: 0.51))
            p.addQuadCurve(to: CGPoint(x: 0.80, y: 0.16), control: CGPoint(x: 0.92, y: 0.51))
            p.closeSubpath()
        case .transport:
            // A flat skiff hull seen from the side, with a mast.
            p.move(to: CGPoint(x: 0.02, y: 0.58))
            p.addLine(to: CGPoint(x: 0.86, y: 0.50))
            p.addQuadCurve(to: CGPoint(x: 0.98, y: 0.62), control: CGPoint(x: 0.98, y: 0.52))
            p.addQuadCurve(to: CGPoint(x: 0.24, y: 0.82), control: CGPoint(x: 0.62, y: 0.82))
            p.closeSubpath()
            p.addRect(CGRect(x: 0.40, y: 0.14, width: 0.07, height: 0.40))
            poly(&p, [(0.47, 0.16), (0.78, 0.34), (0.47, 0.46)])
        case .walker:
            poly(&p, [(0.16, 0.20), (0.84, 0.14), (0.88, 0.50), (0.12, 0.56)])
            poly(&p, [(0.18, 0.54), (0.32, 0.54), (0.26, 0.96), (0.10, 0.96)])
            poly(&p, [(0.66, 0.52), (0.80, 0.52), (0.90, 0.94), (0.74, 0.94)])

        case .life:
            p.move(to: CGPoint(x: 0.5, y: 0.94))
            p.addCurve(
                to: CGPoint(x: 0.02, y: 0.34),
                control1: CGPoint(x: 0.12, y: 0.72),
                control2: CGPoint(x: 0.02, y: 0.52)
            )
            p.addArc(
                center: CGPoint(x: 0.26, y: 0.32),
                radius: 0.24,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            p.addArc(
                center: CGPoint(x: 0.74, y: 0.32),
                radius: 0.24,
                startAngle: .degrees(180),
                endAngle: .degrees(0),
                clockwise: false
            )
            p.addCurve(
                to: CGPoint(x: 0.5, y: 0.94),
                control1: CGPoint(x: 0.98, y: 0.52),
                control2: CGPoint(x: 0.88, y: 0.72)
            )
            p.closeSubpath()
        case .population:
            biped(&p, shoulder: 0.19, hem: 0.27, headRadius: 0.125)
        }
    }

    // MARK: Primitives

    private func poly(_ p: inout Path, _ points: [(Double, Double)]) {
        guard let first = points.first else { return }
        p.move(to: CGPoint(x: first.0, y: first.1))
        for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.0, y: point.1)) }
        p.closeSubpath()
    }

    private func regular(_ p: inout Path, sides: Int, radius: Double, centerY: Double = 0.5) {
        let points = (0..<sides).map { index -> (Double, Double) in
            let angle = Double(index) / Double(sides) * 2 * .pi - .pi / 2
            return (0.5 + cos(angle) * radius, centerY + sin(angle) * radius)
        }
        poly(&p, points)
    }

    private func star(_ p: inout Path, points: Int, outer: Double, inner: Double, centerY: Double = 0.5) {
        let steps = points * 2
        let coords = (0..<steps).map { step -> (Double, Double) in
            let radius = step.isMultiple(of: 2) ? outer : inner
            let angle = Double(step) / Double(steps) * 2 * .pi - .pi / 2
            return (0.5 + cos(angle) * radius, centerY + sin(angle) * radius)
        }
        poly(&p, coords)
    }

    private func ring(_ p: inout Path, outer: Double, inner: Double) {
        p.addEllipse(in: CGRect(x: 0.5 - outer, y: 0.5 - outer, width: outer * 2, height: outer * 2))
        p.addEllipse(in: CGRect(x: 0.5 - inner, y: 0.5 - inner, width: inner * 2, height: inner * 2))
    }

    private func triangle(_ p: inout Path, x: Double, width: Double) {
        poly(&p, [(x, 0.16), (x + width, 0.5), (x, 0.84)])
    }

    /// The shared human silhouette every unit glyph is cut from, so a Citizen
    /// and a Vanguard read as the same species with different jobs.
    private func biped(_ p: inout Path, shoulder: Double, hem: Double, headRadius: Double) {
        p.addEllipse(in: CGRect(
            x: 0.5 - headRadius,
            y: 0.06,
            width: headRadius * 2,
            height: headRadius * 2
        ))
        poly(&p, [
            (0.5 - shoulder, 0.36),
            (0.5 + shoulder, 0.36),
            (0.5 + hem, 0.96),
            (0.5 - hem, 0.96),
        ])
    }
}

// MARK: - Resource glyphs

/// A distinct silhouette for each resource.
///
/// The rail must be readable without relying on colour alone — four warm-ish
/// tints on a dark panel are not enough separation for a glance, let alone for
/// a colour-blind player. Each glyph therefore differs in outline, not just
/// hue: a leaf, a faceted block, a spiked star, a concave star.
struct ResourceGlyph: Shape {
    let kind: ResourceKind

    func path(in rect: CGRect) -> Path {
        switch kind {
        case .provisions: leaf(in: rect)
        case .matter: block(in: rect)
        case .lumen: spikedStar(in: rect)
        case .aether: concaveStar(in: rect)
        }
    }

    /// Growing, renewable: a pointed leaf leaning off vertical.
    private func leaf(in rect: CGRect) -> Path {
        var path = Path()
        let tip = CGPoint(x: rect.midX + rect.width * 0.20, y: rect.minY)
        let base = CGPoint(x: rect.midX - rect.width * 0.20, y: rect.maxY)
        path.move(to: tip)
        path.addQuadCurve(to: base, control: CGPoint(x: rect.maxX, y: rect.midY + rect.height * 0.18))
        path.addQuadCurve(to: tip, control: CGPoint(x: rect.minX, y: rect.midY - rect.height * 0.18))
        path.closeSubpath()
        return path
    }

    /// Mined, finite: a faceted block with one corner sheared off, echoing the
    /// deposit rocks it comes out of.
    private func block(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + w * 0.08, y: rect.minY + h * 0.34))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.46, y: rect.minY + h * 0.04))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.92, y: rect.minY + h * 0.26))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.98, y: rect.minY + h * 0.70))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.56, y: rect.minY + h * 0.98))
        path.addLine(to: CGPoint(x: rect.minX + w * 0.12, y: rect.minY + h * 0.76))
        path.closeSubpath()
        return path
    }

    /// Light: eight straight spikes, the only glyph with radial symmetry.
    private func spikedStar(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.40
        var path = Path()
        for step in 0..<16 {
            let radius = step.isMultiple(of: 2) ? outer : inner
            let angle = Double(step) / 16 * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    /// Aether: four points with edges curving *inward*, so it reads as drawn
    /// from the void rather than shining into it.
    private func concaveStar(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let points = (0..<4).map { index -> CGPoint in
            let angle = Double(index) / 4 * 2 * .pi - .pi / 2
            return CGPoint(
                x: center.x + CGFloat(cos(angle)) * radius,
                y: center.y + CGFloat(sin(angle)) * radius
            )
        }
        var path = Path()
        path.move(to: points[0])
        for index in 0..<4 {
            path.addQuadCurve(to: points[(index + 1) % 4], control: center)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Kind → glyph

extension UnitKind {
    var glyph: HUDGlyph.Kind {
        switch self {
        case .citizen: .citizen
        case .pathfinder: .pathfinder
        case .vanguard: .vanguard
        case .ranged: .ranged
        case .lightTransport: .transport
        case .bastionWalker: .walker
        }
    }
}

extension BuildingKind {
    var glyph: HUDGlyph.Kind {
        switch self {
        case .civilizationCore: .coreMark
        case .farm: .farm
        case .matterExtractor: .extractor
        case .dwelling: .dwelling
        case .formationYard: .formationYard
        case .expansionOutpost: .outpost
        case .dawnLoom: .loom
        // Nobody builds it and nobody selects it, so this glyph appears only in
        // the minimap legend. The reticle is the closest honest mark for a place
        // rather than a structure.
        case .dominionSpire: .reticle
        }
    }
}
