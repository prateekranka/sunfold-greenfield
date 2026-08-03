# Sunfold Three.js / WKWebView architecture

Status: active experiment on `experiment/threejs-wkwebview`.

## Responsibility boundary

| Responsibility | SwiftUI and native iOS | Bundled Three.js runtime |
| --- | --- | --- |
| Onboarding, home, setup and settings | Owns | Not involved |
| Save slots, purchases, Game Center and system overlays | Owns | Requests and terminal events only |
| Map, camera, simulation and deterministic clock | Not involved | Owns |
| Units, transforms, animation, selection and gameplay HUD | Not involved | Owns |
| Rendering and visual effects | WKWebView container only | Owns through `WebGLRenderer` |

The existing RealityKit implementation remains in `Sources/Rendering` and is not
edited by this experiment. Launch it only with `-sunfoldRealityKitFallback`.

## Bridge protocol v1

Every message is a JSON object with this shape:

```json
{
  "protocolVersion": 1,
  "type": "command | event",
  "name": "startGame",
  "payload": { "faction": "sunwoven" }
}
```

Save snapshots add `saveSchemaVersion: 1`. This save version is independent from
the bridge protocol version. Both versions are validated exactly. Missing, stale,
and future versions fail closed before a message reaches gameplay code.

Swift sends `startGame`, `pauseGame`, `resumeGame`, `saveGame` and
`returnToMenu`. JavaScript sends `runtimeLoaded`, `runtimeReady`, `runtimePaused`,
`runtimeResumed`, `saveReady`, `battleFinished`, `returnedToMenu` and
`fatalError`. `battleFinished` carries only the winning faction and terminal
reason.

The bridge carries lifecycle, setup, save and terminal events only. It never sends
per-frame unit positions, camera state, selection state, animation state, HUD
values or telemetry samples. The runtime reports benchmark telemetry as one final
high-level result in a later milestone. Gameplay controls and HUD controls remain
inside the JavaScript runtime; SwiftUI only hosts the web view and native shell.

Unknown versions, directions or command names produce `fatalError`. Commands sent
before `runtimeLoaded`/`runtimeReady` are queued in Swift and flushed once, in
order, after the runtime handshake.

## Offline asset contract

The source files under `ThreeRuntime/src/` and the local `three` dependency are
bundled by `npm run build --prefix ThreeRuntime` into
`Resources/ThreeRuntime/index.html` and `sunfold-runtime.js`. The generated output
must not be edited by hand. The web view loads the HTML through
`loadFileURL(_:allowingReadAccessTo:)`, with read access limited to the local app
bundle. The CSP blocks network connections, and Swift rejects navigation or
pop-up requests outside that bundle. No CDN, remote webpage or network request is
required.

## Build and verification

```sh
npm ci --prefix ThreeRuntime
npm run build --prefix ThreeRuntime
npm test --prefix ThreeRuntime
xcodegen generate
./scripts/agent-build.sh threejs-wkwebview
```

The fallback remains available for comparison but is outside this experiment's
active runtime path.

Durable bootstrap evidence is stored outside the repository under
`/Users/prateekranka/.codex/evidence/sunfold-threejs-21/` and
`/Users/prateekranka/.codex/evidence/sunfold-interactive-ios-route/`. Debug builds
print one `[ThreeJSBridge]` line per command or event. Each line contains only the
direction, message name, protocol version and payload-key names.
