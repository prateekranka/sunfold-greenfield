import assert from "node:assert/strict";
import test from "node:test";
import {
  BRIDGE_PROTOCOL_VERSION,
  SAVE_SCHEMA_VERSION,
  assertValidEnvelope,
  createEnvelope,
  validateEnvelope
} from "../src/protocol.js";

const validCommand = createEnvelope("command", "startGame", {
  faction: "sunwoven",
  seed: "20260726"
});

test("control envelopes carry the bridge protocol version", () => {
  assert.equal(validCommand.protocolVersion, BRIDGE_PROTOCOL_VERSION);
  assert.deepEqual(validateEnvelope(validCommand), { valid: true, reason: null });
  assert.doesNotThrow(() => assertValidEnvelope(validCommand));
});

test("missing, stale, and future bridge versions fail closed", () => {
  const missing = { ...validCommand };
  delete missing.protocolVersion;
  assert.match(validateEnvelope(missing).reason, /missing/);

  assert.match(
    validateEnvelope({ ...validCommand, protocolVersion: BRIDGE_PROTOCOL_VERSION - 1 }).reason,
    /stale/
  );
  assert.match(
    validateEnvelope({ ...validCommand, protocolVersion: BRIDGE_PROTOCOL_VERSION + 1 }).reason,
    /future/
  );
  assert.throws(() => assertValidEnvelope({ ...validCommand, protocolVersion: 99 }), /future/);
});

test("snapshots carry a distinct save schema version", () => {
  const snapshot = createEnvelope("event", "saveReady", { snapshotID: "minimal-scene-v1" });
  assert.equal(snapshot.protocolVersion, BRIDGE_PROTOCOL_VERSION);
  assert.equal(snapshot.saveSchemaVersion, SAVE_SCHEMA_VERSION);
  assert.deepEqual(validateEnvelope(snapshot), { valid: true, reason: null });

  const missing = { ...snapshot };
  delete missing.saveSchemaVersion;
  assert.match(validateEnvelope(missing).reason, /missing/);
  assert.match(
    validateEnvelope({ ...snapshot, saveSchemaVersion: SAVE_SCHEMA_VERSION - 1 }).reason,
    /stale/
  );
  assert.match(
    validateEnvelope({ ...snapshot, saveSchemaVersion: SAVE_SCHEMA_VERSION + 1 }).reason,
    /future/
  );
});

test("battle completion is a versioned terminal event", () => {
  const result = createEnvelope("event", "battleFinished", {
    winner: "sunwoven",
    reason: "victory"
  });
  assert.deepEqual(validateEnvelope(result), { valid: true, reason: null });
  assert.equal(result.saveSchemaVersion, undefined);
});

test("payloads stay high-level and reject unit or frame state", () => {
  for (const payload of [
    { units: "80" },
    { positions: "per-frame" },
    { camera: "x,y,z" },
    { selection: "unit-1" },
    { animation: "walk" },
    { hud: "resource-values" },
    { telemetry: "frame-sample" }
  ]) {
    const result = validateEnvelope({
      ...validCommand,
      payload
    });
    assert.equal(result.valid, false, result.reason);
  }
});

test("unknown control names and missing payloads are rejected", () => {
  assert.equal(
    validateEnvelope({ ...validCommand, name: "unitState" }).valid,
    false
  );
  const missingPayload = { ...validCommand };
  delete missingPayload.payload;
  assert.equal(validateEnvelope(missingPayload).valid, false);
});
