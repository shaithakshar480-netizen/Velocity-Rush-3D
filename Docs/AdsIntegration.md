# Android ads integration — source delivery

No Godot, Android, Gradle build, emulator or runtime tests were run. The new Ads
AAR is deliberately NOT fabricated. Until it is built/installed and the APK is
exported, ads report unavailable; all offline gameplay continues normally.
Firebase source, its AAR and android/build are untouched.

## Build once using your existing toolchain

Java 17, Android SDK and the existing compatible Gradle installation are needed.
Kotlin Android remains **2.1.0**, AGP **8.2.2**, default bridge compile SDK **34**
and minimum SDK **23**, matching the existing bridge conventions. No target SDK
or application ID change. Supply the SAME Godot release AAR as your working build.
From PowerShell (uses your locally installed Gradle; no wrapper is fabricated):

```powershell
$project = 'F:\VelocityRush3D-Phase1\VelocityRush3D'
gradle -p "$project\Native\AdsBridge" "-PgodotAar=$project\android\build\libs\release\godot-lib.template_release.aar" :bridge:installBridge
```

If Gradle is not on PATH, use your existing Android wrapper instead of `gradle`:
`& "$project\android\build\gradlew.bat"` followed by the same arguments.
The task copies ONLY its own fresh release output to
`addons/rush_ads/bin/RushAdsBridge.aar`, with a config hash sidecar.
Enable `rush_ads` editor plugin (already added to project.godot), keep custom
Gradle export enabled, and manually export the APK. No Firebase rebuild needed.
Missing AAR/config mismatch excludes both Ads AAR and SDK dependencies safely.

## Configuration

`Data/AdsConfig.json` defaults explicitly to TEST, using Google's official
Android demo app/rewarded/interstitial IDs. These are not production IDs.
PRODUCTION requires all three developer IDs and `privacy_setup_complete=true`
AFTER configuring the actual AdMob UMP privacy messages/audience policy.
Missing/invalid production settings disable ads; there is no test fallback.
Rebuild/install AdsBridge whenever this JSON changes: the manifest app ID and
export config stamp must match the current file. Do not edit the stamp manually.
Native initialization also compares the packaged manifest app ID.

Pinned SDKs: Google Mobile Ads **24.1.0**, UMP **3.1.0**. This is a deliberate
Kotlin-2.1-compatible integration pin, NOT a claim that it is the newest SDK.
Resolve dependencies against your actual Android export toolchain manually.
Do not suppress metadata errors or upgrade unrelated tooling automatically.

## Runtime policy

SDK initialization/retry and preload occur only on safe foreground screens.
At most one rewarded and one interstitial object; loads expire after 50 minutes,
30-second load watchdog, 60-second retry/preload cadence. SDK initialization is
once per live bridge, with failed consent/config remaining unavailable.
Fullscreen requests have a 180-second client receipt timeout; timed-out requests
cannot reward. Native retains its presentation lock until genuine dismissal.
Audio uses a temporary master-bus mute and restores the prior mute state, without
changing saved volumes. A transparent input shield prevents navigation while
an ad is being presented. Scene/account changes invalidate pending rewards.

Reward placements delegate unchanged atomic SaveService operations:
- TURBO_REFILL / Store Turbo: **+2 Turbo**, preserving the run's free allowance.
- Store Repair/Magnet/Shield: **+1** corresponding inventory item each.
- Existing Garage upgrades: **one ad-progress step**, existing threshold unchanged.
- Existing Results double coins: **one additional road-coins amount**, existing
  run settlement and once-per-run gate unchanged.
- Existing revive/powerup offers retain their current run-bound eligibility and
  configured effect. No new pre-race powerups screen/navigation was introduced.

SDK reward quantities are ignored. Identity consists of native ticket + placement
+ Save ad receipt + account generation + screen context. Only EARNED followed by
valid dismissal routes to the existing atomic grant. Duplicate, stale, failure,
timeout, incomplete and account-switched callbacks do not grant. A disk-save
failure retains the facade's existing retry-delivery receipt, not a second ad.

Interstitial: only saved completed single-player Results; after at least two
completed races and 120 seconds since launch/last eligible presentation.
One consideration per account/run. Unavailable/failure never waits or blocks
Results. Active/grace membership suppresses forced ads conservatively. No ads
in live multiplayer sessions, race/countdown, auth transition or purchase flow.

## Privacy and future production work

Production uses real UMP `canRequestAds()` after consent-info update/form;
NPA is additionally requested conservatively. NPA is NOT treated as consent.
TEST bypass is restricted to all three exact Google demo identifiers.
A required AD PRIVACY button appears in the Store for UMP options/withdrawal.
Withdrawal discards prepared ads and gates further requests again.
Publish/configure UMP messages, audience/age treatment, privacy policy and Play
Data Safety/ads declarations for the actual audience BEFORE enabling production.
No audience consent is fabricated. Configure mediation and required privacy
adapters through AdMob later; no custom waterfall or extra network SDKs added.

Client earned callbacks are not cryptographic server authority. Production
valuable rewards may require Google SSV plus trusted backend verification and
idempotent receipts. There is no deployed verifier in this delivery. Billing,
Firebase/Google sign-in and multiplayer authority are not changed.

## Manual Android checks

1. Build/install Ads AAR, export, confirm RushAdsBridge registered and
   `VelocityRushAds MODE_TEST`; Firebase login still works independently.
2. Wait on Home/Store for preload. Complete each Store reward; verify exact +2/+1
   once. Rapid taps, cancel/back, failure/offline and duplicate events grant zero.
3. Check Turbo refill, existing Garage progress, Results double and revive;
   simulate disk-save failure and retry existing delivery without another grant.
4. Switch/logout account or navigate programmatically during a request; stale
   callbacks must not affect the new account/screen. Relaunch restores inventory.
5. Two completed races after 120 seconds: Results interstitial only if loaded;
   early races, aborted races, multiplayer and purchases remain ad-free.
6. Background/resume/click-through/Activity recreation/timeout: restore audio,
   no stuck overlay or overlapping ads. No preload repeated each frame.
7. Missing Ads AAR or invalid PRODUCTION IDs: no ad and no crash/test fallback.
8. With real configuration later: UMP required/denied/granted/error/withdrawal,
   membership suppression and mediation consent behavior on physical devices.

API sources reviewed:
- https://developers.google.com/admob/android/rewarded
- https://developers.google.com/admob/android/interstitial
- https://developers.google.com/admob/android/test-ads
- https://developers.google.com/admob/android/privacy
- https://developers.google.com/admob/android/rel-notes
