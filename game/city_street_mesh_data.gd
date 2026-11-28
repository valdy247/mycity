extends RefCounted
# CPU-only street surface preparation. No scene nodes or rendering resources
# are created here; each worker owns its own temporary spatial index.
static func _street_half_plane(poly: PackedVector2Array,a: Vector2,b: Vector2,orientation: float,inside: bool) -> PackedVector2Array:
	var result := PackedVector2Array()
	if poly.size()<3: return result
	var edge := b-a
	if edge.length_squared()<.00000001: return poly if inside else result
	var sign_value := orientation if inside else -orientation
	var prev := poly[poly.size()-1]
	var prev_distance := edge.cross(prev-a)*sign_value
	for point in poly:
		var distance := edge.cross(point-a)*sign_value
		if (prev_distance>=0.0)!=(distance>=0.0):
			var t := clampf(prev_distance/(prev_distance-distance),0.0,1.0)
			result.append(prev.lerp(point,t))
		if distance>=0.0:
			if result.is_empty() or result[result.size()-1].distance_squared_to(point)>.00000001:
				result.append(point)
		prev = point
		prev_distance = distance
	if result.size()>1 and result[0].distance_squared_to(result[result.size()-1])<.00000001:
		result.remove_at(result.size()-1)
	return result

static func _street_subtract_triangle(poly: PackedVector2Array,cut: PackedVector2Array) -> Array:
	var result: Array = []
	var remaining := poly
	var orientation := 1.0 if (cut[1]-cut[0]).cross(cut[2]-cut[0])>0.0 else -1.0
	for i in range(3):
		var a := cut[i]
		var b := cut[(i+1)%3]
		var outside := _street_half_plane(remaining,a,b,orientation,false)
		if outside.size()>=3 and not Geometry2D.triangulate_polygon(outside).is_empty():
			result.append(outside)
		remaining = _street_half_plane(remaining,a,b,orientation,true)
		if remaining.size()<3: break
	return result


static func prepare(streets) -> Dictionary:
	return {"road":_unique(streets,streets.roads),"sidewalk":_unique(streets,streets.sidewalks)}

static func _unique(streets,polygons: Array) -> Array:
	var index: Dictionary = {}
	var result: Array = []
	for poly in polygons:
		var tris := Geometry2D.triangulate_polygon(poly)
		for i in range(0,tris.size(),3):
			var triangle := PackedVector2Array([poly[tris[i]],poly[tris[i+1]],poly[tris[i+2]]])
			var parts: Array = [triangle]
			for cut in streets.near(index,triangle):
				var next: Array = []
				for fragment in parts:
					if Geometry2D.intersect_polygons(fragment,cut).is_empty():
						next.append(fragment)
					else:
						next.append_array(_street_subtract_triangle(fragment,cut))
				parts = next
				if parts.is_empty(): break
			result.append_array(parts)
			streets._register(index,triangle)
	return result
