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
	var graph := AStar3D.new()
	for i in range(4):
		graph.add_point(i,[Vector3.ZERO,Vector3(20,0,0),Vector3(20,0,20),Vector3(0,0,20)][i])
	for i in range(4): graph.connect_points(i,(i+1)%4,true)
	var cycle := Mission.loop_ids(graph,0,2)
	if cycle.size()!=5 or cycle[0]!=0 or cycle[4]!=0 or cycle[1]==cycle[3]:
		printerr("FAIL: escape must return by an independent path")
		quit(1)
		return
	for id in graph.get_point_ids():
		if graph.is_point_disabled(id):
			printerr("FAIL: graph was not restored")
			quit(1)
			return
	graph.disconnect_points(0,3,true)
	if not Mission.loop_ids(graph,0,2).is_empty():
		printerr("FAIL: dead-end route accepted as a loop")
		quit(1)
		return
	if Mission.return_arrived(false,Vector3.ZERO,Vector3(40,0,0),Vector3.ZERO) or Mission.return_arrived(true,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO) or not Mission.return_arrived(false,Vector3.ZERO,Vector3(10,0,0),Vector3(12,0,0)):
		printerr("FAIL: motorcycle arrival guard")
		quit(1)
		return
	var replay: Dictionary = {"stage":13,"reward_paid":false,"delivered":true,"previous_reward_paid":true}
	if not Mission.settle_sale(replay,ledger) or ledger.cash!=start+1000 or int(replay.stage)!=14:
		printerr("FAIL: replay must not pay twice")
		quit(1)
		return
	print("Yordi route, arrival and reward: PASS")
	quit(0)
