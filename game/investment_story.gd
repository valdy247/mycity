extends Node3D
# Continuation of the airport story. The persistent box states and escrow
# are in the same atomic ledger save as the wallet.
const Person = preload("res://street_person.gd")
const Bypass = preload("res://traffic_bypass.gd")
const KEYS := ["pollo","huevos","aceite"]
const ENTRY := Vector3(-.7,110.86,4.85)
const FRIDGE := Vector3(-5.18,110.86,.85)
const OIL := Vector3(-5.38,110.86,-.65)
const TABLE_ROOM := Vector3(60,110,0)
const LINES := [
	["Tú","Déjame ponerme a limpiar un poco esta casa mientras Albertico viene.",4.4],
	["Albertico","Mi socio, vendí todo. Aquí tienes tu plata.",3.0],
	["Tú","Coño, asere, tremenda ayuda.",2.1],
	["Albertico","Oye, yo conozco una MIPYME donde podemos comprar mercancía y revenderla.",4.8],
	["Tú","¿Y eso deja algo?",1.6],
	["Albertico","Claro, caballo. Vamos pa' allá.",2.4],
	["Vendedor","Buen día, ¿en qué te puedo ayudar?",2.5],
	["Tú","Mira, tengo esto. ¿Qué puedo comprar pa' empezar a invertir?",3.8],
	["Vendedor","Mmm... a ver... Sí, llévate una caja de pollo, cien huevos y diez pomos de aceite. Eso es lo que más se vende.",7.0],
	["Albertico","Vamos a guardar esto en tu casa y después buscamos una mesa que tengo en la mía.",5.0],
	["Albertico","Ven, sígueme.",1.3],
	["Albertico","Te voy a avisar cuando se me esté acabando algo, pa' tener siempre mercancía.",4.6],
	["Tú","Dale, está bien. Vamos a ver si esto camina.",3.0],
	["Tú","Ah, mira, hazme un favor. Hoy viene un taxista a buscar este dinero. Es que tengo que ir a un lugar ahora.",6.5],
	["Albertico","Dale, mi hermano. Nos vemos.",2.1]
]
var story
var game
var world
var ledger
var state: Dictionary
var legacy
var phase := "boot"
var resume := ""
var clock := 0.0
var speech_left := 0.0
var line := -1
var after_talk := ""
var actor: Person
var actor_reposition_pending := false
var clerk: Person
var cab: Dictionary = {}
var ride_out := true
var cab_lid: Node3D
var ride_view: Camera3D
var ride_look := Vector2.ZERO
const RETURN_TAXI_FARE := 1000
var fare_notice: Label
var fare_notice_left := 0.0
var ride_driver: Person
var actor_scale := Vector3.ONE
var helper_elapsed := 0.0
var helper_path: PackedVector3Array = PackedVector3Array()
var helper_index := 0
var helper_goal := Vector3.INF
var marker: Label3D
var carry := ""
var held: Node3D
var boxes: Dictionary = {}
var neighbor: Dictionary = {}
var helper_box: Node3D
var helper_stage := ""
var helper_clock := 0.0
var waiting_clock := 0.0
var neighbor_exit_path := PackedVector3Array()
var neighbor_exit_index := 0
var table: Node3D
var carry_table := false
var money_prop: Node3D
var retry := 0.0
var dirt_keys: Array = []
var old_first := true
var last_sweep := 0
var save_clock := 0.0
var cleanup_clock := 0.0

func setup(parent_story) -> void:
	story = parent_story
	game = story.game
	world = game.cuba_world
	ledger = game.business.ledger
	state = story.state
	legacy = game.business.first_story
	old_first = game.first_person
	game.first_person = true
	game._apply_camera_mode()
	story.layer.show()
	story.fade.color.a = 0.0
	story.title.hide()
	game.business.layer.hide()
	game.status.hide()
	game.reticle.hide()
	game.map_credit.hide()
	marker = Label3D.new()
	add_child(marker)
	marker.text = "▼"
	marker.font_size = 84
	marker.pixel_size = .008
	marker.modulate = Color("#ffd34d")
	marker.outline_size = 10
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.hide()
	fare_notice = Label.new()
	story.objective.get_parent().add_child(fare_notice)
	fare_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	fare_notice.offset_left = -350
	fare_notice.offset_right = -24
	fare_notice.offset_top = 110
	fare_notice.offset_bottom = 174
	fare_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fare_notice.add_theme_font_size_override("font_size",22)
	fare_notice.add_theme_color_override("font_color",Color("#ffb4a8"))
	fare_notice.add_theme_color_override("font_outline_color",Color.BLACK)
	fare_notice.add_theme_constant_override("outline_size",6)
	fare_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fare_notice.hide()
	resume = String(state.get("investment_stage","clean"))
	dirt_keys = state.get("investment_dirt",[])
	neighbor = legacy._find_neighbor()
	if resume=="clean" and dirt_keys.is_empty(): _seed_dirt()
	_task("Continuación de la adaptación")

func _save() -> void:
	story._save()

func _set_phase(value: String,checkpoint: String = "") -> void:
	phase = value
	clock = 0.0
	retry = 0.0
	story.subtitle.text = ""
	if not checkpoint.is_empty():
		state.investment_stage = checkpoint
		_save()

func _task(value: String) -> void:
	var extra := ""
	if bool(state.get("suitcase_sale_paid",false)):
		extra = "\n%d CUP disponibles" % int(ledger.cash)
		if int(state.get("taxi_escrow",0))>0: extra += " · Reserva taxi: 20.000 CUP"
	story.objective.text = "CAPÍTULO 1 · LA ADAPTACIÓN\n"+value+extra

func cinematic() -> bool:
	return phase not in ["clean","return_door","outbound","shop","load","return","unload","neighbor","table_room","table_carry","done"]

func handle_look(relative: Vector2) -> void:
	if phase=="ride" and is_instance_valid(ride_view):
		ride_look.x = clampf(ride_look.x-relative.x*.003,-1.85,1.85)
		ride_look.y = clampf(ride_look.y-relative.y*.003,-.60,.35)
		ride_view.rotation = Vector3(ride_look.y,PI+ride_look.x,0)
		return
	if cinematic(): return
	game.yaw -= relative.x*.003
	game.pitch = clampf(game.pitch-relative.y*.003,-1.35,.50)
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)

func _face(at: Vector3,pitch: float=-.10) -> void:
	var d: Vector3 = at-game.player.global_position
	game.yaw = atan2(d.x,d.z)+PI
	game.pitch = pitch
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)

func _near(at: Vector3,radius: float=1.5) -> bool:
	return game.player.global_position.distance_to(at)<radius

func _mark(at: Vector3) -> void:
	marker.global_position = at+Vector3.UP*(.65+sin(clock*3.0)*.10)
	marker.show()

func _walk(delta: float) -> void:
	var input: Vector2 = game._read_controls()
	var move := Vector3(input.x,0,input.y).normalized().rotated(Vector3.UP,game.yaw)
	var speed := 2.1 if carry_table else (3.0 if not carry.is_empty() else 4.2)
	game.player.velocity.x = move.x*speed
	game.player.velocity.z = move.z*speed
	if not game.player.is_on_floor(): game.player.velocity.y -= 18.0*delta
	else: game.player.velocity.y = 0.0
	var before: Vector3 = game.player.global_position
	game.player.move_and_slide()
	if is_instance_valid(actor) and actor.visible and _actor_overlaps_player(actor.global_position):
		if Vector2(before.x-actor.global_position.x,before.z-actor.global_position.z).length()>Vector2(game.player.global_position.x-actor.global_position.x,game.player.global_position.z-actor.global_position.z).length():
			game.player.global_position = before
			game.player.velocity = Vector3.ZERO

func _say(i: int) -> void:
	line = i
	var item: Array = LINES[i]
	story.subtitle.text = String(item[0])+": "+String(item[1])
	story.voice.stop()
	speech_left = float(item[2])+.35
	var path := "res://audio/chapter1/investment_%02d.mp3" % (i+1)
	var audio: AudioStreamMP3
	if FileAccess.file_exists(path): audio = AudioStreamMP3.load_from_file(path)
	elif ResourceLoader.exists(path): audio = load(path) as AudioStreamMP3
	if audio!=null and audio.get_length()>0.0:
		audio.loop = false
		story.voice.stream = audio
		story.voice.play()
		speech_left = audio.get_length()+.35
	else: print("MyCity: falta grabación ",path)

func _dialogue(start: int,last: int,next: String) -> void:
	_set_phase("dialogue")
	state.dialogue_end = last
	after_talk = next
	story.objective.text = ""
	_say(start)

func _talk_tick(delta: float) -> void:
	var speaker: Person = clerk if line in [6,7,8] else actor
	if is_instance_valid(speaker) and speaker.visible:
		speaker.animate(delta,false)
		_face(speaker.global_position+Vector3.UP*1.45)
		var to_player: Vector3 = game.player.global_position-speaker.global_position
		speaker.rotation.y = lerp_angle(speaker.rotation.y,atan2(to_player.x,to_player.z),minf(1.0,delta*5.0))
		if String(LINES[line][0])!="Tú":
			speaker.arms[1].rotation.x = -.30+.10*sin(clock*5.0)
	if speech_left>0.0: return
	if line==7:
		_set_phase("thinking")
		return
	if line<int(state.dialogue_end):
		if line==1 and is_instance_valid(money_prop):
			money_prop.queue_free()
			money_prop = null
		if line==12: _make_money()
		_say(line+1)
		return
	_after_dialogue()

func _after_dialogue() -> void:
	match after_talk:
		"clean": _set_phase("clean","clean")
		"outbound":
			if is_instance_valid(money_prop): money_prop.queue_free()
			money_prop = null
			_set_phase("outbound","outbound")
			_task("Sal de casa con Albertico y sube al taxi.")
		"load": _purchase()
		"unload":
			_set_phase("unload","unload")
			_task("Descarga las cajas y guárdalas en la cocina.")
		"neighbor":
			_set_phase("neighbor","neighbor")
			_task("Sigue a Albertico hasta su casa.")
		"finish": _finish()

func _seed_dirt() -> void:
	# Clusters along accessible paths in all rooms. Save exactly the initial
	# cells so later dust and paint cannot change the completion denominator.
	var centers := [Vector2(-2.7,3.6),Vector2(-1.5,4.8),Vector2(-2.1,1.0),Vector2(-5.3,-.1),Vector2(-3.2,-1.65),Vector2(-2.0,-3.4),Vector2(-3.1,-4.0),Vector2(1.4,4.5),Vector2(2.0,1.1),Vector2(3.8,-1.0),Vector2(2.3,-4.5),Vector2(4.8,-4.45),Vector2(5.3,-3.85)]
	for center in centers:
		for x in range(-2,3):
			for z in range(-2,3):
				if x*x+z*z>5: continue
				var k: String = game.garage._floor_key(Vector3(center.x+float(x)*.24,110,center.y+float(z)*.24))
				if k.is_empty() or dirt_keys.has(k): continue
				dirt_keys.append(k)
				game.garage.state.floor_marks[k] = "dirt"
	game.garage._refresh_floor_marks()
	game.garage._save()
	state.investment_dirt = dirt_keys
	_save()

func _clean_ratio() -> float:
	var left := 0
	for k in dirt_keys:
		if game.garage.state.floor_marks.has(k): left += 1
	return 1.0-float(left)/float(maxi(1,dirt_keys.size()))

func _clean_tick(delta: float) -> void:
	var broom: Node3D = game.garage.resting_broom
	if String(game.garage.state.paint_tool)!="broom":
		_task("Recoge la escoba.")
		_mark(broom.global_position+Vector3.UP*.8)
		story.subtitle.text = "[E] Recoger escoba" if game.garage._near_broom(game.player.global_position) else ""
	else:
		# Use the real sweeping tool and floor ray, not a timed fake completion.
		game.garage._tick_home_paint(delta)
		var ratio := _clean_ratio()
		_task("Limpia la casa · %d%% / 80%%" % roundi(ratio*100.0))
		story.subtitle.text = "Mira al piso y mantén clic izquierdo para barrer."
		if ratio>=.80:
			game.garage._stop_home_paint()
			game.garage._save()
			state.investment_stage = "return_door"
			game.business.life.state.minutes = fposmod(float(game.business.life.state.minutes)+120.0,1440.0)
			_save()
			_set_phase("two_hours")

func _actor_overlaps_player(at: Vector3, minimum: float = 1.10) -> bool:
	var player_at: Vector3 = game.player.global_position-Vector3.UP*.86
	return absf(at.y-player_at.y)<1.6 and Vector2(at.x-player_at.x,at.z-player_at.z).length()<minimum

func _separate_actor_position(at: Vector3) -> Vector3:
	if not _actor_overlaps_player(at,1.45): return at
	var player_at: Vector3 = game.player.global_position-Vector3.UP*.86
	for radius in [1.65,2.2,3.0,4.0]:
		for i in range(12):
			var angle := float(i)*TAU/12.0
			var candidate := player_at+Vector3(cos(angle),0,sin(angle))*float(radius)
			if at.y>70.0: candidate.y = at.y
			else: candidate = game.yordi_mission._ground(candidate,false)
			if not candidate.is_finite() or _actor_overlaps_player(candidate,1.45): continue
			if not world.pedestrian_segment_clear(candidate,candidate): continue
			if not world.pedestrian_space_clear(actor,candidate,.7,false): continue
			return candidate
	return Vector3.INF

func _spawn_actor(at: Vector3) -> void:
	if not is_instance_valid(actor):
		actor = Person.new()
		add_child(actor)
		actor.setup(810)
		actor.remove_from_group("social_people")
		actor.remove_from_group("pedestrian_spacing")
	var safe := _separate_actor_position(at)
	if not safe.is_finite():
		actor.global_position = at
		actor_reposition_pending = true
		actor.hide()
		return
	actor_reposition_pending = false
	actor.global_position = safe
	actor.show()

func _door_return() -> void:
	_spawn_actor(Vector3(-.7,110,5.5))
	game.garage.set_guest_door(true)
	game.player.global_position = Vector3(-.7,110.86,3.3)
	_set_phase("enter_actor")

func _credit() -> void:
	if not bool(state.get("suitcase_sale_paid",false)):
		ledger.cash += 150000
		state.suitcase_sale_paid = true
		state.albertico_sale_pending = false
		_save()

func _factory_door() -> Vector3:
	var f: Dictionary = world.food_factory
	return Vector3(f.center)+Basis(f.basis)*Vector3(0,0,4.45)

func _house_out() -> Vector3:
	return Vector3(story.home.door)+Basis(story.home.basis).z*.9

func _site(shop: bool) -> Dictionary:
	if shop:
		return {"door":_factory_door(),"road":world.food_factory.road,"edge":world.food_factory.get("edge",{})}
	return story.home

func _berths(site: Dictionary) -> Array:
	var result: Array = []
	var pin: Vector3 = site.road
	var door: Vector3 = site.door
	var data = world.geography
	var edges: Array = data.roads_near(pin,32.0)
	var frontage: Dictionary = site.get("edge",{})
	if not frontage.is_empty(): edges.push_front(frontage)
	var seen: Dictionary = {}
	for edge in edges:
		if not bool(edge.get("driveable",false)): continue
		if not frontage.is_empty() and String(edge.get("name",""))!=String(frontage.get("name","")): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var center := Geometry3D.get_closest_point_to_segment(pin,a,b)
		if center.distance_to(pin)>18.0 or center.distance_to(door)>30.0: continue
		for pair in [[String(edge.a_id),String(edge.b_id)],[String(edge.b_id),String(edge.a_id)]]:
			var entry: String = pair[0]
			var exit_id: String = pair[1]
			var key := entry+":"+exit_id
			if seen.has(key): continue
			seen[key] = true
			if not data.graph.get(entry,[]).has(exit_id): continue
			var start: Vector3 = data.points[entry]
			var finish: Vector3 = data.points[exit_id]
			var direction := (finish-start).normalized()
			var side := Vector3(-direction.z,0,direction.x)
			if side.dot(door-center)<=0.0: continue
			var offset: float = data.lane_distance(edge,1.90,true)
			for shift in [0.0,-6.0,6.0,-12.0,12.0]:
				var requested := center+direction*float(shift)+side*offset
				var berth: Vector3 = world.street_geometry.safe_stop_on_edge(start,finish,requested,4.8,1.9)
				if not world.street_geometry.intersection_clear_for_stop(berth,4.8,1.9): continue
				if not Bypass._on_road(world.street_geometry,berth,direction,1.9,4.8): continue
				if berth.distance_to(door)>32.0: continue
				result.append({"p":berth,"d":direction,"entry":entry,"exit":exit_id,"point":berth-side*offset,"rank":berth.distance_to(pin)})
	result.sort_custom(func(a,b): return float(a.rank)<float(b.rank))
	return result

func _park_cab(shop: bool) -> bool:
	if not cab.is_empty() and is_instance_valid(cab.get("body")): return true
	for option in _berths(_site(shop)):
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.94,1.8,4.9)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.transform = Transform3D(Basis(Vector3.UP,atan2(option.d.x,option.d.z)),Vector3(option.p)+Vector3.UP*.92)
		q.collision_mask = 1|4|8|32
		if not get_world_3d().direct_space_state.intersect_shape(q,1).is_empty(): continue
		var body: CharacterBody3D = game.taxis._make_taxi(game.taxis.taxis.size())
		body.global_position = Vector3(option.p)+Vector3.UP*.045
		body.rotation.y = atan2(option.d.x,option.d.z)
		body.add_to_group("traffic_parked")
		cab = {"body":body,"next_node":option.exit,"path":[],"index":0,"speed":0.0,"blocked":0.0,"goal":"","label":"","note":"","albertico_reserved":true,"chapter_side_only":true}
		game.taxis.taxis.append(cab)
		_build_cabin(body)
		return true
	return false

func _build_cabin(body: CharacterBody3D) -> void:
	for child in body.get_children():
		if child is MeshInstance3D or child is Label3D: child.hide()
	var visual := Node3D.new()
	body.add_child(visual)
	# Reuse the actual airport cabin, with doors and a hollow trunk, but keep
	# its old arrival-story references intact.
	var previous_lid: Node3D = story.lid
	var previous_door: Node3D = story.door
	var previous_other: Node3D = story.opposite_door
	story._car_shell(visual,Color("#d6ad47"),true)
	cab_lid = story.lid
	story.lid = previous_lid
	story.door = previous_door
	story.opposite_door = previous_other
	story._box(visual,Vector3(0,1.75,-.1),Vector3(.54,.18,.30),Color("#ead16e"))
	story._label3(visual,"TAXI",Vector3(0,1.75,.061),.003,Color("#222222"))
	ride_driver = Person.new()
	body.add_child(ride_driver)
	ride_driver.setup(933)
	ride_driver.remove_from_group("social_people")
	ride_driver.remove_from_group("pedestrian_spacing")
	_seat(ride_driver,Vector3(.39,.17,.19))

func _seat(person: Person,at: Vector3) -> void:
	person.position = at
	person.rotation = Vector3.ZERO
	person.scale = Vector3.ONE*.74
	for leg in person.limbs: leg.rotation.x = -1.45
	for knee in person.knees: knee.rotation.x = 1.35
	for arm in person.arms: arm.rotation.x = -1.15

func _start_ride(outbound: bool) -> void:
	if cab.is_empty() or not game.taxis.passenger.is_empty(): return
	for option in _berths(_site(outbound)):
		var ids: Array[String] = game.taxis.router.path(String(cab.next_node),String(option.entry))
		if ids.is_empty(): continue
		game.taxis.selected = cab
		game.taxis.selected_route = {"id":option.exit,"path":ids,"label":"MIPYME" if outbound else "Casa alquilada","note":"","point":option.point,"distance":game.taxis.router.route_length(ids),"partial":true,"entry":option.entry,"exit":option.exit,"story_berth":option.p}
		game.taxis.trip_confirmed = true
		if not game.taxis.prepare_trip(): continue
		ride_out = outbound
		if is_instance_valid(cab_lid): cab_lid.rotation.x = 0.0
		actor_scale = actor.scale
		actor.reparent(cab.body,false)
		_seat(actor,Vector3(-.38,.12,-.72))
		actor_reposition_pending = false
		actor.show()
		for arm in actor.arms: arm.rotation.x = -.10
		game._start_taxi_ride()
		ride_view = Camera3D.new()
		cab.body.add_child(ride_view)
		# Rear bench: player and Albertico have independent seat positions.
		ride_view.position = Vector3(.36,1.34,-.72)
		ride_look = Vector2(0,-.03)
		ride_view.rotation = Vector3(ride_look.y,PI,0)
		ride_view.near = .045
		ride_view.fov = 70
		ride_view.far = 320
		ride_view.make_current()
		_set_phase("ride")
		_task("Viaje con Albertico · Mueve el mouse para mirar")
		return
	game.taxis.close_dialog()
	story.subtitle.text = "No hay una ruta segura a esa acera. Pulsa E para volver a intentar."

func _ride_tick(delta: float) -> void:
	if game.taxis.passenger.is_empty(): return
	game.player.global_position = cab.body.global_position+Vector3.UP*.8
	if not game.taxis.arrived: return
	# The service prioritizes the curb side and will wait for a safe exit.
	retry += delta
	if retry<.20: return
	retry = 0.0
	if not game._leave_taxi(): return
	if is_instance_valid(ride_view): ride_view.queue_free()
	game.play_camera.make_current()
	actor.reparent(self,true)
	actor.scale = actor_scale
	actor.rotation.x = 0.0
	for leg in actor.limbs: leg.rotation.x = 0.0
	for knee in actor.knees: knee.rotation.x = 0.0
	for arm in actor.arms: arm.rotation.x = 0.0
	var at: Vector3 = game.yordi_mission._near_ground(game.player.global_position-Vector3.UP*.86,actor,4.0)
	if at.is_finite(): _spawn_actor(at)
	else: _spawn_actor(game.player.global_position-Vector3.UP*.86+Vector3(.9,0,0))
	game.first_person = true
	game._apply_camera_mode()
	if ride_out:
		_set_phase("shop","shop")
		_task("Entra en la MIPYME y habla con el vendedor.")
	else:
		# Persist the fare and arrival checkpoint together, so a reload cannot charge twice.
		state.investment_stage = "unload"
		if not bool(state.get("investment_return_taxi_paid",false)):
			ledger.cash -= RETURN_TAXI_FARE
			ledger.expenses += RETURN_TAXI_FARE
			state.investment_return_taxi_paid = true
			fare_notice.text = "Taxi: -1.000 CUP\nSaldo: %d CUP" % int(ledger.cash)
			fare_notice_left = 6.0
			fare_notice.show()
		_dialogue(9,9,"unload")
		_task("Llegaste a casa con Albertico.")
		if is_instance_valid(cab_lid): cab_lid.rotation.x = 1.15
		_save()

func _shop_clerk() -> Person:
	for n in get_tree().get_nodes_in_group("mission_merchant_visuals"):
		if n is Person and n.style_id==813: return n
	return null

func _box_states() -> Dictionary:
	if not state.has("investment_boxes"): state.investment_boxes = {}
	return state.investment_boxes

func _purchase() -> void:
	if not bool(state.get("investment_paid",false)):
		if ledger.cash<133000:
			_set_phase("shop","shop")
			_task("No hay suficiente dinero para la compra y la reserva del taxi.")
			return
		ledger.cash -= 133000
		ledger.expenses += 113000
		state.taxi_escrow = 20000
		state.investment_paid = true
		for key in KEYS: _box_states()[key] = "shelf"
		_save()
	_set_phase("load","load")
	_rebuild_boxes()
	_task("Lleva dos cajas al maletero. Albertico carga la de aceite.")

func _rebuild_boxes() -> void:
	if is_instance_valid(cab_lid): cab_lid.rotation.x = 1.15 if phase in ["load","unload","return"] else 0.0
	for key in boxes:
		if is_instance_valid(boxes[key]): boxes[key].queue_free()
	boxes.clear()
	for i in range(KEYS.size()):
		var key: String = KEYS[i]
		var location := String(_box_states().get(key,""))
		if location=="shelf":
			var node: Node3D = game.business._crate(game.business.crate_rack,Vector3(-.56+float(i)*.56,.17,0),key)
			boxes[key] = node
		elif location=="taxi" and not cab.is_empty():
			var node: Node3D = game.business._crate(cab.body,Vector3(-.50+float(i)*.50,.76,-1.65),key)
			node.scale = Vector3.ONE*.90
			boxes[key] = node
		elif location=="stored":
			if key=="aceite":
				var node: Node3D = game.business._crate(game.garage.interior,Vector3(-6.35,1.47,.52),key)
				boxes[key] = node
			else: legacy.show_rental_stock(key,false)
	if not carry.is_empty() and boxes.has(carry): boxes[carry].hide()
	if is_instance_valid(helper_box) and boxes.has("aceite"): boxes["aceite"].hide()

func _take(key: String) -> void:
	carry = key
	if boxes.has(key): boxes[key].hide()
	held = game.business._crate(game.play_camera,Vector3(.19,-.48,-.80),key)
	held.rotation_degrees = Vector3(-8,-8,0)

func _deposit(where: String) -> void:
	if carry.is_empty(): return
	var key := carry
	_box_states()[key] = where
	if where=="stored" and key!="aceite": legacy.show_rental_stock(key)
	carry = ""
	if is_instance_valid(held): held.queue_free()
	held = null
	_save()
	_rebuild_boxes()

func _all_at(where: String) -> bool:
	for key in KEYS:
		if String(_box_states().get(key,""))!=where: return false
	return true

func _trunk() -> Vector3:
	return cab.body.to_global(Vector3(0,.86,-2.5))

func _follow(delta: float,at: Vector3,radius: float=1.3) -> bool:
	if not is_instance_valid(actor): return false
	if actor.global_position.y>70.0:
		if actor.global_position.distance_to(at)<radius: return true
		return actor.walk_to(at,delta,1.6)
	return game.yordi_mission._walk(actor,at,delta,2.2,radius)

func _actor_follow(delta: float) -> void:
	if not is_instance_valid(actor) or not actor.visible: return
	var at: Vector3 = game.player.global_position-Vector3.UP*.86
	if absf(at.y-actor.global_position.y)>8.0: return
	if actor.global_position.distance_to(at)>2.5: _follow(delta,at,1.9)
	else: _wait_naturally(delta)

func _helper_trunk_ground() -> Vector3:
	var body: CharacterBody3D = cab.body
	for x in [-1.55,-2.25,-3.0,-4.0,1.55,2.25]:
		var candidate: Vector3 = game.yordi_mission._ground(body.to_global(Vector3(float(x),0,-2.1)),false)
		if candidate.is_finite(): return candidate
	return Vector3.INF

func _helper_walk(delta: float,target: Vector3,inside_house: bool = false) -> bool:
	if not target.is_finite(): return false
	if actor.global_position.distance_to(target)<.85: return true
	if inside_house:
		# A known free corridor around the sofa and dining table.
		if helper_path.is_empty():
			helper_path = PackedVector3Array([Vector3(-2.35,110,3.9),Vector3(-2.35,110,.35),Vector3(-5.32,110,.35),target])
			helper_index = 0
		if helper_index>=helper_path.size(): return true
		if actor.walk_to(helper_path[helper_index],delta,1.8): helper_index += 1
		return helper_index>=helper_path.size()
	if not helper_goal.is_finite() or helper_goal.distance_to(target)>.5:
		helper_goal = target
		helper_path = PackedVector3Array()
		helper_index = 0
	if helper_path.is_empty():
		helper_path = legacy._local_path(actor.global_position,target)
		helper_index = 0
	if helper_path.is_empty(): return _follow(delta,target,1.0)
	if helper_index>=helper_path.size(): return true
	var next := helper_path[helper_index]
	var step := actor.global_position.move_toward(next,2.2*delta)
	if world.pedestrian_segment_clear(actor.global_position,step) and world.pedestrian_space_clear(actor,step,.5):
		if actor.walk_to(next,delta,2.2): helper_index += 1
	else: actor.animate(delta,false)
	return helper_index>=helper_path.size()

func _clear_helper_path() -> void:
	helper_path = PackedVector3Array()
	helper_index = 0
	helper_goal = Vector3.INF

func _wait_naturally(delta: float) -> void:
	if not is_instance_valid(actor) or not actor.visible: return
	waiting_clock += delta
	# Ease out of the last walking/carrying pose, breathe and blink.
	actor.animate(delta,false)
	var blend := minf(1.0,delta*3.5)
	actor.rotation.x = lerpf(actor.rotation.x,sin(waiting_clock*1.65)*.012,blend)
	var target: Vector3 = game.player.global_position
	if fposmod(waiting_clock,10.0)>5.5 and not cab.is_empty() and is_instance_valid(cab.get("body")) and actor.global_position.y<70.0:
		target = cab.body.global_position
	var direction: Vector3 = target-actor.global_position
	if absf(direction.y)<3.0 and Vector2(direction.x,direction.z).length()>1.1:
		var look_yaw := atan2(direction.x,direction.z)+sin(waiting_clock*.65)*.12
		actor.rotation.y = lerp_angle(actor.rotation.y,look_yaw,minf(1.0,delta*1.4))
	# Occasional small relaxed arm movement; never fake walking in place.
	if actor.carried==null and actor.arms.size()>1:
		var gesture := pow(maxf(0.0,sin(waiting_clock*.65)),8.0)*.23
		actor.arms[0].rotation.x = lerpf(actor.arms[0].rotation.x,-gesture,blend)
		actor.arms[1].rotation.x = lerpf(actor.arms[1].rotation.x,sin(waiting_clock*1.3)*.045,blend)

func _helper_tick(delta: float,unloading: bool) -> void:
	var key := "aceite"
	var from := "taxi" if unloading else "shelf"
	var dest := "stored" if unloading else "taxi"
	if not is_instance_valid(actor): return
	if String(_box_states().get(key,""))!=from or cab.is_empty():
		_wait_naturally(delta)
		return
	waiting_clock = 0.0
	helper_clock += delta
	helper_elapsed += delta
	if helper_stage.is_empty():
		var target: Vector3 = _helper_trunk_ground() if unloading else Vector3(world.food_factory.pickup)-Vector3.UP*.86
		if not _helper_walk(delta,target): 
			# If local traffic blocks him, retry from a verified nearby ground
			# point off camera rather than locking the entire chapter.
			if helper_elapsed<24.0 or not target.is_finite(): return
			var safe: Vector3 = game.yordi_mission._near_ground(target,actor,2.5)
			if not safe.is_finite(): return
			if game.player.global_position.distance_to(safe)<5.0: return
			actor.global_position = safe
		helper_stage = "lift"
		helper_clock = 0.0
		helper_elapsed = 0.0
		_clear_helper_path()
		return
	if helper_stage=="lift":
		var bend := sin(clampf(helper_clock/.9,0,1)*PI)*.33
		actor.rotation.x = bend
		for arm in actor.arms: arm.rotation.x = -.85
		for knee in actor.knees: knee.rotation.x = bend*1.8
		if helper_clock<.9: return
		actor.rotation.x = 0.0
		if boxes.has(key): boxes[key].hide()
		helper_box = game.business._crate(actor,Vector3(0,.99,.35),key)
		actor.carried = helper_box
		helper_stage = "carry"
		helper_clock = 0.0
		helper_elapsed = 0.0
		return
	if unloading:
		if actor.global_position.y<70.0:
			if not _helper_walk(delta,_house_out()): return
			_spawn_actor(Vector3(-2.35,110,3.9))
			_clear_helper_path()
			return
		if not _helper_walk(delta,OIL-Vector3.UP*.86,true): return
	else:
		if not _helper_walk(delta,_helper_trunk_ground()): return
	if is_instance_valid(helper_box): helper_box.queue_free()
	actor.carried = null
	helper_box = null
	helper_stage = ""
	helper_elapsed = 0.0
	_clear_helper_path()
	_box_states()[key] = dest
	_save()
	_rebuild_boxes()
	_wait_naturally(delta)

func _neighbor_lead(delta: float) -> void:
	if not is_instance_valid(actor) or not actor.visible: return
	if actor.global_position.y>70.0:
		# Reverse the same kitchen corridor used to carry the oil, avoiding the sofa.
		if neighbor_exit_path.is_empty():
			neighbor_exit_path = PackedVector3Array()
			if actor.global_position.x< -3.0:
				neighbor_exit_path.append(Vector3(-5.32,110,.35))
				neighbor_exit_path.append(Vector3(-2.35,110,.35))
			neighbor_exit_path.append(Vector3(-2.35,110,3.9))
			neighbor_exit_path.append(Vector3(-.7,110,4.95))
			neighbor_exit_index = 0
		if neighbor_exit_index<neighbor_exit_path.size():
			var goal: Vector3 = neighbor_exit_path[neighbor_exit_index]
			var step: Vector3 = actor.global_position.move_toward(goal,1.8*delta)
			if _actor_overlaps_player(step):
				_wait_naturally(delta)
				return
			if actor.walk_to(goal,delta,1.8): neighbor_exit_index += 1
			return
		# The interior is a separate world: transfer only at the logical doorway.
		game.garage.set_guest_door(true)
		var basis: Basis = story.home.basis
		var outside: Vector3 = _house_out()
		for offset in [Vector2(1.65,.55),Vector2(-1.65,.55),Vector2(0,2.2),Vector2(2.5,1.0),Vector2(-2.5,1.0)]:
			var point: Vector3 = game.yordi_mission._ground(outside+basis.x*offset.x+basis.z*offset.y)
			if not point.is_finite() or _actor_overlaps_player(point,1.45): continue
			if not world.pedestrian_space_clear(actor,point,.7,false): continue
			_spawn_actor(point)
			game.garage.set_guest_door(false)
			return
		_wait_naturally(delta)
		return
	if game.garage.inside or neighbor.is_empty():
		_wait_naturally(delta)
		return
	var player_at: Vector3 = game.player.global_position-Vector3.UP*.86
	if actor.global_position.distance_to(player_at)>7.0:
		_wait_naturally(delta)
		return
	var destination: Vector3 = Vector3(neighbor.door)+Vector3(neighbor.normal)*1.0
	if _follow(delta,destination,1.0): _wait_naturally(delta)

func _toggle_home() -> bool:
	if game.garage.inside and _near(ENTRY,1.8):
		game.garage._exit()
		if not game.garage.inside and phase!="neighbor" and (phase!="unload" or _all_at("stored")):
			var at: Vector3 = game.yordi_mission._near_ground(_house_out(),actor,4.0)
			if at.is_finite(): _spawn_actor(at)
		return true
	if not game.garage.inside and story._house_near():
		game.garage._enter()
		if game.garage.inside and (phase!="unload" or _all_at("stored")): _spawn_actor(Vector3(-2.35,110,3.9))
		return true
	return false

func _money() -> void:
	var node := Node3D.new()
	actor.add_child(node)
	node.position = Vector3(.18,1.12,.31)
	game.business._box(node,Vector3.ZERO,Vector3(.18,.035,.09),Color("#a0aa79"))
	money_prop = node

func _make_money() -> void:
	if not is_instance_valid(actor): return
	_money()
	var goal := money_prop.transform
	money_prop.global_position = game.play_camera.global_position-game.play_camera.global_basis.z*.65+Vector3.DOWN*.28
	var tween := create_tween()
	tween.tween_property(money_prop,"transform",goal,.85).set_trans(Tween.TRANS_SINE)

func _enter_neighbor() -> void:
	if neighbor.is_empty(): return
	legacy._build_room()
	table = legacy.table
	game.player.global_position = TABLE_ROOM+Vector3(0,.86,1.6)
	_spawn_actor(TABLE_ROOM+Vector3(.9,0,.3))
	_set_phase("table_room","table_room")
	_task("Recoge la mesa con Albertico.")

func _lift_table() -> void:
	carry_table = true
	if is_instance_valid(table): table.reparent(self,true)
	_set_phase("table_carry","table_carry")

func _table_tick(delta: float) -> void:
	if not is_instance_valid(table): return
	var forward: Vector3 = -game.pivot.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	table.global_position = game.player.global_position+forward*.82-Vector3.UP*.35
	table.rotation.y = atan2(forward.x,forward.z)+PI*.5
	var target: Vector3 = game.player.global_position+forward*1.55-Vector3.UP*.86
	actor.global_position = target
	actor.rotation.y = atan2(-forward.x,-forward.z)
	actor.animate(delta,game.player.velocity.length()>.15)
	for arm in actor.arms: arm.rotation.x = -1.0
	if game.player.global_position.y>70.0 and _near(TABLE_ROOM+Vector3(0,.86,2.0),1.1):
		var at: Vector3 = game.yordi_mission._near_ground(Vector3(neighbor.door)+Vector3(neighbor.normal)*.9,actor,3.0)
		if at.is_finite(): game.player.global_position = at+Vector3.UP*.86
	_task("Lleva la mesa hasta el punto de venta frente a tu casa.")
	if game.player.global_position.y<70.0: _mark(_stall_position()+Vector3.UP*.9)

func _stall_position() -> Vector3:
	var door: Vector3 = story.home.door
	var basis: Basis = story.home.basis
	return door+basis.x*1.85+basis.z*.55

static func restore_business(parent_story) -> void:
	var game = parent_story.game
	var business = game.business
	if not is_instance_valid(business.stand) or not is_instance_valid(business.albertico): return
	var home: Dictionary = parent_story.home
	var basis: Basis = home.basis
	var at: Vector3 = Vector3(home.door)+basis.x*1.85+basis.z*.55
	business.stand.global_position = at
	business.stand.rotation.y = basis.get_euler().y
	business.albertico.global_position = at-basis.z*.65
	business.albertico.rotation.y = basis.get_euler().y
	if business.first_story!=null:
		business.first_story.original_actor = business.albertico.global_position
		business.first_story.original_angle = business.albertico.rotation.y
		for key in ["pollo","huevos"]:
			if int(business.ledger.stock.get(key,0))>0: business.first_story.show_rental_stock(key,false)
	business._sync_visuals()

func _finish() -> void:
	if not bool(state.get("investment_complete",false)):
		for key in KEYS:
			ledger.stock[key] = int(ledger.product(key).units)
			ledger.low_alert[key] = false
		ledger.stage = 4
		ledger.expenses += int(state.get("taxi_escrow",0))
		state.taxi_escrow = 0
		# The player has entrusted the payment; don't claim the first driver
		# has physically collected it until a later collection scene.
		state.taxi_payment_pending = true
		state.taxi_money_with_albertico = true
		state.investment_complete = true
		state.investment_stage = "done"
		ledger.add_message("Albertico","Ya tenemos mercancía. Te aviso cuando quede poca.")
		_save()
	if is_instance_valid(actor): actor.queue_free()
	if is_instance_valid(table): table.queue_free()
	if is_instance_valid(cab_lid): cab_lid.rotation.x = 0.0
	if not cab.is_empty():
		cab.albertico_reserved = false
		cab.chapter_side_only = false
	restore_business(story)
	game.first_person = old_first
	game._apply_camera_mode()
	_set_phase("done")
	story.investment_finished()
	game.business._notify("MISIÓN COMPLETADA · Mi primera inversión")

func _restore() -> void:
	match resume:
		"clean":
			if not game.garage.inside: game.garage._enter()
			if _clean_ratio()>=.80: _set_phase("return_door","return_door")
			else: _dialogue(0,0,"clean")
		"return_door": _set_phase("return_door","return_door")
		"outbound":
			_spawn_actor(Vector3(-2.35,110,3.9))
			_set_phase("outbound","outbound")
		"shop","load","return":
			if world.food_factory.is_empty(): return
			if not _park_cab(true): return
			game.garage.inside = false
			var f: Dictionary = world.food_factory
			game.player.global_position = Vector3(f.center)+Basis(f.basis)*Vector3(0,.96,3.55)
			_spawn_actor(Vector3(f.center)+Basis(f.basis)*Vector3(1.8,.1,3.2))
			_set_phase(resume,resume)
			_rebuild_boxes()
		"unload":
			if not _park_cab(false): return
			if String(_box_states().get("aceite",""))=="stored": _spawn_actor(Vector3(-5.28,110,.87))
			else:
				var at: Vector3 = game.yordi_mission._near_ground(_house_out(),null,4.0)
				if not at.is_finite(): return
				_spawn_actor(at)
			_set_phase("unload","unload")
			_rebuild_boxes()
		"neighbor","table_room","table_carry","finish":
			_spawn_actor(Vector3(-2.35,110,3.9))
			_set_phase("neighbor","neighbor")
		_: _set_phase("return_door","return_door")

func interact() -> void:
	if cinematic(): return
	match phase:
		"clean":
			if String(game.garage.state.paint_tool)!="broom" and game.garage._near_broom(game.player.global_position): game.garage._take_home_tool("broom")
		"return_door":
			if _near(ENTRY,1.7): _door_return()
		"outbound","return":
			if phase=="outbound" and _toggle_home(): return
			if not cab.is_empty() and _near(cab.body.global_position+Vector3.UP*.86,4.0): _start_ride(phase=="outbound")
		"shop":
			if _near(world.food_factory.counter,2.0):
				clerk = _shop_clerk()
				_dialogue(6,8,"load")
		"load":
			if carry.is_empty():
				for key in ["pollo","huevos"]:
					if String(_box_states().get(key,""))=="shelf" and boxes.has(key) and _near(boxes[key].global_position,1.8):
						_take(key)
						break
			elif _near(_trunk(),2.4): _deposit("taxi")
		"unload":
			if _toggle_home(): return
			if game.garage.inside and not carry.is_empty() and _near(OIL if carry=="aceite" else FRIDGE,1.65): _deposit("stored")
			elif not game.garage.inside and carry.is_empty() and not cab.is_empty() and _near(_trunk(),2.4):
				for key in ["pollo","huevos"]:
					if String(_box_states().get(key,""))=="taxi":
						_take(key)
						break
		"neighbor":
			if game.garage.inside and _toggle_home(): return
			if not neighbor.is_empty() and _near(Vector3(neighbor.door)+Vector3.UP*.86,2.2): _enter_neighbor()
		"table_room":
			if is_instance_valid(table) and _near(table.global_position+Vector3.UP*.86,2.0): _lift_table()
		"table_carry":
			if game.player.global_position.y<70.0 and _near(_stall_position()+Vector3.UP*.86,2.1):
				carry_table = false
				table.global_position = _stall_position()
				actor.global_position = _stall_position()-Basis(story.home.basis).z*.7
				state.investment_stage = "finish"
				_save()
				_dialogue(11,14,"finish")

func tick(delta: float) -> void:
	clock += delta
	if fare_notice_left>0.0:
		fare_notice_left = maxf(0.0,fare_notice_left-delta)
		if fare_notice_left<=0.0: fare_notice.hide()
	speech_left = maxf(0.0,speech_left-delta)
	marker.hide()
	if not cinematic(): _walk(delta)
	else: game.player.velocity = Vector3.ZERO
	match phase:
		"boot":
			if clock>.4:
				clock = 0.0
				_restore()
		"dialogue": _talk_tick(delta)
		"thinking":
			if is_instance_valid(clerk):
				clerk.animate(delta,false)
				clerk.arms[1].rotation.x = -.95
				clerk.rotation.y += sin(clock*2.0)*delta*.12
				_face(clerk.global_position+Vector3.UP*1.45)
			if clock>=3.0:
				_set_phase("dialogue")
				_say(8)
		"clean": _clean_tick(delta)
		"two_hours":
			story.fade.color.a = clampf(clock*2.0,0,1) if clock<2.8 else maxf(0.0,1.0-(clock-2.8)*2.0)
			if clock>.55 and clock<2.8:
				story.title.text = "2 HORAS DESPUÉS..."
				story.title.show()
			else: story.title.hide()
			if clock>3.4:
				_set_phase("return_door","return_door")
				if is_instance_valid(story.morning): story.morning._play_effect(story.morning.knock)
		"return_door":
			_task("Abre la puerta. Albertico ha vuelto.")
			_mark(ENTRY+Vector3.UP*.7)
			story.subtitle.text = "[E] Abrir puerta" if _near(ENTRY,1.7) else ""
		"enter_actor":
			_face(actor.global_position+Vector3.UP*1.45)
			if actor.walk_to(Vector3(-.7,110,4.95),delta,1.3):
				game.garage.set_guest_door(false)
				_credit()
				_money()
				_dialogue(1,5,"outbound")
		"outbound","return":
			if game.garage.inside:
				_task("Sal de casa con Albertico.")
				_mark(ENTRY)
				story.subtitle.text = "[E] Salir" if _near(ENTRY,1.8) else ""
			else:
				retry -= delta
				if cab.is_empty() and retry<=0.0:
					retry = 2.0
					_park_cab(phase=="return")
				_actor_follow(delta)
				if not cab.is_empty():
					_task("Sube al taxi con Albertico.")
					_mark(cab.body.global_position+Vector3.UP*1.9)
					story.subtitle.text = "[E] Subir al taxi" if _near(cab.body.global_position+Vector3.UP*.86,4.0) else ""
				else: _task("Esperando una parada segura para el taxi.")
		"ride": _ride_tick(delta)
		"shop":
			_actor_follow(delta)
			_mark(Vector3(world.food_factory.counter)+Vector3.UP*.7)
			story.subtitle.text = "[E] Hablar con el vendedor" if _near(world.food_factory.counter,2.0) else ""
		"load":
			_helper_tick(delta,false)
			if carry.is_empty():
				for key in ["pollo","huevos"]:
					if String(_box_states().get(key,""))=="shelf" and boxes.has(key):
						_mark(boxes[key].global_position)
						story.subtitle.text = "[E] Recoger caja de "+key
						break
			else:
				_mark(_trunk())
				story.subtitle.text = "[E] Cargar caja en el taxi"
			if _all_at("taxi"): _set_phase("return","return")
		"unload":
			_helper_tick(delta,true)
			if carry.is_empty() and not _all_at("stored"):
				if game.garage.inside: _mark(ENTRY)
				else: _mark(_trunk())
				story.subtitle.text = "[E] Salir por otra caja" if game.garage.inside else "[E] Recoger caja del taxi"
			elif not carry.is_empty():
				var target: Vector3 = OIL if carry=="aceite" else FRIDGE
				_mark(target if game.garage.inside else _house_out())
				story.subtitle.text = "[E] Guardar caja" if game.garage.inside else "[E] Entrar en casa"
			if _all_at("stored"):
				if game.garage.inside: _dialogue(10,10,"neighbor")
				else:
					_task("Entra a la casa. Albertico terminó de guardar la mercancía.")
					_mark(_house_out())
		"neighbor":
			_neighbor_lead(delta)
			if game.garage.inside:
				_mark(ENTRY)
				story.subtitle.text = "[E] Salir" if _near(ENTRY,1.8) else "Sigue a Albertico hacia la puerta."
			elif not neighbor.is_empty():
				_mark(Vector3(neighbor.door)+Vector3.UP)
				story.subtitle.text = "[E] Entrar a casa de Albertico" if _near(Vector3(neighbor.door)+Vector3.UP*.86,2.2) else "Sigue a Albertico."
			else: _task("No se encontró una puerta vecina accesible.")
		"table_room":
			_mark(table.global_position+Vector3.UP)
			story.subtitle.text = "[E] Levantar mesa entre los dos"
		"table_carry":
			_table_tick(delta)
			story.subtitle.text = "[E] Instalar mesa" if game.player.global_position.y<70.0 and _near(_stall_position()+Vector3.UP*.86,2.1) else ""

	# Final guard after scripted moves, checkpoint restoration and helper actions.
	if phase!="ride" and is_instance_valid(actor) and not actor.is_queued_for_deletion() and (actor_reposition_pending or (actor.visible and _actor_overlaps_player(actor.global_position))):
		var safe := _separate_actor_position(actor.global_position)
		if safe.is_finite():
			actor.global_position = safe
			actor_reposition_pending = false
			actor.show()
		else:
			actor_reposition_pending = true
			actor.hide()
