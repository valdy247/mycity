extends RefCounted
# Lightweight persistent life model. Only the nearby walker needs a 3D node.
const DAY := 1440.0
const MAX_RESIDENTS := 180

static func now(state: Dictionary) -> float:
	return float(maxi(0,int(state.get("day",1))-1))*DAY+float(state.get("minutes",480.0))

static func normalize(row: Dictionary,style: int,at: float) -> void:
	var defaults := {"personality":["tranquilo","sociable","reservado","trabajador"][posmod(style,4)],"hunger":25.0,"energy":80.0,"last_simulated":at,"last_paid_day":floori(at/DAY)-1,"last_purchase":-1000.0,"last_work":-1000.0,"relationship":0,"last_greeting":-1000.0,"objective":"descansar","money":200+posmod(style*37,800)}
	for key in defaults:
		if not row.has(key): row[key] = defaults[key]
	row.money = clampi(int(row.money),0,1000000)
	row.hunger = clampf(float(row.hunger),0.0,100.0)
	row.energy = clampf(float(row.energy),0.0,100.0)

static func advance(row: Dictionary,style: int,at: float) -> void:
	normalize(row,style,at)
	var previous := minf(at,float(row.last_simulated))
	var elapsed := maxf(0.0,at-previous)
	if elapsed<=0.0:
		row.objective = objective(row,style,at)
		return
	# Bound catch-up work even on imported or unusually old saves.
	previous = maxf(previous,at-7.0*DAY)
	var first_day := floori(previous/DAY)
	var last_day := floori(at/DAY)
	for day in range(first_day,last_day+1):
		var shift_end := float(day)*DAY+1020.0
		if String(row.get("job",""))!="estudio" and previous<shift_end and at>=shift_end and int(row.last_paid_day)<day:
			row.money = mini(1000000,int(row.money)+120+posmod(style,5)*20)
			row.last_paid_day = day
		# Sleeping restores energy, but hunger continues to advance.
		var rest_a := float(day)*DAY
		var rest_b := rest_a+360.0
		var rest := maxf(0.0,minf(at,rest_b)-maxf(previous,rest_a))
		rest += maxf(0.0,minf(at,rest_a+DAY)-maxf(previous,rest_a+1320.0))
		var active := maxf(0.0,minf(at,rest_a+DAY)-maxf(previous,rest_a)-rest)
		row.energy = clampf(float(row.energy)+rest*.18-active*.055,0.0,100.0)
	row.hunger = minf(100.0,float(row.hunger)+minf(elapsed,7.0*DAY)*.055)
	# Basic at-home meals consume savings independently of visible cafés.
	var meals := mini(7,floori(at/DAY)-floori(previous/DAY))
	for i in range(meals):
		if int(row.money)>=60:
			row.money = int(row.money)-60
			row.hunger = maxf(0.0,float(row.hunger)-55.0)
	row.last_simulated = at
	row.objective = objective(row,style,at)

static func objective(row: Dictionary,style: int,at: float) -> String:
	var hour := fposmod(at,DAY)/60.0
	if hour>=22.0 or hour<6.0: return "descansar"
	if float(row.get("hunger",0.0))>=65.0 and int(row.get("money",0))>=60: return "comer"
	if hour>=7.0 and hour<17.0: return "estudiar" if String(row.get("job",""))=="estudio" else "trabajar"
	if hour>=19.0 or float(row.get("energy",100.0))<25.0: return "volver a casa"
	return "hacer mandados"

static func purchase(row: Dictionary,spent: int,at: float) -> bool:
	if spent<=0 or int(row.money)<spent: return false
	row.money = int(row.money)-spent
	row.hunger = maxf(0.0,float(row.hunger)-35.0)
	row.last_purchase = at
	return true

static func greet(row: Dictionary,at: float) -> void:
	if at-float(row.get("last_greeting",-1000.0))<60.0: return
	row.relationship = clampi(int(row.get("relationship",0))+2,0,100)
	row.last_greeting = at
