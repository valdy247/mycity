extends Node3D
# Mission 3. Uses the existing taxi route executor, one motorcycle and
# temporary low-poly actors. All money in this story belongs to Yordi.
const Person = preload("res://street_person.gd")
const Kit = preload("res://vehicle_kit.gd")
const Bypass = preload("res://traffic_bypass.gd")
const Garage = preload("res://home_garage.gd")
const REWARD := 1000
const SALE_DELAY := 25.0
const RIVAL_SPEED := 5.1
var game
var world
var business
var service
var state: Dictionary = {}
var yordi: Person
var seller: Person
var bike: CharacterBody3D
var cab: CharacterBody3D
var bike_driver: Node3D
var bike_passenger: Node3D
var paused_trip: Dictionary = {}
var paused_role := ""
var console_box: Node3D
var marker: Node3D
var cut_camera: Camera3D
var foes: Array[Person] = []
var walkers: Dictionary = {}
var trip_body: CharacterBody3D
var trip_role := ""
var seller_point := Vector3.INF
var pickup_point := Vector3.INF
var chase_origin := Vector3.INF
var retry_clock := 0.0
var call_clock := 0.0
var chase_clock := 0.0
var run_clock := 0.0
var last_player := Vector3.ZERO
var chase_sample := 0.0
var chase_grace := 0.0
var slow_clock := 0.0
var arrival_wait := 0.0
var trip_elapsed := 0.0
var rendezvous_clock := 0.0
var visit_elapsed := 0.0
var visit_retry := 0.0
var visit_notice := false
var visit_foot_elapsed := 0.0
var exit_elapsed := 0.0
var exit_retry_clock := 0.0
var bike_walk_elapsed := 0.0
var bike_wait_point := Vector3.INF
var key_line := false
var restore_pending := false
var location_reported := false
var cinematic := ""
var stone: Node3D
var stone_clock := 0.0
var stone_velocity := Vector3.ZERO
var robbery_phase := ""
var robbery_clock := 0.0
var escape_route := PackedVector3Array()
var escape_index := 0
var escape_goal := Vector3.INF
var leader_retry := 0.0
var leader_last := Vector3.ZERO
var distracted_foe := -1
var stone_camera_previous := true
var stone_camera_changed := false

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	business = game.business
	service = game.taxis
	var life: Dictionary = business.ledger.life_data
	if not life.has("yordi_ps5"):
		life.yordi_ps5 = {"stage":0,"reward_paid":false,"police":false,"delivered":false}
	state = life.yordi_ps5
	_restart_visit_once(life)
	marker = Node3D.new()
	add_child(marker)
	business._arrow(marker,Vector3.UP*2.2,Color("#ffd85c"))
	marker.hide()
	# Never persist scene-node references. Resume a paid purchase at its
	# street checkpoint; earlier phases restart the visit, with no debit.
	var stage := _stage()
	if stage in [2,3,4,5,6]: state.stage = 2
	if stage in [7,8,9,10,11]:
		state.stage = 7
		restore_pending = true
	if stage==13: state.sale_left = maxf(0.0,float(state.get("sale_left",SALE_DELAY)))
	_save()

# One-time replay for saves stranded during the original visit.
# Never debit the player or reset the other missions.
func _restart_visit_once(life: Dictionary) -> void:
	if int(life.get("yordi_replay_version",0))>=2: return
	life.yordi_replay_version = 2
	var previous_stage := _stage()
	if previous_stage==0: return
	var already_paid := bool(state.get("reward_paid",false)) or bool(state.get("previous_reward_paid",false)) or previous_stage>=14
	var saved_seller: Dictionary = state.get("seller",{}).duplicate(true)
	state.clear()
	state.merge({"stage":0,"reward_paid":false,"police":false,"delivered":false,"replay_ready":true,"previous_reward_paid":already_paid})
	if not saved_seller.is_empty(): state.seller = saved_seller
	var label_value: String = game.garage.waypoint_label.to_lower()
	if label_value.contains("yordi") or label_value.contains("ps5") or label_value.contains("tejas") or label_value.contains("infanta") or label_value.contains("punto de recogida del taxi"):
		game.garage.waypoint_active = false
		game.garage.waypoint_label = ""
		game.garage.state.gps = {}
		if is_instance_valid(game.garage.waypoint): game.garage.waypoint.hide()
		service.set_garage_destination(Vector3.ZERO,"")
	print("MyCity: misión de Yordi reiniciada; espera su llamada en casa.")

func _stage() -> int:
	return int(state.get("stage",0))

func _save() -> void:
	business.ledger.save_game()

func _set_stage(value: int) -> void:
	state.stage = value
	retry_clock = 0.0
	_save()

func _encode(p: Vector3) -> Dictionary:
	return {"x":p.x,"y":p.y,"z":p.z}

func _decode(value: Dictionary) -> Vector3:
	if not value.has("x") or not value.has("z"): return Vector3.INF
	return Vector3(float(value.x),float(value.get("y",0.0)),float(value.z))

func _home() -> Vector3:
	if world.garage_home_site.is_empty(): return Vector3.INF
	return world.garage_home_site.door

func _busy() -> bool:
	return game.driving or game.taxi_riding or game.bus_riding or game.garage.riding or game.building_mode

func _target(p: Vector3,label_value: String) -> void:
	if not p.is_finite(): return
	marker.global_position = p
	marker.show()
	game.garage._set_waypoint(p,label_value)

func _clear_target() -> void:
	marker.hide()
	game.garage.waypoint_active = false
	game.garage.state.gps = {}
	service.set_garage_destination(Vector3.ZERO,"")

func objective() -> String:
	match _stage():
		1: return "Yordi te llama · P: teléfono"
		2: return "Espera a Yordi en tu casa."
		3: return "Habla con Yordi."
		4: return "Sal de casa con Yordi." if game.garage.inside else "Sube a la moto de Yordi."
		5: return "Vuelve a subir a la moto de Yordi para continuar." if not paused_trip.is_empty() else "Yordi conduce hacia Infanta · Esquina de Tejas."
		6: return "Ve con Yordi a buscar el PS5."
		7: return _robbery_objective()
		8: return "¡Sigue a Yordi! Mantén Shift · %d m al refugio" % roundi(game.player.global_position.distance_to(escape_goal)) if escape_goal.is_finite() else "¡Sigue a Yordi! Mantén Shift."
		9: return "Yordi llamó un taxi. Espera en un lugar seguro."
		10: return "Sube al taxi que llamó Yordi."
		11: return "Vuelve a subir al taxi de Yordi para continuar." if not paused_trip.is_empty() else "Regresen a casa."
		12: return "Lleva el PS5 a casa y publícalo en Marketplace."
		13: return "PS5 publicado · esperando comprador."
	return ""

func _ground(at: Vector3,sidewalk: bool = true) -> Vector3:
	var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*2.0,at-Vector3.UP*1.0,2)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<.65: return Vector3.INF
	var p: Vector3 = hit.position
	if sidewalk and world.street_geometry.point_on_road(p): return Vector3.INF
	if not world.pedestrian_segment_clear(p,p): return Vector3.INF
	return p

func _near_ground(at: Vector3,actor: Node3D = null,radius: float = 8.0) -> Vector3:
	for r in [0.0,1.1,2.5,4.0,6.0,8.0,12.0,18.0]:
		if float(r)>radius: break
		for i in range(1 if float(r)==0.0 else 8):
			var a := float(i)*TAU/8.0
			var p := _ground(at+Vector3(cos(a),0,sin(a))*float(r))
			if p.is_finite() and world.pedestrian_space_clear(actor,p,.7,false): return p
	return Vector3.INF

func _person(style: int,at: Vector3,label_value: String = "") -> Person:
	var node := Person.new()
	add_child(node)
	node.setup(style)
	node.remove_from_group("social_people")
	node.global_position = at
	if not label_value.is_empty(): business._label(node,label_value,Vector3(0,2.0,0))
	return node

func _ensure_yordi(at: Vector3) -> void:
	if not is_instance_valid(yordi): yordi = _person(807,at,"Yordi")
	yordi.global_position = at
	yordi.show()
	walkers.erase(yordi.get_instance_id())

func _box_ps5(parent: Node3D) -> Node3D:
	var box := Node3D.new()
	parent.add_child(box)
	business._box(box,Vector3.ZERO,Vector3(.49,.35,.16),Color("#e8ebef"))
	business._box(box,Vector3(0,.125,.086),Vector3(.48,.09,.015),Color("#3468aa"))
	business._box(box,Vector3(.10,-.035,.087),Vector3(.15,.19,.018),Color("#20262c"))
	business._box(box,Vector3(.10,-.035,.10),Vector3(.11,.18,.012),Color("#e1e5ea"))
	var label: Label3D = business._label(box,"PS5",Vector3(-.11,.025,.10))
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.pixel_size = .0019
	label.outline_size = 0
	return box

func _carry_ps5() -> void:
	if not is_instance_valid(yordi): return
	if not is_instance_valid(console_box): console_box = _box_ps5(yordi)
	elif console_box.get_parent()!=yordi: console_box.reparent(yordi,false)
	console_box.position = Vector3(0,1.02,.35)
	console_box.rotation = Vector3.ZERO
	console_box.show()

func _carry_pose() -> void:
	if not is_instance_valid(yordi) or not is_instance_valid(console_box) or console_box.get_parent()!=yordi: return
	for arm in yordi.arms: arm.rotation.x = -1.15

func _walk(actor: Person,target: Vector3,delta: float,speed: float,stop_range: float = .65) -> bool:
	if not is_instance_valid(actor) or not target.is_finite(): return false
	if actor.global_position.distance_to(target)<=stop_range:
		actor.animate(delta,false)
		return true
	var id := actor.get_instance_id()
	var memory: Dictionary = walkers.get(id,{"time":float(id%7)*.045,"path":PackedVector3Array(),"index":0,"target":Vector3.INF})
	memory.time = float(memory.time)-delta
	if float(memory.time)<=0.0:
		memory.time = 1.1
		var path := PackedVector3Array()
		var destination := target
		var player_ground: Vector3 = game.player.global_position-Vector3.UP*.86
		# The player has a physical capsule. Aim for its outside edge,
		# not the blocked centre of the capsule.
		if target.distance_to(player_ground)<.6:
			var toward := actor.global_position-target
			toward.y = 0.0
			if toward.length_squared()<.01: toward = Vector3.FORWARD
			toward = toward.normalized()
			var found := false
			for angle in [0.0,.6,-.6,1.2,-1.2,PI]:
				var option := target+toward.rotated(Vector3.UP,float(angle))*maxf(1.25,stop_range*.8)
				if not world.pedestrian_segment_clear(option,option): continue
				destination = option
				found = true
				break
			if not found: destination = actor.global_position
		if world.pedestrian_segment_clear(actor.global_position,destination): path.append(destination)
		elif game.garage.inside and actor.global_position.y>50.0 and destination.y>50.0:
			# The city sidewalk graph cannot route inside the separate house.
			for offset in [Vector3(-1.2,0,0),Vector3(1.2,0,0),Vector3(-1.2,0,-2.1),Vector3(-1.2,0,2.1),Vector3(-1.7,0,-2.8)]:
				var via: Vector3 = Garage.ROOM+Vector3(offset)
				if world.pedestrian_segment_clear(actor.global_position,via) and world.pedestrian_segment_clear(via,destination):
					path = PackedVector3Array([via,destination])
					break
		else: path = game.monte_pedestrians.route_between(actor.global_position,destination)
		memory.path = path
		memory.index = 0
		memory.target = target
	var path: PackedVector3Array = memory.path
	var index := int(memory.index)
	if index<path.size():
		var next := path[index]
		var step := actor.global_position.move_toward(next,speed*delta)
		if world.pedestrian_segment_clear(actor.global_position,step) and world.pedestrian_space_clear(actor,step,.58):
			if actor.walk_to(next,delta,speed): memory.index = index+1
		else:
			var d := (next-actor.global_position).normalized()
			var side := Vector3(-d.z,0,d.x)
			for sign_value in [-1.0,1.0]:
				var option := step+side*float(sign_value)*minf(.20,speed*delta)
				if world.pedestrian_segment_clear(actor.global_position,option) and world.pedestrian_space_clear(actor,option,.58):
					actor.walk_to(option,delta,speed)
					break
	else: actor.animate(delta,false)
	walkers[id] = memory
	return false

func _road_berth(near: Vector3,min_distance: float,max_distance: float,width: float,length: float,height: float) -> Dictionary:
	var choices: Array = []
	for edge in world.geography.roads_near(near,max_distance):
		if not bool(edge.driveable): continue
		for order in [0,1]:
			var first := String(edge.a_id) if order==0 else String(edge.b_id)
			var last := String(edge.b_id) if order==0 else String(edge.a_id)
			if not world.geography.graph.get(first,[]).has(last): continue
			var a: Vector3 = world.geography.points[first]
			var b: Vector3 = world.geography.points[last]
			var d := (b-a).normalized()
			if a.distance_to(b)<12.0: continue
			# Include the actual projection near the requested address, not just fixed block fractions.
			var projected := clampf((near-a).dot(b-a)/a.distance_squared_to(b),.08,.92)
			for fraction in [projected,.35,.6,.78]:
				var p: Vector3 = a.lerp(b,float(fraction))+world.geography.lane_offset(a,b,width,true)
				p = world.street_geometry.safe_stop_on_edge(a,b,p,length,width)
				p.y = .065
				var distance := p.distance_to(near)
				if distance<min_distance or distance>max_distance: continue
				choices.append({"p":p,"d":d,"next":last,"score":absf(distance-(min_distance+max_distance)*.5)})
	choices.sort_custom(func(a,b): return float(a.score)<float(b.score))
	for choice in choices.slice(0,40):
		var p: Vector3 = choice.p
		var d: Vector3 = choice.d
		if not Bypass._on_road(world.street_geometry,p,d,width,length): continue
		if not world.street_geometry.intersection_clear_for_stop(p,length,width): continue
		var shape := BoxShape3D.new()
		shape.size = Vector3(width+.2,height,length+.2)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p+Vector3.UP*(height*.5+.04))
		query.collision_mask = 1|4|8|16|32
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		if not world.pedestrian_space_clear(null,p,1.3,false): continue
		return choice
	return {}

func _spawn_bike(berth: Dictionary) -> void:
	if is_instance_valid(bike): return
	bike = Kit.body(self,"moto")
	bike.name = "Moto_Yordi"
	bike.set_meta("trip_dimensions",Vector3(.85,1.8,2.1))
	bike.set_meta("traffic_priority",2.1)
	bike.global_position = berth.p
	var d: Vector3 = berth.d
	bike.rotation.y = atan2(d.x,d.z)
	bike.add_to_group("traffic_parked")
	# Longer rear seat and rear passenger footrests; shared primitives.
	Kit._box(bike,Vector3(0,.99,-.70),Vector3(.28,.10,.38),Color("#323638"),false)
	for side in [-1.0,1.0]:
		Kit._box(bike,Vector3(float(side)*.27,.43,-.52),Vector3(.15,.045,.09),Color("#343b3c"),false)
	state.bike_berth = {"p":_encode(berth.p),"d":_encode(d),"next":String(berth.next)}

func _next_node(body: CharacterBody3D) -> String:
	var best := INF
	var result := ""
	var forward := body.global_basis.z
	for edge in world.geography.roads_near(body.global_position,20.0):
		if not bool(edge.driveable): continue
		for order in [0,1]:
			var first := String(edge.a_id) if order==0 else String(edge.b_id)
			var last := String(edge.b_id) if order==0 else String(edge.a_id)
			if not world.geography.graph.get(first,[]).has(last): continue
			var a: Vector3 = world.geography.points[first]
			var b: Vector3 = world.geography.points[last]
			if (b-a).normalized().dot(forward)<.45 or (b-body.global_position).dot(forward)<0.0: continue
			var distance := Geometry3D.get_closest_point_to_segment(body.global_position,a,b).distance_to(body.global_position)
			if distance<best:
				best = distance
				result = last
	return result

func _start_trip(body: CharacterBody3D,goal: Vector3,label_value: String,role: String,player_onboard: bool) -> bool:
	if not service.passenger.is_empty() or not service.selected.is_empty() or service.dialog.visible: return false
	var start := _next_node(body)
	if start.is_empty(): return false
	var result: Dictionary = service.router.resolve_point(goal,start)
	if result.has("error"): return false
	result.label = label_value
	service.selected = {"body":body,"next_node":start,"path":[],"index":0,"speed":0.0,"blocked":0.0,"goal":"","label":"","note":"","mission_vehicle":true}
	service.selected_route = result
	service.trip_confirmed = true
	if not service.prepare_trip():
		service.close_dialog()
		return false
	trip_body = body
	trip_role = role
	trip_elapsed = 0.0
	arrival_wait = 0.0
	if player_onboard:
		game._start_taxi_ride()
		if body==bike:
			game.pivot.position = Vector3(0,1.40,-.72)
			game.arm.spring_length = 3.8
	return true

func owns_passenger_trip() -> bool:
	return is_instance_valid(trip_body) and not service.passenger.is_empty() and service.passenger.body==trip_body and game.taxi_riding

# Capture the pending route before the common taxi controller clears it.
func remember_interrupted_ride() -> void:
	paused_trip = service.passenger.duplicate(true)
	paused_role = trip_role

func on_ride_end(emergency: bool,interrupted: bool = false) -> void:
	if trip_role not in ["bike_out","taxi_home"]: return
	var role := trip_role
	trip_role = ""
	trip_body = null
	if interrupted and not emergency and not paused_trip.is_empty():
		var vehicle: CharacterBody3D = paused_trip.body
		if is_instance_valid(vehicle):
			vehicle.set_meta("traffic_servicing",true)
			if is_instance_valid(bike_passenger):
				bike_passenger.hide()
				bike_passenger.queue_free()
				bike_passenger = null
			_target(vehicle.global_position,"Moto de Yordi · vuelve a subir" if role=="bike_out" else "Taxi de Yordi · vuelve a subir")
			business._notify("Yordi: Te espero aquí, mano. Vuelve a subir para continuar.")
			return
	paused_trip = {}
	paused_role = ""
	if role=="bike_out":
		_remove_riders()
		if emergency:
			_discard_bike()
			_set_stage(2)
			return
		var point := _near_ground(game.player.global_position,yordi,9.0)
		if not point.is_finite(): point = game.player.global_position-Vector3.UP*.86
		_ensure_yordi(point)
		_spawn_seller()
		_set_stage(6)
	elif emergency:
		_discard_cab()
		_set_stage(7)
		restore_pending = true
	else:
		var point := _near_ground(game.player.global_position,yordi,8.0)
		if not point.is_finite(): point = game.player.global_position-Vector3.UP*.86
		_ensure_yordi(point)
		_carry_ps5()
		_set_stage(12)
		_target(_home(),"Mi casa · PS5")
		business._notify("Yordi: Vamos a dejar el PS5 adentro y publicarlo.")
		_release_cab()

func _remove_riders() -> void:
	if is_instance_valid(bike_driver): bike_driver.queue_free()
	if is_instance_valid(bike_passenger): bike_passenger.queue_free()
	bike_driver = null
	bike_passenger = null

func _driver() -> void:
	if is_instance_valid(yordi): yordi.hide()
	if not is_instance_valid(bike_driver): bike_driver = game.garage._make_rider(bike,"moto",807)

func _rear_rider() -> void:
	if is_instance_valid(bike_passenger): return
	# Use the real player appearance, not a random civilian style.
	var source: Node3D = game.avatar
	bike_passenger = source.duplicate(0) as Node3D
	bike.add_child(bike_passenger)
	bike_passenger.position = Vector3(0,1.18,-.73)
	bike_passenger.rotation = Vector3.ZERO
	bike_passenger.scale = Vector3(.85,.85,.85)
	bike_passenger.show()
	for limb in game.limb_legs:
		var leg := bike_passenger.get_node_or_null(source.get_path_to(limb)) as Node3D
		if leg!=null: leg.rotation = Vector3(-1.05,0,0)
	for limb in game.limb_arms:
		var arm := bike_passenger.get_node_or_null(source.get_path_to(limb)) as Node3D
		if arm!=null: arm.rotation = Vector3(-.75,0,0)

func _resume_passenger() -> bool:
	if paused_trip.is_empty() or not game.garage._free_hands(): return false
	var vehicle: CharacterBody3D = paused_trip.body
	if not is_instance_valid(vehicle): return false
	if not service.resume_mission_trip(paused_trip): return false
	trip_body = vehicle
	trip_role = paused_role
	paused_trip = {}
	paused_role = ""
	game._start_taxi_ride()
	if vehicle==bike:
		game.pivot.position = Vector3(0,1.40,-.72)
		game.arm.spring_length = 3.8
		_rear_rider()
		_target(_seller_site(),"Infanta · Esquina de Tejas")
	else: _target(_home(),"Mi casa")
	return true

func _discard_bike() -> void:
	_remove_riders()
	if is_instance_valid(bike):
		bike.collision_layer = 0
		bike.queue_free()
	bike = null

func _discard_cab() -> void:
	if is_instance_valid(cab):
		cab.collision_layer = 0
		cab.queue_free()
	cab = null

func _release_cab() -> void:
	# Return the mission taxi to the ordinary parked pool rather than
	# accumulating a new taxi after each replay.
	if is_instance_valid(cab):
		cab.remove_from_group("traffic_parked")
		cab.collision_layer = 0
		cab.queue_free()
	cab = null

func _seller_site() -> Vector3:
	if seller_point.is_finite(): return seller_point
	var saved := _decode(state.get("seller",{}))
	if saved.is_finite():
		seller_point = saved
		return seller_point
	var corners: Array[Vector3] = game.carlos_mission._corners("infanta","monte")
	if corners.is_empty(): corners = game.carlos_mission._corners("infanta","tejas")
	if corners.is_empty(): corners = game.carlos_mission._corners("infanta","cerro")
	if corners.is_empty(): return Vector3.INF
	var home := _home()
	corners.sort_custom(func(a,b): return home.distance_squared_to(a)<home.distance_squared_to(b))
	for corner in corners:
		var p := _near_ground(corner,null,18.0)
		if not p.is_finite(): continue
		seller_point = p
		state.seller = _encode(p)
		_save()
		return p
	return Vector3.INF

func _spawn_seller() -> void:
	var p := _seller_site()
	if not p.is_finite(): return
	if not is_instance_valid(seller): seller = _person(933,p,"Vendedor")
	seller.show()
	_target(p,"Infanta · vendedor del PS5")

func open_call() -> void:
	match _stage():
		1:
			business._open("Llamada entrante · Yordi","Mano, ¿estás en casa? Quiero pasar a verte.")
			business._button("Sí, ven para acá",_accept_visit)
			business._button("Ahora no",business.close)
		4:
			business._open("Yordi","Vamos para Infanta, esquina de Tejas.")
			if not _seller_site().is_finite():
				business._button("Confirmar vendedor en el punto marcado del mapa",_confirm_seller)
			business._button("Cerrar",business.close)
		12:
			if bool(state.get("delivered",false)): open_listing()
			else:
				business._open("Yordi","Lleva el PS5 a casa primero.")
				business._button("Cerrar",business.close)
		_:
			business._open("Yordi",objective() if _stage()<14 else "Gracias, mano. Ya cobraste tus mil pesos.")
			business._button("Cerrar",business.close)

func _confirm_seller() -> void:
	if _stage()!=4 or not game.garage.waypoint_active: return
	var label_value: String = game.garage.waypoint_label
	if label_value.contains("Moto de Yordi") or label_value.contains("Mi casa"):
		business._notify("Marca primero la esquina correcta en el mapa.")
		return
	var point: Vector3 = game.garage.waypoint_point
	var p := _near_ground(point,null,18.0)
	if not p.is_finite():
		business._notify("El punto marcado no tiene una acera válida.")
		return
	seller_point = p
	state.seller = _encode(p)
	_save()
	business.close()
	if is_instance_valid(bike): _target(bike.global_position,"Moto de Yordi")
	business._notify("Punto de venta confirmado.")

func _accept_visit() -> void:
	business.close()
	visit_elapsed = 0.0
	visit_retry = 0.0
	visit_notice = false
	_set_stage(2)
	_target(_home(),"Mi casa · visita de Yordi")

func _show_cinema(kind: String,actor: Node3D,words: String,button_text: String,callback: Callable) -> void:
	cinematic = kind
	if not is_instance_valid(cut_camera):
		cut_camera = Camera3D.new()
		add_child(cut_camera)
	var player_point: Vector3 = game.player.global_position
	var point := (actor.global_position+Vector3.UP*1.25+player_point)*.5
	var direction := actor.global_position-player_point
	direction.y = 0.0
	if direction.length_squared()<.1: direction = Vector3.FORWARD
	var side := Vector3(-direction.z,0,direction.x).normalized()
	var candidate := point+side*2.6+Vector3.UP*.75
	var ray := PhysicsRayQueryParameters3D.create(point,candidate,1|2|4|8)
	ray.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty(): candidate = point.lerp(hit.position,.72)
	cut_camera.global_position = candidate
	if candidate.distance_to(point)>.25: cut_camera.look_at(point)
	cut_camera.current = true
	business.phone_mode = false
	business._open("Yordi" if kind=="visit" else "Esquina de Tejas",words)
	business._button(button_text,callback)
	business._button("Omitir escena",callback)

func _end_cinema() -> void:
	cinematic = ""
	game.play_camera.current = true
	business.close()

func _visit_scene() -> void:
	if _stage()!=3: return
	_show_cinema("visit",yordi,"Yordi: Mano, ¿qué haces?\nTú: Nada, aquí viendo qué cae. Estoy armando una bici.\nYordi: Si quieres, vamos a Infanta. Hay un PS5 barato para revender. Yo pago todo y te doy mil pesos cuando lo vendamos.","Dale, vamos",_accept_job)

func _accept_job() -> void:
	_end_cinema()
	pickup_point = Vector3.INF
	rendezvous_clock = 0.0
	exit_elapsed = 0.0
	exit_retry_clock = 0.0
	bike_walk_elapsed = 0.0
	bike_wait_point = Vector3.INF
	if is_instance_valid(yordi): walkers.erase(yordi.get_instance_id())
	_set_stage(4)
	business._notify("Yordi: Dale, mano. Vamos para la moto.")
	if is_instance_valid(bike): _target(bike.global_position,"Moto de Yordi")

# Home and city are separate spaces; the NPC must cross the same logical
# doorway as the player instead of trying to walk between elevations.
func on_home_exit() -> void:
	if _stage()!=4 or not is_instance_valid(yordi): return
	exit_retry_clock = 0.0
	rendezvous_clock = 0.0
	if yordi.global_position.y>50.0: _leave_home_for_bike()

func _leave_home_for_bike() -> bool:
	var p := _home_door_point()
	if not p.is_finite(): p = _near_ground(_home(),yordi,12.0)
	if not p.is_finite(): return false
	_ensure_yordi(p)
	bike_wait_point = Vector3.INF
	rendezvous_clock = 0.0
	bike_walk_elapsed = 0.0
	return true

func _bike_wait_site() -> Vector3:
	if not is_instance_valid(bike): return Vector3.INF
	var at := bike.global_position
	# Prefer a reachable sidewalk on either side, close enough for boarding.
	for distance in [1.5,2.2,3.0,4.0,5.0]:
		for side in [-1.0,1.0]:
			for along in [0.0,1.5,-1.5]:
				var p := _ground(at+bike.global_basis.x*float(side)*float(distance)+bike.global_basis.z*float(along))
				if not p.is_finite() or p.distance_to(at)>5.8: continue
				if not world.pedestrian_space_clear(yordi,p,.65,false): continue
				if world.pedestrian_segment_clear(yordi.global_position,p): return p
				var route: PackedVector3Array = game.monte_pedestrians.route_between(yordi.global_position,p)
				if not route.is_empty(): return p
	# A clear patch beside the parked bike is also usable when there is
	# no mapped sidewalk close enough. Do not stand in the bike itself.
	for side in [-1.0,1.0]:
		var p := _ground(at+bike.global_basis.x*float(side)*1.5,false)
		if p.is_finite() and world.pedestrian_space_clear(yordi,p,.65,false): return p
	return Vector3.INF

func _tick_departure(delta: float) -> void:
	if not is_instance_valid(bike) or not is_instance_valid(yordi): return
	if yordi.global_position.y>50.0:
		exit_elapsed += delta
		if game.garage.inside:
			var exit_point: Vector3 = Garage.ROOM+Vector3(-.7,0,5.25)
			var reached := _walk(yordi,exit_point,delta,2.5,.65)
			if not reached and exit_elapsed<8.0: return
		exit_retry_clock -= delta
		if exit_retry_clock>0.0: return
		exit_retry_clock = .75
		if not _leave_home_for_bike(): return
	if yordi.global_position.distance_to(bike.global_position)<=4.0:
		yordi.animate(delta,false)
		return
	bike_walk_elapsed += delta
	rendezvous_clock -= delta
	if rendezvous_clock<=0.0:
		rendezvous_clock = 3.0
		if not bike_wait_point.is_finite() or bike_walk_elapsed>=12.0:
			bike_wait_point = _bike_wait_site()
			walkers.erase(yordi.get_instance_id())
			bike_walk_elapsed = 0.0
	if bike_wait_point.is_finite(): _walk(yordi,bike_wait_point,delta,2.8,.6)

func _aim(actor: Node3D,center: Vector3,extent: Vector3,reach: float = 3.0) -> bool:
	if not is_instance_valid(actor) or not actor.is_visible_in_tree(): return false
	var cam: Camera3D = game.play_camera
	var origin := cam.global_position
	var finish := origin-cam.global_basis.z*5.0
	var hit: Variant = AABB(center-extent,extent*2.0).intersects_segment(actor.to_local(origin),actor.to_local(finish))
	if hit==null: return false
	var point := actor.to_global(hit)
	if game.player.global_position.distance_to(point)>reach: return false
	var ray := PhysicsRayQueryParameters3D.create(origin,point,1|4|8|16|32)
	ray.exclude = [game.player.get_rid()]
	if actor is CollisionObject3D: ray.exclude = [game.player.get_rid(),(actor as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func action_text() -> String:
	if _busy(): return ""
	if _stage()==7 and not robbery_phase.is_empty():
		if robbery_phase=="pickup" and _aim(stone,Vector3.ZERO,Vector3(.22,.16,.22),3.0): return "[E] Recoger piedra"
		return _robbery_objective()
	if not paused_trip.is_empty():
		var vehicle: CharacterBody3D = paused_trip.body
		if paused_role=="bike_out" and _aim(vehicle,Vector3(0,.7,0),Vector3(.65,.8,1.2),3.6): return "[E] Volver a subir a la moto de Yordi"
		if paused_role=="taxi_home" and _aim(vehicle,Vector3(0,.9,0),Vector3(1.1,1.0,2.5),4.0): return "[E] Volver a subir al taxi de Yordi"
	if _stage()==3 and _aim(yordi,Vector3.UP,Vector3(.5,1.0,.4)): return "[E] Hablar con Yordi"
	if _stage()==4 and _aim(bike,Vector3(0,.7,0),Vector3(.65,.8,1.2),3.6): return "[E] Subir detrás de Yordi"
	if _stage()==6 and _aim(seller,Vector3.UP,Vector3(.5,1.0,.4)): return "[E] Comprar PS5 con Yordi"
	if _stage()==7 and _aim(bike,Vector3(0,.7,0),Vector3(.7,.8,1.2),5.0): return "[E] Volver a la moto"
	if _stage()==10 and _aim(cab,Vector3(0,.9,0),Vector3(1.1,1.0,2.5),4.0): return "[E] Subir al taxi de Yordi"
	return ""

func interact() -> bool:
	if _stage()==8: return true
	if _stage()==7 and not robbery_phase.is_empty():
		if robbery_phase=="pickup" and _aim(stone,Vector3.ZERO,Vector3(.22,.16,.22),3.0): _pickup_stone()
		return true
	var action := action_text()
	if action.is_empty(): return false
	if not paused_trip.is_empty():
		if not _resume_passenger(): business._notify("Deja tus manos libres y vuelve a intentar subir.")
		return true
	match _stage():
		3: _visit_scene()
		4:
			if not game.garage._free_hands():
				business._notify("Deja lo que llevas antes de subir a la moto.")
				return true
			var p := _seller_site()
			if not p.is_finite():
				business._notify("No se encontró Esquina de Tejas en el mapa cargado.")
				return true
			if not is_instance_valid(yordi) or yordi.global_position.distance_to(bike.global_position)>6.0 or yordi.global_position.y>50.0:
				business._notify("Espera a Yordi. Está caminando hacia la moto.")
				return true
			if _start_trip(bike,p,"Esquina de Tejas","bike_out",true):
				_driver()
				_rear_rider()
				_set_stage(5)
				_target(p,"Infanta · Esquina de Tejas")
			else: business._notify("Yordi: No encuentro paso por esta calle. Intenta otra vez.")
		6:
			if not is_instance_valid(yordi) or yordi.global_position.distance_to(seller.global_position)>5.0:
				business._notify("Espera a Yordi para pagar.")
				return true
			business._open("Vendedor","Aquí está el PS5. Yordi paga el precio acordado con su propio dinero.")
			business._button("Recibir el PS5",_purchase)
		7: _start_robbery()
		10:
			if is_instance_valid(yordi) and yordi.global_position.distance_to(cab.global_position)>8.0:
				business._notify("Espera a Yordi.")
				return true
			if _start_trip(cab,_home(),"Mi casa","taxi_home",true):
				yordi.hide()
				_set_stage(11)
			else: business._notify("El taxi no encuentra una ruta a casa. Intenta de nuevo.")
	return true

func _purchase() -> void:
	if _stage()!=6: return
	business.close()
	_carry_ps5()
	state.purchased = true
	state.checkpoint = {"seller":_encode(seller_point),"bike":_encode(bike.global_position),"heading":_encode(bike.global_basis.z)}
	_set_stage(7)
	if is_instance_valid(seller): seller.hide()
	_target(bike.global_position,"Moto de Yordi")
	business._notify("Yordi: Ya está pagado. Vamos para la moto.")

func _spawn_foes(at: Vector3) -> bool:
	_clear_foes()
	var slots: Array[Vector3] = []
	for radius in [4.5,6.0,8.0,10.0]:
		for i in range(12):
			var angle := float(i)*TAU/12.0
			var p := _ground(at+Vector3(cos(angle),0,sin(angle))*float(radius),false)
			if not p.is_finite() or not world.pedestrian_space_clear(null,p,.85,false): continue
			if not world.pedestrian_segment_clear(p,at+(p-at).normalized()*1.45): continue
			var free := true
			for slot in slots:
				if slot.distance_to(p)<1.5: free = false
			if not free: continue
			slots.append(p)
			if slots.size()>=5: break
		if slots.size()>=5: break
	if slots.size()<5: return false
	for i in range(5):
		var foe := _person(1200+i*3,slots[i])
		# Fictional low-poly mask and wooden prop, no combat physics.
		var mask := Node3D.new()
		foe.add_child(mask)
		business._box(mask,Vector3(0,1.68,0),Vector3(.29,.30,.30),Color("#25292d"))
		business._box(mask,Vector3(0,1.72,.154),Vector3(.19,.055,.018),Color("#9b694b"))
		var club := Node3D.new()
		foe.arms[1].add_child(club)
		club.position = Vector3(0,-.48,.04)
		business._box(club,Vector3(0,0,.22),Vector3(.055,.055,.60),Color("#806447"))
		foes.append(foe)
	return true

func _clear_foes() -> void:
	for foe in foes:
		if is_instance_valid(foe):
			walkers.erase(foe.get_instance_id())
			foe.queue_free()
	foes.clear()
	if is_instance_valid(stone): stone.queue_free()
	stone = null
	robbery_phase = ""
	robbery_clock = 0.0
	escape_route = PackedVector3Array()
	escape_index = 0
	escape_goal = Vector3.INF
	if stone_camera_changed:
		game.first_person = stone_camera_previous
		game._apply_camera_mode()
		stone_camera_changed = false

func _robbery_objective() -> String:
	match robbery_phase:
		"approach": return "Un grupo se está acercando..."
		"pickup": return "Mira la piedra en el suelo y pulsa E."
		"held": return "Apunta y pulsa clic izquierdo para lanzar la piedra."
	return "Regresa con Yordi a la moto."

func robbery_active() -> bool:
	return _stage()==7 and not robbery_phase.is_empty()

func guided_escape_route() -> PackedVector3Array:
	if _stage()!=8: return PackedVector3Array()
	return escape_route

# Choose a reachable public sidewalk checkpoint once, rather than
# making the player run an arbitrary distance in an unknown direction.
func _plan_escape(from: Vector3) -> PackedVector3Array:
	var pedestrians = game.monte_pedestrians
	var start: int = pedestrians._nearest(from,12.0)
	if start<0: return PackedVector3Array()
	var candidates: Array = []
	for id in pedestrians._near_ids(from,95.0):
		var point: Vector3 = pedestrians.graph.get_point_position(int(id))
		var gap := from.distance_to(point)
		if gap<30.0 or gap>90.0: continue
		if pedestrians.graph.get_point_connections(int(id)).is_empty(): continue
		candidates.append({"id":int(id),"score":absf(gap-65.0)})
	candidates.sort_custom(func(a,b): return float(a.score)<float(b.score))
	var fallback := PackedVector3Array()
	for option in candidates.slice(0,24):
		var middle: PackedVector3Array = pedestrians.graph.get_point_path(start,int(option.id))
		if middle.size()<3: continue
		var length := 0.0
		var previous := from
		for point in middle:
			length += previous.distance_to(point)
			previous = point
		if length>145.0 or length<35.0: continue
		var end := middle[middle.size()-1]
		if not world.pedestrian_segment_clear(end,end): continue
		var route := PackedVector3Array([from])
		route.append_array(middle)
		if fallback.is_empty(): fallback = route
		if length>=60.0 and length<=115.0: return route
	return fallback

func _start_robbery() -> void:
	if _stage()!=7 or not robbery_phase.is_empty() or not is_instance_valid(yordi): return
	if yordi.global_position.distance_to(game.player.global_position)>5.0:
		business._notify("Espera a Yordi, que tiene el PS5.")
		return
	var at: Vector3 = game.player.global_position-Vector3.UP*.86
	var path := _plan_escape(yordi.global_position)
	if path.is_empty():
		business._notify("Yordi: Ven conmigo a la acera.")
		return
	if not _spawn_foes(at):
		business._notify("Espera un momento junto a la moto.")
		return
	escape_route = path
	escape_index = 1
	escape_goal = path[path.size()-1]
	chase_origin = at
	state.chase_start = _encode(at)
	robbery_phase = "approach"
	robbery_clock = 0.0
	stone_camera_previous = game.first_person
	stone_camera_changed = true
	game.first_person = true
	game._apply_camera_mode()
	_clear_target()
	_save()
	business._notify("Yordi: Mano, mira esa gente que viene para acá...")

func _stone_model(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	var mesh := SphereMesh.new()
	mesh.radius = .075
	mesh.height = .13
	mesh.radial_segments = 6
	mesh.rings = 3
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.scale = Vector3(1.0,.8,1.25)
	visual.material_override = business._mat(Color("#79736c"))
	root.add_child(visual)
	return root

func _place_stone() -> bool:
	var cam: Camera3D = game.play_camera
	var at: Vector3 = game.player.global_position-Vector3.UP*.86
	var direction := -cam.global_basis.z
	direction.y = 0.0
	if direction.length_squared()<.01: direction = Vector3.FORWARD
	direction = direction.normalized()
	for distance in [1.25,1.75,2.25]:
		for angle in [0.0,.65,-.65,1.3,-1.3,PI]:
			var p := _ground(at+direction.rotated(Vector3.UP,float(angle))*float(distance),false)
			if not p.is_finite() or not world.pedestrian_segment_clear(p,p): continue
			if not world.pedestrian_space_clear(null,p,.24,false): continue
			stone = _stone_model(self)
			stone.global_position = p+Vector3.UP*.065
			marker.global_position = p-Vector3.UP*1.2
			marker.show()
			return true
	return false

func _robbery_tick(delta: float) -> void:
	robbery_clock += delta
	var at: Vector3 = game.player.global_position-Vector3.UP*.86
	for foe in foes:
		if not is_instance_valid(foe): continue
		if robbery_phase=="approach" and robbery_clock<2.8:
			_walk(foe,at,delta,1.65,2.3)
		else:
			var facing := at-foe.global_position
			if facing.length_squared()>.04: foe.rotation.y = lerp_angle(foe.rotation.y,atan2(facing.x,facing.z),minf(1.0,delta*6.0))
			foe.animate(delta,false)
			foe.arms[1].rotation.x = -.45+sin(robbery_clock*3.0)*.10
	_carry_pose()
	if robbery_phase=="approach" and robbery_clock>=2.8:
		if not _place_stone():
			robbery_clock = 2.3
			return
		robbery_phase = "pickup"
		business._notify("Asaltante: ¡Denme las llaves de la moto y el PS5!  Yordi: Mano, la piedra.")
	if robbery_phase=="held" and is_instance_valid(stone):
		stone.rotation.z = sin(robbery_clock*2.0)*.04

func _pickup_stone() -> void:
	if robbery_phase!="pickup" or not is_instance_valid(stone): return
	if not game.garage._free_hands():
		business._notify("Necesitas las manos libres.")
		return
	stone.reparent(game.play_camera,false)
	stone.position = Vector3(.26,-.24,-.63)
	stone.rotation = Vector3.ZERO
	robbery_phase = "held"
	marker.hide()
	business._notify("Clic izquierdo para lanzar. Después sigue a Yordi.")

func throw_stone() -> bool:
	if _stage()!=7 or robbery_phase!="held" or not is_instance_valid(stone): return false
	var cam: Camera3D = game.play_camera
	var direction := -cam.global_basis.z.normalized()
	stone.reparent(self,true)
	stone_velocity = direction*13.0
	stone_clock = 0.0
	distracted_foe = -1
	_start_chase()
	return true

func _stone_tick(delta: float) -> void:
	if not is_instance_valid(stone): return
	stone_clock += delta
	var from := stone.global_position
	stone_velocity.y -= 9.8*delta
	var to := from+stone_velocity*delta
	var query := PhysicsRayQueryParameters3D.create(from,to,1|2|4|8|16|32)
	query.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var closest := from.distance_to(to)
	var impact := false
	if not hit.is_empty():
		var point: Vector3 = hit.position
		closest = from.distance_to(point)
		to = point
		impact = true
	for i in range(foes.size()):
		var foe := foes[i]
		if not is_instance_valid(foe): continue
		var bounds := AABB(Vector3(-.24,.12,-.22),Vector3(.48,1.65,.44))
		var local_hit: Variant = bounds.intersects_segment(foe.to_local(from),foe.to_local(to))
		if local_hit==null: continue
		var point: Vector3 = foe.to_global(local_hit)
		if from.distance_to(point)>closest: continue
		closest = from.distance_to(point)
		distracted_foe = i
		to = point
		impact = true
	stone.global_position = to
	stone.rotate_x(delta*8.0)
	if impact or stone_clock>=2.0:
		stone.queue_free()
		stone = null

func _start_chase() -> void:
	if foes.size()!=5 or escape_route.is_empty(): return
	robbery_phase = ""
	_set_stage(8)
	chase_clock = 0.0
	run_clock = 0.0
	chase_sample = 0.0
	chase_grace = 3.0
	slow_clock = 0.0
	key_line = false
	last_player = game.player.global_position
	leader_last = yordi.global_position
	leader_retry = 0.0
	walkers.erase(yordi.get_instance_id())
	_target(escape_goal,"Refugio · sigue a Yordi")
	business._notify("Yordi: ¡Corre, sígueme! Yo sé por dónde.")

func _lead_escape(delta: float,player_at: Vector3) -> void:
	if not is_instance_valid(yordi): return
	while escape_index<escape_route.size() and yordi.global_position.distance_to(escape_route[escape_index])<.7:
		escape_index += 1
	if escape_index>=escape_route.size():
		yordi.animate(delta,false)
		_carry_pose()
		return
	var gap := yordi.global_position.distance_to(player_at)
	# Lead at a pace the player can follow, and wait briefly if separated.
	var pace := 6.4 if gap<9.0 else (3.0 if gap<16.0 else 0.0)
	var next := escape_route[escape_index]
	if pace>0.0:
		_walk(yordi,next,delta,pace,.45)
	else: yordi.animate(delta,false)
	leader_retry += delta
	if leader_retry>=3.0:
		if pace>0.0 and leader_last.distance_to(yordi.global_position)<.7:
			var replacement: PackedVector3Array = game.monte_pedestrians.route_between(yordi.global_position,escape_goal)
			if not replacement.is_empty():
				escape_route = replacement
				escape_index = 1
				walkers.erase(yordi.get_instance_id())
		leader_last = yordi.global_position
		leader_retry = 0.0
	_carry_pose()

func _chase_tick(delta: float) -> void:
	chase_clock += delta
	chase_grace = maxf(0.0,chase_grace-delta)
	var player_at: Vector3 = game.player.global_position
	var target := player_at-Vector3.UP*.86
	_stone_tick(delta)
	_lead_escape(delta,target)
	if is_instance_valid(yordi):
		marker.global_position = yordi.global_position
		marker.show()
	var nearest := INF
	for i in range(foes.size()):
		var foe := foes[i]
		if not is_instance_valid(foe): continue
		if chase_clock<1.1 or (i==distracted_foe and chase_clock<2.8):
			foe.animate(delta,false)
		else: _walk(foe,target,delta,RIVAL_SPEED,1.0)
		nearest = minf(nearest,foe.global_position.distance_to(target))
	if not key_line and chase_clock>3.0:
		key_line = true
		business._notify("Tú: ¡Yordi, y la moto!  Yordi: No te preocupes, ¡yo tengo la llave!")
	chase_sample += delta
	if chase_sample>=.25:
		var elapsed := chase_sample
		chase_sample = 0.0
		var moving := Vector2(player_at.x-last_player.x,player_at.z-last_player.z).length()/elapsed
		last_player = player_at
		if moving>=5.5:
			run_clock += elapsed
			slow_clock = 0.0
		else: slow_clock += elapsed
	if escape_goal.is_finite() and target.distance_to(escape_goal)<5.0 and is_instance_valid(yordi) and yordi.global_position.distance_to(escape_goal)<5.0:
		var safe := escape_goal
		_clear_foes()
		pickup_point = safe
		state.pickup = _encode(safe)
		_set_stage(9)
		_target(safe,"Punto de recogida del taxi")
		business._notify("Yordi: Ya los perdimos. Voy a llamar un taxi; yo lo pago.")
		business.ledger.add_message("Yordi","Pedí un taxi para regresar a casa. Tengo el PS5 y la llave de la moto.")
		_save()
		return
	if chase_grace<=0.0 and slow_clock>=1.25 and nearest<1.85:
		_retry_chase()

func _retry_chase() -> void:
	_clear_foes()
	_set_stage(7)
	restore_pending = true
	business._notify("Te alcanzaron. Volviendo al punto de control antes de la huida.")

func checkpoint_reset() -> bool:
	if _stage() not in [7,8]: return false
	_retry_chase()
	return true

func _restore_checkpoint() -> bool:
	var checkpoint: Dictionary = state.get("checkpoint",{})
	var p := _decode(checkpoint.get("seller",{}))
	var park := _decode(checkpoint.get("bike",{}))
	var d := _decode(checkpoint.get("heading",{}))
	if not p.is_finite() or not park.is_finite() or not d.is_finite(): return false
	var saved := _decode(state.get("chase_start",{}))
	var at := _near_ground(saved if saved.is_finite() else p,null,12.0)
	if not at.is_finite(): return false
	if not is_instance_valid(bike):
		# Restore only into a free berth, never inside another vehicle.
		var berth := _road_berth(park,0.0,18.0,.85,2.1,1.8)
		if berth.is_empty(): return false
		_spawn_bike(berth)
	game.player.global_position = at+Vector3.UP*.86
	game.player.velocity = Vector3.ZERO
	var companion := _near_ground(at,yordi,5.0)
	_ensure_yordi(companion if companion.is_finite() else at)
	_carry_ps5()
	_target(bike.global_position,"Moto de Yordi · punto de control")
	restore_pending = false
	return true

func can_list() -> bool:
	return _stage()==12 and bool(state.get("delivered",false))

func open_listing() -> void:
	if not can_list(): return
	business._open("Facebook Marketplace · PS5","Publica el PS5 de Yordi. Él pagó la compra y el taxi. Tu pago acordado es de 1,000 CUP al concretarse la venta.")
	business._button("Publicar PS5",_publish)
	business._button("Volver",game.garage.open_phone_market)

func _publish() -> void:
	if not can_list(): return
	state.sale_left = SALE_DELAY
	_set_stage(13)
	business.close()
	business._notify("PS5 publicado. Esperando comprador.")

static func settle_sale(mission: Dictionary,ledger) -> bool:
	if int(mission.get("stage",0))!=13 or bool(mission.get("reward_paid",false)) or not bool(mission.get("delivered",false)): return false
	mission.reward_paid = true
	mission.stage = 14
	if not bool(mission.get("previous_reward_paid",false)): ledger.cash += REWARD
	ledger.add_message("Yordi","Ya vendimos el PS5. Tu pago anterior se conserva." if bool(mission.get("previous_reward_paid",false)) else "Ya vendimos el PS5. Aquí tienes tus mil pesos, como te prometí.")
	return true

func _complete_sale() -> void:
	if not settle_sale(state,business.ledger): return
	_save()
	if is_instance_valid(console_box): console_box.queue_free()
	console_box = null
	if is_instance_valid(yordi): yordi.hide()
	_clear_target()
	business._notify("MISIÓN CUMPLIDA · recompensa ya recibida" if bool(state.get("previous_reward_paid",false)) else "MISIÓN CUMPLIDA · +1,000 CUP")

func _police_call() -> void:
	if bool(state.get("police",false)): return
	state.police = true
	business.ledger.add_message("Yordi","La policía me llamó. Encontraron la moto parqueada; no se la pudieron llevar porque tengo la llave.")
	_save()
	business.phone_ring.play()
	business.phone_mode = false
	business._open("Llamada a Yordi · Policía","Policía: Encontramos tu moto estacionada en la zona de Tejas. Puedes venir a recogerla.\nYordi: ¿Viste, mano? Yo tenía la llave. La moto está bien.")
	business._button("Continuar",business.close)
	# Retrieval of the parked bike happens off-screen after the police call.
	_discard_bike()

func _deliver_home() -> void:
	if not game.garage.inside or _stage()!=12: return
	var point: Vector3 = Garage.ROOM+Vector3(-2.1,0,3.0)
	_ensure_yordi(point+Vector3(.7,0,0))
	if not is_instance_valid(console_box): console_box = _box_ps5(self)
	elif console_box.get_parent()!=self: console_box.reparent(self,false)
	console_box.global_position = point+Vector3.UP*.19
	console_box.rotation = Vector3.ZERO
	console_box.show()
	state.delivered = true
	_clear_target()
	_save()
	business._notify("Yordi: Déjalo aquí. Publícalo en Marketplace y te doy los mil pesos cuando se venda.")

# If the autonomous approach cannot finish, complete only the off-screen
# leg of the visit at a verified free parking berth near the real home.
# Never reposition a ridden motorcycle or an unrelated taxi.
func _recover_visit() -> bool:
	if _stage()!=2 or not game.garage.inside or game.taxi_riding: return false
	if not service.passenger.is_empty() and (not is_instance_valid(bike) or service.passenger.body!=bike): return false
	var home := _home()
	if not home.is_finite(): return false
	var door_point := _home_door_point()
	if not door_point.is_finite(): return false
	var berth := _road_berth(home,3.0,24.0,.85,2.1,1.8)
	if berth.is_empty(): berth = _road_berth(home,3.0,45.0,.85,2.1,1.8)
	if berth.is_empty():
		if not visit_notice:
			visit_notice = true
			business._notify("Yordi: Estoy cerca, buscando dónde parquear.")
		return false
	if not service.passenger.is_empty(): service.finish_trip()
	trip_role = ""
	trip_body = null
	_remove_riders()
	if not is_instance_valid(bike): _spawn_bike(berth)
	else:
		var d: Vector3 = berth.d
		bike.global_transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),berth.p)
		bike.velocity = Vector3.ZERO
		bike.remove_from_group("autonomous_traffic")
		bike.add_to_group("traffic_parked")
		bike.set_meta("traffic_servicing",false)
		state.bike_berth = {"p":_encode(berth.p),"d":_encode(d),"next":String(berth.next)}
	# The player is inside; this is an off-screen arrival, not a visible teleport.
	_ensure_yordi(door_point)
	pickup_point = door_point
	visit_foot_elapsed = 0.0
	rendezvous_clock = 0.0
	_set_stage(3)
	_target(home,"Yordi está llegando a casa")
	business._notify("Yordi: Ya parqueé la moto. Estoy en la puerta.")
	print("Misión Yordi: llegada alternativa en estacionamiento libre.")
	return true

func _home_door_point() -> Vector3:
	var home := _home()
	if not home.is_finite(): return Vector3.INF
	var basis: Basis = world.garage_home_site.basis
	for distance in [.9,1.5,2.1]:
		for lateral in [0.0,.7,-.7,1.4,-1.4]:
			var p := _ground(home+basis.z*float(distance)+basis.x*float(lateral))
			if p.is_finite() and world.pedestrian_space_clear(yordi,p,.65,false): return p
	return _near_ground(home,yordi,5.0)

func _arrival_tick(delta: float) -> void:
	if not is_instance_valid(trip_body): return
	trip_elapsed += delta
	if not service.ready_to_exit():
		if trip_elapsed>180.0:
			var failed_role := trip_role
			service.finish_trip()
			trip_role = ""
			trip_body = null
			if failed_role=="visit": _discard_bike()
			else: _discard_cab()
			retry_clock = 4.0
		return
	arrival_wait -= delta
	if arrival_wait>0.0: return
	arrival_wait = .5
	var role := trip_role
	var body := trip_body
	var p := _near_ground(body.global_position,yordi,14.0)
	if not p.is_finite():
		if trip_elapsed>200.0:
			service.finish_trip()
			trip_body = null
			trip_role = ""
			if role=="visit": _discard_bike()
			else: _discard_cab()
		return
	service.finish_trip()
	trip_role = ""
	trip_body = null
	if role=="visit":
		pickup_point = Vector3.INF
		rendezvous_clock = 0.0
		_remove_riders()
		_ensure_yordi(p)
		visit_foot_elapsed = 0.0
		_set_stage(3)
		_target(_home(),"Yordi está llegando a casa")
	elif role=="taxi_pickup":
		_set_stage(10)
		_target(body.global_position,"Taxi de Yordi")

func tick(delta: float) -> void:
	if cinematic!="" and not business.modal_open():
		cinematic = ""
		game.play_camera.current = true
		if _stage()==7: _clear_foes()
	if business.modal_open() or game.building_mode or (game.city_navigation!=null and game.city_navigation.active): return
	var stage := _stage()
	if stage==0:
		if not bool(state.get("replay_ready",false)) and (not bool(game.garage.state.get("wheel_tutorial",false)) or game.carlos_mission._stage()!=5): return
		if _busy() or not game.garage.inside or not game.garage._free_hands(): return
		call_clock += delta
		if call_clock<8.0: return
		_set_stage(1)
		business.ledger.add_message("Yordi","Mano, ¿estás en casa? Quiero pasar a verte.")
		_save()
		business.phone_ring.play()
		open_call()
		return
	if stage==1 or stage==14: return
	if not game.monte_pedestrians.initialized: return
	if stage==13:
		state.sale_left = maxf(0.0,float(state.get("sale_left",SALE_DELAY))-delta)
		if float(state.sale_left)<=0.0: _complete_sale()
		return
	if restore_pending:
		retry_clock -= delta
		if retry_clock<=0.0:
			retry_clock = 2.0
			_restore_checkpoint()
		return
	if stage==2 and game.garage.inside and not _busy():
		visit_elapsed += delta
		visit_retry -= delta
		if visit_elapsed>=35.0 and visit_retry<=0.0:
			visit_retry = 4.0
			if _recover_visit(): return
	if not trip_role.is_empty() and not game.taxi_riding:
		_arrival_tick(delta)
		return
	if stage==5 or stage==11: return
	if _busy(): return
	var player_at: Vector3 = game.player.global_position-Vector3.UP*.86
	retry_clock -= delta
	match stage:
		2:
			var home := _home()
			if not home.is_finite(): return
			if not game.garage.inside and player_at.distance_to(home)>18.0: return
			if retry_clock>0.0: return
			retry_clock = 3.0
			if not is_instance_valid(bike):
				var berth := _road_berth(home,45.0,120.0,.85,2.1,1.8)
				if berth.is_empty(): return
				_spawn_bike(berth)
			if _start_trip(bike,home,"Casa de mi hermano","visit",false): _driver()
			else:
				# A failed plan must not leave the same parked bike retrying forever.
				_discard_bike()
		3:
			if not is_instance_valid(yordi): return
			var home := _home()
			if game.garage.inside:
				if yordi.global_position.y<50.0:
					rendezvous_clock -= delta
					if rendezvous_clock<=0.0:
						rendezvous_clock = 1.0
						var door_point := _home_door_point()
						if door_point.is_finite(): pickup_point = door_point
					visit_foot_elapsed += delta
					if not pickup_point.is_finite(): return
					if not _walk(yordi,pickup_point,delta,2.4,1.2) and visit_foot_elapsed<15.0: return
					var entry := Garage.ROOM+Vector3(-1.6,0,4.1)
					if not world.pedestrian_segment_clear(entry,entry) or not world.pedestrian_space_clear(yordi,entry,.7,false): return
					_ensure_yordi(entry)
					business._notify("Yordi: ¡Mano, ya llegué!")
				if _walk(yordi,player_at,delta,2.0,2.1): _visit_scene()
			elif _walk(yordi,player_at,delta,2.5,2.1): _visit_scene()
		4: _tick_departure(delta)
		6:
			if is_instance_valid(yordi):
				_walk(yordi,player_at,delta,3.5,1.8)
		7:
			if not robbery_phase.is_empty():
				_robbery_tick(delta)
				return
			if is_instance_valid(yordi):
				_walk(yordi,player_at,delta,3.5,1.8)
				_carry_pose()
			if is_instance_valid(bike) and player_at.distance_to(bike.global_position)<5.0 and retry_clock<=0.0:
				retry_clock = 2.0
				_start_robbery()
		8: _chase_tick(delta)
		9:
			_walk(yordi,player_at,delta,3.0,1.8)
			_carry_pose()
			if retry_clock>0.0: return
			retry_clock = 3.0
			if not pickup_point.is_finite(): pickup_point = _decode(state.get("pickup",{}))
			if not is_instance_valid(cab):
				var berth := _road_berth(pickup_point,35.0,110.0,1.9,4.8,1.8)
				if berth.is_empty(): return
				cab = service._make_taxi(1)
				cab.global_position = berth.p
				var d: Vector3 = berth.d
				cab.rotation.y = atan2(d.x,d.z)
				cab.add_to_group("traffic_parked")
			_start_trip(cab,pickup_point,"Recoger a Yordi","taxi_pickup",false)
		10:
			if is_instance_valid(yordi):
				_walk(yordi,player_at,delta,3.5,1.8)
				_carry_pose()
		12:
			if game.garage.inside:
				if not bool(state.get("delivered",false)) or not is_instance_valid(console_box): _deliver_home()
				if not bool(state.get("police",false)): _police_call()
			elif is_instance_valid(yordi) and not bool(state.get("delivered",false)):
				_walk(yordi,player_at,delta,3.5,1.8)
				_carry_pose()
