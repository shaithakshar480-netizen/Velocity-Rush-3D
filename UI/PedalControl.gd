class_name RushPedalControl
extends Control

## Artwork only: DriveInput still owns each touch independently.
var action: String = "accelerate"
var depression: float = 0.0
var shadow_style: StyleBoxFlat
var pedal_style: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow_style = StyleBoxFlat.new()
	shadow_style.bg_color = Color("05101ce0")
	shadow_style.set_corner_radius_all(14)
	shadow_style.shadow_color = Color("00e5ff33")
	shadow_style.shadow_size = 10
	shadow_style.shadow_offset = Vector2(0, 2)

	pedal_style = StyleBoxFlat.new()
	pedal_style.bg_color = Color("33434eea")
	pedal_style.border_color = Color("b5d4e2dd")
	pedal_style.set_border_width_all(1)
	pedal_style.set_corner_radius_all(12)

func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	depression = move_toward(depression, 1.0 if DriveInput.held(action) else 0.0, delta * 14.0)
	queue_redraw()

func _draw() -> void:
	var gas := action == "accelerate"
	var base_size := Vector2(148.0 if gas else 128.0, 126.0)
	var s: float = clampf(minf(size.x / base_size.x, size.y / base_size.y), 0.4, 2.5)
	var width: float = (62.0 if gas else 102.0) * s
	var height: float = (100.0 if gas else 64.0) * s
	var press_offset := Vector2(0.0, depression * 3.0 * s)
	var rect := Rect2((size - Vector2(width, height)) * 0.5 + press_offset - Vector2(0.0, 12.0 * s), Vector2(width, height))

	# Outer neon glow shadow
	var shadow_rect := Rect2(rect.position - Vector2(3.0, 3.0) * s, rect.size + Vector2(6.0, 34.0) * s)
	draw_style_box(shadow_style, shadow_rect)

	# Main pedal glass plate
	pedal_style.bg_color = Color("33434eea").lerp(Color("496370f4"), depression * 0.5)
	pedal_style.border_color = Color("b5d4e2dd").lerp(Color("58f2ff"), depression)
	draw_style_box(pedal_style, rect)

	# Top inner bevel highlight
	draw_line(
		rect.position + Vector2(10.0 * s, 3.0 * s),
		Vector2(rect.end.x - 10.0 * s, rect.position.y + 3.0 * s),
		Color("00e5ff44").lerp(Color("ffffff"), depression * 0.5),
		1.0 * s,
		true
	)

	# Horizontal grip slats
	var slat_count: int = 7 if gas else 4
	var slat_start_y: float = rect.position.y + (16.0 if gas else 12.0) * s
	var slat_spacing: float = (10.5 if gas else 10.0) * s
	var slat_inset: float = 10.0 * s

	for i: int in slat_count:
		var sy: float = slat_start_y + float(i) * slat_spacing
		var p1 := Vector2(rect.position.x + slat_inset, sy)
		var p2 := Vector2(rect.end.x - slat_inset, sy)
		# Deep shadow groove
		draw_line(p1, p2, Color("020910ee"), 3.5 * s, true)
		# Metallic highlight lip
		draw_line(p1 - Vector2(0.0, 1.2 * s), p2 - Vector2(0.0, 1.2 * s), Color("3d687ecc"), 1.0 * s, true)

	# Clean pedal label at bottom of pedal face
	var font: Font = get_theme_default_font()
	var label_text: String = "ACCEL" if gas else "BRAKE"
	var font_size: int = int(roundf(16.0 * s))
	var text_y: float = rect.end.y + 23.0 * s
	var text_col := Color("d0f4ff").lerp(Color("ffffff"), depression * 0.7)
	draw_string(
		font,
		Vector2(rect.position.x, text_y),
		label_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		rect.size.x,
		font_size,
		text_col
	)

