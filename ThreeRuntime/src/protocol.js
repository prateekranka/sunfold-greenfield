export const BRIDGE_PROTOCOL_VERSION = 1;
export const SAVE_SCHEMA_VERSION = 1;

export const COMMAND_NAMES = Object.freeze([
  "startGame",
  "pauseGame",
  "resumeGame",
  "saveGame",
  "returnToMenu"
]);

export const EVENT_NAMES = Object.freeze([
  "runtimeLoaded",
  "runtimeReady",
  "runtimePaused",
  "runtimeResumed",
  "saveReady",
  "returnedToMenu",
  "fatalError",
  "pauseRequested",
  "resumeRequested",
  "saveRequested",
  "returnToMenuRequested"
]);

const commandPayloadKeys = Object.freeze({
  startGame: new Set(["faction", "seed"]),
  pauseGame: new Set(),
  resumeGame: new Set(),
  saveGame: new Set(),
  returnToMenu: new Set()
});

const eventPayloadKeys = Object.freeze({
  runtimeLoaded: new Set(["offline", "renderer"]),
  runtimeReady: new Set(["offline", "renderer", "faction"]),
  runtimePaused: new Set(),
  runtimeResumed: new Set(),
  saveReady: new Set(["snapshotID"]),
  returnedToMenu: new Set(),
  fatalError: new Set(["code", "message"]),
  pauseRequested: new Set(),
  resumeRequested: new Set(),
  saveRequested: new Set(),
  returnToMenuRequested: new Set()
});

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function owns(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

function invalid(reason) {
  return { valid: false, reason };
}

function versionError(label, value, expected) {
  if (value === undefined) return `${label} is missing`;
  if (!Number.isInteger(value)) return `${label} must be an integer`;
  return value < expected ? `${label} is stale` : `${label} is from the future`;
}

export function validateEnvelope(envelope) {
  if (!isRecord(envelope)) return invalid("bridge envelope must be an object");

  if (!owns(envelope, "protocolVersion") || envelope.protocolVersion !== BRIDGE_PROTOCOL_VERSION) {
    return invalid(versionError("bridge protocol version", envelope.protocolVersion, BRIDGE_PROTOCOL_VERSION));
  }
  if (envelope.type !== "command" && envelope.type !== "event") {
    return invalid("bridge message type is invalid");
  }

  const names = envelope.type === "command" ? COMMAND_NAMES : EVENT_NAMES;
  const payloadKeys = envelope.type === "command" ? commandPayloadKeys : eventPayloadKeys;
  if (typeof envelope.name !== "string" || !names.includes(envelope.name)) {
    return invalid("bridge message name is invalid");
  }
  if (!owns(envelope, "payload") || !isRecord(envelope.payload)) {
    return invalid("bridge payload is missing or invalid");
  }

  const allowedKeys = payloadKeys[envelope.name];
  for (const [key, value] of Object.entries(envelope.payload)) {
    if (!allowedKeys.has(key)) return invalid(`bridge payload key is not allowed: ${key}`);
    if (typeof value !== "string") return invalid(`bridge payload value is not a string: ${key}`);
  }

  if (envelope.name === "saveReady") {
    if (!owns(envelope, "saveSchemaVersion") || envelope.saveSchemaVersion !== SAVE_SCHEMA_VERSION) {
      return invalid(versionError("save schema version", envelope.saveSchemaVersion, SAVE_SCHEMA_VERSION));
    }
  } else if (owns(envelope, "saveSchemaVersion") && envelope.saveSchemaVersion !== null) {
    return invalid("save schema version is only valid on saveReady snapshots");
  }

  return { valid: true, reason: null };
}

export function createEnvelope(type, name, payload = {}, options = {}) {
  const envelope = {
    protocolVersion: BRIDGE_PROTOCOL_VERSION,
    type,
    name,
    payload
  };
  if (name === "saveReady") {
    envelope.saveSchemaVersion = options.saveSchemaVersion ?? SAVE_SCHEMA_VERSION;
  }
  const result = validateEnvelope(envelope);
  if (!result.valid) throw new TypeError(result.reason);
  return envelope;
}

export function assertValidEnvelope(envelope) {
  const result = validateEnvelope(envelope);
  if (!result.valid) throw new TypeError(result.reason);
  return envelope;
}
