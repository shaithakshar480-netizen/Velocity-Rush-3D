# Velocity Rush 3D — controlled Firestore remote edits

## Status
Source implementation complete; runtime behavior remains unverified. No Godot, Android, emulator, APK export or Firebase Console operation was performed.

## Root cause
FirebaseRestProvider rejected any difference between the stored root `digest` and the recomputed document hash before CloudSaveService could validate or restore the data. Duplicate root/wallet coins and root/progression XP/name/level then presented a second obstacle: editing only one copy left inconsistent values. The actual project field is `digest`, not a new `snapshot_digest` field.

## Conflict policy
- Reads remain authenticated, restricted to the active UID's exact known document paths, and made from a consistent read-only snapshot.
- Each acknowledged snapshot now stores the server updateTime for every returned cloud document in local cloud_meta (Schema 5 remains unchanged).
- A mismatched digest is a candidate remote edit, never automatic permission to import.
- Import requires the same owner, an unchanged local snapshot since acknowledgment, a non-regressing remote revision, no regressing/missing previously observed document version, and at least one advanced server version or newly present supported car document.
- Existing installations without saved server versions have a one-time compatibility path: same acknowledged revision, unchanged local digest, and remote stored digest exactly matching the previously acknowledged digest. This identifies changed content relative to that known canonical baseline. It is not a timestamp-ordering proof and cannot identify an administrator. Other ambiguous legacy cases conflict.
- If local and remote both changed, preserve the local save and enter existing CONFLICT handling. Nothing is blindly summed, maximized, or overwritten.
- Older remote revisions never lower the local acknowledgment. Unknown deletions or removed previously observed documents conflict. Locally changed state is checked again immediately before restore.
- Restore is deferred during races or pending purchase/ad activity through the existing safe-screen callback. It runs only in the existing home/profile/account-safe state.
- Once imported, a persisted repair marker identifies the exact accepted remote content and versions. A retry can repair that observation without repeatedly importing it. Another remote edit invalidates that repair match and must be evaluated again.
- The repair commit retains the root revision and existence/updateTime conditions and now adds updateTime/existence preconditions to every written snapshot child. An edit between fetch and commit rejects the atomic batch. No read-write REST transaction is reintroduced.

The current client-authoritative architecture cannot distinguish Console/admin edits from another authorized same-account client's writes. Owner rules prevent cross-account access; validation does not prove an administrator authored a change. This implementation does not confer trusted purchase or competitive authority.

## Digest and coin flow
Example: the developer changes `users/{uid}.coins` from 1000 to 5000 without changing metadata.
1. Read returns the old stored digest plus a newly calculated content digest and server document versions.
2. Local unchanged/version checks admit evaluation.
3. Root coins and `meta/main.wallet_ledger.coins` are compared with the clean local baseline. If just one changed, that value becomes both canonical copies. If both changed differently, reject the ambiguity.
4. Existing wallet range 0..2,000,000,000 and replay-ledger checks apply.
5. SaveService.restore_cloud creates the existing independent `settings.before_cloud.json` backup, imports the validated candidate and atomically commits it. Failure restores runtime state and reports failure.
6. CloudSaveService generates a canonical SHA-256 digest from snapshot(candidate), persists it as local_digest with the repair marker, then schedules the normal sync path.
7. That path commits both corrected mirrors, the new root digest, revision+1, server timestamps and the existing deterministic audit record atomically. Successful acknowledgment clears repair state.

No manual hashes, revisions or timestamps are required. The same mirror policy applies to XP, level and racer name. XP determines level. A level-only edit changes XP to that level's existing threshold without awarding level-up coins. Explicit edits to both XP and level must agree.

## Exact supported edit surface
All paths below are under `users/{uid}`. Do not change auth identity fields or metadata to use this feature.

| Document | Supported editable fields / constraints |
|---|---|
| Root | coins; xp; level; display_name (existing clean 20-character racer name); selected_car (known and owned). Root email/provider/is_guest remain mirrors of Firebase Auth and are not editable identity controls. Schema must stay 5. |
| meta/main.wallet_ledger | coins; issued_run, settled_run and receipt remain protected and unchanged during manual-edit import. |
| progression/main | xp (integer 0 through the existing level-50 threshold), level (1..50), name; stats; achievement_claims/achievement_notices; reward_day (0..7), last_claim_date, date_highwater; daily.date and existing daily task progress/claimed. |
| progression/main.stats | started, completed, distance, play_time, road_coins, pickups, lifetime_coins, best_score, cumulative_score, highest_speed, near_misses, best_combo, turbo_activations, collisions, cars_purchased, upgrades_purchased, cars_owned. Finite nonnegative existing LIMIT; highest_speed <=450. Existing normalization derives ownership totals and preserves purchase-evidence minima. |
| progression/main achievements | Only IDs in AchievementCatalog; no duplicates or rollback of existing claimed rewards. No reward is granted by importing an achievement flag. |
| progression/main daily | Real supported dates; date-seeded catalog tasks remain exact (IDs, targets, event/reward configuration); progress stays 0..target; claimed requires completion. Existing last-claim monotonicity remains. |
| inventory/main | turbo_inventory (integer 0..99,999), repair_kits, coin_magnets, shields (integer 0..2,000,000,000). Ad/initial-grant/replay counters are protected. |
| cars/{existing valid catalog car ID} | owned Boolean, custom_name, paint_index within catalog palette, upgrades for existing categories at integer 0..10. Vortex S must remain owned; selected car must be owned. Adding a valid catalog car document with owned=true is supported. |
| meta/main.settings | master/music/sfx 0..1; steering 0.5..1.5; wheel_deadzone 0..0.20; steering_mode 0..2; quality 0..2; camera 0..4; map 0..7; map_time -1..5; tilt_center in the existing wrapped range; vibration/steering_assist/tilt_invert/tilt_center_saved Booleans. Invalid enums/types/ranges are rejected instead of silently clamped. |
| meta/main.onboarding | completed Boolean and starter as an existing car ID. |

Replay fields last_started, last_finalized, last_reward_id, run_checkpoint and pending_level; purchase_claims, membership_cache and upgrade_ads are protected. They cannot be edited through this import path. Unknown schema keys in supported documents are rejected, not imported. Unrequested/unknown car document IDs are outside the schema and are never added to the game. Deleting documents is not an ownership-edit API: use owned=false, keep Vortex S owned, and select another owned car if necessary.

Previously existing unowned car document slots are retained so revocation can be canonicalized without a perpetual digest mismatch. This does not eagerly create all locked car documents. Fresh accounts remain owned-cars-only.

## Validation and malformed edits
The added helper validates Firestore wire types before decoding, rejects unsupported value representations, checks bounded finite trees, schema/revision types, exact supported keys, mirror ambiguity, catalog IDs, numeric bounds, settings enums, task definitions and protected metadata. It then delegates to the existing CloudRestore candidate validator for ledger monotonicity, inventory bounds, upgrades, ownership and normalization.

Malformed edits never reach SaveService.restore_cloud. Local primary/backup files remain untouched; the normal error state/retry remains. Concurrent edits enter CONFLICT instead. Fields absent from permitted partial car/settings maps are preserved by the existing schema-aware merge. Required core documents/mirrors cannot be deleted to reset values. Local-only envelope fields are preserved by the existing restore path.

## UI refresh
No UI redesign was needed. Existing restore emits cloud_restored, changed, collection_changed, turbo_inventory_changed, wallet_changed and RewardService.progression_changed. AccountUI reapplies the selected car and refreshes Home. Existing counters/settings/inventory observers refresh from SaveService. REMOTE_EDIT_UI_REFRESHED is logged after those synchronous signals return; visual correctness still needs a device check.

## Files changed
- Account/FirebaseRestProvider.gd — return observed/stored digests and server versions; typed wire validation; guard snapshot child writes; return committed versions.
- Account/CloudSaveService.gd — controlled edit branch, version acknowledgment, canonical repair state, retained car slots and diagnostics.
- Account/RemoteEdit.gd — new pure validation/mirror/version helper (no grants or writes).
- Docs/RemoteEdits.md — this report.

## Preservation and checks
Compared every pre-existing file byte-for-byte against VelocityRush3D-Full-FirestoreFirstWrite.zip: only the two listed existing scripts changed. All 102 GDScript files passed gdtoolkit grammar parsing; this is not Godot compilation. Static checks covered restore routing, atomic preconditions, no readWrite reintroduction, revision regression guard and resource paths.

Owner rules remain byte-identical: request.auth != null and request.auth.uid == uid; child sections remain owner-only with existing getAfter root checks. Neither public access nor backend privileges were added. SaveService, safe backup/atomic commits, Schema 5 JSON float fix, Google/Auth/native bridge, Kotlin 2.1.0, Firebase/OAuth IDs, logout/NOT_CONNECTED, gameplay/economy, touch/UI and the first-upload fix are preserved.

AAR rebuild NOT required. No native code changed. Merge the full source ZIP into the current project without deleting local files. It contains no android/build and no RushFirebaseBridge.aar, so it will not replace your locally generated working copies. Re-export the APK yourself with the existing AAR.

## Expected next successful runtime
```text
FIRESTORE_READ_HTTP_STATUS:200
REMOTE_EDIT_DETECTED
REMOTE_EDIT_NEWER:true
REMOTE_EDIT_VALID:true
REMOTE_EDIT_IMPORT_START
REMOTE_EDIT_IMPORT_SUCCESS
REMOTE_CANONICAL_DIGEST_REGENERATED
REMOTE_EDIT_UI_REFRESHED
CLOUD_SYNC_DOWNLOAD_SUCCESS
# Next scheduled sync repairs the accepted snapshot:
CLOUD_SYNC_UPLOAD_START
FIRESTORE_WRITE_PRECHECK_START
FIRESTORE_WRITE_PRECHECK_HTTP_STATUS:200
FIRESTORE_WRITE_START
FIRESTORE_WRITE_HTTP_STATUS:200
FIRESTORE_WRITE_RESULT:SUCCESS
CLOUD_SYNC_UPLOAD_SUCCESS
CLOUD_RECONCILIATION_RESULT:SYNCED
```
Additional existing stage markers appear between these. Continued local activity can keep status SYNCING. No sensitive values/UIDs/tokens are added to logs. A malformed value yields REMOTE_EDIT_VALID:false and REMOTE_EDIT_IMPORT_FAILED:INVALID_REMOTE; invalid wire/schema data fails earlier with FIRESTORE_READ_FAILED. Concurrent/ambiguous state yields REMOTE_EDIT_IMPORT_FAILED:CONFLICT and CONFLICT, preserving local data.

## Manual tests required / uncertainty
- Sync cleanly, edit only root coins, then trigger the existing next sync (resume/relaunch in a safe screen). Confirm wallet/UI/disk and both Firestore mirrors; next unchanged sync must stay clean.
- Repeat with wallet-only coins, child inventory, XP-only, level-only, racer name, settings and valid owned-car/upgrade edits.
- Reject negative/excessive coins, wrong types, fractional counters, bad enums, invalid IDs/achievements and divergent mirrors.
- Make both local and remote changes; confirm CONFLICT and untouched local progress. Edit a child again while repair is pending; confirm no overwrite.
- Restart after import but before repair; confirm repair resumes without importing twice. Verify rewards/claims are not reissued.
- Check normal first upload, offline play, subsequent ordinary uploads, Google sign-in/logout and real UI refresh.

No runtime success is claimed. Deployed rules, Google/Firestore availability and actual rendering were not tested or changed. Console authorship cannot be cryptographically established from this existing client-only schema; a trusted backend approval/signature would be a separate architecture change.
