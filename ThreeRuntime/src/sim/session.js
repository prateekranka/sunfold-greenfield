// The runtime session: one live simulation's ownership, on behalf of the shell.
//
// `main.js` is DOM and WebGL glue; this module is the part of the lifecycle
// that can be exercised headless — which is where the determinism and
// save/restore contracts are actually proven. The ownership rules #22 pins on
// the runtime live here:
//
//   - exactly one `Simulation` exists per started or restored match;
//   - time enters only as render deltas, which the fixed clock inside
//     `Simulation.update` turns into whole 20 Hz steps;
//   - serialisation happens only when `save()` is called — the shell calls it
//     from its `saveGame` command path and nowhere else;
//   - `dispose()` ends runtime ownership, so a return to the menu leaves no
//     simulation quietly advancing behind a scene that no longer exists.

import { Simulation } from "./simulation.js";

export class SimulationSession {
  constructor() {
    /** @type {Simulation | null} */
    this.simulation = null;
  }

  get active() {
    return this.simulation !== null;
  }

  get paused() {
    return this.simulation ? this.simulation.paused : false;
  }

  /** The live world hash, or null when no match is owned. */
  hash() {
    return this.simulation ? this.simulation.hash() : null;
  }

  /**
   * Starts a fresh match. Any previous simulation is replaced outright — the
   * shell starts matches only from the menu, so there is nothing to preserve.
   */
  start({ faction = "sunwoven", seed, mapID } = {}) {
    const options = { playerFaction: faction };
    if (seed !== undefined) options.seed = seed;
    if (mapID !== undefined) options.mapID = mapID;
    this.simulation = new Simulation(options);
    return this.simulation;
  }

  /**
   * Restores a match from a save document. A malformed or foreign-version
   * document raises from `restoreSnapshot` — the shell turns that into a
   * fail-closed bridge error, and the previous simulation (if any) stays
   * owned and untouched.
   */
  restore(document) {
    const restored = Simulation.restore(document);
    this.simulation = restored;
    return restored;
  }

  /**
   * Feeds one frame's real time to the simulation. Returns how many fixed
   * steps ran — zero when paused or when no match is owned, so a shell that
   * calls this before `startGame` cannot manufacture time.
   */
  update(deltaTime) {
    if (!this.simulation) return 0;
    return this.simulation.update(deltaTime);
  }

  setPaused(paused) {
    if (this.simulation) this.simulation.setPaused(paused);
  }

  /**
   * The only path to a save document. Returns null when no match is owned, so
   * the shell can refuse the save rather than file an empty world over a good
   * slot.
   */
  save() {
    return this.simulation ? this.simulation.save() : null;
  }

  /** Ends runtime ownership. After this, `update` is a no-op and `save` is null. */
  dispose() {
    this.simulation = null;
  }
}
