extends RefCounted
# New interior arrival sequence; v1 exterior-only saves are left intact.
const SAVE_PATH := "user://mycity_chapter1_v2.json"
const VERSION := 2
const ACTIONS := ["next","passport","return_passport","pass_gate","cart","pickup_first","cart_first","pickup_second","cart_second","exit","driver_open","take_first","load_first","take_second","load_second","driver_close","board"]
const COMPLETE := 17
const SPAWN := Vector3(0,.91,-29)
var stage := 0
var checkpoint := SPAWN
var cart_position := Vector3(-5,.03,-16)

static func expected_action(step: int) -> String:
	return ACTIONS[step] if step>=0 and step<ACTIONS.size() else ""

static func bag_location(step: int,id: int) -> String:
	if id==0:
		if step>=13: return "trunk"
		if step==12 or step==6: return "hand"
		if step>=7: return "cart"
	else:
		if step>=15: return "trunk"
		if step==14 or step==8: return "hand"
		if step>=9: return "cart"
	return "belt"

func advance(action: String,at: Vector3) -> bool:
	if stage>=COMPLETE or action!=expected_action(stage) or not at.is_finite(): return false
	stage += 1
	checkpoint = at
	return true

func _read_point(value: Variant,fallback: Vector3) -> Vector3:
	if not value is Array or value.size()!=3: return fallback
	for n in value:
		if not n is float and not n is int: return fallback
	var at := Vector3(float(value[0]),float(value[1]),float(value[2]))
	if not at.is_finite(): return fallback
	return Vector3(clampf(at.x,-35,35),fallback.y,clampf(at.z,-31,25))

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH): return false
	var file := FileAccess.open(SAVE_PATH,FileAccess.READ)
	if file==null: return false
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or int(data.get("version",0))!=VERSION: return false
	var step := int(data.get("stage",-1))
	if step<0 or step>COMPLETE: return false
	stage = step
	checkpoint = _read_point(data.get("checkpoint",[]),SPAWN)
	cart_position = _read_point(data.get("cart_position",[]),Vector3(-5,.03,-16))
	return true

func save_game() -> bool:
	var data := {"version":VERSION,"chapter":1,"scene":"airport","stage":stage,"cash":0,"properties":[],"vehicles":[],"businesses":[],"checkpoint":[checkpoint.x,checkpoint.y,checkpoint.z],"cart_position":[cart_position.x,cart_position.y,cart_position.z]}
	var temp := SAVE_PATH+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error!=OK: return false
	return DirAccess.rename_absolute(temp,SAVE_PATH)==OK
