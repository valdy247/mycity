extends SceneTree
const Visual = preload("res://yordi_visual.gd")

func _initialize() -> void:
	if Visual.escape_progress(100.0,75.0)!=.25 or Visual.escape_progress(100.0,0.0)!=1.0 or Visual.escape_progress(0.0,0.0)!=0.0:
		printerr("FAIL: visual escape progress")
		quit(1)
		return
	if Visual.rider_lean(0.0,1.0)!=0.0 or absf(Visual.rider_lean(45.0,100.0))>.121:
		printerr("FAIL: rider tilt exceeds visual limits")
		quit(1)
		return
	for key in ["step","success","warning"]:
		var audio := Visual.cue(key)
		if audio==null or audio.data.is_empty() or audio.data.size()>16000 or audio!=Visual.cue(key):
			printerr("FAIL: cached audio ",key)
			quit(1)
			return
	print("Yordi visual progress, rider pose and cached audio: PASS")
	quit(0)
