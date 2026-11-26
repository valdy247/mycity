extends RefCounted
# Authoritative local-metre street surfaces. Never mutate OSM centerlines.
const MapData = preload("res://pilar_map.gd")
const CELL := 40.0
const WALK_WIDTH := 1.40
var roads: Array = []
var sidewalks: Array = []
var road_index: Dictionary = {}
var protected_index: Dictionary = {}

func rect(a: Vector3,b: Vector3,width: float,extension: float = 0.0) -> PackedVector2Array:
	var d := Vector2(b.x-a.x,b.z-a.z).normalized()
	var n := Vector2(-d.y,d.x)*width*.5
	var p := Vector2(a.x,a.z)-d*extension
	var q := Vector2(b.x,b.z)+d*extension
	return PackedVector2Array([p-n,q-n,q+n,p+n])

func bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var out := Rect2(poly[0],Vector2.ZERO)
	for p in poly:
		out = out.expand(p)
	return out

func _register(index: Dictionary,poly: PackedVector2Array) -> void:
	var box := bounds(poly)
	var low := Vector2i(floori(box.position.x/CELL),floori(box.position.y/CELL))
	var high := Vector2i(floori(box.end.x/CELL),floori(box.end.y/CELL))
	var item := {"poly":poly,"bounds":box,"id":_serial}
	# Shared dictionary identity not needed: duplicates are harmless, but a
	# stable serial avoids clipping the same polygon twice.
	_serial += 1
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			var k := Vector2i(x,z)
			if not index.has(k):
				index[k] = []
			index[k].append(item)

var _serial := 0

func near(index: Dictionary,poly: PackedVector2Array) -> Array:
	var box := bounds(poly)
	var low := Vector2i(floori(box.position.x/CELL),floori(box.position.y/CELL))
	var high := Vector2i(floori(box.end.x/CELL),floori(box.end.y/CELL))
	var out: Array = []
	var seen: Dictionary = {}
	for x in range(low.x,high.x+1):
		for z in range(low.y,high.y+1):
			for item in index.get(Vector2i(x,z),[]):
				if not seen.has(item.id) and box.intersects(item.bounds,true):
					seen[item.id] = true
					out.append(item.poly)
	return out

func _road(poly: PackedVector2Array) -> void:
	if poly.size()<3 or Geometry2D.triangulate_polygon(poly).is_empty():
		return
	roads.append(poly)
	_register(road_index,poly)
	_register(protected_index,poly)

func _walk(poly: PackedVector2Array) -> void:
	if poly.size()<3 or Geometry2D.triangulate_polygon(poly).is_empty():
		return
	sidewalks.append(poly)
	_register(protected_index,poly)

func build(data: MapData) -> void:
	for edge in data.roads:
		_road(rect(edge.a,edge.b,float(edge.width),.04))
	# Fill bends and intersections before cutting sidewalks.
	for id in data.junctions:
		var incident: Array = data.junctions[id]
		var p: Vector3 = data.points[id]
		var corners := PackedVector2Array()
		for edge in incident:
			var other: Vector3 = edge.b if edge.a_id==id else edge.a
			var d := (other-p).normalized()
			var side := Vector3(-d.z,0,d.x)*float(edge.width)*.5
			for v in [p+side+d*.30,p-side+d*.30,p+side-d*.08,p-side-d*.08]:
				corners.append(Vector2(v.x,v.z))
		if corners.size()<4:
			continue
		var hull := Geometry2D.convex_hull(corners)
		if hull.size()>3 and hull[0].is_equal_approx(hull[hull.size()-1]):
			hull.remove_at(hull.size()-1)
		_road(hull)
	for edge in data.roads:
		if not bool(edge.driveable):
			continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		for side in [-1.0,1.0]:
			var off := right*float(side)*(float(edge.width)*.5+WALK_WIDTH*.5)
			var candidate := rect(a+off,b+off,WALK_WIDTH,.04)
			for part in subtract(candidate,road_index):
				_walk(part)

# Difference against every nearby polygon. If the result contains holes
# discard that fragment conservatively instead of filling the hole.
func subtract(poly: PackedVector2Array,index: Dictionary) -> Array:
	var parts: Array = [poly]
	for obstacle in near(index,poly):
		var next_parts: Array = []
		for fragment in parts:
			if Geometry2D.intersect_polygons(fragment,obstacle).is_empty():
				next_parts.append(fragment)
				continue
			var cut := Geometry2D.clip_polygons(fragment,obstacle)
			var hole := false
			for piece in cut:
				if Geometry2D.is_polygon_clockwise(piece):
					hole = true
			if hole:
				continue
			for piece in cut:
				if piece.size()>=3 and not Geometry2D.triangulate_polygon(piece).is_empty():
					next_parts.append(piece)
		parts = next_parts
		if parts.is_empty():
			break
	return parts

func clear(poly: PackedVector2Array) -> bool:
	if poly.size()<3 or Geometry2D.triangulate_polygon(poly).is_empty():
		return false
	for obstacle in near(protected_index,poly):
		if not Geometry2D.intersect_polygons(poly,obstacle).is_empty():
			return false
	return true

func point_on_road(p: Vector3) -> bool:
	# Every polygon is already registered in all cells touched by its
	# bounds. A point only needs its own cell; no temporary polygon,
	# clipping lookup, deduplication dictionary or neighboring cells.
	var q := Vector2(p.x,p.z)
	var cell := Vector2i(floori(q.x/CELL),floori(q.y/CELL))
	for item in road_index.get(cell,[]):
		var box: Rect2 = item.bounds
		if q.x<box.position.x or q.x>box.end.x or q.y<box.position.y or q.y>box.end.y: continue
		if Geometry2D.is_point_in_polygon(q,item.poly):
			return true
	return false
