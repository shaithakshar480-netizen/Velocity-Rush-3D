class_name RushControlPresentation
extends Node
var ui: AutomotiveUI
var wheel: RushSteeringWheel

func build(owner_ui: AutomotiveUI) -> void:
	ui = owner_ui
	wheel = RushSteeringWheel.new()
	ui.screens["drive"].add_child(wheel)
	wheel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	wheel.offset_left = 10
	wheel.offset_right = 350
	wheel.offset_top = -350
	wheel.offset_bottom = -10
	wheel.custom_minimum_size = Vector2(340, 340)
	ui.controls["wheel"] = wheel
	ui.hud_elements["wheel"] = wheel
	HudLayoutService.apply_control("wheel", wheel, ui.screens["drive"].size)
	DriveInput.regions = ui.controls
	SaveService.changed.connect(_update)
	_update()

func _update() -> void:
	var mode := DriveInput.effective_mode()
	var is_customizing: bool = ui.hud_customizer != null and is_instance_valid(ui.hud_customizer)
	var driving_controls := DriveInput.enabled or DriveInput.countdown_capture or is_customizing
	wheel.visible = mode == 0 and driving_controls
	if ui.controls.has("left"):
		ui.controls["left"].visible = mode == 1 and driving_controls
	if ui.controls.has("right"):
		ui.controls["right"].visible = mode == 1 and driving_controls
	if ui.controls.has("horn"):
		ui.controls.horn.visible = driving_controls

func _process(_delta: float) -> void:
	if ui.screen == "drive":
		_update()
