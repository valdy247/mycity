extends RefCounted
# Pure UI helpers; no render targets, shaders or new routing work.
static func phone_size(view: Vector2) -> Vector2:
	return Vector2(minf(420.0,maxf(260.0,view.x-24.0)),minf(636.0,maxf(220.0,view.y-24.0)))

static func distance_text(meters: float) -> String:
	var distance := maxf(0.0,meters)
	if distance>=1000.0: return "%.1f km" % (distance/1000.0)
	return "%d m" % roundi(distance)

static func notice_title(value: String) -> String:
	if value.contains("MISIÓN CUMPLIDA"): return "MISIÓN COMPLETADA"
	if value.contains("MISIÓN INICIADA"): return "NUEVA MISIÓN"
	if value.contains("punto de control") or value.contains("punto de Control"): return "PUNTO DE CONTROL"
	return "MYCITY · AVISO"
