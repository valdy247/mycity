extends Node3D
# Chapter 1. Uses the normal Havana street graph and the airport taxi's cabin.
const Person = preload("res://street_person.gd")
const FARE_REVISION := 2
const FARE_LINES := [
	["Tú","Debo pagarle al taxista.",2.1],
	["Tú","Eh, pero espera. ¿Dónde está mi billetera? Carajo, la perdí en el avión.",5.6],
	["Tú","Mira, lo que pasa es que perdí mi billetera. Dame unos días, yo te voy a pagar esto.",6.5],
	["Chofer","Tranquilo, mi amigo. Llámame cuando lo tengas.",3.2]
]
var game
var service
var world
var state: Dictionary
var home: Dictionary
var house_arrow: Label3D
var arrow_clock := 0.0
const ARRIVAL_STOP_REVISION := 2
const ARRIVAL_PIN_LAT := 23.1223870
const ARRIVAL_PIN_LON := -82.3669249
var phase := "initial"
var cab: CharacterBody3D
var driver: Person
var cab_view: Camera3D
var lid: Node3D
var door: Node3D
var opposite_door: Node3D
var mats: Dictionary = {}
var unit_box := BoxMesh.new()
var luggage_mesh: ArrayMesh
var bags: Array[Node3D] = []
var layer: CanvasLayer
var fade: ColorRect
var title: Label
var subtitle: Label
var objective: Label
var voice: AudioStreamPlayer
var engine: AudioStreamPlayer
var line_index := 0
var line_left := 1.0
var line_active := false
var cinematic_clock := 0.0
var title_clock := 0.0
var arrival_wait := 0.0
var carry := -1
var dropped: Array = [false,false]
var look := Vector2.ZERO
var busy := false
var trunk_open := false
var fallback_voice := ""
var fare_index := 0
var fare_completed_lines := 0
var fare_audio_missing: Array[String] = []
var fare_clock := 0.0
var fare_wait := .6
var fare_active := false
var departure_origin := Vector3.ZERO
var departure_started := false
var departure_record: Dictionary = {}
var approach_cut_done := false

func active() -> bool:
	return phase!="done"

func cinematic() -> bool:
	return phase not in ["done","unload"]

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	service = game.taxis
	home = world.garage_home_site
	var data: Dictionary = game.business.ledger.life_data
	if not data.has("adaptation"): data.adaptation = {"step":0,"dropped":[false,false]}
	state = data.adaptation
	var saved: Array = state.get("dropped",[false,false])
	if saved.size()==2: dropped = [bool(saved[0]),bool(saved[1])]
	_make_ui()
	voice = AudioStreamPlayer.new()
	add_child(voice)
	voice.max_polyphony = 1
	var voices := DisplayServer.tts_get_voices_for_language("es")
	if not voices.is_empty(): fallback_voice = voices[0]
	_make_engine()
	game.garage.state.rented = true
	game.garage.state.house = true # Access to a rented home, not a purchased asset.
	if home.is_empty():
		_fail("No se encontró la casa existente en el mapa.")
		return
	_make_house_arrow()
	# Explicit arrival test resets only this mission's luggage/fare checkpoint.
	if OS.get_cmdline_user_args().has("--replay-home-arrival"):
		state.step = 0
		dropped = [false,false]
		state.fare_scene_done = false
		state.fare_lines_completed = 0
		state.taxi_payment_pending = false
	# Older completion flags did not certify the full farewell sequence.
	# Preserve the bags and balance, but replay the pending fare on resume.
	var replay_fare := OS.get_cmdline_user_args().has("--replay-fare")
	var verified_fare := bool(state.get("fare_scene_done",false)) and int(state.get("fare_revision",0))==FARE_REVISION and int(state.get("fare_lines_completed",0))==FARE_LINES.size()
	if int(state.get("step",0))>=2 and (not verified_fare or replay_fare):
		dropped = [true,true]
		state.step = 1 if state.get("cab",[]).size()==4 else 0
		state.fare_scene_done = false
		print("MyCity: restoring pending fare cinematic; both suitcases already delivered.")
	elif int(state.get("step",0))<2:
		state.fare_scene_done = false
	if int(state.get("step",0))>=2:
		phase = "done"
		_make_bags_at_home()
		game.garage._enter()
		layer.hide()
		return
	game.status.hide()
	game.reticle.hide()
	game.business.layer.hide()
	game.map_credit.hide()
	if int(state.get("step",0))==1 and int(state.get("arrival_stop_revision",0))==ARRIVAL_STOP_REVISION:
		_resume_arrival()
	else:
		_begin_ride()

func _make_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 85
	add_child(layer)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade = ColorRect.new()
	root.add_child(fade)
	fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade.color = Color.BLACK
	fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = Label.new()
	root.add_child(title)
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title.text = "CAPÍTULO 1\nLA ADAPTACIÓN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",44)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.hide()
	subtitle = Label.new()
	root.add_child(subtitle)
	subtitle.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle.offset_left = -460
	subtitle.offset_right = 460
	subtitle.offset_top = -132
	subtitle.offset_bottom = -66
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size",22)
	subtitle.add_theme_color_override("font_outline_color",Color.BLACK)
	subtitle.add_theme_constant_override("outline_size",6)
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	objective = Label.new()
	root.add_child(objective)
	objective.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	objective.offset_left = -400
	objective.offset_right = 400
	objective.offset_top = 24
	objective.offset_bottom = 90
	objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	objective.add_theme_font_size_override("font_size",18)
	objective.add_theme_color_override("font_outline_color",Color.BLACK)
	objective.add_theme_constant_override("outline_size",5)
	objective.mouse_filter = Control.MOUSE_FILTER_IGNORE

func _fail(message: String) -> void:
	phase = "error"
	fade.color = Color.BLACK
	title.hide()
	subtitle.text = message+"\nReinicia el juego para volver a intentar la ruta."
	push_error("MyCity adaptation: "+message)

func _make_engine() -> void:
	engine = AudioStreamPlayer.new()
	add_child(engine)
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 16000
	var data := PackedByteArray()
	data.resize(64000)
	for i in range(32000):
		var t := float(i)/16000.0
		var value := sin(TAU*48.0*t)*.035+sin(TAU*96.0*t)*.009
		data.encode_s16(i*2,roundi(value*32767.0))
	audio.data = data
	audio.loop_mode = AudioStreamWAV.LOOP_FORWARD
	audio.loop_end = 32000
	engine.stream = audio
	engine.volume_db = -26.0

func _make_house_arrow() -> void:
	house_arrow = Label3D.new()
	add_child(house_arrow)
	house_arrow.text = "▼"
	house_arrow.font_size = 96
	house_arrow.pixel_size = .012
	house_arrow.modulate = Color("#ffd146")
	house_arrow.outline_modulate = Color("#30240c")
	house_arrow.outline_size = 12
	house_arrow.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	house_arrow.no_depth_test = true
	house_arrow.hide()

func _update_house_arrow(delta: float) -> void:
	if not is_instance_valid(house_arrow): return
	arrow_clock += delta
	house_arrow.visible = phase=="unload" and not game.garage.inside and not (dropped[0] and dropped[1])
	if house_arrow.visible:
		house_arrow.global_position = Vector3(home.door)+Vector3.UP*(3.3+sin(arrow_clock*3.0)*.18)

func _house_side_routes() -> Array:
	var data = world.geography
	var pin: Vector3 = data.project(ARRIVAL_PIN_LAT,ARRIVAL_PIN_LON)
	var door_at: Vector3 = home.door
	var frontage: Dictionary = home.get("edge",{})
	var street_name := String(frontage.get("name",""))
	var options: Array = []
	var seen: Dictionary = {}
	# Use the clicked location as the longitudinal target, but use the
	# residential doorway to choose the correct curb and legal direction.
	var edges: Array = data.roads_near(pin,35.0)
	if not frontage.is_empty(): edges.append(frontage)
	for edge in edges:
		if not bool(edge.get("driveable",false)): continue
		if not street_name.is_empty() and String(edge.get("name",""))!=street_name: continue
		var aid := String(edge.a_id)
		var bid := String(edge.b_id)
		var key := aid+":"+bid
		if seen.has(key): continue
		seen[key] = true
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var center := Geometry3D.get_closest_point_to_segment(pin,a,b)
		if center.distance_to(pin)>18.0 or center.distance_to(door_at)>28.0: continue
		for order in [0,1]:
			var entry := aid if order==0 else bid
			var exit_id := bid if order==0 else aid
			if not data.graph.get(entry,[]).has(exit_id): continue
			var start: Vector3 = data.points[entry]
			var finish: Vector3 = data.points[exit_id]
			var d := (finish-start).normalized()
			var side := Vector3(-d.z,0,d.x)
			if side.dot(door_at-center)<=0.0: continue
			var width := 1.90
			var offset: float = data.lane_distance(edge,width,true)
			var berth: Vector3 = world.street_geometry.safe_stop_on_edge(start,finish,center+side*offset,4.80,width)
			if not world.street_geometry.intersection_clear_for_stop(berth,4.80,width): continue
			if not world.street_geometry.point_on_road(berth): continue
			if berth.distance_to(door_at)>28.0: continue
			for item in service.taxis:
				var ids: Array[String] = service.router.path(String(item.next_node),entry)
				if ids.is_empty(): continue
				var route: Dictionary = {"id":exit_id,"path":ids,"label":"Casa alquilada","note":"","point":berth-side*offset,"distance":service.router.route_length(ids)+start.distance_to(berth),"partial":true,"entry":entry,"exit":exit_id,"story_berth":berth}
				var score := berth.distance_to(pin)*12.0+berth.distance_to(door_at)+absf(float(route.distance)-200.0)*.015
				options.append({"item":item,"route":route,"score":score})
	return options

func _begin_ride() -> void:
	var goal: Vector3 = home.get("road",home.door)
	var candidates: Array = _house_side_routes()
	if candidates.is_empty():
		push_warning("MyCity: no legal house-side stop near selected GPS; using safe nearby road.")
		for item in service.taxis:
			var route: Dictionary = service.router.resolve_point(goal,String(item.next_node))
			if route.has("error") or not route.has("path"): continue
			var dist := float(route.get("distance",0.0))
			candidates.append({"item":item,"route":route,"score":absf(dist-340.0)+(500.0 if dist<170.0 else 0.0)})
	candidates.sort_custom(func(a,b): return float(a.score)<float(b.score))
	for candidate in candidates:
		service.selected = candidate.item
		service.selected_route = candidate.route
		service.trip_confirmed = true
		if service.prepare_trip():
			cab = service.passenger.body
			break
		service.selected = {}
		service.dialog.hide()
	if not is_instance_valid(cab):
		_fail("No se pudo calcular una parada segura junto a la casa.")
		return
	# Reserve this cab exclusively for the story. TaxiService.tick still drives
	# its passenger route, while the ordinary fare/parking list cannot move it.
	for i in range(service.taxis.size()-1,-1,-1):
		if service.taxis[i].body==cab: service.taxis.remove_at(i)
	_build_story_cab()
	game.player_shape.set_deferred("disabled",true)
	game.player.global_position = cab.global_position+Vector3.UP
	game.avatar.hide()
	cab_view = Camera3D.new()
	cab.add_child(cab_view)
	cab_view.position = Vector3(-.24,1.42,-.77)
	cab_view.rotation = Vector3(-.06,PI,0)
	cab_view.fov = 82
	cab_view.far = 320
	cab_view.make_current()
	# Airport dialogue and chapter card have already finished before loading.
	phase = "approach"
	fade.color = Color.BLACK
	subtitle.text = "Cargando partida…"
	engine.play()
	# Keep the normal city traffic and signals active; no manual stop or fare UI.
	service.speed_mode = 0

func _build_story_cab() -> void:
	for child in cab.get_children():
		if child is MeshInstance3D or child is Label3D: child.hide()
	var visual := Node3D.new()
	cab.add_child(visual)
	_car_shell(visual,Color("#d6ad47"),true)
	_box(visual,Vector3(0,1.75,-.1),Vector3(.54,.18,.30),Color("#ead16e"))
	_label3(visual,"TAXI",Vector3(0,1.75,.061),.003,Color("#222222"))
	_label3(visual,"TAXI",Vector3(0,1.75,-.261),.003,Color("#222222")).rotation.y = PI
	driver = Person.new()
	cab.add_child(driver)
	driver.setup(414)
	driver.position = Vector3(.39,.17,.19)
	driver.scale = Vector3(.74,.74,.74)
	for leg in driver.limbs: leg.rotation.x = -1.45
	for knee in driver.knees: knee.rotation.x = 1.35
	for arm in driver.arms: arm.rotation.x = -1.15
	for i in range(2):
		var bag := _suitcase(Color("#506a8b") if i==0 else Color("#76584a"))
		bags.append(bag)
		bag.reparent(cab,false)
		bag.position = Vector3(-.28 if i==0 else .28,.61,-1.65)
		bag.rotation.x = PI*.5
		if dropped[i]: _place_bag_home(i)

func _make_bags_at_home() -> void:
	for i in range(2):
		var bag := _suitcase(Color("#506a8b") if i==0 else Color("#76584a"))
		bags.append(bag)
		_place_bag_home(i)

func _play_fare_line(i: int) -> void:
	var item: Array = FARE_LINES[i]
	subtitle.text = String(item[0])+": "+String(item[1])
	var path := "res://audio/taxi/fare_%02d.mp3" % (i+1)
	var stream: AudioStreamMP3
	if FileAccess.file_exists(path): stream = AudioStreamMP3.load_from_file(path)
	elif ResourceLoader.exists(path): stream = load(path) as AudioStreamMP3
	fare_wait = float(item[2])+.32
	voice.stop()
	if stream!=null and stream.get_length()>0.0:
		stream.loop = false
		voice.stream = stream
		voice.play()
		fare_wait = stream.get_length()+.32
	else:
		fare_audio_missing.append(path)
		push_warning("MyCity: missing dialogue "+path+"; subtitle still required.")
	# The timer follows the real MP3 length; each line is emitted once.
	print("MyCity: fare dialogue ",i+1,"/",FARE_LINES.size()," | ",String(item[1]))
	fare_active = true

func _safe_approach_cut() -> void:
	# This is a cinematic time ellipsis, only while the screen is fully black.
	if service.arrived or service.passenger.is_empty(): return
	var path: Array = service.passenger.path
	var current := int(service.passenger.index)
	if current>=path.size()-2: return
	var remaining := cab.global_position.distance_to(path.back().p)
	if remaining<26.0: return
	for i in range(path.size()-2,maxi(current,path.size()-35),-1):
		var p: Vector3 = path[i].p
		var next: Vector3 = path[i+1].p
		var d := next-p
		d.y = 0
		if d.length()<.8 or p.distance_to(path.back().p)<8.0 or p.distance_to(path.back().p)>25.0: continue
		d = d.normalized()
		if not world.street_geometry.point_on_road(p): continue
		var angle := atan2(d.x,d.z)
		var q := PhysicsShapeQueryParameters3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.95,1.8,4.9)
		q.shape = shape
		q.transform = Transform3D(Basis(Vector3.UP,angle),p+Vector3.UP*.92)
		q.collision_mask = 1|4|8|32
		q.exclude = [cab.get_rid(),game.player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(q,1).is_empty(): continue
		# Release the old junction reservation and keep the route's final samples.
		var saved: Dictionary = service.passenger.duplicate(true)
		service.finish_trip()
		cab.global_position = Vector3(p.x,cab.global_position.y,p.z)
		cab.rotation.y = angle
		saved.index = i+1
		saved.path = path
		service.resume_mission_trip(saved)
		return

func _arrive() -> void:
	var exit: Dictionary = service.stop_position(game.player,game.player_shape.shape)
	if exit.is_empty():
		# The existing home's threshold is a safe, walkable recovery point.
		var basis: Basis = home.basis
		exit = {"position":Vector3(home.door)+basis.z*1.4+Vector3.UP*.9}
	var angle := cab.rotation.y
	var at := cab.global_position
	service.finish_trip()
	cab.remove_from_group("traffic_parked")
	cab.set_meta("traffic_servicing",true)
	state.step = 1
	state.arrival_stop_revision = ARRIVAL_STOP_REVISION
	state.cab = [at.x,at.y,at.z,angle]
	state.exit = [exit.position.x,exit.position.y,exit.position.z]
	_save()
	_exit_cab(exit.position)
	if dropped[0] and dropped[1]:
		game.garage._enter()
		_begin_fare()

func _resume_arrival() -> void:
	var saved: Array = state.get("cab",[])
	if saved.size()!=4:
		_begin_ride()
		return
	cab = service._make_taxi(0)
	cab.global_position = Vector3(float(saved[0]),float(saved[1]),float(saved[2]))
	cab.rotation.y = float(saved[3])
	_build_story_cab()
	var basis: Basis = home.basis
	var at := Vector3(home.door)+basis.z*1.4+Vector3.UP*.9
	var previous: Array = state.get("exit",[])
	if previous.size()==3: at = Vector3(float(previous[0]),float(previous[1]),float(previous[2]))
	_exit_cab(at)
	if dropped[0] and dropped[1]:
		game.garage._enter()
		_begin_fare()

func _exit_cab(at: Vector3) -> void:
	engine.stop()
	if is_instance_valid(cab_view): cab_view.queue_free()
	game.player.global_position = at
	game.player.velocity = Vector3.ZERO
	game.player_shape.set_deferred("disabled",false)
	game.first_person = true
	game.yaw = atan2(cab.global_position.x-at.x,cab.global_position.z-at.z)+PI
	game.pitch = -.12
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	game.play_camera.make_current()
	driver.position = Vector3(-1.35,0,-1.95)
	driver.rotation.y = 0
	driver.scale = Vector3.ONE
	for leg in driver.limbs: leg.rotation.x = 0
	for knee in driver.knees: knee.rotation.x = 0
	for arm in driver.arms: arm.rotation.x = 0
	lid.rotation.x = 1.15
	trunk_open = true
	phase = "unload"
	_update_house_arrow(0.0)
	fade.color = Color(0,0,0,0)
	title.hide()
	game.business.layer.show()
	game.business.hud.show()
	objective.text = "CAPÍTULO 1 · LA ADAPTACIÓN\nLleva tus dos maletas a la casa alquilada."

func _save() -> void:
	state.dropped = dropped.duplicate()
	game.business.ledger.save_game()

func _place_bag_home(i: int) -> void:
	var bag := bags[i]
	if bag.get_parent()!=self: bag.reparent(self,false)
	# Reuse the existing HomeGarage interior, near the entrance, away from tools.
	bag.global_position = Vector3(-2.15+float(i)*.55,110.03,4.35)
	bag.rotation = Vector3.ZERO

func _flat(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func _trunk() -> Vector3:
	return cab.to_global(Vector3(0,0,-2.65))

func _house_near() -> bool:
	return _flat(game.player.global_position,Vector3(home.door))<2.5

func _action() -> String:
	var count := int(dropped[0])+int(dropped[1])
	objective.text = "CAPÍTULO 1 · LA ADAPTACIÓN\nMaletas dentro de la casa: %d/2" % count
	if game.garage.inside:
		if carry>=0:
			return "[E] Dejar maleta junto a la entrada" if game.player.global_position.distance_to(Vector3(-1.85,110.86,4.35))<2.5 else "Acércate a la entrada de la casa."
		return "[E] Salir a buscar la otra maleta" if game.player.global_position.distance_to(Vector3(-.7,110.86,5.25))<1.8 else "Vuelve a la puerta."
	if carry>=0:
		return "[E] Entrar en la casa alquilada" if _house_near() else "Lleva la maleta hasta la casa."
	return "[E] Recoger maleta del maletero" if _flat(game.player.global_position,_trunk())<2.1 else "Acércate al maletero del taxi."

func interact() -> void:
	if phase!="unload" or busy: return
	if game.garage.inside:
		if carry>=0 and game.player.global_position.distance_to(Vector3(-1.85,110.86,4.35))<2.5:
			var i := carry
			carry = -1
			dropped[i] = true
			_place_bag_home(i)
			_save()
			if dropped[0] and dropped[1]: _begin_fare()
		elif carry<0 and game.player.global_position.distance_to(Vector3(-.7,110.86,5.25))<1.8:
			game.garage._exit()
		return
	if carry>=0:
		if _house_near(): game.garage._enter()
		return
	if _flat(game.player.global_position,_trunk())>=2.1: return
	for i in range(2):
		if dropped[i]: continue
		carry = i
		var bag := bags[i]
		bag.reparent(game.play_camera,false)
		bag.position = Vector3(.34,-.65,-.65)
		bag.rotation = Vector3.ZERO
		if dropped[1-i]: lid.rotation.x = 0.0
		break

func _begin_fare() -> void:
	if phase!="unload" or not dropped[0] or not dropped[1]: return
	phase = "wallet"
	if is_instance_valid(house_arrow): house_arrow.hide()
	state.step = 1
	state.fare_scene_done = false
	state.fare_lines_completed = 0
	_save()
	fare_index = 0
	fare_completed_lines = 0
	fare_audio_missing.clear()
	fare_wait = .85
	print("MyCity: both suitcases delivered; mandatory fare cinematic begins.")
	fare_active = false
	fare_clock = 0.0
	game.player.velocity = Vector3.ZERO
	game.business.layer.hide()
	game.status.hide()
	game.reticle.hide()
	objective.text = ""
	subtitle.text = ""
	lid.rotation.x = 0.0

func _face_point(at: Vector3,pitch_value: float=-.08) -> void:
	var d: Vector3 = at-game.player.global_position
	game.yaw = atan2(d.x,d.z)+PI
	game.pitch = pitch_value
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)

func _safe_talk_position() -> Vector3:
	# Prefer the saved sidewalk exit. Check for newly spawned traffic.
	var previous: Array = state.get("exit",[])
	var positions: Array[Vector3] = []
	if previous.size()==3: positions.append(Vector3(float(previous[0]),float(previous[1]),float(previous[2])))
	for side in [-1.0,1.0]:
		for along in [-2.5,-1.1,0.0]:
			positions.append(cab.to_global(Vector3(float(side)*1.8,.90,float(along))))
	for at in positions:
		var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP,at-Vector3.UP*2.0,2)
		ray.exclude = [game.player.get_rid(),cab.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty(): continue
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = game.player_shape.shape
		var floor_at: Vector3 = hit.position+Vector3.UP*.90
		q.transform = Transform3D(Basis.IDENTITY,floor_at)
		q.collision_mask = 1|4|8|16|32
		q.exclude = [game.player.get_rid()]
		if get_world_3d().direct_space_state.intersect_shape(q,1).is_empty(): return floor_at
	return game.player.global_position

func _tick_fare(delta: float) -> void:
	fare_clock += delta
	game.player.velocity = Vector3.ZERO
	if phase=="wallet":
		# The player looks down to check their pockets, then raises their view.
		var target_pitch := -.62 if fare_index==1 else -.12
		game.pitch = lerpf(game.pitch,target_pitch,minf(delta*3.5,1.0))
		game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	if phase=="wallet_exit":
		fade.color.a = move_toward(fade.color.a,1.0,delta*3.0)
		if fade.color.a<.99: return
		if game.garage.inside: game.garage._exit()
		var safe := _safe_talk_position()
		if safe.y>50.0:
			var basis: Basis = home.basis
			safe = Vector3(home.door)+basis.z*1.4+Vector3.UP*.9
		game.garage.inside = false
		game.player.global_position = safe
		game.player.velocity = Vector3.ZERO
		_face_point(driver.global_position+Vector3.UP*1.5)
		phase = "fare_talk"
		fare_wait = .6
		fare_clock = 0.0
		return
	if phase=="fare_talk":
		fade.color.a = move_toward(fade.color.a,0.0,delta*2.0)
		var d: Vector3 = game.player.global_position-driver.global_position
		driver.rotation.y = lerp_angle(driver.rotation.y,atan2(d.x,d.z)-cab.rotation.y,minf(delta*5.0,1.0))
		driver.arms[1].rotation.x = lerpf(driver.arms[1].rotation.x,-.45 if fare_index==3 and fare_active else 0.0,minf(delta*5.0,1.0))
	fare_wait -= delta
	if fare_wait>0.0: return
	if fare_active:
		fare_active = false
		voice.stop()
		subtitle.text = ""
		fare_index += 1
		fare_completed_lines = fare_index
		fare_wait = .45
		return
	if phase=="wallet" and fare_index>=2:
		phase = "wallet_exit"
		return
	if fare_index>=FARE_LINES.size():
		if fare_completed_lines!=FARE_LINES.size(): return
		phase = "driver_leave"
		fare_clock = 0.0
		departure_origin = cab.global_position
		return
	_play_fare_line(fare_index)

func _start_driver_departure() -> bool:
	var road: Dictionary = service._parking_road(cab.global_position,cab.global_basis.z)
	if road.is_empty(): return false
	var start: String = road.next
	var direction: Vector3 = road.d
	for offset in [direction*150.0,direction*90.0,Vector3(130,0,0),Vector3(-130,0,0),Vector3(0,0,130),Vector3(0,0,-130)]:
		var result: Dictionary = service.router.resolve_point(cab.global_position+offset,start)
		if result.has("error") or float(result.get("distance",0.0))<25.0: continue
		service.selected = {"body":cab,"next_node":start,"path":[],"index":0,"speed":0.0,"blocked":0.0,"goal":"","label":"","note":""}
		service.selected_route = result
		service.trip_confirmed = true
		if service.prepare_trip():
			departure_record = service.passenger
			return true
		service.selected = {}
		service.dialog.hide()
	# A short, legal forward segment is enough to leave the front of the house.
	var finish: Vector3 = road.b
	var berth: Vector3 = world.street_geometry.safe_stop_on_edge(road.a,road.b,finish-direction*5.0+Vector3(road.side)*service.curb_offset(float(road.width),1.90),4.80,1.90)
	if berth.distance_to(cab.global_position)<5.0: return false
	var record := {"body":cab,"path":[{"p":berth,"node":""}],"index":0,"next_node":start,"label":"La Habana","note":"","goal":start}
	if service.resume_mission_trip(record):
		departure_record = service.passenger
		return true
	return false

func _tick_driver_leave(delta: float) -> void:
	fare_clock += delta
	game.player.velocity = Vector3.ZERO
	if not departure_started:
		_face_point(driver.global_position+Vector3.UP*1.2)
		# Walk around the rear of the taxi to the driver's side, then sit.
		var points: Array[Vector3] = [Vector3(-1.35,0,-2.8),Vector3(1.35,0,-2.8),Vector3(1.35,0,.3)]
		var index := mini(2,floori(fare_clock/1.2))
		var goal: Vector3 = points[index]
		var d: Vector3 = goal-driver.position
		if d.length()>.08:
			driver.position = driver.position.move_toward(goal,delta*2.6)
			driver.rotation.y = atan2(d.x,d.z)
			driver.animate(delta,true)
		if fare_clock<4.0: return
		driver.position = Vector3(.39,.17,.19)
		driver.rotation = Vector3.ZERO
		driver.scale = Vector3(.74,.74,.74)
		for leg in driver.limbs: leg.rotation.x = -1.45
		for knee in driver.knees: knee.rotation.x = 1.35
		for arm in driver.arms: arm.rotation.x = -1.15
		departure_started = true
		fare_clock = 0.0
		if _start_driver_departure():
			return
		push_warning("MyCity: no safe departure route; leaving off camera.")
		return
	_face_point(cab.global_position+Vector3.UP*.9)
	if cab.global_position.distance_to(departure_origin)>12.0 or (service.arrived and fare_clock>1.0):
		_finish()
	elif fare_clock>10.0:
		# A traffic jam must not trap the player in the cinematic indefinitely.
		_finish()

func _finish() -> void:
	# Free play is gated by the actual sequence, not just luggage or a timer.
	if phase!="driver_leave" or fare_completed_lines!=FARE_LINES.size() or not dropped[0] or not dropped[1]: return
	state.step = 2
	state.fare_scene_done = true
	state.fare_revision = FARE_REVISION
	state.fare_lines_completed = fare_completed_lines
	state.taxi_payment_pending = true
	state.fare_audio_missing = fare_audio_missing.duplicate()
	print("MyCity: fare cinematic complete; free play unlocked.")
	_save()
	phase = "done"
	subtitle.text = ""
	objective.text = ""
	layer.hide()
	game.status.show()
	game.map_credit.show()
	game.business.layer.show()
	game._update_hud()
	# Keep the departing cab in city traffic rather than deleting it in view.
	# Once its route finishes it is returned to the ordinary taxi fleet.
	if is_instance_valid(cab) and departure_record.is_empty():
		cab.add_to_group("traffic_parked")
		cab.set_meta("traffic_servicing",false)

func _process(_delta: float) -> void:
	if phase=="done" and not departure_record.is_empty() and service.passenger.get("body")==cab and service.arrived:
		var record: Dictionary = service.passenger
		service.finish_trip()
		service.taxis.append(record)
		departure_record = {}

func handle_look(relative: Vector2) -> void:
	if phase=="approach" and is_instance_valid(cab_view):
		look.x = clampf(look.x-relative.x*.003,-1.15,1.15)
		look.y = clampf(look.y-relative.y*.003,-.48,.35)
		cab_view.rotation = Vector3(look.y-.06,PI+look.x,0)
	elif phase=="unload":
		game.yaw -= relative.x*.003
		game.pitch = clampf(game.pitch-relative.y*.003,-1.05,.35)
		game.pivot.rotation = Vector3(game.pitch,game.yaw,0)

func tick(delta: float) -> void:
	_update_house_arrow(delta)
	match phase:
		"approach":
			game.player.global_position = cab.global_position+Vector3.UP
			arrival_wait += delta
			if not approach_cut_done:
				approach_cut_done = true
				_safe_approach_cut()
			var close_to_home: bool = service.arrived
			if not service.passenger.is_empty():
				var route: Array = service.passenger.path
				if not route.is_empty(): close_to_home = cab.global_position.distance_to(route.back().p)<30.0
			if close_to_home:
				subtitle.text = ""
				fade.color.a = move_toward(fade.color.a,0.0,delta*1.3)
			if service.arrived and fade.color.a<=.01:
				phase = "arrival"
				arrival_wait = 0.0
				subtitle.text = ""
		"arrival":
			arrival_wait += delta
			if arrival_wait>.85:
				fade.color.a = move_toward(fade.color.a,1.0,delta*2.5)
				if fade.color.a>=.99: _arrive()
		"wallet","wallet_exit","fare_talk": _tick_fare(delta)
		"driver_leave": _tick_driver_leave(delta)
		"unload":
			# Recover a save interrupted immediately after the final bag.
			if dropped[0] and dropped[1]:
				if not game.garage.inside: game.garage._enter()
				_begin_fare()
				return
			var direction: Vector2 = game._read_controls()
			var move := Vector3(direction.x,0,direction.y).normalized().rotated(Vector3.UP,game.yaw)
			var speed := 3.2 if carry>=0 else (7.0 if game.control_pressed(KEY_SHIFT) else 4.2)
			game.player.velocity.x = move.x*speed
			game.player.velocity.z = move.z*speed
			if not game.player.is_on_floor(): game.player.velocity.y -= 18.0*delta
			else: game.player.velocity.y = 0.0
			game.player.move_and_slide()
			subtitle.text = _action()
			if game.player.global_position.y< -12:
				var basis: Basis = home.basis
				game.player.global_position = Vector3(home.door)+basis.z*1.4+Vector3.UP*.9
				game.player.velocity = Vector3.ZERO
				game.garage.inside = false

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
	# The moving taxi has one collision body managed by TaxiService.
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
