extends Node3D
const Kit = preload("res://vehicle_kit.gd")
const MapView = preload("res://taxi_map.gd")
const Person = preload("res://street_person.gd")
const Bypass = preload("res://traffic_bypass.gd")
const HOUSE_COST := 5000
const VEHICLE_ORDER := ["bicicleta","triciclo","moto","carro"]
const ROOM := Vector3(0,110,0)
const BENCH := Vector3(3.1,0,-1.4)
const PAINT_COLORS := {"azul":"#4c92c9","amarillo":"#e9bf43","blanco":"#eeeae1","verde":"#83a88a","rosa":"#d6a4ad","gris":"#a3abb3","crema":"#e0d8c5"}
const PAINT_PRICE := 240
var home_walls: Dictionary = {}
var home_paint_images: Dictionary = {}
var home_paint_textures: Dictionary = {}
var home_paint_meshes: Dictionary = {}
var paint_station: Node3D
var paint_prop: Node3D
var paint_brush: Node3D
var paint_tip: MeshInstance3D
var paint_clock := 0.0
var paint_save_clock := 0.0
var home_paint_dirty := false
var paint_previous_first := true
const CAN_CAPACITY := 100
const BRUSH_LOAD := 10
const FLOOR_COLS := 56
const FLOOR_ROWS := 48
const PAPER_POS := Vector3(5.35,.042,3.9)
const BROOM_POS := Vector3(-2.9,0,5.25)
var paper: MeshInstance3D
var paper_image: Image
var paper_texture: ImageTexture
var resting_brush: Node3D
var resting_tip: MeshInstance3D
var resting_broom: Node3D
var held_broom: Node3D
var paint_cans: Dictionary = {}
var floor_image: Image
var floor_texture: ImageTexture
var dirt_clock := 0.0
var stroke_count := 0
const FURNITURE := {
	"sofa":{"name":"Sofá","p":[-4.6,0,1.6],"size":Vector3(1.9,.75,.85),"color":Color("#a3866d")},
	"mesa":{"name":"Mesa","p":[-3.5,0,-.7],"size":Vector3(1.20,.75,.8),"color":Color("#82644d")},
	"cama":{"name":"Cama","p":[-4.5,0,-4.1],"size":Vector3(1.5,.5,2.0),"color":Color("#a4b4bd")},
	"armario":{"name":"Armario","p":[-1.7,0,-5.0],"size":Vector3(.95,1.9,.5),"color":Color("#8b715b")}
}
var game
var world
var business
var state: Dictionary
var interior: Node3D
var furniture_nodes: Dictionary = {}
var preview: Node3D
var marker: Node3D
var exterior_label: Label3D
var carried_view: Node3D
var waypoint: Node3D
var rider: Node3D
var waypoint_point := Vector3.ZERO
var waypoint_label := ""
var waypoint_active := false
var inside := false
var previous_first := true
var riding := false
var ride_kind := ""
var ride_speed := 0.0
var owned: Dictionary = {}
var traffic: Array = []
var traffic_ready := false
var garage_near := false
var refresh_clock := 0.0
var last_save := 0.0

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	business = game.business
	var life: Dictionary = business.ledger.life_data
	if not life.has("garage"): life.garage = {}
	state = life.garage
	for key in {"house":false,"project":"", "projects":{},"inventory":{},"deliveries":[],"part":"","furniture":{},"held_furniture":"","parked":{},"trash":[]}.keys():
		if not state.has(key):
			var defaults := {"house":false,"project":"","projects":{},"inventory":{},"deliveries":[],"part":"","furniture":{},"held_furniture":"","parked":{},"trash":[]}
			state[key] = defaults[key]
	_prepare_progression()
	_restart_carlos_once()
	for key in {"paint_stock":{},"paint_order":{},"paint_carry":"","paint_active":"","paint_charge":0,"paint_cells":{},"wheel_tutorial":false}:
		if not state.has(key):
			state[key] = {"paint_stock":{},"paint_order":{},"paint_carry":"","paint_active":"","paint_charge":0,"paint_cells":{},"wheel_tutorial":false}[key]
	# A reload begins outdoors: return unused brush paint to the saved can.
	var active_color := String(state.paint_active)
	if int(state.get("house_tools_version",0))<1:
		if PAINT_COLORS.has(active_color): state.paint_stock[active_color] = int(state.paint_stock.get(active_color,0))+maxi(0,int(state.paint_charge))
		state.paint_active = ""
		state.paint_charge = 0
		state.house_tools_version = 1
	state.paint_tool = ""
	if not state.has("paper_color"): state.paper_color = ""
	if not state.has("floor_marks"): state.floor_marks = {}
	if not state.has("paper_marks"): state.paper_marks = []
	if state.paper_marks.is_empty() and PAINT_COLORS.has(String(state.paper_color)): state.paper_marks.append(String(state.paper_color))
	if bool(state.projects.get("bicicleta",{}).get("wheel_a",false)) or int(state.vehicle_sales.get("bicicleta",0))>0: state.wheel_tutorial = true
	for id in FURNITURE:
		if not state.furniture.has(id): state.furniture[id] = {"p":FURNITURE[id].p.duplicate(),"removed":false}
	# Existing GPS residence belongs to the player; no purchase or exterior sign.
	if not world.garage_home_site.is_empty(): state.house = true
	for site in world.parts_sites:
		var person := Person.new()
		add_child(person)
		person.setup(411 if String(site.id)=="parts_yoyi" else 414)
		var c: Vector3 = site.center
		var basis: Basis = site.basis
		person.global_position = c+basis*Vector3(0,.10,-.8)
		person.rotation.y = basis.get_euler().y
		person.social_context = "worker"
		business._label(person,"Yoyi" if String(site.id)=="parts_yoyi" else "Ernesto",Vector3(0,2,0))
	_build_interior()
	carried_view = Node3D.new()
	game.play_camera.add_child(carried_view)
	carried_view.position = Vector3(.30,-.35,-.88)
	_refresh_carried()
	waypoint = Node3D.new()
	add_child(waypoint)
	business._box(waypoint,Vector3(0,.22,0),Vector3(.13,.40,.13),Color("#f0c85f"))
	var pointer: MeshInstance3D = business._box(waypoint,Vector3.ZERO,Vector3(.28,.28,.12),Color("#f0c85f"))
	pointer.rotation.z = PI*.25
	waypoint.hide()
	var gps: Dictionary = state.get("gps",{})
	if not gps.is_empty():
		_set_waypoint(Vector3(float(gps.x),0,float(gps.z)),String(gps.label))
	for kind in state.parked:
		if Kit.KITS.has(kind) and _unlocked(String(kind)) and _complete(String(kind)):
			var p: Dictionary = state.parked[kind]
			var at := Vector3(float(p.x),float(p.y),float(p.z))
			if world.street_geometry.point_on_road(at):
				var body := Kit.body(self,String(kind))
				body.global_position = at
				body.rotation.y = float(p.angle)
				owned[kind] = body
	_refresh_preview()
	_save()

# One-time migration: reset only the old bicycle, not the wallet or other
# saved projects. Higher projects remain locked until prior sales.
func _prepare_progression() -> void:
	if int(state.get("progression_version",0))>=1: return
	state.progression_version = 1
	state.vehicle_level = 0
	state.vehicle_sales = {}
	state.upgrades = {}
	state.listing = {}
	state.projects.erase("bicicleta")
	state.parked.erase("bicicleta")
	for token in state.inventory.keys():
		if String(token).begins_with("bicicleta:"): state.inventory.erase(token)
	for i in range(state.deliveries.size()-1,-1,-1):
		if String(state.deliveries[i].token).begins_with("bicicleta:"): state.deliveries.remove_at(i)
	if not String(state.part).is_empty():
		var held := String(state.part)
		if not held.begins_with("bicicleta:"): state.inventory[held] = int(state.inventory.get(held,0))+1
		state.part = ""
	if String(state.get("wanted","")).begins_with("bicicleta:"): state.wanted = ""
	state.project = "bicicleta"

# Replay requested for the revised painting mission. Apply once to each
# existing save, before preview/parked vehicles are instantiated.
func _restart_carlos_once() -> void:
	var life: Dictionary = business.ledger.life_data
	if int(life.get("carlos_replay_version",0))>=1: return
	life.carlos_replay_version = 1
	var old: Dictionary = life.get("carlos_paint",{})
	var old_stage := int(old.get("stage",0))
	if old_stage==0: return
	var bike_complete := _complete("bicicleta")
	var already_sold := int(state.get("vehicle_sales",{}).get("bicicleta",0))>0
	var advanced := int(state.get("vehicle_level",0))>0
	# Never dismantle a completed or sold vehicle, or lock earned tiers.
	var preserve_unlock := old_stage>=5 and (bike_complete or already_sold or advanced)
	var fresh := {"stage":0,"painted":{},"brush":false,"charge":0,"color":"blue","paint_version":2,"home_location_version":2,"replay_unlocked":preserve_unlock}
	for key in ["home","customer"]:
		if old.has(key): fresh[key] = old[key]
	life.carlos_paint = fresh
	if old_stage>=5:
		if String(state.part)=="bicicleta:wheel_a": state.part = ""
		if not preserve_unlock and state.projects.has("bicicleta"):
			state.projects.bicicleta.erase("wheel_a")
		if not preserve_unlock: state.wheel_tutorial = false
	var gps: Dictionary = state.get("gps",{})
	var label_value := String(gps.get("label","")).to_lower()
	if label_value.contains("carlos") or label_value.contains("cliente") or (old_stage>=5 and label_value=="mi garaje"):
		state.gps = {}
	print("MyCity: misión de Carlos reiniciada una vez; saldo y demás progreso conservados.")
	_save()

func _unlocked(kind: String) -> bool:
	var index := VEHICLE_ORDER.find(kind)
	var mission: Dictionary = business.ledger.life_data.get("carlos_paint",{})
	return index>=0 and index<=int(state.get("vehicle_level",0)) and (int(mission.get("stage",0))>=5 or bool(mission.get("replay_unlocked",false)))

func _listed(kind: String) -> bool:
	return String(state.get("listing",{}).get("kind",""))==kind

func _progression_hint() -> String:
	if not _unlocked("bicicleta"): return "Completa el trabajo de pintura con Carlos para recibir tu primera goma."
	var level := clampi(int(state.vehicle_level),0,VEHICLE_ORDER.size()-1)
	return "Proyecto desbloqueado: "+String(Kit.KITS[VEHICLE_ORDER[level]].name)

func receive_paint_wheel() -> bool:
	if not _free_hands(): return false
	state.project = "bicicleta"
	if not state.projects.has("bicicleta"): state.projects.bicicleta = {}
	state.part = "bicicleta:wheel_a"
	# A replay always allows the physical handoff, even if the player
	# already has this wheel installed in a completed bicycle.
	state.wheel_tutorial = false
	_refresh_carried()
	_refresh_preview()
	return true

func _upgrade_vehicle(kind: String) -> void:
	if not _unlocked(kind) or not _complete(kind) or _listed(kind) or not inside: return
	var upgrades: Dictionary = state.upgrades
	var level := int(upgrades.get(kind,0))
	if level>=2: return
	var price := roundi(float(Kit.total(kind))*.12)
	if business.ledger.cash<price: return
	upgrades[kind] = level+1
	business.ledger.spend(price)
	_project_menu()

func _sale_price(kind: String) -> int:
	return roundi(float(Kit.total(kind))*(1.25+.15*float(state.upgrades.get(kind,0))))

func _list_vehicle(kind: String) -> void:
	if not _unlocked(kind) or not _complete(kind) or riding or not state.listing.is_empty(): return
	business._open("Facebook Marketplace (juego)","Publicar "+String(Kit.KITS[kind].name)+" por "+str(_sale_price(kind))+" CUP. Cuando un comprador acepte, se entregará el vehículo y se desbloqueará el siguiente proyecto.")
	business._button("Publicar vehículo",_confirm_listing.bind(kind))
	business._button("Cancelar",_project_menu)

func _confirm_listing(kind: String) -> void:
	if not _unlocked(kind) or not _complete(kind) or riding or not state.listing.is_empty(): return
	state.listing = {"kind":kind,"price":_sale_price(kind),"remaining":25.0}
	_save()
	business.close()
	business._notify("Vehículo publicado en Marketplace. Esperando comprador.")

func _tick_listing(delta: float) -> void:
	var listing: Dictionary = state.listing
	if listing.is_empty(): return
	listing.remaining = float(listing.remaining)-delta
	if float(listing.remaining)>0.0: return
	var kind := String(listing.kind)
	if riding and ride_kind==kind: return
	if not _complete(kind):
		state.listing = {}
		_save()
		return
	var price := int(listing.price)
	if owned.has(kind):
		var body: CharacterBody3D = owned[kind]
		if is_instance_valid(body):
			body.collision_layer = 0
			body.queue_free()
		owned.erase(kind)
	state.parked.erase(kind)
	state.projects.erase(kind)
	state.upgrades.erase(kind)
	state.vehicle_sales[kind] = int(state.vehicle_sales.get(kind,0))+1
	var next := mini(VEHICLE_ORDER.size()-1,VEHICLE_ORDER.find(kind)+1)
	state.vehicle_level = maxi(int(state.vehicle_level),next)
	state.project = VEHICLE_ORDER[int(state.vehicle_level)]
	state.listing = {}
	business.ledger.cash += price
	business.ledger.revenue += price
	business.ledger.add_message("Marketplace","Vendiste "+String(Kit.KITS[kind].name)+" por "+str(price)+" CUP. "+_progression_hint())
	_refresh_preview()
	_save()
	business._notify("Vehículo vendido · +"+str(price)+" CUP")

func _save() -> void:
	business.ledger.save_game()

func _solid(root: Node3D,p: Vector3,size: Vector3,color: Color,layer: int = 1) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	root.add_child(body)
	body.position = p
	business._box(body,Vector3.ZERO,size,color)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	return body

func _build_interior() -> void:
	interior = Node3D.new()
	add_child(interior)
	interior.position = ROOM
	var floor_color := Color("#b8ada1")
	var wall := Color("#e0d8c5")
	_solid(interior,Vector3(0,-.10,0),Vector3(14,.20,12),floor_color,2)
	_solid(interior,Vector3(0,3.05,0),Vector3(14,.18,12),wall)
	_home_wall("west",Vector3(-6.9,1.5,0),Vector3(.2,3.0,12),wall,true,false)
	_home_wall("east",Vector3(6.9,1.5,0),Vector3(.2,3.0,12),wall,false,true)
	_home_wall("north",Vector3(0,1.5,-5.9),Vector3(14,3,.2),wall,true,false)
	_home_wall("south",Vector3(0,1.5,5.9),Vector3(14,3,.2),wall,false,true)
	_home_wall("partition_a",Vector3(-.1,1.5,-4.15),Vector3(.16,3,3.5),wall,true,true)
	_home_wall("partition_b",Vector3(-.1,1.5,3.9),Vector3(.16,3,3.9),wall,true,true)
	_home_wall("bedroom",Vector3(-4.7,1.5,-2.3),Vector3(4.4,3,.15),wall,true,true)
	business._box(interior,Vector3(-.7,1.10,5.76),Vector3(1.2,2.2,.10),Color("#685144"))
	business._label(interior,"SALIR",Vector3(-.7,2.4,5.68),Color("#f9e9d2")).rotation.y = PI
	business._box(interior,Vector3(3.2,.012,-1.4),Vector3(5.5,.025,5.2),Color("#777e7f"))
	business._label(interior,"GARAJE",Vector3(3.1,2.65,-5.70),Color("#d2e6f2"))
	for x in [-3.7,3.7]:
		var light := OmniLight3D.new()
		interior.add_child(light)
		light.position = Vector3(float(x),2.7,0)
		light.omni_range = 10.0
		light.light_energy = 1.6
	marker = Node3D.new()
	interior.add_child(marker)
	marker.position = BENCH+Vector3.UP*2.35
	business._box(marker,Vector3(0,.18,0),Vector3(.13,.42,.13),Color("#79df81"))
	var arrow: MeshInstance3D = business._box(marker,Vector3(0,-.07,0),Vector3(.28,.28,.12),Color("#79df81"))
	arrow.rotation.z = PI*.25
	preview = Node3D.new()
	interior.add_child(preview)
	preview.position = BENCH
	paint_station = Node3D.new()
	interior.add_child(paint_station)
	paint_station.position = Vector3.ZERO
	_build_house_tools()
	_refresh_paint_station()
	for id in FURNITURE: _refresh_furniture(String(id))
	_refresh_preview()

func _refresh_furniture(id: String) -> void:
	if furniture_nodes.has(id):
		var old: Node3D = furniture_nodes[id]
		interior.remove_child(old)
		old.queue_free()
		furniture_nodes.erase(id)
	var data: Dictionary = state.furniture[id]
	if bool(data.removed) or String(state.held_furniture)==id: return
	var spec: Dictionary = FURNITURE[id]
	var p: Array = data.p
	var size: Vector3 = spec.size
	var body := _solid(interior,Vector3(float(p[0]),size.y*.5,float(p[2])),size,spec.color)
	body.set_meta("furniture_id",id)
	furniture_nodes[id] = body
	if id=="sofa":
		business._box(body,Vector3(0,.48,-.30),Vector3(1.90,.63,.22),spec.color)
	elif id=="cama":
		business._box(body,Vector3(0,.29,0),Vector3(1.42,.16,1.94),Color("#e4e1d9"))
		business._box(body,Vector3(0,.42,-.68),Vector3(.70,.16,.40),Color("#f2eee5"))

func _refresh_carried() -> void:
	if carried_view==null: return
	for child in carried_view.get_children():
		carried_view.remove_child(child)
		child.queue_free()
	var id := String(state.held_furniture)
	if FURNITURE.has(id):
		business._box(carried_view,Vector3.ZERO,Vector3(.50,.36,.44),FURNITURE[id].color)
	elif not String(state.paint_carry).is_empty():
		_make_paint_can(carried_view,String(state.paint_carry))
	elif not String(state.part).is_empty():
		var split := String(state.part).split(":")
		if split.size()==2 and String(split[1]).begins_with("wheel"):
			var wheel := CylinderMesh.new()
			wheel.top_radius = .28
			wheel.bottom_radius = .28
			wheel.height = .10
			var mesh := MeshInstance3D.new()
			mesh.mesh = wheel
			mesh.rotation.z = PI*.5
			mesh.material_override = Kit._mat(Color("#333739"),false)
			carried_view.add_child(mesh)
		else: business._box(carried_view,Vector3.ZERO,Vector3(.38,.30,.42),Color("#b19672"))

func _project() -> Dictionary:
	var kind := String(state.project)
	if not state.projects.has(kind): return {}
	return state.projects[kind]

func _complete(kind: String) -> bool:
	if not Kit.KITS.has(kind) or not state.projects.has(kind): return false
	var installed: Dictionary = state.projects[kind]
	for key in Kit.KITS[kind].parts:
		if not bool(installed.get(key,false)): return false
	return true

func _refresh_preview() -> void:
	for child in preview.get_children():
		preview.remove_child(child)
		child.queue_free()
	var kind := String(state.project)
	if Kit.KITS.has(kind) and _unlocked(kind): Kit.build(preview,kind,_project())
	preview.visible = not owned.has(kind)

func _free_hands() -> bool:
	if game.backpack!=null and not game.backpack.empty_hands(): return false
	return business.ledger.carry.is_empty() and business.life.state.meal.is_empty() and (game.monte_services==null or game.monte_services.player_bag==null) and String(state.part).is_empty() and String(state.held_furniture).is_empty() and String(state.get("paint_carry","")).is_empty() and String(state.get("paint_tool","")).is_empty()

func _home_menu() -> void:
	business._open("Comprar vivienda","Casa con sala, dormitorio y garaje independiente.\nPrecio: %d CUP" % HOUSE_COST)
	business._button("Comprar",_buy_home,business.ledger.cash<HOUSE_COST)
	business._button("Cerrar",business.close)

func _buy_home() -> void:
	if bool(state.house): return
	if business.ledger.cash<HOUSE_COST: return
	state.house = true
	business.ledger.spend(HOUSE_COST)
	if exterior_label!=null: exterior_label.text = "MI CASA"
	business.close()
	business._notify("Ya tienes tu casa. Pulsa E en la puerta.")

func _enter() -> void:
	if not bool(state.house): return
	inside = true
	garage_near = false
	previous_first = game.first_person
	game.player.global_position = ROOM+Vector3(-.7,.86,4.85)
	game.player.velocity = Vector3.ZERO
	game.yaw = 0.0
	game.pitch = -.12
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()

func _exit() -> void:
	var site: Dictionary = world.garage_home_site
	if site.is_empty(): return
	var basis: Basis = site.basis
	var door: Vector3 = site.door
	var space := get_world_3d().direct_space_state
	var destination := Vector3.ZERO
	var found := false
	for offset in [Vector2(0,.75),Vector2(-.75,.90),Vector2(.75,.90),Vector2(0,1.50),Vector2(-.5,1.80),Vector2(.5,1.80),Vector2(0,2.25)]:
		var at: Vector3 = door+basis.x*offset.x+basis.z*offset.y
		var ground := space.intersect_ray(PhysicsRayQueryParameters3D.create(at+Vector3.UP*1.8,at-Vector3.UP*.4,1|2))
		if ground.is_empty() or ground.normal.y<.65: continue
		var point: Vector3 = ground.position+Vector3.UP*.86
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = game.player_shape.shape
		q.transform = Transform3D(Basis.IDENTITY,point)
		q.collision_mask = 1|4|8|32
		q.exclude = [game.player.get_rid()]
		if space.intersect_shape(q,1).is_empty():
			destination = point
			found = true
			break
	if not found:
		business._notify("La puerta está bloqueada. Espera un momento.")
		return
	inside = false
	_stop_home_paint()
	game.player.global_position = destination
	game.player.velocity = Vector3.ZERO
	game.yaw = atan2(basis.z.x,basis.z.z)+PI
	game.pitch = -.12
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game.first_person = previous_first
	game._apply_camera_mode()

func _aimed_furniture() -> String:
	var cam: Camera3D = game.play_camera
	var actor: CharacterBody3D = game.player
	var ray := PhysicsRayQueryParameters3D.create(cam.global_position,cam.global_position-cam.global_transform.basis.z*6.0,1)
	ray.exclude = [actor.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty(): return ""
	var obj := hit.collider as Node3D
	if obj!=null and obj.has_meta("furniture_id") and obj.global_position.distance_to(actor.global_position)<2.6: return String(obj.get_meta("furniture_id"))
	return ""

func _place_furniture() -> void:
	var id := String(state.held_furniture)
	if not FURNITURE.has(id): return
	var p: Vector3 = game.player.global_position-ROOM
	var forward: Vector3 = -game.play_camera.global_transform.basis.z
	forward.y = 0.0
	p += forward.normalized()*1.8
	p.y = 0.0
	var size: Vector3 = FURNITURE[id].size
	if absf(p.x)+size.x*.5>6.65 or absf(p.z)+size.z*.5>5.65 or p.distance_to(BENCH)<2.6:
		business._notify("No hay espacio para colocar el mueble aquí.")
		return
	var shape := BoxShape3D.new()
	shape.size = size
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY,ROOM+p+Vector3.UP*(size.y*.5+.03))
	q.collision_mask = 1
	if not get_world_3d().direct_space_state.intersect_shape(q,1).is_empty():
		business._notify("Hay un objeto en ese lugar.")
		return
	state.furniture[id].p = [p.x,0,p.z]
	state.held_furniture = ""
	_refresh_furniture(id)
	_refresh_carried()
	_save()

func _vendor_at(at: Vector3) -> Dictionary:
	for site in world.parts_sites:
		var c: Vector3 = site.center
		var basis: Basis = site.basis
		var local := basis.inverse()*(at-c)
		if absf(local.x)<3.0 and local.z>.55 and local.z<4.7 and absf(local.y)<2.0: return site
	return {}

func _nearest_bin(at: Vector3) -> Dictionary:
	if game.monte_services==null: return {}
	for site in game.monte_services.sites:
		var p: Vector3 = site.curb
		if at.distance_to(p)<3.0: return site
	return {}

func _aimed_home(at: Vector3) -> bool:
	if world.garage_home_site.is_empty(): return false
	var site: Dictionary = world.garage_home_site
	var door: Vector3 = site.door
	var basis: Basis = site.basis
	if at.distance_to(door)>3.5 or (at-door).dot(basis.z)<-.12: return false
	var cam: Camera3D = game.play_camera
	var origin := cam.global_position
	var direction := -cam.global_transform.basis.z
	# Intersect the real door plane instead of projecting its centre
	# onto an oblique view ray (which also selected adjacent people).
	var inverse := basis.inverse()
	var local_origin := inverse*(origin-door)
	var local_direction := inverse*direction
	if local_direction.z>=-.001: return false
	var depth := -local_origin.z/local_direction.z
	if depth<=0.0 or depth>8.0: return false
	var hit := local_origin+local_direction*depth
	var half_width := float(site.get("door_width",1.15))*.5
	if absf(hit.x)>half_width or hit.y<.03 or hit.y>2.20: return false
	# Stop before the thin facade itself, but reject intervening objects.
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+direction*maxf(.01,depth-.12),1|4|8|16|32)
	ray.exclude = [game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func action_text(at: Vector3) -> String:
	if riding: return "[E] Bajar detenido"
	if inside:
		if at.distance_to(ROOM+Vector3(-.7,.86,5.25))<1.55: return "[E] Salir de casa"
		var tool_action := _house_tool_action(at)
		if not tool_action.is_empty(): return tool_action
		if _aimed_project(at): return "[E] Mejorar / ensamblar "+String(Kit.KITS.get(String(state.project),{}).get("name","vehículo"))
		if not String(state.held_furniture).is_empty(): return "[E] Colocar mueble · llévalo afuera para desechar"
		var id := _aimed_furniture()
		return "[E] Mover "+String(FURNITURE[id].name) if not id.is_empty() else ""
	if not String(state.held_furniture).is_empty() and not _nearest_bin(at).is_empty(): return "[E] Desechar mueble"
	if _aimed_home(at): return "[E] Entrar a mi casa"
	if not _vendor_at(at).is_empty(): return "[E] Comprar repuestos"
	for kind in owned:
		var body: CharacterBody3D = owned[kind]
		if at.distance_to(body.global_position+Vector3.UP*.6)<2.8 and not _listed(String(kind)): return "[E] Montar "+String(Kit.KITS[kind].name)
	return ""

func interact(at: Vector3) -> bool:
	if riding:
		if absf(ride_speed)<.6: _dismount()
		else: business._notify("Detén el vehículo para bajar.")
		return true
	if inside:
		if at.distance_to(ROOM+Vector3(-.7,.86,5.25))<1.55:
			_exit()
		elif not business.life.state.meal.is_empty(): return false
		elif _house_tool_interact(at): pass
		elif _aimed_project(at):
			if _unlocked(String(state.project)):
				if not state.projects.has(String(state.project)): state.projects[String(state.project)] = {}
				_project_menu()
			else: _garage_menu()
		elif not String(state.held_furniture).is_empty(): _place_furniture()
		else:
			var id := _aimed_furniture()
			if not id.is_empty() and _free_hands():
				state.held_furniture = id
				_refresh_furniture(id)
				_refresh_carried()
				_save()
		return true
	if not String(state.held_furniture).is_empty():
		var bin := _nearest_bin(at)
		if not bin.is_empty():
			var id := String(state.held_furniture)
			if game.monte_services.add_discarded_furniture(bin,id,FURNITURE[id].size,FURNITURE[id].color):
				state.furniture[id].removed = true
				state.held_furniture = ""
				_refresh_carried()
				_save()
				business._notify("Mueble dejado en el basurero. El camión podrá recogerlo.")
			return true
	if _aimed_home(at):
		_enter()
		return true
	var site := _vendor_at(at)
	if not site.is_empty():
		_vendor_menu(site)
		return true
	for kind in owned:
		var body: CharacterBody3D = owned[kind]
		if at.distance_to(body.global_position+Vector3.UP*.6)<2.8 and _free_hands() and not _listed(String(kind)):
			_mount(String(kind))
			return true
	return false

func _garage_menu() -> void:
	if not inside: return
	if not String(state.held_furniture).is_empty():
		business._notify("Primero coloca el mueble o llévalo al basurero.")
		return
	business._open("Mi garaje",_progression_hint()+"\nLas piezas instaladas se ven sólidas; las faltantes, transparentes.")
	for kind in Kit.KITS:
		var name_value := String(Kit.KITS[kind].name)
		var done := _complete(String(kind))
		business._button("%s · %s" % [name_value,"Bloqueado" if not _unlocked(String(kind)) else ("Completo" if done else "%d CUP en piezas" % Kit.total(String(kind)))],_select.bind(String(kind)),not _unlocked(String(kind)))
	business._button("Cerrar",business.close)

func _select(kind: String) -> void:
	if not inside or not _unlocked(kind): return
	state.project = kind
	if not state.projects.has(kind): state.projects[kind] = {}
	_refresh_preview()
	_save()
	_project_menu()

func _project_menu() -> void:
	if not inside: return
	var kind := String(state.project)
	if not Kit.KITS.has(kind) or not _unlocked(kind): return
	if _complete(kind):
		business._open(String(Kit.KITS[kind].name),"¡Vehículo terminado!")
		business._button("Sacar a la calle / montar",_launch.bind(kind),_listed(kind))
		var level := int(state.upgrades.get(kind,0))
		var price := roundi(float(Kit.total(kind))*.12)
		business._button("Mejorar rendimiento · %d/2 · %d CUP" % [level,price],_upgrade_vehicle.bind(kind),level>=2 or not inside or _listed(kind) or business.ledger.cash<price)
		business._button("Publicado · esperando comprador" if _listed(kind) else "Vender en Facebook · %d CUP" % _sale_price(kind),_list_vehicle.bind(kind),not state.listing.is_empty())
		business._button("Otros proyectos",_garage_menu)
		business._button("Cerrar",business.close)
		return
	var installed := _project()
	var count := 0
	for key in installed:
		if bool(installed[key]): count += 1
	business._open(String(Kit.KITS[kind].name),"%d de %d piezas instaladas.\nBilletera: %d CUP" % [count,Kit.KITS[kind].parts.size(),business.ledger.cash])
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390,240)
	business.content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for key in Kit.KITS[kind].parts:
		var token := kind+":"+String(key)
		var caption := String(Kit.PART_NAMES[key])
		var button := Button.new()
		var ready := int(state.inventory.get(token,0))>0 or String(state.part)==token
		button.text = caption+" · "+("Instalada" if bool(installed.get(key,false)) else ("Instalar" if ready else "%d CUP" % int(Kit.KITS[kind].parts[key])))
		button.disabled = bool(installed.get(key,false))
		button.pressed.connect(_part_menu.bind(kind,String(key)))
		list.add_child(button)
	business._button("Otros proyectos",_garage_menu)
	business._button("Cerrar",business.close)

func _part_menu(kind: String,key: String) -> void:
	if not inside or game.player.global_position.distance_to(ROOM+BENCH)>3.5 or not _unlocked(kind): return
	var token := kind+":"+key
	if bool(state.projects[kind].get(key,false)): return
	if String(state.part)==token or int(state.inventory.get(token,0))>0:
		if not inside or game.player.global_position.distance_to(ROOM+BENCH)>3.5:
			business._notify("Instala la pieza físicamente en el garaje.")
			return
		if String(state.part)==token: state.part = ""
		else: state.inventory[token] = int(state.inventory[token])-1
		state.projects[kind][key] = true
		_refresh_preview()
		_refresh_carried()
		_save()
		_project_menu()
		return
	for delivery in state.deliveries:
		if String(delivery.token)==token:
			business._notify("La pieza está en camino.")
			return
	var price := int(Kit.KITS[kind].parts[key])
	business._open(String(Kit.PART_NAMES[key]),"%d CUP · %s" % [price,Kit.KITS[kind].name])
	business._button("Pedir por Facebook (juego) · %d CUP" % (price+100),_order_part.bind(kind,key),business.ledger.cash<price+100)
	business._button("Ir a buscarla · %d CUP" % price,_find_part.bind(kind,key),world.parts_sites.is_empty())
	business._button("Volver",_project_menu)

func _order_part(kind: String,key: String,from_phone: bool = false) -> void:
	if not _unlocked(kind): return
	if not bool(state.house):
		business._notify("Necesitas una vivienda con garaje para recibir repuestos.")
		return
	var token := kind+":"+key
	var price := int(Kit.KITS[kind].parts[key])+100
	if business.ledger.cash<price or _part_already_available(kind,key): return
	state.deliveries.append({"token":token,"remaining":35.0})
	business.ledger.spend(price)
	business.ledger.add_message("Marketplace","Tu repuesto está en camino al garaje.")
	_save()
	if from_phone: _phone_parts(kind)
	else: _project_menu()

func _seller(kind: String,key: String) -> Dictionary:
	if world.parts_sites.is_empty(): return {}
	var index := 1 if key=="drive" or key=="battery" or kind=="carro" else 0
	return world.parts_sites[mini(index,world.parts_sites.size()-1)]

func _find_part(kind: String,key: String) -> void:
	if not _unlocked(kind): return
	var site := _seller(kind,key)
	if site.is_empty(): return
	state["wanted"] = kind+":"+key
	_save()
	_show_map(site.road,String(site.name))

func _set_waypoint(point: Vector3,label_value: String) -> void:
	waypoint_active = true
	waypoint_point = point
	waypoint_label = label_value
	state.gps = {"x":point.x,"z":point.z,"label":label_value}
	game.taxis.set_garage_destination(point,label_value)

func _show_map(point: Vector3,label_value: String) -> void:
	_set_waypoint(point,label_value)
	_save()
	business._open("Mapa · "+label_value,"Puedes caminar o elegir este destino al tomar un taxi.")
	var map := MapView.new()
	business.content.add_child(map)
	map.custom_minimum_size = Vector2(390,240)
	map.setup(world.geography)
	var origin_point: Vector3 = world.garage_home_site.road if inside else game.player.global_position
	map.reset(origin_point)
	map.show_route([],point)
	map.center = Vector2((origin_point.x+point.x)*.5,(origin_point.z+point.z)*.5)
	map.zoom = clampf(280.0/maxf(100.0,origin_point.distance_to(point)),.15,1.0)
	map.queue_redraw()
	business._button("Cerrar",business.close)

func open_phone_market() -> void:
	business._open("Facebook Marketplace (juego)",_progression_hint()+"\nCompra repuestos. Instálalos mirando el vehículo en tu garaje.")
	for kind in Kit.KITS:
		business._button(String(Kit.KITS[kind].name)+(" · Bloqueado" if not _unlocked(String(kind)) else ""),_phone_parts.bind(String(kind)),not _unlocked(String(kind)))
	if game.yordi_mission!=null and game.yordi_mission.can_list():
		business._button("Publicar PS5 de Yordi",game.yordi_mission.open_listing)
	business._button("Comprar pintura para mi casa",_paint_shop.bind(false))
	business._button("Mi casa / mapa",_home_map,world.garage_home_site.is_empty())
	business._button("Inicio",business.open_phone_home)

func _part_already_available(kind: String,key: String) -> bool:
	var token := kind+":"+key
	if bool(state.projects.get(kind,{}).get(key,false)) or String(state.part)==token or int(state.inventory.get(token,0))>0: return true
	for delivery in state.deliveries:
		if String(delivery.token)==token: return true
	return false

func _phone_parts(kind: String) -> void:
	if not _unlocked(kind): return
	business._open("Comprar · "+String(Kit.KITS[kind].name),"Los pedidos llegan al garaje. Aquí no se instalan piezas.")
	for key in Kit.KITS[kind].parts:
		var price := int(Kit.KITS[kind].parts[key])+100
		var available := _part_already_available(kind,String(key))
		business._button(String(Kit.PART_NAMES[key])+(" · Ya disponible" if available else " · %d CUP" % price),_order_part.bind(kind,String(key),true),available or business.ledger.cash<price)
	business._button("Volver",open_phone_market)

func _home_map() -> void:
	if not world.garage_home_site.is_empty(): _show_map(world.garage_home_site.road,"Mi casa")

func _vendor_menu(site: Dictionary) -> void:
	var token := String(state.get("wanted",""))
	var split := token.split(":")
	business._open(String(site.name),"Repuestos para tus proyectos. Selecciona la pieza en el garaje para localizar su vendedor.")
	if split.size()==2 and Kit.KITS.has(split[0]) and Kit.KITS[split[0]].parts.has(split[1]):
		var kind := String(split[0])
		var key := String(split[1])
		if String(_seller(kind,key).get("id",""))==String(site.id):
			business._button("Comprar "+String(Kit.PART_NAMES[key])+" · %d CUP" % int(Kit.KITS[kind].parts[key]),_buy_part.bind(kind,key),not _free_hands() or business.ledger.cash<int(Kit.KITS[kind].parts[key]))
	business._button("Comprar pintura",_paint_shop.bind(true))
	business._button("Cerrar",business.close)

func _buy_part(kind: String,key: String) -> void:
	if not _unlocked(kind): return
	if not _free_hands(): return
	var price := int(Kit.KITS[kind].parts[key])
	if business.ledger.cash<price: return
	state.part = kind+":"+key
	state["wanted"] = ""
	business.ledger.spend(price)
	waypoint_active = false
	state.gps = {}
	game.taxis.set_garage_destination(Vector3.ZERO,"")
	_save()
	_refresh_carried()
	business.close()
	business._notify("Lleva la pieza a tu garaje y selecciona Instalar.")

func _spawn(kind: String) -> CharacterBody3D:
	if world.garage_home_site.is_empty(): return null
	var site: Dictionary = world.garage_home_site
	var edge: Dictionary = site.edge
	var a: Vector3 = edge.a
	var b: Vector3 = edge.b
	var direction := (b-a).normalized()
	var right := Vector3(-direction.z,0,direction.x)
	var road: Vector3 = site.road
	var spec: Dictionary = Kit.KITS[kind]
	for sign_value in [-1.0,1.0]:
		var d := direction*float(sign_value)
		var lane: Vector3 = right*float(sign_value)*world.geography.lane_distance(edge,float(spec.width))
		for shift in [0.0,4.0,-4.0,8.0,-8.0,12.0,-12.0]:
			var p := road+lane+direction*float(shift)
			if not Bypass._on_road(world.street_geometry,p,d,float(spec.width),float(spec.length)): continue
			var shape := BoxShape3D.new()
			shape.size = Vector3(float(spec.width)+.2,float(spec.height),float(spec.length)+.2)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shape
			q.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p+Vector3.UP*(float(spec.height)*.5+.08))
			q.collision_mask = 1|4|8|32
			if not get_world_3d().direct_space_state.intersect_shape(q,1).is_empty(): continue
			var body := Kit.body(self,kind)
			body.global_position = p+Vector3.UP*.055
			body.rotation.y = atan2(d.x,d.z)
			return body
	return null

func _launch(kind: String) -> void:
	if not inside or not _unlocked(kind) or _listed(kind) or not _complete(kind) or not _free_hands(): return
	if not owned.has(kind):
		var body := _spawn(kind)
		if body==null:
			business._notify("La calle está ocupada. Inténtalo de nuevo.")
			return
		owned[kind] = body
		_store_park(kind)
	elif (owned[kind] as Node3D).global_position.distance_to(world.garage_home_site.road)>16.0:
		business._notify("El vehículo está estacionado fuera de casa; búscalo donde lo dejaste.")
		return
	business.close()
	inside = false
	_refresh_preview()
	_mount(kind)

# Solve a static two-link pose once, reusing existing meshes.
func _rider_bend(start: Vector3,finish: Vector3,upper: float,lower: float,preferred: Vector3) -> Vector3:
	var axis := finish-start
	var distance := maxf(.001,axis.length())
	axis = axis/distance
	var reach := minf(distance,upper+lower-.001)
	var along := clampf((upper*upper-lower*lower+reach*reach)/(2.0*reach),0.0,upper)
	var offset := sqrt(maxf(0.0,upper*upper-along*along))
	var bend := preferred-axis*preferred.dot(axis)
	if bend.length_squared()<.001: bend = Vector3.RIGHT-axis*axis.x
	return start+axis*along+bend.normalized()*offset

func _rider_segment(person: Node3D,part: MeshInstance3D,start: Vector3,finish: Vector3) -> void:
	var dims := part.scale
	part.reparent(person,false)
	var axis := finish-start
	if axis.length_squared()<.00001: return
	part.position = (start+finish)*.5
	part.rotation = Basis(Quaternion(Vector3.UP,axis.normalized())).get_euler()
	part.scale = Vector3(dims.x,axis.length()+.025,dims.z)

func _rider_endpoint(person: Node3D,part: MeshInstance3D,at: Vector3) -> void:
	var dims := part.scale
	part.reparent(person,false)
	part.position = at
	part.rotation = Vector3.ZERO
	part.scale = dims

func _pose_moto(person: Person,body: CharacterBody3D) -> void:
	person.position = Vector3(0,.286,-.32)
	var torso := Node3D.new()
	person.add_child(torso)
	torso.position = Vector3(0,.88,0)
	for node in person.get_children():
		if node==torso: continue
		if node is MeshInstance3D and node.position.y>.90:
			node.reparent(torso,true)
		elif node in person.arms:
			node.reparent(torso,true)
	torso.rotation.x = .46
	for i in range(2):
		var side := -1.0 if i==0 else 1.0
		var arm: Node3D = person.arms[i]
		var shoulder := person.to_local(arm.global_position)
		var hand := person.to_local(body.to_global(Vector3(side*.30,1.16,.23)))
		var elbow := _rider_bend(shoulder,hand,.25,.24,Vector3(side*.25,-1,0))
		var arm_parts := arm.get_children()
		_rider_segment(person,arm_parts[0] as MeshInstance3D,shoulder,elbow)
		_rider_segment(person,arm_parts[1] as MeshInstance3D,elbow,hand)
		_rider_endpoint(person,arm_parts[2] as MeshInstance3D,hand)
		var leg: Node3D = person.limbs[i]
		var knee: Node3D = person.knees[i]
		var hip := person.to_local(leg.global_position)
		var foot := person.to_local(body.to_global(Vector3(side*.27,.49,.08)))
		var joint := _rider_bend(hip,foot,.42,.38,Vector3(side*.55,0,1))
		var thigh_parts: Array[MeshInstance3D] = []
		for node in leg.get_children():
			if node is MeshInstance3D: thigh_parts.append(node)
		for j in range(thigh_parts.size()):
			var first := hip.lerp(joint,float(j)/float(thigh_parts.size()))
			var last := hip.lerp(joint,float(j+1)/float(thigh_parts.size()))
			_rider_segment(person,thigh_parts[j],first,last)
		var lower_parts := knee.get_children()
		_rider_segment(person,lower_parts[0] as MeshInstance3D,joint,foot)
		_rider_endpoint(person,lower_parts[1] as MeshInstance3D,foot)

func _make_rider(body: CharacterBody3D,kind: String,style: int) -> Node3D:
	var person := Person.new()
	body.add_child(person)
	person.setup(style)
	person.position = Vector3(0,.37,-.20)
	person.scale = Vector3(.80,.80,.80)
	person.remove_from_group("social_people")
	person.remove_from_group("pedestrian_spacing")
	if kind=="moto":
		_pose_moto(person,body)
	else:
		for leg in person.limbs: leg.rotation.x = -1.00
		for knee in person.knees: knee.rotation.x = 1.25
		for arm in person.arms: arm.rotation.x = -1.25
	return person

func _mount(kind: String) -> void:
	if not _unlocked(kind) or _listed(kind):
		business._notify("Este vehículo está reservado o bloqueado.")
		return
	var body: CharacterBody3D = owned[kind]
	if kind!="carro": rider = _make_rider(body,kind,691)
	riding = true
	ride_kind = kind
	ride_speed = 0.0
	previous_first = game.first_person
	game.player.velocity = Vector3.ZERO
	game.player_shape.set_deferred("disabled",true)
	game.avatar.hide()
	game.reticle.hide()
	game.pivot.reparent(body,false)
	game.pivot.position = Vector3(0,1.30,0)
	game.yaw = PI
	game.pitch = -.20
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game.arm.add_excluded_object(body.get_rid())
	game.arm.spring_length = 4.2
	game.player.global_position = body.global_position+Vector3.UP*.8

func _store_park(kind: String) -> void:
	var body: CharacterBody3D = owned[kind]
	var p := body.global_position
	state.parked[kind] = {"x":p.x,"y":p.y,"z":p.z,"angle":body.rotation.y}
	_save()

func _dismount(force: bool = false) -> void:
	if not riding: return
	var body: CharacterBody3D = owned[ride_kind]
	var spec: Dictionary = Kit.KITS[ride_kind]
	var space := get_world_3d().direct_space_state
	var destination := Vector3.ZERO
	var found := false
	for side in [-1.0,1.0]:
		var p := body.to_global(Vector3(float(side)*(float(spec.width)*.5+.65),0,0))
		var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP*2,2)
		var hit := space.intersect_ray(ray)
		if hit.is_empty(): continue
		var at: Vector3 = hit.position+Vector3.UP*.86
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = game.player_shape.shape
		query.transform = Transform3D(Basis.IDENTITY,at)
		query.collision_mask = 1|4|8
		query.exclude = [game.player.get_rid()]
		if space.intersect_shape(query,1).is_empty():
			destination = at
			found = true
			break
	if not found and not force:
		business._notify("No hay espacio para bajar.")
		return
	_store_park(ride_kind)
	if rider!=null:
		rider.queue_free()
		rider = null
	body.velocity = Vector3.ZERO
	game.arm.remove_excluded_object(body.get_rid())
	game.pivot.reparent(game.player,false)
	game.player.global_position = destination if found else game.spawn_position
	game.player.velocity = Vector3.ZERO
	game.player_shape.set_deferred("disabled",false)
	riding = false
	ride_kind = ""
	ride_speed = 0.0
	game.first_person = previous_first
	game._apply_camera_mode()

func reset() -> void:
	_stop_home_paint()
	if riding: _dismount(true)
	inside = false
	garage_near = false

func drive(delta: float,movement: Vector2) -> void:
	var body: CharacterBody3D = owned[ride_kind]
	var spec: Dictionary = Kit.KITS[ride_kind]
	var speed := float(spec.speed)*(1.0+.08*float(state.upgrades.get(ride_kind,0)))
	var target := -movement.y*(speed if movement.y<=0 else speed*.28)
	var brake := Input.is_physical_key_pressed(KEY_SPACE)
	ride_speed = move_toward(ride_speed,0.0 if brake else target,delta*(12.0 if brake else 4.0))
	var old := body.global_transform
	var impact_speed := ride_speed
	if absf(ride_speed)>.1: body.rotation.y -= movement.x*signf(ride_speed)*delta*1.65*minf(absf(ride_speed)/2.0,1.0)
	var direction := body.global_transform.basis.z.normalized()
	body.velocity = direction*ride_speed
	body.move_and_slide()
	var p := body.global_position
	var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*2,p-Vector3.UP*2,2))
	if hit.is_empty() or absf(p.x)>1245 or absf(p.z)>1245:
		body.global_transform = old
		ride_speed = 0.0
	else: body.global_position.y = float(hit.position.y)+.035
	if game.incidents!=null: game.incidents.vehicle_motion(body,old,impact_speed,float(spec.width),float(spec.length))
	if body.get_slide_collision_count()>0: ride_speed *= .35
	game.player.global_position = body.global_position+Vector3.UP*.8
	last_save += delta
	if last_save>=10.0:
		last_save = 0.0
		_store_park(ride_kind)

func _init_traffic() -> void:
	if game.monte_services==null or not game.monte_services.initialized: return
	var route: Array = []
	for vehicle in game.monte_services.vehicles:
		if not bool(vehicle.truck):
			route = vehicle.route
			break
	if route.size()<5: return
	traffic_ready = true
	var spawn_slot := 0
	for kind in ["bicicleta","triciclo","moto"]:
		var spec: Dictionary = Kit.KITS[kind]
		var preferred := floori(float(route.size()-2)*float(spawn_slot)/3.0)
		spawn_slot += 1
		for offset in range(route.size()-2):
			var i := 1+(preferred+offset)%(route.size()-2)
			var p: Vector3 = route[i].p
			if p.distance_to(game.player.global_position)<25: continue
			var separated := true
			for existing in traffic:
				var other: CharacterBody3D = existing.body
				if other.global_position.distance_to(p)<15.0:
					separated = false
					break
			if not separated: continue
			var next: Vector3 = route[i+1].p
			var d := (next-p).normalized()
			if d.length_squared()<.5 or not Bypass._on_road(world.street_geometry,p,d,float(spec.width),float(spec.length)): continue
			var q := PhysicsShapeQueryParameters3D.new()
			var shape := BoxShape3D.new()
			shape.size = Vector3(float(spec.width)+.4,2.2,float(spec.length)+.4)
			q.shape = shape
			q.transform = Transform3D(Basis(Vector3.UP,atan2(d.x,d.z)),p+Vector3.UP*1.15)
			q.collision_mask = 1|4|8|32
			if not get_world_3d().direct_space_state.intersect_shape(q,1).is_empty(): continue
			var body := Kit.body(self,kind)
			body.global_position = p+Vector3.UP*.055
			body.rotation.y = atan2(d.x,d.z)
			_make_rider(body,kind,600+i)
			body.add_to_group("autonomous_traffic")
			traffic.append({"body":body,"kind":kind,"route":route,"index":i+1,"speed":0.0,"blocked":0.0,"cooldown":0.0,"detour":[],"detour_index":0,"resume":0})
			break

func _traffic_tick(delta: float) -> void:
	for entry in traffic:
		var body: CharacterBody3D = entry.body
		var spec: Dictionary = Kit.KITS[entry.kind]
		var route: Array = entry.route
		var watch_index := int(entry.resume) if not entry.detour.is_empty() else int(entry.index)
		var restored := Bypass.watchdog(entry,body,world.street_geometry,route,watch_index,float(spec.width),float(spec.length),maxf(1.8,float(spec.height)),delta)
		if restored>=0:
			entry.index = restored
			entry.detour = []
			entry.detour_index = 0
			continue
		var detour: Array = entry.detour
		var active := not detour.is_empty()
		var index := int(entry.detour_index) if active else int(entry.index)
		var target: Vector3 = detour[index].p if active else route[index].p
		target.y = body.global_position.y
		var diff := target-body.global_position
		var distance := diff.length()
		if distance<.30:
			if active:
				entry.detour_index = index+1
				if int(entry.detour_index)>=detour.size():
					entry.detour = []
					entry.index = int(entry.resume)
			else: entry.index = (index+1)%route.size()
			continue
		var d := diff.normalized()
		var width := float(spec.width)
		var length := float(spec.length)
		var height := maxf(1.8,float(spec.height))
		var reach := minf(7.0,distance+.6)
		var free := Bypass.clear_distance(body,d,reach,width,length,height)
		var blocked := free<reach-.05
		var stalled := Bypass.stalled(entry,body,delta)
		var junction_limit := Bypass.junction_gate(entry,body,world.street_geometry,detour if active else route,index,not active,width,length,height,delta,route if active else [],int(entry.resume))
		if Bypass.cooperate(entry,body,world.street_geometry,width,length,height,delta,stalled,target): continue
		if bool(entry.get("cooperative_rejoin",false)):
			entry.cooperative_rejoin = false
			entry.detour = []
			entry.index = Bypass.rejoin_index(body,route,int(entry.index),world.street_geometry,width,length,height)
			continue
		entry.cooldown = maxf(0.0,float(entry.cooldown)-delta)
		var speed := minf(3.2 if active else float(spec.speed)*.65,maxf(.75,distance))
		if blocked: speed = minf(speed,sqrt(10.0*maxf(0.0,free-.55)))
		speed = Bypass.junction_speed(speed,junction_limit,5.0)
		if not bool(body.get_meta("junction_guard",false)) and float(entry.get("retreat_remaining",0.0))<=0.0 and (stalled>.8 or (not active and Bypass.early_lane_pass(body,world.street_geometry,blocked,free))) and float(entry.cooldown)<=0.0:
			entry.cooldown = 1.6
			if active:
				entry.detour = []
				entry.index = int(entry.resume)
				continue
			var choice := Bypass.recover(body,route,index,world.street_geometry,width,length,world.geography.signal_nodes,height)
			if not choice.is_empty():
				entry.detour = choice.path
				entry.detour_index = 0
				entry.resume = int(choice.resume)
				entry.traffic_stall = 0.0
				continue
		if not active and Bypass.retreat(entry,body,world.street_geometry,width,length,delta,stalled>3.5 and float(entry.speed)<.12):
			entry.speed = 0.0
			continue
		if stalled<.1: entry.backed_up = 0.0
		entry.speed = move_toward(float(entry.speed),speed,delta*5)
		var angle := lerp_angle(body.rotation.y,atan2(d.x,d.z),minf(delta*5.0,1.0))
		var advance := Bypass.junction_advance(minf(float(entry.speed)*delta,distance),junction_limit)
		if blocked: advance = minf(advance,maxf(0.0,free-.55))
		if advance<.0001:
			if junction_limit<0.0: Bypass.align_if_clear(body,angle)
			body.velocity = Vector3.ZERO
			entry.speed = 0.0
		elif not Bypass.safe_step(body,d,advance,angle,delta): entry.speed = 0.0

func tick(delta: float) -> void:
	_tick_listing(delta)
	if not traffic_ready:
		refresh_clock += delta
		if refresh_clock>1.0:
			refresh_clock = 0.0
			_init_traffic()
	else: _traffic_tick(delta)
	marker.position.y = 2.35+sin(Time.get_ticks_msec()*.003)*.12
	marker.visible = inside and _wheel_pending()
	_tick_home_paint(delta)
	_tick_paint_order(delta)
	if waypoint!=null:
		waypoint.visible = waypoint_active and not inside
		waypoint.global_position = waypoint_point+Vector3.UP*(2.7+sin(Time.get_ticks_msec()*.003)*.15)
	if carried_view!=null: carried_view.visible = not riding and not game.driving and not game.taxi_riding and not game.bus_riding
	for i in range(state.deliveries.size()-1,-1,-1):
		var delivery: Dictionary = state.deliveries[i]
		delivery.remaining = float(delivery.remaining)-delta
		if float(delivery.remaining)<=0:
			var token := String(delivery.token)
			state.inventory[token] = int(state.inventory.get(token,0))+1
			state.deliveries.remove_at(i)
			business.ledger.add_message("Marketplace","Tu pieza llegó al garaje. Ya puedes instalarla.")
			_save()
			business._notify("Repuesto entregado en tu garaje.")
	if inside and not business.modal_open() and _wheel_pending() and game.player.global_position.distance_to(ROOM+BENCH)<2.5:
		_install_reward_wheel()

func _wheel_pending() -> bool:
	return _unlocked("bicicleta") and not bool(state.get("wheel_tutorial",false)) and String(state.part)=="bicicleta:wheel_a"

func _install_reward_wheel() -> void:
	if not inside or not _wheel_pending(): return
	state.project = "bicicleta"
	if not state.projects.has("bicicleta"): state.projects.bicicleta = {}
	state.projects.bicicleta.wheel_a = true
	state.part = ""
	state.wheel_tutorial = true
	_refresh_preview()
	_refresh_carried()
	marker.hide()
	waypoint_active = false
	state.gps = {}
	game.taxis.set_garage_destination(Vector3.ZERO,"")
	_save()
	business._open("Tu primera bicicleta","¡Goma instalada! Las piezas transparentes son las que faltan. Mira la bicicleta y pulsa E para comprar o instalar piezas. Cuando esté completa podrás venderla en Facebook Marketplace y desbloquear un triciclo. También puedes comprar pintura en Facebook o en tiendas de repuestos, traerla a casa y pintar tus paredes.")
	business._button("Entendido",business.close)

func _aimed_project(at: Vector3) -> bool:
	if at.distance_to(ROOM+BENCH)>3.5 or not preview.visible or not _unlocked(String(state.project)): return false
	var cam: Camera3D = game.play_camera
	var origin := cam.global_position
	var end := origin-cam.global_basis.z*4.5
	var depth := INF
	for child in preview.get_children():
		if not child is MeshInstance3D or not child.is_visible_in_tree(): continue
		var part := child as MeshInstance3D
		var hit: Variant = part.get_aabb().intersects_segment(part.to_local(origin),part.to_local(end))
		if hit==null: continue
		var point: Vector3 = part.to_global(hit)
		depth = minf(depth,origin.distance_to(point))
	if not is_finite(depth): return false
	var ray := PhysicsRayQueryParameters3D.create(origin,origin-cam.global_basis.z*depth,1|4|8|16|32)
	ray.exclude = [game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _home_wall(id: String,p: Vector3,size: Vector3,color: Color,positive: bool,negative: bool) -> void:
	var body := _solid(interior,p,size,color)
	body.set_meta("home_paint_wall",id)
	home_walls[id] = body
	var axis_x := size.x<size.z
	for sign_value in [1,-1]:
		if sign_value==1 and not positive: continue
		if sign_value==-1 and not negative: continue
		var sign_float := float(sign_value)
		var key := id+":"+str(sign_value)
		var quad := QuadMesh.new()
		quad.size = Vector2(size.z if axis_x else size.x,size.y)
		var visual := MeshInstance3D.new()
		visual.mesh = quad
		body.add_child(visual)
		visual.position = Vector3(sign_float*(size.x*.5+.006),0,0) if axis_x else Vector3(0,0,sign_float*(size.z*.5+.006))
		visual.rotation.y = sign_float*PI*.5 if axis_x else (0.0 if sign_value==1 else PI)
		var img := Image.create(12,6,false,Image.FORMAT_RGB8)
		img.fill(color)
		var saved: Dictionary = state.paint_cells.get(key,{})
		for cell in saved:
			var index := int(cell)
			var paint := String(saved[cell])
			if index>=0 and index<72 and PAINT_COLORS.has(paint): img.set_pixel(index%12,floori(float(index)/12.0),Color(PAINT_COLORS[paint]))
		var texture := ImageTexture.create_from_image(img)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = texture
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		visual.material_override = mat
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		home_paint_images[key] = img
		home_paint_textures[key] = texture
		home_paint_meshes[key] = visual

func _make_paint_can(parent: Node3D,color: String) -> void:
	var can := CylinderMesh.new()
	can.top_radius = .19
	can.bottom_radius = .17
	can.height = .33
	can.radial_segments = 12
	var mesh := MeshInstance3D.new()
	mesh.mesh = can
	mesh.material_override = business._mat(Color("#65747a"))
	parent.add_child(mesh)
	business._box(parent,Vector3(0,.17,0),Vector3(.25,.025,.25),Color(PAINT_COLORS.get(color,"#e0d8c5")))

func _make_brush_model(root: Node3D,color: Color) -> MeshInstance3D:
	business._box(root,Vector3(0,0,.10),Vector3(.07,.06,.23),Color("#95633d"))
	return business._box(root,Vector3(0,0,-.08),Vector3(.16,.055,.15),color)

func _make_broom_model(root: Node3D) -> void:
	business._box(root,Vector3(0,.74,0),Vector3(.055,1.34,.055),Color("#9c7646"))
	business._box(root,Vector3(0,.18,0),Vector3(.38,.08,.16),Color("#a14e37"))
	business._box(root,Vector3(0,.075,0),Vector3(.40,.14,.18),Color("#c5a260"))

func _brush_color() -> Color:
	return Color(PAINT_COLORS.get(String(state.paint_active),"#cab99a"))

func _build_house_tools() -> void:
	paper = business._box(paint_station,PAPER_POS,Vector3(.65,.008,.47),Color("#e9e6dd"))
	# A small texture holds stains on the paper rather than coloring the
	# entire sheet. The brush remains a separate physical prop.
	paper_image = Image.create(16,12,false,Image.FORMAT_RGB8)
	paper_image.fill(Color("#e9e6dd"))
	paper_texture = ImageTexture.create_from_image(paper_image)
	var sheet := QuadMesh.new()
	sheet.size = Vector2(.63,.45)
	var paper_top := MeshInstance3D.new()
	paper_top.mesh = sheet
	paper_top.position = PAPER_POS+Vector3.UP*.006
	paper_top.rotation.x = -PI*.5
	paper_top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_texture = paper_texture
	paper_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	paper_top.material_override = paper_mat
	paint_station.add_child(paper_top)
	_refresh_paper()
	resting_brush = Node3D.new()
	paint_station.add_child(resting_brush)
	resting_brush.position = PAPER_POS+Vector3.UP*.04
	resting_tip = _make_brush_model(resting_brush,_brush_color())
	resting_broom = Node3D.new()
	paint_station.add_child(resting_broom)
	resting_broom.position = BROOM_POS
	resting_broom.rotation.x = -.15
	floor_image = Image.create(FLOOR_COLS*3,FLOOR_ROWS*3,false,Image.FORMAT_RGBA8)
	floor_image.fill(Color(0,0,0,0))
	floor_texture = ImageTexture.create_from_image(floor_image)
	var quad := QuadMesh.new()
	quad.size = Vector2(13.6,11.6)
	var visual := MeshInstance3D.new()
	visual.mesh = quad
	interior.add_child(visual)
	visual.position = Vector3(0,.036,0)
	visual.rotation.x = -PI*.5
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = floor_texture
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	visual.material_override = mat
	_refresh_floor_marks()
	_refresh_tools()

func _refresh_tools() -> void:
	if not is_instance_valid(resting_brush): return
	var tool := String(state.paint_tool)
	resting_brush.visible = tool!="brush"
	resting_broom.visible = tool!="broom"
	resting_tip.material_override = business._mat(_brush_color())
	_refresh_paper()
	if is_instance_valid(paint_brush):
		paint_brush.visible = inside and tool=="brush"
		paint_tip.material_override = business._mat(_brush_color())
	if is_instance_valid(held_broom): held_broom.visible = inside and tool=="broom"

func _refresh_paper() -> void:
	if paper_image==null: return
	paper_image.fill(Color("#e9e6dd"))
	var marks: Array = state.paper_marks
	for i in range(marks.size()):
		var color := Color(PAINT_COLORS.get(String(marks[i]),"#e9e6dd"))
		var x := 4+posmod(i*5,8)
		var y := 3+posmod(i*3,6)
		for dy in range(-2,3):
			for dx in range(-3,4):
				if abs(dx)+abs(dy)>4: continue
				paper_image.set_pixel(clampi(x+dx,0,15),clampi(y+dy,0,11),color)
	paper_texture.update(paper_image)

func _refresh_paint_station() -> void:
	if not is_instance_valid(paint_station): return
	# A single visual can per owned color, showing the current can's level.
	var slot := 0
	for key in PAINT_COLORS:
		var color := String(key)
		var amount := int(state.paint_stock.get(color,0))
		var can: Node3D = paint_cans.get(color)
		if amount<=0:
			if is_instance_valid(can): can.hide()
			slot += 1
			continue
		if not is_instance_valid(can):
			can = Node3D.new()
			paint_station.add_child(can)
			can.position = Vector3(6.20,.18,1.85+float(slot)*.49)
			var shell := CylinderMesh.new()
			shell.top_radius = .19
			shell.bottom_radius = .17
			shell.height = .34
			shell.radial_segments = 12
			shell.cap_top = false
			var mesh := MeshInstance3D.new()
			mesh.mesh = shell
			var shell_mat := StandardMaterial3D.new()
			shell_mat.albedo_color = Color("#737c80")
			shell_mat.roughness = .76
			# An open cylinder has no back-facing inner wall by default.
			# Draw both sides without changing any shared city materials.
			shell_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.material_override = shell_mat
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			can.add_child(mesh)
			var rim_mesh := TorusMesh.new()
			rim_mesh.inner_radius = .169
			rim_mesh.outer_radius = .199
			rim_mesh.rings = 12
			rim_mesh.ring_segments = 6
			var rim := MeshInstance3D.new()
			rim.mesh = rim_mesh
			rim.material_override = business._mat(Color("#a4abad"))
			rim.position.y = .17
			rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			can.add_child(rim)
			var fill_mesh := CylinderMesh.new()
			fill_mesh.top_radius = .176
			fill_mesh.bottom_radius = .176
			fill_mesh.height = .025
			fill_mesh.radial_segments = 12
			var fill := MeshInstance3D.new()
			fill.name = "PaintLevel"
			fill.mesh = fill_mesh
			fill.material_override = business._mat(Color(PAINT_COLORS[color]))
			can.add_child(fill)
			business._box(can,Vector3(-.17,0,0),Vector3(.025,.14,.16),Color(PAINT_COLORS[color]))
			paint_cans[color] = can
		can.show()
		var level := float((amount-1)%CAN_CAPACITY+1)/float(CAN_CAPACITY)
		var fill_node := can.get_node("PaintLevel") as Node3D
		fill_node.position.y = -.145+.28*level
		slot += 1

func _aim_tool(node: Node3D,center: Vector3,extent: Vector3) -> bool:
	if not is_instance_valid(node): return false
	var cam: Camera3D = game.play_camera
	var start := cam.global_position
	var finish := start-cam.global_basis.z*3.0
	var hit: Variant = AABB(center-extent,extent*2.0).intersects_segment(node.to_local(start),node.to_local(finish))
	if hit==null: return false
	var at := node.to_global(hit)
	if game.player.global_position.distance_to(at)>3.0: return false
	var ray := PhysicsRayQueryParameters3D.create(start,at,1|2)
	ray.exclude = [game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _aim_can() -> String:
	for color in paint_cans:
		var can: Node3D = paint_cans[color]
		if can.visible and _aim_tool(can,Vector3.ZERO,Vector3(.23,.19,.23)): return String(color)
	return ""

func _near_broom(at: Vector3) -> bool:
	if not is_instance_valid(resting_broom): return false
	var p := resting_broom.global_position
	return Vector2(p.x-at.x,p.z-at.z).length()<1.35

func _house_tool_action(at: Vector3) -> String:
	var tool := String(state.paint_tool)
	if not String(state.paint_carry).is_empty():
		if at.distance_to(ROOM+PAPER_POS)<2.5: return "[E] Dejar cubo de pintura"
		return ""
	if tool=="brush":
		if not _aim_can().is_empty(): return "[E] Embarrar brocha"
		if _aim_tool(resting_brush,Vector3.ZERO,Vector3(.38,.14,.28)): return "[E] Dejar brocha sobre el papel"
		return "Clic izquierdo: pintar" if int(state.paint_charge)>0 else "Moja la brocha en un cubo de pintura"
	if tool=="broom":
		if _near_broom(at) or _aim_tool(resting_broom,Vector3(0,.65,0),Vector3(.30,.75,.25)): return "[E] Dejar escoba"
		return "Clic izquierdo: barrer"
	if not _free_hands(): return ""
	if _aim_tool(resting_brush,Vector3.ZERO,Vector3(.27,.12,.24)): return "[E] Recoger brocha"
	if _near_broom(at) or _aim_tool(resting_broom,Vector3(0,.65,0),Vector3(.30,.75,.25)): return "[E] Recoger escoba"
	return ""

func _house_tool_interact(at: Vector3) -> bool:
	var action := _house_tool_action(at)
	if action.is_empty(): return false
	if action.contains("Dejar cubo"):
		var color := String(state.paint_carry)
		state.paint_stock[color] = int(state.paint_stock.get(color,0))+CAN_CAPACITY
		state.paint_carry = ""
		_refresh_carried()
		_refresh_paint_station()
		_save()
	elif action.contains("Recoger brocha"): _take_home_tool("brush")
	elif action.contains("Recoger escoba"): _take_home_tool("broom")
	elif action.contains("Embarrar"): _dip_home_brush(_aim_can())
	elif action.contains("Dejar brocha") or action.contains("Dejar escoba"): _stop_home_paint()
	return true

func _take_home_tool(tool: String) -> void:
	if not inside or not _free_hands(): return
	state.paint_tool = tool
	paint_previous_first = game.first_person
	game.first_person = true
	game._apply_camera_mode()
	if tool=="brush" and not is_instance_valid(paint_brush):
		paint_brush = Node3D.new()
		game.play_camera.add_child(paint_brush)
		paint_brush.position = Vector3(.28,-.30,-.72)
		paint_tip = _make_brush_model(paint_brush,_brush_color())
	if tool=="broom" and not is_instance_valid(held_broom):
		held_broom = Node3D.new()
		game.play_camera.add_child(held_broom)
		held_broom.position = Vector3(.46,-.68,-1.05)
		held_broom.rotation.x = -.65
		_make_broom_model(held_broom)
	_refresh_tools()
	_save()

func _dip_home_brush(color: String) -> void:
	if String(state.paint_tool)!="brush" or not PAINT_COLORS.has(color): return
	var existing := int(state.paint_charge) if String(state.paint_active)==color else 0
	var amount := mini(BRUSH_LOAD-existing,int(state.paint_stock.get(color,0)))
	if amount<=0: return
	state.paint_stock[color] = int(state.paint_stock[color])-amount
	state.paint_active = color
	state.paint_charge = existing+amount
	_refresh_paint_station()
	_refresh_tools()
	_save()

func _paint_shop(local_shop: bool) -> void:
	business._open("Pintura para tu casa","Elige un color. "+("Lleva la lata a tu casa." if local_shop else "Entrega de Facebook simulada: la lata aparecerá en el suelo junto a tu brocha."))
	for color in PAINT_COLORS:
		var price := PAINT_PRICE if local_shop else PAINT_PRICE+60
		business._button(String(color).capitalize()+" · "+str(price)+" CUP",_buy_paint.bind(String(color),local_shop),business.ledger.cash<price or (not _free_hands() if local_shop else not state.paint_order.is_empty()))
	if not local_shop and not world.parts_sites.is_empty():
		business._button("Ir a tienda de pintura",_show_map.bind(world.parts_sites[0].road,String(world.parts_sites[0].name)))
	business._button("Cerrar",business.close)

func _buy_paint(color: String,local_shop: bool) -> void:
	if not PAINT_COLORS.has(color): return
	var price := PAINT_PRICE if local_shop else PAINT_PRICE+60
	if business.ledger.cash<price: return
	if local_shop:
		if not _free_hands() or _vendor_at(game.player.global_position).is_empty(): return
		state.paint_carry = color
	else:
		if not state.paint_order.is_empty(): return
		state.paint_order = {"color":color,"remaining":25.0}
	business.ledger.spend(price)
	_refresh_carried()
	business.close()
	business._notify("Lleva la lata a casa y déjala en el suelo junto a la brocha." if local_shop else "Pedido de pintura realizado. Llegará a tu casa junto a la brocha.")

func _tick_paint_order(delta: float) -> void:
	var order: Dictionary = state.paint_order
	if order.is_empty(): return
	order.remaining = float(order.remaining)-delta
	if float(order.remaining)>0.0: return
	var color := String(order.color)
	state.paint_stock[color] = int(state.paint_stock.get(color,0))+CAN_CAPACITY
	state.paint_order = {}
	_refresh_paint_station()
	_save()
	business._notify("Tu pintura de Facebook llegó a casa.")

func _stop_home_paint() -> void:
	var tool := String(state.paint_tool)
	if tool.is_empty(): return
	if tool=="brush" and not String(state.paint_active).is_empty():
		state.paper_color = String(state.paint_active)
		if state.paper_marks.is_empty() or String(state.paper_marks.back())!=String(state.paint_active):
			state.paper_marks.append(String(state.paint_active))
			if state.paper_marks.size()>8: state.paper_marks.pop_front()
	state.paint_tool = ""
	game.first_person = paint_previous_first
	game._apply_camera_mode()
	_refresh_tools()
	_save()

func _floor_key(at: Vector3) -> String:
	var p := at-ROOM
	if absf(p.x)>=6.8 or absf(p.z)>=5.8: return ""
	var x := clampi(floori((p.x+6.8)/13.6*FLOOR_COLS),0,FLOOR_COLS-1)
	var y := clampi(floori((p.z+5.8)/11.6*FLOOR_ROWS),0,FLOOR_ROWS-1)
	return str(y*FLOOR_COLS+x)

func _refresh_floor_marks() -> void:
	if floor_image==null: return
	floor_image.fill(Color(0,0,0,0))
	for key in state.floor_marks:
		var index := int(key)
		if index<0 or index>=FLOOR_COLS*FLOOR_ROWS: continue
		var kind := String(state.floor_marks[key])
		var color := Color(PAINT_COLORS.get(kind,"#655548"))
		color.a = .84 if PAINT_COLORS.has(kind) else .52
		var x := (index%FLOOR_COLS)*3
		var y := floori(float(index)/FLOOR_COLS)*3
		# Irregular low-resolution splashes, not square floor tiles.
		floor_image.set_pixel(x+1,y+1,color)
		floor_image.set_pixel(x+posmod(index,2),y+1,color)
		floor_image.set_pixel(x+1,y+posmod(index,3),color)
		if posmod(index,3)!=0: floor_image.set_pixel(x+2,y+2,color)
		if PAINT_COLORS.has(kind): floor_image.set_pixel(x+2,y,color)
	floor_texture.update(floor_image)

func _floor_mark(at: Vector3,color: String) -> void:
	var key := _floor_key(at)
	if key.is_empty() or String(state.floor_marks.get(key,""))==color: return
	state.floor_marks[key] = color
	_refresh_floor_marks()
	home_paint_dirty = true

func _tick_dirt(delta: float) -> void:
	dirt_clock += delta
	if dirt_clock<45.0: return
	dirt_clock = 0.0
	var count := 0
	for value in state.floor_marks.values():
		if String(value)=="dirt": count += 1
	if count>=20: return
	var spots := [Vector3(-5.7,0,4.6),Vector3(-2.0,0,4.5),Vector3(-2.1,0,.9),Vector3(-5.9,0,-.5),Vector3(-2.5,0,-3.3),Vector3(1.4,0,4.6),Vector3(4.5,0,2.1),Vector3(1.8,0,-4.8),Vector3(5.9,0,-.1),Vector3(3.2,0,3.0)]
	for i in range(6):
		var at: Vector3 = ROOM+spots[randi()%spots.size()]+Vector3(randf_range(-.35,.35),0,randf_range(-.35,.35))
		var key := _floor_key(at)
		if key.is_empty() or state.floor_marks.has(key): continue
		_floor_mark(at,"dirt")
		break

func _sweep_at(at: Vector3) -> void:
	var key := _floor_key(at)
	if key.is_empty(): return
	var index := int(key)
	var x := index%FLOOR_COLS
	var y := floori(float(index)/FLOOR_COLS)
	var changed := false
	for row in range(maxi(0,y-1),mini(FLOOR_ROWS,y+2)):
		for col in range(maxi(0,x-1),mini(FLOOR_COLS,x+2)):
			if state.floor_marks.erase(str(row*FLOOR_COLS+col)): changed = true
	if changed:
		_refresh_floor_marks()
		home_paint_dirty = true
	if is_instance_valid(held_broom): held_broom.rotation.z = sin(float(Time.get_ticks_msec())*.012)*.22

func _tick_home_paint(delta: float) -> void:
	_tick_dirt(delta)
	if home_paint_dirty:
		paint_save_clock += delta
		if paint_save_clock>=2.0:
			paint_save_clock = 0.0
			home_paint_dirty = false
			_save()
	if not inside or String(state.paint_tool).is_empty() or business.modal_open() or Input.mouse_mode!=Input.MOUSE_MODE_CAPTURED or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): return
	paint_clock += delta
	if paint_clock<.15: return
	paint_clock = 0.0
	var cam: Camera3D = game.play_camera
	var reach := 3.5 if String(state.paint_tool)=="broom" else 2.8
	var ray := PhysicsRayQueryParameters3D.create(cam.global_position,cam.global_position-cam.global_basis.z*reach,1|2)
	ray.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty(): return
	if String(state.paint_tool)=="broom":
		if hit.normal.y>.7 and absf(float(hit.position.y)-ROOM.y)<.12:
			var point: Vector3 = hit.position
			var at: Vector3 = game.player.global_position
			if Vector2(point.x-at.x,point.z-at.z).length()<=2.5: _sweep_at(point)
		return
	if int(state.paint_charge)<=0 or not hit.collider.has_meta("home_paint_wall"): return
	var id := String(hit.collider.get_meta("home_paint_wall"))
	var normal: Vector3 = hit.normal
	var key := id+":"+str(1 if (normal.x if id in ["west","east","partition_a","partition_b"] else normal.z)>0.0 else -1)
	if not home_paint_meshes.has(key): return
	var visual: MeshInstance3D = home_paint_meshes[key]
	var quad := visual.mesh as QuadMesh
	var local := visual.to_local(hit.position)
	var x := clampi(floori((local.x/quad.size.x+.5)*12.0),0,11)
	var y := clampi(floori((.5-local.y/quad.size.y)*6.0),0,5)
	var cell := str(y*12+x)
	var color := String(state.paint_active)
	if not state.paint_cells.has(key): state.paint_cells[key] = {}
	if String(state.paint_cells[key].get(cell,""))==color: return
	state.paint_cells[key][cell] = color
	var img: Image = home_paint_images[key]
	img.set_pixel(x,y,Color(PAINT_COLORS[color]))
	var texture: ImageTexture = home_paint_textures[key]
	texture.update(img)
	state.paint_charge = int(state.paint_charge)-1
	home_paint_dirty = true
	stroke_count += 1
	var drip: Vector3 = hit.position+normal*(.20+float(stroke_count%3)*.12)
	_floor_mark(drip,color)
	if is_instance_valid(paint_brush): paint_brush.rotation.x = -.5+sin(float(state.paint_charge)*1.8)*.22
	if int(state.paint_charge)==0:
		_save()
		business._notify("Brocha seca. Embárrala de pintura otra vez.")

func gps_hint() -> String:
	if not waypoint_active or inside: return ""
	var at: Vector3 = game.player.global_position
	var distance := Vector2(at.x-waypoint_point.x,at.z-waypoint_point.z).length()
	return "%s · %.0f m" % [waypoint_label,distance]
