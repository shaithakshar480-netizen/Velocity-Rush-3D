class_name RushDamageEffects
extends Node3D
## Fixed cosmetic pool: no rigid debris, no racing-time texture/mesh creation.
var scratches: Array[MeshInstance3D] = []
var scratch_material: StandardMaterial3D
var quality: int = 1
var clock: float = -1.0
var stage: int = 0
var emit_clock: float = 0.0
var particles: Array[MeshInstance3D] = []
var velocities: Array[Vector3] = []
var lives: Array[float] = []
var kinds: Array[int] = []
var debris: Array[MeshInstance3D] = []
var debris_velocity: Array[Vector3] = []
var debris_life: Array[float] = []
var last_pose: Transform3D
var pose_ready: bool = false
var flash: MeshInstance3D
var blast_left: float = 0.0
var cursor: int = 0
var smoke: ShaderMaterial
var flame: ShaderMaterial
var spark: StandardMaterial3D
func _ready() -> void:
	scratch_material = RoadGeometry.material(Color("35404b"),.12,.85)
	for i: int in 6:
		var mark := RoadGeometry.box(self,Vector3.ZERO,Vector3(.008,.002,.15+float(i%3)*.06),scratch_material)
		mark.rotation.y = -.3
		mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mark.visible = false
		scratches.append(mark)
	var gradient := Gradient.new()
	gradient.set_color(0,Color.WHITE)
	gradient.set_color(1,Color(1,1,1,0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 32
	texture.height = 32
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(.5,.5)
	texture.fill_to = Vector2(.5,1)
	smoke = ShaderMaterial.new()
	smoke.shader = preload("res://VFX/damage_sprite.gdshader")
	smoke.set_shader_parameter("tint",Color(.24,.26,.29,.65))
	flame = ShaderMaterial.new()
	flame.shader = smoke.shader
	flame.set_shader_parameter("fire",true)
	flame.set_shader_parameter("tint",Color(1,1,1,.9))
	spark = _material(Color("ffd895"),texture)
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	for i: int in 48:
		var part := MeshInstance3D.new()
		part.mesh = mesh
		part.material_override = smoke
		part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		part.visible = false
		add_child(part)
		particles.append(part)
		velocities.append(Vector3.ZERO)
		lives.append(0.0)
		kinds.append(0)
 
	var piece_mesh := BoxMesh.new()
	piece_mesh.size = Vector3(.12,.045,.22)
	var piece_material := RoadGeometry.material(Color("272e36"),.4,.7)
	for i: int in 10:
		var piece := MeshInstance3D.new()
		piece.mesh = piece_mesh
		piece.scale = Vector3(1.0+float(i%3)*0.65,1.0,1.0+float(i%4)*0.4)
		piece.material_override = piece_material
		piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piece.visible = false
		add_child(piece)
		debris.append(piece)
		debris_velocity.append(Vector3.ZERO)
		debris_life.append(0.0)
	flash = MeshInstance3D.new()
	flash.mesh = mesh
	flash.material_override = flame
	flash.visible = false
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flash)
func explode() -> void:
	blast_left = .22
	flash.visible = true
	flash.position = Vector3(0,.9,-1)
	flash.scale = Vector3.ONE*2.4
	for i: int in [3,6,10][clampi(quality,0,2)]:
		debris[i].visible = true
		debris[i].scale = Vector3(1.0+float(i%3)*.65,1.0,1.0+float(i%4)*.4)
		debris[i].position = Vector3(0,.7,-1)
		var angle: float = float(i)*2.399
		debris_velocity[i] = global_basis*Vector3(sin(angle)*(3.0+i*.24),3.4+float(i%4)*.7,cos(angle)*(3.0+i*.24))
		debris_life[i] = 3.6+float(i%3)*.35
	for i: int in (4 if quality==0 else 12):
		_spawn(1,.9,i)
	for i: int in (2 if quality==0 else 5):
		_spawn(0,.8,i)
	impact(1)
func _material(color: Color, texture: Texture2D) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = texture
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.no_depth_test = false
	return mat
func configure(id: String) -> void:
	var data := RushVehicleCatalog.definition(id)
	for i: int in scratches.size():
		# Narrow scuffs on the hood center, below the hood camera's clearance margin.
		scratches[i].position = Vector3(-.12+i*.045,float(data.hood_y)+.015,float(data.windshield_z)-.38+float(i%2)*.10)
func reset() -> void:
	clock = -1
	pose_ready = false
	for mark: MeshInstance3D in scratches:
		mark.visible = false
	blast_left = 0
	flash.visible = false
	for piece: MeshInstance3D in debris:
		piece.visible = false
	stage = 0
	emit_clock = 0
	for i: int in particles.size():
		particles[i].visible = false
		lives[i] = 0
func impact(strength: float) -> void:
	for i: int in (3 if quality==0 else 7):
		_spawn(2,strength,i)
func destroy() -> void:
	clock = 0
	impact(1)
func _spawn(kind: int, strength: float, seed_value: int) -> void:
	var capacity: int = [16,30,48][clampi(quality,0,2)]
	var index := cursor%int(capacity)
	cursor += 1
	var part := particles[index]
	var angle := float(seed_value)*2.399+float(cursor)*.4
	part.position = Vector3(sin(angle)*.28,.55,-1.05)
	velocities[index] = global_basis*Vector3(sin(angle)*(3.0 if kind==2 else .5),(.8+strength if kind==0 else 1.8+strength*2.0),cos(angle)*(3.0 if kind==2 else .5))
	part.material_override = spark if kind==2 else (flame if kind==1 else smoke)
	part.scale = Vector3(.09,.20,.09) if kind==2 else (Vector3(.38,.72,.38) if kind==1 else Vector3.ONE*.42)
	part.visible = true
	lives[index] = .45 if kind==2 else (1.1 if kind==1 else 2.1)
	kinds[index] = kind
func _process(delta: float) -> void:
	# Existing director follows the car. Leave emitted smoke/debris behind in world space.
	if pose_ready:
		var shift: Vector3 = global_position-last_pose.origin
		if shift.length_squared()>6400.0:
			last_pose.origin += shift # Floating-origin rebase/teleport; avoid long trails.
		var compensation: Transform3D = global_transform.affine_inverse()*last_pose
		for i: int in particles.size():
			if lives[i]>0.0: particles[i].position = compensation*particles[i].position
		for i: int in debris.size():
			if debris[i].visible: debris[i].position = compensation*debris[i].position
	last_pose = global_transform
	pose_ready = true
	for mark: MeshInstance3D in scratches:
		mark.visible = stage>=1
	blast_left = maxf(0,blast_left-delta)
	flash.visible = blast_left>0
	flash.scale = Vector3.ONE*(2.4+(1-blast_left/.22)*2)
	for i: int in debris.size():
		if not debris[i].visible:
			continue
		debris_life[i] -= delta
		debris_velocity[i].y -= 9.8*delta
		debris[i].global_position += debris_velocity[i]*delta
		debris[i].rotation += Vector3(2.0+i*.15,1,3)*delta
		var floor_y: float = RushRoadFrame.SURFACE_Y+.08
		if debris[i].global_position.y<floor_y:
			debris[i].global_position.y = floor_y
			debris_velocity[i].y = absf(debris_velocity[i].y)*.32 if debris_velocity[i].y < -.8 else 0.0
			debris_velocity[i].x *= exp(-7.0*delta)
			debris_velocity[i].z *= exp(-7.0*delta)
		if debris_life[i]<.4:
			debris[i].scale *= maxf(0.0,1.0-delta*8.0)
		debris[i].visible = debris_life[i]>0.0
	if clock>=0:
		clock += delta
	if (stage>=2 and clock<0) or (clock>=0 and clock<10.0):
		emit_clock -= delta
		if emit_clock<=0:
			emit_clock = .45 if quality==0 else .13
			_spawn(0,.4,cursor)
			if (stage>=3 and clock<0) or (clock>.15 and clock<7.0):
				_spawn(1,.65,cursor)
			if clock>.5 and clock<1.1:
				impact(.7)
	var any_live: bool = false
	for i: int in particles.size():
		if lives[i] <= 0:
			continue
		any_live = true
		lives[i] -= delta
		particles[i].global_position += velocities[i]*delta
		if kinds[i]==2:
			velocities[i].y -= 8*delta
		else:
			particles[i].scale += Vector3.ONE*delta*(.6 if kinds[i]==0 else .24)
		if lives[i]<.25:
			particles[i].scale *= maxf(0,1-delta*10)
		particles[i].visible = lives[i]>0
	# If nothing was live, a bulk hide sweep ensures no stale visible quads remain.
	if not any_live and blast_left <= 0 and clock < 0:
		for i: int in particles.size():
			if particles[i].visible: particles[i].visible = false
