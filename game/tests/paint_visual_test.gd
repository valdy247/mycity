extends SceneTree
const Paint = preload("res://paint_visual.gd")

func _initialize() -> void:
	var saved := {"0:1:1":"blue","0:2:1":"yellow"}
	var original := saved.duplicate(true)
	var img := Paint.new_surface(0,8,4,saved,false)
	if img.get_size()!=Vector2i(192,96) or saved!=original:
		printerr("FAIL: dimensions or saved state changed")
		quit(1)
		return
	var before := img.get_pixel(4,4)
	saved["0:2:1"] = "blue"
	Paint.redraw(img,0,8,4,saved,false,Vector2i(2,1))
	var rebuilt := Paint.new_surface(0,8,4,saved,false)
	if img.get_data()!=rebuilt.get_data() or img.get_pixel(4,4)!=before:
		printerr("FAIL: incremental update differs from reload")
		quit(1)
		return
	var door := Paint.new_surface(4,2,3,{"4:0:0":"yellow"},true)
	if door.get_size()!=Vector2i(48,72):
		printerr("FAIL: door dimensions")
		quit(1)
		return
	print("Paint textures, reload compatibility and incremental redraw: PASS")
	quit(0)
