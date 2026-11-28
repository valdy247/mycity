extends Node3D
const VehicleLights = preload("res://vehicle_lights.gd")
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
var corner_sites: Array = []
var corner_jobs: Array = []
var corner_cursor := 0
var corner_clock := 0.0
var corner_pending: Array = []
var corner_unplaced := 0
const CORNER_BATCH := 2
var vehicles: Array = []
var civilian_route: Array = []
var prioritize_home_traffic := false
var home_traffic_routes: Array = []
var home_traffic_clock := 0.0
var home_traffic_target := 6
var home_route_link_keys: Dictionary = {}
var story_van: CharacterBody3D
var story_van_registered := false
var story_van_route: Array = []
var main_circuit_ids: Array[String] = []
var story_van_retry := 0.0
var collection_route: Array = []
var truck_retry := 0.0
const MAX_GARBAGE_SITES := 9
const GARBAGE_SITE_SPACING := 50.0
const MAX_CIVILIAN_CARS := 24
var civilian_limit := MAX_CIVILIAN_CARS
var traffic_jobs: Array = []
var traffic_clock := 0.0
var traffic_phase := 0
var traffic_serial := 0
var indicator_clock := 0.0
var indicator_phase := false
var horn_stream: AudioStreamWAV
var main_links: Dictionary = {}
var neighborhood_links: Dictionary = {}
var neighborhood_candidates: Array = []
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
var litter_material: StandardMaterial3D
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
	query.collision_mask = 1|4|8|16|32
	return get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

# Verify the entire bin footprint, not just the centre. The protected
# index includes sidewalks and road polygons, so explicitly exclude roads.
func _bin_sidewalk_clear(curb: Vector3,d: Vector3) -> bool:
	var side := Vector3(-d.z,0,d.x)
	for x in [-.37,.37]:
		for z in [-1.16,1.16]:
			var at := curb+side*float(x)+d*float(z)
			if world.street_geometry.point_on_road(at): return false
			var q := Vector2(at.x,at.z)
			var probe := PackedVector2Array([q-Vector2(.02,.02),q+Vector2(.02,-.02),q+Vector2(.02,.02),q+Vector2(-.02,.02)])
			var found := false
			for poly in world.street_geometry.near(world.street_geometry.protected_index,probe):
				if Geometry2D.is_point_in_polygon(q,poly):
					found = true
					break
			if not found: return false
	return _free_box(curb,d,Vector3(.80,1.05,2.40))

func _new_site(p: Vector3,d: Vector3,width: float,edge: Dictionary) -> Dictionary:
	var right := Vector3(-d.z,0,d.x)
	var desired := p-d*6.5+right*world.geography.lane_distance(edge,2.3,true)
	var parking: Vector3 = world.street_geometry.safe_stop_on_edge(edge.a,edge.b,desired,6.2,2.3)
	if not Bypass._on_road(world.street_geometry,parking,d,2.3,6.2): return {}
	if not world.street_geometry.intersection_clear_for_stop(parking,6.2,2.3): return {}
	var start: Vector3 = edge.a if d.dot(edge.b-edge.a)>0.0 else edge.b
	var finish: Vector3 = edge.b if d.dot(edge.b-edge.a)>0.0 else edge.a
	if (parking-start).dot(d)<3.5 or (finish-parking).dot(d)<9.0: return {}
	var curb := Vector3.INF
	for inset in [.43,.58,.73,.90]:
		var candidate := p+(parking-desired)+right*(width*.5+float(inset))
		if candidate.distance_to(anchor)<12.0: continue
		var clear := true
		for stop in bus_berths:
			var berth: Vector3 = stop.position
			if berth.distance_to(parking)<17.0 or berth.distance_to(candidate)<12.0:
				clear = false
				break
		if not clear: continue
		for previous in sites:
			var old: Vector3 = previous.curb
			if old.distance_to(candidate)<GARBAGE_SITE_SPACING:
				clear = false
				break
		if not clear or not _bin_sidewalk_clear(candidate,d): continue
		curb = candidate
		break
	if not curb.is_finite(): return {}
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

func _litter(root: Node3D,small: bool) -> void:
	var litter := Node3D.new()
	litter.name = "StreetLitter"
	root.add_child(litter)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(root.global_position.x*137.0+root.global_position.z*79.0))+31
	var palette := [Color("#2c302e"),Color("#3d403a"),Color("#7f775e"),Color("#b5a991"),Color("#535a44")]
	for kind in range(2):
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		var count := (7 if small else 13) if kind==0 else (8 if small else 16)
		for i in range(count):
			var sign_value := -1.0 if i%2==0 else 1.0
			var z := rng.randf_range(.43,.83) if small else rng.randf_range(1.13,1.60)
			var p := Vector3(rng.randf_range(-.27,.25),.11,z*sign_value)
			var dims := Vector3(rng.randf_range(.23,.39),.24,rng.randf_range(.25,.42)) if kind==0 else Vector3(rng.randf_range(.10,.27),.025,rng.randf_range(.12,.32))
			if kind==1: p.y = .022
			var safe := true
			for x in [-.5,.5]:
				for dz in [-.5,.5]:
					if world.street_geometry.point_on_road(root.to_global(p+Vector3(float(x)*dims.x,0,float(dz)*dims.z))): safe = false
			if not safe: continue
			# Keep debris close to the container, never create a new obstacle.
			if not world.pedestrian_segment_clear(root.to_global(p),root.to_global(p)): continue
			transforms.append(Transform3D(Basis(Vector3.UP,rng.randf_range(0.0,TAU)).scaled_local(dims),p))
			colors.append(palette[rng.randi_range(0,palette.size()-1)])
		if transforms.is_empty(): continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = bag_mesh if kind==0 else mesh
		batch.instance_count = transforms.size()
		for i in range(transforms.size()):
			batch.set_instance_transform(i,transforms[i])
			batch.set_instance_color(i,colors[i])
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = batch
		if litter_material==null:
			litter_material = StandardMaterial3D.new()
			litter_material.vertex_color_use_as_albedo = true
			litter_material.roughness = .95
		visual.material_override = litter_material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 65.0
		litter.add_child(visual)

func _fill(site: Dictionary) -> void:
	var root: Node3D = site.root
	var bags: Array = site.bags
	var large := bool(site.large)
	var count := 34 if large else 20
	# Decorative litter uses two instanced meshes, not dozens of new bodies.
	if not root.has_node("StreetLitter"): _litter(root,false)
	for i in range(count):
		var p := Vector3.ZERO
		if i<6:
			p = Vector3(.02,.99+float(i%2)*.16,-.93+floorf(float(i)/2.0)*.57)
		else:
			# Local +X points TOWARD the road. Keep the overflow within
			# the bins' curbside footprint; stack higher instead of wider.
			var slot := i-6
			p = Vector3(-.16+float(slot%2)*.29,1.14+float(floori(float(slot)/8.0))*.25,-.91+float(floori(float(slot%8)/2.0))*.59)
		# The whole bag, including its collision sphere, must clear asphalt.
		var safe := true
		for x in [-.28,.28]:
			for z in [-.28,.28]:
				if world.street_geometry.point_on_road(root.to_global(p+Vector3(float(x),0,float(z)))):
					safe = false
		if not safe: continue
		var bag: Node3D
		if i>=6 and i<14:
			var solid := StaticBody3D.new()
			solid.collision_layer = 1
			solid.collision_mask = 0
			bag = solid
		else: bag = Node3D.new()
		root.add_child(bag)
		bag.position = p
		bag.rotation.y = float(i)*.86
		var colors: Array[Color] = [Color("#353935"),Color("#ccc5ac"),Color("#8a806b"),Color("#d5d0c7"),Color("#5e6c4d")]
		_part(bag,Vector3.ZERO,Vector3(.52,.47,.49),colors[i%colors.size()],bag_mesh)
		if i>=6 and i<14:
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
	if site.is_empty() or (not sites.has(site) and not corner_sites.has(site)): return false
	var root: Node3D = site.root
	var object := Node3D.new()
	root.add_child(object)
	object.position = Vector3(-.05,1.25,-.65)
	_part(object,Vector3.ZERO,Vector3(minf(size_value.x,1.35),minf(size_value.y,.80),minf(size_value.z,.65)),color)
	object.set_meta("discarded_furniture",id)
	site.bags.append(object)
	if float(site.refill)>0.0: site.refill = 0.0
	_schedule_corner_cleanup(site)
	return true

func nearest_disposal_site(at: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var distance := 3.0
	for group in [sites,corner_sites]:
		for site in group:
			var p: Vector3 = site.curb
			var gap := at.distance_to(p)
			if gap<distance:
				distance = gap
				best = site
	return best

func add_household_waste(site: Dictionary,item: Dictionary) -> bool:
	if site.is_empty() or (not sites.has(site) and not corner_sites.has(site)): return false
	var bags: Array = site.bags
	# Avoid unbounded visual growth if many deliveries arrive before pickup.
	if bags.size()>=40:
		notice = "Basurero lleno. Busca otro."
		notice_time = 3.0
		return false
	var root: Node3D = site.root
	var object := Node3D.new()
	root.add_child(object)
	var slot := bags.size()
	object.position = Vector3(-.09,.88+float(slot%4)*.20,-.28+float(slot%3)*.23) if bool(site.get("corner",false)) else Vector3(-.04,1.15+float(slot%4)*.22,-.72+float(slot%4)*.40)
	if String(item.get("kind",""))=="paint_can":
		var can := CylinderMesh.new()
		can.top_radius = .18
		can.bottom_radius = .16
		can.height = .33
		can.radial_segments = 8
		_part(object,Vector3.ZERO,Vector3.ONE,Color("#777f83"),can)
	else:
		_part(object,Vector3.ZERO,Vector3(.43,.39,.42),Color("#353935"),bag_mesh)
	object.set_meta("household_waste",true)
	bags.append(object)
	site.refill = 0.0
	_schedule_corner_cleanup(site)
	return true

func _schedule_corner_cleanup(site: Dictionary) -> void:
	if not bool(site.get("corner",false)): return
	if not corner_pending.has(site):
		site.cleanup_at = Time.get_ticks_msec()+170000
		corner_pending.append(site)

func _corner_footprint(p: Vector3,d: Vector3) -> bool:
	var side := Vector3(-d.z,0,d.x)
	for x in [-.31,.31]:
		for z in [-.42,.42]:
			var at := p+side*float(x)+d*float(z)
			if world.street_geometry.point_on_road(at): return false
			var q := Vector2(at.x,at.z)
			var probe := PackedVector2Array([q-Vector2(.02,.02),q+Vector2(.02,-.02),q+Vector2(.02,.02),q+Vector2(-.02,.02)])
			var found := false
			for poly in world.street_geometry.near(world.street_geometry.protected_index,probe):
				if Geometry2D.is_point_in_polygon(q,poly):
					found = true
					break
			if not found: return false
	if not _free_box(p,d,Vector3(.65,.95,.86)): return false
	for stop in bus_berths:
		var berth: Vector3 = stop.position
		if berth.distance_to(p)<7.0: return false
	for entry in world.npc_doorways:
		var door: Vector3 = entry.threshold
		if door.distance_squared_to(p)>25.0: continue
		var normal: Vector3 = entry.normal
		var flat := Vector3(p.x,door.y,p.z)
		var closest := Geometry3D.get_closest_point_to_segment(flat,door,door+normal*2.5)
		if closest.distance_to(flat)<1.15: return false
	return true

func _place_corner_bin(id: String) -> bool:
	var center: Vector3 = world.geography.points[id]
	for group in [sites,corner_sites]:
		for site in group:
			var at: Vector3 = site.curb
			if at.distance_to(center)<12.0: return true
	for edge in world.geography.junctions[id]:
		if not bool(edge.driveable): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var far := b if a.distance_squared_to(center)<b.distance_squared_to(center) else a
		var d := (far-center).normalized()
		var length := center.distance_to(far)
		if length<6.0: continue
		var side := Vector3(-d.z,0,d.x)
		for meters in [5.5,7.5,10.0,13.0]:
			if float(meters)>length-2.0: continue
			for sign_value in [-1.0,1.0]:
				for inset in [.42,.65,.85]:
					var p := center+d*float(meters)+side*float(sign_value)*(float(edge.width)*.5+float(inset))
					if not _corner_footprint(p,d): continue
					var root := Node3D.new()
					add_child(root)
					root.position = p+Vector3.UP*.07
					root.rotation.y = atan2(d.x,d.z)
					_part(root,Vector3(0,.39,0),Vector3(.57,.74,.76),Color("#2f6389"))
					_part(root,Vector3(0,.79,0),Vector3(.64,.08,.82),Color("#344d59"))
					_part(root,Vector3(.04,.89,0),Vector3(.40,.32,.45),Color("#353935"),bag_mesh)
					var site := {"root":root,"curb":root.global_position,"bags":[],"refill":0.0,"corner":true}
					corner_sites.append(site)
					_litter(root,true)
					return true
	return false

func _prepare_corner_jobs() -> void:
	for id in world.geography.junctions:
		var edges: Array = world.geography.junctions[id]
		var arms: Dictionary = {}
		for edge in edges:
			if not bool(edge.driveable): continue
			var other := String(edge.b_id) if String(edge.a_id)==String(id) else String(edge.a_id)
			arms[other] = true
		if arms.size()>=3: corner_jobs.append(String(id))

func _tick_corner_bins(delta: float) -> void:
	corner_clock += delta
	if corner_clock<.25: return
	corner_clock = 0.0
	for i in range(CORNER_BATCH):
		if corner_cursor>=corner_jobs.size(): break
		if not _place_corner_bin(String(corner_jobs[corner_cursor])): corner_unplaced += 1
		corner_cursor += 1
		if corner_cursor==corner_jobs.size(): print("Basureros: ",corner_sites.size()," adicionales; ",corner_unplaced," cruces sin sitio seguro.")
	for i in range(corner_pending.size()-1,-1,-1):
		var site: Dictionary = corner_pending[i]
		if Time.get_ticks_msec()<int(site.cleanup_at): continue
		for bag in site.bags:
			if is_instance_valid(bag): _remove_bag(bag)
		site.bags.clear()
		corner_pending.remove_at(i)

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


# Opaque fixed vehicle panels are rendered together by material.
# The turn lamps, night lights and collision are added afterwards.
func _batch_vehicle_shell(root: Node3D) -> void:
	var batches: Dictionary = {}
	var originals: Array[MeshInstance3D] = []
	for child in root.get_children():
		if not child is MeshInstance3D: continue
		var part := child as MeshInstance3D
		var material := part.material_override as StandardMaterial3D
		if material==null or material.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED: continue
		var key := material.get_instance_id()
		if not batches.has(key):
			var builder := SurfaceTool.new()
			builder.begin(Mesh.PRIMITIVE_TRIANGLES)
			batches[key] = {"builder":builder,"material":material}
		var surface: SurfaceTool = batches[key].builder
		surface.append_from(part.mesh,0,part.transform)
		originals.append(part)
	for key in batches:
		var surface: SurfaceTool = batches[key].builder
		var merged := MeshInstance3D.new()
		merged.mesh = surface.commit()
		merged.material_override = batches[key].material
		merged.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(merged)
	for part in originals:
		root.remove_child(part)
		part.queue_free()

func _body(truck: bool,index: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "Camion_Comunales" if truck else "Auto_Monte_"+str(index)
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.collision_layer = 1
	body.collision_mask = 1|4|8|32
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
			# Lada-inspired boxy sedan: shorter hood, upright pillars, black
			# radiator grille, square lamps. Keep the existing road envelope.
			var lada_colors: Array[Color] = [Color("#d8d2b9"),Color("#7d9772"),Color("#a75d4c"),Color("#69879b")]
			paint = lada_colors[posmod(floori(float(index)/5.0),lada_colors.size())]
			_part(body,Vector3(0,.60,0),Vector3(1.78,.49,4.12),paint)
			_part(body,Vector3(0,.88,1.32),Vector3(1.65,.17,1.48),paint)
			_part(body,Vector3(0,.86,-1.54),Vector3(1.65,.16,1.04),paint)
			_part(body,Vector3(0,1.17,-.17),Vector3(1.45,.48,1.96),glass)
			_part(body,Vector3(0,1.45,-.19),Vector3(1.52,.10,1.91),paint)
			_part(body,Vector3(0,.79,2.09),Vector3(1.04,.21,.055),black)
			for slat in range(3):
				_part(body,Vector3(0,.72+float(slat)*.065,2.125),Vector3(.99,.015,.022),chrome)
			for end in [-1.0,1.0]:
				_part(body,Vector3(0,.49,float(end)*2.065),Vector3(1.78,.14,.12),black)
			_part(body,Vector3(0,.59,-2.132),Vector3(.32,.12,.022),Color("#e1ddc8"))
			for side in [-1.0,1.0]:
				var x := float(side)
				for z in [-1.10,-.18,.76]:
					_part(body,Vector3(x*.74,1.17,float(z)),Vector3(.055,.48,.10),paint)
				_part(body,Vector3(x*.895,.80,0),Vector3(.022,.055,3.76),black)
				for z in [-.73,.35]:
					_part(body,Vector3(x*.900,.91,float(z)),Vector3(.024,.045,.14),chrome)
				_part(body,Vector3(x*.65,.79,length*.5+.03),Vector3(.25,.19,.05),Color("#f0e8bd"))
				_part(body,Vector3(x*.65,.79,-length*.5-.03),Vector3(.22,.17,.05),Color("#af4940"))
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
	# Consolidate only static shell pieces before creating the animated lamps.
	_batch_vehicle_shell(body)
	if not truck:
		var indicators: Array = []
		for side in [-1.0,1.0]:
			var pair: Array = []
			for end in [-1.0,1.0]:
				var lamp := _part(body,Vector3(float(side)*.82,.72,float(end)*2.13),Vector3(.12,.085,.025),Color("#ffae36"))
				lamp.visibility_range_end = 65.0
				lamp.hide()
				pair.append(lamp)
			indicators.append(pair)
		body.set_meta("turn_lamps",indicators)
		body.set_meta("driver_style",posmod(index,3))
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(width,2.7 if truck else 1.5,length)
	collision.shape = shape
	body.add_child(collision)
	collision.position.y = shape.size.y*.5+.06
	if truck:
		VehicleLights.attach(body,Vector3(.86,1.02,3.09),Vector3(.95,.88,-3.21),Vector3(.28,.18,.04),Vector3(.17,.12,.04))
	elif index%5!=4:
		VehicleLights.attach(body,Vector3(.70,.85,2.12),Vector3(.72,.82,-2.115),Vector3(.19,.19,.025),Vector3(.14,.15,.025))
	else:
		VehicleLights.attach(body,Vector3(.65,.79,length*.5+.065),Vector3(.65,.79,-length*.5-.065),Vector3(.23,.17,.025),Vector3(.20,.15,.025))
	return body

# Add intermediate points for distributed spawning on long blocks.
# Civilian circuits use the same directed graph as the buses, but
# distribute the cars between inner/outer lanes and neighborhood loops.
func _traffic_route(ids: Array,outer: bool) -> Array:
	var raw: Array = []
	for i in range(ids.size()-1):
		var edge: Dictionary = planner.edges.get(String(ids[i])+":"+String(ids[i+1]),{})
		if edge.is_empty(): return []
		var a: Vector3 = world.geography.points[ids[i]]
		var b: Vector3 = world.geography.points[ids[i+1]]
		var d := (b-a).normalized()
		var length := a.distance_to(b)
		if length<.2: continue
		var offset := Vector3(-d.z,0,d.x)*world.geography.lane_distance(edge,1.83,outer and int(edge.get("lanes_per_direction",1))==2)
		if length>8.0: raw.append({"p":a+d*3.0+offset})
		raw.append({"p":b+offset})
	return _civilian_route(raw)

func _queue_traffic(route: Array,count: int,kind: String,outer: bool = false) -> void:
	if route.size()<5: return
	var distance := 0.0
	for i in range(route.size()):
		var a: Vector3 = route[i].p
		var b: Vector3 = route[(i+1)%route.size()].p
		distance += a.distance_to(b)
	# Bound density by available road length, even on a short map.
	var capacity := mini(count,maxi(1,floori(distance/(65.0 if kind=="neighborhood" else 38.0))))
	for i in range(capacity):
		traffic_jobs.append({"route":route,"kind":kind,"outer":outer,"slot":i,"slots":capacity,"attempts":0,"serial":traffic_serial})
		traffic_serial += 1

func _prepare_secondary_routes() -> void:
	var ids := planner.plan("CERRO",anchor)
	if ids.size()>=6:
		var length := 0.0
		var fresh := 0.0
		for i in range(ids.size()-1):
			var a: Vector3 = world.geography.points[ids[i]]
			var b: Vector3 = world.geography.points[ids[i+1]]
			var span := a.distance_to(b)
			length += span
			if not main_links.has(String(ids[i])+":"+String(ids[i+1])): fresh += span
		if length>0.0 and fresh/length>=.35:
			_queue_traffic(_traffic_route(ids,false),4,"avenue")
			_queue_traffic(_traffic_route(ids,true),2,"avenue",true)
			for i in range(ids.size()-1): main_links[String(ids[i])+":"+String(ids[i+1])] = true
	# Small streets must be actual drivable links with room for a car.
	# Never create a route through a pedestrian alley or private passage.
	var seen: Dictionary = {}
	for edge in planner.edges.values():
		var width := float(edge.width)
		if width<5.6 or width>=8.5 or world._is_monte_edge(edge): continue
		if String(edge.get("kind","")) in ["service","living_street","pedestrian","footway","path"]: continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var mid := (a+b)*.5
		var dist := mid.distance_to(anchor)
		if dist>650.0 or a.distance_to(b)<12.0: continue
		var first := String(edge.a_id)
		var second := String(edge.b_id)
		var key := first+":"+second if first<second else second+":"+first
		if seen.has(key): continue
		seen[key] = true
		neighborhood_candidates.append({"a":first,"b":second,"distance":dist,"key":key})
	neighborhood_candidates.sort_custom(func(a,b): return float(a.distance)<float(b.distance))

func _neighborhood_loop(first: String,last: String) -> Array[String]:
	var empty: Array[String] = []
	if not planner.edges.has(first+":"+last):
		var swap := first
		first = last
		last = swap
	if not planner.edges.has(first+":"+last): return empty
	var u := int(planner.ids[last])
	var v := int(planner.ids[first])
	var reverse := planner.graph.are_points_connected(u,v,false)
	if reverse: planner.graph.disconnect_points(u,v,false)
	var back := planner._path(last,first)
	if reverse: planner.graph.connect_points(u,v,false)
	if back.size()<3: return empty
	var ids: Array[String] = [first]
	ids.append_array(back)
	return ids

func _next_neighborhood() -> bool:
	# At most six graph searches per update. Require a genuine closed
	# route with several narrow links, no immediate U-turn at a dead end.
	for attempt in range(6):
		if neighborhood_candidates.is_empty(): return true
		var candidate: Dictionary = neighborhood_candidates.pop_front()
		var ids := _neighborhood_loop(String(candidate.a),String(candidate.b))
		if ids.size()<5: continue
		var length := 0.0
		var local := 0.0
		var shared := 0.0
		var links: Array = []
		for i in range(ids.size()-1):
			var key := String(ids[i])+":"+String(ids[i+1])
			var edge: Dictionary = planner.edges[key]
			var a: Vector3 = world.geography.points[ids[i]]
			var b: Vector3 = world.geography.points[ids[i+1]]
			var span := a.distance_to(b)
			length += span
			if float(edge.width)<8.5 and not world._is_monte_edge(edge): local += span
			if neighborhood_links.has(key): shared += span
			links.append(key)
		if length<110.0 or length>850.0 or local<length*.40 or shared>length*.30: continue
		var route := _traffic_route(ids,false)
		if route.size()<5: continue
		for key in links: neighborhood_links[key] = true
		_queue_traffic(route,1,"neighborhood")
		traffic_phase += 1
		return traffic_phase>=6
	return false

# Build short, real directed street loops near the rented home's curb.
# Keep the existing long avenue routes; no imaginary roads or vehicle jumps.
func _prepare_home_traffic() -> void:
	if not prioritize_home_traffic or not home_traffic_routes.is_empty(): return
	var candidates: Array = []
	var seen: Dictionary = {}
	for edge in planner.edges.values():
		if float(edge.width)<5.6: continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var nearest := Geometry3D.get_closest_point_to_segment(anchor,a,b)
		if nearest.distance_to(anchor)>125.0 or a.distance_to(b)<8.0: continue
		var first := String(edge.a_id)
		var last := String(edge.b_id)
		var key := first+":"+last if first<last else last+":"+first
		if seen.has(key): continue
		seen[key] = true
		candidates.append({"a":first,"b":last,"distance":nearest.distance_to(anchor)})
	candidates.sort_custom(func(a,b): return float(a.distance)<float(b.distance))
	for candidate in candidates.slice(0,28):
		var ids := _neighborhood_loop(String(candidate.a),String(candidate.b))
		if ids.size()<4: continue
		var length := 0.0
		var close_length := 0.0
		var overlap := 0.0
		var links: Array[String] = []
		for i in range(ids.size()-1):
			var key: String = ids[i]+":"+ids[i+1]
			var a: Vector3 = world.geography.points[ids[i]]
			var b: Vector3 = world.geography.points[ids[i+1]]
			var span := a.distance_to(b)
			length += span
			if ((a+b)*.5).distance_to(anchor)<150.0: close_length += span
			if home_route_link_keys.has(key): overlap += span
			links.append(key)
		if length<95.0 or length>720.0 or close_length<length*.4 or overlap>length*.45: continue
		var route := _traffic_route(ids,false)
		if route.size()<5: continue
		home_traffic_routes.append(route)
		for key in links: home_route_link_keys[key] = true
		if home_traffic_routes.size()>=2: break
	if not home_traffic_routes.is_empty():
		print("MyCity tráfico local: ",home_traffic_routes.size()," circuitos cerca de la casa.")
	else:
		print("MyCity tráfico local: sin circuito corto; se mantienen las rutas generales.")

func _maintain_home_traffic(delta: float) -> void:
	if not prioritize_home_traffic or home_traffic_routes.is_empty(): return
	home_traffic_clock += delta
	if home_traffic_clock<3.0: return
	home_traffic_clock = 0.0
	var present := 0
	var total := 0
	for car in vehicles:
		if bool(car.truck) or not is_instance_valid(car.body): continue
		total += 1
		if String(car.get("traffic_kind",""))=="home": present += 1
	for job in traffic_jobs:
		if String(job.kind)=="home": present += 1
	var target := mini(home_traffic_target,maxi(2,floori(float(civilian_limit)/3.0)))
	if present>=target or total>=civilian_limit: return
	# Retry one vacant slot per pass. Normal collision checks still apply.
	var route: Array = home_traffic_routes[posmod(traffic_serial,home_traffic_routes.size())]
	traffic_jobs.push_front({"route":route,"kind":"home","outer":false,"slot":posmod(traffic_serial,6),"slots":6,"attempts":0,"serial":traffic_serial})
	traffic_serial += 1

func _traffic_tick(delta: float) -> void:
	traffic_clock += delta
	if traffic_clock<.65: return
	traffic_clock = 0.0
	if traffic_phase==0:
		_prepare_secondary_routes()
		traffic_phase = 1
	elif traffic_phase<6:
		if _next_neighborhood(): traffic_phase = 6
	_maintain_home_traffic(.65)
	if traffic_jobs.is_empty(): return
	var total := 0
	for car in vehicles:
		if not bool(car.truck) and is_instance_valid(car.body): total += 1
	if total>=civilian_limit:
		traffic_jobs.clear()
		return
	var job: Dictionary = traffic_jobs.pop_front()
	var before := vehicles.size()
	_make_vehicle(job.route,false,int(job.serial),int(job.slots),int(job.slot),String(job.kind),bool(job.outer))
	if vehicles.size()==before and int(job.attempts)<3:
		job.attempts = int(job.attempts)+1
		job.slot = int(job.slot)+1
		traffic_jobs.append(job)

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

func _small_traffic_street(p: Vector3,d: Vector3) -> bool:
	var nearest: Dictionary = {}
	var best := INF
	for edge in world.geography.roads_near(p,8.0):
		if not bool(edge.driveable): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		if absf((b-a).normalized().dot(d))<.8: continue
		var q := Geometry3D.get_closest_point_to_segment(p,a,b)
		var dist := p.distance_to(q)
		if dist>float(edge.width)*.5 or dist>=best: continue
		nearest = edge
		best = dist
	return not nearest.is_empty() and float(nearest.width)>=5.6 and float(nearest.width)<8.5 and not world._is_monte_edge(nearest)

func _make_vehicle(route: Array,truck: bool,index: int,slots: int = 8,slot: int = -1,kind: String = "avenue",outer: bool = false) -> void:
	var start := -1
	if route.size()<2: return
	var preferred := 0 if truck else floori(float(route.size())*float(posmod(index if slot<0 else slot,maxi(1,slots)))/float(maxi(1,slots)))
	var live: Array = []
	if not truck:
		for node in get_tree().get_nodes_in_group("autonomous_traffic"):
			if node is Node3D and node.is_inside_tree(): live.append(node.global_position)
		if is_instance_valid(player): live.append(player.global_position)
	for step in range(route.size()):
		var i := (preferred+step)%route.size()
		var item: Dictionary = route[i]
		if truck and not item.has("stop"): continue
		var p: Vector3 = item.p
		var clear := true
		for v in avoid:
			var other: Vector3 = v
			if other.distance_to(p)<(6.5 if truck else 21.0):
				clear = false
				break
		if not clear: continue
		if truck and is_instance_valid(player) and player.global_position.distance_to(p)<10.0: continue
		if not truck:
			for other in live:
				if p.distance_to(other)<(24.0 if kind=="neighborhood" else 15.0):
					clear = false
					break
			if not clear: continue
		var next: Vector3 = route[(i+1)%route.size()].p
		var d := (next-p).normalized()
		if item.has("stop"): d = item.stop.direction
		if not truck and not world.street_geometry.intersection_clear_for_stop(p,4.25,1.83): continue
		if not truck and kind=="neighborhood" and not _small_traffic_street(p,d): continue
		if not truck and kind=="home" and p.distance_to(anchor)>180.0: continue
		if not truck and outer:
			if world.street_geometry.four_lane_at(p,d).is_empty(): continue
			var service_clear := true
			for stop in bus_berths:
				if p.distance_to(stop.position)<14.0: service_clear = false
			for site in sites:
				if p.distance_to(site.parking)<14.0: service_clear = false
			if not service_clear: continue
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
	if truck: avoid.append(p)
	var crew: Array = []
	if truck:
		for i in range(2):
			var person := Person.new()
			add_child(person)
			person.setup(700+i,true)
			person.hide()
			crew.append({"node":person,"state":"idle","pause":0.0})
	vehicles.append({"body":body,"route":route,"index":start if truck else (start+1)%route.size(),"speed":0.0,"truck":truck,"crew":crew,"site":{},"blocked":0.0,"cooldown":0.0,"detour":[],"detour_index":0,"resume":0,"traffic_kind":kind})

func _initialize() -> void:
	planner.setup(world.geography)
	var ids := planner.plan("MONTE",anchor)
	main_circuit_ids = ids.duplicate()
	_prepare_home_traffic()
	if ids.size()<5:
		# A missing long avenue circuit must not disable all city traffic.
		if not home_traffic_routes.is_empty():
			civilian_route = home_traffic_routes[0]
			for local_route in home_traffic_routes:
				_queue_traffic(local_route,3,"home")
		else:
			_prepare_secondary_routes()
			traffic_phase = 1
		return
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
		# Serve the connected circuit, including its adjoining streets.
		# Try several positions per block before rejecting that block.
		if sites.size()<MAX_GARBAGE_SITES and width>=6.0 and length>23.0:
			for fraction in [.70,.55,.85,.42]:
				var at := a+d*clampf(length*float(fraction),14.0,length-2.5)
				var site := _new_site(at,d,width,edge)
				if site.is_empty(): continue
				var park: Vector3 = site.parking
				route.append({"p":park,"stop":site})
				break
		route.append({"p":b+lane})
		car_route.append({"p":b+passing_lane})
	if route.size()<5: return
	collection_route = route
	if not sites.is_empty(): _make_vehicle(collection_route,true,0)
	car_route = _civilian_route(car_route)
	civilian_route = car_route
	# Keep the existing rescue circuit. Spread the initial eight cars,
	# then add the other traffic in batches while the city is running.
	for i in range(ids.size()-1):
		main_links[String(ids[i])+":"+String(ids[i+1])] = true
	for i in range(8):
		_make_vehicle(car_route,false,i,8)
	traffic_serial = 8
	# Place local jobs ahead of the extra long-route traffic, preserving the cap.
	for local_route in home_traffic_routes:
		_queue_traffic(local_route,3,"home")
	var outer := _traffic_route(ids,true)
	_queue_traffic(outer,4,"avenue",true)
	print("Comunales: ",sites.size()," puntos de basura; ",vehicles.size()," vehículos iniciales.")
	if sites.is_empty(): print("Comunales: no se encontró un punto de recogida seguro en el circuito.")

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
				q.collision_mask = 1|4|8|32
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

func _build_story_van_route() -> Array:
	var ids: Array[String] = main_circuit_ids
	var route: Array = []
	for i in range(ids.size()-1):
		var edge: Dictionary = planner.edges.get(String(ids[i])+":"+String(ids[i+1]),{})
		if edge.is_empty(): continue
		var a: Vector3 = world.geography.points[ids[i]]
		var b: Vector3 = world.geography.points[ids[i+1]]
		var d := (b-a).normalized()
		var offset := Vector3(-d.z,0,d.x)*world.geography.lane_distance(edge,2.18)
		if a.distance_to(b)>8.0: route.append({"p":a+d*3.0+offset})
		route.append({"p":b+offset})
	route = _civilian_route(route)
	if route.size()<5: route = civilian_route.duplicate(true)
	if route.size()<5 and not home_traffic_routes.is_empty(): route = home_traffic_routes[0].duplicate(true)
	return route

func _register_story_van() -> void:
	if story_van_route.is_empty(): story_van_route = _build_story_van_route()
	var route: Array = story_van_route
	if route.size()<5: return
	for j in range(route.size()):
		var i := (floori(float(route.size())*.5)+j)%route.size()
		var p: Vector3 = route[i].p
		var next: Vector3 = route[(i+1)%route.size()].p
		var d := (next-p).normalized()
		if d.length_squared()<.1 or p.distance_to(player.global_position)<25.0: continue
		if not world.street_geometry.intersection_clear_for_stop(p,5.12,2.18): continue
		if not Bypass._on_road(world.street_geometry,p,d,2.18,5.12): continue
		if not _free_box(p,d,Vector3(2.18,1.9,5.12)): continue
		story_van.global_position = p+Vector3.UP*.055
		story_van.rotation.y = atan2(d.x,d.z)
		story_van.collision_layer = 4
		story_van.collision_mask = 1|4|8|32
		story_van.add_to_group("autonomous_traffic")
		story_van.set_meta("driver_style",1)
		story_van.show()
		vehicles.append({"body":story_van,"route":route,"index":(i+1)%route.size(),"speed":0.0,"truck":false,"crew":[],"site":{},"blocked":0.0,"cooldown":0.0,"detour":[],"detour_index":0,"resume":0,"traffic_kind":"avenue","story_van":true})
		story_van_registered = true
		return

func _drive(vehicle: Dictionary,delta: float) -> void:
	var body: CharacterBody3D = vehicle.body
	var is_story_van := bool(vehicle.get("story_van",false))
	var width := 2.18 if is_story_van else (2.3 if bool(vehicle.truck) else 1.83)
	var half := 2.56 if is_story_van else (3.1 if bool(vehicle.truck) else 2.125)
	var height := 1.9 if is_story_van else (2.8 if bool(vehicle.truck) else 1.65)
	body.set_meta("traffic_priority",half*2.0)
	body.set_meta("traffic_servicing",not vehicle.site.is_empty())
	if not vehicle.site.is_empty():
		Bypass.reset_watchdog(vehicle)
		_collect(vehicle,delta)
		return
	var original: Array = vehicle.route
	var watch_index := int(vehicle.resume) if not vehicle.detour.is_empty() else int(vehicle.index)
	var restored := Bypass.watchdog(vehicle,body,world.street_geometry,original,watch_index,width,half*2.0,height,delta)
	if restored>=0:
		vehicle.index = restored
		vehicle.detour = []
		vehicle.detour_index = 0
		return
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
	if not bool(vehicle.truck):
		var side := Vector3(-body.global_basis.z.z,0,body.global_basis.z.x)
		var lateral := direction.dot(side)
		if active and absf(lateral)>.10: vehicle.turn_signal = 1 if lateral>0.0 else -1
		elif not active: vehicle.turn_signal = 0
	var limit := 6.5 if bool(vehicle.truck) else (6.0 if String(vehicle.get("traffic_kind","avenue")) in ["neighborhood","home"] else 10.5)
	var driving_style := int(body.get_meta("driver_style",1))
	if not bool(vehicle.truck): limit *= float([.88,1.0,1.07][clampi(driving_style,0,2)])
	var speed := minf(limit,maxf(.8,sqrt(2.0*4.0*distance)))
	var next: Vector3 = route[(index+1)%route.size()].p
	var next_dir := (next-target).normalized()
	if direction.dot(next_dir)<.85: speed = minf(speed,maxf(1.0,distance*1.0))
	if active: speed = minf(speed,3.4)
	# A car needs room to steer around a stationary vehicle, not just brake.
	# On straight multi-lane sections, look past intermediate waypoints.
	var gap := .65
	var reach := minf(maxf(5.0,float(vehicle.speed)*float(vehicle.speed)/12.0+3.0),distance+gap)
	if not active and direction.dot(next_dir)>.92 and direction.dot(body.global_transform.basis.z)>.92:
		var lane := world.street_geometry.four_lane_at(body.global_position,direction)
		if not lane.is_empty():
			gap = 3.2
			reach = maxf(reach,13.0)
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
			vehicle.backed_up = 0.0
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

func _traffic_horn(body: CharacterBody3D) -> void:
	if horn_stream==null:
		horn_stream = AudioStreamWAV.new()
		horn_stream.format = AudioStreamWAV.FORMAT_16_BITS
		horn_stream.mix_rate = 22050
		var samples := PackedByteArray()
		samples.resize(13230)
		for i in range(6615):
			var t := float(i)/22050.0
			var envelope := minf(t/.02,1.0)*clampf((.30-t)/.055,0.0,1.0)
			var wave := sin(t*TAU*390.0)*.65+sin(t*TAU*495.0)*.35
			samples.encode_s16(i*2,int(wave*envelope*10000.0))
		horn_stream.data = samples
	var audio := body.get_node_or_null("ClaxonCivil") as AudioStreamPlayer3D
	if audio==null:
		audio = AudioStreamPlayer3D.new()
		audio.name = "ClaxonCivil"
		audio.stream = horn_stream
		audio.unit_size = 6.0
		audio.max_distance = 45.0
		audio.volume_db = -12.0
		body.add_child(audio)
		audio.position = Vector3(0,.8,1.9)
	audio.play()

func _update_indicators(delta: float) -> void:
	indicator_clock += delta
	if indicator_clock<.4: return
	indicator_clock = 0.0
	indicator_phase = not indicator_phase
	for vehicle in vehicles:
		var body: CharacterBody3D = vehicle.body
		if not body.has_meta("turn_lamps"): continue
		var turn_direction := int(vehicle.get("turn_signal",0))
		# Only audible nearby, physically blocked cars may honk, at most once every 12 seconds.
		if not bool(vehicle.get("incident_hold",false)) and not bool(body.get_meta("junction_guard",false)) and camera!=null and body.global_position.distance_squared_to(camera.global_position)<1600.0:
			var threshold := 4.0+float(body.get_meta("driver_style",1))*2.0
			if float(vehicle.get("stalled",0.0))>threshold and Time.get_ticks_msec()>=int(vehicle.get("next_horn",0)):
				vehicle.next_horn = Time.get_ticks_msec()+12000
				_traffic_horn(body)
		if vehicle.detour.is_empty(): turn_direction = 0
		var pairs: Array = body.get_meta("turn_lamps")
		for i in range(2):
			for lamp in pairs[i]:
				lamp.visible = indicator_phase and turn_direction==(1 if i==0 else -1)

func tick(delta: float) -> void:
	_update_indicators(delta)
	if is_instance_valid(story_van) and not story_van_registered and initialized:
		story_van_retry -= delta
		if story_van_retry<=0.0:
			story_van_retry = 2.0
			_register_story_van()
	notice_time = maxf(0.0,notice_time-delta)
	if not initialized:
		initialized = true
		_initialize()
		_prepare_corner_jobs()
	else:
		_traffic_tick(delta)
	if corner_cursor<corner_jobs.size() or not corner_pending.is_empty(): _tick_corner_bins(delta)
	# If all berths were occupied at startup, retry without duplicating trucks.
	truck_retry += delta
	if truck_retry>=15.0 and not collection_route.is_empty() and not sites.is_empty():
		truck_retry = 0.0
		var has_truck := false
		for vehicle in vehicles:
			if bool(vehicle.truck) and is_instance_valid(vehicle.body):
				has_truck = true
				break
		if not has_truck: _make_vehicle(collection_route,true,0)
	for vehicle in vehicles:
		if bool(vehicle.get("incident_hold",false)): continue
		_drive(vehicle,delta)
	for site in sites:
		if float(site.refill)>0.0:
			site.refill = maxf(0.0,float(site.refill)-delta)
			if float(site.refill)<=0.0: _fill(site)
