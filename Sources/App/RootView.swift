import SwiftUI

/// The app shell: the diorama, the tactical HUD over it, and the debug surface.
///
/// The HUD deliberately occupies only the top strip and the lower-left corner.
/// The centre of a landscape iPad is where the player's hands are not, and where
/// the game lives — nothing permanent is allowed to sit there.
struct RootView: View {
    @State private var controller: WorldController
    @State private var isDebugExpanded = true

    init(seed: UInt64) {
        _controller = State(initialValue: WorldController(simulation: SkirmishSimulation(seed: seed)))
    }

    private var simulation: SkirmishSimulation { controller.simulation }

    var body: some View {
        ZStack(alignment: .topLeading) {
            SunfoldRealityView(controller: controller)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topStrip
                Spacer(minLength: 0)
                bottomStrip
            }
        }
        .background(Color(SunfoldPalette.voidDeep))
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    /// The rail hangs from the top edge; the debug panel is inset from it so the
    /// two never read as one piece of chrome.
    private var topStrip: some View {
        HStack(alignment: .top, spacing: 12) {
            ResourceRail(
                stock: simulation.stock(for: .sunwoven),
                population: simulation.population(for: .sunwoven),
                age: simulation.age(for: .sunwoven)
            )
            Spacer(minLength: 0)
            DebugOverlay(controller: controller, isExpanded: $isDebugExpanded)
                .padding(.top, 12)
        }
        .padding(.horizontal, 20)
    }

    private var bottomStrip: some View {
        HStack(alignment: .bottom) {
            SelectionPanel(simulation: simulation, selection: controller.selection)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.18), value: controller.selection.selectedUnits)
        .animation(.easeOut(duration: 0.18), value: controller.selection.selectedBuilding)
    }
}
