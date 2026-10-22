class_name RushHornControl
extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_delta: float) -> void:
	if is_visible_in_tree():
		queue_redraw()

func _draw() -> void:
	var held := DriveInput.held("horn")
	var c := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.46
	var s: float = maxf(radius / 35.0, 0.4)

	# 1. Soft outer cyan glow halo
	draw_arc(c, radius + 2.5 * s, 0.0, TAU, 48, Color("00e5ff26") if not held else Color("00e5ff55"), 6.0 * s, true)

	# 2. Dark glass circle body
	var bg_color := Color("0e2b3bf4") if held else Color("071422f0")
	draw_circle(c + Vector2(0, 2 * s), radius, Color("020910bb"))
	draw_circle(c, radius, bg_color)

	# 3. Bright cyan neon border ring
	var border_color := Color("54f0ff") if held else Color("00e5ffaa")
	draw_arc(c, radius, 0.0, TAU, 48, border_color, 1.8 * s if held else 1.4 * s, true)

	# 4. Subtle inner concentric ring
	draw_arc(c, radius - 4.5 * s, 0.0, TAU, 36, Color("00e5ff20"), 1.0 * s, true)

	# Symmetric automotive horn silhouette, optically centered.
	var ink := Color("e0faff") if held else Color("89e7ff")
	var pts := PackedVector2Array([
		c + Vector2(-19, -10) * s,
		c + Vector2(-10, -4) * s,
		c + Vector2(10, -4) * s,
		c + Vector2(19, -10) * s,
		c + Vector2(19, 10) * s,
		c + Vector2(10, 4) * s,
		c + Vector2(-10, 4) * s,
		c + Vector2(-19, 10) * s
	])
	draw_colored_polygon(pts, ink)
	draw_arc(c + Vector2(0, 5 * s), 7 * s, 0, PI, 20, ink, 3 * s, true)
