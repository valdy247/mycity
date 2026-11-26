extends Node3D
# Mission 2. Only two NPCs, one temporary room and four tiny wall textures.
const Person = preload("res://street_person.gd")
const ROOM := Vector3(30,110,0)
const COLS := 8
const ROWS := 4
const TOTAL := COLS*ROWS*4
const OLD_PAINT := Color("#a99d88")
const NEW_PAINT := Color("#f1e6cb")
var game
var world
var business
var state: Dictionary
var carlos: Person
var client: Person
var home: Dictionary = {}
var customer: Dictionary = {}
var room: Node3D
var marker: Node3D
var hand: Node3D
var brush_item: Node3D
var bucket: Node3D
var walls: Array[MeshInstance3D] = []
var images: Array[Image] = []
var textures: Array[ImageTexture] = []
var inside := false
var previous_first := true
var call_wait := 0.0
var work_clock := 0.0
var brush_clock := 0.0
var follow_clock := 0.0
var follow_path := PackedVector3Array()
var follow_index := 0
var was_vehicle := false
var locate_wait := 0.0
var locate_reported := false
var paint_dirty := false
var paint_save_clock := 0.0

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	business = game.business
	var life: Dictionary = business.ledger.life_data
	if not life.has("carlos_paint"): life.carlos_paint = {"stage":0,"painted":{},"brush":false,"charge":0}
	state = life.carlos_paint
	# Re-enter the client house to resume a partially painted job.
	marker = Node3D.new()
	add_child(marker)
	business._arrow(marker,Vector3.UP*2.6,Color("#ffd85c"))
	marker.hide()

func _save() -> void:
	business.ledger.save_game()

func _stage() -> int:
	return int(state.get("stage",0))

func _named(edge: Dictionary,term: String) -> bool:
	for value in [String(edge.name)]+edge.get("aliases",[]):
		var name_value: String = world.geography.normalized(String(value))
		if name_value.contains(term): return true
	return false

func _corners(first: String,second: String) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for id in world.geography.junctions:
		var one := false
		var two := false
		for edge in world.geography.junctions[id]:
			if _named(edge,first) or (first=="monte" and bool(edge.get("monte_corridor",false))): one = true
			if _named(edge,second) or (second=="monte" and bool(edge.get("monte_corridor",false))): two = true
		if one and two: out.append(world.geography.points[id])
	return out

func _ground(at: Vector3) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(at+Vector3.UP*1.5,at-Vector3.UP*.5,2)
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<.65: return {}
	var p: Vector3 = hit.position
	if world.street_geometry.point_on_road(p) or not world.pedestrian_segment_clear(p,p): return {}
	return {"p":p}

func _door_data(entry: Dictionary) -> Dictionary:
	var door: Vector3 = entry.threshold
	var normal: Vector3 = entry.normal
	for distance in [.65,1.05,1.50]:
		var ground := _ground(door+normal*float(distance))
		if not ground.is_empty(): return {"door":door,"normal":normal,"p":ground.p}
	return {}

func _restore_door(key: String) -> Dictionary:
	var record: Dictionary = state.get(key,{})
	if record.is_empty(): return {}
	var p := Vector3(float(record.x),0,float(record.z))
	for entry in world.npc_doorways:
		var door: Vector3 = entry.threshold
		if Vector2(door.x-p.x,door.z-p.z).length()<.25: return _door_data(entry)
	return {}

func _remember(key: String,site: Dictionary) -> void:
	var p: Vector3 = site.door
	state[key] = {"x":p.x,"z":p.z}

func _locate() -> bool:
	if not home.is_empty() and not customer.is_empty(): return true
	if not game.monte_pedestrians.initialized: return false
	home = _restore_door("home")
	customer = _restore_door("customer")
	if home.is_empty():
		var monte := _corners("flores","monte")
		var esteves := _corners("flores","esteves")
		if monte.is_empty() or esteves.is_empty():
			_location_notice("No se encontraron las dos esquinas de Flores en el mapa cargado.")
			return false
		var corner := Vector3.ZERO
		var start := Vector3.ZERO
		var best := INF
		for a in monte:
			for b in esteves:
				var distance: float = a.distance_to(b)
				if distance<2.0 or distance>=best: continue
				best = distance
				start = a
				corner = b
		if not is_finite(best): return false
		var travel := (corner-start).normalized()
		var right := Vector3(-travel.z,0,travel.x)
		var choices: Array = []
		for entry in world.npc_doorways:
			if String(entry.kind)!="home": continue
			var p: Vector3 = entry.threshold
			var normal: Vector3 = entry.normal
			if p.distance_to(corner)>27.0 or normal.dot(-right)<.55: continue
			for edge in world.geography.roads_near(p,18.0):
				if not _named(edge,"flores"): continue
				var a: Vector3 = edge.a
				var b: Vector3 = edge.b
				var road := Geometry3D.get_closest_point_to_segment(p,a,b)
				if (p-road).dot(right)<1.0 or road.distance_to(p)>float(edge.width)*.5+5.0: continue
				var site := _door_data(entry)
				if not site.is_empty(): choices.append({"site":site,"score":p.distance_to(corner)+maxf(0.0,(p-start).dot(travel)-best)*.5})
				break
		choices.sort_custom(func(a,b): return float(a.score)<float(b.score))
		if choices.is_empty():
			_location_notice("Flores y Estévez localizado, pero falta una puerta residencial segura en el lado indicado.")
			return false
		home = choices[0].site
		_remember("home",home)
	if customer.is_empty():
		var origin: Vector3 = home.p
		var choices: Array = []
		for entry in world.npc_doorways:
			if String(entry.kind)!="home": continue
			var p: Vector3 = entry.threshold
			var distance := p.distance_to(origin)
			if distance<12.0 or distance>85.0: continue
			if not world.garage_home_site.is_empty() and p.distance_to(world.garage_home_site.door)<3.0: continue
			choices.append({"entry":entry,"score":absf(distance-32.0)})
		choices.sort_custom(func(a,b): return float(a.score)<float(b.score))
		for option in choices.slice(0,20):
			var site := _door_data(option.entry)
			if site.is_empty(): continue
			var route: PackedVector3Array = game.monte_pedestrians.route_between(origin,site.p)
			if route.is_empty() and not world.pedestrian_segment_clear(origin,site.p): continue
			customer = site
			_remember("customer",customer)
			break
	if customer.is_empty():
		_location_notice("Casa de Carlos localizada, pero no hay una casa cercana conectada por la red peatonal.")
		return false
	locate_reported = false
	_save()
	return true

func _location_notice(message: String) -> void:
	if locate_reported: return
	locate_reported = true
	print("Misión Carlos: "+message)
	business._notify(message)

func _spawn_carlos(at: Vector3) -> void:
	if not is_instance_valid(carlos):
		carlos = Person.new()
		add_child(carlos)
		carlos.setup(806)
		carlos.remove_from_group("social_people")
		business._label(carlos,"Carlos",Vector3(0,2.03,0))
	carlos.global_position = at
	carlos.show()

func _target(site: Dictionary,label_value: String) -> void:
	if site.is_empty(): return
	var p: Vector3 = site.p
	marker.global_position = p
	marker.show()
	game.garage._set_waypoint(p,label_value)

func _clear_target() -> void:
	marker.hide()
	game.garage.waypoint_active = false
	game.garage.state.gps = {}
	game.taxis.set_garage_destination(Vector3.ZERO,"")

func open_call() -> void:
	if _stage()==0: return
	if _stage()!=1:
		business._open("Carlos",objective())
		business._button("Cerrar",business.close)
		return
	business._open("Llamada entrante · Carlos","Asere, conseguí un trabajo pintando una casa cerca de la mía. ¿Vienes conmigo? Vivo en Flores, esquina Estévez.")
	business._button("Sí, cuenta conmigo",_accept)
	business._button("Ahora no",business.close)

func _accept() -> void:
	state.stage = 2
	business.ledger.add_message("Tú → Carlos","Sí, cuenta conmigo. Voy a buscarte.")
	business.close()
	_save()
	if _locate():
		_spawn_carlos(home.p)
		_target(home,"Casa de Carlos · Flores y Estévez")
	else: business._notify("Buscando la casa de Carlos en Flores y Estévez…")

func objective() -> String:
	match _stage():
		1: return "Carlos te llama · P: teléfono"
		2: return "Busca a Carlos en Flores y Estévez."
		3: return "Ve con Carlos a casa del cliente."
		4: return "Pinta todas las paredes · %d%%" % roundi(100.0*float(state.painted.size())/float(TOTAL))
		5:
			if String(game.garage.state.part)=="bicicleta:wheel_a": return "Misión cumplida · instala la goma en tu garaje."
			return ""
	return ""

func _aim_node(node: Node3D,center: Vector3,extent: Vector3,reach: float = 3.0) -> bool:
	if not is_instance_valid(node) or not node.is_visible_in_tree(): return false
	var target := node.to_global(center)
	if game.player.global_position.distance_to(target)>reach: return false
	var camera: Camera3D = game.play_camera
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var local_hit: Variant = AABB(center-extent,extent*2.0).intersects_segment(node.to_local(origin),node.to_local(origin+direction*8.0))
	if local_hit==null: return false
	var at := node.to_global(local_hit)
	var ray := PhysicsRayQueryParameters3D.create(origin,at,1|4|8|16|32)
	ray.exclude = [game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _aim_door() -> bool:
	if customer.is_empty(): return false
	var door: Vector3 = customer.door
	var normal: Vector3 = customer.normal
	var camera: Camera3D = game.play_camera
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var denom := direction.dot(normal)
	if denom>=-.01 or game.player.global_position.distance_to(door)>3.5: return false
	var depth := (door-origin).dot(normal)/denom
	if depth<=0.0 or depth>8.0: return false
	var offset := origin+direction*depth-door
	var side := Vector3(-normal.z,0,normal.x)
	if absf(offset.dot(side))>.60 or offset.y<.03 or offset.y>2.2: return false
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+direction*maxf(.01,depth-.12),1|4|8|16)
	ray.exclude = [game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func action_text() -> String:
	if inside:
		if _stage()==4 and state.painted.size()>=TOTAL and _aim_node(client,Vector3.UP,Vector3(.45,.95,.35)): return "[E] Cobrar al cliente"
		if not bool(state.brush) and _aim_node(brush_item,Vector3.ZERO,Vector3(.28,.16,.28)): return "[E] Recoger brocha"
		if bool(state.brush) and _aim_node(bucket,Vector3.ZERO,Vector3(.32,.32,.32)): return "[E] Mojar brocha"
		if _exit_aim(): return "[E] Salir de la casa"
		if bool(state.brush): return "Clic izquierdo: pintar · carga %d/12" % int(state.charge)
		return "Mira la brocha del suelo y pulsa E"
	if _stage()==2 and _aim_node(carlos,Vector3.UP,Vector3(.38,.95,.35)): return "[E] Hablar con Carlos"
	if _stage() in [3,4] and _aim_door(): return "[E] Entrar a casa del cliente"
	return ""

func interact() -> bool:
	var action := action_text()
	if inside:
		if action.contains("Cobrar"): _payment()
		elif action.contains("Recoger brocha"):
			state.brush = true
			brush_item.hide()
			_refresh_hand()
			_save()
		elif action.contains("Mojar"):
			state.charge = 12
			_save()
		elif action.contains("Salir"): _exit()
		return true
	if action.contains("Hablar con Carlos"):
		if not game.garage._free_hands():
			business._notify("Deja primero lo que llevas en las manos.")
			return true
		state.stage = 3
		business._notify("Carlos: Vamos, es aquí cerca. Te sigo.")
		_target(customer,"Casa del cliente")
		_save()
		return true
	if action.contains("Entrar a casa del cliente"):
		if not game.garage._free_hands():
			business._notify("Necesitas las manos libres para trabajar.")
			return true
		if not is_instance_valid(carlos) or carlos.global_position.distance_to(customer.p)>5.0:
			business._notify("Espera a Carlos para entrar juntos.")
			return true
		_enter()
		return true
	return false

func _solid(p: Vector3,size: Vector3,color: Color,layer: int = 1) -> StaticBody3D:
	return game.garage._solid(room,p,size,color,layer)

func _make_room() -> void:
	room = Node3D.new()
	add_child(room)
	room.position = ROOM
	_solid(Vector3(0,-.10,0),Vector3(8,.2,6),Color("#b3aba1"),2)
	_solid(Vector3(0,2.88,0),Vector3(8,.16,6),Color("#e8e2d6"))
	for i in range(4):
		var side := i>=2
		var sign_value := -1.0 if i%2==0 else 1.0
		var p := Vector3(sign_value*3.95,1.4,0) if side else Vector3(0,1.4,sign_value*2.95)
		var body := _solid(p,Vector3(.10,2.8,6) if side else Vector3(8,2.8,.10),OLD_PAINT)
		body.set_meta("paint_wall",i)
		var quad := QuadMesh.new()
		quad.size = Vector2(5.8 if side else 7.8,2.8)
		var visual := MeshInstance3D.new()
		visual.mesh = quad
		room.add_child(visual)
		visual.position = p-(Vector3.RIGHT if side else Vector3.BACK)*sign_value*.056
		visual.rotation.y = (-sign_value*PI*.5 if side else (PI if sign_value>0 else 0.0))
		var img := Image.create(COLS,ROWS,false,Image.FORMAT_RGB8)
		img.fill(OLD_PAINT)
		for y in range(ROWS):
			for x in range(COLS):
				if state.painted.has(_cell_key(i,x,y)): img.set_pixel(x,y,NEW_PAINT)
		var tex := ImageTexture.create_from_image(img)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		visual.material_override = mat
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		walls.append(visual)
		images.append(img)
		textures.append(tex)
	var light := OmniLight3D.new()
	room.add_child(light)
	light.position = Vector3(0,2.65,0)
	light.omni_range = 10.0
	light.light_energy = 1.5
	bucket = Node3D.new()
	room.add_child(bucket)
	bucket.position = Vector3(0,.25,0)
	var can := CylinderMesh.new()
	can.top_radius = .22
	can.bottom_radius = .19
	can.height = .42
	can.radial_segments = 12
	var mesh := MeshInstance3D.new()
	mesh.mesh = can
	mesh.material_override = business._mat(Color("#537c86"))
	bucket.add_child(mesh)
	business._box(bucket,Vector3(0,.22,0),Vector3(.29,.03,.29),NEW_PAINT)
	brush_item = Node3D.new()
	room.add_child(brush_item)
	brush_item.position = Vector3(.55,.07,0)
	_make_brush(brush_item)
	_make_brush(brush_item,Vector3(.25,0,.15))
	brush_item.visible = not bool(state.brush)
	# Exit marker lies on the entrance wall; paint behind it is still possible.
	business._label(room,"SALIR · E",Vector3(0,2.55,2.87)).rotation.y = PI
	_spawn_carlos(ROOM+Vector3(-2.8,0,-1.9))
	carlos.rotation.y = -PI*.5
	var worker_brush := Node3D.new()
	room.add_child(worker_brush)
	worker_brush.name = "CarlosBrush"
	worker_brush.position = Vector3(-3.35,1.1,-1.9)
	worker_brush.rotation.y = PI*.5
	_make_brush(worker_brush)
	_refresh_hand()
	_refresh_client()

func _make_brush(root: Node3D,offset: Vector3 = Vector3.ZERO) -> void:
	business._box(root,offset+Vector3(0,0,.10),Vector3(.07,.06,.23),Color("#95633d"))
	business._box(root,offset+Vector3(0,0,-.08),Vector3(.16,.055,.15),Color("#cab99a"))

func _refresh_hand() -> void:
	if not is_instance_valid(hand):
		hand = Node3D.new()
		game.play_camera.add_child(hand)
		hand.position = Vector3(.28,-.30,-.72)
		hand.rotation.x = -.5
		_make_brush(hand)
	hand.visible = inside and bool(state.brush) and state.painted.size()<TOTAL

func _enter() -> void:
	inside = true
	previous_first = game.first_person
	state.stage = 4
	_clear_target()
	_make_room()
	game.player.global_position = ROOM+Vector3(0,.86,2.05)
	game.player.velocity = Vector3.ZERO
	game.first_person = true
	game.yaw = 0.0
	game.pitch = -.20
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	_save()

func _exit_aim() -> bool:
	if not inside: return false
	var camera: Camera3D = game.play_camera
	var origin := camera.global_position-ROOM
	var direction := -camera.global_basis.z
	if direction.z<=.01: return false
	var depth := (2.88-origin.z)/direction.z
	if depth<=0.0 or depth>3.0: return false
	var p := origin+direction*depth
	return absf(p.x)<.65 and p.y>.05 and p.y<2.65

func _destroy_room() -> void:
	if is_instance_valid(hand): hand.hide()
	if is_instance_valid(client): client.queue_free()
	client = null
	if is_instance_valid(room): room.queue_free()
	room = null
	walls.clear()
	images.clear()
	textures.clear()

func _exit() -> void:
	inside = false
	_destroy_room()
	var point: Vector3 = customer.p
	game.player.global_position = point+Vector3.UP*.86
	game.player.velocity = Vector3.ZERO
	game.first_person = previous_first
	game._apply_camera_mode()
	if _stage()==4:
		_spawn_carlos(point)
		_target(customer,"Casa del cliente")
	else:
		if is_instance_valid(carlos): carlos.hide()
		if not world.garage_home_site.is_empty(): game.garage._set_waypoint(world.garage_home_site.door,"Mi garaje")
	_save()

func reset() -> void:
	if not inside: return
	inside = false
	_destroy_room()
	if not customer.is_empty():
		_spawn_carlos(customer.p)
		_target(customer,"Casa del cliente")
	_save()

func _cell_key(wall: int,x: int,y: int) -> String:
	return "%d:%d:%d" % [wall,x,y]

func _paint_cell(wall: int,x: int,y: int) -> bool:
	var key := _cell_key(wall,x,y)
	if state.painted.has(key): return false
	state.painted[key] = true
	paint_dirty = true
	images[wall].set_pixel(x,y,NEW_PAINT)
	textures[wall].update(images[wall])
	return true

func _paint() -> void:
	if not bool(state.brush) or int(state.charge)<=0: return
	var camera: Camera3D = game.play_camera
	var origin := camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(origin,origin-camera.global_basis.z*2.8,1)
	ray.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or not hit.collider.has_meta("paint_wall"): return
	var wall := int(hit.collider.get_meta("paint_wall"))
	var mesh := walls[wall]
	var quad := mesh.mesh as QuadMesh
	var local := mesh.to_local(hit.position)
	var x := clampi(floori((local.x/quad.size.x+.5)*COLS),0,COLS-1)
	var y := clampi(floori((.5-local.y/quad.size.y)*ROWS),0,ROWS-1)
	if _paint_cell(wall,x,y):
		state.charge = int(state.charge)-1
		if is_instance_valid(hand): hand.rotation.x = -.5+sin(float(state.painted.size())*1.8)*.22

func _refresh_client() -> void:
	if state.painted.size()<TOTAL or is_instance_valid(client): return
	client = Person.new()
	add_child(client)
	client.setup(945)
	client.remove_from_group("social_people")
	client.global_position = ROOM+Vector3(0,0,2.4)
	business._label(client,"Cliente",Vector3(0,2.03,0))
	business._notify("Cliente: ¡Quedó buenísima! Ven para pagarte.")
	_refresh_hand()

func _payment() -> void:
	if _stage()!=4 or state.painted.size()<TOTAL: return
	business._open("Cliente","Asere, me robaron el dinero al salir del cajero. No tengo efectivo. Tengo una goma de bicicleta en buen estado. ¿Te sirve como pago?")
	business._button("Aceptar la goma",_accept_wheel)

func _accept_wheel() -> void:
	if _stage()!=4 or state.painted.size()<TOTAL: return
	if not game.garage.receive_paint_wheel():
		business._notify("Libera las manos para recibir la goma.")
		return
	state.stage = 5
	game.garage._refresh_preview()
	state.brush = false
	state.charge = 0
	_save()
	business.ledger.add_message("Carlos","¡Trabajo terminado! Lleva esa goma al garaje. Es el comienzo de tu bicicleta.")
	_save()
	business.close()
	_refresh_hand()
	business._notify("MISIÓN CUMPLIDA · Una goma para empezar")
	_exit()

func _follow(delta: float) -> void:
	if not is_instance_valid(carlos): return
	var vehicle: bool = game.driving or game.taxi_riding
	if vehicle:
		carlos.hide()
		was_vehicle = true
		return
	var target: Vector3 = game.player.global_position-Vector3.UP*.86
	if was_vehicle:
		# Passenger ride uses existing taxi/van; find a free sidewalk exit.
		for offset in [Vector3(1.2,0,0),Vector3(-1.2,0,0),Vector3(0,0,1.2),Vector3(0,0,-1.2),Vector3.ZERO]:
			var ground := _ground(target+offset)
			if ground.is_empty() or not world.pedestrian_space_clear(carlos,ground.p,.7,false): continue
			carlos.global_position = ground.p
			carlos.show()
			was_vehicle = false
			break
		if was_vehicle: return
	if carlos.global_position.distance_to(customer.p)<1.3 and target.distance_to(customer.p)<6.0:
		carlos.animate(delta,false)
		return
	if carlos.global_position.distance_to(target)<1.9:
		carlos.animate(delta,false)
		return
	follow_clock -= delta
	if follow_clock<=0.0:
		follow_clock = 1.0
		var ground := _ground(target)
		if not ground.is_empty(): target = ground.p
		if world.pedestrian_segment_clear(carlos.global_position,target):
			follow_path = PackedVector3Array([target])
		else: follow_path = game.monte_pedestrians.route_between(carlos.global_position,target)
		follow_index = 0
	if follow_index>=follow_path.size(): return
	var next := follow_path[follow_index]
	var step := carlos.global_position.move_toward(next,delta*3.6)
	if world.pedestrian_segment_clear(carlos.global_position,step) and world.pedestrian_space_clear(carlos,step):
		if carlos.walk_to(next,delta,3.6): follow_index += 1

func tick(delta: float) -> void:
	if _stage()==0:
		if business.ledger.stage!=4: return
		call_wait += delta
		if call_wait<8.0 or business.modal_open() or game.driving or game.taxi_riding or game.bus_riding or game.garage.inside or game.garage.riding: return
		state.stage = 1
		business.ledger.add_message("Carlos","Llámame. Tengo un trabajo pintando una casa cerca de Flores y Estévez.")
		_save()
		business.phone_ring.play()
		open_call()
		return
	if _stage()==1 or _stage()==5: return
	if not inside and not is_instance_valid(carlos):
		locate_wait -= delta
		if locate_wait>0.0: return
		locate_wait = 5.0
		if not _locate(): return
		_spawn_carlos(home.p if _stage()<=3 else customer.p)
		_target(home if _stage()==2 else customer,"Casa de Carlos · Flores y Estévez" if _stage()==2 else "Casa del cliente")
	if inside:
		if business.modal_open() or _stage()!=4: return
		work_clock += delta
		brush_clock += delta
		paint_save_clock += delta
		if paint_dirty and paint_save_clock>=2.0:
			paint_dirty = false
			paint_save_clock = 0.0
			_save()
		if is_instance_valid(client): client.walk_to(ROOM+Vector3(1.4,0,1.7),delta,1.4)
		# Carlos paints one wall independently; the player finishes the rest.
		if work_clock>=2.0:
			work_clock = 0.0
			for y in range(ROWS):
				var done := false
				for x in range(COLS):
					if _paint_cell(2,x,y):
						done = true
						# Move Carlos along the wall as he finishes each section.
						var z := -2.45+float(x)*.70
						carlos.global_position = ROOM+Vector3(-3.0,0,z)
						var prop := room.get_node_or_null("CarlosBrush") as Node3D
						if prop!=null: prop.position = Vector3(-3.65,2.45-float(y)*.65,z)
						break
				if done: break
			if is_instance_valid(carlos): carlos.arms[1].rotation.x = -1.1 if state.painted.size()<TOTAL else 0.0
		if brush_clock>=.13 and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			brush_clock = 0.0
			_paint()
		if state.painted.size()>=TOTAL and paint_dirty:
			paint_dirty = false
			_save()
		_refresh_client()
	elif _stage() in [3,4] and not game.garage.inside and not game.bus_riding and not game.garage.riding:
		_follow(delta)
