# Firebase native bridge — source-level integration

## Supplied configuration
The exact supplied client JSON is stored once at `Config/Firebase/google-services.json`. `Data/FirebaseConfig.json` is derived from its package-matching client; its API key comes from current_key, not a fabricated value. `Tools/import_firebase_config.py` can reimport future supplied changes without logging credentials. Package remains com.velocityrush3d.game; Google token audience comes exclusively from web_client_id. The Android OAuth client is registration metadata, not the server audience.

There was no native Android project/custom build template or Google Services Gradle integration in the supplied project. This bridge uses Credential Manager plus the existing Firebase REST transport, so it does not consume JSON through the Google Services Gradle plugin. Do not copy it into random module folders. If adding native Firebase SDKs later, the standard plugin consumes google-services.json in the application module root—normally android/build/google-services.json for Godot's installed custom build—and that module must apply com.google.gms.google-services. That integration is not claimed active here.

`oauth_request_uri=http://localhost` follows Firebase's documented ID-token exchange example. It does not start a localhost server or substitute for an OAuth redirect/client registration. Native Credential Manager obtains the Google token; Firebase validates it.

## Build steps still required (not run here)
1. Use Godot's matching 4.7.2 Android build/export templates; install the Android build template in this existing project. Do not create a replacement game project. Internet and Gradle export are enabled in the existing preset; package, architecture and existing target configuration are retained.
2. Open `Native/FirebaseBridge` as the standalone plugin library source. It uses JDK 17, Gradle 8.2 and AGP 8.2.2. No wrapper binary is fabricated. Supply the actual matching Godot Android AAR from your engine release/template with `-PgodotAar=...`. Do not substitute an unrelated engine version.
3. With a local Gradle 8.2 installation, run from Native/FirebaseBridge:
   `gradle :bridge:installBridge -PgodotAar="/absolute/path/to/matching/godot.aar"`
   This builds/copies `addons/rush_firebase/bin/RushFirebaseBridge.aar`. It was deliberately not built in this source-only pass. Android export requires that artifact; missing it is a build blocker, not a working native login.
4. The enabled Godot v2 export plugin adds the AAR plus Credential Manager 1.3.0, Play Services credential auth 1.3.0, googleid 1.1.1 and coroutines 1.7.3. Dependencies are pinned equally in Gradle and export code. Plugin compileSdk defaults 34; if the matching engine AAR requires a higher compile SDK, pass bridgeCompileSdk accordingly. This does not change the app Target SDK. Bridge minSdk is 23 for Keystore AES/GCM, so the custom app build must support API 23 or above.
5. Verify the externally configured SHA fingerprints match the actual debug/release signing certificate and supplied Android OAuth registration. Build/export and device testing are left to you as requested.

## Runtime wiring implemented
AuthService initializes FirebaseRestProvider once, creates AndroidCredentialBridge and detects the built RushFirebaseBridge singleton. The bridge validates package/configuration and attaches Google picker, cancellation, secure load/save/clear and Google session clearing callables before account launch. Missing native plugin leaves Google unavailable and preserves local Guest.

CONTINUE WITH GOOGLE → Credential Manager's explicit Google button flow → real Google ID token with Web-client audience and nonce correlation → existing Firebase signInWithIdp → existing AuthService identity and asynchronous cloud reconciliation. Firebase remains the verifier. Cancellation produces a clean cancellation message without advancing the account screen. Anonymous-to-Google linking still passes the anonymous Firebase token and refuses credential collisions.

Native callbacks carry request IDs, are delivered to GDScript deferred, and are invalidated on cancellation, timeout/sign-out and activity destruction. The native layer never logs tokens or SDK exception payloads. It does not contain Firebase Auth/Firestore logic.

## Token storage
Refresh tokens are AES-256/GCM encrypted using Android Keystore keys and AtomicFile in noBackupFilesDir. Only encrypted bytes and a non-secret revocation flag are persisted. Sign-out deletes the ciphertext/key and marks the session revoked. ID tokens/Google credentials remain transient. Unavailable or invalidated Keystore reads return empty; gameplay saves are untouched. Keystore encryption failures do not fabricate a persistent session. Storage failure/reinstallation and signing changes need physical-device verification.

## App Check
This configuration explicitly uses development mode (`require_app_check=false`); it does not disable any Firebase server enforcement. If enforcement is already enabled remotely, requests without App Check will fail safely. AppCheckProvider is a typed, once-only callback boundary for a later real native App Check token source. Attach it to the REST provider and set require_app_check=true for production once Play Integrity is configured. No token simulation or debug App Check provider is present.

## Verification scope
Source/config checks only: exact JSON import, OAuth client selection, GDScript structure, native/GDScript method and signal matching, XML manifest, Gradle/export dependency consistency, token logging search, resource paths and protected-source hashes. No Kotlin/Godot compilation, Gradle build, Firebase login, Android export, emulator or device tests were run.

Manual tests: picker success/cancel/retry; Web audience/SHA rejection; anonymous offline fallback; guest link/collision; refresh after relaunch; secure sign-out; token expiry; activity recreation; late callbacks; server rules; cloud restore/conflicts; regression check of schema-5 progress.

Official references: [Godot v2 plugins](https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html), [Credential Manager Google flow](https://developer.android.com/identity/sign-in/credential-manager-siwg-implementation), [Android Keystore](https://developer.android.com/privacy-and-security/keystore), [Firebase REST](https://firebase.google.com/docs/reference/rest/auth).
