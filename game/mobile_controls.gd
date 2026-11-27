extends Control
# Multi-touch gameplay overlay. Only active outside existing game menus.
# Input state is independent of browser pointer lock and virtual keyboard.
var game
var movement := Vector2.ZERO
var use_held := false
var joystick_id := -1
var camera_id := -1
var fingers: Dictionary = {}
var buttons: Dictionary = {}
var center := Vector2.ZERO
var radius := 56.0
var active := false
var last_vehicle := false

func setup(controller) -> void:
	game = controller
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(_layout)
	_layout()
	sync()

func _layout() -> void:
	var view: Vector2 = get_viewport_rect().size
	radius = clampf(view.y*.112,42.0,62.0)
	center = Vector2(radius+25.0,view.y-radius-81.0)
	buttons.clear()
	var right := view.x-40.0
	var bottom := view.y-42.0
	var step := 68.0
	# Right hand: action and jump/brake, with auxiliary controls above.
	for spec in [["e",0,1],["space",1,0],["shift",0,0],["g",1,1],["use",2,0],["p",0,2],["m",1,2],["v",2,2],["i",2,1]]:
		buttons[String(spec[0])] = Vector2(right-float(spec[1])*step,bottom-float(spec[2])*step)
	queue_redraw()

func _vehicle() -> bool:
	return game.driving or game.taxi_riding or game.bus_riding or (game.garage!=null and game.garage.riding)

func sync() -> void:
	if game==null: return
	var next: bool = not game.touch_blocked()
	if next!=active:
		active = next
		visible = next
		_clear()
		queue_redraw()
	var vehicle := _vehicle()
	if vehicle!=last_vehicle:
		last_vehicle = vehicle
		queue_redraw()
	if Input.mouse_mode!=Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _clear() -> void:
	fingers.clear()
	joystick_id = -1
	camera_id = -1
	movement = Vector2.ZERO
	use_held = false

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT:
		_clear()
		queue_redraw()

func held(key: Key) -> bool:
	if not active: return false
	var name_value := "shift" if key==KEY_SHIFT else ("space" if key==KEY_SPACE else "")
	return not name_value.is_empty() and name_value in fingers.values()

func _label(id: String) -> String:
	match id:
		"e": return "Bajar" if last_vehicle else "Acción"
		"space": return "Freno" if last_vehicle else "Salto"
		"shift": return "Turbo" if last_vehicle else "Correr"
		"g": return "Cajas"
		"use": return "Usar"
		"p": return "Tel."
		"m": return "Mapa"
		"v": return "Vista"
		"i": return "Bolsa"
	return id

func _draw() -> void:
	if not active: return
	draw_circle(center,radius,Color("#15273570"))
	draw_arc(center,radius,0.0,TAU,40,Color("#e7eef2aa"),2.0,true)
	draw_line(center-Vector2(radius*.78,0),center+Vector2(radius*.78,0),Color("#e7eef23a"),1.0,true)
	draw_line(center-Vector2(0,radius*.78),center+Vector2(0,radius*.78),Color("#e7eef23a"),1.0,true)
	draw_circle(center+movement*radius*.64,radius*.34,Color("#e4edf0b0"))
	var font := ThemeDB.fallback_font
	for id in buttons:
		var at: Vector2 = buttons[id]
		var pressed: bool = id in fingers.values()
		draw_circle(at,29.0,Color("#7aa8bcdd") if pressed else Color("#172b39b8"))
		draw_arc(at,29.0,0.0,TAU,28,Color("#e7eef2b0"),1.5,true)
		var label := _label(String(id))
		var span := font.get_string_size(label,HORIZONTAL_ALIGNMENT_LEFT,-1,13)
		draw_string(font,at+Vector2(-span.x*.5,4.5),label,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)

func _move(point: Vector2) -> void:
	var axis := (point-center)/radius
	movement = axis.limit_length(1.0) if axis.length()>.13 else Vector2.ZERO
	queue_redraw()

func _trigger(id: String) -> void:
	match id:
		"e": game.touch_action(KEY_E)
		"g": game.touch_action(KEY_G)
		"p": game.touch_action(KEY_P)
		"m": game.touch_action(KEY_M)
		"v": game.touch_action(KEY_V)
		"i": game.touch_action(KEY_I)
		"use":
			use_held = true
			game.touch_use()

func handle_touch(event: InputEvent) -> bool:
	sync()
	if not active: return false
	if event is InputEventScreenTouch:
		var id: int = event.index
		var point: Vector2 = event.position
		if not event.pressed:
			if id==joystick_id:
				joystick_id = -1
				movement = Vector2.ZERO
			if id==camera_id: camera_id = -1
			fingers.erase(id)
			use_held = "use" in fingers.values()
			queue_redraw()
			return true
		for name_value in buttons:
			var at: Vector2 = buttons[name_value]
			if point.distance_to(at)>32.0: continue
			fingers[id] = name_value
			_trigger(String(name_value))
			queue_redraw()
			return true
		if joystick_id<0 and point.distance_to(center)<radius*1.25:
			joystick_id = id
			_move(point)
		elif camera_id<0:
			camera_id = id
		return true
	if event is InputEventScreenDrag:
		if event.index==joystick_id: _move(event.position)
		elif event.index==camera_id: game.touch_look(event.relative)
		return true
	return false
