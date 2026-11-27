extends Node3D
# Airport arrivals inspired by the supplied exterior/interior/baggage references.
# Geometry is procedural, not a measured terminal survey; the city is not loaded.
const Progress = preload("res://airport_progress.gd")
const Person = preload("res://street_person.gd")
const Lights = preload("res://vehicle_lights.gd")
const DESK := Vector3(-1.7,0,-24)
const GATE := Vector3(0,0,-20)
const CART_START := Vector3(-5,.03,-16)
const EXIT := Vector3(0,0,1)
const BELT := Vector3(4,.72,-11)
const TASKS := ["Espera tu turno en migración.","Acércate a la agente y entrega el pasaporte.","Espera la revisión y recoge el pasaporte.","Cruza el pasador verde.","Recoge un carrito de equipaje.","Recoge tu primera maleta de la cinta.","Coloca la primera maleta en el carrito.","Recoge tu segunda maleta de la cinta.","Coloca la segunda maleta en el carrito.","Sal del aeropuerto con tus maletas.","Acércate al taxi con el carrito.","Recoge la primera maleta del carrito.","Coloca la primera maleta en el maletero.","Recoge la segunda maleta del carrito.","Coloca la segunda maleta en el maletero.","Espera a que el chofer cierre el maletero.","Sube al taxi por la puerta del pasajero.","Fase 1 completada. Viaje pendiente."]
var progress := Progress.new()
var mats: Dictionary = {}
var unit_box := BoxMesh.new()
var player: CharacterBody3D
var camera: Camera3D
var taxi: Node3D
var lid: Node3D
var door: Node3D
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
var lid_tween: Tween
var officer: Person
var previous: Person
var passport: Node3D
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
var driver_clock := 0.0
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
	_box(self,Vector3(-3.0,1.05,-23),Vector3(2.35,2.1,1.5),Color("#d5d0c3"),true)
	_box(self,Vector3(-3.0,2.35,-23),Vector3(2.45,.48,1.6),red)
	_label3(self,"MIGRACIÓN  •  01",Vector3(-3,2.37,-23.83),.006).rotation.y = PI
	_box(self,Vector3(-1.73,.99,-23.8),Vector3(.48,.10,.78),metal)
	_box(self,Vector3(-3.0,1.30,-22.15),Vector3(.50,.35,.12),glass)
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
	_box(root,Vector3(0,.78,-.03),Vector3(1.54,.45,1.84),paint,interactive)
	_box(root,Vector3(0,1.51,-.10),Vector3(1.57,.12,1.86),paint)
	_box(root,Vector3(0,1.20,.84),Vector3(1.45,.48,.055),glass)
	_box(root,Vector3(0,1.20,-1.03),Vector3(1.45,.48,.055),glass)
	_box(root,Vector3(0,.55,-1.66),Vector3(1.72,.14,1.26),dark)
	_box(root,Vector3(0,.75,-2.26),Vector3(1.74,.40,.10),paint,interactive)
	for side in [-1.0,1.0]:
		var x := float(side)
		_box(root,Vector3(x*.83,.77,-1.65),Vector3(.12,.44,1.16),paint,interactive)
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
		door = Node3D.new()
		root.add_child(door)
		door.position = Vector3(.82,.85,.76)
		_box(door,Vector3(0,0,-.50),Vector3(.09,.47,1.0),paint)
		_box(door,Vector3(0,.35,-.50),Vector3(.055,.39,1.0),glass)
		_box(door,Vector3(.06,.13,-.79),Vector3(.025,.04,.15),chrome)
	else:
		_box(root,Vector3(0,1.0,-1.65),Vector3(1.72,.09,1.2),paint)

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
			walkers.append({"node":person,"origin":person.position,"phase":float(i)})
	# The assigned driver waits beside the front of the taxi.
	driver = Person.new()
	add_child(driver)
	driver.setup(414)
	driver.position = Vector3(10.1,.03,11.0)
	driver.rotation.y = PI
	if progress.stage>=11 and progress.stage<Progress.COMPLETE:
		driver.position = taxi.to_global(Vector3(-1.35,0,-2.25))

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
	officer.position = Vector3(-1.65,.03,-22.9)
	officer.rotation.y = PI
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
	_label3(passport,"PASAPORTE",Vector3(0,.021,0),.0012,Color("#d4bd70")).rotation.x = -PI*.5
	cart = Node3D.new()
	add_child(cart)
	cart.position = progress.cart_position
	var steel := Color("#a9afb1")
	_box(cart,Vector3(0,.24,0),Vector3(.68,.075,1.06),steel)
	for x in [-.30,.30]:
		_box(cart,Vector3(float(x),.56,.44),Vector3(.045,.68,.045),steel)
		_box(cart,Vector3(float(x),.32,0),Vector3(.045,.12,1.04),steel)
		for z in [-.44,.44]: _box(cart,Vector3(float(x),.09,float(z)),Vector3(.09,.16,.14),Color("#343a3c"))
	_box(cart,Vector3(0,.90,.44),Vector3(.72,.07,.07),Color("#253c57"))
	_box(cart,Vector3(0,.50,-.48),Vector3(.65,.34,.045),steel)
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
	_label3(marker,"▼",Vector3(0,1.7,0),.010,Color("#ffd976")).billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _belt_point(slot: int) -> Vector3:
	var a := belt_time*.17+float(slot)*TAU/7.0
	return BELT+Vector3(cos(a)*4.35,0,sin(a)*1.65)

func _update_belt(delta: float) -> void:
	belt_time = fposmod(belt_time+delta,TAU/.17)
	for i in range(other_bags.size()):
		other_bags[i].position = _belt_point(i+2)
	for i in range(bags.size()):
		if Progress.bag_location(progress.stage,i)=="belt":
			bags[i].position = _belt_point(i)

func _say(words: String) -> void:
	_notice("Agente: "+words)
	if dialogue!=null:
		dialogue.text = "Agente: "+words
	if not voice_id.is_empty(): DisplayServer.tts_speak(words,voice_id,90,1.0,.92,0,true)

func _trunk_point() -> Vector3:
	return taxi.to_global(Vector3(0,0,-2.9))

func _door_point() -> Vector3:
	return taxi.to_global(Vector3(1.35,0,.23))

func _target() -> Vector3:
	match progress.stage:
		0: return Progress.SPAWN
		1,2: return DESK
		3: return GATE+Vector3.FORWARD*-2.0
		4: return cart.global_position
		5: return bags[0].global_position
		6,8,11,13: return cart.global_position
		7: return bags[1].global_position
		9: return EXIT
		10,12,14,15: return _trunk_point()
		16: return _door_point()
	return taxi.global_position

func _near(at: Vector3,radius: float=1.45) -> bool:
	return Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(at.x,at.z))<=radius

func _sync() -> void:
	var step := progress.stage
	if previous!=null: previous.visible = step==0
	var cleared := step>=3
	gate_body.get_child(0).set_deferred("disabled",cleared)
	gate_visual.visible = not cleared
	gate_light.material_override = _mat(Color("#38b86a") if cleared else Color("#b92b2e"))
	exit_body.get_child(0).set_deferred("disabled",step>=9)
	exit_visual.visible = step<9
	if step==2:
		passport.show()
		if passport.get_parent()!=officer: passport.reparent(officer,false)
		passport.position = Vector3(.15,1.02,.39)
		passport.rotation = Vector3.ZERO
	elif step<=3:
		passport.show()
		if passport.get_parent()!=camera: passport.reparent(camera,false)
		passport.position = Vector3(.31,-.38,-.55)
		passport.rotation = Vector3(.55,0,-.18)
	else: passport.hide()
	for i in range(bags.size()):
		var bag := bags[i]
		var place := Progress.bag_location(step,i)
		var parent: Node3D = self
		if place=="hand": parent = camera
		elif place=="cart": parent = cart
		elif place=="trunk": parent = taxi
		if bag.get_parent()!=parent: bag.reparent(parent,false)
		bag.rotation = Vector3.ZERO
		match place:
			"hand": bag.position = Vector3(.40,-.62,-.75)
			"cart": bag.position = Vector3(-.15 if i==0 else .15,.29,-.20 if i==0 else .25)
			"trunk":
				bag.position = Vector3(-.28 if i==0 else .28,.61,-1.65)
				bag.rotation.x = PI*.5
			"belt": bag.position = _belt_point(i)
		bag_arrows[i].visible = place=="belt" and step>=4
	lid.rotation.x = 1.15 if step>=11 and step<=15 else 0.0
	marker.visible = step not in [0,5,7,15,Progress.COMPLETE]
	if marker.visible: marker.global_position = _target()
	objective.text = "CAPÍTULO 1 · DE REGRESO A CUBA\n"+TASKS[step]+"   (%d/%d)" % [step,Progress.COMPLETE]
	if step==Progress.COMPLETE: prompt.text = "Fase 1 completada · Esc para abrir el menú"

func _advance(action: String) -> bool:
	var old := progress.stage
	var old_pos := progress.checkpoint
	var old_cart := progress.cart_position
	if not progress.advance(action,player.global_position): return false
	progress.cart_position = cart.global_position
	if not progress.save_game():
		progress.stage = old
		progress.checkpoint = old_pos
		progress.cart_position = old_cart
		_notice("No se pudo guardar. Intenta de nuevo.")
		return false
	stage_time = 0.0
	_sync()
	if progress.stage==Progress.COMPLETE: _seat_player()
	return true

func _interact() -> void:
	var step := progress.stage
	if menu_open or step in [0,3,9,10,15,Progress.COMPLETE]: return
	if not _near(_target(),1.60):
		_notice("Acércate al objetivo marcado.")
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
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.hide()
	if is_instance_valid(driver):
		driver.reparent(taxi,false)
		driver.position = Vector3(-.34,.32,.30)
		driver.rotation = Vector3.ZERO
		driver.scale = Vector3(.66,.66,.66)
		for leg in driver.limbs: leg.rotation.x = -1.0
		for knee in driver.knees: knee.rotation.x = 1.0
		for arm in driver.arms: arm.rotation.x = -1.05
	camera.reparent(taxi,false)
	camera.position = Vector3(.36,1.31,.03)
	camera.rotation = Vector3(0,PI,0)
	camera.make_current()
	door.rotation.y = -.70
	var boarding := create_tween()
	boarding.tween_property(door,"rotation:y",0.0,.45)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
		for item in [["←","left"],["↑","forward"],["↓","back"],["→","right"]]:
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open or mobile or progress.stage==Progress.COMPLETE else Input.MOUSE_MODE_CAPTURED

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
	if menu_open or progress.stage==Progress.COMPLETE: return
	var look := Vector2.ZERO
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED: look = event.relative
	elif event is InputEventScreenDrag and mobile: look = event.relative
	if look!=Vector2.ZERO:
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
	for item in walkers:
		var person: Person = item.node
		item.phase = float(item.phase)+delta*.30
		var origin: Vector3 = item.origin
		person.position.x = origin.x+sin(float(item.phase))*2.0
		person.rotation.y = PI*.5 if cos(float(item.phase))>0 else -PI*.5
		person.animate(delta,true,1.2)
	if progress.stage==Progress.COMPLETE: return
	_update_belt(delta)
	stage_time += delta
	var axis := Vector2(float(_pressed(KEY_D,"right"))-float(_pressed(KEY_A,"left")),float(_pressed(KEY_S,"back"))-float(_pressed(KEY_W,"forward"))).limit_length(1.0)
	var direction := player.transform.basis*Vector3(axis.x,0,axis.y)
	var speed := 2.8 if progress.stage>=5 and progress.stage<=10 else 3.8
	player.velocity.x = direction.x*speed
	player.velocity.z = direction.z*speed
	player.velocity.y -= 9.8*delta
	player.move_and_slide()
	if player.position.y<-.8:
		player.position = progress.checkpoint
		player.velocity = Vector3.ZERO
	if progress.stage>=5 and progress.stage<=10:
		# Cart is pushed in front of the camera; the ray keeps it on the
		# player's side of walls and locked doors when turning near a corner.
		var start := player.global_position
		start.y = .45
		var forward := -player.global_transform.basis.z
		var desired := start+forward*1.25
		var query := PhysicsRayQueryParameters3D.create(start,desired)
		query.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty(): desired = start+forward*maxf(.35,start.distance_to(hit.position)-.35)
		cart.global_position = Vector3(desired.x,.03,desired.z)
		cart.rotation.y = yaw
	officer.animate(delta,false)
	if progress.stage==2:
		officer.arms[1].rotation.x = lerpf(officer.arms[1].rotation.x,-1.0,minf(1.0,delta*7.0))
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
			if player.global_position.z>.25 and absf(player.global_position.x)<4.0: _advance("exit")
		10:
			if _near(_trunk_point(),2.0) and not driver_opening:
				driver_opening = true
				driver_clock = 0.0
			if driver_opening:
				driver_clock += delta
				var at := taxi.to_global(Vector3(-1.35,0,-2.25))
				if driver.walk_to(at,delta,2.0) or driver_clock>8.0:
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
	if progress.stage==Progress.COMPLETE: return
	if marker.visible: marker.global_position = _target()
	var near := _near(_target(),1.60)
	var actions := ["","Entregar pasaporte","Recoger pasaporte","","Tomar carrito","Recoger primera maleta","Poner en carrito","Recoger segunda maleta","Poner en carrito","","","Tomar primera maleta","Guardar en maletero","Tomar segunda maleta","Guardar en maletero","","Subir al taxi"]
	var action: String = actions[progress.stage]
	if progress.stage==2 and not spoken_welcome: action = ""
	prompt.text = ("[E] "+action) if near and not action.is_empty() else "WASD · Caminar / Sigue el objetivo"

