# Firestore first-upload 403 — source fix

## Finding and scope
The failing request was the second documents:batchGet, before documents:commit. `_read(uid,true)` opened `newTransaction.readWrite` using a Firebase Auth bearer token. Google explicitly documents that third-party authentication cannot create read-write transactions. This is a REST request-mode defect, not a proven security-rule defect. The supplied status sequence and source branch identify this stage; deployed rule contents were not inspected.

Reference: https://docs.cloud.google.com/firestore/docs/reference/rest/v1/TransactionOptions

## Secure fix
The write precheck now reads only the root without opening a transaction. A missing root receives `currentDocument.exists=false`; an existing root receives `currentDocument.updateTime` from the server Document metadata. Missing updateTime on an existing root fails closed. All writes still use one atomic documents:commit, now without a transaction token. Revision equality and digest idempotency checks remain. Concurrent creation or root updates invalidate the precondition and reject the complete batch. Commit ABORTED/ALREADY_EXISTS/FAILED_PRECONDITION statuses route to conflict; raw error payloads are never logged.

The initial consistent read-only snapshot transaction and its cleanup remain unchanged. Owner rules and server timestamps remain unchanged. This is not non-atomic batchWrite.

References:
- https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents/commit
- https://firebase.google.com/docs/firestore/reference/rest/v1/Precondition

## Exact first-sync write set
N owned cars produce N+5 operations. Every operation is an update/upsert with transforms, no deletes. Names are fully qualified under projects/{project}/databases/(default)/documents. The root is absent before the atomic commit and present in its post-write state. UID comes from the authenticated identity, is checked by the provider, and appears in the path; no redundant UID field is required or added.

| Path | Payload and revision | Server transforms | Rule |
|---|---|---|---|
| users/{uid} | profile display_name/email/provider/is_guest, schema_version=5, wallet coins, level, XP, selected_car; save_revision=1 and snapshot digest | updated_at, last_login_at, created_at | /users/{uid} create: owner(uid), validRoot(), revision=1 |
| users/{uid}/progression/main | local progression: XP, career stats, achievements, missions, daily metadata; no per-child revision field | updated_at | /users/{uid}/{section}/{id}; progression allowlist, owner(uid), root getAfter updated_at=request.time |
| users/{uid}/inventory/main | consumable inventory, including Turbo, Repair, Magnet, Shield; no per-child revision | updated_at | same child rule; inventory |
| users/{uid}/meta/main | settings, onboarding, wallet ledger, purchase claims, membership cache, upgrade-ad metadata; no per-child revision | updated_at | same child rule; meta |
| users/{uid}/cars/{owned_car_id} | owned, custom_name, paint_index, upgrades; no per-child revision | updated_at | same child rule; cars |
| users/{uid}/transactions/{snapshot_digest} | source=offline_snapshot, reward_id=digest, run_id from settled_run, save_revision=1 | created_at | same child rule; transactions |

New accounts write owned cars only, not all locked cars. Legacy snapshot layout remains supported. Snapshot claims/cache are backup data, not authority to issue purchases or memberships. No credentials are written. Root coins and XP/level mirrors are existing mappings, unchanged.

## Rule/payload audit
Root create uses request.resource.data, not missing resource.data. Updates require the stored revision plus one. Child rules already use getAfter(), so the newly created parent can authorize children in the same atomic commit. There is no mismatched UID field or strict field allowlist. Schema, revision and coins encode as integerValue, including whole JSON floats. Coin bounds remain 0..2,000,000,000. updated_at uses REQUEST_TIME, matching request.time. Root updateMask preserves created_at on later saves; audit is allowed by the existing child section list. One denied operation still rejects the entire commit.

Under the included rules, same-UID valid bootstrap is permitted, other-UID and unauthenticated writes are denied, and children remain owner-only. Local revision 0 / missing root safely becomes revision 1. No security rules were changed or deployed. Client-authoritative offline coin/XP values are not made cheat-proof by these rules; high-value or competitive authority still belongs behind verified provider/backend boundaries.

## Files and preservation
Only implementation file changed: Account/FirebaseRestProvider.gd.
Added documentation: Docs/FirestoreFirstWriteFix.md.
SaveService, Schema 5 float compatibility, safe recovery, AuthService, CloudSaveService, native bridge, config, Kotlin 2.1.0, UI/touch, gameplay/economy and owner rules are byte-identical to the input project.

AAR rebuild NOT required. Re-export the APK manually using your existing working AAR. This full source ZIP deliberately contains neither your locally generated android/build nor a replacement RushFirebaseBridge.aar. Merge into your current project; do not delete those local artifacts or saves. The existing BUILD_REQUIRED.md is generic historical setup guidance, not a rebuild requirement for this patch.

## Static validation
All 101 GDScript files parsed with gdtoolkit. This is a grammar check, not a Godot compiler/runtime test. Source review checked atomic preconditions, exact endpoints, bearer/JSON headers, fully qualified same-user paths, field encoding, root mask, transforms, failure routing and preservation hashes. Rules received source review only, not emulator/deployment evaluation.

## Expected successful next-device sequence
```text
CLOUD_RECONCILIATION_START
FIRESTORE_BOOTSTRAP_START
FIRESTORE_READ_START
FIRESTORE_READ_HTTP_STATUS:200
FIRESTORE_USER_DOC_EXISTS:false
CLOUD_SYNC_UPLOAD_START
FIRESTORE_WRITE_PRECHECK_START
FIRESTORE_WRITE_PRECHECK_HTTP_STATUS:200
FIRESTORE_USER_DOC_CREATE_START
FIRESTORE_WRITE_STAGE:FIRST_BOOTSTRAP
FIRESTORE_WRITE_OPERATION_COUNT:<N+5>
FIRESTORE_WRITE_HAS_ROOT:true
FIRESTORE_WRITE_HAS_PROGRESSION:true
FIRESTORE_WRITE_HAS_INVENTORY:true
FIRESTORE_WRITE_HAS_META:true
FIRESTORE_WRITE_HAS_AUDIT:true
FIRESTORE_WRITE_HAS_CARS:true
FIRESTORE_WRITE_START
FIRESTORE_WRITE_HTTP_STATUS:200
FIRESTORE_WRITE_RESULT:SUCCESS
FIRESTORE_USER_DOC_CREATE_SUCCESS
CLOUD_SYNC_UPLOAD_SUCCESS
CLOUD_RECONCILIATION_RESULT:SYNCED
```
Generic FIRESTORE_HTTP_STATUS and existing reconciliation markers may appear between these. SYNCING can follow acknowledgment if local changes are still pending. Failed prechecks are distinct from commit HTTP status; no commit success is printed before an accepted commit response. Safe failure codes include PERMISSION_DENIED, UNAUTHENTICATED, CONFLICT, RATE_LIMITED, SERVER_ERROR, TRANSPORT and MALFORMED_RESPONSE; no payloads/UIDs are logged.

## Remaining manual checks
Cloud save is not yet runtime-proven. Re-export/install manually without replacing the working AAR, then confirm commit success AND actual documents. Verify subsequent read sees root/revision, later update advances revision, restart restores safely, concurrent clients conflict rather than overwrite, retry does not duplicate settlement, offline saves remain intact. A different deployed rule set or further server rejection can still block commit; the new diagnostics identify that stage. No Godot, Android, emulator, APK export or Firebase Console action was performed here.
