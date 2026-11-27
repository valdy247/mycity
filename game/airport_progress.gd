extends RefCounted
# Separate from legacy city saves. Phase 1 contains no cash or property grants.
const SAVE_PATH := "user://mycity_chapter1_v1.json"
const VERSION := 1
const BAG_COUNT := 2
var stage := 0
# 0 first pickup, 1 approach, 2 open, 3 load, 4 second pickup,
# 5 second load, 6 close, 7 board, 8 boarded (phase 2 boundary).
var checkpoint := Vector3(-8.5,.91,3.0)

static func expected_action(step: int) -> String:
	match step:
		0: return "pickup_first"
		1: return "approach"
		2: return "open"
		3: return "load_first"
		4: return "pickup_second"
		5: return "load_second"
		6: return "close"
		7: return "board"
	return ""

func advance(action: String,at: Vector3) -> bool:
	if stage>=8 or action!=expected_action(stage): return false
	stage += 1
	checkpoint = at
	return true

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH): return false
	var file := FileAccess.open(SAVE_PATH,FileAccess.READ)
	if file==null: return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or int(data.get("version",0))!=VERSION: return false
	var step := int(data.get("stage",-1))
	if step<0 or step>8: return false
	var p: Variant = data.get("checkpoint",[])
	if not p is Array or p.size()!=3: return false
	var at := Vector3(float(p[0]),float(p[1]),float(p[2]))
	if not at.is_finite(): return false
	stage = step
	checkpoint = Vector3(clampf(at.x,-35.0,35.0),.91,clampf(at.z,-1.5,25.0))
	return true

func save_game() -> bool:
	var data := {"version":VERSION,"chapter":1,"scene":"airport","stage":stage,"cash":0,"properties":[],"vehicles":[],"businesses":[],"checkpoint":[checkpoint.x,checkpoint.y,checkpoint.z]}
	var temp := SAVE_PATH+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error!=OK: return false
	return DirAccess.rename_absolute(temp,SAVE_PATH)==OK
