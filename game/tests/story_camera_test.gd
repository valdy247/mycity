extends SceneTree
const Director = preload("res://story_camera.gd")
const Business = preload("res://business_mission.gd")

func _initialize() -> void:
	var focus := Vector3(4,1.4,8)
	var candidates := Director.shot_candidates(focus,Vector3(4,.8,8))
	if candidates.size()!=5:
		printerr("FAIL: missing fallback camera positions")
		quit(1)
		return
	for point in candidates:
		if not point.is_finite() or point.distance_to(focus)<.5:
			printerr("FAIL: invalid cinematic position")
			quit(1)
			return
	var line := Business.story_line_parts("Yordi: Mano, vamos.","Historia")
	var fallback := Business.story_line_parts("Sin prefijo","Carlos")
	if line[0]!="Yordi" or line[1]!="Mano, vamos." or fallback[0]!="Carlos":
		printerr("FAIL: subtitle parsing")
		quit(1)
		return
	var business := Business.new()
	var confirmed := [0]
	business.story_active = true
	business.story_lines = ["Uno","Dos"]
	business.story_callback = func(): confirmed[0] += 1
	business._confirm_story()
	if confirmed[0]!=0:
		printerr("FAIL: early mission acceptance")
		business.free()
		quit(1)
		return
	business.story_index = 2
	business._confirm_story()
	if confirmed[0]!=1:
		printerr("FAIL: explicit decision lost")
		business.free()
		quit(1)
		return
	business.free()
	print("Story camera candidates, subtitles and decision guard: PASS")
	quit(0)
