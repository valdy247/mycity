extends RefCounted
# OSM topology stays separate from fictional game buildings and characters.
const PATH := "res://pilar_atares_v2.osm"
const OLD_PATH := "res://pilar_atares.osm"
const WEB_PATH := "res://web_map/pilar_atares_v2.osm"
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
var stadium_boundary := PackedVector2Array()
var park_areas: Array = []
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

# Preserve only closed, fully mapped public park polygons; a named POI
# by itself is not a license to clear the surrounding city block.
func _register_park(id: String,ids: Array,t: Dictionary) -> void:
	if ids.size()<4 or ids[0]!=ids.back() or String(t.get("access","")) in ["private","no"]: return
	var polygon := PackedVector2Array()
	for i in range(ids.size()-1):
		if not points.has(ids[i]): return
		var pos: Vector3 = points[ids[i]]
		if absf(pos.x)>LIMIT or absf(pos.z)>LIMIT: return
		var point := Vector2(pos.x,pos.z)
		if polygon.is_empty() or polygon[polygon.size()-1].distance_to(point)>.05: polygon.append(point)
	if polygon.size()<3 or Geometry2D.triangulate_polygon(polygon).is_empty(): return
	var label := String(t.get("name",""))
	if id=="373927999": label = "Parque de La Normal"
	elif id=="23917140": label = "La Normal"
	elif id=="23918119": label = "El Pontón"
	if label.is_empty(): label = "Parque público"
	park_areas.append({"id":id,"name":label,"poly":polygon,"tags":t})

func load_map() -> bool:
	var parser := XMLParser.new()
	source_path = PATH
	if OS.has_feature("web") and FileAccess.file_exists(WEB_PATH):
		source_path = WEB_PATH
	elif not FileAccess.file_exists(PATH):
		if OS.has_feature("web"):
			push_error("MyCity Web: falta el mapa actualizado pilar_atares_v2.osm.")
			return false
		source_path = OLD_PATH
	var open_error := parser.open(source_path)
	if open_error != OK:
		push_error("MyCity: no se pudo abrir "+source_path+" (error "+str(open_error)+")")
		return false
	print("MyCity mapa: ",source_path)
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
				if node_tags.has("name") or node_tags.get("highway","")=="bus_stop" or node_tags.get("public_transport","") in ["platform","stop_position"]:
					poi.append({"id":node_id,"position":points[node_id],"tags":node_tags})
				active = ""
	var seen: Dictionary = {}
	for way in ways:
		var t: Dictionary = way.tags
		if String(way.id)=="665673095" or (String(t.get("leisure",""))=="stadium" and normalized(String(t.get("name",""))).contains("latinoamericano")):
			var outline := PackedVector2Array()
			for id in way.refs:
				if not points.has(id): continue
				var point: Vector3 = points[id]
				outline.append(Vector2(point.x,point.z))
			if outline.size()>3 and outline[0].is_equal_approx(outline[outline.size()-1]): outline.remove_at(outline.size()-1)
			if outline.size()>=3: stadium_boundary = outline
		if String(t.get("leisure",""))=="park" or String(way.id) in ["373927999","23917140","23918119"]:
			_register_park(String(way.id),way.refs,t)
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
	_mark_monte_corridor()
	_configure_calzada_lanes()
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

func _named_edge(edge: Dictionary,term: String) -> bool:
	var values: Array = [String(edge.name)]
	values.append_array(edge.get("aliases",[]))
	for value in values:
		var n := normalized(String(value))
		if term=="monte" and (n.contains("monte") or n.contains("maximo gomez")): return true
		if term=="cerro" and (n=="cerro" or n.contains("calzada del cerro") or n.contains("calzada de cerro") or n.contains("calzada de el cerro") or n.contains("principe alfonso")): return true
		if term=="infanta" and (n.contains("infanta") or n.contains("menocal")): return true
	return false

func _mark_monte_corridor() -> void:
	var monte_nodes: Dictionary = {}
	var infanta_nodes: Dictionary = {}
	var cerro_edges: Array = []
	var network := AStar3D.new()
	var ids: Dictionary = {}
	var reverse: Dictionary = {}
	for edge in roads:
		if not bool(edge.driveable): continue
		var a := String(edge.a_id)
		var b := String(edge.b_id)
		if _named_edge(edge,"monte"):
			edge.monte_corridor = true
			monte_nodes[a] = true
			monte_nodes[b] = true
		if _named_edge(edge,"infanta"):
			infanta_nodes[a] = true
			infanta_nodes[b] = true
		if not _named_edge(edge,"cerro"): continue
		cerro_edges.append(edge)
		for id in [a,b]:
			if not ids.has(id):
				var serial := ids.size()+1
				ids[id] = serial
				reverse[serial] = id
				network.add_point(serial,points[id])
		network.connect_points(int(ids[a]),int(ids[b]),true)
	var starts: Array = []
	var ends: Array = []
	for id in ids:
		if monte_nodes.has(id): starts.append(id)
		if infanta_nodes.has(id): ends.append(id)
	# Some extracts split an intersection into several adjacent OSM nodes.
	# Accept only a nearby actual named street, not an arbitrary district.
	if starts.is_empty() or ends.is_empty():
		for id in ids:
			var p: Vector3 = points[id]
			for edge in roads_near(p,12.0):
				var a: Vector3 = edge.a
				var b: Vector3 = edge.b
				if Geometry3D.get_closest_point_to_segment(p,a,b).distance_to(p)>8.0: continue
				if starts.is_empty() and _named_edge(edge,"monte"): starts.append(id)
				if ends.is_empty() and _named_edge(edge,"infanta"): ends.append(id)
	var best := INF
	var chosen := PackedInt64Array()
	for start in starts:
		for finish in ends:
			var path := network.get_id_path(int(ids[start]),int(ids[finish]))
			if path.size()<2: continue
			var length := 0.0
			for i in range(path.size()-1):
				length += network.get_point_position(path[i]).distance_to(network.get_point_position(path[i+1]))
			if length<best:
				best = length
				chosen = path
	var links: Dictionary = {}
	for i in range(chosen.size()-1):
		var a := String(reverse[chosen[i]])
		var b := String(reverse[chosen[i+1]])
		links[a+":"+b] = true
		links[b+":"+a] = true
	for edge in cerro_edges:
		if links.has(String(edge.a_id)+":"+String(edge.b_id)):
			edge.monte_corridor = true
			edge.portal = true
	print("Monte-Infanta: ",chosen.size()," connected Cerro nodes included in arcade corridor.")

# Gameplay corridor: two independent lanes per direction. Keep original
# OSM nodes and source widths; all rendered surfaces use the game width.
func _configure_calzada_lanes() -> void:
	road_cells.clear()
	for edge in roads:
		var named_monte := _named_edge(edge,"monte")
		var named_cerro := _named_edge(edge,"cerro")
		var arcade := bool(edge.get("monte_corridor",false)) or named_monte or named_cerro or bool(edge.portal)
		for value in [String(edge.name)]+edge.get("aliases",[]):
			if normalized(String(value)).contains("calzada "): arcade = true
		edge["arcade_corridor"] = bool(edge.driveable) and arcade
		if bool(edge.arcade_corridor): edge.portal = true
		if bool(edge.driveable) and (bool(edge.get("monte_corridor",false)) or named_monte or named_cerro):
			edge["source_width"] = float(edge.width)
			edge["width"] = maxf(12.8,float(edge.width))
			edge["lanes_per_direction"] = 2
			var a_id := String(edge.a_id)
			var b_id := String(edge.b_id)
			if not graph[a_id].has(b_id): graph[a_id].append(b_id)
			if not graph[b_id].has(a_id): graph[b_id].append(a_id)
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var radius := float(edge.width)*.5+3.0
		_index(road_cells,a.min(b)-Vector3(radius,0,radius),a.max(b)+Vector3(radius,0,radius),edge)

# Right-hand lane centres, based on each segment's actual width.
func lane_distance(edge: Dictionary,vehicle_width: float,curbside: bool = false) -> float:
	var width := float(edge.get("width",6.4))
	var maximum := maxf(0.0,width*.5-vehicle_width*.5-.20)
	if int(edge.get("lanes_per_direction",1))==2:
		return minf(width*.375 if curbside else width*.125,maximum)
	return maximum if curbside else minf(width*.25,maximum)

func lane_offset(a: Vector3,b: Vector3,vehicle_width: float,curbside: bool = false) -> Vector3:
	var d := (b-a).normalized()
	var middle := (a+b)*.5
	var best := INF
	var road: Dictionary = {}
	for edge in roads_near(middle,12.0):
		if not bool(edge.driveable): continue
		var p: Vector3 = edge.a
		var q: Vector3 = edge.b
		if absf((q-p).normalized().dot(d))<.8: continue
		var score := Geometry3D.get_closest_point_to_segment(middle,p,q).distance_to(middle)
		if score<best:
			best = score
			road = edge
	return Vector3(-d.z,0,d.x)*lane_distance(road,vehicle_width,curbside)

# Recover the actual bounded street face even when a geocoder pin sits
# on its entrance, a street alias is missing, or a service spur enters it.
func _market_street_term(edge: Dictionary) -> String:
	var values: Array = [String(edge.get("name",""))]
	values.append_array(edge.get("aliases",[]))
	for value in values:
		var n := normalized(String(value))
		if n.contains("monte") or n.contains("maximo gomez"): return "monte"
		if n.contains("matadero"): return "matadero"
		if n.contains("cristina") or n.contains("mexico"): return "cristina"
		if n.contains("arroyo"): return "arroyo"
	return ""

func _market_area(poly: PackedVector2Array) -> float:
	var area := 0.0
	for i in range(poly.size()): area += poly[i].cross(poly[(i+1)%poly.size()])
	return area*.5

func _market_pair(a: String,b: String) -> String:
	return a+":"+b if a<b else b+":"+a

func _market_face_distance(poly: PackedVector2Array,p: Vector2) -> float:
	if Geometry2D.is_point_in_polygon(p,poly): return 0.0
	var best := INF
	for i in range(poly.size()):
		best = minf(best,p.distance_to(Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%poly.size()])))
	return best

func market_street_block(anchor: Vector3) -> Dictionary:
	var adjacency: Dictionary = {}
	var edge_by_pair: Dictionary = {}
	for edge in roads:
		if not bool(edge.driveable): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		if a.distance_to(anchor)>240.0 or b.distance_to(anchor)>240.0: continue
		var first := String(edge.a_id)
		var second := String(edge.b_id)
		if not adjacency.has(first): adjacency[first] = []
		if not adjacency.has(second): adjacency[second] = []
		adjacency[first].append(second)
		adjacency[second].append(first)
		edge_by_pair[_market_pair(first,second)] = edge
	# Peel dead ends from the perimeter search; they are not block sides.
	var queue: Array = []
	var peeled: Dictionary = {}
	for id in adjacency:
		if adjacency[id].size()<2: queue.append(id)
	while not queue.is_empty():
		var id := String(queue.pop_back())
		if not adjacency.has(id) or adjacency[id].size()>=2: continue
		for other in adjacency[id].duplicate():
			peeled[_market_pair(id,String(other))] = true
			adjacency[other].erase(id)
			if adjacency[other].size()<2: queue.append(other)
		adjacency.erase(id)
	for id in adjacency:
		var center: Vector3 = points[id]
		adjacency[id].sort_custom(func(a,b):
			var u: Vector3 = points[a]-center
			var v: Vector3 = points[b]-center
			return atan2(u.z,u.x)<atan2(v.z,v.x))
	var visited: Dictionary = {}
	var best: Dictionary = {}
	var best_score := INF
	var pin := Vector2(anchor.x,anchor.z)
	for id in adjacency:
		for neighbor in adjacency[id]:
			var start := String(id)
			var second := String(neighbor)
			var a := start
			var b := second
			var ids: Array = []
			var closed := false
			for step in range(250):
				var directed := a+">"+b
				if visited.has(directed):
					closed = a==start and b==second
					break
				visited[directed] = true
				ids.append(a)
				var around: Array = adjacency.get(b,[])
				var at := around.find(a)
				if at<0 or around.size()<2: break
				var next := String(around[posmod(at-1,around.size())])
				a = b
				b = next
			if not closed or ids.size()<3: continue
			var unique: Dictionary = {}
			var poly := PackedVector2Array()
			var terms: Dictionary = {}
			var perimeter: Dictionary = {}
			var max_width := 0.0
			var midpoint := Vector2.ZERO
			for i in range(ids.size()):
				var node := String(ids[i])
				var next := String(ids[(i+1)%ids.size()])
				unique[node] = true
				var p: Vector3 = points[node]
				var v := Vector2(p.x,p.z)
				poly.append(v)
				midpoint += v
				var pair := _market_pair(node,next)
				perimeter[pair] = true
				var edge: Dictionary = edge_by_pair[pair]
				var term := _market_street_term(edge)
				if not term.is_empty(): terms[term] = true
				max_width = maxf(max_width,float(edge.width))
			if unique.size()!=ids.size(): continue
			var area := _market_area(poly)
			# The other winding is the exterior of the local network.
			if area<1800.0 or area>30000.0: continue
			if Geometry2D.triangulate_polygon(poly).is_empty(): continue
			midpoint /= float(poly.size())
			var distance := _market_face_distance(poly,pin)
			if distance>45.0 or midpoint.distance_to(pin)>125.0: continue
			# Require geographic evidence: known boundary streets, or a
			# large block containing the exact published market location.
			if terms.size()<2 and (distance>2.0 or midpoint.distance_to(pin)>65.0 or area<3200.0): continue
			var score := distance*3.0+midpoint.distance_to(pin)*.28-float(terms.size())*24.0
			if score>=best_score: continue
			best_score = score
			best = {"poly":poly,"perimeter":perimeter,"width":max_width,"terms":terms,"area":area}
	if best.is_empty(): return {}
	# Only remove dead-end links that were peeled and lie INSIDE this
	# selected block. Never delete perimeter or through-street links.
	var block: PackedVector2Array = best.poly
	var removed: Dictionary = {}
	for edge in roads:
		var a := String(edge.a_id)
		var b := String(edge.b_id)
		var key := _market_pair(a,b)
		if best.perimeter.has(key): continue
		var eligible := peeled.has(key) or (not bool(edge.driveable) and String(edge.get("kind","")) in ["service","footway","path","pedestrian","steps"])
		if not eligible or not _market_street_term(edge).is_empty(): continue
		var p: Vector3 = edge.a
		var q: Vector3 = edge.b
		var inside := true
		for fraction in [.12,.35,.65,.88]:
			var v := p.lerp(q,float(fraction))
			if not Geometry2D.is_point_in_polygon(Vector2(v.x,v.z),block): inside = false
		if inside: removed[key] = true
	best["removed"] = removed
	return best

func remove_market_spurs(block: Dictionary) -> void:
	var removed: Dictionary = block.get("removed",{})
	if removed.is_empty(): return
	for i in range(roads.size()-1,-1,-1):
		var edge: Dictionary = roads[i]
		var a := String(edge.a_id)
		var b := String(edge.b_id)
		if not removed.has(_market_pair(a,b)): continue
		if graph.has(a): graph[a].erase(b)
		if graph.has(b): graph[b].erase(a)
		for id in [a,b]:
			if junctions.has(id):
				junctions[id].erase(edge)
				if junctions[id].is_empty(): junctions.erase(id)
		roads.remove_at(i)
	road_cells.clear()
	for edge in roads:
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var radius := float(edge.width)*.5+3.0
		_index(road_cells,a.min(b)-Vector3(radius,0,radius),a.max(b)+Vector3(radius,0,radius),edge)
	print("Cuatro Caminos: ",removed.size()," accesos interiores retirados; calles exteriores intactas.")
