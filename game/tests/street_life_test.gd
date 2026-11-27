extends SceneTree
const Business = preload("res://business_mission.gd")
const Wear = preload("res://road_wear.gd")
func _initialize() -> void:
	for sample in [[0,false],[419,false],[420,true],[1079,true],[1080,false],[1439,false]]:
		if Business.trading_hour(float(sample[0]))!=sample[1]:
			printerr("FAIL: trading hours")
			quit(1)
			return
	if Wear.spacing(false)>=Wear.spacing(true):
		printerr("FAIL: side street wear density")
		quit(1)
		return
	print("Business hours and street wear density: PASS")
	quit(0)
