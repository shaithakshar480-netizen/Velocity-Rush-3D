# Phase 4 — collection, controls and world presentation

**PARTIALLY COMPLETE — integrated source and offline validation; Godot runtime NOT VERIFIED.**

This extends VelocityRush3D-Phase3. The same GDScript/Compatibility renderer project remains, with no engine migration or Phase 5 services. The user's local editor is reported as Godot 4.7.2 stable. No Godot executable exists in this authoring environment, so no import/compilation, shader rendering, playable purchase test, audio listening, Android build or device-performance claim is made.

## Garage and collection

Home now exposes RACE, GARAGE and Settings plus the selected vehicle and existing wallet. Garage uses a dedicated camera, dark stage, platform, warm key/cool rim lights, slow orbit and drag/swipe orbit interaction. Left panel shows the actual configured performance and paint choices; right panel shows five upgrade categories and exact next prices. The center stays available for the 3D car. Button state changes between SELECTED, SELECT and BUY. Insufficient funds and maximum levels disable the respective actions. Stat changes animate; purchase/select/upgrade have original short sounds.

Six preloaded original low-poly models have distinct dimensions, rooflines, cabin lengths, wheelbases and aero details. All share explicit material roles, proper wheels/arches, fascia, glazing, mirrors, lamps, bumpers, side intakes and model-local exhausts. Super/hypercars add raised aero. Geometry checks find 3,062–3,092 triangles per player car including four wheels. These are original development models, not a claim of final production visual quality. Docs/player-geometry-preview.png is an **offline projection**, not a Godot screenshot.

| Car | Class | Price | Base cap | Acceleration coefficient | Steering response | Braking | Grip | Turbo cap |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Vortex S | Sport Coupe | Free | 210 KM/H | 11.5 | 6.5 | 24 | 11 | 270 KM/H |
| Falcon S1 | Sport Hatch / Coupe | 15,000 | 225 KM/H | 13.0 | 7.4 | 25 | 12 | 280 KM/H |
| Apex RS | Performance Sports Car | 40,000 | 240 KM/H | 13.8 | 7.0 | 27 | 12 | 300 KM/H |
| Inferno R | Supercar | 90,000 | 260 KM/H | 15.3 | 7.2 | 28 | 12.5 | 325 KM/H |
| Phantom X | Exotic Supercar | 180,000 | 280 KM/H | 15.8 | 7.0 | 30 | 13 | 350 KM/H |
| Titan V12 | Hypercar | 350,000 | 305 KM/H | 16.5 | 6.8 | 32 | 13.5 | 380 KM/H |

Acceleration/braking coefficients use m/s²; actual acceleration also depends on weight, speed taper and Turbo. Handling stat reports steering-response rate, not an invented score. Paint choices are Racing Red, Electric Blue, Pearl White, Midnight Black, Titanium Silver and Neon Cyan; free for owned cars and persisted per vehicle. No paint purchases or Turbo upgrade category exists.

## Atomic purchase and save behavior

Schema 3 stores settings, wallet and collection together in the existing pending-file/backup/rename envelope. Collection contains owned IDs, selected ID, per-car paint indices and per-car upgrade levels. Schemas 1 and 2 remain readable. Existing settings/wallet migrate without a reset; Vortex S is always granted; missing collection values receive defaults. Unknown IDs, nonnumeric values, invalid selected ownership, paint ranges and upgrade ranges are sanitized. Locked cars cannot inherit upgrades from malformed collection data.

Purchase checks ID, existing ownership and affordability, then commits ownership and debit together. Upgrade checks ownership, category, current expected level, level <10 and affordability, then commits exactly one level and debit together. A rejected/failed commit rolls back memory and discards an orphan pending transaction. A busy guard and compare-and-swap expected level protect duplicate calls; Garage also debounces purchase taps for 500 ms. No asynchronous server simulation is used. Local saves are not anti-tamper server accounting.

Selected car/paint are applied on Home and Race, including calibrated collision dimensions, effective performance and the corresponding Turbo resource. Effective specs are new resources; the base catalog and preloaded Turbo resource are not destructively modified. Existing issued/settled run checks and reward calculation remain unchanged. Coin collection still contributes to the run reward, which settles through the existing results flow.

## Upgrade formulas

Each level E/H/B/T/G is clamped to 0–10 for Engine, Handling, Brakes, Tires and Transmission:

- Acceleration = base × (1 + 0.035E + 0.020G).
- Normal speed = base × (1 + 0.008E + 0.006G).
- Steering response = base × (1 + 0.040H).
- Grip = base × (1 + 0.015H + 0.030T).
- Braking = base × (1 + 0.050B).
- Turbo cap = base Turbo cap + the increase in normal speed, retaining the car's stock Turbo advantage.

Next-level costs: **500, 800, 1,200, 1,800, 2,600, 3,700, 5,000, 6,500, 8,000, 10,000** coins. One category totals 40,100. Costs/modifiers are in Data/VehicleCatalog.json. No economy reward increase was added to offset these prices. Titan's all-upgrade normal/Turbo caps are 347.7/422.7 KM/H; high-speed handling and traffic reaction need real playtesting at these extremes.

Falcon's charge multiplier is 1.18, Vortex/Apex/Inferno 1.0, Phantom 0.95, Titan 0.90. Turbo acceleration multipliers are Vortex 2.7, Falcon 2.5, Apex 2.8, Inferno 3.0, Phantom 2.9 and Titan 2.8. The existing state machine, meter, drain, events, pause/reset and finish cleanup are preserved. Four reusable nozzle slots support one/dual/quad emitter configurations; the current six use dual exhausts.

## Mobile controls

Steering Wheel is the default for new and migrated saves. A 216-unit wheel rotates proportionally to horizontal drag, clamps at ±110°, smooths input and returns at 240°/sec after release. Its finger retains ownership outside the hit box. Other fingers independently control throttle, brake and Turbo. Keyboard input remains available in every mode.

Buttons retains the original independent Left/Right touch path and pressed-state styling. Tilt uses Android gravity (accelerometer fallback), current-pose neutral calibration, a 6% dead zone, ±28° range, exponential filtering and clamping. Unavailable/unsuitable sensor readings fall back to the wheel without changing the stored preference. Calibration is session-local because the neutral holding position changes. Validate steering direction and comfort on an actual phone.

Settings persists mode, sensitivity (0.5–1.5) and steering assist. Assist preserves the original ~9 m/s² lateral comfort limit; OFF permits up to 11 while retaining the flat-road stability model. Mode-specific HUD is automatic, including a tilt indicator. No pedal/Turbo positions are removed. Layout uses the existing logical viewport expansion and safe-area margins; physical aspect-ratio testing remains pending.

## Traffic material fix

Old GLBs had white base materials and depended on COLOR_0 vertex data for body, windows and trim. That dependency was an identifiable source risk; the user's exact runtime import state was not reproducible here. New GLBs use seven named PBR roles (Paint, Glass, Trim, Rubber, Alloy, Headlight, Taillight), explicit factors, and no COLOR_0 dependency. Runtime resolves the active imported material role and assigns explicit material definitions, with vertex-color albedo disabled.

Paint is chosen deterministically from white, black, silver, gray, blue, red, green and bronze using spawn position/lane/type. Only paint changes; windows, tires, rims and lights remain distinct. Existing five fictional classes and pool movement remain. Simple contact-shadow geometry grounds traffic and player cars, including Low quality. Traffic collision/pass extents now use the selected player's dimensions. Spawn ceiling grows to 800 m so upgraded Turbo speeds do not prevent safe traffic spawning.

## Environment redesign

The stable deck and barrier colliders are unchanged. Decorative geometry has no collider and no Y authority over the player.

- Road: restrained asphalt grain/wheel-path wear shader, aligned lane/edge paint and flat shoulders.
- Road construction: barrier caps, panel joints, reflectors, guardrails, drainage grates, improved lamp heads and double-beam sign gantries with fictional destinations.
- Midground: irregular rock formations, berms, sparse vegetation, culverts, utility structures, communications masts and occasional 7.5 m-clearance overpasses.
- Background: layered, multi-section ridge meshes replace five-sided cone mountains. City sections add stepped towers, window bands and distant simpler tower meshes.
- Atmosphere: stronger blue-to-horizon gradient, warm low-angle sunlight, reduced ambient wash and less dense cool haze. No volumetric cloud/fog or dynamic weather is introduced.
- Route sections: Open Mountain (0–2 km), Rock Cut (2–4 km), City Approach (4–6 km), Outskirts (6–8 km), selected per tile's absolute route distance across origin rebases. These are visual sections of one map, not selectable maps.

Four scenery assets are generated offline at 2,546–5,432 triangles each including alternative LOD geometry. Thirteen visual tiles keep extra forward coverage for faster cars. All four variants exist per tile before driving; recycling switches prebuilt variants and transforms only. Detailed buildings switch to simpler distant silhouettes; rocks, vegetation and detail density reduce with distance/quality. Distant ridges remain to anchor the background. Fog and advance coverage soften changes; pop-in has not been visually measured.

## Quality and performance

| Setting | Low | Balanced | High |
| --- | --- | --- | --- |
| Target cap | 30 FPS | 60 FPS | 60 FPS |
| 3D scale | 0.70 | 0.85 | 1.00 |
| MSAA | Off | Off | 2× |
| Sun shadow distance | Off; contact shadows remain | 70 m | 150 m |
| Shadow atlas | 1,024 | 1,024 | 2,048 |
| Scenery | Simple skyline; nearby rocks; no vegetation/details | Moderate vegetation and detailed near skyline | Nearby utility detail and more rocks |
| Turbo streaks | 6 | 14 | 24 |
| Exhaust planes per active nozzle | 1 | 2 | 2 |

Static road boxes are consolidated into unit-box MultiMeshes by material at boot, reducing separate road-furniture submissions. Scenery is offline-batched by material; imported meshes are reused across pooled variants. Player non-paint materials are shared; traffic keeps a bounded per-car material set for independent fade. No heavy model/scenery generation occurs during driving. LOD visibility is updated at 5 Hz. All scenery sections and player types are presented behind splash prewarm. Existing sustained-slow-frame fallback now also lowers Turbo effect quality. These are source-level cost controls, not measured FPS guarantees.

## Verification actually performed

- Foundation offline suite: 261 checks, zero failures.
- Phase 2 adapted contracts: 56 checks, zero failures.
- Fix-pass geometry/structure: 348 checks, zero failures.
- Phase 3 adapted contracts/balance: 67 checks, zero failures.
- Phase 4 catalog/GLB/source/PCM: 306 checks, zero failures.
- Python tools compile. Mesh preview inspected offline. No Godot render was inspected.
- Engine launcher: BLOCKED, executable unavailable.

Earlier byte-identity assertions were updated only for authorized changes (schema, models, controls, world). Preserved reward/settlement and fixed-collider functions are compared against Phase 3; mesh contact checks now include every split wheel material. Offline source checks are not execution of the purchase or input code.

Tests/Phase4Smoke.tscn contains real Godot scenarios for affordable/insufficient/duplicate purchases, selected ownership, reload, all upgrade levels, duplicate expected-level requests, failed-write rollback, corrupt collection input, selected-car race integration, wheel return, triple touch, buttons, desktop tilt fallback, keyboard, material roles and stationary road collision. This and the previous four smoke scenes remain **unexecuted here**.

## Minimum local validation

Import project.godot, then run:

    python Tools/run_engine_checks.py --godot /absolute/path/to/godot

Run the full visual/device checklist in DEVICE_TESTS.md: Garage buy/equip/paint/upgrade/relaunch, all six cars and Turbo, all steering modes, pause/replay/results/wallet, colored traffic, each scenery section, origin rebase, 16:9–20:9 landscape safe areas, Low/Balanced/High frame times and maximum-upgrade speeds.

The reported Android “Unable to open Android build-tools directory” remains a local SDK setup task. Android export support is retained; no SDK workaround was added to game code. No APK/AAB has been built here.

Known limitations: Godot/GDScript/shader compilation and live presentation remain unverified; tilt requires physical calibration/direction testing; source-level performance measures need device profiling; the vehicle model remains constrained to flat roads. Visual quality must be approved through actual Godot screenshots, not these offline previews. Phase 1–3 runtime regression status: NOT VERIFIED. Ready for Phase 5: NO. No Phase 5 work started.

API references used: [Godot Input sensors](https://docs.godotengine.org/en/stable/classes/class_input.html) and [RenderingServer shadow atlas](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html). These guide the implementation; they are not runtime test evidence.
