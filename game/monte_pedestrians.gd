extends Node3D
const World = preload("res://cuba_world.gd")
const Person = preload("res://street_person.gd")
const MAX_WALKERS := 38
const CELL := 4.0
var world: World
var buses: Node3D
var graph := AStar3D.new()
var cells: Dictionary = {}
var destinations: Array = []
var walkers: Array = []
var next_id := 1
var initialized := false
var elapsed := 0.0
var population_clock := 0.0
var serial := 200
var shape := CapsuleShape3D.new()

func setup(city: World,bus_service: Node3D) -> void:
	world = city
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
	for shift in [Vector3.ZERO,side,-side]:
		var ray := PhysicsRayQueryParameters3D.create(a+Vector3.UP*.75+shift,b+Vector3.UP*.75+shift,1|4|8|16)
		if not space.intersect_ray(ray).is_empty(): return false
	return true

func _add(p: Vector3,covered: bool) -> int:
	var ground := _ground(p)
	if ground.is_empty(): return -1
	var at: Vector3 = ground.p
	for id in _near_ids(at,.45):
		if covered: graph.set_point_weight_scale(int(id),.62)
		return int(id)
	var id := next_id
	next_id += 1
	graph.add_point(id,at,.62 if covered else 1.0)
	var key := _cell(at)
	if not cells.has(key): cells[key] = []
	cells[key].append(id)
	return id

func _run(a: Vector3,b: Vector3,covered: bool) -> void:
	var count := maxi(1,ceili(a.distance_to(b)/2.1))
	for i in range(count+1):
		_add(a.lerp(b,float(i)/float(count)),covered)

func _build() -> void:
	# Start from the actual traversable portal strips created by CubaWorld.
	for strip in world.monte_walkways:
		_run(strip.a,strip.b,true)
		var door := _add(strip.door,true)
		if door>0: destinations.append({"id":door,"kind":String(strip.kind)})
	# Connect the covered arcade to the exterior sidewalks of Monte.
	for edge in world.geography.roads:
		if not world._is_monte_edge(edge): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		for side in [-1.0,1.0]:
			var off := right*float(side)*(float(edge.width)*.5+.71)
			var count := maxi(1,ceili(a.distance_to(b)/2.2))
			for i in range(count+1):
				var p := a.lerp(b,float(i)/float(count))+off
				if not world.street_geometry.point_on_road(p): _add(p,false)
	if world.home_root!=null:
		var home := world.home_root
		_run(home.to_global(Vector3(-3.3,0,2.75)),home.to_global(Vector3(3.3,0,2.75)),true)
		var home_id := _add(home.to_global(Vector3(1.25,0,2.65)),true)
		if home_id>0: destinations.append({"id":home_id,"kind":"shop"})
	for id in graph.get_point_ids():
		var p := graph.get_point_position(id)
		for other in _near_ids(p,3.8):
			if int(other)<=id: continue
			var q := graph.get_point_position(int(other))
			# Long connections over traffic lanes are not shortcuts.
			var middle := p.lerp(q,.5)
			if world.street_geometry.point_on_road(middle) and p.distance_to(q)>3.1: continue
			if _clear(p,q): graph.connect_points(id,int(other),true)
	# Bridge gaps at small side streets, only along unobstructed routes.
	for id in graph.get_point_ids():
		if graph.get_point_connections(id).size()>1: continue
		var p := graph.get_point_position(id)
		for other in _near_ids(p,7.0):
			if int(other)==id or graph.are_points_connected(id,int(other)): continue
			var q := graph.get_point_position(int(other))
			if _clear(p,q):
				graph.connect_points(id,int(other),true)
				break
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
	print("Monte: ",graph.get_point_count()," pedestrian waypoints, ",destinations.size()," destinations.")

func _nearest(p: Vector3,radius: float) -> int:
	var best := radius
	var found := -1
	for id in _near_ids(p,radius):
		if graph.get_point_connections(int(id)).is_empty(): continue
		var dist := graph.get_point_position(int(id)).distance_to(p)
		if dist<best:
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
	for i in range(mini(nearby.size(),20)):
		var dest: Dictionary = nearby[i]
		var path := graph.get_point_path(start,int(dest.id))
		if path.size()<2: continue
		agent.path = path
		agent.index = 0
		agent.destination = dest
		agent.pause = 0.0
		return true
	var neighbors := graph.get_point_connections(start)
	if neighbors.is_empty(): return false
	var end := int(neighbors[randi_range(0,neighbors.size()-1)])
	agent.path = graph.get_point_path(start,end)
	agent.index = 0
	agent.destination = {"id":end,"kind":"walk"}
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
	walkers.append(agent)
	return true

func _populate() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera==null: return
	var at := camera.global_position
	for i in range(walkers.size()-1,-1,-1):
		var person: Person = walkers[i].node
		if person.global_position.distance_to(at)>190.0:
			person.queue_free()
			walkers.remove_at(i)
	var candidates := _near_ids(at,100.0)
	candidates.shuffle()
	var added := 0
	for id in candidates:
		if walkers.size()>=MAX_WALKERS or added>=6: break
		if graph.get_point_connections(int(id)).is_empty(): continue
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
			walkers.append(agent)
			added += 1
		else:
			person.queue_free()

func tick(delta: float) -> void:
	if not initialized:
		initialized = true
		_build()
		_populate()
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
		person.visible = camera==null or person.global_position.distance_squared_to(camera.global_position)<14400.0
		if float(agent.pause)>0.0:
			agent.pause = maxf(0.0,float(agent.pause)-dt)
			person.animate(dt,false)
			if float(agent.pause)<=0.0: _choose_route(agent)
			continue
		var path: PackedVector3Array = agent.path
		var index := int(agent.index)
		if index>=path.size():
			var dest: Dictionary = agent.destination
			if String(dest.get("kind",""))=="bus" and buses!=null:
				if buses.join_stop(dest.stop,person):
					walkers.remove_at(i)
					continue
			# Visit a facade/shop, wait as if shopping, then walk onward.
			agent.pause = 3.0+float(posmod(person.style_id,8)) if String(dest.get("kind","")) in ["shop","home"] else .5
			continue
		var p: Vector3 = path[index]
		if person.walk_to(p,dt,float(agent.speed)):
			agent.index = index+1
