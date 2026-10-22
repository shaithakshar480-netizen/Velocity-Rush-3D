# Velocity Rush 3D — Phase 3

**PARTIALLY COMPLETE: integrated Turbo and cinematic source; Godot runtime tests pending.**

Continue from the existing Phase 2 fix-pass project. Import project.godot in Godot 4.4.1+ and press F5. No scene assembly is required. Retain the previous ZIP as a separate checkpoint.

W/arrows accelerate, S/down brake/reverse, A/D steer, C switches four cameras, Escape pauses, R restarts, and **SHIFT activates Turbo** when ready. Android adds an independent Turbo touch target above the pedals. Drive at 25+ KM/H to activate a full meter.

Read **Docs/PHASE3.md** for balance, integration, assets, performance decisions and exact validation limits. Docs/PHASE2_README.md and Docs/FIX_PASS.md describe prior checkpoints.

Run all engine tests with:

    python Tools/run_engine_checks.py --godot /absolute/path/to/godot

The engine is unavailable in the authoring environment, so compilation, runtime correctness, in-game presentation and Android performance are **not verified**. No APK/AAB is included. Do not mistake passing offline checks for a passing Godot playtest.

Major additions: Turbo/, Data/TurboSpec.gd, Data/VortexTurbo.tres, Camera/CameraImpulse.gd, VFX/, UI/TurboPresentation.gd, Core/Haptics.gd, six original synthesized audio clips and Tests/Phase3Smoke.tscn. Save/wallet and reward logic are unchanged. No Phase 4 features are implemented.
