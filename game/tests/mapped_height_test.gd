extends SceneTree
const H = preload("res://mapped_height.gd")
func _initialize() -> void:
	assert(H.resolve({"height":"21 m","building:levels":"2"}).metres==21.0)
	assert(absf(H.resolve({"height":"30 ft"}).metres-9.144)<.001)
	assert(H.resolve({"building:levels":"5"}).metres==16.25)
	assert(H.resolve({"height":"0","building:levels":"0"}).is_empty())
	assert(H.resolve({}).is_empty())
	var samples: Array[float] = [3.25,6.5,9.75]
	assert(H.estimate("house",samples)==6.5)
	assert(H.estimate("garage",[])==2.8)
	assert(not H.compatible("house","warehouse"))
	print("OSM height resolution: PASS")
	quit(0)
