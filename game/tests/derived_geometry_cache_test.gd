extends SceneTree
const Cache = preload("res://city_derived_cache.gd")
const World = preload("res://cuba_world.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _run() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.derived_key = "test"
	world.building_cache = {"clip":{},"frontage":{},"height":{},"extrusion":{}}
	var poly := PackedVector2Array([Vector2(0,0),Vector2(4,0),Vector2(4,3),Vector2(0,3)])
	var cold := world._extrusion_geometry(poly,0.0,4.0)
	_check(cold.vertices.size()==30 and cold.normals.size()==10,"rectangle has two roof and eight wall triangles")
	var warm := world._extrusion_geometry(poly,0.0,4.0)
	_check(cold==warm and world.building_hits==1,"cached vertices and normals match exactly")
	var raised := world._extrusion_geometry(poly,1.0,4.0)
	_check(raised.vertices.size()==36,"raised arcade retains underside")
	var moved := poly.duplicate()
	moved[1] += Vector2(1,0)
	_check(world._extrusion_geometry(moved,0.0,4.0)!=cold,"changed polygon creates independent geometry")
	var path := "user://mycity_derived_test_"+str(OS.get_process_id())+".bin"
	Cache.write(path,"test",world.building_cache)
	var restored := Cache.read(path,"test")
	_check(restored==world.building_cache,"binary snapshot preserves geometry")
	_check(Cache.read(path,"other").is_empty(),"different map fingerprint rejects snapshot")
	Cache.write(path,"test",{"updated":true})
	_check(bool(Cache.read(path,"test").get("updated",false)),"existing cache can be atomically replaced")
	var broken := FileAccess.open(path,FileAccess.WRITE)
	if broken!=null:
		broken.store_string("test\ntruncated")
		broken.close()
	_check(Cache.read(path,"test").is_empty(),"truncated file safely rejected")
	DirAccess.remove_absolute(path)
	var plan := {"poles":[{"p":Vector3.ZERO,"out":Vector3.RIGHT},{"p":Vector3(0,0,15),"out":Vector3.RIGHT}],"links":[Vector2i(0,1)]}
	_check(world._valid_utility_plan(plan),"valid pole plan accepted")
	_check(not world._valid_utility_plan({"poles":plan.poles,"links":[Vector2i(0,8)]}),"invalid wire index rejected")
	_check(not world._valid_utility_plan({"poles":[{"p":Vector3.INF,"out":Vector3.RIGHT}],"links":[]}),"invalid pole location rejected")
	var metal := StandardMaterial3D.new()
	var wire := StandardMaterial3D.new()
	world.utility_lens = StandardMaterial3D.new()
	for pole in plan.poles:
		world._utility_register(pole.p,pole.out,metal,true)
	_check(world._utility_connect(0,1,wire,true),"cached validated connection replays")
	_check(world.utility_poles.size()==2 and world.utility_links.size()==1,"network geometry and indices retained")
	_check(world._utility_near(Vector3.ZERO,1.0).has(0),"replayed pole has spatial index")
	world.free()
	print("MyCity derived geometry cache: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)
