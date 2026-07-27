import SwiftUI

@main
struct SunfoldGreenfieldApp: App {
    /// The authored, locked seed for the first playable map. Procedural variation
    /// is a later checkpoint; every G0–G6 run must be reproducible from this value.
    static let lockedSeed: UInt64 = 20_260_726

    var body: some Scene {
        WindowGroup {
            RootView(seed: Self.lockedSeed)
        }
    }
}
