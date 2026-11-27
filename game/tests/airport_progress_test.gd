extends SceneTree
const Progress = preload("res://airport_progress.gd")

func _initialize() -> void:
	var state := Progress.new()
	var at := Vector3(0,.91,-24)
	if state.advance("board",at) or state.stage!=0:
		printerr("FAIL: boarding before migration")
		quit(1)
		return
	var expected := [
		["belt","belt"],["belt","belt"],["belt","belt"],["belt","belt"],["belt","belt"],["belt","belt"],
		["hand","belt"],["cart","belt"],["cart","hand"],["cart","cart"],["cart","cart"],["cart","cart"],
		["hand","cart"],["trunk","cart"],["trunk","hand"],["trunk","trunk"],["trunk","trunk"],["trunk","trunk"]
	]
	for step in range(Progress.COMPLETE+1):
		for id in range(2):
			if Progress.bag_location(step,id)!=expected[step][id]:
				printerr("FAIL: bag ownership ",step," ",id)
				quit(1)
				return
		if step==Progress.COMPLETE: break
		var action := Progress.expected_action(step)
		if step==5:
			if not state.cart_attached or state.advance(action,at) or not state.set_cart_attached(false):
				printerr("FAIL: must park before collecting luggage")
				quit(1)
				return
		if step in [6,7,8] and (state.cart_attached or state.set_cart_attached(true)):
			printerr("FAIL: cart must remain parked during luggage transfer")
			quit(1)
			return
		if step==9:
			if state.advance(action,at) or not state.set_cart_attached(true):
				printerr("FAIL: must take loaded cart before leaving")
				quit(1)
				return
		if not state.advance(action,at) or state.stage!=step+1:
			printerr("FAIL: arrival sequence ",step)
			quit(1)
			return
		if state.advance(action,at):
			printerr("FAIL: duplicate action ",step)
			quit(1)
			return
	if state.stage!=Progress.COMPLETE or not Progress.expected_action(state.stage).is_empty():
		quit(1)
		return
	if state.cart_attached:
		printerr("FAIL: cart must remain outside taxi")
		quit(1)
		return
	print("Airport migration, parked cart, bag ownership and taxi sequence: PASS")
	quit(0)
