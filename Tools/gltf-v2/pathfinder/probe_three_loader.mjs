// probe_three_loader.mjs — does three r178 linearize baseColorFactor?
// Loads pathfinder_scout.glb with the repo's own three + GLTFLoader (node,
// no WebGL needed: the GLB has no textures) and prints the resulting
// material.color values as the runtime would see them.
import { readFileSync } from "node:fs";
import { GLTFLoader } from "/Users/prateekranka/Claude/Projects/aoe-space-edition/SunfoldGreenfield-threejs-wkwebview/ThreeRuntime/node_modules/three/examples/jsm/loaders/GLTFLoader.js";

const glbPath = process.argv[2];
const buffer = readFileSync(glbPath);

const loader = new GLTFLoader();
loader.parse(buffer.buffer.slice(buffer.byteOffset, buffer.byteOffset + buffer.byteLength),
  "", (gltf) => {
    const seen = new Map();
    gltf.scene.traverse((o) => {
      if (o.isMesh && o.material) {
        const mats = Array.isArray(o.material) ? o.material : [o.material];
        for (const m of mats) {
          if (!seen.has(m.name)) seen.set(m.name, m);
        }
      }
    });
    for (const [name, m] of seen) {
      const c = m.color;
      console.log(
        `MAT ${name} color=(${c.r.toFixed(4)}, ${c.g.toFixed(4)}, ${c.b.toFixed(4)})` +
        ` emissive=(${m.emissive.r.toFixed(3)}, ${m.emissive.g.toFixed(3)}, ${m.emissive.b.toFixed(3)})` +
        ` emissiveIntensity=${m.emissiveIntensity.toFixed(3)}`
      );
    }
    const anims = gltf.animations.map((a) => `${a.name}:${Math.round(a.duration * 100) / 100}s`);
    console.log("ANIMS", anims.join(", "));
  }, (err) => {
    console.error("LOAD ERROR", err);
    process.exit(1);
  });
