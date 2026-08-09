// Navigation graph for RTS space maps — platforms, bridges, and chokepoints.
// Bridges can be disabled; pathfinding respects repair state.

/**
 * @typedef {object} PathNode
 * @property {string} id
 * @property {number} x
 * @property {number} z
 * @property {string} [platformId]
 */

/**
 * @typedef {object} PathEdge
 * @property {string} id
 * @property {string} from
 * @property {string} to
 * @property {number} cost
 * @property {string} [bridgeId]
 * @property {boolean} enabled
 */

export class PathGraph {
  /**
   * @param {import('./map-definition.js').MapDefinition} def
   */
  constructor(def) {
    /** @type {Map<string, PathNode>} */
    this.nodes = new Map();
    /** @type {PathEdge[]} */
    this.edges = [];

    for (const p of def.terrain.platforms) {
      this.nodes.set(p.id, {
        id: p.id,
        x: p.center.x,
        z: p.center.z,
        platformId: p.id
      });
    }

    for (const r of def.resources) {
      const nid = `res-${r.id}`;
      this.nodes.set(nid, { id: nid, x: r.position.x, z: r.position.z, platformId: r.platformId });
    }

    for (const o of def.objectives) {
      const nid = `obj-${o.id}`;
      this.nodes.set(nid, { id: nid, x: o.position.x, z: o.position.z });
    }

    for (const b of def.bridges) {
      const mid = {
        id: `bridge-mid-${b.id}`,
        x: (b.from.x + b.to.x) / 2,
        z: (b.from.z + b.to.z) / 2
      };
      this.nodes.set(mid.id, mid);
      const len = Math.hypot(b.to.x - b.from.x, b.to.z - b.from.z);
      const enabled = b.startsEnabled !== false;
      this.addEdge(`edge-${b.id}-a`, b.fromPlatformId, mid.id, len * 0.5, b.id, enabled);
      this.addEdge(`edge-${b.id}-b`, mid.id, b.toPlatformId, len * 0.5, b.id, enabled);
    }

    // Adjacent platform shortcuts along the ring (intra-fragment movement)
    this._linkNearbyPlatforms(def, 22);
  }

  /**
   * @param {string} id
   * @param {string} from
   * @param {string} to
   * @param {number} cost
   * @param {string} [bridgeId]
   * @param {boolean} [enabled]
   */
  addEdge(id, from, to, cost, bridgeId, enabled = true) {
    if (!this.nodes.has(from) || !this.nodes.has(to)) return;
    this.edges.push({ id, from, to, cost, bridgeId, enabled });
    this.edges.push({ id: `${id}-rev`, from: to, to: from, cost, bridgeId, enabled });
  }

  /**
   * @param {import('./map-definition.js').MapDefinition} def
   * @param {number} maxDist
   */
  _linkNearbyPlatforms(def, maxDist) {
    const platforms = def.terrain.platforms;
    for (let i = 0; i < platforms.length; i += 1) {
      for (let j = i + 1; j < platforms.length; j += 1) {
        const a = platforms[i];
        const b = platforms[j];
        const d = Math.hypot(a.center.x - b.center.x, a.center.z - b.center.z);
        if (d <= maxDist && d > 0.5) {
          const bridgeBetween = def.bridges.some(
            (br) =>
              (br.fromPlatformId === a.id && br.toPlatformId === b.id) ||
              (br.fromPlatformId === b.id && br.toPlatformId === a.id)
          );
          if (!bridgeBetween) {
            this.addEdge(`near-${a.id}-${b.id}`, a.id, b.id, d);
          }
        }
      }
    }
  }

  /**
   * @param {string} bridgeId
   * @param {boolean} enabled
   */
  setBridgeEnabled(bridgeId, enabled) {
    for (const e of this.edges) {
      if (e.bridgeId === bridgeId) e.enabled = enabled;
    }
  }

  isBridgeEnabled(bridgeId) {
    const edge = this.edges.find((e) => e.bridgeId === bridgeId);
    return edge ? edge.enabled : false;
  }

  /**
   * @param {number} x
   * @param {number} z
   * @returns {string | null}
   */
  nearestNode(x, z) {
    let best = null;
    let bestD = Infinity;
    for (const n of this.nodes.values()) {
      const d = Math.hypot(n.x - x, n.z - z);
      if (d < bestD) {
        bestD = d;
        best = n.id;
      }
    }
    return best;
  }

  /**
   * A* on the path graph.
   * @param {number} fromX
   * @param {number} fromZ
   * @param {number} toX
   * @param {number} toZ
   * @returns {{ x: number, z: number }[]}
   */
  findPath(fromX, fromZ, toX, toZ) {
    const startId = this.nearestNode(fromX, fromZ);
    const goalId = this.nearestNode(toX, toZ);
    if (!startId || !goalId) return [{ x: toX, z: toZ }];

    const goal = this.nodes.get(goalId);
    const h = (id) => {
      const n = this.nodes.get(id);
      return Math.hypot(n.x - goal.x, n.z - goal.z);
    };

    const open = new Set([startId]);
    const cameFrom = new Map();
    const g = new Map([[startId, 0]]);
    const f = new Map([[startId, h(startId)]]);

    while (open.size > 0) {
      let current = null;
      let bestF = Infinity;
      for (const id of open) {
        const fv = f.get(id) ?? Infinity;
        if (fv < bestF) {
          bestF = fv;
          current = id;
        }
      }
      if (!current) break;
      if (current === goalId) {
        const path = [];
        let c = current;
        while (c) {
          const n = this.nodes.get(c);
          path.unshift({ x: n.x, z: n.z });
          c = cameFrom.get(c);
        }
        path.push({ x: toX, z: toZ });
        return path;
      }
      open.delete(current);
      for (const e of this.edges) {
        if (e.from !== current || !e.enabled) continue;
        const tentative = (g.get(current) ?? Infinity) + e.cost;
        if (tentative < (g.get(e.to) ?? Infinity)) {
          cameFrom.set(e.to, current);
          g.set(e.to, tentative);
          f.set(e.to, tentative + h(e.to));
          open.add(e.to);
        }
      }
    }

    return [{ x: toX, z: toZ }];
  }

  /** @returns {Record<string, unknown>} */
  toJSON() {
    return {
      nodes: [...this.nodes.values()],
      edges: this.edges.map((e) => ({ ...e }))
    };
  }
}
