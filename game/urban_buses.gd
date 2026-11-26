extends Node3D
const MapData = preload("res://pilar_map.gd")
const StreetGeometry = preload("res://street_geometry.gd")
const Planner = preload("res://urban_bus_routes.gd")
const BUS_LENGTH := 8.0
const BUS_WIDTH := 2.35
const MAX_PASSENGERS := 18
var data: MapData
var streets: StreetGeometry
var planner := Planner.new()
var buses: Array = []
var stops: Array = []
var materials: Dictionary = {}
var meshes: Dictionary = {}
var serial := 0
var pedestrian_update := 0.0

func setup(map_data: MapData,street_geometry: StreetGeometry,anchor: Vector3,avoid: Array) -> void:
	data = map_data
	streets = street_geometry
	planner.setup(data)
	for line in ["MONTE","CERRO"]:
		var route := planner.plan(line,anchor)
		if route.is_empty():
			push_warning("Guagua: no hay circuito vial seguro para "+line)
			continue
		var itinerary := _make_itinerary(route,line)
		if itinerary.size()<4: continue
		var start_index := -1
		for i in range(itinerary.size()):
			var item: Dictionary = itinerary[i]
			if not item.has("stop"): continue
			var p: Vector3 = item.p
			var free := true
			for other in avoid:
				var at: Vector3 = other
				if p.distance_to(at)<15.0:
					free = false
					break
			if free:
				start_index = i
				break
		if start_index<0: continue
		var model := _make_bus(line,buses.size())
		var body: CharacterBody3D = model.body
		var item: Dictionary = itinerary[start_index]
		var stop: Dictionary = item.stop
		var direction: Vector3 = stop.direction
		body.position = Vector3(item.p)+Vector3.UP*.065
		body.rotation.y = atan2(direction.x,direction.z)
		var bus := {"body":body,"door":model.door,"route":itinerary,"index":start_index,"speed":0.0,"line":line,"dwell":0.0,"active_stop":{},"onboard":[],"transfer":{},"served":0,"blocked":0.0}
		buses.append(bus)
		avoid.append(body.position)
	print("Guaguas urbanas: ",buses.size()," circuitos, ",stops.size()," paradas.")

func _make_itinerary(route: Array[String],line: String) -> Array:
	var result: Array = []
	var since_stop := 160.0
	for i in range(route.size()-1):
		var edge: Dictionary = planner.edges.get(route[i]+":"+route[i+1],{})
		if edge.is_empty(): continue
		var a: Vector3 = data.points[route[i]]
		var b: Vector3 = data.points[route[i+1]]
		var d := (b-a).normalized()
		var length := a.distance_to(b)
		var width := float(edge.width)
		var right := Vector3(-d.z,0,d.x)
		var lane := minf(1.40,maxf(.65,width*.5-BUS_WIDTH*.5-.30))
		if length>5.0:
			result.append({"p":a+d*minf(3.0,length*.22)+right*lane})
		var is_major := width>=7.2 or planner._corridor(edge,line)
		if length>=15.0 and is_major:
			var midpoint := (a+b)*.5
			var mapped := false
			var stop_name := ""
			var best_poi := 11.0
			for place in data.poi:
				var tags: Dictionary = place.tags
				if tags.get("highway","")!="bus_stop" and not tags.get("public_transport","") in ["platform","stop_position"]: continue
				var location: Vector3 = place.position
				var along := (location-a).dot(d)
				if along<6.0 or along>length-6.0: continue
				var q := a+d*along
				var side_distance := (location-q).dot(right)
				if side_distance< -.75 or side_distance>width*.5+6.0: continue
				if location.distance_to(q)<best_poi:
					best_poi = location.distance_to(q)
					midpoint = q
					mapped = true
					stop_name = String(tags.get("name",""))
			if since_stop>=125.0 or (mapped and since_stop>=55.0):
				var stop := _make_stop(midpoint,d,width,lane,line,edge,mapped,stop_name)
				if not stop.is_empty():
					result.append({"p":stop.position,"stop":stop})
					since_stop = 0.0
		result.append({"p":b+right*lane})
		since_stop += length
	return result

func _on_sidewalk(p: Vector3) -> bool:
	if streets.point_on_road(p): return false
	var q := Vector2(p.x,p.z)
	var tiny := PackedVector2Array([q-Vector2(.02,.02),q+Vector2(.02,-.02),q+Vector2(.02,.02),q+Vector2(-.02,.02)])
	for poly in streets.near(streets.protected_index,tiny):
		if Geometry2D.is_point_in_polygon(q,poly):
			return true
	return false

func _make_stop(mid: Vector3,d: Vector3,width: float,lane: float,line: String,edge: Dictionary,mapped: bool,name_value: String) -> Dictionary:
	var right := Vector3(-d.z,0,d.x)
	var sidewalk := mid+right*(width*.5+.70)
	var p := mid+right*lane
	for other in stops:
		var old: Vector3 = other.position
		if old.distance_to(p)<27.0: return {}
	# Full vehicle and waiting queue must fit, not merely the centre point.
	for v in streets.rect(p-d*BUS_LENGTH*.5,p+d*BUS_LENGTH*.5,BUS_WIDTH):
		if not streets.point_on_road(Vector3(v.x,0,v.y)): return {}
	for shift in [-2.3,-1.2,0.0,1.2,2.3]:
		if not _on_sidewalk(sidewalk+d*float(shift)): return {}
	var root := Node3D.new()
	add_child(root)
	root.position = sidewalk+Vector3.UP*.065
	root.rotation.y = atan2(d.x,d.z)
	_part(root,Vector3(0,1.05,0),Vector3(.08,2.1,.08),Color("#77746a"))
	_part(root,Vector3(0,2.05,0),Vector3(.65,.38,.11),Color("#244d78"))
	var label := Label3D.new()
	label.text = "PARADA"
	label.font_size = 40
	label.pixel_size = .0032
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 60.0
	root.add_child(label)
	label.position = Vector3(0,2.05,.065)
	var stop := {"position":p,"wait":sidewalk+Vector3.UP*.065,"direction":d,"right":right,"line":line,"name":name_value if not name_value.is_empty() else data.street_label(String(edge.name)),"mapped":mapped,"queue":[],"cooldown":0.0,"root":root,"departing":[]}
	for i in range(3):
		_add_waiter(stop)
	stops.append(stop)
	return stop

func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = .85
		materials[key] = material
	return materials[key] as StandardMaterial3D

func _part(root: Node3D,p: Vector3,dimensions: Vector3,color: Color) -> MeshInstance3D:
	if not meshes.has(dimensions):
		var mesh := BoxMesh.new()
		mesh.size = dimensions
		meshes[dimensions] = mesh
	var instance := MeshInstance3D.new()
	instance.mesh = meshes[dimensions] as BoxMesh
	instance.material_override = _mat(color)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(instance)
	instance.position = p
	return instance

func _make_bus(line: String,index: int) -> Dictionary:
	var body := CharacterBody3D.new()
	body.name = "Guagua_"+line
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.collision_layer = 1
	body.collision_mask = 1|4
	add_child(body)
	var paint := Color("#d2b56c") if index%2==0 else Color("#9bbcc4")
	var ivory := Color("#e1dfd1")
	var glass := Color("#526b73")
	var dark := Color("#353a3c")
	_part(body,Vector3(0,1.03,0),Vector3(BUS_WIDTH,1.25,BUS_LENGTH),paint)
	_part(body,Vector3(0,2.16,0),Vector3(2.27,1.15,7.92),ivory)
	_part(body,Vector3(0,2.78,0),Vector3(2.32,.17,8.0),ivory)
	_part(body,Vector3(0,2.1,4.015),Vector3(2.02,.86,.06),glass)
	_part(body,Vector3(0,2.18,-4.015),Vector3(1.9,.65,.06),glass)
	_part(body,Vector3(0,.65,4.025),Vector3(2.35,.19,.13),dark)
	_part(body,Vector3(0,.65,-4.025),Vector3(2.35,.19,.13),dark)
	for side in [-1.0,1.0]:
		var x := float(side)
		for z in [-3.05,-1.65,-.25,1.15,2.55]:
			if x<0.0 and float(z)>2.0: continue
			_part(body,Vector3(x*1.145,2.18,float(z)),Vector3(.035,.80,1.25),glass)
		_part(body,Vector3(x*.86,.99,4.05),Vector3(.36,.24,.06),Color("#faf0c2"))
		_part(body,Vector3(x*.86,.99,-4.05),Vector3(.24,.25,.06),Color("#ac4039"))
		for z in [-2.65,2.65]:
			var wheel := MeshInstance3D.new()
			var tyre := CylinderMesh.new()
			tyre.top_radius = .49
			tyre.bottom_radius = .49
			tyre.height = .25
			tyre.radial_segments = 12
			wheel.mesh = tyre
			wheel.material_override = _mat(dark)
			wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(wheel)
			wheel.rotation.z = PI*.5
			wheel.position = Vector3(x*1.05,.48,float(z))
	var door := Node3D.new()
	body.add_child(door)
	door.position = Vector3(-1.19,1.63,2.60)
	_part(door,Vector3(0,0,0),Vector3(.06,1.95,1.12),paint)
	_part(door,Vector3(-.035,.36,0),Vector3(.035,.75,.94),glass)
	_part(body,Vector3(0,2.68,4.052),Vector3(1.83,.23,.05),dark)
	var sign_label := Label3D.new()
	sign_label.text = line
	sign_label.font_size = 48
	sign_label.pixel_size = .0034
	sign_label.modulate = Color("#f3dd89")
	sign_label.outline_size = 0
	body.add_child(sign_label)
	sign_label.position = Vector3(0,2.68,4.09)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(BUS_WIDTH,2.70,BUS_LENGTH)
	collision.shape = shape
	body.add_child(collision)
	collision.position.y = 1.40
	return {"body":body,"door":door}

func _person(style: int) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var shirts: Array[Color] = [Color("#ad8954"),Color("#7197ad"),Color("#d0c2a4"),Color("#976f7f"),Color("#839975")]
	var skin: Array[Color] = [Color("#c79a77"),Color("#886044"),Color("#ddb291")]
	_part(root,Vector3(0,1.0,0),Vector3(.36,.53,.25),shirts[posmod(style,shirts.size())])
	_part(root,Vector3(0,1.43,0),Vector3(.28,.31,.28),skin[posmod(style,skin.size())])
	for side in [-1.0,1.0]:
		_part(root,Vector3(float(side)*.10,.36,0),Vector3(.15,.62,.19),Color("#46525a"))
		_part(root,Vector3(float(side)*.23,.96,0),Vector3(.12,.41,.13),skin[posmod(style,skin.size())])
	return root

func _queue_position(stop: Dictionary,index: int) -> Vector3:
	var base: Vector3 = stop.wait
	var d: Vector3 = stop.direction
	return base+d*(-2.3+float(index)*1.10)

func _add_waiter(stop: Dictionary) -> void:
	var queue: Array = stop.queue
	if queue.size()>=4: return
	serial += 1
	var person := _person(serial)
	person.position = _queue_position(stop,queue.size())
	var right: Vector3 = stop.right
	person.rotation.y = atan2(-right.x,-right.z)
	queue.append({"node":person,"style":serial})

func _walk(person: Node3D,target: Vector3,delta: float) -> bool:
	var diff := target-person.position
	if diff.length()<.12:
		person.position = target
		return true
	var dir := diff.normalized()
	person.rotation.y = atan2(dir.x,dir.z)
	person.position = person.position.move_toward(target,delta*1.8)
	return false

func _start_stop(bus: Dictionary,stop: Dictionary) -> void:
	bus.active_stop = stop
	bus.dwell = 4.0
	bus.served = 0
	bus.speed = 0.0
	var body: CharacterBody3D = bus.body
	body.velocity = Vector3.ZERO
	var direction: Vector3 = stop.direction
	body.rotation.y = atan2(direction.x,direction.z)
	var door: Node3D = bus.door
	door.position.z = 3.62

func _transfer_tick(bus: Dictionary,delta: float) -> void:
	var stop: Dictionary = bus.active_stop
	var body: CharacterBody3D = bus.body
	var onboard: Array = bus.onboard
	var transfer: Dictionary = bus.transfer
	var door_point := body.to_global(Vector3(-1.32,0,2.6))
	door_point.y = .065
	var exit_point: Vector3 = stop.wait+Vector3(stop.direction)*2.3
	if not transfer.is_empty():
		var person: Node3D = transfer.node
		var target: Vector3 = transfer.target
		if _walk(person,target,delta):
			if bool(transfer.board):
				onboard.append({"style":int(transfer.style),"remaining":int(transfer.remaining)})
				person.queue_free()
				bus.served = int(bus.served)+1
			else:
				var departing: Array = stop.departing
				departing.append({"node":person,"time":1.4,"target":exit_point})
			bus.transfer = {}
		return
	# Alight passengers whose destination was this stop before boarding.
	for i in range(onboard.size()):
		if int(onboard[i].remaining)<=0:
			var passenger_data: Dictionary = onboard.pop_at(i)
			var person := _person(int(passenger_data.style))
			person.position = door_point
			bus.transfer = {"node":person,"target":exit_point,"board":false}
			return
	var queue: Array = stop.queue
	if not queue.is_empty() and onboard.size()<MAX_PASSENGERS and int(bus.served)<3:
		var waiting: Dictionary = queue.pop_front()
		bus.transfer = {"node":waiting.node,"target":door_point,"board":true,"style":waiting.style,"remaining":2+posmod(int(waiting.style),3)}
		return
	bus.dwell = float(bus.dwell)-delta
	if float(bus.dwell)>0.0: return
	for passenger_data in onboard:
		passenger_data.remaining = int(passenger_data.remaining)-1
	var door: Node3D = bus.door
	door.position.z = 2.60
	bus.active_stop = {}
	var route: Array = bus.route
	bus.index = (int(bus.index)+1)%route.size()
	stop.cooldown = 8.0

func tick(delta: float) -> void:
	for bus in buses:
		var body: CharacterBody3D = bus.body
		if not bus.active_stop.is_empty():
			_transfer_tick(bus,delta)
			continue
		var route: Array = bus.route
		var index := int(bus.index)
		var item: Dictionary = route[index]
		var target: Vector3 = item.p
		target.y = body.position.y
		var diff := target-body.position
		var distance := diff.length()
		if distance<.30:
			body.velocity = Vector3.ZERO
			if item.has("stop"):
				_start_stop(bus,item.stop)
			else:
				bus.index = (index+1)%route.size()
			continue
		var d := diff.normalized()
		var speed := minf(8.5,maxf(.75,sqrt(2.0*3.5*distance)))
		if item.has("stop"):
			speed = minf(speed,maxf(.75,distance*.75))
		var next_target: Vector3 = route[(index+1)%route.size()].p
		var next_dir := (next_target-target).normalized()
		if next_dir.length_squared()>.1 and d.dot(next_dir)<.85:
			speed = minf(speed,maxf(1.1,distance*.7))
		var ray := PhysicsRayQueryParameters3D.create(body.position+Vector3.UP*.95+d*4.15,body.position+Vector3.UP*.95+d*(5.2+float(bus.speed)*.8),1|4)
		ray.exclude = [body.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			speed = 0.0
		bus.speed = move_toward(float(bus.speed),speed,delta*(7.0 if speed<float(bus.speed) else 2.5))
		body.rotation.y = lerp_angle(body.rotation.y,atan2(d.x,d.z),minf(delta*3.5,1.0))
		body.velocity = d*minf(float(bus.speed),distance/maxf(delta,.001))
		body.move_and_slide()
	pedestrian_update += delta
	if pedestrian_update<.10: return
	var elapsed := pedestrian_update
	pedestrian_update = 0.0
	var camera := get_viewport().get_camera_3d()
	for stop in stops:
		var at: Vector3 = stop.wait
		var near := camera==null or camera.global_position.distance_squared_to(at)<32400.0
		var queue: Array = stop.queue
		for i in range(queue.size()):
			var person: Node3D = queue[i].node
			person.visible = near
			if near:
				_walk(person,_queue_position(stop,i),elapsed)
		var departing: Array = stop.departing
		for i in range(departing.size()-1,-1,-1):
			var entry: Dictionary = departing[i]
			var person: Node3D = entry.node
			entry.time = float(entry.time)-elapsed
			if float(entry.time)<=0.0:
				person.queue_free()
				departing.remove_at(i)
		stop.cooldown = maxf(0.0,float(stop.cooldown)-elapsed)
		if float(stop.cooldown)<=0.0 and queue.size()<3:
			_add_waiter(stop)
			stop.cooldown = 12.0
