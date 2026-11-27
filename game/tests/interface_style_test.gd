extends SceneTree
const UI = preload("res://interface_style.gd")
func _initialize() -> void:
	for view in [Vector2(960,540),Vector2(1280,720),Vector2(1920,1080)]:
		var phone := UI.phone_size(view)
		if phone.x>view.x-24.0 or phone.y>view.y-24.0 or phone.y>636.0:
			printerr("FAIL: phone outside viewport")
			quit(1)
			return
	if UI.distance_text(999.0)!="999 m" or UI.distance_text(1500.0)!="1.5 km":
		printerr("FAIL: GPS distance format")
		quit(1)
		return
	if UI.notice_title("MISIÓN CUMPLIDA · +1000 CUP")!="MISIÓN COMPLETADA":
		printerr("FAIL: mission notification")
		quit(1)
		return
	print("Responsive phone, GPS formatting and notice categories: PASS")
	quit(0)
