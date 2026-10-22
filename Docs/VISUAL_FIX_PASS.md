> Historical checkpoint documentation. Current presentation, budgets and test status: PREMIUM_OVERHAUL.md.

# Phase 5 compile and sports-visual fix pass

PARTIALLY COMPLETE: source and mesh integration finished; Godot compilation, rendered appearance, gameplay and Android profiling remain unverified. No Phase 6 work was started.

## Compile correction
RewardService's profile setter was named `set_name`, conflicting with the inherited Node API. It is now `set_player_name` in the service, Profile UI and test callers. Profile validation/persistence logic is unchanged. No warning suppression was added. The native method is documented at https://docs.godotengine.org/en/stable/classes/class_node.html. No additional compiler failures were established without an engine. Tests/VisualPassSmoke audits public script methods against ClassDB in a real engine; that test has not run here.

## Original player geometry
All six models have smooth lofted body/glazing surfaces, open wheel arches, molded fenders, recessed intakes, lamps, skirts, wheels, split spokes, hubs, brake rotors and exhaust bores. Medium and High add tessellation and small geometry detail. Wheels share mesh resources within each asset. They remain stylized original fictional designs, not manufacturer replicas.

Vortex S uses a rounded coupe nose and short rear lip. Falcon S1 has a longer hatch-influenced roof and rear glass. Apex RS has wider fenders and side intake treatment. Inferno R uses a low roof and pedestal aero. Phantom X has a canopy-style roof and twin intake bridge. Titan V12 has the longest, widest silhouette, a carbon roof spine and larger wing.

Actual triangles, including all four wheel instances:

| Car | Low | Medium | High |
| --- | ---: | ---: | ---: |
| Vortex S | 6,586 | 15,050 | 30,698 |
| Falcon S1 | 6,666 | 15,274 | 31,034 |
| Apex RS | 6,786 | 15,250 | 30,898 |
| Inferno R | 6,926 | 15,750 | 31,654 |
| Phantom X | 6,862 | 15,366 | 31,014 |
| Titan V12 | 6,958 | 15,942 | 31,974 |

The 18 independently authored LOD resources are selected by graphics quality, not distance. Hidden tiers share resources and materials; switching does not generate geometry or load files. Body weight animation acts on the shell, leaving tire contact heights stable. Collider and vehicle dimensions are preserved. The offline preview in sports-models-preview.png projects these actual GLBs; it is NOT a Godot screenshot.

## Materials and lighting
Ten opaque material roles: Paint, Glass, Trim, Rubber, Alloy, Headlight, Taillight, Carbon, Housing and BrakeDisc. Metallic paint and opaque tinted glass use base PBR, roughness and procedural sky reflections. No downloaded textures, transparency sorting, realtime reflection probes or screen-space reflection dependency. Paint and brake emissions are separate per car instance, preventing brake-light leakage into other cars/showroom. Immutable materials are reused. High clearcoat is enabled only on a non-Compatibility renderer; the delivered Compatibility project deliberately uses base PBR. Visual results must be inspected on the target renderer.

## Graphics profiles
| Profile | FPS cap (target) | Render scale | AA | Directional atlas | Sky radiance |
| --- | ---: | ---: | --- | ---: | ---: |
| Low | 30 | 70% | Off | 512; shadows disabled | 64 |
| Medium (recommended) | 60 | 85% | 2x MSAA | 1024 | 128 |
| High | 60 | 100% | 4x MSAA | 2048 | 256 |

Two consecutive five-second windows below 45 FPS trigger each downgrade: effects, scenery/sky, shadow cost, player LOD/traffic shadows, then Low visuals/70%/30 FPS. No automatic upward oscillation. Selecting a quality setting resets this bounded sequence. Physics timestep, traffic counts/logic, coins, rewards and progression are not altered. These are configured targets, not measured performance. Mid-range devices should start at Medium; High requires physical-device profiling. All tiers are retained in memory to avoid in-race loading; memory and initial prewarm cost need device measurement.

## Integration and preserved behavior
Garage and race use the same model/paint/LOD binding. Four vehicle-specific camera anchors are data-driven; the existing camera interpolation remains. Exhaust attachment positions are retained and checked against mesh geometry. Traffic keeps the existing five fictional lightweight models and color palette; only shadow quality changes. Phase 5 save schema 4, car IDs, prices, upgrades, wallet, XP, missions, rewards and progression logic are preserved. No local Android SDK path or build-tools workaround was introduced.

## Replacing a model later
Import an original licensed GLB/GLTF or a Godot wrapper scene; FBX requires your editor's supported import pipeline. Set `visual_scene_path` to the High PackedScene resource and the first two `visual_lod_paths` entries to Low/Medium. Assets are preloaded before gameplay. Use meters, forward -Z, road-contact origin Y=0, the catalog dimensions and wheelbase. Provide four wheel pivots named Wheel_0 through Wheel_3 in front-left/front-right/rear-left/rear-right order; wheels spin around local X. An optional Body child receives visual weight lean. Name material surfaces by the roles above, especially Paint and Taillight. Update camera_anchors and exhaust points to match the replacement while retaining gameplay/stat fields. Do not attach render meshes as collision shapes. External assets were not available for an import test in this pass.

## Verification
Executed: source/resources 284; Phase 2 contracts 56; Phase 2 fix 348; Phase 3 66; Phase 4 449; Phase 5 352; visual pass 1,312. All zero failures. Checks include all 18 GLB buffers/normals/materials/budgets, wheel contact, camera clearance, exhaust alignment, source wiring and byte comparison of preserved gameplay against the Phase 5 checkpoint. Updated historical visual-budget assertions now reflect this explicitly requested redesign; they do not imply runtime correctness.

Run `python Tools/run_engine_checks.py --godot /absolute/path/to/godot` for isolated engine import, integration tests and launch. Godot is absent here; no compiler, GUI, gameplay, touch, Android build or FPS test was performed. The runner includes the new VisualPassSmoke suite. See DEVICE_TESTS.md for the remaining manual gate.
