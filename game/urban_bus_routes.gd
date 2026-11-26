extends RefCounted
const MapData = preload("res://pilar_map.gd")
var data: MapData
var graph := AStar3D.new()
var ids: Dictionary = {}
var reverse_ids: Dictionary = {}
var edges: Dictionary = {}

func setup(value: MapData) -> void:
	data = value
	var serial := 1
	for edge in data.roads:
		if not bool(edge.driveable) or float(edge.width)<5.6: continue
		var a := String(edge.a_id)
		var b := String(edge.b_id)
		for id in [a,b]:
			if not ids.has(id):
				ids[id] = serial
				reverse_ids[serial] = id
				graph.add_point(serial,data.points[id])
				serial += 1
		for pair in [[a,b],[b,a]]:
			if data.graph.get(pair[0],[]).has(pair[1]):
				var key := String(pair[0])+":"+String(pair[1])
				edges[key] = edge
				graph.connect_points(int(ids[pair[0]]),int(ids[pair[1]]),false)

func _corridor(edge: Dictionary,name_value: String) -> bool:
	var values: Array = [String(edge.name)]
	values.append_array(edge.get("aliases",[]))
	for v in values:
		var n := data.normalized(String(v))
		if name_value=="MONTE" and (bool(edge.get("monte_corridor",false)) or n.contains("monte") or n.contains("maximo gomez")): return true
		if name_value=="CERRO" and (n.contains("cerro") or n.contains("principe alfonso")): return true
	return false

func _path(a: String,b: String) -> Array[String]:
	var result: Array[String] = []
	if not ids.has(a) or not ids.has(b): return result
	for id in graph.get_id_path(int(ids[a]),int(ids[b])):
		result.append(String(reverse_ids[id]))
	return result

func _loop(a: String,b: String) -> Array[String]:
	var empty: Array[String] = []
	var outbound := _path(a,b)
	if outbound.size()<3: return empty
	var removed: Array = []
	# Return on a different directed road instead of performing U-turns.
	for i in range(outbound.size()-1):
		var u: int = int(ids[outbound[i+1]])
		var v: int = int(ids[outbound[i]])
		if graph.are_points_connected(u,v,false):
			graph.disconnect_points(u,v,false)
			removed.append([u,v])
	var inbound := _path(b,a)
	for pair in removed:
		graph.connect_points(int(pair[0]),int(pair[1]),false)
	if inbound.size()<3: return empty
	outbound.append_array(inbound.slice(1))
	return outbound

func plan(name_value: String,anchor: Vector3) -> Array[String]:
	var pool: Dictionary = {}
	for edge in edges.values():
		if not _corridor(edge,name_value): continue
		for id in [String(edge.a_id),String(edge.b_id)]:
			pool[id] = true
	# No invented real route numbers. Use broad streets as a fallback
	# only when a named calzada does not have enough mapped segments.
	if pool.size()<5:
		for edge in edges.values():
			if float(edge.width)<7.5: continue
			for id in [String(edge.a_id),String(edge.b_id)]:
				var p: Vector3 = data.points[id]
				if p.distance_to(anchor)<650.0: pool[id] = true
	var nodes := pool.keys()
	nodes.sort_custom(func(a,b): return anchor.distance_squared_to(data.points[a])<anchor.distance_squared_to(data.points[b]))
	var best: Array[String] = []
	var score := -INF
	for i in range(mini(nodes.size(),5)):
		var a := String(nodes[i])
		var start: Vector3 = data.points[a]
		var destinations: Array = []
		for id in nodes:
			var p: Vector3 = data.points[id]
			var dist := start.distance_to(p)
			if dist>=220.0 and dist<=850.0:
				destinations.append({"id":id,"score":absf(dist-480.0)})
		destinations.sort_custom(func(a,b): return float(a.score)<float(b.score))
		for j in range(mini(destinations.size(),5)):
			var b := String(destinations[j].id)
			var route := _loop(a,b)
			if route.size()<6: continue
			var total := 0.0
			var major := 0.0
			for k in range(route.size()-1):
				var edge: Dictionary = edges[route[k]+":"+route[k+1]]
				var p: Vector3 = data.points[route[k]]
				var q: Vector3 = data.points[route[k+1]]
				var length := p.distance_to(q)
				total += length
				if _corridor(edge,name_value): major += length
			if total<380.0 or total>2200.0: continue
			var value := major*1.4-total*.22-start.distance_to(anchor)*.6
			if value>score:
				score = value
				best = route
		if not best.is_empty() and score>170.0: break
	return best
