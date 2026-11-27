extends SceneTree
const Taxi = preload("res://taxi_service.gd")
func _initialize() -> void:
	if absf(Taxi.curb_offset(12.0,1.9)-4.8)>.001:
		quit(1)
		return
	if Taxi.parallel_to_road(Vector3(1,0,1),Vector3(0,0,1)) or not Taxi.parallel_to_road(Vector3(0,0,1),Vector3(0,0,1)):
		quit(1)
		return
	if Taxi._idle_berth_score({"lanes_per_direction":2},12.0)<=Taxi._idle_berth_score({"lanes_per_direction":1},25.0):
		quit(1)
		return
	print("Taxi parking: PASS")
	quit(0)
