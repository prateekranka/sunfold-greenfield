import Foundation

/// Drives the simulation at a fixed step regardless of display frame rate.
///
/// The renderer may run at 60 or 120 Hz, or stutter; the simulation still advances
/// in equal slices, so gathering, combat, production and AI stay reproducible.
struct SimulationClock: Sendable {
    let stepDuration: Double
    let maxStepsPerFrame: Int

    private(set) var tick: UInt64 = 0
    private(set) var accumulator: Double = 0
    /// Wall-clock seconds of simulated match time. Drives AI gates and hint timers.
    private(set) var elapsed: Double = 0

    /// How far presentation should interpolate between the last two steps, in [0, 1).
    var interpolationAlpha: Double { accumulator / stepDuration }

    init(tuning: SkirmishTuning) {
        stepDuration = tuning.stepDuration
        maxStepsPerFrame = tuning.maxStepsPerFrame
    }

    /// Consumes real elapsed time and reports how many fixed steps to run.
    ///
    /// If the app was suspended or a frame took far too long, surplus time is
    /// dropped rather than replayed as a burst — a paused game must not fast-forward.
    mutating func advance(by deltaTime: Double) -> Int {
        guard deltaTime > 0 else { return 0 }
        accumulator += deltaTime

        var steps = 0
        while accumulator >= stepDuration && steps < maxStepsPerFrame {
            accumulator -= stepDuration
            steps += 1
        }

        if accumulator >= stepDuration {
            // Fell too far behind to catch up honestly. Drop the backlog.
            accumulator = 0
        }

        tick &+= UInt64(steps)
        elapsed += Double(steps) * stepDuration
        return steps
    }
}
