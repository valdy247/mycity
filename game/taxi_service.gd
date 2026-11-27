extends Node3D
const VehicleLights = preload("res://vehicle_lights.gd")
const Routes = preload("res://taxi_routes.gd")
const TrafficBypass = preload("res://traffic_bypass.gd")
const TaxiMap = preload("res://taxi_map.gd")
const MapData = preload("res://pilar_map.gd")
const Streets = preload("res://street_geometry.gd")
var router := Routes.new()
var geography: MapData
var streets: Streets
var taxis: Array = []
var selected: Dictionary = {}
var passenger: Dictionary = {}
var pending_query := ""
var map_view: TaxiMap
var go_button: Button
var selected_route: Dictionary = {}
var trip_confirmed := false
var business_enabled := false
var business_factory := Vector3.ZERO
var business_home := Vector3.ZERO
var factory_button: Button
var home_button: Button
var garage_button: Button
var garage_target := Vector3.ZERO
var garage_label := ""
var ride_status := ""
var dialog: PanelContainer
var destination: LineEdit
var feedback: Label
var arrived := false
var speed_mode := 1
var speed_choice: OptionButton
const SPEEDS := [14.0,19.0,23.0]
const BRAKE := 9.0
const ACCEL := 6.5
const PASSENGER_BOOST := 2.0
var boost_active := false
var stop_requested := false
var idle_scan := 0.0
var parking_scan := 0.0
var parking_cursor := 0
const SPEED_NAMES := ["Normal","Rápido","Exprés"]
var mats: Dictionary = {}
var meshes: Dictionary = {}

func setup(data: MapData,street_geometry: Streets,anchor: Vector3,van_pos: Vector3) -> void:
	geography = data
	streets = street_geometry
	router.setup(data)
	_make_dialog()
	var candidates: Array = []
	for edge in data.roads:
		if not bool(edge.driveable) or float(edge.width)<5.0:
			continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		if a.distance_to(b)<18.0:
			continue
		var p := (a+b)*.5
		if p.distance_to(van_pos)<12.0:
			continue
		candidates.append({"edge":edge,"point":p})
	var anchors: Array[Vector3] = [anchor,anchor+Vector3(210,0,0),anchor+Vector3(-180,0,160),anchor+Vector3(0,0,-210)]
	for target in anchors:
		candidates.sort_custom(func(a,b): return _idle_berth_score(a.edge,target.distance_to(a.point))<_idle_berth_score(b.edge,target.distance_to(b.point)))
		for candidate in candidates:
			var p: Vector3 = candidate.point
			var free := true
			for taxi in taxis:
				var node: CharacterBody3D = taxi.body
				if node.position.distance_to(p)<32.0:
					free = false
					break
			if not free: continue
			var edge: Dictionary = candidate.edge
			var a_id := String(edge.a_id)
			var b_id := String(edge.b_id)
			if not geography.graph.get(a_id,[]).has(b_id):
				var swap := a_id
				a_id = b_id
				b_id = swap
			if not geography.graph.get(a_id,[]).has(b_id): continue
			var a: Vector3 = data.points[a_id]
			var b: Vector3 = data.points[b_id]
			var d := (b-a).normalized()
			var berth := p+Vector3(-d.z,0,d.x)*curb_offset(float(edge.width),1.90)
			if not streets.intersection_clear_for_stop(berth,4.80,1.90) or not TrafficBypass._on_road(streets,berth,d,1.90,4.80): continue
			var body := _make_taxi(taxis.size())
			body.position = berth+Vector3.UP*.065
			body.rotation.y = atan2(d.x,d.z)
			body.add_to_group("traffic_parked")
			body.set_meta("traffic_priority",4.8)
			taxis.append({"body":body,"next_node":b_id,"path":[],"index":0,"speed":0.0,"blocked":0.0,"goal":"","label":"","note":""})
			break

static func curb_offset(road_width: float,vehicle_width: float) -> float:
	return maxf(0.0,road_width*.5-vehicle_width*.5-.25)

static func _idle_berth_score(edge: Dictionary,distance: float) -> float:
	return distance+(55.0 if int(edge.get("lanes_per_direction",1))>=2 else 0.0)

static func parallel_to_road(heading: Vector3,direction: Vector3) -> bool:
	return heading.normalized().dot(direction.normalized())>=.985

func _parking_road(at: Vector3,heading: Vector3) -> Dictionary:
	var result: Dictionary = {}
	var best := INF
	for edge in geography.roads_near(at,12.0):
		if not bool(edge.driveable): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var d := (b-a).normalized()
		if absf(d.dot(heading))<.25: continue
		var first := String(edge.a_id)
		var last := String(edge.b_id)
		if d.dot(heading)<0.0:
			var swap := a
			a = b
			b = swap
			d = -d
			var swap_id := first
			first = last
			last = swap_id
		if not geography.graph.get(first,[]).has(last): continue
		var flat := Vector3(at.x,0,at.z)
		var center := Geometry3D.get_closest_point_to_segment(flat,a,b)
		var side := Vector3(-d.z,0,d.x)
		var lateral := (flat-center).dot(side)
		if lateral<-.6 or lateral>float(edge.width)*.5+.2: continue
		var score := center.distance_to(flat)+(1.0-absf(heading.dot(d)))*3.0
		if score>=best: continue
		best = score
		result = {"a":a,"b":b,"d":d,"side":side,"center":center,"lateral":lateral,"width":float(edge.width),"next":last}
	return result

func _parking_plan(body: CharacterBody3D,road: Dictionary) -> Array:
	var origin := body.global_position
	var d: Vector3 = road.d
	var side: Vector3 = road.side
	var center: Vector3 = road.center
	center.y = origin.y
	var desired := curb_offset(float(road.width),1.90)
	var lateral := float(road.lateral)
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.0,1.8,4.9)
	for distance in [7.0,10.0,14.0]:
		var end := center+d*float(distance)+side*desired
		if (road.b-end).dot(d)<3.0 or not streets.intersection_clear_for_stop(end,4.8,1.9): continue
		var points: Array = []
		var previous := origin
		var valid := true
		var count := ceili(float(distance)/.75)
		for i in range(1,count+1):
			var along := float(distance)*float(i)/float(count)
			var blend := smoothstep(0.0,maxf(1.0,float(distance)-2.0),along)
			var p := center+d*along+side*lerpf(lateral,desired,blend)
			var facing := (p-previous).normalized()
			if not streets.intersection_clear_for_stop(p,4.8,1.9) or not TrafficBypass._on_road(streets,p,facing,1.9,4.8) or not TrafficBypass._segment_clear(body,previous,p,facing,shape):
				valid = false
				break
			points.append(p)
			previous = p
		if valid and TrafficBypass._clear(body,end,d,shape): return points
	return []

func _maintain_parked_taxis(delta: float) -> void:
	parking_scan += delta
	if parking_scan<1.5 or taxis.is_empty(): return
	parking_scan = 0.0
	parking_cursor = posmod(parking_cursor,taxis.size())
	var taxi: Dictionary = taxis[parking_cursor]
	parking_cursor += 1
	if taxi==passenger or taxi==selected or not taxi.path.is_empty(): return
	if not (taxi.get("yield_path",[]) as Array).is_empty() or not (taxi.get("cooperative_path",[]) as Array).is_empty(): return
	var body: CharacterBody3D = taxi.body
	if not is_instance_valid(body): return
	var road := _parking_road(body.global_position,body.global_basis.z)
	if road.is_empty(): return
	var d: Vector3 = road.d
	var at_curb := absf(float(road.lateral)-curb_offset(float(road.width),1.90))<.40
	if at_curb and parallel_to_road(body.global_basis.z,d): return
	if at_curb and TrafficBypass._on_road(streets,body.global_position,d,1.90,4.80):
		TrafficBypass.align_if_clear(body,atan2(d.x,d.z))
		if parallel_to_road(body.global_basis.z,d):
			taxi.next_node = road.next
			return
	var plan := _parking_plan(body,road)
	if plan.is_empty(): return
	taxi.yield_path = plan
	taxi.yield_index = 0
	taxi.parking_heading = d
	taxi.next_node = road.next

func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = .72
		mats[key] = m
	return mats[key] as StandardMaterial3D

func _part(root: Node3D,p: Vector3,size: Vector3,color: Color) -> void:
	if not meshes.has(size):
		var mesh := BoxMesh.new()
		mesh.size = size
		meshes[size] = mesh
	var view := MeshInstance3D.new()
	view.mesh = meshes[size] as BoxMesh
	view.material_override = _material(color)
	view.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(view)
	view.position = p

func _make_taxi(index: int) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "TaxiClasico_"+str(index+1)
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	body.collision_layer = 1
	body.collision_mask = 1|4|8|32
	add_child(body)
	var colors: Array[Color] = [Color("#d3a843"),Color("#73a69c"),Color("#a44f49"),Color("#9ab0bd")]
	var paint: Color = colors[index%colors.size()]
	var ivory := Color("#e8e1ca")
	var chrome := Color("#b9c2bd")
	var glass := Color("#587078")
	var rubber := Color("#292b2b")
	# 1950s-inspired Cuban almendrón: long hood, trunk, rounded-looking
	# stepped fenders, two-tone roof and chrome trim. +Z is forward.
	_part(body,Vector3(0,.68,0),Vector3(1.83,.65,4.65),paint)
	_part(body,Vector3(0,.92,1.36),Vector3(1.65,.20,1.70),paint)
	_part(body,Vector3(0,.90,-1.55),Vector3(1.65,.20,1.30),paint)
	_part(body,Vector3(0,1.19,-.28),Vector3(1.48,.60,2.0),glass)
	_part(body,Vector3(0,1.54,-.30),Vector3(1.55,.17,1.95),ivory)
	for side in [-1.0,1.0]:
		var x: float = float(side)
		_part(body,Vector3(x*.75,1.18,-.29),Vector3(.08,.62,.11),ivory)
		_part(body,Vector3(x*.88,.78,0),Vector3(.055,.10,4.35),ivory)
		_part(body,Vector3(x*.80,.84,-1.75),Vector3(.20,.29,1.12),paint)
		_part(body,Vector3(x*.79,.83,1.43),Vector3(.22,.30,1.24),paint)
		_part(body,Vector3(x*.70,.81,2.35),Vector3(.28,.24,.06),Color("#f6e9b9"))
		_part(body,Vector3(x*.70,.76,-2.35),Vector3(.18,.24,.06),Color("#b33133"))
		for z in [-1.46,1.43]:
			var wheel := MeshInstance3D.new()
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = .34
			cylinder.bottom_radius = .34
			cylinder.height = .22
			cylinder.radial_segments = 12
			wheel.mesh = cylinder
			wheel.material_override = _material(rubber)
			wheel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(wheel)
			wheel.rotation.z = PI*.5
			wheel.position = Vector3(x*.86,.34,float(z))
			_part(body,Vector3(x*1.0,.34,float(z)),Vector3(.025,.28,.28),chrome)
	for z in [-2.35,2.35]:
		_part(body,Vector3(0,.43,float(z)),Vector3(1.92,.14,.12),chrome)
	_part(body,Vector3(0,.72,2.35),Vector3(1.10,.23,.07),chrome)
	_part(body,Vector3(0,1.73,-.30),Vector3(.71,.23,.34),Color("#e6bb46"))
	for side in [-1.0,1.0]:
		var sign_label := Label3D.new()
		sign_label.text = "TAXI"
		sign_label.font_size = 48
		sign_label.pixel_size = .003
		sign_label.modulate = Color("#222222")
		sign_label.outline_size = 0
		body.add_child(sign_label)
		sign_label.position = Vector3(0,1.73,-.30+float(side)*.18)
		sign_label.rotation.y = 0.0 if float(side)>0 else PI
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.90,1.55,4.80)
	col.shape = shape
	body.add_child(col)
	col.position.y = .82
	_make_indicators(body)
	VehicleLights.attach(body,Vector3(.70,.81,2.39),Vector3(.70,.76,-2.39),Vector3(.25,.21,.025),Vector3(.16,.21,.025))
	return body

func _make_indicators(body: Node3D) -> void:
	for side in [-1,1]:
		var root := Node3D.new()
		body.add_child(root)
		root.name = "IndicatorRight" if side==1 else "IndicatorLeft"
		var x := -float(side)*.82
		_part(root,Vector3(x,.81,2.397),Vector3(.14,.11,.035),Color("#ffad25"))
		_part(root,Vector3(x,.76,-2.397),Vector3(.14,.11,.035),Color("#ffad25"))
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = Color("#ffad25")
		for child in root.get_children():
			if child is MeshInstance3D: child.material_override = glow
		root.hide()

func _indicators(body: Node3D,side: int) -> void:
	var flash := posmod(Time.get_ticks_msec(),720)<360
	for pair in [[-1,"IndicatorLeft"],[1,"IndicatorRight"]]:
		var root := body.get_node_or_null(NodePath(pair[1])) as Node3D
		if root!=null: root.visible = flash and side==pair[0]

func _make_dialog() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 18
	add_child(layer)
	dialog = PanelContainer.new()
	layer.add_child(dialog)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.offset_left = 16
	dialog.offset_right = -16
	dialog.offset_top = 16
	dialog.offset_bottom = -16
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,12)
	dialog.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation",6)
	margin.add_child(col)
	var title := Label.new()
	title.text = "TAXI · Elige tu destino"
	title.add_theme_font_size_override("font_size",22)
	col.add_child(title)
	var search_row := HBoxContainer.new()
	col.add_child(search_row)
	destination = LineEdit.new()
	destination.placeholder_text = "Buscar calle o esquina (opcional)"
	destination.max_length = 100
	destination.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_row.add_child(destination)
	destination.text_submitted.connect(_submit)
	var search_button := Button.new()
	search_button.text = "Buscar"
	search_button.pressed.connect(func(): _submit(destination.text))
	search_row.add_child(search_button)
	speed_choice = OptionButton.new()
	for i in range(SPEEDS.size()):
		speed_choice.add_item("%s · %d km/h" % [SPEED_NAMES[i],roundi(float(SPEEDS[i])*3.6)],i)
	speed_choice.select(speed_mode)
	speed_choice.item_selected.connect(func(index): speed_mode = index)
	search_row.add_child(speed_choice)
	var places := HBoxContainer.new()
	col.add_child(places)
	factory_button = Button.new()
	factory_button.text = "MIPYME de alimentos"
	factory_button.pressed.connect(func(): _business_destination(business_factory,"MIPYME de alimentos"))
	places.add_child(factory_button)
	home_button = Button.new()
	home_button.text = "Puesto de Albertico"
	home_button.pressed.connect(func(): _business_destination(business_home,"Puesto de Albertico"))
	places.add_child(home_button)
	garage_button = Button.new()
	garage_button.text = "Repuestos / casa"
	garage_button.pressed.connect(func(): _business_destination(garage_target,garage_label))
	places.add_child(garage_button)
	garage_button.hide()
	factory_button.hide()
	home_button.hide()
	map_view = TaxiMap.new()
	map_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(map_view)
	map_view.setup(geography)
	map_view.point_selected.connect(_select_map_point)
	feedback = Label.new()
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	feedback.text = "Clic: marcar destino · Arrastrar: mover mapa · Rueda: acercar"
	col.add_child(feedback)
	var buttons := HBoxContainer.new()
	col.add_child(buttons)
	go_button = Button.new()
	go_button.text = "Ir al destino"
	go_button.disabled = true
	go_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go_button.pressed.connect(func(): trip_confirmed = true)
	buttons.add_child(go_button)
	var cancel := Button.new()
	cancel.text = "Cancelar"
	cancel.pressed.connect(close_dialog)
	buttons.add_child(cancel)
	dialog.hide()

func nearby(at: Vector3) -> Dictionary:
	var closest: Dictionary = {}
	var best := 3.7*3.7
	for taxi in taxis:
		var body: CharacterBody3D = taxi.body
		if bool(taxi.get("albertico_reserved",false)) or taxi==passenger or not taxi.path.is_empty() or not (taxi.get("yield_path",[]) as Array).is_empty() or not (taxi.get("cooperative_path",[]) as Array).is_empty(): continue
		var d := at.distance_squared_to(body.position+Vector3.UP*.8)
		if d<best:
			best = d
			closest = taxi
	return closest

func open_dialog(at: Vector3) -> bool:
	# The route executor can also be reserved by a story vehicle.
	if not passenger.is_empty(): return false
	selected = nearby(at)
	if selected.is_empty(): return false
	destination.clear()
	speed_choice.select(speed_mode)
	selected_route = {}
	trip_confirmed = false
	pending_query = ""
	go_button.disabled = true
	var body: CharacterBody3D = selected.body
	map_view.reset(body.global_position)
	factory_button.visible = business_enabled
	home_button.visible = business_enabled
	garage_button.visible = not garage_label.is_empty()
	garage_button.text = garage_label if not garage_label.is_empty() else "Repuestos / casa"
	map_view.set_business_markers(business_factory,business_home,business_enabled)
	feedback.text = "Clic: marcar destino · Arrastrar: mover mapa · Rueda: acercar"
	dialog.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return true

func close_dialog() -> void:
	dialog.hide()
	selected = {}
	pending_query = ""
	selected_route = {}
	trip_confirmed = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _submit(value: String) -> void:
	if not value.strip_edges().is_empty():
		pending_query = value.strip_edges()

func set_business_points(factory: Vector3,home: Vector3,enabled: bool) -> void:
	business_factory = factory
	business_home = home
	business_enabled = enabled

func set_garage_destination(point: Vector3,label_value: String) -> void:
	garage_target = point
	garage_label = label_value

func _business_destination(point: Vector3,label_value: String) -> void:
	if selected.is_empty(): return
	var result := router.resolve_point(point,String(selected.next_node))
	if not result.has("error"):
		result.label = label_value
	_show_selection(result)

func _select_map_point(point: Vector3) -> void:
	if selected.is_empty(): return
	var result := router.resolve_point(point,String(selected.next_node))
	_show_selection(result)

func _show_selection(result: Dictionary) -> void:
	selected_route = {}
	trip_confirmed = false
	go_button.disabled = true
	if result.has("error"):
		map_view.clear_route()
		feedback.text = String(result.error)
		return
	var ids: Array[String] = result.path
	if ids.is_empty():
		map_view.clear_route()
		feedback.text = "No hay ruta disponible."
		return
	var points: Array = []
	for id in ids:
		points.append(geography.points[id])
	var target: Vector3 = result.get("point",geography.points[ids.back()])
	var distance: float = float(result.get("distance",router.route_length(ids)))
	var body: CharacterBody3D = selected.body
	distance += body.global_position.distance_to(geography.points[ids[0]])
	map_view.show_route(points,target)
	var label_value := String(result.label)
	var note := String(result.get("note",""))
	feedback.text = "%s · %.0f m · %s" % [label_value,distance,geography.coordinate_text(target)]
	if not note.is_empty():
		feedback.text += "\n"+note
	selected_route = result
	go_button.disabled = false

func _trip_dimensions(body: CharacterBody3D) -> Vector3:
	# Width, height, length. Motorcycles must not use the taxi envelope.
	return body.get_meta("trip_dimensions",Vector3(1.90,1.8,4.80))

func _ensure_safe_arrival(waypoints: Array,ids: Array[String],result: Dictionary,body: CharacterBody3D) -> bool:
	if waypoints.is_empty(): return false
	var dims := _trip_dimensions(body)
	var last: Vector3 = waypoints.back().p
	if streets.intersection_clear_for_stop(last,dims.z,dims.x): return true
	var node := String(result.get("exit",ids.back())) if bool(result.get("partial",false)) else String(ids.back())
	if not geography.points.has(node): return false
	var center: Vector3 = geography.points[node]
	var approach := center-body.global_position
	if waypoints.size()>1:
		var previous: Vector3 = waypoints[waypoints.size()-2].p
		approach = center-previous
		approach.y = 0.0
	var options: Array = []
	for other in geography.graph.get(node,[]):
		var finish: Vector3 = geography.points[other]
		var d := (finish-center).normalized()
		if approach.normalized().dot(d)<-.5: continue
		var desired := center+d*minf(center.distance_to(finish)*.5,18.0)+geography.lane_offset(center,finish,dims.x,true)
		var berth := streets.safe_stop_on_edge(center,finish,desired,dims.z,dims.x)
		if not streets.intersection_clear_for_stop(berth,dims.z,dims.x): continue
		options.append({"p":berth,"node":String(other),"distance":berth.distance_to(last)})
	options.sort_custom(func(a,b): return float(a.distance)<float(b.distance))
	if options.is_empty(): return false
	waypoints.back().node = node
	waypoints.append({"p":options[0].p,"node":""})
	return true

func _parallel_arrival(points: Array,dims: Vector3) -> void:
	if points.size()<2: return
	var last: Vector3 = points.back().p
	var prior: Vector3 = points[points.size()-2].p
	var heading := (last-prior).normalized()
	if heading.length_squared()<.1: return
	var road := _parking_road(last,heading)
	if road.is_empty(): return
	var d: Vector3 = road.d
	var side: Vector3 = road.side
	var center: Vector3 = road.center
	var end := center+side*curb_offset(float(road.width),dims.x)
	end.y = last.y
	var approach := end-d*5.0
	if (approach-prior).dot(d)<1.0 or absf((approach-prior).dot(side))>5.0: return
	if (approach-road.a).dot(d)<dims.z*.5 or not streets.intersection_clear_for_stop(end,dims.z,dims.x): return
	if not TrafficBypass._on_road(streets,approach,d,dims.x,dims.z) or not TrafficBypass._on_road(streets,end,d,dims.x,dims.z): return
	points[points.size()-1] = {"p":approach,"node":"","parking_approach":true}
	points.append({"p":end,"node":"","parking_approach":true})

func prepare_trip() -> bool:
	if selected.is_empty() or not passenger.is_empty(): return false
	if not pending_query.is_empty():
		var query := pending_query
		pending_query = ""
		_show_selection(router.resolve(query,String(selected.next_node)))
	if not trip_confirmed or selected_route.is_empty(): return false
	trip_confirmed = false
	var result := selected_route
	selected_route = {}
	var ids: Array[String] = result.path
	var body: CharacterBody3D = selected.body
	var dims := _trip_dimensions(body)
	var waypoints: Array = []
	var start: Vector3 = geography.points[ids[0]]
	var forward := body.global_transform.basis.z.normalized()
	var first_offset := Vector3(-forward.z,0,forward.x)*1.10
	var current_road: Dictionary = {}
	var closest := INF
	for edge in geography.roads_near(body.position,12.0):
		if not bool(edge.driveable): continue
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		if absf((b-a).normalized().dot(forward))<.85: continue
		var dist := Geometry3D.get_closest_point_to_segment(body.position,a,b).distance_to(body.position)
		if dist<closest:
			closest = dist
			current_road = edge
	first_offset = Vector3(-forward.z,0,forward.x)*geography.lane_distance(current_road,dims.x)
	# Approach the next directed graph node from the current lane.
	var first_stop := start+first_offset
	var partial: bool = bool(result.get("partial",false))
	if ids.size()==1 and not partial:
		var remaining := body.position.distance_to(first_stop)
		first_stop -= forward*minf(4.5,remaining*.5)
		if not current_road.is_empty():
			first_stop = streets.safe_stop_on_edge(current_road.a,current_road.b,first_stop,dims.z,dims.x)
	waypoints.append({"p":first_stop,"node":ids[0]})
	for i in range(ids.size()-1):
		var a: Vector3 = geography.points[ids[i]]
		var b: Vector3 = geography.points[ids[i+1]]
		var d := (b-a).normalized()
		var lane_offset := geography.lane_offset(a,b,dims.x)
		var length := a.distance_to(b)
		# Leave room before the last corner for passenger drop-off.
		if length>8.0:
			waypoints.append({"p":a+d*minf(3.0,length*.25)+lane_offset,"node":""})
		var end := b+lane_offset
		if i==ids.size()-2 and not partial:
			end = b-d*minf(4.5,length*.35)+geography.lane_offset(a,b,dims.x,true)
			end = streets.safe_stop_on_edge(a,b,end,dims.z,dims.x)
		waypoints.append({"p":end,"node":ids[i+1]})
	if partial:
		var entry: Vector3 = geography.points[String(result.entry)]
		var exit_point: Vector3 = geography.points[String(result.exit)]
		var target: Vector3 = result.point
		var lane_offset := geography.lane_offset(entry,exit_point,dims.x)
		var direction := (exit_point-entry).normalized()
		if entry.distance_to(target)>4.0:
			waypoints.append({"p":entry+direction*2.0+lane_offset,"node":""})
		var berth := streets.safe_stop_on_edge(entry,exit_point,target+geography.lane_offset(entry,exit_point,dims.x,true),dims.z,dims.x)
		waypoints.append({"p":berth,"node":""})
	if not _ensure_safe_arrival(waypoints,ids,result,body):
		_show_selection({"error":"No hay una parada segura junto a ese destino. Elige una calle cercana."})
		return false
	if dims.z>=4.0: _parallel_arrival(waypoints,dims)
	selected.path = _smooth_route(waypoints,body.global_position,dims.x)
	stop_requested = false
	selected.index = 0
	selected.goal = String(result.id)
	selected.label = String(result.label)
	selected.note = String(result.note)
	selected.speed = 0.0
	selected.blocked = 0.0
	selected.traffic_stall = 0.0
	selected.retreat_remaining = 0.0
	selected.backed_up = 0.0
	selected.traffic_last = body.global_position
	selected.signal_wait = 0.0
	selected.signal_seen = ""
	selected.next_node = String(result.id)
	passenger = selected
	body.remove_from_group("traffic_parked")
	body.add_to_group("autonomous_traffic")
	selected = {}
	dialog.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	arrived = false
	ride_status = String(passenger.note) if not String(passenger.note).is_empty() else "Destino: "+String(passenger.label)
	return true

# Resume a parked story vehicle from its exact remaining route.
# No new fare, destination lookup or vehicle spawn.
func resume_mission_trip(saved: Dictionary) -> bool:
	if not passenger.is_empty() or not selected.is_empty() or dialog.visible or saved.is_empty(): return false
	var body: CharacterBody3D = saved.get("body")
	var path: Array = saved.get("path",[])
	var index := int(saved.get("index",0))
	if not is_instance_valid(body) or index<0 or index>=path.size(): return false
	passenger = saved.duplicate(true)
	TrafficBypass.reset_watchdog(passenger)
	for key in ["junction_claim","junction_entered","junction_signal_id","junction_signal_wait","junction_retry"]:
		passenger.erase(key)
	passenger.speed = 0.0
	passenger.traffic_stall = 0.0
	passenger.traffic_last = body.global_position
	passenger.retreat_remaining = 0.0
	passenger.backed_up = 0.0
	passenger.cooperative_path = []
	passenger.cooperative_hold = 0
	passenger.cooperative_rejoin = false
	body.velocity = Vector3.ZERO
	body.set_meta("traffic_servicing",false)
	body.set_meta("junction_guard",false)
	body.remove_from_group("traffic_parked")
	body.add_to_group("autonomous_traffic")
	stop_requested = false
	arrived = false
	ride_status = "Destino: "+String(passenger.label)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	return true

func request_stop() -> void:
	if passenger.is_empty(): return
	stop_requested = true
	ride_status = "Deteniendo el vehículo para que puedas bajar..."

func ready_to_exit() -> bool:
	if passenger.is_empty(): return false
	var body: CharacterBody3D = passenger.body
	var dims := _trip_dimensions(body)
	return (arrived or stop_requested) and streets.intersection_clear_for_stop(body.global_position,dims.z,dims.x) and float(passenger.speed)<.15 and body.velocity.length()<.15

# Round sharp corners along the actual road. Keep signals and the final stop.
func _smooth_route(raw: Array,origin: Vector3,width: float = 1.90) -> Array:
	var result: Array = []
	for i in range(raw.size()):
		var item: Dictionary = raw[i]
		var corner: Vector3 = item.p
		if i==raw.size()-1 or bool(item.get("parking_approach",false)) or geography.signal_nodes.has(String(item.node)):
			result.append(item)
			continue
		var previous: Vector3 = origin if i==0 else raw[i-1].p
		var following: Vector3 = raw[i+1].p
		previous.y = corner.y
		following.y = corner.y
		var incoming := corner-previous
		var outgoing := following-corner
		var a_len := incoming.length()
		var b_len := outgoing.length()
		if minf(a_len,b_len)<.8:
			result.append(item)
			continue
		var a := incoming/a_len
		var b := outgoing/b_len
		if a.dot(b)>.985 or a.dot(b)<-.85:
			result.append(item)
			continue
		var trim := minf(5.0,minf(a_len,b_len)*.43)
		var rounded: Array = []
		for attempt in range(3):
			var entry := corner-a*trim
			var exit_point := corner+b*trim
			var valid := true
			rounded.clear()
			var count := maxi(4,ceili(trim*2.0/.8))
			for k in range(count+1):
				var t := float(k)/float(count)
				var p := entry.lerp(corner,t).lerp(corner.lerp(exit_point,t),t)
				var tangent := (corner-entry).lerp(exit_point-corner,t).normalized()
				var right := Vector3(-tangent.z,0,tangent.x)
				if not streets.point_on_road(p) or not streets.point_on_road(p+right*(width*.5)) or not streets.point_on_road(p-right*(width*.5)):
					valid = false
					break
				rounded.append({"p":p,"node":""})
			if valid: break
			rounded.clear()
			trim *= .55
		if rounded.is_empty(): result.append(item)
		else: result.append_array(rounded)
	return result

func _route_speed(body: CharacterBody3D,waypoints: Array,index: int) -> float:
	var cruise: float = SPEEDS[speed_mode]
	if _trip_dimensions(body).z<3.0: cruise = minf(cruise,11.0)
	if boost_active: cruise = minf(cruise*PASSENGER_BOOST,36.0)
	var limit := cruise
	var previous: Vector3 = body.position
	var traveled := 0.0
	for i in range(index,waypoints.size()):
		var item: Dictionary = waypoints[i]
		var p: Vector3 = item.p
		p.y = previous.y
		var incoming := p-previous
		var length := incoming.length()
		traveled += length
		var target_speed := cruise
		if i==waypoints.size()-1:
			target_speed = 0.0
		else:
			var next_point: Vector3 = waypoints[i+1].p
			next_point.y = p.y
			var outgoing := next_point-p
			if incoming.length()>.15 and outgoing.length()>.15:
				var angle := acos(clampf(incoming.normalized().dot(outgoing.normalized()),-1.0,1.0))
				if angle>.035:
					var radius := maxf(.6,minf(length,outgoing.length())/maxf(angle,.035))
					target_speed = minf(target_speed,maxf(2.5,sqrt(6.0*radius)))
		limit = minf(limit,sqrt(target_speed*target_speed+2.0*BRAKE*traveled))
		previous = p
		if traveled>maxf(40.0,cruise*cruise/(2.0*BRAKE)+12.0): break
	return limit

# Trace the actual path rather than a long straight ray into a corner wall.
func _route_blocked(body: CharacterBody3D,waypoints: Array,index: int) -> bool:
	var speed := float(passenger.speed)
	var remaining := 3.0+speed*.25+speed*speed/(2.0*BRAKE)
	var previous := body.position
	var space := get_world_3d().direct_space_state
	var checks := 0
	for i in range(index,waypoints.size()):
		var p: Vector3 = waypoints[i].p
		p.y = body.position.y
		var offset := p-previous
		var distance := offset.length()
		if distance<.05: continue
		var end := previous+offset.normalized()*minf(distance,remaining)
		var ray := PhysicsRayQueryParameters3D.create(previous+Vector3.UP*.85,end+Vector3.UP*.85,1|4)
		ray.exclude = [body.get_rid()]
		if not space.intersect_ray(ray).is_empty(): return true
		var low_ray := PhysicsRayQueryParameters3D.create(previous+Vector3.UP*.27,end+Vector3.UP*.27,1|4)
		low_ray.exclude = [body.get_rid()]
		if not space.intersect_ray(low_ray).is_empty(): return true
		remaining -= distance
		checks += 1
		if remaining<=0.0 or checks>=24: break
		previous = p
	return false

# Parked taxis must not monopolize a public bus stop. A horn requests
# a forward relocation, with the left lane as the safe alternative.
func yield_to_bus(stop: Dictionary,bus: CharacterBody3D) -> void:
	var center: Vector3 = stop.position
	var direction: Vector3 = stop.direction
	var side := Vector3(-direction.z,0,direction.x)
	var approach := maxf(0.0,(center-bus.global_position).dot(direction))
	for taxi in taxis:
		if taxi==passenger or taxi==selected or not taxi.path.is_empty(): continue
		if not (taxi.get("yield_path",[]) as Array).is_empty() or not (taxi.get("cooperative_path",[]) as Array).is_empty(): continue
		var body: CharacterBody3D = taxi.body
		var road := _parking_road(body.global_position,body.global_basis.z)
		if not road.is_empty() and float(road.width)>=10.0: continue
		var offset := body.global_position-center
		if absf(offset.dot(side))>2.30 or offset.dot(direction)<-approach-2.5 or offset.dot(direction)>8.5: continue
		var forward := body.global_transform.basis.z.normalized()
		if absf(forward.dot(direction))<.8: continue
		var left := Vector3(forward.z,0,-forward.x)
		var origin := body.global_position
		var four_lane := not streets.four_lane_at(origin,forward).is_empty()
		var goal_distance := 0.0
		# Stay on the current directed road, without jumping a junction.
		var next_id := String(taxi.next_node)
		if geography.points.has(next_id):
			var end: Vector3 = geography.points[next_id]
			goal_distance = (end-origin).dot(forward)-3.0
		var candidates: Array = []
		for distance in [9.0,12.0,16.0,20.0,24.0]:
			if float(distance)>goal_distance: continue
			for shift in ([0.0] if four_lane else [0.0,2.4,3.0]):
				var goal := origin+forward*float(distance)+left*float(shift)
				var relative := goal-center
				if absf(relative.dot(side))<2.75 and absf(relative.dot(direction))<9.0: continue
				candidates.append({"distance":distance,"shift":shift})
		# If the road ends too close, clear the berth laterally instead.
		for shift in [2.7,3.2,3.7]:
			if not four_lane and goal_distance>=4.0:
				candidates.append({"distance":minf(goal_distance,7.0),"shift":shift})
		var shape := BoxShape3D.new()
		shape.size = Vector3(2.0,1.65,4.9)
		for candidate in candidates:
			var points: Array = []
			var last := origin
			var valid := true
			var steps := ceili(float(candidate.distance)/.55)
			for i in range(1,steps+1):
				var t := float(i)/float(steps)
				var p := origin+forward*float(candidate.distance)*t+left*float(candidate.shift)*smoothstep(0.0,1.0,t)
				var d := (p-last).normalized()
				if not streets.intersection_clear_for_stop(p,4.80,1.90) or (four_lane and not streets.in_carriageway(p,d,1.90,4.80)) or not TrafficBypass._on_road(streets,p,d,1.90,4.80) or not TrafficBypass._segment_clear(body,last,p,d,shape):
					valid = false
					break
				points.append(p)
				last = p
			if valid and not points.is_empty():
				taxi.yield_path = points
				taxi.yield_index = 0
				break

func _tick_yielding_taxis(delta: float) -> void:
	for taxi in taxis:
		if taxi==passenger or taxi==selected: continue
		var parked: CharacterBody3D = taxi.body
		var requested := Time.get_ticks_msec()<int(parked.get_meta("traffic_yield_until",0))
		if not taxi.has("parking_heading") and (requested or not (taxi.get("cooperative_path",[]) as Array).is_empty() or Time.get_ticks_msec()<int(taxi.get("cooperative_hold",0))):
			if TrafficBypass.cooperate(taxi,parked,streets,1.90,4.80,1.8,delta,0.0,parked.global_position+parked.global_transform.basis.z*5.0):
				taxi.yield_path = []
				continue
		if bool(taxi.get("cooperative_rejoin",false)):
			taxi.cooperative_rejoin = false
			var best := INF
			var direction := parked.global_transform.basis.z
			for edge in geography.roads_near(parked.position,20.0):
				if not bool(edge.driveable): continue
				for id in [edge.a_id,edge.b_id]:
					var p: Vector3 = geography.points[id]
					if (p-parked.position).dot(direction)<0.0: continue
					var dist := parked.position.distance_squared_to(p)
					if dist<best:
						best = dist
						taxi.next_node = String(id)
		var path: Array = taxi.get("yield_path",[])
		if path.is_empty(): continue
		var body: CharacterBody3D = taxi.body
		var index := int(taxi.get("yield_index",0))
		var target: Vector3 = path[index]
		var diff := target-body.global_position
		diff.y = 0.0
		if diff.length()<.10:
			index += 1
			taxi.yield_index = index
			if index>=path.size():
				taxi.yield_path = []
				body.velocity = Vector3.ZERO
				if taxi.has("parking_heading"):
					var heading: Vector3 = taxi.parking_heading
					TrafficBypass.align_if_clear(body,atan2(heading.x,heading.z))
					taxi.erase("parking_heading")
			continue
		var d := diff.normalized()
		var step := minf(diff.length(),2.4*delta)
		var angle := lerp_angle(body.rotation.y,atan2(d.x,d.z),minf(delta*7.0,1.0))
		if not TrafficBypass.safe_step(body,d,step,angle,delta):
			taxi.yield_path = []
			taxi.erase("parking_heading")
			body.velocity = Vector3.ZERO

# An idle taxi also yields to approaching municipal and ordinary traffic,
# not only when a bus horn sounds at a designated stop.
func _yield_idle_traffic(delta: float) -> void:
	idle_scan += delta
	if idle_scan<1.2: return
	idle_scan = 0.0
	for node in get_tree().get_nodes_in_group("autonomous_traffic"):
		var approaching := node as CharacterBody3D
		if approaching==null: continue
		var forward := approaching.global_transform.basis.z.normalized()
		var side := Vector3(-forward.z,0,forward.x)
		for taxi in taxis:
			if taxi==passenger or taxi==selected or not taxi.path.is_empty(): continue
			var body: CharacterBody3D = taxi.body
			var offset := body.global_position-approaching.global_position
			if offset.dot(forward)<3.5 or offset.dot(forward)>12.0 or absf(offset.dot(side))>1.8: continue
			yield_to_bus({"position":body.global_position,"direction":forward},approaching)
			break

func tick(delta: float,_clock: float,boost_requested: bool = false) -> void:
	boost_active = boost_requested and not stop_requested and not arrived and not passenger.is_empty()
	_yield_idle_traffic(delta)
	_maintain_parked_taxis(delta)
	_tick_yielding_taxis(delta)
	if passenger.is_empty(): return
	var body: CharacterBody3D = passenger.body
	var dims := _trip_dimensions(body)
	passenger.ignore_red = boost_active
	passenger.indicator_left = maxf(0.0,float(passenger.get("indicator_left",0.0))-delta)
	_indicators(body,int(passenger.get("indicator_side",0)) if float(passenger.indicator_left)>0.0 and not arrived else 0)
	if arrived:
		body.velocity = Vector3.ZERO
		passenger.speed = 0.0
		return
	var waypoints: Array = passenger.path
	var index := int(passenger.index)
	if stop_requested: TrafficBypass.reset_watchdog(passenger)
	if not stop_requested:
		var watch_index := index
		while watch_index<waypoints.size()-1 and bool(waypoints[watch_index].get("bypass",false)): watch_index += 1
		var restored := TrafficBypass.watchdog(passenger,body,streets,waypoints,watch_index,dims.x,dims.z,dims.y,delta,false)
		if restored>=0:
			passenger.index = restored
			return
	# Consume intermediate samples without introducing a one-frame stop.
	while index<waypoints.size():
		var p: Vector3 = waypoints[index].p
		p.y = body.position.y
		if p.distance_to(body.position)>.22: break
		index += 1
	passenger.index = index
	if index>=waypoints.size():
		arrived = true
		ride_status = "Llegaste a "+String(passenger.label)+"."
		body.velocity = Vector3.ZERO
		passenger.speed = 0.0
		return
	var target: Vector3 = waypoints[index].p
	target.y = body.position.y
	var diff := target-body.position
	var distance := diff.length()
	var d := diff.normalized()
	var speed := _route_speed(body,waypoints,index)
	if bool(waypoints[index].get("bypass",false)): speed = minf(speed,4.0)
	passenger.signal_wait = 0.0
	var reach := minf(maxf(5.0,float(passenger.speed)*float(passenger.speed)/(2.0*BRAKE)+3.0),distance+.7)
	var lane := streets.four_lane_at(body.global_position,body.global_basis.z)
	if not lane.is_empty() and not bool(waypoints[index].get("lane_change",false)) and d.dot(body.global_basis.z)>.94: reach = maxf(reach,18.0)
	var free := TrafficBypass.clear_distance(body,d,reach,dims.x,dims.z)
	var blocked := free<reach-.05
	var stalled := TrafficBypass.stalled(passenger,body,delta)
	var junction_limit := TrafficBypass.junction_gate(passenger,body,streets,waypoints,index,false,dims.x,dims.z,dims.y,delta)
	speed = TrafficBypass.junction_speed(speed,junction_limit,BRAKE)
	if bool(passenger.get("red_wait",false)):
		passenger.signal_wait = 1.0
		passenger.traffic_stall = 0.0
		ride_status = "Semáforo rojo · "+String(passenger.label)
	elif ride_status.begins_with("Semáforo rojo"):
		ride_status = "Destino: "+String(passenger.label)
	var should_stop := stop_requested and streets.intersection_clear_for_stop(body.global_position,dims.z,dims.x)
	body.set_meta("traffic_priority",dims.z)
	body.set_meta("traffic_servicing",stop_requested or float(passenger.signal_wait)>0.0)
	# Shift requests a left pass before cooperative waiting or the ordinary
	# bypass timer. Retain the crossing gate and the original destination.
	passenger.shift_pass_retry = maxf(0.0,float(passenger.get("shift_pass_retry",0.0))-delta)
	# Normal taxi driving uses either same-direction lane on four-lane roads.
	if blocked and not lane.is_empty() and not bool(body.get_meta("junction_guard",false)) and not stop_requested and float(passenger.shift_pass_retry)<=0.0 and not bool(waypoints[index].get("lane_change",false)) and not bool(waypoints[index].get("bypass",false)):
		passenger.shift_pass_retry = 1.5
		var choice := TrafficBypass.taxi_lane_change(body,waypoints,index,streets,dims.x,dims.z,dims.y)
		if not choice.is_empty():
			var changed: Array = waypoints.slice(0,index)
			changed.append_array(choice.path)
			changed.append_array(waypoints.slice(int(choice.resume)))
			passenger.path = changed
			passenger.indicator_side = int(choice.side)
			passenger.indicator_left = 3.0
			passenger.traffic_stall = 0.0
			ride_status = "Cambiando al carril "+("derecho" if int(choice.side)>0 else "izquierdo")+" · "+String(passenger.label)
			return
	var wants_pass := boost_active and lane.is_empty() and not bool(body.get_meta("junction_guard",false)) and blocked
	if wants_pass and float(passenger.shift_pass_retry)<=0.0 and not bool(waypoints[index].get("requested_left",false)):
		passenger.shift_pass_retry = 1.25
		var base := index
		while base<waypoints.size() and bool(waypoints[base].get("bypass",false)): base += 1
		if base<waypoints.size():
			var left_pass := TrafficBypass.requested_left_pass(body,waypoints,base,streets,dims.x,dims.z,geography.signal_nodes,dims.y)
			if not left_pass.is_empty():
				var changed: Array = waypoints.slice(0,index)
				changed.append_array(left_pass.path)
				changed.append_array(waypoints.slice(int(left_pass.resume)))
				passenger.path = changed
				passenger.traffic_stall = 0.0
				passenger.retreat_remaining = 0.0
				passenger.cooperative_path = []
				passenger.cooperative_hold = 0
				passenger.cooperative_rejoin = false
				passenger.speed = minf(float(passenger.speed),2.0)
				passenger.indicator_side = -1
				passenger.indicator_left = 3.0
				ride_status = "Adelantando por la izquierda · "+String(passenger.label)
				return
	if not bool(body.get_meta("traffic_servicing")) and TrafficBypass.cooperate(passenger,body,streets,dims.x,dims.z,dims.y,delta,stalled,target): return
	if bool(passenger.get("cooperative_rejoin",false)):
		passenger.cooperative_rejoin = false
		while index<waypoints.size()-1 and bool(waypoints[index].get("bypass",false)): index += 1
		passenger.index = index
		return
	passenger.bypass_cooldown = maxf(0.0,float(passenger.get("bypass_cooldown",0.0))-delta)
	if not bool(body.get_meta("junction_guard",false)) and float(passenger.get("retreat_remaining",0.0))<=0.0 and (stalled>1.0 or (not bool(waypoints[index].get("bypass",false)) and TrafficBypass.early_lane_pass(body,streets,blocked,free))) and not stop_requested and float(passenger.signal_wait)<=0.0 and float(passenger.bypass_cooldown)<=0.0:
		passenger.bypass_cooldown = 1.8
		# Discard only pending bypass samples, not the original destination.
		var base := index
		while base<waypoints.size() and bool(waypoints[base].get("bypass",false)): base += 1
		if base<waypoints.size():
			var bypass := TrafficBypass.recover(body,waypoints,base,streets,dims.x,dims.z,geography.signal_nodes,dims.y)
			if not bypass.is_empty():
				var changed: Array = waypoints.slice(0,index)
				changed.append_array(bypass.path)
				changed.append_array(waypoints.slice(int(bypass.resume)))
				passenger.path = changed
				passenger.traffic_stall = 0.0
				var first: Vector3 = bypass.path[0].p
				var side := Vector3(-body.global_basis.z.z,0,body.global_basis.z.x)
				passenger.indicator_side = 1 if (first-body.global_position).dot(side)>0.0 else -1
				passenger.indicator_left = 3.0
				ride_status = "Bordeando el atasco · "+String(passenger.label)
				return
			elif base>index:
				passenger.index = base
				return
	if blocked: speed = minf(speed,sqrt(2.0*BRAKE*maxf(0.0,free-.7)))
	if should_stop: speed = 0.0
	if not stop_requested and float(passenger.signal_wait)<=0.0 and TrafficBypass.retreat(passenger,body,streets,dims.x,dims.z,delta,stalled>3.5 and float(passenger.speed)<.12):
		passenger.speed = 0.0
		return
	if stalled<.1 and not blocked: passenger.backed_up = 0.0
	passenger.speed = move_toward(float(passenger.speed),speed,delta*(BRAKE if speed<float(passenger.speed) else ACCEL*(1.7 if boost_active else 1.0)))
	var angle := lerp_angle(body.rotation.y,atan2(d.x,d.z),1.0-exp(-delta*8.0))
	var advance := TrafficBypass.junction_advance(minf(float(passenger.speed)*delta,distance),junction_limit)
	if blocked: advance = minf(advance,maxf(0.0,free-.7))
	if advance<=.0001:
		if junction_limit<0.0 and not blocked and not should_stop: TrafficBypass.align_if_clear(body,angle)
		body.velocity = Vector3.ZERO
		passenger.speed = 0.0
	elif not TrafficBypass.safe_step(body,d,advance,angle,delta): passenger.speed = 0.0
	if stalled>5.0 and not stop_requested: ride_status = "Buscando paso seguro · "+String(passenger.label)

func stop_position(player: CharacterBody3D,shape: Shape3D) -> Dictionary:
	if passenger.is_empty(): return {}
	var body: CharacterBody3D = passenger.body
	var space := get_world_3d().direct_space_state
	# Prefer sidewalks, then any unoccupied ground next to the stationary
	# taxi. Wide avenues previously had no valid exit inside 4.4 metres.
	for pass_index in range(2):
		for distance_value in [1.65,2.1,2.6,3.5,4.4,5.5,6.5,8.0]:
			for side in [1.0,-1.0]:
				for along in [0.0,-1.3,1.3,-2.7,2.7]:
					var p := body.to_global(Vector3(-float(side)*float(distance_value),0,float(along)))
					if pass_index==0 and streets.point_on_road(p): continue
					if pass_index==1 and float(distance_value)>4.4: continue
					var ground_ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*2.0,p-Vector3.UP*1.0,2)
					ground_ray.exclude = [player.get_rid()]
					var hit := space.intersect_ray(ground_ray)
					if hit.is_empty(): continue
					var at: Vector3 = hit.position+Vector3.UP*.90
					var query := PhysicsShapeQueryParameters3D.new()
					query.shape = shape
					query.transform = Transform3D(Basis.IDENTITY,at)
					query.collision_mask = 1|4|8|16
					query.exclude = [player.get_rid()]
					if not space.intersect_shape(query,1).is_empty(): continue
					var start := body.global_position+Vector3.UP*.90
					var clear_ray := PhysicsRayQueryParameters3D.create(start,at,1|4|8|16)
					clear_ray.exclude = [body.get_rid(),player.get_rid()]
					if not space.intersect_ray(clear_ray).is_empty(): continue
					return {"position":at}
	return {}

func finish_trip() -> void:
	if passenger.is_empty(): return
	var body: CharacterBody3D = passenger.body
	TrafficBypass._junction_release(passenger,body,streets)
	_indicators(body,0)
	body.set_meta("junction_guard",false)
	body.remove_from_group("autonomous_traffic")
	body.add_to_group("traffic_parked")
	body.set_meta("traffic_servicing",false)
	passenger.cooperative_path = []
	body.velocity = Vector3.ZERO
	passenger.path = []
	passenger.speed = 0.0
	# A premature stop is not necessarily at the planned goal. Find the
	# closest forward graph node before allowing another fare.
	if not arrived:
		var best := INF
		var direction := body.global_transform.basis.z
		for edge in geography.roads_near(body.position,20.0):
			if not bool(edge.driveable): continue
			for id in [edge.a_id,edge.b_id]:
				var p: Vector3 = geography.points[id]
				if (p-body.position).dot(direction)<0.0: continue
				var distance := body.position.distance_squared_to(p)
				if distance<best:
					best = distance
					passenger.next_node = String(id)
	passenger = {}
	arrived = false
	stop_requested = false
	boost_active = false

func cycle_speed() -> void:
	speed_mode = (speed_mode+1)%SPEEDS.size()

func speed_description() -> String:
	return "%s | %d km/h" % ["Turbo" if boost_active else SPEED_NAMES[speed_mode],roundi(float(passenger.get("speed",0.0))*3.6)]
