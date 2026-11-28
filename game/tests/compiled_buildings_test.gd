extends SceneTree
const World = preload("res://cuba_world.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _has_scene_owner(node: Node) -> bool:
	if node.owner!=null: return true
	for child in node.get_children():
		if _has_scene_owner(child): return true
	return false

func _run() -> void:
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.detail_stream_enabled = true
	var mat := world._mat("compiled_test",Color("#c0b8a2"))
	var poly := PackedVector2Array([Vector2(0,0),Vector2(4,0),Vector2(4,3),Vector2(0,3)])
	world._extrude(poly,0.0,4.0,mat,Vector2i.ZERO)
	world._cube(Vector3(2,2,0),Vector3(.25,4,.25),mat,0.0,true)
	world._cube(Vector3(2,2,1),Vector3(.05,.5,.05),mat,0.0,false,true)
	world._register_npc_door(Vector3(2,0,0),Vector3.FORWARD,"home",1.1)
	world._flush_city_boxes()
	world._flush_footprints()
	world._compiled_material_table()
	var details := world._compiled_details_snapshot(world.detail_stream_tiles)
	var packed := world._compiled_pack(world.get_children())
	_check(packed!=null,"static city meshes and collisions pack successfully")
	_check(not details.is_empty(),"cosmetic detail retains serialized transforms")
	if packed!=null:
		var path := "user://mycity_compiled_test_"+str(OS.get_process_id())+".res"
		_check(ResourceSaver.save(packed,path,ResourceSaver.FLAG_COMPRESS)==OK,"packed mesh resources can be persisted")
		var from_disk := ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		_check(from_disk!=null,"compiled scene can be loaded from disk")
		if from_disk!=null:
			var restored := World.new()
			root.add_child(restored)
			restored.set_process(false)
			restored.detail_stream_enabled = true
			restored.geography.footprints = [{"id":"test","poly":poly}]
			var data := {"materials":world.compiled_materials,"details":details,"npc_doors":world.npc_doorways,"walkways":[],"kept":["test"],"landmark_sites":[],"editable":{},"rendered":{},"services":{},"heights":{"estimated":1},"mapped":1,"market_drawn":false}
			_check(restored._compiled_restore({"scene":from_disk,"data":data}),"restore static scene and gameplay metadata")
			_check(restored.npc_doorways==world.npc_doorways,"door thresholds preserved exactly")
			_check(restored.kept_footprints.size()==1,"canonical footprint restored")
			_check(restored.detail_stream_tiles.size()==world.detail_stream_tiles.size(),"deferred visual batches preserved")
			var solids := 0
			var meshes := 0
			for node in restored.get_children():
				_check(not _has_scene_owner(node),"restored runtime node and descendants have no stale PackedScene owner")
				if node is StaticBody3D: solids += node.get_child_count()
				if node is MeshInstance3D or node is MultiMeshInstance3D: meshes += 1
			_check(solids>=2 and meshes>=2,"compiled walls retain meshes and physical shapes")
			restored._compiled_update_visuals(Vector3(2000,0,0))
			for node in restored.get_children():
				if node is StaticBody3D: _check(node.collision_layer==1,"visual streaming never disables collision")
			restored._compiled_update_visuals(Vector3.ZERO)
			restored.free()
		DirAccess.remove_absolute(path)
	world.free()
	print("MyCity compiled buildings: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)
