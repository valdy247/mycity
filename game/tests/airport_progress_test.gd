extends SceneTree
const Progress = preload("res://airport_progress.gd")

func _initialize() -> void:
	var at := Vector3(0,.91,-17)
	for move_cart in [false,true]:
		for first in [0,1]:
			var state := Progress.new()
			for step in range(4):
				if not state.advance(Progress.expected_action(step),at):
					printerr("FAIL: migration")
					quit(1)
					return
			if state.advance("exit",at) or state.advance("direct_pickup",at,first):
				printerr("FAIL: bypassing mandatory cart")
				quit(1)
				return
			if move_cart:
				if not state.advance("cart",at) or state.advance("pickup_first",at,first) or not state.set_cart_attached(false):
					printerr("FAIL: parking")
					quit(1)
					return
			if not state.advance("pickup_first",at,first) or state.stage!=6 or state.cart_attached:
				printerr("FAIL: pickup with stationary cart")
				quit(1)
				return
			if Progress.bag_location(6,first,first)!="hand" or Progress.bag_location(6,1-first,first)!="belt":
				quit(1)
				return
			if state.advance("exit",at) or not state.advance("cart_first",at) or Progress.bag_location(7,first,first)!="cart":
				quit(1)
				return
			if state.advance("pickup_second",at,first) or not state.advance("pickup_second",at,1-first):
				quit(1)
				return
			if state.advance("exit",at) or not state.advance("cart_second",at) or state.stage!=9:
				quit(1)
				return
			if Progress.bag_location(9,0,first)!="cart" or Progress.bag_location(9,1,first)!="cart":
				quit(1)
				return
			if state.advance("exit",at) or not state.set_cart_attached(true):
				quit(1)
				return
			for step in range(9,Progress.COMPLETE):
				var action := Progress.expected_action(step)
				if step==10:
					if not state.cart_attached or state.advance(action,at) or not state.set_cart_attached(false):
						printerr("FAIL: park trolley before opening taxi trunk")
						quit(1)
						return
					if Progress.bag_location(step,0,first)!="cart" or Progress.bag_location(step,1,first)!="cart":
						printerr("FAIL: parked trolley must retain both bags")
						quit(1)
						return
				if not state.advance(action,at) or state.advance(action,at):
					printerr("FAIL: exit/taxi step ",step)
					quit(1)
					return
			if state.stage!=Progress.COMPLETE or state.cart_attached:
				quit(1)
				return
			for id in range(2):
				if Progress.bag_location(state.stage,id,first)!="trunk":
					quit(1)
					return
	print("PASS: both bag orders, stationary or moved cart, mandatory loading before exit")
	quit(0)
