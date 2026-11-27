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
const TASKS := ["Espera tu turno en migración.","Acércate a la agente y entrega el pasaporte.","Espera la revisión y recoge el pasaporte.","Cruza el pasador verde.","Recoge un carrito de equipaje.","Recoge tu primera maleta de la cinta.","Coloca la primera maleta en el carrito.","Recoge tu segunda maleta de la cinta.","Coloca la segunda maleta en el carrito.","Sal del aeropuerto con tus maletas.","Acércate al taxi con el carrito.","Recoge la primera maleta del carrito.","Coloca la primera maleta en el maletero.","Recoge la segunda maleta del carrito.","Coloca la segunda maleta en el maletero.","Espera a que el chofer cierre el maletero.","Sube al taxi por cualquiera de las puertas traseras.","Fase 1 completada. Viaje pendiente."]
var progress := Progress.new()
var mats: Dictionary = {}
var unit_box := BoxMesh.new()
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
var voice_id := ""
var bag_arrows: Array[Label3D] = []
var other_bags: Array[Node3D] = []
var driver_opening := false
var driver_route_index := 0
var driver_return_index := 0
var driver_ready := false
var cabin_look := Vector2.ZERO
var waiting_people: Array[Person] = []
var ambient_clock := 0.0
var dialogue: Label

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
	_make_hud()
	var voices := DisplayServer.tts_get_voices_for_language("es")
	if not voices.is_empty(): voice_id = voices[0]
	_sync()
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
	parent.add_child(label)
	label.position = p
	return label

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
	env.ambient_light_color = Color("#e1e1d8")
	env.ambient_light_energy = .65
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-30,0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	add_child(sun)

func _make_terminal() -> void:
	var concrete := Color("#c8c5b8")
	var tile := Color("#e5dfcd")
	var cream := Color("#eee6d3")
	var red := Color("#b92b2e")
	var blue := Color("#12548c")
	var ochre := Color("#c69a49")
	var glass := Color("#445b65")
	var metal := Color("#a9aaa5")
	_box(self,Vector3(0,-.18,-4),Vector3(84,.36,64),concrete,true)
	_box(self,Vector3(0,.012,18),Vector3(84,.022,12),Color("#555956"))
	_box(self,Vector3(0,.015,5),Vector3(84,.03,13),concrete,true)
	# The reference façade: ochre colonnade, deep blue fascia, long glass bays.
	for side in [-1.0,1.0]:
		var x := float(side)
		_box(self,Vector3(x*19,2.2,-2),Vector3(33,4.4,.30),cream,true)
		for i in range(7):
			_box(self,Vector3(x*(4.8+float(i)*4.3),1.7,-1.80),Vector3(3.8,3.1,.12),glass)
		_box(self,Vector3(x*14.8,2,-17),Vector3(.34,4,30),cream,true)
	_box(self,Vector3(0,2,-32),Vector3(30,4,.35),cream,true)
	_box(self,Vector3(0,4.12,-17),Vector3(30,.24,30),cream,true)
	_box(self,Vector3(0,3.95,1.1),Vector3(72,.52,6.6),ochre,true)
	_box(self,Vector3(0,4.35,1.1),Vector3(72,.32,6.6),blue)
	_box(self,Vector3(0,5.0,.8),Vector3(24,1.0,1.0),blue)
	_label3(self,"AEROPUERTO INTERNACIONAL\nJOSÉ MARTÍ – LA HABANA",Vector3(0,5.03,1.33),.010)
	for i in range(10):
		var x := -32.4+float(i)*7.2
		if absf(x)>2.8: _box(self,Vector3(x,1.85,3.7),Vector3(.43,3.7,.43),ochre,true)
	_label3(self,"SALIDA  /  ARRIVALS",Vector3(0,3.82,4.45),.006)
	# Continuous tiled interior with thin joints, red ceiling borders and lights.
	_box(self,Vector3(0,.016,-17),Vector3(29.4,.03,29.6),tile)
	for x in range(-14,15):
		_box(self,Vector3(float(x),.035,-17),Vector3(.012,.004,29.6),Color("#b5b1a4"))
	for z in range(-31,-1):
		_box(self,Vector3(0,.035,float(z)),Vector3(29.4,.004,.012),Color("#b5b1a4"))
	for z in [-29.0,-24.0,-18.0,-12.0,-6.0]:
		_box(self,Vector3(0,3.94,float(z)),Vector3(29.3,.07,.40),red)
		for x in [-10.0,-5.0,0.0,5.0,10.0]:
			_box(self,Vector3(float(x),3.91,float(z)+1.0),Vector3(.9,.035,.55),Color("#fff5d7"))
	# Migration room and physically gated passage. Only the centre opening leads onward.
	for side in [-1.0,1.0]:
		_box(self,Vector3(float(side)*8.3,2,-20),Vector3(12.8,4,.32),cream,true)
		_box(self,Vector3(float(side)*8.3,3.25,-20.19),Vector3(12.8,1.0,.08),red)
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
		transparent.albedo_color = Color(.56,.72,.76,.23)
		transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pane.material_override = transparent
	_label3(self,"MIGRACIÓN  •  01",booth+Vector3(0,2.29,-1.07),.0055).rotation.y = PI
	# Desk equipment and chair, leaving the officer's head visible in the window.
	_box(self,booth+Vector3(-.65,1.22,-.66),Vector3(.42,.36,.09),Color("#333b40"))
	_box(self,booth+Vector3(-.65,1.08,-.60),Vector3(.40,.035,.22),Color("#363b3f"))
	_box(self,booth+Vector3(0,.48,.20),Vector3(.48,.10,.48),Color("#343a3e"))
	_box(self,booth+Vector3(0,.81,.47),Vector3(.48,.65,.09),Color("#343a3e"))
	_box(self,booth+Vector3(0,.24,.20),Vector3(.09,.45,.09),metal)
	_label3(self,"CONTROL DE PASAPORTES",Vector3(0,3.4,-20.22),.008).rotation.y = PI
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
	_label3(self,"LLEGADAS  /  ARRIVALS\nMIAMI      LANDED\nMADRID     LANDED\nPANAMÁ     EXPECTED",Vector3(8.5,2.66,-20.28),.0045,Color("#e4d381")).rotation.y = PI
	for z in [-17.0,-14.0,-8.0]:
		_box(self,Vector3(-13.5,.46,float(z)),Vector3(1.0,.13,2.2),blue,true)
		_box(self,Vector3(-13.95,.85,float(z)),Vector3(.13,.75,2.2),blue)
	# Baggage hall has an open aisle west of the carousel.
	_box(self,Vector3(4,.30,-11),Vector3(10.0,.60,4.0),metal,true)
	_box(self,Vector3(4,.65,-11),Vector3(9.85,.12,3.85),Color("#252b2d"))
	_box(self,Vector3(4,.76,-11),Vector3(5.4,.18,1.3),metal)
	_box(self,Vector3(4,1.4,-11),Vector3(.13,1.3,.13),metal)
	_box(self,Vector3(4,2.07,-11),Vector3(1.8,.65,.14),Color("#168bbb"))
	_label3(self,"2  EQUIPAJE",Vector3(4,2.08,-11.09),.006).rotation.y = PI
	_label3(self,"2  EQUIPAJE",Vector3(4,2.08,-10.91),.006)
	_label3(self,"RECOGIDA DE EQUIPAJE",Vector3(-5,3.40,-19.80),.008)
	_box(self,Vector3(0,3.25,-2.25),Vector3(5,.5,.15),red)
	_label3(self,"SALIDA",Vector3(0,3.25,-2.36),.008).rotation.y = PI
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
		_label3(self,"TAXIS",Vector3(x,2.2,9.48),.005,Color("#233c4a"))
	for x in [-42.0,42.0]:
		_box(self,Vector3(x,1,8),Vector3(.3,2,36),concrete,true)
	_box(self,Vector3(0,1,26),Vector3(84,2,.3),concrete,true)
	for x in [-28.0,-15.0,25.0,35.0]:
		_box(self,Vector3(x,.24,23.4),Vector3(2.5,.48,1.5),Color("#a5a89b"))
		_box(self,Vector3(x,1.6,23.4),Vector3(.21,2.5,.21),Color("#7e6c50"))
		for leaf in [-1.0,1.0]:
			var v := _box(self,Vector3(x+float(leaf)*.70,2.96,23.4),Vector3(1.8,.16,.62),Color("#668453"))
			v.rotation.z = float(leaf)*-.25

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
		# Parked props are outside the mission's walkable interaction area.
		_box(other,Vector3(0,.75,0),Vector3(1.75,1.5,4.5),Color("#777777"),true).hide()

func _make_people() -> void:
	for i in range(8):
		var person := Person.new()
		add_child(person)
		person.setup(330+i*17,i==0 or i==5,true)
		person.position = Vector3(-28+float(i)*7.7,.03,6.4 if i%2==0 else 8.4)
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

func _suitcase(color: Color) -> Node3D:
	var bag := Node3D.new()
	add_child(bag)
	_box(bag,Vector3(0,.23,0),Vector3(.40,.44,.24),color)
	_box(bag,Vector3(0,.46,0),Vector3(.15,.045,.055),Color("#303738"))
	for x in [-.15,.15]:
		_box(bag,Vector3(float(x),.025,0),Vector3(.06,.05,.065),Color("#25292b"))
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
	_label3(self,"CARROS DE EQUIPAJE",Vector3(-5,2.4,-17),.006).rotation.y = PI

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

func _belt_point(slot: int) -> Vector3:
	var a := belt_time*.17+float(slot)*TAU/7.0
	return BELT+Vector3(cos(a)*4.35,0,sin(a)*1.65)

func _update_belt(delta: float) -> void:
	belt_time = fposmod(belt_time+delta,TAU/.17)
	for i in range(other_bags.size()):
		other_bags[i].position = _belt_point(i+2)
	for i in range(bags.size()):
		if Progress.bag_location(progress.stage,i,progress.first_bag)=="belt":
			bags[i].position = _belt_point(i)

func _say(words: String) -> void:
	_notice("Agente: "+words)
	if dialogue!=null:
		dialogue.text = "Agente: "+words
	if not voice_id.is_empty(): DisplayServer.tts_speak(words,voice_id,90,1.0,.92,0,true)

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
	var best := 0
	var distance := INF
	for i in range(bags.size()):
		if Progress.bag_location(progress.stage,i,progress.first_bag)!="belt": continue
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
	var cleared := step>=3
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
		match place:
			"hand": bag.position = Vector3(.40,-.62,-.75)
			"cart": bag.position = Vector3(-.225 if i==0 else .225,.27,-.13)
			"trunk":
				bag.position = Vector3(-.28 if i==0 else .28,.61,-1.65)
				bag.rotation.x = PI*.5
			"belt": bag.position = _belt_point(i)
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
		if _near(bags[bag_id].global_position,1.60):
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
		if _near(bags[candidate].global_position,1.60):
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
	if step==2 and not spoken_welcome:
		_notice("La agente está revisando tu pasaporte.")
		return
	if _advance(Progress.expected_action(step)):
		if step==1:
			dialogue.text = ""
			spoken_welcome = false
			_notice("La agente revisa tu pasaporte.")
		if step==2:
			dialogue.text = ""
			gate_visual.show()
			var opening := create_tween()
			opening.tween_property(gate_visual,"position:y",1.6,.55)
			opening.tween_callback(gate_visual.hide)
			_notice("Pasaporte recuperado. Continúa por el paso verde.")
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
	dialogue.add_theme_font_size_override("font_size",23)
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
	touch_keys.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open or mobile else Input.MOUSE_MODE_CAPTURED

func _restart() -> void:
	# Only the new airport checkpoint is reset. Legacy saves remain untouched.
	var fresh := Progress.new()
	if fresh.save_game(): get_tree().reload_current_scene()
	else: _notice("No se pudo reiniciar la misión.")

func _legacy() -> void:
	get_tree().change_scene_to_file("res://main.tscn")

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
	if progress.stage==Progress.COMPLETE: return
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
					if _advance("next"): _say("Siguiente.")
		2:
			if stage_time>=1.8 and not spoken_welcome:
				spoken_welcome = true
				_say("Bienvenido a la patria.")
		3:
			if player.global_position.z>-19.25 and absf(player.global_position.x)<2.3: _advance("pass_gate")
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
		if near: prompt.text = "[E] Recoger maleta"
		elif _near(cart.global_position,1.60): prompt.text = "[E] Acercar carrito (opcional)"
		else: prompt.text = "Recoge una maleta y llévala al carrito."
		return
	if progress.stage in [5,7] and not progress.cart_attached:
		if near: prompt.text = "[E] Recoger maleta"
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
	if progress.stage==2 and not spoken_welcome: action = ""
	prompt.text = ("[E] "+action) if near and not action.is_empty() else "WASD · Caminar  /  Shift · Correr"

