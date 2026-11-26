extends Control
const MapData = preload("res://pilar_map.gd")
signal point_selected(point: Vector3)
var geography: MapData
var center := Vector2.ZERO
var zoom := .75
var origin := Vector2.ZERO
var marker := Vector2.ZERO
var has_marker := false
var route := PackedVector2Array()
var local_roads := PackedVector2Array()
var main_roads := PackedVector2Array()
var pedestrian_roads := PackedVector2Array()
var labels: Array = []
var pressed := false
var dragged := false
var press_at := Vector2.ZERO
var press_center := Vector2.ZERO

func setup(data: MapData) -> void:
	geography = data
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	custom_minimum_size = Vector2(300,220)
	var named: Dictionary = {}
	for edge in data.roads:
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var pair := PackedVector2Array([Vector2(a.x,a.z),Vector2(b.x,b.z)])
		if not bool(edge.driveable):
			pedestrian_roads.append_array(pair)
		elif float(edge.width)>=8.0:
			main_roads.append_array(pair)
		else:
			local_roads.append_array(pair)
		var name_value := data.street_label(String(edge.name))
		if name_value.is_empty() or name_value=="CALLE SIN NOMBRE": continue
		if a.distance_to(b)<8.0: continue
		var p := Vector2((a.x+b.x)*.5,(a.z+b.z)*.5)
		var key := name_value+":"+str(floori(p.x/125.0))+":"+str(floori(p.y/125.0))
		var length := a.distance_to(b)
		if not named.has(key) or length>float(named[key].length):
			named[key] = {"p":p,"name":name_value,"length":length,"major":float(edge.width)>=8.0}
	labels = named.values()
	resized.connect(queue_redraw)

func reset(at: Vector3) -> void:
	origin = Vector2(at.x,at.z)
	center = origin
	zoom = .75
	has_marker = false
	route.clear()
	pressed = false
	dragged = false
	queue_redraw()

func show_route(points: Array, destination: Vector3) -> void:
	marker = Vector2(destination.x,destination.z)
	has_marker = true
	route.clear()
	route.append(origin)
	for p in points:
		var v: Vector3 = p
		route.append(Vector2(v.x,v.z))
	route.append(marker)
	queue_redraw()

func clear_route() -> void:
	has_marker = false
	route.clear()
	queue_redraw()

func _screen(p: Vector2) -> Vector2:
	return (p-center)*zoom+size*.5

func _world(p: Vector2) -> Vector2:
	return (p-size*.5)/zoom+center

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
			var before := _world(mouse.position)
			zoom = clampf(zoom*(1.25 if mouse.button_index==MOUSE_BUTTON_WHEEL_UP else .8),.13,5.0)
			center = before-(mouse.position-size*.5)/zoom
			_limit_center()
			queue_redraw()
			accept_event()
			return
		if mouse.button_index==MOUSE_BUTTON_LEFT:
			if mouse.pressed:
				pressed = true
				dragged = false
				press_at = mouse.position
				press_center = center
			elif pressed:
				pressed = false
				if not dragged:
					var p := _world(mouse.position)
					point_selected.emit(Vector3(p.x,0,p.y))
			accept_event()
	elif event is InputEventMouseMotion and pressed:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var displacement: Vector2 = motion.position-press_at
		if displacement.length()>5.0: dragged = true
		if dragged:
			center = press_center-displacement/zoom
			_limit_center()
			queue_redraw()
		accept_event()

func _limit_center() -> void:
	center.x = clampf(center.x,-MapData.LIMIT,MapData.LIMIT)
	center.y = clampf(center.y,-MapData.LIMIT,MapData.LIMIT)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Color("#242d35"))
	if geography==null: return
	# All roads are cached as flat line arrays. The map is redrawn only
	# on interaction, resize or a new destination, with no second 3D view.
	draw_set_transform(size*.5-center*zoom,0.0,Vector2.ONE*zoom)
	if not pedestrian_roads.is_empty():
		draw_multiline(pedestrian_roads,Color("#47535b"),maxf(.8,1.0/zoom))
	if not local_roads.is_empty():
		draw_multiline(local_roads,Color("#abb4b7"),maxf(2.3,1.5/zoom),true)
	if not main_roads.is_empty():
		draw_multiline(main_roads,Color("#d4c5a2"),maxf(4.5,2.5/zoom),true)
	if route.size()>=2:
		draw_polyline(route,Color("#132338"),7.0/zoom,true)
		draw_polyline(route,Color("#58aaff"),4.0/zoom,true)
	draw_set_transform(Vector2.ZERO)
	var font := get_theme_default_font()
	var used: Array[Rect2] = []
	if zoom>=.37:
		for label_value in labels:
			if zoom<.65 and not bool(label_value.major): continue
			var p := _screen(label_value.p)
			if not Rect2(Vector2.ZERO,size).has_point(p): continue
			var name_value := String(label_value.name)
			var extent := font.get_string_size(name_value,HORIZONTAL_ALIGNMENT_LEFT,-1,11)
			var rect := Rect2(p-Vector2(extent.x*.5,9),extent+Vector2(8,6))
			var occupied := false
			for other in used:
				if rect.intersects(other):
					occupied = true
					break
			if occupied: continue
			used.append(rect)
			draw_rect(rect,Color(.13,.17,.20,.87))
			draw_string(font,rect.position+Vector2(4,12),name_value,HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("#e5e9ed"))
			if used.size()>=38: break
	var taxi := _screen(origin)
	draw_circle(taxi,9.0,Color("#151b21"))
	draw_circle(taxi,6.5,Color("#ffd259"))
	if has_marker:
		var dest := _screen(marker)
		draw_circle(dest,11.0,Color("#172633"))
		draw_circle(dest,8.0,Color("#ff6960"))
		draw_circle(dest,3.0,Color.WHITE)
	draw_string(font,Vector2(12,20),"N ↑",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color.WHITE)
	var scale_distance := 100.0 if zoom>=.5 else 500.0
	var scale_width := scale_distance*zoom
	if scale_width>size.x*.35:
		scale_distance = 25.0
		scale_width = scale_distance*zoom
	var bottom := Vector2(14,size.y-15)
	draw_line(bottom,bottom+Vector2(scale_width,0),Color.WHITE,2.0)
	draw_string(font,bottom+Vector2(0,-5),"%d m" % int(scale_distance),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color.WHITE)
	draw_string(font,Vector2(maxf(10,size.x-174),size.y-9),"© OpenStreetMap contributors",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("#c3cbd0"))
