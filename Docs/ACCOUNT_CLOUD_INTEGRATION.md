# Velocity Rush 3D — account, cloud and menu integration

Source-level integration completed on the current corrected project tree. No Godot, Android, APK export, native build or device test was run. All 101 GDScript files passed gdtoolkit grammar parsing; this is not Godot compilation or runtime verification.

## Delivery and installation

The full ZIP contains the complete maintained project source, assets, scenes, data, tools, native bridge source and export configuration, including the preceding handshake, configure diagnostics, strict Boolean true/integer 1 acceptance and Gradle import repair.

Extract the `VelocityRush3D` folder over your existing project after making a backup. Keep your existing `android/build` directory and working `addons/rush_firebase/bin/RushFirebaseBridge.aar`. Those locally generated files were not supplied in their latest working form and are not replaced by an older AAR in this archive. No local `user://` save files are included or reset.

**AAR rebuild not required.** Native/Kotlin files did not change. Re-export the APK manually using your existing working native AAR.

## Changes by issue

| Issue / source finding | Integrated change | Files |
|---|---|---|
| Logout previously remembered Guest choice and emitted login completion; no login navigation occurred. | Confirmed sign-out clears native/session state, persists logged-out choice, emits auth state change, routes to Welcome and dismisses notices. A central screen gate prevents stale Back navigation from reopening menus until Google or Guest is chosen. | Account/AuthService.gd, Account/AccountUI.gd, UI/AutomotiveUI.gd |
| Link action was unconditional. | Reactive account cards show Google Connected and actual AuthService email; linked accounts have no link button. Guest cards offer linking. Settings and Profile share centralized state. | Account/AccountUI.gd, Account/AuthService.gd |
| Welcome was a plain centered column. | Existing highway artwork, dark panel, typography, readable Google/Guest buttons, press animation, fade and scrollable safe-area layout. | Account/AccountUI.gd, UI/AutomotiveUI.gd |
| Cloud status was marked OFFLINE immediately on account change, before any HTTP request; retry delay could survive account changes. | Show pending/syncing when authenticated; reset old retry delay on new identity; initialize account reconciliation even if an earlier auth signal was missed. Add stage, HTTP and response-validation diagnostics. | Account/CloudSaveService.gd, Account/FirebaseRestProvider.gd |
| Touch scrolling relied only on mouse-filter propagation; sliders consumed gestures and some bounded panels had no overflow handling. | Shared touch gesture arbitration, drag-to-scroll over cards/rows, delayed taps to prevent drag purchases, horizontal slider routing, bounded inertia and nested-scroll avoidance. Garage tab panels and centered menus now have scroll containers. | UI/TouchScroll.gd, UI/AutomotiveUI.gd, Garage/GarageUI.gd |
| Default steering ID was 0, which means Wheel. Invalid numeric values were clamped into another mode. | New/missing/invalid mode uses Buttons ID 1. Existing valid 0/1/2 remains untouched, including after restart. | Save/SaveService.gd |
| Account state was only a generic profile label. | Profile and Settings show Guest/Google, real email, actual cloud state, link option where eligible, and confirmed Sign Out. | Account/AccountUI.gd |

## Firestore findings and limits

**The exact device-side cause of an empty Firestore database is not established by the supplied authentication logs.** No missing Firebase ID-token propagation or missing first-document bootstrap was found. Bearer headers, owner UID checks, server timestamps and transactional root/child creation were already implemented.

The prior OFFLINE marker was not proof of a transport failure: it was emitted while scheduling an authenticated account's first read. That misleading state is corrected. Existing HTTP failures generally became ERROR, but their causes were discarded. New internal categories distinguish 401 authentication, 403 permission, 404 endpoint/not-found, 409 conflict, 429 throttling, 5xx server, malformed responses, and actual network failures. Only recognized network failures become OFFLINE; no rules or Console settings were changed.

Flow remains: authenticated identity → authorized batch read → compare saved revision/digest → atomic creation/upload or safe restore → SaveService acknowledgement. Missing roots are created with revision 1 and server timestamps inside the same transaction as progress and audit documents. Root deletion, concurrent revisions, account collisions and unsafe restores remain protected. New accounts write owned cars only; previously synchronized legacy all-car snapshots remain compatible. No locked-car documents are eagerly created for new accounts.

Safe diagnostics include CLOUD_AUTH_AVAILABLE, CLOUD_UID_AVAILABLE, CLOUD_ID_TOKEN_AVAILABLE, FIRESTORE_BOOTSTRAP_START, CLOUD_REMOTE_READ_STATUS, FIRESTORE_HTTP_STATUS, FIRESTORE_REQUEST_FAILED, FIRESTORE_READ_FAILED, FIRESTORE_USER_DOC_EXISTS, create start/success/failure, local/remote revisions, upload/download success and reconciliation result. No headers, tokens, UID, email or response bodies are logged.

## Preserved / static checks

- AndroidCredentialBridge.gd is byte-identical to the working return fix: exact capability handshake; bool true or int 1 only; no has_method fallback.
- Kotlin Android plugin remains 2.1.0. Native exports, configure validation, Credential Manager, Keystore and cancellation are unchanged.
- FirebaseConfig identity values, package identity, native/build source and configuration are byte-identical.
- Save Schema 5 retained. Existing saves, rewards, economy, vehicle/input/traffic/camera code, Store, multiplayer and tournaments were not changed.
- All 101 GDScript files passed grammar parsing; literal resources and scene references resolved, autoload/global-class names were checked for duplicates. No engine type-check or visual/device test is claimed.

## Mobile pages covered

Shared scrolling covers Settings (including controls/account section), Profile, Missions/Achievements, Daily Rewards, Store tabs, Garage tab content, Results, Welcome and centered menu pages. Nested tournament lists retain inner gesture ownership; online logic was not modified. Gameplay HUD and driving touch regions are not scroll containers.

No existing Terms/Privacy/Help routes or official Google logo asset were found. The welcome screen uses text-only Google identification and an explanatory privacy note; it does not invent legal links or ask agreement to nonexistent policies.

## Manual tests

1. Re-export using the current working AAR; verify Google login still reaches FIREBASE_IDP_SUCCESS.
2. Fresh/no-value settings: Buttons. Change to Wheel/Tilt; restart and verify persistence.
3. Login: Profile and Settings show actual email and Connected, no link action. Cloud status is not falsely Synced.
4. Allow the first sync to run; inspect HTTP/read/commit diagnostics and Firestore root plus inventory/progression/owned-car/audit documents. Test offline, permission-denied and existing newer/concurrent cloud data separately.
5. Confirm logout; Welcome appears, Back stays there, local progress is retained. Login again and verify account/cloud state.
6. Drag Settings from blank rows, buttons and sliders. Vertical drags scroll; horizontal slider gestures adjust. Drags must not activate purchases/options. Check inertia, taps and desktop mouse wheel.
7. Check long pages and garage tabs at 16:9, 18:9, 19.5:9 and 20:9, including safe areas and all bottom controls. Verify driving multitouch separately.

Remaining uncertainty: actual Firestore transport/permissions outcome, Android touch arbitration, visual fit and Godot type/runtime checks require your manual testing. Latest locally generated Android build/AAR artifacts remain on your PC and should be retained.
