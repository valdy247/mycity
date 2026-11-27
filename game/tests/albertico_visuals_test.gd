extends SceneTree
const Business = preload("res://business_mission.gd")
const Ledger = preload("res://business_ledger.gd")

func _initialize() -> void:
	var colors: Dictionary = {}
	for key in Ledger.PRODUCTS:
		var color := Business.crate_band(String(key)).to_html()
		if colors.has(color):
			printerr("FAIL: ambiguous product color")
			quit(1)
			return
		colors[color] = true
	for pair in [[0,0],[4,0],[5,1],[19,1],[20,2],[100,2]]:
		if Business.stall_tier(pair[0])!=pair[1]:
			printerr("FAIL: cosmetic growth tier")
			quit(1)
			return
	var ledger := Ledger.new()
	ledger.persistence_enabled = false
	ledger.stage = 2
	if not ledger.buy("pollo",1) or not ledger.pick_up("pollo") or not ledger.load_vehicle("van") or not ledger.unload_vehicle("van") or not ledger.deliver() or not ledger.hire():
		printerr("FAIL: original business progression")
		quit(1)
		return
	if ledger.stage!=4 or int(ledger.stock.get("pollo",0))!=10:
		printerr("FAIL: visual upgrades must preserve inventory")
		quit(1)
		return
	print("Albertico cosmetic tiers, crate identity and business progression: PASS")
	quit(0)
