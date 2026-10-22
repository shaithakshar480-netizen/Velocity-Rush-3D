# Cloud precheck investigation — latest integrated source

## Conclusion

No single runtime cause is statically proven. There are exactly two explicit CloudSaveService exits matching the supplied sequence with no FIRESTORE_BOOTSTRAP_START: unavailable provider, or an empty committed local snapshot. This pass adds diagnostics rather than manufacturing an authentication, network, permission or save repair.

## Early-exit trace

| Function / file | Condition before provider entry | Result | Distinguished by old log? |
|---|---|---|---|
| CloudSaveService.sync — Account/CloudSaveService.gd | `not AuthService.provider.available()` | ERROR; 60-second retry delay | No |
| CloudSaveService.sync → snapshot → SaveService.cloud_envelope → _read(PATH) | `docs.is_empty()` because `_read` returned an empty dictionary | `failed()` → ERROR, unless the retained provider error is TRANSPORT (then OFFLINE); exponential retry | No |

Provider availability expands into: REST init state must be READY, its host Node must remain valid, and required App Check must have a callable. The default FirebaseProvider always returns unavailable. None of these conditions is changed or bypassed.

The snapshot reader returns empty for missing primary settings file, open failure, JSON not accepted as a dictionary, unsupported schema version, absent/non-dictionary settings, or a present non-dictionary wallet. Cloud reads committed `settings.json`; unlike startup recovery, it does not choose the backup or pending file. No recovery/commit behavior was changed because the log does not prove such a failure. Snapshot schema acceptance diagnostics describe this existing reader contract, not a new full-data validator.

There is **no local-revision rejection before provider entry**. A missing revision is normal for the first sync. Remote/base revision checks occur only after the remote read. A malformed nested snapshot could cause a script error, but that is not either explicit ERROR return shown above.

## Downstream branches before the first HTTP request

These cannot explain ZERO bootstrap markers in the stated source, since `fetch_save` prints FIRESTORE_BOOTSTRAP_START first:

| Function | Early branch | Result |
|---|---|---|
| FirebaseRestProvider.fetch_save | Firestore already busy; empty UID; UID differs from provider identity | false callback → cloud failure; now REQUEST_BUSY or AUTH_CHANGED marker |
| _authorized → _refresh | ID token absent/expired and no refresh token | false callback → cloud failure; now NO_TOKEN or SESSION_AUTHORIZATION_FAILED |
| _refresh → _http | Provider unavailable or request limit reached | false callback → cloud failure |
| _http | App Check rejects/missing required callback; request fails to start | false callback → cloud failure |
| asynchronous request guards | generation changed/stale callback | Callback ignored; does not itself emit ERROR. The cloud timeout can fail only if its epoch remains current and busy. |

A 50-second cloud timeout is installed after fetch_save is called, so that path also requires an earlier bootstrap marker. HTTP-response parsing, permissions and revision/restore failures are later still and cannot be the first explanation for the supplied negative evidence.

## Token and provider trace

`_google_exchange` → `_accept` validates a nonempty `idToken`, stores it in the REST provider's `id_token`, and sets the provider identity before FIREBASE_IDP_SUCCESS. AuthService receives only public identity fields and then emits AUTH_STATE_UPDATED. CloudSaveService uses the current `AuthService.provider` directly; it never copies or reads a token from AuthService.user. The same REST instance authorizes Firestore, refreshing where needed, and constructs the Bearer header internally.

Therefore the token was present when Firebase authentication was accepted. Its presence at the later failing sync is not proven by the old log. No wrong-key lookup, stale cached provider reference, or normal-flow provider replacement after success was found. AuthService's explicit configure(adapter) hook clears its public identity; no project caller uses it to replace a successful provider. No token flow or binding changes were made.

## Files changed

- Account/CloudSaveService.gd — precheck diagnostics; diagnostic snapshot flag; signed-out status/ephemeral cloud cleanup.
- Account/FirebaseProvider.gd — diagnostic-only virtual method returning Boolean state, never credentials.
- Account/FirebaseRestProvider.gd — diagnostic state implementation and reason markers on existing fetch/authorization failure exits.
- Docs/CLOUD_PRECHECK_INVESTIGATION.md — this report.

## New diagnostic sequence

After CLOUD_SYNC_START, CLOUD_AUTH_AVAILABLE and CLOUD_UID_AVAILABLE:

- CLOUD_ID_TOKEN_AVAILABLE
- CLOUD_PROVIDER_AVAILABLE
- CLOUD_PROVIDER_CONFIGURED
- CLOUD_PROVIDER_SUPPORTED
- CLOUD_PROVIDER_HOST_AVAILABLE
- CLOUD_PROVIDER_APP_CHECK_READY
- CLOUD_PROVIDER_IDENTITY_MATCH
- CLOUD_PROVIDER_REQUEST_BUSY
- CLOUD_LOCAL_REVISION_AVAILABLE

Each has a Boolean suffix. Provider rejection is followed by:

`CLOUD_RECONCILE_PRECHECK_FAILED:INVALID_PROVIDER|PROVIDER_NOT_CONFIGURED|PROVIDER_HOST_UNAVAILABLE|APP_CHECK_UNAVAILABLE|UNSUPPORTED_STATE`

If provider entry is allowed, snapshot diagnostics follow:

- CLOUD_LOCAL_SAVE_FILE_EXISTS
- CLOUD_LOCAL_SNAPSHOT_AVAILABLE
- CLOUD_LOCAL_SNAPSHOT_VALID

An empty snapshot prints NO_LOCAL_SNAPSHOT if the primary file is absent, or INVALID_LOCAL_SNAPSHOT if present but unreadable/rejected, before the existing failure handler. No data contents or paths from user input are printed. Existing revision logic is unchanged; no missing-token bypass or forced upload was added.

If the prechecks pass, expect CLOUD_RECONCILIATION_START → FIRESTORE_BOOTSTRAP_START → existing token/HTTP/read diagnostics. This diagnostic-only pass does not guarantee that an unknown failed precondition now passes.

## Logout and safety

Logged-out/local-only cloud state is now NOT_CONNECTED instead of OFFLINE. This is an additive status string consistent with the UI's existing “Not connected” presentation; no auth navigation or UI script changed. Empty identity clears the in-memory account UID, busy/fetching/conflict flags and invalidates old epochs. Persisted ownership/revision/digest markers remain intact. AuthService already cancels provider requests and clears tokens at sign-out; those methods are unchanged. A later account cannot silently inherit another user's cloud ownership.

Revision/digest/transaction guards, idempotency, timestamps, safe restore, owner checks and owned-car-only new saves are unchanged. AndroidCredentialBridge.gd, native/Kotlin/build source, auth service, SaveService/Schema 5, Firebase config, Firestore rules, UI/touch/controls, gameplay and economy are unchanged from the preceding integrated tree. Kotlin remains 2.1.0.

**AAR rebuild is NOT required.** Keep your locally generated working android/build and addons/rush_firebase/bin/RushFirebaseBridge.aar. The full ZIP includes maintained project source/assets and every prior source fix; it does not replace these generated files with an older binary.

## Verification and next manual test

Static grammar/resource checks only; no Godot, Android, APK export, native build or device run. These checks are not Godot type checking or runtime success.

Re-export manually using your working AAR, sign in, and capture one complete sync attempt including the new precheck markers. That log will establish which candidate fails and whether the token remains available. Also confirm logout retains its four existing navigation markers and now logs CLOUD_RECONCILIATION_RESULT:NOT_CONNECTED, rather than OFFLINE.
