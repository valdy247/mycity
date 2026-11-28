extends RefCounted
# Persistent CPU-only map preparation. Never stores saves, nodes, resources,
# traffic state or user edits. The original OSM remains authoritative.
const MapData = preload("res://pilar_map.gd")
const Streets = preload("res://street_geometry.gd")
const Surfaces = preload("res://city_street_mesh_data.gd")
const VERSION := 1
const CACHE := "user://mycity_prepared_map_v1.bin"
const MAX_BYTES := 256*1024*1024

static func source_path() -> String:
	if OS.has_feature("web") and FileAccess.file_exists(MapData.WEB_PATH): return MapData.WEB_PATH
	if FileAccess.file_exists(MapData.PATH): return MapData.PATH
	return "" if OS.has_feature("web") else MapData.OLD_PATH

static func fingerprint() -> String:
	var path := source_path()
	if path.is_empty() or not FileAccess.file_exists(path): return ""
	var key := str(VERSION)+":"+str(Engine.get_version_info().get("string",""))+":"+path
	for file_path in [path,"res://pilar_map.gd","res://street_geometry.gd","res://city_street_mesh_data.gd","res://city_map_cache.gd"]:
		# Exported scripts may not be available as source. Don't reuse a
		# cache when its generator cannot be fingerprinted.
		if not FileAccess.file_exists(file_path): return ""
		var digest := FileAccess.get_sha256(file_path)
		if digest.is_empty(): return ""
		key += ":"+digest
	return key.sha256_text()

static func prepare() -> Dictionary:
	var started := Time.get_ticks_msec()
	var key := fingerprint() if not OS.has_feature("web") else ""
	var enabled := not key.is_empty() and not OS.get_cmdline_user_args().has("--no-map-cache")
	if enabled:
		var restored := _read(key)
		if not restored.is_empty():
			restored["topology_ms"] = Time.get_ticks_msec()-started
			restored["surface_ms"] = 0
			restored["cache_hit"] = true
			print("MyCity cache: HIT · mapa y superficies preparados en ",restored.topology_ms," ms")
			return restored
	var geo := MapData.new()
	if not geo.load_map(): return {}
	var market := geo.market_street_block(geo.project(23.1234716,-82.3659728))
	if not market.is_empty(): geo.remove_market_spurs(market)
	var streets := Streets.new()
	streets.build(geo)
	var topology_ms := Time.get_ticks_msec()-started
	var surface_started := Time.get_ticks_msec()
	var surfaces := Surfaces.prepare(streets)
	var surface_ms := Time.get_ticks_msec()-surface_started
	if enabled:
		_write(key,geo,streets,market,surfaces)
	print("MyCity cache: MISS · preparación=",topology_ms+surface_ms," ms")
	return {"geography":geo,"streets":streets,"market":market,"surfaces":surfaces,"topology_ms":topology_ms,"surface_ms":surface_ms,"cache_hit":false}

static func _digest(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()

static func _write(key: String,geo: MapData,streets: Streets,market: Dictionary,surfaces: Dictionary,path: String = CACHE) -> void:
	var snapshot := {
		"points":geo.points,"roads":geo.roads,"graph":geo.graph,"names":geo.names,
		"signals":geo.signal_nodes,"building_count":geo.building_count,"footprints":geo.footprints,
		"junction_keys":geo.junctions.keys(),
		"stadium":geo.stadium_boundary,"parks":geo.park_areas,"poi":geo.poi,
		"street_roads":streets.roads,"sidewalks":streets.sidewalks,"road_index":streets.road_index,
		"protected_index":streets.protected_index,"intersections":streets.intersection_cells,
		"signal_sites":streets.signal_sites,"serial":streets._serial,
		"market":market,"surfaces":surfaces
	}
	var bytes := var_to_bytes(snapshot)
	if bytes.is_empty() or bytes.size()>MAX_BYTES: return
	var temp := path+"."+str(OS.get_process_id())+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return
	file.store_line(key)
	file.store_line(_digest(bytes))
	file.store_64(bytes.size())
	file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(temp,path)!=OK:
		DirAccess.remove_absolute(temp)

static func _read(key: String,path: String = CACHE) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return {}
	if file.get_length()>MAX_BYTES+512 or file.get_line()!=key: return {}
	var digest := file.get_line()
	var size := file.get_64()
	if size<=0 or size>MAX_BYTES or size!=file.get_length()-file.get_position(): return {}
	var bytes := file.get_buffer(size)
	if _digest(bytes)!=digest: return {}
	var raw: Variant = bytes_to_var(bytes)
	if not raw is Dictionary: return {}
	var data: Dictionary = raw
	for field in ["points","graph","names","signals","road_index","protected_index","intersections","market","surfaces"]:
		if not data.get(field) is Dictionary: return {}
	for field in ["roads","footprints","parks","poi","street_roads","sidewalks","signal_sites","junction_keys"]:
		if not data.get(field) is Array: return {}
	if not data.get("stadium") is PackedVector2Array or not data.get("serial") is int: return {}
	if data.roads.size()<20 or data.points.is_empty() or data.street_roads.is_empty(): return {}
	if not data.surfaces.get("road") is Array or not data.surfaces.get("sidewalk") is Array: return {}
	var geo := MapData.new()
	geo.source_path = source_path()
	geo.points = data.points
	geo.roads = data.roads
	geo.graph = data.graph
	geo.names = data.names
	geo.signal_nodes = data.signals
	geo.building_count = int(data.get("building_count",0))
	geo.footprints = data.footprints
	geo.stadium_boundary = data.stadium
	geo.park_areas = data.parks
	geo.poi = data.poi
	# Rebuild spatial indexes from the canonical dictionaries so edits and
	# callers see the same edge/footprint objects, not deserialized copies.
	for id in data.junction_keys:
		geo.junctions[id] = []
	for edge in geo.roads:
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var radius := float(edge.width)*.5+3.0
		geo._index(geo.road_cells,a.min(b)-Vector3(radius,0,radius),a.max(b)+Vector3(radius,0,radius),edge)
		for id in [edge.a_id,edge.b_id]:
			if not geo.junctions.has(id): geo.junctions[id] = []
			geo.junctions[id].append(edge)
	for fp in geo.footprints:
		geo._index(geo.footprint_cells,fp.low,fp.high,fp)
	var streets := Streets.new()
	streets.map_data = geo
	streets.roads = data.street_roads
	streets.sidewalks = data.sidewalks
	streets.road_index = data.road_index
	streets.protected_index = data.protected_index
	streets.intersection_cells = data.intersections
	streets.signal_sites = data.signal_sites
	streets._serial = int(data.serial)
	return {"geography":geo,"streets":streets,"market":data.market,"surfaces":data.surfaces}
