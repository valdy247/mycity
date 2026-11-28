extends Node3D
# Optional, local sports practice on the courts and diamonds that actually
# exist in El Pontón. No extra world meshes outside an active session.
const Leisure = preload("res://leisure_rules.gd")
var game
var sites: Array = []
var session: Dictionary = {}
var root: Node3D
var ball: MeshInstance3D
var goalie: Node3D
var overlay: CanvasLayer
var label: Label
var prior_first := true
var prior_yaw := 0.0
var prior_pitch := 0.0
var return_at := Vector3.ZERO
var attempts := 0
var score := 0
var lane := 0
var timer := 0.0
var flight := 0.0
var flight_from := Vector3.ZERO
var flight_to := Vector3.ZERO
var flight_good := false
var feedback := ""
var forward := Vector3.FORWARD
var side := Vector3.RIGHT

func setup(controller) -> void:
	game = controller
	if is_instance_valid(game.cuba_world.parks): sites = game.cuba_world.parks.sport_sites

func active() -> bool:
	return not session.is_empty()

func _near() -> Dictionary:
	if game.driving or game.taxi_riding or game.bus_riding or game.garage.riding or game.garage.inside or game.player.global_position.y>5.0: return {}
	for site in sites:
		if game.player.global_position.distance_to(Vector3(site.start)+Vector3.UP*.86)<3.0: return site
	return {}

func action_text() -> String:
	if active(): return "Espacio: jugar · Esc: terminar"
	var site := _near()
	return "[E] "+String(site.name) if not site.is_empty() else ""

func interact() -> bool:
	if active(): return true
	var site := _near()
	if site.is_empty(): return false
	if not game.garage._free_hands():
		game.business._notify("Deja libres las manos para practicar.")
		return true
	_begin(site)
	return true

func _begin(site: Dictionary) -> void:
	session = site
	attempts = 0
	score = 0
	lane = 0
	timer = 0.0
	flight = 0.0
	feedback = ""
	return_at = game.player.global_position
	prior_first = game.first_person
	prior_yaw = game.yaw
	prior_pitch = game.pitch
	var start: Vector3 = site.start
	var target: Vector3 = site.target
	forward = (target-start).normalized()
	side = Vector3(-forward.z,0,forward.x)
	game.player.global_position = start-forward*.85+Vector3.UP*.86
	game.player.velocity = Vector3.ZERO
	game.first_person = false
	game.yaw = atan2(-forward.x,-forward.z)
	game.pitch = -.18
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	game.arm.spring_length = 3.0
	root = Node3D.new()
	add_child(root)
	ball = MeshInstance3D.new()
	root.add_child(ball)
	var mesh := SphereMesh.new()
	mesh.radius = .11 if String(site.kind)=="futbol" else .055
	mesh.height = mesh.radius*2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	ball.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#eee5ce")
	ball.material_override = material
	if String(site.kind)=="futbol":
		for sign_value in [-1.0,1.0]:
			game.business._box(root,target+side*float(sign_value)*1.6+Vector3.UP*.95,Vector3(.11,1.9,.11),Color("#e0d9c4"))
		var bar: MeshInstance3D = game.business._box(root,target+Vector3.UP*1.9,Vector3(3.2,.11,.11),Color("#e0d9c4"))
		bar.rotation.y = atan2(-side.z,side.x)
		goalie = Node3D.new()
		root.add_child(goalie)
		goalie.position = target
		game.business._box(goalie,Vector3.UP*.75,Vector3(.55,1.05,.26),Color("#c69a47"))
		game.business._box(goalie,Vector3.UP*1.45,Vector3(.25,.30,.25),Color("#b78a64"))
		game.business._box(goalie,Vector3(-.42,.95,0),Vector3(.32,.13,.13),Color("#c69a47"))
		game.business._box(goalie,Vector3(.42,.95,0),Vector3(.32,.13,.13),Color("#c69a47"))
	overlay = CanvasLayer.new()
	add_child(overlay)
	overlay.layer = 12
	var panel := PanelContainer.new()
	overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -250
	panel.offset_right = 250
	panel.offset_top = -100
	panel.offset_bottom = -12
	var col := VBoxContainer.new()
	panel.add_child(col)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(label)
	var row := HBoxContainer.new()
	col.add_child(row)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if String(site.kind)=="futbol":
		_button(row,"Izquierda",_aim.bind(-1))
		_button(row,"Centro",_aim.bind(0))
		_button(row,"Derecha",_aim.bind(1))
	_button(row,"¡Ahora!",_strike)
	_button(row,"Salir",end_session)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_reset_ball()

func _button(row: HBoxContainer,value: String,callback: Callable) -> void:
	var button := Button.new()
	row.add_child(button)
	button.text = value
	button.custom_minimum_size.y = 40
	button.pressed.connect(callback)

func _aim(value: int) -> void:
	if flight<=0.0: lane = clampi(value,-1,1)

func _reset_ball() -> void:
	timer = 0.0
	flight = 0.0
	var start: Vector3 = session.start
	var target: Vector3 = session.target
	ball.position = start+Vector3.UP*.12 if String(session.kind)=="futbol" else target+Vector3.UP*1.05

func _strike() -> void:
	if not active() or flight>0.0 or attempts>=5: return
	var start: Vector3 = session.start
	var target: Vector3 = session.target
	flight_from = ball.position
	flight = .75
	attempts += 1
	if String(session.kind)=="futbol":
		var accurate := absf(fposmod(timer,1.5)-.75)<.29
		var keeper := randi_range(-1,1)
		flight_good = accurate and keeper!=lane
		if is_instance_valid(goalie): goalie.position = target+side*float(keeper)
		flight_to = target+side*(float(lane)*1.05 if accurate else 2.4)+Vector3.UP*.7
		feedback = "¡Gol!" if flight_good else ("Atajada" if accurate else "Fuera")
	else:
		flight_good = absf(timer-1.45)<.24
		flight_to = target+forward*3.0+side*randf_range(-1.5,1.5) if flight_good else start-forward*.6
		flight_to.y += .2
		feedback = "¡Buen batazo!" if flight_good else "Fallaste el lanzamiento"
		for arm in game.limb_arms: arm.rotation.x = -1.0
	if flight_good: score += 1

func handle(event: InputEvent) -> bool:
	if not active(): return false
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE,KEY_R: end_session()
			KEY_SPACE: _strike()
			KEY_LEFT: _aim(-1)
			KEY_UP: _aim(0)
			KEY_RIGHT: _aim(1)
		return true
	return event is InputEventMouseMotion

func tick(delta: float) -> void:
	if not active(): return
	game.player.velocity = Vector3.ZERO
	if flight>0.0:
		flight = maxf(0.0,flight-delta)
		var t := 1.0-flight/.75
		ball.position = flight_from.lerp(flight_to,t)+Vector3.UP*sin(t*PI)*(.75 if flight_good else .15)
		if flight<=0.0:
			if attempts>=5:
				end_session()
				return
			_reset_ball()
	else:
		timer += delta
		if String(session.kind)=="pelota":
			var target: Vector3 = session.target
			var start: Vector3 = session.start
			ball.position = (target+Vector3.UP*1.05).lerp(start+Vector3.UP*.85,minf(1.0,timer/1.45))
			if timer>1.75: _strike()
	var timing := absf(fposmod(timer,1.5)-.75)<.29 if String(session.kind)=="futbol" else absf(timer-1.45)<.24
	label.text = "%s · %d de 5\n%s" % [String(session.name),score,feedback if flight>0.0 else ("¡AHORA!" if timing else "Espera el momento")]

func end_session() -> void:
	if not active(): return
	var kind := String(session.kind)
	session = {}
	if is_instance_valid(root): root.queue_free()
	if is_instance_valid(overlay): overlay.queue_free()
	root = null
	overlay = null
	goalie = null
	game.player.global_position = return_at
	game.player.velocity = Vector3.ZERO
	game.first_person = prior_first
	game.yaw = prior_yaw
	game.pitch = prior_pitch
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	for arm in game.limb_arms: arm.rotation = Vector3.ZERO
	game._apply_camera_mode()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if attempts>0:
		var life: Dictionary = game.business.life.state
		if not life.has("sport_records"): life.sport_records = {}
		life.sport_records[kind] = maxi(int(life.sport_records.get(kind,0)),score)
		Leisure.reward(life,"ponton_"+kind,6.0,0.0,120.0)
		game.business.ledger.save_game()
		game.business._notify("Práctica terminada · %d aciertos de %d" % [score,attempts])
