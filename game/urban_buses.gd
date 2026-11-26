extends Node3D
const MapData = preload("res://pilar_map.gd")
const StreetGeometry = preload("res://street_geometry.gd")
const Planner = preload("res://urban_bus_routes.gd")
const BUS_LENGTH := 9.4
const BUS_WIDTH := 2.45
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
		var start_point: Vector3 = item.p
		body.position = start_point+Vector3.UP*.035
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

# Reference-inspired Havana city bus: white/blue livery, flat front,
# panoramic glazing, real wheel openings, and a hollow passenger cabin.
func _bus_strip(root: Node3D,x: float,lo: float,hi: float,y: float,h: float,color: Color) -> void:
	if hi-lo<.025: return
	_part(root,Vector3(x,y,(lo+hi)*.5),Vector3(.065,h,hi-lo),color)

func _bus_wheel(root: Node3D,x: float,z: float,dark: Color,rim: Color) -> void:
	for layer in range(3):
		var mesh := CylinderMesh.new()
		mesh.top_radius = [.51,.32,.13][layer]
		mesh.bottom_radius = mesh.top_radius
		mesh.height = [.29,.055,.065][layer]
		mesh.radial_segments = 16 if layer==0 else 12
		var wheel := MeshInstance3D.new()
		wheel.mesh = mesh
		wheel.material_override = _mat(dark if layer==0 else (rim if layer==1 else dark))
		wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(wheel)
		wheel.rotation.z = PI*.5
		wheel.position = Vector3(x+signf(x)*[0.0,.155,.19][layer],.51,z)

func _bus_glass(root: Node3D,p: Vector3,dimensions: Vector3) -> void:
	var pane := _part(root,p,dimensions,Color("#526b7790"))
	var glass := pane.material_override as StandardMaterial3D
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = .34

func _batch_bus_shell(root: Node3D) -> void:
	# Consolidate all fixed opaque panels into one mesh per material.
	# Keep transparent windows separate for sorting and doors separate
	# for animation. This avoids dozens of independent draw calls.
	var batches: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	for child in root.get_children():
		if not child is MeshInstance3D: continue
		var part := child as MeshInstance3D
		var material := part.material_override as StandardMaterial3D
		if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var key := material.get_instance_id()
		if not batches.has(key):
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key] = {"surface":surface,"material":material}
		var tool: SurfaceTool = batches[key].surface
		tool.append_from(part.mesh,0,part.transform)
		originals.append(part)
	for key in batches:
		var tool: SurfaceTool = batches[key].surface
		var view := MeshInstance3D.new()
		view.mesh = tool.commit()
		view.material_override = batches[key].material
		view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(view)
	for part in originals:
		root.remove_child(part)
		part.queue_free()

func _make_bus(line: String,index: int) -> Dictionary:
	var body := CharacterBody3D.new()
	body.name = "Guagua_"+line
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.collision_layer = 1
	body.collision_mask = 1|4
	add_child(body)
	var white := Color("#e5e4db")
	var blue := Color("#2986bc")
	var pale_blue := Color("#65afd1")
	var dark := Color("#303739")
	var rubber := Color("#242729")
	var metal := Color("#8b9191")
	var black := Color("#20292d")
	var floor_color := Color("#65645e")
	var half := BUS_LENGTH*.5
	var side_x := BUS_WIDTH*.5-.033
	# Flat underframe with no solid block through the wheel arches.
	_part(body,Vector3(0,.65,0),Vector3(1.40,.35,BUS_LENGTH-.6),dark)
	_part(body,Vector3(0,.91,-.77),Vector3(BUS_WIDTH-.15,.14,7.50),floor_color)
	_part(body,Vector3(.43,.91,3.65),Vector3(1.45,.14,1.30),floor_color)
	_part(body,Vector3(0,.91,4.35),Vector3(BUS_WIDTH-.15,.14,.62),floor_color)
	# Slightly stepped roof shoulders and full-length white roof.
	_part(body,Vector3(0,2.82,0),Vector3(BUS_WIDTH-.02,.30,BUS_LENGTH-.04),white)
	_part(body,Vector3(0,3.00,0),Vector3(BUS_WIDTH-.19,.13,BUS_LENGTH-.17),white)
	# Side skins segmented around both wheel openings and front entrance.
	for side in [-1.0,1.0]:
		var x := float(side)*side_x
		var cuts: Array[float] = [-half,-3.46,-2.18,-.82,.60,2.18,3.46,half]
		# Right side uses a forward door; other side remains continuous.
		if side<0.0:
			cuts.append(2.92)
			cuts.append(4.12)
			cuts.sort()
		for k in range(cuts.size()-1):
			var lo: float = cuts[k]
			var hi: float = cuts[k+1]
			var mid := (lo+hi)*.5
			if side<0.0 and mid>2.92 and mid<4.12: continue
			var arch := absf(absf(mid)-2.82)<.64
			var bottom := 1.09 if arch else .39
			_bus_strip(body,x,lo,hi,(bottom+1.46)*.5,1.46-bottom,white)
			_bus_strip(body,x+float(side)*.037,lo,hi,1.28,.30,blue)
			if not arch:
				_bus_strip(body,x+float(side)*.037,lo,hi,.53,.18,pale_blue)
		# Window frames and individual panes leave the cabin genuinely hollow.
		var frames: Array[float] = [-4.62,-3.36,-2.07,-.78,.51,1.80,3.09,4.62]
		if side<0.0:
			frames = [-4.62,-3.36,-2.07,-.78,.51,1.80,2.92,4.12,4.62]
		for k in range(frames.size()-1):
			var lo: float = frames[k]
			var hi: float = frames[k+1]
			if side<0.0 and lo>=2.91 and hi<=4.13: continue
			_bus_strip(body,x,lo,lo+.065,2.03,1.14,dark)
			_bus_strip(body,x,lo,hi,2.64,.13,white)
			_bus_strip(body,x,lo,hi,1.49,.10,dark)
			_bus_glass(body,Vector3(x,2.045,(lo+hi)*.5),Vector3(.025,1.0,maxf(.04,hi-lo-.09)))
		_bus_strip(body,x,4.53,4.68,2.03,1.16,dark)
		for z in [-2.82,2.82]:
			_bus_wheel(body,float(side)*1.07,float(z),rubber,metal)
		# Wheel wells protrude slightly into the cabin above the wheels.
		for z in [-2.82,2.82]:
			_part(body,Vector3(float(side)*.89,1.02,float(z)),Vector3(.57,.35,1.18),dark)
	# Two visible entry steps and a separate sliding pair of door leaves.
	_part(body,Vector3(-.89,.33,3.52),Vector3(.60,.13,1.18),dark)
	_part(body,Vector3(-.67,.60,3.52),Vector3(.76,.13,1.18),floor_color)
	_part(body,Vector3(-.49,.86,3.52),Vector3(.65,.13,1.18),floor_color)
	var door := Node3D.new()
	body.add_child(door)
	door.position = Vector3(-BUS_WIDTH*.5-.045,1.53,3.52)
	for side in [-1.0,1.0]:
		var leaf := Node3D.new()
		door.add_child(leaf)
		leaf.position.z = float(side)*.30
		leaf.set_meta("closed_z",leaf.position.z)
		_part(leaf,Vector3(0,-.60,0),Vector3(.06,.86,.57),white)
		_part(leaf,Vector3(-.04,-.35,0),Vector3(.035,.24,.57),blue)
		_part(leaf,Vector3(0,.50,0),Vector3(.06,.10,.57),dark)
		for edge in [-.265,.265]:
			_part(leaf,Vector3(0,.06,float(edge)),Vector3(.06,1.00,.05),dark)
		_bus_glass(leaf,Vector3(0,.05,0),Vector3(.025,.91,.48))
	# Front fascia: large dark destination board over a split windshield.
	_part(body,Vector3(0,1.05,half-.035),Vector3(BUS_WIDTH-.05,1.24,.09),white)
	_part(body,Vector3(0,1.19,half+.025),Vector3(BUS_WIDTH-.06,.30,.05),blue)
	_part(body,Vector3(0,.62,half+.025),Vector3(BUS_WIDTH-.06,.23,.05),pale_blue)
	_part(body,Vector3(0,.43,half+.045),Vector3(BUS_WIDTH-.08,.16,.16),dark)
	_part(body,Vector3(0,2.68,half),Vector3(BUS_WIDTH-.12,.38,.10),black)
	_part(body,Vector3(0,1.71,half),Vector3(BUS_WIDTH-.12,.12,.10),black)
	for side in [-1.0,1.0]:
		var x := float(side)
		_part(body,Vector3(x*1.10,2.12,half),Vector3(.12,.92,.10),black)
		_bus_glass(body,Vector3(x*.55,2.13,half+.045),Vector3(1.03,.83,.026))
		_part(body,Vector3(x*.91,.93,half+.065),Vector3(.43,.23,.055),dark)
		_part(body,Vector3(x*.91,.93,half+.10),Vector3(.31,.16,.04),Color("#f3efcf"))
		_part(body,Vector3(x*1.12,.91,half+.10),Vector3(.09,.16,.04),Color("#dca54b"))
		var wiper := _part(body,Vector3(x*.53,1.96,half+.08),Vector3(.033,.48,.026),black)
		wiper.rotation.z = x*.60
		_part(body,Vector3(x*1.30,2.37,half-.38),Vector3(.26,.055,.06),black)
		_part(body,Vector3(x*1.39,2.29,half-.38),Vector3(.13,.29,.16),dark)
	_part(body,Vector3(0,2.12,half+.065),Vector3(.045,.92,.08),black)
	_part(body,Vector3(0,.77,half+.07),Vector3(.54,.13,.045),black)
	var sign_label := Label3D.new()
	sign_label.text = line
	sign_label.font_size = 52
	sign_label.pixel_size = .0035
	sign_label.modulate = Color("#e9b96d")
	sign_label.outline_size = 0
	body.add_child(sign_label)
	sign_label.position = Vector3(0,2.68,half+.075)
	var fleet := Label3D.new()
	fleet.text = str(5304+index)
	fleet.font_size = 36
	fleet.pixel_size = .0035
	fleet.modulate = black
	fleet.outline_size = 0
	body.add_child(fleet)
	fleet.position = Vector3(.70,1.57,half+.075)
	# Rear panel and tail lamps.
	_part(body,Vector3(0,1.0,-half+.03),Vector3(BUS_WIDTH-.05,1.28,.09),white)
	_part(body,Vector3(0,1.22,-half-.025),Vector3(BUS_WIDTH-.06,.30,.05),blue)
	_part(body,Vector3(0,2.68,-half),Vector3(BUS_WIDTH-.08,.24,.08),white)
	_part(body,Vector3(0,1.68,-half),Vector3(BUS_WIDTH-.08,.12,.08),dark)
	_bus_glass(body,Vector3(0,2.14,-half-.03),Vector3(2.04,.84,.035))
	for side in [-1.0,1.0]:
		var x := float(side)
		_part(body,Vector3(x*1.09,2.14,-half),Vector3(.13,.94,.10),white)
		_part(body,Vector3(x*1.02,.91,-half-.06),Vector3(.18,.34,.055),Color("#b53d39"))
	# Simple seats and yellow hand rails, visible behind the tinted glass.
	for z in [-3.7,-2.25,-.85,.55,1.95]:
		for side in [-1.0,1.0]:
			var x := float(side)*.74
			_part(body,Vector3(x,1.18,float(z)),Vector3(.72,.16,.46),Color("#51616a"))
			_part(body,Vector3(x,1.48,float(z)-.22),Vector3(.72,.48,.10),Color("#51616a"))
	for x in [-.48,.48]:
		_part(body,Vector3(float(x),2.51,-.6),Vector3(.035,.035,6.6),Color("#c5ae55"))
		for z in [-3.55,-.70,2.1]:
			_part(body,Vector3(float(x),1.75,float(z)),Vector3(.04,1.52,.04),Color("#c5ae55"))
	_batch_bus_shell(body)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(BUS_WIDTH,3.02,BUS_LENGTH)
	collision.shape = shape
	body.add_child(collision)
	collision.position.y = 1.54
	return {"body":body,"door":door}

func _set_bus_door(door: Node3D,opened: bool) -> void:
	for child in door.get_children():
		var leaf := child as Node3D
		var closed_z := float(leaf.get_meta("closed_z",0.0))
		leaf.position.z = closed_z+signf(closed_z)*.59 if opened else closed_z
		leaf.position.x = -.065 if opened else 0.0

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
	_set_bus_door(door,true)

func _transfer_tick(bus: Dictionary,delta: float) -> void:
	var stop: Dictionary = bus.active_stop
	var body: CharacterBody3D = bus.body
	var onboard: Array = bus.onboard
	var transfer: Dictionary = bus.transfer
	var door_point := body.to_global(Vector3(-.59,.89,3.52))
	var stop_direction: Vector3 = stop.direction
	var wait_point: Vector3 = stop.wait
	var exit_point: Vector3 = wait_point+stop_direction*2.3
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
				departing.append({"node":person,"time":2.0,"target":exit_point+stop_direction*2.0})
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
	_set_bus_door(door,false)
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
		var ray := PhysicsRayQueryParameters3D.create(body.position+Vector3.UP*.95+d*(BUS_LENGTH*.5+.15),body.position+Vector3.UP*.95+d*(BUS_LENGTH*.5+1.2+float(bus.speed)*.8),1|4)
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
			var target: Vector3 = entry.target
			if near and _on_sidewalk(target):
				_walk(person,target,elapsed)
			person.visible = near
			if float(entry.time)<=0.0:
				person.queue_free()
				departing.remove_at(i)
		stop.cooldown = maxf(0.0,float(stop.cooldown)-elapsed)
		if float(stop.cooldown)<=0.0 and queue.size()<3:
			_add_waiter(stop)
			stop.cooldown = 12.0
