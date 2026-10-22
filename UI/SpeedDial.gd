class_name RushSpeedDial
extends Control

## Vehicle speed fraction against top speed (0.0 -> 1.0+)
static var fraction: float = 0.0

## Transmission RPM telemetry (0.0 -> 1.0 against redline)
static var rpm_fraction: float = 0.0
static var rpm_value: int = 0
static var gear_text: String = "N"
static var speed_value: int = 0
static var turbo_intensity: float = 0.0

const ARC_START: float = PI * 0.96
const ARC_SPAN: float = PI * 1.08

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	# A wide instrument arc frames the readout, rather than sitting beside it.
	var center := Vector2(size.x * 0.5, 127.0)
	var radius: float = minf(size.x * 0.5 - 27.0, 113.0)
	var end: float = ARC_START + ARC_SPAN
	draw_arc(center, radius + 13, ARC_START, end, 64, Color("33566699"), 10, true)
	draw_arc(center, radius, ARC_START, end, 64, Color("08738aaa"), 7, true)
	draw_arc(center, radius - 7, ARC_START, end, 64, Color("75dcff55"), 1, true)
	# Always-visible luminous dial outline; the thicker sweep shows actual speed.
	draw_arc(center, radius, ARC_START, end, 64, Color("29ccebbb"), 2, true)
	var sweep: float = ARC_START + ARC_SPAN * clampf(fraction, 0, 1)
	if fraction > 0.001:
		draw_arc(center, radius, ARC_START, sweep, 64, Color("00dfff33"), 12, true)
		draw_arc(center, radius, ARC_START, sweep, 64, Color("60edff"), 7, true)
	for i: int in 29:
		var angle: float = ARC_START + ARC_SPAN * float(i) / 28.0
		var radial := Vector2(cos(angle), sin(angle))
		var major: bool = i % 4 == 0
		draw_line(center + radial * (radius + 9), center + radial * (radius + (18 if major else 14)), Color("a5eaffaa"), 1.4 if major else 1, true)
	draw_arc(center, radius, end - 0.25, end, 12, Color("ff8e36"), 3, true)
	for i: int in 5:
		var lit: bool = float(i) / 5.0 < rpm_fraction
		draw_rect(Rect2(17 + i * 11, 145, 8, 7), Color("46efff") if lit else Color("153747"))
	if turbo_intensity > 0.01:
		draw_arc(center, radius - 4, ARC_START, end, 64, Color(0.5, 0.95, 1, turbo_intensity * 0.65), 2, true)
