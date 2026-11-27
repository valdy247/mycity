extends CanvasLayer
# A single reusable 2D map. No extra camera, viewport or background route search.
const MapView = preload("res://taxi_map.gd")
const Interface = preload("res://interface_style.gd")
var game
var root: PanelContainer
var map: MapView
var places: OptionButton
var mode: OptionButton
var info: Label
var query: LineEdit
var destinations: Array = []
var active := false
var map_ready := false
var origin := Vector3.ZERO
var selected := Vector3.ZERO
var selected_label := ""
var has_destination := false
var previous_mouse := Input.MOUSE_MODE_CAPTURED

func setup(controller) -> void:
	game = controller
	layer = 90
	root = PanelContainer.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#141d26")
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	root.add_theme_stylebox_override("panel",style)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation",10)
	root.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var title := Label.new()
	title.text = "MYCITY  /  NAVEGACIÓN"
	title.add_theme_font_size_override("font_size",24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_button(header,"Centrar en mí",_center_player)
	_button(header,"Cerrar [M / Esc]",close)
	var toolbar := HBoxContainer.new()
	layout.add_child(toolbar)
	places = OptionButton.new()
	places.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(places)
	places.item_selected.connect(_choose_place)
	mode = OptionButton.new()
	mode.add_item("A pie")
	mode.add_item("Vehículo")
	toolbar.add_child(mode)
	mode.item_selected.connect(_change_mode)
	_button(toolbar,"Quitar destino",_clear)
	var search := HBoxContainer.new()
	layout.add_child(search)
	query = LineEdit.new()
	query.placeholder_text = "Calle, esquina o coordenadas GPS"
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_child(query)
	query.text_submitted.connect(func(_value: String): _search())
	_button(search,"Buscar",_search)
	map = MapView.new()
	layout.add_child(map)
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map.point_selected.connect(_choose_point)
	var route_card := PanelContainer.new()
	var route_style := StyleBoxFlat.new()
	route_style.bg_color = Color("#1c3042")
	route_style.set_corner_radius_all(8)
	route_style.content_margin_left = 12.0
	route_style.content_margin_right = 12.0
	route_style.content_margin_top = 9.0
	route_style.content_margin_bottom = 9.0
	route_card.add_theme_stylebox_override("panel",route_style)
	layout.add_child(route_card)
	info = Label.new()
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	route_card.add_child(info)
	var hint := Label.new()
	hint.text = "Amarillo: tú  ·  Verde: lugares  ·  Rojo: destino  ·  Azul: ruta\nClic: destino  ·  Arrastrar: mover  ·  Rueda: zoom"
	hint.add_theme_color_override("font_color",Color("#aab9c9"))
	layout.add_child(hint)
	root.hide()

func _button(parent: Control,label_value: String,callback: Callable) -> void:
	var button := Button.new()
	button.text = label_value
	button.pressed.connect(callback)
	parent.add_child(button)

func _player_point() -> Vector3:
	if game.garage.inside and not game.cuba_world.garage_home_site.is_empty():
		return game.cuba_world.garage_home_site.door
	if game.carlos_mission!=null and game.carlos_mission.inside:
		return game.carlos_mission.customer.p
	if game.driving: return game.van.global_position
	return game.player.global_position

func _add_place(label_value: String,point: Vector3) -> void:
	if not point.is_finite(): return
	destinations.append({"label":label_value,"p":point})
	places.add_item(label_value)

func _refresh_places() -> void:
	places.clear()
	destinations.clear()
	places.add_item("Destinos útiles y misiones")
	var world = game.cuba_world
	var mission = game.carlos_mission
	var first_stage: int = game.business.ledger.stage
	if first_stage in [0,3] and is_instance_valid(game.business.albertico):
		_add_place("MISIÓN · Albertico",game.business.albertico.global_position)
	elif first_stage in [1,2] and not world.food_factory.is_empty():
		_add_place("MISIÓN · Recoger mercancía",world.food_factory.counter)
	if mission!=null:
		var stage: int = mission._stage()
		if stage==2:
			var p: Vector3 = mission.home.get("p",world.geography.project(mission.CARLOS_LAT,mission.CARLOS_LON))
			_add_place("MISIÓN · Casa de Carlos",p)
		elif stage in [3,4] and not mission.customer.is_empty():
			_add_place("MISIÓN · Casa del cliente",mission.customer.p)
		elif stage==5 and String(game.garage.state.part)=="bicicleta:wheel_a" and not world.garage_home_site.is_empty():
			_add_place("MISIÓN · Llevar goma al garaje",world.garage_home_site.door)
	if game.garage.waypoint_active: _add_place("Destino actual · "+game.garage.waypoint_label,game.garage.waypoint_point)
	if not world.garage_home_site.is_empty(): _add_place("Mi casa / garaje",world.garage_home_site.door)
	if is_instance_valid(game.business.albertico): _add_place("Albertico",game.business.albertico.global_position)
	if not world.food_factory.is_empty(): _add_place("MIPYME · Fábrica",world.food_factory.counter)
	for site in world.commerce_sites:
		_add_place(String(site.name),site.entrance)
	for site in world.parts_sites:
		_add_place(String(site.name),site.road)
	map.business_markers.clear()
	for place in destinations:
		var p: Vector3 = place.p
		map.business_markers.append({"p":Vector2(p.x,p.z),"label":place.label})
	places.select(0)

func open() -> void:
	if active: return
	active = true
	if not map_ready:
		map.setup(game.cuba_world.geography)
		map_ready = true
	previous_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	origin = _player_point()
	mode.select(1 if game.driving or game.taxi_riding or game.bus_riding or game.garage.riding else 0)
	map.reset(origin)
	_refresh_places()
	root.show()
	has_destination = game.garage.waypoint_active
	if has_destination:
		selected = game.garage.waypoint_point
		selected_label = game.garage.waypoint_label
		_draw_route(true)
	elif not destinations.is_empty() and String(destinations[0].label).begins_with("MISIÓN"):
		places.select(1)
		_set_destination(destinations[0].p,String(destinations[0].label))
	else: info.text = "Selecciona una misión, un lugar o cualquier calle."

func close() -> void:
	if not active: return
	active = false
	root.hide()
	Input.mouse_mode = previous_mouse

func _center_player() -> void:
	map.center = Vector2(origin.x,origin.z)
	map.queue_redraw()

func _choose_place(index: int) -> void:
	if index<=0 or index>destinations.size(): return
	var place: Dictionary = destinations[index-1]
	_set_destination(place.p,String(place.label))

func _choose_point(point: Vector3) -> void:
	for i in range(destinations.size()):
		var p: Vector3 = destinations[i].p
		if Vector2(p.x-point.x,p.z-point.z).length()*map.zoom<=12.0:
			places.select(i+1)
			_choose_place(i+1)
			return
	places.select(0)
	_set_destination(point,"Destino marcado")

func _set_destination(point: Vector3,label_value: String) -> void:
	selected = point
	selected_label = label_value
	has_destination = true
	game.garage._set_waypoint(selected,selected_label)
	game.garage._save()
	_draw_route(true)

func _clear() -> void:
	has_destination = false
	selected_label = ""
	game.garage.waypoint_active = false
	game.garage.state.gps = {}
	game.taxis.set_garage_destination(Vector3.ZERO,"")
	game.garage._save()
	map.clear_route()
	places.select(0)
	info.text = "Destino eliminado."

func _change_mode(_index: int) -> void:
	if has_destination: _draw_route(false)

func _start_node() -> String:
	var router = game.taxis.router
	if router.astar.get_point_count()==0: return ""
	var id: int = router.astar.get_closest_point(origin)
	return String(router.osm_ids.get(id,""))

func _search() -> void:
	var value := query.text.strip_edges()
	if value.is_empty(): return
	var geography = game.cuba_world.geography
	var gps: Dictionary = geography.parse_coordinates(value)
	if gps.has("point"):
		_set_destination(gps.point,"GPS · "+value)
		return
	var result: Dictionary = game.taxis.router.resolve(value,_start_node())
	if result.has("error"):
		info.text = String(result.error)
		return
	var point: Vector3 = geography.points[result.id]
	_set_destination(point,String(result.label))

# Start from the closest real road segment rather than drawing a line
# from an arbitrary nearest junction across a building.
func _vehicle_route(at: Vector3,goal: Vector3) -> Dictionary:
	var geography = game.cuba_world.geography
	var router = game.taxis.router
	var edge_best: Dictionary = {}
	var projection := at
	var distance := INF
	for edge in geography.roads_near(at,35.0):
		if not bool(edge.driveable): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var p := Geometry3D.get_closest_point_to_segment(at,a,b)
		if at.distance_to(p)<distance:
			distance = at.distance_to(p)
			edge_best = edge
			projection = p
	if edge_best.is_empty(): return {"error":"No hay una calle de circulación cerca de tu posición."}
	var best: Dictionary = {}
	var best_length := INF
	for order in [0,1]:
		var entry := String(edge_best.a_id) if order==0 else String(edge_best.b_id)
		var exit_id := String(edge_best.b_id) if order==0 else String(edge_best.a_id)
		if not geography.graph.get(entry,[]).has(exit_id): continue
		# Handle a destination directly ahead on this same street segment.
		var a: Vector3 = geography.points[entry]
		var b: Vector3 = geography.points[exit_id]
		var target := Geometry3D.get_closest_point_to_segment(goal,a,b)
		if target.distance_to(goal)<=4.0 and (target-projection).dot(b-a)>=0.0:
			var length := projection.distance_to(target)
			if length<best_length:
				best_length = length
				best = {"path":[],"point":target,"start_point":projection}
		var result: Dictionary = router.resolve_point(goal,exit_id)
		if result.has("error"): continue
		var total: float = projection.distance_to(b)+float(result.get("distance",0.0))
		if total<best_length:
			best_length = total
			best = result
			best.start_point = projection
	return best if not best.is_empty() else {"error":"No existe una ruta vehicular desde esta calle."}

func _draw_route(fit: bool) -> void:
	var path: Array = []
	var route_end := selected
	var note := ""
	var from := Vector3(origin.x,0,origin.z)
	var escape: PackedVector3Array = game.yordi_mission.guided_escape_route() if game.yordi_mission!=null else PackedVector3Array()
	if not escape.is_empty() and selected.distance_to(escape[escape.size()-1])<1.0:
		for p in escape: path.append(p)
		note = "Ruta de huida de Yordi · sigue su flecha."
	elif mode.selected==0:
		var walk: PackedVector3Array = game.monte_pedestrians.route_between(from,selected)
		if not walk.is_empty():
			for p in walk: path.append(p)
		elif from.distance_to(selected)<35.0 and game.cuba_world.pedestrian_segment_clear(from,selected):
			path.append(from)
			path.append(selected)
		else:
			var pedestrians = game.monte_pedestrians
			if pedestrians.initialized:
				var start: int = pedestrians._nearest(from,12.0)
				var finish: int = pedestrians.graph.get_closest_point(selected)
				if start>=0 and finish>=0:
					var end: Vector3 = pedestrians.graph.get_point_position(finish)
					if end.distance_to(selected)<=18.0:
						var middle: PackedVector3Array = pedestrians.graph.get_point_path(start,finish)
						if not middle.is_empty():
							path.append(from)
							for p in middle: path.append(p)
							note = "Ruta hasta la acera accesible más cercana."
			if path.is_empty(): note = "No hay una ruta peatonal comprobada para este punto. Prueba una acera o el modo vehículo."
	else:
		var result: Dictionary = _vehicle_route(from,selected)
		if result.has("error"):
			note = String(result.error)
		else:
			if result.has("start_point"): path.append(result.start_point)
			for id in result.path: path.append(game.cuba_world.geography.points[id])
			var last: Vector3 = path.back() if not path.is_empty() else from
			route_end = result.get("point",last)
			path.append(route_end)
			note = "Ruta por calles de sentido permitido; termina en la calle accesible más cercana."
	# A destination marker is not a route. Never draw a straight blue line
	# across buildings when the routing graph could not find a connection.
	map.origin = Vector2(origin.x,origin.z)
	map.clear_route()
	map.marker = Vector2(selected.x,selected.z)
	map.has_marker = true
	var distance := 0.0
	if not path.is_empty():
		var previous: Vector3 = path[0]
		for p in path:
			var point: Vector3 = p
			map.route.append(Vector2(point.x,point.z))
			distance += previous.distance_to(point)
			previous = point
		info.text = "%s · %s por ruta\n%s" % [selected_label,Interface.distance_text(distance),note]
	else:
		info.text = selected_label+" · "+note
	if fit:
		var low := Vector2(minf(origin.x,selected.x),minf(origin.z,selected.z))
		var high := Vector2(maxf(origin.x,selected.x),maxf(origin.z,selected.z))
		for p in map.route:
			low = low.min(p)
			high = high.max(p)
		_fit_bounds.call_deferred(low,high)
	map.queue_redraw()

func _fit_bounds(low: Vector2,high: Vector2) -> void:
	if not active: return
	map.center = (low+high)*.5
	var span := high-low
	map.zoom = clampf(minf(maxf(300.0,map.size.x-120.0)/maxf(70.0,span.x),maxf(220.0,map.size.y-120.0)/maxf(70.0,span.y)),.13,2.5)
	map.queue_redraw()
