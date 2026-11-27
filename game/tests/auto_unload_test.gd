extends SceneTree
const Ledger = preload("res://business_ledger.gd")
func _initialize() -> void:
	var ledger := Ledger.new()
	ledger.persistence_enabled = false
	ledger.stage = 4
	ledger.cargo = {"taxi_0":{"pollo":2},"van":{"pollo":1}}
	ledger.carry = "huevos"
	if not ledger.deliver_vehicle_box("taxi_0","pollo") or ledger.stock.get("pollo",0)!=10 or ledger.cargo.taxi_0.pollo!=1 or ledger.carry!="huevos":
		quit(1)
		return
	if not ledger.deliver_vehicle_box("taxi_0","pollo") or ledger.deliver_vehicle_box("taxi_0","pollo") or ledger.cargo.has("taxi_0") or ledger.cargo.van.pollo!=1 or ledger.stock.pollo!=20 or ledger.cash!=10000:
		quit(1)
		return
	print("Automatic unloading transfers exactly one paid crate without altering player hands or cash: PASS")
	quit(0)
