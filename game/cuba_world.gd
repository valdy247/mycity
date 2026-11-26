extends "res://city_world.gd"
# Real road centerlines; reconstructed facades and gameplay premises.
const MapData = preload("res://pilar_map.gd")
const StreetGeometry = preload("res://street_geometry.gd")
const TrafficBypass = preload("res://traffic_bypass.gd")
const HavanaTextures = preload("res://havana_textures.gd")
var havana_textures := HavanaTextures.new()
var texture_anchor := Vector3.ZERO
var texture_market := Vector3.ZERO
var texture_kinds: Dictionary = {}
var street_geometry := StreetGeometry.new()
const EDIT_FILE := "user://pilar_atares_edits_v1.json"
var map_edits: Dictionary = {}
var editable_buildings: Dictionary = {}
var original_footprints: Dictionary = {}
var suppressed_infill: Array = []
var home_defaults: Dictionary = {}
var home_building := false
var home_cutaway: Array = []
const INVENTORY_PATH := "user://pilar_atares_inventory.json"
var geography := MapData.new()
var home_root: Node3D
var business_frontage: Node3D
var custom_home_enabled := false
var alborada_lot: Dictionary = {}
var old_home_transform: Transform3D = Transform3D.IDENTITY
var old_home_found := false
var paired_landmarks := false
var home_relocated := false
var home_gps_status := ""
var home_spawn := Vector3.ZERO
var van_spawn := Vector3.ZERO
var van_angle := 0.0
var home_edge: Dictionary = {}
var food_factory: Dictionary = {}
var commerce_sites: Array = []
var garage_home_site: Dictionary = {}
var parts_sites: Array = []
# Walkable portal centre lines and frontage destinations for Monte life.
var monte_walkways: Array = []
# Only actual rendered door panels may be used for simulated indoor visits.
var npc_doorways: Array = []
var pedestrian_router: Node
var pedestrian_body := CapsuleShape3D.new()
var monte_columns: Dictionary = {}
var home_local_door := Vector3(0,0,1.65)
var slots: Array = []
var box_groups: Dictionary = {}
var shop_items: Array = []
var inventory: Dictionary = {}
var residents: Array = []
var road_names: Array = []
var lot_cells: Dictionary = {}
var map_surfaces: Dictionary = {}
var map_collision: Dictionary = {}
var street_collision: Dictionary = {}
var physics_chunks: Dictionary = {}
var static_box_shapes: Dictionary = {}
var detail_batches := 0
var npc_update_time := 0.0
var kept_footprints: Array = []
var market_drawn := false
var market_block: PackedVector2Array = PackedVector2Array()
var mapped_buildings := 0
var plaque_count := 0
var service_count := 0
var public_rooms: Array = []
var current_room := -1
var upstairs := false
var prompt := ""
var prompt_time := 0.0
var travel: Array = []
var cuba_clock := 0.0
const UTILITY_SPACING := 24.0
const UTILITY_CELL := 48.0
var utility_poles: Array = []
var utility_cells: Dictionary = {}
var utility_links: Dictionary = {}
var utility_lamps: Array[OmniLight3D] = []
var utility_lens: StandardMaterial3D
var utility_light_clock := 0.0
var utility_night := false
var service_names: Array[String] = ["BODEGA","CUPET","HOSPITAL • LA DEPENDIENTE","PNR","ESCUELA PRIMARIA","TALLER MECÁNICO","AGROMERCADO","FARMACIA","CORREOS DE CUBA","PARADA DE GUAGUA","CUERPO DE BOMBEROS"]

func load_map() -> bool:
	return geography.load_map()

func setup(builder: Builder) -> void:
	var start_ms := Time.get_ticks_msec()
	pedestrian_body.radius = .27
	pedestrian_body.height = 1.55
	grid_builder = builder
	solid_body = StaticBody3D.new()
	solid_body.collision_layer = 1
	solid_body.collision_mask = 0
	add_child(solid_body)
	road_ground = StaticBody3D.new()
	road_ground.collision_layer = 2
	road_ground.collision_mask = 0
	add_child(road_ground)
	_visual_box(road_ground,Vector3(0,-.25,0),Vector3(2520,.50,2520),_mat("urban_ground",Color("#aaa394")))
	_shape(road_ground,Vector3(0,-.25,0),Vector3(2520,.50,2520))
	_load_inventory()
	texture_anchor = geography.project(23.12230,-82.36677)
	texture_market = geography.project(23.1234716,-82.3659728)
	for place in geography.poi:
		if String(place.id)=="5233654525":
			texture_anchor = place.position
			break
	street_geometry.build(geography)
	var street_ms := Time.get_ticks_msec()
	_load_map_edits()
	_make_osm_streets()
	_make_frontages()
	_make_corner_plaques()
	_make_utility_network()
	var frontage_ms := Time.get_ticks_msec()
	_flush_city_boxes()
	_flush_monte_columns()
	_flush_footprints()
	print("MyCity carga (ms): calles=",street_ms-start_ms,", edificios=",frontage_ms-street_ms,", mallas=",Time.get_ticks_msec()-frontage_ms)
	print("Pilar-Atarés: ",slots.size()," generated facade lots, ",service_count," game services, ",residents.size()," citizens; ",mapped_buildings," OSM building footprints; ",plaque_count," corner plaques.")
	# Real-world source attribution is visible in HUD via main.gd.

# One static body per spatial tile instead of thousands of shapes on a
# single city-wide body. Broad-phase queries can reject distant tiles.
func _chunk_body(tile: Vector2i, layer_id: int) -> StaticBody3D:
	var key := str(tile)+":"+str(layer_id)
	if physics_chunks.has(key):
		return physics_chunks[key] as StaticBody3D
	var body := StaticBody3D.new()
	body.collision_layer = layer_id
	body.collision_mask = 0
	add_child(body)
	body.position = Vector3(float(tile.x)*96.0,0,float(tile.y)*96.0)
	physics_chunks[key] = body
	return body

func _textured(base: StandardMaterial3D,at: Vector3) -> StandardMaterial3D:
	if at.distance_squared_to(texture_anchor)>62500.0 and at.distance_squared_to(texture_market)>32400.0:
		return base
	var material_id := base.get_instance_id()
	if texture_kinds.has(material_id):
		var cached: String = texture_kinds[material_id]
		return base if cached.is_empty() else havana_textures.material(base,cached)
	var kind := ""
	for key in mats:
		if mats[key]!=base:
			continue
		var k := String(key)
		if k.begins_with("mapped_wall") or k.begins_with("custom_wall") or k.begins_with("plaster") or k in ["home_old","alborada_wall","market_wall"]:
			kind = "plaster"
		elif k in ["asphalt_cuba"]:
			kind = "asphalt"
		elif k in ["home_floor_cuba","public_floor"]:
			kind = "tile"
		elif k in ["home_wood_cuba","old_door","facade_door","alborada_blue","public_wood"]:
			kind = "wood"
		elif k in ["old_sidewalk","old_stone","facade_trim","home_trim","market_trim"]:
			kind = "stone"
		break
	texture_kinds[material_id] = kind
	return base if kind.is_empty() else havana_textures.material(base,kind)

func _cube(at: Vector3, size: Vector3, material: StandardMaterial3D, angle: float = 0.0, solid: bool = false) -> void:
	material = _textured(material,at)
	var basis := Basis(Vector3.UP,angle)
	var level := 0
	if home_building:
		if at.y-size.y*.5>6.0:
			level = 2
		elif at.y-size.y*.5>=2.94:
			level = 1
	var tile := Vector2i(floori(at.x/96.0),floori(at.z/96.0))
	var origin := Vector3(float(tile.x)*96.0,0,float(tile.y)*96.0)
	# Thin trim, window bars, wires and weathering are close-range detail.
	# Structural geometry and all collisions remain present.
	var detail := not solid and not home_building and minf(size.x,minf(size.y,size.z))<=.15
	var key := str(tile)+":"+str(material.get_instance_id())+":"+str(level)+":"+str(detail)
	if not box_groups.has(key):
		box_groups[key] = {"material":material,"transforms":[],"home_level":level,"origin":origin,"detail":detail}
	box_groups[key].transforms.append(Transform3D(basis.scaled_local(size),at-origin))
	if solid:
		var col := CollisionShape3D.new()
		# Immutable repeated collision dimensions share one shape resource.
		# Each building still has its own collision transform.
		if not static_box_shapes.has(size):
			var shape := BoxShape3D.new()
			shape.size = size
			static_box_shapes[size] = shape
		col.shape = static_box_shapes[size]
		var body := _chunk_body(tile,1)
		body.add_child(col)
		col.transform = Transform3D(basis,at-body.position)

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
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
		instance.position = item.origin
		if bool(item.detail):
			instance.visibility_range_end = 190.0
			instance.visibility_range_end_margin = 12.0
			detail_batches += 1
		if int(item.home_level)>0:
			home_cutaway.append({"node":instance,"level":item.home_level})
	box_groups.clear()

func _line(a: Vector3,b: Vector3,width: float,height: float,y: float,mat: StandardMaterial3D) -> void:
	var v := b-a
	var p := (a+b)*.5+Vector3.UP*y
	_cube(p,Vector3(width,height,v.length()+.15),mat,atan2(v.x,v.z))

func _make_osm_streets() -> void:
	var asphalt := _mat("asphalt_cuba",Color("#555653"))
	var concrete := _mat("old_sidewalk",Color("#a39c89"))
	var stripe := _mat("faded_line",Color("#b3a67d"))
	for poly in street_geometry.roads:
		_draw_street_polygon(poly,.030,asphalt,"road")
	for poly in street_geometry.sidewalks:
		_draw_street_polygon(poly,.061,concrete,"sidewalk")
	for edge in geography.roads:
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var width: float = float(edge.width)
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		# Geometry comes from the shared polygon layer, not overlapping strips.
		if a.distance_to(b)>8 and (width>=8 or _is_monte_edge(edge)) and bool(edge.driveable):
			for i in range(int(a.distance_to(b)/9.0)):
				var p := a+d*(float(i)*9.0+3.0)
				if street_geometry.point_on_road(p) and street_geometry.point_on_road(p+d*2.5):
					_line(p,p+d*2.5,.09,.006,.034,stripe)

# Utility lines are generated from real road topology, not one free end
# per OSM segment. All cable endpoints are registered physical supports.
func _utility_edge(edge: Dictionary) -> bool:
	return bool(edge.driveable) or (float(edge.width)>=2.5 and String(edge.kind) in ["pedestrian","residential","living_street","service","unclassified","primary","secondary","tertiary","road"])

func _utility_cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x/UTILITY_CELL),floori(p.z/UTILITY_CELL))

func _utility_near(p: Vector3,radius: float) -> Array:
	var lo := _utility_cell(p-Vector3(radius,0,radius))
	var hi := _utility_cell(p+Vector3(radius,0,radius))
	var out: Array = []
	for x in range(lo.x,hi.x+1):
		for z in range(lo.y,hi.y+1):
			out.append_array(utility_cells.get(Vector2i(x,z),[]))
	return out

func _utility_open(p: Vector3) -> bool:
	var q := Vector2(p.x,p.z)
	# Keep poles and overhead lines outside building footprints, including
	# procedural arcades. The curb-side furniture strip remains walkable.
	for lot in _lots_near(p):
		var c: Vector3 = lot.center
		if Vector2(c.x,c.z).distance_squared_to(q)>180.0: continue
		if Geometry2D.is_point_in_polygon(q,_lot_polygon(lot)): return false
	for fp in geography.footprints_near(p,.25):
		var lo: Vector3 = fp.low
		var hi: Vector3 = fp.high
		if p.x<lo.x or p.x>hi.x or p.z<lo.z or p.z>hi.z: continue
		if Geometry2D.is_point_in_polygon(q,fp.poly): return false
	if not market_block.is_empty() and Geometry2D.is_point_in_polygon(q,market_block): return false
	return true

func _utility_pole_clear(p: Vector3,edge: Dictionary,outward: Vector3) -> bool:
	var side := Vector3(outward.z,0,-outward.x)
	for q in [p,p+outward*.12,p-outward*.12,p+side*.12,p-side*.12]:
		if street_geometry.point_on_road(q) or not _utility_open(q): return false
	# At junctions never put a post in the swept area of a crossing.
	return _street_clear(p,.13,edge)

# Full 3D beam, with no distance-based detail cutoff: a wire and its
# supports stay visible together. All beams share the existing batches.
func _utility_beam(a: Vector3,b: Vector3,thickness: float,mat: StandardMaterial3D) -> void:
	var d := b-a
	if d.length_squared()<.00001: return
	var at := (a+b)*.5
	var tile := Vector2i(floori(at.x/96.0),floori(at.z/96.0))
	var origin := Vector3(float(tile.x)*96.0,0,float(tile.y)*96.0)
	var key := "utility:"+str(tile)+":"+str(mat.get_instance_id())
	if not box_groups.has(key):
		box_groups[key] = {"material":mat,"transforms":[],"home_level":0,"origin":origin,"detail":false}
	var up := Vector3.UP if absf(d.normalized().dot(Vector3.UP))<.98 else Vector3.FORWARD
	var basis := Basis.looking_at(-d.normalized(),up).scaled_local(Vector3(thickness,thickness,d.length()+.025))
	box_groups[key].transforms.append(Transform3D(basis,at-origin))

func _utility_register(p: Vector3,outward: Vector3,metal: StandardMaterial3D) -> int:
	for id in _utility_near(p,1.3):
		var old: Vector3 = utility_poles[int(id)].p
		if old.distance_to(p)<1.3: return int(id)
	var id := utility_poles.size()
	var head := p-outward*.94+Vector3.UP*6.20
	var contact_a := p+outward*.32+Vector3.UP*6.37
	var contact_b := p-outward*.32+Vector3.UP*6.37
	utility_poles.append({"p":p,"a":contact_a,"b":contact_b,"lamp":head})
	var cell := _utility_cell(p)
	if not utility_cells.has(cell): utility_cells[cell] = []
	utility_cells[cell].append(id)
	# Slim concrete pole; only the post itself has physical collision.
	_cube(p+Vector3.UP*3.27,Vector3(.18,6.42,.18),metal,0,true)
	_utility_beam(p+Vector3.UP*6.26-outward*.48,p+Vector3.UP*6.26+outward*.48,.13,metal)
	for contact in [contact_a,contact_b]:
		_utility_beam(contact-Vector3.UP*.13,contact,.10,metal)
	# Bracket and lamp head face the road, not a house.
	_utility_beam(p+Vector3.UP*5.76,head+Vector3.UP*.10,.10,metal)
	_cube(head+Vector3.UP*.075,Vector3(.30,.15,.38),metal,atan2(outward.x,outward.z))
	# The lens is batched separately and emissive only during the night.
	_utility_beam(head-Vector3.UP*.035-outward*.12,head-Vector3.UP*.035+outward*.12,.19,utility_lens)
	return id

func _utility_span_clear(a: Vector3,b: Vector3) -> bool:
	var length := a.distance_to(b)
	if length>42.0 or length<.5: return false
	# No cable may cut across a facade or a building corner.
	var steps := maxi(1,ceili(length/1.5))
	for i in range(steps+1):
		if not _utility_open(a.lerp(b,float(i)/float(steps))): return false
	return true

func _utility_connect(i: int,j: int,wire: StandardMaterial3D) -> bool:
	if i<0 or j<0 or i==j: return false
	var key := str(mini(i,j))+":"+str(maxi(i,j))
	if utility_links.has(key): return true
	var first: Dictionary = utility_poles[i]
	var second: Dictionary = utility_poles[j]
	var a: Vector3 = first.a
	var b: Vector3 = first.b
	var c: Vector3 = second.a
	var d: Vector3 = second.b
	# Keep the two parallel cables from crossing at orientation changes.
	if a.distance_squared_to(c)+b.distance_squared_to(d)>a.distance_squared_to(d)+b.distance_squared_to(c):
		var swap := c
		c = d
		d = swap
	if not _utility_span_clear(a,c) or not _utility_span_clear(b,d): return false
	for pair in [[a,c],[b,d]]:
		var start: Vector3 = pair[0]
		var finish: Vector3 = pair[1]
		var sag := minf(.40,start.distance_to(finish)*.012)
		var previous := start
		for k in range(1,5):
			var t := float(k)/4.0
			var p := start.lerp(finish,t)-Vector3.UP*(4.0*t*(1.0-t)*sag)
			_utility_beam(previous,p,.034,wire)
			previous = p
	utility_links[key] = true
	return true

# Walk through degree-two road nodes so short OSM segments don't produce
# a separate pole or a dangling wire. Break at crossings and sharp turns.
func _utility_chain(seed: int,from_id: String,edges: Array,incidents: Dictionary,visited: Dictionary) -> Dictionary:
	var segments: Array = []
	var total := 0.0
	var current := seed
	var start := from_id
	var node := from_id
	while not visited.has(current):
		visited[current] = true
		var edge: Dictionary = edges[current]
		var a: Vector3 = edge.a if String(edge.a_id)==node else edge.b
		var b: Vector3 = edge.b if String(edge.a_id)==node else edge.a
		var next_node := String(edge.b_id) if String(edge.a_id)==node else String(edge.a_id)
		var length := a.distance_to(b)
		var direction := (b-a).normalized()
		segments.append({"edge":edge,"a":a,"b":b,"d":direction,"start":total,"length":length})
		total += length
		node = next_node
		var incident: Array = incidents.get(node,[])
		if incident.size()!=2: break
		var next_index := int(incident[1]) if int(incident[0])==current else int(incident[0])
		if visited.has(next_index): break
		var next_edge: Dictionary = edges[next_index]
		var other: Vector3 = next_edge.b if String(next_edge.a_id)==node else next_edge.a
		if direction.dot((other-b).normalized())<.88: break
		if String(edge.name)!=String(next_edge.name): break
		current = next_index
	return {"segments":segments,"length":total,"start":start,"end":node}

func _utility_station(chain: Dictionary,at: float,side: float) -> Dictionary:
	for seg in chain.segments:
		if at>float(seg.start)+float(seg.length)+.001: continue
		var d: Vector3 = seg.d
		var outward := Vector3(-d.z,0,d.x)*side
		var edge: Dictionary = seg.edge
		var a: Vector3 = seg.a
		var center := a+d*clampf(at-float(seg.start),0.0,float(seg.length))
		for offset in [.26,.42,.60]:
			var p := center+outward*(float(edge.width)*.5+float(offset))
			if _utility_pole_clear(p,edge,outward): return {"p":p,"out":outward}
		break
	return {}

func _utility_chain_poles(chain: Dictionary,metal: StandardMaterial3D,wire: StandardMaterial3D) -> Array:
	var total := float(chain.length)
	if total<.7: return []
	var margin := minf(4.0,total*.26)
	var count := maxi(1,ceili(maxf(0.0,total-margin*2.0)/UTILITY_SPACING)+1)
	if total<10.0: count = 1
	var found: Array = []
	var preferred := 1.0
	for i in range(count):
		var station := total*.5 if count==1 else lerpf(margin,total-margin,float(i)/float(count-1))
		var candidate: Dictionary = {}
		var chosen_side := preferred
		for side in [preferred,-preferred]:
			for shift in [0.0,1.5,-1.5,3.0,-3.0,5.0,-5.0]:
				var at := clampf(station+float(shift),.35,total-.35)
				candidate = _utility_station(chain,at,float(side))
				if not candidate.is_empty():
					chosen_side = float(side)
					break
			if not candidate.is_empty(): break
		if candidate.is_empty(): continue
		var p: Vector3 = candidate.p
		var outward: Vector3 = candidate.out
		var id := _utility_register(p,outward,metal)
		if not found.is_empty():
			if int(found.back())==id: continue
			_utility_connect(int(found.back()),id,wire)
		found.append(id)
		preferred = chosen_side
	return found

func _make_utility_network() -> void:
	var metal := _mat("utility_concrete",Color("#77786e"))
	var wire := _mat("utility_wire",Color("#343b3d"))
	utility_lens = _mat("utility_lens",Color("#e9dfc4"))
	utility_lens.emission = Color("#ffda94")
	utility_lens.emission_energy_multiplier = 1.35
	utility_lens.emission_enabled = false
	var edges: Array = []
	var incidents: Dictionary = {}
	for edge in geography.roads:
		if not _utility_edge(edge): continue
		var index := edges.size()
		edges.append(edge)
		for node in [String(edge.a_id),String(edge.b_id)]:
			if not incidents.has(node): incidents[node] = []
			incidents[node].append(index)
	var visited: Dictionary = {}
	var chains: Array = []
	# Start at intersections and road ends; then handle closed loops.
	for node in incidents:
		if incidents[node].size()==2: continue
		for index in incidents[node]:
			if not visited.has(index): chains.append(_utility_chain(int(index),String(node),edges,incidents,visited))
	for index in range(edges.size()):
		if not visited.has(index): chains.append(_utility_chain(index,String(edges[index].a_id),edges,incidents,visited))
	var ends: Dictionary = {}
	var no_support := 0
	for chain in chains:
		var ids := _utility_chain_poles(chain,metal,wire)
		if ids.is_empty():
			no_support += 1
			continue
		for endpoint in [[String(chain.start),int(ids.front())],[String(chain.end),int(ids.back())]]:
			var node: String = endpoint[0]
			if not ends.has(node): ends[node] = []
			if not ends[node].has(endpoint[1]): ends[node].append(endpoint[1])
	# Build a small connected network at each intersection instead of
	# pairing two independent branches of a four-way crossing.
	for node in ends:
		var ids: Array = ends[node]
		var joined: Array = []
		if not ids.is_empty(): joined.append(ids[0])
		while joined.size()<ids.size():
			var pairs: Array = []
			for first in joined:
				var p: Vector3 = utility_poles[int(first)].p
				for second in ids:
					if joined.has(second): continue
					var q: Vector3 = utility_poles[int(second)].p
					pairs.append({"a":int(first),"b":int(second),"distance":p.distance_squared_to(q)})
			pairs.sort_custom(func(a,b): return float(a.distance)<float(b.distance))
			var linked := false
			for pair in pairs:
				if _utility_connect(int(pair.a),int(pair.b),wire):
					joined.append(int(pair.b))
					linked = true
					break
			if not linked: break
	# Some tiny connecting road segments have no usable curb themselves.
	# Connect their neighboring supports across the segment when safe.
	for chain in chains:
		if float(chain.length)>18.0: continue
		var left: Array = ends.get(String(chain.start),[])
		var right: Array = ends.get(String(chain.end),[])
		if left.is_empty() or right.is_empty(): continue
		var pairs: Array = []
		for first in left:
			var p: Vector3 = utility_poles[int(first)].p
			for second in right:
				if first==second: continue
				var q: Vector3 = utility_poles[int(second)].p
				pairs.append({"a":int(first),"b":int(second),"distance":p.distance_squared_to(q)})
		pairs.sort_custom(func(a,b): return float(a.distance)<float(b.distance))
		for pair in pairs:
			if _utility_connect(int(pair.a),int(pair.b),wire): break
	# Single supports on short blocks can join another nearby support only
	# when both actual cables are clear; never render an unsupported end.
	var degrees: Dictionary = {}
	for key in utility_links:
		for id in String(key).split(":"):
			degrees[int(id)] = true
	for id in range(utility_poles.size()):
		if degrees.has(id): continue
		var p: Vector3 = utility_poles[id].p
		var candidates := _utility_near(p,30.0)
		candidates.sort_custom(func(a,b): return p.distance_squared_to(utility_poles[int(a)].p)<p.distance_squared_to(utility_poles[int(b)].p))
		for other in candidates:
			if int(other)==id or p.distance_squared_to(utility_poles[int(other)].p)>900.0: continue
			if _utility_connect(id,int(other),wire): break
	print("Red eléctrica: ",utility_poles.size()," postes / luminarias, ",utility_links.size()," tramos conectados; ",no_support," cadenas sin emplazamiento seguro.")
	# A small reusable pool, not thousands of active lights at once.
	for i in range(8):
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("#ffdaa2")
		lamp.light_energy = 1.15
		lamp.omni_range = 13.0
		lamp.omni_attenuation = 1.25
		lamp.shadow_enabled = false
		add_child(lamp)
		lamp.hide()
		utility_lamps.append(lamp)

func update_utility_lighting(minutes: float,delta: float) -> void:
	utility_light_clock += delta
	if utility_light_clock<.45: return
	utility_light_clock = 0.0
	if utility_lens==null: return
	var night := minutes>=1140.0 or minutes<360.0
	if night!=utility_night:
		utility_night = night
		utility_lens.emission_enabled = night
	var camera := get_viewport().get_camera_3d()
	if not night or camera==null or camera.global_position.y>35.0:
		for lamp in utility_lamps: lamp.hide()
		return
	var at := camera.global_position
	var nearby := _utility_near(at,45.0)
	nearby.sort_custom(func(a,b): return at.distance_squared_to(utility_poles[int(a)].p)<at.distance_squared_to(utility_poles[int(b)].p))
	for i in range(utility_lamps.size()):
		var lamp := utility_lamps[i]
		if i>=nearby.size() or at.distance_squared_to(utility_poles[int(nearby[i])].p)>2025.0:
			lamp.hide()
			continue
		lamp.global_position = utility_poles[int(nearby[i])].lamp
		lamp.show()

func _draw_street_polygon(poly: PackedVector2Array,y: float,mat: StandardMaterial3D,kind: String) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	if tris.is_empty():
		return
	var p := poly[0]
	var tile := Vector2i(floori(p.x/96.0),floori(p.y/96.0))
	mat = _textured(mat,Vector3(float(tile.x)*96.0+48.0,0,float(tile.y)*96.0+48.0))
	var key := kind+":"+str(tile)
	if not map_surfaces.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		surface.set_material(mat)
		map_surfaces[key] = surface
	var st: SurfaceTool = map_surfaces[key]
	if not street_collision.has(tile):
		street_collision[tile] = []
	for idx in tris:
		var v := poly[idx]
		var vertex := Vector3(v.x,y,v.y)
		st.set_normal(Vector3.UP)
		st.add_vertex(vertex)
		street_collision[tile].append(vertex)

func _street_clear(p: Vector3,padding: float,ignore: Dictionary = {}) -> bool:
	for e in geography.roads_near(p,padding+1.0):
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
	var candidate := _lot_polygon({"center":center,"front":front})
	if not street_geometry.clear(candidate):
		return false
	for existing in _lots_near(center):
		var other: Vector3 = existing.center
		if center.distance_squared_to(other)<210.0 and not Geometry2D.intersect_polygons(candidate,_lot_polygon(existing)).is_empty():
			return false
	return true

func _lots_near(p: Vector3) -> Array:
	var k := Vector2i(floori(p.x/24.0),floori(p.z/24.0))
	var result: Array = []
	for x in range(k.x-1,k.x+2):
		for z in range(k.y-1,k.y+2):
			result.append_array(lot_cells.get(Vector2i(x,z),[]))
	return result

func _add_lot(lot: Dictionary) -> void:
	lot["_cached_polygon"] = _lot_polygon(lot)
	slots.append(lot)
	var p: Vector3 = lot.center
	var k := Vector2i(floori(p.x/24.0),floori(p.z/24.0))
	if not lot_cells.has(k):
		lot_cells[k] = []
	lot_cells[k].append(lot)

func _lot_polygon(lot: Dictionary) -> PackedVector2Array:
	if lot.has("_cached_polygon"): return lot._cached_polygon
	var c: Vector3 = lot.center
	var front: Vector3 = lot.front
	var side := Vector3(front.z,0,-front.x)
	var poly := PackedVector2Array()
	var half_width := float(lot.get("lot_width",8.90))*.5
	var half_depth := float(lot.get("lot_depth",9.0))*.5
	for v in [Vector2(-half_width,-half_depth),Vector2(half_width,-half_depth),Vector2(half_width,half_depth),Vector2(-half_width,half_depth)]:
		var p: Vector3 = c+side*float(v.x)+front*float(v.y)
		poly.append(Vector2(p.x,p.z))
	return poly

func _overlaps_footprint(lot: Dictionary) -> bool:
	var shape := _lot_polygon(lot)
	for fp in geography.footprints_near(lot.center,9.0):
		if not Geometry2D.intersect_polygons(shape,fp.poly).is_empty():
			return true
	for fp in suppressed_infill:
		if not Geometry2D.intersect_polygons(shape,fp.poly).is_empty():
			return true
	return false

func _overlaps_game_lot(fp: Dictionary) -> bool:
	var low: Vector3 = fp.low
	var high: Vector3 = fp.high
	var start := Vector2i(floori((low.x-7.0)/24.0),floori((low.z-7.0)/24.0))
	var finish := Vector2i(floori((high.x+7.0)/24.0),floori((high.z+7.0)/24.0))
	for x in range(start.x,finish.x+1):
		for z in range(start.y,finish.y+1):
			for lot in lot_cells.get(Vector2i(x,z),[]):
				if not Geometry2D.intersect_polygons(_lot_polygon(lot),fp.poly).is_empty():
					return true
	return false

func _home_score(lot: Dictionary,anchor: Vector3) -> float:
	var c: Vector3 = lot.center
	var f: Vector3 = lot.front
	var curb: Vector3 = lot.curb
	var side := Vector3(f.z,0,-f.x)
	var result := c.distance_to(anchor)
	if geography.street_label(String(lot.edge.name))!="MONTE":
		result += 250.0
	if (anchor-curb).dot(-f)<0.0:
		result += 75.0
	if (c-anchor).dot(side)<0.0:
		result += 45.0
	return result

# Facing the facade from the street, +basis.x is the viewer's right.
# Move the fictional home to the old shop position, and reconstruct the
# shop on its immediate right. No real private address is persisted.
func _on_monte_alignment(p: Vector3,direction: Vector3) -> bool:
	for edge in geography.roads_near(p,2.0):
		if geography.street_label(String(edge.name))!="MONTE":
			continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		if absf((b-a).normalized().dot(direction))>.94 and Geometry3D.get_closest_point_to_segment(p,a,b).distance_to(p)<1.15:
			return true
	return false

# Placement is a local game preference, not a change to OSM.
const HOME_PLACEMENT_FILE := "user://pilar_home_placement_v3.json"

# Original shop selection: reproduce the exact algorithm used before
# the home/shop relocation. The sign was drawn at front.mid, NOT at
# the closest point on the edge and NOT at the former home parcel.
var original_shop_front: Dictionary = {}
var original_shop_id := ""

func _alborada_anchor() -> Vector3:
	var anchor := geography.project(23.12230,-82.36677)
	for place in geography.poi:
		if String(place.id)=="5233654525":
			anchor = place.position
			break
	var best := 22.0
	original_shop_front = {}
	original_shop_id = ""
	for fp in geography.footprints_near(anchor,20.0):
		var face := _front_edge(fp.poly)
		if face.is_empty():
			continue
		var q := Geometry3D.get_closest_point_to_segment(anchor,face.a,face.b)
		var distance := q.distance_to(anchor)
		if distance<best:
			best = distance
			original_shop_front = face
			original_shop_id = String(fp.id)
	if not original_shop_front.is_empty():
		var midpoint: Vector3 = original_shop_front.mid
		var normal: Vector3 = original_shop_front.normal
		return midpoint-normal*.25
	return anchor

func _saved_home_anchor() -> Dictionary:
	if not FileAccess.file_exists(HOME_PLACEMENT_FILE):
		return {}
	var file := FileAccess.open(HOME_PLACEMENT_FILE,FileAccess.READ)
	if file==null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	if value is Dictionary and value.has("x") and value.has("z"):
		var p := Vector3(float(value.x),0,float(value.z))
		if p.is_finite():
			return {"point":p}
	return {}

func _monte_pair(anchor: Vector3,manual: bool = false) -> Array:
	var best: Array = []
	var best_score := INF
	var best_home: Dictionary = {}
	var best_home_score := INF
	# Find the nearest Monte frontage first. The selected point determines
	# the side of the avenue, and the viewer-facing right is +local X.
	var nearest: Dictionary = {}
	var nearest_distance := INF
	if not manual and not original_shop_front.is_empty():
		nearest = original_shop_front.road
		var original_q := Geometry3D.get_closest_point_to_segment(anchor,nearest.a,nearest.b)
		nearest_distance = original_q.distance_to(anchor)
	for edge in geography.roads_near(anchor,65.0):
		if not manual and not original_shop_front.is_empty():
			break
		if not bool(edge.driveable) or geography.street_label(String(edge.name))!="MONTE":
			continue
		var q := Geometry3D.get_closest_point_to_segment(anchor,edge.a,edge.b)
		if q.distance_to(anchor)<nearest_distance:
			nearest_distance = q.distance_to(anchor)
			nearest = edge
	if nearest.is_empty() or nearest_distance>45.0:
		return []
	var ra: Vector3 = nearest.a
	var rb: Vector3 = nearest.b
	var road_dir := (rb-ra).normalized()
	var reference := Geometry3D.get_closest_point_to_segment(anchor,ra,rb)
	# A mapped segment may end before the shop midpoint. Project onto the
	# frontage line, then check the full protected street geometry.
	if not manual and not original_shop_front.is_empty():
		reference = ra+road_dir*(anchor-ra).dot(road_dir)
	var outward := Vector3(-road_dir.z,0,road_dir.x)
	if outward.dot(anchor-reference)<0.0:
		outward = -outward
	var front := -outward
	if not manual and not original_shop_front.is_empty():
		var normal: Vector3 = original_shop_front.normal
		if normal.dot(front)<0.0:
			outward = -outward
			front = -outward
	var right := Vector3(front.z,0,-front.x)
	# OSM splits one street into many short segments; don't require the
	# two buildings to fit inside a single segment.
	for shift in [0.0,-.5,.5,-1.0,1.0,-2.0,2.0,-3.0,3.0,-4.0,4.0,-5.0,5.0,-6.0,6.0,-8.0,8.0,-10.0,10.0,-12.0,12.0,-15.0,15.0,-18.0,18.0]:
		if manual and absf(float(shift))>4.0:
			continue
		var curb := reference+right*float(shift)
		var shop_curb := curb+right*9.12
		if manual and (not _on_monte_alignment(curb,road_dir) or not _on_monte_alignment(shop_curb,road_dir)):
			continue
		if not manual and original_shop_front.is_empty() and (not _on_monte_alignment(curb,road_dir) or not _on_monte_alignment(shop_curb,road_dir)):
			continue
		for setback in [1.5,1.8,2.1,2.5,3.0,3.5,4.0,4.5,5.0,6.0]:
			var offset := outward*(float(nearest.width)*.5+float(setback)+4.5)
			var home := {"center":curb+offset,"front":front,"edge":nearest,"curb":curb,"outward":outward,"d":road_dir,"portal":true,"landmark":"home"}
			var shop := {"center":shop_curb+offset,"front":front,"edge":nearest,"curb":shop_curb,"outward":outward,"d":road_dir,"portal":true,"landmark":"alborada"}
			var safe := true
			var home_safe := false
			for lot in [home,shop]:
				var poly := _lot_polygon(lot)
				if not street_geometry.clear(poly):
					safe = false
					break
				for fp in geography.footprints_near(lot.center,12.0):
					var tags: Dictionary = fp.tags
					var label_value := geography.normalized(String(tags.get("name","")))
					var extent: Vector3 = fp.high-fp.low
					var protected := label_value.contains("cuatro caminos") or label_value.contains("mercado unico") or extent.x*extent.z>1500.0
					var change: Dictionary = map_edits.get(String(fp.id),{})
					if (protected or not change.is_empty()) and not Geometry2D.intersect_polygons(poly,fp.poly).is_empty():
						safe = false
						break
				if not safe: break
				if String(lot.landmark)=="home":
					home_safe = true
			if not home_safe:
				continue
			var score := absf(float(shift))*100.0+float(setback)*.6
			if not manual and not original_shop_front.is_empty():
				var original_mid: Vector3 = original_shop_front.mid
				var center: Vector3 = home.center
				var facade_mid := center+front*4.5
				score += facade_mid.distance_to(original_mid)*2.0
			if score<best_home_score:
				best_home_score = score
				best_home = home
			if safe and score<best_score:
				best_score = score
				best = [home,shop]
	# The house is the fixed landmark. Never move it several metres just
	# to make the neighboring store fit. Manual placement still requires both.
	if not manual and not best_home.is_empty() and (best.is_empty() or best_score>best_home_score+105.0):
		return [best_home]
	return best

func _pair_at_parked_van(home: Dictionary) -> Array:
	# The viewer looks opposite the facade normal, so their right is
	# -basis.x, not +basis.x (the building's own right).
	var front: Vector3 = home.front
	var right := Vector3(-front.z,0,front.x)
	var center: Vector3 = home.center
	var curb: Vector3 = home.curb
	var result: Array = [home]
	for distance in [8.96,9.12,9.5,10.0,11.0,12.0]:
		for setback in [0.0,.3,.6,1.0,1.5,2.0,3.0]:
			var shop := home.duplicate(true)
			shop.center = center+right*float(distance)-front*float(setback)
			shop.curb = curb+right*float(distance)
			shop.landmark = "alborada"
			var poly := _lot_polygon(shop)
			if not street_geometry.clear(poly):
				continue
			if not Geometry2D.intersect_polygons(_lot_polygon(home),poly).is_empty():
				continue
			var safe := true
			for fp in geography.footprints_near(shop.center,12.0):
				var tags: Dictionary = fp.tags
				var label_value := geography.normalized(String(tags.get("name","")))
				var extent: Vector3 = fp.high-fp.low
				if (label_value.contains("cuatro caminos") or label_value.contains("mercado unico") or extent.x*extent.z>1500.0 or not map_edits.get(String(fp.id),{}).is_empty()) and not Geometry2D.intersect_polygons(poly,fp.poly).is_empty():
					safe = false
					break
			if safe:
				result.append(shop)
				return result
	return result

# Explicit private GPS pin is read only from the player's local save.
# Never publish the real home coordinates in the shared repository.
const HOME_GPS_FILE := "user://pilar_home_gps.json"

func _private_home_pin() -> Dictionary:
	if not FileAccess.file_exists(HOME_GPS_FILE):
		home_gps_status = "GPS casa: sin punto guardado (B > F8)."
		return {}
	var file := FileAccess.open(HOME_GPS_FILE,FileAccess.READ)
	if file==null:
		home_gps_status = "GPS casa: no se pudo leer el archivo local."
		return {"error":home_gps_status}
	var raw := file.get_as_text().strip_edges().trim_prefix("\ufeff")
	file.close()
	var data: Variant = JSON.parse_string(raw)
	if not data is Dictionary or not data.has("lat") or not data.has("lon"):
		home_gps_status = "GPS casa: archivo inválido."
		return {"error":home_gps_status}
	var result := geography.parse_coordinates("%.9f, %.9f" % [float(data.lat),float(data.lon)])
	if result.has("error"):
		home_gps_status = String(result.error)
	else:
		home_gps_status = "GPS casa: punto local leído."
	print(home_gps_status)
	return result

func _is_monte_edge(edge: Dictionary) -> bool:
	if not bool(edge.driveable): return false
	if bool(edge.get("monte_corridor",false)): return true
	if edge.has("_cached_monte"): return bool(edge._cached_monte)
	for name_value in [String(edge.name)]+edge.get("aliases",[]):
		var n := geography.normalized(String(name_value))
		if geography.street_label(String(name_value))=="MONTE" or n.contains("monte") or n.contains("maximo gomez"):
			edge["_cached_monte"] = true
			return true
	edge["_cached_monte"] = false
	return false

func _home_from_gps(pin: Vector3) -> Array:
	# The GPS pin fixes the frontage along Monte, not the middle of a
	# nine-metre-deep building. Keep the exact along-street position
	# and move the footprint only perpendicular to the road as needed.
	var center := Vector3(pin.x,0,pin.z)
	# The approved overhead screenshot shows the avenue running roughly
	# NNE/SSW (34 degrees clockwise from north). A tiny nearby OSM segment
	# previously selected the wrong tangent, turning the entire house.
	# Prefer the actual nearby road matching that visible axis.
	var heading := deg_to_rad(34.0)
	var reference := Vector3(sin(heading),0,-cos(heading))
	var nearest: Dictionary = {}
	var best := INF
	for edge in geography.roads_near(center,40.0):
		if not bool(edge.driveable): continue
		var road_a: Vector3 = edge.a
		var road_b: Vector3 = edge.b
		var tangent := (road_b-road_a).normalized()
		var alignment := absf(tangent.dot(reference))
		if alignment<cos(deg_to_rad(15.0)):
			continue
		var q := Geometry3D.get_closest_point_to_segment(center,road_a,road_b)
		var distance := q.distance_to(center)
		if distance>25.0:
			continue
		var score := distance+(1.0-alignment)*35.0
		if _is_monte_edge(edge):
			score -= 1.0
		if score<best:
			best = score
			nearest = edge
	var matched_axis := not nearest.is_empty()
	if nearest.is_empty():
		nearest = _nearest_street(center)
	if nearest.is_empty():
		home_gps_status = "GPS casa: no existe calle para orientar la fachada."
		return []
	var a: Vector3 = nearest.a
	var b: Vector3 = nearest.b
	var direction := reference
	if matched_axis:
		var tangent := (b-a).normalized()
		direction = tangent if tangent.dot(reference)>0.0 else -tangent
	# Use the actual selected road centreline for parking and determine
	# the facade side from the fixed house point. Do not alter the point.
	var curb := Geometry3D.get_closest_point_to_segment(center,a,b)
	var outward := Vector3(-direction.z,0,direction.x)
	if outward.dot(center-curb)<0.0:
		outward = -outward
	var front := -outward
	var home := {"center":center,"front":front,"edge":nearest,"curb":curb,"outward":outward,"d":direction,"portal":true,"landmark":"home"}
	# The roof, slabs and all portal columns fit inside the full lot.
	# Add a small clearance to avoid edge contact caused by rounding.
	for step in range(251):
		var setback := float(step)*.10
		var candidate := center+outward*setback
		home.center = candidate
		var clearance := home.duplicate()
		clearance.lot_width = 9.10
		clearance.lot_depth = 9.20
		if not street_geometry.clear(_lot_polygon(clearance)):
			continue
		var safe := true
		for fp in geography.footprints_near(candidate,12.0):
			var tags: Dictionary = fp.tags
			var name_value := geography.normalized(String(tags.get("name","")))
			if (name_value.contains("cuatro caminos") or name_value.contains("mercado unico")) and not Geometry2D.intersect_polygons(_lot_polygon(clearance),fp.poly).is_empty():
				safe = false
				break
		if not safe:
			continue
		home_gps_status = "Casa GPS: portal fuera de la acera | ajuste interior %.1f m" % setback
		print(home_gps_status)
		return _gps_home_and_shop(home)
	home_gps_status = "Casa GPS: no cabe la huella sin invadir la calle."
	push_warning(home_gps_status)
	return []

# Fit the shop to its actual available frontage instead of requiring
# another full-size 9x9 house. The house centre and rotation stay fixed.
func _gps_home_and_shop(home: Dictionary) -> Array:
	var front: Vector3 = home.front
	var right := Vector3(-front.z,0,front.x)
	var center: Vector3 = home.center
	var curb: Vector3 = home.curb
	for width_value in [8.9,7.5,6.0,4.5,3.0]:
		var width := float(width_value)
		for depth_value in [9.0,7.0,5.0,3.5]:
			var depth := float(depth_value)
			for setback_value in [0.0,.5,1.0,1.5,2.0,3.0,4.0,5.0,6.0,8.0]:
				var setback := float(setback_value)
				var distance := 4.45+width*.5+.12
				var shop := home.duplicate(true)
				shop.center = center+right*distance-front*(depth*.5-4.5+setback)
				shop.curb = curb+right*distance
				shop.landmark = "alborada"
				shop.lot_width = width
				shop.lot_depth = depth
				if not street_geometry.clear(_lot_polygon(shop)):
					continue
				var safe := true
				for fp in geography.footprints_near(shop.center,12.0):
					var tags: Dictionary = fp.tags
					var label_value := geography.normalized(String(tags.get("name","")))
					var extent: Vector3 = fp.high-fp.low
					if (label_value.contains("cuatro caminos") or label_value.contains("mercado unico") or extent.x*extent.z>1500.0 or not map_edits.get(String(fp.id),{}).is_empty()) and not Geometry2D.intersect_polygons(_lot_polygon(shop),fp.poly).is_empty():
						safe = false
						break
				if safe:
					return [home,shop]
	return [home]

func _make_alborada(lot: Dictionary) -> void:
	if not lot.has("lot_width"):
		_facade(lot,7,"LA ALBORADA")
		return
	var c: Vector3 = lot.center
	var front: Vector3 = lot.front
	var angle := atan2(front.x,front.z)
	var basis := Basis(Vector3.UP,angle)
	var w := float(lot.lot_width)
	var depth := float(lot.lot_depth)
	var z := depth*.5
	var wall := _mat("alborada_wall",Color("#91a9a9"))
	var blue := _mat("alborada_blue",Color("#47677e"))
	var stone := _mat("old_stone",Color("#b3aa96"))
	var dark := _mat("dark_recess",Color("#494d47"))
	var portal_depth := minf(1.7,depth*.28)
	var facade_z := z-portal_depth
	_local_cube(c,basis,Vector3(0,1.55,-portal_depth*.5),Vector3(w-.06,3.1,depth-portal_depth-.04),wall,true)
	_local_cube(c,basis,Vector3(0,.065,z-portal_depth*.5),Vector3(w-.05,.13,portal_depth),stone,true)
	_local_cube(c,basis,Vector3(0,3.2,0),Vector3(w-.03,.25,depth-.03),stone,true)
	_local_cube(c,basis,Vector3(0,4.8,0),Vector3(w-.06,2.95,depth-.05),wall,true)
	_local_cube(c,basis,Vector3(0,6.31,0),Vector3(w-.02,.12,depth-.02),stone,true)
	for side in [-1.0,1.0]:
		var x := float(side)*(w*.5-.24)
		_local_cube(c,basis,Vector3(x,1.55,z-.22),Vector3(.31,3.1,.31),stone,true)
		_local_cube(c,basis,Vector3(float(side)*w*.24,4.75,z-.02),Vector3(minf(w*.32,1.35),1.55,.05),dark)
	_local_cube(c,basis,Vector3(0,1.38,facade_z+.035),Vector3(w*.76,2.25,.06),blue)
	_local_cube(c,basis,Vector3(0,1.55,facade_z+.078),Vector3(w*.62,1.30,.035),dark)
	_local_cube(c,basis,Vector3(0,2.75,facade_z+.08),Vector3(w*.86,.40,.10),blue)
	_label("LA ALBORADA",c+basis*Vector3(0,2.75,facade_z+.16),minf(.010,w*.0016),angle,Color("#fff2cb"))

func request_home_placement(at: Vector3) -> String:
	var pair := _home_from_gps(Vector3(at.x,0,at.z))
	if pair.is_empty():
		return home_gps_status
	var gps := geography.unproject(at)
	var file := FileAccess.open(HOME_GPS_FILE,FileAccess.WRITE)
	if file==null:
		return "No se pudo guardar el punto GPS."
	file.store_string(JSON.stringify({"lat":gps.lat,"lon":gps.lon}))
	file.close()
	return ""

func _make_frontages() -> void:
	var proposals: Array = []
	var public_anchor: Vector3 = _alborada_anchor()
	# The public POI still drives the historic home fallback and shop lookup.
	# It is not the relocation target when the original facade exists.
	var legacy_anchor := geography.project(23.12230,-82.36677)
	for place in geography.poi:
		if String(place.id)=="5233654525":
			legacy_anchor = place.position
			break
	for edge in geography.roads:
		if not bool(edge.driveable) or float(edge.width)<3.5:
			continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var length := a.distance_to(b)
		if length<12.0:
			continue
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		var count := maxi(1,floori((length-7.0)/9.0))
		for side in [-1.0,1.0]:
			var outward := right*float(side)
			for i in range(count):
				var p := a+d*((length-float(count-1)*9.0)*.5+float(i)*9.0)
				var center := p+outward*(float(edge.width)*.5+1.65+4.5)
				proposals.append({"center":center,"front":-outward,"edge":edge,"curb":p,"outward":outward,"d":d,"portal":bool(edge.portal)})
	# Use a public landmark as a general neighborhood reference. The game
	# residence is fictional; do not encode a private dwelling's address.
	var home_candidates: Array = proposals.duplicate()
	for lot in home_candidates:
		lot["_home_score"] = _home_score(lot,legacy_anchor)
	home_candidates.sort_custom(func(a,b): return float(a._home_score)<float(b._home_score))
	for lot in home_candidates:
		var c: Vector3 = lot.center
		if not bool(lot.portal) or c.distance_to(legacy_anchor)<10.0 or not _lot_clear(c,lot.front,lot.edge):
			continue
		# Do not replace the market or a large mapped complex with a house.
		var huge := false
		for fp in geography.footprints_near(c,10.0):
			var extent: Vector3 = fp.high-fp.low
			var contains_shop := Geometry2D.is_point_in_polygon(Vector2(legacy_anchor.x,legacy_anchor.z),fp.poly)
			if (extent.x*extent.z>380.0 or contains_shop) and not Geometry2D.intersect_polygons(_lot_polygon(lot),fp.poly).is_empty():
				huge = true
				break
		if huge: continue
		var legacy_front: Vector3 = lot.front
		old_home_transform = Transform3D(Basis(Vector3.UP,atan2(legacy_front.x,legacy_front.z)),c)
		old_home_found = true
		break
	var manual := _saved_home_anchor()
	var target: Vector3 = manual.get("point",public_anchor)
	var gps := _private_home_pin()
	var pair: Array = []
	var fixed_gps := FileAccess.file_exists(HOME_GPS_FILE)
	if fixed_gps:
		if gps.has("point"):
			pair = _home_from_gps(gps.point)
		if pair.is_empty():
			push_warning("GPS vivienda: la posición indicada no admite la geometría de la casa sin invadir la calle.")
	else:
		pair = _monte_pair(target,not manual.is_empty())
	# The screenshot identifies the white van's parked frontage. Its spawn
	# is derived from the selected residence lot, not the POI. Pin that
	# lot rather than letting the neighboring shop change its position.
	if not fixed_gps and not pair.is_empty():
		var pinned_home: Dictionary = pair[0]
		pair = _pair_at_parked_van(pinned_home)
	elif not fixed_gps and old_home_found:
		for candidate in home_candidates:
			var c: Vector3 = candidate.center
			if c.distance_to(old_home_transform.origin)<.01:
				pair = _pair_at_parked_van(candidate)
				break
	# Keep the old GPS/layout on disk, but do not reserve or render the
	# custom dwelling or its paired shop. Restore geographic frontages.
	var anchor_lot: Dictionary = {}
	if not pair.is_empty():
		anchor_lot = pair[0] if fixed_gps or pair.size()==1 else pair[1]
	elif old_home_found:
		for lot in home_candidates:
			var center: Vector3 = lot.center
			if center.distance_to(old_home_transform.origin)<.01:
				anchor_lot = lot
				break
	if not anchor_lot.is_empty():
		var c: Vector3 = anchor_lot.center
		var front: Vector3 = anchor_lot.front
		var basis := Basis(Vector3.UP,atan2(front.x,front.z))
		home_edge = anchor_lot.edge
		home_spawn = c+basis*Vector3(0,.96,3.35)
		old_home_transform = Transform3D(basis,c)
		old_home_found = true
	else:
		home_edge = _nearest_street(public_anchor)
		home_spawn = public_anchor+Vector3.UP*.96
	home_gps_status = "Vivienda personalizada retirada · Monte en reconstrucción"
	_reserve_food_factory(proposals)
	# Keep special interiors from the prototype in small unrecorded lots.
	proposals.sort_custom(func(a,b): return a.center.distance_squared_to(public_anchor)<b.center.distance_squared_to(public_anchor))
	for lot in proposals:
		if service_count>=service_names.size():
			break
		if lot.center.distance_to(public_anchor)<35.0 or lot.center.length()>1000.0:
			continue
		if not _lot_clear(lot.center,lot.front,lot.edge) or _overlaps_footprint(lot):
			continue
		_add_lot(lot)
		_facade(lot,slots.size(),service_names[service_count])
		service_count += 1
	_reserve_commerce(proposals)
	_reserve_garage_sites(proposals)
	# Geographic footprints are authoritative; procedural infill is secondary.
	_make_mapped_buildings(legacy_anchor)
	proposals.sort_custom(func(a,b): return a.center.length_squared()<b.center.length_squared())
	for lot in proposals:
		if slots.size()>=1400:
			break
		if not _lot_clear(lot.center,lot.front,lot.edge) or _overlaps_footprint(lot):
			continue
		if not market_block.is_empty() and not Geometry2D.intersect_polygons(market_block,_lot_polygon(lot)).is_empty():
			continue
		_add_lot(lot)
		_facade(lot,slots.size(),"")
	_fill_monte_frontage_gaps()
	_place_temporary_business()

# Extrude the original OSM polygon, not a rectangular approximation.
# Combine the visible meshes and collision by spatial tile for the iGPU.
# Fictional wholesale warehouse, reserved before generic buildings are
# rendered. Its location uses the same local-metre road geometry as taxis.
# Fill missing frontage in short, variable-width lots, leaving real
# mapped footprints and protected street/sidewalk surfaces untouched.
func _fill_monte_frontage_gaps() -> void:
	for edge in geography.roads:
		if not _is_monte_edge(edge): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var d := (b-a).normalized()
		var length := a.distance_to(b)
		if length<6.0: continue
		var right := Vector3(-d.z,0,d.x)
		for side in [-1.0,1.0]:
			var outward := right*float(side)
			var cursor := 2.0
			while cursor<length-3.0:
				var placed := false
				for width_value in [8.8,6.0,4.0,2.8]:
					var w := minf(float(width_value),length-2.0-cursor)
					if w<2.8: continue
					var p := a+d*(cursor+w*.5)
					var c := p+outward*(float(edge.width)*.5+1.47+4.5)
					var lot := {"center":c,"front":-outward,"edge":edge,"curb":p,"outward":outward,"d":d,"portal":true,"lot_width":w,"lot_depth":9.0}
					var poly := _lot_polygon(lot)
					if not street_geometry.clear(poly) or _overlaps_footprint(lot): continue
					if not market_block.is_empty() and not Geometry2D.intersect_polygons(poly,market_block).is_empty(): continue
					var free := true
					for other in _lots_near(c):
						if not Geometry2D.intersect_polygons(poly,_lot_polygon(other)).is_empty():
							free = false
							break
					if not free: continue
					_add_lot(lot)
					_monte_infill(lot,slots.size())
					cursor += w+.025
					placed = true
					break
				if not placed: cursor += .65

func _monte_infill(lot: Dictionary,index: int) -> void:
	var c: Vector3 = lot.center
	var front: Vector3 = lot.front
	var basis := Basis(Vector3.UP,atan2(front.x,front.z))
	var angle := atan2(front.x,front.z)
	var w := float(lot.lot_width)
	var h := float(2+index%2)*3.1
	var paint := _mat("monte_wall"+str(index%7),_monte_color(index))
	var lower := _mat("monte_shaded_infill"+str(index%7),_monte_color(index).darkened(.18))
	var trim := _mat("monte_capital",Color("#d1c8b7"))
	var shade := _mat("monte_portal_shade",Color("#817c71"))
	var door := _mat("monte_joinery"+str(index%3),[Color("#397e8d"),Color("#496b62"),Color("#80604b")][index%3])
	_local_cube(c,basis,Vector3(0,1.55,-1.43),Vector3(w-.015,3.1,6.1),lower,true)
	_local_cube(c,basis,Vector3(0,3.05,0),Vector3(w-.015,.24,9.0),trim,true)
	_local_cube(c,basis,Vector3(0,3.1+(h-3.1)*.5,0),Vector3(w-.015,h-3.1,9.0),paint,true)
	_local_cube(c,basis,Vector3(0,.065,2.98),Vector3(w-.015,.13,3.0),shade,true)
	var count := maxi(1,roundi(w/3.0))
	for i in range(count):
		var x := -w*.5+(float(i)+.5)*w/float(count)
		_monte_column(c+basis*Vector3(x,0,4.12),3.0,paint,angle)
		var opening := minf(w/float(count)*.62,1.45)
		_local_cube(c,basis,Vector3(x,1.38,1.65),Vector3(opening,2.55,.075),door)
		_register_npc_door(c+basis*Vector3(x,0,1.69),front,"home",opening)
		for floor in range(1,roundi(h/3.1)):
			var y := float(floor)*3.1+1.50
			_local_cube(c,basis,Vector3(x,y,4.53),Vector3(1.05,1.85,.08),door)
			_local_cube(c,basis,Vector3(x,y-.96,4.68),Vector3(1.43,.14,.40),trim)
	monte_walkways.append({"a":c+basis*Vector3(-w*.5+.15,0,2.85),"b":c+basis*Vector3(w*.5-.15,0,2.85),"door":c+basis*Vector3(0,0,2.10),"kind":"home"})

func _place_temporary_business() -> void:
	var requested := home_spawn
	var chosen: Dictionary = {}
	var best := INF
	for strip in monte_walkways:
		var a: Vector3 = strip.a
		var b: Vector3 = strip.b
		if a.distance_to(b)<2.0: continue
		var p := (a+b)*.5
		var door: Vector3 = strip.door
		var toward := (p-door).normalized()
		if toward.length_squared()<.5: continue
		var score := p.distance_squared_to(requested)
		if score<best:
			best = score
			chosen = {"p":p,"front":toward,"door":door,"a":a,"b":b}
	if chosen.is_empty():
		# Maps without usable portal polygons still have a temporary
		# sidewalk spawn. Do not re-create the removed house.
		if home_edge.is_empty(): home_edge = _nearest_street(requested)
		if home_edge.is_empty(): return
		var ra: Vector3 = home_edge.a
		var rb: Vector3 = home_edge.b
		var d := (rb-ra).normalized()
		var q := Geometry3D.get_closest_point_to_segment(requested,ra,rb)
		var outward := Vector3(-d.z,0,d.x)
		if outward.dot(requested-q)<0.0: outward = -outward
		var sidewalk := q+outward*(float(home_edge.width)*.5+.70)
		chosen = {"p":sidewalk,"front":-outward}
	var front: Vector3 = chosen.front
	var p: Vector3 = chosen.p
	# Invisible interaction reference, not a dwelling or lot reservation.
	business_frontage = Node3D.new()
	business_frontage.name = "Puesto_temporal_Albertico"
	add_child(business_frontage)
	var basis := Basis(Vector3.UP,atan2(front.x,front.z))
	business_frontage.transform = Transform3D(basis,p-basis*Vector3(-2.55,0,2.85))
	home_spawn = p+Vector3.UP*.96+basis.x*.85
	home_edge = _nearest_street(p)
	if not home_edge.is_empty():
		var a: Vector3 = home_edge.a
		var b: Vector3 = home_edge.b
		var d := (b-a).normalized()
		var q := Geometry3D.get_closest_point_to_segment(p,a,b)
		var side := Vector3(-d.z,0,d.x)
		if side.dot(p-q)<0.0:
			side = -side
			d = -d
		van_spawn = q+side*geography.lane_distance(home_edge,2.18,true)+Vector3.UP*.06
		van_angle = atan2(d.x,d.z)

func _reachable_food_nodes(start: String,reverse: bool = false) -> Dictionary:
	var links: Dictionary = geography.graph
	if reverse:
		links = {}
		for id in geography.graph:
			for dest in geography.graph[id]:
				if not links.has(dest): links[dest] = []
				links[dest].append(id)
	var visited: Dictionary = {start:true}
	var pending: Array = [start]
	var cursor := 0
	while cursor<pending.size():
		var id: String = pending[cursor]
		cursor += 1
		for dest in links.get(id,[]):
			if not visited.has(dest):
				visited[dest] = true
				pending.append(dest)
	return visited

func _reserve_food_factory(proposals: Array) -> void:
	var home := home_spawn
	var candidates := proposals.duplicate()
	candidates.sort_custom(func(a,b): return absf(home.distance_to(a.center)-280.0)<absf(home.distance_to(b.center)-280.0))
	var reach: Dictionary = {}
	var return_reach: Dictionary = {}
	if not home_edge.is_empty():
		var id := String(home_edge.a_id)
		reach = _reachable_food_nodes(id)
		return_reach = _reachable_food_nodes(id,true)
	var market := geography.project(23.1234716,-82.3659728)
	for pass_index in range(2):
		for lot in candidates:
			var c: Vector3 = lot.center
			var front: Vector3 = lot.front
			var edge: Dictionary = lot.edge
			var dist := c.distance_to(home)
			if dist<90.0 or dist>1000.0 or c.distance_to(market)<75.0: continue
			if float(edge.width)<5.6: continue
			if pass_index==0 and (dist<170.0 or dist>520.0 or not bool(edge.portal)): continue
			if not reach.is_empty():
				var a_id := String(edge.a_id)
				var b_id := String(edge.b_id)
				if not reach.has(a_id) or not reach.has(b_id) or not return_reach.has(a_id) or not return_reach.has(b_id): continue
			if not _lot_clear(c,front,edge) or _overlaps_footprint(lot): continue
			var basis := Basis(Vector3.UP,atan2(front.x,front.z))
			_add_lot(lot)
			food_factory = {"center":c,"basis":basis,"counter":c+basis*Vector3(-1.6,.96,2.95),"pickup":c+basis*Vector3(1.55,.96,2.95),"road":lot.curb,"name":"MIPYME de alimentos"}
			var wall := _mat("factory_wall",Color("#c8c3ae"))
			var trim := _mat("factory_trim",Color("#638795"))
			var floor_mat := _mat("public_floor",Color("#b9b5a5"))
			var dark := _mat("factory_dark",Color("#454d50"))
			_local_cube(c,basis,Vector3(0,.05,0),Vector3(8.8,.10,9.0),floor_mat,true)
			_local_cube(c,basis,Vector3(0,1.9,-4.30),Vector3(8.7,3.8,.22),wall,true)
			for side in [-1.0,1.0]:
				_local_cube(c,basis,Vector3(float(side)*4.28,1.9,0),Vector3(.22,3.8,8.75),wall,true)
				_local_cube(c,basis,Vector3(float(side)*3.75,1.65,4.25),Vector3(1.0,3.3,.20),trim,true)
			_local_cube(c,basis,Vector3(0,3.70,0),Vector3(8.9,.30,9.0),wall,true)
			_local_cube(c,basis,Vector3(0,3.25,4.28),Vector3(6.3,.55,.18),trim)
			_local_cube(c,basis,Vector3(-1.6,.56,1.58),Vector3(2.5,1.02,.78),dark,true)
			_local_cube(c,basis,Vector3(1.55,.43,1.60),Vector3(2.0,.78,.80),trim,true)
			_label("MIPYME DE ALIMENTOS",c+basis*Vector3(0,3.26,4.40),.010,atan2(front.x,front.z),Color("#fff4d7"))
			return
	push_warning("Misión: no se encontró parcela libre para la fábrica de alimentos.")

# Fictional businesses occupy only free parcels, never mapped buildings.
# Reserve a fictional purchasable residence and parts vendors. The old
# removed personal house remains untouched; the new interior is separate.
func _reserve_garage_sites(proposals: Array) -> void:
	var specs := [
		{"id":"garage_home","name":"CASA EN VENTA","distance":45.0,"paint":Color("#c4b39c")},
		{"id":"parts_taller","name":"TALLER DE ERNESTO","distance":115.0,"paint":Color("#9eaaa8")},
		{"id":"parts_yoyi","name":"REPUESTOS YOYI","distance":205.0,"paint":Color("#c1b48b")}
	]
	var market := geography.project(23.1234716,-82.3659728)
	for lot in proposals:
		lot["_home_distance"] = home_spawn.distance_to(lot.center)
	for spec in specs:
		var candidates := proposals.duplicate()
		candidates.sort_custom(func(a,b): return absf(float(a._home_distance)-float(spec.distance))<absf(float(b._home_distance)-float(spec.distance)))
		for lot in candidates:
			var c: Vector3 = lot.center
			var front: Vector3 = lot.front
			if c.distance_to(home_spawn)<22.0 or c.distance_to(home_spawn)>650.0 or c.distance_to(market)<75.0: continue
			if float(lot.edge.width)<4.2 or not _lot_clear(c,front,lot.edge) or _overlaps_footprint(lot): continue
			var basis := Basis(Vector3.UP,atan2(front.x,front.z))
			_add_lot(lot)
			var site: Dictionary = {"id":spec.id,"name":spec.name,"center":c,"basis":basis,"door":c+basis*Vector3(0,.0,4.45),"road":lot.curb,"edge":lot.edge}
			var wall := _mat("garage_site_"+String(spec.id),spec.paint)
			var trim := _mat("garage_site_trim",Color("#d4c8b4"))
			var door := _mat("garage_site_door",Color("#48686a"))
			var is_home := String(spec.id)=="garage_home"
			if is_home:
				garage_home_site = site
				_local_cube(c,basis,Vector3(0,1.6,0),Vector3(8.8,3.2,8.8),wall,true)
				_local_cube(c,basis,Vector3(0,1.13,4.45),Vector3(1.15,2.25,.12),door)
				_local_cube(c,basis,Vector3(2.35,1.12,4.45),Vector3(2.9,2.22,.14),door)
				for i in range(9):
					_local_cube(c,basis,Vector3(2.35,.15+float(i)*.23,4.53),Vector3(2.85,.025,.035),trim)
				_local_cube(c,basis,Vector3(-2.5,1.65,4.45),Vector3(1.5,1.4,.11),door)
			else:
				parts_sites.append(site)
				_local_cube(c,basis,Vector3(0,.05,0),Vector3(8.8,.10,9),trim,true)
				_local_cube(c,basis,Vector3(0,1.6,-4.3),Vector3(8.7,3.2,.22),wall,true)
				for side in [-1.0,1.0]:
					_local_cube(c,basis,Vector3(float(side)*4.3,1.6,0),Vector3(.20,3.2,8.8),wall,true)
					_local_cube(c,basis,Vector3(float(side)*3.4,1.6,4.2),Vector3(1.7,3.2,.24),wall,true)
				_local_cube(c,basis,Vector3(0,.51,.2),Vector3(3.2,1.02,.75),trim,true)
			_local_cube(c,basis,Vector3(0,3.24,0),Vector3(8.9,.20,9.0),wall,true)
			if not is_home: _label(String(spec.name),c+basis*Vector3(0,2.75,4.5),.008,atan2(front.x,front.z),Color("#f8efd9"))
			break

func _reserve_commerce(proposals: Array) -> void:
	var specs := [
		{"id":"cafe_mimi","name":"CAFETERÍA MIMI","kind":"cafe","contact":"Maritza","owner":"Rafael","distance":65.0,"color":Color("#d2b69a")},
		{"id":"mayorista_sol","name":"MIPYME EL SOL","kind":"wholesale","contact":"Ernesto","owner":"Ernesto","distance":125.0,"color":Color("#9eb8b0")},
		{"id":"cafe_esquina","name":"CAFETERÍA LA ESQUINA","kind":"cafe","contact":"Yanelis","owner":"Omar","distance":175.0,"color":Color("#b6b9d2")},
		{"id":"mayorista_union","name":"MIPYME LA UNIÓN","kind":"wholesale","contact":"Lidia","owner":"Lidia","distance":225.0,"color":Color("#c9b49a")}
	]
	var market := geography.project(23.1234716,-82.3659728)
	for lot in proposals:
		lot["_home_distance"] = home_spawn.distance_to(lot.center)
	for spec in specs:
		var candidates := proposals.duplicate()
		candidates.sort_custom(func(a,b): return absf(float(a._home_distance)-float(spec.distance))+(0.0 if _is_monte_edge(a.edge) else 180.0)<absf(float(b._home_distance)-float(spec.distance))+(0.0 if _is_monte_edge(b.edge) else 180.0))
		for lot in candidates:
			var c: Vector3 = lot.center
			var front: Vector3 = lot.front
			if c.distance_to(home_spawn)<26.0 or c.distance_to(home_spawn)>450.0 or c.distance_to(market)<75.0: continue
			if float(lot.edge.width)<4.2: continue
			if not _lot_clear(c,front,lot.edge) or _overlaps_footprint(lot): continue
			var too_close := false
			for other in commerce_sites:
				if c.distance_to(other.center)<30.0: too_close = true
			if too_close: continue
			var basis := Basis(Vector3.UP,atan2(front.x,front.z))
			_add_lot(lot)
			var site: Dictionary = spec.duplicate()
			site.merge({"center":c,"basis":basis,"entrance":c+basis*Vector3(0,.11,4.12),"counter":c+basis*Vector3(0,.11,.55),"clerk":c+basis*Vector3(0,.11,-1.25),"road":lot.curb})
			commerce_sites.append(site)
			var wall := _mat("commerce_"+String(spec.id),spec.color)
			var trim := _mat("commerce_trim",Color("#e6ddc8"))
			var floor_mat := _mat("commerce_floor",Color("#b8b4a8"))
			var desk := _mat("commerce_counter",Color("#695d50"))
			_local_cube(c,basis,Vector3(0,.05,0),Vector3(8.8,.10,9),floor_mat,true)
			_local_cube(c,basis,Vector3(0,1.75,-4.30),Vector3(8.7,3.5,.24),wall,true)
			for side in [-1.0,1.0]:
				_local_cube(c,basis,Vector3(float(side)*4.28,1.75,0),Vector3(.22,3.5,8.75),wall,true)
				_local_cube(c,basis,Vector3(float(side)*3.30,1.65,4.26),Vector3(1.9,3.3,.23),wall,true)
			_local_cube(c,basis,Vector3(0,3.48,0),Vector3(8.9,.22,9),trim,true)
			_local_cube(c,basis,Vector3(0,3.10,4.30),Vector3(4.7,.55,.20),trim)
			_local_cube(c,basis,Vector3(0,.52,-.15),Vector3(3.25,1.04,.68),desk,true)
			_label(String(spec.name),c+basis*Vector3(0,3.12,4.43),.007,atan2(front.x,front.z),Color("#33404b"))
			break

func _face(a: Vector3,b: Vector3,c: Vector3,normal: Vector3,mat: StandardMaterial3D,tile: Vector2i) -> void:
	mat = _textured(mat,Vector3(float(tile.x)*96.0+48.0,0,float(tile.y)*96.0+48.0))
	var key := str(tile)+":"+str(mat.get_instance_id())
	if not map_surfaces.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_material(mat)
		map_surfaces[key] = surface
	var st: SurfaceTool = map_surfaces[key]
	for vertex in [a,b,c]:
		st.set_normal(normal)
		st.add_vertex(vertex)
	if not map_collision.has(tile):
		map_collision[tile] = []
	map_collision[tile].append_array([a,b,c])

func _extrude(poly: PackedVector2Array,bottom: float,top: float,mat: StandardMaterial3D,tile: Vector2i) -> bool:
	var triangles := Geometry2D.triangulate_polygon(poly)
	if triangles.is_empty():
		return false
	for i in range(0,triangles.size(),3):
		var a := poly[triangles[i]]
		var b := poly[triangles[i+1]]
		var c := poly[triangles[i+2]]
		_face(Vector3(a.x,top,a.y),Vector3(b.x,top,b.y),Vector3(c.x,top,c.y),Vector3.UP,mat,tile)
		# An underside is required for walkable arcades.
		if bottom>0.1:
			_face(Vector3(c.x,bottom,c.y),Vector3(b.x,bottom,b.y),Vector3(a.x,bottom,a.y),Vector3.DOWN,mat,tile)
	var clockwise := Geometry2D.is_polygon_clockwise(poly)
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i+1)%poly.size()]
		var av := Vector3(a.x,bottom,a.y)
		var bv := Vector3(b.x,bottom,b.y)
		var at := Vector3(a.x,top,a.y)
		var bt := Vector3(b.x,top,b.y)
		var normal := Vector3(b.y-a.y,0,a.x-b.x).normalized()
		if clockwise:
			normal = -normal
		_face(av,at,bt,normal,mat,tile)
		_face(av,bt,bv,normal,mat,tile)
	return true

func _flush_footprints() -> void:
	for key in map_surfaces:
		var surface: SurfaceTool = map_surfaces[key]
		var instance := MeshInstance3D.new()
		instance.mesh = surface.commit()
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	for tile in map_collision:
		var vertices: Array = map_collision[tile]
		var body := _chunk_body(tile,1)
		var local_faces := PackedVector3Array()
		for vertex in vertices:
			local_faces.append(Vector3(vertex)-body.position)
		var collider := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(local_faces)
		collider.shape = shape
		body.add_child(collider)
	for tile in street_collision:
		var vertices: Array = street_collision[tile]
		var body := _chunk_body(tile,2)
		var local_faces := PackedVector3Array()
		for vertex in vertices:
			local_faces.append(Vector3(vertex)-body.position)
		var col := CollisionShape3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(local_faces)
		col.shape = shape
		body.add_child(col)
	street_collision.clear()
	map_surfaces.clear()
	map_collision.clear()

func _nearest_street(p: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var best: float = INF
	for road in geography.roads_near(p,25.0):
		if not bool(road.driveable):
			continue
		var a: Vector3 = road.a
		var b: Vector3 = road.b
		var q := Geometry3D.get_closest_point_to_segment(p,a,b)
		var d := q.distance_squared_to(p)
		if d<best:
			best = d
			result = road
	return result

func _front_edge(poly: PackedVector2Array,monte_only: bool = false) -> Dictionary:
	var best: float = INF
	var result: Dictionary = {}
	for i in range(poly.size()):
		var a := Vector3(poly[i].x,0,poly[i].y)
		var j := (i+1)%poly.size()
		var b := Vector3(poly[j].x,0,poly[j].y)
		if a.distance_to(b)<2.8:
			continue
		var m := (a+b)*.5
		var road := _nearest_monte_street(m,(b-a).normalized()) if monte_only else _nearest_street(m)
		if road.is_empty():
			continue
		var ra: Vector3 = road.a
		var rb: Vector3 = road.b
		var nearest := Geometry3D.get_closest_point_to_segment(m,ra,rb)
		var dist := nearest.distance_to(m)
		if dist>23.0 or absf((b-a).normalized().dot((rb-ra).normalized()))<.65:
			continue
		var tangent := (b-a).normalized()
		var normal := Vector3(-tangent.z,0,tangent.x)
		if normal.dot(nearest-m)<0.0:
			normal = -normal
		if dist<best:
			best = dist
			result = {"a":a,"b":b,"mid":m,"normal":normal,"road":road}
	return result

func _clip_inward(poly: PackedVector2Array,front: Dictionary,depth: float) -> PackedVector2Array:
	var output := PackedVector2Array()
	var m: Vector3 = front.mid
	var n: Vector3 = front.normal
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i+1)%poly.size()]
		var da := Vector3(a.x-m.x,0,a.y-m.z).dot(n)+depth
		var db := Vector3(b.x-m.x,0,b.y-m.z).dot(n)+depth
		if da<=0.0:
			output.append(a)
		if (da<=0.0)!=(db<=0.0):
			output.append(a.lerp(b,da/(da-db)))
	return output

func _building_height(tags: Dictionary,index: int) -> float:
	var raw := String(tags.get("height","")).strip_edges().trim_suffix("m").strip_edges()
	if raw.is_valid_float():
		return clampf(float(raw),2.8,80.0)
	var levels := String(tags.get("building:levels",""))
	if levels.is_valid_float():
		return clampf(float(levels)*3.25,3.0,80.0)
	return float(1+index%3)*3.25

func _market_corner(first: String,second: String,anchor: Vector3) -> Vector3:
	var best := INF
	var answer := Vector3(INF,0,INF)
	for id in geography.junctions:
		var p: Vector3 = geography.points[id]
		if p.distance_to(anchor)>250.0:
			continue
		var has_first := false
		var has_second := false
		for edge in geography.junctions[id]:
			var label: String = geography.normalized(String(edge.name))
			if first=="monte" and geography.street_label(String(edge.name))=="MONTE":
				has_first = true
			elif label.contains(first):
				has_first = true
			if second=="monte" and geography.street_label(String(edge.name))=="MONTE":
				has_second = true
			elif label.contains(second) or (second=="cristina" and label.contains("mexico")):
				has_second = true
		if has_first and has_second and p.distance_to(anchor)<best:
			best = p.distance_to(anchor)
			answer = p
	return answer

func _market_from_intersections(anchor: Vector3) -> PackedVector2Array:
	# A fallback based on all four actual shared street nodes; not a survey.
	var corners: Array[Vector3] = [
		_market_corner("monte","matadero",anchor),
		_market_corner("matadero","cristina",anchor),
		_market_corner("arroyo","cristina",anchor),
		_market_corner("arroyo","monte",anchor)
	]
	var poly := PackedVector2Array()
	for p in corners:
		if not p.is_finite():
			return PackedVector2Array()
		poly.append(Vector2(p.x,p.z))
	if Geometry2D.triangulate_polygon(poly).is_empty():
		return PackedVector2Array()
	var inset := Geometry2D.offset_polygon(poly,-6.5,Geometry2D.JOIN_MITER)
	if inset.is_empty():
		return PackedVector2Array()
	var candidate: PackedVector2Array = inset[0]
	if candidate.size()<3 or not Geometry2D.is_point_in_polygon(Vector2(anchor.x,anchor.z),candidate):
		return PackedVector2Array()
	for i in range(candidate.size()):
		var a := candidate[i]
		var b := candidate[(i+1)%candidate.size()]
		for fraction in [0.0,.25,.5,.75]:
			var v := a.lerp(b,float(fraction))
			if not _street_clear(Vector3(v.x,0,v.y),.2):
				return PackedVector2Array()
	return candidate

func _load_map_edits() -> void:
	if FileAccess.file_exists(EDIT_FILE):
		var file := FileAccess.open(EDIT_FILE,FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				map_edits = parsed
	# Preserve the geographic source and construct a separate editable layer.
	var working: Array = []
	geography.footprint_cells.clear()
	for original in geography.footprints:
		var id := String(original.id)
		original_footprints[id] = original.duplicate(true)
		var changes: Dictionary = map_edits.get(id,{})
		if bool(changes.get("deleted",false)) or absf(float(changes.get("dx",0.0)))>.001 or absf(float(changes.get("dz",0.0)))>.001 or absf(float(changes.get("angle",0.0)))>.001:
			suppressed_infill.append(original)
		if bool(changes.get("deleted",false)):
			continue
		var fp: Dictionary = original.duplicate(true)
		var polygon: PackedVector2Array = fp.poly
		var origin: Vector3 = fp.center
		var dx := float(changes.get("dx",0.0))
		var dz := float(changes.get("dz",0.0))
		var angle := float(changes.get("angle",0.0))
		var changed := PackedVector2Array()
		var middle := Vector2(origin.x,origin.z)
		for p in polygon:
			changed.append((p-middle).rotated(-angle)+middle+Vector2(dx,dz))
		if not street_geometry.clear(changed):
			# OSM widths are estimated. Do not let inferred pavement overlap
			# a solid model: clip only the game rendering, never the source.
			var safe: Array = street_geometry.subtract(changed,street_geometry.protected_index)
			if safe.is_empty():
				continue
			var largest: PackedVector2Array = safe[0]
			for piece in safe:
				if street_geometry.bounds(piece).get_area()>street_geometry.bounds(largest).get_area():
					largest = piece
			changed = largest
		var rect := street_geometry.bounds(changed)
		fp.poly = changed
		fp.center = Vector3(rect.get_center().x,0,rect.get_center().y)
		fp.low = Vector3(rect.position.x,0,rect.position.y)
		fp.high = Vector3(rect.end.x,0,rect.end.y)
		working.append(fp)
		geography._index(geography.footprint_cells,fp.low,fp.high,fp)
	geography.footprints = working

func save_map_edits() -> bool:
	var file := FileAccess.open(EDIT_FILE,FileAccess.WRITE)
	if file==null:
		return false
	file.store_string(JSON.stringify(map_edits,"\t"))
	file.close()
	return true

func _inside_downloaded_map(p: Vector2) -> bool:
	var expanded: bool = geography.source_path.ends_with("v2.osm")
	var a: Vector3 = geography.project(23.1130,-82.3770) if expanded else geography.project(23.1162,-82.3720)
	var b: Vector3 = geography.project(23.1310,-82.3570) if expanded else geography.project(23.1261,-82.3608)
	return p.x>=minf(a.x,b.x) and p.x<=maxf(a.x,b.x) and p.y>=minf(a.z,b.z) and p.y<=maxf(a.z,b.z)

func build_allowed(poly: PackedVector2Array,ignore_id: String = "") -> String:
	if not street_geometry.clear(poly):
		return "Calle, cruce o acera protegida"
	var rect := street_geometry.bounds(poly)
	for p in poly:
		if not _inside_downloaded_map(p):
			return "Fuera del mapa"
	var center := Vector3(rect.get_center().x,0,rect.get_center().y)
	var radius := rect.size.length()*.5+2.0
	for fp in geography.footprints_near(center,radius):
		if String(fp.id)==ignore_id:
			continue
		if not Geometry2D.intersect_polygons(poly,fp.poly).is_empty():
			return "Edificio cartografiado"
	var low := Vector2i(floori((rect.position.x-7.0)/24.0),floori((rect.position.y-7.0)/24.0))
	var high := Vector2i(floori((rect.end.x+7.0)/24.0),floori((rect.end.y+7.0)/24.0))
	var nearby_lots: Array = []
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			nearby_lots.append_array(lot_cells.get(Vector2i(x,z),[]))
	for lot in nearby_lots:
		if not Geometry2D.intersect_polygons(poly,_lot_polygon(lot)).is_empty():
			return "Parcela ocupada"
	if not market_block.is_empty() and not Geometry2D.intersect_polygons(poly,market_block).is_empty():
		return "Plaza de Cuatro Caminos protegida"
	return ""

func _make_mapped_buildings(public_anchor: Vector3) -> void:
	var palette: Array[Color] = [Color("#a5b2a5"),Color("#c3b49b"),Color("#a2b8ba"),Color("#b19a88"),Color("#c3bc9d"),Color("#a4a29a"),Color("#b8ad99")]
	var market_pos: Vector3 = geography.project(23.1234716,-82.3659728)
	var market_poly_id := ""
	var alborada_poly_id := ""
	var best: float = INF
	for fp in geography.footprints_near(market_pos,80.0):
		var tags: Dictionary = fp.tags
		var n: String = geography.normalized(String(tags.get("name","")))
		var extent: Vector3 = fp.high-fp.low
		var poly: PackedVector2Array = fp.poly
		var inside := Geometry2D.is_point_in_polygon(Vector2(market_pos.x,market_pos.z),poly)
		if n.contains("cuatro caminos") or n.contains("mercado unico"):
			market_poly_id = String(fp.id)
			break
		if inside and extent.x*extent.z>1500.0:
			market_poly_id = String(fp.id)
			break
	if market_poly_id.is_empty():
		market_block = _market_from_intersections(market_pos)
	for fp in geography.footprints_near(public_anchor,20.0):
		var front := _front_edge(fp.poly)
		if front.is_empty():
			continue
		var q: Vector3 = Geometry3D.get_closest_point_to_segment(public_anchor,front.a,front.b)
		var dist := q.distance_to(public_anchor)
		if dist<best and dist<22.0:
			best = dist
			alborada_poly_id = String(fp.id)
	for fp in geography.footprints:
		if _overlaps_game_lot(fp):
			continue
		var poly: PackedVector2Array = fp.poly
		if not market_block.is_empty() and not Geometry2D.intersect_polygons(market_block,poly).is_empty():
			continue
		var center: Vector3 = fp.center
		var tile := Vector2i(floori(center.x/96.0),floori(center.z/96.0))
		var tags: Dictionary = fp.tags
		var idx: int = abs(String(fp.id).hash())%7
		var market: bool = String(fp.id)==market_poly_id
		var h: float = _building_height(tags,idx)
		if market and not tags.has("height") and not tags.has("building:levels"):
			h = 10.0
		var edit: Dictionary = map_edits.get(String(fp.id),{})
		var front := _front_edge(poly)
		var monte_front := _front_edge(poly,true)
		var monte := not monte_front.is_empty() and not market
		if monte: front = monte_front
		var base_color: Color = _monte_color(idx) if monte else (palette[idx] if not market else Color("#ded4bc"))
		var paint := String(edit.get("paint",""))
		if Color.html_is_valid(paint):
			base_color = Color(paint)
		var wall_key := ("monte_wall" if monte else "mapped_wall")+str(idx)
		if not paint.is_empty() or market: wall_key = "custom_wall_"+String(fp.id)
		var wall := _mat(wall_key,base_color)
		wall.cull_mode = BaseMaterial3D.CULL_DISABLED
		var portal := false
		var portal_depth := 2.85 if monte else 2.25
		var portal_ceiling := minf(3.4,h-.26) if monte else 3.4
		if not front.is_empty() and bool(edit.get("portal",front.road.portal or monte)) and h>(3.10 if monte else 3.8):
			var clipped := _clip_inward(poly,front,portal_depth)
			# Fall back to the mapped solid if the inset is too small/invalid.
			if clipped.size()>=3 and not Geometry2D.triangulate_polygon(clipped).is_empty():
				var lower_wall := wall
				if monte:
					lower_wall = _mat("monte_shaded_"+wall_key,base_color.darkened(.18))
					lower_wall.cull_mode = BaseMaterial3D.CULL_DISABLED
				portal = _extrude(clipped,0.0,portal_ceiling,lower_wall,tile)
		var ok := _extrude(poly,portal_ceiling if portal else 0.0,h,wall,tile)
		if not ok:
			continue
		mapped_buildings += 1
		kept_footprints.append(fp)
		editable_buildings[String(fp.id)] = {"poly":poly,"center":center,"height":h,"name":String(tags.get("name","Edificio")),"protected":market or String(fp.id)==alborada_poly_id,"front":front}
		if not front.is_empty():
			_detail_front(front,h,idx,portal,market,monte,portal_depth)
			if monte and portal:
				_monte_portal(front,poly,portal_depth,portal_ceiling,idx,base_color)
			if market:
				_market_side_details(poly,front,h)
			var name_value := String(tags.get("name",""))
			if market:
				name_value = "PLAZA DE CUATRO CAMINOS"
				market_drawn = true
			elif String(fp.id)==alborada_poly_id:
				name_value = "" if home_relocated else "LA ALBORADA"
			if home_relocated and geography.normalized(name_value).contains("alborada"):
				name_value = ""
			if not name_value.is_empty() and (market or String(fp.id)==alborada_poly_id or tags.has("amenity") or tags.has("shop")):
				var m: Vector3 = front.mid
				var n: Vector3 = front.normal
				var z: float = -portal_depth+.07 if portal else .08
				_label(name_value.to_upper(),m+n*z+Vector3.UP*2.85,.010,atan2(n.x,n.z),Color("#f5ead0"))
	# Missing source polygon: never invent a market footprint or obstruct roads.
	if not market_drawn and not market_block.is_empty():
		var tile := Vector2i(floori(market_pos.x/96.0),floori(market_pos.z/96.0))
		var wall := _mat("market_wall",Color("#ded4bc"))
		wall.cull_mode = BaseMaterial3D.CULL_DISABLED
		if _extrude(market_block,0.0,10.0,wall,tile):
			var front := _front_edge(market_block)
			if not front.is_empty():
				_detail_front(front,10.0,0,false,true)
				_market_side_details(market_block,front,10.0)
				var m: Vector3 = front.mid
				var n: Vector3 = front.normal
				_label("PLAZA DE CUATRO CAMINOS",m+n*.15+Vector3.UP*3.15,.013,atan2(n.x,n.z),Color("#554d3e"))
			market_drawn = true
			print("Cuatro Caminos: approximate facade from four mapped intersections (not exact building footprint).")
	if not market_drawn:
		print("Cuatro Caminos: no verified market footprint or four safe corners in this OSM extract.")
	if alborada_poly_id.is_empty() and not home_relocated:
		var closest := _nearest_street(public_anchor)
		if not closest.is_empty():
			var a: Vector3 = closest.a
			var b: Vector3 = closest.b
			var q := Geometry3D.get_closest_point_to_segment(public_anchor,a,b)
			var n := (q-public_anchor).normalized()
			_label("LA ALBORADA",public_anchor+Vector3.UP*2.85,.010,atan2(n.x,n.z),Color("#f5ead0"))
		print("La Alborada: named geographic point; building footprint unavailable.")

# Cuatro Caminos: repeated bays, pilasters and upper windows on each
# long street-facing edge. Keep all decoration inside the legal footprint.
func _market_side_details(poly: PackedVector2Array,primary: Dictionary,h: float) -> void:
	var stone := _mat("market_trim",Color("#c0b39b"))
	for i in range(poly.size()):
		var j := (i+1)%poly.size()
		var a := Vector3(poly[i].x,0,poly[i].y)
		var b := Vector3(poly[j].x,0,poly[j].y)
		var length := a.distance_to(b)
		if length<9.0:
			continue
		var mid := (a+b)*.5
		var tangent := (b-a).normalized()
		var n := Vector3(-tangent.z,0,tangent.x)
		var sample := mid+n*.25
		if Geometry2D.is_point_in_polygon(Vector2(sample.x,sample.z),poly):
			n = -n
		var road := _nearest_street(mid)
		if road.is_empty():
			continue
		var road_a: Vector3 = road.a
		var road_b: Vector3 = road.b
		var nearest := Geometry3D.get_closest_point_to_segment(mid,road_a,road_b)
		if nearest.distance_to(mid)>22.0 or n.dot(nearest-mid)<0.0:
			continue
		var count := clampi(roundi(length/4.2),2,32)
		var angle := atan2(n.x,n.z)
		for k in range(count+1):
			var p := a.lerp(b,float(k)/float(count))
			_cube(p-n*.04+Vector3.UP*(h*.48),Vector3(.24,h*.88,.12),stone,angle)
		if mid.distance_to(primary.mid)>1.0:
			_detail_front({"a":a,"b":b,"normal":n,"mid":mid,"road":road},h,0,false,true)

# A checked movement step for scripted NPCs. The capsule stays above
# shallow pavement and detects the whole person rather than a single ray.
func pedestrian_segment_clear(a: Vector3,b: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = pedestrian_body
	query.collision_mask = 1|4|8|16
	query.transform = Transform3D(Basis.IDENTITY,a+Vector3.UP*.95)
	if not space.intersect_shape(query,1).is_empty(): return false
	query.transform = Transform3D(Basis.IDENTITY,b+Vector3.UP*.95)
	if not space.intersect_shape(query,1).is_empty(): return false
	if a.distance_squared_to(b)<.0001: return true
	query.transform = Transform3D(Basis.IDENTITY,a+Vector3.UP*.95)
	query.motion = b-a
	var fraction := space.cast_motion(query)
	if fraction.size()<2 or fraction[0]<.999: return false
	for height in [.25,1.65]:
		var lift := Vector3.UP*float(height)
		var ray := PhysicsRayQueryParameters3D.create(a+lift,b+lift,1|4|8|16)
		ray.hit_from_inside = true
		if not space.intersect_ray(ray).is_empty(): return false
	return true

func _register_npc_door(threshold: Vector3,normal: Vector3,kind: String,width: float) -> void:
	if width<.72: return
	npc_doorways.append({"threshold":threshold,"normal":normal.normalized(),"kind":kind})

func _monte_color(index: int) -> Color:
	var palette: Array[Color] = [Color("#8fbdac"),Color("#dbada7"),Color("#70b7c8"),Color("#d8c096"),Color("#a5c9cb"),Color("#c4a18b"),Color("#e2d1b4")]
	return palette[posmod(index,palette.size())]

func _nearest_monte_street(p: Vector3,tangent: Vector3) -> Dictionary:
	var best := 15.0
	var result: Dictionary = {}
	for edge in geography.roads_near(p,18.0):
		if not _is_monte_edge(edge): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		if absf((b-a).normalized().dot(tangent))<.82: continue
		var q := Geometry3D.get_closest_point_to_segment(p,a,b)
		var dist := p.distance_to(q)
		if dist<best and dist>=float(edge.width)*.5:
			best = dist
			result = edge
	return result

func _monte_column(p: Vector3,h: float,paint: StandardMaterial3D,angle: float) -> void:
	var stone := _mat("monte_stone",Color("#a29d91"))
	var trim := _mat("monte_capital",Color("#d1c8b7"))
	_cube(p+Vector3.UP*.12,Vector3(.54,.24,.54),stone,angle,true)
	_cube(p+Vector3.UP*.30,Vector3(.43,.16,.43),stone,angle)
	_cube(p+Vector3.UP*(h-.11),Vector3(.56,.22,.56),trim,angle)
	_cube(p+Vector3.UP*(h-.30),Vector3(.44,.15,.44),trim,angle)
	var tile := Vector2i(floori(p.x/96.0),floori(p.z/96.0))
	var origin := Vector3(float(tile.x)*96.0,0,float(tile.y)*96.0)
	var key := str(tile)+":"+str(paint.get_instance_id())
	if not monte_columns.has(key):
		monte_columns[key] = {"origin":origin,"material":paint,"transforms":[]}
	monte_columns[key].transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(.35,h-.51,.35)),p+Vector3.UP*(h*.5+.025)-origin))
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = .18
	shape.height = h-.30
	collider.shape = shape
	var body := _chunk_body(tile,1)
	body.add_child(collider)
	collider.position = p+Vector3.UP*(h*.5)-body.position

func _flush_monte_columns() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = .5
	cylinder.bottom_radius = .5
	cylinder.height = 1.0
	cylinder.radial_segments = 12
	for entry in monte_columns.values():
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = cylinder
		multi.instance_count = entry.transforms.size()
		for i in range(multi.instance_count):
			multi.set_instance_transform(i,entry.transforms[i])
		var node := MultiMeshInstance3D.new()
		node.multimesh = multi
		node.material_override = entry.material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		node.position = entry.origin
	monte_columns.clear()

func _monte_portal(front: Dictionary,poly: PackedVector2Array,depth: float,ceiling: float,idx: int,paint: Color) -> void:
	var a: Vector3 = front.a
	var b: Vector3 = front.b
	var n: Vector3 = front.normal
	var t := (b-a).normalized()
	var length := a.distance_to(b)
	var angle := atan2(n.x,n.z)
	var count := maxi(1,roundi(length/3.05))
	var step := length/float(count)
	var mat := _mat("monte_column"+str(idx),paint.lightened(.07))
	var trim := _mat("monte_capital",Color("#d1c8b7"))
	var floor_mat := _mat("monte_portal_shade",Color("#817c71"))
	# Clip the floor to the real mapped footprint, never extend into road.
	var strip := street_geometry.rect(a-n*depth*.5,b-n*depth*.5,depth-.07)
	for piece in Geometry2D.intersect_polygons(strip,poly):
		_draw_street_polygon(piece,.072,floor_mat,"monte_portal")
	for i in range(count):
		var p := a+t*(float(i)+.17)*step-n*.26
		if Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),poly):
			_monte_column(p,ceiling,mat,angle)
		var door := a+t*(float(i)+.5)*step-n*(depth-.40)
		var run_a := a+t*float(i)*step-n*1.37
		var run_b := a+t*float(i+1)*step-n*1.37
		if Geometry2D.is_point_in_polygon(Vector2(door.x,door.z),poly):
			monte_walkways.append({"a":run_a,"b":run_b,"door":door,"kind":"shop" if (idx+i)%3==0 else "home"})
	_cube((a+b)*.5-n*.07+Vector3.UP*(ceiling-.03),Vector3(length,.22,.27),trim,angle)
	_cube((a+b)*.5-n*.07+Vector3.UP*(ceiling+.18),Vector3(length,.14,.21),trim,angle)

func _detail_front(front: Dictionary,h: float,idx: int,portal: bool,market: bool,monte: bool = false,portal_depth: float = 2.25) -> void:
	var a: Vector3 = front.a
	var b: Vector3 = front.b
	var n: Vector3 = front.normal
	var t := (b-a).normalized()
	var length := a.distance_to(b)
	var angle := atan2(n.x,n.z)
	var stone := _mat("facade_trim",Color("#bcb3a0"))
	var door_mat := _mat("monte_joinery"+str(idx%3),[Color("#397e8d"),Color("#496b62"),Color("#80604b")][idx%3]) if monte else _mat("facade_door",Color("#627873"))
	var dark := _mat("facade_shadow",Color("#4a514c"))
	var iron := _mat("facade_iron",Color("#393d3a"))
	var patch := _mat("facade_wear",Color("#938a77"))
	var count := clampi(roundi(length/(4.2 if market else 2.9)),1,48)
	var step := length/float(count)
	var offset: float = -portal_depth+.07 if portal else .045
	for i in range(count):
		var p := a+t*(float(i)+.5)*step
		var q := p+n*offset
		var door_width := minf(step*.58,1.5)
		_cube(q+Vector3.UP*1.38,Vector3(door_width,2.50,.065),door_mat,angle)
		if not market:
			_register_npc_door(q+n*.04,n,"home",door_width)
		_cube(q+Vector3.UP*2.71,Vector3(minf(step*.74,1.85),.17,.12),stone,angle)
		if monte:
			var opening := minf(step*.58,1.5)
			for side in [-1.0,1.0]:
				_cube(q+t*float(side)*(opening*.5+.065)+n*.07+Vector3.UP*1.37,Vector3(.13,2.55,.14),stone,angle)
			_cube(q+n*.07+Vector3.UP*.15,Vector3(opening+.20,.16,.16),stone,angle)
		if portal and not monte:
			var col := a+t*(float(i)+.12)*step+n*.04
			_cube(col+Vector3.UP*1.65,Vector3(.34,3.30,.34),stone,angle,true)
			_cube(col+Vector3.UP*.17,Vector3(.52,.32,.52),stone,angle)
			_cube(col+Vector3.UP*3.20,Vector3(.52,.22,.52),stone,angle)
		for level in range(1,mini(8,floori(h/3.25))):
			var y := float(level)*3.25+1.55
			var w := minf(step*.54,1.35)
			_cube(p+n*.05+Vector3.UP*y,Vector3(w,1.88,.08),dark,angle)
			_cube(p+n*.10+Vector3.UP*y,Vector3(.065,1.86,.10),door_mat,angle)
			_cube(p+n*.11+Vector3.UP*(y+.99),Vector3(w+.25,.13,.19),stone,angle)
			_cube(p+n*.11+Vector3.UP*(y-.99),Vector3(w+.25,.13,.19),stone,angle)
			if market or idx%3!=0:
				_cube(p+n*.28+Vector3.UP*(y-.98),Vector3(w+.50,.15,.57),stone,angle)
				_cube(p+n*.56+Vector3.UP*(y-.45),Vector3(w+.46,.045,.07),iron,angle)
				for k in range(5):
					var pos := p+t*(float(k)/4.0-.5)*(w+.4)+n*.56
					_cube(pos+Vector3.UP*(y-.70),Vector3(.04,.50,.04),iron,angle)
		if not market:
			var worn := q+t*.60+Vector3.UP*(.55+float((i+idx)%3)*.42)
			_cube(worn+n*.01,Vector3(.47,.28,.012),patch,angle)
	_cube((a+b)*.5+n*.08+Vector3.UP*(h-.16),Vector3(length,.24,.19),stone,angle)

# Beveled Cuban enamel plate: eight corners, dark outline, white center.
func _plaque_layer(p: Vector3,normal: Vector3,width: float,height: float,material: StandardMaterial3D) -> void:
	var tangent := Vector3(normal.z,0,-normal.x)
	var cut := minf(height*.19,width*.09)
	var vertices := [
		Vector2(-width*.5+cut,-height*.5),Vector2(width*.5-cut,-height*.5),
		Vector2(width*.5,-height*.5+cut),Vector2(width*.5,height*.5-cut),
		Vector2(width*.5-cut,height*.5),Vector2(-width*.5+cut,height*.5),
		Vector2(-width*.5,height*.5-cut),Vector2(-width*.5,-height*.5+cut)
	]
	var tile := Vector2i(floori(p.x/96.0),floori(p.z/96.0))
	var key := "plaque:"+str(tile)+":"+str(material.get_instance_id())
	if not map_surfaces.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		surface.set_material(material)
		map_surfaces[key] = surface
	var st: SurfaceTool = map_surfaces[key]
	for i in range(1,vertices.size()-1):
		for v in [vertices[0],vertices[i],vertices[i+1]]:
			st.set_normal(normal)
			st.add_vertex(p+tangent*float(v.x)+Vector3.UP*float(v.y))

func _make_corner_plaques() -> void:
	var white := _mat("street_plaque_white",Color("#e8e9e5"))
	var black := _mat("street_plaque_border",Color("#151f2b"))
	var concrete := _mat("street_plaque_post",Color("#797c72"))
	for node_id in geography.junctions:
		var incident: Array = geography.junctions[node_id]
		var unique: Dictionary = {}
		for road in incident:
			if bool(road.driveable) and String(road.name)!="Calle sin nombre":
				unique[geography.street_label(String(road.name))] = true
		if unique.size()<2:
			continue
		var corner: Vector3 = geography.points[node_id]
		var done: Dictionary = {}
		for road in incident:
			if not bool(road.driveable) or String(road.name)=="Calle sin nombre":
				continue
			var label: String = geography.street_label(String(road.name))
			var other: Vector3 = road.b if road.a_id==node_id else road.a
			var d := (other-corner).normalized()
			var right := Vector3(-d.z,0,d.x)
			var run := minf(9.0,corner.distance_to(other)*.55)
			for sign_side in [-1.0,1.0]:
				var outward := right*float(sign_side)
				var p := corner+d*run+outward*(float(road.width)*.5+1.0)
				if not _street_clear(p,.10):
					continue
				var nearest: float = INF
				var pos := p
				var normal := -outward
				var mounted := false
				# Snap to the real mapped wall where one is available.
				for fp in geography.footprints_near(p,10.0):
					if _overlaps_game_lot(fp):
						continue
					var poly: PackedVector2Array = fp.poly
					for i in range(poly.size()):
						var j := (i+1)%poly.size()
						var a := Vector3(poly[i].x,0,poly[i].y)
						var b := Vector3(poly[j].x,0,poly[j].y)
						if a.distance_to(b)<.8:
							continue
						var q := Geometry3D.get_closest_point_to_segment(p,a,b)
						var distance := q.distance_to(p)
						if distance<nearest and distance<6.0:
							var tangent := (b-a).normalized()
							var n := Vector3(-tangent.z,0,tangent.x)
							if n.dot(p-q)<0.0:
								n = -n
							if n.dot(-outward)<.45:
								continue
							nearest = distance
							pos = q+n*.13
							var face := _front_edge(poly)
							if not face.is_empty() and bool(face.road.portal) and n.dot(face.normal)>.8:
								var tags: Dictionary = fp.tags
								var idx: int = abs(String(fp.id).hash())%7
								var inset := _clip_inward(poly,face,2.25)
								if _building_height(tags,idx)>3.8 and inset.size()>=3 and not Geometry2D.triangulate_polygon(inset).is_empty():
									pos -= n*2.25
							normal = n
							mounted = true
				var key := label+":"+str(Vector2i(roundi(pos.x/2.0),roundi(pos.z/2.0)))
				if done.has(key):
					continue
				done[key] = true
				var angle := atan2(normal.x,normal.z)
				var width := clampf(float(label.length())*.105+.27,.68,2.15)
				if not mounted:
					_cube(pos+Vector3.UP*1.18,Vector3(.09,2.36,.09),concrete,angle)
				var y := 2.48
				_plaque_layer(pos+Vector3.UP*y+normal*.030,normal,width,.31,black)
				_plaque_layer(pos+Vector3.UP*y+normal*.046,normal,width-.085,.235,white)
				_label(label,pos+Vector3.UP*y+normal*.065,minf(.0038,(width-.13)/(float(label.length())*29.0)),angle,Color("#151d28"))
				plaque_count += 1

func _local_cube(c: Vector3,basis: Basis,p: Vector3,size: Vector3,material: StandardMaterial3D,solid: bool = false) -> void:
	_cube(c+basis*p,size,material,atan2(basis.z.x,basis.z.z),solid)

func _label(words: String,at: Vector3,pixel: float,angle: float,color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = words
	label.font_size = 48
	label.pixel_size = pixel
	label.outline_size = 3
	label.modulate = color
	label.visibility_range_end = 85.0
	label.visibility_range_end_margin = 5.0
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
	var monte := _is_monte_edge(lot.edge)
	var plaster := _mat("monte_wall"+str(index%7),_monte_color(index)) if monte else _mat("plaster"+str(index%7),palette[index%7])
	var weathered := _mat("weathered",Color("#8d8574"))
	var stone := _mat("old_stone",Color("#b3aa96"))
	var doors := _mat("old_door",Color("#5e7773"))
	var recess := _mat("dark_recess",Color("#494d47"))
	var iron := _mat("iron",Color("#43433d"))
	var upper := 1+index%3
	var h: float = float(upper)*3.1
	if service=="LA ALBORADA":
		plaster = _mat("alborada_wall",Color("#91a9a9"))
		doors = _mat("alborada_blue",Color("#47677e"))
	var portal: bool = bool(lot.get("portal",false)) or monte
	var face_z: float = 1.52 if portal else 4.43
	# Deep covered portal, facade behind columns, upper floors above walkway.
	if portal or service in ["BODEGA","HOSPITAL • LA DEPENDIENTE"]:
		_local_cube(c,basis,Vector3(0,.065,2.8),Vector3(8.8,.13,3.3),stone,true)
	if service in ["BODEGA","HOSPITAL • LA DEPENDIENTE"]:
		face_z = 1.52
		_public_room(c,basis,plaster,service)
	else:
		var lower_wall := _mat("monte_shaded_infill"+str(index%7),_monte_color(index).darkened(.18)) if monte and portal else plaster
		_local_cube(c,basis,Vector3(0,1.55,-1.45 if portal else 0.0),Vector3(8.8,3.1,5.9 if portal else 8.8),lower_wall,true)
	_local_cube(c,basis,Vector3(0,3.05,0),Vector3(8.8,.24,9.0),stone,true)
	if upper>1:
		_local_cube(c,basis,Vector3(0,3.1+(h-3.1)*.5,0),Vector3(8.8,h-3.1,8.8),plaster,true)
	_local_cube(c,basis,Vector3(0,h+.07,0),Vector3(8.95,.14,9.0),stone)
	for x in ([-4.15,-1.4,1.4,4.15] if portal else []):
		if monte:
			_monte_column(c+basis*Vector3(float(x),0,4.10),3.0,plaster,angle)
		else:
			_local_cube(c,basis,Vector3(float(x),1.58,4.10),Vector3(.36,3.0,.36),stone,true)
			_local_cube(c,basis,Vector3(float(x),.18,4.10),Vector3(.52,.31,.52),weathered)
			_local_cube(c,basis,Vector3(float(x),2.96,4.10),Vector3(.50,.21,.50),stone)
	if monte and portal:
		monte_walkways.append({"a":c+basis*Vector3(-4.15,0,2.7),"b":c+basis*Vector3(4.15,0,2.7),"door":c+basis*Vector3(0,0,2.05),"kind":"shop" if not service.is_empty() else "home"})
		var shade := _mat("monte_portal_shade",Color("#817c71"))
		_local_cube(c,basis,Vector3(0,.139,2.77),Vector3(8.72,.012,3.06),shade)
	for x in [-2.7,0.0,2.7]:
		if service not in ["BODEGA","HOSPITAL • LA DEPENDIENTE"] or float(x)!=0.0:
			_local_cube(c,basis,Vector3(float(x),1.35,face_z),Vector3(1.12,2.55,.06),doors)
			if service.is_empty():
				_register_npc_door(c+basis*Vector3(float(x),0,face_z+.04),front,"home",1.12)
		_local_cube(c,basis,Vector3(float(x),2.77,face_z+.04),Vector3(1.34,.16,.12),stone)
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
		_local_cube(c,basis,Vector3(px,py,face_z+.006),Vector3(.48+float(k)*.12,.30,.008),weathered)
	if service=="LA ALBORADA":
		# Recognizable shopfront, not a surveyed reproduction.
		_local_cube(c,basis,Vector3(0,1.36,face_z+.07),Vector3(5.8,2.28,.075),doors)
		for x in [-1.94,0.0,1.94]:
			_local_cube(c,basis,Vector3(float(x),1.56,face_z+.12),Vector3(1.65,1.48,.055),recess)
			_local_cube(c,basis,Vector3(float(x),.68,face_z+.15),Vector3(1.65,.12,.11),stone)
	if not service.is_empty():
		_local_cube(c,basis,Vector3(0,2.65,face_z+.10),Vector3(5.2,.48,.10),doors)
		_label(service,c+basis*Vector3(0,2.66,face_z+.17),.010,angle,Color("#fff2cb"))
	elif portal and not monte and index%13==0 and residents.size()<45:
		_vendor(lot,index)
	elif portal and not monte and index%5==0 and residents.size()<65:
		_citizen(lot,index,false)

func _public_room(c: Vector3,basis: Basis,wall: StandardMaterial3D,service: String) -> void:
	var floor_mat := _mat("public_floor",Color("#b9b5a5"))
	var wood := _mat("public_wood",Color("#8e785f"))
	var metal := _mat("public_metal",Color("#b7bdb8"))
	_local_cube(c,basis,Vector3(0,.045,-1.45),Vector3(8.8,.09,5.9),floor_mat,true)
	_local_cube(c,basis,Vector3(0,1.55,-4.28),Vector3(8.8,3.10,.18),wall,true)
	for side in [-1.0,1.0]:
		var v: float = float(side)
		_local_cube(c,basis,Vector3(v*4.3,1.55,-1.45),Vector3(.18,3.1,5.9),wall,true)
		_local_cube(c,basis,Vector3(v*2.65,1.55,1.48),Vector3(3.3,3.1,.15),wall,true)
	# Use the central doorway to enter and leave; keep other premises closed.
	_local_cube(c,basis,Vector3(0,1.2,1.48),Vector3(1.95,2.4,.13),wood,true)
	_local_cube(c,basis,Vector3(0,2.8,1.48),Vector3(1.95,.7,.13),wall,true)
	_local_cube(c,basis,Vector3(0,.60,-2.4),Vector3(3.1,1.0,.85),wood,true)
	if service=="BODEGA":
		for y in [.55,1.05,1.55]:
			_local_cube(c,basis,Vector3(-3.6,float(y),-1.65),Vector3(.85,.09,3.6),wood,true)
			for k in range(5):
				_local_cube(c,basis,Vector3(-3.6,float(y)+.15,-3.0+float(k)*.64),Vector3(.34,.24,.25),_mat("food_package",Color("#c5a773")))
	else:
		for x in [-3.1,3.1]:
			_local_cube(c,basis,Vector3(float(x),.50,-1.0),Vector3(1.1,.15,2.1),metal,true)
			_local_cube(c,basis,Vector3(float(x),.66,-1.0),Vector3(1.02,.18,2.0),_mat("hospital_linen",Color("#e3e5dc")))
		_local_cube(c,basis,Vector3(0,2.35,-4.10),Vector3(.25,.85,.05),_mat("hospital_cross",Color("#9f4941")))
		_local_cube(c,basis,Vector3(0,2.35,-4.10),Vector3(.85,.25,.05),_mat("hospital_cross",Color("#9f4941")))
	public_rooms.append({"name":service,"center":c,"basis":basis})

func _citizen(lot: Dictionary,index: int,sitting: bool) -> Node3D:
	var c: Vector3 = lot.center
	var f: Vector3 = lot.front
	var basis := Basis(Vector3.UP,atan2(f.x,f.z))
	var p := c+basis*Vector3(-2.1,0,2.55)
	var npc := Node3D.new()
	add_child(npc)
	npc.position = p
	npc.rotation.y = atan2(f.x,f.z)
	npc.add_to_group("social_people")
	npc.set_meta("female",posmod(index,3)==1)
	npc.set_meta("social_context","worker" if sitting else "street")
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

# Sample the rendered road, not just the centreline from the chosen
# frontage. A full van footprint must fit the road without touching a lot.
func _repark_home_van() -> void:
	var center := home_root.position
	var front := home_root.transform.basis.z.normalized()
	var along := home_root.transform.basis.x.normalized()
	var best := INF
	var found := false
	for edge in geography.roads_near(center,65.0):
		if not bool(edge.driveable): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var d := (b-a).normalized()
		if absf(d.dot(along))<.75:
			continue
		var q := Geometry3D.get_closest_point_to_segment(center,a,b)
		if q.distance_to(center)>45.0: continue
		var side := Vector3(-d.z,0,d.x)
		if side.dot(center-q)<0.0: side = -side
		for offset_value in [0.0,2.5,-2.5,5.0,-5.0,8.0,-8.0,12.0,-12.0]:
			var offset := float(offset_value)
			var base := Geometry3D.get_closest_point_to_segment(q+d*offset,a,b)
			for lateral in [maxf(0.0,float(edge.width)*.5-1.35),0.0]:
				var p := base+side*float(lateral)
				if (p-center).dot(front)<0.0: continue
				var footprint := street_geometry.rect(p-d*2.65,p+d*2.65,2.30)
				var safe := true
				for v in footprint:
					if not street_geometry.point_on_road(Vector3(v.x,0,v.y)):
						safe = false
						break
				if not safe or not street_geometry.point_on_road(p): continue
				for lot in _lots_near(p):
					if not Geometry2D.intersect_polygons(footprint,_lot_polygon(lot)).is_empty():
						safe = false
						break
				if not safe: continue
				var score := p.distance_squared_to(center)+(1.0-absf(d.dot(along)))*100.0
				if score<best:
					best = score
					found = true
					van_spawn = p+Vector3.UP*.06
					van_angle = atan2(d.x,d.z)
	if not found:
		push_warning("No se encontró estacionamiento completo sobre el asfalto cerca de la vivienda.")

func _make_humble_home(lot: Dictionary) -> void:
	home_building = true
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
	for level in [0,1]:
		var y := 1.55+float(level)*3.10
		for x in [-4.3,4.3]:
			_local_cube(c,basis,Vector3(float(x),y,-1.45),Vector3(.18,3.10,5.9),wall,true)
		_local_cube(c,basis,Vector3(0,y,-4.4),Vector3(8.6,3.10,.18),wall,true)
	for x in [-2.6,2.6]:
		_local_cube(c,basis,Vector3(float(x),1.55,1.55),Vector3(3.5,3.1,.16),wall,true)
	_local_cube(c,basis,Vector3(0,2.76,1.55),Vector3(1.7,.68,.16),wall,true)
	_local_cube(c,basis,Vector3(0,1.16,1.55),Vector3(1.5,2.30,.12),wood,true)
	_local_cube(c,basis,Vector3(0,4.65,1.55),Vector3(8.6,3.1,.18),wall,true)
	_local_cube(c,basis,Vector3(0,6.24,0),Vector3(8.9,.22,9.0),wall,true)
	for x in [-4.1,0.0,4.1]:
		_local_cube(c,basis,Vector3(float(x),1.55,4.0),Vector3(.36,3.1,.36),trim,true)
	# Humble colonial facade: cornice, tall shutters, and iron balcony.
	_local_cube(c,basis,Vector3(0,3.23,1.73),Vector3(8.55,.22,.34),trim)
	_local_cube(c,basis,Vector3(0,6.10,1.73),Vector3(8.55,.25,.30),trim)
	for x in [-2.5,2.5]:
		var xx: float = float(x)
		_local_cube(c,basis,Vector3(xx,4.66,1.66),Vector3(1.45,2.20,.06),dark)
		_local_cube(c,basis,Vector3(xx,4.66,1.72),Vector3(1.35,2.07,.065),wood)
		for k in range(7):
			_local_cube(c,basis,Vector3(xx,3.82+float(k)*.26,1.77),Vector3(1.24,.055,.035),trim)
		_local_cube(c,basis,Vector3(xx,3.60,1.95),Vector3(1.85,.15,.68),trim)
		_local_cube(c,basis,Vector3(xx,4.31,2.24),Vector3(1.85,.065,.06),dark)
		for k in range(7):
			_local_cube(c,basis,Vector3(xx-.84+float(k)*.28,3.99,2.24),Vector3(.045,.66,.045),dark)
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
		_home_default("home_bed_"+str(int(zz*100)),"Cama",Vector3(-2.75,3.2,zz),PI/2.0,"#aaa9a0")
		_local_cube(c,basis,Vector3(-.65,3.55,zz-.55),Vector3(.60,.70,.58),wood,true)
	_home_default("home_bed_wall_a","Pared",Vector3(-2.72,3.2,-1.35),0.0,"#b4b29a")
	_home_default("home_bed_wall_b","Pared",Vector3(.30,3.2,-1.35),0.0,"#b4b29a")
	# Modest ground-floor living room, kitchen and bathroom corner.
	_local_cube(c,basis,Vector3(-2.7,.46,.30),Vector3(1.0,.72,1.9),trim,true)
	_local_cube(c,basis,Vector3(-3.14,.91,.30),Vector3(.18,.68,1.9),trim)
	_local_cube(c,basis,Vector3(-.8,.42,.25),Vector3(.8,.65,.65),wood,true)
	_local_cube(c,basis,Vector3(-.8,.92,.25),Vector3(.55,.37,.24),dark)
	_local_cube(c,basis,Vector3(-2.7,.54,-3.85),Vector3(2.5,.9,.75),wood,true)
	_local_cube(c,basis,Vector3(-2.7,1.03,-3.85),Vector3(2.5,.08,.75),floor_mat)
	_local_cube(c,basis,Vector3(-3.0,1.09,-3.85),Vector3(.52,.08,.45),dark)
	_local_cube(c,basis,Vector3(-.9,.98,-3.9),Vector3(.7,1.8,.75),cloth,true)
	_home_default("home_bath_wall","Pared",Vector3(.65,0,-2.92),PI/2.0,"#b4b29a")
	_home_default("home_toilet","Inodoro",Vector3(1.55,0,-3.90),PI,"#d8d9d4")
	for y in [1.0,4.2]:
		_local_cube(c,basis,Vector3(-2.5,float(y)+.55,1.66),Vector3(1.3,1.1,.05),dark)
		for x in range(5):
			_local_cube(c,basis,Vector3(-3.05+float(x)*.27,float(y)+.55,1.71),Vector3(.035,1.1,.04),trim)
	home_building = false
	_label("MI CASA",home_root.to_global(Vector3(0,2.64,1.67)),.010,angle,Color("#f1e2c4"))
	_pickup("llaves_casa","Llaves",home_root.to_global(Vector3(-2.0,1.16,-3.8)),Vector3(.16,.07,.10),_mat("keys",Color("#b3a47b")))
	_pickup("libreta_casa","Libreta",home_root.to_global(Vector3(-1.5,1.16,-3.8)),Vector3(.22,.05,.31),_mat("notebook",Color("#596c86")))

func _home_default(id: String,kind: String,local: Vector3,rotation: float,paint: String) -> void:
	var p := home_root.to_global(local)
	home_defaults[id] = {"kind":kind,"x":p.x,"y":local.y,"z":p.z,"angle":home_root.rotation.y+rotation,"paint":paint}

func set_home_cutaway(enabled: bool,level: float = 0.0) -> void:
	for item in home_cutaway:
		var n: Node3D = item.node
		n.visible = not enabled or (int(item.level)==1 and level>1.0)

func interaction_text(at: Vector3) -> String:
	for i in range(public_rooms.size()):
		var room: Dictionary = public_rooms[i]
		var c: Vector3 = room.center
		var basis: Basis = room.basis
		var local: Vector3 = basis.inverse()*(at-c)
		if absf(local.x)<1.3 and absf(local.z-1.48)<1.55 and local.y<2.5:
			return "[E] Salir de "+String(room.name) if current_room==i else "[E] Entrar a "+String(room.name)
	if home_root!=null:
		var p := home_root.to_local(at)
		if inside_home and p.x>2.0 and not upstairs and p.z>-.3 and p.y<2.2:
			return "[E] Subir al segundo piso"
		if inside_home and upstairs and p.x>1.0 and p.z< -2.7 and p.y>3.4:
			return "[E] Bajar al primer piso"
		if absf(p.x)<1.4 and absf(p.z-1.55)<1.65 and p.y<2.6:
			return "[E] Salir de casa" if inside_home else "[E] Entrar a mi casa"
	return ""

func interact(player: CharacterBody3D,avatar: Node3D,legs: Array,arms: Array) -> bool:
	var action := interaction_text(player.global_position)
	if action.is_empty():
		return false
	for i in range(public_rooms.size()):
		var room: Dictionary = public_rooms[i]
		if not action.ends_with(String(room.name)):
			continue
		var c: Vector3 = room.center
		var basis: Basis = room.basis
		current_room = -1 if current_room==i else i
		player.global_position = c+basis*Vector3(0,.95,2.55 if current_room<0 else .52)
		player.velocity = Vector3.ZERO
		return true
	if action.contains("segundo piso"):
		upstairs = true
		player.global_position = home_root.to_global(Vector3(1.30,4.16,-3.85))
		player.velocity = Vector3.ZERO
		return true
	if action.contains("primer piso"):
		upstairs = false
		player.global_position = home_root.to_global(Vector3(2.4,.95,1.0))
		player.velocity = Vector3.ZERO
		return true
	inside_home = not inside_home
	player.global_position = home_root.to_global(Vector3(0,.96,.62 if inside_home else 2.60))
	player.velocity = Vector3.ZERO
	return true

func reset_interaction(avatar: Node3D,legs: Array) -> void:
	inside_home = false
	current_room = -1
	upstairs = false
	seated = false
	avatar.position.y = 0.0

func _load_inventory() -> void:
	if not FileAccess.file_exists(INVENTORY_PATH):
		return
	var file := FileAccess.open(INVENTORY_PATH,FileAccess.READ)
	if file==null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	if data is Dictionary:
		inventory = data

func _pickup(id: String,title_value: String,at: Vector3,size: Vector3,material: StandardMaterial3D) -> void:
	if inventory.has(id):
		return
	var body := StaticBody3D.new()
	body.collision_layer = 16
	body.collision_mask = 0
	add_child(body)
	body.position = at
	_visual_box(body,Vector3.ZERO,size,material)
	_shape(body,Vector3.ZERO,size+Vector3(.10,.15,.10))
	body.set_meta("product",title_value)
	body.set_meta("pickup_id",id)

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
	var obj := hit.collider as Node3D
	if obj == null:
		return null
	if obj.has_meta("product") and player.global_position.distance_to(obj.global_position)<3.0:
		return obj
	return null

func aimed_text(camera: Camera3D,player: CharacterBody3D) -> String:
	var item := aimed_product(camera,player)
	if item==null:
		return ""
	return ("[E] Recoger " if item.has_meta("pickup_id") else "[E] Consultar ")+String(item.get_meta("product"))

func inspect_product(camera: Camera3D,player: CharacterBody3D) -> bool:
	var item := aimed_product(camera,player)
	if item==null:
		return false
	if item.has_meta("pickup_id"):
		var id := String(item.get_meta("pickup_id"))
		inventory[id] = String(item.get_meta("product"))
		item.queue_free()
		prompt = "Recogiste: "+String(inventory[id])+" | Inventario: "+str(inventory.size())
		var file := FileAccess.open(INVENTORY_PATH,FileAccess.WRITE)
		if file!=null:
			file.store_string(JSON.stringify(inventory))
	else:
		prompt = "Vendedor: Tengo "+String(item.get_meta("product"))+". Compra disponible cuando incorporemos dinero."
	prompt_time = 4.0
	return true

func add_school_bus(original: Node3D) -> void:
	var route := geography.bus_loop(String(home_edge.get("a_id","")),String(home_edge.get("b_id","")))
	if route.size()<4:
		push_warning("Pilar-Atarés: no safe bus loop found; original bus parked.")
	var bus := CharacterBody3D.new()
	bus.name = "SchoolBus_Original"
	bus.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	bus.collision_layer = 1
	bus.collision_mask = 1|4|8
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
	if route.size()>=4:
		bus.position = route[0].lerp(route[1],.4)+Vector3.UP*.055
		var d := (route[1]-route[0]).normalized()
		bus.rotation.y = atan2(d.x,d.z)
		bus.add_to_group("autonomous_traffic")
		travel.append({"node":bus,"route":route,"next":1,"speed":0.0,"stop":0.0})
	else:
		var edge: Dictionary = geography.roads[0]
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		bus.position = a.lerp(b,.5)+Vector3.UP*.055
		bus.rotation.y = atan2((b-a).x,(b-a).z)
	print("Pilar-Atarés: original bus loop, ",route.size()," road graph nodes.")

func tick(delta: float) -> void:
	cuba_clock += delta
	prompt_time = maxf(0.0,prompt_time-delta)
	for entry in travel:
		var car: CharacterBody3D = entry.node
		var route: Array = entry.route
		var next: int = int(entry.next)
		var detour: Array = entry.get("detour",[])
		var active := not detour.is_empty()
		var detour_index := int(entry.get("detour_index",0))
		var target: Vector3 = detour[detour_index].p if active else route[next]
		target.y = car.position.y
		var diff := target-car.position
		var distance := diff.length()
		if distance<.28:
			if active:
				entry.detour_index = detour_index+1
				if int(entry.detour_index)>=detour.size():
					entry.detour = []
					entry.next = int(entry.resume)
			else:
				entry.next = (next+1)%route.size()
				entry.stop = .7
			continue
		entry.stop = maxf(0.0,float(entry.stop)-delta)
		var d := diff.normalized()
		var speed := minf(3.0 if active else 5.0,maxf(1.2,distance*1.5))
		if float(entry.stop)>0.0: speed = 0.0
		var reach := minf(9.0,distance+.7)
		var free := TrafficBypass.clear_distance(car,d,reach,2.35,7.65,2.8)
		var blocked := free<reach-.05
		var stalled := TrafficBypass.stalled(entry,car,delta)
		if TrafficBypass.cooperate(entry,car,street_geometry,2.35,7.65,2.8,delta,stalled,target): continue
		if bool(entry.get("cooperative_rejoin",false)):
			entry.cooperative_rejoin = false
			if active: entry.next = int(entry.resume)
			entry.detour = []
			continue
		entry.cooldown = maxf(0.0,float(entry.get("cooldown",0.0))-delta)
		if blocked: speed = minf(speed,sqrt(12.0*maxf(0.0,free-.7)))
		if float(entry.get("retreat_remaining",0.0))<=0.0 and stalled>1.0 and float(entry.stop)<=0.0 and float(entry.cooldown)<=0.0:
			entry.cooldown = 1.8
			if active:
				entry.detour = []
				entry.next = int(entry.resume)
				continue
			var ordered: Array = []
			for i in range(route.size()):
				ordered.append({"p":route[(next+i)%route.size()]})
			var choice := TrafficBypass.recover(car,ordered,0,street_geometry,2.35,7.65,geography.signal_nodes,2.8)
			if not choice.is_empty():
				entry.detour = choice.path
				entry.detour_index = 0
				entry.resume = (next+int(choice.resume))%route.size()
				entry.traffic_stall = 0.0
				continue
		if not active and TrafficBypass.retreat(entry,car,street_geometry,2.35,7.65,delta,stalled>3.5 and float(entry.speed)<.12):
			entry.speed = 0.0
			continue
		if stalled<.1: entry.backed_up = 0.0
		entry.speed = move_toward(float(entry.speed),speed,delta*5.0)
		var angle := lerp_angle(car.rotation.y,atan2(d.x,d.z),minf(delta*4.0,1.0))
		var advance := minf(float(entry.speed)*delta,distance)
		if blocked: advance = minf(advance,maxf(0.0,free-.7))
		if advance<.0001:
			car.velocity = Vector3.ZERO
			entry.speed = 0.0
		elif not TrafficBypass.safe_step(car,d,advance,angle,delta): entry.speed = 0.0
	npc_update_time += delta
	if npc_update_time < .10:
		return
	npc_update_time = 0.0
	var cam := get_viewport().get_camera_3d()
	for resident in residents:
		var person: Node3D = resident.node
		var near := cam == null or person.global_position.distance_squared_to(cam.global_position)<14400.0
		person.visible = near
		if not near or bool(resident.sitting) or Time.get_ticks_msec()<int(person.get_meta("conversation_until",0)):
			continue
		var npc: Node3D = resident.node
		var base: Vector3 = resident.origin
		var direction: Vector3 = resident.direction
		var phase: float = cuba_clock*.32+float(resident.phase)
		var target := base+direction*sin(phase)*1.2
		var next := npc.position.move_toward(target,.15)
		if pedestrian_segment_clear(npc.position,next):
			npc.position = next
			var d: Vector3 = direction if cos(phase)>0.0 else -direction
			npc.rotation.y = atan2(d.x,d.z)
