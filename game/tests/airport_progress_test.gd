extends SceneTree
const Progress = preload("res://airport_progress.gd")

func _initialize() -> void:
	var state := Progress.new()
	var at := Vector3(4,.91,13)
	if state.advance("board",at) or state.stage!=0:
		printerr("FAIL: boarding before luggage")
		quit(1)
		return
	var actions := ["pickup_first","approach","open","load_first","pickup_second","load_second","close","board"]
	for i in range(actions.size()):
		if not state.advance(actions[i],at) or state.stage!=i+1:
			printerr("FAIL: airport sequence ",i)
			quit(1)
			return
		if state.advance(actions[i],at):
			printerr("FAIL: duplicate action ",i)
			quit(1)
			return
	if state.stage!=8 or not Progress.expected_action(8).is_empty():
		quit(1)
		return
	print("Airport ordered mission and duplicate action prevention: PASS")
	quit(0)
