extends SceneTree
const World = preload("res://cuba_world.gd")
const Pedestrians = preload("res://monte_pedestrians.gd")
const Person = preload("res://street_person.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _run() -> void:
	var world := World.new()
	var router := Pedestrians.new()
	root.add_child(world)
	root.add_child(router)
	router.world = world
	world.street_geometry._register(world.street_geometry.road_index,PackedVector2Array([Vector2(-3,-20),Vector2(3,-20),Vector2(3,20),Vector2(-3,20)]))
	router.graph.add_point(1,Vector3(0,0,0),router.SIDEWALK_COST)
	router.graph.add_point(2,Vector3(4,0,0),router.SIDEWALK_COST)
	router.graph.add_point(3,Vector3(-4,0,0),router.SIDEWALK_COST)
	router.graph.add_point(4,Vector3(2,0,0),router.ROAD_COST)
	_check(not router._safe_destination(1),"even mislabeled road nodes cannot be destinations")
	_check(router._safe_destination(2) and router._safe_destination(3),"both sidewalks remain destinations")
	_check(not router._safe_destination(4),"curb roadway is transit only")
	var first := Person.new()
	var second := Person.new()
	var third := Person.new()
	router.add_child(first)
	router.add_child(second)
	router.add_child(third)
	first.position = Vector3(4,0,0)
	second.position = Vector3(4,0,1)
	third.position = Vector3(-4,0,0)
	router.walkers = [{"node":first,"destination":{"id":2}},{"node":second,"destination":{"id":2}}]
	_check(not router._destination_available(2,third),"occupied sidewalk destination rejects additional crowd")
	_check(router._destination_available(3,third),"uncrowded opposite sidewalk remains available")
	router.free()
	world.free()
	print("MyCity pedestrian destinations: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)
