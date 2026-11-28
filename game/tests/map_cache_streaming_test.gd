extends SceneTree
const Cache = preload("res://city_map_cache.gd")
const MapData = preload("res://pilar_map.gd")
const Streets = preload("res://street_geometry.gd")
const Surfaces = preload("res://city_street_mesh_data.gd")
const World = preload("res://cuba_world.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _run() -> void:
	# No private map or saved game is required; build a small deterministic
	# road graph and use a separate disposable cache file.
	var geo := MapData.new()
	for i in range(25):
		geo.points[str(i)] = Vector3(float(i)*12.0,0,0)
	for i in range(24):
		var a_id := str(i)
		var b_id := str(i+1)
		var a: Vector3 = geo.points[a_id]
		var b: Vector3 = geo.points[b_id]
		var edge := {"a":a,"b":b,"a_id":a_id,"b_id":b_id,"width":6.4,"name":"Prueba","kind":"residential","portal":false,"driveable":true,"aliases":[]}
		geo.roads.append(edge)
		for id in [a_id,b_id]:
			if not geo.junctions.has(id): geo.junctions[id] = []
			geo.junctions[id].append(edge)
			if not geo.graph.has(id): geo.graph[id] = []
		geo.graph[a_id].append(b_id)
		geo.graph[b_id].append(a_id)
		geo._index(geo.road_cells,a-Vector3(6.2,0,6.2),b+Vector3(6.2,0,6.2),edge)
	geo.names["Prueba"] = true
	var streets := Streets.new()
	streets.build(geo)
	var surfaces := Surfaces.prepare(streets)
	var path := "user://mycity_map_cache_test_"+str(OS.get_process_id())+".bin"
	Cache._write("test-key",geo,streets,{},surfaces,path)
	var restored := Cache._read("test-key",path)
	_check(not restored.is_empty(),"read a valid cache")
	if not restored.is_empty():
		var g: MapData = restored.geography
		var st: Streets = restored.streets
		_check(g.points==geo.points and g.graph==geo.graph and g.roads==geo.roads,"round trip preserves geography")
		_check(g.junctions==geo.junctions and g.junctions.keys()==geo.junctions.keys(),"junction order and edges preserved")
		_check(g.road_cells==geo.road_cells,"spatial index round trip")
		_check(st.roads==streets.roads and st.sidewalks==streets.sidewalks,"street polygons preserved")
		_check(restored.surfaces==surfaces,"clipped surfaces preserved")
		_check(st._serial==streets._serial and st.protected_index==streets.protected_index,"future spatial registrations remain valid")
		_check(st.point_on_road(Vector3(5,0,0)),"restored road geometry query")
		g.roads[0]["test_marker"] = true
		_check(bool(g.junctions["0"][0].get("test_marker",false)),"junctions retain canonical road identity")
	_check(Cache._read("wrong-key",path).is_empty(),"changed fingerprint invalidates cache")
	var broken := FileAccess.open(path,FileAccess.WRITE)
	if broken!=null:
		broken.store_string("truncated")
		broken.close()
	_check(Cache._read("test-key",path).is_empty(),"corrupt cache falls back safely")
	DirAccess.remove_absolute(path)
	# Verify that cosmetic data streams while structural batches remain
	# resident. No world setup or save-file access takes place.
	var world := World.new()
	root.add_child(world)
	world.set_process(false)
	world.detail_stream_enabled = true
	var mat := StandardMaterial3D.new()
	var item := {"material":mat,"transforms":[Transform3D.IDENTITY],"home_level":0,"origin":Vector3.ZERO,"detail":true}
	world.box_groups["detail"] = item
	var structural := item.duplicate()
	structural.detail = false
	world.box_groups["structural"] = structural
	world._flush_city_boxes()
	_check(world.detail_stream_tiles.size()==1 and world.detail_batches==0,"cosmetic batch deferred")
	_check(world.get_child_count()==1,"structural batch stays resident")
	world._detail_stream_update(Vector3.ZERO)
	_check(world.detail_stream_pending.size()==1,"nearby tile queued")
	var entry: Dictionary = world.detail_stream_tiles[Vector2i.ZERO]
	entry.nodes.append(world._create_city_box_batch(item))
	entry.next = 1
	world._detail_stream_update(Vector3(450,0,48))
	_check(int(entry.next)==1,"hysteresis prevents premature unload")
	world._detail_stream_update(Vector3(1000,0,0))
	_check(int(entry.next)==0 and entry.nodes.is_empty() and world.detail_batches==0,"far detail unloads")
	world._detail_stream_update(Vector3.ZERO)
	_check(world.detail_stream_pending.size()==1,"returning to tile queues detail again")
	world.free()
	print("MyCity map cache and visual streaming: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)
