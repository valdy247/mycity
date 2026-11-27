extends SceneTree
const Stadium = preload("res://latino_stadium.gd")
func _initialize() -> void:
	var ring := Stadium.make_ring(Vector3.ZERO,Basis.IDENTITY,84.0,94.0)
	if ring.size()!=14 or Geometry2D.triangulate_polygon(ring).is_empty():
		printerr("FAIL: stadium geometry")
		quit(1)
		return
	if Stadium.GATE_EDGES.size()<4 or Stadium.ROWS<16:
		quit(1)
		return
	print("Latinoamericano outline and architectural sectors: PASS")
	quit(0)
