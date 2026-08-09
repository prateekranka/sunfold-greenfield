// Asset registry contract — logical unit-art ids (Fidelity Ladder).
//
// The registry maps sim units (faction.kind.tier) to representations:
// authored directionalSprite art when a sheet exists, procedural.* primitive
// stand-ins otherwise. Procedural entries are visible debug fallbacks and
// must never be mistaken for shipping art.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  createRegistry,
  resolveChain,
  resolveEntry,
  assetIdForUnit,
  REGISTRY_SCHEMA,
  AGE_TIERS
} from "../src/asset-registry.js";
import { UNIT_KINDS } from "../src/sim/kinds.js";

const here = dirname(fileURLToPath(import.meta.url));
const data = JSON.parse(
  readFileSync(resolve(here, "../assets/asset-registry.json"), "utf8")
);
const registry = createRegistry(data);

test("registry carries the locked schema", () => {
  assert.equal(registry.schema, REGISTRY_SCHEMA);
  assert.equal(data.schema, REGISTRY_SCHEMA);
});

test("the four canonical ids exist with the specified fields", () => {
  const ids = [
    "sunwoven.citizen.foundation",
    "sunwoven.citizen.voyager",
    "gravemark.stoneguard.foundation",
    "gravemark.bastionWalker.voyager"
  ];
  for (const id of ids) {
    const entry = registry.entries[id];
    assert.ok(entry, `missing entry ${id}`);
    assert.equal(entry.id, id, "entry id must match its key");
    assert.equal(typeof entry.representation, "string");
    assert.equal(typeof entry.scaleMeters, "number");
    assert.ok(entry.scaleMeters >= 1 && entry.scaleMeters <= 5, `${id} scaleMeters sane`);
    assert.ok(Array.isArray(entry.clips) && entry.clips.length >= 1, `${id} has clips`);
    assert.equal(typeof entry.factionMask, "boolean", `${id} factionMask boolean`);
    assert.equal(typeof entry.fallback, "string", `${id} has a fallback`);
  }
});

test("every sim unit kind × faction × tier resolves through the registry", () => {
  for (const faction of ["sunwoven", "gravemark"]) {
    for (const kind of UNIT_KINDS) {
      for (const tier of AGE_TIERS) {
        const id = `${faction}.${kind}.${tier}`;
        assert.ok(registry.entries[id], `missing roster id ${id}`);
      }
    }
  }
});

test("fallback chains terminate at a procedural entry and never cycle", () => {
  for (const id of Object.keys(registry.entries)) {
    const chain = resolveChain(registry, id);
    assert.ok(chain.length >= 1, `${id} resolves to at least itself`);
    const last = chain[chain.length - 1];
    assert.equal(last.representation, "procedural", `${id} chain must end procedural`);
    assert.equal(last.fallback, undefined, `${last.id} must be terminal (no fallback)`);
    const ids = chain.map((entry) => entry.id);
    assert.equal(new Set(ids).size, ids.length, `${id} chain must not revisit ids`);
  }
});

test("resolveEntry prefers authored art, falls through to procedural", () => {
  const citizen = resolveEntry(registry, "sunwoven.citizen.foundation");
  assert.equal(citizen.source, "authored");
  assert.equal(citizen.entry.id, "sunwoven.citizen.foundation");

  // Voyager citizen chains to the foundation sheet (same authored art).
  const voyager = resolveEntry(registry, "sunwoven.citizen.voyager");
  assert.equal(voyager.source, "authored");
  assert.equal(voyager.entry.id, "sunwoven.citizen.voyager");

  // No authored sheet anywhere in these chains → procedural stand-in.
  const stoneguard = resolveEntry(registry, "gravemark.stoneguard.foundation");
  assert.equal(stoneguard.source, "procedural");
  assert.equal(stoneguard.entry.id, "procedural.stoneguard");

  const walker = resolveEntry(registry, "gravemark.bastionWalker.voyager");
  assert.equal(walker.source, "procedural");
  assert.equal(walker.entry.id, "procedural.bastionWalker");

  const gravCitizen = resolveEntry(registry, "gravemark.citizen.foundation");
  assert.equal(gravCitizen.source, "procedural");
  assert.equal(gravCitizen.entry.id, "procedural.citizen");
});

test("Sunwoven Foundation Citizen is the authored experiment asset", () => {
  const entry = registry.entries["sunwoven.citizen.foundation"];
  assert.equal(entry.representation, "directionalSprite");
  assert.equal(entry.spriteSheet, "village-manbun-wanderer");
  assert.deepEqual(entry.clips, ["idle", "walk", "gather", "carry", "build"]);
  // Village Man-Bun 16-dir combined atlas is the sprite LOD (default via ?art=sprite /
  // default art mode); the skinned GLB remains available via ?art=gltf.
  assert.deepEqual(
    entry.lods.map((lod) => lod.kind),
    ["gltf", "sprite", "procedural"]
  );
  assert.equal(entry.lods[0].gltf, "units/citizen_villager.glb");
  assert.equal(entry.lods[1].spriteSheet, "village-manbun-wanderer");
});

test("assetIdForUnit maps sim units to logical ids", () => {
  assert.equal(
    assetIdForUnit({ faction: "sunwoven", kind: "citizen" }, { sunwoven: "foundation" }),
    "sunwoven.citizen.foundation"
  );
  assert.equal(
    assetIdForUnit({ faction: "gravemark", kind: "bastionWalker" }, { gravemark: "voyager" }),
    "gravemark.bastionWalker.voyager"
  );
  assert.equal(
    assetIdForUnit({ faction: "gravemark", kind: "stoneguard" }, { gravemark: "foundation" }),
    "gravemark.stoneguard.foundation"
  );
  // Unknown tier collapses to the oldest tier; unknown units default sensibly.
  assert.equal(
    assetIdForUnit({ faction: "sunwoven", kind: "citizen" }, { sunwoven: "iron" }),
    "sunwoven.citizen.foundation"
  );
  assert.equal(assetIdForUnit({}, {}), "sunwoven.citizen.foundation");
  assert.equal(assetIdForUnit(null, null), "sunwoven.citizen.foundation");
});

test("procedural entries are visible debug fallbacks, not shipping art", () => {
  const procedural = Object.entries(registry.entries).filter(([id]) =>
    id.startsWith("procedural.")
  );
  assert.ok(procedural.length >= 7, "one stand-in per sim kind, plus stoneguard");
  for (const [id, entry] of procedural) {
    assert.equal(entry.representation, "procedural", `${id} representation`);
    assert.equal(entry.fallback, undefined, `${id} is terminal`);
    assert.equal(entry.factionMask, true, `${id} supports faction masking`);
    assert.ok(entry.scaleMeters >= 1 && entry.scaleMeters <= 5, `${id} scaleMeters`);
  }
  // Every procedural id is referenced by at least one fallback chain.
  for (const [id] of procedural) {
    const referenced = Object.values(registry.entries).some(
      (entry) => entry.fallback === id
    );
    assert.ok(referenced, `${id} must be reachable from an authored entry`);
  }
});

test("unknown ids produce an empty chain and null resolution", () => {
  assert.deepEqual(resolveChain(registry, "no.such.id"), []);
  assert.equal(resolveEntry(registry, "no.such.id"), null);
});

test("createRegistry rejects malformed payloads", () => {
  assert.throws(() => createRegistry({ entries: {} }), /schema/);
  assert.throws(() => createRegistry({ schema: REGISTRY_SCHEMA }), /entries/);
  assert.throws(
    () =>
      createRegistry({
        schema: REGISTRY_SCHEMA,
        entries: { "x.y.z": { representation: "procedural" } }
      }),
    /matching id/
  );
});
