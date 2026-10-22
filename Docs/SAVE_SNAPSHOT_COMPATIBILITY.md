# SaveService/cloud snapshot compatibility fix

## Proven source bug

The writer serializes `schema_version: 5`. Godot JSON parses numbers as floats; the old reader used `result.get("schema_version",0) in [1,2,3,4,5]`. Godot Array membership is type-sensitive, so float 5.0 does not match integer 5. The old reader therefore rejects the project's own valid serialized save and returns `{}` to `cloud_envelope()`, preventing Firestore entry.

The corresponding rejection is SCHEMA_UNSUPPORTED under the old membership rule. This is a definite source-level contract bug, not an OAuth, permission or network problem. The actual device settings.json was not supplied, so additional corruption/open failures in that particular file cannot be ruled out.

Official references:
- [Godot 4.7 JSON number parsing](https://docs.godotengine.org/en/4.7/classes/class_json.html)
- [Godot 4.7 Array.has / in type-sensitive membership](https://docs.godotengine.org/en/4.7/classes/class_array.html#class-array-method-has)

## Exact fix

Only Save/SaveService.gd changes production source.

1. `_read()` accepts only numeric, finite, integral schema versions in the inclusive range 1–5. Conversion to int happens after validation. Strings, Boolean values, fractional values and unsupported versions remain rejected. Valid data fields are not discarded by this conversion.
2. Reader diagnostics distinguish file/open/JSON/root/schema/settings/wallet/known-section failures without logging contents, parser error text, identifiers or credentials. Known wallet/inventory counters and core progression/collection shapes receive fail-closed type checks before migration.
3. Existing startup recovery still chooses primary, then backup, then pending. Recovered or supported older/incomplete envelopes are normalized through the existing loaders and committed with the existing TEMP → primary atomic sequence before cloud can consume them. A sole valid pending file is copied to backup before TEMP is reused. Unknown dictionary fields are retained across commits, including nested extensions; recognized gameplay fields remain authoritative.
4. If all existing save candidates are invalid, writes are blocked rather than replacing those files with defaults. This preserves files for recovery; it does not claim damaged data was recovered.
5. `cloud_envelope()` reads committed primary state only and requires canonical Schema 5 sections. It never uploads in-flight runtime state or independently chooses a backup. A failed migration leaves cloud sync blocked until canonical persistence succeeds.

No schema number increase, new revision, reward grant, reset or default save replacement was introduced. A valid complete Schema-5 primary requires no migration/rewrite merely to become readable. Older accepted saves use the existing normalization rules; their canonical commit retains unknown dictionary extensions and a recovery copy. Data absent from all available files cannot be reconstructed by this fix.

## Writer/reader audit

The production writer is SaveService.commit(), which JSON-serializes the canonical envelope to settings.pending.json, flushes/closes it, preserves a readable previous primary as backup, then renames TEMP to settings.json. No alternate production writer to the primary was found. Tests contain fixture writers but are not production navigation. AuthService's ConfigFile writes target account.cfg, not settings.json.

Field names and wrapper structure already matched: schema_version, settings and wallet were not renamed or nested elsewhere. The mismatch was numeric Variant membership. Startup and cloud used the same reader, so both were affected. Recovery selection differs intentionally; this pass commits recovered state through SaveService rather than creating another cloud recovery mechanism.

## Envelope categories

| Category | Existing data retained |
|---|---|
| Coins | wallet.coins plus run settlement/receipt ledger |
| XP / level | progression XP, normalized progression data and derived cloud profile level |
| Profile / statistics | progression name, stats and career records |
| Cars / upgrades | collection ownership, selected car, names, paints, upgrades and upgrade-ad metadata |
| Inventory | consumables: Turbo, repair, magnet, shield and reward counters |
| Achievements / daily challenges | progression achievement claims/notices and daily progression/reward metadata |
| Settings | settings, including existing valid control preference |
| Other persisted safety state | onboarding, membership cache, store_claims and cloud_meta |

CloudSaveService's existing document mapping remains unchanged. New cloud accounts still create owned-car documents only. Tokens are still held by the provider/secure storage, not added to this envelope.

## Safe diagnostics

LOCAL_SAVE_OPEN_SUCCESS
LOCAL_SAVE_JSON_PARSE_SUCCESS
LOCAL_SAVE_ROOT_IS_DICTIONARY
LOCAL_SAVE_SCHEMA_PRESENT
LOCAL_SAVE_SCHEMA_TYPE
LOCAL_SAVE_SCHEMA_VALUE (only a validated integer 1–5)
LOCAL_SAVE_SCHEMA_SUPPORTED
LOCAL_SAVE_SETTINGS_PRESENT
LOCAL_SAVE_SETTINGS_IS_DICTIONARY
LOCAL_SAVE_WALLET_PRESENT
LOCAL_SAVE_WALLET_IS_DICTIONARY
LOCAL_SAVE_MIGRATION_REQUIRED
LOCAL_SAVE_MIGRATION_SUCCESS (when a migration/recovery commit is attempted)
LOCAL_SAVE_ACCEPTED

LOCAL_SAVE_REJECTED reasons: FILE_MISSING, OPEN_FAILED, JSON_PARSE_FAILED, ROOT_NOT_DICTIONARY, SCHEMA_MISSING, SCHEMA_UNSUPPORTED, SETTINGS_MISSING, SETTINGS_WRONG_TYPE, WALLET_WRONG_TYPE, SECTION_WRONG_TYPE, PROGRESS_WRONG_TYPE, NO_VALID_RECOVERY, MIGRATION_FAILED, MIGRATION_REQUIRED, CANONICAL_SECTION_INVALID.

These reader markers can also appear during startup and atomic backup checks. They contain no save payloads. A missing wallet remains compatible with supported earlier envelopes; startup supplies the existing migration defaults before canonical cloud use.

## Expected next device sequence

For a valid current save:

```
LOCAL_SAVE_SCHEMA_TYPE:float
LOCAL_SAVE_SCHEMA_SUPPORTED:true
LOCAL_SAVE_SCHEMA_VALUE:5
LOCAL_SAVE_ACCEPTED
CLOUD_LOCAL_SNAPSHOT_AVAILABLE:true
CLOUD_LOCAL_SNAPSHOT_VALID:true
CLOUD_RECONCILIATION_START
FIRESTORE_BOOTSTRAP_START
```

First-sync CLOUD_LOCAL_REVISION_AVAILABLE:false remains valid. The authenticated remote read, revision comparison, digest checks and transactional bootstrap still happen before any upload. Firestore HTTP results are not known until the user's next device test.

## Verification / preserved systems

All 101 GDScript files passed static grammar parsing. Offline schema-policy fixtures modeled documented float JSON parsing and type-sensitive old membership: versions 1–5 accepted by the corrected rule; Boolean/string/fractional/out-of-range/non-finite cases rejected. These are source/policy checks, not execution of Godot save migration or filesystem crash recovery.

Source hashes confirm all other existing files unchanged, including Firebase providers, AuthService, AndroidCredentialBridge.gd, Kotlin/build files, Firestore rules, Firebase config, UI/TouchScroll and gameplay. Schema remains 5. Cloud revision/conflict/ownership/restore protections, logout navigation and NOT_CONNECTED status remain intact. Kotlin remains 2.1.0.

**AAR rebuild NOT required.** No Godot, Android, native build, APK export or device test was run.

## Delivery and manual checks

Full maintained source project ZIP, including all previous fixes. Merge over the existing project; retain the locally authoritative android/build directory and addons/rush_firebase/bin/RushFirebaseBridge.aar. No older generated AAR is included.

Back up the app's local save through your existing development procedure before manual testing; do not clear app data. Re-export using the existing working AAR. Verify existing coins, XP, names, cars, upgrades, inventory and claims survive restart; inspect the new schema/snapshot/Firestore sequence. Test migration/recovery with separate disposable copies of older/corrupt fixtures, never by corrupting the real player save. Runtime acceptance, disk recovery and actual Firestore success remain unverified.

Files: Save/SaveService.gd; Docs/SAVE_SNAPSHOT_COMPATIBILITY.md (this report).
