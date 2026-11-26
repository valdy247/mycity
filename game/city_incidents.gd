extends Node3D
# One active scene at a time. Existing pedestrian and vehicle controllers
# keep ownership of ordinary routines; only participants are reserved.
const Person = preload("res://street_person.gd")
const Bypass = preload("res://traffic_bypass.gd")
const WIDTH := 1.83
const LENGTH := 4.25
const HEIGHT := 1.65
const CASUALTY_LAYER := 32
var game
var world
var router
var market
var municipal
var streets
var data
var scene: Dictionary = {}
var injured: Array = []
# Keep pickups independent of hospital journeys, with a strict budget.
const MAX_MEDICAL_TRANSFERS := 2
var medical_transfers: Array = []
var dispatch_wait := 0.0
var returning: Array = []
var crowd: Array = []
var police_wait := 35.0
var crowd_clock := 0.0
var crowd_center := Vector3.INF
const RESCUE_WALK_RANGE := 85.0
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
	elif source=="rescue_volunteer":
		p.queue_free()
	elif source=="business":
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
		elif not bool(stall.get("detained",false)):
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
	var normal: PackedVector3Array = router.route_between(a,b)
	if not normal.is_empty(): return normal
	var starts: Array = router._near_ids(a,12.0)
	var ends: Array = router._near_ids(b,12.0)
	starts.sort_custom(func(x,y): return a.distance_squared_to(router.graph.get_point_position(int(x)))<a.distance_squared_to(router.graph.get_point_position(int(y))))
	ends.sort_custom(func(x,y): return b.distance_squared_to(router.graph.get_point_position(int(x)))<b.distance_squared_to(router.graph.get_point_position(int(y))))
	var valid_starts: Array = []
	var valid_ends: Array = []
	for id in starts.slice(0,18):
		if world.pedestrian_segment_clear(a,router.graph.get_point_position(int(id))): valid_starts.append(id)
		if valid_starts.size()>=3: break
	for id in ends.slice(0,18):
		if world.pedestrian_segment_clear(router.graph.get_point_position(int(id)),b): valid_ends.append(id)
		if valid_ends.size()>=3: break
	for first in valid_starts:
		for last in valid_ends:
			var path: PackedVector3Array = router.graph.get_point_path(int(first),int(last))
			if path.is_empty(): continue
			path.append(b)
			return path
	return PackedVector3Array()

func _advance_actor(person: Person,path: PackedVector3Array,index: int,dt: float,speed: float = 1.5) -> int:
	if index>=path.size(): return index
	var target := path[index]
	var step := person.global_position.move_toward(target,speed*dt)
	if not world.pedestrian_segment_clear(person.global_position,step): return index
	if String(person.get_meta("incident_role","")) in ["curioso","primeros_auxilios","auxilio"] and String(scene.get("phase","")) not in ["position_carry","lift","carry","load"]:
		if not world.pedestrian_space_clear(person,step,.60): return index
	if person.walk_to(target,dt,speed): return index+1
	return index

func _crowd_clear() -> void:
	for item in crowd: _release(item.agent)
	crowd.clear()

func _crowd_tick(center: Vector3,delta: float) -> void:
	if not crowd_center.is_finite() or crowd_center.distance_to(center)>12.0:
		_crowd_clear()
		crowd_center = center
		crowd_clock = 1.0
	crowd_clock += delta
	var crowd_limit := 3 if not injured.is_empty() else 8
	if crowd_clock>=.8 and crowd.size()<crowd_limit:
		crowd_clock = 0.0
		var candidates: Array = _walkers(center,42.0)
		var spots := _witness_spots(center)
		_watch_nearby(center)
		# Other visible citizens, including passengers waiting at stops,
		# may become witnesses. Do not steal working vendors or residents.
		for node in get_tree().get_nodes_in_group("social_people"):
			if not node is Person or not node.is_visible_in_tree() or node.has_meta("incident_role"): continue
			if node.global_position.distance_to(center)>30.0: continue
			if String(node.social_context)!="bus_wait": continue
			var at: Vector3 = node.global_position
			if at.distance_to(center)<=8.0 and at.distance_to(center)>=1.8 and not streets.point_on_road(at) and _witness_slot_free(at,node) and crowd.size()<4:
				var witness := _impact_agent(node)
				if not witness.is_empty():
					_lock(witness,"curioso")
					crowd.append({"agent":witness,"target":at,"path":PackedVector3Array(),"index":0,"time":0.0,"last":at,"stuck":0.0})
					continue
			candidates.append({"node":node,"waiting_witness":true})
		for agent in candidates:
			if crowd.size()>=crowd_limit: break
			var p: Person = agent.node
			if p.has_meta("incident_role"): continue
			for spot in spots:
				if not _witness_slot_free(spot): continue
				var path := _ped_path(p.global_position,spot)
				if path.is_empty(): continue
				if bool(agent.get("waiting_witness",false)):
					agent = _impact_agent(p)
					if agent.is_empty(): break
				_lock(agent,"curioso")
				crowd.append({"agent":agent,"target":spot,"path":path,"index":0,"time":0.0,"last":p.global_position,"stuck":0.0})
				break
		# Low population at night must not make every incident deserted.
		# At most two additional nearby residents per update, at valid
		# graph nodes outside the gathering, then walk to it normally.
		if injured.is_empty() and crowd.size()<4:
			_neighborhood_witness(center,spots)
	for i in range(crowd.size()-1,-1,-1):
		var item: Dictionary = crowd[i]
		if not is_instance_valid(item.agent.node):
			crowd.remove_at(i)
			continue
		var p: Person = item.agent.node
		item.time = float(item.time)+delta
		if int(item.index)<item.path.size():
			item.index = _advance_actor(p,item.path,int(item.index),delta,2.0)
			if p.global_position.distance_to(item.last)<.015:
				item.stuck = float(item.stuck)+delta
			else:
				item.stuck = 0.0
				item.last = p.global_position
			if float(item.stuck)>4.0:
				_release(item.agent)
				crowd.remove_at(i)
		else:
			var d := center-p.global_position
			p.rotation.y = lerp_angle(p.rotation.y,atan2(d.x,d.z),minf(1.0,delta*6.0))
			p.animate(delta,false)

func _watch_nearby(center: Vector3) -> void:
	for agent in _walkers(center,8.0):
		if crowd.size()>=3: break
		var p: Person = agent.node
		var at := p.global_position
		if streets.point_on_road(at) or at.distance_to(center)<1.8 or not _witness_slot_free(at,p): continue
		_lock(agent,"curioso")
		crowd.append({"agent":agent,"target":at,"path":PackedVector3Array(),"index":0,"time":0.0,"last":at,"stuck":0.0})

func _witness_slot_free(spot: Vector3,actor: Node3D = null) -> bool:
	if not world.pedestrian_space_clear(actor,spot,.85,false): return false
	for other in crowd:
		if spot.distance_to(other.target)<1.05: return false
	return true

func _witness_spots(center: Vector3) -> Array:
	var spots: Array = []
	for id in router._near_ids(center,15.0):
		if router.graph.get_point_weight_scale(int(id))>=router.ROAD_COST: continue
		var p: Vector3 = router.graph.get_point_position(int(id))
		var distance := p.distance_to(center)
		if distance<2.6 or distance>14.0 or streets.point_on_road(p): continue
		if _foot(p).is_empty(): continue
		# Aim at the general scene, not exactly at a body which might
		# be obscured by a lamppost or car.
		var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*1.5,center+Vector3.UP*1.15,1|16)
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		spots.append(p)
	if spots.size()<4:
		for radius in [3.0,4.5,6.0,8.0,11.0]:
			for i in range(12):
				var angle := float(i)*TAU/12.0
				var p := center+Vector3(cos(angle),0,sin(angle))*float(radius)
				if streets.point_on_road(p): continue
				var ground := _foot(p)
				if ground.is_empty(): continue
				var q: Vector3 = ground.p
				var ray := PhysicsRayQueryParameters3D.create(q+Vector3.UP*1.5,center+Vector3.UP*1.15,1|16)
				if get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): spots.append(q)
	spots.sort_custom(func(a,b): return center.distance_squared_to(a)<center.distance_squared_to(b))
	return spots

func _neighborhood_witness(center: Vector3,spots: Array) -> void:
	if spots.is_empty(): return
	var camera := get_viewport().get_camera_3d()
	var origins: Array = router._near_ids(center,36.0)
	origins.shuffle()
	for id in origins.slice(0,80):
		if router.graph.get_point_weight_scale(int(id))>=router.ROAD_COST: continue
		var p: Vector3 = router.graph.get_point_position(int(id))
		if p.distance_to(center)<15.0 or streets.point_on_road(p): continue
		if camera!=null and camera.is_position_in_frustum(p+Vector3.UP) and p.distance_to(camera.global_position)<26.0: continue
		if _foot(p).is_empty() or not world.pedestrian_space_clear(null,p,1.0,false): continue
		var free := true
		for agent in router.walkers:
			if p.distance_to(agent.node.global_position)<1.8: free = false
		if not free: continue
		for spot in spots:
			if not _witness_slot_free(spot): continue
			var path := _ped_path(p,spot)
			if path.is_empty(): continue
			var person := Person.new()
			router.add_child(person)
			person.setup(rng.randi_range(2000,9000))
			person.global_position = p
			var agent := {"node":person,"path":PackedVector3Array(),"index":0,"destination":{},"pause":0.0,"speed":1.35}
			router.walkers.append(agent)
			_lock(agent,"curioso")
			crowd.append({"agent":agent,"target":spot,"path":path,"index":0,"time":0.0,"last":p,"stuck":0.0})
			return

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
	if ids.is_empty(): ids = data._path(String(start.last),String(finish.first),"","")
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

func _car_trip(body: CharacterBody3D,at: Vector3,radius: float = 38.0,exclude: Dictionary = {}) -> Dictionary:
	var start: Array = _berths(body.global_position,11.0,body.global_transform.basis.z,false)
	var goals: Array = _berths(at,radius)
	if radius>=RESCUE_WALK_RANGE:
		# A single closest projection is insufficient when another car
		# occupies it. Try additional positions along the same block.
		var extra: Array = []
		for goal in goals.slice(0,12):
			var p: Vector3 = goal.p
			var d: Vector3 = goal.d
			for distance in [-16.0,16.0,-8.0,8.0]:
				var candidate: Dictionary = goal.duplicate()
				var q: Vector3 = streets.safe_stop_on_edge(goal.a,goal.b,p+d*float(distance),LENGTH,WIDTH)
				if q.distance_to(at)>radius or not streets.intersection_clear_for_stop(q,LENGTH,WIDTH): continue
				if not Bypass._on_road(streets,q,d,WIDTH,LENGTH): continue
				candidate.p = q
				candidate.dist = q.distance_to(at)
				extra.append(candidate)
		goals.append_array(extra)
		goals.sort_custom(func(a,b): return float(a.dist)<float(b.dist))
	for goal in goals.slice(0,36):
		if not exclude.is_empty() and _flat_distance_to_berth(goal,exclude)<4.0: continue
		if not _clear_pose(body,goal): continue
		if radius>=RESCUE_WALK_RANGE:
			if _rescue_foot_access(goal,at).is_empty(): continue
		for origin in start.slice(0,4):
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
		if world.incident_services.has("clinic"): return {"p":world.incident_services.clinic}
		for room in world.public_rooms:
			if String(room.name).begins_with("HOSPITAL"):
				return {"p":room.center+room.basis.z*4.8}
		for fp in world.original_footprints.values():
			var tags: Dictionary = fp.tags
			if String(tags.get("amenity",""))=="hospital" and not _berths(fp.center,45.0).is_empty(): return {"p":fp.center}
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
# Reserve a distinct ground footprint for each fallen person. A prone
# model occupies a full body length, not just its original standing point.
func _casualty_slot_free(at: Vector3,axis: Vector3,length: float,person: Node3D = null) -> bool:
	var start := _flat(at)
	var finish := start+axis*length
	for victim in injured:
		var other: Node3D = victim.agent.node
		if not is_instance_valid(other) or other==person or not other.is_visible_in_tree(): continue
		var other_start := _flat(other.global_position)
		var other_end := other_start+_flat(other.global_transform.basis.y)*1.85
		var nearest := Geometry3D.get_closest_points_between_segments(start,finish,other_start,other_end)
		if nearest[0].distance_squared_to(nearest[1])<.64: return false
	return true

# Cars see the whole prone body, including feet and head. Pedestrian
# navigation does not use this layer, so medics can still approach.
func _casualty_shape(pose: Transform3D) -> BoxShape3D:
	var shape := BoxShape3D.new()
	shape.size = Vector3(.86,.85,1.85*pose.basis.get_scale().y+.25)
	return shape

func _casualty_transform(pose: Transform3D) -> Transform3D:
	var axis := -_flat(pose.basis.z).normalized()
	if axis.length_squared()<.01: axis = Vector3.FORWARD
	return Transform3D(Basis(Vector3.UP,atan2(axis.x,axis.z)),pose.origin+axis*(.925*pose.basis.get_scale().y)+Vector3.UP*.45)

func _casualty_vehicle_clear(pose: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _casualty_shape(pose)
	query.transform = _casualty_transform(pose)
	query.collision_mask = 1|4|8|16|CASUALTY_LAYER
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

# A wall or portal column may touch the protective envelope without
# obstructing traffic. Only a live vehicle or another casualty prevents
# inserting the guard. Layer 2 (road ground) was already excluded.
func _casualty_guard_clear(pose: Transform3D) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _casualty_shape(pose)
	query.transform = _casualty_transform(pose)
	query.collision_mask = 1|4|8|CASUALTY_LAYER
	for hit in get_world_3d().direct_space_state.intersect_shape(query,32):
		var collider = hit.collider
		if collider is CharacterBody3D: return false
		if collider is CollisionObject3D and (collider.collision_layer & CASUALTY_LAYER)!=0: return false
	return true

func _remove_casualty_guard(victim: Dictionary) -> void:
	var guard = victim.get("traffic_guard")
	if is_instance_valid(guard):
		guard.collision_layer = 0
		guard.queue_free()
	victim.erase("traffic_guard")

func _protect_casualty(victim: Dictionary) -> void:
	if is_instance_valid(victim.get("traffic_guard")): return
	var person: Node3D = victim.agent.node
	if not is_instance_valid(person) or not person.is_visible_in_tree(): return
	var old: Transform3D = victim.old
	if not _casualty_guard_clear(old):
		# If the impact left the actor inside a bumper, resolve the initial
		# fall to nearby free ground before inserting a collision body.
		if Time.get_ticks_msec()<int(victim.get("guard_retry",0)): return
		victim.guard_retry = Time.get_ticks_msec()+1500
		# Never relocate a victim after the rescue crew has committed to a position.
		if scene.get("victim",{})==victim or victim.has("first_aid"): return
		old = _casualty_pose(person,old)
		if not _casualty_guard_clear(old):
			_rescue_log(victim,"espacio del herido ocupado; esperando una posición segura.")
			return
		victim.old = old
		person.global_transform = old
		person.rotation.x = -PI*.5
		person.global_position.y += .13
	var guard := StaticBody3D.new()
	guard.name = "Herido_Proteccion"
	guard.collision_layer = CASUALTY_LAYER
	guard.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.shape = _casualty_shape(old)
	guard.add_child(collision)
	add_child(guard)
	guard.global_transform = _casualty_transform(old)
	victim.traffic_guard = guard

func _casualty_pose(person: Node3D,old: Transform3D) -> Transform3D:
	var axis := -_flat(old.basis.z).normalized()
	var length := 1.85*old.basis.get_scale().y
	if _casualty_slot_free(old.origin,axis,length,person) and _casualty_guard_clear(old): return old
	# Try nearby distinct poses, using ground and geometry checks.
	for radius in [.75,1.2,1.8,2.5,3.2,4.0,5.0,6.5]:
		for i in range(12):
			var angle := float(i)*TAU/12.0
			var point := old.origin+Vector3(cos(angle),0,sin(angle))*float(radius)
			var ground := _foot(point)
			if ground.is_empty(): continue
			var at: Vector3 = ground.p
			if not _casualty_slot_free(at,axis,length,person): continue
			var candidate := old
			candidate.origin = at
			if not _casualty_vehicle_clear(candidate): continue
			if not world.pedestrian_segment_clear(at,at+axis*length): continue
			if not world.pedestrian_space_clear(person,at,.55,false) or not world.pedestrian_space_clear(person,at+axis*length,.55,false): continue
			old.origin = at
			return old
	return old

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
		if edge.distance_to(target)>.025:
			var ray := PhysicsRayQueryParameters3D.create(edge,target,1|4|16)
			ray.exclude = [body.get_rid(),game.player.get_rid()]
			if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		var agent := _impact_agent(person)
		if agent.is_empty(): continue
		_lock(agent,"herido")
		var severe := absf(speed)>=5.5
		var old := _casualty_pose(person,person.global_transform)
		person.global_transform = old
		if person is Person: (person as Person).animate(.2,false)
		person.rotation.x = -PI*.5
		person.global_position.y = old.origin.y+.13
		var victim := {"agent":agent,"severe":severe,"old":old,"time":0.0,"retry":0.0}
		injured.append(victim)
		_protect_casualty(victim)
		print("Accidente: ",person.name," velocidad=",roundi(absf(speed)*3.6)," km/h grave=",severe)
		if injured.size()>=8: break

func _injury_tick(delta: float) -> void:
	for i in range(injured.size()-1,-1,-1):
		var victim: Dictionary = injured[i]
		if not is_instance_valid(victim.agent.node):
			_first_aid_release(victim)
			_remove_casualty_guard(victim)
			injured.remove_at(i)
			continue
		var being_carried: bool = bool(victim.get("in_transport",false)) or String(scene.get("kind",""))=="rescue" and scene.get("victim",{})==victim and String(scene.get("phase","")) in ["lift","carry","load","hospital","hospital_retry","hospital_reposition"]
		if not being_carried: _protect_casualty(victim)
		if bool(victim.severe):
			victim.time = float(victim.time)+delta
			continue
		victim.time = float(victim.time)+delta
		if float(victim.time)<5.0: continue
		var aid: Dictionary = victim.get("first_aid",{})
		if aid.is_empty() or not bool(aid.get("arrived",false)):
			if float(victim.time)>=12.0:
				victim.severe = true
				victim.retry = 0.0
				_rescue_log(victim,"no se recupera; solicitando traslado médico.")
			continue
		var p: Node3D = victim.agent.node
		var old: Transform3D = victim.old
		if _foot(old.origin).is_empty():
			var safe: Dictionary = {}
			for distance in [.7,1.2,1.8,2.5]:
				for n in range(8):
					var angle := float(n)*TAU/8.0
					var candidate := old.origin+Vector3(cos(angle),0,sin(angle))*float(distance)
					safe = _foot(candidate)
					if not safe.is_empty():
						var safe_point: Vector3 = safe.p
						var check := PhysicsRayQueryParameters3D.create(old.origin+Vector3.UP*.65,safe_point+Vector3.UP*.65,1|16)
						if get_world_3d().direct_space_state.intersect_ray(check).is_empty(): break
						safe = {}
				if not safe.is_empty(): break
			if safe.is_empty():
				if float(victim.time)>10.0: victim.severe = true
				continue
			old.origin = safe.p
		_first_aid_release(victim)
		_remove_casualty_guard(victim)
		p.global_transform = old
		p.set_meta("impact_immunity",Time.get_ticks_msec()+2500)
		_release(victim.agent)
		injured.remove_at(i)

# First aid is independent of the single vehicle/police scene.
func _first_aid_release(victim: Dictionary) -> void:
	var aid: Dictionary = victim.get("first_aid",{})
	victim.erase("first_aid")
	if not aid.is_empty(): _release(aid.agent)

func _first_aid_access(from: Vector3,center: Vector3) -> Dictionary:
	var targets: Array = []
	for radius in [1.05,1.65,2.3]:
		for i in range(8):
			var angle := float(i)*TAU/8.0
			var ground := _foot(center+Vector3(cos(angle),0,sin(angle))*float(radius))
			if not ground.is_empty():
				var point: Vector3 = ground.p
				if point.distance_to(from)<.15 or world.pedestrian_space_clear(null,point,.65,false): targets.append(point)
	targets.sort_custom(func(a,b): return from.distance_squared_to(a)<from.distance_squared_to(b))
	for target in targets:
		if world.pedestrian_segment_clear(from,target):
			return {"p":target,"path":PackedVector3Array([target])}
	for target in targets.slice(0,4):
		var path := _ped_path(from,target)
		if not path.is_empty(): return {"p":target,"path":path}
	return {}

func _first_aid_assign(victim: Dictionary,agent: Dictionary,access: Dictionary) -> void:
	var p: Person = agent.node
	_lock(agent,"primeros_auxilios")
	p.show()
	victim.first_aid = {"agent":agent,"path":access.path,"index":0,"last":p.global_position,"stuck":0.0,"arrived":false,"dt":0.0}
	print("Rescate: vecino va a atender al herido mientras llega el transporte.")

func _first_aid_start(victim: Dictionary) -> bool:
	var old: Transform3D = victim.old
	var center := old.origin
	var candidates := _walkers(center,38.0)
	for node in get_tree().get_nodes_in_group("social_people"):
		if not node is Person or not node.is_visible_in_tree() or node.has_meta("incident_role"): continue
		if String(node.social_context)!="bus_wait" or node.global_position.distance_to(center)>20.0: continue
		candidates.append({"node":node,"waiting_witness":true})
	for witness in crowd:
		var agent: Dictionary = witness.agent
		if is_instance_valid(agent.get("node")) and agent.node is Person and agent.node.global_position.distance_to(center)<38.0:
			candidates.append(agent)
	candidates.sort_custom(func(a,b): return (a.node as Node3D).global_position.distance_squared_to(center)<(b.node as Node3D).global_position.distance_squared_to(center))
	for agent in candidates.slice(0,5):
		var p: Person = agent.node
		var access := _first_aid_access(p.global_position,center)
		if access.is_empty(): continue
		if bool(agent.get("waiting_witness",false)):
			agent = _impact_agent(p)
			if agent.is_empty(): continue
		for i in range(crowd.size()-1,-1,-1):
			if crowd[i].agent.node==p:
				crowd.remove_at(i)
				break
		_first_aid_assign(victim,agent,access)
		return true
	# Bounded fallback: only spawn on checked, non-road ground.
	var origins: Array = []
	for radius in [2.5,3.5,5.0,8.0,12.0,18.0]:
		for i in range(8):
			var angle := float(i)*TAU/8.0
			var point := center+Vector3(cos(angle),0,sin(angle))*float(radius)
			if streets.point_on_road(point): continue
			var ground := _foot(point)
			if ground.is_empty(): continue
			origins.append(ground.p)
	origins.sort_custom(func(a,b): return center.distance_squared_to(a)<center.distance_squared_to(b))
	var tested := 0
	for origin in origins:
		if not world.pedestrian_space_clear(null,origin,.85,false): continue
		tested += 1
		if tested>6: break
		var access := _first_aid_access(origin,center)
		if access.is_empty(): continue
		var person := Person.new()
		add_child(person)
		person.setup(rng.randi_range(1300,1399))
		person.remove_from_group("social_people")
		person.global_position = origin
		_first_aid_assign(victim,{"node":person,"incident_source":"rescue_volunteer"},access)
		return true
	return false

func _first_aid_tick(victim: Dictionary,delta: float) -> void:
	if bool(victim.get("in_transport",false)): return
	var casualty: Node3D = victim.agent.node
	if not is_instance_valid(casualty) or not casualty.is_visible_in_tree(): return
	# Every fallen person gets assistance. Physical guard insertion is
	# independent; access candidates still require a clear walking path.
	if String(scene.get("kind",""))=="rescue" and scene.get("victim",{})==victim and String(scene.phase)!="approach":
		return
	var aid: Dictionary = victim.get("first_aid",{})
	if aid.is_empty():
		victim.aid_retry = maxf(0.0,float(victim.get("aid_retry",0.0))-delta)
		if float(victim.aid_retry)>0.0: return
		victim.aid_retry = 3.0
		if not _first_aid_start(victim):
			_rescue_log(victim,"buscando un vecino con acceso libre.")
		return
	if not is_instance_valid(aid.agent.get("node")):
		_first_aid_release(victim)
		return
	aid.dt = float(aid.dt)+delta
	if float(aid.dt)<.075: return
	var dt: float = aid.dt
	aid.dt = 0.0
	var p: Person = aid.agent.node
	var old: Transform3D = victim.old
	if bool(aid.arrived):
		var facing := old.origin-p.global_position
		p.rotation.y = atan2(facing.x,facing.z)
		p.animate(dt,false)
		return
	aid.index = _advance_actor(p,aid.path,int(aid.index),dt,2.3)
	if int(aid.index)>=aid.path.size():
		aid.arrived = true
		_say(p,"¡Tranquilo! Estoy aquí contigo. Vamos a buscar ayuda.")
		print("Rescate: primeros auxilios presentes junto al herido.")
		return
	if p.global_position.distance_to(aid.last)<.015:
		aid.stuck = float(aid.stuck)+dt
	else:
		aid.stuck = 0.0
		aid.last = p.global_position
	if float(aid.stuck)>3.0:
		var access := _first_aid_access(p.global_position,old.origin)
		aid.replans = int(aid.get("replans",0))+1
		if access.is_empty() or int(aid.replans)>=3:
			_first_aid_release(victim)
			victim.aid_retry = 1.0
		else:
			aid.path = access.path
			aid.index = 0
			aid.stuck = 0.0

func _rescue_log(victim: Dictionary,message: String) -> void:
	if String(victim.get("rescue_status",""))==message: return
	victim.rescue_status = message
	print("Rescate: ",message)

func _assign_rescue(victim: Dictionary,car: Dictionary,approach: Dictionary) -> void:
	var body: CharacterBody3D = car.body
	Bypass._junction_release(car,body,streets)
	car.incident_hold = true
	car.detour = []
	car.speed = 0.0
	var person: Node3D = victim.agent.node
	scene = {"kind":"rescue","phase":"approach","trip":approach.trip,"berth":approach.berth,"car":car,"victim":victim,"center":person.global_position,"time":0.0,"age":0.0,"actors":[]}
	_rescue_log(victim,"automóvil asignado: "+String(body.name))

func _reserve_responder(victim: Dictionary,center: Vector3) -> bool:
	# One supplementary civilian, only on a free road away from the event.
	# It has the same geometry and navigation rules as ordinary traffic.
	var extras := 0
	for car in municipal.vehicles:
		if not bool(car.get("rescue_extra",false)): continue
		extras += 1
		if bool(car.get("incident_hold",false)): return false
	if extras>=2 or municipal.civilian_route.size()<2: return false
	var goals: Array = []
	for goal in _berths(center,RESCUE_WALK_RANGE).slice(0,24):
		if _rescue_foot_access(goal,center).is_empty(): continue
		goals.append(goal)
	if goals.is_empty(): return false
	var tested: Dictionary = {}
	for edge in data.roads_near(center,100.0):
		if not bool(edge.driveable): continue
		var key := String(edge.a_id)+":"+String(edge.b_id)
		if tested.has(key): continue
		tested[key] = true
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		for fraction in [.25,.75]:
			var sample := a.lerp(b,float(fraction))
			if sample.distance_to(center)<22.0 or sample.distance_to(center)>100.0: continue
			for start in _berths(sample,9.0,Vector3.ZERO,false).slice(0,3):
				var p: Vector3 = start.p
				var d: Vector3 = start.d
				if not streets.intersection_clear_for_stop(p,LENGTH,WIDTH): continue
				if not municipal._free_box(p,d,Vector3(WIDTH,HEIGHT,LENGTH)): continue
				for goal in goals.slice(0,4):
					if not municipal._free_box(goal.p,goal.d,Vector3(WIDTH,HEIGHT,LENGTH)): continue
					var route := _route(start,goal,p)
					if route.is_empty(): continue
					var body: CharacterBody3D = municipal._body(false,10)
					body.global_position = p+Vector3.UP*.04
					body.rotation.y = atan2(d.x,d.z)
					var car := {"body":body,"route":municipal.civilian_route,"index":0,"speed":0.0,"truck":false,"crew":[],"site":{},"blocked":0.0,"cooldown":0.0,"detour":[],"detour_index":0,"resume":0,"rescue_extra":true}
					municipal.vehicles.append(car)
					_assign_rescue(victim,car,{"trip":_new_trip(body,route),"berth":goal})
					return true
		if tested.size()>=8: break
	return false

func _local_responder(victim: Dictionary,center: Vector3) -> bool:
	if municipal.civilian_route.size()<2: return false
	var camera := get_viewport().get_camera_3d()
	var goals := _berths(center,RESCUE_WALK_RANGE)
	# Prefer a curb outside the current view. A driver may already be
	# parked on this block; a disconnected driving graph is not a veto.
	var ranked: Array = []
	for goal in goals:
		var p: Vector3 = goal.p
		if p.distance_to(center)<4.0: continue
		if not municipal._free_box(p,goal.d,Vector3(WIDTH,HEIGHT,LENGTH)): continue
		var visible := camera!=null and camera.is_position_in_frustum(p+Vector3.UP)
		ranked.append({"goal":goal,"score":p.distance_to(center)+(35.0 if visible else 0.0)})
	ranked.sort_custom(func(a,b): return float(a.score)<float(b.score))
	for entry in ranked.slice(0,20):
		var goal: Dictionary = entry.goal
		if _rescue_foot_access(goal,center).is_empty(): continue
		var existing := 0
		for car in municipal.vehicles:
			if bool(car.get("rescue_extra",false)): existing += 1
		if existing>=2: return false
		var body: CharacterBody3D = municipal._body(false,10+existing)
		var p: Vector3 = goal.p
		var d: Vector3 = goal.d
		body.global_position = p+Vector3.UP*.04
		body.rotation.y = atan2(d.x,d.z)
		var car := {"body":body,"route":municipal.civilian_route,"index":0,"speed":0.0,"truck":false,"crew":[],"site":{},"blocked":0.0,"cooldown":0.0,"detour":[],"detour_index":0,"resume":0,"rescue_extra":true}
		municipal.vehicles.append(car)
		_assign_rescue(victim,car,{"trip":_new_trip(body,[]),"berth":goal})
		return true
	return false

func _rescue_start(victim: Dictionary) -> void:
	var person: Node3D = victim.agent.node
	var center := person.global_position
	var candidates: Array = []
	var failed: Dictionary = victim.get("failed_cars",{})
	for car in municipal.vehicles:
		if bool(car.truck) or bool(car.get("incident_hold",false)): continue
		var body: CharacterBody3D = car.body
		if not is_instance_valid(body) or String(body.name).begins_with("Patrulla") or body.global_position.distance_to(center)>240.0: continue
		if int(failed.get(body.get_instance_id(),0))>Time.get_ticks_msec(): continue
		candidates.append(car)
	candidates.sort_custom(func(a,b): return (a.body as Node3D).global_position.distance_squared_to(center)<(b.body as Node3D).global_position.distance_squared_to(center))
	var budget := 3 if float(victim.time)>=8.0 else 5
	for car in candidates.slice(0,budget):
		var body: CharacterBody3D = car.body
		var parked := _park_here(body,center)
		var approach := {"trip":_new_trip(body,[]),"berth":parked} if not parked.is_empty() else _car_trip(body,center,RESCUE_WALK_RANGE)
		if approach.is_empty(): continue
		_assign_rescue(victim,car,approach)
		return
	if _local_responder(victim,center): return
	if float(victim.time)>=8.0 and float(victim.time)>=float(victim.get("next_extra_probe",0.0)):
		victim.next_extra_probe = float(victim.time)+8.0
		if _reserve_responder(victim,center): return
	_rescue_log(victim,"esperando automóvil con acceso seguro; reintentando.")

# Find a reachable approach beside the casualty instead of insisting on
# the exact foot position, which may overlap a pole or parked vehicle.
func _rescue_foot_access(berth: Dictionary,at: Vector3) -> Dictionary:
	var p: Vector3 = berth.p
	var side: Vector3 = berth.right
	var d: Vector3 = berth.d
	# Probe the driver's curb first, but do not reject the opposite curb.
	for direction in [1.0,-1.0]:
		var origins: Array = []
		for shift in [0.0,1.8,-1.8,3.5,-3.5,5.5,-5.5]:
			for dist in [1.65,2.45,3.4,4.6,6.0]:
				var candidate := p+side*float(dist)*float(direction)+d*float(shift)
				if streets.point_on_road(candidate): continue
				var ground := _foot(candidate)
				if ground.is_empty(): continue
				origins.append(ground.p)
		origins.sort_custom(func(x,y): return p.distance_squared_to(x)<p.distance_squared_to(y))
		for origin in origins.slice(0,4):
			var access := _rescue_access(origin,at)
			if not access.is_empty():
				access["spawn"] = origin
				return access
	return {}

func _rescue_access(from: Vector3,at: Vector3) -> Dictionary:
	var candidates: Array = []
	for radius in [1.05,1.65,2.3,2.8]:
		for i in range(8):
			var angle := float(i)*TAU/8.0
			candidates.append(at+Vector3(cos(angle),0,sin(angle))*float(radius))
	var valid: Array = []
	for candidate in candidates:
		var ground := _foot(candidate)
		if ground.is_empty(): continue
		var p: Vector3 = ground.p
		if p.distance_to(from)>.15 and not world.pedestrian_space_clear(null,p,.65,false): continue
		if world.pedestrian_segment_clear(from,p):
			return {"p":p,"path":PackedVector3Array([p])}
		valid.append(p)
	# Try a limited set of graph routes after the direct options.
	for p in valid.slice(0,5):
		var path := _ped_path(from,p)
		if not path.is_empty(): return {"p":p,"path":path}
	return {}

func _hospital_trip(body: CharacterBody3D) -> Dictionary:
	var destinations: Array = []
	var dest := _destination("hospital")
	if not dest.is_empty(): destinations.append(dest.p)
	if world.incident_services.has("clinic"): destinations.append(world.incident_services.clinic)
	for fp in world.original_footprints.values():
		var kind := String(fp.tags.get("amenity",""))
		if kind not in ["hospital","clinic"]: continue
		var p: Vector3 = fp.center
		if not destinations.has(p): destinations.append(p)
	for p in destinations:
		var trip := _car_trip(body,p,65.0)
		if not trip.is_empty(): return trip
	return {}

# Accept the current position only if the whole car is on the road,
# clear of the junction and close to the curb, with a walking connection.
func _flat_distance_to_berth(a: Dictionary,b: Dictionary) -> float:
	var p: Vector3 = a.p
	return p.distance_to(b.p)

func _park_here(body: CharacterBody3D,center: Vector3) -> Dictionary:
	var origin := body.global_position
	if origin.distance_to(center)>RESCUE_WALK_RANGE: return {}
	if not streets.intersection_clear_for_stop(origin,LENGTH,WIDTH): return {}
	var heading := body.global_transform.basis.z.normalized()
	if not Bypass._on_road(streets,origin,heading,WIDTH,LENGTH): return {}
	for berth in _berths(origin,6.0,heading):
		var p: Vector3 = berth.p
		if _flat(p-origin).length()>1.35: continue
		var candidate: Dictionary = berth.duplicate()
		candidate.p = origin
		if _rescue_foot_access(candidate,center).is_empty(): continue
		return candidate
	# On narrow blocks an existing car can stop in its current lane for
	# a brief rescue, provided it is outside the junction and has a
	# validated walking connection. Do not require an exact parking offset.
	if origin.distance_to(center)<=22.0:
		for berth in _berths(origin,6.0,heading,false).slice(0,4):
			var point: Vector3 = berth.p
			if _flat(point-origin).length()>1.1: continue
			var candidate: Dictionary = berth.duplicate()
			candidate.p = origin
			if not _rescue_foot_access(candidate,center).is_empty(): return candidate
	return {}

func _rescue_parked(victim: Dictionary,body: CharacterBody3D) -> bool:
	var casualty: Vector3 = victim.old.origin
	var access := _rescue_foot_access(scene.berth,casualty)
	if access.is_empty(): return false
	var spawn: Vector3 = access.spawn
	Bypass._junction_release(scene.trip,body,streets)
	body.set_meta("junction_guard",false)
	body.set_meta("traffic_servicing",true)
	body.velocity = Vector3.ZERO
	var driver := Person.new()
	add_child(driver)
	driver.setup(rng.randi_range(1200,1290))
	driver.remove_from_group("social_people")
	driver.global_position = spawn
	var path: PackedVector3Array = access.path
	scene.actors = [{"node":driver,"path":path,"index":0,"last":spawn,"stuck":0.0}]
	scene.pickup_point = spawn
	scene.access_point = access.p
	scene.phase = "help"
	scene.time = 0.0
	var target: Vector3 = access.p
	var helper_target := Vector3.INF
	var axis := _flat(target-casualty).normalized()
	if axis.length_squared()<.01: axis = Vector3.FORWARD
	for angle in [PI*.5,-PI*.5,PI,PI*.25,-PI*.25]:
		var candidate := casualty+axis.rotated(Vector3.UP,float(angle))*1.6
		var ground := _foot(candidate)
		if ground.is_empty(): continue
		var point: Vector3 = ground.p
		if point.distance_to(target)<1.05: continue
		if not world.pedestrian_space_clear(null,point,.65,false): continue
		helper_target = point
		break
	var helper: Dictionary = {}
	# Reuse the neighbor who is already helping.
	var aid: Dictionary = victim.get("first_aid",{})
	if helper_target.is_finite() and not aid.is_empty() and is_instance_valid(aid.agent.get("node")):
		var neighbor: Person = aid.agent.node
		var route := _ped_path(neighbor.global_position,helper_target)
		if not route.is_empty():
			helper = {"agent":aid.agent,"node":neighbor,"path":route,"index":0}
			victim.erase("first_aid")
	_first_aid_release(victim)
	# A second person is welcome but never a condition for rescue.
	for agent in _walkers(target,30.0):
		if not helper.is_empty() or not helper_target.is_finite(): break
		var p: Person = agent.node
		var route := _ped_path(p.global_position,helper_target)
		if route.is_empty(): continue
		helper = {"agent":agent,"node":p,"path":route,"index":0}
		break
	if helper.is_empty() and helper_target.is_finite():
		for i in range(crowd.size()):
			var agent: Dictionary = crowd[i].agent
			var p: Person = agent.node
			var route := _ped_path(p.global_position,helper_target)
			if route.is_empty(): continue
			crowd.remove_at(i)
			helper = {"agent":agent,"node":p,"path":route,"index":0}
			break
	if not helper.is_empty():
		_lock(helper.agent,"auxilio")
		scene.actors.append(helper)
		_say(driver,"¡Ven, ayúdame a llevarlo al carro!")
	else:
		_say(driver,"Tranquilo, yo te llevo al hospital.")
	return true

func _release_helper() -> void:
	if scene.actors.size()<2: return
	var helper: Dictionary = scene.actors.pop_back()
	var person: Person = helper.node
	person.rotation.x = 0.0
	for arm in person.arms: arm.rotation = Vector3.ZERO
	_release(helper.agent)

# The patient is beside the carriers, not on the line connecting their
# torsos. Both carriers face the patient and walk sideways together.
# Aim the original articulated arms at the underside of the body.
func _rescue_grip(carrier: Person,axis: Vector3,center: Vector3) -> void:
	var facing := center-carrier.global_position
	facing.y = 0.0
	# Face across the casualty's body, not diagonally toward its center.
	facing -= axis*facing.dot(axis)
	if facing.length_squared()>.01: carrier.rotation.y = atan2(facing.x,facing.z)
	for arm in carrier.arms:
		var shoulder := arm.global_position
		var offset := clampf((shoulder-center).dot(axis),-.76,.76)
		var hand := center+axis*offset
		var inward := -facing.normalized()
		if inward.length_squared()>.01: hand += inward*.10
		hand.y -= .10
		var direction := carrier.global_basis.inverse()*(hand-shoulder)
		if direction.length_squared()>.0001:
			arm.quaternion = Quaternion(Vector3.DOWN,direction.normalized())

func _carry_heading(driver: Person,path: PackedVector3Array,index: int) -> Vector3:
	for i in range(index,path.size()):
		var d := _flat(path[i]-driver.global_position)
		if d.length()>.35: return d.normalized()
	var prior: Vector3 = scene.get("carry_direction",driver.global_transform.basis.z)
	return _flat(prior).normalized() if _flat(prior).length_squared()>.01 else Vector3.FORWARD

func _carry_side_clear(driver: Person,helper: Person,side: Vector3) -> bool:
	var a := driver.global_position
	var b := helper.global_position
	var shift := side*.46
	return world.pedestrian_segment_clear(a,a+shift) and world.pedestrian_segment_clear(b,b+shift) and world.pedestrian_segment_clear(a+shift,b+shift)

func _carry_pose(person: Node3D,driver: Person,helper: Person,_delta: float,blend: float = 1.0) -> void:
	var heading: Vector3 = scene.get("carry_direction",Vector3.FORWARD)
	var side := Vector3(-heading.z,0,heading.x)
	var axis := side
	var original_pose: Transform3D = scene.victim.old
	var size := original_pose.basis.get_scale()
	var body_scale := driver.global_basis.get_scale().y
	var center := driver.global_position+heading*.46+Vector3.UP*(body_scale*1.13)
	if helper!=null:
		var span := _flat(driver.global_position-helper.global_position)
		if span.length()>.65:
			axis = span.normalized()
			side = Vector3(-axis.z,0,axis.x)*float(scene.get("carry_side",1.0))
			if not _carry_side_clear(driver,helper,side):
				if _carry_side_clear(driver,helper,-side):
					scene.carry_side = -float(scene.get("carry_side",1.0))
					side = -side
				else:
					_release_helper()
					helper = null
			if helper!=null:
				var support_height := minf(body_scale,helper.global_basis.get_scale().y)*1.13
				center = (driver.global_position+helper.global_position)*.5+side*.46+Vector3.UP*support_height
		else:
			_release_helper()
			helper = null
	if helper==null:
		# One person holds the casualty across both arms, in front of the
		# chest, rather than through their hips or legs.
		axis = Vector3(-heading.z,0,heading.x)
		center = driver.global_position+heading*.46+Vector3.UP*(body_scale*1.13)
	var normal := Vector3.UP
	var across := axis.cross(normal).normalized()
	var pose := Basis(across,axis,normal).orthonormalized().scaled_local(size)
	# Local Y runs from feet to head; the torso midpoint is at ~.90 m.
	var feet := center-axis*(.90*size.y)
	var target := Transform3D(pose,feet)
	if blend<1.0:
		var lift: Transform3D = scene.lift_pose
		person.global_transform = lift.interpolate_with(target,blend)
	else:
		person.global_transform = target
	_rescue_grip(driver,axis,center)
	if helper!=null: _rescue_grip(helper,axis,center)
	if person is Person:
		var casualty := person as Person
		for limb in casualty.limbs: limb.rotation = Vector3.ZERO
		for arm in casualty.arms: arm.rotation = Vector3.ZERO

func _begin_transport(victim: Dictionary,person: Node3D,body: CharacterBody3D) -> void:
	victim.in_transport = true
	# The patient belongs to the vehicle before any hospital-route lookup.
	# A routing failure no longer returns the patient to the street.
	person.reparent(body,true)
	person.position = Vector3(0,.68,-.48)
	person.hide()
	body.set_meta("rescue_patient",true)
	_release_helper()
	var driver: Person = scene.actors[0].node
	driver.queue_free()
	scene.actors = []
	scene.phase = "hospital_retry"
	scene.time = 3.0
	scene.medical_wait = 0.0
	_crowd_clear()
	_rescue_log(victim,"herido dentro del automóvil; preparando traslado.")

func _rescue_tick(delta: float) -> void:
	var victim: Dictionary = scene.victim
	var person: Node3D = victim.agent.node
	var body: CharacterBody3D = scene.trip.body
	var phase := String(scene.phase)
	if phase=="approach":
		var arrived := _drive_trip(scene.trip,delta)
		if not arrived:
			if float(scene.trip.get("traffic_stall",0.0))<3.5: return
			if float(scene.age)<float(scene.get("next_park_probe",0.0)): return
			scene.next_park_probe = float(scene.age)+1.0
			var parked := _park_here(body,scene.center)
			if not parked.is_empty():
				scene.berth = parked
				if _rescue_parked(victim,body): return
			# Try a different reachable curb, including the next street.
			if float(scene.time)>5.0:
				scene.time = 0.0
				var alternate := _car_trip(body,scene.center,RESCUE_WALK_RANGE,scene.berth)
				if not alternate.is_empty() and _flat_distance_to_berth(alternate.berth,scene.berth)>3.0:
					Bypass._junction_release(scene.trip,body,streets)
					scene.trip = alternate.trip
					scene.berth = alternate.berth
			return
		if float(scene.time)<float(scene.get("park_retry_at",0.0)): return
		scene.park_retry_at = float(scene.time)+1.5
		if _rescue_parked(victim,body): return
		_rescue_log(victim,"buscando otro acceso a pie.")
		var alternative := _car_trip(body,scene.center,RESCUE_WALK_RANGE,scene.berth)
		if not alternative.is_empty() and _flat_distance_to_berth(alternative.berth,scene.berth)>3.0:
			scene.trip = alternative.trip
			scene.berth = alternative.berth
			scene.time = 0.0
			scene.park_retry_at = 0.0
		elif float(scene.time)>15.0:
			_end_rescue(false)
	elif phase=="help":
		var driver_actor: Dictionary = scene.actors[0]
		var driver: Person = driver_actor.node
		driver_actor.index = _advance_actor(driver,driver_actor.path,int(driver_actor.index),delta,2.6)
		if driver.global_position.distance_to(driver_actor.last)<.015:
			driver_actor.stuck = float(driver_actor.stuck)+delta
		else:
			driver_actor.stuck = 0.0
			driver_actor.last = driver.global_position
		if float(driver_actor.stuck)>3.0:
			var access := _rescue_access(driver.global_position,victim.old.origin)
			if not access.is_empty():
				driver_actor.path = access.path
				driver_actor.index = 0
				scene.access_point = access.p
			driver_actor.stuck = 0.0
		if scene.actors.size()>1:
			var helper_actor: Dictionary = scene.actors[1]
			helper_actor.index = _advance_actor(helper_actor.node,helper_actor.path,int(helper_actor.index),delta,2.5)
		if int(driver_actor.index)<driver_actor.path.size():
			if float(scene.time)>28.0: _end_rescue(false)
			return
		if scene.actors.size()>1:
			var helper_actor: Dictionary = scene.actors[1]
			if int(helper_actor.index)<helper_actor.path.size():
				scene.helper_wait = float(scene.get("helper_wait",0.0))+delta
				if float(scene.helper_wait)<2.5: return
				_release_helper()
		if float(scene.time)<float(scene.get("carry_probe_at",0.0)): return
		scene.carry_probe_at = float(scene.time)+1.0
		var path := _ped_path(driver.global_position,scene.pickup_point)
		if path.is_empty():
			path = _ped_path(driver.global_position,_flat(scene.pickup_point))
		if path.is_empty():
			if float(scene.time)>30.0: _end_rescue(false)
			return
		scene.carry_path = path
		scene.carry_index = 0
		scene.phase = "position_carry"
		scene.time = 0.0
		scene.carry_direction = _carry_heading(driver,path,0)
		scene.carry_side = 1.0
		scene.lift_pose = person.global_transform
		scene.carry_last = driver.global_position
		scene.carry_stuck = 0.0
	elif phase=="position_carry":
		var driver: Person = scene.actors[0].node
		var heading: Vector3 = scene.carry_direction
		if scene.actors.size()>1:
			var helper: Person = scene.actors[1].node
			var original_pose: Transform3D = victim.old
			var target := driver.global_position-heading*(1.05*original_pose.basis.get_scale().y)
			if helper.global_position.distance_to(target)>.15:
				var step := helper.global_position.move_toward(target,delta*2.0)
				if world.pedestrian_segment_clear(helper.global_position,step):
					helper.walk_to(target,delta,2.0)
				if float(scene.time)<2.5: return
				_release_helper()
		_remove_casualty_guard(victim)
		scene.phase = "lift"
		scene.time = 0.0
	elif phase=="lift":
		var driver: Person = scene.actors[0].node
		var helper: Person = scene.actors[1].node if scene.actors.size()>1 else null
		var t := clampf(float(scene.time)/1.2,0.0,1.0)
		_carry_pose(person,driver,helper,delta,smoothstep(0.0,1.0,t))
		# Lean toward the casualty at the beginning, then straighten.
		driver.rotation.x = sin(t*PI)*.22
		if is_instance_valid(helper) and scene.actors.size()>1: helper.rotation.x = sin(t*PI)*.22
		if t>=1.0:
			driver.rotation.x = 0.0
			if is_instance_valid(helper): helper.rotation.x = 0.0
			scene.phase = "carry"
			scene.time = 0.0
	elif phase=="carry":
		var driver: Person = scene.actors[0].node
		var helper: Person = scene.actors[1].node if scene.actors.size()>1 else null
		var path: PackedVector3Array = scene.carry_path
		var speed := 1.25 if helper!=null else 1.15
		var prior := driver.global_position
		scene.carry_index = _advance_actor(driver,path,int(scene.carry_index),delta,speed)
		var direction := _flat(driver.global_position-prior)
		if direction.length_squared()>.000001:
			var previous: Vector3 = scene.carry_direction
			var next := previous.lerp(direction.normalized(),minf(1.0,delta*8.0))
			if next.length_squared()>.001: scene.carry_direction = next.normalized()
		var heading: Vector3 = scene.carry_direction
		if helper!=null:
			var original_pose: Transform3D = victim.old
			var follow := driver.global_position-heading*(1.05*original_pose.basis.get_scale().y)
			if helper.global_position.distance_to(follow)>.09:
				var step := helper.global_position.move_toward(follow,delta*1.85)
				if world.pedestrian_segment_clear(helper.global_position,step): helper.walk_to(follow,delta,1.85)
			var gap := helper.global_position.distance_to(driver.global_position)
			if gap>1.65 or gap<.62:
				_release_helper()
				helper = null
		_carry_pose(person,driver,helper,delta)
		if driver.global_position.distance_to(scene.carry_last)<.015:
			scene.carry_stuck = float(scene.carry_stuck)+delta
		else:
			scene.carry_stuck = 0.0
			scene.carry_last = driver.global_position
		if float(scene.carry_stuck)>3.0:
			_release_helper()
			var route := _ped_path(driver.global_position,scene.pickup_point)
			if not route.is_empty():
				scene.carry_path = route
				scene.carry_index = 0
			scene.carry_stuck = 0.0
		if int(scene.carry_index)>=path.size():
			scene.phase = "load"
			scene.time = 0.0
			scene.load_from = person.global_position
	elif phase=="load":
		var driver: Person = scene.actors[0].node
		var t := clampf(float(scene.time)/1.25,0.0,1.0)
		var start: Vector3 = scene.load_from
		var seat := body.to_global(Vector3(0,.78,-.48))
		person.global_position = start.lerp(seat,smoothstep(0.0,1.0,t))
		var axis := person.global_basis.y.normalized()
		_rescue_grip(driver,axis,person.global_position+axis*.90)
		if scene.actors.size()>1:
			var helper: Person = scene.actors[1].node
			_rescue_grip(helper,axis,person.global_position+axis*.90)
		if t>=1.0: _begin_transport(victim,person,body)
	elif phase=="hospital_retry":
		if float(scene.time)<2.0: return
		scene.time = 0.0
		var transfer := _hospital_trip(body)
		if transfer.is_empty():
			_rescue_log(victim,"herido a bordo; buscando una ruta médica alternativa.")
			scene.medical_wait = float(scene.get("medical_wait",0.0))+2.0
			if float(scene.medical_wait)>=8.0:
				# Move to a connected street instead of occupying the pickup
				# berth indefinitely. Patient remains in the vehicle.
				var here := body.global_position
				var heading := body.global_transform.basis.z
				for goal in _berths(here+heading*45.0,35.0,heading):
					var point: Vector3 = goal.p
					if point.distance_to(here)<20.0: continue
					var alternative := _car_trip(body,point,20.0)
					if alternative.is_empty(): continue
					scene.trip = alternative.trip
					scene.phase = "hospital_reposition"
					scene.medical_wait = 0.0
					break
			return
		scene.trip = transfer.trip
		scene.hospital_berth = transfer.berth
		scene.phase = "hospital"
		_rescue_log(victim,"rumbo al centro médico.")
	elif phase=="hospital_reposition":
		if _drive_trip(scene.trip,delta) or float(scene.trip.get("traffic_stall",0.0))>7.0:
			Bypass._junction_release(scene.trip,body,streets)
			body.velocity = Vector3.ZERO
			scene.phase = "hospital_retry"
			scene.time = 2.0
	elif phase=="hospital":
		if not _drive_trip(scene.trip,delta):
			if float(scene.trip.get("traffic_stall",0.0))>8.0 and float(scene.time)>10.0:
				scene.time = 0.0
				var alternative := _hospital_trip(body)
				if not alternative.is_empty():
					Bypass._junction_release(scene.trip,body,streets)
					scene.trip = alternative.trip
					scene.hospital_berth = alternative.berth
			return
		var ground := _sidewalk(scene.hospital_berth,scene.hospital_berth.p)
		if ground.is_empty():
			scene.phase = "hospital_retry"
			scene.time = 0.0
			return
		person.reparent(_impact_parent(victim.agent),true)
		person.global_position = ground.p
		var original_pose: Transform3D = victim.old
		person.global_basis = original_pose.basis
		person.show()
		body.remove_meta("rescue_patient")
		_say(person,"Gracias por traerme al hospital.")
		_end_rescue(true)

func _end_rescue(delivered: bool) -> void:
	var car: Dictionary = scene.car
	var victim: Dictionary = scene.victim
	var was_transport: bool = bool(victim.get("in_transport",false))
	victim.in_transport = false
	var person: Node3D = victim.agent.node
	for actor in scene.actors:
		if actor.has("agent"):
			var helper: Person = actor.node
			helper.rotation.x = 0.0
			for arm in helper.arms: arm.rotation = Vector3.ZERO
			_release(actor.agent)
		elif is_instance_valid(actor.node): actor.node.queue_free()
	var body: CharacterBody3D = car.body
	Bypass._junction_release(scene.trip,body,streets)
	body.set_meta("traffic_servicing",false)
	body.set_meta("junction_guard",false)
	car.detour = []
	car.speed = 0.0
	_rejoin_car(car)
	if delivered:
		_remove_casualty_guard(victim)
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
		victim.severe = true
		_remove_casualty_guard(victim)
		_protect_casualty(victim)
		victim.retry = 5.0
		injured.erase(victim)
		injured.append(victim)
		var failed: Dictionary = victim.get("failed_cars",{})
		failed[body.get_instance_id()] = Time.get_ticks_msec()+30000
		victim.failed_cars = failed
		_rescue_log(victim,"cambiando automóvil o acceso; rescate sigue pendiente.")
	if delivered and not was_transport: _crowd_clear()
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

func _detach_medical_transfer() -> void:
	if scene.is_empty() or medical_transfers.size()>=MAX_MEDICAL_TRANSFERS: return
	if String(scene.get("kind",""))!="rescue": return
	if String(scene.get("phase","")) not in ["hospital","hospital_retry","hospital_reposition"]: return
	medical_transfers.append(scene)
	scene = {}

func _tick_medical_transfers(delta: float) -> void:
	var foreground: Dictionary = scene
	for i in range(medical_transfers.size()-1,-1,-1):
		scene = medical_transfers[i]
		scene.time = float(scene.time)+delta
		scene.age = float(scene.age)+delta
		_rescue_tick(delta)
		if scene.is_empty():
			medical_transfers.remove_at(i)
		else:
			medical_transfers[i] = scene
	scene = foreground

func tick(delta: float) -> void:
	_tick_returning(delta)
	_tick_medical_transfers(delta)
	_detach_medical_transfer()
	dispatch_wait = maxf(0.0,dispatch_wait-delta)
	_injury_tick(delta)
	for victim in injured:
		victim.retry = maxf(0.0,float(victim.retry)-delta)
	if not router.initialized: return
	for victim in injured:
		_first_aid_tick(victim,delta)
	# Medical rescue has priority over a patrol that has not begun loading.
	if String(scene.get("kind",""))=="police" and String(scene.get("phase","")) in ["approach","walk","ask"]:
		for victim in injured:
			if bool(victim.severe) and not bool(victim.get("in_transport",false)):
				_finish_police(false)
				break
	if scene.is_empty() and dispatch_wait<=0.0:
		for victim in injured:
			if bool(victim.severe) and not bool(victim.get("in_transport",false)) and float(victim.retry)<=0.0:
				dispatch_wait = .65
				victim.retry = 4.0
				_rescue_start(victim)
				if not scene.is_empty(): break
				# One expensive vehicle search per frame, not one per casualty.
				break
		if scene.is_empty() and not injured.is_empty():
			for victim in injured:
				if bool(victim.get("in_transport",false)): continue
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
	if phase not in ["depart","depart_retry","hospital","hospital_retry","hospital_reposition"] and (phase!="approach" or String(scene.kind)=="rescue"):
		_crowd_tick(scene.center,delta)
	if String(scene.kind)=="police":
		_police_tick(delta)
		if not scene.is_empty() and float(scene.age)>155.0: _finish_police(false)
	else:
		_rescue_tick(delta)
		_detach_medical_transfer()
		if not scene.is_empty() and float(scene.age)>55.0 and String(scene.phase)=="approach":
			_end_rescue(false)
		elif not scene.is_empty() and float(scene.age)>150.0 and String(scene.phase) not in ["hospital","hospital_retry","hospital_reposition","load"]:
			_end_rescue(false)
