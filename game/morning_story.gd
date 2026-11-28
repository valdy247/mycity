extends Node3D
# First morning in the rental home. All tasks are checkpointed; the legacy
# Albertico trade/tutorial is deliberately not activated.
const Person = preload("res://street_person.gd")
const ENTRY := Vector3(-.7,110.86,4.85)
const SINK := Vector3(5.65,110.86,-4.42)
const BAG_SPOT := Vector3(-1.88,110.86,4.35)
const LINES := [
	["Tú","Qué día más largo... Voy a descansar un rato.",3.6],
	["Tú","¿Quién será a esta hora?",2.3],
	["Albertico","Buen día, mi socio. Yo soy Albertico, el vecino de al frente. ¿Tú eres familia de Odalis?",5.6],
	["Tú","Ah, sí, ya Odalis me habló de usted. No somos familia. Ella me alquiló esto desde Miami. Es que me deportaron, brother.",8.0],
	["Albertico","Coño, qué mal, caballo.",2.2],
	["Tú","No, tranquilo, todo bien... Oye, ¿tú sabes de alguien que quiera comprar unas cosas que traje pa' vender?",6.2],
	["Albertico","Tranquilo, dame eso a mí. Yo vengo en la tarde con la plata.",4.5],
	["Tú","Dale, mi hermano. Ven, que tengo las cosas aquí en las maletas.",4.0],
	["Albertico","Bueno, mi socio, nos vemos por la tarde.",3.0],
	["Tú","Dale, gracias, brother.",2.2]
]
var story
var game
var state: Dictionary
var phase := "initial"
var clock := 0.0
var speech_left := 0.0
var line := -1
var actor: Person
var ambience: AudioStreamPlayer
var effects: AudioStreamPlayer
var knock: AudioStreamWAV
var water: AudioStreamWAV
var brush: AudioStreamWAV
var marker: Label3D
var props: Node3D
var teeth_prop: Node3D
var hand_l: Node3D
var hand_r: Node3D
var handoff_index := 0
var walk_index := 0
var handed_bags: Array[Node3D] = []
var visitor_path: Array[Vector3] = []
var sleep_start := Vector3.ZERO
var sleep_view := 0.0
var ambience_clock := 0.0

func cinematic() -> bool:
	return phase not in ["return","bed","brush","wash","door","done"]

func setup(parent_story,resuming: bool) -> void:
	story = parent_story
	game = story.game
	state = story.state
	story.layer.show()
	story.fade.color = Color(0,0,0,0)
	story.title.hide()
	game.status.hide()
	game.reticle.hide()
	game.business.layer.hide()
	game.map_credit.hide()
	_make_marker()
	_make_sound()
	_make_props()
	var saved := String(state.get("morning_stage","return"))
	if resuming:
		if saved=="return": saved = "bed"
		if saved in ["sleep","rest"]: saved = "bed"
		if saved in ["visit","handoff"]: saved = "door"
		if saved in ["brush","wash"]:
			game.player.global_position = _bed_stand()
			_start_city()
		elif saved=="door":
			game.player.global_position = SINK
			_start_city()
	phase = saved if resuming else "return"
	_checkpoint(phase)
	if phase=="return": _task("Regresa a la casa alquilada.")
	elif phase=="bed": _task("Acércate a la cama y descansa.")
	elif phase=="brush": _task("Ve al baño y cepíllate los dientes.")
	elif phase=="wash": _task("Lávate la cara en el lavabo.")
	elif phase=="door": _task("Abre la puerta.")

func _checkpoint(value: String) -> void:
	state.morning_stage = value
	story._save()

func _task(value: String) -> void:
	story.objective.text = "CAPÍTULO 1 · LA ADAPTACIÓN\n"+value
	story.subtitle.text = ""

func _make_marker() -> void:
	marker = Label3D.new()
	add_child(marker)
	marker.text = "▼"
	marker.font_size = 84
	marker.pixel_size = .008
	marker.modulate = Color("#ffd34d")
	marker.outline_modulate = Color("#33260d")
	marker.outline_size = 10
	marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	marker.no_depth_test = true
	marker.hide()

func _mark(at: Vector3,delta: float) -> void:
	ambience_clock += delta
	marker.global_position = at+Vector3.UP*(1.08+sin(ambience_clock*3.0)*.12)
	marker.show()

func _bed_stand() -> Vector3:
	var p: Vector3 = game.garage.furniture_nodes.get("cama",null).global_position if game.garage.furniture_nodes.has("cama") else Vector3(-4.5,110.25,-4.1)
	return Vector3(p.x+1.24,110.86,p.z)

func _face(at: Vector3,pitch: float=-.12) -> void:
	var d: Vector3 = at-game.player.global_position
	game.yaw = atan2(d.x,d.z)+PI
	game.pitch = pitch
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)

func _near(at: Vector3,radius: float=1.3) -> bool:
	return game.player.global_position.distance_to(at)<radius

func _say(i: int) -> void:
	line = i
	var item: Array = LINES[i]
	story.subtitle.text = String(item[0])+": "+String(item[1])
	var path := "res://audio/chapter1/morning_%02d.mp3" % (i+1)
	var stream: AudioStreamMP3
	if FileAccess.file_exists(path): stream = AudioStreamMP3.load_from_file(path)
	elif ResourceLoader.exists(path): stream = load(path) as AudioStreamMP3
	story.voice.stop()
	speech_left = float(item[2])+.38
	if stream!=null and stream.get_length()>0.0:
		stream.loop = false
		story.voice.stream = stream
		story.voice.play()
		speech_left = stream.get_length()+.38
	else:
		# The final Cuban voices are a separate audio pack. Never silently
		# substitute an unrelated protagonist voice or charge for new takes.
		print("MyCity: morning subtitle; recording not installed: ",path)

func _make_sound() -> void:
	ambience = AudioStreamPlayer.new()
	add_child(ambience)
	ambience.volume_db = -24.0
	ambience.stream = _sound("city",8.0,true)
	effects = AudioStreamPlayer.new()
	add_child(effects)
	effects.volume_db = -13.0
	knock = _sound("knock",1.05,false)
	water = _sound("water",3.6,false)
	brush = _sound("brush",3.6,false)

func _sound(kind: String,duration: float,looping: bool) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 12000
	var samples := roundi(duration*12000.0)
	var bytes := PackedByteArray()
	bytes.resize(samples*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 13371
	var filtered := 0.0
	for i in range(samples):
		var t := float(i)/12000.0
		var n := rng.randf_range(-1.0,1.0)
		filtered = lerpf(filtered,n,.07)
		var v := 0.0
		match kind:
			"city":
				# Distant engine hum, passing traffic and a brief muted horn.
				# No birds or nature effects.
				var pass_env := .30+.70*pow(sin(PI*t/duration),2.0)
				v = (.10*sin(TAU*48.0*t)+.055*sin(TAU*96.0*t)+.23*filtered)*pass_env
				var horn := maxf(0.0,1.0-absf(t-5.65)*3.3)
				v += .075*horn*(sin(TAU*390.0*t)+.4*sin(TAU*510.0*t))
			"knock":
				for offset in [.03,.32,.62]:
					var d := t-float(offset)
					if d>=0.0 and d<.20: v += exp(-d*32.0)*(.40*sin(TAU*125.0*d)+.17*n)
			"water":
				v = (.17*n+.24*filtered)*smoothstep(0.0,.17,t)*(1.0-smoothstep(duration-.28,duration,t))
			"brush":
				v = n*.105*(.35+.65*pow(sin(TAU*2.8*t),2.0))
		bytes.encode_s16(i*2,roundi(clampf(v,-1,1)*32767.0))
	stream.data = bytes
	if looping:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = samples
	return stream

func _start_city() -> void:
	if not ambience.playing: ambience.play()

func _play_effect(sound: AudioStreamWAV) -> void:
	effects.stream = sound
	effects.play()

func _make_props() -> void:
	props = Node3D.new()
	game.play_camera.add_child(props)
	var skin := Color("#c28b66")
	hand_l = Node3D.new()
	props.add_child(hand_l)
	hand_r = Node3D.new()
	props.add_child(hand_r)
	for hand in [hand_l,hand_r]:
		story._box(hand,Vector3(0,-.055,.045),Vector3(.075,.16,.075),skin)
		story._box(hand,Vector3(0,.022,0),Vector3(.085,.077,.045),skin)
		for i in range(4):
			story._box(hand,Vector3(-.03+float(i)*.02,.067,-.015),Vector3(.017,.061,.029),skin)
		story._box(hand,Vector3(.047,.018,-.018),Vector3(.027,.05,.031),skin)
	teeth_prop = Node3D.new()
	hand_r.add_child(teeth_prop)
	story._box(teeth_prop,Vector3(0,.12,0),Vector3(.018,.23,.018),Color("#4d9aa5"))
	story._box(teeth_prop,Vector3(0,.246,-.006),Vector3(.031,.062,.026),Color("#e7e1ce"))
	props.hide()

func _walk(delta: float) -> void:
	var direction: Vector2 = game._read_controls()
	var move := Vector3(direction.x,0,direction.y).normalized().rotated(Vector3.UP,game.yaw)
	game.player.velocity.x = move.x*4.0
	game.player.velocity.z = move.z*4.0
	if not game.player.is_on_floor(): game.player.velocity.y -= 18.0*delta
	else: game.player.velocity.y = 0.0
	game.player.move_and_slide()
	if game.player.global_position.y< -12.0: game.garage._enter()

func handle_look(relative: Vector2) -> void:
	if cinematic(): return
	game.yaw -= relative.x*.003
	game.pitch = clampf(game.pitch-relative.y*.003,-1.05,.35)
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)

func interact() -> void:
	match phase:
		"return":
			if story._house_near():
				game.garage._enter()
				phase = "rest"
				_checkpoint("bed")
				_say(0)
		"bed":
			if _near(_bed_stand(),1.5):
				phase = "sleep"
				clock = 0.0
				sleep_start = game.player.global_position
				sleep_view = game.pitch
				story.subtitle.text = ""
				story.objective.text = ""
		"brush":
			if _near(SINK,1.1): _begin_hygiene("brushing")
		"wash":
			if _near(SINK,1.1): _begin_hygiene("washing")
		"door":
			if _near(ENTRY,1.45): _open_visitor()

func _begin_hygiene(value: String) -> void:
	phase = value
	clock = 0.0
	_face(Vector3(6.36,111.04,-4.42),-.32)
	game.player.global_position = SINK
	props.show()
	hand_l.visible = value=="washing"
	hand_r.show()
	teeth_prop.visible = value=="brushing"
	story.subtitle.text = ""
	_play_effect(brush if value=="brushing" else water)

func _spawn_visitor() -> void:
	actor = Person.new()
	add_child(actor)
	actor.setup(810)
	actor.remove_from_group("social_people")
	actor.remove_from_group("pedestrian_spacing")
	actor.global_position = Vector3(-.7,110.0,5.55)
	actor.rotation.y = PI

func _open_visitor() -> void:
	phase = "visitor_enter"
	_checkpoint("visit")
	clock = 0.0
	story.objective.text = ""
	story.subtitle.text = ""
	game.garage.set_guest_door(true)
	_spawn_visitor()
	game.player.global_position = Vector3(-.72,110.86,3.35)
	_face(actor.global_position+Vector3.UP*1.48)
	visitor_path = [Vector3(-.70,110.0,4.7),Vector3(-.70,110.0,4.15)]
	walk_index = 0

func _walk_visitor(delta: float,speed: float=1.35) -> bool:
	if walk_index>=visitor_path.size(): return true
	if actor.walk_to(visitor_path[walk_index],delta,speed):
		walk_index += 1
	return walk_index>=visitor_path.size()

func _visitor_talk(delta: float) -> void:
	actor.animate(delta,false)
	var d: Vector3 = game.player.global_position-actor.global_position
	actor.rotation.y = lerp_angle(actor.rotation.y,atan2(d.x,d.z),minf(delta*5.0,1.0))
	_face(actor.global_position+Vector3.UP*1.53)
	var talking := line>=2 and line<LINES.size() and String(LINES[line][0])=="Albertico"
	actor.arms[1].rotation.x = lerpf(actor.arms[1].rotation.x,-.35+.12*sin(clock*6.0) if talking else 0.0,minf(delta*5.0,1.0))

func _give_bag(i: int) -> void:
	if i>=story.bags.size(): return
	var bag: Node3D = story.bags[i]
	if not is_instance_valid(bag): return
	var start := bag.global_transform
	bag.reparent(actor,false)
	bag.global_transform = start
	var side := -1.0 if i==0 else 1.0
	var tween := create_tween()
	tween.tween_property(bag,"position",Vector3(side*.48,.28,.10),.6).set_trans(Tween.TRANS_SINE)
	tween.parallel().tween_property(bag,"rotation",Vector3.ZERO,.6)
	handed_bags.append(bag)

func _finish_visit() -> void:
	for bag in handed_bags:
		if is_instance_valid(bag): bag.queue_free()
	if is_instance_valid(actor): actor.queue_free()
	game.garage.set_guest_door(false)
	state.bags_given_to_albertico = true
	state.albertico_sale_pending = true
	state.morning_complete = true
	_checkpoint("done")
	phase = "done"
	marker.hide()
	props.hide()
	ambience.stop()
	story.morning_finished()

func tick(delta: float) -> void:
	clock += delta
	speech_left = maxf(0.0,speech_left-delta)
	marker.hide()
	if not cinematic(): _walk(delta)
	else: game.player.velocity = Vector3.ZERO
	match phase:
		"return":
			_mark(Vector3(story.home.door)+Vector3.UP*1.5,delta)
			story.subtitle.text = "[E] Entrar en casa" if story._house_near() else "Regresa a la casa."
		"rest":
			if speech_left<=0.0:
				phase = "bed"
				_checkpoint("bed")
				_task("Acércate a la cama y descansa.")
		"bed":
			_mark(_bed_stand(),delta)
			story.subtitle.text = "[E] Acostarte" if _near(_bed_stand(),1.5) else "Ve al dormitorio."
		"sleep":
			if clock<1.0:
				game.pitch = lerpf(sleep_view,-.55,clampf(clock,0,1))
				game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
				story.fade.color.a = clampf(clock,0,1)
			elif clock<3.6:
				story.title.text = "AL DÍA SIGUIENTE..."
				story.title.show()
				if clock>2.4: _start_city()
			else:
				story.title.hide()
				game.business.life.state.minutes = 420.0
				game.business.life.state.day = int(game.business.life.state.get("day",1))+1
				game.business.life.state.fatigue = 0.0
				game.business.life.state.bed_unmade = true
				game.garage._refresh_furniture("cama")
				game.player.global_position = _bed_stand()
				_face(Vector3(-4.5,111.25,-4.1),-.10)
				story.fade.color.a = 0.0
				phase = "brush"
				_checkpoint("brush")
				_task("Ve al baño y cepíllate los dientes.")
		"brush","wash":
			_mark(SINK,delta)
			story.subtitle.text = ("[E] Cepillarte los dientes" if phase=="brush" else "[E] Lavarte la cara") if _near(SINK,1.1) else "Acércate al lavabo del baño."
		"brushing","washing":
			if phase=="brushing":
				hand_r.position = Vector3(.13+sin(clock*17.0)*.065,-.22,-.30)
				hand_r.rotation = Vector3(-.40,0,-.35)
			else:
				var raise := sin(clampf(clock/1.1,0,1)*PI*.5)
				hand_l.position = Vector3(-.12,-.43+.23*raise+sin(clock*8.0)*.04,-.31)
				hand_r.position = Vector3(.12,-.43+.23*raise+sin(clock*8.0+.5)*.04,-.31)
				hand_l.rotation.z = -.35
				hand_r.rotation.z = .35
			if clock>=3.7:
				props.hide()
				if phase=="brushing":
					phase = "wash"
					_checkpoint("wash")
					_task("Lávate la cara en el lavabo.")
				else:
					phase = "knock"
					clock = 0.0
					_checkpoint("door")
					_play_effect(knock)
		"knock":
			if clock>1.2:
				phase = "wonder"
				_say(1)
		"wonder":
			if speech_left<=0.0:
				phase = "door"
				_task("Abre la puerta.")
		"door":
			_mark(ENTRY,delta)
			story.subtitle.text = "[E] Abrir la puerta" if _near(ENTRY,1.45) else "Alguien está tocando la puerta."
		"visitor_enter":
			_face(actor.global_position+Vector3.UP*1.5)
			if _walk_visitor(delta):
				phase = "visit"
				_say(2)
		"visit":
			_visitor_talk(delta)
			if speech_left<=0.0:
				if line<7: _say(line+1)
				else:
					phase = "handoff_walk"
					story.subtitle.text = ""
					visitor_path = [Vector3(-1.85,110.0,3.72)]
					walk_index = 0
		"handoff_walk":
			_face(actor.global_position+Vector3.UP*1.1,-.30)
			if _walk_visitor(delta):
				phase = "handoff"
				clock = 0.0
				handoff_index = 0
		"handoff":
			actor.rotation.y = 0.0
			_face(Vector3(-1.85,110.65,4.1),-.47)
			var bend := sin(clampf(fmod(clock,1.0),0.0,1.0)*PI)*.32 if handoff_index<2 else 0.0
			actor.rotation.x = bend
			for leg in actor.limbs: leg.rotation.x = -bend*.8
			for knee in actor.knees: knee.rotation.x = bend*1.6
			if handoff_index<2 and clock>=.55+float(handoff_index)*.95:
				_give_bag(handoff_index)
				handoff_index += 1
			if clock>2.4:
				actor.rotation.x = 0.0
				phase = "goodbye"
				_say(8)
		"goodbye":
			_visitor_talk(delta)
			if speech_left<=0.0:
				if line==8: _say(9)
				else:
					phase = "visitor_leave"
					visitor_path = [Vector3(-.7,110.0,4.15),Vector3(-.7,110.0,5.65)]
					walk_index = 0
		"visitor_leave":
			_face(actor.global_position+Vector3.UP*1.35)
			var left := _walk_visitor(delta)
			for arm in actor.arms: arm.rotation.x = -.10
			if left:
				# Doorway is a logical transition between interior and city.
				_finish_visit()
