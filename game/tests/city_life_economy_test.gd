extends SceneTree
const Life = preload("res://city_life.gd")
const Ledger = preload("res://business_ledger.gd")
var failures := 0

func _initialize() -> void:
	var life := Life.new()
	var ledger := Ledger.new()
	ledger.persistence_enabled = false
	life.ledger = ledger
	life.state = {"cafes":{"test":{"cash":0,"harina":0,"queso":0,"tomate":0,"refresco":0,"perrito":0,"supplier_debt":0}},"supplies":Life.INITIAL.duplicate(true)}
	var cafe: Dictionary = life.state.cafes.test
	for key in Life.MENU:
		var menu: Dictionary = Life.MENU[key]
		var cost := 0.0
		for ingredient in menu.needs:
			cost += float(life._cafe_cost(ingredient))*float(menu.needs[ingredient])/float(Ledger.PRODUCTS[ingredient].units)
		_check(cost<float(menu.price),"positive gross margin: "+String(key))
	_check(life._cafe_buy("test","mayorista_sol","harina"),"empty cafe uses trade credit")
	_check(int(cafe.harina)==10 and int(cafe.supplier_debt)==340,"inventory and commercial debt")
	_check(int(life.state.supplies.mayorista_sol.harina)==14,"supplier crate consumed")
	_check(not life._cafe_buy("test","mayorista_sol","harina"),"no excess restock")
	_check(life._cafe_buy("test","mayorista_sol","refresco"),"drink inventory restock")
	life.agents.append({"site":"test","role":"clerk","departed":false,"task":""})
	_check(life.citizen_purchase("test",59)==0,"cannot buy without budget")
	_check(life.citizen_purchase("test",60)==60,"resident purchases available drink")
	_check(int(cafe.refresco)==9 and int(cafe.cash)==45,"sale consumes stock and pays cafe")
	_check(int(cafe.supplier_debt)==705,"sale repays credit")
	cafe.cash = 1000
	_check(life._delivery_available("test","queso"),"delivery offer when stock is low")
	cafe.delivery_cooldown = 120.0
	_check(not life._delivery_available("test","queso"),"contract cooldown prevents repeated deliveries")
	_check(life._delivery_price("queso")>int(Ledger.PRODUCTS.queso.cost),"delivery premium")
	life.free()
	print("City life economy: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
