extends SceneTree
const Map = preload("res://pilar_map.gd")
const Routes = preload("res://taxi_routes.gd")
var failures := 0

func _initialize() -> void:
	var data := Map.new()
	data.points = {"a":Vector3(0,0,0),"b":Vector3(20,0,0),"c":Vector3(20,0,20),"d":Vector3(40,0,0),"e":Vector3(40,0,20)}
	data.graph = {"a":["b"],"b":["c","d"],"c":[],"d":["e"],"e":[]}
	for item in [["a","b","Pila"],["b","c","Matadero"],["b","d","Pila"],["d","e","Estévez"]]:
		data.roads.append({"a_id":item[0],"b_id":item[1],"name":item[2],"driveable":true,"aliases":[]})
	var router := Routes.new()
	router.setup(data)
	var exact := router.resolve("Pila y Matadero","a")
	_check(not exact.has("error") and exact.get("id","")=="b","exact corner")
	var fallback := router.resolve("Desconocida y Matadero","a")
	_check(not fallback.has("error") and not String(fallback.get("note","")).is_empty(),"one known street")
	var accented := router.resolve("pila y estevez","a")
	_check(not accented.has("error") and accented.get("id","")=="d","accent-insensitive lookup")
	_check(router.resolve("Pila y Matadero","e").has("error"),"one-way route cannot go backwards")
	_check(router.resolve("Inventada y Inexistente","a").has("error"),"two unknown streets")
	_check(router.resolve("Matadero y Estévez","a").has("error"),"known streets without shared corner")
	print("Taxi routes: ", "PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
