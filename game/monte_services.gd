extends Node3D
const World = preload("res://cuba_world.gd")
const Planner = preload("res://urban_bus_routes.gd")
const Person = preload("res://street_person.gd")
const Bypass = preload("res://traffic_bypass.gd")
var world: World
var planner := Planner.new()
var anchor := Vector3.ZERO
var avoid: Array = []
var sites: Array = []
var vehicles: Array = []
var initialized := false
var mats: Dictionary = {}
var mesh := BoxMesh.new()
var bag_mesh := SphereMesh.new()
var wheel_mesh := CylinderMesh.new()

func setup(city: World,home: Vector3,occupied: Array) -> void:
	world = city
	anchor = home
	avoid = occupied.duplicate()
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

func _new_site(p: Vector3,d: Vector3,width: float) -> Dictionary:
	var right := Vector3(-d.z,0,d.x)
	var curb := p+right*(width*.5+.43)
	var parking := p+right*minf(1.55,width*.5-1.45)
	if world.street_geometry.point_on_road(curb): return {}
	if not _free_box(curb,d,Vector3(.80,1.05,2.40)): return {}
	if not Bypass._on_road(world.street_geometry,parking,d,2.3,6.2): return {}
	if curb.distance_to(anchor)<24.0: return {}
	for previous in sites:
		var old: Vector3 = previous.curb
		if old.distance_to(curb)<65.0: return {}
	var root := Node3D.new()
	add_child(root)
	root.position = curb+Vector3.UP*.07
	root.rotation.y = atan2(d.x,d.z)
	for z in [-.65,.65]:
		_part(root,Vector3(0,.44,float(z)),Vector3(.65,.82,1.0),Color("#2f6389"))
		_part(root,Vector3(0,.87,float(z)),Vector3(.72,.09,1.06),Color("#344d59"))
		_part(root,Vector3(-.35,.20,float(z)),Vector3(.07,.19,.70),Color("#252d31"))
	var site := {"root":root,"curb":curb+Vector3.UP*.07,"parking":parking,"direction":d,"bags":[],"refill":0.0}
	sites.append(site)
	_fill(site)
	return site

func _fill(site: Dictionary) -> void:
	var root: Node3D = site.root
	var bags: Array = site.bags
	for i in range(7):
		var p := Vector3(-.05+float(i%2)*.15,.20+float(i/3)*.12,-1.35+float(i%3)*.36)
		if i>=3: p = Vector3(0,.98+float((i-3)%2)*.10,-.65+float(i-3)*.38)
		var bag := _part(root,p,Vector3(.38,.34,.40),[Color("#353935"),Color("#ccc5ac"),Color("#8a806b")][i%3],bag_mesh)
		bag.rotation.y = float(i)*.86
		bags.append(bag)
	site.refill = 0.0

func _body(truck: bool,index: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Camion_Comunales" if truck else "Auto_Monte_"+str(index)
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.collision_layer = 1
	body.collision_mask = 1|4
	add_child(body)
	var paint := Color("#537c72") if truck else [Color("#a47155"),Color("#6990a1"),Color("#a7a19a")][index%3]
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
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width,2.7 if truck else 1.5,length)
	collision.shape = shape
	body.add_child(collision)
	collision.position.y = shape.size.y*.5+.06
	return body

func _make_vehicle(route: Array,truck: bool,index: int) -> void:
	var start := -1
	for i in range(route.size()):
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
	for i in range(ids.size()-1):
		var edge: Dictionary = planner.edges.get(ids[i]+":"+ids[i+1],{})
		if edge.is_empty(): continue
		var a: Vector3 = world.geography.points[ids[i]]
		var b: Vector3 = world.geography.points[ids[i+1]]
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		var width := float(edge.width)
		var lane := right*minf(1.55,width*.5-1.45)
		var length := a.distance_to(b)
		if length>8.0: route.append({"p":a+d*3.0+lane})
		if sites.size()<5 and world._is_monte_edge(edge) and width>=6.5 and length>17.0:
			var near_corner := a+d*minf(length*.5,9.5)
			var site := _new_site(near_corner,d,width)
			if not site.is_empty(): route.append({"p":site.parking,"stop":site})
		route.append({"p":b+lane})
	if route.size()<5: return
	if not sites.is_empty(): _make_vehicle(route,true,0)
	var car_route: Array = []
	for item in route:
		car_route.append({"p":item.p})
	for i in range(2):
		_make_vehicle(car_route,false,i)
	print("Monte: ",sites.size()," garbage collection points; ",vehicles.size()," municipal/ordinary vehicles.")

func _begin_collection(vehicle: Dictionary,site: Dictionary) -> void:
	vehicle.site = site
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
		var pickup := curb+direction*(-.95+float(i)*1.90)
		var hopper := body.to_global(Vector3(-1.38,0,-2.7-float(i)*.23))
		var cab := body.to_global(Vector3(-1.38,0,1.9-float(i)*.75))
		match String(worker.state):
			"to_bin":
				done = false
				if bags.is_empty():
					worker.state = "return"
				elif person.walk_to(pickup,delta,1.65):
					var bag: Node3D = bags.pop_back()
					bag.queue_free()
					person.set_bag(true)
					worker.state = "to_hopper"
			"to_hopper":
				done = false
				if person.walk_to(hopper,delta,1.65):
					person.set_bag(false)
					worker.state = "to_bin" if not bags.is_empty() else "return"
			"return":
				done = false
				if person.walk_to(cab,delta,1.7):
					person.hide()
					worker.state = "idle"
	if done:
		site.refill = 170.0
		vehicle.site = {}
		var route: Array = vehicle.route
		vehicle.index = (int(vehicle.index)+1)%route.size()

func _drive(vehicle: Dictionary,delta: float) -> void:
	var body: CharacterBody3D = vehicle.body
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
	var ray := PhysicsRayQueryParameters3D.create(body.position+Vector3.UP*.85+direction*(half+.06),body.position+Vector3.UP*.85+direction*(half+2.5+float(vehicle.speed)*.9),1|4)
	ray.exclude = [body.get_rid()]
	var blocked := not get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	vehicle.cooldown = maxf(0.0,float(vehicle.cooldown)-delta)
	if blocked:
		speed = 0.0
		vehicle.blocked = float(vehicle.blocked)+delta
		if not active and float(vehicle.blocked)>1.7 and float(vehicle.cooldown)<=0.0:
			vehicle.cooldown = 4.0
			var choice := Bypass.find(body,original,index,world.street_geometry,2.3 if bool(vehicle.truck) else 1.83,half*2.0,world.geography.signal_nodes)
			if not choice.is_empty():
				vehicle.detour = choice.path
				vehicle.detour_index = 0
				vehicle.resume = int(choice.resume)
				vehicle.blocked = 0.0
				return
	else:
		vehicle.blocked = 0.0
	vehicle.speed = move_toward(float(vehicle.speed),speed,delta*(7.0 if speed<float(vehicle.speed) else 3.5))
	if float(vehicle.speed)<.04:
		body.velocity = Vector3.ZERO
		return
	body.rotation.y = lerp_angle(body.rotation.y,atan2(direction.x,direction.z),1.0-exp(-delta*4.5))
	body.velocity = direction*minf(float(vehicle.speed),distance/maxf(delta,.001))
	body.move_and_slide()

func tick(delta: float) -> void:
	if not initialized:
		initialized = true
		_initialize()
	for vehicle in vehicles:
		_drive(vehicle,delta)
	for site in sites:
		if float(site.refill)>0.0:
			site.refill = maxf(0.0,float(site.refill)-delta)
			if float(site.refill)<=0.0: _fill(site)
