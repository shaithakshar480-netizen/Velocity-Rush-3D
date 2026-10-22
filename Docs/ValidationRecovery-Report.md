# Velocity Rush 3D — validation diagnostics and recovery

Status: targeted source fixes complete; Account 2's specific data incompatibility remains unconfirmed. No Godot/Android/emulator/APK execution or build was performed.

## What the device log proves—and does not

Account 2 reaches CloudSaveService's bootstrap branch, where RushRemoteEdit.prepare(local, remote.documents, remote.versions, true) returns an empty dictionary. That exact call causes REMOTE_EDIT_VALID:false and CLOUD_EXISTING_ACCOUNT_RESTORE_FAILED:INVALID_REMOTE. HTTP/read/generation checks have already succeeded.

The supplied log contains no branch reason or Account 2 snapshot. Consequently it cannot prove which internal prepare/valid/candidate predicate failed, why Account 1's data passed, or whether coins were involved. No particular mirror, field or legacy-version diagnosis is asserted without that evidence. The new branch diagnostics identify the predicate on the next test without exposing data.

## Validation and compatibility changes

RemoteEdit now reports REMOTE_VALIDATION_FAILED:<category>:B<number> at each rejection. CloudRestore.candidate reports RESTORE_CANDIDATE_INVALID:C<number> at each candidate rejection. The identifiers map directly to the condition in source. The REST decoder also reports its existing specific schema/document error as REMOTE_VALIDATION_FAILED.

Mirror failures name only the fixed supported field: MIRROR_AMBIGUOUS:B008:COINS/XP/LEVEL/DISPLAY_NAME. Missing mirror fields use B007. Missing required documents use B002. The value is never printed.

Structural diagnostics precede compatibility handling: REMOTE_ROOT_PRESENT, REMOTE_WALLET_PRESENT, REMOTE_PROGRESSION_PRESENT, REMOTE_INVENTORY_PRESENT, REMOTE_SCHEMA_SUPPORTED and REMOTE_LEGACY_COMPAT_PATH.

Safe legacy normalization now supplies only absent metadata:
- achievement_notices → empty presentation queue;
- pending_level → empty presentation notice;
- run_checkpoint → empty only when last_started and last_finalized exist and match (no unfinished run);
- last_reward_id → empty only when last_finalized is zero;
- initial_grant_claimed → true for an existing remote inventory, preventing a duplicate initial grant.

Existing supplied values are never replaced by these defaults. Coins, purchase claims, receipts, replay counters, ownership and inventories remain validated and required where the existing restore security rules require them. Missing locked-car documents were already permitted and remain permitted. Missing version history/cloud_meta on a fresh install is still not required; server response updateTime is used. Integral JSON floats remain supported for Schema 5.

This is not a blanket acceptance of every incomplete historical snapshot. An older snapshot missing unreconstructible economy/replay evidence remains an explicit recoverable error. No new account/default upload is selected when remote exists but validation fails.

Root/wallet mirror policy is unchanged: resolve against the clean acknowledged local value, or use strictly newer server document updateTime for fresh bootstrap. Equal/missing versions with divergent mirrors fail explicitly. Coins are never summed.

## Sticky error/conflict fix

The previous failed() set blocked=true for non-transient validation failures. _process returned immediately whenever blocked, and labelled even ERROR as a skipped CONFLICT. Resume merely scheduled work, leaving that latch intact. Same-UID auth completion also scheduled without clearing/rechecking it.

The coordinator now provides retry_reconciliation(): it clears only the execution latch, forces a fresh authenticated full read, clears stale absence-cache state and logs CLOUD_CONFLICT_RECHECK_START. Blocked states recheck on a 15-second foreground cadence, on resume and on a new authentication generation. New UID/scope binding still resets old state. Same-account error retries therefore do not require process restart.

Recheck does not clear the saved baseline or merge data. Every attempt repeats the existing ownership/revision/local-change/remote validation rules. Genuine concurrent conflicts remain CONFLICT. Errors are labelled VALIDATION_OR_PROVIDER_ERROR, not misleadingly CONFLICT. Native account-collision checks remain.

## Terminal-state cleanup

conflict() now releases busy/fetching, clears pending and sets an explicit CONFLICT terminal state before a later recheck. Deferred restores no longer repeatedly leave SYNCING active: they release flags and finish with ERROR, then retry from a safe screen. Successful restore/new-account local initialization finishes SYNCED; a required canonical upload remains scheduled as a separate operation and can subsequently finish successfully or report an error. Existing HTTP20s/cloud-watchdog110s bounds and bounded transient retries remain. Offline transport still uses the existing OFFLINE status after actual failure.

No guarantee is made that an invalid account will eventually become SYNCED without its data being corrected. It will terminate each attempt explicitly and remain recoverable, rather than spin indefinitely or overwrite it with defaults.

## Freed lambda capture

Definite source hazard: FirebaseRestProvider._http created an eight-second timeout lambda capturing the temporary HTTPRequest node. request_completed queues that node for deletion. A quick response therefore frees the captured node before the timer lambda is invoked; an is_instance_valid check inside the lambda occurs too late to prevent capture restoration warnings.

The timer now connects the named _slow_request(ticket, WeakRef) method with bound scalar generation and WeakRef arguments. The method resolves the request, checks generation and request membership, and no-ops with ASYNC_CALLBACK_STALE_IGNORED:SLOW_REQUEST when cancelled/freed. It does not capture the HTTPRequest node. This is a concrete source capable of producing the reported warning; no device stack ties every historical warning exclusively to it.

Other cloud watchdog callbacks capture scalar tickets and the persistent autoload. Existing HTTP callbacks retain provider generation checks; cloud read/write callbacks retain UID, scope and epoch guards. No native changes were made.

## Changed files

- Account/RemoteEdit.gd — exact reasons and bounded legacy metadata handling
- Account/CloudRestore.gd — candidate-branch diagnostics only
- Account/CloudSaveService.gd — controlled rechecks and terminal-state cleanup
- Account/FirebaseRestProvider.gd — safe slow-request callback and decoder diagnostics
- Docs/ValidationRecovery-Report.md

## Static traces A–H

| Scenario | Source result |
| --- | --- |
| A: Account 1 valid existing cloud | Existing bootstrap validation/atomic restore → READY/SYNCED |
| B: Account 2 valid current/compatible legacy data | Missing safe metadata reconstructed; validation → restore; other rejection now reports exact B/C reason |
| C: root coins edited | Existing five-second probe/full read → unchanged mirror policy → import/UI → conditional canonical repair |
| D: prior invalid/conflict, server corrected | 15-second controlled full recheck or resume/auth retry; corrected safe data may import |
| E: logout A/login B | UID/scope/auth generations bind independently; old latch cannot prevent new scope initialization |
| F: 12–15-second response | Existing20s request allows response; LOADING→validation→READY if valid |
| G: switches/timers | Slow-request callback resolves WeakRef; stale request/provider generation no-ops |
| H: both sides changed | Full recheck repeats conflict checks, never blindly selects remote |

All103 GDScript files passed gdtoolkit grammar parsing. Byte comparison confirms only the four implementation files changed from the preceding ForegroundSync ZIP; candidate validation logic is otherwise unchanged. This is not Godot semantic compilation or runtime verification.

## Preservation and next device check

Schema remains5. No saves/progress were reset or deleted. UID isolation, credentials, Guest/linking, owner-only rules, first writes, repair preconditions, five-second polling/background suspension, purchase safeguards, garage/durability/Turbo fixes and native/Kotlin2.1.0 are retained. AAR rebuild is NOT required.

Merge the full ZIP into the existing project while keeping android/build and addons/rush_firebase/bin/RushFirebaseBridge.aar; those generated paths are excluded. Re-export the APK yourself.

Next test Account2 and capture REMOTE_VALIDATION_FAILED plus the six structural flags. That supplies the missing exact predicate without sending UID/email/tokens/coins or a full payload. Also verify corrected-remote recovery, real concurrent conflicts, repeated login/logout and timer cleanup. Account2-specific compatibility and absence of all runtime capture warnings remain unverified; no runtime success is claimed.
