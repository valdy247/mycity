extends SceneTree
const Story = preload("res://albertico_story.gd")
func _initialize() -> void:
	var bought := {"huevos":1,"pollo":1,"perrito":1,"picadillo":1}
	var loaded := {"huevos":1,"perrito":1}
	if Story.ready_to_return(bought,loaded,"") or not Story.player_box("huevos") or Story.player_box("perrito"):
		quit(1)
		return
	loaded["pollo"] = 1
	loaded["picadillo"] = 1
	if not Story.ready_to_return(bought,loaded,"") or Story.ready_to_return(bought,loaded,"pollo"):
		quit(1)
		return
	var path := PackedVector3Array([Vector3(0,0,120),Vector3(0,0,10)])
	if Story.local_path_valid(path,Vector3.ZERO,Vector3(0,0,10)):
		quit(1)
		return
	if not Story.local_path_valid(PackedVector3Array([Vector3(0,0,10)]),Vector3.ZERO,Vector3(0,0,10)):
		quit(1)
		return
	print("Two boxes per person, physical loading guard and local route limit: PASS")
	quit(0)
