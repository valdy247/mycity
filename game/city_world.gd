extends Node3D
# Native Godot city. Coordinates match the 8 m construction grid.
const SIZE := 512.0
const ROAD_Y := 0.055
const ROAD_AXES := [-128, -64, 0, 64, 128]
const HOME := Vector3(16, ROAD_Y, 16)
const HOME_OUT := Vector3(16, 0.91, 21.0)
const HOME_IN := Vector3(16, 1.02, 17.35)
const VAN_PARK := Vector3(8, 0, 16)
const Builder = preload("res://city_builder.gd")
var grid_builder: Builder
var mats: Dictionary = {}
var mesh_cache: Dictionary = {}
var batches: Dictionary = {}
var solid_body: StaticBody3D
var road_ground: StaticBody3D
var seats: Array = []
var cars: Array = []
var walkers: Array = []
var signals: Array = []
var clock := 0.0
var inside_home := false
var seated := false
var seat_exit := Vector3.ZERO
var door: Node3D
var door_tween: Tween
var door_anchor := Vector3.ZERO

func setup(builder: Builder) -> void:
	grid_builder = builder
	solid_body = StaticBody3D.new()
	solid_body.collision_layer = 1
	solid_body.collision_mask = 0
	add_child(solid_body)
	var ground := StaticBody3D.new()
	ground.collision_layer = 2
	ground.collision_mask = 0
	add_child(ground)
	road_ground = ground
	_visual_box(ground, Vector3(0,-0.3,0), Vector3(SIZE,0.6,SIZE), _mat("grass",Color("#76a34f")))
	_shape(ground,Vector3(0,-0.3,0),Vector3(SIZE,0.6,SIZE))
	_make_roads()
	_make_districts()
	_make_home()
	_make_park(Vector3(40,0,32))
	_make_park(Vector3(-40,0,-40))
	_make_park(Vector3(104,0,104))
	_flush_batches()
	_make_traffic()
	_make_pedestrians()

func _mat(key: String, color: Color) -> StandardMaterial3D:
	if mats.has(key):
		return mats[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mats[key] = mat
	return mat

func _box_mesh(size: Vector3) -> BoxMesh:
	if mesh_cache.has(size):
		return mesh_cache[size] as BoxMesh
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_cache[size] = mesh
	return mesh

func _visual_box(parent: Node3D, at: Vector3, size: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = _box_mesh(size)
	m.material_override = material
	parent.add_child(m)
	m.position = at
	return m

func _batch(at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	var key := str(material.get_instance_id()) + ":" + str(size)
	if not batches.has(key):
		batches[key] = {"mesh":_box_mesh(size),"material":material,"positions":[]}
	batches[key].positions.append(at)

func _flush_batches() -> void:
	for value in batches.values():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = value.mesh
		mm.instance_count = value.positions.size()
		for i in range(mm.instance_count):
			mm.set_instance_transform(i,Transform3D(Basis.IDENTITY,value.positions[i]))
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = mm
		instance.material_override = value.material
		add_child(instance)
	batches.clear()

func _shape(body: StaticBody3D, at: Vector3, size: Vector3) -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	col.position = at

func _static_box(at: Vector3, size: Vector3, material: StandardMaterial3D) -> void:
	_batch(at,size,material)
	_shape(solid_body,at,size)

func _reserve(x: int, z: int, kind: String = "lot") -> void:
	grid_builder.reserve_cell(x,z,kind)

func _make_roads() -> void:
	var asphalt := _mat("road",Color(0.20,0.23,0.27))
	var stripe := _mat("stripe",Color(0.96,0.78,0.15))
	var concrete := _mat("walk",Color("#b9bcb6"))
	var white := _mat("white",Color("#eeeeea"))
	# A connected network with full-width intersections. Sidewalks live
	# inside the road tile, so a new 8 m road meets the existing grid.
	for axis in ROAD_AXES:
		_shape(road_ground,Vector3(float(axis),ROAD_Y/2,0),Vector3(8,ROAD_Y,392))
		_shape(road_ground,Vector3(0,ROAD_Y/2,float(axis)),Vector3(392,ROAD_Y,8))
		for k in range(-24,25):
			_reserve(roundi(float(axis)/8.0),k,"road")
			_reserve(k,roundi(float(axis)/8.0),"road")
	for axis in ROAD_AXES:
		for k in range(-24,25):
			var q: float = float(k)*8.0
			var a: float = float(axis)
			_batch(Vector3(a,ROAD_Y/2,q),Vector3(8,ROAD_Y,8),asphalt)
			if not ROAD_AXES.has(int(q)):
				_batch(Vector3(a,ROAD_Y+0.009,q),Vector3(0.10,0.018,2.5),stripe)
				for side in [-1.0,1.0]:
					_batch(Vector3(a+float(side)*3.65,ROAD_Y+0.018,q),Vector3(0.65,0.036,8),concrete)
				_batch(Vector3(q,ROAD_Y/2,a),Vector3(8,ROAD_Y,8),asphalt)
				_batch(Vector3(q,ROAD_Y+0.009,a),Vector3(2.5,0.018,0.10),stripe)
				for side in [-1.0,1.0]:
					_batch(Vector3(q,ROAD_Y+0.018,a+float(side)*3.65),Vector3(8,0.036,0.65),concrete)
	# Local access streets connect the residential and commercial lots.
	for lane_z in [-24,24]:
		_shape(road_ground,Vector3(0,ROAD_Y/2,float(lane_z)),Vector3(128,ROAD_Y,8))
		for cell_x in range(-7,8):
			if cell_x == 0:
				continue
			_reserve(cell_x,roundi(float(lane_z)/8.0),"road")
			var xx: float = float(cell_x)*8.0
			var zz: float = float(lane_z)
			_batch(Vector3(xx,ROAD_Y/2,zz),Vector3(8,ROAD_Y,8),asphalt)
			_batch(Vector3(xx,ROAD_Y+.009,zz),Vector3(2.5,.018,.1),stripe)
			for side in [-1.0,1.0]:
				_batch(Vector3(xx,ROAD_Y+.018,zz+float(side)*3.65),Vector3(8,.036,.65),concrete)
		for main_x in [-64.0,0.0,64.0]:
			_batch(Vector3(float(main_x),ROAD_Y+.043,float(lane_z)),Vector3(8,.016,6.5),asphalt)
	# Starter roads and new pieces use the same physical road elevation.
	for xx in ROAD_AXES:
		for zz in ROAD_AXES:
			var x: float = float(xx)
			var z: float = float(zz)
			for side in [-1.0,1.0]:
				var sign_value: float = float(side)
				for i in range(6):
					var off: float = -2.5+float(i)
					_batch(Vector3(x+off,ROAD_Y+0.015,z+sign_value*4.5),Vector3(0.52,0.025,0.85),white)
					_batch(Vector3(x+sign_value*4.5,ROAD_Y+0.015,z+off),Vector3(0.85,0.025,0.52),white)
			_make_signal(x,z)

func _make_signal(x: float,z: float) -> void:
	var pole := _mat("pole",Color("#414b52"))
	var housing := _mat("signal",Color("#22282d"))
	# Four visible heads, one for each approach, paired by direction.
	for i in range(4):
		var axis: int = i%2
		var angle: float = float(i)*PI/2.0
		var at: Vector3 = Vector3(3.5,0,-3.5).rotated(Vector3.UP,angle)+Vector3(x,0,z)
		_batch(at+Vector3(0,1.4,0),Vector3(.13,2.8,.13),pole)
		var head := Node3D.new()
		add_child(head)
		head.position=at+Vector3(0,2.9,0)
		head.rotation.y=angle
		_visual_box(head,Vector3.ZERO,Vector3(.34,.85,.34),housing)
		var lamp := _visual_box(head,Vector3(0,.10,-.19),Vector3(.21,.21,.07),_mat("red",Color("#ff423c")))
		signals.append({"lamp":lamp,"axis":1-axis})

func _starter(kind: String, x: int, z: int, turn: int) -> void:
	_reserve(x,z)
	var ob := Node3D.new()
	ob.name = "Starter_" + kind
	add_child(ob)
	ob.position = Vector3(x*8,ROAD_Y,z*8)
	ob.rotation.y = turn*PI/2.0
	grid_builder._make_model(ob,kind,true,0.12)

func _make_districts() -> void:
	# Uniform buildings use exactly the same model generator as player builds.
	# Keep many empty blocks and lots for future construction.
	for p in [Vector2i(-6,2),Vector2i(-5,2),Vector2i(-4,2),Vector2i(-3,2),Vector2i(-2,2),Vector2i(3,2),Vector2i(4,2),Vector2i(6,2),Vector2i(7,2),Vector2i(-6,4),Vector2i(-5,4),Vector2i(-4,4),Vector2i(3,4),Vector2i(4,4)]:
		_starter("house",p.x,p.y,0 if p.y==2 else 2)
	for p in [Vector2i(-2,-2),Vector2i(-3,-2),Vector2i(-4,-2),Vector2i(2,-2),Vector2i(3,-2),Vector2i(4,-2),Vector2i(7,-2)]:
		_starter("shop",p.x,p.y,2)
	for p in [Vector2i(-3,6),Vector2i(3,6),Vector2i(10,-10),Vector2i(-10,10)]:
		_starter("school",p.x,p.y,0)
	for p in [Vector2i(-10,-10),Vector2i(-11,-10),Vector2i(-12,-10),Vector2i(10,10),Vector2i(11,10),Vector2i(12,10),Vector2i(10,-4),Vector2i(11,-4)]:
		_starter("house",p.x,p.y,0)

func _make_home() -> void:
	_reserve(2,2)
	_reserve(1,2) # player's parking space
	var wall := _mat("home_wall",Color(0.94,0.85,0.66))
	var roof := _mat("home_roof",Color(0.65,0.22,0.13))
	var glass := _mat("home_glass",Color(0.16,0.38,0.54))
	var wood := _mat("home_wood",Color(0.34,0.19,0.08))
	var floor := _mat("floor",Color("#c5ae87"))
	var blue := _mat("sofa",Color("#427a9f"))
	var cream := _mat("cream",Color("#eee3c8"))
	_batch(HOME+Vector3(0,-0.06,0),Vector3(7.8,0.12,7.8),_mat("lot",Color("#8bb65e")))
	_static_box(HOME+Vector3(0,0.06,0),Vector3(5,0.12,4.8),floor)
	_static_box(HOME+Vector3(0,1.5,-2.35),Vector3(5,3,.15),wall)
	for side in [-1.0,1.0]:
		var v: float = float(side)
		_static_box(HOME+Vector3(v*2.425,1.5,0),Vector3(.15,3,4.7),wall)
		_static_box(HOME+Vector3(v*1.50,1.5,2.35),Vector3(2.0,3,.15),wall)
		_batch(HOME+Vector3(v*1.5,1.58,2.44),Vector3(1.15,1.0,.04),glass)
		var slab := _visual_box(self,HOME+Vector3(v*1.25,3.60,0),Vector3(3.05,.18,5.25),roof)
		slab.rotation.z = -v*.39
	_static_box(HOME+Vector3(0,2.55,2.35),Vector3(1.0,.9,.15),wall)
	_static_box(HOME+Vector3(0,3.03,0),Vector3(5,.14,4.8),roof)
	door = Node3D.new()
	add_child(door)
	door.position = HOME+Vector3(-.48,0.12,2.43)
	_visual_box(door,Vector3(.48,1.0,0),Vector3(.96,2.0,.09),wood)
	# Doorway is accessible only via E; the invisible blocker prevents
	# wandering into the home by accident.
	_shape(solid_body,HOME+Vector3(0,1.05,2.35),Vector3(.95,2.10,.13))
	door_anchor = HOME+Vector3(0,0.9,2.55)
	_static_box(HOME+Vector3(-1.65,.35,-1.2),Vector3(.95,.60,1.8),blue)
	_batch(HOME+Vector3(-2.06,.75,-1.2),Vector3(.18,.65,1.8),blue)
	_static_box(HOME+Vector3(1.48,.29,-1.35),Vector3(1.55,.48,1.75),wood)
	_batch(HOME+Vector3(1.48,.58,-1.35),Vector3(1.5,.15,1.7),cream)
	_static_box(HOME+Vector3(0,.40,-.7),Vector3(.85,.72,.60),wood)
	_batch(HOME+Vector3(0,0.13,3.0),Vector3(1.1,.12,1.2),floor)
	var label := Label3D.new()
	label.text = "MI CASA"
	label.font_size = 48
	label.pixel_size = .009
	label.modulate = Color("#fff3c5")
	label.outline_size = 5
	add_child(label)
	label.position = HOME+Vector3(0,2.65,2.47)

func _make_park(center: Vector3) -> void:
	# 2x2 tile footprint, with seats available to the player.
	for dx in [0,1]:
		for dz in [0,1]:
			_reserve(roundi(center.x/8.0)+int(dx),roundi(center.z/8.0)+int(dz))
	var c := center+Vector3(4,0,4)
	var grass := _mat("park",Color("#8ab958"))
	var path := _mat("path",Color("#d2c49b"))
	var wood := _mat("bench",Color("#84502d"))
	var metal := _mat("bench_metal",Color("#35454b"))
	_batch(c+Vector3(0,.025,0),Vector3(15.8,.05,15.8),grass)
	_batch(c+Vector3(0,.065,0),Vector3(2,.07,15),path)
	_batch(c+Vector3(0,.065,0),Vector3(15,.07,2),path)
	for side in [-1.0,1.0]:
		var v: float = float(side)
		var p := c+Vector3(v*3.4,0,2.4)
		_static_box(p+Vector3(0,.52,0),Vector3(2.0,.13,.58),wood)
		_batch(p+Vector3(0,.79,-.29),Vector3(2.0,.45,.10),wood)
		for dx in [-.7,.7]:
			_batch(p+Vector3(float(dx),.24,0),Vector3(.13,.48,.52),metal)
		seats.append({"at":p+Vector3(0,1.10,0.02),"exit":p+Vector3(0,.86,.95),"yaw":0.0})
		for dz in [-5.2,5.2]:
			var t := c+Vector3(v*5.1,0,float(dz))
			_static_box(t+Vector3(0,.8,0),Vector3(.22,1.6,.22),wood)
			var tree := MeshInstance3D.new()
			var sphere := SphereMesh.new()
			sphere.radius = 1.25
			sphere.height = 2.5
			sphere.radial_segments = 10
			sphere.rings = 5
			tree.mesh = sphere
			tree.material_override = _mat("leaves",Color("#497f32"))
			add_child(tree)
			tree.position = t+Vector3(0,2.1,0)

func _all_seats() -> Array:
	var result: Array = seats.duplicate()
	for entry in grid_builder.pieces.values():
		if String(entry.kind) != "park":
			continue
		var root: Node3D = entry.node
		if not is_instance_valid(root):
			continue
		for side in [-1.0,1.0]:
			var x: float = float(side)*1.8
			result.append({"at":root.to_global(Vector3(x,1.08,.90)),"exit":root.to_global(Vector3(x,.86,-.1)),"yaw":root.rotation.y+PI})
	return result

func interaction_text(at: Vector3) -> String:
	if seated:
		return "[E] Levantarse"
	if at.distance_to(door_anchor) < 2.6:
		return "[E] Salir de mi casa" if inside_home else "[E] Entrar a mi casa"
	for seat in _all_seats():
		if at.distance_to(seat.at) < 2.1:
			return "[E] Sentarse"
	return ""

func _animate_door() -> void:
	if door_tween != null and door_tween.is_valid():
		door_tween.kill()
	door.rotation.y = 0.0
	door_tween = create_tween()
	door_tween.tween_property(door,"rotation:y",-1.4,.25)
	door_tween.tween_interval(.2)
	door_tween.tween_property(door,"rotation:y",0.0,.25)

func interact(player: CharacterBody3D, avatar: Node3D, legs: Array, arms: Array) -> bool:
	if seated:
		seated = false
		player.global_position = seat_exit
		player.velocity = Vector3.ZERO
		avatar.position.y = 0
		for leg in legs:
			leg.rotation.x = 0.0
		return true
	if player.global_position.distance_to(door_anchor)<2.6:
		inside_home = not inside_home
		_animate_door()
		player.global_position = HOME_IN if inside_home else HOME_OUT
		player.velocity = Vector3.ZERO
		return true
	for seat in _all_seats():
		if player.global_position.distance_to(seat.at)<2.1:
			seated = true
			seat_exit = seat.exit
			player.global_position = seat.at
			player.velocity = Vector3.ZERO
			avatar.rotation.y = float(seat.yaw)
			avatar.position.y = -.20
			for leg in legs:
				leg.rotation.x = -1.45
			for arm in arms:
				arm.rotation.x = -.3
			return true
	return false

func reset_interaction(avatar: Node3D, legs: Array) -> void:
	inside_home = false
	seated = false
	avatar.position.y = 0
	for leg in legs:
		leg.rotation.x = 0.0

func _phase() -> int:
	# 10 seconds green, 2 seconds all red; alternate axes.
	var t := fmod(clock,24.0)
	if t<10.0: return 0
	if t>=12.0 and t<22.0: return 1
	return -1

func _make_traffic() -> void:
	# Four disjoint clockwise circuits: one car per circuit, right-hand lanes.
	for p in [Vector2i(0,0),Vector2i(-128,-128),Vector2i(64,-128),Vector2i(-128,64)]:
		var x: float = float(p.x)
		var z: float = float(p.y)
		var route: Array[Vector3] = [Vector3(x+1.8,0,z+1.8),Vector3(x+64-1.8,0,z+1.8),Vector3(x+64-1.8,0,z+64-1.8),Vector3(x+1.8,0,z+64-1.8)]
		var car := CharacterBody3D.new()
		car.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
		car.collision_layer = 1
		car.collision_mask = 1|4
		add_child(car)
		car.position = route[0]+Vector3(12,ROAD_Y,0)
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.65,1.2,3.3)
		col.shape = shape
		car.add_child(col)
		col.position.y = .65
		var tint := [Color("#df8b42"),Color("#427dc9"),Color("#e5e5de"),Color("#ae4d58")]
		var paint := _mat("car"+str(cars.size()),tint[cars.size()])
		_visual_box(car,Vector3(0,.55,0),Vector3(1.65,.65,3.3),paint)
		_visual_box(car,Vector3(0,1.05,-.20),Vector3(1.4,.48,1.75),_mat("car_glass",Color("#507080")))
		_visual_box(car,Vector3(0,1.31,-.2),Vector3(1.45,.12,1.8),paint)
		for side in [-1.0,1.0]:
			for end in [-1.0,1.0]:
				_visual_box(car,Vector3(float(side)*.79,.27,float(end)*1.03),Vector3(.25,.52,.55),_mat("tire",Color("#23282d")))
		cars.append({"node":car,"route":route,"next":1,"speed":0.0,"committed":false})

func _make_pedestrians() -> void:
	# Six people use sidewalk paths outside the traffic lanes; no random
	# crossing or crowd simulation. Their routes stay within the same block.
	for i in range(6):
		var x: float = 3.65 if i<3 else 60.35
		var z: float = 11.0+float(i%3)*17.0
		if i%3==1:
			z=36.0
		elif i%3==2:
			z=50.0
		var person := Node3D.new()
		add_child(person)
		person.position = Vector3(x,.09,z)
		var clothing := _mat("npc"+str(i),[Color("#d18b40"),Color("#617bc6"),Color("#b96585")][i%3])
		_visual_box(person,Vector3(0,.85,0),Vector3(.40,.58,.26),clothing)
		_visual_box(person,Vector3(0,1.28,0),Vector3(.34,.34,.31),_mat("npc_skin",Color("#c89164")))
		var legs: Array[Node3D] = []
		for side in [-1.0,1.0]:
			var leg := Node3D.new()
			person.add_child(leg)
			leg.position=Vector3(float(side)*.12,.56,0)
			_visual_box(leg,Vector3(0,-.23,0),Vector3(.16,.46,.18),_mat("npc_pants",Color("#364255")))
			legs.append(leg)
		walkers.append({"node":person,"legs":legs,"origin":person.position,"phase":float(i)*.7})

func tick(delta: float) -> void:
	clock += delta
	var phase := _phase()
	for signal in signals:
		var lamp: MeshInstance3D = signal.lamp
		lamp.material_override = _mat("green",Color("#45ed62")) if int(signal.axis)==phase else _mat("red",Color("#ff423c"))
	for entry in cars:
		var car: CharacterBody3D = entry.node
		var route: Array = entry.route
		var next: int = int(entry.next)
		var target: Vector3 = route[next]+Vector3.UP*ROAD_Y
		var diff := target-car.position
		diff.y=0
		var distance := diff.length()
		if distance<.18:
			entry.next=(next+1)%4
			entry.committed=false
			car.velocity=Vector3.ZERO
			continue
		var direction := diff.normalized()
		var axis: int = 0 if absf(direction.x)>.5 else 1
		var target_speed: float = 6.0
		if not bool(entry.committed):
			if phase != axis:
				target_speed = minf(target_speed,maxf(0.0,(distance-4.8)*1.8))
			elif distance<5.0:
				entry.committed=true
		var space := get_world_3d().direct_space_state
		var ray := PhysicsRayQueryParameters3D.create(car.position+Vector3.UP*.65,car.position+Vector3.UP*.65+direction*5.0,1|4)
		ray.exclude=[car.get_rid()]
		if not space.intersect_ray(ray).is_empty():
			target_speed=0.0
		var speed := move_toward(float(entry.speed),target_speed,delta*6.0)
		entry.speed=speed
		car.rotation.y=atan2(direction.x,direction.z)
		car.velocity=direction*minf(speed,distance/maxf(delta,.001))
		car.move_and_slide()
		if car.get_slide_collision_count()>0:
			entry.speed=0.0
	for entry in walkers:
		var person: Node3D = entry.node
		var origin: Vector3 = entry.origin
		var phase_value: float = clock*.16+float(entry.phase)
		person.position=origin+Vector3(0,0,sin(phase_value)*3.0)
		person.rotation.y=0.0 if cos(phase_value)>0 else PI
		var legs: Array=entry.legs
		for i in range(legs.size()):
			legs[i].rotation.x=sin(clock*6.0+i*PI+float(entry.phase))*.40
