# Current native integration

Real client configuration and Credential Manager/Keystore bridge source are now supplied. See FIREBASE_ANDROID_BRIDGE.md for current build/setup requirements; the historical optional-hook notes below describe the same provider boundary. Native AAR compilation remains pending.

# Firebase REST provider and safe restore — source-only delivery

## Detected integration
No third-party addon was present; the project now includes its own v2 native bridge source. FirebaseRestProvider implements the documented Firebase Authentication and Firestore HTTPS APIs using Godot HTTPRequest. It initializes once from Data/FirebaseConfig.json via AuthService; states are UNCONFIGURED / INITIALIZING / READY / ERROR. No network calls were made to a Firebase project during implementation. Client configuration was subsequently supplied; no credentials were invented.

## Configure the separate Android project
Retain package `com.velocityrush3d.game`. Supply your separate Firebase project ID, app ID, client API key and OAuth request URI in Data/FirebaseConfig.json, then enable configured. Enable Google and Anonymous Authentication plus Firestore. Android Google configuration/SHA fingerprints must match your signing certificates. Firebase client configuration is not a service-account secret; never place service-account credentials or refresh tokens in this file.

The REST adapter does real anonymous signup, Google ID-token exchange, linking via the existing Firebase ID token, secure-token refresh, account lookup, Firestore consistent snapshot reads and transaction commits. There is no fake success path.

## Native platform hooks still required
No addon API is assumed. Supply these explicitly on the initialized `AuthService.provider as RushFirebaseRestProvider`, before AccountUI.launch:
- `google_token`: Callable taking callback(bool, String). Obtain a real Google ID token through your Android Credential Manager/native plugin using the configured OAuth client. Invoke callback once; false for cancel/failure. Do not return a Firebase token in this slot.
- `secure_load`: Callable returning the stored Firebase refresh token or empty string.
- `secure_save`: Callable taking a refresh token and returning bool; store using Android Keystore-backed storage.
- `secure_clear`: Callable clearing only this account's credentials.
- `google_sign_out`: Callable clearing your native Google credential session.
- `app_check`: Callable taking callback(bool, String), supplying a real App Check token; refresh through the native SDK.
These are application-owned hook contracts, not claimed methods of an installed addon. Without Google credentials, Google login reports unavailable/failure. Without secure storage, tokens remain memory-only and cannot restore sessions after relaunch. No plaintext token persistence is supplied. Guest identity is never recreated automatically after a previously linked cloud identity fails restoration.

Production should use `require_app_check=true`: requests then remain unavailable without the hook. The current supplied config explicitly permits development without App Check. For a development Firebase project where enforcement is not enabled, explicitly setting it false permits REST requests without App Check. It never simulates attestation. Enable Play Integrity and enforcement through Firebase before production.

## Firestore protocol
users/{uid} is the profile/root; cars/{id}, inventory/main, progression/main and meta/main hold bounded structured sections. A batchGet read-only transaction obtains a consistent snapshot; decoded documents must match the canonical root digest. compare_and_set starts a read-write transaction, reads root revision, then atomically writes all sections, revision+1 and transactions/{digest}. updated_at and created_at use server transforms. Identical content retries acknowledge the existing revision without additive economy writes. Run IDs, reward/achievement/daily claims, ad markers and hashed purchase claim IDs travel with their corresponding data. No raw purchase tokens are uploaded. Profile and game names remain separate from Google identity.

Deploy Account/firestore.rules after reviewing/testing. They isolate authenticated owners, disallow deletion and require root revision/server-time metadata. This is offline backup validation, not anti-cheat: a modified client can still fabricate its own progress. Paid purchase verification, membership authority, tournament payouts and online transport remain in their existing boundaries.

## Reconciliation
A: no cloud and no previous binding → upload local.
B: genuinely new local progress + valid cloud → validated restore when safe.
C: cloud revision equals last acknowledged revision → upload locally changed snapshot using compare-and-set.
D: cloud advanced and local digest still equals its last synchronized state → validated restore.
E: local and cloud changed, cloud revision regressed/deleted, account changed, credential collision or invalid restore data → CONFLICT, retaining local and remote copies. No clocks, max or sum merges determine economy.

Newness excludes earned/spent coins, runs, XP, custom names/paint/upgrades, purchases, inventory beyond the starter grant and claimed daily/achievement rewards. Missing fields preserve local values; invalid types reject restoration. Economy data requires replay ledgers. Level is derived from XP. Restore takes a recovery copy at user://settings.before_cloud.json, validates all sections, and commits through SaveService. Revision/owner/local digest are stored atomically in an optional cloud_meta field inside schema 5. The older cloud_sync.cfg owner binding is migrated conservatively. No schema reset is required.

Restoration is deferred outside Home/Profile/Account and while transactions, races, unsettled results or purchase/ad callbacks are pending. Auth and cloud callbacks use generation guards. Local edits during a fetch prevent overwrite. Restore emits state refresh signals without running reward grant or celebration paths. Failed commits roll back; requests use controlled retry/backoff. Failed login does not block offline Guest.

## Manual validation
No Godot, Android, emulator or device tests were run. Connect the native hooks/config and verify actual Auth/Firestore responses, Google picker/cancel, anonymous/session restoration, link collision, sign-out during requests, server-time writes, rules isolation, duplicate callbacks, retries, new-device restore, partial/malformed documents, two-device concurrent saves, app exit during restore and schema-5 preservation. Verify claims are not reissued after restoration. Native secure storage and App Check integration remain required; no real account connection is claimed.

## Official protocol references
- [Firebase Authentication REST](https://firebase.google.com/docs/reference/rest/auth)
- [Firestore batchGet](https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents/batchGet)
- [Firestore commit](https://firebase.google.com/docs/firestore/reference/rest/v1/projects.databases.documents/commit)
- [Firestore writes and server transforms](https://firebase.google.com/docs/firestore/reference/rest/v1/Write)
- [Google authentication on Android](https://firebase.google.com/docs/auth/android/google-signin)
- [Android App Check](https://firebase.google.com/docs/app-check/android/play-integrity-provider)
