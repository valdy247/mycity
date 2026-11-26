extends "res://city_world.gd"
# Real road centerlines; reconstructed facades and gameplay premises.
const MapData = preload("res://pilar_map.gd")
var geography := MapData.new()
var home_root: Node3D
var home_spawn := Vector3.ZERO
var van_spawn := Vector3.ZERO
var van_angle := 0.0
var home_edge: Dictionary = {}
var home_local_door := Vector3(0,0,1.65)
var slots: Array = []
var box_groups: Dictionary = {}
var shop_items: Array = []
var inventory: Dictionary = {}
var residents: Array = []
var road_names: Array = []
var service_count := 0
var prompt := ""
var prompt_time := 0.0
var travel: Array = []
var cuba_clock := 0.0
var service_names: Array[String] = ["BODEGA","CUPET","HOSPITAL • LA DEPENDIENTE","PNR","ESCUELA PRIMARIA","TALLER MECÁNICO","AGROMERCADO","FARMACIA","CORREOS DE CUBA","PARADA DE GUAGUA","CUERPO DE BOMBEROS"]

func load_map() -> bool:
	return geography.load_map()

func setup(builder: Builder) -> void:
	grid_builder = builder
	solid_body = StaticBody3D.new()
	solid_body.collision_layer = 1
	solid_body.collision_mask = 0
	add_child(solid_body)
	road_ground = StaticBody3D.new()
	road_ground.collision_layer = 2
	road_ground.collision_mask = 0
	add_child(road_ground)
	_visual_box(road_ground,Vector3(0,-.25,0),Vector3(1240,.50,1240),_mat("urban_ground",Color("#aaa394")))
	_shape(road_ground,Vector3(0,-.25,0),Vector3(1240,.50,1240))
	_make_osm_streets()
	_make_frontages()
	_flush_city_boxes()
	print("Pilar-Atarés: ",slots.size()," generated facade lots, ",service_count," game services, ",residents.size()," citizens.")
	# Real-world source attribution is visible in HUD via main.gd.

func _cube(at: Vector3, size: Vector3, material: StandardMaterial3D, angle: float = 0.0, solid: bool = false) -> void:
	var basis := Basis(Vector3.UP,angle)
	var key: int = material.get_instance_id()
	if not box_groups.has(key):
		box_groups[key] = {"material":material,"transforms":[]}
	box_groups[key].transforms.append(Transform3D(basis.scaled_local(size),at))
	if solid:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		solid_body.add_child(col)
		col.transform = Transform3D(basis,at)

func _flush_city_boxes() -> void:
	var cube := BoxMesh.new()
	cube.size = Vector3.ONE
	for item in box_groups.values():
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = cube
		multi.instance_count = item.transforms.size()
		for i in range(multi.instance_count):
			multi.set_instance_transform(i,item.transforms[i])
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multi
		instance.material_override = item.material
		add_child(instance)
	box_groups.clear()

func _line(a: Vector3,b: Vector3,width: float,height: float,y: float,mat: StandardMaterial3D) -> void:
	var v := b-a
	var p := (a+b)*.5+Vector3.UP*y
	_cube(p,Vector3(width,height,v.length()+.15),mat,atan2(v.x,v.z))

func _make_osm_streets() -> void:
	var asphalt := _mat("asphalt_cuba",Color("#555653"))
	var concrete := _mat("old_sidewalk",Color("#a39c89"))
	var stripe := _mat("faded_line",Color("#b3a67d"))
	var pole := _mat("old_pole",Color("#777366"))
	var wires := _mat("wire",Color("#383b38"))
	for edge in geography.roads:
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var width: float = float(edge.width)
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		_line(a,b,width,.05,.026,asphalt)
		if a.distance_to(b)>8 and width>=8:
			for i in range(int(a.distance_to(b)/9.0)):
				var p := a+d*(float(i)*9.0+3.0)
				_line(p,p+d*2.5,.09,.014,.058,stripe)
		for side in [-1.0,1.0]:
			var off := right*float(side)*(width*.5+.70)
			_line(a+off,b+off,1.40,.055,.031,concrete)
		if a.distance_to(b)>20.0:
			var p := a.lerp(b,.45)+right*(width*.5+.55)
			if _street_clear(p,0.0,edge):
				_cube(p+Vector3.UP*2.65,Vector3(.17,5.3,.17),pole,0,true)
				_cube(p+Vector3.UP*5.12,Vector3(1.0,.12,.13),pole)
				var end := b-right*.0+right*(width*.5+.55)
				for offset in [-.32,.32]:
					_line(p+Vector3(float(offset),0,0),end+Vector3(float(offset),0,0),.026,.026,5.04,wires)
		if String(edge.name)!="Calle sin nombre" and not road_names.has(edge.name) and road_names.size()<55:
			road_names.append(edge.name)
			var p := a.lerp(b,.5)+right*(width*.5+.85)
			_label(String(edge.name),p+Vector3.UP*2.55,.009,atan2(-right.x,-right.z),Color("#edf0d6"))

func _street_clear(p: Vector3,padding: float,ignore: Dictionary = {}) -> bool:
	for e in geography.roads:
		if not ignore.is_empty() and e.a_id==ignore.a_id and e.b_id==ignore.b_id:
			continue
		var a: Vector3 = e.a
		var b: Vector3 = e.b
		if p.distance_squared_to((a+b)*.5)>pow(a.distance_to(b)*.5+float(e.width)*.5+padding+1.0,2.0):
			continue
		var nearest := Geometry3D.get_closest_point_to_segment(p,a,b)
		if p.distance_to(nearest)<float(e.width)*.5+padding:
			return false
	return true

func _lot_clear(center: Vector3,front: Vector3,edge: Dictionary) -> bool:
	var side := Vector3(front.z,0,-front.x)
	for x in [-3.8,0.0,3.8]:
		for z in [-4.2,0.0,4.2]:
			if not _street_clear(center+side*float(x)+front*float(z),.85,edge):
				return false
	for existing in slots:
		var other: Vector3 = existing.center
		if center.distance_squared_to(other)<76.0:
			return false
	return true

func _make_frontages() -> void:
	var ordered: Array = geography.roads.duplicate()
	ordered.sort_custom(func(a,b): return ((a.a+a.b)*.5).length_squared()<((b.a+b.b)*.5).length_squared())
	var proposals: Array = []
	for edge in ordered:
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var length := a.distance_to(b)
		if length<17.0:
			continue
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		for side in [-1.0,1.0]:
			var outward := right*float(side)
			for i in range(maxi(1,int((length-8.0)/9.0))):
				var p := a+d*(8.5+float(i)*9.0)
				if p.distance_to(b)<5.0:
					continue
				var center := p+outward*(float(edge.width)*.5+1.7+4.5)
				proposals.append({"center":center,"front":-outward,"edge":edge,"curb":p,"outward":outward,"d":d})
	proposals.sort_custom(func(a,b): return a.center.length_squared()<b.center.length_squared())
	for lot in proposals:
		if slots.size()>=680:
			break
		var c: Vector3 = lot.center
		var f: Vector3 = lot.front
		var e: Dictionary = lot.edge
		if not _lot_clear(c,f,e):
			continue
		slots.append(lot)
		if home_root==null and float(e.width)>=6.0:
			_make_humble_home(lot)
		elif service_count<service_names.size() and slots.size()%7==0:
			_facade(lot,slots.size(),service_names[service_count])
			service_count += 1
		else:
			_facade(lot,slots.size(),"")
	# If OSM topology is unusually sparse, do not place a home inside a road.
	if home_root==null:
		push_warning("Pilar-Atarés: no safe home lot found.")
		home_spawn = geography.roads[0].a+Vector3.UP*.9
		van_spawn = home_spawn+Vector3(0,0,5)

func _local_cube(c: Vector3,basis: Basis,p: Vector3,size: Vector3,material: StandardMaterial3D,solid: bool = false) -> void:
	_cube(c+basis*p,size,material,atan2(basis.z.x,basis.z.z),solid)

func _label(words: String,at: Vector3,pixel: float,angle: float,color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = 48
	label.pixel_size = pixel
	label.outline_size = 3
	label.modulate = color
	add_child(label)
	label.position = at
	label.rotation.y = angle
	return label

func _facade(lot: Dictionary,index: int,service: String) -> void:
	var c: Vector3 = lot.center
	var front: Vector3 = lot.front
	var angle := atan2(front.x,front.z)
	var basis := Basis(Vector3.UP,angle)
	var palette: Array[Color] = [Color("#9bafa3"),Color("#b4ab92"),Color("#8eabb1"),Color("#b69883"),Color("#c1b995"),Color("#92918b"),Color("#a8a18c")]
	var plaster := _mat("plaster"+str(index%7),palette[index%7])
	var weathered := _mat("weathered",Color("#8d8574"))
	var stone := _mat("old_stone",Color("#b3aa96"))
	var doors := _mat("old_door",Color("#5e7773"))
	var recess := _mat("dark_recess",Color("#494d47"))
	var iron := _mat("iron",Color("#43433d"))
	var upper := 1+index%3
	var h: float = float(upper)*3.1
	# Deep covered portal, facade behind columns, upper floors above walkway.
	_local_cube(c,basis,Vector3(0,.065,2.8),Vector3(8.8,.13,3.3),stone,true)
	_local_cube(c,basis,Vector3(0,1.55,-1.45),Vector3(8.8,3.1,5.9),plaster,true)
	_local_cube(c,basis,Vector3(0,3.05,0),Vector3(8.8,.24,9.0),stone,true)
	if upper>1:
		_local_cube(c,basis,Vector3(0,3.1+(h-3.1)*.5,0),Vector3(8.8,h-3.1,8.8),plaster,true)
	_local_cube(c,basis,Vector3(0,h+.07,0),Vector3(8.95,.14,9.0),stone)
	for x in [-4.15,-1.4,1.4,4.15]:
		_local_cube(c,basis,Vector3(float(x),1.58,4.10),Vector3(.36,3.0,.36),stone,true)
		_local_cube(c,basis,Vector3(float(x),.18,4.10),Vector3(.52,.31,.52),weathered)
		_local_cube(c,basis,Vector3(float(x),2.96,4.10),Vector3(.50,.21,.50),stone)
	for x in [-2.7,0.0,2.7]:
		_local_cube(c,basis,Vector3(float(x),1.35,1.52),Vector3(1.12,2.55,.06),doors)
		_local_cube(c,basis,Vector3(float(x),2.77,1.56),Vector3(1.34,.16,.12),stone)
		for floor in range(1,upper):
			var y := float(floor)*3.1+1.5
			_local_cube(c,basis,Vector3(float(x),y,4.43),Vector3(1.0,1.85,.07),recess)
			_local_cube(c,basis,Vector3(float(x),y,4.49),Vector3(.05,1.8,.07),doors)
			if index%3!=0:
				_local_cube(c,basis,Vector3(float(x),y-.94,4.63),Vector3(1.65,.15,.55),stone)
				_local_cube(c,basis,Vector3(float(x),y-.43,4.90),Vector3(1.65,.05,.07),iron)
				for k in range(5):
					_local_cube(c,basis,Vector3(float(x)-.7+float(k)*.35,y-.68,4.90),Vector3(.045,.48,.045),iron)
	# Irregular weathering patches; graphics deliberately lightweight.
	for k in range(4):
		var px := -3.85+fmod(float(index*17+k*13)*.37,7.7)
		var py := .40+fmod(float(index+k*3)*.73,2.2)
		_local_cube(c,basis,Vector3(px,py,1.514),Vector3(.48+float(k)*.12,.30,.008),weathered)
	if not service.is_empty():
		_local_cube(c,basis,Vector3(0,2.65,1.62),Vector3(5.2,.48,.10),doors)
		_label(service,c+basis*Vector3(0,2.66,1.69),.010,angle,Color("#fff2cb"))
	elif index%13==0 and residents.size()<45:
		_vendor(lot,index)
	elif index%5==0 and residents.size()<65:
		_citizen(lot,index,false)

func _citizen(lot: Dictionary,index: int,sitting: bool) -> Node3D:
	var c: Vector3 = lot.center
	var f: Vector3 = lot.front
	var basis := Basis(Vector3.UP,atan2(f.x,f.z))
	var p := c+basis*Vector3(-2.1,0,2.55)
	var npc := Node3D.new()
	add_child(npc)
	npc.position = p
	npc.rotation.y = atan2(f.x,f.z)
	var skin := _mat("skin_cuba"+str(index%3),[Color("#bc8b65"),Color("#896044"),Color("#d1a47f")][index%3])
	var shirt := _mat("shirt_cuba"+str(index%4),[Color("#77939d"),Color("#ad8954"),Color("#8e6661"),Color("#b9b4a5")][index%4])
	var pants := _mat("pants_cuba",Color("#4d555b"))
	_visual_box(npc,Vector3(0,.92 if not sitting else .82,0),Vector3(.42,.53,.30),shirt)
	_visual_box(npc,Vector3(0,1.38 if not sitting else 1.25,0),Vector3(.32,.34,.31),skin)
	for side in [-1.0,1.0]:
		_visual_box(npc,Vector3(float(side)*.115,.39 if not sitting else .44,.16 if sitting else 0),Vector3(.17,.53,.19),pants)
		_visual_box(npc,Vector3(float(side)*.27,.91,0),Vector3(.13,.40,.15),skin)
	residents.append({"id":"citizen_"+str(index),"node":npc,"role":"vendedor" if sitting else "vecino","home":str(lot.edge.name),"origin":p,"direction":basis.x,"sitting":sitting,"phase":float(index)*.87})
	return npc

func _vendor(lot: Dictionary,index: int) -> void:
	var c: Vector3 = lot.center
	var front: Vector3 = lot.front
	var basis := Basis(Vector3.UP,atan2(front.x,front.z))
	var angle := atan2(front.x,front.z)
	var wood := _mat("vendor_wood",Color("#92724e"))
	_local_cube(c,basis,Vector3(-2.1,.25,2.55),Vector3(.55,.5,.55),wood,true)
	_citizen(lot,index,true)
	_local_cube(c,basis,Vector3(-.95,.55,2.9),Vector3(1.55,.8,.76),wood,true)
	var products: Array[String] = ["Picadillo","Pollo","Cuchillos","Gafas","Frutas","Pan"]
	var name_value: String = products[index%products.size()]
	_label("SE VENDE "+name_value.to_upper(),c+basis*Vector3(-.95,1.38,2.92),.006,angle,Color("#fff4cc"))
	for i in range(3):
		var p := c+basis*Vector3(-1.4+float(i)*.42,1.02,2.9)
		_cube(p,Vector3(.27,.12,.22),_mat("goods"+str(index%3),[Color("#9d6551"),Color("#d4c59f"),Color("#6e795d")][index%3]),angle)
	# Physical selectable sample on table. No purchase is simulated yet.
	var item := StaticBody3D.new()
	item.collision_layer = 16
	item.collision_mask = 0
	add_child(item)
	item.position = c+basis*Vector3(-.95,1.03,3.05)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.45,.35,.35)
	col.shape = shape
	item.add_child(col)
	item.set_meta("product",name_value)
	shop_items.append(item)

func _make_humble_home(lot: Dictionary) -> void:
	var c: Vector3 = lot.center
	var front: Vector3 = lot.front
	var basis := Basis(Vector3.UP,atan2(front.x,front.z))
	var angle := atan2(front.x,front.z)
	home_root = Node3D.new()
	add_child(home_root)
	home_root.transform = Transform3D(basis,c)
	home_edge = lot.edge
	home_spawn = home_root.to_global(Vector3(0,.96,3.35))
	van_spawn = lot.curb+lot.outward*(float(lot.edge.width)*.5-1.25)+Vector3.UP*.06
	var d: Vector3 = lot.d
	van_angle = atan2(d.x,d.z)
	var wall := _mat("home_old",Color("#b4b29a"))
	var trim := _mat("home_trim",Color("#777c66"))
	var wood := _mat("home_wood_cuba",Color("#795b44"))
	var floor_mat := _mat("home_floor_cuba",Color("#b4a89a"))
	var dark := _mat("home_dark_cuba",Color("#504d45"))
	var cloth := _mat("home_cloth",Color("#aaa9a0"))
	_local_cube(c,basis,Vector3(0,.05,0),Vector3(8.8,.10,9),floor_mat,true)
	for x in [-4.3,4.3]:
		_local_cube(c,basis,Vector3(float(x),3.1,-1.45),Vector3(.18,6.2,5.9),wall,true)
	_local_cube(c,basis,Vector3(0,3.1,-4.4),Vector3(8.6,6.2,.18),wall,true)
	for x in [-2.6,2.6]:
		_local_cube(c,basis,Vector3(float(x),1.55,1.55),Vector3(3.5,3.1,.16),wall,true)
	_local_cube(c,basis,Vector3(0,2.76,1.55),Vector3(1.7,.68,.16),wall,true)
	_local_cube(c,basis,Vector3(0,1.16,1.55),Vector3(1.5,2.30,.12),wood,true)
	_local_cube(c,basis,Vector3(0,4.65,1.55),Vector3(8.6,3.1,.18),wall,true)
	_local_cube(c,basis,Vector3(0,6.24,0),Vector3(8.9,.22,9.0),wall,true)
	for x in [-4.1,0.0,4.1]:
		_local_cube(c,basis,Vector3(float(x),1.55,4.0),Vector3(.36,3.1,.36),trim,true)
	# Upper floor, leaving a staircase opening along the east wall.
	_local_cube(c,basis,Vector3(-1.16,3.10,-1.45),Vector3(6.1,.20,5.9),floor_mat,true)
	_local_cube(c,basis,Vector3(3.15,3.10,-3.90),Vector3(2.3,.20,1.05),floor_mat,true)
	_local_cube(c,basis,Vector3(0,3.10,3.0),Vector3(8.8,.20,2.9),wall,true)
	for i in range(16):
		var step_h := float(i+1)*.20
		_local_cube(c,basis,Vector3(3.15,step_h*.5,.95-float(i)*.27),Vector3(1.45,step_h,.28),wood,true)
	# Two upstairs bedrooms, accessible from east corridor.
	for z in [-2.9,.05]:
		var zz: float = float(z)
		_local_cube(c,basis,Vector3(-2.75,3.45,zz),Vector3(1.8,.5,1.65),wood,true)
		_local_cube(c,basis,Vector3(-2.75,3.79,zz),Vector3(1.76,.18,1.60),cloth)
		_local_cube(c,basis,Vector3(-3.35,3.93,zz),Vector3(.40,.18,.75),_mat("pillow",Color("#d5cbbb")))
		_local_cube(c,basis,Vector3(-.65,3.55,zz-.55),Vector3(.60,.70,.58),wood,true)
	_local_cube(c,basis,Vector3(-1.35,4.72,-1.35),Vector3(5.8,3.04,.14),wall,true)
	# Modest ground-floor living room, kitchen and bathroom corner.
	_local_cube(c,basis,Vector3(-2.7,.46,.30),Vector3(1.0,.72,1.9),trim,true)
	_local_cube(c,basis,Vector3(-3.14,.91,.30),Vector3(.18,.68,1.9),trim)
	_local_cube(c,basis,Vector3(-.8,.42,.25),Vector3(.8,.65,.65),wood,true)
	_local_cube(c,basis,Vector3(-.8,.92,.25),Vector3(.55,.37,.24),dark)
	_local_cube(c,basis,Vector3(-2.7,.54,-3.85),Vector3(2.5,.9,.75),wood,true)
	_local_cube(c,basis,Vector3(-2.7,1.03,-3.85),Vector3(2.5,.08,.75),floor_mat)
	_local_cube(c,basis,Vector3(-3.0,1.09,-3.85),Vector3(.52,.08,.45),dark)
	_local_cube(c,basis,Vector3(-.9,.98,-3.9),Vector3(.7,1.8,.75),cloth,true)
	_local_cube(c,basis,Vector3(.65,1.55,-3.05),Vector3(.13,3.0,2.5),wall,true)
	_local_cube(c,basis,Vector3(1.55,.40,-3.90),Vector3(.53,.66,.65),cloth,true)
	_local_cube(c,basis,Vector3(1.55,.80,-3.90),Vector3(.53,.16,.45),cloth)
	for y in [1.0,4.2]:
		_local_cube(c,basis,Vector3(-2.5,float(y)+.55,1.66),Vector3(1.3,1.1,.05),dark)
		for x in range(5):
			_local_cube(c,basis,Vector3(-3.05+float(x)*.27,float(y)+.55,1.71),Vector3(.035,1.1,.04),trim)
	_label("MI CASA",home_root.to_global(Vector3(0,2.64,1.67)),.010,angle,Color("#f1e2c4"))

func interaction_text(at: Vector3) -> String:
	if home_root!=null:
		var p := home_root.to_local(at)
		if absf(p.x)<1.4 and absf(p.z-1.55)<1.65 and p.y<2.6:
			return "[E] Salir de casa" if inside_home else "[E] Entrar a mi casa"
	return ""

func interact(player: CharacterBody3D,avatar: Node3D,legs: Array,arms: Array) -> bool:
	if interaction_text(player.global_position).is_empty():
		return false
	inside_home = not inside_home
	player.global_position = home_root.to_global(Vector3(0,.96,.62 if inside_home else 2.60))
	player.velocity = Vector3.ZERO
	return true

func reset_interaction(avatar: Node3D,legs: Array) -> void:
	inside_home = false
	seated = false
	avatar.position.y = 0.0

func aimed_product(camera: Camera3D,player: CharacterBody3D) -> Node:
	if camera==null or player==null:
		return null
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+direction*7.0,1|16)
	ray.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty():
		return null
	var obj: Node = hit.collider
	if obj.has_meta("product") and player.global_position.distance_to(obj.global_position)<3.0:
		return obj
	return null

func inspect_product(camera: Camera3D,player: CharacterBody3D) -> bool:
	var item := aimed_product(camera,player)
	if item==null:
		return false
	prompt = "Vendedor: Tengo "+String(item.get_meta("product"))+". Compra disponible cuando incorporemos dinero."
	prompt_time = 4.0
	return true

func add_school_bus(original: Node3D) -> void:
	var route := geography.bus_loop(String(home_edge.get("a_id","")),String(home_edge.get("b_id","")))
	if route.size()<4:
		push_warning("Pilar-Atarés: no safe bus loop found in imported road graph.")
		return
	var bus := CharacterBody3D.new()
	bus.name = "SchoolBus_Original"
	bus.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	bus.collision_layer = 1
	bus.collision_mask = 1|4
	add_child(bus)
	original.reparent(bus,true)
	original.position = Vector3.ZERO
	var low := _lowest_mesh_y(original,bus)
	if is_finite(low):
		original.position.y -= low
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.35,2.9,7.65)
	col.shape = shape
	bus.add_child(col)
	col.position.y = 1.48
	bus.position = route[0].lerp(route[1],.4)+Vector3.UP*.055
	travel.append({"node":bus,"route":route,"next":1,"speed":0.0,"stop":0.0})
	print("Pilar-Atarés: original bus loop, ",route.size()," road graph nodes.")

func tick(delta: float) -> void:
	cuba_clock += delta
	prompt_time = maxf(0.0,prompt_time-delta)
	for entry in travel:
		var car: CharacterBody3D = entry.node
		var route: Array = entry.route
		var next: int = int(entry.next)
		var target: Vector3 = route[next]+Vector3.UP*.055
		var diff := target-car.position
		diff.y=0.0
		var distance := diff.length()
		if distance<.28:
			entry.next = (next+1)%route.size()
			entry.stop = .7
			continue
		entry.stop = maxf(0.0,float(entry.stop)-delta)
		var d := diff.normalized()
		var speed := minf(5.0,maxf(1.2,distance*1.5))
		if float(entry.stop)>0.0:
			speed = 0.0
		var ray := PhysicsRayQueryParameters3D.create(car.position+Vector3.UP*.75,car.position+Vector3.UP*.75+d*7.0,1|4)
		ray.exclude = [car.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			speed = 0.0
		entry.speed = move_toward(float(entry.speed),speed,delta*4.0)
		car.rotation.y = lerp_angle(car.rotation.y,atan2(d.x,d.z),minf(delta*4.0,1.0))
		car.velocity = d*minf(float(entry.speed),distance/maxf(delta,.001))
		car.move_and_slide()
	for resident in residents:
		if bool(resident.sitting):
			continue
		var npc: Node3D = resident.node
		var base: Vector3 = resident.origin
		var direction: Vector3 = resident.direction
		var phase: float = cuba_clock*.32+float(resident.phase)
		npc.position = base+direction*sin(phase)*1.2
		var d: Vector3 = direction if cos(phase)>0.0 else -direction
		npc.rotation.y = atan2(d.x,d.z)
