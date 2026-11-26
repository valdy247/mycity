extends RefCounted
# OSM topology stays separate from fictional game buildings and characters.
const PATH := "res://pilar_atares_v2.osm"
const OLD_PATH := "res://pilar_atares.osm"
const LAT := 23.12115
const LON := -82.3664
const LIMIT := 1250.0
const CELL := 48.0
const ROAD_TYPES := ["primary","secondary","tertiary","residential","unclassified","living_street","primary_link","secondary_link","tertiary_link","service","trunk","trunk_link","motorway","motorway_link","road","pedestrian","footway","path","steps","track","cycleway"]
const WALK_ONLY := ["pedestrian","footway","path","steps","cycleway"]
var points: Dictionary = {}
var roads: Array = []
var graph: Dictionary = {}
var names: Dictionary = {}
var signal_nodes: Dictionary = {}
var building_count := 0
var footprints: Array = []
var poi: Array = []
var junctions: Dictionary = {}
var road_cells: Dictionary = {}
var footprint_cells: Dictionary = {}
var source_path := PATH

# WGS84 local tangent plane (east/north); one Godot unit = one metre.
# Perform subtraction in scalar double precision before constructing Vector3.
func project(lat: float,lon: float) -> Vector3:
	var phi := deg_to_rad(lat)
	var lam := deg_to_rad(lon)
	var phi0 := deg_to_rad(LAT)
	var lam0 := deg_to_rad(LON)
	var ecc := 0.00669437999014
	var n := 6378137.0/sqrt(1.0-ecc*sin(phi)*sin(phi))
	var n0 := 6378137.0/sqrt(1.0-ecc*sin(phi0)*sin(phi0))
	var dx := n*cos(phi)*cos(lam)-n0*cos(phi0)*cos(lam0)
	var dy := n*cos(phi)*sin(lam)-n0*cos(phi0)*sin(lam0)
	var dz := (n*sin(phi)-n0*sin(phi0))*(1.0-ecc)
	var east := -sin(lam0)*dx+cos(lam0)*dy
	var north := -sin(phi0)*cos(lam0)*dx-sin(phi0)*sin(lam0)*dy+cos(phi0)*dz
	return Vector3(east,0,-north)

# Invert the existing WGS84 tangent-plane projection. Latitude and
# longitude stay in scalar 64-bit floats; do not store them in Vector2
# (its default float32 precision would lose metres of longitude).
func unproject(at: Vector3) -> Dictionary:
	var phi0 := deg_to_rad(LAT)
	var eccentricity := 0.00669437999014
	var w := 1.0-eccentricity*sin(phi0)*sin(phi0)
	var metres_lat := 6378137.0*(1.0-eccentricity)/pow(w,1.5)*PI/180.0
	var metres_lon := 6378137.0*cos(phi0)/sqrt(w)*PI/180.0
	var latitude := LAT-float(at.z)/metres_lat
	var longitude := LON+float(at.x)/metres_lon
	# Iteratively correct curvature against the same forward projection.
	for i in range(4):
		var estimated := project(latitude,longitude)
		latitude -= float(at.z-estimated.z)/metres_lat
		longitude += float(at.x-estimated.x)/metres_lon
	return {"lat":latitude,"lon":longitude}

func coordinate_text(at: Vector3) -> String:
	var gps := unproject(at)
	return "%.7f, %.7f" % [float(gps.lat),float(gps.lon)]

func parse_coordinates(value: String) -> Dictionary:
	var cleaned := value.strip_edges().replace(";",",")
	var parts := cleaned.split(",",false)
	if parts.size()!=2:
		parts = cleaned.split(" ",false)
	if parts.size()!=2:
		return {"error":"Usa latitud, longitud en grados decimales."}
	var lat_text := parts[0].strip_edges()
	var lon_text := parts[1].strip_edges()
	if not lat_text.is_valid_float() or not lon_text.is_valid_float():
		return {"error":"Coordenadas no válidas."}
	var latitude := float(lat_text)
	var longitude := float(lon_text)
	if not is_finite(latitude) or not is_finite(longitude) or absf(latitude)>90.0 or absf(longitude)>180.0:
		return {"error":"Latitud o longitud fuera de rango."}
	# Reject remote points before projection (the tangent plane alone
	# is not a unique representation of the whole globe).
	if absf(latitude-LAT)>.025 or absf(longitude-LON)>.025:
		return {"error":"El destino está fuera del mapa de Pilar-Atarés."}
	var point := project(latitude,longitude)
	if absf(point.x)>LIMIT or absf(point.z)>LIMIT:
		return {"error":"El destino está fuera de los límites del mapa."}
	return {"point":point,"lat":latitude,"lon":longitude}

func normalized(value: String) -> String:
	return value.to_lower().replace("á","a").replace("é","e").replace("í","i").replace("ó","o").replace("ú","u").replace("ü","u")

func is_calzada(value: String) -> bool:
	var n := normalized(value)
	return n=="monte" or n=="cerro" or n=="maximo gomez" or n=="principe alfonso" or n.contains("(monte)") or n.contains("(cerro)") or n.contains("calzada de monte") or n.contains("calzada del monte") or n.contains("calzada del cerro") or n.contains("calzada de el cerro") or n.contains("calzada de cerro")

func street_label(value: String) -> String:
	var n := normalized(value)
	if is_calzada(value):
		if n.contains("cerro") or n=="cerro": return "CERRO"
		return "MONTE"
	return value.to_upper()

func _cell(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x/CELL),floori(p.z/CELL))

func _index(index: Dictionary,minp: Vector3,maxp: Vector3,item: Dictionary) -> void:
	var low := _cell(minp)
	var high := _cell(maxp)
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			var k := Vector2i(x,z)
			if not index.has(k): index[k] = []
			index[k].append(item)

func roads_near(p: Vector3,radius: float = 0.0) -> Array:
	var low := _cell(p-Vector3(radius,0,radius))
	var high := _cell(p+Vector3(radius,0,radius))
	var result: Array = []
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			result.append_array(road_cells.get(Vector2i(x,z),[]))
	return result

func footprints_near(p: Vector3,radius: float = 0.0) -> Array:
	var low := _cell(p-Vector3(radius,0,radius))
	var high := _cell(p+Vector3(radius,0,radius))
	var result: Array = []
	var seen: Dictionary = {}
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			for item in footprint_cells.get(Vector2i(x,z),[]):
				if not seen.has(item.id):
					seen[item.id] = true
					result.append(item)
	return result

func _register_footprint(id: String,ids: Array,t: Dictionary) -> void:
	if ids.size()<4 or ids[0]!=ids.back() or String(t.get("building",""))=="no":
		return
	var poly := PackedVector2Array()
	var low := Vector3(INF,0,INF)
	var high := Vector3(-INF,0,-INF)
	var center := Vector3.ZERO
	for i in range(ids.size()-1):
		if not points.has(ids[i]): return
		var p: Vector3 = points[ids[i]]
		if absf(p.x)>LIMIT+100.0 or absf(p.z)>LIMIT+100.0: return
		var q := Vector2(p.x,p.z)
		if not poly.is_empty() and poly[poly.size()-1].distance_to(q)<.05: continue
		poly.append(q)
		center += p
		low = low.min(p)
		high = high.max(p)
	if poly.size()<3: return
	center /= float(poly.size())
	var item := {"id":id,"poly":poly,"center":center,"low":low,"high":high,"tags":t}
	footprints.append(item)
	_index(footprint_cells,low,high,item)

func load_map() -> bool:
	var parser := XMLParser.new()
	if not FileAccess.file_exists(PATH):
		source_path = OLD_PATH
	if parser.open(source_path) != OK:
		return false
	var refs: Array = []
	var tags: Dictionary = {}
	var active := ""
	var ways: Array = []
	var node_id := ""
	var way_id := ""
	var node_tags: Dictionary = {}
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var key := parser.get_node_name()
			if key == "node":
				node_id = parser.get_named_attribute_value_safe("id")
				var lat := float(parser.get_named_attribute_value_safe("lat"))
				var lon := float(parser.get_named_attribute_value_safe("lon"))
				points[node_id] = project(lat,lon)
				node_tags = {}
				active = "node" if not parser.is_empty() else ""
			elif key == "way":
				active = "way"
				way_id = parser.get_named_attribute_value_safe("id")
				refs = []
				tags = {}
			elif key == "nd" and active == "way":
				refs.append(parser.get_named_attribute_value_safe("ref"))
			elif key == "tag":
				var k := parser.get_named_attribute_value_safe("k")
				var v := parser.get_named_attribute_value_safe("v")
				if active == "way":
					tags[k] = v
				elif active == "node":
					node_tags[k] = v
					if k=="highway" and v=="traffic_signals": signal_nodes[node_id] = true
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "way":
				ways.append({"id":way_id,"refs":refs,"tags":tags})
				active = ""
			elif parser.get_node_name() == "node":
				if node_tags.has("name"):
					poi.append({"id":node_id,"position":points[node_id],"tags":node_tags})
				active = ""
	var seen: Dictionary = {}
	for way in ways:
		var t: Dictionary = way.tags
		if t.has("building"):
			building_count += 1
			_register_footprint(String(way.id),way.refs,t)
		var kind := String(t.get("highway",""))
		if not ROAD_TYPES.has(kind):
			continue
		var driveable: bool = not WALK_ONLY.has(kind) and not String(t.get("access","")) in ["private","no"] and not String(t.get("motor_vehicle","")) in ["private","no"] and not String(t.get("service","")) in ["driveway","parking_aisle"]
		var width: float = 6.4
		if kind in ["primary","secondary","primary_link","secondary_link"]:
			width = 8.4
		elif kind in ["service","living_street"]:
			width = 4.8
		elif WALK_ONLY.has(kind):
			width = 1.8
		var tagged_width := String(t.get("width","")).strip_edges().trim_suffix("m").strip_edges()
		var lanes := String(t.get("lanes",""))
		if tagged_width.is_valid_float() and float(tagged_width)>0.5:
			width = clampf(float(tagged_width),.6,35.0)
		elif lanes.is_valid_int() and int(lanes)>0:
			width = clampf(float(lanes.to_int())*3.15,2.6,30.0)
		var one := String(t.get("oneway","yes" if t.get("junction","")=="roundabout" else "no"))
		var street := String(t.get("name",t.get("alt_name","Calle sin nombre")))
		var portal: bool = is_calzada(street) or is_calzada(String(t.get("alt_name",""))) or is_calzada(String(t.get("old_name","")))
		var ids: Array = way.refs
		for i in range(ids.size()-1):
			var a_id := String(ids[i])
			var b_id := String(ids[i+1])
			if not points.has(a_id) or not points.has(b_id):
				continue
			var a: Vector3 = points[a_id]
			var b: Vector3 = points[b_id]
			if maxf(absf(a.x),absf(a.z))>LIMIT or maxf(absf(b.x),absf(b.z))>LIMIT or a.distance_to(b)<.35:
				continue
			var pair := a_id+":"+b_id if a_id<b_id else b_id+":"+a_id
			if seen.has(pair):
				continue
			seen[pair] = true
			var edge := {"a":a,"b":b,"a_id":a_id,"b_id":b_id,"width":width,"name":street,"kind":kind,"portal":portal,"driveable":driveable,"aliases":[String(t.get("alt_name","")),String(t.get("old_name","")),String(t.get("official_name","")),String(t.get("loc_name",""))]}
			roads.append(edge)
			_index(road_cells,a.min(b)-Vector3(width*.5+3,0,width*.5+3),a.max(b)+Vector3(width*.5+3,0,width*.5+3),edge)
			if street!="Calle sin nombre": names[street] = true
			for node in [a_id,b_id]:
				if not junctions.has(node): junctions[node] = []
				junctions[node].append(edge)
			if not driveable: continue
			if not graph.has(a_id):
				graph[a_id] = []
			if not graph.has(b_id):
				graph[b_id] = []
			if one != "-1":
				graph[a_id].append(b_id)
			if not one in ["yes","1","true"]:
				graph[b_id].append(a_id)
	print("Pilar-Atarés OSM: ",roads.size()," road segments; ",names.size()," street names; ",building_count," building ways in source.")
	return roads.size()>=20

func _path(start: String, goal: String, blocked_a: String, blocked_b: String) -> Array:
	var queue: Array = [start]
	var parent: Dictionary = {}
	parent[start] = ""
	var cursor := 0
	while cursor<queue.size():
		var current := String(queue[cursor])
		cursor += 1
		if current == goal:
			var result: Array = [goal]
			while String(result.back()) != start:
				result.append(parent[result.back()])
			result.reverse()
			return result
		for adjacent in graph.get(current,[]):
			var n := String(adjacent)
			if (current==blocked_a and n==blocked_b) or (current==blocked_b and n==blocked_a) or parent.has(n):
				continue
			parent[n] = current
			queue.append(n)
	return []

func bus_loop(avoid_a: String, avoid_b: String) -> Array[Vector3]:
	var best: Array = []
	var tested := 0
	for edge in roads:
		if not bool(edge.driveable): continue
		if tested>=140:
			break
		if float(edge.width)<6.0:
			continue
		var a := String(edge.a_id)
		var b := String(edge.b_id)
		if a==avoid_a or a==avoid_b or b==avoid_a or b==avoid_b:
			continue
		if not graph[a].has(b):
			var tmp := a
			a = b
			b = tmp
		if not graph[a].has(b):
			continue
		tested += 1
		var path := _path(b,a,a,b)
		if path.size()<4:
			continue
		var len_m := 0.0
		var valid := true
		for i in range(path.size()-1):
			if String(path[i]) in [avoid_a,avoid_b]:
				valid = false
			var p: Vector3 = points[path[i]]
			var q: Vector3 = points[path[i+1]]
			len_m += p.distance_to(q)
		if not valid or len_m<120.0 or len_m>1600.0:
			continue
		if path.size()>best.size():
			best = path
		if len_m>450.0 and path.size()>8:
			best = path
			break
	var result: Array[Vector3] = []
	if best.is_empty():
		return result
	for i in range(best.size()):
		var p: Vector3 = points[best[i]]
		var previous: Vector3 = points[best[posmod(i-1,best.size())]]
		var following: Vector3 = points[best[(i+1)%best.size()]]
		var in_dir := (p-previous).normalized()
		var out_dir := (following-p).normalized()
		var right := Vector3(-in_dir.z-out_dir.z,0,in_dir.x+out_dir.x).normalized()
		result.append(p+right*1.4)
	return result
