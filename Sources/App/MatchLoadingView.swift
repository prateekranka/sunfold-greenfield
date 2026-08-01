import SwiftUI

/// Keeps scene construction legible while RealityKit warms materials and builds
/// the new world. The loading state is brief, but it must not look like a dead
/// frame or invite input before the scene subscription exists.
struct MatchLoadingView: View {
    let faction: Faction

    var body: some View {
        ZStack {
            Color(SunfoldPalette.voidDeep)

            VStack(spacing: 10) {
                Text("SUNFOLD")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .tracking(5)
                    .foregroundStyle(HUDInk.accent)

                Text("WEAVING THE WORLD")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(HUDInk.text)

                ProgressView()
                    .tint(HUDInk.friendly(for: faction))
                    .accessibilityLabel("Building the world")
            }
            .hudSurface(edge: HUDInk.accent.opacity(0.72), fill: HUDInk.field)
            .padding(.horizontal, 48)
            .padding(.vertical, 30)
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Building the new match")
    }
}
