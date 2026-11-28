extends Node3D
# Lightweight shared low-poly hand: attached to the held object, never a collider.
var forearm: MeshInstance3D
var side := 1.0
var wrist := Vector3.ZERO
var skin: StandardMaterial3D

func configure(grip: Vector3, left: bool = false, under: bool = false) -> void:
	side = -1.0 if left else 1.0
	position = grip
	skin = StandardMaterial3D.new()
	skin.albedo_color = Color("#c59169")
	skin.roughness = .86
	var palm := _oval(Vector3(side*.025,0,.018),Vector3(.065,.035,.083))
	if not under: palm.rotation.z = side*.35
	for i in range(4):
		var finger := _oval(Vector3(-side*(.010+float(i)*.008),.008,.030-float(i)*.019),Vector3(.047,.018,.020))
		finger.rotation.z = -side*.28 if not under else 0.0
	_oval(Vector3(side*.018,.023,-.027),Vector3(.048,.024,.026)).rotation.y = side*.45
	wrist = Vector3(side*.047,-.008,.045)
	forearm = _oval(wrist,Vector3(.075,.070,.20))

func _oval(at: Vector3,dimensions: Vector3) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 5
	visual.mesh = mesh
	visual.material_override = skin
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	visual.position = at
	visual.scale = dimensions
	return visual

func _process(_delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(forearm): return
	var camera := get_viewport().get_camera_3d()
	if camera==null: return
	var shoulder := camera.to_global(Vector3(side*.32,-.52,.06))
	var wrist_world := to_global(wrist)
	var direction := shoulder-wrist_world
	var length := clampf(direction.length(),.09,.47)
	if direction.length_squared()<.0001: return
	var end := wrist_world+direction.normalized()*length
	forearm.global_position = wrist_world.lerp(end,.5)
	forearm.look_at(end,Vector3.UP if absf(direction.normalized().y)<.97 else Vector3.RIGHT)
	forearm.scale = Vector3(.075,.070,length+.025)
