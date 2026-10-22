# Native exposure audit — source only

## Finding and limitation
Device evidence proves singleton registration succeeds and configure is absent from the exposed Godot method table. This source has a public, non-suspend, non-null configure(String,String): Boolean annotated with org.godotengine.godot.plugin.UsedByGodot. There is no duplicate configure or mismatched GDScript spelling. No definitive reason for the device method-table failure can be established without the installed AAR and exact Godot AAR/APK. Annotation stripping, stale packaged code and engine registration behavior remain alternatives, not established causes. No OAuth/Firebase changes are justified.

Godot v2 documentation specifies GodotPlugin inheritance, UsedByGodot methods and getPluginSignals. It does not require a separate annotation processor/generated registration table. Source follows that mechanism. Boolean/Int/String use primitive JVM Z/I and java.lang.String; secureClear's Boolean result remains intact and is ignored by GDScript. No alternate exposure mechanism or unchecked GDScript bypass was added.
Reference: https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html

## Locations
- Single native class: Native/FirebaseBridge/bridge/src/main/java/com/velocityrush3d/firebase/RushFirebaseBridge.kt.
- Single v2 metadata registration: bridge/src/main/AndroidManifest.xml.
- Native/FirebaseBridge/{settings.gradle.kts,build.gradle.kts,gradle.properties}: one bridge module, Kotlin 2.1.0.
- bridge/build.gradle.kts: compileOnly exact -PgodotAar (engine is not embedded); explicit release minification disabled; assembleRelease -> verifyBridge -> installBridge.
- bridge/consumer-rules.pro: existing class/method keep rules; explicit annotation metadata retention added.
- addons/rush_firebase/plugin.cfg -> export_plugin.gd: one export provider; one AAR path relative to addons: rush_firebase/bin/RushFirebaseBridge.aar. Path is correct and unchanged. Credential dependencies match native module.
- Expected output: Native/FirebaseBridge/bridge/build/outputs/aar/bridge-release.aar.
- Expected installed output: addons/rush_firebase/bin/RushFirebaseBridge.aar.
- No actual AAR/JAR, compiled class output or android/build tree exists in supplied workspace. Only bin/BUILD_REQUIRED.md exists. No stale/duplicate binary was found here; user's Windows build tree is uninspected.
- Account/AndroidCredentialBridge.gd validation and google_result callback unchanged.

## Changes
1. Constructor logs BRIDGE_BINARY_REVISION:exposure-audit-1 plus seven BRIDGE_JVM_METHOD:<name>:public=true:annotated=true lines. These do not depend on GDScript exposure and contain no values/credentials.
2. Annotation retention rules prevent R8 removing runtime annotation attributes; release library minification explicitly disabled. This hardens a potential failure point; stripping was not proven on device.
3. verifyBridge inspects actual classes.jar with JDK javap, verifies seven exact public JVM descriptors and runtime UsedByGodot annotations, and retains reports under bridge/build/bridge-inspection. It also inspects GodotPlugin and UsedByGodot from the exact supplied Godot AAR. It does not execute Android classes. Signal source remains google_result(Int boxed, Boolean boxed, String, String) through getPluginSignals.
4. installBridge rejects additional AAR/JARs containing the bridge class under addons and android/build/libs; copies verified release output through a staging file, then compares SHA256. No ambiguous wildcard Copy task. Build-time checks must still be run by the user; not executed here.

## Manual PowerShell (from existing game root)
```powershell
Set-Location 'F:\VelocityRush3D-Phase1\VelocityRush3D'
& '.\android\build\gradlew.bat' -p '.\Native\FirebaseBridge' :bridge:clean :bridge:installBridge '-PgodotAar=F:\VelocityRush3D-Phase1\VelocityRush3D\android\build\libs\release\godot-lib.template_release.aar' --rerun-tasks --no-build-cache
if ($LASTEXITCODE -ne 0) { throw 'Bridge verification/install failed; do not export APK.' }
```
Use the existing Android template wrapper/JDK. No wrapper or engine AAR fabricated. Require BRIDGE_BYTECODE_VERIFIED and BRIDGE_INSTALLED with matching hashes. Then manually rebuild the APK.

## Device markers
First require BRIDGE_BINARY_REVISION:exposure-audit-1 and seven public=true:annotated=true lines. If revision is absent, this newly instrumented class is not running (or tag output is filtered). If annotation false, inspect shrinker configuration/final APK. If all seven are true but has_method fails, provide engine javap reports and packaged AAR for registration analysis.
Then expect ANDROID_BRIDGE_BIND, ANDROID_PLATFORM_CHECK:true, SINGLETON_CHECK:true, ANDROID_BRIDGE_BOUND:true. On Google press expect UI_GOOGLE_BUTTON_PRESSED, AUTH_SERVICE_GOOGLE_REQUEST, GOOGLE_TOKEN_CALLBACK_CHECK:true, ANDROID_BRIDGE_REQUEST, SINGLETON_CHECK:true, NATIVE_METHOD_CHECK:true, NATIVE_METHOD_INVOKE, GOOGLE_SIGNIN_REQUEST_RECEIVED, CREDENTIAL_MANAGER_REQUEST_START. These are expected, not verified results.

No Godot, Gradle build, Android, emulator or device tests were run. Static checks verified changed-file scope and seven source annotations only. Exact Godot 4.7.2 bytecode and final APK registration remain unverified. Gameplay, touch/UI, identity, saves and cloud architecture unchanged.
