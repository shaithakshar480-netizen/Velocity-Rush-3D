# Velocity Rush 3D — polling, bootstrap, garage and durability

Source changes complete; Account B's exact device failure remains unconfirmed without its diagnostic trace. No Godot/Android/emulator execution, APK export or native build was performed.

## Account-specific remote edits

Source findings: cloud acknowledgment already resides in each UID's SaveService scope; no global fallback was reintroduced. Poll timer/fetch state was not fully reset on identity changes, binding tracked UID but not SaveService's scope generation, and a stale ACCOUNT_COLLISION provider error was checked before logout/new-scope handling. That error could block reconciliation before the new account was bound. Existing conflict/safe-screen suppression lacked reason diagnostics. These are concrete lifecycle gaps; they do not prove which one affected Account B.

Changes: bind UID plus scope generation; reset fetch/poll/pending/backoff state on rebind and logout; clear old bootstrap cache; invalidate callbacks using epoch, scope generation and both current auth/storage UIDs. A collision from the current unchanged identity remains a conflict, while stale prior-identity error state cannot preempt logout/new binding. Acknowledged revision, digest, local baseline, server document versions and repair markers remain scoped on disk. Runtime generations are deliberately process-local cancellation tokens, not restored counters.

New safe logs: REMOTE_POLL_ACCOUNT_BOUND:true, REMOTE_POLL_GENERATION_VALID:true, REMOTE_POLL_SKIPPED:NOT_CONNECTED/AUTH_BUSY/REQUEST_BUSY/CONFLICT/SCOPE_CHANGED/UNSAFE_SCREEN/STALE_CALLBACK, REMOTE_EDIT_BASELINE_AVAILABLE:true/false, REMOTE_EDIT_REMOTE_ADVANCED:true/false. Skip reasons are logged on transition, not every frame. No UID, email, coins or credentials are logged.

Normal clean-local/newer-remote imports retain validation, mirror resolution, atomic restore, UI signals and conditional canonical repair. Concurrent local/remote changes still conflict. Missing baselines and malformed remote data are not accepted merely to force success.

## New-account latency

Previous new binding called the ordinary schedule() debounce, imposing at least three seconds before bootstrap. Confirmed absence then scheduled another delayed sync with a redundant existence fetch before first upload. Home was already intended to open before upload; this pass does not weaken that gate.

New binding schedules immediately. One authoritative missing-remote result allows atomic local initialization and Home immediately. That absence result is consumed once for the initial upload attempt. The existing compare_and_set read and exists:false/updateTime preconditions remain, so a concurrently created remote cannot be overwritten. Failed reads never qualify as absence. No 30-second poll wait is used for bootstrap.

Markers, each paired with an elapsed-ms diagnostic:
ACCOUNT_BOOTSTRAP_START → ACCOUNT_BOOTSTRAP_REMOTE_CHECK_START → ACCOUNT_BOOTSTRAP_REMOTE_CHECK_DONE → ACCOUNT_BOOTSTRAP_NEW_ACCOUNT_CONFIRMED → ACCOUNT_BOOTSTRAP_LOCAL_INIT_DONE → ACCOUNT_BOOTSTRAP_HOME_READY → ACCOUNT_BOOTSTRAP_FIRST_UPLOAD_START → ACCOUNT_BOOTSTRAP_FIRST_UPLOAD_SUCCESS.

Network/auth latency remains outside the eliminated fixed waits. Existing-remote bootstrap still restores before Home/default upload.

## Garage

The previous arrows set left/right anchors, then assigned absolute position.x=12/-70, replacing the intended right-edge placement. They also used the whole page's vertical center rather than the reserved car region.

A dedicated navigation Control now matches the showroom region above the lower panel. Buttons use left/right anchors with symmetric 12px inset offsets, 56×64 minimum targets and vertical-center offsets. No absolute position assignment remains. Existing safe-area page, premium theme, pressed feedback and browse callbacks are retained. The empty navigation area ignores input.

## Damage balance

Old formula: clamp((3 + normal_speed² × 0.021) × orientation × barrier_factor, 0.5, 65). Legacy health values covered only six cars (90–125 HP); all six newer cars defaulted to 100 HP regardless of price. Two capped 65-HP impacts could destroy a flagship. There were no front/rear distinctions: abs(dot) treats both similarly; side impacts have lower damage.

The vehicle already debounces barriers by 0.35 seconds and traffic responses by 0.6 seconds, plus traffic was_hit protection. No every-physics-frame damage duplication was proven. The damage controller now adds a short 0.22-second backstop after an accepted impact, including shield absorption. Its existing physics-driven grace timer pauses with gameplay. No long invulnerability was introduced.

New health: 100 for every car. New formula:

final_damage = clamp((3 + normal_speed² × 0.008) × lerp(0.35, 1, abs(normal·forward)) × (1.12 for barrier, otherwise 1), 0.5, 45) / durability_multiplier

Durability is read from each existing car's VehicleCatalog entry; IDs, prices and upgrades are unchanged. Old DrivingPass health entries are retained for compatibility but no longer govern this controller.

| Car | Multiplier | Repeated 45 m/s frontal traffic impacts to depletion* |
| --- | ---: | ---: |
| Vortex S | 1.00 | 6 |
| Falcon S1 | 1.10 | 6 |
| Apex RS | 1.18 | 7 |
| Inferno R | 1.25 | 7 |
| Phantom X | 1.35 | 8 |
| Titan V12 | 1.45 | 8 |
| Tempest GT | 1.50 | 8 |
| Razor X | 1.55 | 9 |
| Nebula R | 1.60 | 9 |
| Solaris V | 1.65 | 9 |
| Cyclone RS | 1.70 | 9 |
| Aether One | 1.75 | 10 |

*Offline arithmetic, full health, spaced impacts, no shield/repair. This is not a runtime crash test. At the extreme damage cap, starter/top survive 3/4 impacts respectively; neither is invincible. Real impact speed and angle determine damage.

Stages unchanged: light damage ≤75%, medium/smoke ≤50%, critical ≤25%, destroyed at zero. Existing flames/destruction sequence starts after depletion; no earlier fire threshold was added. Existing pooled smoke, crash VFX, warning/audio and repair behavior remain.

## Changed files

- Account/CloudSaveService.gd
- Garage/GarageUI.gd
- Vehicle/DamageController.gd
- Data/VehicleCatalog.json — durability_multiplier only
- Docs/PollBootstrapDurability-Report.md — report

## Static audit

103 GDScript files parsed using gdtoolkit; this is grammar checking, not Godot semantic compilation. JSON parsed; all 12 multipliers are bounded and nondecreasing by price. Formula arithmetic verifies premium survival improves. Diff against the preceding AccountIsolation ZIP confirms only the four implementation files above changed; all other existing files are byte-identical. Source traces:

A: synced account + newer Console edit → unchanged baseline gate → import/repair.
B: logout A clears polling/cache; B binds its own generation/metadata → independent fetch/diagnostics/import, unless a genuine conflict or invalid baseline exists.
C: missing local + confirmed absent remote → immediate initialization/Home → conditional upload; existing remote still restores first.
D: arrows anchored to opposite edges of the showroom-height control.
E/F: identical spaced impacts yield six starter versus ten flagship hits at 45 m/s.
G: existing source debounce plus new controller cooldown prevents same-frame multiplication; prolonged scraping can still cause bounded subsequent damage.

## Preserved and remaining tests

Schema remains 5. No player progress was reset, no save data was deleted, and no prices changed. Native source, Kotlin 2.1.0, Firebase identity/config/rules, REST provider/commit preconditions, account storage, settings/profile, audio, traffic AI and driving physics are unchanged. No Cloud Functions. AAR rebuild is NOT required.

The ZIP omits android/build and addons/rush_firebase/bin/RushFirebaseBridge.aar. Merge its project contents while retaining those local generated files, then re-export the APK yourself.

Manual checks required: A/B remote-edit traces (including baseline/advanced/skipped reasons), C timing markers, reinstall existing account, concurrent changes, logout during fetch, first-upload retry, garage arrows at Android aspect ratios, shield/repair/pause/restart and comparable impact tests across tiers. Actual Account B cause, UI rendering, Godot type checking and gameplay feel remain runtime uncertainties. Do not interpret static checks as confirmed device success.
