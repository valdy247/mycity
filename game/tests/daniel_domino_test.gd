extends SceneTree
const Domino = preload("res://daniel_domino.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _check(ok: bool,label: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func _run() -> void:
	for round_number in range(12):
		var g := Domino.start()
		var unique := {}
		for hand in g.hands:
			_check(hand.size()==10,"four players get ten tiles")
			for tile in hand: unique[str(tile)] = true
		_check(unique.size()==40,"no duplicate tiles")
		_check(not Domino.pass_turn(g),"cannot pass with a legal tile")
		var count := 0
		while not bool(g.done) and count<100:
			_check(int(g.turn)==0,"NPC turns return control to player")
			var hand: Array = g.hands[0]
			var moved := false
			for i in range(hand.size()):
				if Domino.legal(g,hand[i],true):
					moved = Domino.play(g,i,true)
					break
				if Domino.legal(g,hand[i],false):
					moved = Domino.play(g,i,false)
					break
			if not moved: _check(Domino.pass_turn(g),"only pass when no move is legal")
			Domino.opponents(g)
			count += 1
		_check(bool(g.done),"hand eventually terminates")
		var chain: Array = g.chain
		_check(chain.size()==int(g.moves),"each placed tile appears on table")
		for i in range(chain.size()-1):
			_check(int(chain[i][1])==int(chain[i+1][0]),"adjacent domino ends always match")
		if not chain.is_empty():
			_check(int(chain[0][0])==int(g.left) and int(chain[-1][1])==int(g.right),"displayed ends match table")
	print("MyCity Daniel domino: ","PASS" if failures==0 else "FAIL"," | failures: ",failures)
	quit(0 if failures==0 else 1)
