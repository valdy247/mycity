extends SceneTree
const Ledger = preload("res://business_ledger.gd")
func _initialize() -> void:
	var ledger := Ledger.new()
	ledger.persistence_enabled = false
	if ledger.albertico_visible() or ledger.meet_albertico():
		printerr("FAIL: Albertico visible before invitation")
		quit(1)
		return
	if not ledger.invite_albertico() or ledger.invite_albertico() or ledger.albertico_visible():
		printerr("FAIL: invitation state")
		quit(1)
		return
	if not ledger.meet_albertico() or not ledger.albertico_visible() or ledger.stage!=0 or ledger.meet_albertico():
		printerr("FAIL: meeting state")
		quit(1)
		return
	ledger.accept()
	if ledger.stage!=1 or not ledger.albertico_visible() or ledger.cash!=10000:
		printerr("FAIL: original mission progression")
		quit(1)
		return
	var existing := Ledger.new()
	existing.stage = 3
	if not existing.albertico_visible():
		printerr("FAIL: compatibility with older saves")
		quit(1)
		return
	print("Albertico introduction and saved progression: PASS")
	quit(0)
