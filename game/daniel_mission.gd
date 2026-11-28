extends Node3D
# A social chapter, independent of money rewards and external services.
const Person = preload("res://street_person.gd")
const Domino = preload("res://daniel_domino.gd")
const Leisure = preload("res://leisure_rules.gd")
const PartyPlay = preload("res://party_play.gd")
const ROOM := Vector3(65,110,0)
const TRACKS := ["01_fuego","02_my_oxygen","03_reggaeton_fiesta","04_music_box","05_tumbao","06_old_school_salsa","07_rumba","08_afro_cuban","09_bailando","10_bajo_la_luna"]
# Initial rhythm-game tempos, adjustable after listening to the real audio.
const TEMPOS := [95,95,100,92,108,100,110,105,125,125]
var game
var world
var business
var state: Dictionary
var inside := false
var previous_first := false
var room: Node3D
var marker: Node3D
var speaker: AudioStreamPlayer3D
var exterior: AudioStreamPlayer3D
var dancers: Array[Dictionary] = []
var track := 0
var call_wait := 0.0
var elapsed := 0.0
var dance_time := 0.0
var dance_hits := 0
var dance_attempts := 0
var dance_active := false
var rhythm_singing := false
var exterior_retry := 0.0
var beat_label: Label
var next_tap := 0.0
var smoking := 0.0
var cigarette: Node3D
var drink_prop: Node3D
var drink_time := 0.0
var play: Node
var guests: Array[Dictionary] = []
var party_lights: Array[OmniLight3D] = []
var event_clock := 0.0
var power_cut := false
var quiet_music := false
var party_event := ""
var guest_clock := 0.0
var last_phase := -1
var event_cursor := 0
var event_order: Array[String] = []
var escort: Person
var guest_nav := AStarGrid2D.new()
var party_photo: Node3D

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	business = game.business
	var life: Dictionary = business.ledger.life_data
	if not life.has("daniel_party"): life.daniel_party = {"stage":0,"activities":{},"drinks":0,"domino":{},"contacts":{},"track":0}
	state = life.daniel_party
	play = PartyPlay.new()
	add_child(play)
	play.setup(self)
	track = posmod(int(state.get("track",0)),TRACKS.size())
	marker = Node3D.new()
	add_child(marker)
	business._arrow(marker,Vector3.UP*2.2,Color("#d5a6ff"))
	marker.hide()
	exterior = AudioStreamPlayer3D.new()
	add_child(exterior)
	exterior.max_distance = 26.0
	exterior.unit_size = 4.0
	exterior.volume_db = -16.0
	exterior.attenuation_filter_cutoff_hz = 1300.0
	exterior.finished.connect(_next_track)
	# Reenter the house after restart; never restore the player into an unloaded room.
	if int(state.stage)==2: _target(false)

func _save() -> void:
	business.ledger.save_game()

func completed() -> bool:
	return int(state.stage)>=3

func _ready_for_call() -> bool:
	return game.carlos_mission._stage()==5 and bool(game.garage.state.get("wheel_tutorial",false))

func _busy() -> bool:
	return game.driving or game.taxi_riding or game.bus_riding or game.garage.riding or game.building_mode or game.carlos_mission.inside or (game.arrival_story!=null and game.arrival_story.active())

func _house() -> Vector3:
	var row: Dictionary = state.get("house",{})
	return Vector3(float(row.get("x",INF)),float(row.get("y",0)),float(row.get("z",INF)))

func _find_house() -> bool:
	if _house().is_finite(): return true
	var origin: Vector3 = world.home_spawn
	var best := INF
	var selected := Vector3.INF
	# Use a real, verified residential doorway. Optional local GPS override
	# picks the closest verified home to the supplied latitude/longitude.
	var config := "user://daniel_house.json"
	var preferred := Vector3.INF
	if FileAccess.file_exists(config):
		var f := FileAccess.open(config,FileAccess.READ)
		if f!=null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary and data.has("lat") and data.has("lon"):
				preferred = world.geography.project(float(data.lat),float(data.lon))
			f.close()
	for entry in world.npc_doorways:
		if String(entry.get("kind",""))!="home": continue
		var door: Vector3 = entry.threshold
		var distance := origin.distance_to(door)
		if preferred.is_finite():
			if door.distance_to(preferred)>40.0: continue
		elif distance<35.0 or distance>350.0: continue
		if not game.carlos_mission.customer.is_empty():
			var customer_point: Vector3 = game.carlos_mission.customer.get("p",Vector3.INF)
			if door.distance_to(customer_point)<12.0: continue
		var site: Dictionary = game.carlos_mission._door_data(entry)
		if site.is_empty(): continue
		var point: Vector3 = site.p
		var score := point.distance_to(preferred) if preferred.is_finite() else absf(distance-125.0)
		if score<best:
			best = score
			selected = point
	if not selected.is_finite(): return false
	state.house = {"x":selected.x,"y":selected.y,"z":selected.z}
	_save()
	return true

func _target(gps: bool = true) -> void:
	var p := _house()
	if not p.is_finite(): return
	marker.global_position = p
	marker.show()
	exterior.global_position = p+Vector3.UP
	if gps: game.garage._set_waypoint(p,"Casa de Daniel")

func objective() -> String:
	match int(state.stage):
		1: return "Responde la llamada de Daniel."
		2:
			if inside: return "Disfruta la fiesta · "+str(state.activities.size())+" actividades"
			return "Visita la casa de Daniel."
	return ""

func open_call() -> void:
	if int(state.stage)==0 and not _ready_for_call(): return
	business._open("Daniel", "Asere, ¿qué bolá? Hace rato que no nos vemos. Llégate a mi casa." if not completed() else "¡Mano! Cuando quieras, ven a jugar dominó o pasar el rato.")
	if int(state.stage)<2: business._button("Dale, mándame la ubicación",_accept)
	else: business._button("Marcar casa de Daniel",_mark_home)
	business._button("Ahora no",business.close)

func _accept() -> void:
	if not _find_house():
		business._notify("No encontramos una entrada libre. Puedes llamar a Daniel de nuevo.")
		business.close()
		return
	state.stage = 2
	business.ledger.add_message("Daniel","Te espero en casa, mano. Ven cuando puedas.")
	_target()
	_save()
	business.close()

func _mark_home() -> void:
	if _find_house(): _target()
	_save()
	business.close()

func action_text() -> String:
	if inside:
		if play.active(): return play.hint()
		var p: Vector3 = game.player.global_position-ROOM
		if p.distance_to(Vector3(0,.86,5.1))<2.0:
			if is_instance_valid(escort): return "[E] Acompañar al invitado hasta la puerta"
			return "[E] Salir de casa de Daniel"
		if p.distance_to(Vector3(-3,.86,-1.9))<2.2: return "[E] Jugar dominó"
		if p.distance_to(Vector3(3,.86,-3.2))<2.4:
			if power_cut: return "[E] Conectar batería de respaldo"
			if party_event=="Vecino pide bajar el volumen": return "[E] Bajar volumen por el vecino"
			return "[E] Equipo de música"
		if p.distance_to(Vector3(3,.86,2.5))<2.2: return "[E] Bebidas y comida"
		if p.distance_to(Vector3(-3,.86,2.8))<2.2: return "[E] Conversar con Daniel"
		return "[E] Bailar · [F] Invitar / conversar"
	if int(state.stage)>=2 and _house().is_finite() and not _busy() and not game.garage.inside and game.player.global_position.distance_to(_house()+Vector3.UP*.86)<2.8:
		return "[E] Entrar a casa de Daniel"
	return ""

func interact() -> bool:
	var action := action_text()
	if action.is_empty(): return false
	if play.active(): return true
	if not inside:
		if game.garage._free_hands(): _enter()
		else: business._notify("Deja lo que llevas antes de entrar.")
	elif action.contains("Acompañar"): _finish_escort()
	elif action.contains("batería") or action.contains("volumen"): _resolve_event()
	elif action.contains("Salir"): _leave()
	elif action.contains("dominó"): play.begin_domino()
	elif action.contains("música"): _music_menu()
	elif action.contains("Bebidas"): _drink_menu()
	elif action.contains("Daniel"): _daniel_menu()
	else: play.begin_dance(false)
	return true

func _solid(p: Vector3,size: Vector3,color: Color) -> void:
	var body := StaticBody3D.new()
	room.add_child(body)
	body.position = p
	business._box(body,Vector3.ZERO,size,color)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)

func _label(value: String,p: Vector3) -> void:
	business._label(room,value,p)

func _guest(style: int,p: Vector3,name_value: String,dancing: bool) -> Person:
	var person := Person.new()
	room.add_child(person)
	person.setup(style)
	person.position = p
	person.remove_from_group("social_people")
	person.remove_from_group("pedestrian_spacing")
	person.set_meta("citizen_name",name_value)
	if dancing:
		var entry := {"node":person,"p":p,"phase":float(dancers.size())*.9,"name":name_value,"personality":["sociable","tranquila","alegre","reservado"][dancers.size()%4],"role":"dance","timer":8.0+float(dancers.size())*3.0,"slot":dancers.size()}
		dancers.append(entry)
		guests.append(entry)
	return person

func _enter() -> void:
	inside = true
	previous_first = game.first_person
	marker.hide()
	exterior.stop()
	room = Node3D.new()
	add_child(room)
	room.position = ROOM
	last_phase = -1
	event_clock = 0.0
	party_event = ""
	event_order = ["Apagón","Vecino pide bajar el volumen","Competencia de baile","Acompañar a un invitado","Recuerdos de infancia"]
	event_order.shuffle()
	event_cursor = 0
	escort = null
	power_cut = false
	quiet_music = false
	guest_clock = 0.0
	var wall := Color("#d2b8a0")
	_solid(Vector3(0,-.10,0),Vector3(12,.20,12),Color("#a99b88"))
	_solid(Vector3(-5.9,1.6,0),Vector3(.2,3.2,12),wall)
	_solid(Vector3(5.9,1.6,0),Vector3(.2,3.2,12),wall)
	_solid(Vector3(0,1.6,-5.9),Vector3(12,3.2,.2),wall)
	_solid(Vector3(0,1.6,5.9),Vector3(12,3.2,.2),wall)
	_solid(Vector3(0,3.2,0),Vector3(12,.18,12),wall)
	_solid(Vector3(0,1.05,5.72),Vector3(1.25,2.1,.12),Color("#77584c"))
	_label("SALIR",Vector3(0,2.5,5.6))
	_solid(Vector3(-3,.74,-1.9),Vector3(1.60,.12,1.55),Color("#725b42"))
	for x in [-3.65,-2.35]:
		for z in [-2.52,-1.28]: business._box(room,Vector3(x,.35,z),Vector3(.09,.70,.09),Color("#5c4735"))
	for p in [Vector3(-1.93,0,-1.9),Vector3(-4.08,0,-1.9),Vector3(-3,0,-3.02),Vector3(-3,0,-.78)]:
		business._box(room,p+Vector3.UP*.43,Vector3(.45,.09,.45),Color("#856649"))
		for dx in [-.17,.17]:
			for dz in [-.17,.17]: business._box(room,p+Vector3(dx,.20,dz),Vector3(.045,.40,.045),Color("#594634"))
	_solid(Vector3(3,.8,2.7),Vector3(1.6,.14,.9),Color("#725b42"))
	for i in range(5):
		business._box(room,Vector3(2.5+float(i)*.22,.99,2.7),Vector3(.10,.25,.10),Color("#567641") if i%2==0 else Color("#a77736"))
	# The playable domino controller builds the actual hand and chain.
	_solid(Vector3(3,.75,-3.2),Vector3(.85,1.5,.5),Color("#30343c"))
	business._box(room,Vector3(3,.9,-2.93),Vector3(.62,.60,.06),Color("#12151b"))
	_label("DOMINÓ",Vector3(-3,1.8,-1.9))
	_label("MÚSICA",Vector3(3,1.95,-3.2))
	# A small backup battery is physically beside the speaker.
	business._box(room,Vector3(3.64,.24,-3.2),Vector3(.34,.44,.30),Color("#485258"))
	business._box(room,Vector3(3.64,.48,-3.2),Vector3(.20,.05,.10),Color("#202527"))
	party_photo = Node3D.new()
	room.add_child(party_photo)
	party_photo.position = Vector3(-5.74,1.70,2.65)
	party_photo.rotation.y = PI*.5
	business._box(party_photo,Vector3.ZERO,Vector3(.54,.38,.06),Color("#74573d"))
	business._box(party_photo,Vector3(0,0,.04),Vector3(.46,.30,.015),Color("#c5aa80"))
	# Placeholder illustration, not a fabricated photograph of real people.
	for x in [-.12,.12]:
		business._box(party_photo,Vector3(x,.045,.052),Vector3(.065,.065,.008),Color("#806047"))
		business._box(party_photo,Vector3(x,-.055,.052),Vector3(.09,.13,.008),Color("#546d83"))
	_label("BEBIDAS",Vector3(3,1.75,2.7))
	_guest(915,Vector3(-3,0,2.8),"Daniel",false).rotation.y = 1.4
	_label("Daniel",Vector3(-3,2.05,2.8))
	for i in range(3):
		var p: Vector3 = [Vector3(-4.1,0,-1.9),Vector3(-3,0,-3.1),Vector3(-3,0,-.7)][i]
		var guest := _guest(920+i,p,["Mario","Luis","Rafa"][i],false)
		guest.rotation.y = atan2(-3.0-p.x,-1.9-p.z)
		guest.position.y = -.34
		for leg in guest.limbs: leg.rotation.x = -1.35
		for knee in guest.knees: knee.rotation.x = 1.40
		for arm in guest.arms: arm.rotation.x = -1.0
		play.register_opponent(guest)
	for i in range(4):
		var p := Vector3(-.8+float(i%2)*1.6,0,-2.0+floorf(float(i)/2.0)*2.0)
		_guest([919,922,925,923][i],p,["Laura","María","Ana","Javier"][i],true)
	for i in range(3):
		_guest([931,934,937][i],Vector3(-1.8+float(i)*1.7,0,3.1),["Lili","Elena","Nora"][i],true)
	for i in range(3):
		var light := OmniLight3D.new()
		room.add_child(light)
		light.position = Vector3(-3+float(i)*3,2.8,-.5)
		light.light_color = [Color("#ffc69d"),Color("#c29dff"),Color("#9fcbff")][i]
		light.omni_range = 7.5
		light.light_energy = 1.1
		light.shadow_enabled = false
		party_lights.append(light)
	speaker = AudioStreamPlayer3D.new()
	room.add_child(speaker)
	speaker.position = Vector3(3,1.25,-3.2)
	speaker.unit_size = 5.0
	speaker.max_distance = 25.0
	speaker.volume_db = -7.0
	speaker.finished.connect(_next_track)
	game.player.global_position = ROOM+Vector3(0,.86,4.5)
	game.player.velocity = Vector3.ZERO
	game.first_person = true
	game.yaw = 0.0
	game.pitch = -.08
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	game._update_visual_lighting(true)
	_build_guest_nav()
	play.rebuild_table()
	_refresh_party_phase()
	_play_track()
	if not bool(state.get("welcomed",false)):
		state.welcomed = true
		_save()
		business._open("¡Sorpresa!","Daniel: ¡Asere! Hoy no se habla de trabajo. Ven, que estamos entre amigos. Hay dominó, baile, comida y música.")
		business._button("¡Vamos a pasarla bien!",business.close)

func _activity(key: String) -> void:
	state.activities[key] = true
	if key in ["amistad","social","domino","baile","canto","musica","evento","descanso"]:
		Leisure.reward(business.life.state,"daniel_"+key,8.0 if key!="descanso" else 4.0,6.0,90.0)
	business.life._update_hud()
	_save()

func _daniel_menu() -> void:
	business._open("Daniel","¡Cuántos recuerdos, mano! Desde chiquitos juntos. Hoy deja los problemas a un lado.")
	if not party_event.is_empty(): business._button("Situación: "+party_event,_event_menu)
	business._button("Recordar la infancia",_remember)
	business._button("Descansar aquí un rato",_rest_here)
	business._button("Despedirme de la fiesta",_finish_party)
	business._button("Seguir disfrutando",business.close)

func _rest_here() -> void:
	var life = business.life
	var duration := 180.0
	# Home cooking and paid orders still advance even while visiting a friend.
	game.garage._advance_home_sleep(duration)
	life.advance_sleep_economy(duration)
	life.advance_game_minutes(duration)
	life.state.fatigue = maxf(0.0,float(life.state.fatigue)-35.0)
	life.state.fullness = maxf(0.0,float(life.state.fullness)-duration*.025)
	life.state.party_alcohol = maxf(0.0,float(life.state.get("party_alcohol",0.0))-duration*.45)
	if is_instance_valid(world.pedestrian_router): world.pedestrian_router.advance_residents()
	life._update_hud()
	_activity("descanso")
	business._open("Descansaste en casa de Daniel","Daniel: Tómate tu tiempo, mano. No hay apuro.")
	business._button("Volver",business.close)

func _remember() -> void:
	_activity("amistad")
	business._open("Un rato entre amigos","Daniel: La vida cambia, asere, pero los amigos de verdad siguen ahí. Me alegro de que hayas vuelto.\nTú: Yo también, mano. Hacía falta un día así.")
	business._button("Volver a la fiesta",business.close)

func _social_menu() -> void:
	business._open("Pista de baile","Comparte con los invitados o practica el ritmo.")
	business._button("Bailar",play.begin_dance.bind(false))
	business._button("Cantar siguiendo el ritmo",play.begin_dance.bind(true))
	for entry in guests:
		if entry.node.visible: business._button("Invitar a bailar a "+String(entry.name),_invite.bind(String(entry.name)))
	for name_value in ["Laura","María","Ana","Javier"]:
		business._button("Conversar con "+name_value,_meet.bind(name_value))
	business._button("Volver",business.close)

func _meet(name_value: String) -> void:
	if not bool(state.contacts.get(name_value,false)):
		state.contacts[name_value] = true
		business.ledger.add_message(name_value,"¡Qué bueno conocerte en casa de Daniel! Nos vemos por el barrio.")
		business.ledger.change_reputation(name_value,2)
	_activity("social")
	business._open(name_value,"¡Qué bolá! Qué bueno que viniste. Nos vemos en otra fiesta.")
	business._button("Volver",_social_menu)

func _drink_menu() -> void:
	business._open("Compartir","Puedes disfrutar sin beber alcohol ni fumar. Bebidas tomadas: %d" % int(state.drinks))
	business._button("Brindar con ron",_drink.bind(true),drink_time>0.0)
	business._button("Refresco o agua",_drink.bind(false),drink_time>0.0)
	business._button("Comer algo",_eat)
	business._button("Fumar un cigarro (opcional)",_smoke,smoking>0.0)
	business._button("Volver",business.close)

func _drink(alcohol: bool) -> void:
	if drink_time>0.0: return
	drink_time = 2.0
	if alcohol:
		state.drinks = int(state.drinks)+1
		business.life.state.party_alcohol = minf(100.0,float(business.life.state.get("party_alcohol",0.0))+16.0)
	_activity("brindis")
	drink_prop = Node3D.new()
	game.play_camera.add_child(drink_prop)
	drink_prop.position = Vector3(.25,-.26,-.48)
	business._box(drink_prop,Vector3.ZERO,Vector3(.09,.14,.09),Color("#d7b56e") if alcohol else Color("#8dd2dd"))
	business.close()

func _eat() -> void:
	business.life.state.fullness = minf(100.0,float(business.life.state.fullness)+15.0)
	_activity("comida")
	business._notify("Compartiste comida con tus amigos.")
	business.close()

func _smoke() -> void:
	if smoking>0.0: return
	smoking = 8.0
	cigarette = Node3D.new()
	game.play_camera.add_child(cigarette)
	cigarette.position = Vector3(.26,-.25,-.52)
	business._box(cigarette,Vector3.ZERO,Vector3(.017,.09,.017),Color("#e5dec7"))
	business._box(cigarette,Vector3(0,.05,0),Vector3(.019,.014,.019),Color("#bb6944"))
	_activity("cigarro")
	business.close()

func _domino_menu() -> void:
	var g: Dictionary = state.domino
	if g.is_empty(): 
		state.domino = Domino.start()
		g = state.domino
		_save()
	if bool(g.done):
		business._open("Dominó",String(g.log))
		business._button("Otra partida",_new_domino)
		business._button("Volver",business.close)
		return
	business._open("Dominó · doble nueve","Tú y Luis contra Mario y Rafa. Extremos: %d | %d\nFichas rivales: %d / %d / %d\n%s" % [int(g.left),int(g.right),g.hands[1].size(),g.hands[2].size(),g.hands[3].size(),String(g.log)])
	var chain: Array = g.get("chain",[])
	if not chain.is_empty():
		var table := Label.new()
		var tiles: Array[String] = []
		for tile in chain: tiles.append("%d:%d" % tile)
		table.text = "Mesa: "+ " | ".join(tiles)
		table.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		business.content.add_child(table)
	var hand: Array = g.hands[0]
	var grid := GridContainer.new()
	grid.columns = 3
	business.content.add_child(grid)
	var playable := false
	for i in range(hand.size()):
		var tile: Array = hand[i]
		var left := Domino.legal(g,tile,true)
		var right := Domino.legal(g,tile,false)
		if left:
			playable = true
			_tile_button(grid,"%d-%d · I" % tile,_domino_play.bind(i,true))
		if right and int(g.left)!=int(g.right):
			playable = true
			_tile_button(grid,"%d-%d · D" % tile,_domino_play.bind(i,false))
		if not left and not right: _tile_button(grid,"%d-%d" % tile,_domino_menu,true)
	business._button("Paso",_domino_pass,playable)
	business._button("Pausar partida",business.close)

func _tile_button(grid: GridContainer,label_value: String,callback: Callable,disabled_value: bool = false) -> void:
	var button := Button.new()
	button.text = label_value
	button.disabled = disabled_value
	button.pressed.connect(callback)
	grid.add_child(button)

func _new_domino() -> void:
	state.domino = Domino.start()
	_save()
	_domino_menu()

func _domino_play(index: int,left: bool) -> void:
	if Domino.play(state.domino,index,left):
		Domino.opponents(state.domino)
		_activity("domino")
	_domino_menu()

func _domino_pass() -> void:
	if Domino.pass_turn(state.domino):
		Domino.opponents(state.domino)
		_save()
	_domino_menu()

func _start_rhythm(singing: bool) -> void:
	dance_active = true
	rhythm_singing = singing
	dance_time = 0.0
	dance_hits = 0
	dance_attempts = 0
	next_tap = 0.0
	business._open("Canta" if singing else "Baila","Pulsa al ritmo del indicador. Doce intentos. El juego no depende de beber.")
	beat_label = Label.new()
	beat_label.text = "Preparado..."
	business.content.add_child(beat_label)
	business._button("¡Al ritmo!",_tap)
	business._button("Terminar",_end_rhythm)

func _period() -> float:
	return 60.0/float(TEMPOS[track])

func _rhythm_clock() -> float:
	if is_instance_valid(speaker) and speaker.playing: return speaker.get_playback_position()
	return dance_time if dance_active else elapsed

func _tap() -> void:
	if not dance_active or dance_time<next_tap: return
	var phase := fposmod(_rhythm_clock(),_period())
	if minf(phase,_period()-phase)<.16: dance_hits += 1
	dance_attempts += 1
	next_tap = dance_time+_period()*.7
	if dance_attempts>=12: _end_rhythm()

func _end_rhythm() -> void:
	dance_active = false
	if dance_attempts>0: _activity("canto" if rhythm_singing else "baile")
	business._open("¡Qué ritmo!","Aciertos: %d de %d. Sigue practicando cuando quieras." % [dance_hits,dance_attempts])
	business._button("Volver",business.close)

func _stream(index: int) -> AudioStream:
	for directory in ["user://daniel_music/","res://audio/daniel/"]:
		for ext in [".ogg",".mp3"]:
			var path: String = directory+TRACKS[index]+ext
			if directory.begins_with("res") and ResourceLoader.exists(path): return load(path) as AudioStream
			if FileAccess.file_exists(path):
				if ext==".mp3": return AudioStreamMP3.load_from_file(path)
				else: return AudioStreamOggVorbis.load_from_file(path)
	return null

func _play_track() -> void:
	var output: AudioStreamPlayer3D = speaker if inside else exterior
	if not is_instance_valid(output): return
	for i in range(TRACKS.size()):
		var index := (track+i)%TRACKS.size()
		var audio := _stream(index)
		if audio==null: continue
		track = index
		output.stream = audio
		output.play()
		if inside:
			output.stream_paused = power_cut
			output.volume_db = -15.0 if quiet_music else -7.0
		return
	output.stop()

func _next_track() -> void:
	track = (track+1)%TRACKS.size()
	state.track = track
	_play_track()
	_save()

func _music_menu() -> void:
	business._open("Equipo de música","Playlist local · "+TRACKS[track]+"\nSi no hay archivos instalados, la fiesta funciona sin música. No requiere Internet.")
	for i in range(TRACKS.size()):
		business._button(TRACKS[i],_select_track.bind(i))
	business._button("Siguiente canción",_next_and_menu)
	business._button("Volver",business.close)

func _select_track(index: int) -> void:
	track = index
	state.track = index
	_play_track()
	_activity("musica")
	business.close()

func _next_and_menu() -> void:
	_next_track()
	_music_menu()

func _finish_party() -> void:
	if not completed():
		if state.activities.size()<2:
			business._open("Daniel","¡Pero si acabas de llegar! Comparte dos actividades antes de despedirte. También puedes salir y regresar más tarde.")
			business._button("Seguir disfrutando",business.close)
			business._button("Salir por ahora",_exit)
			return
		state.stage = 3
		state.completed_at = float(business.life.state.day)*1440.0+float(business.life.state.minutes)
		business.ledger.change_reputation("Daniel",10)
		business.ledger.add_message("Daniel","Gracias por venir, hermano. La vida no es solo trabajar. Esta es tu casa.")
		_save()
		business.close()
		_exit()
		business.show_mission_reward("Amistad recuperada","Una noche entre amigos")
	else:
		business.close()
		_exit()

func _leave() -> void:
	business._open("Salir de la fiesta","Puedes volver cuando quieras. ¿Quieres despedirte de Daniel o continuar más tarde?")
	business._button("Despedirme y terminar misión",_finish_party)
	business._button("Salir por ahora",_exit)
	business._button("Quedarme",business.close)

func _exit() -> void:
	business.close()
	play.end_session(false)
	inside = false
	dance_active = false
	smoking = 0.0
	drink_time = 0.0
	if is_instance_valid(cigarette): cigarette.queue_free()
	if is_instance_valid(drink_prop): drink_prop.queue_free()
	dancers.clear()
	escort = null
	guests.clear()
	party_lights.clear()
	play.clear_room()
	if is_instance_valid(room): room.queue_free()
	room = null
	speaker = null
	exterior.stream = null
	game.player.global_position = _house()+Vector3.UP*.86
	game.player.velocity = Vector3.ZERO
	game.first_person = previous_first
	game._apply_camera_mode()
	game._update_visual_lighting(true)
	_save()

func reset() -> bool:
	if not inside: return false
	_exit()
	return true

func tick(delta: float) -> void:
	if int(state.stage)==0 and _ready_for_call() and not _busy() and not business.modal_open() and not game.home_exit_loading:
		call_wait += delta
		if call_wait>=8.0:
			state.stage = 1
			business.ledger.add_message("Daniel","Asere, llégate pa' mi casa. Hace rato que no nos vemos.")
			_save()
			business.phone_ring.play()
			open_call()
	if int(state.stage)>=2 and not inside and _house().is_finite():
		if game.player.global_position.distance_to(_house())<26.0 and int(state.stage)==2:
			if exterior.stream==null:
				exterior_retry -= delta
				if exterior_retry<=0.0:
					exterior_retry = 2.0
					_play_track()
			elif not exterior.playing: exterior.play()
		elif exterior.playing: exterior.stop()
	if not inside: return
	elapsed += delta
	play.tick(delta)
	guest_clock += delta
	if guest_clock>=1.0:
		guest_clock = 0.0
		_refresh_party_phase()
	_tick_party_events(delta)
	var period := _period()
	for entry in dancers:
		_tick_guest(entry,delta)
	if dance_active:
		if not business.modal_open() or not is_instance_valid(beat_label): dance_active = false
		else:
			dance_time += delta
			var phase := fposmod(_rhythm_clock(),period)
			beat_label.text = ("¡AHORA!" if minf(phase,period-phase)<.16 else "Espera el pulso…")+"   %d/%d" % [dance_hits,dance_attempts]
	if smoking>0.0:
		smoking = maxf(0.0,smoking-delta)
		if smoking<=0.0 and is_instance_valid(cigarette): cigarette.queue_free()
	if drink_time>0.0:
		drink_time = maxf(0.0,drink_time-delta)
		if drink_time<=0.0 and is_instance_valid(drink_prop): drink_prop.queue_free()

func _refresh_party_phase() -> void:
	var minute := float(business.life.state.minutes)
	var phase := Leisure.phase(minute)
	if phase==last_phase: return
	last_phase = phase
	var count := Leisure.guest_count(minute)
	# First mission always has a celebration, even if the player arrives early.
	if not completed(): count = maxi(4,count)
	for entry in guests:
		entry.desired = int(entry.slot)<count and not bool(entry.get("left_early",false))
	if not play.active(): business._notify(Leisure.phase_name(minute))

func _invite(name_value: String) -> void:
	for entry in guests:
		if String(entry.name)!=name_value or not entry.node.visible: continue
		if String(entry.personality)=="reservado" and not bool(state.contacts.get(name_value,false)):
			business._open(name_value,"Prefiero conversar un rato primero.")
			business._button("Conversar",_meet.bind(name_value))
			business._button("Volver",business.close)
			return
		play.partner = entry.node
		entry.role = "dance"
		play.begin_dance(false)
		return

# The small room uses its own cheap navigation grid, not the whole city graph.
func _build_guest_nav() -> void:
	guest_nav.region = Rect2i(-13,-13,27,27)
	guest_nav.cell_size = Vector2(.4,.4)
	guest_nav.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	guest_nav.update()
	for x in range(-13,14):
		for z in range(-13,14):
			var p := Vector3(float(x)*.4,0,float(z)*.4)
			var blocked := (absf(p.x+3.0)<1.45 and absf(p.z+1.9)<1.50) or (absf(p.x-3.0)<1.15 and absf(p.z-2.7)<.80) or (absf(p.x-3.0)<.8 and absf(p.z+3.2)<.70) or p.distance_to(Vector3(-3,0,2.8))<.7
			guest_nav.set_point_solid(Vector2i(x,z),blocked)

func _guest_cell(p: Vector3) -> Vector2i:
	return Vector2i(clampi(roundi(p.x/.4),-13,13),clampi(roundi(p.z/.4),-13,13))

func _guest_walk(entry: Dictionary,goal: Vector3,delta: float) -> bool:
	var person: Person = entry.node
	if person.position.distance_to(goal)<.23: return true
	var from := _guest_cell(person.position)
	var to := _guest_cell(goal)
	if guest_nav.is_point_solid(from) or guest_nav.is_point_solid(to): return false
	if entry.get("nav_goal",Vector2i(999,999))!=to or not entry.has("nav_path"):
		entry.nav_goal = to
		entry.nav_path = guest_nav.get_id_path(from,to)
		entry.nav_index = 1
	var path: Array = entry.nav_path
	var index := int(entry.nav_index)
	var waypoint := goal
	if index<path.size():
		var cell: Vector2i = path[index]
		waypoint = Vector3(float(cell.x)*.4,0,float(cell.y)*.4)
		if person.position.distance_to(waypoint)<.15:
			entry.nav_index = index+1
			return false
	elif path.is_empty():
		entry.erase("nav_path")
		return false
	var target := ROOM+waypoint
	var step := person.global_position.move_toward(target,delta*1.10)
	var player_at: Vector3 = game.player.global_position-Vector3.UP*.86
	if step.distance_to(player_at)<.52 and step.distance_to(player_at)<person.global_position.distance_to(player_at):
		person.animate(delta,false)
		return false
	for other in guests:
		var node: Person = other.node
		if node==person or not node.visible: continue
		if step.distance_to(node.global_position)<.48 and step.distance_to(node.global_position)<person.global_position.distance_to(node.global_position):
			person.animate(delta,false)
			entry.timer = minf(float(entry.timer),1.0)
			return false
	person.walk_to(target,delta,1.10)
	return false

func _tick_guest(entry: Dictionary,delta: float) -> void:
	var person: Person = entry.node
	if not is_instance_valid(person): return
	if play.partner==person and play.active(): return
	if person==escort:
		_guest_walk(entry,Vector3(.8,0,5.1),delta)
		return
	if not bool(entry.get("desired",true)):
		if person.visible and _guest_walk(entry,Vector3(0,0,5.15),delta): person.hide()
		return
	if not person.visible:
		# Enter only at the doorway, when no other guest occupies it.
		for other in guests:
			if other.node.visible and other.node.position.distance_to(Vector3(0,0,5.15))<.7: return
		person.position = Vector3(0,0,5.15)
		person.show()
		entry.role = "arrive"
		entry.erase("nav_path")
	entry.timer = float(entry.timer)-delta
	if float(entry.timer)<=0.0 and String(entry.role)!="arrive":
		entry.timer = 12.0+float(posmod(int(entry.slot)*7+floori(elapsed),11))
		var roles := ["dance","chat","drink","watch"]
		entry.role = roles[posmod(floori(elapsed/10.0)+int(entry.slot),roles.size())]
		entry.erase("nav_path")
	var goal: Vector3 = entry.p
	match String(entry.role):
		"chat": goal = Vector3(-1.4+float(int(entry.slot)%3)*.95,0,3.1)
		"drink": goal = Vector3(1.65+float(int(entry.slot)%2)*.35,0,1.15+float(int(entry.slot)%3)*.48)
		"watch": goal = Vector3(-1.2,0,-3.5+float(int(entry.slot)%3)*.45)
	if not _guest_walk(entry,goal,delta): return
	if String(entry.role)=="arrive": entry.role = "dance"
	if String(entry.role)=="dance" and not power_cut:
		play.pose_guest(person,_rhythm_clock()*TAU/_period()+float(entry.phase),Leisure.genre(track))
	else:
		person.animate(delta,false)
		if String(entry.role)=="drink": person.arms[1].rotation.x = -1.15+sin(elapsed*2.0)*.18
		elif String(entry.role)=="chat": person.arms[0].rotation.x = -.4+sin(elapsed*2.4)*.32

func _tick_party_events(delta: float) -> void:
	if not party_event.is_empty() or play.active() or business.modal_open(): return
	event_clock += delta
	if event_clock<50.0: return
	event_clock = 0.0
	if event_order.is_empty(): return
	party_event = event_order.pop_back()
	event_cursor += 1
	if party_event=="Apagón":
		power_cut = true
		if is_instance_valid(speaker): speaker.stream_paused = true
		for light in party_lights: light.light_energy = .10
	business._notify("Daniel: "+party_event+". Ven a hablar conmigo.")

func _event_menu() -> void:
	business._open("Daniel",party_event)
	match party_event:
		"Apagón": business._button("Ir a la batería junto al equipo",business.close)
		"Vecino pide bajar el volumen": business._button("Ir al equipo de música",business.close)
		"Competencia de baile": business._button("Participar",_event_dance)
		"Acompañar a un invitado": business._button("Acompañarlo hasta la puerta",_event_escort)
		"Recuerdos de infancia": business._button("Conversar sobre los recuerdos",_show_memory)
	business._button("Más tarde",business.close)

func _event_dance() -> void:
	party_event = ""
	play.begin_dance(false)

func _event_escort() -> void:
	for entry in guests:
		if entry.node.visible:
			escort = entry.node
			entry.erase("nav_path")
			business.close()
			business._notify("Acompaña a "+String(entry.name)+" hasta la puerta.")
			return
	_resolve_event()

func _finish_escort() -> void:
	if not is_instance_valid(escort): return
	if escort.position.distance_to(Vector3(.8,0,5.1))>.8:
		business._notify("Espera a que llegue el invitado.")
		return
	for entry in guests:
		if entry.node==escort:
			entry.desired = false
			entry.left_early = true
			escort.hide()
			break
	escort = null
	_resolve_event()

func _show_memory() -> void:
	business._open("Recuerdos de infancia","Daniel te enseña un recuerdo de cuando eran niños. La foto es un espacio reservado para una imagen real que se podrá incorporar más adelante.")
	business._button("Gracias por compartirlo",_resolve_event)

func _resolve_event() -> void:
	if party_event=="Apagón":
		power_cut = false
		if is_instance_valid(speaker): speaker.stream_paused = false
		for light in party_lights: light.light_energy = 1.1
	if party_event=="Vecino pide bajar el volumen":
		quiet_music = true
		if is_instance_valid(speaker): speaker.volume_db = -15.0
	party_event = ""
	_activity("evento")
	business.close()
