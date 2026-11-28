extends Node3D
# Low-poly articulated grip. World collision is checked without adding physics bodies.
var forearm: MeshInstance3D
var side := 1.0
var wrist := Vector3.ZERO
var skin: StandardMaterial3D
var nails: StandardMaterial3D
var fingers: Node3D
var arm_anchor: Node3D
var anchor_shoulder := Vector3.ZERO
var anchor_elbow := Vector3.ZERO
var upper_arm: MeshInstance3D
var elbow_joint: MeshInstance3D
var sleeve: MeshInstance3D

func configure(grip: Vector3,left: bool = false,under: bool = false) -> void:
	side = -1.0 if left else 1.0
	position = grip
	skin = StandardMaterial3D.new()
	skin.albedo_color = Color("#ba875f")
	skin.roughness = .84
	nails = StandardMaterial3D.new()
	nails.albedo_color = Color("#d3aa91")
	nails.roughness = .65
	fingers = Node3D.new()
	add_child(fingers)
	# Broad connected palm, knuckles and wrist. Fingers begin inside the
	# palm and use continuous curved meshes rather than separated beads.
	_oval(fingers,Vector3(side*.031,0,.002),Vector3(.077,.037,.088),skin)
	_oval(fingers,Vector3(side*.058,-.002,.023),Vector3(.057,.035,.058),skin)
	for i in range(4):
		var z := -.030+float(i)*.019
		var length: float = [.064,.073,.069,.055][i]
		var bend := -.012 if under else -.023
		var points: Array[Vector3] = [
			Vector3(side*.015,.001,z),
			Vector3(side*.002,.002,z),
			Vector3(-side*length*.40,bend*.35,z),
			Vector3(-side*length*.66,bend,z),
			Vector3(-side*length*.70,bend-.008,z)]
		var radii: Array[float] = [.012,.0115,.010,.008,.003]
		_skin_tube(points,radii)
		# A short nail stays on the distal segment instead of floating above it.
		var nail := _oval(fingers,points[3]+Vector3(0,.006,0),Vector3(.012,.003,.011),nails)
		nail.rotation.z = side*(.10 if under else .42)
	var thumb_points: Array[Vector3] = [
		Vector3(side*.045,.002,-.030),
		Vector3(side*.030,.013,-.046),
		Vector3(side*.006,.017,-.052),
		Vector3(-side*.009,.013,-.042)]
	var thumb_radii: Array[float] = [.016,.013,.011,.005]
	_skin_tube(thumb_points,thumb_radii)
	wrist = Vector3(side*.072,-.002,.028)
	_oval(fingers,wrist,Vector3(.049,.034,.047),skin)
	# Taper from wrist to elbow; use a dedicated segment instead of
	# stretching a sphere across the entire screen.
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = .023
	arm_mesh.bottom_radius = .035
	arm_mesh.height = 1.0
	arm_mesh.radial_segments = 12
	forearm = MeshInstance3D.new()
	forearm.mesh = arm_mesh
	forearm.material_override = skin
	forearm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(forearm)
	forearm.position = wrist
	forearm.hide()

func _skin_tube(points: Array[Vector3],radii: Array[float]) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for i in range(points.size()):
		var tangent := (points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]).normalized()
		var axis := tangent.cross(Vector3.BACK).normalized()
		var ring := PackedVector3Array()
		for j in range(10):
			var angle := TAU*float(j)/10.0
			ring.append(points[i]+(axis*cos(angle)+Vector3.BACK*sin(angle))*radii[i])
		rings.append(ring)
	for i in range(rings.size()-1):
		for j in range(10):
			var k := (j+1)%10
			for vertex in [rings[i][j],rings[i+1][j],rings[i][k],rings[i][k],rings[i+1][j],rings[i+1][k]]:
				surface.add_vertex(vertex)
	for j in range(10):
		surface.add_vertex(points.back())
		surface.add_vertex(rings.back()[j])
		surface.add_vertex(rings.back()[(j+1)%10])
	surface.generate_normals()
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	var material := skin.duplicate() as StandardMaterial3D
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fingers.add_child(mesh)

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

# For fixed world interactions, use body-relative joints instead of
# shortening the arm toward a moving camera.
func configure_body_arm(anchor: Node3D,shoulder: Vector3,elbow: Vector3,shirt_material: Material) -> void:
	arm_anchor = anchor
	anchor_shoulder = shoulder
	anchor_elbow = elbow
	upper_arm = _arm_piece(.035,.046,skin)
	elbow_joint = _oval(self,Vector3.ZERO,Vector3(.074,.074,.074),skin)
	sleeve = _arm_piece(.049,.055,shirt_material)
	upper_arm.hide()
	elbow_joint.hide()
	sleeve.hide()

func _arm_piece(top: float,bottom: float,mat: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = 1.0
	mesh.radial_segments = 12
	node.mesh = mesh
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return node

func _place_arm_segment(part: MeshInstance3D,tip: Vector3,base: Vector3) -> void:
	var axis := (tip-base).normalized()
	var x := axis.cross(Vector3.BACK if absf(axis.z)<.95 else Vector3.RIGHT).normalized()
	var z := x.cross(axis).normalized()
	var basis := Basis(x,axis,z).scaled_local(Vector3(1.0,tip.distance_to(base)+.014,1.0))
	part.global_transform = Transform3D(basis,tip.lerp(base,.5))

func _arm_segment_clear(camera: Camera3D,from: Vector3,to: Vector3,radius: float) -> bool:
	var space := camera.get_world_3d().direct_space_state
	var q := _sphere_query(from,radius,camera)
	if not space.intersect_shape(q,1).is_empty(): return false
	q.motion = to-from
	var result := space.cast_motion(q)
	return result.size()>0 and result[0]>=.985

func _pose_body_arm(camera: Camera3D,wrist_world: Vector3) -> void:
	var shoulder := arm_anchor.to_global(anchor_shoulder)
	var elbow := arm_anchor.to_global(anchor_elbow)
	var clear := fingers.visible and _arm_segment_clear(camera,wrist_world,elbow,.028) and _arm_segment_clear(camera,elbow,shoulder,.036)
	forearm.visible = clear
	upper_arm.visible = clear
	elbow_joint.visible = clear
	sleeve.visible = clear
	fingers.visible = clear
	if not clear: return
	_place_arm_segment(forearm,wrist_world,elbow)
	_place_arm_segment(upper_arm,elbow,shoulder)
	elbow_joint.global_position = elbow
	_place_arm_segment(sleeve,elbow.lerp(shoulder,.52),shoulder)

func _physics_process(_delta: float) -> void:
	if not is_visible_in_tree() or not is_instance_valid(forearm): return
	var camera := get_viewport().get_camera_3d()
	if camera==null: return
	var space := get_world_3d().direct_space_state
	var wrist_world := to_global(wrist)
	var grip_query := _sphere_query(to_global(Vector3(side*.032,0,.012)),.032,camera)
	fingers.visible = space.intersect_shape(grip_query,1).is_empty()
	if is_instance_valid(arm_anchor):
		_pose_body_arm(camera,wrist_world)
		return
	var shoulder := camera.to_global(Vector3(side*.32,-.46,.03))
	var direction := shoulder-wrist_world
	if direction.length_squared()<.0001 or not fingers.visible:
		forearm.hide()
		return
	var length := minf(direction.length(),.43)
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
	var arm_axis := (wrist_world-end).normalized()
	var arm_x := arm_axis.cross(Vector3.BACK if absf(arm_axis.z)<.95 else Vector3.RIGHT).normalized()
	var arm_z := arm_x.cross(arm_axis).normalized()
	var arm_basis := Basis(arm_x,arm_axis,arm_z).scaled_local(Vector3(1.0,length+.018,1.0))
	forearm.global_transform = Transform3D(arm_basis,wrist_world.lerp(end,.5))
