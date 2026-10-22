# Settings, vehicle sound and streetlight polish

Source-only update on the latest RemoteEdits project. No Godot, Android, emulator or APK export was run.

## Settings and buttons
- Four focused tabs: AUDIO, CONTROLS, DISPLAY, ACCOUNT.
- Graphite/cyan cards, compact headers, descriptive subtitles, rounded buttons, distinct focus/press/hover states, original vector switches and slider thumbs.
- Sliders use full-width tracks with labels and readouts above them. Touch scrolling and the existing settings/save callbacks remain intact.
- Settings widgets reload saved values when opened, including values restored from cloud.
- Existing tilt calibration, sensitivity, assist, vibration, audio levels and quality controls retain their actual functionality.
- Profile navigation moved from the bottom navigation strip into a top-right player-name button. Wallet and level/XP sit below it, with the central vehicle area kept open. Existing profile destination is unchanged. Original racing-game styling; no copied PUBG/Free Fire branding or artwork.

## Audio
- All 12 car IDs now map to their own four-layer engine bank and individual brake/tire loops through Data/VehicleAudioProfiles.json. The six newer cars no longer fall back to the first six engine banks.
- Engine character varies by fundamental frequency, harmonic balance, intake noise and per-car throttle/pitch response. Existing RPM, load, shifts, turbo, overrun and damage response remain.
- Friction ramps progressively with braking and speed. Tire squeal follows actual existing arcade slip/traction estimates, with smooth amplitude and pitch changes. Ordinary gentle braking does not produce maximum squeal.
- Reverse acceleration is no longer interpreted as braking; opposing input while reversing is braking.
- Loops stay running and fade; they are not restarted on each pedal press. Assets are generated offline and cached at startup, never synthesized while racing.
- All assets are original synthesized approximations, not recordings of real engines or tires. Auditory realism and phone-speaker balance remain for manual evaluation.

## Proximity streetlights
- Added 52 fixed fixtures to the existing recycled highway visuals, with local lamp lenses and downward spotlights.
- Dusk/night enables smooth proximity lighting; daytime fades it off. Lamps illuminate the road as the player approaches and fade out after departure. Both directions of travel work by distance, without direction assumptions.
- Quality-scaled activation radius: LOW 40m, MEDIUM 62m, HIGH 80m. Only nearby fixtures illuminate; distant lights are hidden. Spotlights cast no additional shadows, and nodes are reused rather than spawned during driving.
- Existing map/time presets and vehicle lighting are preserved. This controls the highway street fixtures; decorative building-window emissions retain their existing time-of-day behavior.

## Major files
- UI/AutomotiveUI.gd
- UI/ProgressionUI.gd
- UI/RushPresentation.gd
- Audio/DrivingAudio.gd
- VFX/BrakeEffects.gd
- Environment/Highway.gd
- Environment/TimeOfDay.gd
- Environment/StreetLighting.gd (new)
- Data/VehicleAudioProfiles.json (new)
- Tools/generate_vehicle_sound_profiles.py (new, offline authoring only)
- Assets/Audio: 48 engine layers and 24 per-car brake/tire loops
- Assets/UI: slider_thumb.svg, switch_on.svg, switch_off.svg

## Verification
- All 103 GDScript files passed gdtoolkit grammar parsing. This is not Godot compilation.
- All 72 car audio loops are distinct, valid mono 16-bit 22,050Hz WAV files, three seconds each, with nonzero signal and peak below clipping.
- Vector artwork parsed as valid XML.
- Byte comparison with the previous full RemoteEdits ZIP confirmed Account/, Save/ and Native/ files unchanged. Latest remote-edit sync, first-upload fix, owner rules, Schema 5 and Kotlin 2.1.0 remain intact.
- No gameplay physics, traffic AI, purchase economy or cloud code was modified.

## Installation and manual checks
Merge the full project ZIP into the existing project; do not delete your generated android/build or working addons/rush_firebase/bin/RushFirebaseBridge.aar. Neither is included in this ZIP. AAR rebuild NOT required; import the updated assets and re-export your APK manually.

Check settings tabs/touch scrolling on narrow and wide landscape screens, button focus/pressed contrast, top-right profile navigation, settings persistence and cloud-restored values. Compare all cars at idle/throttle/overrun and gentle/hard braking, reverse, pause/resume and restart. Drive through dusk/night fixtures in both directions and verify fade, road illumination and LOW/MEDIUM/HIGH frame rate. No rendered visual, acoustic or Android performance success is claimed from source checks alone.
