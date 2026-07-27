import SwiftUI

/// The selection lasso, drawn over the world while the player holds and drags.
///
/// Deliberately the same turquoise as the selection rings the lasso produces:
/// the box and the rings are one statement about what is now yours, so they use
/// one colour. Nothing else in the game may use it.
///
/// Lives inside `SunfoldRealityView` rather than the HUD stack so it shares the
/// gesture layer's exact coordinate space — the rectangle is in raw view points
/// and must land under the finger, not under the safe area.
struct MarqueeOverlay: View {
    let rect: CGRect?
    let hitCount: Int

    private var tint: Color { Color(SunfoldPalette.sunwovenTurquoise) }

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                if let rect, rect.width > 2 || rect.height > 2 {
                    box(rect)
                    // Live count, pinned to the box's leading corner. Confirms
                    // the lasso is working before the player lets go — without
                    // it, dragging over units that are small on screen is a
                    // guess that only resolves on release.
                    if hitCount > 0 { badge(rect) }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func box(_ rect: CGRect) -> some View {
        ChamferedRect(cut: 6)
            .fill(tint.opacity(0.13))
            .overlay(ChamferedRect(cut: 6).stroke(tint.opacity(0.85), lineWidth: 1.5))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private func badge(_ rect: CGRect) -> some View {
        Text("\(hitCount)")
            .font(.system(size: 13, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Color(SunfoldPalette.voidDeep))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint, in: Capsule())
            .position(x: rect.minX + 14, y: rect.minY - 12)
    }
}
