extends SceneTree
const Garage = preload("res://home_garage.gd")
const Business = preload("res://business_mission.gd")
const Mission = preload("res://carlos_mission.gd")
var failures := 0

func _initialize() -> void:
	var business := Business.new()
	business.ledger.persistence_enabled = false
	var garage := Garage.new()
	garage.business = business
	garage.state = {"project":"bicicleta","projects":{"bicicleta":{"frame":true},"moto":{"frame":true}},"parked":{"bicicleta":{"x":1}},"inventory":{"bicicleta:wheel_b":2,"moto:seat":1},"deliveries":[{"token":"bicicleta:wheel_a"},{"token":"moto:wheel_a"}],"part":"moto:drive"}
	garage._prepare_progression()
	_check(not garage.state.projects.has("bicicleta"),"legacy bicycle reset")
	_check(garage.state.projects.has("moto"),"other installed parts preserved")
	_check(int(garage.state.inventory["moto:drive"])==1,"old held part safely stored")
	_check(not garage.state.inventory.has("bicicleta:wheel_b"),"old bike inventory reset")
	_check(garage.state.deliveries.size()==1,"only old bicycle orders cleared")
	_check(not garage._unlocked("bicicleta"),"painting reward required")
	business.ledger.life_data.carlos_paint = {"stage":5}
	_check(garage._unlocked("bicicleta") and not garage._unlocked("triciclo"),"first project only")
	garage.state.vehicle_level = 1
	_check(garage._unlocked("triciclo") and not garage._unlocked("moto"),"next project after sale")
	garage.state.projects.bicicleta = {"wheel_a":true}
	garage._prepare_progression()
	_check(bool(garage.state.projects.bicicleta.wheel_a),"migration is idempotent")
	var mission := Mission.new()
	var keys: Dictionary = {}
	for wall in range(4):
		for y in range(Mission.ROWS):
			for x in range(Mission.COLS): keys[mission._cell_key(wall,x,y)] = true
	_check(keys.size()==Mission.TOTAL,"unique paint cells across four walls")
	mission.free()
	garage.free()
	business.free()
	print("Carlos and garage progression: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
