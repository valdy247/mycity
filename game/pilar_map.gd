extends RefCounted
# OSM topology stays separate from fictional game buildings and characters.
const PATH := "res://pilar_atares.osm"
const LAT := 23.12115
const LON := -82.3664
const LIMIT := 610.0
const ROAD_TYPES := ["primary","secondary","tertiary","residential","unclassified","living_street","primary_link","secondary_link","tertiary_link","service"]
var points: Dictionary = {}
var roads: Array = []
var graph: Dictionary = {}
var names: Dictionary = {}
var signal_nodes: Dictionary = {}
var building_count := 0

func load_map() -> bool:
	var parser := XMLParser.new()
	if parser.open(PATH) != OK:
		return false
	var refs: Array = []
	var tags: Dictionary = {}
	var active := ""
	var ways: Array = []
	var node_id := ""
	while parser.read() == OK:
		if parser.get_node_type() == XMLParser.NODE_ELEMENT:
			var key := parser.get_node_name()
			if key == "node":
				node_id = parser.get_named_attribute_value_safe("id")
				var lat := float(parser.get_named_attribute_value_safe("lat"))
				var lon := float(parser.get_named_attribute_value_safe("lon"))
				points[node_id] = Vector3((lon-LON)*111320.0*cos(deg_to_rad(LAT)),0,(LAT-lat)*110574.0)
				active = "node" if not parser.is_empty() else ""
			elif key == "way":
				active = "way"
				refs = []
				tags = {}
			elif key == "nd" and active == "way":
				refs.append(parser.get_named_attribute_value_safe("ref"))
			elif key == "tag":
				var k := parser.get_named_attribute_value_safe("k")
				var v := parser.get_named_attribute_value_safe("v")
				if active == "way":
					tags[k] = v
				elif active == "node" and k == "highway" and v == "traffic_signals":
					signal_nodes[node_id] = true
		elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
			if parser.get_node_name() == "way":
				ways.append({"refs":refs,"tags":tags})
				active = ""
			elif parser.get_node_name() == "node":
				active = ""
	var seen: Dictionary = {}
	for way in ways:
		var t: Dictionary = way.tags
		if t.has("building"):
			building_count += 1
		var kind := String(t.get("highway",""))
		if not ROAD_TYPES.has(kind) or String(t.get("access","")) in ["private","no"] or String(t.get("service","")) in ["driveway","parking_aisle"]:
			continue
		var width: float = 6.4
		if kind in ["primary","secondary","primary_link","secondary_link"]:
			width = 8.4
		elif kind in ["service","living_street"]:
			width = 4.8
		var one := String(t.get("oneway","yes" if t.get("junction","")=="roundabout" else "no"))
		var street := String(t.get("name","Calle sin nombre"))
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
			roads.append({"a":a,"b":b,"a_id":a_id,"b_id":b_id,"width":width,"name":street,"kind":kind})
			names[street] = true
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
