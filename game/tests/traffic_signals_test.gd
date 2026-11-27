extends SceneTree
const Streets = preload("res://street_geometry.gd")
func _initialize() -> void:
	for t in range(80):
		if Streets.phase_color(float(t),true)==2 and Streets.phase_color(float(t),false)==2:
			printerr("FAIL: conflicting green phases")
			quit(1)
			return
	if Streets.phase_color(0.0,true)!=2 or Streets.phase_color(17.0,true)!=1 or Streets.phase_color(19.5,true)!=0 or Streets.phase_color(20.0,false)!=2:
		printerr("FAIL: phase timing")
		quit(1)
		return
	print("Traffic signal phases: PASS")
	quit(0)
