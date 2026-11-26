extends RefCounted
const MapData = preload("res://pilar_map.gd")
var data: MapData
var astar := AStar3D.new()
var node_ids: Dictionary = {}
var osm_ids: Dictionary = {}
var streets: Dictionary = {}
var canonical_names: Dictionary = {}
var node_streets: Dictionary = {}

func setup(map_data: MapData) -> void:
	data = map_data
	var serial := 1
	for id in data.graph:
		node_ids[id] = serial
		osm_ids[serial] = id
		astar.add_point(serial,data.points[id])
		serial += 1
	for id in data.graph:
		for dest in data.graph[id]:
			if node_ids.has(dest):
				astar.connect_points(node_ids[id],node_ids[dest],false)
	for edge in data.roads:
		if not bool(edge.driveable) or String(edge.name)=="Calle sin nombre":
			continue
		var canonical := _key(data.street_label(String(edge.name)))
		if canonical.is_empty():
			continue
		canonical_names[canonical] = data.street_label(String(edge.name))
		var aliases: Array = [String(edge.name),canonical]
		aliases.append_array(edge.get("aliases",[]))
		for alias in aliases:
			for part in String(alias).split(";"):
				var k := _key(part)
				if not k.is_empty():
					if not streets.has(k): streets[k] = {}
					streets[k][canonical] = true
		for id in [edge.a_id,edge.b_id]:
			if not node_streets.has(id): node_streets[id] = {}
			node_streets[id][canonical] = true

func _key(value: String) -> String:
	var n := data.normalized(value).strip_edges()
	for prefix in ["calzada del ","calzada de ","calzada ","calle ","avenida ","av. "]:
		if n.begins_with(prefix):
			n = n.substr(prefix.length()).strip_edges()
			break
	if n in ["maximo gomez","jesus del monte","maximo gomez (monte)"]: return "monte"
	if n=="la pila": return "pila"
	if n=="principe alfonso": return "cerro"
	return n

func _matches(value: String) -> Dictionary:
	var key := _key(value)
	if streets.has(key):
		return streets[key]
	# A partial name must be unambiguous; do not silently guess a street.
	var candidates: Dictionary = {}
	if key.length()>=3:
		for alias in streets:
			if String(alias).begins_with(key):
				candidates.merge(streets[alias])
	return candidates if candidates.size()==1 else {}

func path(start: String,goal: String) -> Array[String]:
	var result: Array[String] = []
	if not node_ids.has(start) or not node_ids.has(goal): return result
	for id in astar.get_id_path(node_ids[start],node_ids[goal]):
		result.append(String(osm_ids[id]))
	return result

func route_length(ids: Array[String]) -> float:
	var distance := 0.0
	for i in range(ids.size()-1):
		var a: Vector3 = data.points[ids[i]]
		var b: Vector3 = data.points[ids[i+1]]
		distance += a.distance_to(b)
	return distance

func resolve(query: String,start: String) -> Dictionary:
	if not node_ids.has(start): return {"error":"El taxi no está conectado a la red de calles."}
	var text_value := data.normalized(query).strip_edges()
	for sep in [" esquina con "," esquina de "," esquina "," con "," y "," / ",",","&","/"]:
		text_value = text_value.replace(sep,"|")
	var parts := text_value.split("|",false)
	if parts.is_empty() or parts.size()>2:
		return {"error":"Escribe una calle o dos calles: Pila y Matadero."}
	var first := _matches(parts[0].strip_edges())
	var second: Dictionary = _matches(parts[1]) if parts.size()==2 else {}
	if first.is_empty() and second.is_empty():
		return {"error":"No encuentro esas calles en el mapa descargado."}
	var both := not first.is_empty() and not second.is_empty()
	var known: Dictionary = first if not first.is_empty() else second
	var candidates: Array = []
	for id in node_streets:
		var names_here: Dictionary = node_streets[id]
		var found_a := ""
		var found_b := ""
		for k in known:
			if names_here.has(k): found_a = k
		if both:
			for k in second:
				if names_here.has(k) and k!=found_a: found_b = k
		if not found_a.is_empty() and (not both or not found_b.is_empty()):
			candidates.append({"id":id,"first":found_a,"second":found_b})
	if candidates.is_empty():
		return {"error":"Las calles existen, pero no encuentro una esquina común en este mapa."}
	var origin: Vector3 = data.points[start]
	candidates.sort_custom(func(a,b): return origin.distance_squared_to(data.points[a.id])<origin.distance_squared_to(data.points[b.id]))
	var best: Dictionary = {}
	var best_distance := INF
	for candidate in candidates:
		var ids := path(start,String(candidate.id))
		if ids.is_empty(): continue
		var distance := route_length(ids)
		if distance<best_distance:
			best_distance = distance
			best = candidate.duplicate()
			best.path = ids
		# Euclidean distance is a lower bound for route length.
		var goal: Vector3 = data.points[candidate.id]
		if best_distance<INF and origin.distance_to(goal)>best_distance: break
	if best.is_empty():
		return {"error":"No hay una ruta vehicular accesible hasta ese destino."}
	var label_value := String(canonical_names[best.first])
	if both:
		label_value += " y "+String(canonical_names[best.second])
	var note := ""
	if parts.size()==2 and not both:
		note = "Solo reconozco "+label_value+". Te dejo en un punto accesible de esa calle."
	best.label = label_value
	best.note = note
	return best

func lane(a: Vector3,b: Vector3) -> Vector3:
	var d := (b-a).normalized()
	return data.lane_offset(a,b,1.90)

# Resolve a map click to an accessible road point, respecting one-way
# edges. Prefer a real junction within 10 metres, otherwise use the
# closest position on a driveable segment.
func resolve_point(point: Vector3,start: String) -> Dictionary:
	if not node_ids.has(start):
		return {"error":"El taxi no está conectado a la red vial."}
	var candidates: Array = []
	var seen: Dictionary = {}
	for edge in data.roads_near(point,85.0):
		if not bool(edge.driveable): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var aid := String(edge.a_id)
		var bid := String(edge.b_id)
		var key := aid+":"+bid
		if seen.has(key): continue
		seen[key] = true
		var p := Geometry3D.get_closest_point_to_segment(point,a,b)
		var distance := p.distance_to(point)
		if distance>85.0: continue
		candidates.append({"edge":edge,"p":p,"distance":distance})
	if candidates.is_empty():
		return {"error":"Marca una calle del mapa."}
	candidates.sort_custom(func(a,b): return float(a.distance)<float(b.distance))
	var corners: Dictionary = {}
	for candidate in candidates:
		var edge: Dictionary = candidate.edge
		for id in [String(edge.a_id),String(edge.b_id)]:
			var p: Vector3 = data.points[id]
			var names_here: Dictionary = node_streets.get(id,{})
			if p.distance_to(point)<=10.0 and names_here.size()>=2:
				corners[id] = p.distance_to(point)
	var corner_ids := corners.keys()
	corner_ids.sort_custom(func(a,b): return float(corners[a])<float(corners[b]))
	for id in corner_ids:
		var ids := path(start,String(id))
		if ids.is_empty(): continue
		var labels: Array[String] = []
		for name_key in node_streets.get(id,{}):
			labels.append(String(canonical_names.get(name_key,name_key)))
		var position: Vector3 = data.points[id]
		return {"id":String(id),"path":ids,"label":" y ".join(labels),"note":"","point":position,"distance":route_length(ids),"partial":false}
	var best: Dictionary = {}
	var best_click := INF
	var best_length := INF
	for i in range(mini(candidates.size(),20)):
		var candidate: Dictionary = candidates[i]
		if float(candidate.distance)>best_click+.3: break
		var edge: Dictionary = candidate.edge
		var p: Vector3 = candidate.p
		for order in [0,1]:
			var entry := String(edge.a_id) if order==0 else String(edge.b_id)
			var exit_id := String(edge.b_id) if order==0 else String(edge.a_id)
			if not data.graph.get(entry,[]).has(exit_id): continue
			var ids := path(start,entry)
			if ids.is_empty(): continue
			var entry_point: Vector3 = data.points[entry]
			var length := route_length(ids)+entry_point.distance_to(p)
			if float(candidate.distance)<best_click-.3 or length<best_length:
				best_click = float(candidate.distance)
				best_length = length
				best = {"id":exit_id,"path":ids,"label":data.street_label(String(edge.name)),"note":"","point":p,"distance":length,"partial":true,"entry":entry,"exit":exit_id}
	if best.is_empty():
		return {"error":"No existe una ruta vehicular hasta ese punto. Prueba otra calle."}
	return best
