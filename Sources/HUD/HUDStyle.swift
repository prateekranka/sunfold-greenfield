import SwiftUI

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

extension View {
    /// The one panel treatment every HUD surface uses. Centralised so no screen
    /// can quietly invent its own chrome.
    func hudPanel(
        cut: CGFloat = 11,
        corners: ChamferedRect.Corners = .all,
        padding: EdgeInsets = EdgeInsets(top: 9, leading: 12, bottom: 9, trailing: 12)
    ) -> some View {
        let shape = ChamferedRect(cut: cut, corners: corners)
        return self
            .padding(padding)
            .background(SunfoldPalette.hudPanel, in: shape)
            .overlay(shape.stroke(SunfoldPalette.hudEdge, lineWidth: 1))
    }
}

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

/// A thin horizontal meter. Used for construction progress, damage and a
/// citizen's carried load, so all three read as the same kind of statement.
struct HUDMeter: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 3

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(SunfoldPalette.hudText.opacity(0.14))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: height)
    }
}

/// Small-caps label styling for the HUD's secondary text.
extension Text {
    func hudLabel() -> some View {
        self
            .font(.system(size: 9, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(SunfoldPalette.hudTextDim)
    }
}
