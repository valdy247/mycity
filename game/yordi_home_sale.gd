extends Node3D
# Local domestic choreography. One buyer and two tiny props; the existing
# mission owns the economy and persists payment before the reward.
const Person = preload("res://street_person.gd")
const Garage = preload("res://home_garage.gd")
const ENTRY := Vector3(-.7,0,5.05)
const HOST := Vector3(-2.5,0,3.15)
const GUEST := Vector3(-1.35,0,3.25)
const CONSOLE := Vector3(-2.1,.19,3.0)
var mission
var game
var business
var state: Dictionary
var buyer: Person
var broom: Node3D
var money: Node3D
var phase := ""
var clock := 0.0
var retry := 0.0
var door_point := Vector3.INF
var rest_mode := ""
var rest_clock := 0.0
var rest_index := 0
var seat: Node3D
var seat_at := Vector3.ZERO
var stand_at := Vector3.ZERO
var sweep_clock := 0.0
var banner: Label
var banner_left := 0.0
var departing := false
var outside := false
var buyer_outside := false
var buyer_exit_target := Vector3.INF

func setup(owner) -> void:
	mission = owner
	game = mission.game
	business = mission.business
	state = mission.state
	var overlay := CanvasLayer.new()
	overlay.layer = 22
	add_child(overlay)
	banner = Label.new()
	overlay.add_child(banner)
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	banner.offset_left = -320
	banner.offset_right = 320
	banner.offset_top = -55
	banner.offset_bottom = 55
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size",30)
	banner.add_theme_color_override("font_color",Color("#ffe6a1"))
	banner.add_theme_color_override("font_shadow_color",Color.BLACK)
	banner.add_theme_constant_override("shadow_offset_y",3)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.hide()

func _go(value: String) -> void:
	phase = value
	clock = 0.0
	retry = 0.0

func clear() -> void:
	_stop_rest()
	for node in [buyer,money]:
		if is_instance_valid(node): node.queue_free()
	buyer = null
	money = null
	buyer_outside = false
	departing = false
	outside = false
	banner_left = 0.0
	banner.hide()
	game.garage.set_guest_door(false)
	_go("")

func begin() -> void:
	_go("waiting")

func _actor() -> Person:
	return mission.yordi as Person

func _face(actor: Person,point: Vector3,delta: float) -> void:
	var d := point-actor.global_position
	d.y = 0.0
	if d.length_squared()>.01:
		actor.rotation.y = lerp_angle(actor.rotation.y,atan2(d.x,d.z),minf(delta*10.0,1.0))

func _clear_point(point: Vector3,actor: Person) -> bool:
	var player_at: Vector3 = game.player.global_position-Vector3.UP*.86
	return point.distance_to(player_at)>.80 and mission.world.pedestrian_segment_clear(point,point) and mission.world.pedestrian_space_clear(actor,point,.65,false)

func _entry_point(actor: Person) -> Vector3:
	for offset in [Vector3(-.7,0,5.05),Vector3(-1.5,0,4.9),Vector3(-.7,0,4.15),Vector3(-1.65,0,4.1)]:
		var point: Vector3 = Garage.ROOM+offset
		if _clear_point(point,actor): return point
	return Vector3.INF

func _ensure_home() -> bool:
	if not game.garage.inside: return false
	var actor := _actor()
	if not is_instance_valid(actor) or actor.global_position.y<50.0:
		var at := _entry_point(actor)
		if not at.is_finite(): return false
		mission._ensure_yordi(at)
	if not bool(state.get("buyer_paid",false)):
		if not is_instance_valid(mission.console_box):
			mission.console_box = mission._box_ps5(mission)
		var box: Node3D = mission.console_box
		if box.get_parent()!=mission: box.reparent(mission,false)
		box.global_position = Garage.ROOM+CONSOLE
		box.rotation = Vector3.ZERO
		box.show()
	return true

func _stop_rest() -> void:
	var actor := _actor()
	if is_instance_valid(actor):
		if rest_mode=="seated":
			# Stand in front of the actual sofa before using the walking rig.
			var at := stand_at
			if not _clear_point(at,actor):
				for offset in [Vector3(.6,0,0),Vector3(-.6,0,0),Vector3(0,0,.6),Vector3(0,0,1.1)]:
					if _clear_point(stand_at+offset,actor):
						at = stand_at+offset
						break
			actor.global_position = at
			mission.walkers.erase(actor.get_instance_id())
		actor.animate(.25,false)
	if is_instance_valid(broom): broom.hide()
	rest_mode = ""
	rest_clock = 0.0

func rest(delta: float) -> void:
	var actor := _actor()
	if not is_instance_valid(actor) or not game.garage.inside: return
	rest_clock += delta
	match rest_mode:
		"":
			actor.animate(delta,false)
			if rest_clock<.8: return
			rest_clock = 0.0
			var choice := rest_index%3
			rest_index += 1
			if choice==0 and game.garage.furniture_nodes.has("sofa"):
				seat = game.garage.furniture_nodes["sofa"] as Node3D
				if is_instance_valid(seat):
					seat_at = seat.global_position
					stand_at = Vector3(seat_at.x,Garage.ROOM.y,seat_at.z+.92)
					if _clear_point(stand_at,actor):
						rest_mode = "sofa"
						return
			rest_mode = "bike" if choice!=2 else "sweep_walk"
		"sofa":
			if not is_instance_valid(seat) or seat.global_position.distance_to(seat_at)>.1 or rest_clock>10.0:
				_stop_rest()
				return
			if mission._walk(actor,stand_at,delta,1.8,.30):
				actor.global_position = Vector3(seat_at.x,seat_at.y+.375-.86*actor.scale.y,seat_at.z+.09)
				actor.rotation.y = 0.0
				rest_mode = "seated"
				rest_clock = 0.0
		"seated":
			if not is_instance_valid(seat) or seat.global_position.distance_to(seat_at)>.1 or rest_clock>6.0:
				_stop_rest()
				return
			actor.animate(delta,false)
			for leg in actor.limbs: leg.rotation.x = -PI*.5
			for knee in actor.knees: knee.rotation.x = PI*.5
			for arm in actor.arms: arm.rotation.x = -.28
		"bike":
			var at := Garage.ROOM+Vector3(1.05,0,-.15)
			if mission._walk(actor,at,delta,1.8,.45):
				_face(actor,Garage.ROOM+Garage.BENCH,delta)
				rest_mode = "inspect"
				rest_clock = 0.0
			elif rest_clock>12.0: _stop_rest()
		"inspect":
			actor.animate(delta,false)
			_face(actor,Garage.ROOM+Garage.BENCH,delta)
			if rest_clock>3.5: _stop_rest()
		"sweep_walk":
			var at := Garage.ROOM+Vector3(-3.0,0,4.25)
			if game.garage.has_home_tool() or rest_clock>10.0:
				_stop_rest()
				return
			if mission._walk(actor,at,delta,1.8,.5):
				if not is_instance_valid(broom):
					broom = Node3D.new()
					actor.add_child(broom)
					game.garage._make_broom_model(broom)
				broom.position = Vector3(.26,0,.52)
				broom.show()
				rest_mode = "sweep"
				rest_clock = 0.0
		"sweep":
			if game.garage.has_home_tool() or rest_clock>5.0:
				_stop_rest()
				return
			actor.animate(delta,false)
			for arm in actor.arms: arm.rotation.x = -.75+sin(rest_clock*5.0)*.15
			broom.rotation = Vector3(-.30,0,sin(rest_clock*5.0)*.20)
			sweep_clock += delta
			if sweep_clock>.65:
				sweep_clock = 0.0
				game.garage._sweep_at(actor.global_position+actor.global_basis.z*.65)

func _spawn_visitor() -> bool:
	door_point = mission._home_door_point()
	if not door_point.is_finite(): return false
	var basis: Basis = mission.world.garage_home_site.basis
	for distance in [12.0,8.0,5.0,3.0]:
		for side in [-1.0,1.0]:
			var p: Vector3 = mission._ground(door_point+basis.x*distance*side)
			if not p.is_finite() or not _clear_point(p,null): continue
			if not mission.world.pedestrian_segment_clear(p,door_point): continue
			buyer = mission._person(945,p,"Comprador")
			_go("approach")
			return true
	return false

func _knock() -> void:
	_go("knock")
	mission._cue("knock")
	business._notify("Tocan la puerta. Es el comprador del PS5.")

func _admit() -> bool:
	if phase!="knock" and phase!="host_door": return false
	if not game.garage.inside or not is_instance_valid(buyer): return false
	var at := _entry_point(buyer)
	if not at.is_finite(): return false
	_stop_rest()
	game.garage.set_guest_door(true)
	buyer.global_position = at
	buyer.rotation.y = PI
	mission.walkers.erase(buyer.get_instance_id())
	_go("enter")
	business._notify("Comprador: Buenas, vengo por el PS5.")
	return true

func _cash(actor: Person) -> void:
	if not is_instance_valid(money):
		money = Node3D.new()
		actor.add_child(money)
		business._box(money,Vector3.ZERO,Vector3(.13,.035,.075),Color("#8aa87b"))
		business._box(money,Vector3(0,.019,0),Vector3(.035,.006,.075),Color("#ded5b6"))
	elif money.get_parent()!=actor: money.reparent(actor,false)
	money.position = Vector3(.18,1.05,.38)
	money.rotation = Vector3.ZERO
	money.show()

func _paid() -> void:
	if bool(state.get("buyer_paid",false)): return
	state.buyer_paid = true
	mission._save()
	var actor := _actor()
	_cash(actor)
	if is_instance_valid(mission.console_box):
		var box: Node3D = mission.console_box
		box.reparent(buyer,false)
		box.position = Vector3(0,1.02,.35)
		box.rotation = Vector3.ZERO
	_go("exit")
	business._notify("Comprador: Gracias, aquí tienes el dinero. ¡Hasta luego!")

func _leave_buyer() -> void:
	if not is_instance_valid(buyer): return
	var at: Vector3 = mission._home_door_point()
	if not at.is_finite() or not _clear_point(at,buyer): return
	game.garage.set_guest_door(true)
	buyer.global_position = at
	mission.walkers.erase(buyer.get_instance_id())
	buyer_outside = true
	buyer_exit_target = Vector3.INF
	var basis: Basis = mission.world.garage_home_site.basis
	for side in [1.0,-1.0]:
		var p: Vector3 = mission._ground(at+basis.x*float(side)*8.0)
		if p.is_finite() and mission.world.pedestrian_segment_clear(at,p):
			buyer_exit_target = p
			break
	state.buyer_left = true
	mission._save()
	_go("reward")
	business._notify("Yordi: Mano, aquí está tu parte. Ven a cobrar.")

func _outside_buyer(delta: float) -> void:
	if not buyer_outside or not is_instance_valid(buyer): return
	if buyer_exit_target.is_finite():
		if not mission._walk(buyer,buyer_exit_target,delta,2.2,.65):
			for arm in buyer.arms: arm.rotation.x = -1.15
			return
	elif game.garage.inside:
		# If a sidewalk is temporarily blocked, keep the visitor outside.
		buyer.animate(delta,false)
		return
	if is_instance_valid(mission.console_box) and mission.console_box.get_parent()==buyer:
		mission.console_box = null
	buyer.queue_free()
	buyer = null
	buyer_outside = false

func _pay_player() -> void:
	if phase!="reward" or not bool(state.get("buyer_left",false)) or not game.garage.inside: return
	var actor := _actor()
	if not is_instance_valid(actor) or actor.global_position.distance_to(game.player.global_position-Vector3.UP*.86)>2.6: return
	_go("pay_player")
	_cash(actor)

func action_text() -> String:
	if not game.garage.inside: return ""
	var at: Vector3 = game.player.global_position
	if phase in ["knock","host_door"] and at.distance_to(Garage.ROOM+ENTRY+Vector3.UP*.86)<1.7:
		return "[E] Abrir la puerta al comprador"
	if phase=="reward" and is_instance_valid(_actor()) and at.distance_to(_actor().global_position+Vector3.UP*.86)<2.6:
		return "[E] Recibir tu parte de Yordi"
	return ""

func interact() -> bool:
	var action := action_text()
	if action.contains("Abrir"):
		_admit()
		return true
	if action.contains("Recibir"):
		_pay_player()
		return true
	return false

func objective() -> String:
	if not game.garage.inside: return "Regresa a tu casa para atender la venta del PS5."
	match phase:
		"approach": return "El comprador viene caminando hacia tu casa."
		"knock","host_door": return "Tocan la puerta. Abre con E o deja que Yordi atienda."
		"enter","payment": return "El comprador está dentro. Espera a que pague a Yordi."
		"exit": return "El comprador se lleva el PS5. Espera a que salga."
		"reward": return "Acércate a Yordi y pulsa E para recibir tus 1,000 CUP."
		"pay_player": return "Yordi te está entregando tu parte."
	return "PS5 publicado. Espera al comprador (%d s)." % ceili(float(state.get("sale_left",0.0)))

func tick(delta: float) -> void:
	_outside_buyer(delta)
	if mission._busy() or not _ensure_home(): return
	var actor := _actor()
	clock += delta
	if phase.is_empty():
		# Reload only the unpaid scene. A confirmed payment is never repeated.
		if bool(state.get("buyer_left",false)):
			_go("reward")
		elif bool(state.get("buyer_paid",false)):
			var at := _entry_point(null)
			if not at.is_finite(): return
			buyer = mission._person(945,at,"Comprador")
			mission.console_box = mission._box_ps5(buyer)
			mission.console_box.position = Vector3(0,1.02,.35)
			_go("exit")
		else: _go("waiting")
	match phase:
		"waiting":
			rest(delta)
			state.sale_left = maxf(0.0,float(state.get("sale_left",0.0))-delta)
			if float(state.sale_left)>0.0: return
			retry -= delta
			if retry<=0.0:
				retry = 2.0
				_spawn_visitor()
		"approach":
			rest(delta)
			if not is_instance_valid(buyer):
				_go("waiting")
				return
			if mission._walk(buyer,door_point,delta,2.2,.65): _knock()
			elif clock>22.0:
				buyer.queue_free()
				buyer = null
				_go("waiting")
		"knock":
			rest(delta)
			if clock>=9.0:
				_stop_rest()
				_go("host_door")
		"host_door":
			if mission._walk(actor,Garage.ROOM+ENTRY,delta,2.0,.75): _admit()
			elif clock>12.0:
				_go("knock")
				mission._cue("knock")
		"enter":
			if clock>.8: game.garage.set_guest_door(false)
			var host_ready: bool = mission._walk(actor,Garage.ROOM+HOST,delta,1.9,.45)
			var guest_ready: bool = mission._walk(buyer,Garage.ROOM+GUEST,delta,1.9,.45)
			if host_ready and guest_ready:
				_face(actor,buyer.global_position,delta)
				_face(buyer,actor.global_position,delta)
				_cash(buyer)
				_go("payment")
		"payment":
			actor.animate(delta,false)
			buyer.animate(delta,false)
			_face(actor,buyer.global_position,delta)
			_face(buyer,actor.global_position,delta)
			actor.arms[1].rotation.x = -.95
			buyer.arms[1].rotation.x = -.95
			if clock>=2.0: _paid()
		"exit":
			actor.animate(delta,false)
			if mission._walk(buyer,Garage.ROOM+ENTRY,delta,2.0,.65): _leave_buyer()
			for arm in buyer.arms: arm.rotation.x = -1.15
		"reward":
			if clock>.7: game.garage.set_guest_door(false)
			actor.animate(delta,false)
			_face(actor,game.player.global_position,delta)
			_cash(actor)
		"pay_player":
			actor.animate(delta,false)
			_face(actor,game.player.global_position,delta)
			actor.arms[1].rotation.x = -1.05
			if clock>=1.2:
				if actor.global_position.distance_to(game.player.global_position-Vector3.UP*.86)>2.8:
					_go("reward")
					return
				if is_instance_valid(money): money.queue_free()
				money = null
				mission._complete_sale()
				if mission._stage()==14:
					banner.text = "MISIÓN CUMPLIDA\nEl negocio del PS5"
					banner.show()
					banner_left = 4.5
					departing = true
					outside = false
					_go("farewell")

func tick_departure(delta: float) -> void:
	_outside_buyer(delta)
	if banner_left>0.0:
		banner_left -= delta
		if banner_left<=0.0: banner.hide()
	if not departing or not is_instance_valid(_actor()): return
	var actor := _actor()
	if not outside:
		if not mission._walk(actor,Garage.ROOM+ENTRY,delta,2.0,.65): return
		var at: Vector3 = mission._home_door_point()
		if not at.is_finite() or not _clear_point(at,actor): return
		game.garage.set_guest_door(true)
		actor.global_position = at
		mission.walkers.erase(actor.get_instance_id())
		outside = true
		clock = 0.0
	else:
		clock += delta
		if clock>.8: game.garage.set_guest_door(false)
		var at: Vector3 = mission._bike_wait_site() if is_instance_valid(mission.bike) else Vector3.INF
		if not at.is_finite():
			var basis: Basis = mission.world.garage_home_site.basis
			for side in [1.0,-1.0]:
				var p: Vector3 = mission._ground(actor.global_position+basis.x*float(side)*7.0)
				if p.is_finite() and mission.world.pedestrian_segment_clear(actor.global_position,p):
					at = p
					break
		if at.is_finite() and mission._walk(actor,at,delta,2.2,.70):
			actor.hide()
			actor.queue_free()
			mission.yordi = null
			if bool(state.get("bike_returned",false)): mission._discard_bike()
			departing = false
