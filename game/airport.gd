extends Node3D
# Independent playable airport blockout. Dimensions/materials provisional until
# the player's photographs are approved. No city world or business is loaded.
const Progress = preload("res://airport_progress.gd")
const Person = preload("res://street_person.gd")
const Lights = preload("res://vehicle_lights.gd")
const SPAWN := Vector3(-8.5,.91,3.0)
const BAG_POINTS := [Vector3(-7,0,4),Vector3(-5.8,0,4)]
const TASKS := ["Recoge la primera maleta.","Acércate a la parte trasera del taxi.","Abre el maletero.","Coloca la primera maleta dentro.","Regresa por la segunda maleta.","Coloca la segunda maleta dentro.","Cierra el maletero.","Sube al taxi por la puerta del pasajero.","Fase 1 completada. Viaje pendiente de la fase 2."]
var progress := Progress.new()
var mats: Dictionary = {}
var unit_box := BoxMesh.new()
var player: CharacterBody3D
var camera: Camera3D
var taxi: Node3D
var lid: Node3D
var door: Node3D
var bags: Array[Node3D] = []
var walkers: Array = []
var objective: Label
var prompt: Label
var message: Label
var menu: PanelContainer
var hud: CanvasLayer
var yaw := -2.05
var pitch := -.08
var menu_open := false
var touch_keys: Dictionary = {}
var mobile := false
var note_time := 0.0
var marker: Node3D
var lid_tween: Tween

func _ready() -> void:
	mobile = OS.has_feature("android") or OS.has_feature("ios") or OS.get_cmdline_user_args().has("--touch-controls")
	progress.load_game()
	_make_environment()
	_make_terminal()
	_make_taxi()
	_make_people()
	_make_player()
	_make_bags()
	_make_hud()
	_sync()
	if progress.stage==8: _seat_player()
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
	var concrete := Color("#c7c3b6")
	var cream := Color("#e0d9ca")
	var glass := Color("#506c7a")
	var asphalt := Color("#555956")
	var trim := Color("#a1a6a3")
	_box(self,Vector3(0,-.18,8),Vector3(84,.36,50),concrete,true)
	_box(self,Vector3(0,.012,18),Vector3(84,.022,12),asphalt)
	_box(self,Vector3(0,.065,5),Vector3(84,.13,13),concrete,true)
	# Façade only: arrivals zone is outdoors. The interior is deliberately closed.
	_box(self,Vector3(0,4.6,-8),Vector3(70,9.2,12),cream,true)
	_box(self,Vector3(0,5.6,-1.94),Vector3(70,5.5,.14),glass)
	_box(self,Vector3(0,8.4,-1.76),Vector3(70,.65,.28),cream)
	for i in range(15):
		var x := -33.6+float(i)*4.8
		_box(self,Vector3(x,5.6,-1.80),Vector3(.13,5.5,.28),trim)
	for i in range(10):
		var x := -31.5+float(i)*7.0
		_box(self,Vector3(x,1.5,-1.75),Vector3(5.6,2.9,.16),glass)
		_box(self,Vector3(x,1.5,-1.63),Vector3(.09,2.9,.10),trim)
		_box(self,Vector3(x,2.98,-1.63),Vector3(5.6,.13,.18),trim)
	_box(self,Vector3(0,3.65,1.0),Vector3(72,.48,6.3),cream,true)
	for i in range(9):
		var x := -32.0+float(i)*8.0
		_box(self,Vector3(x,1.78,3.8),Vector3(.48,3.56,.48),trim,true)
	_label3(self,"AEROPUERTO INTERNACIONAL JOSÉ MARTÍ",Vector3(0,8.43,-1.55),.011,Color("#253941"))
	_label3(self,"LLEGADAS  /  ARRIVALS",Vector3(0,3.71,4.22),.008,Color("#31424b"))
	for x in range(-36,37,6):
		_box(self,Vector3(float(x),.025,18),Vector3(2.8,.012,.11),Color("#e1d7ab"))
	_box(self,Vector3(0,.028,11.9),Vector3(82,.012,.12),Color("#c9ac51"))
	for x in [-32.0,-22.0,20.0,31.0]:
		_box(self,Vector3(x,1.2,9.4),Vector3(.12,2.4,.12),trim)
		_label3(self,"TAXIS",Vector3(x,2.2,9.48),.005,Color("#233c4a"))
	# Boundaries outside the visible playable pickup area.
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
	taxi.position = Vector3(7.5,.13,13.4)
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
		other.position = Vector3([-13.0,20.0,31.0][i],.13,13.4)
		other.rotation.y = PI*.5
		_car_shell(other,[Color("#aeb8b9"),Color("#e1dacb"),Color("#66838c")][i],false)
		# Parked props are outside the mission's walkable interaction area.
		_box(other,Vector3(0,.75,0),Vector3(1.75,1.5,4.5),Color("#777777"),true).hide()

func _make_people() -> void:
	for i in range(8):
		var person := Person.new()
		add_child(person)
		person.setup(330+i*17,i==0 or i==5,true)
		person.position = Vector3(-28+float(i)*7.7,.13,6.4 if i%2==0 else 8.4)
		person.rotation.y = PI*.5
		if i%3==1: person.set_bag(true)
		if i in [2,6]:
			walkers.append({"node":person,"origin":person.position,"phase":float(i)})
	# The assigned driver waits beside the front of the taxi.
	var driver := Person.new()
	add_child(driver)
	driver.setup(414)
	driver.position = Vector3(10.1,.13,11.0)
	driver.rotation.y = PI

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

func _make_bags() -> void:
	for i in range(2):
		var bag := Node3D.new()
		add_child(bag)
		var color := Color("#596b79") if i==0 else Color("#76584a")
		_box(bag,Vector3(0,.28,0),Vector3(.42,.53,.24),color)
		_box(bag,Vector3(0,.55,0),Vector3(.15,.06,.06),Color("#303738"))
		for x in [-.15,.15]:
			_box(bag,Vector3(float(x),.035,0),Vector3(.065,.07,.07),Color("#25292b"))
		bags.append(bag)
	marker = Node3D.new()
	add_child(marker)
	_label3(marker,"▼",Vector3(0,1.7,0),.010,Color("#ffd976")).billboard = BaseMaterial3D.BILLBOARD_ENABLED

func _trunk_point() -> Vector3:
	return taxi.to_global(Vector3(0,0,-2.9))

func _door_point() -> Vector3:
	return taxi.to_global(Vector3(1.35,0,.23))

func _target() -> Vector3:
	match progress.stage:
		0: return BAG_POINTS[0]
		4: return BAG_POINTS[1]
		7: return _door_point()
	return _trunk_point()

func _near(at: Vector3,radius: float=1.45) -> bool:
	return Vector2(player.global_position.x,player.global_position.z).distance_to(Vector2(at.x,at.z))<=radius

func _sync() -> void:
	var step := progress.stage
	for i in range(bags.size()):
		var bag := bags[i]
		var carried := (i==0 and step>=1 and step<=3) or (i==1 and step==5)
		var stored := (i==0 and step>=4) or (i==1 and step>=6)
		if carried:
			if bag.get_parent()!=camera: bag.reparent(camera,false)
			bag.position = Vector3(.40,-.62,-.75)
			bag.rotation = Vector3.ZERO
		elif stored:
			if bag.get_parent()!=taxi: bag.reparent(taxi,false)
			bag.position = Vector3(-.28 if i==0 else .28,.61,-1.65)
			bag.rotation = Vector3.ZERO
			# Lower the upright case into the trunk on its side.
			bag.rotation.x = PI*.5
		else:
			if bag.get_parent()!=self: bag.reparent(self,false)
			bag.position = BAG_POINTS[i]+Vector3.UP*.13
			bag.rotation = Vector3.ZERO
	lid.rotation.x = 1.15 if step>=3 and step<=6 else 0.0
	marker.visible = step<8
	if step<8: marker.global_position = _target()
	objective.text = "CAPÍTULO 1 · DE REGRESO A CUBA\n"+TASKS[step]+"   (%d/8)" % step
	if step==8: prompt.text = "Fase 1 completada · Esc para abrir el menú"

func _advance(action: String) -> void:
	var old := progress.stage
	var old_pos := progress.checkpoint
	if not progress.advance(action,player.global_position): return
	if not progress.save_game():
		progress.stage = old
		progress.checkpoint = old_pos
		_notice("No se pudo guardar. Intenta de nuevo.")
		return
	_sync()
	if progress.stage==8: _seat_player()

func _interact() -> void:
	if menu_open or progress.stage==8: return
	if not _near(_target()):
		_notice("Acércate al objetivo marcado.")
		return
	if progress.stage==1: return
	var before := progress.stage
	var old_angle := lid.rotation.x
	_advance(Progress.expected_action(before))
	if progress.stage==before: return
	if before in [2,6]:
		if lid_tween!=null: lid_tween.kill()
		var goal := lid.rotation.x
		lid.rotation.x = old_angle
		lid_tween = create_tween()
		lid_tween.tween_property(lid,"rotation:x",goal,.45)

func _seat_player() -> void:
	player.velocity = Vector3.ZERO
	player.set_physics_process(false)
	player.hide()
	camera.reparent(taxi,false)
	camera.position = Vector3(.36,1.31,.03)
	camera.rotation = Vector3(0,PI,0)
	camera.make_current()
	door.rotation.y = 0.0
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
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu_open or mobile or progress.stage==8 else Input.MOUSE_MODE_CAPTURED

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
	if menu_open or progress.stage==8: return
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
		var person: Node3D = item.node
		item.phase = float(item.phase)+delta*.30
		var origin: Vector3 = item.origin
		person.position.x = origin.x+sin(float(item.phase))*2.0
		person.rotation.y = PI*.5 if cos(float(item.phase))>0 else -PI*.5
		person.animate(delta,true,1.2)
	if progress.stage==8: return
	var axis := Vector2(float(_pressed(KEY_D,"right"))-float(_pressed(KEY_A,"left")),float(_pressed(KEY_S,"back"))-float(_pressed(KEY_W,"forward"))).limit_length(1.0)
	var direction := player.transform.basis*Vector3(axis.x,0,axis.y)
	player.velocity.x = direction.x*3.8
	player.velocity.z = direction.z*3.8
	player.velocity.y -= 9.8*delta
	player.move_and_slide()
	if player.position.y<-.8:
		player.position = progress.checkpoint
		player.velocity = Vector3.ZERO
	if progress.stage==1 and _near(_trunk_point()): _advance("approach")
	var near := _near(_target())
	var actions := ["Recoger maleta","","Abrir maletero","Guardar maleta","Recoger maleta","Guardar maleta","Cerrar maletero","Subir al taxi"]
	if progress.stage<8:
		prompt.text = ("[E] "+actions[progress.stage]) if near and progress.stage!=1 else "WASD · Caminar   /   Sigue el marcador"
