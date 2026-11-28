extends SceneTree
const Garage = preload("res://home_garage.gd")
const Kit = preload("res://vehicle_kit.gd")
const Person = preload("res://street_person.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _run() -> void:
	var garage := Garage.new()
	root.add_child(garage)
	garage.set_process(false)
	var body := CharacterBody3D.new()
	root.add_child(body)
	body.position = Vector3(12,0,4)
	body.rotation.y = .7
	for style in [600,601,602,603]:
		var person := Person.new()
		body.add_child(person)
		person.setup(style)
		var hands: Array[Node3D] = []
		var shoes: Array[Node3D] = []
		var head: MeshInstance3D
		for node in person.get_children():
			if node is MeshInstance3D and absf(node.position.y-1.66)<.001:
				head = node
		for i in range(2):
			hands.append(person.arms[i].get_child(2) as Node3D)
			shoes.append(person.knees[i].get_child(1) as Node3D)
		garage._pose_moto(person,body,true)
		for i in range(2):
			var side := -1.0 if i==0 else 1.0
			var hand := body.to_local(hands[i].global_position)
			var foot := body.to_local(shoes[i].global_position)
			_check(hand.distance_to(Vector3(side*Kit.TRI_GRIP_X,Kit.TRI_GRIP_Y,Kit.TRI_GRIP_Z))<.005,"hand reaches physical grip")
			_check(foot.distance_to(Vector3(side*Kit.TRI_FOOT_X,Kit.TRI_FOOT_Y,Kit.TRI_FOOT_Z))<.005,"foot rests on footboard")
		if is_instance_valid(head):
			var center := body.to_local(head.global_position)
			_check(center.y+.25<Kit.TRI_ROOF_Y-.045,"head clears canopy underside")
		person.free()
	_check(float(Kit.KITS.triciclo.height)>=Kit.TRI_ROOF_Y+.0825,"collision covers new roof")
	body.free()
	garage.free()
	print("MyCity triciclo driver pose: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)
