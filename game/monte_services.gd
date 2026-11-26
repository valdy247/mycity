extends Node3D
const World = preload("res://cuba_world.gd")
const Planner = preload("res://urban_bus_routes.gd")
const Person = preload("res://street_person.gd")
const Bypass = preload("res://traffic_bypass.gd")
var world: World
var planner := Planner.new()
var anchor := Vector3.ZERO
var avoid: Array = []
var bus_berths: Array = []
var sites: Array = []
var vehicles: Array = []
var civilian_route: Array = []
var initialized := false
var player: CharacterBody3D
var camera: Camera3D
var player_bag: Node3D
var player_site: Dictionary = {}
var helped := 0
var notice := ""
var notice_time := 0.0
var mats: Dictionary = {}
var mesh := BoxMesh.new()
var bag_mesh := SphereMesh.new()
var wheel_mesh := CylinderMesh.new()

func setup(city: World,home: Vector3,occupied: Array,actor: CharacterBody3D,view: Camera3D,stops: Array = []) -> void:
	player = actor
	camera = view
	world = city
	anchor = home
	avoid = occupied.duplicate()
	bus_berths = stops.duplicate()
	mesh.size = Vector3.ONE
	bag_mesh.radius = .5
	bag_mesh.height = 1.0
	bag_mesh.radial_segments = 8
	bag_mesh.rings = 4
	wheel_mesh.top_radius = .5
	wheel_mesh.bottom_radius = .5
	wheel_mesh.height = 1.0
	wheel_mesh.radial_segments = 12

func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not mats.has(key):
		var value := StandardMaterial3D.new()
		value.albedo_color = color
		value.roughness = .88
		mats[key] = value
	return mats[key] as StandardMaterial3D

func _part(root: Node3D,p: Vector3,size_value: Vector3,color: Color,primitive: Mesh = null) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh if primitive==null else primitive
	node.material_override = _mat(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(node)
	node.position = p
	node.scale = size_value
	return node

func _free_box(p: Vector3,d: Vector3,size_value: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = size_value
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p+Vector3.UP*(size_value.y*.5+.09))
	query.collision_mask = 1|4|8|16
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func _new_site(p: Vector3,d: Vector3,width: float,edge: Dictionary) -> Dictionary:
	var right := Vector3(-d.z,0,d.x)
	var desired := p-d*6.5+right*world.geography.lane_distance(edge,2.3,true)
	var parking: Vector3 = world.street_geometry.safe_stop_on_edge(edge.a,edge.b,desired,6.2,2.3)
	var curb := p+(parking-desired)+right*(width*.5+.43)
	if world.street_geometry.point_on_road(curb): return {}
	if not _free_box(curb,d,Vector3(.80,1.05,2.40)): return {}
	if not Bypass._on_road(world.street_geometry,parking,d,2.3,6.2): return {}
	if not world.street_geometry.intersection_clear_for_stop(parking,6.2,2.3): return {}
	if curb.distance_to(anchor)<24.0: return {}
	for stop in bus_berths:
		var berth: Vector3 = stop.position
		if berth.distance_to(parking)<17.0 or berth.distance_to(curb)<12.0: return {}
	for previous in sites:
		var old: Vector3 = previous.curb
		if old.distance_to(curb)<65.0: return {}
	var root := StaticBody3D.new()
	root.collision_layer = 1
	root.collision_mask = 0
	add_child(root)
	root.position = curb+Vector3.UP*.07
	root.rotation.y = atan2(d.x,d.z)
	for z in [-.65,.65]:
		_part(root,Vector3(0,.44,float(z)),Vector3(.65,.82,1.0),Color("#2f6389"))
		_part(root,Vector3(0,.87,float(z)),Vector3(.72,.09,1.06),Color("#344d59"))
		_part(root,Vector3(-.35,.20,float(z)),Vector3(.07,.19,.70),Color("#252d31"))
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(.65,.88,1.0)
		collider.shape = shape
		root.add_child(collider)
		collider.position = Vector3(0,.44,float(z))
	var site := {"root":root,"curb":curb+Vector3.UP*.07,"parking":parking,"direction":d,"bags":[],"refill":0.0,"large":sites.size()%2==1 and width>=6.5,"width":width,"collected":0}
	sites.append(site)
	_fill(site)
	return site

func _fill(site: Dictionary) -> void:
	var root: Node3D = site.root
	var bags: Array = site.bags
	var large := bool(site.large)
	var count := 26 if large else 13
	for i in range(count):
		var p := Vector3.ZERO
		if i<6:
			p = Vector3(.02,.99+float(i%2)*.16,-.93+floorf(float(i)/2.0)*.57)
		else:
			# Local +X points TOWARD the road. Keep the overflow within
			# the bins' curbside footprint; stack higher instead of wider.
			var slot := i-6
			p = Vector3(-.16+float(slot%2)*.29,1.18+float(floori(float(slot)/8.0))*.39,-.91+float(floori(float(slot%8)/2.0))*.59)
		# The whole bag, including its collision sphere, must clear asphalt.
		var safe := true
		for x in [-.28,.28]:
			for z in [-.28,.28]:
				if world.street_geometry.point_on_road(root.to_global(p+Vector3(float(x),0,float(z)))):
					safe = false
		if not safe: continue
		var bag := StaticBody3D.new()
		bag.collision_layer = 1
		bag.collision_mask = 0
		root.add_child(bag)
		bag.position = p
		bag.rotation.y = float(i)*.86
		var colors: Array[Color] = [Color("#353935"),Color("#ccc5ac"),Color("#8a806b"),Color("#d5d0c7"),Color("#5e6c4d")]
		_part(bag,Vector3.ZERO,Vector3(.52,.47,.49),colors[i%colors.size()],bag_mesh)
		if i>=6:
			var collision := CollisionShape3D.new()
			var shape := SphereShape3D.new()
			shape.radius = .25
			collision.shape = shape
			bag.add_child(collision)
		bags.append(bag)
	site.refill = 0.0
	site.collected = 0

# Furniture joins the same collection queue as municipal refuse.
func add_discarded_furniture(site: Dictionary,id: String,size_value: Vector3,color: Color) -> bool:
	if site.is_empty() or not sites.has(site): return false
	var root: Node3D = site.root
	var object := Node3D.new()
	root.add_child(object)
	object.position = Vector3(-.05,1.25,-.65)
	_part(object,Vector3.ZERO,Vector3(minf(size_value.x,1.35),minf(size_value.y,.80),minf(size_value.z,.65)),color)
	object.set_meta("discarded_furniture",id)
	site.bags.append(object)
	if float(site.refill)>0.0: site.refill = 0.0
	return true

func _remove_bag(bag: Node3D) -> void:
	if bag is StaticBody3D:
		(bag as StaticBody3D).collision_layer = 0
	bag.queue_free()

func _active_truck() -> Dictionary:
	for vehicle in vehicles:
		if bool(vehicle.truck) and not vehicle.site.is_empty():
			return vehicle
	return {}

func action_text(at: Vector3) -> String:
	if player_bag!=null:
		var vehicle := _active_truck()
		if not vehicle.is_empty() and vehicle.site==player_site:
			var body: CharacterBody3D = vehicle.body
			if at.distance_to(body.to_global(Vector3(-1.40,.9,-2.8)))<2.5:
				return "[E] Echar bolsa en el camión"
		return "Lleva la bolsa a la parte trasera del camión"
	var vehicle := _active_truck()
	if vehicle.is_empty(): return ""
	var site: Dictionary = vehicle.site
	for bag in site.bags:
		if is_instance_valid(bag) and at.distance_to(bag.global_position)<2.3:
			return "[E] Ayudar a recoger basura"
	return ""

func interact(at: Vector3) -> bool:
	var action := action_text(at)
	if not action.begins_with("[E]"): return false
	if player_bag!=null:
		player_bag.queue_free()
		player_bag = null
		player_site = {}
		helped += 1
		notice = "Bolsa recogida · Has ayudado con %d bolsas" % helped
		notice_time = 4.0
		return true
	var vehicle := _active_truck()
	if vehicle.is_empty(): return false
	var site: Dictionary = vehicle.site
	var bags: Array = site.bags
	var closest := -1
	var best := 2.3
	for i in range(bags.size()):
		var bag: Node3D = bags[i]
		var dist := at.distance_to(bag.global_position)
		if dist<best:
			best = dist
			closest = i
	if closest<0: return false
	var bag: Node3D = bags.pop_at(closest)
	_remove_bag(bag)
	player_site = site
	player_bag = Node3D.new()
	camera.add_child(player_bag)
	player_bag.position = Vector3(.30,-.37,-.85)
	_part(player_bag,Vector3.ZERO,Vector3(.44,.44,.40),Color("#353935"),bag_mesh)
	return true

func return_player_bag() -> void:
	if player_bag==null: return
	if not player_site.is_empty():
		var root: Node3D = player_site.root
		var bag := StaticBody3D.new()
		bag.collision_layer = 1
		bag.collision_mask = 0
		root.add_child(bag)
		bag.position = Vector3(0,1.35,-.65)
		_part(bag,Vector3.ZERO,Vector3(.5,.45,.5),Color("#353935"),bag_mesh)
		var bags: Array = player_site.bags
		bags.append(bag)
	player_bag.queue_free()
	player_bag = null
	player_site = {}


func _body(truck: bool,index: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Camion_Comunales" if truck else "Auto_Monte_"+str(index)
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.collision_layer = 1
	body.collision_mask = 1|4|8
	add_child(body)
	body.add_to_group("autonomous_traffic")
	var paint: Color = Color("#537c72") if truck else [Color("#a47155"),Color("#6990a1"),Color("#a7a19a")][index%3]
	var black := Color("#303538")
	var glass := Color("#587681")
	var width := 2.3 if truck else 1.83
	var length := 6.2 if truck else 4.25
	if truck:
		_part(body,Vector3(0,.68,0),Vector3(2.20,.40,6.1),black)
		_part(body,Vector3(0,1.50,2.0),Vector3(2.22,1.75,2.10),Color("#d4d4be"))
		_part(body,Vector3(0,1.92,3.065),Vector3(1.95,.71,.045),glass)
		for side in [-1.0,1.0]:
			_part(body,Vector3(float(side)*1.125,1.92,2.13),Vector3(.04,.74,1.25),glass)
		_part(body,Vector3(0,1.72,-.75),Vector3(2.28,1.88,3.3),paint)
		_part(body,Vector3(0,1.34,-2.68),Vector3(2.25,.95,.62),paint)
		_part(body,Vector3(0,1.64,-3.02),Vector3(1.70,.66,.07),black)
		_part(body,Vector3(0,.84,-3.12),Vector3(2.20,.16,.13),Color("#c9b87e"))
		var sign_label := Label3D.new()
		sign_label.text = "COMUNALES"
		sign_label.font_size = 38
		sign_label.pixel_size = .0035
		sign_label.rotation.y = -PI*.5
		sign_label.position = Vector3(-1.16,1.91,-.85)
		body.add_child(sign_label)
	else:
		# Keep the existing physics envelope. Most cars resemble American
		# 1940s/1950s sedans, with three distinct silhouettes and two-tone paint.
		var classic := index%5!=4
		var chrome := Color("#bfc5c5")
		if classic:
			var colors := [Color("#487f79"),Color("#9b4e46"),Color("#587a9d"),Color("#bd9a56"),Color("#737c65"),Color("#a28d91")]
			paint = colors[posmod(index,colors.size())]
			var roof := paint.lightened(.32) if index%3==0 else Color("#e4dfce")
			var style := index%3
			_part(body,Vector3(0,.58,0),Vector3(1.76,.48,4.08),paint)
			_part(body,Vector3(0,.85,1.24),Vector3(1.48,.26,1.42),paint)
			_part(body,Vector3(0,.79,-1.38),Vector3(1.48,.26,1.25),paint)
			_part(body,Vector3(0,1.16,-.15),Vector3(1.46,.49,1.80),glass)
			_part(body,Vector3(0,1.44,-.19),Vector3(1.52,.10,1.87),roof)
			_part(body,Vector3(0,.65,2.09),Vector3(1.74,.12,.07),chrome)
			_part(body,Vector3(0,.79,2.05),Vector3(1.21,.19,.07),black)
			for stripe in range(5):
				_part(body,Vector3(0,.72+float(stripe)*.035,2.10),Vector3(1.13,.012,.025),chrome)
			_part(body,Vector3(0,.62,-2.09),Vector3(1.74,.12,.07),chrome)
			for side in [-1.0,1.0]:
				var x := float(side)
				for z in [-1.37,1.37]:
					_part(body,Vector3(x*.77,.76,float(z)),Vector3(.27,.28,1.17),paint)
				for z in [-.99,-.18,.68]:
					_part(body,Vector3(x*.74,1.16,float(z)),Vector3(.055,.49,.09),roof)
				_part(body,Vector3(x*.892,.77,0),Vector3(.025,.055,3.85),chrome)
				_part(body,Vector3(x*.895,.91,-.19),Vector3(.025,.04,.19),chrome)
				var light := _part(body,Vector3(x*.70,.85,2.075),Vector3(.25,.06,.25),Color("#f0e6c7"),wheel_mesh)
				light.rotation.x = PI*.5
				_part(body,Vector3(x*.72,.82,-2.075),Vector3(.16,.17,.045),Color("#a42e2d"))
				if style==1:
					var fin := _part(body,Vector3(x*.78,.96,-1.63),Vector3(.13,.24,.76),paint)
					fin.rotation.x = -.20
				elif style==2:
					_part(body,Vector3(x*.77,.89,-1.45),Vector3(.17,.10,1.13),roof)
		else:
			_part(body,Vector3(0,.66,0),Vector3(width,.67,length),paint)
			_part(body,Vector3(0,1.12,-.18),Vector3(1.55,.58,1.9),glass)
			_part(body,Vector3(0,1.45,-.19),Vector3(1.62,.11,1.85),paint.lightened(.25))
			for side in [-1.0,1.0]:
				_part(body,Vector3(float(side)*.76,1.12,-.14),Vector3(.065,.56,.12),paint)
				_part(body,Vector3(float(side)*.65,.79,length*.5+.03),Vector3(.25,.19,.05),Color("#f0e8bd"))
				_part(body,Vector3(float(side)*.65,.79,-length*.5-.03),Vector3(.22,.17,.05),Color("#af4940"))
	var radius := .45 if truck else .33
	for side in [-1.0,1.0]:
		for z in ([-2.05,1.95] if truck else [-1.35,1.35]):
			var tire := _part(body,Vector3(float(side)*(width*.5-.13),radius,float(z)),Vector3(radius*2.0,.28,radius*2.0),black,wheel_mesh)
			tire.rotation.z = PI*.5
			var rim := _part(body,Vector3(float(side)*(width*.5+.025),radius,float(z)),Vector3(radius*1.1,.045,radius*1.1),Color("#9c9d98"),wheel_mesh)
			rim.rotation.z = PI*.5
			if not truck and index%5!=4:
				var whitewall := _part(body,Vector3(float(side)*(width*.5+.013),radius,float(z)),Vector3(radius*1.55,.024,radius*1.55),Color("#e5e0cb"),wheel_mesh)
				whitewall.rotation.z = PI*.5
				var hub := _part(body,Vector3(float(side)*(width*.5+.04),radius,float(z)),Vector3(radius*.90,.035,radius*.90),Color("#bfc5c5"),wheel_mesh)
				hub.rotation.z = PI*.5
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width,2.7 if truck else 1.5,length)
	collision.shape = shape
	body.add_child(collision)
	collision.position.y = shape.size.y*.5+.06
	return body

# Add intermediate points for distributed spawning on long blocks.
func _civilian_route(raw: Array) -> Array:
	var result: Array = []
	for i in range(raw.size()):
		var p: Vector3 = raw[i].p
		var q: Vector3 = raw[(i+1)%raw.size()].p
		result.append(raw[i])
		var count := ceili(p.distance_to(q)/13.0)
		for j in range(1,count):
			var at := p.lerp(q,float(j)/float(count))
			if Bypass._on_road(world.street_geometry,at,(q-p).normalized(),1.83,4.25):
				result.append({"p":at})
	return result

func _make_vehicle(route: Array,truck: bool,index: int) -> void:
	var start := -1
	if route.size()<2: return
	var preferred := 0 if truck else floori(float(route.size())*float(index%8)/8.0)
	for step in range(route.size()):
		var i := (preferred+step)%route.size()
		var item: Dictionary = route[i]
		if truck and not item.has("stop"): continue
		var p: Vector3 = item.p
		var clear := true
		for v in avoid:
			var other: Vector3 = v
			if other.distance_to(p)<21.0:
				clear = false
				break
		if not clear: continue
		var next: Vector3 = route[(i+1)%route.size()].p
		var d := (next-p).normalized()
		if item.has("stop"): d = item.stop.direction
		if not truck and not world.street_geometry.intersection_clear_for_stop(p,4.25,1.83): continue
		if not Bypass._on_road(world.street_geometry,p,d,2.3 if truck else 1.83,6.2 if truck else 4.25): continue
		if d.length_squared()<.1: continue
		if not _free_box(p,d,Vector3(2.3 if truck else 1.83,2.7 if truck else 1.5,6.2 if truck else 4.25)): continue
		start = i
		break
	if start<0: return
	var body := _body(truck,index)
	var item: Dictionary = route[start]
	var p: Vector3 = item.p
	var following: Vector3 = route[(start+1)%route.size()].p
	var direction := (following-p).normalized()
	if item.has("stop"): direction = item.stop.direction
	body.position = p+Vector3.UP*.04
	body.rotation.y = atan2(direction.x,direction.z)
	avoid.append(p)
	var crew: Array = []
	if truck:
		for i in range(2):
			var person := Person.new()
			add_child(person)
			person.setup(700+i,true)
			person.hide()
			crew.append({"node":person,"state":"idle","pause":0.0})
	vehicles.append({"body":body,"route":route,"index":start if truck else (start+1)%route.size(),"speed":0.0,"truck":truck,"crew":crew,"site":{},"blocked":0.0,"cooldown":0.0,"detour":[],"detour_index":0,"resume":0})

func _initialize() -> void:
	planner.setup(world.geography)
	var ids := planner.plan("MONTE",anchor)
	if ids.size()<5: return
	var route: Array = []
	var car_route: Array = []
	for i in range(ids.size()-1):
		var edge: Dictionary = planner.edges.get(ids[i]+":"+ids[i+1],{})
		if edge.is_empty(): continue
		var a: Vector3 = world.geography.points[ids[i]]
		var b: Vector3 = world.geography.points[ids[i+1]]
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		var width := float(edge.width)
		var lane := right*world.geography.lane_distance(edge,2.3,int(edge.get("lanes_per_direction",1))==2)
		var passing_lane := right*world.geography.lane_distance(edge,1.83)
		var length := a.distance_to(b)
		if length>8.0:
			route.append({"p":a+d*3.0+lane})
			car_route.append({"p":a+d*3.0+passing_lane})
		if sites.size()<5 and world._is_monte_edge(edge) and width>=6.5 and length>25.0:
			var near_corner := a+d*clampf(length*.70,17.0,length-5.0)
			var site := _new_site(near_corner,d,width,edge)
			if not site.is_empty():
				var park: Vector3 = site.parking
				route.append({"p":park,"stop":site})
		route.append({"p":b+lane})
		car_route.append({"p":b+passing_lane})
	if route.size()<5: return
	if not sites.is_empty(): _make_vehicle(route,true,0)
	car_route = _civilian_route(car_route)
	civilian_route = car_route
	for i in range(8):
		_make_vehicle(car_route,false,i)
	print("Monte: ",sites.size()," garbage collection points; ",vehicles.size()," municipal/ordinary vehicles.")

func _begin_collection(vehicle: Dictionary,site: Dictionary) -> void:
	vehicle.site = site
	vehicle["collection_wait"] = 0.0
	vehicle.speed = 0.0
	var body: CharacterBody3D = vehicle.body
	body.velocity = Vector3.ZERO
	var direction: Vector3 = site.direction
	body.rotation.y = atan2(direction.x,direction.z)
	var crew: Array = vehicle.crew
	for i in range(crew.size()):
		var worker: Dictionary = crew[i]
		var person: Person = worker.node
		person.global_position = body.to_global(Vector3(-1.38,0,1.90-float(i)*.75))
		person.show()
		worker.state = "to_bin"

func _collect(vehicle: Dictionary,delta: float) -> void:
	var site: Dictionary = vehicle.site
	var body: CharacterBody3D = vehicle.body
	var crew: Array = vehicle.crew
	var bags: Array = site.bags
	var direction: Vector3 = site.direction
	var curb: Vector3 = site.curb
	var done := true
	for i in range(crew.size()):
		var worker: Dictionary = crew[i]
		var person: Person = worker.node
		var right := Vector3(-direction.z,0,direction.x)
		var pickup := curb-right*.65+direction*(-.95+float(i)*1.90)
		var hopper := body.to_global(Vector3(-1.38,0,-2.7-float(i)*.23))
		var cab := body.to_global(Vector3(-1.38,0,1.9-float(i)*.75))
		match String(worker.state):
			"to_bin":
				done = false
				if bags.is_empty():
					worker.state = "return"
				elif person.walk_to(pickup,delta,1.65):
					var bag: Node3D = bags.pop_back()
					_remove_bag(bag)
					person.set_bag(true)
					worker.state = "to_hopper"
			"to_hopper":
				done = false
				if person.walk_to(hopper,delta,1.65):
					person.set_bag(false)
					worker.state = "to_bin" if not bags.is_empty() else "return"
			"idle":
				if not bags.is_empty():
					person.global_position = cab
					person.show()
					worker.state = "to_bin"
					done = false
			"return":
				done = false
				if person.walk_to(cab,delta,1.7):
					person.hide()
					worker.state = "idle"
	# A player holding the last bag cannot hold the route indefinitely.
	if done and player_site==site and bags.is_empty():
		vehicle.collection_wait = float(vehicle.get("collection_wait",0.0))+delta
		if float(vehicle.collection_wait)>25.0:
			return_player_bag()
			notice = "El camión debe continuar; la bolsa volvió al basurero."
			notice_time = 4.0
			vehicle.collection_wait = 0.0
	else:
		vehicle.collection_wait = 0.0
	if done and player_site!=site and bags.is_empty():
		site.refill = 170.0
		vehicle.site = {}
		var route: Array = vehicle.route
		vehicle.index = (int(vehicle.index)+1)%route.size()

# Short checked recovery arcs for tight corners and curb approaches.
# Preserve the pending collection stop and never teleport the truck.
func _local_recovery(body: CharacterBody3D,target: Vector3,width: float,length: float,height: float) -> Array:
	var origin := body.global_position
	var heading := body.global_transform.basis.z.normalized()
	var left := Vector3(heading.z,0,-heading.x)
	var shape := BoxShape3D.new()
	shape.size = Vector3(width+.06,height,length+.06)
	var space := get_world_3d().direct_space_state
	for advance in [4.0,6.0,8.0,10.0]:
		for shift in [1.5,2.3,3.0,-1.5,-2.3,0.0]:
			var goal := origin+heading*float(advance)+left*float(shift)
			if goal.distance_to(target)>origin.distance_to(target)+1.0: continue
			var points: Array = []
			var previous := origin
			var valid := true
			var steps := ceili(float(advance)/.55)
			for j in range(1,steps+1):
				var t := float(j)/float(steps)
				var p := origin+heading*float(advance)*t+left*float(shift)*smoothstep(0.0,1.0,t)
				var d := (p-previous).normalized()
				if not Bypass._on_road(world.street_geometry,p,d,width,length):
					valid = false
					break
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = shape
				q.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p+Vector3.UP*(height*.5+.08))
				q.collision_mask = 1|4|8
				q.exclude = [body.get_rid()]
				if not space.intersect_shape(q,1).is_empty():
					valid = false
					break
				q.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),previous+Vector3.UP*(height*.5+.08))
				q.motion = p-previous
				var sweep := space.cast_motion(q)
				if sweep.size()<2 or sweep[0]<.999:
					valid = false
					break
				points.append({"p":p,"bypass":true})
				previous = p
			if valid and not points.is_empty(): return points
	return []

func _drive(vehicle: Dictionary,delta: float) -> void:
	var body: CharacterBody3D = vehicle.body
	body.set_meta("traffic_priority",6.2 if bool(vehicle.truck) else 4.25)
	body.set_meta("traffic_servicing",not vehicle.site.is_empty())
	if not vehicle.site.is_empty():
		_collect(vehicle,delta)
		return
	var original: Array = vehicle.route
	var detour: Array = vehicle.detour
	var active := not detour.is_empty()
	var route: Array = detour if active else original
	var index := int(vehicle.detour_index) if active else int(vehicle.index)
	var item: Dictionary = route[index]
	var target: Vector3 = item.p
	target.y = body.position.y
	var diff := target-body.position
	var distance := diff.length()
	if distance<.30:
		vehicle.stalled = 0.0
		vehicle.backed_up = 0.0
		body.velocity = Vector3.ZERO
		if active:
			vehicle.detour_index = index+1
			if int(vehicle.detour_index)>=detour.size():
				vehicle.detour = []
				vehicle.index = int(vehicle.resume)
		elif bool(vehicle.truck) and item.has("stop") and not item.stop.bags.is_empty():
			_begin_collection(vehicle,item.stop)
		else:
			vehicle.index = (index+1)%route.size()
		return
	var direction := diff.normalized()
	var limit := 6.5 if bool(vehicle.truck) else 10.5
	var speed := minf(limit,maxf(.8,sqrt(2.0*4.0*distance)))
	var next: Vector3 = route[(index+1)%route.size()].p
	var next_dir := (next-target).normalized()
	if direction.dot(next_dir)<.85: speed = minf(speed,maxf(1.0,distance*1.0))
	if active: speed = minf(speed,3.4)
	var half := 3.1 if bool(vehicle.truck) else 2.125
	var width := 2.3 if bool(vehicle.truck) else 1.83
	var height := 2.8 if bool(vehicle.truck) else 1.65
	var gap := .65
	var reach := minf(maxf(5.0,float(vehicle.speed)*float(vehicle.speed)/12.0+3.0),distance+gap)
	var free := Bypass.clear_distance(body,direction,reach,width,half*2.0,height)
	var blocked := free<reach-.05
	var safe_speed := sqrt(12.0*maxf(0.0,free-gap)) if blocked else speed
	speed = minf(speed,safe_speed)
	vehicle.cooldown = maxf(0.0,float(vehicle.cooldown)-delta)
	var stalled := float(vehicle.get("stalled",0.0))
	var junction_limit := Bypass.junction_gate(vehicle,body,world.street_geometry,route,index,not active,width,half*2.0,height,delta,original if active else [],int(vehicle.resume))
	speed = Bypass.junction_speed(speed,junction_limit,6.0)
	if Bypass.cooperate(vehicle,body,world.street_geometry,width,half*2.0,height,delta,stalled,target): return
	if bool(vehicle.get("cooperative_rejoin",false)):
		vehicle.cooperative_rejoin = false
		if active: vehicle.index = int(vehicle.resume)
		vehicle.detour = []
		if not bool(vehicle.truck): vehicle.index = Bypass.rejoin_index(body,original,int(vehicle.index),world.street_geometry,width,half*2.0,height)
		return
	if not bool(body.get_meta("junction_guard",false)) and float(vehicle.get("retreat_remaining",0.0))<=0.0 and (stalled>.8 or (not active and Bypass.early_lane_pass(body,world.street_geometry,blocked,free))) and float(vehicle.cooldown)<=0.0:
		vehicle.cooldown = 1.6
		if active:
			# An interrupted detour is not permanent. Replan from here.
			vehicle.detour = []
			vehicle.index = int(vehicle.resume)
			return
		var choice := Bypass.recover(body,original,index,world.street_geometry,width,half*2.0,world.geography.signal_nodes,height)
		if not choice.is_empty():
			vehicle.detour = choice.path
			vehicle.detour_index = 0
			vehicle.resume = int(choice.resume)
			vehicle.stalled = 0.0
			return
		if stalled>2.5 and world.street_geometry.four_lane_at(body.global_position,body.global_transform.basis.z).is_empty():
			var recovery := _local_recovery(body,target,width,half*2.0,height)
			if not recovery.is_empty():
				vehicle.detour = recovery
				vehicle.detour_index = 0
				vehicle.resume = index
				vehicle.stalled = 0.0
				return
	if not active and Bypass.retreat(vehicle,body,world.street_geometry,width,half*2.0,delta,stalled>3.0 and float(vehicle.speed)<.12):
		vehicle.speed = 0.0
		return
	vehicle.speed = move_toward(float(vehicle.speed),speed,delta*(7.0 if speed<float(vehicle.speed) else 3.5))
	var angle := lerp_angle(body.rotation.y,atan2(direction.x,direction.z),1.0-exp(-delta*4.5))
	var advance := Bypass.junction_advance(minf(float(vehicle.speed)*delta,distance),junction_limit)
	if blocked: advance = minf(advance,maxf(0.0,free-gap))
	var previous := body.global_position
	if advance>.0001:
		if not Bypass.safe_step(body,direction,advance,angle,delta):
			vehicle.speed = 0.0
	else:
		if junction_limit<0.0: Bypass.align_if_clear(body,angle)
		body.velocity = Vector3.ZERO
		vehicle.speed = 0.0
	if body.global_position.distance_to(previous)<.10*delta:
		vehicle.stalled = stalled+delta
	else:
		vehicle.stalled = maxf(0.0,stalled-delta*2.0)
		if not blocked: vehicle.backed_up = 0.0

func tick(delta: float) -> void:
	notice_time = maxf(0.0,notice_time-delta)
	if not initialized:
		initialized = true
		_initialize()
	for vehicle in vehicles:
		if bool(vehicle.get("incident_hold",false)): continue
		_drive(vehicle,delta)
	for site in sites:
		if float(site.refill)>0.0:
			site.refill = maxf(0.0,float(site.refill)-delta)
			if float(site.refill)<=0.0: _fill(site)
