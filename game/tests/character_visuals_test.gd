extends SceneTree
const Person = preload("res://street_person.gd")

func _initialize() -> void:
	var actors: Array[Node3D] = []
	for style in [806,807,810,813,933,945]:
		var actor := Person.new()
		root.add_child(actor)
		actors.append(actor)
		actor.setup(style)
		if not actor.story_character or actor.limbs.size()!=2 or actor.knees.size()!=2 or actor.arms.size()!=2:
			printerr("FAIL: story identity or articulated limbs ",style)
			quit(1)
			return
		for i in range(2):
			# The motorcycle rider solver depends on these exact mesh orders.
			if actor.arms[i].get_child_count()!=3 or actor.knees[i].get_child_count()!=2:
				printerr("FAIL: rider mesh layout ",style)
				quit(1)
				return
		for frame in range(120): actor.animate(1.0/60.0,true,7.0)
		for frame in range(60): actor.animate(1.0/60.0,false)
		if absf(actor.limbs[0].rotation.x)>.05 or actor.stride_weight>.01:
			printerr("FAIL: idle blend ",style)
			quit(1)
			return
	var ambient := Person.new()
	root.add_child(ambient)
	ambient.setup(807,false,true)
	if ambient.story_character or not ambient.facial_eyes.is_empty():
		printerr("FAIL: ambient pedestrians got story detail")
		quit(1)
		return
	print("Character identities, rider layout and animation blend: PASS")
	quit(0)
