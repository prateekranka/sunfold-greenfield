import assert from "node:assert/strict";
import test from "node:test";

import { HELIOS_RIFT } from "../src/rts-maps/maps/helios-rift.js";
import { PathGraph } from "../src/rts-maps/path-graph.js";
import { applyHazardBridgeAvailability, createHazards } from "../src/rts-maps/hazard-system.js";
import {
  findWalkablePath,
  isPointWalkable,
  isPolylineWalkable,
  nearestWalkablePoint
} from "../src/rts-maps/ground-navigation.js";

function makeNavigation() {
  const bridgeStates = new Map(
    HELIOS_RIFT.bridges.map((bridge) => [bridge.id, bridge.startsEnabled !== false])
  );
  const pathGraph = new PathGraph(HELIOS_RIFT);
  return { bridgeStates, pathGraph };
}

test("Helios land rules reject open void and accept authored ground", () => {
  const { bridgeStates } = makeNavigation();
  assert.equal(isPointWalkable(HELIOS_RIFT, bridgeStates, 0, -32), true, "north fragment");
  assert.equal(isPointWalkable(HELIOS_RIFT, bridgeStates, 0, -8), true, "core platform");
  assert.equal(isPointWalkable(HELIOS_RIFT, bridgeStates, 22, -22), true, "expansion islet");
  assert.equal(isPointWalkable(HELIOS_RIFT, bridgeStates, 15, 15), false, "open inner void");
  assert.equal(isPointWalkable(HELIOS_RIFT, bridgeStates, 49, 0), false, "outer space");
});

test("reachable Helios paths stay on platforms and enabled bridges", () => {
  const { bridgeStates, pathGraph } = makeNavigation();
  const routes = [
    findWalkablePath(HELIOS_RIFT, pathGraph, bridgeStates, 0, -32, 0, -8),
    findWalkablePath(HELIOS_RIFT, pathGraph, bridgeStates, 0, -32, 32, 0),
    findWalkablePath(HELIOS_RIFT, pathGraph, bridgeStates, 0, -32, -4, -29)
  ];

  for (const route of routes) {
    assert.ok(route.length > 0, "expected a reachable land route");
  }
  assert.equal(
    isPolylineWalkable(HELIOS_RIFT, bridgeStates, [{ x: 0, z: -32 }, ...routes[0]]),
    true,
    "core route"
  );
  assert.equal(
    isPolylineWalkable(HELIOS_RIFT, bridgeStates, [{ x: 0, z: -32 }, ...routes[1]]),
    true,
    "north-east bridge route"
  );
});

test("void destinations and disconnected islets fail closed", () => {
  const { bridgeStates, pathGraph } = makeNavigation();
  assert.deepEqual(
    findWalkablePath(HELIOS_RIFT, pathGraph, bridgeStates, 0, -32, 15, 15),
    [],
    "an open-void command must not create a direct fallback"
  );
  assert.deepEqual(
    findWalkablePath(HELIOS_RIFT, pathGraph, bridgeStates, 0, -32, 22, -22),
    [],
    "an isolated expansion islet needs transport or an authored bridge"
  );

  pathGraph.setBridgeEnabled("bridge-ne", false);
  bridgeStates.set("bridge-ne", false);
  assert.deepEqual(
    findWalkablePath(HELIOS_RIFT, pathGraph, bridgeStates, 0, -32, 32, 0),
    [],
    "a disabled bridge must not produce a straight-line fallback"
  );
});

test("formation slots can clamp to nearby ground but not distant void", () => {
  const { bridgeStates } = makeNavigation();
  const corrected = nearestWalkablePoint(HELIOS_RIFT, bridgeStates, 46, 0, 2.4);
  assert.ok(corrected, "near-edge slot should resolve onto the east fragment");
  assert.equal(isPointWalkable(HELIOS_RIFT, bridgeStates, corrected.x, corrected.z), true);
  assert.equal(nearestWalkablePoint(HELIOS_RIFT, bridgeStates, 15, 15, 2.4), null);
});

test("solar flare bridge locks restore the physical bridge state", () => {
  const { bridgeStates, pathGraph } = makeNavigation();
  const [flare] = createHazards(HELIOS_RIFT.hazards);

  applyHazardBridgeAvailability(flare, true, pathGraph, bridgeStates);
  assert.equal(pathGraph.isBridgeEnabled("bridge-n-core"), false, "flare locks repaired bridge");
  assert.equal(pathGraph.isBridgeEnabled("bridge-e-core"), false, "broken bridge stays locked");

  applyHazardBridgeAvailability(flare, false, pathGraph, bridgeStates);
  assert.equal(pathGraph.isBridgeEnabled("bridge-n-core"), true, "repaired bridge restores");
  assert.equal(pathGraph.isBridgeEnabled("bridge-e-core"), false, "broken bridge stays broken");
});
