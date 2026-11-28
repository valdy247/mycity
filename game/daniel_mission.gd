extends Node3D
# A social chapter, independent of money rewards and external services.
const Person = preload("res://street_person.gd")
const Domino = preload("res://daniel_domino.gd")
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

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	business = game.business
	var life: Dictionary = business.ledger.life_data
	if not life.has("daniel_party"): life.daniel_party = {"stage":0,"activities":{},"drinks":0,"domino":{},"contacts":{},"track":0}
	state = life.daniel_party
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
		var p: Vector3 = game.player.global_position-ROOM
		if p.distance_to(Vector3(0,.86,5.1))<2.0: return "[E] Salir de casa de Daniel"
		if p.distance_to(Vector3(-3,.86,-1.9))<2.2: return "[E] Jugar dominó"
		if p.distance_to(Vector3(3,.86,-3.2))<2.4: return "[E] Equipo de música"
		if p.distance_to(Vector3(3,.86,2.5))<2.2: return "[E] Bebidas y comida"
		if p.distance_to(Vector3(-3,.86,2.8))<2.2: return "[E] Conversar con Daniel"
		return "[E] Bailar / cantar / conocer invitados"
	if int(state.stage)>=2 and _house().is_finite() and not _busy() and not game.garage.inside and game.player.global_position.distance_to(_house()+Vector3.UP*.86)<2.8:
		return "[E] Entrar a casa de Daniel"
	return ""

func interact() -> bool:
	var action := action_text()
	if action.is_empty(): return false
	if not inside:
		if game.garage._free_hands(): _enter()
		else: business._notify("Deja lo que llevas antes de entrar.")
	elif action.contains("Salir"): _leave()
	elif action.contains("dominó"): _domino_menu()
	elif action.contains("música"): _music_menu()
	elif action.contains("Bebidas"): _drink_menu()
	elif action.contains("Daniel"): _daniel_menu()
	else: _social_menu()
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
	if dancing: dancers.append({"node":person,"p":p,"phase":float(dancers.size())*.9})
	return person

func _enter() -> void:
	inside = true
	previous_first = game.first_person
	marker.hide()
	exterior.stop()
	room = Node3D.new()
	add_child(room)
	room.position = ROOM
	var wall := Color("#d2b8a0")
	_solid(Vector3(0,-.10,0),Vector3(12,.20,12),Color("#a99b88"))
	_solid(Vector3(-5.9,1.6,0),Vector3(.2,3.2,12),wall)
	_solid(Vector3(5.9,1.6,0),Vector3(.2,3.2,12),wall)
	_solid(Vector3(0,1.6,-5.9),Vector3(12,3.2,.2),wall)
	_solid(Vector3(0,1.6,5.9),Vector3(12,3.2,.2),wall)
	_solid(Vector3(0,3.2,0),Vector3(12,.18,12),wall)
	_solid(Vector3(0,1.05,5.72),Vector3(1.25,2.1,.12),Color("#77584c"))
	_label("SALIR",Vector3(0,2.5,5.6))
	_solid(Vector3(-3,.70,-1.9),Vector3(1.35,.12,1.2),Color("#725b42"))
	_solid(Vector3(3,.8,2.7),Vector3(1.6,.14,.9),Color("#725b42"))
	for i in range(5):
		business._box(room,Vector3(2.5+float(i)*.22,.99,2.7),Vector3(.10,.25,.10),Color("#567641") if i%2==0 else Color("#a77736"))
	for i in range(4):
		business._box(room,Vector3(-3.3+float(i)*.2,.79,-1.9),Vector3(.09,.025,.15),Color("#e5dfc8"))
	_solid(Vector3(3,.75,-3.2),Vector3(.85,1.5,.5),Color("#30343c"))
	business._box(room,Vector3(3,.9,-2.93),Vector3(.62,.60,.06),Color("#12151b"))
	_label("DOMINÓ",Vector3(-3,1.8,-1.9))
	_label("MÚSICA",Vector3(3,1.95,-3.2))
	_label("BEBIDAS",Vector3(3,1.75,2.7))
	_guest(915,Vector3(-3,0,2.8),"Daniel",false).rotation.y = 1.4
	_label("Daniel",Vector3(-3,2.05,2.8))
	for i in range(3):
		var p: Vector3 = [Vector3(-4.1,0,-1.9),Vector3(-3,0,-3.1),Vector3(-3,0,-.7)][i]
		var guest := _guest(920+i,p,["Mario","Luis","Rafa"][i],false)
		guest.rotation.y = atan2(-3.0-p.x,-1.9-p.z)
	for i in range(4):
		var p := Vector3(-.8+float(i%2)*1.6,0,-2.0+floorf(float(i)/2.0)*2.0)
		_guest([919,922,925,923][i],p,["Laura","María","Ana","Javier"][i],true)
	for i in range(3):
		var light := OmniLight3D.new()
		room.add_child(light)
		light.position = Vector3(-3+float(i)*3,2.8,-.5)
		light.light_color = [Color("#ffc69d"),Color("#c29dff"),Color("#9fcbff")][i]
		light.omni_range = 7.5
		light.light_energy = 1.1
		light.shadow_enabled = false
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
	_play_track()
	if not bool(state.get("welcomed",false)):
		state.welcomed = true
		_save()
		business._open("¡Sorpresa!","Daniel: ¡Asere! Hoy no se habla de trabajo. Ven, que estamos entre amigos. Hay dominó, baile, comida y música.")
		business._button("¡Vamos a pasarla bien!",business.close)

func _activity(key: String) -> void:
	state.activities[key] = true
	_save()

func _daniel_menu() -> void:
	business._open("Daniel","¡Cuántos recuerdos, mano! Desde chiquitos juntos. Hoy deja los problemas a un lado.")
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
	business._button("Bailar",_start_rhythm.bind(false))
	business._button("Cantar siguiendo el ritmo",_start_rhythm.bind(true))
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
	inside = false
	dance_active = false
	smoking = 0.0
	drink_time = 0.0
	if is_instance_valid(cigarette): cigarette.queue_free()
	if is_instance_valid(drink_prop): drink_prop.queue_free()
	dancers.clear()
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
	var period := _period()
	for entry in dancers:
		var person: Person = entry.node
		var phase := _rhythm_clock()*TAU/period+float(entry.phase)
		person.position = Vector3(entry.p)+Vector3(sin(phase)*.13,absf(sin(phase))*.025,cos(phase*.5)*.08)
		person.rotation.y = sin(phase*.5)*.30
		for arm in person.arms: arm.rotation.x = -.65+sin(phase)*.38
		for leg in person.limbs: leg.rotation.x = sin(phase)*.16
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
