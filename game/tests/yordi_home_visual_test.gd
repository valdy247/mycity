extends SceneTree
const Person = preload("res://street_person.gd")
func _initialize() -> void:
	var yordi := Person.new()
	root.add_child(yordi)
	yordi.setup(807)
	if not yordi.has_node("YordiCap") or not yordi.has_node("YordiCapBrim") or not yordi.has_node("YordiBeard"):
		printerr("FAIL: missing permanent Yordi identity")
		quit(1)
		return
	for arm in yordi.arms: arm.rotation.x = -1.15
	for frame in range(60): yordi.animate(1.0/60.0,false)
	if absf(yordi.arms[0].rotation.x)>.10 or absf(yordi.arms[1].rotation.x)>.10:
		printerr("FAIL: arms stuck in PS5 carrying pose")
		quit(1)
		return
	print("Yordi identity and resting arms: PASS")
	quit(0)
