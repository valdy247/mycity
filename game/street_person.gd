extends Node3D
# A shared low-poly articulated human for sidewalk life and municipal crews.
# All limbs reuse a small set of primitive meshes and materials.
static var meshes: Dictionary = {}
static var materials: Dictionary = {}
var limbs: Array[Node3D] = []
var arms: Array[Node3D] = []
var phase := 0.0
var last_position := Vector3.ZERO
var style_id := 0
var female := false
var social_context := "street"
var carried: Node3D

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not materials.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = .86
		materials[key] = mat
	return materials[key] as StandardMaterial3D

func _mesh(kind: String) -> Mesh:
	if not meshes.has(kind):
		if kind=="head":
			var sphere := SphereMesh.new()
			sphere.radius = .5
			sphere.height = 1.0
			sphere.radial_segments = 10
			sphere.rings = 5
			meshes[kind] = sphere
		elif kind=="limb":
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .48
			cylinder.bottom_radius = .40
			cylinder.height = 1.0
			cylinder.radial_segments = 8
			meshes[kind] = cylinder
		else:
			var box := BoxMesh.new()
			box.size = Vector3.ONE
			meshes[kind] = box
	return meshes[kind] as Mesh

func _part(root: Node3D,kind: String,p: Vector3,dims: Vector3,color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _mesh(kind)
	node.material_override = _material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	node.position = p
	node.scale = dims
	return node

func setup(style: int,worker: bool = false) -> void:
	style_id = style
	female = not worker and posmod(style,3)==1
	add_to_group("social_people")
	var skin_colors: Array[Color] = [Color("#9b694b"),Color("#cc9b75"),Color("#70482f"),Color("#e1b797"),Color("#ac7a52")]
	var shirts: Array[Color] = [Color("#d6cfb6"),Color("#667e99"),Color("#9c6a68"),Color("#72918a"),Color("#e1e0da"),Color("#8d856c")]
	var skin: Color = skin_colors[posmod(style,skin_colors.size())]
	var shirt: Color = Color("#d48a3c") if worker else shirts[posmod(style,shirts.size())]
	var pants := Color("#4d5a64") if not worker else Color("#526456")
	var height := 0.94+float(posmod(style,5))*.035
	scale = Vector3(height,height,height)
	_part(self,"limb",Vector3(0,1.18,0),Vector3(.43,.58,.27),shirt)
	_part(self,"box",Vector3(0,.88,0),Vector3(.35,.17,.25),pants)
	_part(self,"limb",Vector3(0,1.48,0),Vector3(.14,.16,.13),skin)
	_part(self,"head",Vector3(0,1.66,.015),Vector3(.28,.34,.29),skin)
	_part(self,"head",Vector3(0,1.77,-.028),Vector3(.29,.17,.29),Color("#302b28") if not worker else Color("#d5c14b"))
	_part(self,"box",Vector3(0,1.65,.155),Vector3(.064,.075,.055),skin)
	for side in [-1.0,1.0]:
		var x := float(side)
		var leg := Node3D.new()
		add_child(leg)
		leg.position = Vector3(x*.10,.86,0)
		limbs.append(leg)
		_part(leg,"limb",Vector3(0,-.21,0),Vector3(.17,.42,.18),pants)
		_part(leg,"limb",Vector3(0,-.59,0),Vector3(.13,.36,.14),pants)
		_part(leg,"box",Vector3(0,-.80,.05),Vector3(.16,.12,.27),Color("#393832"))
		var arm := Node3D.new()
		add_child(arm)
		arm.position = Vector3(x*.25,1.38,0)
		arms.append(arm)
		_part(arm,"limb",Vector3(0,-.12,0),Vector3(.14,.26,.15),shirt)
		_part(arm,"limb",Vector3(0,-.34,0),Vector3(.105,.22,.11),skin)
		_part(arm,"head",Vector3(0,-.49,0),Vector3(.105,.13,.11),skin)
	if female:
		_part(self,"head",Vector3(0,1.61,-.13),Vector3(.30,.31,.20),Color("#302b28"))
		_part(self,"head",Vector3(0,1.73,-.18),Vector3(.17,.17,.16),Color("#302b28"))
	if worker:
		social_context = "worker"
		_part(self,"box",Vector3(0,1.14,.14),Vector3(.38,.075,.018),Color("#eee0a0"))
		_part(self,"box",Vector3(0,1.14,-.14),Vector3(.38,.075,.018),Color("#eee0a0"))

func animate(delta: float,moving: bool) -> void:
	if moving: phase += delta*9.5
	for i in range(limbs.size()):
		var swing := sin(phase+float(i)*PI)*.43 if moving else 0.0
		limbs[i].rotation.x = lerpf(limbs[i].rotation.x,swing,minf(1.0,delta*15.0))
		arms[i].rotation.x = lerpf(arms[i].rotation.x,-swing*.72 if carried==null else -.85,minf(1.0,delta*15.0))

func conversation_active(delta: float) -> bool:
	if Time.get_ticks_msec()>=int(get_meta("conversation_until",0)): return false
	animate(delta,false)
	return true

func walk_to(target: Vector3,delta: float,speed: float = 1.4) -> bool:
	if conversation_active(delta): return false
	var diff := target-global_position
	if diff.length()<.12:
		global_position = target
		animate(delta,false)
		return true
	var flat := Vector3(diff.x,0,diff.z)
	if flat.length()>.03:
		rotation.y = lerp_angle(rotation.y,atan2(flat.x,flat.z),minf(1.0,delta*12.0))
	global_position = global_position.move_toward(target,speed*delta)
	animate(delta,true)
	return false

func set_bag(value: bool) -> void:
	if value and carried==null:
		carried = Node3D.new()
		add_child(carried)
		carried.position = Vector3(.05,.91,.36)
		_part(carried,"head",Vector3.ZERO,Vector3(.43,.46,.38),Color("#333a36"))
	elif not value and carried!=null:
		carried.queue_free()
		carried = null
