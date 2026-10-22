# Cinematic driving, damage, opponents and time of day

Status: PARTIALLY COMPLETE — source integration and offline checks completed; Godot, rendered gameplay, Android export and physical-device tests remain unverified. No runtime/compiler/FPS claims are made. This report supersedes the presentation-only constraints and schema/camera counts in earlier reports.

## Integrated implementation

- Core/Game.gd constructs DrivingDirector during Splash, prewarms it before Play, resets its run state before countdown, enables damage/opponents at GO, and handles finish, crash, results, replay and Home. Pause uses the existing pausable world. Four conditions and three traffic tiers are prepared while the opaque loading screen remains visible. No new mesh/texture/audio resource creation occurs in the new active VFX and sound event handlers.
- CameraRig retains one interpolated vehicle pose. A critically damped local spring supplies acceleration/braking/steering response without adding lag to the world follow position. Speed adds pullback, look-ahead, restrained vibration and FOV; existing Turbo increases the presentation. Peripheral streaks leave the road center readable. No full-screen motion blur was added.
- Camera cycle: Chase, Far Chase, Hood, Bumper, Cockpit. Cockpit adds a small camera-mounted dashboard, steering ring, cluster and pillars. The exterior shell is hidden during cockpit driving to avoid opaque glass obscuring the view; it is restored for the finish orbit and menus. Steering follows the input abstraction.
- All six cars have five data anchors and seven named attachment points. External models can supply Node3D/Marker3D children named camera_chase_anchor, camera_far_anchor, camera_hood_anchor, camera_bumper_anchor, camera_cockpit_anchor, headlight_L, headlight_R. VortexVisual caches their model-local positions; catalog points remain the fallback. Existing GLB replacement, wheel, paint and collider conventions remain in place.
- Six forward automatic gears use ordered speed bands and declining torque multipliers, 180 ms shift interruption and 650 ms minimum gear hold. Transmission RPM drives the new engine bank, shift sound and small camera impulse. Gear data can be overridden separately for each car in Data/DrivingPass.json. Braking/reverse retain the existing independent handling path.
- H and the horn touch region use DriveInput. A cooldown limits sound repetition; nearby traffic has a 25% chance of a brief, small desired-speed increase, still constrained by headway checks.
- Near misses retain the existing geometric validation, score/combo and Turbo-meter rewards. Configurable gap/speed thresholds select NEAR MISS, CLOSE CALL or INSANE NEAR MISS; text expansion/fade, positional whoosh and a small camera/peripheral impulse supplement the existing score popup. Opponent pass-bys also use positional audio.

## Damage and destruction

Health uses per-car durability and relative contact speed, angle and object type. A minor contact cannot instantly destroy a healthy car. Traffic contacts are excluded from the barrier branch, preventing duplicate/misclassified damage. Previously hit traffic does not continuously inflict artificial damage while touching.

Stages are Healthy >75%, Light >50%, Heavy >25%, Critical >0%, Destroyed 0%. Presentation adds body darkening/roughness, narrow hood scuffs, impact sparks, smoke, a critical HUD tint/warning and rougher engine pitch. Scuffs are lightweight generic procedural marks; external replacement cars should tune/remove them for their body geometry.

Zero health cancels the run, disables driving/Turbo/collection/traffic, stops the player, and starts sparks/smoke/fire. A short flash, explosion sound and 2–4 cosmetic debris pieces follow. Failure UI appears after 2.6 seconds with Replay and Main Menu. No race-completion reward is generated. Existing valid progress telemetry is retained through the normal abandonment path. `revive_requested` is an extension signal only; no revive product, reward or SDK is supplied.

Damage effects allocate 48 billboard slots at boot, with 16/30/48 active budgets for Low/Medium/High. Debris is cosmetic; it never adds rigid bodies or changes road grounding. The original authoritative flat X/Z vehicle model and continuous road collision remain intact.

## Turbo inventory and persistence

Meter charge and consumable availability are separate. Each standard run resets to two free activation uses. The existing meter, minimum speed, brake, pause, run-state and cooldown gates must still pass. After two valid uses, each additional activation atomically consumes one saved extra charge before entering ACTIVE. Rejected/duplicate activation requests do not debit inventory. HUD shows free and saved counts and NO CHARGES when depleted.

Home → Turbo Supply provides coin-only offers: 2 charges/500 coins, 4/900, 10/2,000. Prices and quantities are data-driven. Coin deduction and inventory addition share one save transaction, roll back together on failure, and have a UI repeat-click gate. The page scrolls for short landscape windows.

Save schema 5 adds `consumables` with `turbo_inventory`, `ad_issued`, `ad_settled`. Schemas 1–4 remain readable; missing fields become zero. Existing settings, wallet, cars, paints, upgrades, progression, missions, achievements, daily rewards and receipts follow their existing loaders. Camera settings accept 0–4. Temp/backup/rename persistence and existing purchase/reward rollback methods remain.

RewardedAdService ships without a production SDK/provider. The provider interface is `request_rewarded(token, earned_callback, closed_without_reward_callback)`. Only the verified SDK reward event may invoke earned. A committed completion adds exactly two charges and marks that token settled atomically. Duplicate/stale tokens are rejected; skipped/unavailable ads grant nothing. A failed reward save retains the earned token in memory for the visible retry action. If the process is killed before that failed save can succeed, no durable reward receipt exists: provider-side recovery must be supplied with the future SDK. The current offline client is not an anti-tamper service.

Debug builds expose clearly labeled DEBUG AD / COMPLETE / SKIP controls. Both simulation entry points are guarded by OS.is_debug_build(). Release builds show the real unavailable state; they do not simulate production ads.

## Traffic, opponents and lighting

The identified LOD source defect was graphics-setting-only selection. Close vehicles could stay on Low. Distance now controls the selected mesh: High below 65 m, remain High until 85 m, Medium/Low boundary 135/165/205 m by quality with ±12 m hysteresis. Reused cars start High and then evaluate distance. All tiers retain proper imported vehicle meshes; BoxShape3D is collision-only. A new Medium tier contains approximately 2.35K triangles per class. Existing fictional hatchback, sedan, fastback, crossover and utility silhouettes are retained.

Four fixed-grid numbered fastback opponents use Cautious, Balanced, Aggressive and Elite data. They accelerate within bounded limits, evaluate adjacent lanes, check current/projected player clearance, traffic and other racers, reserve intended lanes, telegraph for 0.40–0.55 seconds, recheck before committing and interpolate lane changes over 0.95 seconds. Headway checks apply to both occupied lanes. Normal traffic also brakes for opponents. No teleport or rubber band is implemented; all racers participate in world rebasing. Competitive balance and unavoidable-collision risk still need runtime playtesting.

Morning, Evening, Dusk and Night are chosen once before each countdown. Four original 1K HDR panoramas supply cached sky tiers. Sun, ambient/fog colors, vehicle emission, road markers, lamp heads and city-window emission match the selection. Street lamps use emission, not individual real lights. The player has only two real shadow-free spotlights, with 85/105/130 m ranges and arcade attenuation. Traffic uses emissive headlights/taillights and stronger braking emission. All six player cars receive headlights, brake lights and small reverse lamps.

## Audio and graphics budgets

24 original synthesized mono PCM clips provide four layers for each of the six cars, with different base harmonics and modulation. Ten new original clips cover horn, shifts, blow-off, pass-by, scraping, heavy impact, explosion, fire, warnings and road noise. There are four engine players, six pooled positional effect players and two quiet loop beds. Music, Engine, SFX and UI buses remain separate; major events briefly duck the existing two-deck music mix. The old speed-modulo engine loop is muted when the RPM bank owns engine audio. No external commercial recordings were used. These are synthesized assets, not production engine recordings; listening/tuning on speakers and headphones remains required.

Low/Medium/High retain existing degradation and mobile rendering controls. No SSAO/SSR/desktop blur dependency was introduced. Near traffic detail is preserved even when shadow/effect quality is reduced. This is a design budget, not a measured Android performance result.

## Verification

The final nine offline suites returned **3,457 checks, 0 failures**. GLB file-length integrity also passed for all delivered models.

Offline checks validate resource paths/delimiters, baseline preservation of critical methods/data, GLB structure/budgets, PCM format/peaks/loop endpoints, configuration, source-level transaction/lifecycle contracts and numerical reference acceleration at 30/60/120 Hz. Reference models do not execute GDScript and do not establish handling or compiler correctness. See driving-validation.json and the other validation JSON files for exact results.

Historical whole-file preservation checks were updated where this pass explicitly authorizes changes: input horn, transmission/damage, traffic, Turbo inventory, schema 5 and five cameras. Critical unchanged road/input/progression/purchase methods are compared to the prior delivered hash baseline. Earlier Turbo balance fixtures describe meter opportunities; additional activations now also require inventory.

Tests/DrivingPassSmoke.gd adds engine scenarios for schemas 1–4, save reload, a real forced file-open failure/rollback, duplicate completion tokens, absent/skipped providers, gears, GO, all cameras, pause, three-touch horn input, two free/one extra Turbo, depleted rejection, LOD hysteresis, destruction UI and replay cleanup. Existing fixtures were adjusted for five cameras/schema 5 and isolate opponents for their original physics scenarios. These engine tests have NOT run in this environment.

Run locally from the extracted project:

```text
python Tools/run_engine_checks.py --godot /path/to/Godot-4.7.2
```

The runner imports the project, executes smoke scenes and launches the main scene using isolated save storage. Godot is not installed here; invoking the runner returned BLOCKED / exit 2. No Android APK/AAB was produced.

API source review used the official [TorusMesh](https://docs.godotengine.org/en/stable/classes/class_torusmesh.html), [GradientTexture2D](https://docs.godotengine.org/en/stable/classes/class_gradienttexture2d.html), [SpotLight3D](https://docs.godotengine.org/en/stable/classes/class_spotlight3d.html) and [AudioStreamPlayer3D](https://docs.godotengine.org/en/stable/classes/class_audiostreamplayer3d.html) references. No warnings were disabled. Documentation review does not replace compiling on 4.7.2.

## Required runtime and Android gate

1. Run the isolated engine runner above; resolve any import, compile or runtime failures it exposes.
2. Play each car with all five cameras; check cockpit clipping, gear/RPM response, braking/reverse, sustained high speed, seams, collisions and camera comfort. Test 80/150/220/300+ km/h where the selected car supports it.
3. Check every time condition and quality tier. In particular verify night road/traffic visibility, headlight range, cockpit exposure, close traffic LODs, transitions and transparent smoke/fire sorting.
4. Drive opponent battles, horn reactions and near misses. Check adjacent-lane reservations, emergency braking, fair overtakes and long-route rebasing without visible jumps.
5. Trigger light/heavy/critical/destroyed states, pause/background during effects, and repeatedly Replay/Home. Check that physics, particles, audio and free uses reset without duplicate rewards.
6. On an Android phone use simultaneous steering, throttle/brake, Turbo and horn; test display cutouts/short landscape ratios, steering modes, app suspend/resume, music/SFX levels, frame pacing, temperature and 30 FPS fallback. Debug ad tests must not appear in a release export.
7. With an existing save backup, verify ownership/upgrades/progression/wallet preservation, extra-charge purchases and restart persistence. Production rewarded ads remain unavailable until a real provider is integrated in a later authorized pass.

Ready for next feature pass: NO — runtime/device validation remains the completion gate.
