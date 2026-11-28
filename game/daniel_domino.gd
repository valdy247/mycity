extends RefCounted
# Cuban double-nine: 4 players, 10 tiles each, remaining 15 aside.
# No drawing; partnerships 0+2 / 1+3. One playable hand per session.
static func start() -> Dictionary:
	var pool: Array = []
	for a in range(10):
		for b in range(a,10): pool.append([a,b])
	pool.shuffle()
	var hands: Array = [[],[],[],[]]
	for i in range(40): hands[i%4].append(pool[i])
	var game := {"hands":hands,"left":-1,"right":-1,"turn":0,"passes":0,"done":false,"winner":-1,"moves":0,"chain":[],"log":"Empiezas tú. Coloca una ficha."}
	return game

static func legal(g: Dictionary,tile: Array,left: bool) -> bool:
	var end := int(g.left if left else g.right)
	return end<0 or int(tile[0])==end or int(tile[1])==end

static func points(hand: Array) -> int:
	var total := 0
	for tile in hand: total += int(tile[0])+int(tile[1])
	return total

static func finish(g: Dictionary,player: int = -1) -> void:
	g.done = true
	var a := points(g.hands[0])+points(g.hands[2])
	var b := points(g.hands[1])+points(g.hands[3])
	g.winner = player%2 if player>=0 else (0 if a<b else (1 if b<a else -1))
	g.log = "Empate · %d a %d tantos" % [a,b] if int(g.winner)<0 else ("Ganó tu pareja" if int(g.winner)==0 else "Ganó la otra pareja")+" · %d / %d tantos restantes" % [a,b]

static func play(g: Dictionary,index: int,left: bool) -> bool:
	if bool(g.done): return false
	var player := int(g.turn)
	var hand: Array = g.hands[player]
	if index<0 or index>=hand.size(): return false
	var tile: Array = hand[index]
	if not legal(g,tile,left): return false
	if not g.has("chain"): g.chain = []
	if int(g.left)<0:
		g.left = int(tile[0])
		g.right = int(tile[1])
		g.chain.append([int(tile[0]),int(tile[1])])
	else:
		var end := int(g.left if left else g.right)
		var other := int(tile[1]) if int(tile[0])==end else int(tile[0])
		if left:
			g.left = other
			g.chain.push_front([other,end])
		else:
			g.right = other
			g.chain.append([end,other])
	hand.remove_at(index)
	g.moves = int(g.moves)+1
	g.passes = 0
	g.log = "%s puso %d-%d" % ["Tú" if player==0 else "Jugador "+str(player+1),int(tile[0]),int(tile[1])]
	if hand.is_empty(): finish(g,player)
	else: g.turn = (player+1)%4
	return true

static func pass_turn(g: Dictionary) -> bool:
	if bool(g.done): return false
	for tile in g.hands[int(g.turn)]:
		if legal(g,tile,true) or legal(g,tile,false): return false
	g.passes = int(g.passes)+1
	if int(g.passes)>=4: finish(g)
	else: g.turn = (int(g.turn)+1)%4
	return true

static func opponents(g: Dictionary) -> void:
	for turn in range(3):
		if bool(g.done) or int(g.turn)==0: return
		var hand: Array = g.hands[int(g.turn)]
		var best := -1
		var value := -1
		var left := true
		for i in range(hand.size()):
			var tile: Array = hand[i]
			if not legal(g,tile,true) and not legal(g,tile,false): continue
			var p := int(tile[0])+int(tile[1])
			if p>value:
				best = i
				value = p
				left = legal(g,tile,true)
		if best>=0: play(g,best,left)
		else: pass_turn(g)
