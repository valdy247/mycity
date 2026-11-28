extends SceneTree
const Ledger = preload("res://business_ledger.gd")
const Life = preload("res://city_life.gd")
const Business = preload("res://business_mission.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _run() -> void:
	# Isolated temporary save, never touch the player's live save.
	var path := "user://mycity_life_logic_test_"+str(OS.get_process_id())+".json"
	var ledger := Ledger.new()
	ledger.save_path = path
	ledger.cash = 1000
	ledger.life_data = {"test":true}
	ledger.save_game()
	ledger.cash = 800
	ledger.save_game()
	var corrupt := FileAccess.open(path,FileAccess.WRITE)
	if corrupt!=null:
		corrupt.store_string("{invalid")
		corrupt.close()
	var restored := Ledger.new()
	restored.save_path = path
	restored.load_game()
	_check(restored.cash==1000 and bool(restored.life_data.get("test",false)),"corrupt primary recovers last valid backup")
	restored.change_reputation("Carlos",80)
	_check(restored.reputation("Carlos")==100,"reputation has upper bound")
	restored.change_reputation("Carlos",-200)
	_check(restored.reputation("Carlos")==0 and restored.reputation("Albertico")==50,"independent reputation and lower bound")
	restored.persistence_enabled = false
	restored.stage = 4
	restored.stock = {"huevos":1}
	var before := restored.cash
	var sale := restored.sell_one(false)
	_check(not sale.is_empty() and restored.cash>before and restored.stock.huevos==0,"sale consumes inventory before credit")
	var paid := restored.cash
	_check(restored.sell_one(false).is_empty() and restored.cash==paid,"empty stock cannot duplicate income")
	var life := Life.new()
	life.state = {"minutes":480.0,"day":1,"cafes":{}}
	var cafe := {"cash":2600,"supplier_debt":200,"management":{"staff":true,"last_day":1,"sales":1000,"costs":200,"withdrawn":0,"wage_due":0}}
	life._pay_cafe_wage(cafe,2)
	_check(int(cafe.cash)==2480 and int(cafe.management.costs)==320,"daily wages debited once")
	life._pay_cafe_wage(cafe,2)
	_check(int(cafe.cash)==2480,"same day cannot charge wages twice")
	_check(life._cafe_withdrawable(cafe)==280,"profit withdrawal protects reserves and debt")
	cafe.cash = 100
	life._pay_cafe_wage(cafe,3)
	_check(int(cafe.cash)==0 and int(cafe.management.wage_due)==20,"unpaid wages become liability, not negative cash")
	_check(life._cafe_withdrawable(cafe)==0,"insolvent cafe cannot withdraw")
	life.state.cafes["test"] = cafe
	_check(not life._cafe_open("test"),"unpaid staff closes managed cafe")
	# Closed cafés cannot sell to simulated pedestrians even with inventory.
	life.state.minutes = 60.0
	cafe.management.staff = true
	cafe.management.wage_due = 0
	_check(not life._cafe_open("test"),"night closure applies even with paid staff")
	_check(life.citizen_purchase("test",500)==0,"closed cafe rejects simulated customer")
	# Verify the route cooldown never blocks emergency income, and lateness
	# reduces compensation rather than deleting the job.
	var mission := Business.new()
	mission.life = life
	mission.ledger.persistence_enabled = false
	mission.ledger.cash = 1000
	mission.ledger.life_data.job_route_history = {"a→b":mission._job_now()+90.0}
	_check(not mission._job_route_available("a","b"),"recently completed route cools down")
	mission.ledger.cash = 0
	_check(mission._job_route_available("a","b"),"broke player always has access to work")
	var job := {"pay":300,"deadline":mission._job_now()+10.0}
	_check(mission._job_pay(job)==300,"on-time job pays full amount")
	life.state.minutes += 11.0
	_check(mission._job_pay(job)==240,"late job remains payable at reduced rate")
	mission.free()
	life.free()
	# Recover a complete temp snapshot if the primary never committed.
	var pending := Ledger.new()
	pending.save_path = path+".pending"
	pending.cash = 345
	pending.save_game()
	DirAccess.rename_absolute(path+".pending",path+".tmp")
	var recovered := Ledger.new()
	recovered.save_path = path
	recovered.load_game()
	_check(recovered.cash==345,"complete interrupted temp write recovered before older backup")
	for suffix in ["",".bak",".tmp",".bak.tmp",".pending"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("MyCity life logic: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)
