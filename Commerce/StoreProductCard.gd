class_name RushStoreProductCard
extends Button
var movement: Tween
func _ready() -> void:
	pivot_offset = size * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	button_down.connect(_compress)
	button_up.connect(_release)
	mouse_entered.connect(_hover)
	focus_entered.connect(_hover)
	mouse_exited.connect(_release)
	focus_exited.connect(_release)
func _hover() -> void:
	if not disabled:
		_animate(1.02)
func _compress() -> void:
	if not disabled:
		_animate(0.975)
func _release() -> void:
	_animate(1.0)
func _animate(value: float) -> void:
	pivot_offset = size * 0.5
	if movement != null and movement.is_valid():
		movement.kill()
	movement = create_tween()
	movement.tween_property(self, "scale", Vector2.ONE * value, 0.12).set_trans(Tween.TRANS_QUAD)
