# Phase 3 — Turbo and cinematic presentation

**PARTIALLY COMPLETE. Integrated source, not runtime verified.** Existing Godot 4.4.1+ Compatibility architecture retained. No Phase 4 implementation. Godot is absent in the authoring environment: no GDScript compilation, shader compilation, live rendering, listening in-game, physics execution or Android build/device tests were possible.

## Integrated path

DriveInput collects one-shot SHIFT or Turbo touch presses, independently of pedal/steering fingers. RushTurboController owns EMPTY / CHARGING / READY / ACTIVE / COOLDOWN, charge, drain, and smooth intensity. ArcadeVehicle reads intensity for acceleration and speed ceiling; it retains planar X/Z collision physics, steering, braking and grip. Activation signals fan out once to camera, exhaust, HUD, audio and haptics. RunManager coin/near-miss signals add charge without changing their existing reward handling. Wallet, settings schema and reward arithmetic are unchanged.

Configuration lives in Data/TurboSpec.gd and Data/VortexTurbo.tres, referenced by VehicleSpec. Future cars can select a different resource and any number of model-local exhaust points. No upgrade system is instantiated.

## Starting balance

| Property | Value |
| --- | --- |
| Capacity / new-run charge | 100 / 0 |
| Near miss | 16 × (1 + 0.08 × combo steps), capped at four steps |
| Near-miss award range | 16–21.12 |
| High speed | 0.6 energy/sec above 150 KM/H on new forward road |
| Coin | 0.35 energy per pickup; 90 pickups at most 31.5 energy |
| Full boost drain/duration | 16.666667/sec; approximately 6 seconds |
| Cooldown | 3 seconds; no charge during cooldown or ACTIVE |
| Normal / Turbo cap | 210 / 270 KM/H |
| Acceleration multiplier | Up to 2.7× |
| Intensity ramp in / out | 0.30 / 0.75 sec |
| Above-cap return | 5 m/s² deceleration; no speed teleport |
| Activation | Full meter, running, unpaused, forward speed ≥25 KM/H, brake released |
| Collision | Ends active boost; charge loss up to 8; existing slowdown retained |

Repeated presses during ACTIVE do nothing. Presses during countdown, pause or results are discarded. Holding SHIFT does not auto-reactivate. Holding throttle/steering through countdown remains supported. Braking cancels boost and remains authoritative. Residual presentation fades out; no invincibility or vertical forces are added. Every replay resets Turbo and audio transients. No partially filled meter is saved.

Target: 2–4 meaningful activations per typical run, depending on skill. Offline reference schedules yield 2 over 180 seconds with a near miss every 20 seconds, 3 over 180 seconds at 14-second intervals/combo 2, and 3 over 240 seconds at 15-second intervals/combo 2. These schedules assume forward high-speed travel after ten seconds and a coin every four seconds outside boost/cooldown. They are not traffic simulation, telemetry, or a guarantee; short/slow/unskilled runs can yield fewer.

## Presentation

- Four camera modes retain normal speed FOV. Turbo adds up to 9 degrees; hood/bumper use 60% of that. Chase offset pulls back 0.85 m and lowers 0.18 m at full intensity.
- Reusable bounded CameraImpulse uses brief 4–5 Hz decaying displacement; Turbo kick is 0.065 m and impact at most 0.085 m. Low quality and interior modes reduce it. No perpetual random shake.
- Vortex S has two model-local emitters following the interpolated visual body. Original additive procedural blue/orange flame quads respond to load, activation flash and boost. No screen-space distortion, smoke during normal straight driving, or texture downloads.
- Peripheral streaks leave the center clear and react to speed/boost. Heavy collisions briefly accent the side edges. No fullscreen blur, chromatic aberration or bright flash.
- HUD adds a smoothed meter below the speedometer and an independent Turbo target above the pedals. READY subtly pulses; BOOST colors the speed digits. A stationary READY button explains the 25 KM/H requirement. Combo scale/fade and score interpolation add restrained feedback.
- Finish locks input, ends boost, decelerates coasting motion and moves the camera outward before a deterministic side/front orbit. Results follows after 2.8 seconds. Camera stays above road and within barrier bounds by construction; live clipping still needs checking. Global time scale is never changed. Existing results calculations and wallet settlement are untouched.

## Audio and haptics

Six original mono 22.05 kHz PCM clips are synthesized by Tools/generate_phase3_audio.py: wind, turbo_spool, turbo_ready, turbo_ignition, turbo_flare and turbo_end. Wind/spool players loop continuously at inaudible levels when inactive; boost blends gain/pitch rather than restarting clips each frame. Ignition/flare supplies the boost hit and whoosh. READY and end cues fire on state transitions. Engine pitch responds to smoothed RPM/load, boost and acceleration/collision slowdown. Existing Music / Engine / SFX / UI buses and volume settings remain in charge.

Pausable gameplay nodes freeze drain, effects and impulses; audio gameplay streams pause at the same transition. Restart/Home stop Turbo one-shots and mute its loops. Android haptics uses the existing vibration setting through a bounded/debounced shared interface. Sounds remain synthesized placeholders; production timbre and in-game mix are not approved by a listening test.

## Performance

All exhaust geometry/materials and audio players are created before countdown. Exhaust draws during splash prewarm; audio feedback clips prewarm silently. No particles or audio players are allocated at activation. Speed streak budgets are 6 / 14 / 24 lines for Low / Balanced / High. Low uses one flame plane per emitter, other levels two. The mechanic/balance never depends on quality. Additive exhaust uses no lighting, textures, shadow casting, fullscreen pass or depth writes. Effects reuse nodes; normal UI work continues at the existing cadence. These measures are design choices, not measured frame-rate results.

## Validation and local test gate

Available offline suites pass: 206 foundation checks, 59 Phase 2 checks, 304 fix-pass checks and 72 Phase 3 checks. Python tools compile. Phase 3 checks cover source integration/gates, clamps, single signal connections, no runtime node creation in key loops, original PCM integrity/endpoints, unchanged save/reward/traffic/coin/road sources, and balance arithmetic. They do not execute the GDScript state machine.

Tests/Phase3Smoke.tscn adds actual Godot assertions for charge caps, one-shot READY, simultaneous touches, SHIFT, acceleration beyond normal cap, pause/drain/audio, collision and brake cancellation, large-delta drain, finish, replay and wallet isolation. It has NOT been executed here. Previous runtime suites remain included.

1. Import project.godot with Godot 4.4.1+.
2. Run: python Tools/run_engine_checks.py --godot /absolute/path/to/godot
3. Play a full run and verify all four cameras, boost visibility/control, audio tailoff, first-use frame times, collisions/braking, finish camera from every view/lane, results/wallet/replay, and 30/60 FPS transitions.
4. On Android verify three-finger steering/throttle/Turbo, pause/focus loss, vibration toggle, safe areas and 16:9 / tall landscape HUD, Low/Balanced/High effects and heat/frame-time behavior. No APK/AAB is included; the existing Android build helper still requires the local Android/Godot toolchain.

Phase 1/2 regression status: NOT VERIFIED in engine. Earlier fix-pass runtime stability issues are not certified resolved. Current known limitations include flat-road-only vehicle physics and unverified shader/material rendering, visual clipping, audio mix and device performance. Ready for Phase 4: NO pending runtime verification. No further gameplay systems were added.
