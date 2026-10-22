class_name RushPowerIcon
extends Button

const TARGET_SIZE: Vector2 = Vector2(64, 64)
const ART_SIZE: Vector2 = Vector2(38, 38)
const COUNT_SIZE: Vector2 = Vector2(40, 16)

static func fit_art(art: TextureRect) -> void:
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	art.offset_left = -ART_SIZE.x * 0.5
	art.offset_right = ART_SIZE.x * 0.5
	art.offset_top = 6
	art.offset_bottom = 6 + ART_SIZE.y
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE

static func fit_count(label: Label) -> void:
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	label.offset_left = -COUNT_SIZE.x * 0.5
	label.offset_right = COUNT_SIZE.x * 0.5
	label.offset_top = -18
	label.offset_bottom = -3
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color("e8f8ff"))
	label.add_theme_color_override("font_shadow_color", Color("00e5ff55"))
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE

var item_kind: String = ""
var remaining_fraction: float = 0.0

func _draw() -> void:
	var center := size * 0.5
	var radius: float = minf(size.x, size.y) * 0.46

	# Soft inner dark glass bg fill
	draw_circle(center, radius - 1.0, Color("071422f0"))

	# Neon glow halo (outer soft ring)
	draw_arc(center, radius + 2.0, 0.0, TAU, 48, Color("00e5ff28"), 5.0, true)

	# Main bright cyan neon border ring
	var ring_color: Color
	if remaining_fraction > 0.001:
		ring_color = Color("54f0ff")
	else:
		ring_color = Color("00e5ffaa")
	draw_arc(center, radius, 0.0, TAU, 48, ring_color, 1.4, true)

	# Inner subtle concentric ring
	draw_arc(center, radius - 4.5, 0.0, TAU, 36, Color("00e5ff20"), 1.0, true)

	# Active timer / cooldown arc over the ring
	if remaining_fraction > 0:
		draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * remaining_fraction, 48, Color("00e5ff"), 2.8, true)
		# Bright tip dot at arc end
		var tip_angle: float = -PI * 0.5 + TAU * remaining_fraction
		var tip_pos := center + Vector2(cos(tip_angle), sin(tip_angle)) * radius
		draw_circle(tip_pos, 2.2, Color("ffffff"))

	# HUD-specific silhouettes: no miniature landscape Store illustration.
	var glyph := Vector2(center.x, center.y - 8)
	var ink := Color("c2f5ff")
	match item_kind:
		"magnet":
			draw_arc(glyph, 11, 0, PI, 24, ink, 7, true)
			draw_line(glyph + Vector2(-11, 0), glyph + Vector2(-11, -12), ink, 7, true)
			draw_line(glyph + Vector2(11, 0), glyph + Vector2(11, -12), ink, 7, true)
			draw_line(glyph + Vector2(-14, -7), glyph + Vector2(-8, -7), Color("17cfff"), 3, true)
			draw_line(glyph + Vector2(8, -7), glyph + Vector2(14, -7), Color("17cfff"), 3, true)
		"repair":
			draw_line(glyph + Vector2(-11, 12), glyph + Vector2(8, -7), ink, 7, true)
			draw_arc(glyph + Vector2(7, -6), 8, -0.4, PI * 1.4, 20, ink, 4, true)
			draw_circle(glyph + Vector2(-10, 11), 2, Color("092231"))
		"shield":
			var points := PackedVector2Array([glyph+Vector2(0,-16),glyph+Vector2(14,-10),glyph+Vector2(11,6),glyph+Vector2(0,16),glyph+Vector2(-11,6),glyph+Vector2(-14,-10),glyph+Vector2(0,-16)])
			draw_colored_polygon(points, Color("205473"))
			draw_polyline(points, ink, 2, true)
			draw_polyline(PackedVector2Array([glyph+Vector2(-6,0),glyph+Vector2(-1,5),glyph+Vector2(7,-5)]), ink, 3, true)

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed and is_visible_in_tree() and not disabled and get_global_rect().has_point(event.position):
		pressed.emit()
		get_viewport().set_input_as_handled()

