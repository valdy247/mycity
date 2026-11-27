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
var profiles: Dictionary = {}
var resident_clock := 480.0
var home_destinations: Array = []
var commerce_destinations: Array = []
var life
const MAX_PROFILES := 180

func setup(city: World,bus_service: UrbanBuses,city_life = null) -> void:
	life = city_life
	if life!=null: resident_clock = float(life.state.minutes)
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
	# Add the actual clear park paths, not an artificial indoor doorway.
	for strip in world.park_walkways:
		_run(strip.a,strip.b,SIDEWALK_COST)
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
	for site in world.commerce_sites:
		var entrance: Vector3 = site.entrance
		var nearest := _nearest(entrance,7.0)
		if nearest<0: continue
		var link := graph.get_point_position(nearest)
		if not world.pedestrian_segment_clear(entrance,link): continue
		var id := _add(entrance,SIDEWALK_COST,.20)
		if id<0: continue
		if id!=nearest and not graph.are_points_connected(id,nearest): graph.connect_points(id,nearest,true)
		var destination := {"id":id,"kind":"shop","site":String(site.id),"business_kind":String(site.kind)}
		commerce_destinations.append(destination)
		destinations.append(destination)
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
	for dest in destinations:
		if String(dest.kind)=="home": home_destinations.append(dest)
	_restore_profiles()
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
# Temporarily transfer a real outdoor pedestrian to the stall controller.
# Keep their profile, appearance and world position. No new NPC allocation.
func take_street_customer(stand_at: Vector3,frontage: Basis,recent: Array) -> Dictionary:
	if not initialized: return {}
	var options: Array = []
	for i in range(walkers.size()):
		var agent: Dictionary = walkers[i]
		var person: Person = agent.node
		if not is_instance_valid(person) or not person.is_visible_in_tree() or person.style_id in recent: continue
		if person.has_meta("incident_role") or person.has_meta("conversation_until") or bool(agent.get("indoors",false)) or agent.has("yield_target") or float(agent.pause)>0.0: continue
		var at := person.global_position
		var distance := at.distance_to(stand_at)
		if distance<5.0 or distance>38.0 or world.street_geometry.point_on_road(at): continue
		# Exclude the player's doorstep and other door thresholds.
		if not world.garage_home_site.is_empty() and at.distance_to(world.garage_home_site.door)<5.0: continue
		var on_door := false
		for dest in destinations:
			if not bool(dest.get("door",false)): continue
			if graph.get_point_position(int(dest.id)).distance_squared_to(at)<1.0:
				on_door = true
				break
		if not on_door: options.append({"index":i,"distance":distance})
	options.shuffle()
	for option in options.slice(0,5):
		var agent: Dictionary = walkers[int(option.index)]
		var person: Person = agent.node
		for shift in [frontage.z*.95,-frontage.z*.95,frontage.x*1.25,-frontage.x*1.25]:
			var ground := _ground(stand_at+shift)
			if ground.is_empty(): continue
			var target: Vector3 = ground.p
			if world.street_geometry.point_on_road(target): continue
			var path := route_between(person.global_position,target)
			if path.size()<2: continue
			var length := 0.0
			for i in range(1,path.size()): length += path[i-1].distance_to(path[i])
			if length>55.0: continue
			walkers.remove_at(int(option.index))
			person.remove_from_group("bus_yield_walkers")
			person.phone_idle = false
			return {"agent":agent,"path":path}
	return {}

func release_street_customer(agent: Dictionary) -> void:
	if agent.is_empty() or not is_instance_valid(agent.get("node")): return
	var person: Person = agent.node
	agent.pause = 0.0
	agent.lod_dt = 0.0
	agent.erase("yield_target")
	agent.erase("preview_index")
	agent.erase("blocked_time")
	agent.erase("people_wait")
	agent.path = PackedVector3Array()
	agent.index = 0
	if not _choose_route(agent,true): agent.pause = .5
	person.add_to_group("bus_yield_walkers")
	walkers.append(agent)

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

# Profiles stay in memory after the visual actor is streamed out.
# Homes are verified doorway destinations, not guessed coordinates.
# Save only compact JSON-compatible data, never graph objects or nodes.
# Rebind a saved home only when its position still matches the rebuilt graph.
func _restore_profiles() -> void:
	if life==null: return
	var saved: Dictionary = life.state.get("resident_profiles",{})
	var homes: Dictionary = {}
	for dest in home_destinations: homes[str(dest.id)] = dest
	var workplaces: Dictionary = {}
	for dest in commerce_destinations: workplaces[String(dest.site)] = dest
	for key in saved.keys().slice(0,MAX_PROFILES):
		var row: Dictionary = saved[key]
		var home: Dictionary = homes.get(String(row.get("home_id","")),{}).duplicate()
		if not home.is_empty():
			var p := graph.get_point_position(int(home.id))
			if absf(p.x-float(row.get("home_x",INF)))>.5 or absf(p.z-float(row.get("home_z",INF)))>.5: home = {}
		if home.is_empty(): continue
		var workplace: Dictionary = workplaces.get(String(row.get("workplace","")),{})
		var style := int(key)
		profiles[String(key)] = {"id":"resident_"+String(key),"style":style,"name":String(row.name),"home":home,"workplace":workplace,"money":maxi(0,int(row.money)),"activity":"street","job":String(row.job),"last_work":-1000.0,"last_purchase":-1000.0,"active":false}
		serial = maxi(serial,style)
	# Rewrite only successfully rebound profiles on the next normal save.
	life.state.resident_profiles = {}
	for key in profiles: _save_profile(profiles[key])

func _save_profile(profile: Dictionary) -> void:
	if life==null: return
	var key := str(int(profile.style))
	if not profiles.has(key): return
	if not life.state.has("resident_profiles"): life.state.resident_profiles = {}
	var home: Dictionary = profile.home
	if home.is_empty(): return
	var p := graph.get_point_position(int(home.id))
	var workplace: Dictionary = profile.workplace
	life.state.resident_profiles[key] = {"name":profile.name,"job":profile.job,"money":int(profile.money),"home_id":str(home.id),"home_x":p.x,"home_z":p.z,"workplace":String(workplace.get("site",""))}

func _profile_for(style: int,at: Vector3) -> Dictionary:
	var first_names: Array[String] = ["Rafael","Yunier","Carlos","Maritza","Yanelis","Lidia","Omar","Ernesto","Dailen","Marta","Luis","Alina"]
	var surnames: Array[String] = ["Pérez","García","Rodríguez","Hernández","Díaz","Martínez"]
	var key := str(style)
	if profiles.has(key): return profiles[key]
	var home: Dictionary = {}
	var best := INF
	for dest in home_destinations:
		var p := graph.get_point_position(int(dest.id))
		var distance := p.distance_squared_to(at)
		if distance<best:
			best = distance
			home = dest
	var job: String = ["comercio","servicios","oficio","estudio"][posmod(style,4)]
	var workplace: Dictionary = {}
	if not commerce_destinations.is_empty(): workplace = commerce_destinations[posmod(style,commerce_destinations.size())]
	var profile := {"id":"resident_"+key,"style":style,"name":first_names[posmod(style,first_names.size())]+" "+surnames[posmod(floori(float(style)/3.0),surnames.size())],"home":home,"workplace":workplace,"money":200+posmod(style*37,800),"activity":"street","job":job,"last_work":-1000.0,"last_purchase":-1000.0}
	if profiles.size()>=MAX_PROFILES:
		for old_key in profiles.keys():
			if not bool(profiles[old_key].get("active",false)):
				profiles.erase(old_key)
				if life!=null and life.state.has("resident_profiles"): life.state.resident_profiles.erase(old_key)
				break
	if profiles.size()<MAX_PROFILES:
		profiles[key] = profile
		_save_profile(profile)
	return profile

func _attach_profile(agent: Dictionary) -> void:
	var person: Person = agent.node
	var profile := _profile_for(person.style_id,person.global_position)
	profile.active = true
	agent.profile = profile
	person.set_meta("citizen_name",profile.name)
	person.set_meta("resident_job",profile.job)

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
	var profile: Dictionary = agent.get("profile",{})
	var hour := fmod(resident_clock,1440.0)/60.0
	if not profile.is_empty():
		var home: Dictionary = profile.home
		# In the evening favor the resident's own doorway if reachable.
		if (hour>=19.0 or hour<6.0) and not home.is_empty():
			var home_path := graph.get_point_path(start,int(home.id))
			if not home_path.is_empty():
				agent.path = home_path
				agent.index = 0
				agent.destination = home
				agent.pause = 0.0
				profile.activity = "home"
				person.social_context = "homeward"
				return true
		if hour>=7.0 and hour<17.0 and not force_non_bus:
			var workplace: Dictionary = profile.get("workplace",{})
			if not workplace.is_empty() and resident_clock-float(profile.last_work)>=180.0:
				var work_path := graph.get_point_path(start,int(workplace.id))
				if work_path.size()>=2 and origin.distance_to(graph.get_point_position(int(workplace.id)))<155.0:
					agent.path = work_path
					agent.index = 0
					agent.destination = workplace
					agent.pause = 0.0
					profile.activity = "work"
					person.social_context = "workward"
					return true
			nearby.sort_custom(func(a,b): return int(String(a.kind)=="shop")>int(String(b.kind)=="shop"))
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
		if not profile.is_empty(): profile.activity = String(dest.kind)
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
	_attach_profile(agent)
	if not _choose_route(agent,true):
		agent.profile.active = false
		return false
	person.reparent(self,true)
	person.show()
	person.add_to_group("bus_yield_walkers")
	walkers.append(agent)
	return true

func agent_has_profile(agent: Dictionary) -> bool:
	return agent.has("profile") and not agent.profile.is_empty()

func _resident_style(at: Vector3) -> int:
	# Reuse the same identity when its neighborhood streams back in.
	for key in profiles:
		var profile: Dictionary = profiles[key]
		if bool(profile.get("active",false)): continue
		var home: Dictionary = profile.home
		if home.is_empty(): continue
		if graph.get_point_position(int(home.id)).distance_squared_to(at)<1225.0:
			return int(key)
	serial += 1
	return serial

func _populate() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera==null: return
	var at := camera.global_position
	for i in range(walkers.size()-1,-1,-1):
		var person: Person = walkers[i].node
		if person.has_meta("incident_role"): continue
		if person.global_position.distance_to(at)>190.0:
			if agent_has_profile(walkers[i]): walkers[i].profile.active = false
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
		if not world.pedestrian_space_clear(null,p,1.0,false): continue
		var safe := true
		for agent in walkers:
			var other: Person = agent.node
			if other.global_position.distance_to(p)<2.1:
				safe = false
				break
		if not safe: continue
		var person := Person.new()
		add_child(person)
		var style := _resident_style(p)
		person.setup(style,false,true)
		person.global_position = p
		var agent := {"node":person,"path":PackedVector3Array(),"index":0,"destination":{},"pause":0.0,"speed":1.12+float(posmod(style,7))*.065}
		_attach_profile(agent)
		agent.speed = float(agent.speed)*person.gait
		if _choose_route(agent):
			person.add_to_group("bus_yield_walkers")
			walkers.append(agent)
			added += 1
		else:
			agent.profile.active = false
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

# Only called by the story runner when his immediate path is blocked.
# Idle/walking residents make room using their existing yield behaviour.
func yield_to_runner(runner: Person,target: Vector3) -> void:
	var origin := runner.global_position
	var direction := target-origin
	direction.y = 0.0
	if direction.length_squared()<.01: return
	direction = direction.normalized()
	var side := Vector3(-direction.z,0,direction.x)
	for agent in walkers:
		var person: Person = agent.node
		if not is_instance_valid(person) or person==runner or not person.is_visible_in_tree(): continue
		if person.has_meta("incident_role") or bool(agent.get("indoors",false)) or agent.has("yield_target"): continue
		var at := person.global_position
		var offset := at-origin
		if absf(offset.y)>1.0 or offset.dot(direction)<-.4 or offset.dot(direction)>3.5 or absf(offset.dot(side))>1.0: continue
		var moved := false
		for sign_value in [1.0,-1.0]:
			for shift in [1.25,1.8,2.3]:
				var candidate := at+side*float(sign_value)*float(shift)
				if world.street_geometry.point_on_road(candidate): continue
				var ground := _ground(candidate)
				if ground.is_empty(): continue
				var safe: Vector3 = ground.p
				if not world.pedestrian_segment_clear(at,safe) or not world.pedestrian_space_clear(person,safe,.75,false): continue
				person.remove_meta("conversation_until")
				agent.pause = 0.0
				agent.yield_target = safe
				moved = true
				break
			if moved: break

func tick(delta: float) -> void:
	# Keep monotonic elapsed time, initialized from the saved city clock.
	resident_clock += delta
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
		var distance_sq := person.global_position.distance_squared_to(camera.global_position) if camera!=null else 0.0
		person.visible = not bool(agent.get("indoors",false)) and distance_sq<14400.0
		# Far pedestrians retain their route but use fewer collision/animation
		# updates. Near the player and during incidents the full rate remains.
		agent.lod_dt = float(agent.get("lod_dt",0.0))+dt
		if distance_sq>4900.0 and float(agent.lod_dt)<.20 and not agent.has("yield_target"): continue
		var actor_dt: float = agent.lod_dt
		agent.lod_dt = 0.0
		person.phone_idle = float(agent.pause)>0.0 and not bool(agent.get("indoors",false)) and distance_sq<900.0
		if agent.has("yield_target"):
			var safe: Vector3 = agent.yield_target
			var step := person.global_position.move_toward(safe,1.8*actor_dt)
			if world.pedestrian_segment_clear(person.global_position,step) and world.pedestrian_space_clear(person,step):
				if person.walk_to(safe,actor_dt,1.8):
					agent.erase("yield_target")
					agent.pause = 6.0
			else:
				agent.erase("yield_target")
			continue
		if person.conversation_active(actor_dt): continue
		if float(agent.pause)>0.0:
			agent.pause = maxf(0.0,float(agent.pause)-actor_dt)
			person.animate(actor_dt,false)
			if float(agent.pause)<=0.0:
				if bool(agent.get("indoors",false)):
					if not world.pedestrian_segment_clear(person.global_position,person.global_position) or not world.pedestrian_space_clear(person,person.global_position,.75,false):
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
					# Keep identity reserved while the person is on a bus.
					walkers.remove_at(i)
					continue
			if agent_has_profile(agent) and dest.has("site"):
				var profile: Dictionary = agent.profile
				if String(profile.activity)=="work":
					profile.last_work = resident_clock
					profile.money = int(profile.money)+35
					_save_profile(profile)
					profile.activity = "working"
					agent.pause = 20.0
					person.social_context = "worker"
					continue
				if life!=null and String(dest.get("business_kind",""))=="cafe" and resident_clock-float(profile.last_purchase)>60.0:
					var spent: int = life.citizen_purchase(String(dest.site),int(profile.money))
					if spent>0:
						profile.money = int(profile.money)-spent
						_save_profile(profile)
						profile.last_purchase = resident_clock
						person.social_context = "shopping"
						agent.pause = 5.0
						continue
			# Simulated indoor visits are only allowed at a verified door.
			if bool(dest.get("door",false)) and person.global_position.distance_to(graph.get_point_position(int(dest.id)))<.14:
				var normal: Vector3 = dest.normal
				person.rotation.y = atan2(-normal.x,-normal.z)
				agent.indoors = true
				person.hide()
				agent.pause = 3.0+float(posmod(person.style_id,8))
				if agent_has_profile(agent) and String(agent.profile.activity)=="home": agent.pause = 25.0
			else:
				agent.pause = .5
			continue
		var p: Vector3 = path[index]
		# Recheck the live scene: walkers use scripted movement rather than
		# CharacterBody3D, so never advance into a new obstacle.
		var step := person.global_position.move_toward(p,maxf(.12,float(agent.speed)*actor_dt))
		# Always sweep the actual next step; the longer preview only needs
		# refreshing when the waypoint changes or every quarter second.
		var preview_due := int(agent.get("preview_index",-1))!=index or float(agent.get("preview_wait",0.0))<=0.0
		agent.preview_wait = float(agent.get("preview_wait",0.0))-actor_dt
		var route_clear := true
		if preview_due:
			agent.preview_index = index
			agent.preview_wait = .25
			route_clear = person.global_position.distance_to(p)<=.12 or _clear(person.global_position,p)
		if not world.pedestrian_space_clear(person,step):
			# Try a small checked sidestep, without walking through others
			# or leaving a portal for the roadway.
			var heading := (p-person.global_position).normalized()
			var side := Vector3(-heading.z,0,heading.x)
			var moved := false
			for direction in [-1.0,1.0]:
				var candidate := step+side*float(direction)*minf(.18,float(agent.speed)*actor_dt)
				if world.street_geometry.point_on_road(candidate) and not world.street_geometry.point_on_road(person.global_position): continue
				if not world.pedestrian_space_clear(person,candidate) or not world.pedestrian_segment_clear(person.global_position,candidate): continue
				person.walk_to(candidate,actor_dt,float(agent.speed))
				moved = true
				break
			if moved:
				agent.people_wait = 0.0
			else:
				person.animate(actor_dt,false)
				agent.people_wait = float(agent.get("people_wait",0.0))+actor_dt
				if float(agent.people_wait)>2.0:
					agent.people_wait = 0.0
					_choose_route(agent,true)
			continue
		agent.people_wait = 0.0
		if not world.pedestrian_segment_clear(person.global_position,step) or not route_clear:
			person.animate(actor_dt,false)
			agent["blocked_time"] = float(agent.get("blocked_time",0.0))+actor_dt
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
		if person.walk_to(p,actor_dt,float(agent.speed)):
			agent.index = index+1
