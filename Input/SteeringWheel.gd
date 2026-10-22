class_name RushSteeringWheel
extends Control
## Scalable true-analog touch steering wheel.
var pad_depth: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _process(delta: float) -> void:
	pad_depth = lerpf(pad_depth, 1.0 if DriveInput.held("horn") else 0.0, 1.0 - exp(-20.0 * delta))
	if visible:
		queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var radius := minf(size.x, size.y) * 0.42
	var s: float = maxf(radius / 82.0, 0.4)
	var angle := deg_to_rad(DriveInput.wheel_angle)
	var rim := PackedVector2Array()
	for i: int in 81:
		var theta := TAU * float(i) / 80.0
		var p := Vector2(cos(theta) * radius, maxf(sin(theta) * radius, -radius * 0.79))
		rim.append(center + p.rotated(angle))
	draw_polyline(rim, Color("050a10ca"), 22.0 * s, true)
	draw_polyline(rim, Color("748795"), 15.0 * s, true)
	draw_polyline(rim, Color("202c36"), 10.0 * s, true)
	for side: float in [-1.0, 1.0]:
		var spoke := PackedVector2Array()
		for p: Vector2 in [Vector2(side * 19.0, -10.0) * s, Vector2(side * 61.0, -7.0) * s, Vector2(side * 68.0, 10.0) * s, Vector2(side * 23.0, 19.0) * s]:
			spoke.append(center + p.rotated(angle))
		draw_colored_polygon(spoke, Color("687e8d"))
		for row: int in 2:
			for col: int in 2:
				draw_circle(center + Vector2(side * (43.0 + col * 9.0) * s, (row * 9.0 - 3.0) * s).rotated(angle), 2.7 * s, Color("12202b"))
	var lower := PackedVector2Array()
	for p: Vector2 in [Vector2(-14.0, 14.0) * s, Vector2(14.0, 14.0) * s, Vector2(8.0, 65.0) * s, Vector2(-8.0, 65.0) * s]:
		lower.append(center + p.rotated(angle))
	draw_colored_polygon(lower, Color("455c6b"))
	var pad := PackedVector2Array()
	for i: int in 33:
		var theta := TAU * float(i) / 32.0
		var p := Vector2(cos(theta) * 31.0, sin(theta) * 26.0) * s * (1.0 - pad_depth * 0.045)
		pad.append(center + p.rotated(angle) + Vector2(0.0, pad_depth * 2.0 * s))
	draw_colored_polygon(pad, Color("1a2732").darkened(pad_depth * 0.18))
	draw_polyline(pad, Color("587080"), 1.5 * s, true)
	var marker := Vector2(0.0, -radius).rotated(angle)
	draw_line(center + marker * 0.94, center + marker * 1.06, Color("c1dbe5"), 5.0 * s, true)
