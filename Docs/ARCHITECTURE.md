# Phase 1 foundation reference

This document records the original Phase 1 design. For current wallet, race and traffic behavior, see PHASE2_ARCHITECTURE.md. Statements about future progression below describe the earlier phase.

# Phase 1 boundaries

`Core/Main.tscn` instantiates `Game.gd`, which assembles an in-memory driving scene and UI. Using a single loaded world avoids duplicate service instances across menu transitions. `Game` is the navigation coordinator; the vehicle never knows about menu widgets.

The autoloads start in this order: SaveService → DriveInput → GameAudio. The main game then builds Highway → ArcadeVehicle → CameraRig → PerformanceManager → AutomotiveUI. Generated geometry is deterministic. Per-frame object creation is avoided for road segments and touch polling. Camera obstruction ray queries and the engine collision solver still have their normal allocation costs.

State transitions:

| State | Allowed transitions |
| --- | --- |
| Splash | Home after 2.3 seconds |
| Home | Driving, Settings |
| Driving | Paused, restart Driving |
| Paused | Driving, restart Driving, Settings, Home |
| Settings | Return to originating Home or Paused state |

The coordinator and UI process while the scene tree is paused. World and vehicle explicitly use pausable processing. Engine/skid streams pause; menu audio remains available. Focus loss pauses driving and commits settings; focus gain never auto-resumes into moving gameplay. Android Back follows the pause/settings navigation path.

## Vehicle and coordinate conventions

Local forward = -Z; +Y = up; world units = meters; velocity = meters/second; HUD = KM/H. The road top is -0.01 m and the vehicle collider extends from 0.01 to 0.97 m relative to its origin. The vehicle is a `CharacterBody3D` with a controlled bicycle-model yaw and exponential lateral grip. Yaw acceleration is bounded by a lateral acceleration limit, and roll/pitch exist only on the visual body. This explicitly prevents free rigid-body rollover but does not establish that handling is tuned or collision behavior is bug-free without runtime tests.

Braking first removes forward speed. Once stopped, holding the brake for 0.3 seconds engages reverse. Acceleration brakes an already-reversing vehicle before moving forward. Airborne frames preserve horizontal momentum and apply gravity, preventing in-air throttle steering. Ground snap handles minor discontinuities on the flat expressway. This phase does not include a stunt/ramp suspension simulator.

`VehicleSpec` owns speed, acceleration, steering, braking, wheelbase, grip, mass, drag, gravity and suspension parameters. Future turbo/unlock/upgrade fields are metadata only. No currency service, ad shim, store screen or fake billing code exists.

## Audio

Four buses send to Master. User Music maps to Music; user SFX maps to Engine, SFX and UI. Original mono PCM loops are synthesized offline. Audio update accepts speed, pedal demand and skid amount, keeping clips replaceable. RPM uses simulated gear ranges for audible variation; it is not a transmission upgrade system.

## Save

Envelope: `{"schema_version":1,"settings":{...}}`. Known keys are individually validated and unknown keys are ignored. A new complete pending file is flushed; the last valid primary is copied to backup; pending is renamed to primary. Read order is primary → backup → pending → defaults. Errors are retained and exposed in the settings screen. This provides recoverability but does not claim hardware-level power-loss durability or cross-process concurrency control.

Future progression should get a separate versioned payload and explicit migration from known schema versions. Keep economy transactions out of settings setters. Do not reinterpret old values silently.

## Android costs

Compatibility renderer, fixed 60 Hz physics, one car, no realtime point lights, no full-screen effects, no texture downloads, primitive collisions, instanced lane markings/posts and nine recycled 120 m road segments. Origin rebases at 2,400 m by whole segment lengths. Quality switches change render scale and shadow/MSAA costs. Sustained averages below 42 FPS over three 5-second windows select 30 FPS and low render costs for the session. Re-selecting another quality permits retesting.

Production decisions deferred: device profiling, physical suspension fidelity, final model/audio polish, release signing, final package ownership and Play submission validation.
