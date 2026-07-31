# The App Store launch gate

Everything that must be true before Sunfold Greenfield can be submitted. Each row is its
own verifiable gate: a state, a way to check it, and an owner.

**Owner column:**
**A** = an agent can do it and verify it.
**A+D** = an agent can do it but needs a **physical device** to verify.
**H** = **human only — a pause boundary.** An agent must stop and ask. These involve money,
credentials, legal attestations, or irreversible published actions.

Status recorded here is as of **2026-07-31**, verified by reading the tree. No simulator was
available, so nothing below is a runtime observation unless it cites a committed capture.

---

## 0 · Blocking today

Three of these stop an upload outright, before App Review ever sees the build.

| # | Gate | Status |
|---|---|---|
| 1.1 | App icon exists | ❌ **`AppIcon.appiconset` contains no image at all** |
| 3.1 | Version reconciled | ❌ Info.plist says 0.1.0/1; VERSION.md says 0.3.0/42 |
| 5.1 | Privacy manifest present | ❌ No `PrivacyInfo.xcprivacy` anywhere |
| 4.1 | `UIRequiresFullScreen` | ⚠️ Deprecated on iOS 26, warns on every build |
| 6.1 | Signing configured | ❌ `CODE_SIGNING_REQUIRED: NO`, `DEVELOPMENT_TEAM: ""` |

---

## 1 · App icon and visual identity

| # | Gate | How to check | Owner |
|---|---|---|---|
| 1.1 | A 1024×1024 PNG marketing icon exists in `Resources/Assets.xcassets/AppIcon.appiconset/`, no alpha channel, no transparency, no rounded corners pre-applied | `ls` the appiconset; `sips -g hasAlpha icon.png` must report `no`. **Today the folder holds only a `Contents.json` declaring one universal slot with no `filename` key** — the build produces no icon and App Store Connect rejects the upload | A |
| 1.2 | `Contents.json` references the file and Xcode emits no missing-icon warning | Build; grep the log for `warning:.*icon` | A |
| 1.3 | The icon reads at 60×60 on a home screen and is not programmer art | Render at 60 px and look; blind-critic it against three shipped strategy-game icons | A |
| 1.4 | `ASSETCATALOG_COMPILER_APPICON_NAME` resolves | Already `AppIcon` in `project.yml` ✅ | A |
| 1.5 | `AccentColor` and `VoidBackground` colorsets have real values for both appearances | Read the two `Contents.json` files | A |

## 2 · Launch screen and first impression

| # | Gate | How to check | Owner |
|---|---|---|---|
| 2.1 | `UILaunchScreen` present | ✅ Present, `UIColorName: VoidBackground` | A |
| 2.2 | Launch screen does not flash white before the dark scene | Record the first 2 s of a cold launch at 60 fps and step through | A |
| 2.3 | Launch appears in landscape without a portrait flash | Cold-launch with the device already in landscape and record | A |
| 2.4 | **Time to first playable frame is acceptable in Release** | `PerfHarness` `LaunchMetrics` (`-sunfoldPerf`). Debug takes ~12 s because procedural textures cost ~570 ms per recipe; Release is ~37 ms per recipe, so this should be ~1 s — **but it has never been measured**. iPadOS kills an app that does not draw promptly. **Gate: first interactive frame ≤ 3 s in Release** | A+D |

## 3 · Identity and versioning

| # | Gate | How to check | Owner |
|---|---|---|---|
| 3.1 | `CFBundleShortVersionString` and `CFBundleVersion` agree with `VERSION.md`, `CHANGELOG.md` and `PROJECT_STATE.md` | Read all four. **They do not: the plist says 0.1.0 / 1, the docs say 0.3.0 / build 42.** Pick one source of truth — `project.yml` — and make the docs read from it | A |
| 3.2 | `CFBundleVersion` strictly increases per upload | App Store Connect rejects a duplicate; keep a monotonic build counter | A |
| 3.3 | Display name fits under an iPad icon without truncation | ✅ `CFBundleDisplayName: Sunfold` | A |
| 3.4 | Bundle id matches the App Store Connect record exactly | `com.sunfold.greenfield`. Requires the record to exist | **H** |
| 3.5 | `CFBundleName` / `PRODUCT_NAME` stay `SunfoldGreenfield` so the test target's `TEST_HOST` resolves | ✅ Already commented in `project.yml` | A |
| 3.6 | The name "Sunfold" is available on the App Store and does not collide with a trademark | Search the App Store and the trademark register | **H** |

## 4 · Info.plist, orientation, device family, multitasking

| # | Gate | How to check | Owner |
|---|---|---|---|
| 4.1 | **`UIRequiresFullScreen` migrated.** It is deprecated in iOS 26 and *will be ignored*: `build-agents/cp08-09.log:308` — *"has been deprecated starting in iOS 26.0 and will be ignored in a future release."* | Read Apple's current `UIRequiresFullScreen` documentation for the supported replacement before changing anything. **The gate is behavioural, not a key: the game must not break when the system ignores the key and gives it a resizable window.** Test at several window sizes and in Stage Manager | A+D |
| 4.2 | Landscape-only is enforced and correct | ✅ `UISupportedInterfaceOrientations~ipad` = LandscapeLeft + LandscapeRight. Verify the app never presents content in portrait even transiently during rotation | A |
| 4.3 | `TARGETED_DEVICE_FAMILY = 2` (iPad only) matches the App Store Connect availability | ✅ Set in `project.yml`. Must match the store listing | A / **H** |
| 4.4 | **Stage Manager and external display behave.** iPadOS 26 can hand the app an arbitrary window size, an external display, and a visible menu bar | Run under Stage Manager, resize to the smallest allowed window, attach an external display. The HUD must not clip and the orthographic camera must not distort. **`AGENTS.md` records that a `Spacer` in a width-less SwiftUI column makes the whole column greedy — that class of bug shows up here first** | A+D |
| 4.5 | Safe areas and the home indicator are respected at every size | Capture at several window sizes; no control under the indicator | A+D |
| 4.6 | `UIStatusBarHidden` and `UIUserInterfaceStyle: Dark` are intentional | ✅ Both set and correct for this game | A |
| 4.7 | `UIApplicationSupportsMultipleScenes: false` is intentional | ✅ Correct for a single-session RTS | A |
| 4.8 | **`ITSAppUsesNonExemptEncryption` declared** | Not present today, so every upload prompts for export compliance. The app has no networking and no custom crypto — verified: `rg` for `URLSession`, `Network.`, `CFNetwork` across `Sources/` returns nothing — so `false` is the correct value. Adding the key removes the prompt. The **legal attestation itself** is the human's | A proposes / **H** attests |
| 4.9 | No unused permission strings | ✅ No `NS*UsageDescription` keys present, and no camera/mic/location/photos APIs in `Sources/`. A usage string for a permission never requested is a review flag | A |
| 4.10 | Deployment target confirmed | `IPHONEOS_DEPLOYMENT_TARGET: 26.0`. Correct per the project's stated constraint, but it restricts the audience to iPadOS 26+. Confirm this is the intended market | **H** |

## 5 · Privacy manifest and required-reason APIs

| # | Gate | How to check | Owner |
|---|---|---|---|
| 5.1 | **`PrivacyInfo.xcprivacy` exists** and is in the app bundle's resources | No such file exists anywhere in the tree today. It must be added under `Resources/` (which `project.yml` already includes as a resource phase) and confirmed present inside the built `.app` | A |
| 5.2 | `NSPrivacyTracking` = `false`, `NSPrivacyTrackingDomains` empty | True today — no `AppTrackingTransparency`, no analytics, no network | A |
| 5.3 | `NSPrivacyCollectedDataTypes` empty | The app collects nothing. Verified: no networking, no accounts, no analytics | A |
| 5.4 | **Required-reason APIs declared.** Two are in use today: `ProcessInfo.processInfo.systemUptime` at `WorldController.swift:217,249` (double-tap detection) → **system boot time** category; and file access in `Sources/Diagnostics/PerfHarness.swift:198` writing perf reports to the Documents directory → **file timestamp / disk space** category if it reads attributes | Grep for the full Apple required-reason list on every audit, not once. Declare each with its reason code. **If `PerfHarness` is compiled out of Release, its API use does not need declaring — confirm which** | A |
| 5.5 | No third-party SDK, so no third-party privacy manifests or signatures needed | ✅ No `Package.swift`, no SPM dependencies in `project.yml` | A |
| 5.6 | App Store Connect privacy answers match the manifest | The two are checked against each other at review | **H** |

## 6 · Signing, capabilities, account

| # | Gate | How to check | Owner |
|---|---|---|---|
| 6.1 | A real `DEVELOPMENT_TEAM`, and code signing enabled for Release | `project.yml` currently sets `DEVELOPMENT_TEAM: ""`, `CODE_SIGNING_REQUIRED: NO`, `CODE_SIGN_IDENTITY: ""` — correct for simulator agent builds, fatal for distribution. Needs a separate Release/distribution configuration | A configures / **H** supplies the team |
| 6.2 | Apple Developer Program membership active | Costs money | **H** |
| 6.3 | Distribution certificate and provisioning profile | Credentials | **H** |
| 6.4 | App Store Connect app record created with the matching bundle id | Ownership | **H** |
| 6.5 | No capabilities or entitlements enabled that the app does not use | Inspect the entitlements in the archived `.app` | A |

## 7 · The Release build itself

| # | Gate | How to check | Owner |
|---|---|---|---|
| 7.1 | **An archive-configuration build exists at all.** Every build in this project so far is Debug for the simulator | `xcodebuild archive` for a device destination; then validate the archive | A+D |
| 7.2 | Debug overlays off by default | ✅ Verified: `RootView.swift:17` gates the overlay behind `-sunfoldDebug`. Confirm the same for `-sunfoldPerf` / `-sunfoldPerfOverlay`, which are newer | A |
| 7.3 | Debug launch arguments cannot be reached by a player | Launch arguments are not settable on a shipped App Store app, so this is satisfied by construction — but confirm no in-app debug affordance exists | A |
| 7.4 | No `print` / `DebugLog` output in Release | `rg` for `print(` in `Sources/`; check `Sources/Debug/DebugLog.swift` compiles out or no-ops under `#if !DEBUG` | A |
| 7.5 | Zero warnings in the Release build, or every remaining one explained | Three are known today: `UIRequiresFullScreen` deprecation (gate 4.1) and two `appintentsmetadataprocessor` notes | A |
| 7.6 | Swift 6 complete strict concurrency clean | ✅ `SWIFT_STRICT_CONCURRENCY: complete` already, and building green | A |
| 7.7 | Bitcode / symbols: dSYM produced and uploaded | Check the archive's dSYM folder | A |
| 7.8 | App size is sane | `ls -la` the `.ipa`. Everything is procedural, so this should be small — confirm no accidental asset bloat | A |
| 7.9 | Test targets and `Tools/mappreview` are not in the shipped app | Inspect the archived bundle's contents | A |

## 8 · Content — nothing placeholder ships

| # | Gate | How to check | Owner |
|---|---|---|---|
| 8.1 | Zero placeholder-magenta pixels | Already a solved and measured problem: CP-02 took it 64,490 → 0. Re-measure on the shipping capture, since new materials have landed since | A |
| 8.2 | **No programmer art in a shipping frame.** Blind-critic every object class against the concepts | The Farm currently renders as a flat brown rectangle with three bars (`Docs/QA/G2/cp-g2a/15-farm-complete-fullres.png`). That does not ship. Gate: the blind critic never names a specific object as "obviously placeholder" | A |
| 8.3 | No lorem-ipsum, TODO or debug copy in any user-visible string | `rg -i "todo|fixme|placeholder|lorem|xxx"` across `Sources/HUD` and `Sources/App` | A |
| 8.4 | No dead chrome: every enabled control does something | Tap every control. Known open: control-group slots are chrome only; command tiles disabled | A |
| 8.5 | No stale alerts | "Light transport docked at home rim" is visible in five committed captures across four days. An alert with no lifecycle is a defect | A |
| 8.6 | Nothing resembling another game's trade dress | The bible already forbids AoE UI chrome and copied compositions; re-read the continuity checklist against the shipping frame | A |
| 8.7 | All third-party asset licences cleared | Everything is procedurally generated in-code today, which is the cleanest possible position. Any purchased asset is a **pause boundary** | A / **H** |

## 9 · Accessibility

`Sources/Accessibility/` exists and contains **zero files**. Roadmap G7 owns this.

| # | Gate | How to check | Owner |
|---|---|---|---|
| 9.1 | VoiceOver reaches every critical HUD action: resource rail, selection panel, command grid, minimap, pause and speed | Turn VoiceOver on and complete a gather → build cycle using it | A+D |
| 9.2 | Every interactive control has a label and, where it is not obvious, a hint | Accessibility Inspector audit; zero unlabelled elements | A |
| 9.3 | **Reduced Motion honoured.** Already partly built — `LocomotionTuning.reducedMotionScale = 0.40` simplifies gait without freezing it, which is the right design | Enable Reduced Motion and confirm gait, camera easing and any new animation all respond | A+D |
| 9.4 | Dynamic Type or a UI text-scale option; nothing clipped at the largest supported size | Raise text size and capture | A+D |
| 9.5 | Contrast: every HUD text run ≥ 4.5:1 against its local background; readable with Increase Contrast on | Sample the capture (bar B4b) | A |
| 9.6 | No information carried by colour alone | `ResourceGlyph` already gives each resource a distinct silhouette ✅. Check faction identity and legal/illegal placement the same way | A |
| 9.7 | Touch targets ≥ 44×44 pt | Measure the HUD controls in the capture | A |
| 9.8 | No flashing content that could trigger photosensitivity | Review bloom pulses, completion flashes and alert animations | A |

## 10 · Stability, memory, thermals

| # | Gate | How to check | Owner |
|---|---|---|---|
| 10.1 | Crash-free launch, 20 consecutive cold launches | Script it; zero crashes, zero hangs | A+D |
| 10.2 | No crash across a full 10-minute match, both win paths, restart, and Play Again | Play it | A+D |
| 10.3 | Memory ceiling: peak resident memory stays well inside the device budget and does not grow without bound over 10 minutes | `PerfHarness.residentMemoryMB` already samples this. Gate: no monotonic growth across a 10-minute session | A+D |
| 10.4 | No leaked entities: unit / building / deposit entity counts return to baseline after a restart | `EntityPresenter.removeStale` exists; verify the dictionaries actually empty | A |
| 10.5 | **Thermals:** `ProcessInfo.thermalState` never reaches `.serious` in 10 minutes; the final minute averages ≥ 58 fps | Bar B2c | A+D |
| 10.6 | Battery drain is not pathological over 10 minutes | Xcode Energy gauge / Metrics | A+D |
| 10.7 | Graceful backgrounding and resume mid-match | Background, wait 60 s, return. The 20 Hz accumulator must not fast-forward or desync | A+D |
| 10.8 | Determinism holds in Release, not only Debug | Bar B6, run against a Release build | A+D |

## 11 · App Store metadata and screenshots

| # | Gate | How to check | Owner |
|---|---|---|---|
| 11.1 | **iPad screenshots at the sizes App Store Connect currently requires.** Our native capture is 2732×2048 (iPad Air 13 / 12.9" class). The 13-inch iPad requirement has moved to 2064×2752 portrait / **2752×2064 landscape** — close to ours but **not identical**, so a naïve upload of a raw capture may be rejected | Read the accepted sizes in App Store Connect at submission time and resize deliberately rather than assuming the capture fits. Landscape-only app → landscape screenshots | A produces / **H** uploads |
| 11.2 | Screenshots show real gameplay, no device frames, no added marketing text that misrepresents | Compare each against the running build | A |
| 11.3 | Screenshots pass the visual bar. **Do not ship a screenshot the blind critic would fail** | Run bar B1a on every candidate screenshot | A |
| 11.4 | App preview video, if used, meets the format spec | Optional | A / **H** |
| 11.5 | Name, subtitle, keywords, description, promotional text | A can draft; publishing is the human's | A drafts / **H** |
| 11.6 | Support URL and marketing URL reachable | Requires a domain — possibly money | **H** |
| 11.7 | Privacy policy URL — **required** even when nothing is collected | Hosting | **H** |
| 11.8 | Copyright line and primary/secondary category (Games → Strategy) | | **H** |
| 11.9 | Localisation: English only, declared as such | Only `CFBundleDevelopmentRegion` today; no `.strings` catalogue. Fine for launch if declared | A |

## 12 · Age rating, legal, compliance

| # | Gate | How to check | Owner |
|---|---|---|---|
| 12.1 | Age rating questionnaire answered honestly. Two civilizations fighting a war → expect a *fantasy violence* declaration; there is no blood, no gore, no purchases, no user-generated content, no gambling, no web access | Answer in App Store Connect | **H** |
| 12.2 | No account, no login, so no demo-account requirement for review | ✅ True by construction | A |
| 12.3 | No in-app purchases, no ads, no subscriptions — `ROADMAP.md` explicitly puts monetisation out of scope | ✅ Verify nothing crept in | A |
| 12.4 | Export compliance answered (gate 4.8) | | **H** |
| 12.5 | Content rights: everything is procedurally generated in-code; the concept PNGs are internal references and **must not ship inside the app bundle** | Confirm `Docs/` is not in any resource build phase — `project.yml` includes only `Sources` and `Resources` ✅ | A |
| 12.6 | Guideline 4.2 "minimum functionality" — the game must be a complete experience, not a demo. A build with no win condition would fail this | Bar B5b: three unassisted 8–10 minute playthroughs that end | A |

## 13 · TestFlight validation

| # | Gate | How to check | Owner |
|---|---|---|---|
| 13.1 | Archive validates and uploads without error | `xcodebuild -exportArchive` then upload | A+D / **H** for credentials |
| 13.2 | Build finishes processing and is installable | Watch App Store Connect | **H** |
| 13.3 | Installs and launches from TestFlight on a real iPad, landscape, first try | Install and launch | A+D |
| 13.4 | The full launch-gate play test passes **on the TestFlight build**, not on a Debug simulator build | Run gates 10.1–10.8 against it | A+D |
| 13.5 | External testers, if any, and beta review | | **H** |
| 13.6 | No TestFlight-only code paths remain in the App Store build | Diff the two configurations | A |

## 14 · The performance floor — which iPads this app actually admits

**This is a launch gate, and today it is unaddressed.** All performance thinking on the
project so far assumes an iPad Air 13-inch (M2). That is the development device, not the
floor.

`IPHONEOS_DEPLOYMENT_TARGET: "26.0"` with `TARGETED_DEVICE_FAMILY: "2"` means **every iPad
that can run iPadOS 26 can install this app.** iPadOS 26 requires an A12 or later, so the
admitted set runs from an M5 iPad Pro down to:

| Weakest admitted | Chip | RAM | Year | Display |
|---|---|---|---|---|
| iPad Air (3rd generation) | A12 Bionic | 3 GB | 2019 | 10.5″, 2224×1668 |
| iPad (8th generation) | A12 Bionic | 3 GB | 2020 | 10.2″, 2160×1620 |
| iPad mini (5th generation) | A12 Bionic | 3 GB | 2019 | 7.9″, 2048×1536 |

*(iPadOS 26 dropped the 7th-generation iPad and its A10. A12 / 3 GB is the true floor.)*

That is several generations and a large multiple of GPU throughput below an M2 with 8 GB.
This app runs **4× MSAA** and a **full-resolution post composite**, which are precisely the
costs that do not scale down gracefully. A comfortable 60 fps on the M2 Air says very little
about an A12.

| # | Gate | How to check | Owner |
|---|---|---|---|
| 14.1 | The floor is decided, deliberately and in writing: either the app holds 60 fps on an A12 / 3 GB iPad, **or** the admitted device set is deliberately narrowed | This is a product decision with a real cost either way. Note there is no clean Info.plist key that gates on chip generation — raising the deployment target does not help, since A12 devices run iPadOS 26. Narrowing realistically means a quality-tier system that detects the device and drops MSAA, shadow resolution and post-process quality | **H** decides, A implements |
| 14.2 | 60 fps validated on the weakest admitted device at both density rungs | Bars B2a and B2c, run on a physical A12-class iPad. **Do not attempt to test every model** — the weakest is the only one that matters | A+D, **H** provides the device |
| 14.3 | Memory fits 3 GB, not 8 GB. Procedural textures, the IBL and mesh caches were all sized without this constraint in view | Gate 10.3 re-run on the floor device; watch for jetsam | A+D |
| 14.4 | The HUD is usable on a 7.9″ iPad mini 5, not only a 13″ Air | The bottom strip is minimap · selection · command grid across a landscape iPad. At mini scale, check touch targets stay ≥ 44 pt (gate 9.7) and nothing overlaps | A+D |
| 14.5 | If a quality-tier system ships, each tier is visually re-judged | Bar B1a at the lowest tier. A tier that holds 60 fps by looking bad is a different failure, not a fix | A |
| 14.6 | Store listing sets honest expectations if low-end performance is compromised | Description and screenshots must not imply M-series fidelity on an A12 | **H** |

---

## Human-only summary — the pause boundaries in this document

An agent must **stop and ask** for every one of these. They are not delegated, not
approximated, and not worked around.

1. Apple Developer Program membership — **money** (6.2)
2. Distribution certificate and provisioning profile — **credentials** (6.3)
3. The App Store Connect app record and bundle-id reservation — **ownership** (3.4, 6.4)
4. `DEVELOPMENT_TEAM` value — **credentials** (6.1)
5. Export-compliance attestation — **a legal statement** (4.8, 12.4)
6. Age-rating questionnaire — **a legal statement** (12.1)
7. Privacy answers in App Store Connect — **a legal statement** (5.6)
8. Domain, hosting, support URL, privacy-policy URL — **possibly money** (11.6, 11.7)
9. Pricing, availability, territories (**H**)
10. Any purchased asset, font, sound library or service — **money** (8.7)
11. Confirming iPadOS 26.0 as the minimum, and the market that implies (4.10)
11b. **Deciding the performance floor** — hold 60 fps on an A12 / 3 GB iPad, or deliberately
     narrow what the app admits. Either choice costs something (14.1)
12. Confirming the name "Sunfold" is clear of trademark (3.6)
13. **Submitting to App Review, and releasing.** Irreversible and public.
14. Providing a physical iPad Air 13-class device for every **A+D** gate.

## What an agent can finish today, with no human and no device

In rough order of value: **1.1–1.5** (icon), **3.1–3.2** (version reconciliation),
**5.1–5.5** (privacy manifest), **7.2, 7.4, 7.5** (Release hygiene), **8.1, 8.3–8.6**
(placeholder and dead-chrome sweep), **9.2, 9.5–9.7** (static accessibility audit),
**12.3, 12.5** (compliance sweep). These are Piece **P15a** in `00-PLAN.md` and are
parallel-safe — they never touch the simulator, so they cost the loop nothing.
