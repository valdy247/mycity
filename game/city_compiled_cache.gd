extends RefCounted
# A packed, value-only static city snapshot. The manifest is committed last:
# interrupted writes cannot make a partial scene eligible for reuse.
const Derived = preload("res://city_derived_cache.gd")
const MANIFEST := "user://mycity_compiled_buildings_v1.bin"
const SCENE_PREFIX := "user://mycity_compiled_buildings_v1_"
const MAX_SCENE_BYTES := 256*1024*1024

static func read(key: String) -> Dictionary:
	var manifest := Derived.read(MANIFEST,key)
	if manifest.is_empty(): return {}
	var expected := String(manifest.get("scene_digest",""))
	if expected.length()!=64 or not expected.is_valid_hex_number(): return {}
	var path := SCENE_PREFIX+expected+".res"
	if not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null or file.get_length()>MAX_SCENE_BYTES: return {}
	file.close()
	if FileAccess.get_sha256(path)!=expected: return {}
	var scene := ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if scene==null or not scene.can_instantiate(): return {}
	return {"scene":scene,"data":manifest}

static func write(key: String,scene: PackedScene,data: Dictionary) -> bool:
	if key.is_empty(): return false
	var temp := SCENE_PREFIX+str(OS.get_process_id())+".tmp.res"
	if ResourceSaver.save(scene,temp,ResourceSaver.FLAG_COMPRESS)!=OK: return false
	var file := FileAccess.open(temp,FileAccess.READ)
	if file==null: return false
	var size := file.get_length()
	file.close()
	if size<=0 or size>MAX_SCENE_BYTES:
		DirAccess.remove_absolute(temp)
		return false
	var digest := FileAccess.get_sha256(temp)
	if digest.length()!=64:
		DirAccess.remove_absolute(temp)
		return false
	var path := SCENE_PREFIX+digest+".res"
	if not FileAccess.file_exists(path):
		if DirAccess.rename_absolute(temp,path)!=OK:
			DirAccess.remove_absolute(temp)
			return false
	else:
		DirAccess.remove_absolute(temp)
	data["scene_digest"] = digest
	Derived.write(MANIFEST,key,data)
	# Retain the last verified generation; prune obsolete snapshots only
	# after verifying that the manifest commit actually succeeded.
	var verified := Derived.read(MANIFEST,key)
	if String(verified.get("scene_digest",""))!=digest: return false
	for name_value in DirAccess.get_files_at("user://"):
		if name_value.begins_with("mycity_compiled_buildings_v1_") and name_value.ends_with(".res") and not name_value.ends_with(".tmp.res") and name_value!="mycity_compiled_buildings_v1_"+digest+".res":
			DirAccess.remove_absolute("user://"+name_value)
	return true
