extends Node3D
# Private modern family home, garage and pool. All dimensions in metres.
const Builder = preload("res://city_builder.gd")
const ORIGIN := Vector3(20,0.055,16)
const OUTSIDE := Vector3(16,0.94,21.0)
const INSIDE := Vector3(16,1.03,18.65)
var materials: Dictionary = {}
var meshes: Dictionary = {}
var collision_body: StaticBody3D
var door: Node3D
var door_tween: Tween
var tv_screen: MeshInstance3D
var tv_title: Label3D
var tv_on := false
var tv_material: ShaderMaterial
var seats: Array = []
var inside := false
var pool_inside := false

func setup(builder: Builder) -> void:
	name = "VJ_Family_Residence"
	position = ORIGIN
	for x in range(1,5):
		builder.reserve_cell(x,2)
	collision_body = StaticBody3D.new()
	collision_body.collision_layer = 1
	collision_body.collision_mask = 0
	add_child(collision_body)
	_build_exterior()
	_build_interior()
	_build_pool()

func _mat(key: String, color: Color, rough: float = 0.8, transparent: bool = false) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key] as StandardMaterial3D
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	materials[key] = m
	return m

func _box(at: Vector3, size: Vector3, mat: Material, parent: Node3D = null) -> MeshInstance3D:
	if not meshes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		meshes[size] = mesh
	var ob := MeshInstance3D.new()
	ob.mesh = meshes[size] as BoxMesh
	ob.material_override = mat
	if parent == null:
		add_child(ob)
	else:
		parent.add_child(ob)
	ob.position = at
	return ob

func _shape(at: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	collision_body.add_child(col)
	col.position = at

func _solid(at: Vector3, size: Vector3, mat: Material) -> void:
	_box(at,size,mat)
	_shape(at,size)

func _sphere(at: Vector3, scale_value: Vector3, mat: Material) -> void:
	var ob := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	ob.mesh = mesh
	ob.material_override = mat
	add_child(ob)
	ob.position = at
	ob.scale = scale_value

func _label(words: String, at: Vector3, font: int, pixel: float, color: Color, angle: float = 0.0) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = font
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	add_child(label)
	label.position = at
	label.rotation.y = angle
	return label

func _build_exterior() -> void:
	var white := _mat("plaster",Color("#f4eee1"))
	var dark := _mat("graphite",Color("#333d42"))
	var wood := _mat("oak",Color("#a8734b"))
	var stone := _mat("stone",Color("#c1c5c2"))
	var glass := _mat("glass",Color(0.61,0.83,0.91,0.22),0.18,true)
	var lawn := _mat("lawn",Color("#8bb65d"))
	var tile := _mat("tile",Color("#ddd7cb"))
	# Existing four parcels: x=4..36, z=12..20. No new streets occupied.
	_box(Vector3(0,-0.035,0),Vector3(31.9,.07,7.9),lawn)
	_solid(Vector3(0,.055,0),Vector3(15.8,.11,7.35),tile)
	# Flat floating roof, horizontal stone and timber detailing.
	_solid(Vector3(0,3.43,0),Vector3(16.0,.24,7.50),white)
	_box(Vector3(0,3.61,0),Vector3(16.0,.14,7.50),dark)
	_solid(Vector3(0,1.76,-3.60),Vector3(15.8,3.4,.16),white)
	_solid(Vector3(7.82,1.76,0),Vector3(.16,3.4,7.2),white)
	_solid(Vector3(-7.82,1.76,0),Vector3(.16,3.4,7.2),white)
	# Front: broad glazing with opaque walls and a central entry at x=-4.
	for section in [Vector2(-6.35,3.10),Vector2(1.55,9.50),Vector2(7.10,1.60)]:
		var span: Vector2 = section
		_solid(Vector3(span.x,.31,3.60),Vector3(span.y,.50,.16),white)
		_solid(Vector3(span.x,2.99,3.60),Vector3(span.y,.94,.16),white)
		_box(Vector3(span.x,1.54,3.60),Vector3(span.y,1.96,.07),glass)
		_shape(Vector3(span.x,1.54,3.60),Vector3(span.y,1.96,.12))
		for t in [-.45,0.0,.45]:
			_box(Vector3(span.x+span.y*float(t),1.54,3.69),Vector3(.085,2.0,.13),dark)
	# Close small facade gaps at the edges of the 1.6 m door.
	_solid(Vector3(-4,2.91,3.60),Vector3(1.6,1.1,.16),wood)
	_shape(Vector3(-4,1.23,3.60),Vector3(1.6,2.45,.16))
	door = Node3D.new()
	add_child(door)
	door.position = Vector3(-4.8,.11,3.60)
	_box(Vector3(.8,1.16,0),Vector3(1.6,2.32,.12),wood,door)
	_box(Vector3(1.35,1.14,.10),Vector3(.055,.42,.08),dark,door)
	_box(Vector3(-4,2.75,3.79),Vector3(2.5,.10,.24),dark)
	_label("VJ • FAMILY HOME",Vector3(-4,3.12,3.70),45,.006,Color("#fdf8e8"))
	_box(Vector3(-4,.07,3.82),Vector3(2.0,.08,.32),stone)
	# Open garage / carport, sized to keep the original van accessible.
	_box(Vector3(-12,.02,0),Vector3(7.75,.04,7.80),stone)
	_solid(Vector3(-12,3.30,0),Vector3(7.65,.24,7.4),dark)
	_solid(Vector3(-15.65,1.55,0),Vector3(.22,3.1,7.1),white)
	_solid(Vector3(-8.20,1.55,0),Vector3(.22,3.1,7.1),white)
	_solid(Vector3(-12,1.55,-3.52),Vector3(7.25,3.1,.18),white)
	_box(Vector3(-12,3.13,3.68),Vector3(7.4,.16,.15),wood)
	_label("VJ GARAGE",Vector3(-12,3.25,3.79),54,.009,Color("#fff3d7"))
	# Landscaping and exterior path lights.
	for x in [-7.20,7.20]:
		_solid(Vector3(float(x),.22,3.02),Vector3(.68,.40,.58),dark)
		_sphere(Vector3(float(x),.80,3.02),Vector3(.64,.93,.64),_mat("leaves",Color("#51813f")))
	for x in [-5.25,-2.75,5.5,7.1]:
		_box(Vector3(float(x),2.63,3.78),Vector3(.16,.27,.14),dark)
		_box(Vector3(float(x),2.62,3.86),Vector3(.11,.17,.03),_mat("warm",Color("#ffe3a1")))

func _build_interior() -> void:
	var wood := _mat("oak",Color("#a8734b"))
	var dark := _mat("graphite",Color("#333d42"))
	var white := _mat("plaster",Color("#f4eee1"))
	var marble := _mat("marble",Color("#eeeae5"),.36)
	var navy := _mat("navy",Color("#34556e"))
	var linen := _mat("linen",Color("#e3d5bf"))
	var steel := _mat("steel",Color("#8f9ca2"),.30)
	var teal := _mat("teal",Color("#477c7c"))
	# Rooms: living room west, kitchen/dining middle, two bedrooms east.
	# Bathroom opens onto common area; two bedroom doorways face corridor.
	_solid(Vector3(1.98,1.70,-.85),Vector3(2.84,3.18,.13),white)
	_solid(Vector3(.56,1.70,-2.20),Vector3(.13,3.18,2.7),white)
	_solid(Vector3(3.40,1.70,-2.80),Vector3(.13,3.18,1.4),white)
	# Open bath door on east wall from z=-2.1 to -1.0.
	_solid(Vector3(4.50,1.70,-3.10),Vector3(.13,3.18,.92),white)
	_solid(Vector3(4.50,1.70,0),Vector3(.13,3.18,1.38),white)
	_solid(Vector3(4.50,1.70,3.10),Vector3(.13,3.18,.92),white)
	_solid(Vector3(6.16,1.70,0),Vector3(3.30,3.18,.13),white)
	# Entertainment wall, real switchable animated TV (no internet/video files).
	_solid(Vector3(-7.39,.50,0),Vector3(.63,.77,3.0),wood)
	var frame := _box(Vector3(-7.56,1.77,0),Vector3(.12,1.55,2.70),dark)
	frame.name = "Television"
	tv_screen = _box(Vector3(-7.485,1.77,0),Vector3(.025,1.38,2.52),_mat("tv_off",Color("#151c24"),.30))
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded;
void fragment(){
	float a = smoothstep(0.0,1.0,0.5+0.5*sin(UV.x*6.283+TIME*0.8));
	float b = 0.5+0.5*cos(UV.y*9.0-TIME);
	vec3 c = mix(vec3(0.035,0.15,0.38),vec3(0.06,0.55,0.58),a);
	float band = smoothstep(0.91,0.98,sin(UV.x*12.0+UV.y*7.0+TIME));
	ALBEDO = c + vec3(0.20,0.12,0.02)*b + band*0.14;
}"""
	tv_material = ShaderMaterial.new()
	tv_material.shader = shader
	tv_title = _label("VJ TV",Vector3(-7.455,1.77,0),96,.012,Color.WHITE,PI/2.0)
	tv_title.hide()
	# Sectional sofa faces screen; sit and stand via E.
	_solid(Vector3(-3.70,.45,0),Vector3(1.05,.65,3.00),navy)
	_box(Vector3(-3.26,.89,0),Vector3(.21,.72,3.05),navy)
	for z in [-1.40,1.40]:
		_box(Vector3(-3.72,.77,float(z)),Vector3(1.06,.26,.24),navy)
	for z in [-.72,.72]:
		_box(Vector3(-3.70,.83,float(z)),Vector3(.54,.18,.62),linen)
		seats.append({"at":to_global(Vector3(-3.78,1.34,float(z))),"exit":to_global(Vector3(-4.63,1.04,float(z))),"yaw":-PI/2.0,"indoors":true})
	_box(Vector3(-5.55,.12,0),Vector3(2.7,.035,3.0),_mat("rug",Color("#c6b8a4")))
	_solid(Vector3(-5.48,.41,0),Vector3(.92,.50,1.48),wood)
	_box(Vector3(-5.48,.69,0),Vector3(1.00,.08,1.56),marble)
	# Kitchen: counters, range, sink, fridge, cabinets and dining island.
	_solid(Vector3(-.9,.58,-3.08),Vector3(2.7,.94,.88),wood)
	_box(Vector3(-.9,1.08,-3.08),Vector3(2.8,.10,.93),marble)
	_box(Vector3(-1.50,1.15,-3.08),Vector3(.75,.04,.62),dark)
	for x in [-1.68,-1.32]:
		for z in [-3.29,-2.88]:
			_box(Vector3(float(x),1.18,float(z)),Vector3(.24,.025,.24),steel)
	_box(Vector3(.02,1.15,-3.08),Vector3(.57,.04,.51),steel)
	_box(Vector3(.02,1.33,-3.42),Vector3(.045,.35,.045),steel)
	_box(Vector3(.02,1.49,-3.33),Vector3(.045,.045,.20),steel)
	_box(Vector3(-.9,2.39,-3.25),Vector3(2.8,.68,.60),white)
	_solid(Vector3(-2.75,1.15,-3.05),Vector3(.86,2.08,.90),steel)
	_box(Vector3(-2.75,1.34,-2.58),Vector3(.83,.045,.04),dark)
	_box(Vector3(-2.45,1.58,-2.56),Vector3(.055,.40,.06),dark)
	_solid(Vector3(.85,.56,1.38),Vector3(2.15,.86,1.00),wood)
	_box(Vector3(.85,1.04,1.38),Vector3(2.30,.10,1.14),marble)
	for x in [.15,1.55]:
		_solid(Vector3(float(x),.38,2.38),Vector3(.43,.54,.43),dark)
		seats.append({"at":to_global(Vector3(float(x),1.26,2.38)),"exit":to_global(Vector3(float(x),1.03,3.05)),"yaw":PI,"indoors":true})
	# Two furnished bedrooms.
	for room_z in [-1.83,1.83]:
		var z: float = float(room_z)
		_solid(Vector3(6.63,.34,z),Vector3(2.15,.45,1.65),wood)
		_box(Vector3(6.63,.64,z),Vector3(2.10,.22,1.60),white)
		_box(Vector3(6.22,.80,z),Vector3(1.45,.13,1.57),navy if z>0 else teal)
		for dz in [-.38,.38]:
			_box(Vector3(7.27,.83,z+float(dz)),Vector3(.43,.17,.58),linen)
		_solid(Vector3(7.48,.85,z),Vector3(.18,1.4,1.7),wood)
		_solid(Vector3(5.20,.42,z+(1.15 if z<0 else -1.15)),Vector3(.62,.62,.55),wood)
		_box(Vector3(5.20,.85,z+(1.15 if z<0 else -1.15)),Vector3(.26,.35,.26),_mat("lamp",Color("#ffe3a1")))
	# Modern bathroom: vanity, mirror, toilet and glass shower.
	_solid(Vector3(1.12,.55,-3.10),Vector3(.85,.86,.68),wood)
	_box(Vector3(1.12,1.03,-3.10),Vector3(.95,.10,.75),marble)
	_sphere(Vector3(1.12,1.10,-3.10),Vector3(.45,.12,.34),white)
	_box(Vector3(1.12,1.75,-3.50),Vector3(.76,.86,.035),steel)
	_solid(Vector3(2.13,.36,-3.08),Vector3(.48,.51,.65),white)
	_sphere(Vector3(2.13,.66,-2.91),Vector3(.47,.18,.52),white)
	_box(Vector3(2.13,.83,-3.31),Vector3(.44,.55,.21),white)
	_box(Vector3(2.90,.15,-3.00),Vector3(.85,.10,1.02),marble)
	_box(Vector3(2.48,1.19,-3.00),Vector3(.045,2.0,1.0),_mat("shower",Color(0.68,.87,.91,.23),.2,true))
	_box(Vector3(2.90,1.19,-3.50),Vector3(.85,2.0,.045),steel)
	_box(Vector3(2.92,2.11,-3.34),Vector3(.25,.04,.25),steel)
	# Warm lights, no shadow maps.
	for point in [Vector3(-5.1,3.15,0),Vector3(-.4,3.15,0),Vector3(6.2,3.15,-1.8),Vector3(6.2,3.15,1.8),Vector3(2.1,3.15,-2.2)]:
		var p: Vector3 = point
		_box(p+Vector3(0,.08,0),Vector3(.36,.09,.36),_mat("lamp",Color("#ffe3a1")))
		var light := OmniLight3D.new()
		light.light_color = Color("#fff1d8")
		light.light_energy = .55
		light.omni_range = 3.8
		light.shadow_enabled = false
		add_child(light)
		light.position = p

func _build_pool() -> void:
	var deck := _mat("deck",Color("#d5bc91"))
	var stone := _mat("pool_edge",Color("#eef2ee"))
	var water := _mat("pool_water",Color(0.08,.67,.82,.68),.15,true)
	var blue := _mat("pool_tile",Color("#39a4c0"))
	var white := _mat("plaster",Color("#f4eee1"))
	var dark := _mat("graphite",Color("#333d42"))
	# Private raised pool, 6.3 x 4.1 m, shallow play water.
	_box(Vector3(12,.02,0),Vector3(7.75,.04,7.8),deck)
	_solid(Vector3(12,.12,-.60),Vector3(6.50,.24,4.30),blue)
	for side in [-1.0,1.0]:
		var v: float = float(side)
		_solid(Vector3(12+v*3.20,.42,-.60),Vector3(.22,.66,4.40),stone)
		_solid(Vector3(12,.42,-.60+v*2.10),Vector3(6.2,.66,.22),stone)
	_box(Vector3(12,.57,-.60),Vector3(6.13,.025,3.96),water)
	# Fine water highlights, all geometry, no expensive simulation.
	for i in range(7):
		_box(Vector3(9.8+float(i)*.72,.591,-.9+sin(float(i)*1.7)*.65),Vector3(.38,.006,.028),_mat("ripple",Color("#b5eced"),.25))
	# Small entrance steps and ladder handrails.
	_solid(Vector3(12,.16,1.83),Vector3(1.3,.28,.55),stone)
	_solid(Vector3(12,.33,1.51),Vector3(1.3,.32,.38),stone)
	for x in [11.40,12.60]:
		_box(Vector3(float(x),.78,1.46),Vector3(.055,.95,.055),dark)
		_box(Vector3(float(x),1.22,1.28),Vector3(.055,.055,.42),dark)
	# Two sun loungers with cushions.
	for x in [9.5,14.5]:
		var xx: float = float(x)
		_solid(Vector3(xx,.24,2.80),Vector3(1.24,.38,.76),white)
		_box(Vector3(xx,.48,2.80),Vector3(1.17,.14,.70),_mat("navy",Color("#34556e")))
		_box(Vector3(xx-.46,.68,2.80),Vector3(.24,.40,.70),_mat("navy",Color("#34556e")))
		seats.append({"at":to_global(Vector3(xx,.99,2.80)),"exit":to_global(Vector3(xx,1.0,3.48)),"yaw":0.0,"indoors":false})
	_label("POOL",Vector3(12,1.10,-2.78),48,.008,Color("#f4ffff"))

func interaction_text(at: Vector3) -> String:
	var p: Vector3 = to_local(at)
	# Determine pool presence from geometry, so jumping over a wall is safe.
	pool_inside = absf(p.x-12.0)<3.05 and absf(p.z+.60)<1.94 and p.y<2.0
	if pool_inside:
		return "[E] Salir de la piscina"
	if absf(p.x-12.0)<1.35 and absf(p.z-1.90)<1.10 and p.y<2.1:
		return "[E] Entrar a la piscina"
	if absf(p.x+4.0)<1.35 and absf(p.z-3.60)<1.55 and p.y<2.6:
		return "[E] Salir de casa" if inside else "[E] Entrar a mi casa"
	if inside and p.x < -5.85 and absf(p.z)<1.70:
		return "[E] Apagar TV" if tv_on else "[E] Encender TV"
	return ""

func interact(player: CharacterBody3D) -> bool:
	var action: String = interaction_text(player.global_position)
	if action.is_empty():
		return false
	if action.contains("piscina"):
		player.global_position = to_global(Vector3(12,1.17,2.25) if pool_inside else Vector3(12,1.08,.70))
		pool_inside = not pool_inside
		player.velocity = Vector3.ZERO
		return true
	if action.contains("TV"):
		tv_on = not tv_on
		tv_screen.material_override = tv_material if tv_on else _mat("tv_off",Color("#151c24"),.30)
		tv_title.visible = tv_on
		return true
	inside = not inside
	if door_tween != null and door_tween.is_valid():
		door_tween.kill()
	door.rotation.y = 0
	door_tween = create_tween()
	door_tween.tween_property(door,"rotation:y",-1.35,.25)
	door_tween.tween_interval(.18)
	door_tween.tween_property(door,"rotation:y",0.0,.25)
	player.global_position = INSIDE if inside else OUTSIDE
	player.velocity = Vector3.ZERO
	return true

func reset() -> void:
	inside = false
	pool_inside = false
