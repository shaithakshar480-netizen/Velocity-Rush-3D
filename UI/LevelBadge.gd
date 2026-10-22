class_name RushLevelBadge
extends VBoxContainer
## One styled component shared by Home, Profile and Results. No textures.
var caption: Label
var bar: ProgressBar
var detail: Label
func build(ui: Node) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	caption = ui._label(row, "", 14, ui.ACCENT)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail = ui._label(row, "", 12, ui.MUTED)
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, 11)
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := StyleBoxFlat.new()
	track.bg_color = Color("05101a")
	track.border_color = Color("183244")
	track.set_border_width_all(1)
	track.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("38d9f5")
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)
	add_child(bar)
	refresh()
func refresh() -> void:
	var p: Dictionary = SaveService.progression
	var level := int(p.level)
	caption.text = tr("LEVEL %d")%level
	var progress := int(p.xp)-RushProgressionData.threshold(level)
	var capped := level>=int(RushProgressionData.spec.max_level)
	bar.value = 100.0 if capped else 100.0*progress/RushProgressionData.required(level)
	detail.text = tr("MAX LEVEL  •  %d TOTAL XP")%int(p.xp) if capped else tr("%d / %d XP")%[progress,RushProgressionData.required(level)]
