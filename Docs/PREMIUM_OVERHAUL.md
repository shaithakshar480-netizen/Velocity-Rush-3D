# Premium visual / UI / audio overhaul

## Status
PARTIALLY COMPLETE. This is the existing Phase 5 project with integrated presentation changes. No monetization, new gameplay phase, physics replacement or save-schema migration was added. Source and offline asset checks passed. Godot is unavailable in this environment: compilation, in-engine visuals, before/after screenshots, touch gameplay, Android exports and achieved frame rates are NOT verified. The requested final premium visual standard cannot be certified from these offline checks.

## Player cars
The existing three-tier external-model architecture is retained. Each car now includes stationary caliper geometry behind rotating rims, optical projector barrels, lens surrounds and additional aero detail. Profiles differ in canopy height, shoulder/waist/taper, fascia, intakes, wheel spokes and rear treatment.

- Vortex S: sculpted modern coupe nose, integrated lighting and restrained lip aero.
- Falcon S1: shorter, lower canopy and rear glass, compact aggressive nose and six-spoke wheel language.
- Apex RS: wider track-oriented shoulders, fender gills and side intake treatment.
- Inferno R: lowered exotic canopy, airflow channels, buttresses and pedestal aero.
- Phantom X: canopy-style greenhouse, segmented rear light bridge and narrow twin-intake nose.
- Titan V12: widest flagship stance, carbon center spine, extra gills, heavier buttresses and large rear aero.

These are original procedural/stylized meshes, not scanned or production-artist vehicle assets. Actual in-engine lighting and silhouette review remains necessary before final art acceptance. The offline geometry projection in sports-models-preview.png is explicitly NOT a Godot screenshot.

| Car | Low triangles | Medium triangles | High triangles |
| --- | ---: | ---: | ---: |
| Vortex S | 7,394 | 16,778 | 33,450 |
| Falcon S1 | 7,474 | 17,018 | 33,818 |
| Apex RS | 7,642 | 17,026 | 33,698 |
| Inferno R | 7,918 | 17,694 | 34,654 |
| Phantom X | 7,962 | 17,418 | 34,122 |
| Titan V12 | 7,982 | 17,918 | 35,006 |

Thirteen named opaque material roles separate Paint, Glass, Trim, Rubber, Alloy, Headlight, Taillight, Carbon, Housing, BrakeDisc, BrakeCaliper, Lens and LightInternals. Metallic/roughness response uses authored HDR environment reflections. Glass stays opaque and tinted to avoid alpha sorting. Brake materials are isolated per instance; all LODs share each car's paint. High clearcoat remains conditional on a non-Compatibility renderer; the delivered project retains Compatibility and base PBR. Contact shadows and the original colliders/road-contact model remain.

## Highway and lighting
A generated 2048×1024 golden-hour HDR panorama provides warm horizon/sun glow and baked cloud bands, with cool upper sky. A separate 1024×512 studio HDR contains broad softbox reflections. Both use PanoramaSkyMaterial and bounded sky radiance (64/128/256). Clouds are static texture detail, with no animated sky evaluation or volumetrics. HDR lighting orientation and exposure need renderer inspection.

One warm highway DirectionalLight3D and cool sky fill define the scene. No ray tracing, SSR, SDFGI or volumetric cloud/fog system was introduced. Existing non-volumetric distance haze stays quality-scaled. Studio ribs, floor rails, softbox surfaces and fictional branding support Home/Garage presentation. The showroom and highway retain separate Environment resources so changing quality cannot substitute the wrong sky.

The road now samples a shared 1K packed asphalt surface map with subtle grain and roughness variation, paired tire-wear bands and repair patches in world coordinates. Physical road support and recycling functions are preserved byte-for-byte. New edge ribs and reflector studs are non-colliding instanced visuals. Fictional signage rotates through Aurora City, Northline, Summit Pass, Central Loop, Coast District and Velocity Way.

Four existing scenery sections now have three irregular ridge bands, more silhouette breakup, merged grass/shrub geometry, stepped building crowns, facade fins and rooftop equipment. All terrain/grass/structure meshes are generated offline. Section mesh totals range from 4,540 to 8,266 triangles before runtime detail/distance visibility selection. Scenery pooling and batching remain; no per-frame environment mesh generation.

## UI and cinematic presentation
Home uses the selected car in the showroom, a directional gradient scrim, editorial title, compact navigation and retained wallet/XP/daily indicators. The theme uses graphite surfaces, cool metallic/cyan accents and warm reward accents, with one existing Godot default font family and consistent size hierarchy. No proprietary font was bundled.

Garage retains every purchase, selection, paint and upgrade action. Vehicle browsing slides the old car out and the new car in over 0.28 seconds. Stat bars animate; upgrade labels show current/next percentage effects, prices and insufficient-funds/MAX states. The purchase logic remains the original logic with presentation feedback added.

Race HUD adds a digital arc speedometer, slim progress/Turbo bars and recognizable pedal artwork. The accelerator is slim/vertical; the brake is wider/horizontal. The invisible touch rectangles remain 148×126 and 128×126 while artwork is 53×96 and 88×59. Brake sits left of accelerator. Presses depress the artwork over ~0.08 seconds with cyan/red edges; reverse remains separately visible as R in the gear display. DriveInput still owns independent finger IDs, preserving steering + pedal + Turbo. The semi-transparent steering ring retains its existing input algorithm.

Results uses a revised RUN COMPLETE hierarchy, coin count-up, XP/mission information and live-run top speed. Old recovered receipts do not contain per-run top speed; they show a dash instead of inventing it. Missions have icon/progress cards, distinct warm career titles, and unchanged claims. Profile uses paired stat cards and selected-car presentation. Seven daily cards retain date/claim logic, with current-day styling and claim pulse. Settings, pause, safe-area handling and landscape enforcement remain.

Chase cameras use bounded lateral response, velocity-aware look-ahead and acceleration/brake kick from the existing physics acceleration measurement. All four modes, Turbo FOV/pullback, restrained impact impulse and existing interpolated vehicle pose remain. No physics timing changes were made.

## Original audio
Two original sixteen-bar stereo synth compositions are included as Ogg Vorbis: Home/Garage (104 BPM, 36.923 seconds) and Race (128 BPM, 30 seconds). They contain authored bass, pads, percussion and arpeggios, with circular note tails and a short mastered boundary correction. Decoded loop boundaries were measured; seamless perceptual looping still requires listening in-engine.

Both music decks remain playing, including the silent deck, so navigation does not restart tracks. A 1.2-second constant-power crossfade follows Home/Race/Results state; pause ducks music. Existing Master/Music/SFX settings and buses remain persistent.

Twenty-one original synthesized clips replace engine, skid, wind, collision, Turbo spool/ready/ignition/flare/end, UI, coin, near miss, car selection/purchase, upgrade, XP, level-up, mission, achievement and reward sounds. Engine pitch/load transitions are smoothed. Clips retain their existing names, mono 22.05 kHz format and event hooks. Countdown and GO behavior are retained. No sampled commercial songs, artist imitation, external instruments or downloaded audio were used. Final mix/loop listening on speakers and headphones remains pending.

## Quality and performance
| Profile | Frame-rate target/cap | Scale / AA | Player detail | Traffic detail | Sky radiance |
| --- | --- | --- | --- | --- | --- |
| Low | 30 FPS | 70% / off | Low | 1.8K meshes | 64 |
| Medium, default | 45–60 target; 60 cap | 85% / 2x | Medium | original ~3K | 128 |
| High | 60 where supported | 100% / 4x | High | original ~3K | 256 |

Shadow atlas sizes remain 512/1024/2048; Low disables main shadows but retains contact shadows. Scenery and effects follow the selected profile. Traffic Low is a real separately tessellated asset, not a label, and is prewarmed before the race.

Adaptive reductions require two sustained five-second windows below 45 FPS per step: effects, scenery, shadow distance/resolution, sky reflection resolution, traffic/player LOD, then render scale/AA and 30 FPS fallback. Physics, traffic counts/movement, reward calculations and saved quality preference are not changed. All car LOD resources are cached to prevent in-race loading; the tradeoff is initial import/prewarm and memory cost. Actual Android memory, thermal behavior and frame time have not been measured.

## Godot API corrections
The invalid `Environment.REFLECTED_SOURCE_SKY` was replaced by `Environment.REFLECTION_SOURCE_SKY`. New code uses documented PanoramaSkyMaterial.panorama and AudioStreamOggVorbis.loop APIs. Official source references:
- https://docs.godotengine.org/en/stable/classes/class_environment.html
- https://docs.godotengine.org/en/stable/classes/class_panoramaskymaterial.html
- https://docs.godotengine.org/en/stable/classes/class_audiostreamoggvorbis.html

These documentation checks do not replace compiling in the user's Godot 4.7.2 editor. The prior set_player_name fix remains. No global warning suppression was introduced.

## External models and preservation
For Vortex S, replace Data/VehicleCatalog.json's vortex_s visual_scene_path and first two visual_lod_paths entries with imported High/Low/Medium GLB/GLTF or wrapper scene resources. FBX requires the editor's supported importer. Keep meters, forward -Z, road origin Y=0, catalog wheelbase/radius, four Wheel_0..3 pivots ordered front-left/front-right/rear-left/rear-right, and optional Body shell. Wheels spin around local X. Match material role names; update camera_anchors and exhaust_points to the asset. Never use the render mesh as collision. See VISUAL_FIX_PASS.md for the underlying replacement architecture; its older budgets are superseded by this report.

Save schema 4 and persistence, wallet, XP, levels, missions, achievements, collection, paints, upgrades, settings and career-stat logic remain unchanged. Baseline hashes in premium-baseline.json allow the standalone premium offline validator to verify protected source. No SDK path, ads, billing, Firebase or monetization system was added.

## Tests and remaining gate
Eight offline suites ran with zero failures: Source/resources 303; Phase 2 56; Fix 348; Phase 3 66; Phase 4 509; Phase 5 344; visual geometry 1,415; premium integration/assets 116. Historical assertions were adjusted only for explicitly redesigned geometry/audio/presentation; preserved gameplay checks remain. Actual shipped Oggs were decoded with FFmpeg and checked for duration, finite samples, headroom and boundary discontinuity. All 21 SFX were decoded and checked for format/headroom/endpoints. HDR scanlines, texture dimensions, model buffers/normals, wheel contact, camera/exhaust geometry and previews were checked offline.

Godot runner result: BLOCKED, executable absent. No compilation, gameplay, screenshots, Android build or FPS measurement was performed. Tests/PremiumSmoke adds engine checks for showroom transitions/reflection isolation, music imports, all menu routes and three-finger ownership; it has NOT run here. Run the included engine runner before manual testing:

    python Tools/run_engine_checks.py --godot /absolute/path/to/godot

Then perform the checks in DEVICE_TESTS.md. No manual scene assembly or missing implementation step is required. A passing engine run and visual/device acceptance are prerequisites for monetization readiness. READY FOR MONETIZATION: NO.
