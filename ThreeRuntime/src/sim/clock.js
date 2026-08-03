// Drives the simulation at a fixed step regardless of display frame rate.
//
// Ported from `Sources/Simulation/SimulationClock.swift`. The renderer may run
// at 60 or 120 Hz, or stutter; the simulation still advances in equal slices,
// so gathering, construction, production and movement stay reproducible.

export const SIMULATION_HZ = 20;
export const STEP_DURATION = 1 / SIMULATION_HZ;
export const MAX_STEPS_PER_FRAME = 5;

export class SimulationClock {
  constructor({ hz = SIMULATION_HZ, maxStepsPerFrame = MAX_STEPS_PER_FRAME } = {}) {
    this.hz = hz;
    this.stepDuration = 1 / hz;
    this.maxStepsPerFrame = maxStepsPerFrame;
    this.tick = 0;
    this.accumulator = 0;
    /** Simulated match seconds. Derived from the tick count, never accumulated. */
    this.elapsed = 0;
  }

  /** How far presentation should interpolate between the last two steps, in [0, 1). */
  get interpolationAlpha() {
    return this.accumulator / this.stepDuration;
  }

  /**
   * Consumes real elapsed time and reports how many fixed steps to run.
   *
   * If the app was suspended or a frame took far too long, surplus time is
   * dropped rather than replayed as a burst — a resumed game must not
   * fast-forward through the time it spent in the background.
   */
  advance(deltaTime) {
    if (!(deltaTime > 0)) return 0;
    this.accumulator += deltaTime;

    let steps = 0;
    while (this.accumulator >= this.stepDuration && steps < this.maxStepsPerFrame) {
      this.accumulator -= this.stepDuration;
      steps += 1;
    }

    if (this.accumulator >= this.stepDuration) {
      // Fell too far behind to catch up honestly. Drop the backlog.
      this.accumulator = 0;
    }

    this.tick += steps;
    // Elapsed is recomputed from the tick count rather than summed, so a long
    // match cannot drift by accumulated floating-point error — tick 36000 is
    // exactly 1800 s on every run, which is what the AI gates and hold
    // schedules are written against.
    this.elapsed = this.tick * this.stepDuration;
    return steps;
  }

  snapshot() {
    // The accumulator is deliberately excluded: it is sub-step presentation
    // residue, not simulation truth, and restoring it would make a reload
    // depend on exactly when the save happened inside a frame.
    return { tick: this.tick };
  }

  static restore(snapshot, options = {}) {
    const clock = new SimulationClock(options);
    clock.tick = snapshot.tick >>> 0;
    clock.elapsed = clock.tick * clock.stepDuration;
    return clock;
  }
}
