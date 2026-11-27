extends Node3D
# Airport arrivals inspired by the supplied exterior/interior/baggage references.
# Geometry is procedural, not a measured terminal survey; the city is not loaded.
const Progress = preload("res://airport_progress.gd")
const Person = preload("res://street_person.gd")
const Lights = preload("res://vehicle_lights.gd")
const DESK := Vector3(-2.7,0,-24.4)
const GATE := Vector3(0,0,-20)
const CART_START := Vector3(-5,.03,-16)
const EXIT := Vector3(0,0,1)
const BELT := Vector3(4,.72,-11)
const BELT_LEFT := 1.0
const BELT_HIDDEN := 12.6
const BELT_RADIUS := 1.5
const BELT_WALL := 10.8
const BELT_LOOP := 2.0*(BELT_HIDDEN-BELT_LEFT)+TAU*BELT_RADIUS
var luggage_mesh: ArrayMesh
var baggage_slats: Array[MeshInstance3D] = []
const TASKS := ["Espera tu turno en migración.","Acércate a la agente y entrega el pasaporte.","Espera la revisión y recoge el pasaporte.","Cruza el pasador verde.","Recoge un carrito de equipaje.","Recoge tu primera maleta de la cinta.","Coloca la primera maleta en el carrito.","Recoge tu segunda maleta de la cinta.","Coloca la segunda maleta en el carrito.","Sal del aeropuerto con tus maletas.","Acércate al taxi con el carrito.","Recoge la primera maleta del carrito.","Coloca la primera maleta en el maletero.","Recoge la segunda maleta del carrito.","Coloca la segunda maleta en el maletero.","Espera a que el chofer cierre el maletero.","Sube al taxi por cualquiera de las puertas traseras.","Fase 1 completada. Viaje pendiente."]
var progress := Progress.new()
var mats: Dictionary = {}
var unit_box := BoxMesh.new()
var contact_shadow_mesh: PlaneMesh
var contact_shadow_material: StandardMaterial3D
var player: CharacterBody3D
var camera: Camera3D
var taxi: Node3D
var lid: Node3D
var door: Node3D
var opposite_door: Node3D
var driver: Person
var bags: Array[Node3D] = []
var walkers: Array = []
var objective: Label
var prompt: Label
var message: Label
var menu: PanelContainer
var hud: CanvasLayer
var yaw := PI
var pitch := -.08
var menu_open := false
var touch_keys: Dictionary = {}
var mobile := false
var note_time := 0.0
var marker: Node3D
var marker_arrow: Label3D
var lid_tween: Tween
var officer: Person
var previous: Person
var passport: Node3D
var officer_grip: Node3D
var cart: Node3D
var gate_visual: MeshInstance3D
var gate_light: MeshInstance3D
var gate_body: StaticBody3D
var exit_visual: MeshInstance3D
var exit_body: StaticBody3D
var belt_time := 0.0
var stage_time := 0.0
var spoken_welcome := false
var migration_greeted := false
var migration_part := 0
var migration_remaining := 0.0
var migration_thanked := false
var migration_voice: AudioStreamPlayer
var protagonist_voice_id := ""
const MIGRATION_LINES := {"next":["Agente","¡Próximooo!",1.52],"greeting":["Agente","Buenas tardes, su pasaporte, por favor.",2.64],"handover":["Tú","Buenas tardes. Aquí tiene.",2.24],"question":["Agente","¿Hace mucho tiempo que no viene a Cuba?",2.24],"answer":["Tú","Sí, hace varios años.",3.52],"welcome":["Agente","Todo está en orden. Puede pasar a recoger su equipaje. Bienvenido a la patria.",4.64],"thanks":["Tú","Muchas gracias.",1.44]}
var voice_id := ""
var bag_arrows: Array[Label3D] = []
var other_bags: Array[Node3D] = []
var driver_opening := false
var driver_route_index := 0
var driver_return_index := 0
var driver_ready := false
var cabin_look := Vector2.ZERO
var waiting_people: Array[Person] = []
var terminal_people: Array[Dictionary] = []
var ambient_bag_slots: Dictionary = {}
var ambient_trolley: Node3D
var ambient_clock := 0.0
var dialogue: Label
var airport_audio: Dictionary = {}
var airport_samples: Dictionary = {}
var announcement_time := 11.0
var announcement_index := 0
var announcement_caption_time := 0.0
var footstep_time := 0.0
var footstep_variant := 0
const AIRPORT_SAMPLE_RATE := 16000
const AIRPORT_ANNOUNCEMENTS := ["Atención, pasajeros. Comprueben sus etiquetas antes de retirar el equipaje.","Bienvenidos al Aeropuerto Internacional José Martí. Mantengan despejadas las zonas de circulación.","Se recuerda a los pasajeros que deben mantener sus pertenencias consigo en todo momento."]

func _ready() -> void:
	mobile = OS.has_feature("android") or OS.has_feature("ios") or OS.get_cmdline_user_args().has("--touch-controls")
	progress.load_game()
	_make_environment()
	_make_terminal()
	_make_taxi()
	_make_people()
	_make_player()
	_make_arrivals_props()
	_make_bags()
	_make_terminal_people()
	_update_belt(0.0)
	_make_hud()
	var voices := DisplayServer.tts_get_voices_for_language("es")
	if not voices.is_empty(): voice_id = voices[0]
	_make_airport_audio()
	migration_voice = AudioStreamPlayer.new()
	add_child(migration_voice)
	var male_voices := DisplayServer.tts_get_voices_for_language("es")
	if male_voices.size()>1: protagonist_voice_id = male_voices[1]
	_sync()
	if progress.stage==2: _migration_line("handover")
	elif progress.stage==3: _migration_line("thanks")
	if progress.stage==Progress.COMPLETE: _seat_player()
	else: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mobile else Input.MOUSE_MODE_CAPTURED

func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.roughness = .84
		mats[key] = mat
	return mats[key] as StandardMaterial3D

func _box(parent: Node3D,p: Vector3,size: Vector3,color: Color,solid: bool=false) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = unit_box
	visual.material_override = _mat(color)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(visual)
	visual.position = p
	visual.scale = size
	if solid:
		var body := StaticBody3D.new()
		parent.add_child(body)
		body.position = p
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)
	return visual

func _label3(parent: Node3D,words: String,p: Vector3,pixel: float,color: Color=Color.WHITE) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = 48
	label.pixel_size = pixel
	label.modulate = color
	label.outline_size = 0
	label.double_sided = false
	parent.add_child(label)
	label.position = p
	return label

# Tiny generated textures are shared; no external art dependencies or PBR maps.
func _finish_texture(kind: String) -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 1297
	noise.frequency = .085
	var img := Image.create(128,128,false,Image.FORMAT_RGB8)
	for y in range(128):
		for x in range(128):
			var n := noise.get_noise_2d(float(x),float(y))
			var fine := float(posmod(x*73+y*137+x*y*17,31))/30.0-.5
			var v := .94+n*.055+fine*.045
			if kind=="tile":
				var tx := x%32
				var ty := y%32
				var variation := float(posmod(floori(float(x)/32.0)*13+floori(float(y)/32.0)*7,9))*.006
				v = .91+n*.065+fine*.075+variation
				if tx==0 or ty==0: v = .56
				elif tx==1 or ty==1: v = .78
				elif tx==31 or ty==31: v = .85
			elif kind=="ceiling":
				v = .95+fine*.035
				if x%32==0 or y%32==0: v = .64
			elif kind=="asphalt":
				v = .82+n*.065+fine*.17
			img.set_pixel(x,y,Color(v,v,v))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _architectural_material(kind: String,color: Color) -> StandardMaterial3D:
	var key := "architecture:"+kind+":"+color.to_html()
	if not mats.has(key):
		var texture_key := "texture:"+kind
		if not mats.has(texture_key): mats[texture_key] = _finish_texture(kind)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.albedo_texture = mats[texture_key] as Texture2D
		mat.roughness = .48 if kind=="tile" else .88
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		mat.uv1_triplanar = true
		mat.uv1_world_triplanar = true
		mat.uv1_scale = Vector3.ONE*.25 if kind in ["tile","ceiling"] else Vector3.ONE*.60
		mats[key] = mat
	return mats[key] as StandardMaterial3D

func _architectural_finish(node: MeshInstance3D,kind: String,color: Color) -> void:
	node.material_override = _architectural_material(kind,color)

func _floor_and_ceiling() -> void:
	# Replace dozens of individual grout strips with one repeating tile material.
	_architectural_finish(_box(self,Vector3(0,.016,-17),Vector3(29.4,.03,29.6),Color("#e6dfd0")),"tile",Color("#e6dfd0"))
	_architectural_finish(_box(self,Vector3(0,3.997,-17),Vector3(29.3,.012,29.7),Color("#e1e3df")),"ceiling",Color("#e1e3df"))
	var frame_color := Color("#b6babe")
	var diffuser := StandardMaterial3D.new()
	diffuser.albedo_color = Color("#f8f6e8")
	diffuser.emission_enabled = true
	diffuser.emission = Color("#fff7e0")
	diffuser.emission_energy_multiplier = .55
	for z in [-29.0,-24.0,-18.0,-12.0,-6.0]:
		_box(self,Vector3(0,3.94,float(z)),Vector3(29.3,.07,.40),Color("#a73034"))
		for x in [-10.0,-5.0,0.0,5.0,10.0]:
			var at := Vector3(float(x),3.935,float(z)+1.0)
			_box(self,at,Vector3(1.20,.065,.65),frame_color)
			var panel := _box(self,at+Vector3(0,-.042,0),Vector3(1.10,.024,.55),Color("#f8f6e8"))
			panel.material_override = diffuser
		# Ceiling vents and structural details are flat, never in the walking space.
		for x in [-12.0,12.0]:
			var at := Vector3(float(x),3.978,float(z)+2.0)
			_box(self,at,Vector3(.75,.025,.45),frame_color)
			for i in range(4):
				_box(self,at+Vector3(0,-.018,-.15+float(i)*.10),Vector3(.61,.010,.026),Color("#646c70"))
	# Five shadowless local lights, with small overlapping ranges, for Compatibility.
	for at in [Vector3(0,3.55,-27),Vector3(-5,3.55,-15),Vector3(5,3.55,-15),Vector3(-5,3.55,-6),Vector3(5,3.55,-6)]:
		var light := OmniLight3D.new()
		light.light_color = Color("#fff5e2")
		light.light_energy = .68
		light.omni_range = 8.2
		light.omni_attenuation = 1.5
		light.shadow_enabled = false
		add_child(light)
		light.position = at

func _make_contact_shadow(parent: Node3D,at: Vector3,dims: Vector2) -> void:
	# A shared soft ground-contact decal, independent of expensive dynamic shadows.
	if contact_shadow_mesh==null:
		contact_shadow_mesh = PlaneMesh.new()
		contact_shadow_mesh.size = Vector2.ONE
		var img := Image.create(64,64,false,Image.FORMAT_RGBA8)
		for y in range(64):
			for x in range(64):
				var p := Vector2(float(x)/63.0*2.0-1.0,float(y)/63.0*2.0-1.0)
				var alpha := pow(maxf(0.0,1.0-p.length_squared()),2.0)*.33
				img.set_pixel(x,y,Color(0.07,0.08,0.09,alpha))
		img.generate_mipmaps()
		contact_shadow_material = StandardMaterial3D.new()
		contact_shadow_material.albedo_texture = ImageTexture.create_from_image(img)
		contact_shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		contact_shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		contact_shadow_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var shadow := MeshInstance3D.new()
	shadow.mesh = contact_shadow_mesh
	shadow.material_override = contact_shadow_material
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(shadow)
	shadow.position = at
	shadow.scale = Vector3(dims.x,1.0,dims.y)

func _terminal_sign(words: String,at: Vector3,dims: Vector2,pixel: float,two_sided: bool=false,facing: float=0.0) -> void:
	var sign_root := Node3D.new()
	add_child(sign_root)
	sign_root.position = at
	sign_root.rotation.y = facing
	_box(sign_root,Vector3.ZERO,Vector3(dims.x,dims.y,.10),Color("#164974"))
	_box(sign_root,Vector3(0,-dims.y*.5+.025,0),Vector3(dims.x,.05,.12),Color("#a9afb1"))
	var front := _label3(sign_root,words,Vector3(0,0,.058),pixel)
	front.double_sided = false
	if two_sided:
		var back := _label3(sign_root,words,Vector3(0,0,-.058),pixel)
		back.rotation.y = PI
		back.double_sided = false

func _make_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var material := ProceduralSkyMaterial.new()
	material.sky_top_color = Color("#5087b4")
	material.sky_horizon_color = Color("#c1d2d9")
	material.ground_bottom_color = Color("#929485")
	sky.sky_material = material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#e5e8ec")
	env.ambient_light_energy = .57
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-30,0)
	sun.light_energy = .88
	sun.light_color = Color("#fff2dc")
	sun.shadow_enabled = false
	add_child(sun)

func _make_terminal() -> void:
	var concrete := Color("#c8c5b8")
	var cream := Color("#eee6d3")
	var red := Color("#b92b2e")
	var blue := Color("#12548c")
	var ochre := Color("#c69a49")
	var glass := Color("#445b65")
	var metal := Color("#a9aaa5")
	_architectural_finish(_box(self,Vector3(0,-.18,-4),Vector3(84,.36,64),concrete,true),"concrete",concrete)
	_architectural_finish(_box(self,Vector3(0,.012,18),Vector3(84,.022,12),Color("#555956")),"asphalt",Color("#555956"))
	_architectural_finish(_box(self,Vector3(0,.015,5),Vector3(84,.03,13),concrete,true),"concrete",concrete)
	# The reference façade: ochre colonnade, deep blue fascia, long glass bays.
	for side in [-1.0,1.0]:
		var x := float(side)
		_architectural_finish(_box(self,Vector3(x*19,2.2,-2),Vector3(33,4.4,.30),cream,true),"plaster",cream)
		for i in range(7):
			var wx := x*(4.8+float(i)*4.3)
			var pane := _box(self,Vector3(wx,1.7,-1.80),Vector3(3.8,3.1,.12),glass)
			var tinted := _mat(Color("#516e7b")).duplicate() as StandardMaterial3D
			tinted.roughness = .23
			tinted.metallic = .12
			pane.material_override = tinted
			# Aluminium mullions and transoms give the exterior windows depth.
			for edge in [-1.84,0.0,1.84]:
				_box(self,Vector3(wx+float(edge),1.7,-1.70),Vector3(.045,3.1,.08),metal)
			_box(self,Vector3(wx,2.42,-1.69),Vector3(3.8,.055,.08),metal)
		_architectural_finish(_box(self,Vector3(x*14.8,2,-17),Vector3(.34,4,30),cream,true),"plaster",cream)
		_box(self,Vector3(x*14.58,.13,-17),Vector3(.07,.26,29.5),Color("#8d9290"))
	_architectural_finish(_box(self,Vector3(0,2,-32),Vector3(30,4,.35),cream,true),"plaster",cream)
	_box(self,Vector3(0,.13,-31.77),Vector3(29.1,.26,.07),Color("#8d9290"))
	_box(self,Vector3(0,4.12,-17),Vector3(30,.24,30),cream,true)
	_box(self,Vector3(0,3.95,1.1),Vector3(72,.52,6.6),ochre,true)
	_box(self,Vector3(0,4.35,1.1),Vector3(72,.32,6.6),blue)
	_box(self,Vector3(0,5.0,.8),Vector3(24,1.0,1.0),blue)
	_label3(self,"AEROPUERTO INTERNACIONAL\nJOSÉ MARTÍ – LA HABANA",Vector3(0,5.03,1.33),.010)
	for i in range(10):
		var x := -32.4+float(i)*7.2
		if absf(x)>2.8:
			_architectural_finish(_box(self,Vector3(x,1.85,3.7),Vector3(.43,3.7,.43),ochre,true),"plaster",ochre)
			_box(self,Vector3(x,.16,3.7),Vector3(.54,.32,.54),Color("#9e988a"))
			_make_contact_shadow(self,Vector3(x,.041,3.7),Vector2(1.1,1.1))
	_label3(self,"SALIDA  /  ARRIVALS",Vector3(0,3.82,4.45),.006)
	_floor_and_ceiling()
	# Migration room and physically gated passage. Only the centre opening leads onward.
	for side in [-1.0,1.0]:
		_architectural_finish(_box(self,Vector3(float(side)*8.3,2,-20),Vector3(12.8,4,.32),cream,true),"plaster",cream)
		_box(self,Vector3(float(side)*8.3,3.25,-20.19),Vector3(12.8,1.0,.08),red)
		_box(self,Vector3(float(side)*8.3,.13,-20.20),Vector3(12.8,.26,.05),Color("#8d9290"))
		_box(self,Vector3(float(side)*8.3,.13,-19.80),Vector3(12.8,.26,.05),Color("#8d9290"))
	# Enclosed immigration cubicle, with an open service window facing the queue.
	var booth := Vector3(-2.7,0,-22.5)
	var panel := Color("#d5d0c3")
	_box(self,booth+Vector3(0,.51,-.96),Vector3(2.15,1.02,.12),panel,true)
	_box(self,booth+Vector3(0,1.04,-1.03),Vector3(2.21,.10,.43),metal)
	_box(self,booth+Vector3(0,2.28,0),Vector3(2.25,.36,2.12),red)
	_box(self,booth+Vector3(0,1.08,.97),Vector3(2.15,2.16,.12),panel,true)
	for side in [-1.0,1.0]:
		var x := float(side)*1.02
		_box(self,booth+Vector3(x,.53,0),Vector3(.12,1.06,1.92),panel,true)
		for z in [-.94,.94]:
			_box(self,booth+Vector3(x,1.66,float(z)),Vector3(.10,1.23,.10),metal,true)
		var pane := _box(self,booth+Vector3(x,1.61,0),Vector3(.04,1.08,1.78),glass,true)
		var transparent := StandardMaterial3D.new()
		transparent.albedo_color = Color(.68,.80,.84,.16)
		transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		transparent.roughness = .22
		transparent.cull_mode = BaseMaterial3D.CULL_DISABLED
		pane.material_override = transparent
	var migration_sign := _label3(self,"MIGRACIÓN  •  01",booth+Vector3(0,2.29,-1.07),.004)
	migration_sign.rotation.y = PI
	migration_sign.double_sided = false
	# Desk equipment and chair, leaving the officer's head visible in the window.
	_box(self,booth+Vector3(-.65,1.22,-.66),Vector3(.42,.36,.09),Color("#333b40"))
	_box(self,booth+Vector3(-.65,1.08,-.60),Vector3(.40,.035,.22),Color("#363b3f"))
	_box(self,booth+Vector3(0,.48,.20),Vector3(.48,.10,.48),Color("#343a3e"))
	_box(self,booth+Vector3(0,.81,.47),Vector3(.48,.65,.09),Color("#343a3e"))
	_box(self,booth+Vector3(0,.24,.20),Vector3(.09,.45,.09),metal)
	_terminal_sign("CONTROL DE PASAPORTES",Vector3(0,3.40,-20.23),Vector2(5.4,.65),.0065,false,PI)
	for side in [-1.0,1.0]:
		_box(self,Vector3(float(side)*1.7,.55,-20),Vector3(.32,1.10,.55),metal,true)
	gate_body = StaticBody3D.new()
	add_child(gate_body)
	gate_body.position = GATE+Vector3.UP*.53
	var gate_shape := BoxShape3D.new()
	gate_shape.size = Vector3(3.4,1.06,.23)
	var gate_col := CollisionShape3D.new()
	gate_col.shape = gate_shape
	gate_body.add_child(gate_col)
	gate_visual = _box(gate_body,Vector3.ZERO,Vector3(3.35,.12,.20),metal)
	gate_light = _box(self,Vector3(1.7,1.16,-20.29),Vector3(.20,.12,.06),red)
	# Queue barriers flank the walking lane, never close the central aisle.
	for x in [-4.0,2.5]:
		for z in [-30.0,-27.8,-25.6]:
			_box(self,Vector3(float(x),.49,float(z)),Vector3(.07,.98,.07),Color("#323638"))
			_box(self,Vector3(float(x),.035,float(z)),Vector3(.28,.07,.28),metal)
			if z<-26.0: _box(self,Vector3(float(x),.88,float(z)+1.1),Vector3(.035,.07,2.2),blue)
	# Red counter fascia, flight information panels and modest seating.
	for i in range(3):
		var z := -30.0+float(i)*3.0
		_box(self,Vector3(12.9,1.0,z),Vector3(2.0,1.95,2.4),Color("#ddd9cc"),true)
		_box(self,Vector3(13.0,2.52,z),Vector3(2.3,.75,2.75),red)
		var display := _label3(self,"0"+str(i+2),Vector3(11.80,2.53,z),.006)
		display.rotation.y = -PI*.5
	_box(self,Vector3(8.5,2.65,-20.20),Vector3(4.5,1.35,.12),Color("#252d35"))
	var flight_sign := _label3(self,"LLEGADAS  /  ARRIVALS\nMIAMI      LANDED\nMADRID     LANDED\nPANAMÁ     EXPECTED",Vector3(8.5,2.66,-20.28),.0045,Color("#e4d381"))
	flight_sign.rotation.y = PI
	flight_sign.double_sided = false
	for z in [-17.0,-14.0,-8.0]:
		_box(self,Vector3(-13.5,.46,float(z)),Vector3(1.0,.13,2.2),blue,true)
		_box(self,Vector3(-13.95,.85,float(z)),Vector3(.13,.75,2.2),blue)
	_make_baggage_carousel(metal,cream)
	_terminal_sign("RECOGIDA DE EQUIPAJE",Vector3(-5,3.40,-19.74),Vector2(5.2,.65),.0065)
	_box(self,Vector3(0,3.25,-2.25),Vector3(5,.5,.15),red)
	var exit_sign := _label3(self,"SALIDA",Vector3(0,3.25,-2.34),.007)
	exit_sign.rotation.y = PI
	exit_sign.double_sided = false
	exit_body = StaticBody3D.new()
	add_child(exit_body)
	exit_body.position = Vector3(0,1.4,-2)
	var exit_col := CollisionShape3D.new()
	var exit_shape := BoxShape3D.new()
	exit_shape.size = Vector3(5,2.8,.24)
	exit_col.shape = exit_shape
	exit_body.add_child(exit_col)
	exit_visual = _box(exit_body,Vector3.ZERO,Vector3(4.95,2.78,.12),glass)
	for x in range(-36,37,6):
		_box(self,Vector3(float(x),.025,18),Vector3(2.8,.012,.11),Color("#e1d7ab"))
	_box(self,Vector3(0,.028,11.9),Vector3(82,.012,.12),Color("#c9ac51"))
	for x in [-32.0,-22.0,20.0,31.0]:
		_box(self,Vector3(x,1.2,9.4),Vector3(.12,2.4,.12),metal)
		_terminal_sign("TAXIS",Vector3(x,2.2,9.48),Vector2(.95,.42),.0045,true)
	for x in [-42.0,42.0]:
		_box(self,Vector3(x,1,8),Vector3(.3,2,36),concrete,true)
	_box(self,Vector3(0,1,26),Vector3(84,2,.3),concrete,true)
	for x in [-28.0,-15.0,25.0,35.0]:
		_box(self,Vector3(x,.24,23.4),Vector3(2.5,.48,1.5),Color("#a5a89b"))
		_box(self,Vector3(x,1.6,23.4),Vector3(.21,2.5,.21),Color("#7e6c50"))
		for leaf in [-1.0,1.0]:
			var v := _box(self,Vector3(x+float(leaf)*.70,2.96,23.4),Vector3(1.8,.16,.62),Color("#668453"))
			v.rotation.z = float(leaf)*-.25

func _make_baggage_carousel(metal: Color,cream: Color) -> void:
	# The belt runs through two real openings into a screened service area.
	var rubber := Color("#25292c")
	var trim := Color("#777f82")
	# Straight runs and a rounded return. Collision remains on the low deck.
	_box(self,Vector3(5.9,.30,-11),Vector3(9.8,.60,3.9),metal,true)
	var cap := MeshInstance3D.new()
	var drum := CylinderMesh.new()
	drum.top_radius = 1.95
	drum.bottom_radius = 1.95
	drum.height = .58
	drum.radial_segments = 32
	drum.rings = 0
	cap.mesh = drum
	cap.material_override = _mat(metal)
	cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cap)
	cap.position = Vector3(BELT_LEFT,.29,-11)
	var body := StaticBody3D.new()
	add_child(body)
	body.position = cap.position
	var shape := CylinderShape3D.new()
	shape.radius = 1.95
	shape.height = .58
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	# Moving slats trace the same path as luggage; the edge remains continuous.
	for z in [-12.5,-9.5]:
		_box(self,Vector3(6,.655,float(z)),Vector3(10.0,.07,.92),rubber)
		for edge in [-1.0,1.0]:
			_box(self,Vector3(6,.70,float(z)+float(edge)*.50),Vector3(10.0,.055,.075),trim)
	_box(self,Vector3(6,.69,-11),Vector3(10.0,.12,1.90),metal)
	for i in range(36):
		var a := -PI*.5-PI*(float(i)+.5)/36.0
		var p := Vector3(BELT_LEFT+cos(a)*BELT_RADIUS,.69,-11+sin(a)*BELT_RADIUS)
		var segment := _box(self,p,Vector3(.94,.065,.15),rubber)
		segment.rotation.y = -a
	# Slats provide visible belt motion without textures or per-frame mesh rebuilding.
	for i in range(84):
		var slat := _box(self,Vector3.ZERO,Vector3(.89,.012,.027),Color("#3c4244"))
		baggage_slats.append(slat)
	# Wall panels leave openings at z=-12.5 and -9.5, with black rubber curtains.
	_box(self,Vector3(BELT_WALL,2,-16.47),Vector3(.22,4,6.66),cream,true)
	_box(self,Vector3(BELT_WALL,2,-5.43),Vector3(.22,4,6.86),cream,true)
	_box(self,Vector3(BELT_WALL,2,-11),Vector3(.22,4,1.72),cream,true)
	for z in [-12.5,-9.5]:
		var zz := float(z)
		_box(self,Vector3(BELT_WALL,.32,zz),Vector3(.24,.64,1.28),metal,true)
		_box(self,Vector3(BELT_WALL,2.82,zz),Vector3(.24,2.36,1.28),cream,true)
		_box(self,Vector3(BELT_WALL+.24,1.12,zz),Vector3(.035,1.0,1.25),Color("#101415"))
		for i in range(9):
			_box(self,Vector3(BELT_WALL-.14,1.16,zz-.56+float(i)*.14),Vector3(.045,.94,.125),Color("#202427"))
		for side in [-1.0,1.0]:
			_box(self,Vector3(BELT_WALL-.15,1.15,zz+float(side)*.67),Vector3(.08,1.1,.08),trim)
		_box(self,Vector3(BELT_WALL-.15,1.65,zz),Vector3(.08,.10,1.40),trim)
	# The signs and approach aisles stay in their existing locations.
	_box(self,Vector3(4,1.4,-11),Vector3(.13,1.3,.13),metal)
	_box(self,Vector3(4,2.07,-11),Vector3(1.8,.65,.14),Color("#168bbb"))
	var belt_back := _label3(self,"2  EQUIPAJE",Vector3(4,2.08,-11.09),.0035)
	belt_back.rotation.y = PI
	belt_back.double_sided = false
	var belt_front := _label3(self,"2  EQUIPAJE",Vector3(4,2.08,-10.91),.0035)
	belt_front.double_sided = false

func _wheel(root: Node3D,p: Vector3) -> void:
	var wheel := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .33
	cylinder.bottom_radius = .33
	cylinder.height = .19
	cylinder.radial_segments = 12
	cylinder.rings = 0
	wheel.mesh = cylinder
	wheel.material_override = _mat(Color("#272a2a"))
	wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(wheel)
	wheel.position = p
	wheel.rotation.z = PI*.5

func _car_shell(root: Node3D,paint: Color,interactive: bool) -> void:
	var glass := Color("#536b73")
	var dark := Color("#333a3c")
	var chrome := Color("#b9beb8")
	_box(root,Vector3(0,.39,0),Vector3(1.72,.28,4.5),dark,interactive)
	_box(root,Vector3(0,.74,1.25),Vector3(1.76,.52,1.90),paint,interactive)
	if interactive:
		# Hollow passenger cabin: floor and sills instead of a solid body block.
		_box(root,Vector3(0,.55,-.03),Vector3(1.54,.12,1.84),paint)
		_box(root,Vector3(0,1.66,-.10),Vector3(1.59,.10,1.96),paint)
		_box(root,Vector3(0,.78,-1.04),Vector3(1.54,.42,.11),paint)
		for z in [-1.04,.89]:
			_cabin_glass(root,Vector3(0,1.35,float(z)),Vector3(1.45,.53,.028))
			_box(root,Vector3(0,1.08,float(z)),Vector3(1.54,.055,.055),chrome)
			_box(root,Vector3(0,1.62,float(z)),Vector3(1.56,.07,.065),paint)
	else:
		_box(root,Vector3(0,.78,-.03),Vector3(1.54,.45,1.84),paint)
		_box(root,Vector3(0,1.51,-.10),Vector3(1.57,.12,1.86),paint)
		_box(root,Vector3(0,1.20,.84),Vector3(1.45,.48,.055),glass)
		_box(root,Vector3(0,1.20,-1.03),Vector3(1.45,.48,.055),glass)
	_box(root,Vector3(0,.55,-1.66),Vector3(1.72,.14,1.26),dark)
	_box(root,Vector3(0,.75,-2.26),Vector3(1.74,.40,.10),paint,interactive)
	for side in [-1.0,1.0]:
		var x := float(side)
		_box(root,Vector3(x*.83,.77,-1.65),Vector3(.12,.44,1.16),paint,interactive)
		if interactive:
			for z in [-1.01,.02,.87]:
				_box(root,Vector3(x*.77,1.35,float(z)),Vector3(.065,.57,.065),paint)
			_box(root,Vector3(x*.78,.82,.45),Vector3(.10,.46,.84),paint,true)
			_cabin_glass(root,Vector3(x*.78,1.35,.45),Vector3(.028,.51,.80))
		else:
			_box(root,Vector3(x*.78,1.20,-.40),Vector3(.06,.48,1.2),glass)
			_box(root,Vector3(x*.78,1.21,-.93),Vector3(.08,.53,.09),paint)
		_box(root,Vector3(x*.70,.76,2.21),Vector3(.26,.19,.07),Color("#f2e7bb"))
		_box(root,Vector3(x*.70,.75,-2.32),Vector3(.22,.15,.05),Color("#aa3633"))
		for z in [-1.39,1.38]:
			_wheel(root,Vector3(x*.84,.33,float(z)))
	_box(root,Vector3(0,.50,2.25),Vector3(1.85,.13,.12),chrome)
	_box(root,Vector3(0,.50,-2.30),Vector3(1.85,.13,.12),chrome)
	if interactive:
		lid = Node3D.new()
		root.add_child(lid)
		lid.position = Vector3(0,1.00,-1.07)
		_box(lid,Vector3(0,0,-.60),Vector3(1.72,.09,1.20),paint)
		door = _make_rear_door(root,-1.0,paint,chrome)
		opposite_door = _make_rear_door(root,1.0,paint,chrome)
		_make_taxi_interior(root,door)
	else:
		_box(root,Vector3(0,1.0,-1.65),Vector3(1.72,.09,1.2),paint)

func _make_rear_door(root: Node3D,side: float,paint: Color,chrome: Color) -> Node3D:
	var panel := Node3D.new()
	root.add_child(panel)
	panel.position = Vector3(side*.78,.83,.02)
	_box(panel,Vector3(0,0,-.50),Vector3(.09,.46,.98),paint,true)
	_cabin_glass(panel,Vector3(0,.52,-.50),Vector3(.027,.51,.94))
	_box(panel,Vector3(0,.79,-.50),Vector3(.055,.055,1.0),paint)
	_box(panel,Vector3(0,.52,-.97),Vector3(.055,.56,.045),paint)
	_box(panel,Vector3(side*.06,.13,-.79),Vector3(.025,.04,.15),chrome)
	return panel

func _cabin_glass(root: Node3D,at: Vector3,dims: Vector3) -> void:
	var pane := _box(root,at,dims,Color("#92b9cb"))
	var key := "taxi_clear_glass"
	if not mats.has(key):
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(.68,.84,.92,.09)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mat.roughness = .16
		mats[key] = mat
	pane.material_override = mats[key] as StandardMaterial3D

func _cabin_disc(root: Node3D,at: Vector3,radius: float,depth: float,color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = depth
	cylinder.radial_segments = 20
	cylinder.rings = 0
	node.mesh = cylinder
	node.material_override = _mat(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	node.position = at
	node.rotation.x = PI*.5
	return node

func _make_taxi_interior(root: Node3D,rear_door: Node3D) -> void:
	var red := Color("#ad282b")
	var vinyl := Color("#712728")
	var cream := Color("#d9c1ac")
	var metal := Color("#bfc3bd")
	var black := Color("#252627")
	# Classic red painted dashboard and cream roof liner, based on the reference.
	# The painted floor ends at y=.610; keep the carpet surface above it.
	# Coplanar surfaces caused visible z-fighting on Intel GL Compatibility.
	_box(root,Vector3(0,.622,-.04),Vector3(1.52,.024,1.84),black)
	_box(root,Vector3(0,1.595,-.09),Vector3(1.46,.028,1.88),cream)
	_box(root,Vector3(0,.97,.73),Vector3(1.45,.29,.32),red)
	_box(root,Vector3(0,1.125,.72),Vector3(1.44,.048,.35),red)
	_box(root,Vector3(0,1.015,.552),Vector3(1.38,.025,.018),metal)
	_box(root,Vector3(.37,1.065,.545),Vector3(.59,.145,.024),cream)
	for i in range(3):
		var x := .19+float(i)*.17
		_cabin_disc(root,Vector3(x,1.071,.522),.061,.018,metal)
		_cabin_disc(root,Vector3(x,1.071,.507),.049,.015,black)
		var needle := _box(root,Vector3(x,1.071,.494),Vector3(.004,.065,.006),cream)
		needle.rotation.z = -.65+float(i)*.4
	_box(root,Vector3(-.14,.977,.544),Vector3(.26,.085,.028),metal)
	_box(root,Vector3(-.14,.986,.521),Vector3(.17,.045,.012),black)
	for x in [-.25,-.035]: _cabin_disc(root,Vector3(float(x),.971,.503),.018,.016,black)
	_box(root,Vector3(-.49,1.043,.55),Vector3(.35,.11,.025),red)
	_box(root,Vector3(-.49,1.06,.53),Vector3(.11,.018,.02),metal)
	# Steering wheel with a thin rim, three spokes and horn hub.
	var steering := Node3D.new()
	root.add_child(steering)
	steering.position = Vector3(.40,1.16,.43)
	steering.rotation.x = -.30
	var rim := TorusMesh.new()
	rim.inner_radius = .151
	rim.outer_radius = .171
	rim.rings = 24
	rim.ring_segments = 8
	var wheel := MeshInstance3D.new()
	wheel.mesh = rim
	wheel.material_override = _mat(black)
	wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	steering.add_child(wheel)
	wheel.rotation.x = PI*.5
	for i in range(3):
		var angle := TAU*float(i)/3.0
		var spoke := _box(steering,Vector3(sin(angle)*.085,cos(angle)*.085,0),Vector3(.019,.145,.018),metal)
		spoke.rotation.z = -angle
	_cabin_disc(steering,Vector3.ZERO,.045,.032,red)
	_box(root,Vector3(.40,1.10,.56),Vector3(.07,.07,.23),black)
	# Wide bench seats, stitched seams and trim.
	for z in [-.82,.16]:
		var seat_z := float(z)
		_box(root,Vector3(0,.70,seat_z),Vector3(1.39,.22,.45),vinyl)
		_box(root,Vector3(0,.94,seat_z-.24),Vector3(1.38,.42,.12),vinyl)
		_box(root,Vector3(0,1.155,seat_z-.24),Vector3(1.40,.047,.13),cream)
		for x in [-.46,0.0,.46]:
			_box(root,Vector3(float(x),.817,seat_z),Vector3(.008,.007,.39),cream)
			_box(root,Vector3(float(x),.95,seat_z-.305),Vector3(.008,.35,.006),cream)
	for x in [-.72,.72]:
		_box(root,Vector3(float(x),.84,.45),Vector3(.035,.40,.82),vinyl)
		_box(root,Vector3(float(x),1.055,.45),Vector3(.045,.045,.82),cream)
		_box(root,Vector3(float(x),.95,.38),Vector3(.065,.045,.27),cream)
	for panel in [rear_door,opposite_door]:
		var inward := 1.0 if panel==rear_door else -1.0
		_box(panel,Vector3(inward*.052,0,-.50),Vector3(.025,.37,.92),vinyl)
		_box(panel,Vector3(inward*.07,.21,-.50),Vector3(.05,.045,.92),cream)
		_box(panel,Vector3(inward*.075,.07,-.50),Vector3(.06,.045,.28),cream)
	# Rear-view mirror, sun strip, and small taxi sign on the dashboard.
	_box(root,Vector3(0,1.53,.77),Vector3(.035,.15,.035),black)
	_box(root,Vector3(0,1.46,.72),Vector3(.30,.10,.042),black)
	_box(root,Vector3(0,1.46,.693),Vector3(.27,.077,.008),Color("#738c95"))
	_box(root,Vector3(0,1.58,.895),Vector3(1.45,.09,.03),Color("#315b78"))
	_box(root,Vector3(-.04,1.185,.76),Vector3(.20,.075,.11),Color("#dfb43e"))
	_label3(root,"TAXI",Vector3(-.04,1.185,.70),.0017,black).rotation.y = PI

func _make_taxi() -> void:
	taxi = Node3D.new()
	add_child(taxi)
	taxi.position = Vector3(7.5,.025,13.4)
	taxi.rotation.y = PI*.5
	_car_shell(taxi,Color("#d6ad47"),true)
	_make_contact_shadow(taxi,Vector3(0,.012,0),Vector2(2.5,5.3))
	_box(taxi,Vector3(0,1.65,-.1),Vector3(.54,.18,.30),Color("#ead16e"))
	var sign_label := _label3(taxi,"TAXI",Vector3(0,1.65,.061),.003,Color("#222222"))
	sign_label = _label3(taxi,"TAXI",Vector3(0,1.65,-.261),.003,Color("#222222"))
	sign_label.rotation.y = PI
	Lights.attach(taxi,Vector3(.70,.76,2.25),Vector3(.70,.75,-2.35),Vector3(.23,.16,.025),Vector3(.18,.13,.025))
	for i in range(3):
		var other := Node3D.new()
		add_child(other)
		other.position = Vector3([-13.0,20.0,31.0][i],.025,13.4)
		other.rotation.y = PI*.5
		_car_shell(other,[Color("#aeb8b9"),Color("#e1dacb"),Color("#66838c")][i],false)
		_make_contact_shadow(other,Vector3(0,.012,0),Vector2(2.5,5.3))
		# Parked props are outside the mission's walkable interaction area.
		_box(other,Vector3(0,.75,0),Vector3(1.75,1.5,4.5),Color("#777777"),true).hide()

func _make_people() -> void:
	for i in range(8):
		var person := Person.new()
		add_child(person)
		person.setup(330+i*17,i==0 or i==5,true)
		person.position = Vector3(-28+float(i)*7.7,.03,6.4 if i%2==0 else 8.4)
		_make_contact_shadow(person,Vector3(0,.014,0),Vector2(.82,.68))
		person.rotation.y = PI*.5
		if i%3==1: person.set_bag(true)
		if i in [2,6]:
			walkers.append({"node":person,"origin":person.position,"side":1.0,"pause":float(i)*.45})
		else:
			waiting_people.append(person)
	# The driver stays outside the car footprint and walks along the curb side.
	driver = Person.new()
	add_child(driver)
	driver.setup(414)
	driver.position = taxi.to_global(Vector3(1.65,0,2.15))
	driver.rotation.y = PI
	if progress.stage>=11 and progress.stage<16:
		driver.position = taxi.to_global(Vector3(.85,0,-2.90))
	elif progress.stage==16:
		driver.position = taxi.to_global(Vector3(1.65,0,.30))
		driver_ready = true

func _terminal_person(style: int,at: Vector3,worker: bool=false) -> Person:
	var person := Person.new()
	add_child(person)
	person.setup(style,worker,true)
	person.position = at
	_make_contact_shadow(person,Vector3(0,.014,0),Vector2(.82,.68))
	return person

func _make_terminal_people() -> void:
	# Small groups deliberately stay off the migration lane and exit corridor.
	for i in range(2):
		var x := -10.5 if i==0 else 7.3
		var z := -26.8 if i==0 else -5.1
		var a := _terminal_person(561+i*39,Vector3(x,.03,z))
		var b := _terminal_person(582+i*41,Vector3(x+1.05,.03,z+.12))
		a.rotation.y = PI*.5
		b.rotation.y = -PI*.5
		terminal_people.append({"node":a,"role":"talk","partner":b,"offset":float(i)*3.0})
		terminal_people.append({"node":b,"role":"talk","partner":a,"offset":float(i)*3.0+2.8})
	# Workers patrol along the side wall rather than crossing the player's gate.
	var worker := _terminal_person(617,Vector3(-11.2,.03,-18.0),true)
	terminal_people.append({"node":worker,"role":"patrol","route":[Vector3(-11.2,.03,-18),Vector3(-11.2,.03,-10),Vector3(-11.2,.03,-4.6)],"index":1,"pause":1.7})
	# A passenger takes a non-player suitcase from the moving belt and carries it away.
	var collector := _terminal_person(643,Vector3(5,.03,-15.9))
	collector.rotation.y = 0.0
	terminal_people.append({"node":collector,"role":"collect","state":0,"pause":2.0,"bag_slot":0,"index":0,"route":[Vector3(5,.03,-13.40),Vector3(5,.03,-16.0),Vector3(9.5,.03,-16.0)],"bag":null})
	# A separate ambient trolley, never used by the player's mission.
	var pusher := _terminal_person(672,Vector3(-8.5,.03,-14.6))
	pusher.rotation.y = 0.0
	ambient_trolley = Node3D.new()
	add_child(ambient_trolley)
	var steel := Color("#a9afb1")
	_box(ambient_trolley,Vector3(0,.24,0),Vector3(.80,.06,1.04),steel)
	for x in [-.37,.37]:
		_box(ambient_trolley,Vector3(float(x),.57,.45),Vector3(.04,.70,.04),steel)
		for z in [-.43,.43]:
			_box(ambient_trolley,Vector3(float(x),.085,float(z)),Vector3(.09,.15,.14),Color("#303638"))
	_box(ambient_trolley,Vector3(0,.90,.45),Vector3(.80,.05,.05),Color("#253c57"))
	var load := _suitcase(Color("#465e55"))
	load.reparent(ambient_trolley,false)
	load.position = Vector3(0,.28,-.08)
	terminal_people.append({"node":pusher,"role":"push","route":[Vector3(-8.5,.03,-14.6),Vector3(-8.5,.03,-6.5)],"index":1,"pause":2.3})
	_update_ambient_trolley(pusher)

func _update_ambient_trolley(person: Person) -> void:
	var forward := person.global_transform.basis.z
	ambient_trolley.global_position = person.global_position+forward*.86
	ambient_trolley.global_position.y = .03
	ambient_trolley.rotation.y = person.rotation.y+PI
	for arm in person.arms:
		arm.rotation.x = -1.08

func _ambient_player_near(person: Person) -> bool:
	if player==null: return false
	return Vector2(person.global_position.x,person.global_position.z).distance_to(Vector2(player.global_position.x,player.global_position.z))<1.0

func _tick_terminal_people(delta: float) -> void:
	for item in terminal_people:
		var person: Person = item.node
		var role: String = item.role
		if role=="talk":
			var partner: Person = item.partner
			var diff := partner.global_position-person.global_position
			person.rotation.y = lerp_angle(person.rotation.y,atan2(diff.x,diff.z),minf(1.0,delta*3.0))
			_idle_person(person,delta,float(item.offset))
			var rhythm := sin((ambient_clock+float(item.offset))*1.1)
			if rhythm>.1:
				person.arms[1].rotation.x = lerpf(person.arms[1].rotation.x,-.35-rhythm*.32,minf(1.0,delta*5.0))
			continue
		if role=="collect":
			_tick_bag_collector(item,delta)
			continue
		var route: Array = item.route
		if float(item.pause)>0.0 or _ambient_player_near(person):
			item.pause = maxf(0.0,float(item.pause)-delta)
			_idle_person(person,delta,float(person.style_id)*.31)
		else:
			var goal: Vector3 = route[int(item.index)]
			if person.walk_to(goal,delta,.82 if role=="push" else 1.05):
				item.index = (int(item.index)+1)%route.size()
				item.pause = 2.0+float(posmod(person.style_id,3))*.6
		if role=="push": _update_ambient_trolley(person)

func _tick_bag_collector(item: Dictionary,delta: float) -> void:
	var person: Person = item.node
	var state: int = item.state
	var slot: int = item.bag_slot
	var bag: Node3D = other_bags[slot]
	var route: Array = item.route
	if state==0:
		item.pause = maxf(0.0,float(item.pause)-delta)
		_idle_person(person,delta,2.0)
		if float(item.pause)<=0.0: item.state = 1
	elif state==1:
		if _ambient_player_near(person):
			_idle_person(person,delta,2.0)
			return
		if person.walk_to(route[0],delta,1.05):
			person.rotation.y = 0.0
			item.state = 2
	elif state==2:
		_idle_person(person,delta,2.0)
		if not bag.visible: return
		var at := bag.global_position
		if absf(at.x-(person.global_position.x+.20))>.35 or absf(at.z+12.5)>.2: return
		if _ambient_player_near(person): return
		# Reach only for the assigned ambient bag, never the player's luggage.
		ambient_bag_slots[slot] = true
		person.arms[1].rotation.x = -1.0
		bag.reparent(person.arms[1],true)
		var pickup := create_tween()
		pickup.set_parallel(true)
		pickup.tween_property(bag,"position",Vector3(0,-.98,.02),.42)
		pickup.tween_property(bag,"rotation",Vector3.ZERO,.42)
		item.state = 6
		item.pause = .45
		item.index = 1
	elif state==6:
		item.pause = float(item.pause)-delta
		person.arms[1].rotation.x = lerpf(person.arms[1].rotation.x,-.08,minf(1.0,delta*4.0))
		if float(item.pause)<=0.0: item.state = 3
	elif state==3:
		if _ambient_player_near(person):
			_idle_person(person,delta,2.0)
		else:
			if person.walk_to(route[int(item.index)],delta,1.0):
				item.index = int(item.index)+1
				if int(item.index)>=route.size():
					item.state = 4
					item.pause = 8.0
		person.arms[1].rotation.x = -.08
	elif state==4:
		_idle_person(person,delta,2.0)
		person.arms[1].rotation.x = -.08
		item.pause = maxf(0.0,float(item.pause)-delta)
		# Recycle the ambient prop only when the player is away from this area.
		if float(item.pause)<=0.0 and player.global_position.distance_to(person.global_position)>8.0:
			bag.reparent(self,false)
			ambient_bag_slots.erase(slot)
			item.state = 5
	elif state==5:
		if _ambient_player_near(person):
			_idle_person(person,delta,2.0)
			return
		if person.walk_to(Vector3(5,.03,-15.9),delta,1.0):
			item.state = 0
			item.pause = 4.0

func _idle_person(person: Person,delta: float,offset: float) -> void:
	person.animate(delta,false)
	var t := ambient_clock+offset
	person.rotation.z = lerpf(person.rotation.z,sin(t*.83)*.021,minf(delta*3.0,1.0))
	for i in range(person.arms.size()):
		var arm: Node3D = person.arms[i]
		arm.rotation.x = lerpf(arm.rotation.x,sin(t*.72+float(i)*1.7)*.065,minf(delta*3.0,1.0))
		arm.rotation.z = sin(t*.57+float(i)*2.0)*.025
	for i in range(person.knees.size()):
		person.knees[i].rotation.x = maxf(0.0,sin(t*.83+float(i)*PI)*.045)

func _tick_ambient_people(delta: float) -> void:
	ambient_clock = fposmod(ambient_clock+delta,600.0)
	_tick_terminal_people(delta)
	for person in waiting_people:
		_idle_person(person,delta,float(person.style_id)*.31)
	for item in walkers:
		var person: Person = item.node
		var origin: Vector3 = item.origin
		if float(item.pause)>0.0:
			item.pause = maxf(0.0,float(item.pause)-delta)
			_idle_person(person,delta,float(person.style_id)*.31)
			continue
		var goal := origin+Vector3(float(item.side)*2.2,0,0)
		person.rotation.z = lerpf(person.rotation.z,0.0,minf(delta*5.0,1.0))
		for arm in person.arms: arm.rotation.z = lerpf(arm.rotation.z,0.0,minf(delta*5.0,1.0))
		if person.walk_to(goal,delta,1.05):
			item.side = -float(item.side)
			item.pause = 2.2+float(posmod(person.style_id,4))*.7

func _driver_walk_route(points: Array[Vector3],index: int,delta: float) -> int:
	if index>=points.size(): return index
	var at := taxi.to_global(points[index])
	driver.rotation.z = lerpf(driver.rotation.z,0.0,minf(delta*5.0,1.0))
	if driver.walk_to(at,delta,1.55): return index+1
	return index

func _make_player() -> void:
	player = CharacterBody3D.new()
	add_child(player)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .29
	capsule.height = 1.74
	collision.shape = capsule
	player.add_child(collision)
	player.position = progress.checkpoint
	camera = Camera3D.new()
	player.add_child(camera)
	camera.position = Vector3(0,.67,0)
	camera.current = true
	camera.fov = 75.0
	player.rotation.y = yaw
	camera.rotation.x = pitch

func _rounded_luggage_mesh() -> ArrayMesh:
	# Rounded rectangle extruded through depth; all seven bags share one mesh.
	var points: Array[Vector2] = []
	var radius := .048
	for i in range(4):
		var corner := Vector2(.152,.162)
		if i==1: corner.x = -corner.x
		elif i==2: corner = -corner
		elif i==3: corner.y = -corner.y
		for j in range(5):
			var angle := (float(i)+float(j)/4.0)*PI*.5
			points.append(corner+Vector2(cos(angle),sin(angle))*radius)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(points.size()):
		var a := points[i]
		var b := points[(i+1)%points.size()]
		for z in [-.115,.115]:
			var depth := float(z)
			var vertices: Array[Vector3] = [Vector3(0,0,depth),Vector3(b.x,b.y,depth),Vector3(a.x,a.y,depth)]
			if depth<0.0:
				vertices.reverse()
			for v in vertices:
				surface.set_normal(Vector3(0,0,signf(depth)))
				surface.add_vertex(v)
		var edge := b-a
		var normal := Vector3(edge.y,-edge.x,0).normalized()
		var sides: Array[Vector3] = [Vector3(a.x,a.y,-.115),Vector3(b.x,b.y,.115),Vector3(b.x,b.y,-.115),Vector3(a.x,a.y,-.115),Vector3(a.x,a.y,.115),Vector3(b.x,b.y,.115)]
		for v in sides:
			surface.set_normal(normal)
			surface.add_vertex(v)
	return surface.commit()

func _suitcase(color: Color) -> Node3D:
	var bag := Node3D.new()
	add_child(bag)
	if luggage_mesh==null: luggage_mesh = _rounded_luggage_mesh()
	var shell := MeshInstance3D.new()
	shell.mesh = luggage_mesh
	shell.material_override = _mat(color)
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bag.add_child(shell)
	shell.position.y = .255
	# Zipper seam, molded ribs, wheel housings, grip and retracted telescopic handle.
	var dark := Color("#303638")
	for x in [-.14,.14]:
		_box(bag,Vector3(float(x),.26,.118),Vector3(.014,.30,.009),color.darkened(.18))
		_box(bag,Vector3(float(x),.055,0),Vector3(.08,.075,.10),dark)
		var wheel := MeshInstance3D.new()
		var tire := CylinderMesh.new()
		tire.top_radius = .034
		tire.bottom_radius = .034
		tire.height = .032
		tire.radial_segments = 10
		tire.rings = 0
		wheel.mesh = tire
		wheel.material_override = _mat(dark)
		wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bag.add_child(wheel)
		wheel.position = Vector3(float(x),.035,.015)
		wheel.rotation.z = PI*.5
	for x in [-.073,.073]:
		_box(bag,Vector3(float(x),.476,0),Vector3(.028,.048,.045),dark)
		_box(bag,Vector3(float(x),.29,-.119),Vector3(.018,.29,.010),Color("#a3a9ab"))
	_box(bag,Vector3(0,.503,0),Vector3(.17,.025,.047),dark)
	_box(bag,Vector3(0,.254,.120),Vector3(.36,.012,.010),color.darkened(.42))
	_box(bag,Vector3(.13,.27,.13),Vector3(.025,.036,.009),Color("#c2c3bd"))
	return bag

func _make_arrivals_props() -> void:
	officer = Person.new()
	add_child(officer)
	officer.setup(331)
	officer.position = Vector3(-2.7,-.33,-22.30)
	officer.rotation.y = PI
	officer.scale = Vector3(.94,.94,.94)
	for leg in officer.limbs: leg.rotation.x = -PI*.5
	for knee in officer.knees: knee.rotation.x = PI*.5
	for arm in officer.arms: arm.rotation.x = -1.05
	# The hand mesh is centred at local (0,-.49,0) in StreetPerson's arm.
	# Place the grip at the palm, so the document follows every arm movement.
	officer_grip = Node3D.new()
	officer.arms[1].add_child(officer_grip)
	officer_grip.position = Vector3(0,-.51,.045)
	officer_grip.rotation.x = 1.85
	previous = Person.new()
	add_child(previous)
	previous.setup(343)
	previous.position = DESK+Vector3(0,.03,.0)
	# Passport is a real prop that changes parent between hand and officer.
	passport = Node3D.new()
	add_child(passport)
	_box(passport,Vector3.ZERO,Vector3(.105,.012,.15),Color("#213d66"))
	_box(passport,Vector3(0,.008,0),Vector3(.094,.008,.135),Color("#d9d1b7"))
	_box(passport,Vector3(0,.015,0),Vector3(.105,.008,.15),Color("#213d66"))
	# Fit the gold lettering within the 10.5 cm wide passport cover.
	var cover_title := _label3(passport,"PASAPORTE",Vector3(0,.0205,-.037),.00040,Color("#d4bd70"))
	cover_title.font_size = 24
	cover_title.rotation.x = -PI*.5
	cover_title.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	cover_title.fixed_size = false
	cart = Node3D.new()
	add_child(cart)
	cart.position = progress.cart_position
	cart.rotation.y = progress.cart_angle
	var steel := Color("#a9afb1")
	# Wide luggage platform, thin rails, actual round caster wheels.
	_box(cart,Vector3(0,.24,0),Vector3(.92,.055,1.12),steel)
	for x in [-.43,.43]:
		_box(cart,Vector3(float(x),.58,.49),Vector3(.035,.68,.035),steel)
		_box(cart,Vector3(float(x),.31,0),Vector3(.035,.095,1.10),steel)
		for z in [-.45,.45]:
			var wheel := MeshInstance3D.new()
			var tire := CylinderMesh.new()
			tire.top_radius = .085
			tire.bottom_radius = .085
			tire.height = .06
			tire.radial_segments = 12
			tire.rings = 0
			wheel.mesh = tire
			wheel.material_override = _mat(Color("#343a3c"))
			wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cart.add_child(wheel)
			wheel.position = Vector3(float(x),.09,float(z))
			wheel.rotation.z = PI*.5
			_box(cart,Vector3(float(x),.18,float(z)),Vector3(.05,.10,.05),steel)
	_box(cart,Vector3(0,.92,.49),Vector3(.91,.045,.045),Color("#253c57"))
	_box(cart,Vector3(0,.34,-.52),Vector3(.87,.035,.035),steel)
	_box(cart,Vector3(0,.66,.49),Vector3(.85,.03,.035),steel)
	_terminal_sign("CARROS DE EQUIPAJE",Vector3(-5,3.25,-17),Vector2(3.8,.55),.0055,true)
	for x in [-6.55,-3.45]:
		_box(self,Vector3(float(x),3.76,-17),Vector3(.035,.48,.035),Color("#a9afb1"))

func _make_bags() -> void:
	for i in range(2):
		var bag := _suitcase(Color("#506a8b") if i==0 else Color("#76584a"))
		bags.append(bag)
		var arrow := _label3(bag,"▼",Vector3(0,.85,0),.010,Color("#ffd976"))
		arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bag_arrows.append(arrow)
	for i in range(5):
		other_bags.append(_suitcase([Color("#a73b39"),Color("#c6a247"),Color("#506f59"),Color("#4e5052"),Color("#8b7770")][i]))
	marker = Node3D.new()
	add_child(marker)
	marker_arrow = _label3(marker,"▼",Vector3(0,1.7,0),.010,Color("#ffd976"))
	marker_arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _belt_pose(distance: float) -> Vector3:
	var d := fposmod(distance,BELT_LOOP)
	var length := BELT_HIDDEN-BELT_LEFT
	var arc := PI*BELT_RADIUS
	if d<length:
		return Vector3(BELT_HIDDEN-d,.72,-11-BELT_RADIUS)
	d -= length
	if d<arc:
		var a := -PI*.5-d/BELT_RADIUS
		return Vector3(BELT_LEFT+cos(a)*BELT_RADIUS,.72,-11+sin(a)*BELT_RADIUS)
	d -= arc
	if d<length:
		return Vector3(BELT_LEFT+d,.72,-11+BELT_RADIUS)
	d -= length
	var a := PI*.5-d/BELT_RADIUS
	return Vector3(BELT_HIDDEN+cos(a)*BELT_RADIUS,.72,-11+sin(a)*BELT_RADIUS)

func _belt_distance(slot: int) -> float:
	return belt_time+7.8+float(slot)*BELT_LOOP/7.0

func _belt_point(slot: int) -> Vector3:
	return _belt_pose(_belt_distance(slot))

func _move_belt_bag(bag: Node3D,slot: int) -> void:
	var distance := _belt_distance(slot)
	var p := _belt_pose(distance)
	var tangent := _belt_pose(distance+.04)-p
	bag.position = p
	bag.rotation.y = atan2(tangent.x,tangent.z)
	bag.visible = p.x<BELT_WALL-.12

func _update_belt(delta: float) -> void:
	belt_time = fposmod(belt_time+delta*.85,BELT_LOOP)
	for i in range(baggage_slats.size()):
		var distance := belt_time+float(i)*BELT_LOOP/float(baggage_slats.size())
		var p := _belt_pose(distance)
		var tangent := _belt_pose(distance+.04)-p
		var slat := baggage_slats[i]
		slat.position = Vector3(p.x,.736,p.z)
		slat.rotation.y = atan2(tangent.x,tangent.z)
		slat.visible = p.x<BELT_WALL-.13
	for i in range(other_bags.size()):
		if not ambient_bag_slots.has(i): _move_belt_bag(other_bags[i],i+2)
	for i in range(bags.size()):
		if Progress.bag_location(progress.stage,i,progress.first_bag)=="belt":
			_move_belt_bag(bags[i],i)

# Generate small PCM samples once per scene; no external assets are needed.
func _airport_sample(kind: String,duration: float,looped: bool=false) -> AudioStreamWAV:
	var count := roundi(duration*AIRPORT_SAMPLE_RATE)
	# Generate an overlap for seamless loops, instead of dipping to silence at each repeat.
	var overlap := roundi(.12*AIRPORT_SAMPLE_RATE) if looped else 0
	var data := PackedByteArray()
	data.resize((count+overlap)*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1979+kind.hash()
	var low := 0.0
	var mid := 0.0
	for i in range(count+overlap):
		var t := float(i)/float(AIRPORT_SAMPLE_RATE)
		var white := rng.randf_range(-1.0,1.0)
		low = lerpf(low,white,.035)
		mid = lerpf(mid,white,.23)
		var value := 0.0
		match kind:
			"hall":
				value = low*.45+mid*.12
			"outside":
				value = low*.55+mid*.10
			"belt":
				# Steady mechanical hum: no repetitive impacts or rhythmic clicks.
				value = low*.24+mid*.10+sin(TAU*74.0*t)*.025
			"engine":
				value = sin(TAU*48.0*t)*.035+sin(TAU*96.0*t)*.012+low*.24
			"wheels":
				value = mid*.15+white*.025+low*.15
			"step_a","step_b":
				# A quiet shoe scuff rather than a bass-heavy thump.
				var decay := 24.0 if kind=="step_a" else 29.0
				value = (low*.22+mid*.35)*exp(-t*decay)
			"bag":
				value = (low*.75+mid*.22+sin(TAU*83.0*t)*.20)*exp(-t*13.0)
			"latch":
				value = (mid*.70+sin(TAU*190.0*t)*.22)*exp(-t*24.0)
			"chime":
				var hz := 660.0 if t<.20 else 880.0
				var local_t := fposmod(t,.20)
				value = sin(TAU*hz*local_t)*.28*sin(PI*clampf(local_t/.20,0.0,1.0))
		var envelope := 1.0 if looped else minf(1.0,minf(t/.008,(duration-t)/.025))
		data.encode_s16(i*2,roundi(clampf(value*envelope,-1.0,1.0)*32767.0))
	if looped:
		for i in range(overlap):
			var blend := smoothstep(0.0,1.0,float(i)/float(overlap))
			var tail := float(data.decode_s16((count+i)*2))
			var head := float(data.decode_s16(i*2))
			data.encode_s16(i*2,roundi(lerpf(tail,head,blend)))
		data.resize(count*2)
	var sample := AudioStreamWAV.new()
	sample.format = AudioStreamWAV.FORMAT_16_BITS
	sample.mix_rate = AIRPORT_SAMPLE_RATE
	sample.stereo = false
	sample.data = data
	if looped:
		sample.loop_mode = AudioStreamWAV.LOOP_FORWARD
		sample.loop_begin = 0
		sample.loop_end = count
	return sample

func _airport_loop(key: String,duration: float,at: Vector3,spatial: bool=false) -> void:
	var stream := _airport_sample(key,duration,true)
	if spatial:
		var sound := AudioStreamPlayer3D.new()
		add_child(sound)
		sound.position = at
		sound.stream = stream
		sound.unit_size = 3.0
		sound.max_distance = 22.0
		sound.volume_db = -65.0
		airport_audio[key] = sound
		sound.play()
	else:
		var sound := AudioStreamPlayer.new()
		add_child(sound)
		sound.stream = stream
		sound.volume_db = -65.0
		airport_audio[key] = sound
		sound.play()

func _make_airport_audio() -> void:
	_airport_loop("hall",4.0,Vector3.ZERO)
	_airport_loop("outside",4.0,Vector3.ZERO)
	_airport_loop("belt",2.0,Vector3(4,.75,-11),true)
	_airport_loop("engine",2.0,taxi.global_position,true)
	_airport_loop("wheels",2.0,Vector3.ZERO)
	for key in ["step_a","step_b","bag","latch","chime"]:
		airport_samples[key] = _airport_sample(key,.4 if key=="chime" else .30)
	for key in ["steps","effects"]:
		var sound := AudioStreamPlayer.new()
		add_child(sound)
		airport_audio[key] = sound

func _airport_effect(key: String,db: float=-12.0,channel: String="effects") -> void:
	if not airport_audio.has(channel) or not airport_samples.has(key): return
	var sound: AudioStreamPlayer = airport_audio[channel]
	sound.stream = airport_samples[key]
	sound.volume_db = db
	sound.play()

func _airport_volume(key: String,target: float,delta: float) -> void:
	var sound: Node = airport_audio[key]
	sound.set("volume_db",lerpf(float(sound.get("volume_db")),target,minf(1.0,delta*3.0)))

func _tick_airport_audio(delta: float,moving: bool=false) -> void:
	if airport_audio.is_empty(): return
	var seated := progress.stage==Progress.COMPLETE
	var inside := not seated and player.global_position.z<-2.0
	_airport_volume("hall",-28.0 if inside else -65.0,delta)
	_airport_volume("outside",-31.0 if not inside and not seated else -48.0 if seated else -65.0,delta)
	_airport_volume("belt",-28.0 if inside and progress.stage>=4 else -65.0,delta)
	_airport_volume("engine",-30.0 if not inside else -65.0,delta)
	_airport_volume("wheels",-32.0 if moving and progress.cart_attached else -65.0,delta)
	if moving and not seated:
		footstep_time -= delta
		if footstep_time<=0.0:
			footstep_variant = 1-footstep_variant
			_airport_effect("step_a" if footstep_variant==0 else "step_b",-25.0 if inside else -28.0,"steps")
			var pace := Vector2(player.velocity.x,player.velocity.z).length()
			footstep_time = clampf(1.8/maxf(pace,1.0),.31,.67)
	else:
		footstep_time = 0.0
	if announcement_caption_time>0.0:
		announcement_caption_time -= delta
		if announcement_caption_time<=0.0 or not inside:
			announcement_caption_time = 0.0
			if dialogue.text.begins_with("Altavoz:"): dialogue.text = ""
	if not inside or progress.stage<4 or progress.stage>=10: return
	announcement_time -= delta
	if announcement_time>0.0: return
	announcement_time = 43.0
	var words: String = AIRPORT_ANNOUNCEMENTS[announcement_index]
	announcement_index = (announcement_index+1)%AIRPORT_ANNOUNCEMENTS.size()
	_airport_effect("chime",-18.0)
	dialogue.text = "Altavoz: "+words
	announcement_caption_time = 7.0
	if not voice_id.is_empty():
		DisplayServer.tts_speak(words,voice_id,35,1.0,.95,0,false)

func _migration_line(key: String) -> void:
	var line: Array = MIGRATION_LINES[key]
	dialogue.text = String(line[0])+": "+String(line[1])
	var path := "res://audio/migration/"+key+".mp3"
	migration_remaining = float(line[2])+.20
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream!=null:
			migration_voice.stream = stream
			migration_voice.volume_db = 0.0 if key=="next" else -3.0
			migration_voice.play()
			migration_remaining = stream.get_length()+.20
			return
	# A missing clip must not block progression. Local speech is only a fallback.
	var fallback := protagonist_voice_id if String(line[0])=="Tú" else voice_id
	if fallback.is_empty(): fallback = voice_id
	if not fallback.is_empty():
		DisplayServer.tts_speak(String(line[1]),fallback,100 if key=="next" else 90,1.0,.96,0,true)

func _tick_migration_dialogue(delta: float) -> void:
	migration_remaining = maxf(0.0,migration_remaining-delta)
	if migration_remaining>0.0: return
	if progress.stage==1 and not migration_greeted and _near(DESK,1.75):
		migration_greeted = true
		_migration_line("greeting")
	elif progress.stage==2 and not spoken_welcome:
		match migration_part:
			0:
				migration_part = 1
				migration_remaining = 1.5
				dialogue.text = ""
			1:
				migration_part = 2
				_migration_line("question")
			2:
				migration_part = 3
				_migration_line("answer")
			3:
				migration_part = 4
				migration_remaining = .8
				dialogue.text = ""
			4:
				migration_part = 5
				_migration_line("welcome")
			5:
				spoken_welcome = true
				dialogue.text = ""
	elif progress.stage==3 and not migration_thanked:
		migration_thanked = true
		dialogue.text = ""
		_sync()
		gate_visual.show()
		var opening := create_tween()
		opening.tween_property(gate_visual,"position:y",1.6,.55)
		opening.tween_callback(gate_visual.hide)
		_notice("Pasaporte recuperado. Continúa por el paso verde.")
	elif progress.stage==1 and migration_greeted:
		dialogue.text = ""

func _trunk_point() -> Vector3:
	return taxi.to_global(Vector3(0,0,-2.9))

func _boarding_side() -> float:
	return -1.0 if taxi.to_local(player.global_position).x<0.0 else 1.0

func _door_point() -> Vector3:
	return taxi.to_global(Vector3(_boarding_side()*1.35,0,-.50))

func _can_board() -> bool:
	# Either rear door; use the car's local coordinates instead of a single point.
	var local := taxi.to_local(player.global_position)
	return absf(local.x)>=.65 and absf(local.x)<=2.65 and local.z>=-1.45 and local.z<=.50

func _nearest_belt_bag() -> int:
	var best := progress.first_bag if progress.stage<=5 else 1-progress.first_bag
	var distance := INF
	for i in range(bags.size()):
		if Progress.bag_location(progress.stage,i,progress.first_bag)!="belt": continue
		if not bags[i].visible: continue
		var at := bags[i].global_position
		var d := Vector2(at.x,at.z).distance_to(Vector2(player.global_position.x,player.global_position.z))
		if d<distance:
			distance = d
			best = i
	return best

func _target() -> Vector3:
	match progress.stage:
		0: return Progress.SPAWN
		1,2: return DESK
		3: return GATE+Vector3.FORWARD*-2.0
		4: return bags[_nearest_belt_bag()].global_position
		5: return cart.global_position if progress.cart_attached else bags[_nearest_belt_bag()].global_position
		6,8: return cart.global_position
		11,13: return cart.global_position
		7: return cart.global_position if progress.cart_attached else bags[1-progress.first_bag].global_position
		9: return EXIT if progress.cart_attached else cart.global_position
		10,12,14,15: return _trunk_point()
		16: return _door_point()
	return taxi.global_position

# The taxi's visual marker is centered above its roof. Interaction
# distances still use the trunk or passenger door, not the marker.
func _position_marker() -> void:
	if progress.stage in [10,12,14,16]:
		marker.global_position = taxi.global_position
		marker_arrow.position = Vector3(0,2.45,0)
		marker_arrow.pixel_size = .020
	else:
		marker.global_position = _target()
		marker_arrow.position = Vector3(0,1.7,0)
		marker_arrow.pixel_size = .010

func _near(at: Vector3,radius: float=1.45) -> bool:
	return Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(at.x,at.z))<=radius

func _sync() -> void:
	var step := progress.stage
	if previous!=null: previous.visible = step==0
	var cleared := step>=4 or (step==3 and migration_thanked)
	gate_body.get_child(0).set_deferred("disabled",cleared)
	gate_visual.visible = not cleared
	gate_light.material_override = _mat(Color("#38b86a") if cleared else Color("#b92b2e"))
	var exit_open := step>=9
	exit_body.get_child(0).set_deferred("disabled",exit_open)
	exit_visual.visible = not exit_open
	if step==2:
		passport.show()
		if passport.get_parent()!=officer_grip: passport.reparent(officer_grip,false)
		passport.position = Vector3(0,.009,-.018)
		passport.rotation = Vector3(0,0,-.08)
	elif step<=3:
		passport.show()
		if passport.get_parent()!=camera: passport.reparent(camera,false)
		passport.position = Vector3(.31,-.38,-.55)
		passport.rotation = Vector3(.55,0,-.18)
	else: passport.hide()
	for i in range(bags.size()):
		var bag := bags[i]
		var place := Progress.bag_location(step,i,progress.first_bag)
		var parent: Node3D = self
		if place=="hand": parent = camera
		elif place=="cart": parent = cart
		elif place=="trunk": parent = taxi
		if bag.get_parent()!=parent: bag.reparent(parent,false)
		bag.rotation = Vector3.ZERO
		bag.show()
		match place:
			"hand": bag.position = Vector3(.40,-.62,-.75)
			"cart": bag.position = Vector3(-.225 if i==0 else .225,.27,-.13)
			"trunk":
				bag.position = Vector3(-.28 if i==0 else .28,.61,-1.65)
				bag.rotation.x = PI*.5
			"belt": _move_belt_bag(bag,i)
		bag_arrows[i].visible = place=="belt" and step>=4
	lid.rotation.x = 1.15 if step>=11 and step<=15 else 0.0
	_refresh_objective()
	if marker.visible: _position_marker()
	if step==Progress.COMPLETE: prompt.text = "Fase 1 completada · Esc para abrir el menú"

func _refresh_objective() -> void:
	var step := progress.stage
	var task: String = TASKS[step]
	if step==4:
		task = "Recoge cualquiera de tus maletas. Puedes acercar el carrito o dejarlo donde está."
	elif step in [5,7] and progress.cart_attached:
		task = "Estaciona el carrito en un espacio libre y pulsa E."
	elif step in [5,7]:
		task = "Recoge una de las maletas marcadas."
	elif step in [6,8]:
		task = "Lleva la maleta al carrito y pulsa E para cargarla."
	elif step==9 and not progress.cart_attached:
		task = "Vuelve al carrito y pulsa E para llevar tus maletas a la salida."
	elif step==10:
		task = "Estaciona el carrito junto al taxi y pulsa E." if progress.cart_attached else "Espera a que el chofer abra el maletero."
	marker.visible = step not in [0,4,15,Progress.COMPLETE] and (step not in [5,7] or progress.cart_attached)
	objective.text = "CAPÍTULO 1 · DE REGRESO A CUBA\n"+task+"   (%d/%d)" % [step,Progress.COMPLETE]

func _cart_can_park() -> bool:
	var at := cart.global_position
	# Exterior parking must be clear and within reach of the assigned taxi's trunk.
	if progress.stage==10:
		if not _cart_at_taxi(): return false
	else:
		# The trolley can stay anywhere in the baggage hall, including its rack.
		if at.z>=-2.5 or at.z<=-19.5: return false
	return _cart_space_clear(at,cart.global_transform.basis)

func _cart_at_taxi() -> bool:
	var at := cart.global_position
	var trunk := _trunk_point()
	return Vector2(at.x,at.z).distance_to(Vector2(trunk.x,trunk.z))<=3.5

func _cart_space_clear(at: Vector3,orientation: Basis) -> bool:
	# Test the whole loaded platform, not only a ray through its centre.
	var shape := BoxShape3D.new()
	shape.size = Vector3(.98,.90,1.18)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(orientation,at+Vector3.UP*.52)
	query.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _push_cart() -> bool:
	var forward := -player.global_transform.basis.z
	var orientation := Basis(Vector3.UP,yaw)
	for distance in [1.45,1.25,1.05]:
		var desired := player.global_position+forward*float(distance)
		desired.y = .03
		if _cart_space_clear(desired,orientation):
			cart.global_position = desired
			cart.rotation.y = yaw
			return true
	return false

func _toggle_cart(value: bool) -> void:
	var old := progress.cart_attached
	var old_pos := progress.checkpoint
	var old_cart := progress.cart_position
	var old_angle := progress.cart_angle
	if not progress.set_cart_attached(value): return
	progress.checkpoint = player.global_position
	progress.cart_position = cart.global_position
	progress.cart_angle = cart.rotation.y
	if not progress.save_game():
		progress.cart_attached = old
		progress.checkpoint = old_pos
		progress.cart_position = old_cart
		progress.cart_angle = old_angle
		_notice("No se pudo guardar. Intenta de nuevo.")
		return
	_refresh_objective()
	_airport_effect("latch",-19.0)
	if value: _notice("Carrito recogido.")
	elif progress.stage==10: _notice("Carrito estacionado. El chofer abrirá el maletero.")
	else: _notice("Carrito estacionado. Recoge las maletas.")

func _advance(action: String,bag_id: int=-1) -> bool:
	var old := progress.stage
	var old_pos := progress.checkpoint
	var old_cart := progress.cart_position
	var old_attached := progress.cart_attached
	var old_angle := progress.cart_angle
	var old_first := progress.first_bag
	if not progress.advance(action,player.global_position,bag_id): return false
	progress.cart_position = cart.global_position
	progress.cart_angle = cart.rotation.y
	if not progress.save_game():
		progress.stage = old
		progress.checkpoint = old_pos
		progress.cart_position = old_cart
		progress.cart_attached = old_attached
		progress.cart_angle = old_angle
		progress.first_bag = old_first
		_notice("No se pudo guardar. Intenta de nuevo.")
		return false
	stage_time = 0.0
	_sync()
	if action in ["passport","return_passport","cart_first","cart_second","load_first","load_second","pickup_first","pickup_second","take_first","take_second"]:
		_airport_effect("bag",-16.0)
	elif action in ["driver_open","driver_close","board"]: _airport_effect("latch",-12.0)
	if progress.stage==Progress.COMPLETE: _seat_player()
	return true

func _interact() -> void:
	var step := progress.stage
	if menu_open or step in [0,3,15,Progress.COMPLETE]: return
	if step==10:
		if progress.cart_attached:
			if _cart_can_park(): _toggle_cart(false)
			else: _notice("Busca un espacio libre junto a la parte trasera del taxi.")
		else: _notice("Espera a que el chofer abra el maletero.")
		return
	if step==4:
		var bag_id := _nearest_belt_bag()
		if bags[bag_id].visible and _near(bags[bag_id].global_position,1.60):
			_advance("pickup_first",bag_id)
		elif _near(cart.global_position,1.60):
			_advance("cart")
		else: _notice("Acércate a una maleta marcada o al carrito.")
		return
	if step in [5,7] and progress.cart_attached:
		if _cart_can_park(): _toggle_cart(false)
		else: _notice("Busca espacio libre para soltar el carrito.")
		return
	if step in [5,7] and not progress.cart_attached:
		var candidate := _nearest_belt_bag()
		if bags[candidate].visible and _near(bags[candidate].global_position,1.60):
			_advance(Progress.expected_action(step),candidate)
		elif _near(cart.global_position,1.60):
			_toggle_cart(true)
		else: _notice("Acércate a una maleta marcada o al carrito.")
		return
	if step==9:
		if not progress.cart_attached:
			if _near(cart.global_position,1.60): _toggle_cart(true)
			else: _notice("Acércate al carrito.")
		return
	if (step==16 and not _can_board()) or (step!=16 and not _near(_target(),1.60)):
		_notice("Acércate a una de las puertas traseras." if step==16 else "Acércate al objetivo marcado.")
		return
	if step==16 and not driver_ready:
		_notice("Espera a que el chofer llegue a su puerta.")
		return
	if step==1 and (not migration_greeted or migration_remaining>0.0):
		_notice("Espera a que la agente termine de hablar.")
		return
	if step==2 and not spoken_welcome:
		_notice("La agente está revisando tu pasaporte.")
		return
	if _advance(Progress.expected_action(step)):
		if step==1:
			spoken_welcome = false
			migration_part = 0
			_migration_line("handover")
		if step==2:
			migration_thanked = false
			_migration_line("thanks")
		if step==8:
			exit_visual.show()
			var sliding := create_tween()
			sliding.tween_property(exit_visual,"position:x",5.0,.65)
			sliding.tween_callback(exit_visual.hide)

func _seat_player() -> void:
	var side := _boarding_side()
	var boarding_door := door if side<0.0 else opposite_door
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.hide()
	if is_instance_valid(driver):
		driver.reparent(taxi,false)
		driver.position = Vector3(.39,.17,.19)
		driver.rotation = Vector3.ZERO
		driver.scale = Vector3(.74,.74,.74)
		for leg in driver.limbs: leg.rotation.x = -1.45
		for knee in driver.knees: knee.rotation.x = 1.35
		for arm in driver.arms: arm.rotation.x = -1.15
	camera.reparent(taxi,false)
	# Rear passenger seat on the side used for boarding.
	camera.position = Vector3(side*.24,1.42,-.77)
	camera.rotation = Vector3(-.06,PI,0)
	cabin_look = Vector2.ZERO
	camera.fov = 82.0
	camera.make_current()
	boarding_door.rotation.y = -side*.90
	var boarding := create_tween()
	boarding.tween_property(boarding_door,"rotation:y",0.0,.45)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if mobile else Input.MOUSE_MODE_CAPTURED
	_notice("Maletas guardadas. Listo para comenzar el viaje.")

func _notice(words: String) -> void:
	message.text = words
	note_time = 3.0

func _make_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	hud.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	root.add_child(panel)
	panel.position = Vector2(20,20)
	panel.custom_minimum_size.x = 380
	var col := VBoxContainer.new()
	panel.add_child(col)
	objective = Label.new()
	objective.add_theme_font_size_override("font_size",19)
	col.add_child(objective)
	var cash := Label.new()
	cash.text = "0 CUP  ·  Aeropuerto José Martí"
	col.add_child(cash)
	prompt = Label.new()
	root.add_child(prompt)
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	prompt.offset_left = -320
	prompt.offset_right = 320
	prompt.offset_top = -68
	prompt.offset_bottom = -30
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size",20)
	prompt.add_theme_color_override("font_shadow_color",Color.BLACK)
	prompt.add_theme_constant_override("shadow_offset_y",2)
	message = Label.new()
	root.add_child(message)
	message.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	message.offset_left = -320
	message.offset_right = 320
	message.offset_top = 120
	message.offset_bottom = 150
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_color_override("font_shadow_color",Color.BLACK)
	message.add_theme_constant_override("shadow_offset_y",2)
	dialogue = Label.new()
	root.add_child(dialogue)
	dialogue.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue.offset_left = -360
	dialogue.offset_right = 360
	dialogue.offset_top = -140
	dialogue.offset_bottom = -98
	dialogue.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dialogue.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue.add_theme_font_size_override("font_size",21)
	dialogue.add_theme_color_override("font_shadow_color",Color.BLACK)
	dialogue.add_theme_constant_override("shadow_offset_y",2)
	menu = PanelContainer.new()
	root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	menu.offset_left = -180
	menu.offset_right = 180
	menu.offset_top = -120
	menu.offset_bottom = 120
	var actions := VBoxContainer.new()
	menu.add_child(actions)
	var title := Label.new()
	title.text = "MYCITY · VOLVER A EMPEZAR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	actions.add_child(title)
	_button(actions,"Continuar",_toggle_menu)
	_button(actions,"Reiniciar misión del aeropuerto",_restart)
	_button(actions,"Ciudad anterior (modo clásico)",_legacy)
	menu.hide()
	if mobile:
		var controls := HBoxContainer.new()
		root.add_child(controls)
		controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		controls.offset_top = -65
		for item in [["←","left"],["↑","forward"],["↓","back"],["→","right"],["Correr","run"]]:
			var button := Button.new()
			button.text = item[0]
			button.custom_minimum_size = Vector2(52,52)
			var key := String(item[1])
			button.button_down.connect(func(): touch_keys[key]=true)
			button.button_up.connect(func(): touch_keys[key]=false)
			controls.add_child(button)
		_button(controls,"Acción",_interact)
		_button(controls,"Menú",_toggle_menu)

func _button(parent: Control,words: String,action: Callable) -> void:
	var b := Button.new()
	b.text = words
	b.custom_minimum_size.y = 44
	parent.add_child(b)
	b.pressed.connect(action)

func _toggle_menu() -> void:
	menu_open = not menu_open
	menu.visible = menu_open
	for sound in airport_audio.values(): sound.stream_paused = menu_open
	if migration_voice!=null: migration_voice.stream_paused = menu_open
	if menu_open and not voice_id.is_empty(): DisplayServer.tts_stop()
	touch_keys.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open or mobile else Input.MOUSE_MODE_CAPTURED

func _restart() -> void:
	# Only the new airport checkpoint is reset. Legacy saves remain untouched.
	var fresh := Progress.new()
	if fresh.save_game(): get_tree().reload_current_scene()
	else: _notice("No se pudo reiniciar la misión.")

func _legacy() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

func _exit_tree() -> void:
	if not voice_id.is_empty(): DisplayServer.tts_stop()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			_toggle_menu()
			get_viewport().set_input_as_handled()
		elif event.keycode==KEY_E:
			_interact()
			get_viewport().set_input_as_handled()
	if menu_open: return
	var look := Vector2.ZERO
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED: look = event.relative
	elif event is InputEventScreenDrag and mobile: look = event.relative
	if look!=Vector2.ZERO:
		if progress.stage==Progress.COMPLETE:
			cabin_look.x = clampf(cabin_look.x-look.x*.003,-1.15,1.15)
			cabin_look.y = clampf(cabin_look.y-look.y*.003,-.50,.38)
			camera.rotation = Vector3(cabin_look.y-.06,PI+cabin_look.x,0)
			return
		yaw -= look.x*.003
		pitch = clampf(pitch-look.y*.003,-1.25,1.25)
		player.rotation.y = yaw
		camera.rotation.x = pitch

func _pressed(key: Key,touch: String) -> bool:
	return Input.is_physical_key_pressed(key) or bool(touch_keys.get(touch,false))

func _physics_process(delta: float) -> void:
	if player==null or objective==null: return
	if note_time>0:
		note_time -= delta
		if note_time<=0: message.text = ""
	if menu_open: return
	_tick_ambient_people(delta)
	if progress.stage==Progress.COMPLETE:
		_tick_airport_audio(delta)
		return
	_update_belt(delta)
	stage_time += delta
	var axis := Vector2(float(_pressed(KEY_D,"right"))-float(_pressed(KEY_A,"left")),float(_pressed(KEY_S,"back"))-float(_pressed(KEY_W,"forward"))).limit_length(1.0)
	var direction := player.transform.basis*Vector3(axis.x,0,axis.y)
	var running := _pressed(KEY_SHIFT,"run")
	var carrying := progress.stage in [6,8,12,14]
	var speed := (3.3 if running else 2.8) if progress.cart_attached else ((4.2 if running else 3.1) if carrying else (7.2 if running else 3.8))
	player.velocity.x = direction.x*speed
	player.velocity.z = direction.z*speed
	player.velocity.y -= 9.8*delta
	var before_move := player.global_position
	player.move_and_slide()
	if player.position.y<-.8:
		player.position = progress.checkpoint
		player.velocity = Vector3.ZERO
	if progress.cart_attached and not _push_cart():
		# Prevent the trolley from sliding into the carousel or other solids.
		player.global_position.x = before_move.x
		player.global_position.z = before_move.z
		player.velocity.x = 0.0
		player.velocity.z = 0.0
	var actual_distance := Vector2(player.global_position.x-before_move.x,player.global_position.z-before_move.z).length()
	_tick_airport_audio(delta,actual_distance>.002 and player.is_on_floor())
	_tick_migration_dialogue(delta)
	# Keep the seated pose. Raise the document above the counter to inspect it,
	# then hold it forward until the player collects it. The prop follows the palm.
	var reach := -1.05
	if progress.stage==2:
		reach = -1.95 if spoken_welcome else -2.16+sin(stage_time*2.2)*.035
	officer.arms[1].rotation.x = lerpf(officer.arms[1].rotation.x,reach,minf(1.0,delta*7.0))
	match progress.stage:
		0:
			if stage_time>1.5 and previous.visible:
				if previous.walk_to(Vector3(5.2,.03,-24),delta,1.8) or stage_time>7.0:
					if _advance("next"): _migration_line("next")
		3:
			if migration_thanked and player.global_position.z>-19.25 and absf(player.global_position.x)<2.3: _advance("pass_gate")
		9:
			if progress.cart_attached and player.global_position.z>.25 and absf(player.global_position.x)<4.0: _advance("exit")
		10:
			if not progress.cart_attached and _cart_at_taxi() and not driver_opening:
				driver_opening = true
			if driver_opening:
				var route: Array[Vector3] = [Vector3(1.65,0,-2.90),Vector3(.85,0,-2.90)]
				driver_route_index = _driver_walk_route(route,driver_route_index,delta)
				if driver_route_index>=route.size() and not progress.cart_attached and _cart_at_taxi():
					var old := lid.rotation.x
					if _advance("driver_open"):
						lid.rotation.x = old
						lid_tween = create_tween()
						lid_tween.tween_property(lid,"rotation:x",1.15,.55)
						driver.arms[1].rotation.x = -1.0
						_notice("El chofer abrió el maletero.")
		15:
			driver.arms[1].rotation.x = -1.1
			if stage_time>=.65:
				var old := lid.rotation.x
				if _advance("driver_close"):
					lid.rotation.x = old
					lid_tween = create_tween()
					lid_tween.tween_property(lid,"rotation:x",0.0,.55)
					_notice("El chofer cerró el maletero.")
					driver.arms[1].rotation.x = 0.0
		16:
			if not driver_ready:
				var return_route: Array[Vector3] = [Vector3(1.65,0,-2.90),Vector3(1.65,0,.30)]
				driver_return_index = _driver_walk_route(return_route,driver_return_index,delta)
				driver_ready = driver_return_index>=return_route.size()
	if progress.stage<10 or (progress.stage==10 and not driver_opening) or progress.stage in [11,12,13,14] or (progress.stage==16 and driver_ready):
		_idle_person(driver,delta,4.0)
	if progress.stage==Progress.COMPLETE: return
	if marker.visible: _position_marker()
	var near := _can_board() if progress.stage==16 else _near(_target(),1.60)
	var actions := ["","Entregar pasaporte","Recoger pasaporte","","Recoger maleta","Recoger primera maleta","Cargar maleta en carrito","Recoger segunda maleta","Cargar maleta en carrito","","","Tomar primera maleta","Guardar en maletero","Tomar segunda maleta","Guardar en maletero","","Subir al taxi"]
	var action: String = actions[progress.stage]
	if progress.stage==4:
		if near and bags[_nearest_belt_bag()].visible: prompt.text = "[E] Recoger maleta"
		elif _near(cart.global_position,1.60): prompt.text = "[E] Acercar carrito (opcional)"
		else: prompt.text = "Recoge una maleta y llévala al carrito."
		return
	if progress.stage in [5,7] and not progress.cart_attached:
		if near and bags[_nearest_belt_bag()].visible: prompt.text = "[E] Recoger maleta"
		elif _near(cart.global_position,1.60): prompt.text = "[E] Mover carrito"
		else: prompt.text = "Recoge una de tus maletas marcadas."
		return
	if progress.stage in [5,7] and progress.cart_attached:
		prompt.text = "[E] Soltar carrito" if _cart_can_park() else "Lleva el carrito a un espacio libre."
		return
	if progress.stage==9:
		if not progress.cart_attached: action = "Tomar carrito"
		else:
			prompt.text = "Empuja el carrito hacia la SALIDA · Sigue la flecha"
			return
	if progress.stage==10:
		if progress.cart_attached:
			prompt.text = "[E] Soltar carrito junto al taxi" if _cart_can_park() else "Lleva el carrito a un espacio libre junto al maletero."
		else:
			prompt.text = "Espera a que el chofer abra el maletero."
		return
	if progress.stage==16 and not driver_ready:
		prompt.text = "Espera al chofer."
		return
	if progress.stage==1 and (not migration_greeted or migration_remaining>0.0):
		prompt.text = "Acércate a la agente." if not near else "Escucha a la agente."
		return
	if progress.stage==2 and not spoken_welcome:
		prompt.text = "Espera a que termine la revisión."
		return
	prompt.text = ("[E] "+action) if near and not action.is_empty() else "WASD · Caminar  /  Shift · Correr"

