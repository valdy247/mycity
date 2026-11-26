extends SceneTree
const Mission = preload("res://yordi_mission.gd")
const Ledger = preload("res://business_ledger.gd")

func _initialize() -> void:
	var ledger := Ledger.new()
	ledger.persistence_enabled = false
	var start: int = ledger.cash
	var mission: Dictionary = {"stage":13,"reward_paid":false,"delivered":false}
	if Mission.settle_sale(mission,ledger):
		printerr("FAIL: missing PS5 cannot be sold")
		quit(1)
		return
	mission.delivered = true
	if not Mission.settle_sale(mission,ledger) or ledger.cash!=start+1000 or int(mission.stage)!=14:
		printerr("FAIL: exact 1000 CUP reward")
		quit(1)
		return
	if Mission.settle_sale(mission,ledger) or ledger.cash!=start+1000:
		printerr("FAIL: duplicate reward")
		quit(1)
		return
	print("Yordi reward: PASS")
	quit(0)
