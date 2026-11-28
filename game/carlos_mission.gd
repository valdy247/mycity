extends Node3D
# Mission 2. Only two NPCs, one temporary room and four tiny wall textures.
const Person = preload("res://street_person.gd")
const PaintVisual = preload("res://paint_visual.gd")
const HAND_REST := Vector3(.28,-.30,-.72)
var hand_tween: Tween
var paint_progress: Label3D
const ROOM := Vector3(30,110,0)
# Exact reference copied from the in-game editor by the player.
const CARLOS_LAT := 23.1219468
const CARLOS_LON := -82.3684516
const HOME_LOCATION_VERSION := 2
const COLS := 8
const ROWS := 4
const TOTAL := COLS*ROWS*4
const OLD_PAINT := Color("#a99d88")
const BLUE := Color("#4c92c9")
const YELLOW := Color("#e9bf43")
const DOOR_SURFACE := 4
var buckets: Array[Node3D] = []
var correct_tiles := 0
var worker_charge := 0
var worker_color := ""
var worker_phase := "choose"
var worker_job: Dictionary = {}
var warning_clock := 0.0
var farewell := false
var farewell_time := 0.0
var follow_stall := 0.0
var exit_retry := 0.0
var hand_tip: MeshInstance3D
var worker_tip: MeshInstance3D
var mission_voice: AudioStreamPlayer
var greeting_tween: Tween
var game
var world
var business
var state: Dictionary
var carlos: Person
var client: Person
var home: Dictionary = {}
var customer: Dictionary = {}
var room: Node3D
var marker: Node3D
var hand: Node3D
var brush_item: Node3D
var worker_brush: Node3D
var bucket: Node3D
var walls: Array[MeshInstance3D] = []
var images: Array[Image] = []
var textures: Array[ImageTexture] = []
var inside := false
var previous_first := true
var call_wait := 0.0
var work_clock := 0.0
var brush_clock := 0.0
var follow_clock := 0.0
var follow_path := PackedVector3Array()
var follow_index := 0
var was_vehicle := false
var locate_wait := 0.0
var locate_reported := false
var paint_dirty := false
var paint_save_clock := 0.0

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	business = game.business
	var life: Dictionary = business.ledger.life_data
	if not life.has("carlos_paint"): life.carlos_paint = {"stage":0,"painted":{},"brush":false,"charge":0}
	state = life.carlos_paint
	if int(state.get("paint_version",0))<2:
		var converted: Dictionary = {}
		for key in state.painted:
			var parts := String(key).split(":")
			if parts.size()!=3: continue
			var wall := int(parts[0])
			var x := int(parts[1])
			var y := int(parts[2])
			if wall<0 or wall>=4 or x<0 or x>=COLS or y<0 or y>=ROWS or _covered(wall,x,y): continue
			converted[key] = "blue"
		state.painted = converted
		state.paint_version = 2
		state.color = "blue"
		state.charge = 0
		_save()
	correct_tiles = _correct_count()
	# Re-enter the client house to resume a partially painted job.
	marker = Node3D.new()
	add_child(marker)
	business._arrow(marker,Vector3.UP*2.6,Color("#ffd85c"))
	marker.hide()
	# Rebind older automatic selections before Carlos has been collected.
	# Never relocate the client or companion in a job already underway.
	if int(state.get("home_location_version",0))<HOME_LOCATION_VERSION and _stage()<=2:
		state.erase("home")
		state.erase("customer")
		state.home_location_version = HOME_LOCATION_VERSION
		if _stage()==2: _clear_target()
		_save()

func _save() -> void:
	business.ledger.save_game()

func _stage() -> int:
	return int(state.get("stage",0))

func _named(edge: Dictionary,term: String) -> bool:
	for value in [String(edge.name)]+edge.get("aliases",[]):
		var name_value: String = world.geography.normalized(String(value))
		if name_value.contains(term): return true
	return false

func _corners(first: String,second: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for id in world.geography.junctions:
		var one := false
		var two := false
		for edge in world.geography.junctions[id]:
			if _named(edge,first) or (first=="monte" and bool(edge.get("monte_corridor",false))): one = true
			if _named(edge,second) or (second=="monte" and bool(edge.get("monte_corridor",false))): two = true
		if one and two: out.append(world.geography.points[id])
	return out

func _ground(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*1.5,at-Vector3.UP*.5,2)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<.65: return {}
	var p: Vector3 = hit.position
	if world.street_geometry.point_on_road(p) or not world.pedestrian_segment_clear(p,p): return {}
	return {"p":p}

func _door_data(entry: Dictionary) -> Dictionary:
	var door: Vector3 = entry.threshold
	var normal: Vector3 = entry.normal
	for distance in [.65,1.05,1.50]:
		var ground := _ground(door+normal*float(distance))
		if not ground.is_empty(): return {"door":door,"normal":normal,"p":ground.p,"width":float(entry.get("width",1.15))}
	return {}

func _restore_door(key: String) -> Dictionary:
	var record: Dictionary = state.get(key,{})
	if record.is_empty(): return {}
	var p := Vector3(float(record.x),0,float(record.z))
	for entry in world.npc_doorways:
		var door: Vector3 = entry.threshold
		if Vector2(door.x-p.x,door.z-p.z).length()<.25: return _door_data(entry)
	return {}

func _remember(key: String,site: Dictionary) -> void:
	var p: Vector3 = site.door
	state[key] = {"x":p.x,"z":p.z}

# Use the copied WGS84 point instead of guessing from street names.
# If the point lies on a mapped building, prefer doors belonging to it.
# Do not silently select a house farther down the block.
func _home_from_gps() -> Dictionary:
	var anchor: Vector3 = world.geography.project(CARLOS_LAT,CARLOS_LON)
	var q := Vector2(anchor.x,anchor.z)
	var footprints: Array = []
	for item in world.geography.footprints_near(anchor,18.0):
		if Geometry2D.is_point_in_polygon(q,item.poly): footprints.append(item.poly)
	var choices: Array = []
	for entry in world.npc_doorways:
		if String(entry.kind)!="home": continue
		var door: Vector3 = entry.threshold
		var distance := Vector2(door.x-anchor.x,door.z-anchor.z).length()
		if distance>18.0: continue
		var normal: Vector3 = entry.normal
		var inner := door-normal*.65
		var belongs := false
		for poly in footprints:
			if Geometry2D.is_point_in_polygon(Vector2(inner.x,inner.z),poly):
				belongs = true
				break
		if not footprints.is_empty() and not belongs: continue
		if footprints.is_empty() and distance>10.0: continue
		choices.append({"entry":entry,"distance":distance})
	choices.sort_custom(func(a,b): return float(a.distance)<float(b.distance))
	for option in choices:
		var site := _door_data(option.entry)
		if not site.is_empty():
			print("Misión Carlos: entrada asociada al GPS ",CARLOS_LAT,", ",CARLOS_LON," a ",snappedf(float(option.distance),.1)," m del punto.")
			return site
	return {}

func _locate() -> bool:
	if not home.is_empty() and not customer.is_empty(): return true
	if not game.monte_pedestrians.initialized: return false
	home = _restore_door("home")
	customer = _restore_door("customer")
	if home.is_empty():
		home = _home_from_gps()
		if home.is_empty():
			if _stage()==2 and not locate_reported:
				var anchor: Vector3 = world.geography.project(CARLOS_LAT,CARLOS_LON)
				game.garage._set_waypoint(anchor,"GPS de Carlos · confirmar puerta")
				_save()
			_location_notice("GPS de Carlos localizado, pero falta una puerta residencial segura junto al punto. Puedes confirmarla en el teléfono.")
			return false
		_remember("home",home)
		state.home_location_version = HOME_LOCATION_VERSION
	if customer.is_empty():
		var origin: Vector3 = home.p
		var choices: Array = []
		for entry in world.npc_doorways:
			if String(entry.kind)!="home": continue
			var p: Vector3 = entry.threshold
			var distance := p.distance_to(origin)
			if distance<12.0 or distance>85.0: continue
			if not world.garage_home_site.is_empty() and p.distance_to(world.garage_home_site.door)<3.0: continue
			choices.append({"entry":entry,"score":absf(distance-32.0)})
		choices.sort_custom(func(a,b): return float(a.score)<float(b.score))
		for option in choices.slice(0,20):
			var site := _door_data(option.entry)
			if site.is_empty(): continue
			var route: PackedVector3Array = game.monte_pedestrians.route_between(origin,site.p)
			if route.is_empty() and not world.pedestrian_segment_clear(origin,site.p): continue
			customer = site
			_remember("customer",customer)
			break
	if customer.is_empty():
		_location_notice("Casa de Carlos localizada, pero no hay una casa cercana conectada por la red peatonal.")
		return false
	locate_reported = false
	_save()
	return true

func _location_notice(message: String) -> void:
	if locate_reported: return
	locate_reported = true
	print("Misión Carlos: "+message)
	business._notify(message)

func _spawn_carlos(at: Vector3) -> void:
	if not is_instance_valid(carlos):
		carlos = Person.new()
		add_child(carlos)
		carlos.setup(806)
		carlos.remove_from_group("social_people")
		business._label(carlos,"Carlos",Vector3(0,2.03,0))
	carlos.global_position = at
	carlos.show()

func _target(site: Dictionary,label_value: String) -> void:
	if site.is_empty(): return
	var p: Vector3 = site.p
	marker.global_position = p
	marker.show()
	game.garage._set_waypoint(p,label_value)

func _clear_target() -> void:
	marker.hide()
	game.garage.waypoint_active = false
	game.garage.state.gps = {}
	game.taxis.set_garage_destination(Vector3.ZERO,"")

# Local prerecorded dialogue; no network or runtime TTS required.
const CALL_AUDIO_DIR := "res://audio/carlos/"

func _scene_clips(names: Array) -> Array:
	var paths: Array = []
	for name_value in names:
		paths.append(CALL_AUDIO_DIR+String(name_value)+".mp3")
	return paths

func _stop_mission_voice() -> void:
	if is_instance_valid(mission_voice): mission_voice.stop()

func _mission_line(text_value: String,clip_name: String) -> void:
	business._notify(text_value)
	var path := CALL_AUDIO_DIR+clip_name+".mp3"
	if not ResourceLoader.exists(path): return
	var clip := load(path) as AudioStream
	if clip==null: return
	if not is_instance_valid(mission_voice):
		mission_voice = AudioStreamPlayer.new()
		add_child(mission_voice)
	if mission_voice.playing: return
	mission_voice.stream = clip
	mission_voice.play()

func _greeting_pose(pose: float) -> void:
	if not is_instance_valid(carlos): return
	carlos.arms[1].rotation.x = pose
	if game.limb_arms.size()>1: game.limb_arms[1].rotation.x = pose

func _finish_greeting() -> void:
	if is_instance_valid(carlos):
		carlos.remove_meta("story_handshake")
		carlos.arms[1].rotation.x = 0.0
	if game.limb_arms.size()>1: game.limb_arms[1].rotation.x = 0.0
	if is_instance_valid(game.avatar): game.avatar.visible = not game.first_person

func _greet_carlos() -> void:
	if is_instance_valid(greeting_tween): greeting_tween.kill()
	var face: Vector3 = game.player.global_position-carlos.global_position
	face.y = 0.0
	if face.length_squared()>.02:
		carlos.rotation.y = atan2(face.x,face.z)
		game.avatar.rotation.y = atan2(-face.x,-face.z)
	_stop_mission_voice()
	business.open_story(carlos,"Carlos",["Carlos: Menos mal que viniste. Así me ayudas y te buscas una plata, mano. Vamos, sígueme, que es aquí mismo cerca.","Tú: Dale, vamos."],"Vamos",_meet_carlos,"",_scene_clips(["meet_carlos","meet_player"]))
	carlos.set_meta("story_handshake",true)
	if is_instance_valid(business.story_camera) and business.story_camera.active: game.avatar.show()
	greeting_tween = create_tween()
	greeting_tween.tween_method(_greeting_pose,0.0,-1.10,.22)
	for i in range(3):
		greeting_tween.tween_method(_greeting_pose,-1.10,-.97,.14)
		greeting_tween.tween_method(_greeting_pose,-.97,-1.23,.14)
	greeting_tween.tween_method(_greeting_pose,-1.23,0.0,.28)
	greeting_tween.tween_callback(_finish_greeting)

const CALL_INTRO := [
	["Carlos","Buen día, te estoy llamando de parte de Odalis. Me dijo que necesitabas buscar dinero.","carlos_intro",5.20],
	["Tú","Oh, sí, bro, dime, ¿qué hay que hacer?","player_intro_v2",2.56],
	["Carlos","Mira, un vecino mío quiere pintar la casa y me hace falta una mano. ¿Estás dentro?","carlos_offer",5.04]
]
const CALL_YES := [
	["Tú","De una, mándame tu ubicación.","player_yes",2.00],
	["Carlos","¡Jajajaja! ¿Qué ubicación? Ya tú estás en Cuba. Coge por Esteve pa' arriba y dobla Flores. En la primera casa te voy a esperar afuera.","carlos_yes",7.92],
	["Tú","Jajaja, dale, te veo ahora.","player_yes_end",2.56]
]
const CALL_NO := [
	["Tú","Hermano, si algo más tarde te escribo porque estoy ocupado ahora.","player_no",3.92],
	["Carlos","Oh, sí, está bien, me dices.","carlos_no",2.40],
	["Tú","Dale.","player_no_end",0.56]
]
var call_generation := 0
const CALL_DIALOGUE_VERSION := 3
var call_ring_started := false
var call_session_offered := false
var call_last_blocker := ""

func _call_unlocked() -> bool:
	var adaptation: Dictionary = business.ledger.life_data.get("adaptation",{})
	return business.ledger.stage==4 or (game.adaptation_mode and bool(adaptation.get("investment_complete",false)))

func _prepare_call() -> void:
	if _stage()!=0: return
	state.stage = 1
	business.ledger.add_message("Carlos","Llámame. Tengo un trabajo pintando una casa cerca de Flores y Estévez.")
	_save()

func open_call() -> void:
	if not _call_unlocked() and _stage()==0:
		business._open("Carlos","La llamada estará disponible después de completar la primera inversión con Albertico.")
		business._button("Cerrar",business.close)
		return
	if _stage()==0: _prepare_call()
	call_session_offered = true
	if _stage()!=1:
		business._open("Carlos",objective())
		if _stage()==2:
			business._button("Confirmar la puerta de Carlos que estoy mirando",_confirm_home)
		business._button("Escuchar llamada de Carlos",_play_call.bind(CALL_INTRO,0))
		business._button("Cerrar",business.close)
		return
	_play_call(CALL_INTRO,0)

func _play_call(lines: Array,decision: int) -> void:
	if _stage()<1: return
	var starting_stage := _stage()
	call_generation += 1
	var generation := call_generation
	business.phone_mode = true
	business._open("Llamada · Carlos")
	print("MyCity Carlos: diálogo abierto; etapa=",starting_stage," rama=",decision)
	if is_instance_valid(business.phone_ring): business.phone_ring.stop()
	var subtitle := Label.new()
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	business.content.add_child(subtitle)
	var voice := AudioStreamPlayer.new()
	subtitle.add_child(voice)
	subtitle.visibility_changed.connect(func():
		if not subtitle.is_visible_in_tree(): voice.stop()
	)
	for entry in lines:
		if generation!=call_generation or not is_instance_valid(subtitle) or not subtitle.is_visible_in_tree() or _stage()!=starting_stage: return
		subtitle.text = String(entry[0])+": "+String(entry[1])
		var path := CALL_AUDIO_DIR+String(entry[2])+".mp3"
		var duration := float(entry[3])
		if ResourceLoader.exists(path):
			var clip := load(path) as AudioStream
			if clip!=null:
				voice.stream = clip
				duration = maxf(.1,clip.get_length())
				voice.play()
		else:
			# Readable subtitles remain available before the optional voice pack is installed.
			duration = maxf(duration,2.0)
		await get_tree().create_timer(duration+.25).timeout
	if generation!=call_generation or not is_instance_valid(subtitle) or not subtitle.is_visible_in_tree() or _stage()!=starting_stage: return
	voice.stop()
	match decision:
		0:
			state.call_dialogue_version = CALL_DIALOGUE_VERSION
			_save()
			business._button("Sí",_call_yes)
			business._button("No",_call_no)
		1:
			state.call_dialogue_version = CALL_DIALOGUE_VERSION
			_save()
			if _stage()==1: _accept()
			else: business.close()
		2:
			state.call_dialogue_version = CALL_DIALOGUE_VERSION
			_save()
			business.close()

func _call_yes() -> void:
	_play_call(CALL_YES,1)

func _call_no() -> void:
	_play_call(CALL_NO,2)

# Local maps may differ in street spelling or doorway generation.
# Let the player correct the exact house without changing the map itself.
func _confirm_home() -> void:
	if _stage()!=2: return
	var at: Vector3 = game.player.global_position
	for entry in world.npc_doorways:
		if String(entry.kind)!="home": continue
		var door: Vector3 = entry.threshold
		if at.distance_to(door)>3.5: continue
		var site := _door_data(entry)
		if site.is_empty() or not _aim_door_at(site): continue
		home = site
		customer = {}
		if is_instance_valid(carlos):
			carlos.hide()
			carlos.queue_free()
		carlos = null
		_clear_target()
		_remember("home",home)
		state.home_location_version = HOME_LOCATION_VERSION
		state.erase("customer")
		_save()
		business.close()
		if _locate():
			_spawn_carlos(home.p)
			_target(home,"Casa de Carlos · Flores y Estévez")
		else: business._notify("Casa de Carlos confirmada. Buscando cliente cercano.")
		return
	business._notify("Mira directamente una puerta residencial cercana antes de confirmar.")

func _accept() -> void:
	state.stage = 2
	business.ledger.add_message("Tú → Carlos","Dale, te veo ahora.")
	business.close()
	_save()
	if _locate():
		_spawn_carlos(home.p)
		_target(home,"Casa de Carlos · Flores y Estévez")
	else: business._notify("Buscando la casa de Carlos en Flores y Estévez…")

func objective() -> String:
	match _stage():
		1: return "Abre el teléfono (P) y responde a Carlos."
		2: return "Busca a Carlos en Flores y Estévez. Habla con él (E)."
		3: return "Sigue a Carlos a casa del cliente y entra por la puerta (E)."
		4:
			if not inside: return "Regresa a casa del cliente. Entra con E."
			if _finished(): return "Pintura terminada. Habla con el cliente (E) para cobrar."
			if not bool(state.brush): return "Recoge la brocha del suelo (E)."
			var progress := "%d%% correcto" % roundi(100.0*float(correct_tiles)/float(TOTAL))
			if int(state.charge)<=0: return "Moja la brocha en una lata (E). "+progress
			return "Clic izquierdo: paredes azules y puerta amarilla. "+progress
		5:
			if String(game.garage.state.part)=="bicicleta:wheel_a": return "Lleva la goma a tu garaje e instálala en la bicicleta."
			return ""
	return ""

func _aim_node(node: Node3D,center: Vector3,extent: Vector3,reach: float = 3.0) -> bool:
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return false
	var target := node.to_global(center)
	if game.player.global_position.distance_to(target)>reach: return false
	var camera: Camera3D = game.play_camera
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var local_hit: Variant = AABB(center-extent,extent*2.0).intersects_segment(node.to_local(origin),node.to_local(origin+direction*8.0))
	if local_hit==null: return false
	var at := node.to_global(local_hit)
	var ray := PhysicsRayQueryParameters3D.create(origin,at,1|4|8|16|32)
	ray.exclude = [game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _aim_door() -> bool:
	return _aim_door_at(customer)

func _aim_door_at(site: Dictionary) -> bool:
	if site.is_empty(): return false
	var door: Vector3 = site.door
	var normal: Vector3 = site.normal
	var camera: Camera3D = game.play_camera
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var denom := direction.dot(normal)
	if denom>=-.01 or game.player.global_position.distance_to(door)>3.5: return false
	var depth := (door-origin).dot(normal)/denom
	if depth<=0.0 or depth>8.0: return false
	var offset := origin+direction*depth-door
	var side := Vector3(-normal.z,0,normal.x)
	if absf(offset.dot(side))>float(site.get("width",1.15))*.5 or offset.y<.03 or offset.y>2.2: return false
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+direction*maxf(.01,depth-.12),1|4|8|16)
	ray.exclude = [game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func action_text() -> String:
	if inside:
		if _stage()==5: return "[E] Salir de la casa" if _exit_aim() else "Lleva la goma al garaje."
		if _stage()==4 and _finished() and _aim_node(client,Vector3.UP,Vector3(.45,.95,.35)): return "[E] Cobrar al cliente"
		if not bool(state.brush) and _aim_node(brush_item,Vector3.ZERO,Vector3(.28,.16,.28)): return "[E] Recoger brocha"
		if bool(state.brush) and _stage()==4:
			for i in range(buckets.size()):
				if _aim_node(buckets[i],Vector3.ZERO,Vector3(.32,.32,.32)): return "[E] Mojar brocha · "+("Azul" if i==0 else "Amarillo")
		if _exit_aim(): return "[E] Salir de la casa"
		if bool(state.brush): return "Clic izquierdo: pintar · %s · carga %d/12" % ["Azul" if String(state.get("color","blue"))=="blue" else "Amarillo",int(state.charge)]
		return "Mira la brocha del suelo y pulsa E"
	if _stage()==2 and _aim_node(carlos,Vector3.UP,Vector3(.38,.95,.35)): return "[E] Hablar con Carlos"
	if _stage() in [3,4] and _aim_door(): return "[E] Entrar a casa del cliente"
	return ""

func interact() -> bool:
	var action := action_text()
	if inside:
		if action.contains("Cobrar"): _payment()
		elif action.contains("Recoger brocha"):
			state.brush = true
			brush_item.hide()
			_refresh_hand()
			_animate_hand(Vector3(0,-.18,.05),-.28,.24)
			_save()
		elif action.contains("Mojar"):
			state.color = "blue" if action.contains("Azul") else "yellow"
			state.charge = 12
			_refresh_hand()
			_animate_hand(Vector3(0,-.17,-.05),-.55,.26)
			_save()
		elif action.contains("Salir"): _exit()
		return true
	if action.contains("Hablar con Carlos"):
		if not game.garage._free_hands():
			business._notify("Deja primero lo que llevas en las manos.")
			return true
		_greet_carlos()
		return true
	if action.contains("Entrar a casa del cliente"):
		if not game.garage._free_hands():
			business._notify("Necesitas las manos libres para trabajar.")
			return true
		if not is_instance_valid(carlos) or carlos.global_position.distance_to(customer.p)>5.0:
			business._notify("Espera a Carlos para entrar juntos.")
			return true
		_enter()
		return true
	return false

func _meet_carlos() -> void:
	if _stage()!=2 or not game.garage._free_hands(): return
	if is_instance_valid(greeting_tween): greeting_tween.kill()
	_finish_greeting()
	business.close()
	state.stage = 3
	follow_clock = 0.0
	follow_stall = 0.0
	business._notify("Sigue a Carlos hasta la casa del cliente.")
	_target(customer,"Casa del cliente")
	_save()

func _solid(p: Vector3,size: Vector3,color: Color,layer: int = 1) -> StaticBody3D:
	return game.garage._solid(room,p,size,color,layer)

func _make_room() -> void:
	room = Node3D.new()
	add_child(room)
	room.position = ROOM
	_solid(Vector3(0,-.10,0),Vector3(8,.2,6),Color("#b3aba1"),2)
	_solid(Vector3(0,2.88,0),Vector3(8,.16,6),Color("#e8e2d6"))
	for i in range(4):
		var side := i>=2
		var sign_value := -1.0 if i%2==0 else 1.0
		var p := Vector3(sign_value*3.95,1.4,0) if side else Vector3(0,1.4,sign_value*2.95)
		var body := _solid(p,Vector3(.10,2.8,6) if side else Vector3(8,2.8,.10),OLD_PAINT)
		body.set_meta("paint_wall",i)
		_add_surface(i,p-(Vector3.RIGHT if side else Vector3.BACK)*sign_value*.056,Vector2(5.8 if side else 7.8,2.8),-sign_value*PI*.5 if side else (PI if sign_value>0 else 0.0))
	# Door covers exactly six wall cells; these are not counted as wall.
	var door := _solid(Vector3(0,1.05,2.83),Vector3(1.95,2.10,.10),Color("#79644e"))
	door.set_meta("paint_wall",DOOR_SURFACE)
	_add_surface(DOOR_SURFACE,Vector3(0,1.05,2.774),Vector2(1.95,2.10),PI)
	business._box(room,Vector3(.78,1.05,2.72),Vector3(.12,.08,.10),Color("#514a40"))
	var light := OmniLight3D.new()
	room.add_child(light)
	light.position = Vector3(0,2.65,0)
	light.omni_range = 10.0
	light.light_energy = 1.35
	light.light_color = Color("#fff0da")
	light.omni_attenuation = 1.05
	light.shadow_enabled = false
	# Ceiling fixture and floor protection are outside all paintable wall cells.
	business._box(room,Vector3(0,2.76,0),Vector3(.76,.06,.25),Color("#736f66"))
	business._box(room,Vector3(0,2.71,0),Vector3(.64,.05,.18),Color("#f5e8cb"))
	business._box(room,Vector3(-.23,.012,0),Vector3(1.60,.012,.85),Color("#c7baa1"))
	paint_progress = business._label(room,"",Vector3(0,2.55,2.87),Color("#f0e6c9"))
	paint_progress.rotation.y = PI
	_update_paint_progress()
	buckets.clear()
	for i in range(2):
		var can_root := Node3D.new()
		room.add_child(can_root)
		can_root.position = Vector3(-.65 if i==0 else .15,.25,0)
		var can := CylinderMesh.new()
		can.top_radius = .22
		can.bottom_radius = .19
		can.height = .42
		can.radial_segments = 12
		var mesh := MeshInstance3D.new()
		mesh.mesh = can
		mesh.material_override = business._mat(Color("#537c86"))
		can_root.add_child(mesh)
		var fill := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = .196
		disc.bottom_radius = .196
		disc.height = .012
		disc.radial_segments = 12
		fill.mesh = disc
		fill.material_override = business._mat(BLUE if i==0 else YELLOW)
		fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		can_root.add_child(fill)
		fill.position.y = .219
		var rim := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = .198
		ring.outer_radius = .228
		ring.rings = 12
		ring.ring_segments = 6
		rim.mesh = ring
		rim.material_override = business._mat(Color("#9d9b8d"))
		rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		can_root.add_child(rim)
		rim.position.y = .222
		var tag: Label3D = business._label(can_root,"AZUL" if i==0 else "AMARILLO",Vector3(0,.0,.228))
		tag.font_size = 28
		tag.pixel_size = .002
		tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		buckets.append(can_root)
	bucket = buckets[0]
	brush_item = Node3D.new()
	room.add_child(brush_item)
	brush_item.position = Vector3(.85,.07,.55)
	_make_brush(brush_item)
	brush_item.visible = not bool(state.brush)
	# Exit marker lies on the entrance wall; paint behind it is still possible.
	# The progress/exit label above the door is cosmetic, never a collider.
	_spawn_carlos(ROOM+Vector3(-2.8,0,-1.9))
	carlos.rotation.y = -PI*.5
	worker_brush = Node3D.new()
	carlos.arms[1].add_child(worker_brush)
	worker_brush.position = Vector3(0,-.51,.045)
	worker_brush.rotation.x = PI*.5
	# Keep the wrist animation unchanged; rotate only the brush geometry.
	var worker_brush_model := Node3D.new()
	worker_brush.add_child(worker_brush_model)
	worker_brush_model.rotation.y = PI
	worker_tip = _make_brush(worker_brush_model)
	worker_charge = 0
	worker_phase = "choose"
	worker_job = {}
	work_clock = 0.0
	_refresh_hand()
	_refresh_client()

func _make_brush(root: Node3D,offset: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	business._box(root,offset+Vector3(0,0,.105),Vector3(.065,.055,.23),Color("#95633d"))
	business._box(root,offset+Vector3(0,0,-.015),Vector3(.155,.064,.065),Color("#a7a5a0"))
	return business._box(root,offset+Vector3(0,0,-.108),Vector3(.153,.049,.128),Color("#cab99a"))

func _refresh_hand() -> void:
	if not is_instance_valid(hand):
		hand = Node3D.new()
		game.play_camera.add_child(hand)
		hand.position = HAND_REST
		hand.rotation.x = -.5
		hand_tip = _make_brush(hand)
		# One shared sphere for the glove/hand, independent of brush collision.
		var grip := MeshInstance3D.new()
		var grip_mesh := SphereMesh.new()
		grip_mesh.radius = .5
		grip_mesh.height = 1.0
		grip_mesh.radial_segments = 8
		grip_mesh.rings = 4
		grip.mesh = grip_mesh
		grip.material_override = business._mat(Color("#b98762"))
		grip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hand.add_child(grip)
		grip.position = Vector3(.01,-.025,.14)
		grip.scale = Vector3(.13,.105,.16)
	hand.visible = inside and _stage()==4 and bool(state.brush) and not _finished()
	if is_instance_valid(hand_tip): hand_tip.material_override = business._mat(_paint_color(String(state.get("color","blue"))) if int(state.charge)>0 else Color("#cab99a"))

func _animate_hand(offset: Vector3,angle: float,duration: float) -> void:
	if not is_instance_valid(hand) or not hand.visible: return
	if is_instance_valid(hand_tween): hand_tween.kill()
	hand.position = HAND_REST+offset
	hand.rotation.x = -.5+angle
	hand_tween = create_tween().set_parallel(true)
	hand_tween.tween_property(hand,"position",HAND_REST,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	hand_tween.tween_property(hand,"rotation:x",-.5,duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func _update_paint_progress() -> void:
	if not is_instance_valid(paint_progress): return
	paint_progress.text = "SALIR · E    |    %d%% PINTADO" % roundi(100.0*float(correct_tiles)/float(TOTAL))

func _enter() -> void:
	var first_entry := not bool(state.get("paint_dialogue_seen",false))
	inside = true
	previous_first = game.first_person
	state.stage = 4
	_clear_target()
	_make_room()
	game.player.global_position = ROOM+Vector3(0,.86,2.05)
	game.player.velocity = Vector3.ZERO
	game.first_person = true
	game.yaw = 0.0
	game.pitch = -.20
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	_save()
	if first_entry and not _finished():
		_stop_mission_voice()
		business.open_story(carlos,"Carlos",["Carlos: Mira, el azul para las paredes y el amarillo para la puerta. Él viene cuando terminemos a pagarnos.","Tú: Dale, no hay lío. Está fácil, yo hice algo de pintura en Miami."],"Empezar a pintar",_finish_paint_intro,"",_scene_clips(["paint_carlos","paint_player"]))
	else:
		business._notify("Recoge una brocha y mójala en la lata correcta.")

func _finish_paint_intro() -> void:
	state.paint_dialogue_seen = true
	_save()
	business.close()
	business._notify("Recoge una brocha y mójala en la lata correcta.")

func _exit_aim() -> bool:
	if not inside: return false
	var camera: Camera3D = game.play_camera
	var origin := camera.global_position-ROOM
	var direction := -camera.global_basis.z
	if direction.z<=.01: return false
	var depth := (2.88-origin.z)/direction.z
	if depth<=0.0 or depth>3.0: return false
	var p := origin+direction*depth
	return absf(p.x)<.975 and p.y>.05 and p.y<2.10

func _destroy_room() -> void:
	_stop_mission_voice()
	if is_instance_valid(hand_tween): hand_tween.kill()
	if is_instance_valid(hand):
		hand.hide()
		hand.position = HAND_REST
		hand.rotation.x = -.5
	paint_progress = null
	if is_instance_valid(worker_brush): worker_brush.queue_free()
	worker_brush = null
	if is_instance_valid(client): client.queue_free()
	client = null
	if is_instance_valid(room): room.queue_free()
	room = null
	walls.clear()
	images.clear()
	textures.clear()
	buckets.clear()

func _exit() -> void:
	inside = false
	_destroy_room()
	var point: Vector3 = customer.p
	game.player.global_position = point+Vector3.UP*.86
	game.player.velocity = Vector3.ZERO
	game.first_person = previous_first
	game._apply_camera_mode()
	if _stage()==4:
		_spawn_carlos(_companion_exit(point))
		_target(customer,"Casa del cliente")
	else:
		_spawn_carlos(_companion_exit(point))
		farewell = true
		farewell_time = 0.0
		follow_clock = 0.0
		follow_path = PackedVector3Array()
		follow_index = 0
		_mission_line("Carlos: Lleva eso pa’ tu casa y ármate una bici pa’ que te muevas más rápido.","carlos_farewell")
		if not world.garage_home_site.is_empty(): game.garage._set_waypoint(world.garage_home_site.door,"Mi garaje")
	_save()

func reset() -> void:
	if not inside: return
	inside = false
	_destroy_room()
	if not customer.is_empty():
		_spawn_carlos(customer.p)
		_target(customer,"Casa del cliente")
	_save()

func _cell_key(wall: int,x: int,y: int) -> String:
	return "%d:%d:%d" % [wall,x,y]

func _covered(wall: int,x: int,y: int) -> bool:
	return wall==1 and x in [3,4] and y>=1

func _columns(wall: int) -> int:
	return 2 if wall==DOOR_SURFACE else COLS

func _rows(wall: int) -> int:
	return 3 if wall==DOOR_SURFACE else ROWS

func _required(wall: int) -> String:
	return "yellow" if wall==DOOR_SURFACE else "blue"

func _paint_color(color: String) -> Color:
	return BLUE if color=="blue" else YELLOW

func _correct_count() -> int:
	var count := 0
	for wall in range(5):
		for y in range(_rows(wall)):
			for x in range(_columns(wall)):
				if _covered(wall,x,y): continue
				if String(state.painted.get(_cell_key(wall,x,y),""))==_required(wall): count += 1
	return count

func _finished() -> bool:
	return correct_tiles==TOTAL

func _add_surface(wall: int,p: Vector3,dimensions: Vector2,angle: float) -> void:
	var quad := QuadMesh.new()
	quad.size = dimensions
	var visual := MeshInstance3D.new()
	visual.mesh = quad
	room.add_child(visual)
	visual.position = p
	visual.rotation.y = angle
	var img := PaintVisual.new_surface(wall,_columns(wall),_rows(wall),state.painted,wall==DOOR_SURFACE)
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	mat.roughness = .82
	visual.material_override = mat
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	walls.append(visual)
	images.append(img)
	textures.append(tex)

func _paint_cell(wall: int,x: int,y: int,color: String) -> bool:
	if _covered(wall,x,y) or not color in ["blue","yellow"]: return false
	var key := _cell_key(wall,x,y)
	var previous := String(state.painted.get(key,""))
	if previous==color: return false
	if previous==_required(wall): correct_tiles -= 1
	if color==_required(wall): correct_tiles += 1
	state.painted[key] = color
	paint_dirty = true
	# Redraw only the changed cell and its neighbors; upload only this wall.
	PaintVisual.redraw(images[wall],wall,_columns(wall),_rows(wall),state.painted,wall==DOOR_SURFACE,Vector2i(x,y))
	textures[wall].update(images[wall])
	_update_paint_progress()
	return true

func _paint() -> void:
	if not bool(state.brush) or int(state.charge)<=0 or _finished(): return
	var camera: Camera3D = game.play_camera
	var origin := camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(origin,origin-camera.global_basis.z*2.8,1)
	ray.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or not hit.collider.has_meta("paint_wall"): return
	var wall := int(hit.collider.get_meta("paint_wall"))
	var mesh := walls[wall]
	var quad := mesh.mesh as QuadMesh
	var local := mesh.to_local(hit.position)
	var x := clampi(floori((local.x/quad.size.x+.5)*_columns(wall)),0,_columns(wall)-1)
	var y := clampi(floori((.5-local.y/quad.size.y)*_rows(wall)),0,_rows(wall)-1)
	var color := String(state.get("color","blue"))
	if _paint_cell(wall,x,y,color):
		state.charge = int(state.charge)-1
		_refresh_hand()
		_animate_hand(Vector3(0,.035,-.12),sin(float(state.charge)*1.8)*.22,.16)
		if color!=_required(wall) and warning_clock<=0.0:
			warning_clock = 6.0
			_mission_line("Carlos: ¡Ey, recuerda! Azul para la pared y amarillo para la puerta.","paint_warning")

# Carlos owns two full blue walls; the player handles the other two and the door.
# After finishing his assignment, Carlos still repairs incorrect colors anywhere.
const WORKER_WALLS := [2,0]

func _worker_next() -> Dictionary:
	for wall in [2,0,1,3,4]:
		for y in range(_rows(wall)):
			for x in range(_columns(wall)):
				if _covered(wall,x,y): continue
				var color := String(state.painted.get(_cell_key(wall,x,y),""))
				if color==_required(wall): continue
				if wall in WORKER_WALLS or not color.is_empty(): return {"wall":wall,"x":x,"y":y,"color":_required(wall),"repair":not color.is_empty() and color!=_required(wall)}
	return {}

func _worker_position(job: Dictionary) -> Vector3:
	var wall := int(job.wall)
	var mesh := walls[wall]
	var quad := mesh.mesh as QuadMesh
	var x := (float(job.x)+.5)/float(_columns(wall))-.5
	var point := mesh.to_global(Vector3(x*quad.size.x,0,.65))
	point.y = ROOM.y
	point.x = clampf(point.x,ROOM.x-3.1,ROOM.x+3.1)
	point.z = clampf(point.z,ROOM.z-2.2,ROOM.z+2.2)
	return point

func _worker_tick(delta: float) -> void:
	if not is_instance_valid(carlos) or _finished():
		if is_instance_valid(carlos):
			carlos.rotation.x = 0.0
			carlos.animate(delta,false)
		return
	if worker_phase=="choose":
		worker_job = _worker_next()
		if worker_job.is_empty():
			carlos.animate(delta,false)
			return
		worker_phase = "refill_walk" if worker_charge<=0 or worker_color!=String(worker_job.color) else "walk"
		work_clock = 0.0
	if worker_phase=="refill_walk":
		var can := buckets[0 if String(worker_job.color)=="blue" else 1]
		var at := can.global_position+Vector3(0,-.25,-.65)
		if carlos.walk_to(at,delta,1.8):
			worker_phase = "dip"
			work_clock = 0.0
		return
	if worker_phase=="dip":
		work_clock += delta
		carlos.rotation.y = 0.0
		carlos.arms[1].rotation.x = -.35+sin(work_clock*5.0)*.22
		carlos.rotation.x = .65*sin(minf(1.0,work_clock)*PI)
		worker_brush.rotation.x = PI*.5-.75*sin(minf(1.0,work_clock)*PI)
		if work_clock>=1.0:
			carlos.rotation.x = 0.0
			worker_brush.rotation.x = PI*.5
			worker_charge = 12
			worker_color = String(worker_job.color)
			if is_instance_valid(worker_tip): worker_tip.material_override = business._mat(_paint_color(worker_color))
			worker_phase = "walk"
		return
	if worker_phase=="walk":
		if carlos.walk_to(_worker_position(worker_job),delta,1.8):
			worker_phase = "paint"
			work_clock = 0.0
		return
	work_clock += delta
	var wall := int(worker_job.wall)
	var facing := -walls[wall].global_basis.z
	carlos.rotation.y = atan2(facing.x,facing.z)
	carlos.arms[1].rotation.x = -1.65+float(worker_job.y)*.35+sin(work_clock*8.0)*.18
	if work_clock>=.85:
		if _paint_cell(wall,int(worker_job.x),int(worker_job.y),worker_color):
			worker_charge -= 1
			if bool(worker_job.repair) and warning_clock<=0.0:
				warning_clock = 6.0
				_mission_line("Carlos: Voy a corregir esta parte, mano.","paint_repair")
		worker_phase = "choose"

func _refresh_client() -> void:
	if not _finished() or is_instance_valid(client): return
	client = Person.new()
	add_child(client)
	client.setup(945)
	client.remove_from_group("social_people")
	client.global_position = ROOM+Vector3(0,0,2.4)
	business._label(client,"Cliente",Vector3(0,2.03,0))
	_mission_line("Cliente: ¡Quedó buenísima! Ven para pagarte.","client_done")
	_refresh_hand()

func _payment() -> void:
	if _stage()!=4 or not _finished(): return
	_stop_mission_voice()
	business.open_story(client,"Cliente",["Cliente: Asere, me robaron el dinero al salir del cajero. No tengo efectivo.","Cliente: Tengo una goma de bicicleta en buen estado. ¿Te sirve como pago?","Tú: Bueno, sí, qué remedio. A ver qué hago con eso."],"Recibir la goma",_accept_wheel,"",_scene_clips(["client_payment1","client_payment2","player_payment"]))

func _accept_wheel() -> void:
	if _stage()!=4 or not _finished(): return
	if not game.garage.receive_paint_wheel():
		business._notify("Libera las manos para recibir la goma.")
		return
	state.stage = 5
	business.ledger.change_reputation("Carlos",8)
	game.garage._refresh_preview()
	state.brush = false
	state.charge = 0
	_save()
	business.ledger.add_message("Carlos","¡Trabajo terminado! Lleva esa goma al garaje. Es el comienzo de tu bicicleta.")
	_save()
	business.close()
	_refresh_hand()
	business._notify("Goma recibida · Llévala a tu casa e instálala en la bicicleta.")
	if not world.garage_home_site.is_empty(): game.garage._set_waypoint(world.garage_home_site.door,"Mi garaje")
	_save()

func _companion_exit(point: Vector3) -> Vector3:
	for offset in [Vector3(1.1,0,0),Vector3(-1.1,0,0),Vector3(0,0,1.1),Vector3(0,0,-1.1)]:
		var ground := _ground(point+offset)
		if not ground.is_empty() and world.pedestrian_space_clear(carlos,ground.p,.65,false): return ground.p
	return point

func _farewell_tick(delta: float) -> void:
	if not is_instance_valid(carlos): 
		farewell = false
		return
	farewell_time += delta
	if farewell_time<2.0:
		carlos.animate(delta,false)
		return
	follow_clock -= delta
	if follow_path.is_empty() and not home.is_empty() and follow_clock<=0.0:
		follow_clock = 2.0
		follow_path = game.monte_pedestrians.route_between(carlos.global_position,home.p)
		if follow_path.is_empty(): follow_path = PackedVector3Array([home.p]) if world.pedestrian_segment_clear(carlos.global_position,home.p) else PackedVector3Array()
	if follow_index<follow_path.size():
		var next := follow_path[follow_index]
		var step := carlos.global_position.move_toward(next,delta*1.8)
		if world.pedestrian_segment_clear(carlos.global_position,step) and world.pedestrian_space_clear(carlos,step):
			if carlos.walk_to(next,delta,1.8): follow_index += 1
	if follow_index>=follow_path.size() or farewell_time>60.0:
		if carlos.global_position.distance_to(game.player.global_position)>20.0 or (not home.is_empty() and carlos.global_position.distance_to(home.p)<1.0):
			carlos.hide()
			farewell = false

func _follow(delta: float) -> void:
	if not is_instance_valid(carlos): return
	var vehicle: bool = game.driving or game.taxi_riding
	if vehicle:
		carlos.hide()
		was_vehicle = true
		exit_retry = 0.0
		return
	var player_at: Vector3 = game.player.global_position-Vector3.UP*.86
	var target: Vector3 = player_at
	if target.distance_to(customer.p)<7.0: target = customer.p
	if was_vehicle:
		exit_retry -= delta
		if exit_retry>0.0: return
		exit_retry = .5
		# Passenger ride uses existing taxi/van; find a free sidewalk exit.
		for offset in [Vector3(1.2,0,0),Vector3(-1.2,0,0),Vector3(0,0,1.2),Vector3(0,0,-1.2),Vector3.ZERO]:
			var ground := _ground(target+offset)
			if ground.is_empty() or not world.pedestrian_space_clear(carlos,ground.p,.7,false): continue
			carlos.global_position = ground.p
			carlos.show()
			was_vehicle = false
			break
		if was_vehicle:
			for distance in [2.5,4.0,6.0,8.0]:
				for angle in range(8):
					var direction := Vector3(cos(float(angle)*TAU/8.0),0,sin(float(angle)*TAU/8.0))
					var ground := _ground(target+direction*float(distance))
					if ground.is_empty() or not world.pedestrian_space_clear(carlos,ground.p,.7,false): continue
					carlos.global_position = ground.p
					carlos.show()
					was_vehicle = false
					break
				if not was_vehicle: break
		if was_vehicle: return
	# Carlos leads the first walk and waits when the player falls behind.
	if _stage()==3:
		if carlos.global_position.distance_to(player_at)>7.0 or carlos.global_position.distance_to(customer.p)<1.0:
			carlos.animate(delta,false)
			return
		target = customer.p
	if carlos.global_position.distance_to(customer.p)<1.3 and target.distance_to(customer.p)<6.0:
		carlos.animate(delta,false)
		return
	if carlos.global_position.distance_to(target)<(0.8 if _stage()==3 else 1.9):
		carlos.animate(delta,false)
		return
	follow_clock -= delta
	if follow_clock<=0.0:
		follow_clock = 1.0
		var ground := _ground(target)
		if not ground.is_empty(): target = ground.p
		if carlos.global_position.distance_to(target)<8.0 and world.pedestrian_segment_clear(carlos.global_position,target):
			follow_path = PackedVector3Array([target])
		else:
			follow_path = game.monte_pedestrians.route_between(carlos.global_position,target)
			if follow_path.is_empty(): follow_path = game.monte_pedestrians.route_between(carlos.global_position,customer.p)
			if follow_path.is_empty() and world.pedestrian_segment_clear(carlos.global_position,customer.p): follow_path = PackedVector3Array([customer.p])
		follow_index = 0
	if follow_index>=follow_path.size():
		carlos.animate(delta,false)
		return
	var next := follow_path[follow_index]
	var step := carlos.global_position.move_toward(next,delta*3.6)
	if world.pedestrian_segment_clear(carlos.global_position,step) and world.pedestrian_space_clear(carlos,step):
		follow_stall = 0.0
		if carlos.walk_to(next,delta,3.6): follow_index += 1
	else:
		follow_stall += delta
		var heading := (next-carlos.global_position).normalized()
		var side := Vector3(-heading.z,0,heading.x)
		for sign_value in [-1.0,1.0]:
			var candidate := step+side*float(sign_value)*minf(.15,delta*3.6)
			if world.pedestrian_segment_clear(carlos.global_position,candidate) and world.pedestrian_space_clear(carlos,candidate):
				carlos.walk_to(candidate,delta,3.6)
				break
		if follow_stall>2.0:
			follow_clock = 0.0
			follow_stall = 0.0

# Run incoming calls independently of the main physics mission dispatch.
# Only the full painting/companion simulation still depends on tick().
func _process(delta: float) -> void:
	if game==null or business==null or not is_instance_valid(game.garage): return
	if call_session_offered or int(state.get("call_dialogue_version",0))>=CALL_DIALOGUE_VERSION: return
	var blocker := ""
	if not _call_unlocked(): blocker = "primera inversión pendiente"
	elif is_instance_valid(game.arrival_story) and game.arrival_story.active(): blocker = "historia de llegada activa"
	elif game.home_exit_loading: blocker = "cargando la ciudad"
	elif inside or game.garage.inside: blocker = "dentro de una casa"
	elif game.driving or game.taxi_riding or game.bus_riding or game.garage.riding: blocker = "en vehículo"
	elif game.touch_blocked(): blocker = "menú, mapa o diálogo abierto"
	if blocker!=call_last_blocker:
		call_last_blocker = blocker
		print("MyCity Carlos: ", "listo para llamar" if blocker.is_empty() else blocker, "; Albertico=",business.ledger.stage,"; Carlos=",_stage())
	if not blocker.is_empty():
		call_wait = 0.0
		call_ring_started = false
		return
	call_wait += delta
	if call_wait>=8.0 and not call_ring_started:
		call_ring_started = true
		if is_instance_valid(business.phone_ring): business.phone_ring.play()
	if call_wait>=9.0:
		call_session_offered = true
		_prepare_call()
		print("MyCity Carlos: llamada entrante iniciada")
		_play_call(CALL_INTRO,0)

func tick(delta: float) -> void:
	if _stage()<=1: return
	if _stage()==5:
		if farewell: _farewell_tick(delta)
		return
	if not inside and not is_instance_valid(carlos):
		locate_wait -= delta
		if locate_wait>0.0: return
		locate_wait = 15.0 if locate_reported else 5.0
		if not _locate(): return
		_spawn_carlos(home.p if _stage()<=3 else customer.p)
		_target(home if _stage()==2 else customer,"Casa de Carlos · Flores y Estévez" if _stage()==2 else "Casa del cliente")
	if inside:
		if business.modal_open() or _stage()!=4: return
		warning_clock = maxf(0.0,warning_clock-delta)
		brush_clock += delta
		paint_save_clock += delta
		if paint_dirty and paint_save_clock>=2.0:
			paint_dirty = false
			paint_save_clock = 0.0
			_save()
		if is_instance_valid(client): client.walk_to(ROOM+Vector3(1.4,0,1.7),delta,1.4)
		_worker_tick(delta)
		if brush_clock>=.13 and game.gameplay_input() and game.primary_held():
			brush_clock = 0.0
			_paint()
		if _finished() and paint_dirty:
			paint_dirty = false
			_save()
		_refresh_client()
	elif _stage() in [3,4] and not game.garage.inside and not game.bus_riding and not game.garage.riding:
		_follow(delta)
