extends SceneTree
const Facades = preload("res://real_facades.gd")
func _initialize() -> void:
	if Facades.profile("437450994","","")!="pilar" or Facades.profile("320464758","","")!="tejas" or Facades.profile("","policlinico abel santamaria","clinic")!="abel" or not Facades.profile("","escuela abel santamaria","school").is_empty():
		quit(1)
		return
	print("Landmark identity selection: PASS")
	quit(0)
