extends SceneTree
const Data = preload("res://pilar_map.gd")
const Streets = preload("res://street_geometry.gd")

func _edge(data,first: String,second: String,label: String,width: float,kind: String = "residential") -> void:
	var a: Vector3 = data.points[first]
	var b: Vector3 = data.points[second]
	var item := {"a":a,"b":b,"a_id":first,"b_id":second,"name":label,"aliases":[],"width":width,"kind":kind,"driveable":true}
	data.roads.append(item)
	for id in [first,second]:
		if not data.junctions.has(id): data.junctions[id] = []
		data.junctions[id].append(item)
		if not data.graph.has(id): data.graph[id] = []
	data.graph[first].append(second)
	data.graph[second].append(first)

func _initialize() -> void:
	var data := Data.new()
	data.points = {"a":Vector3(0,0,0),"b":Vector3(100,0,0),"c":Vector3(100,0,45),"d":Vector3(100,0,90),"e":Vector3(0,0,90),"spur":Vector3(55,0,45)}
	_edge(data,"a","b","Monte",12.8)
	_edge(data,"b","c","Matadero",6.4)
	_edge(data,"c","d","Matadero",6.4)
	_edge(data,"d","e","Avenida de México",8.4)
	_edge(data,"e","a","Calle sin nombre",6.4)
	_edge(data,"c","spur","Calle sin nombre",4.8,"service")
	# Published location can be on the perimeter instead of inside the
	# inset building. One street name may be missing from the extract.
	var block := data.market_street_block(Vector3(98,0,45))
	var failures := 0
	if block.is_empty():
		printerr("FAIL: market block was not recovered")
		quit(1)
		return
	if absf(float(block.area)-9000.0)>.1 or block.terms.size()!=3:
		printerr("FAIL: incorrect market perimeter")
		failures += 1
	if block.removed.size()!=1:
		printerr("FAIL: interior spur not identified")
		failures += 1
	data.remove_market_spurs(block)
	if data.roads.size()!=5 or data.graph["c"].has("spur") or not data.graph["c"].has("b"):
		printerr("FAIL: incorrect street graph after removing interior access")
		failures += 1
	var geometry := Streets.new()
	geometry.build(data)
	var inset := Geometry2D.offset_polygon(block.poly,-8.7,Geometry2D.JOIN_MITER)
	if inset.is_empty() or not geometry.clear(inset[0]):
		printerr("FAIL: market footprint conflicts with protected sidewalks")
		failures += 1
	if geometry.point_on_road(Vector3(70,0,45)):
		printerr("FAIL: interior access still rendered as road")
		failures += 1
	if not geometry.point_on_road(Vector3(50,0,0)):
		printerr("FAIL: perimeter road removed")
		failures += 1
	print("Market block regression: ", "PASS" if failures==0 else "FAIL")
	quit(0 if failures==0 else 1)
