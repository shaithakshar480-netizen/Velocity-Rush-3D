# Velocity Rush 3D — foreground sync, slow bootstrap and power-up sizing

Source implementation complete; device verification pending. No Godot, Android, emulator, APK export or native build was run.

## 1. Logged-in remote updates

The preceding code explicitly waited 30 seconds after successful sync. It also called SaveService.acknowledge_cloud on unchanged full reads, committing the local save again. Background notifications scheduled work instead of suspending it. These explain delayed detection and unnecessary writes; a particular device's persistent conflict or unavailable baseline cannot be diagnosed without its logs.

Normal foreground poll interval is now **5 seconds** after the previous successful request. Logged-in users do not need to relogin. The existing safe-screen predicate allows Home/Profile/Account when the game is ready and no purchase/reward activity is pending. It now explicitly excludes purchase settlement; SaveService transaction checks also gate requests. Active racing and other unsafe screens defer sync.

On background, polling is suspended and in-flight reads are cancelled with their generation invalidated. An already issued write is not cancelled halfway through its commit; no new poll starts while it completes. Resume schedules an immediate check, subject to safety/auth/conflict gates. Logout and scope changes retain the preceding identity/generation protections.

Coordinator busy/fetching flags, AuthService busy state, scope tickets and provider request diagnostics prevent overlapping polling cycles. Provider diagnostics now include outstanding HTTP requests such as transaction cleanup. Existing provider-controlled read/commit operations remain intact.

## 2. Efficient change detection and unchanged reads

An authenticated, acknowledged, locally clean account first calls poll_save. The REST provider uses batchGet with a schema_version field mask to retrieve server updateTime values with minimal payload for all existing supported paths. It compares these against that UID's persisted versions. All paths are checked because a Console edit to inventory, progression or a car document does not update its parent root automatically.

Equal versions return unchanged without importing, saving, acknowledging again or uploading. Local changes made while the probe is in flight schedule normal reconciliation. Changed versions trigger the existing full supported snapshot fetch and validation. This reduces response bytes, **not Firestore's document-read billing**; five-second polling still consumes reads for the probed documents. No native listener or Cloud Functions were introduced.

Newer valid remote edits with a clean baseline restore atomically and refresh through existing SaveService signals. Canonical differences/digest repair use existing conditional commits. Both-sides-changed, malformed data and wrong ownership remain fail-closed. Missing/repaired/new account baselines use full reconciliation rather than the probe shortcut.

The requested normal log sequence remains: CLOUD_REMOTE_POLL → REMOTE_POLL_GENERATION_VALID:true → REMOTE_EDIT_DETECTED → REMOTE_EDIT_NEWER:true → REMOTE_EDIT_VALID:true → REMOTE_EDIT_IMPORT_START → REMOTE_EDIT_IMPORT_SUCCESS → REMOTE_EDIT_UI_REFRESHED → CLOUD_SYNC_DOWNLOAD_SUCCESS → canonical repair if needed → CLOUD_RECONCILIATION_RESULT:SYNCED. Binding logs REMOTE_POLL_ACCOUNT_BOUND:true; startup logs REMOTE_POLL_INTERVAL_MS:5000. Skips report safe reason codes only.

## 3. Bootstrap error and slow-network behavior

The old UI showed “Account progress is not ready” whenever bootstrap status became ERROR/OFFLINE/CONFLICT, including the first transient failure. Individual HTTP requests timed out after 12 seconds and the coordinator had a 50-second overall request-chain watchdog. There was no fixed three-second readiness failure: three seconds was sync debounce. Full Firestore documents were already batched, not fetched serially one by one.

HTTP timeout is now 20 seconds, including Identity Toolkit/token refresh requests through the same transport. The cloud chain watchdog is 110 seconds to accommodate refresh, probe/full read and conditional write stages. It is a failure bound, not a fixed delay.

Transient transport/5xx/rate-limit/request-busy errors receive at most two immediate retries with 2- and 4-second waits. While these retries are active, bootstrap remains SYNCING/LOADING. After exhaustion, the UI reports actual failure; transient failures can recover automatically on a 20-second foreground recovery cycle or resume. Permission/authentication/malformed-data failures do not retry blindly. Existing auth session logic and native picker are unchanged.

An eight-second pending-request diagnostic reports SLOW but does not cancel or classify the connection as offline. No connection-speed estimate is used. A late successful bootstrap clears the loading/failure state, commits restored data and opens Home through the existing completion signal. Local Guest remains available; defaults cannot upload before confirmed remote absence.

Safe diagnostics added: ACCOUNT_PROGRESS_STATE:LOADING/READY/FAILED, ACCOUNT_PROGRESS_WAIT_MS:<elapsed>, FIRESTORE_REQUEST_TIMEOUT_MS:20000, FIRESTORE_NETWORK_CLASS:IN_PROGRESS/SLOW/FAILED, CLOUD_BOOTSTRAP_RETRY:1/2. No UID/email/coins/credentials/save payload is logged.

A 1 Mbps bandwidth figure alone cannot prove why Account B failed: latency, timeout, permission, validation and conflict logs still distinguish the actual device cause. Slow pending work itself no longer selects the reconnect message.

## 4. Turbo sizing

Turbo used an 86×80 PanelContainer control and a 36×36 minimum-size-only TextureRect, while Magnet/Shield used explicit 66×62 buttons with 60×43 artwork. PanelContainer also laid out Turbo's label and artwork independently across the panel, causing inconsistent image bounds.

RushPowerIcon now supplies shared constants and layout helpers: touch target 66×62, artwork 60×43 centered at the top with keep-aspect scaling, and a centered 66×22 inventory label at y=39. Turbo uses an overlay Control inside its zero-margin panel so its children retain those exact bounds. Its slot width and height match the other controls. Original SVGs, activation behavior, counter updates and pressed animation remain unchanged. No HUD-wide rearrangement was made.

## 5. Files changed

- Account/CloudSaveService.gd
- Account/FirebaseProvider.gd — optional polling method with existing fetch fallback
- Account/FirebaseRestProvider.gd
- Account/AccountUI.gd
- UI/PowerIcon.gd
- UI/TurboPresentation.gd
- Commerce/RacePowerupDock.gd
- Docs/ForegroundSync-Report.md

## 6. Static traces A–G

| Scenario | Source result |
| --- | --- |
| A: Account A remains on Home, Console coin edit | Five-second safe poll detects changed updateTime, full validation/import/UI/canonical repair without relogin |
| B: Account B same | B's UID, scope generation and stored versions are checked independently; A cannot supply its baseline |
| C: Background/resume | Suspend/cancel read and invalidate callback; resume schedules immediate safe check |
| D: Delayed working response | LOADING; SLOW is diagnostic only; success gives READY and completion without reconnect |
| E: Actual timeout | 20-second request failure, two bounded short retries; FAILED after exhaustion; no blind 401/403 retries |
| F: Ten unchanged polls | Metadata-only probes return before acknowledgment/import/upload; no local write; next poll waits five seconds |
| G: Turbo/Magnet/Shield | Shared touch, artwork and label sizing helpers; aspect preserved; Turbo container no longer stretches artwork |

All 103 GDScript files parsed with gdtoolkit. Source/diff checks verified intended changed files, the unchanged early-return path, timeout/interval values, shared sizing calls and preserved native/config/save/rules source. Grammar parsing is not Godot semantic/type checking. The REST field-mask path and rendered controls require device verification; a documentation fetch attempt timed out during this pass.

## 7. Preservation and delivery

Schema remains 5. No player progress was reset or deleted. UID save isolation, Guest/linking, restore-before-default-upload, owner-only rules, revision/updateTime checks, first-write preconditions and previous durability/garage fixes are retained. Native bridge and Kotlin 2.1.0 remain unchanged. **AAR rebuild is NOT required.**

Merge this full project ZIP into the existing project, retaining android/build and addons/rush_firebase/bin/RushFirebaseBridge.aar. Neither generated path is included/replaced. Re-export the APK yourself to incorporate source changes.

Remaining runtime uncertainty: actual Account B error, Android background ordering, slow-network recovery timing, Firestore masked-response handling, Godot type checking, and icon rendering/touch behavior. Verify A–G plus edits during an in-flight probe, concurrent remote changes, malformed edits, purchase blocking and reconnect recovery. Detection is approximately one poll interval plus network/full-fetch/repair latency, not a guaranteed five-second end-to-end deadline. Existing genuine conflicts remain explicit rather than silently resolved.
