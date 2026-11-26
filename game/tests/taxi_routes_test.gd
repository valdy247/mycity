extends SceneTree
const Map = preload("res://pilar_map.gd")
const Routes = preload("res://taxi_routes.gd")
var failures := 0

func _initialize() -> void:
	var data := Map.new()
	data.points = {"a":Vector3(0,0,0),"b":Vector3(20,0,0),"c":Vector3(20,0,20),"d":Vector3(40,0,0),"e":Vector3(40,0,20)}
	data.graph = {"a":["b"],"b":["c","d"],"c":[],"d":["e"],"e":[]}
	for item in [["a","b","Pila"],["b","c","Matadero"],["b","d","Pila"],["d","e","Estévez"]]:
		var a: Vector3 = data.points[item[0]]
		var b: Vector3 = data.points[item[1]]
		var edge := {"a_id":item[0],"b_id":item[1],"a":a,"b":b,"width":6.0,"name":item[2],"driveable":true,"aliases":[]}
		data.roads.append(edge)
		data._index(data.road_cells,a.min(b),a.max(b),edge)
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
	var clicked_corner := router.resolve_point(Vector3(20,0,0),"a")
	_check(not clicked_corner.has("error") and clicked_corner.get("id","")=="b" and not bool(clicked_corner.get("partial",true)),"map corner")
	var clicked_street := router.resolve_point(Vector3(20,0,14),"a")
	_check(not clicked_street.has("error") and bool(clicked_street.get("partial",false)) and clicked_street.get("exit","")=="c","map mid-street one-way route")
	if not clicked_street.has("error"):
		var point: Vector3 = clicked_street.point
		_check(point.distance_to(Vector3(20,0,14))<.01,"map destination is not moved to end of street")
	_check(router.resolve_point(Vector3(20,0,0),"e").has("error"),"map inaccessible destination")
	print("Taxi routes: ", "PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
