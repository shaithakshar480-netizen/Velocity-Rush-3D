class_name RushStartupPresentation
extends Control
## Four-second custom video ident, followed by the existing loading presentation.
signal brand_finished
var progress: float = 0.0
var displayed: float = 0.0
var elapsed: float = 0.0
var exiting: float = 0.0
var revealed: bool = false
var _rail_style: StyleBoxFlat
var sound: AudioStreamPlayer
var brand_video: VideoStreamPlayer
var pass_sound: AudioStream = preload("res://Assets/Audio/passby.wav")
var exit_sound: AudioStream = preload("res://Assets/Audio/turbo_ignition.wav")
const CITY_ART: Texture2D = preload("res://Assets/UI/startup_city.svg")
const CAR_ART: Texture2D = preload("res://Assets/UI/startup_hologram_car.svg")
const BRAND_SECONDS: float = 4.0
const BRAND_VIDEO: VideoStream = preload("res://Assets/Video/gen_z_intro.ogv")
const CYAN: Color = Color("69ddf5")
func _ready() -> void:
	_rail_style = StyleBoxFlat.new()
	_rail_style.bg_color = Color("102531")
	_rail_style.border_color = Color("617e8e")
	_rail_style.set_border_width_all(1)
	_rail_style.set_corner_radius_all(4)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	sound = AudioStreamPlayer.new()
	sound.bus = "UI"
	sound.volume_db = -10
	add_child(sound)
	brand_video = VideoStreamPlayer.new()
	brand_video.name = "BrandVideo"
	brand_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_video.expand = true
	brand_video.bus = "UI"
	brand_video.volume_db = 0.0
	brand_video.stream = BRAND_VIDEO
	brand_video.finished.connect(_brand_complete)
	add_child(brand_video)
	resized.connect(_fit_brand_video)
	_fit_brand_video()
	brand_video.play()
func _fit_brand_video() -> void:
	if not is_instance_valid(brand_video):
		return
	var fit: float = minf(size.x / 848.0, size.y / 478.0)
	brand_video.size = Vector2(848.0, 478.0) * fit
	brand_video.position = (size - brand_video.size) * 0.5
func _brand_complete() -> void:
	if revealed:
		return
	revealed = true
	elapsed = BRAND_SECONDS
	brand_video.stop()
	brand_video.hide()
	brand_video.queue_free()
	sound.stream = pass_sound
	sound.play()
	brand_finished.emit()
	queue_redraw()
func _process(delta: float) -> void:
	# A stalled load must not skip the entire animated reveal in one frame.
	elapsed += minf(delta,0.05)
	displayed = move_toward(displayed,progress,minf(delta,0.05)*0.65)
	# Playback completion owns the transition: frame stalls cannot cut off the sound.
	if not revealed and elapsed > 1.0 and not brand_video.is_playing():
		_brand_complete() # Failed/stopped playback must not block startup forever.
	queue_redraw()
func finish() -> void:
	progress = 1.0
	while not revealed or elapsed<BRAND_SECONDS+1.4 or displayed<0.995:
		await get_tree().process_frame
	sound.stop()
	sound.stream = exit_sound
	sound.play()
	var tween: Tween = create_tween()
	tween.tween_property(self,"exiting",1.0,0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(sound,"volume_db",-45.0,0.45)
	await tween.finished
	sound.stop()
	hide()
	queue_free()
func caption(text: String, center: Vector2, font_size: int, color: Color) -> void:
	var font: Font = ThemeDB.fallback_font
	var width: float = font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	draw_string(font,center-Vector2(width*0.5,0),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)
func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("050910"))
	if not revealed:
		return # Video child draws the brand ident; no old logo or sting underneath.
	var scale_value: float = minf(size.x/1280.0,size.y/720.0)
	var origin: Vector2 = (size-Vector2(1280,720)*scale_value)*0.5
	draw_set_transform(origin,0.0,Vector2.ONE*scale_value)
	# Fixed bounded geometry: layered illumination and moving perspective rails.
	for i: int in 12:
		var radius: float = 300.0-float(i)*18.0
		draw_circle(Vector2(640,325),radius,Color(0.03,0.15,0.20,0.035))
	for i: int in 14:
		var x: float = fmod(float(i)*113.0+elapsed*55.0,1550.0)-140.0
		draw_line(Vector2(x,720),Vector2(x+300,0),Color(0.25,0.65,0.8,0.045),1.0,true)
	var t: float = elapsed-BRAND_SECONDS
	var reveal: float = ease(clampf(t/0.7,0.0,1.0),0.3)
	draw_texture_rect(CITY_ART,Rect2(0,0,1280,720),false,Color(1,1,1,reveal))
	caption("VELOCITY",Vector2(640,208),62,Color(0.03,0.12,0.18,reveal))
	caption("VELOCITY",Vector2(640,204),62,Color(0.88,0.95,1.0,reveal))
	caption("R U S H   3 D",Vector2(640,254),34,Color(0.33,0.91,1.0,reveal))
	caption("BUILT FOR THE OPEN ROAD",Vector2(640,282),12,Color(0.60,0.74,0.81,reveal))
	# Same smoothed progress drives the car, percentage and progress rail.
	# Never time-loop the car or show completion ahead of actual loading.
	var fraction: float = clampf(displayed,0.0,1.0)
	var car_x: float = lerpf(275.0,1000.0,fraction)+exiting*850.0
	var car_y: float = 383.0
	var car_scale: float = 0.86
	for i: int in 3:
		draw_line(Vector2(165,500),Vector2(car_x,500),Color(0.25,0.88,1.0,reveal*(0.08+float(i)*0.05)),10.0-float(i)*3.0,true)
	# Fixed count of fine hologram fragments; no nodes/particles allocated.
	for i: int in 18:
		var travel: float = fmod(t*150.0+float(i)*31.7,240.0)
		var x: float = car_x-115.0-travel
		if x<166.0: continue
		var y: float = 463.0+sin(float(i)*2.7+t*1.5)*15.0
		var alpha: float = (1.0-travel/240.0)*0.45*reveal
		draw_line(Vector2(x,y),Vector2(x+9.0,y-2.0),Color(0.35,0.88,1.0,alpha),2.0,true)
	draw_texture_rect(CAR_ART,Rect2(car_x-180.0*car_scale,car_y,360.0*car_scale,150.0*car_scale),false,Color(1,1,1,reveal))
	# Spokes turn only as loading advances: stationary percentage = stationary car.
	for wheel: Vector2 in [Vector2(79,111),Vector2(286,108)]:
		var center: Vector2 = Vector2(car_x-180.0*car_scale,car_y)+wheel*car_scale
		for spoke: int in 5:
			var angle: float = fraction*28.0+float(spoke)*TAU/5.0
			draw_line(center+Vector2.from_angle(angle)*5.0,center+Vector2.from_angle(angle)*14.0,Color(0.45,0.80,0.92,reveal*0.8),1.2,true)
	caption("%d%%"%int(fraction*100.0),Vector2(640,556),28,Color(0.39,0.94,1.0,reveal))
	draw_style_box(_rail_style,Rect2(420,577,440,12))
	draw_rect(Rect2(424,581,432*fraction,4),Color(0.37,0.89,0.98,reveal))
	draw_circle(Vector2(424+432*fraction,583),3.0,Color(0.77,1.0,1.0,reveal))
	caption("READY" if fraction>=0.995 else "PREPARING YOUR DRIVE",Vector2(640,615),14,Color(0.62,0.77,0.83,reveal))

	draw_set_transform(Vector2.ZERO)
	if exiting>0:
		draw_rect(Rect2(Vector2.ZERO,size),Color(0.02,0.035,0.055,exiting))
