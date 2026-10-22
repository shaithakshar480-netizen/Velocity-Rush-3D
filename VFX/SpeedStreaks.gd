class_name RushSpeedStreaks
extends Control
## Bounded peripheral streaks and quality-scaled Turbo-only screen blur.
var intensity: float = 0.0
var quality: int = 1
var clock: float = 0.0
var impact: float = 0.0
var turbo_strength: float = 0.0
var blur: ColorRect
var blur_material: ShaderMaterial
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_PAUSABLE
	blur_material = ShaderMaterial.new()
	blur_material.shader = preload("res://VFX/turbo_edge_blur.gdshader")
	blur = ColorRect.new()
	blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur.material = blur_material
	blur.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur.show_behind_parent = true
	blur.visible = false
	add_child(blur)
func _process(delta: float) -> void:
	clock += delta*(0.5+intensity*2.0)
	impact = move_toward(impact,0.0,delta*3.0)
	blur.visible = visible and quality>0 and turbo_strength>0.015
	if blur.visible:
		blur_material.set_shader_parameter("strength",clampf(turbo_strength,0.0,1.0))
		blur_material.set_shader_parameter("rich",quality>1)
	if visible:
		queue_redraw()
func _draw() -> void:
	if intensity>0.01:
		var count := 6 if quality==0 else (14 if quality==1 else 24)
		for i: int in count:
			var t := fposmod(clock+i*0.618,1.0)
			var side := -1.0 if i%2==0 else 1.0
			var y := 0.16+fposmod(i*0.381,0.68)
			var start := Vector2(size.x*(0.5+side*(0.36+t*0.13)),size.y*y)
			var end := start+Vector2(side*(12.0+intensity*48.0), (y-0.5)*20.0)
			draw_line(start,end,Color(0.5,0.9,1.0,intensity*0.22*(1.0-t)),1.2,true)
	if impact>0.0:
		draw_rect(Rect2(Vector2.ZERO,Vector2(5,size.y)),Color(1.0,0.5,0.3,impact*0.25))
		draw_rect(Rect2(Vector2(size.x-5,0),Vector2(5,size.y)),Color(1.0,0.5,0.3,impact*0.25))
