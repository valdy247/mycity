extends SceneTree
const Residents = preload("res://resident_simulation.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _run() -> void:
	var row := {"job":"oficio","money":400}
	Residents.advance(row,201,480.0)
	_check(row.objective=="trabajar","daytime worker chooses work")
	Residents.advance(row,201,1021.0)
	_check(int(row.money)==540,"daily salary credited exactly once")
	Residents.advance(row,201,1080.0)
	_check(int(row.money)==540,"same shift cannot pay again")
	var same := row.duplicate(true)
	Residents.advance(row,201,1080.0)
	_check(row==same,"same clock does not alter needs or finances")
	Residents.advance(row,201,1800.0)
	_check(float(row.hunger)>=0 and float(row.hunger)<=100,"sleep keeps hunger bounded")
	_check(float(row.energy)>=0 and float(row.energy)<=100,"sleep keeps energy bounded")
	var before := int(row.money)
	_check(not Residents.purchase(row,before+1,1800.0),"cannot buy beyond wallet")
	_check(int(row.money)==before,"failed purchase leaves balance unchanged")
	var hunger := float(row.hunger)
	_check(Residents.purchase(row,60,1800.0),"affordable meal purchased")
	_check(int(row.money)==before-60 and float(row.hunger)<=hunger,"meal consumes money and reduces hunger")
	Residents.greet(row,1800.0)
	Residents.greet(row,1801.0)
	_check(int(row.relationship)==2,"repeat greetings do not farm trust")
	Residents.greet(row,1861.0)
	_check(int(row.relationship)==4,"later greeting builds trust")
	var student := {"job":"estudio","money":300}
	Residents.advance(student,202,480.0)
	Residents.advance(student,202,1021.0)
	_check(int(student.money)==300,"student receives no automatic wage")
	_check(Residents.now({"day":2,"minutes":480.0})==1920.0,"clock remains monotonic across midnight")
	print("MyCity resident simulation: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)
