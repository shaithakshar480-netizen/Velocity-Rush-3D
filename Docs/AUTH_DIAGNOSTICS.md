# Temporary authentication call-chain diagnostics

Source/static review only. No Godot, Android, emulator, builds or device tests executed.

Runtime root: Core/Main.tscn -> Core/Game.gd -> RushAccountUI.new()/build().
Account screen CONTINUE WITH GOOGLE: Account/AccountUI.gd::_google_pressed -> AuthService.sign_in_with_google().
Profile screen LINK GOOGLE ACCOUNT: Account/AccountUI.gd::_link_google_pressed -> AuthService.link_guest_to_google().
Both buttons use the direct-handler option of AutomotiveUI._button; each pressed signal connects once, without an intervening audio callback. First statement in both handlers is the direct UI marker.
Then AuthService.request -> FirebaseRestProvider.authenticate -> google_token Callable -> AndroidCredentialBridge.request_token -> RushFirebaseBridge.requestGoogleToken(request_id). Native google_result(ticket,ok,token,code) matches _result.

Expected success-path prefix (additional startup binding logs are expected):
UI_GOOGLE_BUTTON_PRESSED
AUTH_SERVICE_GOOGLE_REQUEST
GOOGLE_TOKEN_CALLBACK_CHECK:true
ANDROID_BRIDGE_REQUEST
SINGLETON_CHECK:true
NATIVE_METHOD_CHECK:true
NATIVE_METHOD_INVOKE
GOOGLE_SIGNIN_REQUEST_RECEIVED
CREDENTIAL_MANAGER_REQUEST_START

Godot prints carry [VelocityRushAuth]; native Log.i uses VelocityRushAuth.
The helper now always prints through Godot rather than depending on a native logging method/flag. Bind failure reports platform/singleton, missing required method/signal or configure rejection. Missing google_token previously went straight to generic failure with no diagnostic; now it prints GOOGLE_REQUEST_BLOCKED:BRIDGE_NOT_BOUND. This path is established in source, but the actual device failure cause is not established. No name mismatch found.

Capture from app launch through a single Google attempt:
```sh
adb logcat -v time VelocityRushAuth:I godot:I "*:S" > velocity-rush-auth.txt
```

Local Gradle source was stale at 1.9.22; aligned to the required Kotlin Android 2.1.0. No other dependency/config ID changed. Native Kotlin diagnostic implementation unchanged.

Mobile menus: enabled touch-to-mouse emulation for normal controls and existing ScrollContainers. DriveInput ignores synthetic mouse events (device -1), preserving real multitouch IDs and desktop mouse controls. Manually verify tap vs swipe cancellation, settings sliders, Profile/Store scrolling, simultaneous steering/pedals and wheel return.

Disable temporary diagnostics after investigation: AuthDiagnostics.ENABLED, native AUTH_DIAGNOSTICS, and remove direct [VelocityRushAuth] print statements at UI/Auth/bridge boundaries. No secrets or response payloads are printed.
