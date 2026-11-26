extends Node3D
# Mayuli's Bakery: local, walkable shop with free system speech.
const Builder = preload("res://city_builder.gd")
const GREETING := "Hola, soy Mayuli, ¿en qué te puedo ayudar?"
const CENTER := Vector3(20.0,0.055,-16.0)
var inside := false
var door: Node3D
var door_tween: Tween
var materials: Dictionary = {}
var meshes: Dictionary = {}
var collision_body: StaticBody3D
var caption: Label
var caption_time: float = 0.0
var voice_id: String = ""
var voice_checked := false

func setup(builder: Builder) -> void:
	name = "MayulisBakery"
	position = CENTER
	rotation.y = PI
	builder.reserve_cell(2,-2)
	builder.reserve_cell(3,-2)
	collision_body = StaticBody3D.new()
	collision_body.collision_layer = 1
	collision_body.collision_mask = 0
	add_child(collision_body)
	_build_shop()
	_make_caption()

func _mat(key: String, color: Color, transparent: bool = false) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key] as StandardMaterial3D
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.76
	if transparent:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.roughness = 0.18
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	materials[key] = material
	return material

func _box(parent: Node3D, at: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	if not meshes.has(size):
		var new_mesh := BoxMesh.new()
		new_mesh.size = size
		meshes[size] = new_mesh
	var item := MeshInstance3D.new()
	item.mesh = meshes[size] as BoxMesh
	item.material_override = material
	parent.add_child(item)
	item.position = at
	return item

func _shape(at: Vector3, size: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collision_body.add_child(collider)
	collider.position = at

func _solid(at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	_box(self,at,size,material)
	_shape(at,size)

func _cylinder(at: Vector3, radius: float, height: float, material: StandardMaterial3D, top_radius: float = -1.0) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 20
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	add_child(item)
	item.position = at
	return item

func _sphere(at: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var item := MeshInstance3D.new()
	item.mesh = mesh
	item.material_override = material
	add_child(item)
	item.position = at
	item.scale = size
	return item

func _sign(words: String, at: Vector3, size: int, pixel: float, color: Color) -> void:
	var label := Label3D.new()
	label.text = words
	label.font_size = size
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.no_depth_test = false
	add_child(label)
	label.position = at

func _build_shop() -> void:
	var cream := _mat("cream",Color("#fff0dd"))
	var rose := _mat("rose",Color("#cf8797"))
	var blush := _mat("blush",Color("#f8d7d8"))
	var wood := _mat("wood",Color("#b87c51"))
	var walnut := _mat("walnut",Color("#71442e"))
	var white := _mat("white",Color("#fffaf0"))
	var dark := _mat("letter",Color("#5b2939"))
	var gold := _mat("gold",Color("#c99b57"))
	var glass := _mat("glass",Color(0.70,0.91,0.97,0.16),true)
	var tile := _mat("tile",Color("#eee0d1"))
	var asphalt := _mat("entry",Color("#d0c6b9"))
	# The entire store occupies two former shop lots: 16 x 8 metres.
	_box(self,Vector3(0,-0.025,0),Vector3(15.9,.05,7.9),asphalt)
	_solid(Vector3(0,.06,0),Vector3(14.8,.12,7.1),tile)
	_solid(Vector3(0,1.83,-3.50),Vector3(14.8,3.55,.16),cream)
	for side in [-1.0,1.0]:
		var sx: float = float(side)
		_solid(Vector3(sx*7.32,1.83,0),Vector3(.16,3.55,7.0),cream)
		_solid(Vector3(sx*4.25,.41,3.48),Vector3(6.3,.58,.16),rose)
		_solid(Vector3(sx*4.25,2.97,3.48),Vector3(6.3,1.05,.16),cream)
		_box(self,Vector3(sx*4.25,1.56,3.48),Vector3(6.3,1.70,.055),glass)
		_shape(Vector3(sx*4.25,1.56,3.48),Vector3(6.3,1.70,.08))
		for offset in [-3.05,0.0,3.05]:
			_box(self,Vector3(sx*4.25+float(offset),1.55,3.54),Vector3(.11,1.78,.14),walnut)
		_box(self,Vector3(sx*4.25,2.42,3.55),Vector3(6.25,.11,.14),gold)
	# Flat parapet roof and decorative striped awning.
	_solid(Vector3(0,3.65,0),Vector3(15.05,.22,7.35),cream)
	_box(self,Vector3(0,3.90,3.56),Vector3(15.0,.42,.22),rose)
	_box(self,Vector3(0,3.01,3.59),Vector3(9.7,.76,.15),blush)
	_sign("Mayuli’s Bakery",Vector3(0,3.09,3.69),82,.013,Color("#632f42"))
	_sign("CAKES  •  DULCES  •  POSTRES",Vector3(0,2.72,3.70),34,.009,Color("#632f42"))
	for i in range(18):
		var x: float = -7.05+float(i)*.83
		var awning := _box(self,Vector3(x,2.48,3.88),Vector3(.82,.10,.77),rose if i%2==0 else white)
		awning.rotation.x = -.15
	# Door opening is 2.2 m wide; E teleports across its closed collider.
	_shape(Vector3(0,1.3,3.48),Vector3(2.2,2.35,.12))
	door = Node3D.new()
	add_child(door)
	door.position = Vector3(-1.1,.12,3.49)
	_box(door,Vector3(1.1,1.16,0),Vector3(2.2,2.32,.09),glass)
	for x in [0.05,2.15]:
		_box(door,Vector3(float(x),1.16,.03),Vector3(.10,2.32,.14),walnut)
	for y in [.05,2.27]:
		_box(door,Vector3(1.1,float(y),.03),Vector3(2.2,.10,.14),walnut)
	_box(door,Vector3(1.93,1.10,.12),Vector3(.07,.33,.08),gold)
	_box(self,Vector3(0,.035,3.76),Vector3(2.4,.07,.47),tile)
	# Two glass display cabinets with walkable space between them.
	for side in [-1.0,1.0]:
		var sx: float = float(side)
		var center_x: float = sx*3.75
		_solid(Vector3(center_x,.51,-1.72),Vector3(5.4,.78,1.12),rose)
		_box(self,Vector3(center_x,.94,-1.72),Vector3(5.5,.08,1.18),white)
		_box(self,Vector3(center_x,1.51,-1.72),Vector3(5.5,.055,1.18),glass)
		for zz in [-2.30,-1.14]:
			_box(self,Vector3(center_x,1.225,float(zz)),Vector3(5.5,.53,.035),glass)
		for dx in [-2.74,2.74]:
			_box(self,Vector3(center_x+float(dx),1.225,-1.72),Vector3(.035,.53,1.18),glass)
			for zz in [-2.30,-1.14]:
				_box(self,Vector3(center_x+float(dx),1.225,float(zz)),Vector3(.045,.58,.045),gold)
		_shape(Vector3(center_x,1.20,-1.72),Vector3(5.5,.57,1.18))
	# Original low-poly pastries, layered frosting and fruit decoration.
	var cake_colors: Array[Color] = [Color("#f2bdc3"),Color("#fff0cf"),Color("#ad704e"),Color("#ed9a9c")]
	for i in range(6):
		var x: float = -6.0+float(i)*.83
		_cake(Vector3(x,.99,-1.72),.28,.25,_mat("icing"+str(i%4),cake_colors[i%4]))
	for i in range(9):
		var x: float = 1.42+float(i)*.56
		_cupcake(Vector3(x,.99,-1.53),_mat("icing"+str(i%4),cake_colors[i%4]))
	for i in range(8):
		var x: float = 1.55+float(i)*.60
		_cylinder(Vector3(x,1.04,-1.98),.12,.09,_mat("cookie",Color("#bc8c55")))
		_sphere(Vector3(x+.03,1.10,-1.98),Vector3(.05,.035,.05),_mat("chocolate",Color("#623724")))
	# Back shelves, a register, two seating nooks and a friendly shopkeeper.
	_box(self,Vector3(0,1.74,-3.34),Vector3(12.8,.10,.38),wood)
	_box(self,Vector3(0,2.48,-3.34),Vector3(12.8,.10,.38),wood)
	for i in range(10):
		var x: float = -5.8+float(i)*1.25
		_box(self,Vector3(x,1.99,-3.33),Vector3(.42,.39,.28),blush if i%2==0 else cream)
		_box(self,Vector3(x,2.68,-3.33),Vector3(.48,.31,.29),rose if i%2==0 else white)
	_solid(Vector3(0,.54,-1.75),Vector3(1.7,.84,.95),wood)
	_box(self,Vector3(.35,1.10,-1.76),Vector3(.48,.23,.35),dark)
	_box(self,Vector3(.35,1.23,-1.80),Vector3(.44,.19,.075),_mat("screen",Color("#557b75")))
	for side in [-1.0,1.0]:
		var sx: float = float(side)
		_cylinder(Vector3(sx*5.7,.50,1.65),.065,.76,walnut)
		_cylinder(Vector3(sx*5.7,.91,1.65),.59,.09,wood)
		_shape(Vector3(sx*5.7,.5,1.65),Vector3(1.1,1.0,1.1))
		for dz in [-.90,.90]:
			_solid(Vector3(sx*5.7,.32,1.65+float(dz)),Vector3(.43,.56,.43),blush)
	_sign("Hecho con amor",Vector3(0,2.92,-3.40),50,.009,Color("#632f42"))
	_shopkeeper()
	# Small warm local lights; no shadows or heavy textures.
	for x in [-4.5,0.0,4.5]:
		_cylinder(Vector3(float(x),3.37,0),.22,.12,gold)
		var light := OmniLight3D.new()
		light.light_color = Color("#fff1d7")
		light.light_energy = .65
		light.omni_range = 5.0
		light.shadow_enabled = false
		add_child(light)
		light.position = Vector3(float(x),3.24,0)

func _cake(at: Vector3, r: float, h: float, icing: StandardMaterial3D) -> void:
	_cylinder(at+Vector3(0,.025,0),r+.055,.035,_mat("plate",Color("#fffaf0")))
	_cylinder(at+Vector3(0,.045+h/2,0),r,h,icing)
	_cylinder(at+Vector3(0,.045+h*.40,0),r+.009,.035,_mat("filling",Color("#f9ebcb")))
	_cylinder(at+Vector3(0,.055+h,0),r+.01,.045,icing)
	for i in range(6):
		var angle: float = float(i)*TAU/6.0
		_sphere(at+Vector3(cos(angle)*r*.65,h+.115,sin(angle)*r*.65),Vector3(.075,.09,.075),_mat("berries",Color("#bd3447")))

func _cupcake(at: Vector3, icing: StandardMaterial3D) -> void:
	_cylinder(at+Vector3(0,.07,0),.105,.13,_mat("cup",Color("#c68e59")),.14)
	_sphere(at+Vector3(0,.17,0),Vector3(.27,.17,.27),icing)
	_sphere(at+Vector3(0,.25,0),Vector3(.15,.11,.15),icing)
	_sphere(at+Vector3(0,.31,0),Vector3(.055,.055,.055),_mat("berries",Color("#bd3447")))

func _shopkeeper() -> void:
	# Fictional cartoon shopkeeper; not a likeness of any real person.
	var skin := _mat("skin",Color("#cb956c"))
	var hair := _mat("hair",Color("#39271e"))
	var uniform := _mat("uniform",Color("#f4d0d9"))
	var apron := _mat("apron",Color("#fff8ea"))
	var eyes := _mat("eyes",Color("#34252a"))
	var p := Vector3(0,0,-2.66)
	_sphere(p+Vector3(0,1.05,0),Vector3(.57,.72,.36),uniform)
	_box(self,p+Vector3(0,1.0,.20),Vector3(.42,.52,.04),apron)
	_sphere(p+Vector3(0,1.65,-.02),Vector3(.48,.53,.48),skin)
	_sphere(p+Vector3(0,1.81,-.11),Vector3(.52,.32,.51),hair)
	_sphere(p+Vector3(0,1.60,-.25),Vector3(.44,.55,.24),hair)
	for side in [-1.0,1.0]:
		var sx: float = float(side)
		_sphere(p+Vector3(sx*.105,1.68,.213),Vector3(.045,.065,.025),eyes)
		_sphere(p+Vector3(sx*.32,1.01,.06),Vector3(.14,.48,.15),skin)
		_box(self,p+Vector3(sx*.13,.47,0),Vector3(.19,.52,.22),_mat("pants",Color("#6f4544")))
	_sign("Mayuli",p+Vector3(0,2.08,.25),42,.006,Color("#632f42"))

func _make_caption() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8
	add_child(layer)
	var background := PanelContainer.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	background.offset_left = -260
	background.offset_right = 260
	background.offset_top = -104
	background.offset_bottom = -32
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.15,0.07,0.10,.94)
	style.set_corner_radius_all(12)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	background.add_theme_stylebox_override("panel",style)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(background)
	caption = Label.new()
	caption.text = "Mayuli\n"+GREETING
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",19)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.add_child(caption)
	background.hide()

func interaction_text(at: Vector3) -> String:
	var local: Vector3 = to_local(at)
	if absf(local.x) < 1.8 and absf(local.z-3.48) < 2.0 and local.y < 3.0:
		return "[E] Salir de Mayuli’s Bakery" if inside else "[E] Entrar a Mayuli’s Bakery"
	if inside and absf(local.x) < 1.8 and absf(local.z+0.75) < 1.5:
		return "[E] Hablar con Mayuli"
	return ""

func interact(player: CharacterBody3D) -> bool:
	var action: String = interaction_text(player.global_position)
	if action.is_empty():
		return false
	if inside and action.contains("Hablar"):
		_greet()
		return true
	inside = not inside
	if door_tween != null and door_tween.is_valid():
		door_tween.kill()
	door.rotation.y = 0.0
	door_tween = create_tween()
	door_tween.tween_property(door,"rotation:y",1.30,.25)
	door_tween.tween_interval(.20)
	door_tween.tween_property(door,"rotation:y",0.0,.25)
	player.global_position = to_global(Vector3(0,1.0,2.20 if inside else 4.45))
	player.velocity = Vector3.ZERO
	if inside:
		_greet()
	else:
		reset()
	return true

func _find_voice() -> void:
	if voice_checked:
		return
	voice_checked = true
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		return
	# Windows SAPI voices expose names and language, not a reliable gender field.
	# Prefer known Spanish female voices; do not substitute a male voice.
	for data in DisplayServer.tts_get_voices():
		var lang: String = String(data.get("language","")).to_lower()
		var name_key: String = (String(data.get("name",""))+" "+String(data.get("id",""))).to_lower()
		if not lang.begins_with("es"):
			continue
		for female_name in ["helena","sabina","laura","elvira","dalia","paloma","monica","mónica","paulina","lucia","lucía","maria","maría","female"]:
			if name_key.contains(female_name):
				voice_id = String(data.get("id",""))
				return

func _greet() -> void:
	caption.text = "Mayuli\n"+GREETING
	caption.get_parent().show()
	caption_time = 5.0
	_find_voice()
	if not voice_id.is_empty():
		DisplayServer.tts_speak(GREETING,voice_id,85,1.0,.95,0,true)
	else:
		print("Mayuli's Bakery: instala una voz femenina en español en Windows (Helena, Sabina o Laura).")

func tick(delta: float) -> void:
	if caption_time > 0:
		caption_time = maxf(0.0,caption_time-delta)
		if caption_time == 0:
			caption.get_parent().hide()

func reset() -> void:
	inside = false
	caption_time = 0.0
	if caption != null:
		caption.get_parent().hide()
	if not voice_id.is_empty():
		DisplayServer.tts_stop()
