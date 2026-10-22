# Mobile interaction and startup polish

Source/static work only; no Godot, Android, builds or device tests.

Touch: shared RushTouchScroll retains native ScrollContainer gestures/inertia and 12-pixel deadzone. Descendant panels/cards/buttons pass unhandled touch events to their scroll ancestor instead of stopping them. Sliders/text editors/scrollbars retain direct manipulation. All existing menu scroll-container constructors use the shared class; no online architecture changed. Child-scroll notifications remain native so swipe gestures cancel button clicks. Non-scrollable headers and driving controls are not page-drag surfaces.

Tilt: low-pass gravity/accelerometer filtering, bounded steering slew, unchanged calibration coordinate convention/settings, graceful sensor-dropout handling before fallback. Sensor readings outside reasonable magnitude/projection ranges are rejected. No vehicle physics or save schema changes.

Startup: bounded original vector art (animated emblem/rings, typography reveal, silhouette, light streaks, progress track). Studio ident finishes before expensive scene setup begins. Added frame boundaries between major setup steps. Threaded model requests now run in batches of three. Removed repeated startup rendering of all twelve cars at all three LODs; current selected car/profile remains warmed. Other car resources remain cached; first display of an unvisited LOD/car can still incur renderer work. Individual scene construction/shader uploads may still stall; device timing is required to quantify improvement.

Static checks: GDScript delimiter/string structure, unique class names, new resource paths, constructor wiring, sensor slew numeric bound and unchanged Account/Save/Native source hashes. Kotlin Android stays 2.1.0. These checks are not compilation.

Manual: swipe Store cards/Profile text/Settings empty areas; confirm swipes never purchase/select items, taps still work, sliders remain usable and inertia clamps at ends. Calibrate tilt at comfortable upright angle, steer gently/hard, test brief sensor loss and simultaneous pedals. Cold-launch LOW/MEDIUM quality; inspect both intros, sound, transitions, loading completion and first garage selection. Check Google button diagnostics still print. No runtime success claimed.
