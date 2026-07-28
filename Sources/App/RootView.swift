import SwiftUI

/// The app shell: the diorama, the tactical HUD over it, and the debug surface.
///
/// The HUD deliberately occupies only the top strip and the lower-left corner.
/// The centre of a landscape iPad is where the player's hands are not, and where
/// the game lives — nothing permanent is allowed to sit there.
struct RootView: View {
    @State private var controller: WorldController
    @State private var isDebugExpanded = true

    /// The debug surface is developer tooling, not chrome, and a visible telemetry
    /// panel is the single loudest "this is a dev build" signal in a captured
    /// frame. It is opt-in: pass `-sunfoldDebug` as a launch argument (Xcode
    /// scheme → Arguments) to bring it back.
    private static let showsDebugOverlay =
        ProcessInfo.processInfo.arguments.contains("-sunfoldDebug")

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
                HStack(alignment: .top, spacing: 0) {
                    GroupRail()
                        .padding(.leading, 12)
                        .padding(.top, 10)
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                bottomStrip
            }
        }
        .background(Color(SunfoldPalette.voidDeep))
        .preferredColorScheme(.dark)
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    /// Emblem and speed join the resource rail so the top edge matches concept 01.
    /// Debug stays inset and opt-in so it never contaminates a capture.
    private var topStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                TopBar(
                    stock: simulation.stock(for: .sunwoven),
                    population: simulation.population(for: .sunwoven),
                    age: simulation.age(for: .sunwoven)
                )
                if Self.showsDebugOverlay {
                    DebugOverlay(controller: controller, isExpanded: $isDebugExpanded)
                        .padding(.top, 4)
                }
            }
            AlertStrip()
                .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
    }

    /// Map at one thumb, commands at the other, and the selection between them.
    ///
    /// The selection panel sits centre-bottom rather than in the corner it used
    /// to occupy: it is the answer to "did my order land?", and the corner is
    /// where the eye goes last. It is also the only one of the three that comes
    /// and goes, so the two anchored panels must not move when it does — hence
    /// the centre column takes the slack rather than the panels being laid out
    /// against each other.
    private var bottomStrip: some View {
        HStack(alignment: .bottom, spacing: 14) {
            Minimap(simulation: simulation, rig: controller.rig)
            Spacer(minLength: 0)
            SelectionPanel(simulation: simulation, selection: controller.selection)
            Spacer(minLength: 0)
            CommandGrid(simulation: simulation, selection: controller.selection)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .animation(.easeOut(duration: 0.18), value: controller.selection.selectedUnits)
        .animation(.easeOut(duration: 0.18), value: controller.selection.selectedBuilding)
    }
}
