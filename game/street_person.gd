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
var age_group := "adulto"
var gait := 1.0
var leisure_prop: Node3D
var phone_idle := false
var knees: Array[Node3D] = []

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

func _part(root: Node3D,kind: String,p: Vector3,dims: Vector3,color: Color,detail: bool = false) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = _mesh(kind)
	node.material_override = _material(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if detail:
		node.visibility_range_end = 38.0
		node.visibility_range_end_margin = 4.0
	root.add_child(node)
	node.position = p
	node.scale = dims
	return node

func setup(style: int,worker: bool = false,ambient: bool = false) -> void:
	style_id = style
	female = not worker and posmod(style,3)==1
	add_to_group("social_people")
	add_to_group("pedestrian_spacing")
	# Deterministic wardrobe: no random allocations or extra per-frame logic.
	var variant := floori(float(style)/3.0)
	var skin_colors: Array[Color] = [Color("#9b694b"),Color("#cc9b75"),Color("#70482f"),Color("#e1b797"),Color("#ac7a52")]
	var shirts: Array[Color] = [Color("#d6cfb6"),Color("#667e99"),Color("#9c6a68"),Color("#72918a"),Color("#e1e0da"),Color("#8d856c"),Color("#d85624"),Color("#922e42"),Color("#282e33"),Color("#c39b39")]
	var trousers: Array[Color] = [Color("#4d5a64"),Color("#345472"),Color("#32353a"),Color("#718eaa"),Color("#827d65")]
	var skin: Color = skin_colors[posmod(style,skin_colors.size())]
	var shirt: Color = Color("#d48a3c") if worker else shirts[posmod(variant+style,shirts.size())]
	var pants: Color = Color("#526456") if worker else trousers[posmod(variant,trousers.size())]
	var outfit := posmod(variant,5)
	var shorts := not worker and (outfit==1 or outfit==3)
	if female and outfit==1:
		shirt = Color("#d85624")
		pants = shirt
	elif female and outfit==3:
		shirt = Color("#922e42")
		pants = shirt
	var build := posmod(variant,4)
	var torso_width: float = .43 if worker else .37+float(build)*.04
	var hip_width := .35 if worker else (.36+float(build)*.025 if female else .32+float(build)*.018)
	var depth := .27 if worker else .24+float(build)*.025
	var height := 0.94+float(posmod(style,5))*.035
	if ambient and posmod(variant,13)==0:
		age_group = "menor"
		height *= .73
		gait = 1.13
	elif ambient and posmod(variant,7)==0:
		age_group = "mayor"
		height *= .94
		gait = .76
	scale = Vector3(height,height,height)
	_part(self,"limb",Vector3(0,1.18,0),Vector3(torso_width,.58,depth),shirt)
	_part(self,"head",Vector3(0,.88,0),Vector3(hip_width,.23,depth),pants)
	_part(self,"limb",Vector3(0,1.48,0),Vector3(.14,.16,.13),skin)
	_part(self,"head",Vector3(0,1.66,.015),Vector3(.28,.34,.29),skin)
	var hair_colors: Array[Color] = [Color("#231e1b"),Color("#302b28"),Color("#4b3428"),Color("#3c3531")]
	var hair: Color = Color("#d5c14b") if worker else hair_colors[posmod(variant,hair_colors.size())]
	if age_group=="mayor": hair = Color("#a29d96")
	_part(self,"head",Vector3(0,1.77,-.028),Vector3(.29,.17,.29),hair)
	_part(self,"head",Vector3(0,1.65,.155),Vector3(.055,.067,.048),skin,true)
	for side in [-1.0,1.0]:
		_part(self,"box",Vector3(float(side)*.060,1.69,.146),Vector3(.045,.022,.014),Color("#d9d3c9"),true)
		_part(self,"box",Vector3(float(side)*.060,1.69,.156),Vector3(.017,.019,.008),Color("#302823"),true)
	_part(self,"box",Vector3(0,1.59,.149),Vector3(.062,.012,.009),Color("#805345"),true)
	var shoe: Color = Color("#393832") if worker or outfit==0 else (Color("#e1ddd4") if outfit%2==1 else Color("#464b50"))
	for side in [-1.0,1.0]:
		var x := float(side)
		var leg := Node3D.new()
		add_child(leg)
		leg.position = Vector3(x*.10,.86,0)
		limbs.append(leg)
		var thigh_width := .17 if worker else .15+float(build)*.014
		if shorts:
			_part(leg,"limb",Vector3(0,-.105,0),Vector3(thigh_width,.21,.18),pants)
			_part(leg,"limb",Vector3(0,-.315,0),Vector3(thigh_width*.88,.21,.16),skin)
		else:
			_part(leg,"limb",Vector3(0,-.21,0),Vector3(thigh_width,.42,.18),pants)
		var knee := Node3D.new()
		leg.add_child(knee)
		knee.position = Vector3(0,-.42,0)
		knees.append(knee)
		_part(knee,"limb",Vector3(0,-.17,0),Vector3(.13,.36,.14),skin if shorts else pants)
		_part(knee,"box",Vector3(0,-.38,.05),Vector3(.16,.12,.27),shoe)
		var arm := Node3D.new()
		add_child(arm)
		# Preserve shoulder/leg pivots used by the rescue choreography.
		arm.position = Vector3(x*.25,1.38,0)
		arms.append(arm)
		_part(arm,"limb",Vector3(0,-.12,0),Vector3(.14,.26,.15),shirt if worker or outfit!=3 else skin)
		_part(arm,"limb",Vector3(0,-.34,0),Vector3(.105,.22,.11),skin)
		_part(arm,"head",Vector3(0,-.49,0),Vector3(.105,.13,.11),skin)
	if female:
		var hairstyle := posmod(variant,4)
		if hairstyle==0:
			_part(self,"head",Vector3(0,1.61,-.13),Vector3(.30,.31,.20),hair)
			_part(self,"head",Vector3(0,1.73,-.18),Vector3(.17,.17,.16),hair)
		elif hairstyle==1:
			_part(self,"head",Vector3(0,1.41,-.16),Vector3(.32,.73,.21),hair)
			_part(self,"head",Vector3(0,1.58,-.19),Vector3(.35,.43,.24),hair)
		elif hairstyle==2:
			_part(self,"head",Vector3(0,1.61,-.09),Vector3(.37,.42,.33),hair)
			_part(self,"head",Vector3(0,1.46,-.15),Vector3(.32,.33,.23),hair)
		else:
			_part(self,"head",Vector3(0,1.69,-.11),Vector3(.29,.24,.22),hair)
			_part(self,"head",Vector3(0,1.43,-.18),Vector3(.13,.43,.16),hair)
		# Everyday shoulder bag; cosmetic only, independent of carried goods.
		if outfit==1 or outfit==4:
			var bag := Color("#16734f") if outfit==1 else Color("#343637")
			_part(self,"box",Vector3(.25,1.02,-.10),Vector3(.25,.34,.13),bag,true)
			_part(self,"box",Vector3(.22,1.29,-.11),Vector3(.045,.31,.035),bag,true)
	if ambient and age_group=="adulto" and posmod(variant,5)==0:
		leisure_prop = Node3D.new()
		arms[1].add_child(leisure_prop)
		leisure_prop.position = Vector3(0,-.48,.05)
		_part(leisure_prop,"box",Vector3.ZERO,Vector3(.065,.115,.018),Color("#262b2e"),true)
		leisure_prop.hide()
	if worker:
		social_context = "worker"
		_part(self,"box",Vector3(0,1.14,.14),Vector3(.38,.075,.018),Color("#eee0a0"))
		_part(self,"box",Vector3(0,1.14,-.14),Vector3(.38,.075,.018),Color("#eee0a0"))

func animate(delta: float,moving: bool,run_speed: float = 0.0) -> void:
	var sprint := clampf((run_speed-4.5)/4.0,0.0,1.0) if moving else 0.0
	if moving: phase += delta*9.5*gait*(1.0+sprint*.55)
	var use_phone := phone_idle and not moving and carried==null and not has_meta("incident_role")
	if is_instance_valid(leisure_prop): leisure_prop.visible = use_phone
	for i in range(limbs.size()):
		var stride := sin(phase+float(i)*PI) if moving else 0.0
		var swing := stride*lerpf(.43,.76,sprint)
		var blend := minf(1.0,delta*15.0)
		limbs[i].rotation.x = lerpf(limbs[i].rotation.x,swing,blend)
		knees[i].rotation.x = lerpf(knees[i].rotation.x,maxf(0.0,-stride)*lerpf(.48,1.02,sprint),blend)
		var arm_pose := -swing*.72 if carried==null else -.85
		if use_phone and i==1: arm_pose = -1.15
		arms[i].rotation.x = lerpf(arms[i].rotation.x,arm_pose,blend)

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
