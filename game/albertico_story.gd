extends Node3D
# The first mission retains ledger stages 0..4 for all downstream unlocks.
# The story substage and paid boxes are persisted independently of taxi IDs.
const Ledger = preload("res://business_ledger.gd")
const Person = preload("res://street_person.gd")
var taxi_companion: Person
var handshake_camera := false
const REQUIRED := ["huevos","perrito","pollo","picadillo"]
const ROOM := Vector3(60,110,0)
const FRIDGE := Vector3(-5.8,110,3.6)
var game
var business
var ledger: Ledger
var state: Dictionary = {}
var cab: Dictionary = {}
var rider_trip := false
var waiting := 0.0
var initialized := false
var home: Dictionary = {}
var neighbor: Dictionary = {}
var original_actor := Vector3.ZERO
var original_angle := 0.0
var room: Node3D
var table: Node3D
var fridge: Node3D
var helper_box: Node3D
var loading := ""
var loading_clock := 0.0
var pickup_clock := 0.0
var fetch_clock := 0.0
var marker: Node3D
var banner: Label
var banner_clock := 0.0
var handshake_clock := 0.0
var old_first := true
var next_retry := 0.0
var table_in_room := false

func setup(controller) -> void:
	game = controller
	business = game.business
	ledger = business.ledger
	home = game.cuba_world.garage_home_site
	if is_instance_valid(business.albertico):
		original_actor = business.albertico.global_position
		original_angle = business.albertico.rotation.y
	if ledger.life_data.has("albertico_story"):
		state = ledger.life_data.albertico_story
	_make_fridge()
	var overlay := CanvasLayer.new()
	overlay.layer = 22
	add_child(overlay)
	banner = Label.new()
	overlay.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -340
	banner.offset_right = 340
	banner.offset_top = -55
	banner.offset_bottom = 55
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size",32)
	banner.add_theme_color_override("font_color",Color("#ffe6a1"))
	banner.add_theme_color_override("font_shadow_color",Color.BLACK)
	banner.add_theme_constant_override("shadow_offset_y",3)
	banner.text = "MISIÓN CUMPLIDA"
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.hide()
	marker = business._arrow(self,Vector3.ZERO,Color("#e9cb70"))
	marker.hide()
	business._sync_visuals()

func _phase() -> String:
	return String(state.get("phase",""))

func active() -> bool:
	return not state.is_empty() and ledger.stage<4

func carrying_table() -> bool:
	return active() and _phase() in ["room_carry","street_carry"]

func _save() -> void:
	ledger.save_game()

func _set_phase(value: String) -> void:
	state.phase = value
	_save()
	business._sync_visuals()

static func all_four(counts: Dictionary) -> bool:
	for key in REQUIRED:
		if int(counts.get(key,0))!=1: return false
	return true

func _home_door() -> Vector3:
	return home.get("door",game.cuba_world.home_spawn)

func _home_road() -> Vector3:
	return home.get("road",game.cuba_world.van_spawn)

func _find_neighbor() -> Dictionary:
	if home.is_empty(): return {}
	var door: Vector3 = home.door
	var road: Vector3 = home.road
	var normal: Vector3 = home.basis.z
	var best := INF
	var found: Dictionary = {}
	for entry in game.cuba_world.npc_doorways:
		if String(entry.kind)!="home": continue
		var p: Vector3 = entry.threshold
		var n: Vector3 = entry.normal
		if n.dot(normal)>-.65 or (p-road).dot(normal)<1.0: continue
		var lateral := absf((p-door).dot(home.basis.x))
		if lateral>13.0 or p.distance_to(door)>36.0: continue
		var rank := lateral*2.0+p.distance_to(door)
		if rank<best:
			best = rank
			found = {"door":p,"normal":n}
	return found

func prepare_meeting() -> void:
	if home.is_empty(): return
	_ensure_cab(_home_road())

func begin() -> bool:
	if not state.is_empty(): return false
	if home.is_empty() or game.cuba_world.food_factory.is_empty():
		business._notify("No se encontró el acceso de tu casa o de la MIPYME.")
		return false
	neighbor = _find_neighbor()
	if neighbor.is_empty():
		business._notify("No se encontró una puerta residencial frente a tu casa.")
		return false
	state = {"phase":"outbound","bought":{},"taxi_boxes":{},"cold":{}}
	ledger.life_data.albertico_story = state
	# accept() writes both the ledger stage and story in the same save.
	prepare_meeting()
	return true

func _ensure_cab(near: Vector3) -> bool:
	if not cab.is_empty() and is_instance_valid(cab.get("body")): return true
	var berth: Dictionary = game.yordi_mission._road_berth(near,4.0,36.0,1.9,4.8,1.55)
	if berth.is_empty(): return false
	var body: CharacterBody3D = game.taxis._make_taxi(game.taxis.taxis.size())
	body.global_position = berth.p
	var direction: Vector3 = berth.d
	body.rotation.y = atan2(direction.x,direction.z)
	body.add_to_group("traffic_parked")
	body.set_meta("traffic_priority",4.8)
	cab = {"body":body,"next_node":String(berth.next),"path":[],"index":0,"speed":0.0,"blocked":0.0,"goal":"","label":"","note":"","albertico_reserved":true}
	game.taxis.taxis.append(cab)
	return true

func owns_trip() -> bool:
	return rider_trip

func _start_trip() -> bool:
	if cab.is_empty() or not game.taxis.passenger.is_empty() or not game.garage._free_hands(): return false
	var body: CharacterBody3D = cab.body
	var goal: Vector3 = game.cuba_world.food_factory.road if _phase()=="outbound" else _home_road()
	var result: Dictionary = game.taxis.router.resolve_point(goal,String(cab.next_node))
	if result.has("error"):
		business._notify("No hay ruta segura. Pulsa R para recuperar el punto de control.")
		return false
	result.label = "MIPYME · con Albertico" if _phase()=="outbound" else "Mi casa · con Albertico"
	game.taxis.selected = cab
	game.taxis.selected_route = result
	game.taxis.trip_confirmed = true
	if not game.taxis.prepare_trip():
		game.taxis.close_dialog()
		business._notify("No hay parada segura. Pulsa R para recuperar el punto de control.")
		return false
	rider_trip = true
	business.albertico.hide()
	taxi_companion = Person.new()
	body.add_child(taxi_companion)
	taxi_companion.setup(810)
	taxi_companion.remove_from_group("social_people")
	taxi_companion.remove_from_group("pedestrian_spacing")
	taxi_companion.position = Vector3(-.39,.55,-.65)
	taxi_companion.scale = Vector3.ONE*.75
	for limb in taxi_companion.limbs: limb.rotation.x = -1.0
	for knee in taxi_companion.knees: knee.rotation.x = 1.0
	game._start_taxi_ride()
	return true

func ride_ended(reached: bool) -> void:
	rider_trip = false
	if is_instance_valid(taxi_companion): taxi_companion.queue_free()
	taxi_companion = null
	var actor: Person = business.albertico as Person
	var at: Vector3 = game.yordi_mission._near_ground(game.player.global_position,actor,6.0)
	actor.global_position = at if at.is_finite() else original_actor
	actor.show()
	if not reached:
		business._notify("Vuelve a subir al taxi para continuar con Albertico.")
		return
	if _phase()=="outbound":
		ledger.stage = 2
		_set_phase("return" if all_four(state.bought) else "shopping")
		business._notify("Compra una caja de huevos, perritos, pollo y picadillo. Albertico las carga.")
	elif _phase()=="return":
		ledger.stage = 3
		_set_phase("cold")
		business._notify("Albertico: Guarda las cajas en el frío. G en el taxi, E en el refrigerador.")

func buy(key: String,supplier: String,paid: bool) -> void:
	if _phase()!="shopping" or supplier!="primary" or paid or not key in REQUIRED:
		business._notify(objective())
		return
	if not loading.is_empty():
		business._notify("Espera a que Albertico cargue la caja.")
		return
	if state.bought.has(key):
		business._notify("Ya compraste esa caja. Falta otra variedad.")
		return
	if not _ensure_cab(game.cuba_world.food_factory.road):
		business._notify("Esperando una parada segura para el taxi.")
		return
	var cost := int(Ledger.PRODUCTS[key].cost)
	if ledger.cash<cost or not business.life.reserve_crate("primary",key):
		business._notify("No hay dinero o mercancía suficiente.")
		return
	# Paid merchandise is safe in the story manifest even if the game closes
	# while the cosmetic helper animation is playing.
	ledger.cash -= cost
	ledger.expenses += cost
	state.bought[key] = 1
	state.taxi_boxes[key] = 1
	_save()
	business.life.refresh_primary()
	loading = key
	loading_clock = 0.0
	var actor: Person = business.albertico as Person
	helper_box = business._crate(actor,Vector3(0,1.05,.30),key)
	business._notify("Albertico lleva la caja de "+business._product_name(key)+" al taxi.")

func _finish_load() -> void:
	if is_instance_valid(helper_box): helper_box.queue_free()
	helper_box = null
	loading = ""
	if all_four(state.bought):
		_set_phase("return")
		business._notify("¡Cuatro cajas listas! Sube al mismo taxi con Albertico.")

func cargo_action() -> bool:
	if _phase()!="cold" or cab.is_empty() or game.player.global_position.distance_to(cab.body.global_position+Vector3.UP*.8)>5.0:
		business._notify(objective())
		return true
	if not ledger.carry.is_empty():
		var key := ledger.carry
		state.taxi_boxes[key] = int(state.taxi_boxes.get(key,0))+1
		ledger.carry = ""
	else:
		for key in REQUIRED:
			if int(state.taxi_boxes.get(key,0))<=0: continue
			state.taxi_boxes[key] = int(state.taxi_boxes[key])-1
			ledger.carry = key
			break
	_save()
	business._sync_visuals()
	return true

func _make_fridge() -> void:
	if not is_instance_valid(game.garage.interior): return
	fridge = Node3D.new()
	game.garage.interior.add_child(fridge)
	fridge.global_position = FRIDGE
	business._box(fridge,Vector3(0,.88,0),Vector3(.70,1.76,.65),Color("#d7d9d6"))
	business._box(fridge,Vector3(0,1.43,.34),Vector3(.68,.58,.035),Color("#e8e9e5"))
	business._box(fridge,Vector3(0,.55,.34),Vector3(.68,1.06,.035),Color("#e8e9e5"))
	for y in [.85,1.40]:
		business._box(fridge,Vector3(.23,float(y),.37),Vector3(.035,.15,.04),Color("#535c60"))

func _store_cold() -> bool:
	if ledger.carry.is_empty(): return false
	var key := ledger.carry
	if active() and (_phase()!="cold" or not key in REQUIRED): return false
	if state.is_empty():
		# Old completed saves retain the standard direct stock path.
		if ledger.stage==4 and ledger.deliver():
			business._sync_visuals()
			business._notify("Caja guardada. Albertico ya dispone de ella.")
			return true
		return false
	var cold: Dictionary = state.cold
	cold[key] = int(cold.get(key,0))+1
	ledger.carry = ""
	_save()
	business._sync_visuals()
	if active() and all_four(cold):
		_set_phase("table")
		business._notify("Albertico: Vamos por una mesa que tengo en mi casa, justo enfrente.")
	else: business._notify("Caja guardada en el refrigerador.")
	return true

func _table_model(root: Node3D) -> Node3D:
	var node := Node3D.new()
	root.add_child(node)
	business._box(node,Vector3(0,.79,0),Vector3(1.45,.09,.62),Color("#a88b64"))
	for x in [-.61,.61]:
		for z in [-.23,.23]:
			business._box(node,Vector3(float(x),.39,float(z)),Vector3(.075,.78,.075),Color("#725f47"))
	return node

func _build_room() -> void:
	if is_instance_valid(room): return
	room = Node3D.new()
	add_child(room)
	room.position = ROOM
	var wall := Color("#b9b19e")
	game.garage._solid(room,Vector3(0,-.10,0),Vector3(5,.2,5),Color("#a39b88"),2)
	game.garage._solid(room,Vector3(0,1.40,-2.45),Vector3(5,2.8,.1),wall)
	for x in [-2.45,2.45]:
		game.garage._solid(room,Vector3(float(x),1.40,0),Vector3(.1,2.8,5),wall)
	game.garage._solid(room,Vector3(0,1.40,2.45),Vector3(5,2.8,.1),wall)
	game.garage._solid(room,Vector3(0,2.85,0),Vector3(5,.15,5),wall)
	business._box(room,Vector3(0,1.05,2.37),Vector3(1.05,2.1,.06),Color("#695345"))
	var label: Label3D = business._label(room,"SALIDA",Vector3(0,2.33,2.33))
	label.rotation.y = PI
	label.pixel_size = .003
	table = _table_model(room)
	table.position = Vector3(0,0,-.55)

func _teleport(p: Vector3,look: float) -> void:
	game.player.global_position = p
	game.player.velocity = Vector3.ZERO
	game.yaw = look
	game.pitch = -.12
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)

func _enter_room() -> void:
	_build_room()
	old_first = game.first_person
	game.first_person = true
	game._apply_camera_mode()
	_teleport(ROOM+Vector3(0,.86,1.55),0.0)
	business.albertico.global_position = ROOM+Vector3(.95,0,-.45)
	business.albertico.rotation.y = PI
	table_in_room = true
	_set_phase("room")

func _lift_table() -> void:
	if not is_instance_valid(table): return
	table.reparent(self,true)
	_set_phase("room_carry")
	business._notify("Lleven la mesa hasta la puerta. No hace falta pulsar E.")

func _leave_room() -> void:
	var door: Vector3 = neighbor.door
	var normal: Vector3 = neighbor.normal
	var p: Vector3 = game.yordi_mission._near_ground(door+normal*.95,business.albertico,4.0)
	if not p.is_finite(): return
	_teleport(p+Vector3.UP*.86,atan2(normal.x,normal.z)+PI)
	table_in_room = false
	_set_phase("street_carry")
	business._notify("Crucen la calle y dejen la mesa en la flecha amarilla.")

func _put_table() -> void:
	if not all_four(state.cold) or ledger.stage!=3: return
	var goal: Vector3 = business.stand.global_position
	if game.player.global_position.distance_to(goal+Vector3.UP*.86)>2.2: return
	if is_instance_valid(table): table.queue_free()
	table = null
	business.albertico.global_position = original_actor
	business.albertico.rotation.y = original_angle
	_set_phase("handshake")
	marker.hide()
	handshake_clock = 1.6
	banner_clock = 0.0
	var actor: Person = business.albertico as Person
	var face: Vector3 = game.player.global_position-actor.global_position
	face.y = 0.0
	if face.length_squared()>.02:
		actor.rotation.y = atan2(face.x,face.z)
		game.avatar.rotation.y = atan2(-face.x,-face.z)
	actor.set_meta("story_handshake",true)
	handshake_camera = business.story_camera.begin(actor,game.player,game.play_camera)
	if handshake_camera: game.avatar.show()

func handshake_active() -> bool:
	return handshake_clock>0.0

func _finish_handshake() -> void:
	business.story_camera.finish()
	business.albertico.remove_meta("story_handshake")
	business.albertico.rotation.y = original_angle
	game.first_person = old_first
	game._apply_camera_mode()
	# Activate sales and downstream missions only after the handshake.
	ledger.stage = 4
	state.phase = "done"
	ledger.add_message("Albertico","¡Ya estamos montados! Puedes darme mercancía afuera o dejarla en tu refrigerador. Mi comisión es el 15% de cada venta.")
	_save()
	business._sync_visuals()
	banner.text = "MISIÓN CUMPLIDA\nTe tengo un bisne"
	banner.show()
	banner_clock = 4.5
	business._notify("Ahora puedes comprar mercancía, entregarla a Albertico o guardarla en el frío.")

func _fetch_stock(delta: float) -> void:
	if state.is_empty() or ledger.stage!=4 or state.get("cold",{}).is_empty(): return
	if game.taxi_riding or business.modal_open(): return
	var cold: Dictionary = state.cold
	var total := ledger.total(cold)
	if total<=0: return
	fetch_clock += delta
	var actor: Person = business.albertico as Person
	if fetch_clock<2.5:
		var target: Vector3 = _home_door()+home.basis.z*.8
		game.yordi_mission._walk(actor,target,delta,2.2,.8)
		return
	if fetch_clock<3.5:
		actor.hide()
		return
	for key in cold:
		var count := int(cold[key])
		if count>0:
			ledger.stock[key] = int(ledger.stock.get(key,0))+count*int(Ledger.PRODUCTS[key].units)
			ledger.low_alert[key] = false
	cold.clear()
	actor.global_position = original_actor
	actor.rotation.y = original_angle
	actor.show()
	fetch_clock = 0.0
	_save()
	business._sync_visuals()
	business._notify("Albertico recogió la mercancía del frío y ya puede venderla.")

func companion_action() -> String:
	return "[E] Hablar con Albertico" if active() and not carrying_table() else ""

func talk() -> void:
	business._notify(objective())

func action_text() -> String:
	if is_instance_valid(fridge) and game.garage.inside and not ledger.carry.is_empty() and game.player.global_position.distance_to(FRIDGE+Vector3.UP*.86)<1.65:
		return "[E] Guardar caja en el frío"
	if not active(): return ""
	if carrying_table(): return "Lleva la mesa con Albertico"
	if _phase()=="room" and game.player.global_position.distance_to(ROOM+Vector3(0,.86,-.55))<2.0: return "[E] Levantar mesa entre los dos"
	if _phase() in ["outbound","return"] and not cab.is_empty() and game.player.global_position.distance_to(cab.body.global_position+Vector3.UP*.8)<4.0: return "[E] Subir al taxi con Albertico"
	if _phase()=="table" and not neighbor.is_empty() and not game.garage.inside and game.player.global_position.distance_to(neighbor.door+Vector3.UP*.86)<2.0: return "[E] Entrar a casa de Albertico"
	return ""

func interact() -> bool:
	var action := action_text()
	if action.contains("Guardar caja"): return _store_cold()
	if action.contains("Subir al taxi"):
		_start_trip()
		return true
	if action.contains("Entrar a casa de Albertico"):
		if game.garage._free_hands(): _enter_room()
		return true
	if action.contains("Levantar mesa"):
		if game.garage._free_hands(): _lift_table()
		return true
	return false

func objective() -> String:
	match _phase():
		"outbound": return "Albertico · Sube al taxi para ir a la MIPYME."
		"shopping":
			var missing := PackedStringArray()
			for key in REQUIRED:
				if not state.bought.has(key): missing.append(business._product_name(key))
			return "Compra 1 caja de cada: "+", ".join(missing) if not missing.is_empty() else "Albertico está cargando las cajas."
		"return": return "Sube al taxi con Albertico y vuelve a casa."
		"cold": return "G: descarga las cajas. E: guárdalas en el frío (%d/4)." % ledger.total(state.cold)
		"table": return "Cruza la calle y entra a casa de Albertico."
		"room": return "Levanta la mesa con Albertico."
		"room_carry": return "Caminen hasta la puerta."
		"street_carry": return "Cruza la calle y lleva la mesa a la flecha."
		"handshake": return "Cerrando el trato con Albertico."
	return ""

func destination() -> Dictionary:
	if not active(): return {}
	match _phase():
		"outbound","return": 
			if not cab.is_empty(): return {"p":cab.body.global_position,"label":"Taxi con Albertico"}
		"shopping": return {"p":game.cuba_world.food_factory.counter,"label":"MIPYME"}
		"cold": return {"p":_home_door(),"label":"Mi casa · refrigerador"}
		"table":
			if not neighbor.is_empty(): return {"p":neighbor.door,"label":"Casa de Albertico"}
		"street_carry": return {"p":business.stand.global_position,"label":"Colocar mesa"}
	return {}

func reset_checkpoint() -> bool:
	if not active(): return false
	if game.taxi_riding: return false
	if is_instance_valid(table): table.queue_free()
	table = null
	if is_instance_valid(room): room.queue_free()
	room = null
	table_in_room = false
	game.garage.inside = false
	if _phase() in ["room","room_carry","street_carry","handshake"]: _set_phase("table")
	if not cab.is_empty() and is_instance_valid(cab.body):
		game.taxis.taxis.erase(cab)
		cab.body.queue_free()
	cab = {}
	if is_instance_valid(helper_box): helper_box.queue_free()
	loading = ""
	initialized = false
	return true

func tick(delta: float) -> void:
	if not is_instance_valid(business.albertico): return
	if banner_clock>0.0:
		banner_clock -= delta
		if banner_clock<=0.0: banner.hide()
	if handshake_clock>0.0:
		handshake_clock -= delta
		var pose := -1.10+sin(handshake_clock*13.0)*.13
		business.albertico.arms[1].rotation.x = pose
		if game.limb_arms.size()>1: game.limb_arms[1].rotation.x = pose
		if handshake_clock<=0.0: _finish_handshake()
		return
	if not active():
		if ledger.stage==4: _fetch_stock(delta)
		elif ledger.albertico_visible() and not game.taxi_riding and not business.modal_open():
			next_retry -= delta
			if next_retry<=0.0:
				next_retry = 3.0
				prepare_meeting()
		return
	if business.modal_open() or game.taxi_riding or game.driving or game.bus_riding or game.garage.riding: return
	if not initialized:
		initialized = true
		neighbor = _find_neighbor()
		if _phase() in ["room","room_carry","street_carry","handshake"]: _set_phase("table")
		if _phase()=="shopping" and all_four(state.bought): _set_phase("return")
		if _phase() in ["shopping","return"]:
			var factory: Dictionary = game.cuba_world.food_factory
			_teleport(factory.center+factory.basis*Vector3(0,.96,3.55),factory.basis.get_euler().y)
		elif _phase() in ["outbound","cold","table"]:
			var start: Vector3 = game.yordi_mission._near_ground(_home_door()+home.basis.z*.9,business.albertico,6.0)
			if start.is_finite(): _teleport(start+Vector3.UP*.86,original_angle)
		business.albertico.global_position = original_actor
		business.albertico.show()
	next_retry -= delta
	if _phase() in ["outbound","shopping","return","cold"] and next_retry<=0.0:
		next_retry = 3.0
		_ensure_cab(game.cuba_world.food_factory.road if _phase() in ["shopping","return"] else _home_road())
	var actor: Person = business.albertico as Person
	if not loading.is_empty():
		loading_clock += delta
		if cab.is_empty() and loading_clock>12.0:
			_finish_load()
			return
		if not cab.is_empty():
			var at: Vector3 = game.yordi_mission._near_ground(cab.body.global_position,actor,8.0) if loading_clock<.2 else Vector3.INF
			if at.is_finite(): actor.set_meta("albertico_load_target",at)
			var target: Vector3 = actor.get_meta("albertico_load_target",actor.global_position)
			if game.yordi_mission._walk(actor,target,delta,2.8,1.0) or loading_clock>12.0: _finish_load()
			else:
				for arm in actor.arms: arm.rotation.x = -.85
		return
	if carrying_table():
		var forward: Vector3 = -game.pivot.global_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		if is_instance_valid(table):
			table.global_position = game.player.global_position+forward*.85-Vector3.UP*.48
			table.rotation.y = atan2(forward.x,forward.z)+PI*.5
		actor.global_position = game.player.global_position+forward*1.65-Vector3.UP*.86
		actor.rotation.y = atan2(-forward.x,-forward.z)
		actor.animate(delta,game.player.velocity.length()>.15)
		for arm in actor.arms: arm.rotation.x = -1.0
		if _phase()=="room_carry" and game.player.global_position.distance_to(ROOM+Vector3(0,.86,2.0))<1.05: _leave_room()
		elif _phase()=="street_carry": _put_table()
	else:
		if _phase() in ["outbound","shopping","return","table"] and not game.garage.inside:
			var ground: Vector3 = game.player.global_position-Vector3.UP*.86
			if actor.global_position.distance_to(ground)>2.0: game.yordi_mission._walk(actor,ground,delta,2.4,1.8)
		elif _phase()=="cold": actor.global_position = original_actor
	var dest := destination()
	marker.visible = not dest.is_empty() and _phase() in ["table","street_carry"]
	if marker.visible: marker.global_position = dest.p+Vector3.UP*2.2
