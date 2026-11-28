extends Node
const Domino = preload("res://daniel_domino.gd")
const Leisure = preload("res://leisure_rules.gd")
const Person = preload("res://street_person.gd")
const TABLE := Vector3(-3,.83,-1.9)
const SEAT := Vector3(-1.93,.58,-1.9)
var party
var game
var mode := ""
var partner: Person
var opponent_nodes: Array[Node3D] = []
var table_root: Node3D
var hand_nodes: Array[Node3D] = []
var chain_nodes: Array[Node3D] = []
var tile_sound: AudioStreamPlayer3D
var place_lock := 0.0
var result_announced := false
var selected := 0
var overlay: CanvasLayer
var status: Label
var controls: HBoxContainer
var return_at := Vector3.ZERO
var prior_first := true
var prior_yaw := 0.0
var prior_pitch := 0.0
var turn_wait := 0.0
var dance_elapsed := 0.0
var taps := 0
var hits := 0
var tap_wait := 0.0
var singing := false
var feedback := ""
var feedback_time := 0.0

func setup(host) -> void:
	party = host
	game = host.game

func active() -> bool:
	return not mode.is_empty()

func hint() -> String:
	return "Dominó · ←/→ elegir · Q izquierda · E derecha · P paso · Esc levantar" if mode=="domino" else "Baile · Espacio al ritmo · E terminar"

func register_opponent(person: Node3D) -> void:
	opponent_nodes.append(person)

func clear_room() -> void:
	opponent_nodes.clear()
	hand_nodes.clear()
	chain_nodes.clear()
	tile_sound = null
	table_root = null
	partner = null

func _make_tile(parent: Node3D,at: Vector3,a: int,b: int,rotation_y: float = 0.0,face: bool = true) -> Node3D:
	var tile := Node3D.new()
	parent.add_child(tile)
	tile.position = at
	tile.rotation.y = rotation_y
	party.business._box(tile,Vector3.ZERO,Vector3(.074,.022,.142),Color("#ede4ce") if face else Color("#38464a"))
	if not face: return tile
	party.business._box(tile,Vector3(0,.012,0),Vector3(.066,.003,.003),Color("#51483c"))
	for side in range(2):
		var value := a if side==0 else b
		var patterns := [[],[4],[0,8],[0,4,8],[0,2,6,8],[0,2,4,6,8],[0,2,3,5,6,8],[0,2,3,4,5,6,8],[0,1,2,3,5,6,7,8],[0,1,2,3,4,5,6,7,8]]
		for index in patterns[clampi(value,0,9)]:
			var i := int(index)
			var x := float(i%3-1)*.019
			var z := float(floori(float(i)/3.0)-1)*.019
			party.business._box(tile,Vector3(x,.013,z+(-.035 if side==0 else .035)),Vector3(.009,.004,.009),Color("#252326"))
	return tile

func rebuild_table() -> void:
	if not is_instance_valid(party.room): return
	if is_instance_valid(table_root):
		table_root.hide()
		table_root.queue_free()
	table_root = Node3D.new()
	party.room.add_child(table_root)
	hand_nodes.clear()
	chain_nodes.clear()
	var g: Dictionary = party.state.domino
	if g.is_empty(): return
	var chain: Array = g.get("chain",[])
	# The real logical chain is shown across five compact rows.
	for i in range(chain.size()):
		var row := floori(float(i)/8.0)
		var col := i%8
		var reverse := row%2==1
		if reverse: col = 7-col
		var tile: Array = chain[i]
		chain_nodes.append(_make_tile(table_root,TABLE+Vector3(-.57+float(col)*.155,0,-.55+float(row)*.19),int(tile[0]),int(tile[1]),-PI*.5 if reverse else PI*.5))
	var hand: Array = g.hands[0]
	selected = clampi(selected,0,maxi(0,hand.size()-1))
	for i in range(hand.size()):
		var tile: Array = hand[i]
		var p := TABLE+Vector3(.66,.035 if i==selected and mode=="domino" else 0.0,-.64+float(i)*.14)
		var node := _make_tile(table_root,p,int(tile[0]),int(tile[1]),PI*.5)
		hand_nodes.append(node)
	for i in range(1,4):
		for j in range(g.hands[i].size()):
			var p := TABLE+Vector3(-.66,0,-.63+float(j)*.14) if i==1 else TABLE+Vector3(-.63+float(j)*.14,0,-.72 if i==2 else .72)
			_make_tile(table_root,p,0,0,PI*.5 if i==1 else 0.0,false)

func _begin(kind: String) -> void:
	if active() or not party.inside: return
	party.business.close()
	mode = kind
	return_at = game.player.global_position
	prior_first = game.first_person
	prior_yaw = game.yaw
	prior_pitch = game.pitch
	game.player.velocity = Vector3.ZERO
	overlay = CanvasLayer.new()
	add_child(overlay)
	overlay.layer = 12
	var panel := PanelContainer.new()
	overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -285
	panel.offset_right = 285
	panel.offset_top = -110
	panel.offset_bottom = -12
	var col := VBoxContainer.new()
	panel.add_child(col)
	status = Label.new()
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(status)
	controls = HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(controls)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _button(label_value: String,callback: Callable) -> void:
	var button := Button.new()
	button.text = label_value
	button.custom_minimum_size.y = 40
	controls.add_child(button)
	button.pressed.connect(callback)

func begin_domino() -> void:
	if active() or not party.inside: return
	var g: Dictionary = party.state.domino
	if bool(g.get("done",false)): _record_match(g)
	if g.is_empty() or bool(g.done):
		var match_score: Dictionary = party.state.domino_match
		if maxi(int(match_score.ours),int(match_score.theirs))>=100: party.state.domino_match = {"ours":0,"theirs":0,"hands":0}
		party.state.domino = Domino.start()
	_begin("domino")
	game.player.global_position = party.ROOM+SEAT
	game.first_person = true
	game.yaw = PI*.5
	game.pitch = -.57
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	game.pivot.position.y = .95
	selected = 0
	turn_wait = .4
	place_lock = 0.0
	result_announced = false
	feedback = ""
	feedback_time = 0.0
	_button("←",_select.bind(-1))
	_button("→",_select.bind(1))
	_button("Izquierda",_place.bind(true))
	_button("Derecha",_place.bind(false))
	_button("Paso",_pass)
	_button("Salir",end_session.bind(true))
	rebuild_table()
	party._save()
	_refresh()

func _select(delta: int) -> void:
	if mode!="domino": return
	var hand: Array = party.state.domino.hands[0]
	if hand.is_empty(): return
	selected = posmod(selected+delta,hand.size())
	_highlight_hand()
	_refresh()

func _place(left: bool) -> void:
	if mode!="domino": return
	var g: Dictionary = party.state.domino
	if bool(g.done) or int(g.turn)!=0 or place_lock>0.0: return
	var origin := TABLE+Vector3(.66,.035,-.64+float(selected)*.14)
	if Domino.play(g,selected,left):
		turn_wait = .8
		party._activity("domino")
		feedback = ""
		rebuild_table()
		_animate_tile(origin,left)
	else:
		feedback = "Esa ficha no encaja en ese extremo."
		feedback_time = 2.0
	_refresh()

func _pass() -> void:
	if mode!="domino": return
	var g: Dictionary = party.state.domino
	if int(g.turn)!=0 or bool(g.done) or place_lock>0.0: return
	if Domino.pass_turn(g):
		turn_wait = .8
		party._save()
	else:
		feedback = "Tienes una ficha que puedes colocar."
		feedback_time = 2.0
	_refresh()

func _npc_turn() -> void:
	var g: Dictionary = party.state.domino
	var who := int(g.turn)
	var hand: Array = g.hands[who]
	var index := -1
	var score := -1
	var left := true
	for i in range(hand.size()):
		var tile: Array = hand[i]
		if not Domino.legal(g,tile,true) and not Domino.legal(g,tile,false): continue
		var points := int(tile[0])+int(tile[1])
		if points>score:
			index = i
			score = points
			left = Domino.legal(g,tile,true)
	var placed := false
	if index>=0: placed = Domino.play(g,index,left)
	else: Domino.pass_turn(g)
	if who>0 and who<=opponent_nodes.size():
		var person = opponent_nodes[who-1]
		if is_instance_valid(person):
			var arm: Node3D = person.arms[1]
			var tween := create_tween()
			tween.tween_property(arm,"rotation:x",-1.5,.20)
			tween.tween_property(arm,"rotation:x",-1.0,.24)
	party._save()
	rebuild_table()
	if placed:
		var origin := TABLE+Vector3(-.66,0,-.63+float(index)*.14) if who==1 else TABLE+Vector3(-.63+float(index)*.14,0,-.72 if who==2 else .72)
		_animate_tile(origin,left)
	_refresh()

func begin_dance(vocal: bool = false) -> void:
	if active() or not party.inside: return
	if party.power_cut:
		party.business._notify("Daniel está resolviendo la corriente.")
		return
	_begin("dance")
	singing = vocal
	dance_elapsed = 0.0
	taps = 0
	hits = 0
	tap_wait = 0.0
	game.player.global_position = party.ROOM+Vector3(0,.86,1.35)
	game.first_person = false
	game.yaw = PI
	game.pitch = -.20
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	game.arm.spring_length = 2.4
	_button("¡Al ritmo!",_tap)
	_button("Terminar",end_session.bind(true))
	_refresh()

func _tap() -> void:
	if mode!="dance" or tap_wait>0.0: return
	var period: float = party._period()
	var phase := fposmod(float(party._rhythm_clock()),period)
	var good := minf(phase,period-phase)<.16
	if good: hits += 1
	taps += 1
	tap_wait = period*.7
	feedback = "¡Bien!" if good else "Sigue el pulso"
	feedback_time = .6
	if taps>=12: end_session(true)
	else: _refresh()

func pose_guest(person,phase: float,genre: String) -> void:
	var strength := .30 if genre=="salsa" else (.21 if genre=="bachata" else .38)
	person.rotation.y = sin(phase*.5)*.22
	for i in range(2):
		var beat := phase+float(i)*PI
		person.arms[i].rotation.x = -.6+sin(beat)*strength
		person.arms[i].rotation.z = (-1.0 if i==0 else 1.0)*(.22+.12*cos(beat))
		person.limbs[i].rotation.x = sin(beat)*strength*.55
		person.knees[i].rotation.x = maxf(0.0,-sin(beat))*.22

func _refresh() -> void:
	if not is_instance_valid(status): return
	if mode=="domino":
		var g: Dictionary = party.state.domino
		var hand: Array = g.hands[0]
		var chosen := "%d-%d" % hand[selected] if not hand.is_empty() else "—"
		status.text = "%s · Ficha %s · Extremos %d / %d\n%s" % ["Fin de la mano" if bool(g.done) else ("Tu turno" if int(g.turn)==0 else "Turno del jugador "+str(int(g.turn)+1)),chosen,int(g.left),int(g.right),feedback if feedback_time>0 else String(g.log)]
		var match_score: Dictionary = party.state.domino_match
		status.text += "\nParejas: %d – %d / 100 tantos" % [int(match_score.ours),int(match_score.theirs)]
	elif mode=="dance":
		var period: float = party._period()
		var phase := fposmod(float(party._rhythm_clock()),period)
		var now := minf(phase,period-phase)<.16
		status.text = "%s · %s · %d/%d\n%s" % ["Canto rítmico" if singing else Leisure.genre(party.track).capitalize(),"¡AHORA!" if now else "Espera el pulso",hits,taps,feedback if feedback_time>0.0 else "Espacio para seguir el ritmo"]

func handle(event: InputEvent) -> bool:
	if not active(): return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ESCAPE,KEY_R]: end_session(true)
		elif mode=="domino":
			match event.keycode:
				KEY_LEFT: _select(-1)
				KEY_RIGHT: _select(1)
				KEY_Q: _place(true)
				KEY_E: _place(false)
				KEY_P: _pass()
		elif mode=="dance":
			if event.keycode==KEY_SPACE: _tap()
			elif event.keycode==KEY_E: end_session(true)
		return true
	if mode=="domino" and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var camera: Camera3D = game.play_camera
		var best := 38.0
		var index := -1
		for i in range(hand_nodes.size()):
			if not is_instance_valid(hand_nodes[i]) or camera.is_position_behind(hand_nodes[i].global_position): continue
			var distance := camera.unproject_position(hand_nodes[i].global_position).distance_to(event.position)
			if distance<best:
				best = distance
				index = i
		if index>=0:
			selected = index
			_highlight_hand()
			_refresh()
			return true
	return event is InputEventMouseMotion

func tick(delta: float) -> void:
	if not active(): return
	feedback_time = maxf(0.0,feedback_time-delta)
	place_lock = maxf(0.0,place_lock-delta)
	if mode=="domino":
		var g: Dictionary = party.state.domino
		if bool(g.done) and not result_announced and place_lock<=0.0:
			result_announced = true
			_record_match(g)
			party.business._notify("¡Buena partida! "+String(g.log))
			for i in range(opponent_nodes.size()):
				var person = opponent_nodes[i]
				if not is_instance_valid(person): continue
				if int(g.winner)==(i+1)%2:
					var tween := create_tween()
					tween.tween_property(person.arms[0],"rotation:x",-2.2,.25)
					tween.tween_property(person.arms[0],"rotation:x",-1.0,.50)
		if not bool(g.done) and int(g.turn)!=0 and place_lock<=0.0:
			turn_wait -= delta
			if turn_wait<=0.0:
				turn_wait = .85
				_npc_turn()
	elif mode=="dance":
		dance_elapsed += delta
		tap_wait = maxf(0.0,tap_wait-delta)
		var phase := float(party._rhythm_clock())*TAU/float(party._period())
		var genre := Leisure.genre(party.track)
		var strength := .30 if genre=="salsa" else (.20 if genre=="bachata" else .38)
		game.avatar.rotation.y = sin(phase*.5)*.27
		game.avatar.position.y = absf(sin(phase))*.025
		for i in range(2):
			var pulse := sin(phase+float(i)*PI)
			game.limb_arms[i].rotation.x = -.55+pulse*strength
			game.limb_arms[i].rotation.z = (-1.0 if i==0 else 1.0)*(.2+.1*pulse)
			game.limb_legs[i].rotation.x = pulse*strength*.65
		if is_instance_valid(partner):
			var goal: Vector3 = party.ROOM+Vector3(1.05,0,1.35)
			if partner.global_position.distance_to(goal)>.18: partner.walk_to(goal,delta,1.3)
			else: pose_guest(partner,phase+PI,genre)
	_refresh()

func end_session(reward: bool = true) -> void:
	if not active(): return
	var was := mode
	mode = ""
	place_lock = 0.0
	if is_instance_valid(overlay): overlay.queue_free()
	overlay = null
	status = null
	game.player.global_position = return_at
	game.player.velocity = Vector3.ZERO
	game.first_person = prior_first
	game.yaw = prior_yaw
	game.pitch = prior_pitch
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	for arm in game.limb_arms: arm.rotation = Vector3.ZERO
	for leg in game.limb_legs: leg.rotation = Vector3.ZERO
	game.avatar.position.y = 0.0
	game._apply_camera_mode()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if was=="dance" and reward and taps>0:
		party._activity("canto" if singing else "baile")
		party.business._notify("Ritmo: %d de %d aciertos" % [hits,taps])
	partner = null
	rebuild_table()
	party._save()

func _highlight_hand() -> void:
	for i in range(hand_nodes.size()):
		if is_instance_valid(hand_nodes[i]): hand_nodes[i].position.y = TABLE.y+(.035 if i==selected else 0.0)

func _animate_tile(origin: Vector3,left: bool) -> void:
	if chain_nodes.is_empty(): return
	var tile: Node3D = chain_nodes[0] if left else chain_nodes.back()
	var target := tile.position
	tile.position = origin+Vector3.UP*.08
	place_lock = .34
	var tween := create_tween().bind_node(tile)
	tween.tween_property(tile,"position",target+Vector3.UP*.04,.22)
	tween.tween_property(tile,"position",target,.10)
	tween.tween_callback(_clack)

func _clack() -> void:
	if not is_instance_valid(party.room): return
	if not is_instance_valid(tile_sound):
		tile_sound = AudioStreamPlayer3D.new()
		party.room.add_child(tile_sound)
		tile_sound.position = TABLE
		tile_sound.unit_size = 2.0
		tile_sound.volume_db = -13.0
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = 22050
		var samples := PackedByteArray()
		samples.resize(1764*2)
		for i in range(1764):
			var time := float(i)/22050.0
			var decay := exp(-time*82.0)
			var pulse := (sin(time*TAU*1830.0)*.52+sin(time*TAU*720.0)*.30)*decay
			samples.encode_s16(i*2,roundi(pulse*20000.0))
		wav.data = samples
		tile_sound.stream = wav
	tile_sound.play()

func _record_match(g: Dictionary) -> void:
	if not bool(g.get("done",false)) or bool(g.get("scored",false)): return
	var match_score: Dictionary = party.state.domino_match
	if int(g.winner)==0:
		match_score.ours = int(match_score.ours)+Domino.points(g.hands[1])+Domino.points(g.hands[3])
	elif int(g.winner)==1:
		match_score.theirs = int(match_score.theirs)+Domino.points(g.hands[0])+Domino.points(g.hands[2])
	match_score.hands = int(match_score.hands)+1
	g.scored = true
	party._save()
	if maxi(int(match_score.ours),int(match_score.theirs))>=100:
		party.business._notify("Torneo terminado · %d – %d" % [int(match_score.ours),int(match_score.theirs)])
