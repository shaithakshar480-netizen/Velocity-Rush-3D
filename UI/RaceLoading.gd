class_name RushRaceLoading
extends Control
## One static background and stage-driven UI; no extra 3D scene or fake timer.
const ART: Texture2D = preload("res://Assets/UI/race_loading_rear.png")
var stage: int = 0
var displayed: float = 0.0
var target_progress: float = 0.0
const STAGES: Array[String] = ["BUILDING COURSE", "PREPARING RACE", "READY"]
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_viewport().size_changed.connect(_fit)
	_fit.call_deferred()
func _fit() -> void:
	position = -get_parent().global_position
	size = get_viewport().get_visible_rect().size
	queue_redraw()
func set_stage(value: int) -> void:
	stage = clampi(value,0,2)
	if stage==0:
		displayed = 0.0
		target_progress = 0.0
	elif stage==1:
		target_progress = 0.95
	else:
		target_progress = 1.0
		displayed = 1.0
	queue_redraw()
func set_course_progress(fraction: float) -> void:
	target_progress = maxf(target_progress,clampf(fraction,0.0,1.0)*0.9)
func _process(delta: float) -> void:
	if not is_visible_in_tree() or is_equal_approx(displayed,target_progress): return
	displayed = move_toward(displayed,target_progress,delta*0.8)
	queue_redraw()
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("030a13"))
	# Full art preserved across wide devices; no cropped metallic frame.
	var scale_value: float = minf(size.x/ART.get_width(),size.y/ART.get_height())
	var art_size: Vector2 = ART.get_size()*scale_value
	var origin: Vector2 = (size-art_size)*0.5
	draw_texture_rect(ART,Rect2(origin,art_size),false)
	var font: Font = ThemeDB.fallback_font
	var unit: float = minf(size.x/1280.0,size.y/576.0)
	_text(font,"VELOCITY RUSH",origin.y+art_size.y*.18,int(43*unit),Color("a4efff"))
	_text(font,"LOADING RACE…  %d%%"%int(displayed*100.0),origin.y+art_size.y*.79,int(27*unit),Color("b8edfa"))
	var bar: Rect2 = Rect2(Vector2(size.x*.27,origin.y+art_size.y*.84),Vector2(size.x*.46,22*unit))
	draw_style_box(_frame(),bar.grow(5*unit))
	for i: int in 12:
		var cell: Rect2 = Rect2(bar.position+Vector2(i*bar.size.x/12.0,0),Vector2(bar.size.x/12.0-4*unit,bar.size.y))
		draw_rect(cell,Color("213348"))
		var fill: float = clampf(displayed*12.0-float(i),0.0,1.0)
		if fill>0.0:
			draw_rect(Rect2(cell.position,Vector2(cell.size.x*fill,cell.size.y)),Color("68dafa"))
	_text(font,STAGES[stage],bar.end.y+26*unit,int(16*unit),Color("96bdcb"))
func _text(font: Font, value: String, y: float, pixels: int, color: Color) -> void:
	var font_size: int = maxi(pixels,12)
	var width: float = font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,Vector2((size.x-width)*.5,y),value,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
func _frame() -> StyleBoxFlat:
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("091628")
	frame.border_color = Color("91c9e4")
	frame.set_border_width_all(1)
	frame.set_corner_radius_all(4)
	return frame
