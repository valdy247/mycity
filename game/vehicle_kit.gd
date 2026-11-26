extends RefCounted
# Reusable low-poly vehicle assemblies. Each part has its own material
# and can be shown as a translucent guide until installed.
const KITS := {
	"bicicleta":{"name":"Bicicleta","width":.65,"length":1.85,"height":1.15,"speed":7.5,"parts":{"frame":900,"wheel_a":500,"wheel_b":500,"steer":350,"seat":250,"drive":450}},
	"triciclo":{"name":"Triciclo eléctrico","width":1.25,"length":2.5,"height":1.65,"speed":10.0,"parts":{"frame":1800,"wheel_a":600,"wheel_b":600,"wheel_c":600,"steer":500,"seat":400,"drive":1800,"battery":1500}},
	"moto":{"name":"Moto","width":.85,"length":2.1,"height":1.35,"speed":15.0,"parts":{"frame":2500,"wheel_a":850,"wheel_b":850,"steer":700,"seat":500,"drive":3500,"battery":1000}},
	"carro":{"name":"Carro","width":1.8,"length":4.1,"height":1.65,"speed":19.0,"parts":{"frame":6000,"wheel_a":1200,"wheel_b":1200,"wheel_c":1200,"wheel_d":1200,"steer":1700,"seat":1000,"drive":7000,"battery":1800}}
}
const PART_NAMES := {"frame":"Chasis","wheel_a":"Goma delantera","wheel_b":"Goma trasera","wheel_c":"Tercera goma","wheel_d":"Cuarta goma","steer":"Dirección / manubrio","seat":"Asiento","drive":"Transmisión / motor","battery":"Batería"}

# Shared unit primitives/materials; transforms carry dimensions.
static var part_materials: Dictionary = {}
static var wheel_meshes: Dictionary = {}
static var unit_box := BoxMesh.new()

static func total(kind: String) -> int:
	var sum := 0
	for price in KITS[kind].parts.values(): sum += int(price)
	return sum

static func _mat(color: Color,ghost: bool) -> StandardMaterial3D:
	var key := "ghost" if ghost else color.to_html()
	if part_materials.has(key): return part_materials[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(.38,.77,.90,.25) if ghost else color
	mat.roughness = .8
	if ghost:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	part_materials[key] = mat
	return mat

static func _box(root: Node3D,p: Vector3,size: Vector3,color: Color,ghost: bool,angle: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = unit_box
	node.scale = size
	node.material_override = _mat(color,ghost)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	node.position = p
	node.rotation.x = angle
	return node

static func _bar(root: Node3D,a: Vector3,b: Vector3,width: float,color: Color,ghost: bool) -> void:
	var d := b-a
	var node := _box(root,(a+b)*.5,Vector3(width,width,d.length()),color,ghost)
	node.look_at(node.global_position+root.global_transform.basis*d,Vector3.UP if absf(d.normalized().dot(Vector3.UP))<.97 else Vector3.FORWARD)

static func _wheel(root: Node3D,p: Vector3,r: float,width: float,ghost: bool) -> void:
	for i in range(2):
		var node := MeshInstance3D.new()
		var key := str(r)+":"+str(width)+":"+str(i)
		if not wheel_meshes.has(key):
			var mesh := CylinderMesh.new()
			mesh.top_radius = r if i==0 else r*.72
			mesh.bottom_radius = mesh.top_radius
			mesh.height = width if i==0 else width+.014
			mesh.radial_segments = 16
			mesh.rings = 0
			wheel_meshes[key] = mesh
		node.mesh = wheel_meshes[key] as Mesh
		node.material_override = _mat(Color("#303337") if i==0 else Color("#abb1b2"),ghost)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(node)
		node.position = p
		node.rotation.z = PI*.5

static func build(root: Node3D,kind: String,installed: Dictionary,all_parts: bool = false) -> void:
	var spec: Dictionary = KITS[kind]
	var car := kind=="carro"
	var tri := kind=="triciclo"
	var moto := kind=="moto"
	var paint := Color("#a64d41") if moto else (Color("#478b89") if tri else Color("#527caa"))
	var length := float(spec.length)
	var width := float(spec.width)
	var r := .32 if car or moto else .33
	var z := length*.35
	for key in spec.parts:
		var ghost := not all_parts and not bool(installed.get(key,false))
		match String(key):
			"frame":
				if car:
					_box(root,Vector3(0,.64,0),Vector3(width,.62,length),paint,ghost)
					_box(root,Vector3(0,1.22,-.28),Vector3(width*.89,.66,length*.51),Color("#9bb7c1"),ghost)
					_box(root,Vector3(0,1.56,-.28),Vector3(width*.94,.10,length*.55),paint,ghost)
				else:
					_bar(root,Vector3(0,.38,-z),Vector3(0,.38,z),.10 if moto else .055,paint,ghost)
					_bar(root,Vector3(0,.38,0),Vector3(0,.98,-.22),.08,paint,ghost)
					_bar(root,Vector3(0,.98,-.22),Vector3(0,.91,z*.77),.07,paint,ghost)
					_bar(root,Vector3(0,.38,0),Vector3(0,.91,z*.77),.07,paint,ghost)
					if tri:
						_box(root,Vector3(0,.65,-.53),Vector3(1.14,.17,.98),paint,ghost)
						_box(root,Vector3(0,1.48,-.40),Vector3(1.20,.09,1.16),paint,ghost)
						for x in [-.53,.53]: _bar(root,Vector3(float(x),.67,-.9),Vector3(float(x),1.48,-.9),.06,paint,ghost)
					if moto:
						# Low-poly tank with a tapered front and rear, not a large cube.
						_box(root,Vector3(0,.91,.15),Vector3(.31,.21,.38),paint,ghost)
						_box(root,Vector3(0,.98,.15),Vector3(.26,.07,.34),paint,ghost)
						_box(root,Vector3(0,.87,.38),Vector3(.22,.16,.15),paint,ghost,-.22)
						_box(root,Vector3(0,.86,-.08),Vector3(.25,.13,.12),paint,ghost,.25)
						_box(root,Vector3(0,.76,-.65),Vector3(.22,.08,.36),paint,ghost,.12)
						_box(root,Vector3(0,.77,-.84),Vector3(.18,.07,.045),Color("#a42f2d"),ghost)
			"wheel_a":
				_wheel(root,Vector3(-width*.42 if car else 0,r,z),r,.22 if car else .11,ghost)
			"wheel_b":
				_wheel(root,Vector3(-width*.42 if car or tri else 0,r,-z),r,.22 if car else .11,ghost)
			"wheel_c":
				_wheel(root,Vector3(width*.42,r,-z),r,.22 if car else .12,ghost)
			"wheel_d":
				_wheel(root,Vector3(width*.42,r,z),r,.22,ghost)
			"steer":
				if car: _box(root,Vector3(-.45,1.06,.40),Vector3(.30,.08,.28),Color("#303438"),ghost)
				else:
					if moto:
						for side in [-1.0,1.0]:
							var x := float(side)
							_bar(root,Vector3(x*.095,.32,z),Vector3(x*.095,1.04,.50),.045,Color("#b5b9bd"),ghost)
							_bar(root,Vector3(0,1.11,.49),Vector3(x*.26,1.16,.23),.035,Color("#b5b9bd"),ghost)
							_box(root,Vector3(x*.30,1.16,.23),Vector3(.10,.052,.052),Color("#343b3c"),ghost)
						_box(root,Vector3(0,1.06,.57),Vector3(.18,.15,.13),Color("#343b3c"),ghost)
						_box(root,Vector3(0,1.06,.645),Vector3(.15,.12,.024),Color("#e2d9b7"),ghost)
						_box(root,Vector3(0,.67,z),Vector3(.16,.07,.35),paint,ghost,-.12)
					else:
						_bar(root,Vector3(0,.35,z),Vector3(0,1.11,z*.77),.06,Color("#b5b9bd"),ghost)
						_box(root,Vector3(0,1.10,z*.77),Vector3(width*.86,.055,.07),Color("#343b3c"),ghost)
			"seat":
				if moto:
					_box(root,Vector3(0,.93,-.32),Vector3(.29,.10,.51),Color("#323638"),ghost)
					_box(root,Vector3(0,.98,-.55),Vector3(.25,.06,.17),Color("#323638"),ghost)
				else: _box(root,Vector3(0,.93,-.23),Vector3(.55 if car or tri else .24,.11,.45),Color("#323638"),ghost)
			"drive":
				_box(root,Vector3(0,.47,.0),Vector3(.60 if car else (.27 if moto else .19),.29,.36),Color("#686d70"),ghost)
				if moto:
					_box(root,Vector3(0,.65,.07),Vector3(.24,.12,.20),Color("#555a5d"),ghost)
					_bar(root,Vector3(.16,.44,.16),Vector3(.21,.36,-.63),.055,Color("#969a9b"),ghost)
					_box(root,Vector3(.21,.36,-.63),Vector3(.08,.08,.30),Color("#696d70"),ghost)
					for side in [-1.0,1.0]:
						_box(root,Vector3(float(side)*.27,.42,.04),Vector3(.16,.045,.09),Color("#343b3c"),ghost)
			"battery":
				_box(root,Vector3(0,.60,-.60),Vector3(.45 if car or tri else .23,.21,.32),Color("#38413c"),ghost)

static func body(root: Node3D,kind: String) -> CharacterBody3D:
	var spec: Dictionary = KITS[kind]
	var node := CharacterBody3D.new()
	node.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	node.collision_layer = 4
	node.collision_mask = 1|4|8|32
	root.add_child(node)
	build(node,kind,{},true)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(spec.width),float(spec.height),float(spec.length))
	col.shape = shape
	node.add_child(col)
	col.position.y = float(spec.height)*.5+.03
	return node
