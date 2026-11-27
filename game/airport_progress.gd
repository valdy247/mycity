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
var cart_attached := false
var cart_angle := 0.0
var first_bag := 0
var ride_finished := false

static func expected_action(step: int) -> String:
	return ACTIONS[step] if step>=0 and step<ACTIONS.size() else ""

static func bag_location(step: int,id: int,first: int=0) -> String:
	if id==first:
		if step>=13: return "trunk"
		if step==12 or step==6: return "hand"
		if step>=7: return "cart"
	else:
		if step>=15: return "trunk"
		if step==14 or step==8: return "hand"
		if step>=9: return "cart"
	return "belt"

# Parking and taking the cart are separate from luggage ownership.
func set_cart_attached(value: bool) -> bool:
	if value==cart_attached: return false
	if value and stage not in [5,7,9]: return false
	if not value and stage not in [5,7,10]: return false
	cart_attached = value
	return true

func advance(action: String,at: Vector3,bag_id: int=-1) -> bool:
	if stage>=COMPLETE or not at.is_finite(): return false
	# The cart can stay at its original position. Both bags must still be loaded into it.
	if stage==4 and action=="pickup_first" and bag_id in [0,1]:
		first_bag = bag_id
		cart_attached = false
		stage = 6
		checkpoint = at
		return true
	if action!=expected_action(stage): return false
	if stage in [5,6,7,8] and cart_attached: return false
	if stage==9 and not cart_attached: return false
	if stage==10 and cart_attached: return false
	if stage==5:
		if bag_id not in [0,1]: return false
		first_bag = bag_id
	if stage==7 and bag_id!=1-first_bag: return false
	if stage==4: cart_attached = true
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
	ride_finished = bool(data.get("ride_finished",false)) and step==COMPLETE
	first_bag = clampi(int(data.get("first_bag",0)),0,1)
	checkpoint = _read_point(data.get("checkpoint",[]),SPAWN)
	cart_position = _read_point(data.get("cart_position",[]),Vector3(-5,.03,-16))
	# Existing v2 checkpoints remain usable, even if the cart was previously glued to the player.
	cart_attached = bool(data.get("cart_attached",step in [5,7,10]))
	if step<5 or step in [6,8] or step>=11: cart_attached = false
	# Saves from the short-lived direct-to-taxi route restart only baggage collection.
	# Migration remains completed; no legacy city data is touched.
	if bool(data.get("direct_mode",false)):
		stage = 4
		checkpoint = Vector3(0,.91,-17.8)
		cart_position = Vector3(-5,.03,-16)
		cart_attached = false
		first_bag = 0
		cart_angle = 0.0
		return true
	cart_angle = float(data.get("cart_angle",0.0))
	if not is_finite(cart_angle): cart_angle = 0.0
	return true

func save_game() -> bool:
	var data := {"version":VERSION,"chapter":1,"scene":"airport","stage":stage,"ride_finished":ride_finished,"cash":0,"properties":[],"vehicles":[],"businesses":[],"checkpoint":[checkpoint.x,checkpoint.y,checkpoint.z],"cart_position":[cart_position.x,cart_position.y,cart_position.z],"cart_attached":cart_attached,"cart_angle":cart_angle,"first_bag":first_bag}
	var temp := SAVE_PATH+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return false
	file.store_string(JSON.stringify(data))
	file.flush()
	var error := file.get_error()
	file.close()
	if error!=OK: return false
	return DirAccess.rename_absolute(temp,SAVE_PATH)==OK
