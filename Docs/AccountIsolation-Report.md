# Velocity Rush 3D — account isolation and restore update

Status: source changes complete; runtime verification pending. No Godot, Android, emulator, APK export or bridge build was run.

## Root causes

- **Account leakage:** SaveService used one global settings/backup/pending file and runtime dictionaries across Firebase identities. Authentication completion could open Home before the new UID's state was loaded. Global cloud acknowledgment fallback could also contaminate a different account.
- **Reinstall restore:** missing local saves had no usable disk snapshot or existing file to back up. Reconciliation lacked a dedicated existing-remote bootstrap branch, and locally remembered acknowledgment metadata was unavailable after reinstall.
- **Console edits:** idle SYNCED state did not periodically fetch remote changes. Fresh installs could not satisfy the locally acknowledged-baseline requirement. Root/mirror differences also needed server document versions when no local baseline exists.
- **Sliders:** shared StyleBoxFlat tracks had zero minimum height. The control/thumb existed without a reliably visible track.

## Account storage and migration

Each authenticated UID uses user://accounts/<SHA-256 of UID>/settings.json, with its own backup, pending file, before-cloud backup, settings, wallet, collection, progression, inventory and cloud metadata. Local-only Guest uses user://accounts/guest/. Raw UIDs are not logged.

Switching flushes the old scope to its old paths before binding/loading the new scope. Account completion and UI refresh occur after binding. Active races, transactions and purchase activity block switching. Cloud generations invalidate stale callbacks; purchase/membership restore callbacks also check the account-scope generation.

Legacy primary/backup/pending/before-cloud files are copied without deleting originals or overwriting existing scoped files. The recorded cloud owner determines the target. A migration sentinel prevents repeated resurrection of obsolete legacy data. Unowned Guest data remains Guest. Registered legacy data without reliable ownership is retained unassigned; it is not guessed to belong to the next Google login. Such orphaned local data may need manual recovery if absent from cloud.

Explicit Guest linking retains the Guest source and carries progress only through the Guest flow. Populated Guest and existing account progress produce conflict rather than an automatic merge. No balances or inventories are summed.

## Bootstrap and conflict policy

1. Valid UID-local cache exists: use normal revision/digest/version reconciliation.
2. No UID-local cache and remote exists: validate and restore remote before allowing local default commits or uploads. Create the scoped local save atomically, then refresh UI and continue Home.
3. No UID-local cache and Firestore confirms no remote: enable new-account initialization and the existing first-upload path.
4. Remote lookup fails: keep bootstrap gated; do not upload defaults. Local Guest remains available.
5. Established clean local state and newer valid remote edit: restore and canonicalize.
6. Both sides changed: CONFLICT, preserve data. Older remote revisions, ambiguous mirror differences and malformed data cannot silently overwrite local state.

Fresh bootstrap uses authenticated owner-scoped documents. Matching mirrors are accepted; divergent mirrors use strictly newer Firestore document updateTime. Equal/missing timestamps with conflicting mirror values fail closed. It does not use the client clock as authority.

## Manual coin edit path

An idle safe-screen poll (30 seconds), app resume or normal sync fetches the changed root document. For an established account, the acknowledged local digest must still match and remote server versions must advance. Root-only coin edits resolve against the clean local baseline. For reinstall bootstrap, the newer root document updateTime resolves the root/wallet mirror.

Validated coins replace the canonical wallet mirror through SaveService.restore_cloud. Existing atomic save/backup logic persists it. Existing wallet, progression, collection, settings and cloud-restored signals refresh UI. A new canonical digest and account acknowledgment are saved; the existing conditional Firestore commit repairs canonical documents and increments revision. Concurrent server changes still fail the write preconditions.

Existing validation remains, including Schema 5, coins/XP/level bounds, known cars, ownership, upgrades, inventories, settings and progression. Bootstrap additionally validates replay-ledger shapes. Purchase and membership caches do not become verified entitlements merely by cloud restoration. No provider security boundary or Firestore rules were changed.

## UI

All shared HSlider tracks now have an opaque rounded 8px minimum track and disabled thumb artwork, retaining existing values, events and touch sizing.

Home has a compact original avatar/name/level/XP card at top-left. Its whole surface opens Profile; children do not intercept taps. It refreshes after account scope changes, restore, progression changes and name updates. The full page title is Profile. The breadcrumb and redundant Home level badge were removed. Branding moves right to avoid the card.

## Files changed

- Save/SaveService.gd
- Account/AuthService.gd
- Account/CloudSaveService.gd
- Account/RemoteEdit.gd
- Account/AccountUI.gd
- Commerce/PurchaseService.gd — restore callback scope guard only
- Commerce/MembershipService.gd — restore callback scope guard only
- UI/AutomotiveUI.gd
- UI/ProgressionUI.gd
- Assets/UI/player_avatar.svg — new
- Assets/UI/slider_thumb_disabled.svg — new
- Docs/AccountIsolation-Report.md — this report

## Static verification

All 103 GDScript files parsed with gdtoolkit. This is grammar validation, not Godot compilation/type checking. Source assertions checked flush/bind ordering, completion gating, bootstrap priority before compare-and-set, pending-save write protection and visible track sizing. Both new SVGs parsed as XML.

Byte comparison against the previous full SettingsAudioLighting project confirmed native bridge, Firebase REST provider, AndroidCredentialBridge, Firebase config, owner-only Firestore rules, vehicle, traffic and audio source were unchanged. Kotlin remains 2.1.0. Schema remains 5. No player save files were deleted or reset by this work. Runtime migration still needs device verification.

### Eight requested scenario traces

| Scenario | Source path/result |
| --- | --- |
| Reinstall → Google A with cloud | Bind missing UID scope → remote read → validated atomic restore → completed/Home; no default upload before read |
| A → logout → B | Flush A → Guest scope → bind B cache/bootstrap; no automatic A copy |
| B → logout → A | Bind A's retained scoped cache; reconcile only A |
| Root coins edited | Poll/resume → newer/version check → mirror canonicalization → restore/UI → conditional repair |
| Both sides changed | Explicit CONFLICT; no automatic merge |
| Neither local nor remote exists | Confirm absence → initialize scoped defaults → first upload |
| Settings | Shared nonzero track style with normal/highlight/disabled thumb assets |
| Home | Top-left tappable current-scope name/level/XP card; full page Profile |

These are static traces, not executed scenarios.

## Expected diagnostic markers

Successful reinstall restore, among existing auth/network diagnostics:

```
ACCOUNT_SCOPE_SWITCH
ACCOUNT_LOCAL_SAVE_AVAILABLE:false
ACCOUNT_REMOTE_SAVE_AVAILABLE:true
CLOUD_BOOTSTRAP_MODE:REMOTE_RESTORE
CLOUD_EXISTING_ACCOUNT_RESTORE_START
CLOUD_EXISTING_ACCOUNT_RESTORE_SUCCESS
CLOUD_SYNC_DOWNLOAD_SUCCESS
CLOUD_RECONCILIATION_RESULT:SYNCED
```

Canonical differences may produce SYNCING, upload and then SYNCED instead. A valid edited bootstrap additionally emits remote-edit import markers.

Account switching:

```
LOGOUT_REQUESTED
ACCOUNT_SCOPE_SWITCH
ACCOUNT_LOCAL_SAVE_AVAILABLE:true
LOGOUT_AUTH_CLEARED
CLOUD_RECONCILIATION_RESULT:NOT_CONNECTED
ACCOUNT_SCOPE_SWITCH
ACCOUNT_LOCAL_SAVE_AVAILABLE:true/false
AUTH_STATE_UPDATED
ACCOUNT_REMOTE_SAVE_AVAILABLE:true/false
```

Established-account Console coin edit with a clean local baseline:

```
CLOUD_REMOTE_POLL
REMOTE_EDIT_DETECTED
REMOTE_EDIT_NEWER:true
REMOTE_EDIT_VALID:true
REMOTE_EDIT_IMPORT_START
REMOTE_EDIT_IMPORT_SUCCESS
REMOTE_CANONICAL_DIGEST_REGENERATED
REMOTE_EDIT_UI_REFRESHED
CLOUD_SYNC_UPLOAD_START
CLOUD_SYNC_UPLOAD_SUCCESS
CLOUD_RECONCILIATION_RESULT:SYNCED
```

Resume/normal sync need not print CLOUD_REMOTE_POLL. Unsafe or concurrent changes produce CONFLICT/ERROR, not success markers. Diagnostics contain no UID, email, credentials or save values.

## Install and manual verification

Merge the ZIP's VelocityRush3D contents into the existing project. Keep your current android/build directory and addons/rush_firebase/bin/RushFirebaseBridge.aar. These generated paths are absent from the ZIP and are not replaced. **AAR rebuild is NOT required.** Re-export the APK yourself to include the GDScript/UI changes.

Verify the eight scenarios above on device, with backups before reinstall; also test offline Guest, populated Guest linking conflicts, malformed remote edits, a remote change during repair, restarting after migration, pending purchase callbacks during account changes, and slider/profile layout at your Android aspect ratio. Check that Google sign-in, logout, first upload, owned-car documents and existing audio/touch systems still behave normally.

Remaining uncertainty: Godot 4.7.2 semantic/type checking, actual network ordering, filesystem failures/recovery and rendered/touch appearance were not executed. Unassigned legacy registered data and concurrent Guest/account conflicts are preserved rather than automatically resolved. No runtime success is claimed.
