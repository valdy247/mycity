extends Node3D
# One active scene at a time. Existing pedestrian and vehicle controllers
# keep ownership of ordinary routines; only participants are reserved.
const Person = preload("res://street_person.gd")
const Bypass = preload("res://traffic_bypass.gd")
const WIDTH := 1.83
const LENGTH := 4.25
const HEIGHT := 1.65
var game
var world
var router
var market
var municipal
var streets
var data
var scene: Dictionary = {}
var injured: Array = []
var returning: Array = []
var crowd: Array = []
var police_wait := 35.0
var crowd_clock := 0.0
var rng := RandomNumberGenerator.new()

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	router = game.monte_pedestrians
	market = game.street_market
	municipal = game.monte_services
	streets = world.street_geometry
	data = world.geography
	rng.randomize()

func _say(person: Node3D,message: String) -> void:
	var bubble := Label3D.new()
	bubble.text = message
	bubble.font_size = 31
	bubble.pixel_size = .006
	bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	bubble.modulate = Color("#fff1d0")
	bubble.outline_size = 8
	person.add_child(bubble)
	bubble.position = Vector3(0,2.15,0)
	get_tree().create_timer(4.0).timeout.connect(func():
		if is_instance_valid(bubble): bubble.queue_free())

func _flat(p: Vector3) -> Vector3:
	return Vector3(p.x,0,p.z)

func _lock(agent: Dictionary,role: String) -> void:
	var p: Node3D = agent.node
	p.set_meta("incident_role",role)
	p.remove_meta("conversation_until")
	agent.erase("yield_target")
	p.remove_from_group("bus_yield_walkers")

func _release(agent: Dictionary) -> void:
	if agent.is_empty() or not is_instance_valid(agent.get("node")): return
	var p: Node3D = agent.node
	p.remove_meta("incident_role")
	var source := String(agent.get("incident_source","walker"))
	if source=="walker":
		p.add_to_group("bus_yield_walkers")
		agent.incident_replan = true
	elif source=="business":
		var life = game.business.life
		var owner: Dictionary = agent.owner
		owner.path = PackedVector3Array()
		owner.index = 0
		owner.task = "return_pending"
		owner.timer = 0.0
	elif source=="resident":
		agent.owner.origin = p.global_position
	elif source=="vendor":
		var stall: Dictionary = agent.owner
		stall.incident_busy = false
		if bool(agent.get("delivered",false)):
			stall.detained = true
			stall.open = false
			stall.root.hide()
			p.position = Vector3(0,0,1.08)
		elif not bool(stall.detained if stall.has("detained") else false):
			p.show()

# Accident detection uses every visible social actor, not just walkers.
# Bus passengers become ordinary walking agents once removed from the
# queue; other systems keep their own actor and suspend their routines.
func _impact_agent(person: Node3D) -> Dictionary:
	for agent in router.walkers:
		if agent.node==person: return agent
	if person is Person and game.urban_buses.detach_incident_person(person):
		person.reparent(router,true)
		var agent := {"node":person,"path":PackedVector3Array(),"index":0,"destination":{},"pause":0.0,"speed":1.35}
		router.walkers.append(agent)
		return agent
	for owner in game.business.life.agents:
		if owner.node==person:
			return {"node":person,"incident_source":"business","owner":owner,"parent":person.get_parent()}
	for stall in market.stalls:
		if stall.person==person and not bool(stall.get("incident_busy",false)):
			stall.incident_busy = true
			return {"node":person,"incident_source":"vendor","owner":stall,"parent":person.get_parent()}
	for resident in world.residents:
		if resident.node==person:
			return {"node":person,"incident_source":"resident","owner":resident,"parent":person.get_parent()}
	return {}

func _impact_parent(agent: Dictionary) -> Node:
	return agent.get("parent",router)

func _impact_contact(before: Transform3D,after: Transform3D,p: Vector3,width: float,length: float) -> Dictionary:
	var travel := _flat(after.origin-before.origin).length()
	var turn := absf(angle_difference(before.basis.get_euler().y,after.basis.get_euler().y))
	var count := clampi(ceili((travel+turn*length*.5)/.12),1,16)
	for i in range(count+1):
		var pose := before.interpolate_with(after,float(i)/float(count))
		var local := pose.affine_inverse()*p
		if absf(local.x)>width*.5+.25 or absf(local.z)>length*.5+.25: continue
		var surface := Vector3(clampf(local.x,-width*.5,width*.5),.65,clampf(local.z,-length*.5,length*.5))
		return {"surface":pose*surface}
	return {}

func _walkers(at: Vector3,radius: float) -> Array:
	var out: Array = []
	for agent in router.walkers:
		var p: Person = agent.node
		if not is_instance_valid(p) or not p.is_visible_in_tree() or p.has_meta("incident_role"): continue
		if bool(agent.get("indoors",false)) or p.global_position.distance_to(at)>radius: continue
		out.append(agent)
	out.sort_custom(func(a,b): return (a.node as Node3D).global_position.distance_squared_to(at)<(b.node as Node3D).global_position.distance_squared_to(at))
	return out

# Ground and live collision checks for actors that leave their normal path.
func _foot(p: Vector3) -> Dictionary:
	var result: Dictionary = router._ground(p)
	return result

func _ped_path(a: Vector3,b: Vector3) -> PackedVector3Array:
	if world.pedestrian_segment_clear(a,b): return PackedVector3Array([b])
	return router.route_between(a,b)

func _advance_actor(person: Person,path: PackedVector3Array,index: int,dt: float,speed: float = 1.5) -> int:
	if index>=path.size(): return index
	var target := path[index]
	var step := person.global_position.move_toward(target,speed*dt)
	if not world.pedestrian_segment_clear(person.global_position,step): return index
	if person.walk_to(target,dt,speed): return index+1
	return index

func _crowd_clear() -> void:
	for item in crowd: _release(item.agent)
	crowd.clear()

func _crowd_tick(center: Vector3,delta: float) -> void:
	crowd_clock += delta
	if crowd_clock>=1.2 and crowd.size()<8:
		crowd_clock = 0.0
		var candidates: Array = _walkers(center,22.0)
		# Leave the nearest available citizen free to help the driver.
		if (scene.is_empty() or (String(scene.get("kind",""))=="rescue" and String(scene.get("phase",""))=="approach")) and not candidates.is_empty(): candidates.pop_front()
		for agent in candidates:
			if crowd.size()>=8: break
			var p: Person = agent.node
			for id in router._near_ids(center,9.0):
				if router.graph.get_point_weight_scale(int(id))>=router.ROAD_COST: continue
				var spot: Vector3 = router.graph.get_point_position(int(id))
				var distance := spot.distance_to(center)
				if distance<3.1 or distance>8.5 or streets.point_on_road(spot): continue
				var free := true
				for other in crowd:
					if spot.distance_to(other.target)<1.15: free = false
				if not free: continue
				var eye := spot+Vector3.UP*1.5
				var look := PhysicsRayQueryParameters3D.create(eye,center+Vector3.UP*.6,1|16)
				if not get_world_3d().direct_space_state.intersect_ray(look).is_empty(): continue
				var path := _ped_path(p.global_position,spot)
				if path.is_empty(): continue
				_lock(agent,"curioso")
				crowd.append({"agent":agent,"target":spot,"path":path,"index":0,"time":0.0})
				break
	for i in range(crowd.size()-1,-1,-1):
		var item: Dictionary = crowd[i]
		if not is_instance_valid(item.agent.node):
			crowd.remove_at(i)
			continue
		var p: Person = item.agent.node
		item.time = float(item.time)+delta
		if float(item.time)>32.0:
			_release(item.agent)
			crowd.remove_at(i)
			continue
		if int(item.index)<item.path.size():
			item.index = _advance_actor(p,item.path,int(item.index),delta,1.65)
		else:
			var d := center-p.global_position
			p.rotation.y = lerp_angle(p.rotation.y,atan2(d.x,d.z),minf(1.0,delta*6.0))
			p.animate(delta,false)

# A directed curbside pose, never in a crossing. Used by responders and
# hospital/station arrivals, with the graph's actual one-way restrictions.
func _berths(at: Vector3,radius: float,heading: Vector3 = Vector3.ZERO,parking: bool = true) -> Array:
	var out: Array = []
	for edge in data.roads_near(at,radius):
		if not bool(edge.driveable): continue
		var ea: Vector3 = edge.a
		var eb: Vector3 = edge.b
		for reverse in [false,true]:
			var a := eb if reverse else ea
			var b := ea if reverse else eb
			var first := String(edge.b_id if reverse else edge.a_id)
			var last := String(edge.a_id if reverse else edge.b_id)
			if not data.graph.get(first,[]).has(last): continue
			var d := (b-a).normalized()
			if heading.length_squared()>.1 and d.dot(heading)<.78: continue
			var right := Vector3(-d.z,0,d.x)
			var offset: float = data.lane_distance(edge,WIDTH,parking)
			var center := Geometry3D.get_closest_point_to_segment(_flat(at),a,b)
			var p := center+right*offset
			if parking:
				p = streets.safe_stop_on_edge(a,b,p,LENGTH,WIDTH)
				if not streets.intersection_clear_for_stop(p,LENGTH,WIDTH): continue
			if p.distance_to(_flat(at))>radius: continue
			if not Bypass._on_road(streets,p,d,WIDTH,LENGTH): continue
			out.append({"p":p,"a":a,"b":b,"first":first,"last":last,"d":d,"right":right,"offset":offset,"dist":p.distance_to(_flat(at))})
	out.sort_custom(func(a,b): return float(a.dist)<float(b.dist))
	return out

func _route(start: Dictionary,finish: Dictionary,origin: Vector3) -> Array:
	var raw: Array = []
	var d: Vector3 = start.d
	var end: Vector3 = finish.p
	var a: Vector3 = start.a
	var b: Vector3 = start.b
	var right: Vector3 = start.right
	if start.first==finish.first and start.last==finish.last and (end-origin).dot(d)>1.0:
		raw.append({"p":end,"node":""})
		return raw
	var ids: Array = data._path(String(start.last),String(finish.first),String(start.first),String(start.last))
	if ids.is_empty(): return []
	var first_point := b+right*float(start.offset)
	if (first_point-origin).dot(d)>.3: raw.append({"p":first_point,"node":String(start.last)})
	for i in range(ids.size()-1):
		var p: Vector3 = data.points[ids[i]]
		var q: Vector3 = data.points[ids[i+1]]
		var axis := (q-p).normalized()
		var offset: Vector3 = data.lane_offset(p,q,WIDTH,false)
		if p.distance_to(q)>8.0: raw.append({"p":p+axis*3.0+offset,"node":""})
		raw.append({"p":q+offset,"node":String(ids[i+1])})
	var final_a: Vector3 = finish.a
	var final_d: Vector3 = finish.d
	var final_right: Vector3 = finish.right
	if final_a.distance_to(end)>5.0: raw.append({"p":final_a+final_d*2.0+final_right*float(finish.offset),"node":""})
	raw.append({"p":end,"node":""})
	return game.taxis._smooth_route(raw,origin)

func _clear_pose(body: CharacterBody3D,berth: Dictionary) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(WIDTH,HEIGHT,LENGTH)
	return Bypass._clear(body,berth.p,berth.d,shape)

func _new_trip(body: CharacterBody3D,route: Array) -> Dictionary:
	body.set_meta("traffic_priority",LENGTH)
	body.set_meta("traffic_servicing",false)
	return {"body":body,"route":route,"index":0,"speed":0.0,"cooldown":0.0,"detour":[],"detour_index":0,"resume":0,"traffic_last":body.global_position,"traffic_stall":0.0}

func _drive_trip(trip: Dictionary,delta: float) -> bool:
	var body: CharacterBody3D = trip.body
	var original: Array = trip.route
	var detour: Array = trip.detour
	var active := not detour.is_empty()
	var route: Array = detour if active else original
	var index := int(trip.detour_index) if active else int(trip.index)
	if index>=route.size():
		if active:
			trip.detour = []
			trip.index = int(trip.resume)
			return false
		Bypass._junction_release(trip,body,streets)
		body.set_meta("junction_guard",false)
		body.velocity = Vector3.ZERO
		trip.speed = 0.0
		return true
	var target: Vector3 = route[index].p
	target.y = body.global_position.y
	var diff := target-body.global_position
	var distance := diff.length()
	if distance<.24:
		if active: trip.detour_index = index+1
		else: trip.index = index+1
		return false
	var d := diff.normalized()
	var speed := minf(7.0,maxf(.65,sqrt(8.0*distance)))
	if active: speed = minf(speed,3.0)
	var reach := minf(7.0,distance+.6)
	var free := Bypass.clear_distance(body,d,reach,WIDTH,LENGTH,HEIGHT)
	var gap := .55
	if free<reach-.05: speed = minf(speed,sqrt(10.0*maxf(0.0,free-gap)))
	var stalled := Bypass.stalled(trip,body,delta)
	var limit := Bypass.junction_gate(trip,body,streets,route,index,false,WIDTH,LENGTH,HEIGHT,delta,original if active else [],int(trip.resume))
	speed = Bypass.junction_speed(speed,limit,5.0)
	trip.cooldown = maxf(0.0,float(trip.cooldown)-delta)
	if stalled>1.4 and float(trip.cooldown)<=0.0 and not bool(body.get_meta("junction_guard",false)):
		trip.cooldown = 2.0
		if active:
			trip.detour = []
			trip.index = int(trip.resume)
			return false
		var option := Bypass.recover(body,original,index,streets,WIDTH,LENGTH,data.signal_nodes,HEIGHT)
		if not option.is_empty():
			trip.detour = option.path
			trip.detour_index = 0
			trip.resume = int(option.resume)
			return false
	if not active and Bypass.retreat(trip,body,streets,WIDTH,LENGTH,delta,stalled>3.0 and float(trip.speed)<.12):
		trip.speed = 0.0
		return false
	trip.speed = move_toward(float(trip.speed),speed,delta*5.0)
	var angle := lerp_angle(body.global_rotation.y,atan2(d.x,d.z),minf(1.0,delta*5.0))
	var advance := Bypass.junction_advance(minf(float(trip.speed)*delta,distance),limit)
	if free<reach-.05: advance = minf(advance,maxf(0.0,free-gap))
	if advance>.0001:
		if not Bypass.safe_step(body,d,advance,angle,delta): trip.speed = 0.0
	else:
		if limit<0.0: Bypass.align_if_clear(body,angle)
		body.velocity = Vector3.ZERO
		trip.speed = 0.0
	return false

func _car_trip(body: CharacterBody3D,at: Vector3) -> Dictionary:
	var start: Array = _berths(body.global_position,8.0,body.global_transform.basis.z,false)
	var goals: Array = _berths(at,32.0)
	for goal in goals.slice(0,6):
		if not _clear_pose(body,goal): continue
		for origin in start.slice(0,2):
			var route := _route(origin,goal,body.global_position)
			if not route.is_empty(): return {"trip":_new_trip(body,route),"berth":goal}
	return {}

func _officer(style: int) -> Person:
	var person := Person.new()
	add_child(person)
	person.setup(style)
	person.remove_from_group("social_people")
	person.social_context = "police"
	person._part(person,"box",Vector3(0,1.18,0),Vector3(.44,.55,.28),Color("#3c5a76"))
	person._part(person,"box",Vector3(0,1.77,0),Vector3(.32,.09,.31),Color("#304455"))
	person._part(person,"box",Vector3(0,1.18,.15),Vector3(.07,.08,.02),Color("#d5c68d"))
	return person

func _police_start() -> void:
	var candidates: Array = []
	for stall in market.stalls:
		var root: Node3D = stall.root
		if not bool(stall.open) or bool(stall.get("detained",false)) or bool(stall.get("incident_busy",false)): continue
		if not market.active.is_empty() and stall==market.active: continue
		if root.global_position.distance_to(game.player.global_position)>100.0: continue
		candidates.append(stall)
	candidates.shuffle()
	for stall in candidates:
		var center: Vector3 = stall.root.global_position
		var goals := _berths(center,24.0)
		if goals.is_empty(): continue
		var body: CharacterBody3D = municipal._body(false,0)
		body.name = "Patrulla_PNR"
		game.business._box(body,Vector3(0,1.52,-.2),Vector3(.72,.10,.21),Color("#252e37"))
		var blue: MeshInstance3D = game.business._box(body,Vector3(-.20,1.62,-.2),Vector3(.29,.17,.20),Color("#377cc5"))
		var red: MeshInstance3D = game.business._box(body,Vector3(.20,1.62,-.2),Vector3(.29,.17,.20),Color("#b03c39"))
		for side in [-1.0,1.0]:
			var plaque: Label3D = game.business._label(body,"PNR",Vector3(float(side)*.94,.77,.15),Color.WHITE)
			plaque.rotation.y = float(side)*PI*.5
		var starts: Array = []
		for edge in data.roads_near(center,65.0):
			if not bool(edge.driveable): continue
			var a: Vector3 = edge.a
			var b: Vector3 = edge.b
			for fraction in [.25,.5,.75]:
				var sample := a.lerp(b,float(fraction))
				if sample.distance_to(center)<30.0 or sample.distance_to(center)>70.0: continue
				for start in _berths(sample,8.0):
					start.dist = start.p.distance_to(center)
					starts.append(start)
			if starts.size()>36: break
		var found := false
		for goal in goals.slice(0,3):
			if not _clear_pose(body,goal): continue
			for start in starts:
				if float(start.dist)<26.0 or not _clear_pose(body,start): continue
				var route := _route(start,goal,start.p)
				if route.is_empty(): continue
				body.global_position = start.p+Vector3.UP*.04
				body.rotation.y = atan2(start.d.x,start.d.z)
				scene = {"kind":"police","phase":"approach","trip":_new_trip(body,route),"berth":goal,"stall":stall,"center":center,"time":0.0,"age":0.0,"actors":[],"blue":blue,"red":red,"refuses":rng.randf()<.40}
				stall.incident_busy = true
				stall.person.set_meta("incident_role","intervencion_policial")
				found = true
				break
			if found: break
		if found: return
		body.queue_free()

func _sidewalk(berth: Dictionary,near: Vector3) -> Dictionary:
	var p: Vector3 = berth.p
	var side: Vector3 = berth.right
	var d: Vector3 = berth.d
	for shift in [0.0,1.0,-1.0,2.0,-2.0,3.0,-3.0]:
		for dist in [1.65,2.1,2.65,3.2,4.0,4.8]:
			var at := p+side*float(dist)+d*float(shift)
			if streets.point_on_road(at): continue
			var ground := _foot(at)
			if not ground.is_empty(): return ground
	return {}

func _destination(kind: String) -> Dictionary:
	if world.incident_services.has(kind):
		return {"p":world.incident_services[kind]}
	if kind=="hospital":
		for room in world.public_rooms:
			if String(room.name).begins_with("HOSPITAL"):
				return {"p":room.center+room.basis.z*4.8}
	return {}

func _depart_police() -> void:
	var body: CharacterBody3D = scene.trip.body
	var dest := _destination("police")
	var route: Dictionary = {}
	if not dest.is_empty(): route = _car_trip(body,dest.p)
	if route.is_empty():
		# If this map extract lacks a station, drive to a verified road
		# berth away from the event, rather than disappear in the street.
		var origin: Vector3 = body.global_position
		for edge in data.roads_near(origin,120.0):
			var p: Vector3 = (edge.a+edge.b)*.5
			if p.distance_to(origin)<55.0: continue
			route = _car_trip(body,p)
			if not route.is_empty(): break
	if route.is_empty():
		scene.phase = "depart_retry"
		scene.time = 0.0
		return
	scene.trip = route.trip
	scene.phase = "depart"
	scene.time = 0.0
	_crowd_clear()

func _police_tick(delta: float) -> void:
	var stall: Dictionary = scene.stall
	var body: CharacterBody3D = scene.trip.body
	var seller: Person = stall.person
	var phase := String(scene.phase)
	var elapsed := float(scene.time)
	var flash := fmod(float(scene.age),.64)<.32
	scene.blue.visible = flash
	scene.red.visible = not flash
	if phase=="approach":
		if not _drive_trip(scene.trip,delta): return
		var ground := _sidewalk(scene.berth,scene.center)
		if ground.is_empty():
			_finish_police(false)
			return
		var spawn: Vector3 = ground.p
		var officers: Array = []
		for i in range(2):
			var officer := _officer(900+i)
			officer.global_position = spawn+Vector3.UP*.01
			var target: Vector3 = seller.global_position+stall.root.global_transform.basis.x*(.65 if i==0 else -.65)-stall.root.global_transform.basis.z*.85
			var path := _ped_path(officer.global_position,target)
			if path.is_empty():
				officer.queue_free()
				continue
			officers.append({"node":officer,"path":path,"index":0,"spawn":spawn})
		if officers.is_empty():
			_finish_police(false)
			return
		scene.actors = officers
		scene.phase = "walk"
		scene.time = 0.0
		body.set_meta("traffic_servicing",true)
	elif phase=="walk":
		var ready := true
		for actor in scene.actors:
			actor.index = _advance_actor(actor.node,actor.path,int(actor.index),delta)
			if int(actor.index)<actor.path.size(): ready = false
		if ready:
			_say(scene.actors[0].node,["Oye, ¿y el dinero de hoy?","Socio, tienes que pagar.","Vamos, dame lo tuyo."].pick_random())
			scene.phase = "ask"
			scene.time = 0.0
		elif elapsed>15.0: _finish_police(false)
	elif phase=="ask" and elapsed>3.0:
		if bool(scene.refuses):
			_say(seller,["No tengo dinero para darte.","No, yo no voy a pagar.","Eso es lo que tengo para vivir."].pick_random())
			scene.phase = "confiscate"
		else:
			_say(seller,["Toma, pero déjame trabajar.","Está bien, aquí tienes.","Asere, no tengo mucho."].pick_random())
			var wallets: Dictionary = market.state.get("vendor_cash",{})
			var id := String(stall.id)
			var payment := mini(int(wallets.get(id,600)),rng.randi_range(80,180))
			wallets[id] = int(wallets.get(id,600))-payment
			if payment>0:
				var officer: Person = scene.actors[0].node
				var cash: MeshInstance3D = game.business._box(seller,Vector3(0,1.02,.33),Vector3(.10,.025,.065),Color("#a5b98b"))
				seller.arms[0].rotation.x = -1.0
				officer.arms[1].rotation.x = -1.0
				get_tree().create_timer(1.0).timeout.connect(func():
					if is_instance_valid(cash): cash.queue_free())
			market.state.vendor_cash = wallets
			game.business.ledger.save_game()
			scene.phase = "payment"
		scene.time = 0.0
	elif phase=="payment" and elapsed>1.5:
		seller.animate(.2,false)
		scene.phase = "return"
		scene.time = 0.0
	elif phase=="confiscate":
		# Each displayed merchandise node is lifted, carried, then loaded.
		if not scene.has("load_queue"):
			var queue: Array = []
			for item in stall.items:
				if int(stall.stock.get(item.key,0))>0: queue.append(item)
			scene.load_queue = queue
			scene.load_item = {}
			scene.load_phase = "take"
		var officer: Dictionary = scene.actors[0]
		var carrier: Person = officer.node
		if scene.load_phase=="take":
			if scene.load_queue.is_empty():
				scene.phase = "escort"
				scene.time = 0.0
				return
			var item: Dictionary = scene.load_queue.pop_front()
			var model: Node3D = item.node
			var path := _ped_path(carrier.global_position,officer.spawn)
			if path.is_empty():
				_finish_police(false)
				return
			item["display_position"] = model.position
			model.reparent(carrier,true)
			model.position = Vector3(0,.85,.35)
			carrier.carried = model
			carrier.arms[0].rotation.x = -.85
			carrier.arms[1].rotation.x = -.85
			scene.load_item = item
			scene.load_path = path
			scene.load_index = 0
			scene.load_phase = "carry"
		elif scene.load_phase=="carry":
			scene.load_index = _advance_actor(carrier,scene.load_path,int(scene.load_index),delta)
			if int(scene.load_index)>=scene.load_path.size():
				var item: Dictionary = scene.load_item
				var model: Node3D = item.node
				carrier.carried = null
				model.reparent(body,true)
				model.position = Vector3(0,.78,-1.40)
				model.hide()
				if not scene.has("loaded_items"): scene.loaded_items = []
				scene.loaded_items.append(item)
				var cargo: Array = body.get_meta("seized_goods",[])
				cargo.append({"product":String(item.key),"quantity":int(stall.stock[item.key])})
				body.set_meta("seized_goods",cargo)
				stall.stock[item.key] = 0
				scene.load_item = {}
				scene.load_path = _ped_path(carrier.global_position,seller.global_position-stall.root.global_transform.basis.z*.9)
				scene.load_index = 0
				scene.load_phase = "back"
		else:
			if scene.load_path.is_empty():
				_finish_police(false)
				return
			scene.load_index = _advance_actor(carrier,scene.load_path,int(scene.load_index),delta)
			if int(scene.load_index)>=scene.load_path.size(): scene.load_phase = "take"
	elif phase=="escort":
		if not scene.has("escort_path"):
			var target: Vector3 = scene.actors[0].spawn
			var path := _ped_path(seller.global_position,target)
			if path.is_empty():
				_finish_police(false)
				return
			scene.escort_path = path
			scene.escort_index = 0
			seller.remove_meta("conversation_until")
		scene.escort_index = _advance_actor(seller,scene.escort_path,int(scene.escort_index),delta,1.3)
		if int(scene.escort_index)>=scene.escort_path.size():
			seller.hide()
			body.set_meta("detained_vendor",String(stall.id))
			seller.reparent(body,true)
			seller.position = Vector3(0,.65,-.55)
			stall.detained = true
			stall.open = false
			game.business.ledger.save_game()
			scene.phase = "return"
			scene.time = 0.0
	elif phase=="return":
		var ready := true
		for actor in scene.actors:
			if not actor.has("return_path"):
				actor.return_path = _ped_path(actor.node.global_position,actor.spawn)
				actor.return_index = 0
			if actor.return_path.is_empty(): continue
			actor.return_index = _advance_actor(actor.node,actor.return_path,int(actor.return_index),delta)
			if int(actor.return_index)<actor.return_path.size(): ready = false
		if ready or elapsed>16.0:
			for actor in scene.actors: actor.node.queue_free()
			scene.actors = []
			if bool(stall.get("detained",false)): stall.root.hide()
			body.set_meta("traffic_servicing",false)
			_depart_police()
	elif phase=="depart_retry" and elapsed>3.0:
		_depart_police()
	elif phase=="depart":
		if _drive_trip(scene.trip,delta):
			_finish_police(true)

func _finish_police(arrived: bool) -> void:
	if scene.is_empty(): return
	var stall: Dictionary = scene.stall
	stall.incident_busy = false
	var seller: Person = stall.person
	seller.remove_meta("incident_role")
	if seller.get_parent()!=stall.root: seller.reparent(stall.root,true)
	seller.position = Vector3(0,0,1.08)
	seller.rotation = Vector3(0,PI,0)
	seller.visible = not bool(stall.get("detained",false))
	for item in scene.get("loaded_items",[]):
		var model: Node3D = item.node
		model.reparent(stall.root,true)
		model.position = item.display_position
		model.hide()
	if scene.has("load_item") and not scene.load_item.is_empty():
		var item: Dictionary = scene.load_item
		var node: Node3D = item.node
		node.reparent(stall.root,true)
		node.position = item.get("display_position",Vector3(0,float(stall.surface)+.1,0))
		node.visible = int(stall.stock.get(item.key,0))>0
	for actor in scene.actors:
		if is_instance_valid(actor.node): actor.node.queue_free()
	game.business.ledger.save_game()
	var body: CharacterBody3D = scene.trip.body
	Bypass._junction_release(scene.trip,body,streets)
	# Remove a completed patrol only at its destination. An interrupted
	# patrol remains a normal moving car if it can rejoin traffic.
	if arrived:
		body.queue_free()
	else:
		var route: Array = scene.trip.route
		if route.size()>2:
			municipal.vehicles.append({"body":body,"route":route,"index":clampi(int(scene.trip.index),0,route.size()-1),"speed":0.0,"truck":false,"crew":[],"site":{},"blocked":0.0,"cooldown":0.0,"detour":[],"detour_index":0,"resume":0})
		else: body.queue_free()
	_crowd_clear()
	scene = {}
	police_wait = rng.randf_range(80.0,150.0)

# Non-graphic collisions are based on the player's actual displacement,
# never on aiming or proximity alone. A wall between car and person
# prevents a hit; stationary vehicles cannot repeatedly strike someone.
func vehicle_motion(body: CharacterBody3D,before: Transform3D,speed: float,width: float,length: float) -> void:
	if absf(speed)<.45 or injured.size()>=8: return
	var after := body.global_transform
	var end := after.origin
	var start := before.origin
	if _flat(end-start).length()<.002 or end.distance_to(start)>3.0: return
	var center := (start+end)*.5
	var reach := Vector2(width,length).length()*.5+1.0
	for node in get_tree().get_nodes_in_group("social_people"):
		if not node is Node3D: continue
		var person := node as Node3D
		if not person.is_visible_in_tree() or person.has_meta("incident_role"): continue
		var p := person.global_position
		if p.distance_squared_to(center)>reach*reach or absf(p.y-end.y)>.8: continue
		if Time.get_ticks_msec()<int(person.get_meta("impact_immunity",0)): continue
		var contact := _impact_contact(before,after,p,width,length)
		if contact.is_empty(): continue
		# Test only the short gap between the actual vehicle envelope and
		# the person, not a long ray through the van and nearby signposts.
		var edge: Vector3 = contact.surface
		var target := p+Vector3.UP*.65
		if edge.distance_to(target)>.30:
			var ray := PhysicsRayQueryParameters3D.create(edge,target,1|4|16)
			ray.exclude = [body.get_rid(),game.player.get_rid()]
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var agent := _impact_agent(person)
		if agent.is_empty(): continue
		_lock(agent,"herido")
		var severe := absf(speed)>=7.5
		var old := person.global_transform
		if person is Person: (person as Person).animate(.2,false)
		person.rotation.x = -PI*.5
		person.global_position.y = old.origin.y+.13
		injured.append({"agent":agent,"severe":severe,"old":old,"time":0.0,"retry":0.0})
		print("Accidente: ",person.name," velocidad=",roundi(absf(speed)*3.6)," km/h grave=",severe)
		if injured.size()>=8: break

func _injury_tick(delta: float) -> void:
	for i in range(injured.size()-1,-1,-1):
		var victim: Dictionary = injured[i]
		if not is_instance_valid(victim.agent.node):
			injured.remove_at(i)
			continue
		if bool(victim.severe): continue
		victim.time = float(victim.time)+delta
		if float(victim.time)<5.0: continue
		var p: Node3D = victim.agent.node
		var old: Transform3D = victim.old
		if _foot(old.origin).is_empty():
			var safe: Dictionary = {}
			for distance in [.7,1.2,1.8,2.5]:
				for n in range(8):
					var angle := float(n)*TAU/8.0
					var candidate := old.origin+Vector3(cos(angle),0,sin(angle))*float(distance)
					safe = _foot(candidate)
					if not safe.is_empty(): break
				if not safe.is_empty(): break
			if safe.is_empty(): continue
			old.origin = safe.p
		p.global_transform = old
		p.set_meta("impact_immunity",Time.get_ticks_msec()+2500)
		_release(victim.agent)
		injured.remove_at(i)

func _rescue_start(victim: Dictionary) -> void:
	var dest := _destination("hospital")
	if dest.is_empty(): return
	var person: Node3D = victim.agent.node
	var center := person.global_position
	var candidates: Array = []
	for car in municipal.vehicles:
		if bool(car.truck) or bool(car.get("incident_hold",false)): continue
		var body: CharacterBody3D = car.body
		if not is_instance_valid(body) or String(body.name).begins_with("Patrulla") or body.global_position.distance_to(center)>125.0: continue
		if not streets.intersection_clear_for_stop(body.global_position,LENGTH,WIDTH): continue
		candidates.append(car)
	candidates.shuffle()
	for car in candidates.slice(0,5):
		var body: CharacterBody3D = car.body
		var approach := _car_trip(body,center)
		if approach.is_empty(): continue
		var hospital: Array = _berths(dest.p,35.0)
		var outbound: Array = []
		var end: Dictionary = {}
		for berth in hospital.slice(0,5):
			var route := _route(approach.berth,berth,approach.berth.p)
			if not route.is_empty():
				outbound = route
				end = berth
				break
		if outbound.is_empty(): continue
		Bypass._junction_release(car,body,streets)
		car.incident_hold = true
		scene = {"kind":"rescue","phase":"approach","trip":approach.trip,"berth":approach.berth,"hospital_route":outbound,"hospital_berth":end,"car":car,"victim":victim,"center":center,"time":0.0,"age":0.0,"actors":[]}
		return

func _rescue_tick(delta: float) -> void:
	var victim: Dictionary = scene.victim
	var person: Node3D = victim.agent.node
	var body: CharacterBody3D = scene.trip.body
	var phase := String(scene.phase)
	if phase=="approach":
		if not _drive_trip(scene.trip,delta): return
		var ground := _sidewalk(scene.berth,scene.center)
		if ground.is_empty():
			_end_rescue(false)
			return
		var spawn: Vector3 = ground.p
		var helper: Dictionary = {}
		var victim_point: Vector3 = victim.old.origin
		for agent in _walkers(victim_point,22.0):
			var p: Person = agent.node
			var path := _ped_path(p.global_position,victim_point)
			if path.is_empty(): continue
			helper = {"agent":agent,"node":p,"path":path,"index":0}
			break
		if helper.is_empty():
			_end_rescue(false)
			return
		var driver := Person.new()
		add_child(driver)
		driver.setup(rng.randi_range(1200,1290))
		driver.remove_from_group("social_people")
		driver.global_position = spawn
		var path := _ped_path(spawn,victim_point)
		if path.is_empty():
			driver.queue_free()
			_end_rescue(false)
			return
		_lock(helper.agent,"auxilio")
		scene.actors = [{"node":driver,"path":path,"index":0},helper]
		scene.pickup_point = spawn
		scene.phase = "help"
		scene.time = 0.0
		body.set_meta("traffic_servicing",true)
		_say(driver,"¡Ayúdame a llevarlo al hospital!")
	elif phase=="help":
		var ready := true
		for actor in scene.actors:
			actor.index = _advance_actor(actor.node,actor.path,int(actor.index),delta,1.6)
			if int(actor.index)<actor.path.size(): ready = false
		if not ready: return
		var path := _ped_path(victim.old.origin,scene.pickup_point)
		if path.is_empty():
			_end_rescue(false)
			return
		scene.carry_path = path
		scene.carry_index = 0
		scene.phase = "carry"
		scene.time = 0.0
	elif phase=="carry":
		var driver: Person = scene.actors[0].node
		var helper: Person = scene.actors[1].node
		var path: PackedVector3Array = scene.carry_path
		scene.carry_index = _advance_actor(driver,path,int(scene.carry_index),delta,.95)
		var follow := driver.global_position
		var d := follow-helper.global_position
		if d.length()>.65 and world.pedestrian_segment_clear(helper.global_position,helper.global_position.move_toward(follow,delta*1.15)):
			helper.walk_to(follow,delta,1.15)
		person.global_position = (driver.global_position+helper.global_position)*.5+Vector3.UP*.70
		for actor in scene.actors:
			actor.node.arms[0].rotation.x = -1.0
			actor.node.arms[1].rotation.x = -1.0
		if int(scene.carry_index)>=path.size() and helper.global_position.distance_to(driver.global_position)<1.1:
			person.hide()
			person.reparent(body,true)
			person.position = Vector3(0,.68,-.48)
			_release(scene.actors[1].agent)
			driver.queue_free()
			scene.actors = []
			scene.trip = _new_trip(body,scene.hospital_route)
			scene.phase = "hospital"
			scene.time = 0.0
			_crowd_clear()
	elif phase=="hospital":
		if _drive_trip(scene.trip,delta):
			var ground := _sidewalk(scene.hospital_berth,scene.hospital_berth.p)
			if ground.is_empty(): return
			# Arrival at the existing hospital; recovery/treatment itself
			# remains a future health-system feature.
			person.reparent(_impact_parent(victim.agent),true)
			person.global_position = ground.p
			person.rotation.x = 0.0
			person.show()
			_say(person,"Gracias por traerme al hospital.")
			_end_rescue(true)

func _end_rescue(delivered: bool) -> void:
	var car: Dictionary = scene.car
	var victim: Dictionary = scene.victim
	var person: Node3D = victim.agent.node
	for actor in scene.actors:
		if actor.has("agent"): _release(actor.agent)
		elif is_instance_valid(actor.node): actor.node.queue_free()
	var body: CharacterBody3D = car.body
	Bypass._junction_release(scene.trip,body,streets)
	body.set_meta("traffic_servicing",false)
	body.set_meta("junction_guard",false)
	car.detour = []
	car.speed = 0.0
	_rejoin_car(car)
	if delivered:
		person.set_meta("impact_immunity",Time.get_ticks_msec()+5000)
		victim.agent.delivered = true
		_release(victim.agent)
		injured.erase(victim)
	else:
		var base: Vector3 = person.global_position
		var parent := _impact_parent(victim.agent)
		if person.get_parent()!=parent: person.reparent(parent,true)
		if not person.visible:
			var nearest := _berths(body.global_position,18.0,body.global_transform.basis.z)
			for berth in nearest:
				var ground := _sidewalk(berth,body.global_position)
				if not ground.is_empty():
					base = ground.p
					break
		else:
			base.y = float(victim.old.origin.y)
		var old: Transform3D = victim.old
		old.origin = base
		victim.old = old
		person.global_transform = old
		person.rotation.x = -PI*.5
		person.global_position.y += .13
		person.show()
		victim.retry = 8.0
	_crowd_clear()
	scene = {}

func _rejoin_car(car: Dictionary) -> void:
	var body: CharacterBody3D = car.body
	var original: Array = car.route
	var candidates: Array = []
	for i in range(original.size()):
		var p: Vector3 = original[i].p
		if not streets.intersection_clear_for_stop(p,LENGTH,WIDTH): continue
		candidates.append({"index":i,"p":p,"distance":p.distance_squared_to(body.global_position)})
	candidates.sort_custom(func(a,b): return float(a.distance)<float(b.distance))
	for candidate in candidates.slice(0,8):
		var route := _car_trip(body,candidate.p)
		if route.is_empty(): continue
		var berth_point: Vector3 = route.berth.p
		if berth_point.distance_to(candidate.p)>6.0: continue
		returning.append({"car":car,"trip":route.trip,"index":int(candidate.index),"time":0.0})
		return
	car.incident_hold = false
	if not candidates.is_empty(): car.index = int(candidates[0].index)

func _tick_returning(delta: float) -> void:
	for i in range(returning.size()-1,-1,-1):
		var entry: Dictionary = returning[i]
		var car: Dictionary = entry.car
		entry.time = float(entry.time)+delta
		var arrived := _drive_trip(entry.trip,delta)
		if not arrived and float(entry.time)<90.0: continue
		Bypass._junction_release(entry.trip,car.body,streets)
		car.body.set_meta("junction_guard",false)
		car.incident_hold = false
		car.index = int(entry.index)
		car.speed = 0.0
		returning.remove_at(i)

func tick(delta: float) -> void:
	_tick_returning(delta)
	_injury_tick(delta)
	for victim in injured:
		victim.retry = maxf(0.0,float(victim.retry)-delta)
	if not router.initialized: return
	if scene.is_empty():
		for victim in injured:
			if bool(victim.severe) and float(victim.retry)<=0.0:
				victim.retry = 6.0
				_rescue_start(victim)
				if not scene.is_empty(): break
		if scene.is_empty() and not injured.is_empty():
			var victim: Dictionary = injured[0]
			var center: Vector3 = victim.old.origin
			_crowd_tick(center,delta)
			return
		if scene.is_empty():
			if not crowd.is_empty(): _crowd_clear()
			police_wait -= delta
			if police_wait<=0.0:
				police_wait = 12.0
				_police_start()
		if scene.is_empty(): return
	scene.time = float(scene.time)+delta
	scene.age = float(scene.age)+delta
	var phase := String(scene.phase)
	if phase not in ["depart","depart_retry","hospital"] and (phase!="approach" or String(scene.kind)=="rescue"):
		_crowd_tick(scene.center,delta)
	if String(scene.kind)=="police":
		_police_tick(delta)
		if not scene.is_empty() and float(scene.age)>155.0: _finish_police(false)
	else:
		_rescue_tick(delta)
		if not scene.is_empty() and float(scene.age)>150.0: _end_rescue(false)
