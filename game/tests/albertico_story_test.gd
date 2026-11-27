extends SceneTree
const Story = preload("res://albertico_story.gd")
const Ledger = preload("res://business_ledger.gd")
func _initialize() -> void:
	var counts := {"huevos":1,"perrito":1,"pollo":1}
	if Story.all_four(counts): quit(1); return
	counts["picadillo"] = 1
	if not Story.all_four(counts): quit(1); return
	counts["pollo"] = 2
	if Story.all_four(counts): quit(1); return
	var ledger := Ledger.new()
	ledger.persistence_enabled = false
	ledger.stage = 3
	ledger.stock = {"pollo":10}
	ledger.life_data.albertico_story = {"phase":"cold"}
	if ledger.hire(): quit(1); return
	print("Four-product mission requirements and early completion guard: PASS")
	quit(0)
