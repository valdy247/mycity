extends Node3D
const World = preload("res://cuba_world.gd")
const Person = preload("res://street_person.gd")
const UrbanBuses = preload("res://urban_buses.gd")
const MAX_WALKERS := 38
const CELL := 4.0
# A shared route priority: covered portal > sidewalk > curbside roadway.
const PORTAL_COST := .62
const SIDEWALK_COST := 1.0
const ROAD_COST := 18.0
var world: World
var buses: UrbanBuses
var graph := AStar3D.new()
var cells: Dictionary = {}
var destinations: Array = []
var walkers: Array = []
var next_id := 1
var initialized := false
var building_graph := false
const BUILD_BUDGET_USEC := 4000
var build_wait := .20
var elapsed := 0.0
var population_clock := 0.0
var serial := 200
var shape := CapsuleShape3D.new()

func setup(city: World,bus_service: UrbanBuses) -> void:
	world = city
	world.pedestrian_router = self
	buses = bus_service
	shape.radius = .27
	shape.height = 1.52

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x/CELL),floori(p.z/CELL))

func _near_ids(p: Vector3,radius: float) -> Array:
	var result: Array = []
	var low := _cell(p-Vector3(radius,0,radius))
	var high := _cell(p+Vector3(radius,0,radius))
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			for id in cells.get(Vector2i(x,z),[]):
				if graph.get_point_position(int(id)).distance_to(p)<=radius:
					result.append(id)
	return result

func _ground(p: Vector3) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(Vector3(p.x,.58,p.z),Vector3(p.x,-.3,p.z),1|2)
	var hit := space.intersect_ray(ray)
	if hit.is_empty(): return {}
	var base: Vector3 = hit.position
	if base.y>.26: return {}
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY,base+Vector3.UP*.83)
	query.collision_mask = 1|4|8|16
	if not space.intersect_shape(query,1).is_empty(): return {}
	return {"p":base+Vector3.UP*.015}

func _clear(a: Vector3,b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var d := (b-a).normalized()
	var side := Vector3(-d.z,0,d.x)*.22
	# Check low obstructions, body and head, not just the centre of the torso.
	for height in [.25,.75,1.35]:
		for shift in [Vector3.ZERO,side,-side]:
			var lift := Vector3.UP*float(height)
			var ray := PhysicsRayQueryParameters3D.create(a+lift+shift,b+lift+shift,1|4|8|16)
			if not space.intersect_ray(ray).is_empty(): return false
	return true

func _add(p: Vector3,cost: float,merge_radius: float = .45) -> int:
	var ground := _ground(p)
	if ground.is_empty(): return -1
	var at: Vector3 = ground.p
	for id in _near_ids(at,merge_radius):
		graph.set_point_weight_scale(int(id),minf(cost,graph.get_point_weight_scale(int(id))))
		return int(id)
	var id := next_id
	next_id += 1
	graph.add_point(id,at,cost)
	var key := _cell(at)
	if not cells.has(key): cells[key] = []
	cells[key].append(id)
	return id

func _run(a: Vector3,b: Vector3,cost: float) -> void:
	var count := maxi(1,ceili(a.distance_to(b)/2.1))
	for i in range(count+1):
		_add(a.lerp(b,float(i)/float(count)),cost)

func _build() -> void:
	var started := Time.get_ticks_msec()
	var slice_start := Time.get_ticks_usec()
	# Start from the actual traversable portal strips created by CubaWorld.
	for strip in world.monte_walkways:
		_run(strip.a,strip.b,PORTAL_COST)
		# Approximate strip points are navigation only, never entry doors.
		_add(strip.door,PORTAL_COST)
		if Time.get_ticks_usec()-slice_start>=BUILD_BUDGET_USEC:
			await get_tree().physics_frame
			slice_start = Time.get_ticks_usec()
	# Extend the existing Monte network into adjoining streets without
	# building a city-wide physics graph at startup.
	var corridor_nodes: Dictionary = {}
	for edge in world.geography.roads:
		if world._is_monte_edge(edge):
			corridor_nodes[edge.a_id] = true
			corridor_nodes[edge.b_id] = true
	var adjacent := corridor_nodes.duplicate()
	for edge in world.geography.roads:
		if corridor_nodes.has(edge.a_id) or corridor_nodes.has(edge.b_id):
			adjacent[edge.a_id] = true
			adjacent[edge.b_id] = true
	for edge in world.geography.roads:
		if Time.get_ticks_usec()-slice_start>=BUILD_BUDGET_USEC:
			await get_tree().physics_frame
			slice_start = Time.get_ticks_usec()
		if not adjacent.has(edge.a_id) and not adjacent.has(edge.b_id): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		if a.distance_to(b)<.15: continue
		if not bool(edge.driveable):
			_run(a,b,SIDEWALK_COST)
			continue
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		var half_width := float(edge.width)*.5
		var count := maxi(1,ceili(a.distance_to(b)/2.0))
		for side in [-1.0,1.0]:
			var outward := right*float(side)
			for i in range(count+1):
				var center := a.lerp(b,float(i)/float(count))
				var sidewalk := center+outward*(half_width+.70)
				if not world.street_geometry.point_on_road(sidewalk):
					_add(sidewalk,SIDEWALK_COST)
				# A costly alternative along the curb, never down the middle
				# of the carriageway when there is room at the edge.
				var curb := center+outward*maxf(0.0,half_width-.55)
				if world.street_geometry.point_on_road(curb):
					_add(curb,ROAD_COST)
				if Time.get_ticks_usec()-slice_start>=BUILD_BUDGET_USEC:
					await get_tree().physics_frame
					slice_start = Time.get_ticks_usec()
	if world.home_root!=null:
		var home := world.home_root
		_run(home.to_global(Vector3(-3.3,0,2.75)),home.to_global(Vector3(3.3,0,2.75)),PORTAL_COST)
		_add(home.to_global(Vector3(1.25,0,2.65)),PORTAL_COST)
	for id in graph.get_point_ids():
		if Time.get_ticks_usec()-slice_start>=BUILD_BUDGET_USEC:
			await get_tree().physics_frame
			slice_start = Time.get_ticks_usec()
		var p := graph.get_point_position(id)
		for other in _near_ids(p,3.8):
			if int(other)<=id: continue
			var q := graph.get_point_position(int(other))
			# Long connections over traffic lanes are not shortcuts.
			var middle := p.lerp(q,.5)
			var curb_link := graph.get_point_weight_scale(id)>=ROAD_COST or graph.get_point_weight_scale(int(other))>=ROAD_COST
			if world.street_geometry.point_on_road(middle) and not curb_link and p.distance_to(q)>3.1: continue
			# Don't connect across the full roadway just because two curb nodes
			# happen to be within the graph search radius.
			if curb_link and p.distance_to(q)>2.9: continue
			if _clear(p,q): graph.connect_points(id,int(other),true)
	# Bridge gaps at small side streets, only along unobstructed routes.
	for id in graph.get_point_ids():
		if Time.get_ticks_usec()-slice_start>=BUILD_BUDGET_USEC:
			await get_tree().physics_frame
			slice_start = Time.get_ticks_usec()
		if graph.get_point_connections(id).size()>1: continue
		var p := graph.get_point_position(id)
		for other in _near_ids(p,7.0):
			if int(other)==id or graph.are_points_connected(id,int(other)): continue
			var q := graph.get_point_position(int(other))
			if graph.get_point_weight_scale(id)>=ROAD_COST or graph.get_point_weight_scale(int(other))>=ROAD_COST: continue
			if world.street_geometry.point_on_road(p.lerp(q,.5)): continue
			if _clear(p,q):
				graph.connect_points(id,int(other),true)
				break
	await _register_doors()
	if buses!=null:
		for stop in buses.stops:
			var p: Vector3 = stop.wait
			var nearest := _nearest(p,5.0)
			if nearest<0: continue
			var q := graph.get_point_position(nearest)
			if not _clear(p,q): continue
			stop["pedestrian_managed"] = true
			destinations.append({"id":nearest,"kind":"bus","stop":stop})
		buses.alight_handler = Callable(self,"accept_alighting")
	print("Monte: ",graph.get_point_count()," pedestrian waypoints, ",destinations.size()," destinations; carga distribuida ",Time.get_ticks_msec()-started," ms.")
	initialized = true
	building_graph = false
	_populate()

# Only generated door panels on reachable facades are indoor destinations.
func _register_doors() -> void:
	var slice_start := Time.get_ticks_usec()
	var used: Dictionary = {}
	for entry in world.npc_doorways:
		if Time.get_ticks_usec()-slice_start>=BUILD_BUDGET_USEC:
			await get_tree().physics_frame
			slice_start = Time.get_ticks_usec()
		var space := get_world_3d().direct_space_state
		var threshold: Vector3 = entry.threshold
		var normal: Vector3 = entry.normal
		var outside := threshold+normal*.48
		if _near_ids(outside,3.2).is_empty(): continue
		var ground := _ground(outside)
		if ground.is_empty(): continue
		var p: Vector3 = ground.p
		var link := _nearest(p,3.2)
		if link<0: continue
		var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*1.15,threshold-normal*.30+Vector3.UP*(p.y+1.15),1)
		if space.intersect_ray(ray).is_empty(): continue
		if not world.pedestrian_segment_clear(p,graph.get_point_position(link)): continue
		var id := _add(p,SIDEWALK_COST,.06)
		if id<0 or used.has(id): continue
		if id!=link and not graph.are_points_connected(id,link):
			graph.connect_points(id,link,true)
		used[id] = true
		destinations.append({"id":id,"kind":String(entry.kind),"door":true,"normal":normal,"threshold":threshold})

# Albertico shares the pedestrian graph instead of crossing buildings
# with an unchecked straight-line animation.
func customer_trip(stand_at: Vector3,frontage: Basis) -> Dictionary:
	if not initialized: return {}
	var options: Array[Vector3] = [
		stand_at+frontage.z*.84,
		stand_at-frontage.z*.84,
		stand_at+frontage.x*1.18,
		stand_at-frontage.x*1.18
	]
	for option in options:
		var ground := _ground(option)
		if ground.is_empty(): continue
		var target: Vector3 = ground.p
		var end := _nearest(target,3.8)
		if end<0 or not world.pedestrian_segment_clear(graph.get_point_position(end),target): continue
		var doors: Array = []
		for dest in destinations:
			if not bool(dest.get("door",false)): continue
			var p := graph.get_point_position(int(dest.id))
			var dist := p.distance_to(target)
			if dist>=3.0 and dist<=32.0:
				doors.append({"dest":dest,"distance":dist})
		doors.sort_custom(func(a,b): return float(a.distance)<float(b.distance))
		for i in range(mini(doors.size(),18)):
			var door: Dictionary = doors[i].dest
			var start := int(door.id)
			var path := graph.get_point_path(start,end)
			if path.size()<2: continue
			var length := 0.0
			for j in range(1,path.size()):
				length += path[j-1].distance_to(path[j])
			if length>45.0: continue
			if not world.pedestrian_segment_clear(path[0],path[0]): continue
			if path[path.size()-1].distance_to(target)>.08: path.append(target)
			return {"path":path,"door":door}
	return {}

# Persistent named residents use the same collision-checked public network.
func route_between(a: Vector3,b: Vector3) -> PackedVector3Array:
	if not initialized: return PackedVector3Array()
	var start := _nearest(a,7.0)
	var finish := _nearest(b,7.0)
	if start<0 or finish<0: return PackedVector3Array()
	if not world.pedestrian_segment_clear(a,graph.get_point_position(start)): return PackedVector3Array()
	if not world.pedestrian_segment_clear(graph.get_point_position(finish),b): return PackedVector3Array()
	var middle := graph.get_point_path(start,finish)
	if middle.is_empty(): return PackedVector3Array()
	var path := PackedVector3Array([a])
	for point in middle: path.append(point)
	path.append(b)
	return path

func _nearest(p: Vector3,radius: float) -> int:
	var best := radius
	var found := -1
	for id in _near_ids(p,radius):
		if graph.get_point_connections(int(id)).is_empty(): continue
		var dist := graph.get_point_position(int(id)).distance_to(p)
		if dist<best and _clear(p,graph.get_point_position(int(id))):
			best = dist
			found = int(id)
	return found

func _choose_route(agent: Dictionary,force_non_bus: bool = false) -> bool:
	var person: Person = agent.node
	var start := _nearest(person.global_position,6.0)
	if start<0: return false
	var nearby: Array = []
	var origin := graph.get_point_position(start)
	for dest in destinations:
		if force_non_bus and String(dest.kind)=="bus": continue
		var p := graph.get_point_position(int(dest.id))
		var dist := origin.distance_to(p)
		if dist<8.0 or dist>155.0: continue
		if String(dest.kind)=="bus":
			var stop: Dictionary = dest.stop
			if stop.queue.size()>=4: continue
		nearby.append(dest)
	nearby.shuffle()
	# A quarter of residents actively seek a bus stop rather than leaving
	# all transport demand to random selection among hundreds of doors.
	if not force_non_bus and posmod(person.style_id,4)==0:
		nearby.sort_custom(func(a,b): return int(String(a.kind)=="bus")>int(String(b.kind)=="bus"))
	for i in range(mini(nearby.size(),20)):
		var dest: Dictionary = nearby[i]
		var path := graph.get_point_path(start,int(dest.id))
		if path.size()<2: continue
		agent.path = path
		agent.index = 0
		agent.destination = dest
		person.social_context = "shopping" if String(dest.kind)=="shop" else "street"
		agent.pause = 0.0
		return true
	var neighbors := graph.get_point_connections(start)
	if neighbors.is_empty(): return false
	var end := int(neighbors[randi_range(0,neighbors.size()-1)])
	agent.path = graph.get_point_path(start,end)
	agent.index = 0
	agent.destination = {"id":end,"kind":"walk"}
	person.social_context = "street"
	agent.pause = 0.0
	return true

func accept_alighting(node: Node3D) -> bool:
	if not initialized or not node is Person or walkers.size()>=MAX_WALKERS+8: return false
	var person := node as Person
	var at := person.global_position
	var start := _nearest(at,7.0)
	if start<0 or not _clear(at,graph.get_point_position(start)): return false
	var agent := {"node":person,"path":PackedVector3Array(),"index":0,"destination":{},"pause":0.0,"speed":1.35}
	if not _choose_route(agent,true): return false
	person.reparent(self,true)
	person.show()
	person.add_to_group("bus_yield_walkers")
	walkers.append(agent)
	return true

func _populate() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera==null: return
	var at := camera.global_position
	for i in range(walkers.size()-1,-1,-1):
		var person: Person = walkers[i].node
		if person.has_meta("incident_role"): continue
		if person.global_position.distance_to(at)>190.0:
			person.queue_free()
			walkers.remove_at(i)
	var candidates := _near_ids(at,100.0)
	candidates.shuffle()
	var added := 0
	for id in candidates:
		if walkers.size()>=MAX_WALKERS or added>=6: break
		if graph.get_point_connections(int(id)).is_empty(): continue
		# Roadway nodes are for fallback travel, not ordinary population spawns.
		if graph.get_point_weight_scale(int(id))>=ROAD_COST: continue
		var p := graph.get_point_position(int(id))
		if p.distance_to(at)<7.0: continue
		var safe := true
		for agent in walkers:
			var other: Person = agent.node
			if other.global_position.distance_to(p)<2.1:
				safe = false
				break
		if not safe: continue
		var person := Person.new()
		add_child(person)
		serial += 1
		person.setup(serial)
		person.global_position = p
		var agent := {"node":person,"path":PackedVector3Array(),"index":0,"destination":{},"pause":0.0,"speed":1.12+float(posmod(serial,7))*.065}
		if _choose_route(agent):
			person.add_to_group("bus_yield_walkers")
			walkers.append(agent)
			added += 1
		else:
			person.queue_free()

# A horn gives a walker a checked path out of the bus lane, not a
# teleport. After reaching safety the normal destination planner resumes.
func yield_to_bus(stop: Dictionary,bus: CharacterBody3D) -> void:
	var center: Vector3 = stop.position
	var direction: Vector3 = stop.direction
	var side := Vector3(-direction.z,0,direction.x)
	var approach := maxf(0.0,(center-bus.global_position).dot(direction))
	for agent in walkers:
		var person: Person = agent.node
		if person.has_meta("incident_role") or bool(agent.get("indoors",false)) or agent.has("yield_target"): continue
		var at := person.global_position
		var offset := at-center
		if absf(offset.dot(side))>1.55 or offset.dot(direction)<-approach-4.7 or offset.dot(direction)>5.6: continue
		var wait: Vector3 = stop.wait
		var along := offset.dot(direction)
		for shift in [0.0,1.0,-1.0,2.0,-2.0]:
			var candidate := wait+direction*(along+float(shift))
			if world.street_geometry.point_on_road(candidate): continue
			var ground := _ground(candidate)
			if ground.is_empty(): continue
			var target: Vector3 = ground.p
			if world.pedestrian_segment_clear(at,target):
				person.remove_meta("conversation_until")
				agent.yield_target = target
				break

func tick(delta: float) -> void:
	if not initialized:
		if building_graph: return
		build_wait -= delta
		if build_wait>0.0: return
		building_graph = true
		_build()
		return
	elapsed += delta
	if elapsed<.065: return
	var dt := elapsed
	elapsed = 0.0
	population_clock += dt
	if population_clock>=1.5:
		population_clock = 0.0
		_populate()
	var camera := get_viewport().get_camera_3d()
	for i in range(walkers.size()-1,-1,-1):
		var agent: Dictionary = walkers[i]
		var person: Person = agent.node
		if person.has_meta("incident_role"): continue
		if bool(agent.get("incident_replan",false)):
			agent.erase("incident_replan")
			agent.erase("yield_target")
			agent.pause = 0.0
			if not _choose_route(agent,true): agent.pause = .5
		person.visible = not bool(agent.get("indoors",false)) and (camera==null or person.global_position.distance_squared_to(camera.global_position)<14400.0)
		if agent.has("yield_target"):
			var safe: Vector3 = agent.yield_target
			var step := person.global_position.move_toward(safe,1.8*dt)
			if world.pedestrian_segment_clear(person.global_position,step):
				if person.walk_to(safe,dt,1.8):
					agent.erase("yield_target")
					agent.pause = 6.0
			else:
				agent.erase("yield_target")
			continue
		if person.conversation_active(dt): continue
		if float(agent.pause)>0.0:
			agent.pause = maxf(0.0,float(agent.pause)-dt)
			person.animate(dt,false)
			if float(agent.pause)<=0.0:
				if bool(agent.get("indoors",false)):
					if not world.pedestrian_segment_clear(person.global_position,person.global_position):
						agent.pause = .5
						continue
					agent.indoors = false
					person.show()
				if not _choose_route(agent): agent.pause = .5
			continue
		var path: PackedVector3Array = agent.path
		var index := int(agent.index)
		if index>=path.size():
			var dest: Dictionary = agent.destination
			if String(dest.get("kind",""))=="bus" and buses!=null:
				if buses.join_stop(dest.stop,person):
					person.remove_from_group("bus_yield_walkers")
					walkers.remove_at(i)
					continue
			# Simulated indoor visits are only allowed at a verified door.
			if bool(dest.get("door",false)) and person.global_position.distance_to(graph.get_point_position(int(dest.id)))<.14:
				var normal: Vector3 = dest.normal
				person.rotation.y = atan2(-normal.x,-normal.z)
				agent.indoors = true
				person.hide()
				agent.pause = 3.0+float(posmod(person.style_id,8))
			else:
				agent.pause = .5
			continue
		var p: Vector3 = path[index]
		# Recheck the live scene: walkers use scripted movement rather than
		# CharacterBody3D, so never advance into a new obstacle.
		var step := person.global_position.move_toward(p,maxf(.12,float(agent.speed)*dt))
		# Always sweep the actual next step; the longer preview only needs
		# refreshing when the waypoint changes or every quarter second.
		var preview_due := int(agent.get("preview_index",-1))!=index or float(agent.get("preview_wait",0.0))<=0.0
		agent.preview_wait = float(agent.get("preview_wait",0.0))-dt
		var route_clear := true
		if preview_due:
			agent.preview_index = index
			agent.preview_wait = .25
			route_clear = person.global_position.distance_to(p)<=.12 or _clear(person.global_position,p)
		if not world.pedestrian_segment_clear(person.global_position,step) or not route_clear:
			person.animate(dt,false)
			agent["blocked_time"] = float(agent.get("blocked_time",0.0))+dt
			if float(agent.blocked_time)>=.65:
				agent.blocked_time = 0.0
				var from_id := -1
				var to_id := graph.get_closest_point(p)
				if index>0: from_id = graph.get_closest_point(path[index-1])
				var disconnected := from_id>0 and to_id>0 and from_id!=to_id and graph.are_points_connected(from_id,to_id)
				if disconnected: graph.disconnect_points(from_id,to_id,true)
				_choose_route(agent)
				if disconnected: graph.connect_points(from_id,to_id,true)
			continue
		agent["blocked_time"] = 0.0
		if person.walk_to(p,dt,float(agent.speed)):
			agent.index = index+1
