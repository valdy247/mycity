extends SceneTree
const Map = preload("res://pilar_map.gd")
const Parks = preload("res://city_parks.gd")
func _initialize() -> void:
	var map := Map.new()
	map.points = {"1":Vector3(0,0,0),"2":Vector3(10,0,0),"3":Vector3(10,0,10),"4":Vector3(0,0,10)}
	map._register_park("373927999",["1","2","3","4","1"],{"leisure":"park"})
	map._register_park("bad",["1","2","3","4"],{"leisure":"park"})
	map._register_park("private",["1","2","3","4","1"],{"access":"private"})
	if map.park_areas.size()!=1 or map.park_areas[0].name!="Parque de La Normal" or absf(Parks.area(map.park_areas[0].poly)-100.0)>.001:
		printerr("FAIL: closed public park polygon validation")
		quit(1)
		return
	print("Mapped parks: PASS")
	quit(0)
