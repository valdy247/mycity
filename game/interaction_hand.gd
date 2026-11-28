extends Node3D
# Low-poly articulated grip. World collision is checked without adding physics bodies.
var forearm: MeshInstance3D
var side := 1.0
var wrist := Vector3.ZERO
var skin: StandardMaterial3D
var nails: StandardMaterial3D
var fingers: Node3D

func configure(grip: Vector3,left: bool = false,under: bool = false) -> void:
	side = -1.0 if left else 1.0
	position = grip
	skin = StandardMaterial3D.new()
	skin.albedo_color = Color("#ba875f")
	skin.roughness = .84
	nails = StandardMaterial3D.new()
	nails.albedo_color = Color("#cda38b")
	nails.roughness = .62
	fingers = Node3D.new()
	add_child(fingers)
	_oval(fingers,Vector3(side*.026,0,.012),Vector3(.072,.030,.086),skin)
	_oval(fingers,Vector3(side*.047,-.002,.044),Vector3(.052,.033,.045),skin)
	for i in range(4):
		var z := -.030+float(i)*.020
		var length: float = [.039,.047,.044,.034][i]
		var knuckle := Node3D.new()
		fingers.add_child(knuckle)
		knuckle.position = Vector3(-side*.004,.002,z)
		knuckle.rotation.z = side*(.10 if under else .34)
		_oval(knuckle,Vector3(-side*length*.26,0,0),Vector3(length*.68,.019,.019),skin)
		var tip := Node3D.new()
		knuckle.add_child(tip)
		tip.position.x = -side*length*.52
		tip.rotation.z = side*(.12 if under else .68)
		_oval(tip,Vector3(-side*length*.22,0,0),Vector3(length*.57,.017,.017),skin)
		_oval(tip,Vector3(-side*length*.34,.007,0),Vector3(.013,.004,.012),nails)
	var thumb := Node3D.new()
	fingers.add_child(thumb)
	thumb.position = Vector3(side*.028,.012,-.044)
	thumb.rotation.y = side*.65
	_oval(thumb,Vector3(-side*.012,.006,-.006),Vector3(.035,.025,.026),skin)
	_oval(thumb,Vector3(-side*.031,.012,-.008),Vector3(.027,.020,.021),skin)
	wrist = Vector3(side*.048,-.003,.048)
	forearm = _oval(self,wrist,Vector3(.065,.059,.20),skin)

func _oval(root: Node3D,at: Vector3,dimensions: Vector3,mat: StandardMaterial3D) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 5
	visual.mesh = mesh
	visual.material_override = mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(visual)
	visual.position = at
	visual.scale = dimensions
	return visual

static func _excluded(camera: Camera3D) -> Array[RID]:
	var exclude: Array[RID] = []
	var ancestor: Node = camera
	while ancestor!=null:
		if ancestor is CollisionObject3D: exclude.append(ancestor.get_rid())
		ancestor = ancestor.get_parent()
	return exclude

static func _sphere_query(at: Vector3,radius: float,camera: Camera3D) -> PhysicsShapeQueryParameters3D:
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY,at)
	query.collision_mask = 1|2|4|8|16|32
	query.exclude = _excluded(camera)
	return query

static func camera_safe_pose(camera: Camera3D,desired: Vector3,radius: float) -> Vector3:
	# Sweep the held object from a near-camera origin, then check its endpoint.
	var space := camera.get_world_3d().direct_space_state
	var origin := camera.to_global(Vector3(desired.x*.22,desired.y*.22,-.09))
	var target := camera.to_global(desired)
	var q := _sphere_query(origin,radius,camera)
	q.motion = target-origin
	var motion := space.cast_motion(q)
	var fraction := 1.0
	if motion.size()>0: fraction = clampf(motion[0]-.025,0.0,1.0) if motion[0]<1.0 else 1.0
	var safe := origin.lerp(target,fraction)
	q.motion = Vector3.ZERO
	for i in range(7):
		q.transform.origin = safe
		if space.intersect_shape(q,1).is_empty(): return camera.to_local(safe)
		safe = safe.lerp(origin,.28)
	# No free pose: retract behind the near plane rather than draw through a solid.
	return Vector3(desired.x*.15,-.06,.20)

func _physics_process(_delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(forearm): return
	var camera := get_viewport().get_camera_3d()
	if camera==null: return
	var space := get_world_3d().direct_space_state
	var wrist_world := to_global(wrist)
	var grip_query := _sphere_query(to_global(Vector3(side*.024,0,.012)),.025,camera)
	fingers.visible = space.intersect_shape(grip_query,1).is_empty()
	var shoulder := camera.to_global(Vector3(side*.32,-.46,.03))
	var direction := shoulder-wrist_world
	if direction.length_squared()<.0001 or not fingers.visible:
		forearm.hide()
		return
	var length := minf(direction.length(),.55)
	var motion_query := _sphere_query(wrist_world,.027,camera)
	if not space.intersect_shape(motion_query,1).is_empty():
		forearm.hide()
		return
	motion_query.motion = direction.normalized()*length
	var motion := space.cast_motion(motion_query)
	if motion.size()>0: length *= clampf(motion[0]-.035,0.0,1.0) if motion[0]<1.0 else 1.0
	forearm.visible = length>.025
	if not forearm.visible: return
	var end := wrist_world+direction.normalized()*length
	forearm.global_position = wrist_world.lerp(end,.5)
	forearm.look_at(end,Vector3.UP if absf(direction.normalized().y)<.97 else Vector3.RIGHT)
	forearm.scale = Vector3(.065,.059,length)
