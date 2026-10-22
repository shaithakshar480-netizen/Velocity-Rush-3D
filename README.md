# Velocity Rush 3D — Final cockpit, control and traffic polish

Latest delivery: see [Docs/STATUS.md](Docs/STATUS.md). Source checks passed; Godot/Android runtime verification is pending. Earlier reports below are historical.

# Velocity Rush 3D — Cinematic driving pass

Latest status: **PARTIALLY COMPLETE**. Integrated source and offline checks; Godot/Android runtime tests remain pending. Read [the current pass report](Docs/CINEMATIC_DRIVING_PASS.md) and run `python Tools/run_engine_checks.py --godot /path/to/Godot-4.7.2`.

The notes below describe previous delivered foundations; schema 5, five cameras and the current report supersede older counts/constraints.

# Velocity Rush 3D — Phase 5 Premium Presentation Pass

**PARTIALLY COMPLETE: integrated source/assets; Godot compilation and visual/device verification pending.**

Continue this existing project by opening `project.godot` in your Godot 4.7.2 editor and allowing asset imports to finish. No manual scene assembly is required. No monetization phase was started.

This pass adds revised three-tier player models, HDR lighting/skies, richer highway scenery, redesigned menu/HUD presentation, automotive pedal symbols, original Home/Race Ogg music, 21 polished synthesized SFX and real Low traffic meshes. Save schema 4 and gameplay/economy are preserved.

Read `Docs/PREMIUM_OVERHAUL.md` for exact changes, budgets, API correction, external-model replacement and validation limits. `Docs/DEVICE_TESTS.md` is the remaining runtime/visual gate. Previews are offline projections, not Godot screenshots. The requested premium appearance and Android frame rates have not been certified.

Run engine checks with an isolated save profile:

    python Tools/run_engine_checks.py --godot /absolute/path/to/godot

Godot is not installed here; no APK/AAB is included. Keep your local Android SDK configuration. The standalone premium offline validator uses the included baseline hashes, NumPy, Pillow and FFmpeg. Historical phase validators may require the earlier checkpoint ZIPs beside the extracted folder.

Generation tools are offline only. Generate_sports_models, generate_environment, generate_premium_surfaces, generate_traffic_low, compose_premium_music and generate_premium_sfx rebuild the delivered assets. Run premium SFX generation last if also running older phase generators. The application needs none of these Python dependencies.
