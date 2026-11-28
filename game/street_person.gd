extends Node3D
const Shoe = preload("res://character_shoe.gd")
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
# Story detail is limited to the main cast, not every city pedestrian.
const STORY_STYLES := [414,806,807,810,813,933,945]
var story_character := false
var idle_phase := 0.0
var stride_weight := 0.0
var facial_eyes: Array[MeshInstance3D] = []
var facial_blink := 0.0
var blink_clock := 0.0

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
		if kind=="head" or kind=="portrait":
			var sphere := SphereMesh.new()
			sphere.radius = .5
			sphere.height = 1.0
			sphere.radial_segments = 14 if kind=="portrait" else 10
			sphere.rings = 7 if kind=="portrait" else 5
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
	story_character = not worker and not ambient and style in STORY_STYLES
	female = not worker and posmod(style,3)==1 and not story_character
	blink_clock = 2.2+float(posmod(style,7))*.23
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
	var everyday := ambient and not worker and not story_character
	if everyday:
		# Independent palette selections reduce identical-looking neighbors.
		var ambient_skin: Array[Color] = [Color("#9b694b"),Color("#cc9b75"),Color("#70482f"),Color("#e1b797"),Color("#ac7a52"),Color("#845b43"),Color("#bf8967")]
		var ambient_shirts: Array[Color] = [Color("#d6cfb6"),Color("#667e99"),Color("#9c6a68"),Color("#72918a"),Color("#e1e0da"),Color("#8d856c"),Color("#d85624"),Color("#922e42"),Color("#282e33"),Color("#c39b39"),Color("#577d5a"),Color("#9a795d"),Color("#a5b4c4"),Color("#b8a0b7")]
		skin = ambient_skin[posmod(style*3+variant,ambient_skin.size())]
		shirt = ambient_shirts[posmod(style*11+variant*3,ambient_shirts.size())]
	var shorts := not worker and (outfit==1 or outfit==3)
	if female and outfit==1:
		shirt = Color("#d85624")
		pants = shirt
	elif female and outfit==3:
		shirt = Color("#922e42")
		pants = shirt
	# Stable wardrobe for recurring story characters; shared palette and meshes.
	if story_character:
		shorts = false
		match style:
			414: # Recurring taxi driver: mature Cuban man, open collar.
				shirt = Color("#c3bca9")
				pants = Color("#46515c")
			806: # Carlos: practical work shirt and faded jeans.
				shirt = Color("#c5b79a")
				pants = Color("#435b70")
			807: # Permanent Yordi identity, including motorcycle passengers.
				skin = Color("#e5b99b")
				shirt = Color("#983c3e")
				pants = Color("#373b42")
			810: # Albertico: green polo, dark blue trousers.
				shirt = Color("#638e77")
				pants = Color("#384b5c")
			813:
				shirt = Color("#8196b0")
				pants = Color("#414950")
			933:
				shirt = Color("#d2ae79")
				pants = Color("#474e54")
			945:
				shirt = Color("#a3a59a")
				pants = Color("#685e4e")
	var build := posmod(variant,4)
	var torso_width: float = .43 if worker else .37+float(build)*.04
	var hip_width := .35 if worker else (.36+float(build)*.025 if female else .32+float(build)*.018)
	var depth := .27 if worker else .24+float(build)*.025
	if style==414 and story_character:
		torso_width = .46
		hip_width = .37
		depth = .31
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
	# A rounded chest instead of a hard cylinder only on featured characters.
	_part(self,"portrait" if story_character else "limb",Vector3(0,1.18,0),Vector3(torso_width,.58,depth),shirt)
	_part(self,"head",Vector3(0,.88,0),Vector3(hip_width,.23,depth),pants)
	_part(self,"limb",Vector3(0,1.48,0),Vector3(.14,.16,.13),skin)
	_part(self,"portrait" if story_character else "head",Vector3(0,1.66,.015),Vector3(.28,.34,.29),skin)
	var hair_colors: Array[Color] = [Color("#231e1b"),Color("#302b28"),Color("#4b3428"),Color("#3c3531")]
	var hair: Color = Color("#d5c14b") if worker else hair_colors[posmod(variant,hair_colors.size())]
	if age_group=="mayor" or (story_character and style==414): hair = Color("#72716b")
	if story_character and style==807:
		var cap := Color("#303b43")
		_part(self,"portrait",Vector3(0,1.795,-.012),Vector3(.316,.155,.314),cap).name = "YordiCap"
		_part(self,"head",Vector3(0,1.748,.139),Vector3(.29,.040,.235),cap).name = "YordiCapBrim"
		_part(self,"head",Vector3(0,1.57,.055),Vector3(.247,.135,.22),Color("#514036")).name = "YordiBeard"
		for side in [-1.0,1.0]:
			_part(self,"head",Vector3(float(side)*.106,1.60,.045),Vector3(.055,.125,.14),Color("#514036"),true)
		_part(self,"head",Vector3(0,1.612,.145),Vector3(.108,.026,.028),Color("#514036"),true)
	elif everyday and not female:
		_ambient_hair(variant,hair)
	else:
		_part(self,"head",Vector3(0,1.77,-.028),Vector3(.29,.17,.29),hair)
	var nose_size := Vector3(.055,.067,.048)
	if everyday:
		nose_size.x += float(posmod(variant,3)-1)*.008
		nose_size.y += float(posmod(style,3)-1)*.007
	_part(self,"head",Vector3(0,1.65,.155),nose_size,skin,true)
	for side in [-1.0,1.0]:
		var eye := _part(self,"box",Vector3(float(side)*.060,1.69,.146),Vector3(.045,.022,.014),Color("#d9d3c9"),true)
		var pupil := _part(self,"box",Vector3(float(side)*.060,1.69,.156),Vector3(.017,.019,.008),Color("#302823"),true)
		if story_character:
			facial_eyes.append(eye)
			facial_eyes.append(pupil)
			_part(self,"head",Vector3(float(side)*.141,1.655,.005),Vector3(.054,.095,.053),skin,true)
			_part(self,"box",Vector3(float(side)*.060,1.723,.143),Vector3(.050,.012,.012),hair,true)
	_part(self,"box",Vector3(0,1.59,.149),Vector3(.062,.012,.009),Color("#805345"),true)
	if story_character:
		# A few tiny accessories, culled beyond the existing detail distance.
		_part(self,"limb",Vector3(0,.974,0),Vector3(hip_width*.98,.045,depth*.99),Color("#40372d"),true)
		_part(self,"box",Vector3(0,.978,depth*.52),Vector3(.049,.031,.012),Color("#887c65"),true)
		if style==806:
			_part(self,"box",Vector3(-.10,1.26,depth*.49),Vector3(.088,.088,.018),shirt.darkened(.16),true)
		elif style==807:
			_part(self,"box",Vector3(.10,1.26,depth*.49),Vector3(.040,.028,.012),Color("#cbbca9"),true)
		elif style==810:
			_part(self,"box",Vector3(0,1.38,depth*.47),Vector3(.06,.13,.016),shirt.darkened(.22),true)
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
		var footwear := _part(knee,"box",Vector3(0,-.38,.055),Vector3(.165,.12,.28),shoe)
		footwear.mesh = Shoe.mesh()
		footwear.material_override = Shoe.material(footwear.material_override as StandardMaterial3D)
		var arm := Node3D.new()
		add_child(arm)
		# Preserve shoulder/leg pivots used by the rescue choreography.
		arm.position = Vector3(x*(torso_width*.42+.012),1.37,0)
		arms.append(arm)
		# Rounded shoulder overlaps the chest instead of leaving a cylinder cap.
		_part(arm,"head",Vector3(x*.012,-.085,0),Vector3(.175,.31,.18),shirt if worker or outfit!=3 or story_character else skin)
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
	if everyday:
		_ambient_clothing(variant,shirt,torso_width,depth)
		_ambient_face(variant,hair)
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

# Ambient pedestrians only. Keep story characters and municipal uniforms intact.
# Hair silhouettes use the existing shared sphere; tiny decorations use the
# existing 38-metre visibility range and never change the articulated rig.
func _ambient_hair(variant: int,hair: Color) -> void:
	var choice := posmod(variant,5)
	match choice:
		0:
			_part(self,"head",Vector3(0,1.755,-.020),Vector3(.278,.112,.279),hair).name = "AmbientHairCropped"
		1:
			_part(self,"head",Vector3(0,1.785,-.027),Vector3(.304,.198,.30),hair).name = "AmbientHairCurly"
			_part(self,"head",Vector3(-.065,1.824,-.015),Vector3(.143,.135,.16),hair)
			_part(self,"head",Vector3(.063,1.824,-.025),Vector3(.145,.135,.16),hair)
		2:
			var caps: Array[Color] = [Color("#393e45"),Color("#7d5143"),Color("#727b61")]
			var cap: Color = caps[posmod(style_id,caps.size())]
			_part(self,"head",Vector3(0,1.78,-.014),Vector3(.310,.153,.305),cap).name = "AmbientCap"
			_part(self,"head",Vector3(0,1.748,.133),Vector3(.255,.035,.19),cap)
		3:
			_part(self,"head",Vector3(0,1.774,-.071),Vector3(.283,.143,.234),hair).name = "AmbientHairReceding"
		_:
			_part(self,"head",Vector3(0,1.779,-.04),Vector3(.29,.174,.28),hair).name = "AmbientHairSwept"
			var fringe := _part(self,"head",Vector3(.061,1.794,.075),Vector3(.18,.08,.16),hair)
			fringe.rotation.z = -.24

func _ambient_clothing(variant: int,shirt: Color,width: float,depth: float) -> void:
	# One simple pattern per pedestrian, not extra animated limbs or textures.
	var front := depth*.51
	var contrast := shirt.darkened(.24) if shirt.get_luminance()>.35 else shirt.lightened(.25)
	match posmod(variant+style_id,4):
		0:
			_part(self,"box",Vector3(0,1.28,front),Vector3(width*.76,.06,.016),contrast,true).name = "AmbientShirtStripe"
		1:
			_part(self,"box",Vector3(-width*.20,1.26,front),Vector3(.072,.078,.014),contrast,true).name = "AmbientShirtPocket"
		2:
			_part(self,"box",Vector3(0,1.38,front),Vector3(.049,.14,.017),contrast,true).name = "AmbientShirtPlacket"
		_:
			pass

func _ambient_face(variant: int,hair: Color) -> void:
	# Sparse eyewear or facial hair, at close range only.
	if age_group!="menor" and posmod(variant+style_id,7)==0:
		var frame := Color("#393536")
		for side in [-1.0,1.0]:
			_part(self,"box",Vector3(float(side)*.060,1.69,.166),Vector3(.065,.009,.015),frame,true)
			_part(self,"box",Vector3(float(side)*.060,1.71,.166),Vector3(.065,.009,.015),frame,true)
		_part(self,"box",Vector3(0,1.70,.171),Vector3(.058,.009,.013),frame,true).name = "AmbientGlasses"
	elif not female and age_group!="menor" and posmod(variant,6)==0:
		_part(self,"head",Vector3(0,1.612,.15),Vector3(.100,.024,.024),hair,true).name = "AmbientMoustache"

func animate(delta: float,moving: bool,run_speed: float = 0.0) -> void:
	var sprint := clampf((run_speed-4.5)/4.0,0.0,1.0) if moving else 0.0
	# Fade between idle, walk and run rather than snapping at a stop.
	var pace := run_speed if run_speed>0.0 else 1.4
	var cadence := clampf(5.2+pace*1.55,6.5,14.5)
	if moving: phase = fposmod(phase+delta*cadence*gait,TAU)
	stride_weight = move_toward(stride_weight,1.0 if moving else 0.0,delta*6.0)
	idle_phase = fposmod(idle_phase+delta*2.0,TAU)
	if story_character and not facial_eyes.is_empty():
		blink_clock -= delta
		if blink_clock<=0.0:
			blink_clock = 3.4+float(posmod(style_id,5))*.27
			facial_blink = .13
		facial_blink = maxf(0.0,facial_blink-delta)
		var open := facial_blink<=.015
		for eye in facial_eyes:
			if eye.visible!=open: eye.visible = open
	var use_phone := phone_idle and not moving and carried==null and not has_meta("incident_role")
	if is_instance_valid(leisure_prop): leisure_prop.visible = use_phone
	for i in range(limbs.size()):
		var stride := sin(phase+float(i)*PI)*stride_weight
		var swing := stride*lerpf(.43,.76,sprint)
		var blend := minf(1.0,delta*15.0)
		limbs[i].rotation.x = lerpf(limbs[i].rotation.x,swing,blend)
		knees[i].rotation.x = lerpf(knees[i].rotation.x,maxf(0.0,-stride)*lerpf(.48,1.02,sprint),blend)
		var arm_pose := -swing*.72 if carried==null else -.85
		if story_character and not moving and carried==null and not has_meta("incident_role"):
			arm_pose += sin(idle_phase+float(i)*.7)*.035
		if use_phone and i==1: arm_pose = -1.15
		if has_meta("story_handshake") and i==1: arm_pose = -1.10
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
	animate(delta,true,speed)
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
