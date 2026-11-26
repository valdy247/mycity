extends Node3D
const Routes = preload("res://taxi_routes.gd")
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
var ride_status := ""
var dialog: PanelContainer
var destination: LineEdit
var feedback: Label
var arrived := false
var speed_mode := 1
var speed_choice: OptionButton
const SPEEDS := [12.0,18.0,22.0]
const BRAKE := 9.0
const ACCEL := 6.5
var stop_requested := false
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
		candidates.sort_custom(func(a,b): return target.distance_squared_to(a.point)<target.distance_squared_to(b.point))
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
			var body := _make_taxi(taxis.size())
			body.position = p+router.lane(a,b)+Vector3.UP*.065
			body.rotation.y = atan2(d.x,d.z)
			taxis.append({"body":body,"next_node":b_id,"path":[],"index":0,"speed":0.0,"blocked":0.0,"goal":"","label":"","note":""})
			break

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
	body.collision_mask = 1|4
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
	return body

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
	factory_button.text = "Fábrica de alimentos"
	factory_button.pressed.connect(func(): _business_destination(business_factory,"Fábrica de alimentos"))
	places.add_child(factory_button)
	home_button = Button.new()
	home_button.text = "Mi casa"
	home_button.pressed.connect(func(): _business_destination(business_home,"Mi casa"))
	places.add_child(home_button)
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
		if taxi==passenger or not taxi.path.is_empty(): continue
		var d := at.distance_squared_to(body.position+Vector3.UP*.8)
		if d<best:
			best = d
			closest = taxi
	return closest

func open_dialog(at: Vector3) -> bool:
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

func prepare_trip() -> bool:
	if selected.is_empty(): return false
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
	var waypoints: Array = []
	var start: Vector3 = geography.points[ids[0]]
	var forward := body.global_transform.basis.z.normalized()
	var first_offset := Vector3(-forward.z,0,forward.x)*1.10
	# Approach the next directed graph node from the current lane.
	var first_stop := start+first_offset
	var partial: bool = bool(result.get("partial",false))
	if ids.size()==1 and not partial:
		var remaining := body.position.distance_to(first_stop)
		first_stop -= forward*minf(4.5,remaining*.5)
	waypoints.append({"p":first_stop,"node":ids[0]})
	for i in range(ids.size()-1):
		var a: Vector3 = geography.points[ids[i]]
		var b: Vector3 = geography.points[ids[i+1]]
		var d := (b-a).normalized()
		var lane_offset := router.lane(a,b)
		var length := a.distance_to(b)
		# Leave room before the last corner for passenger drop-off.
		if length>8.0:
			waypoints.append({"p":a+d*minf(3.0,length*.25)+lane_offset,"node":""})
		var end := b+lane_offset
		if i==ids.size()-2 and not partial:
			end -= d*minf(4.5,length*.35)
		waypoints.append({"p":end,"node":ids[i+1]})
	if partial:
		var entry: Vector3 = geography.points[String(result.entry)]
		var exit_point: Vector3 = geography.points[String(result.exit)]
		var target: Vector3 = result.point
		var lane_offset := router.lane(entry,exit_point)
		var direction := (exit_point-entry).normalized()
		if entry.distance_to(target)>4.0:
			waypoints.append({"p":entry+direction*2.0+lane_offset,"node":""})
		waypoints.append({"p":target+lane_offset,"node":""})
	selected.path = _smooth_route(waypoints,body.global_position)
	stop_requested = false
	selected.index = 0
	selected.goal = String(result.id)
	selected.label = String(result.label)
	selected.note = String(result.note)
	selected.speed = 0.0
	selected.blocked = 0.0
	selected.signal_wait = 0.0
	selected.signal_seen = ""
	selected.next_node = String(result.id)
	passenger = selected
	selected = {}
	dialog.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	arrived = false
	ride_status = String(passenger.note) if not String(passenger.note).is_empty() else "Destino: "+String(passenger.label)
	return true

func request_stop() -> void:
	if passenger.is_empty(): return
	stop_requested = true
	ride_status = "Deteniendo el taxi para que puedas bajar..."

func ready_to_exit() -> bool:
	if passenger.is_empty(): return false
	var body: CharacterBody3D = passenger.body
	return (arrived or stop_requested) and float(passenger.speed)<.15 and body.velocity.length()<.15

# Round sharp corners along the actual road. Keep signals and the final stop.
func _smooth_route(raw: Array,origin: Vector3) -> Array:
	var result: Array = []
	for i in range(raw.size()):
		var item: Dictionary = raw[i]
		var corner: Vector3 = item.p
		if i==raw.size()-1 or geography.signal_nodes.has(String(item.node)):
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
				if not streets.point_on_road(p) or not streets.point_on_road(p+right*.95) or not streets.point_on_road(p-right*.95):
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
	var limit: float = SPEEDS[speed_mode]
	var previous: Vector3 = body.position
	var traveled := 0.0
	for i in range(index,waypoints.size()):
		var item: Dictionary = waypoints[i]
		var p: Vector3 = item.p
		p.y = previous.y
		var incoming := p-previous
		var length := incoming.length()
		traveled += length
		var target_speed: float = SPEEDS[speed_mode]
		if i==waypoints.size()-1:
			target_speed = 0.0
		elif geography.signal_nodes.has(String(item.node)) and String(passenger.signal_seen)!=String(item.node):
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
		if traveled>40.0: break
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
		remaining -= distance
		checks += 1
		if remaining<=0.0 or checks>=24: break
		previous = p
	return false

func tick(delta: float,_clock: float) -> void:
	if passenger.is_empty(): return
	var body: CharacterBody3D = passenger.body
	if arrived:
		body.velocity = Vector3.ZERO
		passenger.speed = 0.0
		return
	var waypoints: Array = passenger.path
	var index := int(passenger.index)
	# Consume intermediate samples without introducing a one-frame stop.
	while index<waypoints.size():
		var p: Vector3 = waypoints[index].p
		p.y = body.position.y
		if p.distance_to(body.position)>.22: break
		var node_id := String(waypoints[index].node)
		if geography.signal_nodes.has(node_id) and String(passenger.signal_seen)!=node_id:
			passenger.signal_seen = node_id
			passenger.signal_wait = 2.0
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
	passenger.signal_wait = maxf(0.0,float(passenger.signal_wait)-delta)
	if float(passenger.signal_wait)>0.0: speed = 0.0
	var blocked := _route_blocked(body,waypoints,index)
	if blocked or stop_requested: speed = 0.0
	passenger.speed = move_toward(float(passenger.speed),speed,delta*(BRAKE if speed<float(passenger.speed) else ACCEL))
	if float(passenger.speed)<.10 and (stop_requested or blocked or float(passenger.signal_wait)>0.0):
		passenger.speed = 0.0
		body.velocity = Vector3.ZERO
		return
	# Smooth yaw while the body follows the rounded lane exactly.
	body.rotation.y = lerp_angle(body.rotation.y,atan2(d.x,d.z),1.0-exp(-delta*8.0))
	body.velocity = d*minf(float(passenger.speed),distance/maxf(delta,.001))
	body.move_and_slide()
	if blocked or body.get_slide_collision_count()>0:
		passenger.blocked = float(passenger.blocked)+delta
		if float(passenger.blocked)>5.0 and not stop_requested:
			ride_status = "Taxi bloqueado. Pulsa E para bajar."
	else:
		passenger.blocked = 0.0

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

func cycle_speed() -> void:
	speed_mode = (speed_mode+1)%SPEEDS.size()

func speed_description() -> String:
	return "%s | %d km/h" % [SPEED_NAMES[speed_mode],roundi(float(passenger.get("speed",0.0))*3.6)]
