export class MarkerScheduler {
  constructor(markers) {
    this.markers = markers;
    this.reset();
  }

  reset() {
    this.clipName = null;
    this.cycle = 0;
    this.previousTime = 0;
    this.fired = new Set();
  }

  advance(clipName, timeS) {
    if (clipName !== this.clipName) {
      this.reset();
      this.clipName = clipName;
    } else if (timeS + 1e-6 < this.previousTime) {
      this.cycle += 1;
    }
    const emitted = [];
    for (const marker of this.markers) {
      if (marker.clip !== clipName) continue;
      const key = `${clipName}:${this.cycle}:${marker.name}`;
      if (timeS >= marker.time_s - 1e-6 && !this.fired.has(key)) {
        this.fired.add(key);
        emitted.push(marker);
      }
    }
    this.previousTime = timeS;
    return emitted;
  }
}
