extends RefCounted
# OSM height is in metres unless another unit is explicit.
# Levels are a count, not a measured height.
static func metres(value: String) -> float:
	var raw := value.strip_edges().to_lower().replace(",",".")
	var scale := 1.0
	if raw.ends_with("feet"):
		raw = raw.trim_suffix("feet").strip_edges()
		scale = .3048
	elif raw.ends_with("ft"):
		raw = raw.trim_suffix("ft").strip_edges()
		scale = .3048
	elif raw.ends_with("m"):
		raw = raw.trim_suffix("m").strip_edges()
	if not raw.is_valid_float(): return 0.0
	var result := float(raw)*scale
	return result if is_finite(result) and result>=1.0 and result<=300.0 else 0.0

static func resolve(tags: Dictionary) -> Dictionary:
	var exact := metres(String(tags.get("height","")))
	if exact>0.0: return {"metres":exact,"source":"height"}
	var levels := String(tags.get("building:levels","")).strip_edges()
	if levels.is_valid_float():
		var count := float(levels)
		if is_finite(count) and count>=1.0 and count<=90.0:
			var roof := metres(String(tags.get("roof:height","")))
			var roof_levels := String(tags.get("roof:levels",""))
			if roof<=0.0 and roof_levels.is_valid_float():
				roof = clampf(float(roof_levels),0.0,4.0)*2.0
			return {"metres":count*3.25+roof,"source":"levels"}
	return {}

static func category(kind: String) -> String:
	if kind in ["yes","residential","house","apartments","detached","terrace","semidetached_house"]: return "residential"
	if kind in ["shed","garage","garages","carport","hut","roof"]: return "small"
	if kind in ["warehouse","industrial","retail","commercial","supermarket"]: return "commercial"
	return kind

static func compatible(a: String,b: String) -> bool:
	return category(a)==category(b)

static func estimate(kind: String,samples: Array[float]) -> float:
	if not samples.is_empty():
		samples.sort()
		var middle := floori(float(samples.size())*.5)
		return samples[middle] if samples.size()%2==1 else (samples[middle-1]+samples[middle])*.5
	match category(kind):
		"small": return 2.8
		"commercial": return 4.5
		_: return 3.25
