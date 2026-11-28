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
	for wall in range(5):
		for y in range(mission._rows(wall)):
			for x in range(mission._columns(wall)):
				if mission._covered(wall,x,y): continue
				keys[mission._cell_key(wall,x,y)] = mission._required(wall)
	_check(keys.size()==Mission.TOTAL,"four wall surfaces plus six door cells without double-counting")
	# Carlos must keep working after the first wall, then leave two walls
	# and the door for the player unless their colors need repair.
	mission.state = {"painted":{}}
	var worker_tiles := 0
	var worker_walls: Dictionary = {}
	for i in range(Mission.TOTAL):
		var job := mission._worker_next()
		if job.is_empty(): break
		var wall := int(job.wall)
		worker_walls[wall] = true
		mission.state.painted[mission._cell_key(wall,int(job.x),int(job.y))] = job.color
		worker_tiles += 1
	_check(worker_walls.size()==2 and worker_walls.has(2) and worker_walls.has(0),"Carlos paints exactly two complete walls")
	_check(worker_tiles==2*mission._columns(0)*mission._rows(0),"Carlos completes every cell of both assigned walls")
	_check(mission._worker_next().is_empty(),"Carlos leaves unpainted remaining walls and door to player")
	mission.state = {"painted":keys.duplicate()}
	mission.correct_tiles = mission._correct_count()
	_check(mission._finished(),"correct blue walls and yellow door permit payment")
	mission.state.painted["4:0:0"] = "blue"
	mission.correct_tiles = mission._correct_count()
	_check(not mission._finished(),"blue door prevents payment")
	mission.state.painted["0:0:0"] = "yellow"
	mission.correct_tiles = mission._correct_count()
	_check(mission.correct_tiles==Mission.TOTAL-2,"wrong wall and door colors both rejected")
	var repair := mission._worker_next()
	_check(int(repair.get("wall",-1))==0 and String(repair.get("color",""))=="blue","Carlos repairs wrong wall after his own wall")
	mission.state.painted["0:0:0"] = "blue"
	repair = mission._worker_next()
	_check(int(repair.get("wall",-1))==4 and String(repair.get("color",""))=="yellow","Carlos repairs wrong door with yellow")
	mission.state.painted["4:0:0"] = "yellow"
	mission.correct_tiles = mission._correct_count()
	_check(mission._finished(),"correcting errors restores completion")
	garage.state.part = "bicicleta:wheel_a"
	garage.state.wheel_tutorial = false
	_check(garage._wheel_pending(),"reward wheel awaits physical garage arrival")
	garage.state.wheel_tutorial = true
	_check(not garage._wheel_pending(),"tutorial cannot be repeated")
	# Replay keeps the wallet, other projects and any earned higher tiers.
	var balance: int = business.ledger.cash
	business.ledger.stage = 4
	business.ledger.life_data.carlos_paint = {"stage":4,"painted":{"0:0:0":"blue"},"brush":true,"charge":7,"home":{"x":1,"z":2}}
	garage._restart_carlos_once()
	var replay: Dictionary = business.ledger.life_data.carlos_paint
	_check(int(replay.stage)==0 and replay.painted.is_empty() and not bool(replay.brush),"painting replay begins from phone call")
	_check(replay.has("home"),"saved Carlos location retained")
	_check(business.ledger.cash==balance and business.ledger.stage==4,"wallet and Albertico remain unchanged")
	replay.stage = 3
	garage._restart_carlos_once()
	_check(int(replay.stage)==3,"replay migration runs only once")
	# Phone purchase availability does not install any parts.
	garage.state.inventory["bicicleta:wheel_b"] = 1
	_check(garage._part_already_available("bicicleta","wheel_b"),"already purchased part cannot be ordered twice")
	garage._part_menu("bicicleta","wheel_b")
	_check(int(garage.state.inventory["bicicleta:wheel_b"])==1 and not bool(garage.state.projects.bicicleta.get("wheel_b",false)),"no installation outside the garage")
	garage.state.paint_tool = "brush"
	garage.state.paint_active = ""
	garage.state.paint_charge = 0
	garage.state.paint_stock = {"azul":Garage.CAN_CAPACITY}
	garage.state.empty_paint = {}
	for i in range(30):
		garage._dip_home_brush("azul")
		_check(int(garage.state.paint_charge)==Garage.BRUSH_LOAD,"dip loads physical brush")
		garage.state.paint_charge = 0
	_check(int(garage.state.paint_stock.azul)==0,"one can covers exactly 300 fresh paint strokes")
	garage._dip_home_brush("azul")
	_check(int(garage.state.paint_charge)==0,"empty can cannot refill")
	_check(int(garage.state.empty_paint.azul)==1,"empty paint can remains as waste")
	garage.state.waste_items = []
	garage.state.waste_overflow = []
	for i in range(3):
		_check(garage.add_house_waste("paint_can",3,"azul"),"can fits in household bag")
	_check(garage.add_house_waste("scrap",1),"last space can be filled")
	_check(Garage.waste_volume(garage.state.waste_items)==Garage.WASTE_CAPACITY,"bag at full capacity")
	_check(not garage.add_house_waste("scrap",1),"full bag refuses more waste")
	_check(garage.state.waste_overflow.size()==1,"overflow remains recoverable on floor")
	garage.state.floor_marks = {}
	var spot := Garage.ROOM+Vector3(2,0,2)
	garage._floor_mark(spot,"azul")
	_check(String(garage.state.floor_marks.get(garage._floor_key(spot),""))=="azul","paint spill persists")
	garage._sweep_at(spot)
	_check(garage.state.floor_marks.is_empty(),"broom clears paint spill")
	garage._floor_mark(spot,"dirt")
	garage._sweep_at(spot)
	_check(garage.state.floor_marks.is_empty(),"broom clears house dirt")
	mission.free()
	garage.free()
	business.free()
	print("Carlos and garage progression: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
