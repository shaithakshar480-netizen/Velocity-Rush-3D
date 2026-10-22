# Velocity Rush 3D — Phase 2 Fix Pass

**PARTIALLY COMPLETE: integrated source; Godot runtime verification pending.**

This extends the existing Phase 1 project, which you reported working in Godot. Godot is unavailable in the implementation environment, so Phase 2 has not been compiled, rendered, played or exported here. No APK/AAB is included.

See **Docs/FIX_PASS.md** for the fix-pass findings, deliberate flat-road physics model, validation results and runtime limitations. Earlier Phase 2 documentation describes the baseline.

## Run

Extract into a separate folder to retain your tested Phase 2 copy. Import `project.godot` in the same Godot 4.x editor and press F5. All scenes, resources and systems are connected; no manual scene assembly is needed.

Home → Play → 3 / 2 / 1 / GO → Highway Rush → Finish → Results → Play Again / Home.

Existing controls remain: W/Up throttle; S/Down brake/reverse; A/D/arrows steering; C camera; Escape pause; R restart. Landscape touch tracks each finger independently. Countdown pauses and resumes without activating controls early.

## Highway Rush

- One configurable 8,000 m route. At average forward speeds of 120–210 KM/H, arithmetic duration is 240–137 seconds. Collisions/slow driving can lengthen it; this is not measured timing.
- 24 pooled traffic vehicles with five original silhouettes: compact hatchback, sedan, fastback, SUV and pickup. Same-direction lane following, speed variation, following distance and player-aware slowing. No lane changes.
- Target active density rises from 7 to 18, subject to safe placement. One lane stays clear of traffic for the run. Spawn lookahead grows with speed; distant fade-in and existing fog soften activation.
- 40 pooled coin objects, up to 90 coins spawned per run. Five-point straight, lane-transition, cluster and adjacent-traffic patterns. Spawn checks include predicted traffic clearance.
- Physical and swept traffic collision detection, slowdown, debounced sound/camera feedback and combo cancellation.
- Near misses require full forward clearance without collision, at least 85 KM/H and a side gap of 0.12–1.25 m. Each encounter resolves once; combo window 7 seconds, cap x5.
- Distance score and forward high-speed scoring above 150 KM/H. Reverse/retrace cannot farm either. HUD retains its existing 20 Hz update rate.
- Finish gate, brief coasting presentation, complete results breakdown, wallet and replay flow. Failed reward writes expose a retry action and block leaving results until saved.

## Economy

| Item | Value |
| --- | --- |
| Road coin | +1 run coin |
| Completion | +300 coins |
| Performance | min(300, floor(score / 30) + near misses × 8 + floor(high-speed seconds / 3)) |
| Total | Road + completion + performance |
| Maximum available road coins | 360 × 1 = 360 |

Road-pickup fixtures now use one coin per collectible. Completion and performance rewards remain separate; actual attainable earnings require device verification.

Run coins are temporary until completion; abandoned/restarted runs pay nothing. Wallet, issued/settled run IDs and the last reward receipt share one atomic save envelope. Repeated claims do not add the same run again; failed writes roll back memory. Phase 1 settings migrate to schema 2 with zero wallet defaults. Offline storage is not tamper-resistant server accounting.

## Main files

| System | Files |
| --- | --- |
| Run / balance | Gameplay/RunManager.gd; Data/RunSpec.gd; Data/HighwayRush.tres |
| Traffic | Traffic/TrafficVehicle.gd; Traffic/TrafficSystem.gd |
| Coins | Collectibles/RoadCoin.gd; Collectibles/CoinSystem.gd |
| Finish marker | Environment/FinishGate.gd |
| UI extension | UI/RushPresentation.gd; UI/AutomotiveUI.gd |
| Navigation / rebases | Core/Game.gd |
| Wallet / migration | Save/SaveService.gd |
| Collision / camera hooks | Vehicle/ArcadeVehicle.gd; Camera/CameraRig.gd |
| Feedback | Audio/GameAudio.gd; Tools/generate_phase2_audio.py |
| Engine checks | Tests/Smoke.tscn; Tests/Phase2Smoke.tscn |

Input, player visual model, vehicle resource, highway, geometry helpers, performance manager, project settings and original five WAV files are byte-identical to the Phase 1 archive available here.

## Verification

Executed: audio generation, `python Tools/validate_source.py`, `python Tools/validate_phase2.py`, and Python compilation of all six tool scripts. Results: **147 structural/resource/audio checks + 42 Phase 2 source-contract/arithmetic/preservation checks, zero failures**. Exact evidence is in Docs/offline-validation.json and Docs/phase2-validation.json. Preservation comparison is skipped when the original Phase 1 ZIP is not adjacent to the project.

These checks do not compile or execute GDScript. The engine launcher was invoked and reported BLOCKED: Godot is not installed.

With Godot installed, run:

```
python Tools/run_engine_checks.py --godot "PATH_TO_GODOT_EXECUTABLE"
```

It imports, runs Phase 1 regression and Phase 2 integration scenarios in an isolated save profile, then smoke-launches. The new test harness itself remains unverified in Godot. For Android after these gates pass, use the existing Tools/build_android.py with configured SDK/JDK and matching export templates. Export preset version is 0.2.0.

See Docs/DEVICE_TESTS.md and Docs/PHASE2_ARCHITECTURE.md. No turbo, garage, purchases, ads, billing, online services, missions, daily rewards, extra environments or final graphics overhaul are implemented. Results has only an invisible empty future reward container; no fake 2X button.

New models/audio are original procedural placeholders. Production polish, spawn fairness under varied driving, reward pacing and mobile FPS require direct review. Phase 1 regression after these changes: NOT VERIFIED. Ready for Phase 3: NO.
