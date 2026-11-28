extends RefCounted
# Reusable rules for private parties, clubs and community gatherings.
static func now(life: Dictionary) -> float:
	return float(life.get("day",1))*1440.0+float(life.get("minutes",480.0))

static func phase(minutes: float) -> int:
	var hour := fposmod(minutes,1440.0)
	if hour>=1140.0 and hour<1260.0: return 0 # arrivals
	if hour>=1260.0 and hour<1380.0: return 1 # social
	if hour>=1380.0 or hour<60.0: return 2 # peak
	if hour<180.0: return 3 # departures
	return 4 # quiet visit

static func phase_name(minutes: float) -> String:
	return ["Llegando los invitados","La fiesta se anima","En pleno ambiente","Últimas canciones","Visita tranquila"][phase(minutes)]

static func guest_count(minutes: float) -> int:
	return [4,6,7,3,1][phase(minutes)]

static func genre(track: int) -> String:
	if track<4: return "regueton"
	if track<8: return "salsa"
	return "bachata"

static func ensure_wellbeing(life: Dictionary) -> void:
	if not life.has("happiness"): life.happiness = 75.0
	if not life.has("social"): life.social = 65.0
	if not life.has("leisure_rewards"): life.leisure_rewards = {}

static func advance_wellbeing(life: Dictionary,minutes: float,working: bool) -> void:
	ensure_wellbeing(life)
	var dt := maxf(0.0,minutes)
	life.happiness = clampf(float(life.happiness)-dt*(.035 if working else .009),0.0,100.0)
	life.social = clampf(float(life.social)-dt*.015,0.0,100.0)

static func reward(life: Dictionary,key: String,happiness: float,social: float,cooldown: float = 90.0) -> bool:
	ensure_wellbeing(life)
	var at := now(life)
	var history: Dictionary = life.leisure_rewards
	if at<float(history.get(key,-10000.0))+cooldown: return false
	history[key] = at
	life.happiness = clampf(float(life.happiness)+happiness,0.0,100.0)
	life.social = clampf(float(life.social)+social,0.0,100.0)
	return true
