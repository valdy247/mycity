extends SceneTree
const Lights = preload("res://vehicle_lights.gd")
func _initialize() -> void:
	for sample in [[0,true],[419,true],[420,false],[1079,false],[1080,true],[1439,true],[1440,true]]:
		if Lights.is_night(float(sample[0]))!=sample[1]:
			printerr("FAIL: day/night boundary ",sample)
			quit(1)
			return
	print("Vehicle lighting time boundaries: PASS")
	quit(0)
