# Phase 2 fix pass — source integrated, runtime pending

Status: PARTIALLY COMPLETE. No Phase 3 or turbo features added. Godot is not installed here; no GDScript compilation, gameplay rendering, Android build or device test was performed.

## Findings and changes

- **Falling/bouncing:** the old CharacterBody skipped physics during countdown, then enabled gravity and floor snapping on GO. Road and barrier colliders also belonged to recycled visual chunks. These are source-level risks, not a reproduced root cause. No physical seam gap was established. The revised flat highway deliberately uses a planar arcade model: one authoritative road height, no gravity/snap/spring competition, horizontal engine collision sliding, and visual-only body lean. This is a consistent constrained model, not a visual cover over vertical physics. It does not support ramps, jumps or airborne driving.
- **Driving/camera jitter:** the render camera followed raw fixed-tick vehicle transforms. Vehicle visuals, traffic visuals and camera now use previous/current physics-pose interpolation. Camera collision queries run in physics; camera presentation runs after vehicle rendering. Origin rebases update both pose samples. This addresses the source timing mismatch; perceived smoothness remains unverified.
- **Countdown hitch:** pools already existed before GO; synchronous mesh creation at GO was not found. First-visibility resource work remains an unprofiled hypothesis. Resources and all five traffic types now warm behind the splash, pool construction yields between batches, feedback audio warms silently, and initial spawns are staggered. Countdown advances before vehicle physics so held touch can unlock on GO. No performance measurements are claimed.
- **Coin misalignment:** the cluster used explicit sinusoidal lateral offsets, independently phased height bobbing, and reused rotation. Patterns now use shared exact lane coordinates; transitions use smoothstep, height stays fixed, and reuse resets orientation/scale. Coins overlapping traffic are hidden and cannot collect until clear. Metallic discs, consistent rims/V emblems and eight reusable pickup rings replace inconsistent presentation.
- **Traffic quality:** stacked primitive bodies were replaced with five original generated glTF silhouettes. Shared wheel geometry, glazing, hood/deck profiles, arches, mirrors, bumpers and lights provide recognizable proportions. Pools instantiate the assets before play. Lane positions stay exact and speed changes are bounded.

Road collision is now one stationary deck and two stationary barriers; visual tiles recycle independently. Asphalt/shoulder tops equal road height and meet without coplanar overlap. Lane guides are available through `highway.set_debug_lanes(true)` only in debug builds and are hidden by default.

## Original traffic

| Vehicle | Class | Length | Triangles including four wheels |
| --- | --- | --- | --- |
| Luma C | Compact hatchback | 3.96 m | 2,942 |
| Meridian S | Sedan | 4.48 m | 2,942 |
| Aero F | Sporty fastback | 4.56 m | 2,946 |
| Summit X | SUV/crossover | 4.56 m | 2,966 |
| Forge U | Utility pickup | 5.02 m | 2,922 |

Geometry is authored by `Tools/generate_traffic_models.py`, with no downloaded models or logos. Each uses about six mesh surface submissions; transparency fade still requires device profiling. `traffic-geometry-preview.png` is an offline geometry projection, NOT a Godot screenshot. Wheel geometry reaches Y=0 in all five assets. Android export explicitly includes the traffic JSON.

## Verification actually performed

- `python Tools/validate_source.py`: 170 checks, zero failures (structural only).
- `python Tools/validate_phase2.py`: 40 checks, zero failures (offline invariants).
- `python Tools/validate_fix_pass.py`: 304 checks, zero failures (GLB integrity/finite coordinates, wheel contact geometry, triangle budget, lane math, seam math, source structure, unchanged save/balance files).
- Python tools compile successfully. These checks do not compile GDScript.
- `python Tools/run_engine_checks.py`: BLOCKED, Godot unavailable.

## Minimum local action

Import `project.godot` in Godot 4.3 or newer. Run `python Tools/run_engine_checks.py --godot /absolute/path/to/godot` to execute import and all three runtime smoke scenes in an isolated save profile. The added Phase2FixSmoke includes an 80-second high-speed seam/rebase scenario. Then play visually and test a physical Android device using DEVICE_TESTS.md. No manual system assembly is needed.

Verify countdown/frame timing, held multi-touch on GO, straight driving and steering at all speeds, barrier/traffic impacts, four cameras at 30/60 FPS, coin occlusion/pickups and lane alignment, near misses, full 8 km finish, results/wallet persistence, replay, audio/settings and safe areas. Headless tests cannot verify these visual/audio/device outcomes.

## References for timing design

Godot's [advanced physics interpolation guidance](https://docs.godotengine.org/en/stable/tutorials/physics/interpolation/advanced_physics_interpolation.html) explains render-camera interpolation and fixed-tick stair stepping. [CharacterBody3D documentation](https://docs.godotengine.org/en/stable/classes/class_characterbody3d.html) describes floating motion and platform/floor handling. This project uses its own matched interpolation samples.

Ready for Phase 3: NO, pending successful Godot and Android regression tests.
