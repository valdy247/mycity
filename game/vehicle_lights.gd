extends RefCounted
# All traffic shares two emissive materials. Only the occupied vehicle
# receives one real, shadowless road light from the main controller.
static var night := false
static var front_material: StandardMaterial3D
static var rear_material: StandardMaterial3D
static var lamp_mesh := BoxMesh.new()

static func is_night(minutes: float) -> bool:
	var minute := fposmod(minutes,1440.0)
	return minute>=1080.0 or minute<420.0

static func _material(rear: bool) -> StandardMaterial3D:
	if rear and rear_material!=null: return rear_material
	if not rear and front_material!=null: return front_material
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color("#ff3434") if rear else Color("#fff0c6")
	if rear: rear_material = mat
	else: front_material = mat
	return mat

static func _pair(root: Node3D,center: Vector3,size: Vector3,rear: bool) -> void:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = lamp_mesh
	multi.instance_count = 2 if absf(center.x)>.01 else 1
	for i in range(multi.instance_count):
		var p := center
		if i==1: p.x = -p.x
		multi.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(size),p))
	var visual := MultiMeshInstance3D.new()
	visual.multimesh = multi
	visual.material_override = _material(rear)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visual.visibility_range_end = 100.0
	visual.visibility_range_end_margin = 5.0
	root.add_child(visual)

static func attach(body: Node3D,front: Vector3,rear: Vector3,front_size: Vector3,rear_size: Vector3) -> void:
	if body.has_meta("night_lamp_front"): return
	var root := Node3D.new()
	root.name = "NightLamps"
	body.add_child(root)
	root.add_to_group("vehicle_night_lamps")
	_pair(root,front,front_size,false)
	_pair(root,rear,rear_size,true)
	root.visible = night
	body.set_meta("night_lamp_front",Vector3(0,front.y,front.z))

static func update_time(tree: SceneTree,minutes: float) -> void:
	var enabled := is_night(minutes)
	if enabled==night: return
	night = enabled
	for node in tree.get_nodes_in_group("vehicle_night_lamps"):
		if node is Node3D: node.visible = night
