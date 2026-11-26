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

static func total(kind: String) -> int:
	var sum := 0
	for price in KITS[kind].parts.values(): sum += int(price)
	return sum

static func _mat(color: Color,ghost: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(.38,.77,.90,.25) if ghost else color
	mat.roughness = .8
	if ghost:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

static func _box(root: Node3D,p: Vector3,size: Vector3,color: Color,ghost: bool,angle: float = 0.0) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
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
		var mesh := CylinderMesh.new()
		mesh.top_radius = r if i==0 else r*.62
		mesh.bottom_radius = mesh.top_radius
		mesh.height = width if i==0 else width+.014
		mesh.radial_segments = 16
		node.mesh = mesh
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
					if moto: _box(root,Vector3(0,.91,.17),Vector3(.36,.29,.55),paint,ghost)
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
					_bar(root,Vector3(0,.35,z),Vector3(0,1.11,z*.77),.06,Color("#b5b9bd"),ghost)
					_box(root,Vector3(0,1.10,z*.77),Vector3(width*.86,.055,.07),Color("#343b3c"),ghost)
			"seat":
				_box(root,Vector3(0,.93,-.23),Vector3(.55 if car or tri else .24,.11,.45),Color("#323638"),ghost)
			"drive":
				_box(root,Vector3(0,.47,.0),Vector3(.60 if car else .19,.29,.36),Color("#686d70"),ghost)
			"battery":
				_box(root,Vector3(0,.60,-.60),Vector3(.45 if car or tri else .23,.21,.32),Color("#38413c"),ghost)

static func body(root: Node3D,kind: String) -> CharacterBody3D:
	var spec: Dictionary = KITS[kind]
	var node := CharacterBody3D.new()
	node.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	node.collision_layer = 4
	node.collision_mask = 1|4|8
	root.add_child(node)
	build(node,kind,{},true)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(float(spec.width),float(spec.height),float(spec.length))
	col.shape = shape
	node.add_child(col)
	col.position.y = float(spec.height)*.5+.03
	return node
