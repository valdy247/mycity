extends SceneTree
const Ledger = preload("res://business_ledger.gd")
var failures := 0

func _initialize() -> void:
	var game := Ledger.new()
	game.persistence_enabled = false
	_check(game.cash==10000 and game.stage==0,"initial wallet and mission")
	_check(not game.buy("pollo",1),"locked before accepting")
	game.accept()
	_check(game.stage==1 and not game.buy("pollo",1),"must arrive at factory")
	game.factory_arrival()
	_check(game.buy("pollo",1) and game.cash==7800,"purchase deducts correct amount")
	_check(not game.buy("pollo",8) and game.cash==7800,"insufficient funds")
	_check(game.pick_up("pollo") and not game.pick_up("pollo"),"no duplicate pickup")
	_check(not game.deliver(),"must load vehicle before delivery")
	_check(game.load_vehicle("taxi_0") and game.stage==3,"load first cargo")
	_check(not game.unload_vehicle("van"),"cargo belongs to actual vehicle")
	_check(game.unload_vehicle("taxi_0"),"unload cargo")
	_check(game.deliver() and game.stock.get("pollo",0)==10,"delivery adds units")
	_check(not game.deliver(),"cannot deliver same box twice")
	_check(game.hire() and game.stage==4,"mission completion")
	_check(not game.hire(),"cannot hire twice")
	for i in range(10):
		_check(not game.sell_one().is_empty(),"sale with stock")
	_check(game.cash==10350 and game.revenue==3000 and game.wages==450,"net sale accounting")
	_check(game.sold==10 and game.total(game.stock)==0,"inventory decreases")
	_check(game.sell_one().is_empty(),"no sales without inventory")
	_check(game.messages.size()==3,"one low stock message for product")
	_check(game.buy("picadillo",1) and game.pick_up("picadillo"),"free play restock")
	_check(game.load_vehicle("van") and game.unload_vehicle("van") and game.deliver(),"van restock")
	_check(game.stage==4 and game.stock.get("picadillo",0)==10,"mission remains complete")
	print("Business ledger: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)
