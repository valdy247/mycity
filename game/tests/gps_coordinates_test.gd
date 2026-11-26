extends SceneTree
const MapData = preload("res://pilar_map.gd")
var failures := 0

func _initialize() -> void:
	var data := MapData.new()
	for coords in [[MapData.LAT,MapData.LON],[23.115,-82.375],[23.130,-82.358],[23.1243217,-82.3678912]]:
		var p := data.project(float(coords[0]),float(coords[1]))
		var inverse := data.unproject(p)
		_check(absf(float(inverse.lat)-float(coords[0]))<.00000002,"latitude round trip")
		_check(absf(float(inverse.lon)-float(coords[1]))<.00000002,"longitude round trip")
		var parsed := data.parse_coordinates(data.coordinate_text(p))
		_check(not parsed.has("error"),"decimal format")
		if not parsed.has("error"):
			var q: Vector3 = parsed.point
			_check(q.distance_to(p)<.025,"coordinate display round trip within 2.5 cm")
	_check(data.parse_coordinates("invalid").has("error"),"invalid input")
	_check(data.parse_coordinates("90, 180").has("error"),"outside map")
	var east := data.project(MapData.LAT,MapData.LON+.00001)
	var north := data.project(MapData.LAT+.00001,MapData.LON)
	_check(east.x>1.0 and absf(east.z)<.001,"east increases X")
	_check(north.z< -1.0 and absf(north.x)<.001,"north decreases Z")
	print("WGS84 tests: ", "PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
