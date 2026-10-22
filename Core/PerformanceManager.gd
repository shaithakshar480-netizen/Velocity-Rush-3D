class_name PerformanceManager
extends Node
## Ordered visual downgrades, never a change to physics, traffic count or race logic.
## LOW (level 0): 30 FPS, 60 % scale, no MSAA, no AF, shadows 25 m, fallback always on.
## MEDIUM (level 1): 30+ FPS target, 80 % scale, no MSAA, 2x AF, shadows 55 m.
## HIGH (level 2): 60 FPS target, 100 % scale, 2x MSAA, 4x AF, shadows 90 m.
## Adaptive: FPS measured over 5-s windows; 2 consecutive below threshold → next stage.
## Hysteresis: counter resets on any good window; no automatic upgrades.
## Adaptive costs never lower the selected render scale or texture filtering.
signal fallback_changed(active: bool)
var level: int = 1
var visual_level: int = 1
var effects_level: int = 1
var degrade_stage: int = 0
var elapsed: float = 0.0
var samples: int = 0
var slow_windows: int = 0
var fallback: bool = false
var highway: Highway
var driving: bool = false
var applied_shadow_size: int = -1
var applied_road_quality: int = -1
## Render scales: LOW 60 %, MEDIUM 80 %, HIGH 100 %.
const SCALES: Array[float] = [0.60, 0.80, 1.0]
const SHADOW_SIZES: Array[int] = [512, 1024, 2048]
## Adaptive threshold: 38 FPS – triggers before hard 30 FPS drops on weak devices.
const FPS_THRESHOLD: float = 38.0

func apply_quality() -> void:
	level = clampi(int(SaveService.settings["quality"]), 0, 2)
	degrade_stage = 0
	fallback = level == 0
	elapsed = 0.0
	samples = 0
	slow_windows = 0
	_apply_costs()

func _apply_costs() -> void:
	visual_level = 0 if degrade_stage >= 6 else (maxi(level - 1, 0) if degrade_stage >= 5 else level)
	effects_level = maxi(level - 1, 0) if degrade_stage >= 1 else level
	if degrade_stage >= 4:
		effects_level = 0
	fallback = level == 0 or degrade_stage >= 6

	# Frame-rate cap: LOW always 30; MEDIUM/HIGH 60 unless adaptive fallback.
	Engine.max_fps = 30 if (fallback or level == 0) else 60

	# Shadow atlas size per quality tier.
	var shadow_size: int = SHADOW_SIZES[0] if degrade_stage >= 3 else SHADOW_SIZES[level]
	if shadow_size!=applied_shadow_size:
		RenderingServer.directional_shadow_atlas_set_size(shadow_size,true)
		applied_shadow_size = shadow_size

	# Preserve selected image resolution; fallback still reduces effects/shadows and caps FPS.
	get_viewport().scaling_3d_scale = SCALES[level]

	# Anisotropic filtering:
	#   LOW  → disabled (saves bandwidth on Mali/Adreno entry chips)
	#   MED  → 2x (mild improvement, very low cost)
	#   HIGH → 4x (16x is wasteful at racing speeds on mobile)
	var af: int
	if level >= 2:
		af = Viewport.ANISOTROPY_4X
	elif level == 1:
		af = Viewport.ANISOTROPY_2X
	else:
		af = Viewport.ANISOTROPY_DISABLED
	get_viewport().anisotropic_filtering_level = af

	# MSAA:
	#   LOW  → disabled (fill-rate is the primary bottleneck)
	#   MED  → disabled (use resolution scale instead; far cheaper)
	#   HIGH → 2x only (4x is too costly on 6 GB class phones at 60 FPS)
	if level == 2 and not fallback and degrade_stage < 3:
		get_viewport().msaa_3d = Viewport.MSAA_2X
	else:
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED

	if is_instance_valid(highway):
		var road_quality: int = 0 if fallback else (maxi(level - 1,0) if degrade_stage>=2 else level)
		if applied_road_quality!=road_quality or highway.quality!=road_quality:
			highway.set_quality(road_quality)
			applied_road_quality = road_quality
		if "sky_variants" in highway and highway.sky_variants != null and not highway.sky_variants.is_empty():
			highway.lighting.sky = highway.sky_variants[0 if fallback else (maxi(level - 1, 0) if degrade_stage >= 4 else level)]
		highway.sun.shadow_enabled = not fallback and level > 0
		# Shadow projection distances per tier – kept short to limit shadow map cost.
		var sdist: float = [25.0, 55.0, 90.0][visual_level]
		if degrade_stage >= 3:
			sdist = minf(sdist, 35.0)
		highway.sun.directional_shadow_max_distance = sdist
		if fallback:
			highway.sun.shadow_enabled = false
	fallback_changed.emit(fallback)

func _process(delta: float) -> void:
	# Adaptive degradation active only while racing; idle/UI screens are excluded.
	if not driving or get_tree().paused or level == 0 or fallback:
		return
	elapsed += delta
	samples += 1
	if elapsed >= 5.0:
		var fps := samples / elapsed
		# Any good window resets the consecutive-slow counter (hysteresis).
		slow_windows = slow_windows + 1 if fps < FPS_THRESHOLD else 0
		elapsed = 0.0
		samples = 0
		# Two consecutive slow windows before each downgrade step.
		if slow_windows >= 2:
			degrade_stage = mini(degrade_stage + 1, 6)
			slow_windows = 0
			_apply_costs()
