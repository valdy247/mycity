extends SceneTree
const Geometry = preload("res://street_geometry.gd")
const Data = preload("res://pilar_map.gd")

func _initialize() -> void:
	var data := Data.new()
	data.points = {"a":Vector3(-20,0,0),"b":Vector3(0,0,0),"c":Vector3(20,0,0),"d":Vector3(0,0,-20),"e":Vector3(0,0,20)}
	for pair in [["a","b"],["b","c"],["d","b"],["b","e"]]:
		var edge := {"a":data.points[pair[0]],"b":data.points[pair[1]],"a_id":pair[0],"b_id":pair[1],"width":6.0,"driveable":true}
		data.roads.append(edge)
		for id in pair:
			if not data.junctions.has(id):
				data.junctions[id] = []
			data.junctions[id].append(edge)
	var geometry := Geometry.new()
	geometry.build(data)
	var errors := 0
	if geometry.sidewalks.is_empty():
		printerr("FAIL: missing sidewalks")
		errors += 1
	for sidewalk in geometry.sidewalks:
		for road in geometry.near(geometry.road_index,sidewalk):
			if not Geometry2D.intersect_polygons(sidewalk,road).is_empty():
				printerr("FAIL: sidewalk intersects road")
				errors += 1
	var safe := PackedVector2Array([Vector2(8,8),Vector2(11,8),Vector2(11,11),Vector2(8,11)])
	var unsafe := PackedVector2Array([Vector2(2.8,8),Vector2(7,8),Vector2(7,11),Vector2(2.8,11)])
	if not geometry.clear(safe):
		printerr("FAIL: valid lot rejected")
		errors += 1
	if geometry.clear(unsafe):
		printerr("FAIL: lot crosses protected road")
		errors += 1
	var one_metre := data.project(Data.LAT,Data.LON+0.00001).length()
	if one_metre<.99 or one_metre>1.06:
		printerr("FAIL: metre-scale projection")
		errors += 1
	print("Street geometry test: ", "PASS" if errors==0 else "FAIL", " | failures: ",errors)
	quit(0 if errors==0 else 1)
