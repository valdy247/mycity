extends Node3D
const InteractionHand = preload("res://interaction_hand.gd")
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
const CAN_CAPACITY := 300
const WASTE_CAPACITY := 10
const TRASH_POS := Vector3(4.9,0,5.20)
const RENTAL_TRASH_POS := Vector3(-6.37,0,1.92)
const RENTAL_FIXED_LAYOUT := {"sofa":[-4.1,0,2.35],"mesa":[-3.55,0,-.85],"cama":[-4.5,0,-4.1],"armario":[-1.7,0,-5.0]}
var empty_cans: Dictionary = {}
var waste_root: Node3D
var waste_bag: Node3D
var waste_overflow: Node3D
var waste_mesh := SphereMesh.new()
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
var guest_door: Node3D
var guest_door_tween: Tween
var guest_door_open := false
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
# The fridge belongs to the rented house, not to the mission NPC.
const RENTAL_FRIDGE_LOCAL := Vector3(-6.29,0,1.0)
var rental_fridge: Node3D
var rental_fridge_doors: Dictionary = {}
var home_food_fridge_body: StaticBody3D
var home_food_props: Dictionary = {}
var home_plate_stack: Node3D
var home_plate_door: Node3D
var home_pan: Node3D
var home_pan_food: Node3D
var home_pan_heat: MeshInstance3D
var home_pan_smoke: CPUParticles3D
var home_pan_save_clock := 0.0
const HOME_PAN_GRACE := {"carne":20.0,"huevo":12.0}
var home_food_busy := false
var dining_seated := false
var dining_chair: Node3D
var dining_chair_body: StaticBody3D
var dining_surface: Node3D
var dining_plate_prop: Node3D
var dining_water_prop: Node3D
var dining_stand_position := Vector3.ZERO
var dining_previous_first := true
var dining_previous_yaw := 0.0
var dining_previous_pitch := 0.0
var dining_water_busy := false
var dish_wash_hint: Label
var dish_washing := false
var dish_sponge: Node3D
var bath_door: Node3D
var bath_door_body: StaticBody3D
var bath_door_target := 0.0
var bath_door_moving := false
var bath_sink: Node3D
var bath_sink_body: StaticBody3D
var bath_toilet: Node3D
var bath_toilet_body: StaticBody3D
var bath_water: MeshInstance3D
var bath_bowl_water: MeshInstance3D
var bath_hint: Label
var bath_mode := ""
var bath_seconds := 0.0
var bath_return := Vector3.ZERO
var bath_old_first := true
var bath_old_yaw := 0.0
var bath_old_pitch := 0.0
var bath_wash_model: Node3D
var bath_left_hand: Node3D
var bath_right_hand: Node3D
var bath_clock := -1.0
var bath_warned := false
var bath_flush_seconds := 0.0
var bath_soap_foam: Node3D
var bath_lower_body: Node3D
const HOME_PAN_TIME := {"carne":25.0,"huevo":12.0}
var rental_storage_doors: Array[Dictionary] = []
var rental_oil: Node3D
var rental_kitchen: Node3D
var rice_cooker: Node3D
var rice_lid: Node3D
var rice_contents: MeshInstance3D
var rice_indicator: MeshInstance3D
var rice_jug: Node3D
var rice_pantry: Dictionary = {}
var rice_doors: Dictionary = {}
var rice_cabinet_body: StaticBody3D
var rice_pouring := false
var rice_lid_tween: Tween
var rice_lid_hand: Node3D
const RICE_INGREDIENTS := ["arroz","agua","sal","aceite"]
const RICE_COOK_SECONDS := 35.0
var home_windows: Array[Dictionary] = []
var bedside_drawer: Node3D
var coffee_pot: Node3D
var coffee_cup: Node3D
var coffee_drink_view: Node3D
var coffee_busy := false
var coffee_liquid: MeshInstance3D
var coffee_heat: MeshInstance3D
var coffee_stream: MeshInstance3D
var coffee_steam: CPUParticles3D
var coffee_phase := ""
const COFFEE_REPLACEMENT_PRICE := 1200
const COFFEE_SHUTOFF_SECONDS := 30.0
var coffee_machine_audio: AudioStreamPlayer3D
var coffee_ready_sound: AudioStreamWAV
var coffee_burst_sound: AudioStreamWAV
var coffee_alert_clock := 0.0
var coffee_save_clock := 0.0
var coffee_stains: Node3D
var coffee_spill_patches: Array[Dictionary] = []
var coffee_broken_prop: Node3D
var coffee_rag: Node3D
var coffee_cleaning := false
var coffee_status_label: Label
var wall_hour_hand: Node3D
var wall_minute_hand: Node3D
var bedside_lamp: Node3D
var bedside_glow: OmniLight3D
var home_light_switches: Dictionary = {}
var home_room_lights: Dictionary = {}
var home_fixture_materials: Dictionary = {}
var home_shadow_active := false
var television: Node3D
var television_screen: MeshInstance3D
var kitchen_tap: Node3D
var tap_water: MeshInstance3D
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
var borrowed_body: CharacterBody3D
var ride_exit_requested := false
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
	if not state.has("bathroom"): state.bathroom = {"door":PI*.5,"need":randf_range(12.0,25.0),"rate":randf_range(.28,.45),"hands_dirty":false,"flush":false}
	if not state.has("rice_recipe"): state.rice_recipe = {"added":[],"remaining":0.0,"portions":0,"hand":"","lid":true,"stock":{"arroz":12,"sal":24,"aceite":24}}
	# A restored game starts outside; return any kitchen utensil to its shelf.
	state.rice_recipe.hand = ""
	if not state.has("home_food"): state.home_food = {"stock":{"carne":8,"huevo":12},"hand":"","pan":"","remaining":0.0,"plate":[]}
	if not state.home_food.stock.has("botella"): state.home_food.stock.botella = 6
	if not state.home_food.has("table_plate"): state.home_food.table_plate = []
	if not state.home_food.has("table_bites"): state.home_food.table_bites = 3
	if not state.home_food.has("table_water"): state.home_food.table_water = -1
	# A saved meal resumes on the table, not in the hands outside the house.
	var saved_meal: Dictionary = business.life.state.get("meal",{})
	if game.adaptation_mode and String(saved_meal.get("key","")) in ["plato_casero","arroz_casero"]:
		state.home_food.table_plate = saved_meal.get("ingredients",["arroz"]).duplicate()
		state.home_food.table_bites = int(saved_meal.get("food_bites",3))
		state.home_food.table_used_plate = true
		business.life.state.meal = {}
		business.life._refresh_meal()
	if not state.home_food.has("table_used_plate"): state.home_food.table_used_plate = not state.home_food.table_plate.is_empty()
	if not state.home_food.has("plate_dirty"): state.home_food.plate_dirty = false
	if String(state.home_food.hand)!="plato": state.home_food.plate_dirty = false
	if not state.home_food.has("heat_on"): state.home_food.heat_on = float(state.home_food.remaining)>0.0
	if not state.home_food.has("overcook"): state.home_food.overcook = 0.0
	if not state.home_food.has("burned"): state.home_food.burned = false
	if String(state.home_food.hand)!="plato": state.home_food.hand = ""
	if not state.has("coffee_machine"): state.coffee_machine = {"phase":"idle","remaining":0.0,"dirty":0,"rag_held":false,"replacement":false}
	state.coffee_machine.rag_held = false
	# Migrate old saves without bringing back stains the player already cleaned.
	if not state.coffee_machine.has("spill_zones"):
		var remaining := clampi(int(state.coffee_machine.get("dirty",0)),0,3)
		state.coffee_machine.spill_zones = []
		for i in range(remaining): state.coffee_machine.spill_zones.append(i)
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
	if int(state.get("paint_capacity_version",0))<1:
		for color in state.paint_stock:
			state.paint_stock[color] = maxi(0,int(state.paint_stock[color]))*3
		state.paint_capacity_version = 1
	for key in {"empty_paint":{},"waste_items":[],"waste_overflow":[],"waste_hand":{}}:
		if not state.has(key):
			var defaults := {"empty_paint":{},"waste_items":[],"waste_overflow":[],"waste_hand":{}}
			state[key] = defaults[key]
	if not state.has("paper_color"): state.paper_color = ""
	if not state.has("floor_marks"): state.floor_marks = {}
	if not state.has("paper_marks"): state.paper_marks = []
	if state.paper_marks.is_empty() and PAINT_COLORS.has(String(state.paper_color)): state.paper_marks.append(String(state.paper_color))
	if bool(state.projects.get("bicicleta",{}).get("wheel_a",false)) or int(state.vehicle_sales.get("bicicleta",0))>0: state.wheel_tutorial = true
	for id in FURNITURE:
		if not state.furniture.has(id): state.furniture[id] = {"p":FURNITURE[id].p.duplicate(),"removed":false}
	# Restore one coherent layout in existing rental saves, without changing
	# inventory, meal state, waste contents or other progress.
	if game.adaptation_mode and int(state.get("fixed_layout_version",0))<1:
		for id in RENTAL_FIXED_LAYOUT:
			state.furniture[id].p = RENTAL_FIXED_LAYOUT[id].duplicate()
			if String(state.held_furniture)==id: state.furniture[id].removed = false
		state.held_furniture = ""
		state.fixed_layout_version = 1
	# Existing GPS residence belongs to the player; no purchase or exterior sign.
	if not world.garage_home_site.is_empty():
		state.house = true
		if game.adaptation_mode: state.rented = true
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
	var visual: MeshInstance3D = business._box(body,Vector3.ZERO,size,color)
	# Only structural walls cast indoor shadows, not thousands of furniture details.
	if game.adaptation_mode and size.y>=.65 and maxf(size.x,size.z)>=.45 and minf(size.x,size.z)<=.21:
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# Give the existing home and client's room real tiled floors without
	# introducing any new meshes, collision shapes or paintable cells.
	if layer==2 and size.x>=5.0 and size.z>=5.0 and game.cuba_world!=null:
		var base := visual.material_override as StandardMaterial3D
		if base!=null:
			visual.material_override = game.cuba_world.havana_textures.material(base,"tile")
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
	var floor_color := Color("#c6bba7") if game.adaptation_mode else Color("#b8ada1")
	var wall := Color("#e6dfc9") if game.adaptation_mode else Color("#e0d8c5")
	_solid(interior,Vector3(0,-.10,0),Vector3(14,.20,12),floor_color,2)
	_solid(interior,Vector3(0,3.05,0),Vector3(14,.18,12),wall)
	_home_wall("west",Vector3(-6.9,1.5,0),Vector3(.2,3.0,12),wall,true,false)
	_home_wall("east",Vector3(6.9,1.5,0),Vector3(.2,3.0,12),wall,false,true)
	_home_wall("north",Vector3(0,1.5,-5.9),Vector3(14,3,.2),wall,true,false)
	_home_wall("south",Vector3(0,1.5,5.9),Vector3(14,3,.2),wall,false,true)
	_home_wall("partition_a",Vector3(-.1,1.5,-4.15),Vector3(.16,3,3.5),wall,true,true)
	_home_wall("partition_b",Vector3(-.1,1.5,3.9),Vector3(.16,3,3.9),wall,true,true)
	_home_wall("bedroom",Vector3(-4.7,1.5,-2.3),Vector3(4.4,3,.15),wall,true,true)
	guest_door = Node3D.new()
	interior.add_child(guest_door)
	guest_door.position = Vector3(-1.30,0,5.76)
	business._box(guest_door,Vector3(.60,1.10,0),Vector3(1.2,2.2,.10),Color("#685144"))
	business._box(guest_door,Vector3(1.07,1.06,-.07),Vector3(.13,.04,.05),Color("#c2b8a6"))
	business._label(interior,"SALIR",Vector3(-.7,2.4,5.68),Color("#f9e9d2")).rotation.y = PI
	business._box(interior,Vector3(3.2,.012,-1.4),Vector3(5.5,.025,5.2),Color("#777e7f"))
	business._label(interior,"GARAJE",Vector3(3.1,2.65,-5.70),Color("#d2e6f2"))
	for x in [-3.7,3.7]:
		var light := OmniLight3D.new()
		interior.add_child(light)
		light.position = Vector3(float(x),2.7,0)
		light.omni_range = 10.0
		light.light_energy = 1.15 if game.adaptation_mode else 1.6
		light.light_color = Color("#fff1dc")
		light.omni_attenuation = 1.1
		if game.adaptation_mode:
			light.position.z = 1.2 if float(x)<0 else -2.35
			light.omni_range = 6.2 if float(x)<0 else 6.0
			if float(x)>0:
				light.position.y = 2.55
				light.light_energy = 1.45
				light.omni_attenuation = .90
			_register_room_light("sala" if float(x)<0 else "garaje",light)
	if game.adaptation_mode:
		# Two distributed fixtures share the garage switch. Keep them away
		# from the ceiling and bathroom partition to illuminate the work area.
		var garage_fill := OmniLight3D.new()
		interior.add_child(garage_fill)
		garage_fill.position = Vector3(3.7,2.55,2.65)
		garage_fill.omni_range = 6.0
		garage_fill.light_energy = 1.45
		garage_fill.light_color = Color("#fff1dc")
		garage_fill.omni_attenuation = .90
		_register_room_light("garaje",garage_fill)
		var entry_fill := OmniLight3D.new()
		interior.add_child(entry_fill)
		entry_fill.position = Vector3(-1.85,2.53,4.45)
		entry_fill.omni_range = 3.9
		entry_fill.light_energy = 1.05
		entry_fill.light_color = Color("#fff1dc")
		entry_fill.omni_attenuation = .90
		entry_fill.set_meta("no_home_shadow",true)
		_register_room_light("sala",entry_fill)
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
	_build_waste()
	_refresh_paint_station()
	for id in FURNITURE: _refresh_furniture(String(id))
	if game.adaptation_mode:
		_decorate_rental_home()
		_build_rental_fridge()
		_build_rental_bathroom()
	_refresh_preview()

# The city and interior are separate rooms; the door remains a logical
# threshold. Opening the visible leaf never removes the room collision.
func set_guest_door(opened: bool) -> void:
	if not is_instance_valid(guest_door) or guest_door_open==opened: return
	guest_door_open = opened
	if is_instance_valid(guest_door_tween): guest_door_tween.kill()
	guest_door_tween = create_tween()
	guest_door_tween.tween_property(guest_door,"rotation:y",1.25 if opened else 0.0,.30)

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
	if game.adaptation_mode:
		# Keep the original collision proxy, furniture ID and saved position.
		# Only its rendered shell is replaced by the detailed model.
		var old_visual := body.get_child(0) as MeshInstance3D
		if old_visual!=null: old_visual.hide()
		_model_rental_furniture(body,id,size)
		return
	if id=="sofa":
		business._box(body,Vector3(0,.48,-.30),Vector3(1.90,.63,.22),spec.color)
	elif id=="cama":
		business._box(body,Vector3(0,.29,0),Vector3(1.42,.16,1.94),Color("#e4e1d9"))
		business._box(body,Vector3(0,.42,-.68),Vector3(.70,.16,.40),Color("#f2eee5"))

# Rental decoration is deliberately inexpensive-looking. All furniture
# visuals are built locally; no assets, money, inventory or missions are granted.
func _rental_part(parent: Node3D,at: Vector3,size: Vector3,paint: Color) -> MeshInstance3D:
	return business._box(parent,at,size,paint) as MeshInstance3D

func _rental_round(parent: Node3D,at: Vector3,size: Vector3,paint: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = .5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = business._mat(paint)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	part.position = at
	part.scale = size
	return part

func _rental_cylinder(parent: Node3D,at: Vector3,radius: float,height: float,paint: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = business._mat(paint)
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(part)
	part.position = at
	return part

func _rental_root(parent: Node3D,at: Vector3,angle: float=0.0) -> Node3D:
	var root := Node3D.new()
	parent.add_child(root)
	root.position = at
	root.rotation.y = angle
	return root

func _model_rental_furniture(body: Node3D,id: String,size: Vector3) -> void:
	var root := _rental_root(body,Vector3(0,-size.y*.5,0))
	var wood := Color("#77563e")
	var dark := Color("#554233")
	var cloth := Color("#9f8b72")
	match id:
		"sofa":
			# Worn fabric and a visible wooden base, separate seat and back cushions.
			_rental_part(root,Vector3(0,.24,0),Vector3(1.84,.24,.77),wood)
			for x in [-.76,.76]:
				for z in [-.30,.30]:
					_rental_part(root,Vector3(float(x),.085,float(z)),Vector3(.11,.17,.11),dark)
			for x in [-.40,.40]:
				_rental_round(root,Vector3(float(x),.40,.065),Vector3(.79,.25,.67),cloth)
				_rental_round(root,Vector3(float(x),.65,-.30),Vector3(.80,.64,.25),cloth.lightened(.055))
			for x in [-.84,.84]:
				_rental_round(root,Vector3(float(x),.47,.02),Vector3(.20,.32,.79),cloth.darkened(.10))
			_rental_round(root,Vector3(-.63,.65,-.14),Vector3(.33,.33,.16),Color("#788477")).rotation.z = -.22
			_rental_round(root,Vector3(.58,.65,-.15),Vector3(.30,.31,.16),Color("#ad7961")).rotation.z = .18
		"mesa":
			_rental_part(root,Vector3(0,.705,0),Vector3(1.20,.09,.80),wood)
			_rental_part(root,Vector3(0,.61,0),Vector3(1.03,.14,.63),dark)
			for x in [-.48,.48]:
				for z in [-.28,.28]:
					_rental_part(root,Vector3(float(x),.32,float(z)),Vector3(.075,.64,.075),wood)
			_rental_part(root,Vector3(0,.756,0),Vector3(.36,.012,.67),Color("#d5c3a6"))
			if body is StaticBody3D: _build_dining_table(root)
		"cama":
			_rental_part(root,Vector3(0,.20,0),Vector3(1.5,.26,2.0),wood)
			for x in [-.62,.62]:
				for z in [-.87,.87]:
					_rental_part(root,Vector3(float(x),.065,float(z)),Vector3(.09,.13,.09),dark)
			_rental_part(root,Vector3(0,.37,0),Vector3(1.45,.19,1.94),Color("#d9d5c7"))
			var unmade := bool(business.life.state.get("bed_unmade",false))
			var blanket := _rental_part(root,Vector3(.18,.53,.50) if unmade else Vector3(0,.49,.31),Vector3(1.05,.14,.85) if unmade else Vector3(1.46,.06,1.29),Color("#819b9c"))
			blanket.rotation.y = .18 if unmade else 0.0
			_rental_part(root,Vector3(.20,.59,.16) if unmade else Vector3(0,.53,-.28),Vector3(.80,.09,.18) if unmade else Vector3(1.46,.045,.18),Color("#a7b8b4"))
			for x in [-.35,.35]:
				_rental_round(root,Vector3(float(x),.55,-.68),Vector3(.62,.18,.40),Color("#eee9d8"))
			_rental_part(root,Vector3(0,.53,-.95),Vector3(1.50,.87,.085),wood)
			for x in [-.69,.69]:
				_rental_part(root,Vector3(float(x),.54,-.95),Vector3(.09,1.04,.12),dark)
		"armario":
			_rental_part(root,Vector3(0,.99,-.23),Vector3(.95,1.82,.045),wood)
			for x in [-.455,.455]: _rental_part(root,Vector3(float(x),.99,0),Vector3(.04,1.82,.50),wood)
			for y in [.20,.72,1.35,1.82]: _rental_part(root,Vector3(0,float(y),0),Vector3(.90,.045,.46),wood)
			_rental_part(root,Vector3(0,.10,0),Vector3(.94,.13,.49),dark)
			_rental_part(root,Vector3(0,1.89,0),Vector3(1.00,.065,.54),dark)
			for x in [-.231,.231]:
				var hinge := _rental_root(root,Vector3(float(x)-.219,.225,.27))
				_rental_part(hinge,Vector3(.219,.825,0),Vector3(.438,1.65,.035),wood.lightened(.075))
				_rental_part(hinge,Vector3(.219,.825,.023),Vector3(.33,1.45,.025),wood.lightened(.12))
				_rental_part(hinge,Vector3(.36,.80,.05),Vector3(.035,.16,.04),Color("#bca985"))
				if body is StaticBody3D: _register_storage_door(hinge,Vector3(.219,.825,.025),Vector3(.438,1.65,.08),"armario del dormitorio")
			_rental_part(root,Vector3(0,.20,.26),Vector3(.86,.17,.045),dark)

func _rental_window(parent: Node3D,at: Vector3,angle: float,width: float) -> void:
	# The house interior is a separate scene volume. A luminous frosted
	# jalousie creates believable daylight without exposing the city below.
	var root := _rental_root(parent,at,angle)
	_rental_part(root,Vector3.ZERO,Vector3(width+.14,1.28,.11),Color("#b8ae92"))
	var pane := _rental_part(root,Vector3(0,0,.068),Vector3(width,1.13,.045),Color("#b9cbd0"))
	var daylight := StandardMaterial3D.new()
	daylight.albedo_color = Color("#c8d6d7")
	daylight.emission_enabled = true
	daylight.emission = Color("#a1bcc3")
	daylight.emission_energy_multiplier = .38
	pane.material_override = daylight
	var window_id := str(home_windows.size())
	var saved: Dictionary = state.get("window_states",{}).get(window_id,{})
	var window_open := bool(saved.get("window",false))
	var curtains_open := bool(saved.get("curtain",true))
	var slats: Array[Node3D] = []
	for i in range(8):
		var slat := _rental_part(root,Vector3(0,-.49+float(i)*.14,.112),Vector3(width,.115,.047),Color("#b5c5c3"))
		slat.rotation.x = -1.22 if window_open else -.30
		slats.append(slat)
	for x in [-width*.5,width*.5,0.0]:
		_rental_part(root,Vector3(float(x),0,.14),Vector3(.042,1.17,.06),Color("#66797a"))
	_rental_part(root,Vector3(0,-.66,.17),Vector3(width+.23,.065,.28),Color("#b9af98"))
	_rental_part(root,Vector3(0,.74,.24),Vector3(width+.48,.045,.05),Color("#78634f"))
	var curtains: Array[Node3D] = []
	for side in [-1.0,1.0]:
		var curtain := _rental_root(root,Vector3(float(side)*width*.25,0,.22))
		for k in range(9):
			var fold := _rental_part(curtain,Vector3(-width*.25+width*.5*(float(k)+.5)/9.0,-.01,float(k%2)*.045),Vector3(width*.5/9.0+.018,1.46,.06),Color("#ded3bd").darkened(float(k%2)*.035))
			fold.rotation.z = float(side)*.015
		curtain.scale.x = .30 if curtains_open else 1.0
		curtain.position.x = float(side)*width*(.45 if curtains_open else .25)
		curtains.append(curtain)
	# Window light is a stationary source facing into the room. It does not
	# depend on the room occupied by the player or on the camera direction.
	var window_light := SpotLight3D.new()
	root.add_child(window_light)
	window_light.position = Vector3(0,.12,.32)
	window_light.rotation = Vector3(-.20,PI,0)
	window_light.spot_range = 7.2
	window_light.spot_angle = 62.0
	window_light.spot_attenuation = 1.15
	window_light.spot_angle_attenuation = .75
	window_light.light_color = Color("#dce9f6")
	window_light.light_energy = 0.0
	window_light.shadow_bias = .10
	window_light.shadow_normal_bias = .6
	window_light.hide()
	home_windows.append({"root":root,"width":width,"slats":slats,"curtains":curtains,"window":window_open,"curtain":curtains_open,"id":window_id,"pane_material":daylight,"room":_home_room_at(at),"daylight_source":window_light})

func _rental_fixture(parent: Node3D,at: Vector3) -> void:
	_rental_cylinder(parent,at+Vector3.UP*.08,.13,.07,Color("#aaa38e"))
	var fixture := _rental_cylinder(parent,at,.19,.075,Color("#fff1d5"))
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("#fff0d1")
	glow.emission_enabled = true
	glow.emission = Color("#fff0d1")
	glow.emission_energy_multiplier = .75
	fixture.material_override = glow
	var key := _home_room_at(at)
	if not home_fixture_materials.has(key): home_fixture_materials[key] = []
	home_fixture_materials[key].append(glow)
	glow.emission_enabled = bool(state.home_lights.get(key,true))

func _rental_wall_frame(parent: Node3D,at: Vector3,angle: float,paint: Color) -> void:
	var root := _rental_root(parent,at,angle)
	_rental_part(root,Vector3.ZERO,Vector3(.44,.56,.045),Color("#76573e"))
	_rental_part(root,Vector3(0,0,.028),Vector3(.37,.49,.018),Color("#e7ddc6"))
	_rental_part(root,Vector3(0,-.04,.041),Vector3(.27,.26,.010),paint)
	_rental_part(root,Vector3(0,-.095,.048),Vector3(.22,.09,.010),paint.darkened(.22))

func _build_rental_fridge() -> void:
	if is_instance_valid(rental_fridge): return
	# Use the same room-local coordinates as the kitchen counter. The
	# appliance faces into the room and is present before any story starts.
	rental_fridge = _rental_root(interior,RENTAL_FRIDGE_LOCAL,PI*.5)
	rental_fridge.name = "RefrigeradorCocina"
	var ivory := Color("#e8e9e5")
	var shell := Color("#c3cbc7")
	var lining := Color("#e1e7e3")
	var edge := Color("#8c9894")
	var body := StaticBody3D.new()
	home_food_fridge_body = body
	rental_fridge.add_child(body)
	body.position.y = .95
	body.collision_layer = 1
	body.collision_mask = 0
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.84,1.90,.74)
	collision.shape = shape
	body.add_child(collision)
	# Explicit closed outer cabinet, dark seal, and solid shelves.
	_rental_part(rental_fridge,Vector3(0,.95,-.34),Vector3(.84,1.90,.06),shell)
	for x in [-.39,.39]:
		_rental_part(rental_fridge,Vector3(float(x),.95,0),Vector3(.06,1.90,.74),shell)
	for y in [.06,1.26,1.87]:
		_rental_part(rental_fridge,Vector3(0,float(y),0),Vector3(.79,.06,.70),lining)
	for y in [.45,.85]:
		_rental_part(rental_fridge,Vector3(0,float(y),0),Vector3(.75,.035,.65),lining)
	_rental_part(rental_fridge,Vector3(0,.038,0),Vector3(.72,.075,.65),edge)
	for key in ["pollo","huevos"]:
		var top: bool = String(key)=="pollo"
		var hinge := _rental_root(rental_fridge,Vector3(-.412,1.29 if top else .10,.375))
		var height := .57 if top else 1.14
		_rental_part(hinge,Vector3(.412,height*.5,0),Vector3(.815,height,.08),edge)
		_rental_part(hinge,Vector3(.412,height*.5,.037),Vector3(.79,height-.018,.062),ivory)
		_rental_part(hinge,Vector3(.70,height*.72,.085),Vector3(.045,.22,.058),Color("#626b68"))
		rental_fridge_doors[key] = hinge
		_register_storage_door(hinge,Vector3(.412,height*.5,.05),Vector3(.82,height,.13),"congelador" if top else "refrigerador")
	_build_home_food_fridge()
	print("MyCity: refrigerador de cocina creado en ",rental_fridge.global_position)

func _register_storage_door(hinge: Node3D,center: Vector3,size: Vector3,label_text: String) -> void:
	rental_storage_doors.append({"hinge":hinge,"center":center,"size":size,"label":label_text,"tween":null})

func _make_storage_leaf(root: Node3D,x: float,y: float,z: float,w: float,h: float,label_text: String,paint: Color) -> Node3D:
	var hinge := _rental_root(root,Vector3(x-w*.5,y-h*.5,z))
	_rental_part(hinge,Vector3(w*.5,h*.5,0),Vector3(w,h,.05),paint)
	_rental_part(hinge,Vector3(w*.77,h*.73,.035),Vector3(.12,.035,.035),Color("#77756a"))
	_register_storage_door(hinge,Vector3(w*.5,h*.5,.02),Vector3(w,h,.10),label_text)
	return hinge

# The rendered door leaves are not physics bodies. Include their current
# hinge transform in interaction rays, so they occlude objects behind them.
func _storage_leaf_depth(entry: Dictionary,origin: Vector3,end: Vector3) -> float:
	var hinge: Node3D = entry.hinge
	if not is_instance_valid(hinge) or hinge.is_queued_for_deletion() or not hinge.is_visible_in_tree(): return INF
	var center: Vector3 = entry.center
	var size: Vector3 = entry.size
	var hit: Variant = AABB(center-size*.5,size).intersects_segment(hinge.to_local(origin),hinge.to_local(end))
	if hit==null: return INF
	return origin.distance_to(hinge.to_global(Vector3(hit)))

func _door_blocks_target(origin: Vector3,point: Vector3,target: Node3D = null) -> bool:
	if not inside or not game.adaptation_mode: return false
	var depth := origin.distance_to(point)
	for entry in rental_storage_doors:
		var hinge: Node3D = entry.hinge
		if not is_instance_valid(hinge): continue
		if target!=null and (hinge==target or hinge.is_ancestor_of(target)): continue
		if _storage_leaf_depth(entry,origin,point)<depth-.008: return true
	return false

func _aimed_storage_door(at: Vector3) -> Dictionary:
	if not inside or not game.adaptation_mode: return {}
	var cam: Camera3D = game.play_camera
	var origin: Vector3 = cam.global_position
	var end: Vector3 = origin-cam.global_basis.z*2.8
	var best: Dictionary = {}
	var distance := INF
	for entry in rental_storage_doors:
		var d := _storage_leaf_depth(entry,origin,end)
		if not is_finite(d) or d>=distance: continue
		var p := origin+(end-origin).normalized()*d
		if at.distance_to(p)>2.8: continue
		# The leaf is visual; reject other solid objects in front of it.
		var ray := PhysicsRayQueryParameters3D.create(origin,origin+(p-origin).normalized()*maxf(.01,d-.10),1|4|8|16|32)
		ray.exclude = [game.player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		best = entry
		distance = d
	return best

func storage_action(at: Vector3) -> String:
	var entry := _aimed_storage_door(at)
	if entry.is_empty(): return ""
	var hinge: Node3D = entry.hinge
	return "[E] "+("Cerrar " if absf(hinge.rotation.y)>=.10 else "Abrir ")+String(entry.label)

func storage_safe_angle(hinge: Node3D,requested: float) -> float:
	var entry: Dictionary = {}
	for candidate in rental_storage_doors:
		if candidate.hinge==hinge:
			entry = candidate
			break
	if entry.is_empty(): return hinge.rotation.y
	var size: Vector3 = entry.size
	var center: Vector3 = entry.center
	var shape := BoxShape3D.new()
	# Slight clearance at the hinge avoids touching the cabinet's own frame.
	shape.size = Vector3(maxf(.02,size.x-.045),maxf(.02,size.y-.035),size.z*.5)
	center.z += .012
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1|4|8|16|32
	var space := get_world_3d().direct_space_state
	var from: float = hinge.rotation.y
	var safe := from
	var parent: Node3D = hinge.get_parent()
	var steps := maxi(1,ceili(absf(requested-from)/.035))
	for i in range(1,steps+1):
		var angle := lerpf(from,requested,float(i)/float(steps))
		var pose := parent.global_transform*Transform3D(Basis(Vector3.UP,angle),hinge.position)
		q.transform = Transform3D(pose.basis,pose*center)
		if not space.intersect_shape(q,1).is_empty(): break
		safe = angle
	return safe

func apply_storage_angle(requested: float,hinge: Node3D) -> void:
	if is_instance_valid(hinge): hinge.rotation.y = storage_safe_angle(hinge,requested)

func storage_interact(at: Vector3) -> bool:
	var entry := _aimed_storage_door(at)
	if entry.is_empty(): return false
	var hinge: Node3D = entry.hinge
	var previous: Tween = entry.get("tween")
	if is_instance_valid(previous): previous.kill()
	var opening := absf(hinge.rotation.y)<.10
	var requested := -1.45 if opening else 0.0
	var allowed := storage_safe_angle(hinge,requested)
	if absf(allowed-requested)>.06:
		business._notify("Hay un obstáculo en el recorrido de la puerta.")
	var tween := create_tween()
	entry.tween = tween
	tween.tween_method(apply_storage_angle.bind(hinge),hinge.rotation.y,allowed,.38).set_trans(Tween.TRANS_SINE)
	return true

func show_rental_oil(stored: bool) -> void:
	if not is_instance_valid(rental_kitchen): return
	if stored and not is_instance_valid(rental_oil):
		# The crate rests on the lower cabinet floor, behind its hinged door.
		rental_oil = business._crate(rental_kitchen,Vector3(.65,.24,-.02),"aceite")
		rental_oil.scale = Vector3.ONE*.80
	if is_instance_valid(rental_oil): rental_oil.visible = stored

func _decorate_rental_home() -> void:
	var decor := _rental_root(interior,Vector3.ZERO)
	decor.name = "RentalHomeDetails"
	var trim := Color("#948775")
	# Skirting and ceiling coves stay outside the paint and floor-mark surfaces.
	for x in [-6.76,6.76]:
		_rental_part(decor,Vector3(float(x),.077,0),Vector3(.055,.15,11.6),trim)
		_rental_part(decor,Vector3(float(x),2.93,0),Vector3(.07,.07,11.6),Color("#d2c8b3"))
	_rental_part(decor,Vector3(0,.077,-5.76),Vector3(13.6,.15,.055),trim)
	for seg in [Vector2(-4.01,5.42),Vector2(3.23,6.72)]:
		_rental_part(decor,Vector3(seg.x,.077,5.76),Vector3(seg.y,.15,.055),trim)
	_rental_part(decor,Vector3(0,2.93,-5.76),Vector3(13.6,.07,.07),Color("#d2c8b3"))
	_rental_part(decor,Vector3(0,2.93,5.76),Vector3(13.6,.07,.07),Color("#d2c8b3"))
	# The original doorway and suitcase drop point remain unobstructed.
	for x in [-1.34,-.06]:
		_rental_part(decor,Vector3(float(x),1.14,5.69),Vector3(.08,2.28,.12),Color("#8a7057"))
	_rental_part(decor,Vector3(-.70,2.28,5.69),Vector3(1.36,.10,.12),Color("#8a7057"))
	for x in [.18,.99]:
		_rental_part(guest_door,Vector3(float(x),1.10,-.064),Vector3(.065,1.72,.035),Color("#83654f"))
	for y in [.28,1.10,1.92]:
		_rental_part(guest_door,Vector3(.60,float(y),-.064),Vector3(.87,.065,.035),Color("#83654f"))
	# Simple jalousies, curtains and wall decoration, away from the doorway.
	_rental_window(decor,Vector3(-6.76,1.83,3.25),PI*.5,1.60)
	_rental_window(decor,Vector3(-4.45,1.78,-5.76),0.0,1.45)
	# Keep the east window clear of the bathroom partition and mirror.
	_rental_window(decor,Vector3(6.76,2.0,2.35),-PI*.5,1.50)
	_rental_wall_frame(decor,Vector3(-3.4,1.9,-2.18),0.0,Color("#8b9e8b"))
	_rental_wall_frame(decor,Vector3(-2.72,1.9,-2.18),0.0,Color("#b59872"))
	# A low woven mat under the living-room area, below the existing
	# sweepable floor overlay at y=.036.
	_rental_part(decor,Vector3(-4.1,.012,2.68),Vector3(2.68,.020,2.40),Color("#a49a84"))
	for i in range(12):
		_rental_part(decor,Vector3(-4.1,.025,1.59+float(i)*.198),Vector3(2.58,.007,.055),Color("#807968").lightened(float(i%3)*.05))
	# Fixed kitchen counter against west wall, with the permanent refrigerator
	# immediately beside it and both facing into the room.
	var kitchen := _rental_root(decor,Vector3(-6.34,0,-.65),PI*.5)
	rental_kitchen = kitchen
	var cabinet_body := _solid(kitchen,Vector3(.25,.44,0),Vector3(2.50,.88,.66),Color("#a39b82"))
	rice_cabinet_body = cabinet_body
	cabinet_body.get_child(0).hide()
	var wood := Color("#a39b82")
	_rental_part(kitchen,Vector3(.25,.07,0),Vector3(2.5,.07,.66),wood)
	_rental_part(kitchen,Vector3(.25,.44,-.31),Vector3(2.5,.82,.04),wood)
	for x in [-.98,-.325,.325,.98,1.48]:
		_rental_part(kitchen,Vector3(float(x),.44,0),Vector3(.04,.82,.66),wood)
	_solid(kitchen,Vector3(.25,.91,0),Vector3(2.58,.09,.72),Color("#777d76"))
	for x in [-.65,0.0,.65]:
		var leaf := _make_storage_leaf(kitchen,float(x),.46,.345,.59,.66,"armario inferior",Color("#c9bda1"))
		if absf(float(x))<.01: rice_doors["arroz"] = leaf
	_make_storage_leaf(kitchen,1.24,.46,.345,.44,.66,"armario inferior",Color("#c9bda1"))
	_rental_part(kitchen,Vector3(-.54,.963,0),Vector3(.61,.022,.47),Color("#b4bfc0"))
	_rental_part(kitchen,Vector3(-.54,.98,0),Vector3(.47,.018,.34),Color("#596669"))
	kitchen_tap = _rental_root(kitchen,Vector3(-.54,1.07,-.25))
	_rental_cylinder(kitchen_tap,Vector3.ZERO,.027,.22,Color("#a9b5b5"))
	_rental_part(kitchen_tap,Vector3(0,.11,.09),Vector3(.052,.045,.19),Color("#a9b5b5"))
	tap_water = _rental_cylinder(kitchen_tap,Vector3(0,.005,.17),.014,.19,Color("#9dc5cf"))
	tap_water.hide()
	dish_sponge = _rental_root(kitchen,Vector3(-.20,.968,.08))
	_draw_dish_sponge(dish_sponge)
	_make_dish_hint()
	_rental_part(kitchen,Vector3(.55,.975,0),Vector3(.62,.06,.49),Color("#454947"))
	for x in [.39,.69]:
		for z in [-.12,.12]:
			_rental_cylinder(kitchen,Vector3(float(x),1.02,float(z)),.10,.025,Color("#272b29"))
	_build_home_pan(kitchen)
	var upper_wood := Color("#bcb098")
	for y in [1.66,1.88,2.10]:
		_rental_part(kitchen,Vector3(0,float(y),-.25),Vector3(1.95,.035,.26),upper_wood)
	_rental_part(kitchen,Vector3(0,1.88,-.37),Vector3(1.95,.46,.035),upper_wood)
	for x in [-.96,-.315,.315,.96]:
		_rental_part(kitchen,Vector3(float(x),1.88,-.25),Vector3(.035,.46,.26),upper_wood)
	for x in [-.63,0.0,.63]:
		var leaf := _make_storage_leaf(kitchen,float(x),1.88,-.10,.60,.40,"armario superior",Color("#cec3ac"))
		if float(x)<-.5: rice_doors["sal"] = leaf
		elif absf(float(x))<.01: rice_doors["aceite"] = leaf
		else: home_plate_door = leaf
	_build_home_plate_stack(kitchen)
	_build_rice_kitchen(kitchen)
	var adaptation: Dictionary = business.ledger.life_data.get("adaptation",{})
	var stock: Dictionary = adaptation.get("investment_boxes",{})
	show_rental_oil(String(stock.get("aceite",""))=="stored")
	# Small CRT and stand along the south wall, outside the luggage area.
	var tv := _rental_root(decor,Vector3(-4.65,0,5.44),PI)
	television = tv
	_solid(tv,Vector3(0,.36,0),Vector3(1.25,.72,.44),Color("#78614a"))
	_rental_part(tv,Vector3(0,.40,.23),Vector3(1.12,.46,.035),Color("#8b7155"))
	_rental_part(tv,Vector3(0,.55,.26),Vector3(.18,.035,.04),Color("#b8a98b"))
	_rental_part(tv,Vector3(0,.98,0),Vector3(.61,.49,.43),Color("#4c504c"))
	television_screen = _rental_round(tv,Vector3(-.055,.99,.226),Vector3(.43,.33,.06),Color("#666e69"))
	_rental_cylinder(tv,Vector3(.24,.98,.233),.045,.034,Color("#b4b0a0")).rotation.x = PI*.5
	for i in range(4):
		_rental_part(tv,Vector3(.24,.87+float(i)*.021,.24),Vector3(.07,.008,.01),Color("#242a28"))
	# Bedside shelf and small lamp do not alter the movable bed.
	var bedside := _rental_root(decor,Vector3(-6.40,0,-4.60))
	_solid(bedside,Vector3(0,.31,0),Vector3(.54,.62,.46),Color("#82694e"))
	# A real hollow drawer, with a moving front and a bottom.
	var bedside_body: Node3D = bedside.get_child(0)
	bedside_body.get_child(0).hide()
	_rental_part(bedside,Vector3(0,.05,0),Vector3(.54,.10,.46),Color("#82694e"))
	_rental_part(bedside,Vector3(0,.59,0),Vector3(.54,.06,.46),Color("#82694e"))
	_rental_part(bedside,Vector3(0,.31,-.21),Vector3(.54,.52,.04),Color("#82694e"))
	for x in [-.25,.25]: _rental_part(bedside,Vector3(float(x),.31,0),Vector3(.04,.52,.46),Color("#82694e"))
	bedside_drawer = _rental_root(bedside,Vector3(0,.39,0))
	_rental_part(bedside_drawer,Vector3(0,0,.24),Vector3(.45,.20,.035),Color("#9b8062"))
	_rental_part(bedside_drawer,Vector3(0,.01,.27),Vector3(.14,.04,.04),Color("#c4b18f"))
	_rental_part(bedside_drawer,Vector3(0,-.085,0),Vector3(.43,.03,.43),Color("#8a6d51"))
	for x in [-.21,.21]: _rental_part(bedside_drawer,Vector3(float(x),-.025,0),Vector3(.025,.14,.43),Color("#8a6d51"))
	_rental_part(bedside_drawer,Vector3(0,-.025,-.20),Vector3(.43,.14,.025),Color("#8a6d51"))
	bedside_lamp = _rental_root(bedside,Vector3(0,.65,0))
	_rental_cylinder(bedside_lamp,Vector3.ZERO,.11,.045,Color("#81715b"))
	_rental_cylinder(bedside_lamp,Vector3(0,.14,0),.025,.24,Color("#81715b"))
	_rental_round(bedside_lamp,Vector3(0,.30,0),Vector3(.34,.29,.34),Color("#e2cba3"))
	bedside_glow = OmniLight3D.new()
	bedside_lamp.add_child(bedside_glow)
	bedside_glow.position.y = .30
	bedside_glow.light_color = Color("#ffe1ae")
	bedside_glow.light_energy = .7
	bedside_glow.omni_range = 2.8
	bedside_glow.visible = bool(state.get("bedside_light",false))
	# Domestic light fixtures and a third light in the formerly dark bedroom.
	for at in [Vector3(-3.7,2.88,1.2),Vector3(-1.85,2.88,4.45),Vector3(3.7,2.88,-2.35),Vector3(3.7,2.88,2.65),Vector3(-3.9,2.88,-4.0)]:
		_rental_fixture(decor,at)
	var bedroom_light := OmniLight3D.new()
	decor.add_child(bedroom_light)
	bedroom_light.position = Vector3(-3.9,2.65,-4.0)
	bedroom_light.light_color = Color("#fff0db")
	bedroom_light.light_energy = .85
	bedroom_light.omni_range = 5.0
	bedroom_light.omni_attenuation = 1.25
	_register_room_light("dormitorio",bedroom_light)
	_make_light_switch(decor,"sala",Vector3(-1.65,1.35,5.67),PI)
	_make_light_switch(decor,"dormitorio",Vector3(-2.80,1.35,-2.19),0.0)
	_make_light_switch(decor,"garaje",Vector3(.04,1.35,2.60),PI*.5)
	# Garage remains a usable workspace; only wall storage is decorative.
	var storage := _rental_root(decor,Vector3(6.43,0,-.5),-PI*.5)
	_rental_part(storage,Vector3(0,1.67,-.19),Vector3(2.2,.72,.04),Color("#9b8c70"))
	for y in [1.38,1.78]:
		_rental_part(storage,Vector3(0,float(y),0),Vector3(2.2,.07,.36),Color("#79694e"))
	for x in [-.76,0.0,.76]:
		_rental_part(storage,Vector3(float(x),1.55,0),Vector3(.22,.22,.23),Color("#a09b86"))
	for x in [-.64,.64]:
		_rental_part(storage,Vector3(float(x),1.19,-.15),Vector3(.055,.31,.05),Color("#515c5b"))
	# Clock uses fixed decorative hands, not a simulated time display.
	var clock := _rental_root(decor,Vector3(-.20,2.37,3.00),-PI*.5)
	_rental_cylinder(clock,Vector3.ZERO,.20,.05,Color("#765c45")).rotation.x = PI*.5
	_rental_cylinder(clock,Vector3(0,0,.033),.177,.025,Color("#e8e2d1")).rotation.x = PI*.5
	wall_hour_hand = _rental_root(clock,Vector3(0,0,.055))
	_rental_part(wall_hour_hand,Vector3(0,.052,0),Vector3(.018,.105,.009),Color("#44423a"))
	wall_minute_hand = _rental_root(clock,Vector3(0,0,.064))
	_rental_part(wall_minute_hand,Vector3(0,.073,0),Vector3(.014,.146,.009),Color("#44423a"))
	_build_home_coffee(kitchen)
	_refresh_tv_screen()
	_update_wall_clock()

func _build_rental_bathroom() -> void:
	var root := _rental_root(interior,Vector3.ZERO)
	root.name = "RentalBathroom"
	var wall := Color("#dedbd0")
	var tile := Color("#d5ddd7")
	# Bathroom in the unused northeast corner. Entrance faces west.
	_solid(root,Vector3(5.45,1.5,-3.35),Vector3(2.65,3,.13),wall).set_meta("broom_support_wall",true)
	_solid(root,Vector3(4.15,1.5,-5.26),Vector3(.13,3,.95),wall).set_meta("broom_support_wall",true)
	_solid(root,Vector3(4.15,1.5,-3.60),Vector3(.13,3,.50),wall).set_meta("broom_support_wall",true)
	_solid(root,Vector3(4.15,2.65,-4.42),Vector3(.15,.70,1.17),wall)
	# Real colliding leaf, hinged inward. The player cannot walk through it.
	bath_door = _rental_root(root,Vector3(4.22,0,-4.74),clampf(float(state.bathroom.door),0.0,PI*.5))
	bath_door_target = bath_door.rotation.y
	bath_door_body = _solid(bath_door,Vector3(0,1.06,.42),Vector3(.055,2.06,.84),Color("#8a6d54"))
	for side in [-1.0,1.0]:
		_rental_part(bath_door,Vector3(float(side)*.052,1.03,.73),Vector3(.065,.045,.13),Color("#c9b27d"))
	_rental_part(root,Vector3(5.49,.025,-4.54),Vector3(2.52,.03,2.28),tile)
	for x in range(7):
		_rental_part(root,Vector3(4.25+float(x)*.39,.043,-4.54),Vector3(.016,.006,2.28),Color("#9ea9a4"))
	for z in range(6):
		_rental_part(root,Vector3(5.48,.043,-5.60+float(z)*.40),Vector3(2.48,.006,.016),Color("#9ea9a4"))
	# Basin against east wall, player stands at x=5.6 facing east.
	var sink := _rental_root(root,Vector3(6.36,0,-4.42),-PI*.5)
	bath_sink = sink
	bath_sink_body = _solid(sink,Vector3(0,.42,0),Vector3(.43,.84,.35),Color("#e5e3d7"))
	_rental_round(sink,Vector3(0,.88,.02),Vector3(.76,.22,.54),Color("#efeee6"))
	_rental_round(sink,Vector3(0,.96,.065),Vector3(.49,.055,.34),Color("#99afb0"))
	_rental_cylinder(sink,Vector3(0,1.02,-.18),.026,.14,Color("#a6b2b1"))
	_rental_part(sink,Vector3(0,1.10,-.12),Vector3(.048,.045,.16),Color("#b0bdbd"))
	bath_water = _rental_cylinder(sink,Vector3(0,1.01,-.045),.011,.145,Color("#a5c8d1"))
	bath_water.hide()
	_rental_part(sink,Vector3(0,1.64,-.31),Vector3(.58,.66,.05),Color("#8c8274"))
	var mirror := _rental_part(sink,Vector3(0,1.64,-.277),Vector3(.50,.58,.012),Color("#a9c1c7"))
	var mirror_mat := StandardMaterial3D.new()
	mirror_mat.albedo_color = Color("#a7bfc4")
	mirror_mat.metallic = .6
	mirror_mat.roughness = .22
	mirror.material_override = mirror_mat
	_rental_cylinder(sink,Vector3(.28,.995,-.10),.06,.12,Color("#749da0"))
	_rental_part(sink,Vector3(.28,1.10,-.10),Vector3(.018,.19,.018),Color("#cfbd80"))
	_rental_part(sink,Vector3(.28,1.20,-.10),Vector3(.028,.055,.018),Color("#eee5d6"))
	var toilet := _rental_root(root,Vector3(5.35,0,-5.27))
	bath_toilet = toilet
	bath_toilet_body = _solid(toilet,Vector3(0,.23,0),Vector3(.44,.46,.62),Color("#e5e2d8"))
	_rental_round(toilet,Vector3(0,.46,.08),Vector3(.52,.17,.66),Color("#f4f1e7"))
	bath_bowl_water = _rental_round(toilet,Vector3(0,.53,.09),Vector3(.35,.045,.43),Color("#a8b6b2"))
	_rental_part(toilet,Vector3(0,.72,-.26),Vector3(.46,.48,.22),Color("#efede2"))
	_rental_part(toilet,Vector3(0,.98,-.26),Vector3(.48,.06,.25),Color("#f5f2e8"))
	_rental_part(toilet,Vector3(.16,.87,-.13),Vector3(.075,.032,.035),Color("#a9b4b4"))
	_rental_part(root,Vector3(5.35,1.33,-3.45),Vector3(.60,.05,.08),Color("#9caaa9"))
	_rental_part(root,Vector3(5.35,1.12,-3.51),Vector3(.48,.45,.045),Color("#96a69c"))
	_rental_fixture(root,Vector3(5.35,2.87,-4.45))
	var light := OmniLight3D.new()
	root.add_child(light)
	light.position = Vector3(5.45,2.65,-4.43)
	light.omni_range = 3.8
	light.light_energy = .9
	light.light_color = Color("#fff1dd")
	_register_room_light("baño",light)
	_make_light_switch(root,"baño",Vector3(4.06,1.35,-3.75),-PI*.5)
	_make_bath_hint()

func _make_bath_hint() -> void:
	bath_hint = Label.new()
	business.layer.add_child(bath_hint)
	bath_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	bath_hint.offset_left = -310
	bath_hint.offset_right = 310
	bath_hint.offset_top = 115
	bath_hint.offset_bottom = 145
	bath_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bath_hint.add_theme_font_size_override("font_size",17)
	bath_hint.add_theme_color_override("font_color",Color("#e9e9cf"))
	bath_hint.add_theme_color_override("font_outline_color",Color.BLACK)
	bath_hint.add_theme_constant_override("outline_size",5)
	bath_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bath_hint.hide()

func _bath_aim_body(body: StaticBody3D) -> bool:
	if not is_instance_valid(body): return false
	var cam: Camera3D = game.play_camera
	var query := PhysicsRayQueryParameters3D.create(cam.global_position,cam.global_position-cam.global_basis.z*2.6,1|2|4|8|16|32)
	query.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider==body

func _bath_action() -> String:
	if not inside or not game.adaptation_mode or not is_instance_valid(bath_door): return ""
	if not bath_mode.is_empty(): return "[E] "+("Lavando las manos…" if bath_mode=="wash" else "Usando el baño…")
	if _bath_aim_body(bath_door_body):
		return "[E] "+("Cerrar puerta del baño" if bath_door.rotation.y>.12 else "Abrir puerta del baño")
	if not _free_hands(): return ""
	if _bath_aim_body(bath_toilet_body) or _aim_tool(bath_toilet,Vector3(0,.59,.03),Vector3(.27,.43,.34)):
		if bool(state.bathroom.flush): return "[E] Descargar el inodoro"
		return "[E] Usar el inodoro"
	if _bath_aim_body(bath_sink_body) or _aim_tool(bath_sink,Vector3(0,1.02,.02),Vector3(.37,.16,.27)):
		return "[E] Lavarse las manos"
	return ""

func _bath_interact() -> bool:
	var action := _bath_action()
	if action.is_empty(): return false
	if not bath_mode.is_empty(): return true
	if action.contains("puerta del baño"):
		bath_door_target = 0.0 if bath_door.rotation.y>.12 else PI*.5
		bath_door_moving = true
	elif action=="[E] Descargar el inodoro":
		state.bathroom.flush = false
		bath_flush_seconds = 1.8
		business._notify("Inodoro descargado. Lávate las manos en el lavamanos.")
		_save()
	elif action=="[E] Usar el inodoro":
		_start_bath_action("sit" if randf()<.40 else "stand")
	elif action=="[E] Lavarse las manos":
		_start_bath_action("wash")
	return true

func _bath_position_clear(at: Vector3,ignore: StaticBody3D = null) -> bool:
	var actor: CharacterBody3D = game.player
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = game.player_shape.shape
	q.transform = Transform3D(Basis.IDENTITY,at)
	q.collision_mask = 1|4|8|16|32
	var excluded: Array[RID] = [actor.get_rid()]
	if is_instance_valid(ignore): excluded.append(ignore.get_rid())
	q.exclude = excluded
	return get_world_3d().direct_space_state.intersect_shape(q,1).is_empty()

func _show_bath_legs(mode: String,heading: float) -> void:
	# World-space lower body: independent of camera pitch and not a HUD overlay.
	if is_instance_valid(bath_lower_body): bath_lower_body.queue_free()
	bath_lower_body = _rental_root(game.player,Vector3.ZERO)
	bath_lower_body.rotation.y = heading+PI
	var seated := mode=="sit"
	for i in range(2):
		var x := -.135 if i==0 else .135
		var source: Node3D = game.limb_legs[i]
		var original_leg: MeshInstance3D = source.get_node("Leg")
		var original_shoe: MeshInstance3D = source.get_node("Shoe")
		if seated:
			# Thighs follow the seat, knees bend at the front of the bowl,
			# and the soles rest on the tiled floor in front of the toilet.
			var thigh := _rental_round(bath_lower_body,Vector3(x,-.105,.19),Vector3(.21,.45,.22),Color("#192e57"))
			thigh.rotation.x = -PI*.5
			thigh.material_override = original_leg.material_override
			var knee := _rental_round(bath_lower_body,Vector3(x,-.15,.39),Vector3(.21,.23,.22),Color("#192e57"))
			knee.material_override = original_leg.material_override
			var shin := _rental_round(bath_lower_body,Vector3(x,-.365,.43),Vector3(.18,.47,.19),Color("#192e57"))
			shin.material_override = original_leg.material_override
		else:
			var leg := _rental_round(bath_lower_body,Vector3(x,-.42,0),Vector3(.22,.64,.23),Color("#192e57"))
			leg.material_override = original_leg.material_override
		var shoe := MeshInstance3D.new()
		shoe.mesh = original_shoe.mesh
		shoe.material_override = original_shoe.material_override
		shoe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bath_lower_body.add_child(shoe)
		shoe.scale = original_shoe.scale
		shoe.position = Vector3(x,-.60 if seated else -.74,.53 if seated else .075)

func _start_bath_action(mode: String) -> void:
	if not bath_mode.is_empty() or not _free_hands(): return
	var actor: CharacterBody3D = game.player
	var target := bath_toilet.to_global(Vector3(0,.86,.83))
	var heading := 0.0
	var pitch := -.48
	if mode=="wash":
		target = bath_sink.to_global(Vector3(0,.86,.68))
		heading = bath_sink.global_rotation.y
		pitch = -.58
	elif mode=="sit":
		target = bath_toilet.to_global(Vector3(0,.72,.12))
		heading = PI
		pitch = -.13
	var ignored: StaticBody3D = bath_toilet_body if mode=="sit" else null
	if not _bath_position_clear(target,ignored) or actor.global_position.distance_to(target)>2.25:
		business._notify("Acércate al baño y deja espacio libre.")
		return
	# Do not teleport across a closed door or other intervening solid.
	var path := PhysicsRayQueryParameters3D.create(actor.global_position,target,1|4|8|16|32)
	var excludes: Array[RID] = [actor.get_rid()]
	if is_instance_valid(ignored): excludes.append(ignored.get_rid())
	path.exclude = excludes
	if not get_world_3d().direct_space_state.intersect_ray(path).is_empty():
		business._notify("El acceso está bloqueado.")
		return
	bath_return = actor.global_position
	bath_old_first = game.first_person
	bath_old_yaw = game.yaw
	bath_old_pitch = game.pitch
	bath_mode = mode
	bath_seconds = randf_range(7.0,10.0) if mode=="sit" else (randf_range(3.5,5.5) if mode=="stand" else 4.5)
	actor.velocity = Vector3.ZERO
	if mode=="sit": game.player_shape.set_deferred("disabled",true)
	actor.global_position = target
	game.first_person = true
	game.yaw = heading
	game.pitch = pitch
	game.pivot.rotation = Vector3(pitch,heading,0)
	game._apply_camera_mode()
	_show_bath_legs(mode,heading)
	if mode=="wash":
		bath_water.show()
		bath_wash_model = _rental_root(bath_sink,Vector3(0,1.025,.045))
		bath_left_hand = _attach_interaction_hand(bath_wash_model,Vector3(-.027,0,.08),true,true)
		bath_right_hand = _attach_interaction_hand(bath_wash_model,Vector3(.027,.037,.08))
		# Palms overlap lightly, fingertips face the faucet, wrists face the body.
		bath_left_hand.basis = Basis(Vector3.UP,PI*.5)*Basis(Vector3.RIGHT,PI)
		bath_right_hand.rotation = Vector3(0,-PI*.5,0)
		var shirt: MeshInstance3D = game.avatar.get_node("Shirt")
		bath_left_hand.configure_body_arm(bath_sink,Vector3(-.19,1.25,.74),Vector3(-.19,1.065,.46),shirt.material_override)
		bath_right_hand.configure_body_arm(bath_sink,Vector3(.19,1.25,.74),Vector3(.19,1.065,.46),shirt.material_override)
		bath_soap_foam = _rental_root(bath_wash_model,Vector3(0,.031,.05))
		for i in range(8):
			var a := float(i)*2.4
			_rental_round(bath_soap_foam,Vector3(cos(a)*.04,.008,sin(a)*.025),Vector3(.012,.009,.012),Color("#f2f2e9"))
		bath_soap_foam.hide()
	business._notify("Lavándote las manos." if mode=="wash" else ("Usando el inodoro sentado." if mode=="sit" else "Usando el inodoro de pie."))

func _finish_bath_action(completed: bool = true) -> void:
	if bath_mode.is_empty(): return
	var mode := bath_mode
	bath_mode = ""
	bath_seconds = 0.0
	if is_instance_valid(bath_lower_body):
		bath_lower_body.hide()
		bath_lower_body.queue_free()
	bath_lower_body = null
	if is_instance_valid(bath_water): bath_water.hide()
	if is_instance_valid(bath_wash_model): bath_wash_model.queue_free()
	bath_wash_model = null
	bath_left_hand = null
	bath_right_hand = null
	bath_soap_foam = null
	if mode=="sit":
		if inside and absf(game.player.global_position.y-ROOM.y)<12.0: game.player.global_position = bath_return
		game.player_shape.set_deferred("disabled",false)
	game.player.velocity = Vector3.ZERO
	game.first_person = bath_old_first
	game.yaw = bath_old_yaw
	game.pitch = bath_old_pitch
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	if not completed: return
	if mode=="wash":
		state.bathroom.hands_dirty = false
		business._notify("Manos limpias.")
	else:
		state.bathroom.need = 0.0
		state.bathroom.rate = randf_range(.28,.45)
		state.bathroom.hands_dirty = true
		state.bathroom.flush = true
		bath_warned = false
		business._notify("Descarga el inodoro y lávate las manos.")
	_save()

func _tick_bathroom(delta: float) -> void:
	if not game.adaptation_mode or not is_instance_valid(bath_door): return
	var data: Dictionary = state.bathroom
	var now := float(business.life.state.get("day",1))*1440.0+float(business.life.state.get("minutes",0.0))
	if bath_clock>=0.0 and bath_mode not in ["sit","stand"]:
		data.need = minf(100.0,float(data.need)+clampf(now-bath_clock,0.0,1440.0)*float(data.rate))
	bath_clock = now
	if float(data.need)>=80.0 and not bath_warned:
		bath_warned = true
		business._notify("Necesitas ir al baño pronto.")
	if bath_door_moving:
		var next := move_toward(bath_door.rotation.y,bath_door_target,delta*2.8)
		var shape := BoxShape3D.new()
		shape.size = Vector3(.060,1.99,.76)
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = shape
		q.collision_mask = 1|4|8|16|32
		q.exclude = [bath_door_body.get_rid()]
		var parent: Node3D = bath_door.get_parent()
		var pose := parent.global_transform*Transform3D(Basis(Vector3.UP,next),bath_door.position)
		q.transform = Transform3D(pose.basis,pose*Vector3(0,1.06,.42))
		if get_world_3d().direct_space_state.intersect_shape(q,1).is_empty():
			bath_door.rotation.y = next
			if absf(next-bath_door_target)<.005: bath_door_moving = false
		else:
			bath_door_moving = false
			business._notify("Hay algo bloqueando la puerta del baño.")
		if not bath_door_moving:
			data.door = bath_door.rotation.y
			_save()
	if not bath_mode.is_empty():
		if not inside or absf(game.player.global_position.y-ROOM.y)>12.0:
			_finish_bath_action(false)
		else:
			bath_seconds = maxf(0.0,bath_seconds-delta)
			if bath_mode=="wash" and is_instance_valid(bath_wash_model):
				var rubbing := bath_seconds<3.6 and bath_seconds>.7
				var wave := sin(bath_seconds*11.0)
				# Wet, rub, then slide both palms beneath the stream to rinse.
				var reach := .08 if rubbing else .025
				bath_left_hand.position = Vector3(-.027,.003,reach+(wave*.014 if rubbing else 0.0))
				bath_right_hand.position = Vector3(.027+(wave*.018 if rubbing else 0.0),.040,reach-(wave*.022 if rubbing else 0.0))
				bath_right_hand.basis = Basis(Vector3.UP,-PI*.5)*Basis(Vector3.RIGHT,wave*.10 if rubbing else 0.0)
				if is_instance_valid(bath_soap_foam): 
					bath_soap_foam.position.z = reach-.025
					bath_soap_foam.visible = rubbing
			if bath_seconds<=0.0: _finish_bath_action()
	if bath_flush_seconds>0.0:
		bath_flush_seconds = maxf(0.0,bath_flush_seconds-delta)
		bath_bowl_water.scale.y = .045*(.5+.5*absf(sin(bath_flush_seconds*9.0))) if bath_flush_seconds>0.0 else .045
	if is_instance_valid(bath_hint):
		var hint := ""
		if not business.modal_open():
			if not bath_mode.is_empty(): hint = ("Lavando manos" if bath_mode=="wash" else "Usando el baño")+" · %d s" % ceili(bath_seconds)
			elif inside and bool(data.flush): hint = "Descarga el inodoro · pulsa E mirando el inodoro"
			elif inside and bool(data.hands_dirty): hint = "Lávate las manos · pulsa E mirando el lavamanos"
			elif float(data.need)>=80.0: hint = "Necesitas ir al baño · %d%%" % roundi(float(data.need))
		if bath_hint.text!=hint: bath_hint.text = hint
		bath_hint.visible = not hint.is_empty()

func _register_room_light(key: String,light: OmniLight3D) -> void:
	if not home_room_lights.has(key): home_room_lights[key] = []
	home_room_lights[key].append(light)
	if not state.has("home_lights"): state.home_lights = {}
	light.visible = bool(state.home_lights.get(key,true))
	light.shadow_enabled = home_shadow_active and not light.has_meta("no_home_shadow")
	light.shadow_bias = .10
	light.shadow_normal_bias = .6

func _home_room_at(p: Vector3) -> String:
	if p.x>4.05 and p.z< -3.30: return "baño"
	if p.x<0.0 and p.z< -2.30: return "dormitorio"
	return "sala" if p.x<0.0 else "garaje"

func update_home_lighting(day: float,active: bool) -> float:
	if home_shadow_active!=active:
		home_shadow_active = active
		for group in home_room_lights.values():
			for light in group:
				if is_instance_valid(light): light.shadow_enabled = active and not light.has_meta("no_home_shadow")
		if is_instance_valid(bedside_glow): bedside_glow.shadow_enabled = active
	for entry in home_windows:
		var source: SpotLight3D = entry.daylight_source
		if not is_instance_valid(source): continue
		var transmission := (1.0 if bool(entry.window) else .72)*(1.0 if bool(entry.curtain) else .07)
		var strength := day*transmission
		var pane: StandardMaterial3D = entry.pane_material
		pane.emission_enabled = active and day>.025
		pane.emission_energy_multiplier = .38*day
		var visible_light := active and strength>.006
		if source.visible!=visible_light: source.visible = visible_light
		if source.shadow_enabled!=visible_light: source.shadow_enabled = visible_light
		source.light_energy = 1.65*strength
	# Constant low ambient for the entire interior. All room differences
	# are produced by fixed local lights, window transmission and shadows.
	return .009 if active else 0.0

func _make_light_switch(root: Node3D,key: String,at: Vector3,angle: float) -> void:
	var node := _rental_root(root,at,angle)
	_rental_part(node,Vector3.ZERO,Vector3(.09,.135,.025),Color("#d4c9b2"))
	var lever := _rental_part(node,Vector3(0,0,.022),Vector3(.037,.068,.025),Color("#f1e8d5"))
	home_light_switches[key] = {"node":node,"lever":lever}
	_refresh_light_switch(key)

func _refresh_light_switch(key: String) -> void:
	var on := bool(state.home_lights.get(key,true))
	for light in home_room_lights.get(key,[]):
		if is_instance_valid(light): light.visible = on
	for fixture in home_fixture_materials.get(key,[]):
		if is_instance_valid(fixture): fixture.emission_enabled = on
	var entry: Dictionary = home_light_switches.get(key,{})
	if not entry.is_empty():
		var lever: Node3D = entry.lever
		lever.rotation.x = -.32 if on else .32

func _aim_light_switch() -> String:
	for key in home_light_switches:
		if _aim_tool(home_light_switches[key].node,Vector3(0,0,.025),Vector3(.07,.09,.035)): return String(key)
	return ""

func _switch_action() -> String:
	var key := _aim_light_switch()
	if key.is_empty(): return ""
	return "[E] "+("Apagar" if bool(state.home_lights.get(key,true)) else "Encender")+" luz · "+key

func _switch_interact() -> bool:
	var key := _aim_light_switch()
	if key.is_empty(): return false
	state.home_lights[key] = not bool(state.home_lights.get(key,true))
	_refresh_light_switch(key)
	game._update_visual_lighting(true)
	var node: Node3D = home_light_switches[key].node
	var hand := _attach_interaction_hand(node,Vector3(.03,0,.055))
	get_tree().create_timer(.25).timeout.connect(hand.queue_free)
	_save()
	return true

func _attach_interaction_hand(root: Node3D,grip: Vector3,left: bool = false,under: bool = false) -> Node3D:
	var hand := InteractionHand.new()
	root.add_child(hand)
	hand.configure(grip,left,under)
	return hand

func _refresh_carried() -> void:
	if carried_view==null: return
	for child in carried_view.get_children():
		carried_view.remove_child(child)
		child.queue_free()
	carried_view.position = Vector3(.30,-.35,-.88)
	var id := String(state.held_furniture)
	if FURNITURE.has(id):
		if game.adaptation_mode:
			var size: Vector3 = FURNITURE[id].size
			var model := Node3D.new()
			carried_view.add_child(model)
			_model_rental_furniture(model,id,size)
			# Keep the recognizable model in view without covering the crosshair.
			model.scale = Vector3.ONE*minf(.75,.85/maxf(size.x,maxf(size.y,size.z)))
			model.rotation.y = -.25
		else: business._box(carried_view,Vector3.ZERO,Vector3(.50,.36,.44),FURNITURE[id].color)
	elif not String(state.home_food.hand).is_empty():
		var food_key := String(state.home_food.hand)
		carried_view.position = Vector3(.30,-.39,-.59)
		if food_key=="plato":
			carried_view.position = Vector3(-.21,-.16,-.66)
			business.life.draw_home_plate(carried_view,state.home_food.plate)
			if bool(state.home_food.plate_dirty): _draw_plate_residue(carried_view)
			_attach_interaction_hand(carried_view,Vector3(-.105,-.027,.045),true,true)
		elif food_key=="botella":
			_draw_home_water(carried_view,3)
			_attach_interaction_hand(carried_view,Vector3(.048,.09,.025))
		else:
			_draw_home_raw_food(carried_view,food_key)
			_attach_interaction_hand(carried_view,Vector3(.055,-.015,.035))
	elif bool(state.coffee_machine.rag_held):
		carried_view.position = Vector3(.29,-.37,-.52)
		_draw_coffee_rag(carried_view)
		_attach_interaction_hand(carried_view,Vector3(.065,0,.025))
	elif bool(state.coffee_machine.replacement):
		carried_view.position = Vector3(.30,-.36,-.65)
		_draw_moka_model(carried_view,false)
		_attach_interaction_hand(carried_view,Vector3(.122,.194,.025))
	elif not String(state.rice_recipe.hand).is_empty():
		carried_view.position = Vector3(.33,-.36,-.58)
		var key := String(state.rice_recipe.hand)
		_draw_rice_ingredient(carried_view,key)
		_attach_interaction_hand(carried_view,Vector3(.066,.075,.025) if key in ["jarra","agua"] else Vector3(.045,.055,.025))
	elif not state.get("waste_hand",{}).is_empty():
		_make_waste_item(carried_view,state.waste_hand)
		if String(state.waste_hand.get("kind",""))=="burned_food":
			carried_view.position = Vector3(.30,-.39,-.59)
			_attach_interaction_hand(carried_view,Vector3(.045,-.02,.025),false,true)
		if String(state.waste_hand.get("kind",""))=="broken_coffee":
			carried_view.position = Vector3(.30,-.39,-.65)
			_attach_interaction_hand(carried_view,Vector3(.10,.05,.035))
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
	if not bath_mode.is_empty(): return false
	if dining_seated or dining_water_busy or home_food_busy or not String(state.home_food.hand).is_empty(): return false
	if coffee_busy or coffee_cleaning or bool(state.coffee_machine.rag_held) or bool(state.coffee_machine.replacement) or not String(state.rice_recipe.hand).is_empty(): return false
	if business.first_story!=null and business.first_story.carrying_table(): return false
	if game.backpack!=null and not game.backpack.empty_hands(): return false
	return business.ledger.carry.is_empty() and business.life.state.meal.is_empty() and (game.monte_services==null or game.monte_services.player_bag==null) and String(state.part).is_empty() and String(state.held_furniture).is_empty() and String(state.get("paint_carry","")).is_empty() and String(state.get("paint_tool","")).is_empty() and state.get("waste_hand",{}).is_empty()

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
	if game.adaptation_mode and not world.garage_home_site.is_empty():
		state.house = true
		state.rented = true
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
	game._update_visual_lighting(true)

func _exit() -> void:
	if String(state.get("paint_tool",""))=="broom":
		business._notify("Apoya la escoba contra una pared antes de salir.")
		return
	if not bath_mode.is_empty(): return
	if dining_seated:
		_stand_from_dining()
		return
	if home_food_busy or not String(state.home_food.hand).is_empty():
		business._notify("Termina de preparar o devuelve la comida antes de salir.")
		return
	if not String(state.rice_recipe.hand).is_empty():
		business._notify("Devuelve el ingrediente o añádelo a la arrocera antes de salir.")
		return
	if bool(state.coffee_machine.rag_held):
		state.coffee_machine.rag_held = false
		_refresh_coffee_machine()
		_refresh_carried()
		_save()
	if coffee_busy or coffee_cleaning:
		business._notify("Termina la interacción de café antes de salir.")
		return
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
	if game.yordi_mission!=null: game.yordi_mission.on_home_exit()
	game.yaw = atan2(basis.z.x,basis.z.z)+PI
	game.pitch = -.12
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game.first_person = previous_first
	game._apply_camera_mode()
	if game.adaptation_mode: game.begin_home_exit_loading()

func _aimed_furniture() -> String:
	var cam: Camera3D = game.play_camera
	var actor: CharacterBody3D = game.player
	var ray := PhysicsRayQueryParameters3D.create(cam.global_position,cam.global_position-cam.global_transform.basis.z*6.0,1)
	ray.exclude = [actor.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty(): return ""
	if _door_blocks_target(cam.global_position,Vector3(hit.position)): return ""
	var obj := hit.collider as Node3D
	if obj!=null and obj.has_meta("furniture_id") and obj.global_position.distance_to(actor.global_position)<2.6: return String(obj.get_meta("furniture_id"))
	return ""

func _place_furniture() -> void:
	if game.adaptation_mode: return
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

func _near_coffee_market(at: Vector3) -> bool:
	if not game.adaptation_mode or inside or absf(at.y)>3.0: return false
	var poly: PackedVector2Array = world.market_block
	if poly.size()<3: return false
	var p := Vector2(at.x,at.z)
	for i in range(poly.size()):
		var edge := Geometry2D.get_closest_point_to_segment(p,poly[i],poly[(i+1)%poly.size()])
		if p.distance_to(edge)<=3.5: return true
	return false

func _coffee_market_menu() -> void:
	var needed := _coffee_machine_phase()=="missing" and not bool(state.coffee_machine.replacement)
	var clean := int(state.coffee_machine.dirty)==0
	business._open("Mercado de Cuatro Caminos · Hogar","Cafetera cubana de una taza · %d CUP. Lleva el repuesto a casa y colócalo en el fogón." % COFFEE_REPLACEMENT_PRICE)
	if not clean: business._button("Primero limpia la cocina",func(): pass,true)
	business._button("Comprar cafetera · %d CUP" % COFFEE_REPLACEMENT_PRICE,_buy_coffee_replacement,not needed or not clean or not _free_hands() or business.ledger.cash<COFFEE_REPLACEMENT_PRICE)
	business._button("Cerrar",business.close)

func _buy_coffee_replacement() -> void:
	if not _near_coffee_market(game.player.global_position) or _coffee_machine_phase()!="missing" or int(state.coffee_machine.dirty)>0 or not _free_hands(): return
	if business.ledger.cash<COFFEE_REPLACEMENT_PRICE: return
	state.coffee_machine.replacement = true
	if not business.ledger.spend(COFFEE_REPLACEMENT_PRICE):
		state.coffee_machine.replacement = false
		return
	_refresh_carried()
	business.close()
	business._notify("Cafetera comprada. Llévala a casa y pulsa E mirando el fogón.")

func _vendor_at(at: Vector3) -> Dictionary:
	for site in world.parts_sites:
		var c: Vector3 = site.center
		var basis: Basis = site.basis
		var local := basis.inverse()*(at-c)
		if absf(local.x)<3.0 and local.z>.55 and local.z<4.7 and absf(local.y)<2.0: return site
	return {}

func _nearest_bin(at: Vector3) -> Dictionary:
	if game.monte_services==null: return {}
	return game.monte_services.nearest_disposal_site(at)

func rental_entry_near(at: Vector3) -> bool:
	if world.garage_home_site.is_empty() or inside or not is_instance_valid(game.play_camera): return false
	var site: Dictionary = world.garage_home_site
	var door: Vector3 = site.door
	var basis: Basis = site.basis
	var offset := at-door
	# Preserve the accessible sidewalk approach, but proximity alone must
	# never activate the portal. Select the actual doorway with the reticle.
	if absf(offset.y)>=3.0: return false
	if not (Vector2(offset.x,offset.z).length()<=3.5 or (absf(offset.dot(basis.x))<=2.6 and offset.dot(basis.z)>=-1.0 and offset.dot(basis.z)<=5.0)): return false
	var cam: Camera3D = game.play_camera
	var origin := cam.global_position
	var direction := -cam.global_transform.basis.z
	var inverse := basis.inverse()
	var local_origin := inverse*(origin-door)
	var local_direction := inverse*direction
	if local_direction.z>=-.001: return false
	var depth := -local_origin.z/local_direction.z
	if depth<=0.0 or depth>8.0: return false
	var hit := local_origin+local_direction*depth
	var half_width := float(site.get("door_width",1.15))*.5
	if absf(hit.x)>half_width or hit.y<.03 or hit.y>2.20: return false
	# Albertico has no physics collider. His visible body still blocks
	# selection of a doorway behind him, regardless of trading hours.
	if is_instance_valid(business.albertico) and business.albertico.is_visible_in_tree():
		var end := origin+direction*depth
		for child in business.albertico.find_children("*","MeshInstance3D",true,false):
			var part := child as MeshInstance3D
			if not is_instance_valid(part) or not part.is_visible_in_tree(): continue
			if is_instance_valid(business.arrow) and business.arrow.is_ancestor_of(part): continue
			if part.get_aabb().intersects_segment(part.to_local(origin),part.to_local(end))!=null: return false
	# The facade itself is intentionally excluded at the doorway plane.
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+direction*maxf(.01,depth-.18),1|4|8|16|32)
	ray.exclude = [game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _aimed_home(at: Vector3) -> bool:
	if game.adaptation_mode: return rental_entry_near(at)
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

func aimed_rental_exit(at: Vector3) -> bool:
	if not inside: return false
	if at.distance_to(ROOM+Vector3(-.7,.86,5.25))>2.2: return false
	# Select the actual door leaf, not the surrounding floor or nearby tools.
	return _aim_tool(guest_door,Vector3(.60,1.10,0),Vector3(.62,1.12,.105))

func _home_exit_selected(at: Vector3) -> bool:
	if game.adaptation_mode: return aimed_rental_exit(at)
	return at.distance_to(ROOM+Vector3(-.7,.86,5.25))<1.55

func _moka_section(root: Node3D,y: float,bottom: float,top: float,height: float,color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.radial_segments = 8
	mesh.rings = 0
	mesh.bottom_radius = bottom
	mesh.top_radius = top
	mesh.height = height
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = business._mat(color)
	root.add_child(part)
	part.position.y = y
	return part

func _make_coffee_cup(root: Node3D) -> MeshInstance3D:
	# Revolve a continuous ceramic wall with an actual hollow interior.
	var ceramic := Color("#eee7d7")
	var profile := [Vector2(.0,0),Vector2(.030,0),Vector2(.033,.006),Vector2(.047,.052),Vector2(.048,.059),Vector2(.043,.062),Vector2(.040,.056),Vector2(.027,.010),Vector2(0,.010)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(profile.size()-1):
		for j in range(24):
			var a := TAU*float(j)/24.0
			var b := TAU*float(j+1)/24.0
			var lo: Vector2 = profile[i]
			var hi: Vector2 = profile[i+1]
			var p0 := Vector3(cos(a)*lo.x,lo.y,sin(a)*lo.x)
			var p1 := Vector3(cos(b)*lo.x,lo.y,sin(b)*lo.x)
			var p2 := Vector3(cos(b)*hi.x,hi.y,sin(b)*hi.x)
			var p3 := Vector3(cos(a)*hi.x,hi.y,sin(a)*hi.x)
			for p in [p0,p1,p2,p0,p2,p3]: surface.add_vertex(p)
	surface.generate_normals()
	var shell := MeshInstance3D.new()
	shell.mesh = surface.commit()
	shell.material_override = business._mat(ceramic)
	root.add_child(shell)
	var handle_mesh := TorusMesh.new()
	handle_mesh.inner_radius = .013
	handle_mesh.outer_radius = .026
	handle_mesh.rings = 16
	handle_mesh.ring_segments = 8
	var handle := MeshInstance3D.new()
	handle.mesh = handle_mesh
	handle.rotation.x = PI*.5
	handle.position = Vector3(.055,.031,0)
	handle.material_override = business._mat(ceramic)
	root.add_child(handle)
	var liquid := _rental_cylinder(root,Vector3(0,.045,0),.038,.003,Color("#41271c"))
	# A thin caramel rim makes the espresso surface distinct from ceramic.
	_rental_cylinder(liquid,Vector3(0,.0018,0),.032,.001,Color("#67402a"))
	liquid.hide()
	return liquid

func _refresh_coffee_visual() -> void:
	if is_instance_valid(coffee_liquid):
		coffee_liquid.visible = bool(business.life.state.get("coffee_served",false))

func _draw_moka_model(root: Node3D,broken: bool = false) -> void:
	if broken:
		_moka_section(root,.044,.08,.055,.08,Color("#696761"))
		var top := _rental_root(root,Vector3(.10,.055,.035))
		top.rotation.z = 1.2
		_moka_section(top,.05,.05,.08,.09,Color("#aaa49b"))
		_rental_part(root,Vector3(.12,.045,.08),Vector3(.06,.03,.04),Color("#34322e"))
		return
	var aluminum := Color("#b6bbb9")
	var dark := Color("#292b29")
	_moka_section(root,.009,.076,.076,.018,Color("#848b88"))
	_moka_section(root,.075,.080,.048,.12,aluminum)
	_moka_section(root,.146,.053,.053,.022,Color("#777e7b"))
	_moka_section(root,.201,.050,.082,.088,aluminum)
	_moka_section(root,.254,.082,.083,.018,Color("#c7cbc8"))
	_moka_section(root,.270,.083,.032,.014,aluminum)
	_moka_section(root,.291,.020,.024,.027,dark)
	# Pouring lip and curved, open black handle on opposing sides.
	_rental_part(root,Vector3(-.083,.247,0),Vector3(.055,.018,.047),aluminum).rotation.z = -.16
	_rental_part(root,Vector3(.090,.235,0),Vector3(.050,.024,.030),dark)
	_rental_part(root,Vector3(.122,.194,0),Vector3(.025,.085,.032),dark).rotation.z = .14
	_rental_part(root,Vector3(.101,.148,0),Vector3(.049,.024,.030),dark).rotation.z = .30

func _build_home_coffee(kitchen: Node3D) -> void:
	coffee_pot = _rental_root(kitchen,Vector3(.69,1.033,-.12))
	_draw_moka_model(coffee_pot)
	coffee_broken_prop = _rental_root(kitchen,coffee_pot.position)
	_draw_moka_model(coffee_broken_prop,true)
	coffee_rag = _rental_root(kitchen,Vector3(-.28,.982,.25))
	_draw_coffee_rag(coffee_rag)
	coffee_stains = _rental_root(kitchen,Vector3(.69,1.043,-.12))
	# Coffee splashes stay attached to the actual surfaces, not suspended in air.
	_add_coffee_spill(kitchen,Vector3(.55,1.008,.0),Vector2(.24,.20),false,"fogón",0)
	_add_coffee_spill(kitchen,Vector3(.09,.959,.23),Vector2(.28,.105),false,"meseta",1)
	_add_coffee_spill(kitchen,Vector3(1.15,.959,.25),Vector2(.29,.085),false,"meseta",2)
	_add_coffee_spill(kitchen,Vector3(.70,1.34,-.449),Vector2(.42,.27),true,"pared",3)
	_add_coffee_spill(kitchen,Vector3(.65,.042,.80),Vector2(.46,.29),false,"piso",4)
	_add_coffee_spill(kitchen,Vector3(-.09,.043,1.12),Vector2(.31,.23),false,"piso",5)
	coffee_machine_audio = AudioStreamPlayer3D.new()
	coffee_pot.add_child(coffee_machine_audio)
	coffee_machine_audio.max_distance = 18.0
	coffee_machine_audio.unit_size = 4.0
	coffee_ready_sound = _make_coffee_sound(false)
	coffee_burst_sound = _make_coffee_sound(true)
	coffee_status_label = Label.new()
	business.layer.add_child(coffee_status_label)
	coffee_status_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	coffee_status_label.offset_left = -345
	coffee_status_label.offset_right = -18
	coffee_status_label.offset_top = 80
	coffee_status_label.offset_bottom = 112
	coffee_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	coffee_status_label.add_theme_font_size_override("font_size",18)
	coffee_status_label.add_theme_color_override("font_color",Color("#ffd396"))
	coffee_status_label.add_theme_color_override("font_outline_color",Color.BLACK)
	coffee_status_label.add_theme_constant_override("outline_size",5)
	coffee_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coffee_status_label.hide()
	coffee_cup = _rental_root(kitchen,Vector3(.03,.979,.12))
	_rental_cylinder(kitchen,Vector3(.03,.972,.12),.078,.012,Color("#dfd6c5"))
	coffee_liquid = _make_coffee_cup(coffee_cup)
	coffee_heat = _rental_cylinder(kitchen,Vector3(.69,1.035,-.12),.095,.006,Color("#e66a29"))
	coffee_heat.hide()
	coffee_stream = _rental_cylinder(kitchen,Vector3(.03,1.086,.12),.006,.090,Color("#593420"))
	coffee_stream.hide()
	coffee_steam = CPUParticles3D.new()
	coffee_pot.add_child(coffee_steam)
	coffee_steam.position = Vector3(-.06,.28,0)
	coffee_steam.amount = 8
	coffee_steam.lifetime = .9
	coffee_steam.direction = Vector3.UP
	coffee_steam.spread = 14.0
	coffee_steam.gravity = Vector3(0,.12,0)
	coffee_steam.initial_velocity_min = .12
	coffee_steam.initial_velocity_max = .24
	var vapor := SphereMesh.new()
	vapor.radius = .012
	vapor.height = .024
	vapor.radial_segments = 6
	vapor.rings = 3
	var steam_material := StandardMaterial3D.new()
	steam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	steam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	steam_material.albedo_color = Color(1,1,1,.24)
	vapor.material = steam_material
	coffee_steam.mesh = vapor
	coffee_steam.emitting = false
	_refresh_coffee_visual()
	_refresh_coffee_machine()

func _add_coffee_spill(kitchen: Node3D,at: Vector3,extent: Vector2,vertical: bool,label_text: String,id: int) -> void:
	var patch := _rental_root(coffee_stains,Vector3.ZERO)
	patch.position = coffee_stains.to_local(kitchen.to_global(at))
	if vertical: patch.rotation.x = PI*.5
	# One mesh per dirty zone: irregular puddles, small scattered droplets and
	# elongated drips on vertical surfaces, with no extra collision bodies.
	var rng := RandomNumberGenerator.new()
	rng.seed = 1931+id*79
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(29):
		var center := Vector2.ZERO
		var radius := Vector2(extent.x*.56,extent.y*.55)
		if i>0:
			center = Vector2(rng.randf_range(-extent.x*.82,extent.x*.82),rng.randf_range(-extent.y*.75,extent.y*.75))
			var size := rng.randf_range(.012,.043)
			radius = Vector2(minf(size,extent.x*.13),minf(size*(rng.randf_range(1.7,3.0) if vertical else rng.randf_range(.5,1.3)),extent.y*.24))
		var shade := Color("#4a2918").lerp(Color("#815134"),rng.randf_range(0.0,.60))
		var outline := PackedVector3Array()
		for k in range(10):
			var angle := TAU*float(k)/10.0
			var jitter := rng.randf_range(.73,1.18)
			outline.append(Vector3(clampf(center.x+cos(angle)*radius.x*jitter,-extent.x,extent.x),.001+float(i)*.00008,clampf(center.y+sin(angle)*radius.y*jitter,-extent.y,extent.y)))
		for k in range(10):
			for vertex in [Vector3(center.x,.001+float(i)*.00008,center.y),outline[k],outline[(k+1)%10]]:
				surface.set_color(shade)
				surface.add_vertex(vertex)
	surface.generate_normals()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = .62
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := MeshInstance3D.new()
	mesh.mesh = surface.commit()
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	patch.add_child(mesh)
	coffee_spill_patches.append({"id":id,"node":patch,"extent":extent,"label":label_text,"vertical":vertical})

func _aimed_coffee_spill() -> Dictionary:
	var best: Dictionary = {}
	var depth := INF
	for entry in coffee_spill_patches:
		var patch: Node3D = entry.node
		if not patch.is_visible_in_tree(): continue
		var extent: Vector2 = entry.extent
		if not _aim_tool(patch,Vector3(0,.012,0),Vector3(extent.x,.027,extent.y)): continue
		var cam: Camera3D = game.play_camera
		var distance: float = cam.global_position.distance_squared_to(patch.global_position)
		if distance<depth:
			depth = distance
			best = entry
	return best

func _draw_coffee_rag(root: Node3D) -> void:
	_rental_part(root,Vector3.ZERO,Vector3(.13,.018,.09),Color("#b9936e")).rotation.y = .16
	_rental_part(root,Vector3(.015,.013,-.007),Vector3(.10,.012,.07),Color("#d3b38b")).rotation.y = -.12

func _make_coffee_sound(burst: bool) -> AudioStreamWAV:
	var rate := 22050
	var duration := .65 if burst else 1.0
	var samples := int(float(rate)*duration)
	var bytes := PackedByteArray()
	bytes.resize(samples*2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 32019
	for i in range(samples):
		var t := float(i)/float(rate)
		var noise := rng.randf_range(-1.0,1.0)
		var signal_value := 0.0
		if burst:
			signal_value = (noise*.55+sin(TAU*82.0*t)*.45)*exp(-t*9.0)
		else:
			var pulse := sin(TAU*7.0*t)*.5+.5
			signal_value = (sin(TAU*(720.0+70.0*sin(TAU*5.0*t))*t)*.36+noise*.11)*pulse*minf(1.0,t*20.0)*minf(1.0,(duration-t)*20.0)
		bytes.encode_s16(i*2,roundi(clampf(signal_value,-1.0,1.0)*22000.0))
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = rate
	audio.data = bytes
	return audio

func _play_coffee_sound(stream: AudioStreamWAV) -> void:
	if not is_instance_valid(coffee_machine_audio) or stream==null: return
	coffee_machine_audio.stream = stream
	coffee_machine_audio.play()

func _coffee_machine_phase() -> String:
	return String(state.coffee_machine.phase)

func _refresh_coffee_machine() -> void:
	if not is_instance_valid(coffee_pot): return
	var phase := _coffee_machine_phase()
	coffee_pot.visible = phase in ["idle","heating","ready"]
	coffee_broken_prop.visible = phase=="broken"
	coffee_heat.visible = phase in ["heating","ready"]
	coffee_steam.emitting = phase=="ready" or (phase=="heating" and float(state.coffee_machine.remaining)<=3.0)
	coffee_rag.visible = not bool(state.coffee_machine.rag_held)
	for entry in coffee_spill_patches:
		entry.node.visible = int(entry.id) in state.coffee_machine.spill_zones

func _coffee_stove_aimed() -> bool:
	if _aim_tool(coffee_pot,Vector3(0,.15,0),Vector3(.18,.18,.15)): return true
	return _aim_tool(coffee_broken_prop,Vector3(0,.07,0),Vector3(.23,.11,.20))

func _coffee_special_action() -> String:
	if not inside or not is_instance_valid(coffee_pot): return ""
	var phase := _coffee_machine_phase()
	if coffee_cleaning: return "[E] Limpiando la cocina…"
	if bool(state.coffee_machine.rag_held):
		if _aim_tool(coffee_rag,Vector3.ZERO,Vector3(.10,.04,.08)): return "[E] Devolver trapo"
		var spill := _aimed_coffee_spill()
		if not spill.is_empty(): return "[E] Limpiar mancha de café · "+String(spill.label)
		return ""
	if bool(state.coffee_machine.replacement):
		if _coffee_stove_aimed(): return "[E] Colocar cafetera nueva" if int(state.coffee_machine.dirty)==0 else "[E] Limpia el fogón antes de colocar la cafetera"
		return ""
	if _coffee_stove_aimed():
		match phase:
			"heating": return "[E] Apagar fogón · preparando café"
			"ready": return "[E] Apagar fogón · %d s" % ceili(float(state.coffee_machine.remaining))
			"broken": return "[E] Recoger cafetera rota"
			"missing": return "[E] Falta una cafetera · compra otra en Cuatro Caminos"
	if _aim_tool(coffee_rag,Vector3.ZERO,Vector3(.10,.04,.08)) and _free_hands(): return "[E] Recoger trapo"
	return ""

func _coffee_special_interact() -> bool:
	var action := _coffee_special_action()
	if action.is_empty(): return false
	if coffee_cleaning: return true
	if action.contains("Apagar fogón"):
		var ready := _coffee_machine_phase()=="ready"
		state.coffee_machine.phase = "idle"
		state.coffee_machine.remaining = 0.0
		coffee_machine_audio.stop()
		var shutoff_hand := _attach_interaction_hand(coffee_pot,Vector3(.12,.06,.18))
		get_tree().create_timer(.35).timeout.connect(shutoff_hand.queue_free)
		if ready: business.life.brew_home_coffee()
		_refresh_coffee_machine()
		_refresh_coffee_visual()
		_save()
		business._notify("Fogón apagado. Sirve el café." if ready else "Fogón apagado antes de terminar. Puedes preparar otra colada.")
	elif action.contains("Recoger cafetera rota"):
		if not _free_hands(): return true
		state.waste_hand = {"kind":"broken_coffee","volume":3}
		state.coffee_machine.phase = "missing"
		_refresh_coffee_machine()
		_refresh_carried()
		_save()
		business._notify("Lleva la cafetera rota a la bolsa de basura o a un contenedor.")
	elif action.contains("Recoger trapo"):
		if not _free_hands(): return true
		state.coffee_machine.rag_held = true
		_refresh_coffee_machine()
		_refresh_carried()
		_save()
	elif action.contains("Devolver trapo"):
		state.coffee_machine.rag_held = false
		_refresh_coffee_machine()
		_refresh_carried()
		_save()
	elif action.contains("Limpiar mancha"):
		_clean_coffee_async()
	elif action.contains("Colocar cafetera nueva"):
		state.coffee_machine.replacement = false
		state.coffee_machine.phase = "idle"
		_refresh_coffee_machine()
		_refresh_carried()
		_save()
		business._notify("Cafetera nueva instalada.")
	elif action.contains("Limpia el fogón"): business._notify("Limpia el fogón antes de instalar el repuesto.")
	else: business._notify("Consigue una cafetera nueva en el Mercado de Cuatro Caminos.")
	return true

func _clean_coffee_async() -> void:
	if coffee_cleaning or not bool(state.coffee_machine.rag_held) or int(state.coffee_machine.dirty)<=0: return
	var entry := _aimed_coffee_spill()
	if entry.is_empty(): return
	coffee_cleaning = true
	var patch: Node3D = entry.node
	var extent: Vector2 = entry.extent
	var rag := _rental_root(patch,Vector3(-extent.x*.65,.045,0))
	_draw_coffee_rag(rag)
	_attach_interaction_hand(rag,Vector3(.065,0,.025))
	carried_view.hide()
	var wipe := create_tween()
	for i in range(3):
		wipe.tween_property(rag,"position",Vector3(extent.x*.65,.045,-extent.y*.52+float(i)*extent.y*.5),.28)
		wipe.tween_property(rag,"position",Vector3(-extent.x*.65,.045,-extent.y*.30+float(i)*extent.y*.5),.28)
	await wipe.finished
	rag.queue_free()
	state.coffee_machine.spill_zones.erase(int(entry.id))
	state.coffee_machine.dirty = state.coffee_machine.spill_zones.size()
	coffee_cleaning = false
	_refresh_coffee_machine()
	_refresh_carried()
	carried_view.show()
	_save()
	business._notify("Cocina limpia." if int(state.coffee_machine.dirty)==0 else "Quedan %d zonas sucias." % int(state.coffee_machine.dirty))

func _physics_process(delta: float) -> void:
	if not state.is_empty() and state.has("coffee_machine"): _tick_coffee_machine(delta)
	if not state.is_empty() and state.has("home_food"):
		_tick_home_pan(delta)
		_update_dish_hint()
	if not state.is_empty() and state.has("bathroom"): _tick_bathroom(delta)

func _tick_coffee_machine(delta: float) -> void:
	if not is_instance_valid(coffee_pot): return
	var phase := _coffee_machine_phase()
	if phase in ["heating","ready"]:
		state.coffee_machine.remaining = maxf(0.0,float(state.coffee_machine.remaining)-delta)
		coffee_save_clock += delta
		if coffee_save_clock>=5.0:
			coffee_save_clock = 0.0
			_save()
		if phase=="heating":
			var steaming := float(state.coffee_machine.remaining)<=3.0
			if coffee_steam.emitting!=steaming: coffee_steam.emitting = steaming
			if float(state.coffee_machine.remaining)<=0.0:
				state.coffee_machine.phase = "ready"
				state.coffee_machine.remaining = COFFEE_SHUTOFF_SECONDS
				coffee_alert_clock = 0.0
				_play_coffee_sound(coffee_ready_sound)
				_save()
				business._notify("¡Café listo! Apaga el fogón en 30 segundos.")
		else:
			coffee_alert_clock += delta
			if coffee_alert_clock>=3.0:
				coffee_alert_clock = 0.0
				_play_coffee_sound(coffee_ready_sound)
			if float(state.coffee_machine.remaining)<=0.0:
				_break_coffee_machine()
	phase = _coffee_machine_phase()
	coffee_status_label.visible = inside and phase in ["heating","ready"]
	if coffee_status_label.visible:
		var line := "¡APAGA EL FOGÓN!" if phase=="ready" else "Preparando café"
		coffee_status_label.text = "%s · %d s" % [line,ceili(float(state.coffee_machine.remaining))]

func _break_coffee_machine() -> void:
	state.coffee_machine.phase = "broken"
	state.coffee_machine.remaining = 0.0
	state.coffee_machine.spill_zones = [0,1,2,3,4,5]
	state.coffee_machine.dirty = state.coffee_machine.spill_zones.size()
	business.life.state.coffee_cups = 0
	business.life.state.coffee_served = false
	_play_coffee_sound(coffee_burst_sound)
	_coffee_burst_visual()
	_refresh_coffee_machine()
	_refresh_coffee_visual()
	_save()
	business._notify("¡La cafetera explotó! Tira los restos y limpia la cocina con el trapo.")

func _coffee_burst_visual() -> void:
	var puff := CPUParticles3D.new()
	coffee_stains.get_parent().add_child(puff)
	puff.position = coffee_stains.position+Vector3(0,.20,0)
	puff.amount = 44
	puff.lifetime = .95
	puff.one_shot = true
	puff.explosiveness = 1.0
	puff.direction = Vector3.UP
	puff.spread = 100.0
	puff.gravity = Vector3(0,-2.0,0)
	puff.initial_velocity_min = .5
	puff.initial_velocity_max = 1.5
	var mesh := SphereMesh.new()
	mesh.radius = .025
	mesh.height = .05
	mesh.radial_segments = 6
	mesh.rings = 3
	mesh.material = business._mat(Color("#64412a"))
	puff.mesh = mesh
	puff.emitting = true
	get_tree().create_timer(1.2).timeout.connect(puff.queue_free)

func _refresh_tv_screen() -> void:
	if not is_instance_valid(television_screen): return
	var on := bool(state.get("tv_on",false))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#8fa7aa") if on else Color("#666e69")
	mat.emission_enabled = on
	mat.emission = Color("#a9c2c9")
	mat.emission_energy_multiplier = .5
	television_screen.material_override = mat

func _update_wall_clock() -> void:
	if not is_instance_valid(wall_hour_hand) or business.life==null: return
	var minute: float = float(business.life.state.minutes)
	wall_hour_hand.rotation.z = -TAU*minute/720.0
	wall_minute_hand.rotation.z = -TAU*minute/60.0

func _draw_rice_ingredient(root: Node3D,key: String) -> void:
	match key:
		"arroz":
			_rental_part(root,Vector3(0,.065,0),Vector3(.13,.13,.09),Color("#e5d8b1"))
			_rental_part(root,Vector3(0,.08,.047),Vector3(.11,.055,.006),Color("#8c9c67"))
		"sal":
			_rental_cylinder(root,Vector3(0,.055,0),.027,.11,Color("#ece9de"))
			_rental_cylinder(root,Vector3(0,.115,0),.030,.025,Color("#426b91"))
		"aceite":
			_rental_cylinder(root,Vector3(0,.074,0),.035,.148,Color("#ceab46"))
			_rental_cylinder(root,Vector3(0,.16,0),.019,.045,Color("#ded7a1"))
			_rental_cylinder(root,Vector3(0,.19,0),.023,.018,Color("#bd7a38"))
			_rental_part(root,Vector3(0,.08,.036),Vector3(.05,.055,.003),Color("#eee3ac"))
		"jarra","agua":
			_rental_cylinder(root,Vector3(0,.075,0),.057,.15,Color("#b2c6cb"))
			_rental_part(root,Vector3(.066,.09,0),Vector3(.035,.09,.022),Color("#8aa4ad"))
			if key=="agua": _rental_cylinder(root,Vector3(0,.148,0),.052,.005,Color("#76b6d4"))

func _build_rice_kitchen(kitchen: Node3D) -> void:
	# Extension toward the bedroom wall stays clear of the refrigerator.
	rice_cooker = _rental_root(kitchen,Vector3(1.25,.955,0))
	_rental_cylinder(rice_cooker,Vector3(0,.025,0),.16,.05,Color("#424745"))
	_rental_cylinder(rice_cooker,Vector3(0,.135,0),.18,.22,Color("#e6e5d8"))
	_rental_cylinder(rice_cooker,Vector3(0,.251,0),.174,.018,Color("#8d9895"))
	_rental_cylinder(rice_cooker,Vector3(0,.259,0),.143,.008,Color("#333b3a"))
	rice_contents = _rental_cylinder(rice_cooker,Vector3(0,.266,0),.133,.009,Color("#eee8cd"))
	_rental_part(rice_cooker,Vector3(-.192,.15,0),Vector3(.05,.055,.09),Color("#373e3e"))
	_rental_part(rice_cooker,Vector3(.192,.15,0),Vector3(.05,.055,.09),Color("#373e3e"))
	_rental_part(rice_cooker,Vector3(0,.105,.174),Vector3(.095,.09,.025),Color("#414948"))
	rice_indicator = _rental_part(rice_cooker,Vector3(0,.13,.191),Vector3(.034,.018,.009),Color("#6d7066"))
	_rental_part(rice_cooker,Vector3(0,.075,.194),Vector3(.045,.025,.012),Color("#c1c4b9"))
	rice_lid = _rental_root(rice_cooker,Vector3(0,.267,-.16))
	_rental_cylinder(rice_lid,Vector3(0,.015,.16),.181,.035,Color("#b3bbb9"))
	_rental_part(rice_lid,Vector3(0,.055,.16),Vector3(.09,.045,.045),Color("#404442"))
	for key in ["arroz","sal","aceite"]:
		var p: Vector3 = Vector3(0,.108,.04) if key=="arroz" else (Vector3(-.63,1.68,-.24) if key=="sal" else Vector3(0,1.68,-.24))
		var prop := _rental_root(kitchen,p)
		_draw_rice_ingredient(prop,key)
		rice_pantry[key] = prop
	rice_jug = _rental_root(kitchen,Vector3(-.91,.955,.10))
	_draw_rice_ingredient(rice_jug,"jarra")
	_refresh_rice_visuals()

func _refresh_rice_visuals(update_lid: bool = true) -> void:
	if not is_instance_valid(rice_cooker): return
	var recipe: Dictionary = state.rice_recipe
	var hand := String(recipe.hand)
	for key in rice_pantry:
		var prop: Node3D = rice_pantry[key]
		prop.visible = int(recipe.stock.get(key,0))>0 and hand!=String(key)
	rice_jug.visible = hand not in ["jarra","agua"]
	if update_lid: rice_lid.rotation.x = 0.0 if bool(recipe.lid) else -1.65
	rice_contents.visible = not recipe.added.is_empty() or int(recipe.portions)>0 or float(recipe.remaining)>0.0
	rice_contents.material_override = business._mat(Color("#eae2c8") if "arroz" in recipe.added or int(recipe.portions)>0 else Color("#9ebdc2"))
	rice_indicator.material_override = business._mat(Color("#df5536") if float(recipe.remaining)>0.0 else (Color("#70b977") if int(recipe.portions)>0 else Color("#6d7066")))

func _build_dining_table(root: Node3D) -> void:
	dining_chair = _rental_root(root,Vector3(0,0,.78))
	dining_chair_body = _solid(dining_chair,Vector3(0,.47,0),Vector3(.44,.94,.43),Color("#77563e"))
	dining_chair_body.get_child(0).hide()
	var wood := Color("#77563e")
	_rental_part(dining_chair,Vector3(0,.45,0),Vector3(.44,.055,.43),wood)
	for x in [-.17,.17]:
		for z in [-.16,.16]:
			_rental_part(dining_chair,Vector3(float(x),.215,float(z)),Vector3(.055,.43,.055),wood)
		_rental_part(dining_chair,Vector3(float(x),.72,.18),Vector3(.055,.52,.055),wood)
	for y in [.66,.88]:
		_rental_part(dining_chair,Vector3(0,float(y),.18),Vector3(.40,.095,.045),wood)
	dining_surface = _rental_root(root,Vector3(0,.775,.13))
	dining_plate_prop = _rental_root(dining_surface,Vector3(0,0,0))
	dining_water_prop = _rental_root(dining_surface,Vector3(.35,0,-.10))
	_refresh_dining_table()

func _draw_home_water(root: Node3D,sips: int) -> void:
	# Reusable lightweight bottle shape with a blue cap and a visible fill level.
	var plastic := Color("#a8c5cc")
	_rental_cylinder(root,Vector3(0,.092,0),.037,.172,plastic)
	_rental_cylinder(root,Vector3(0,.19,0),.023,.035,plastic)
	_rental_cylinder(root,Vector3(0,.217,0),.025,.023,Color("#416b9b"))
	_rental_cylinder(root,Vector3(0,.102,0),.038,.055,Color("#e4e9df"))
	if sips>0:
		var h := .043*float(sips)
		_rental_cylinder(root,Vector3(0,.014+h*.5,0),.0385,h,Color("#80b5d0"))

func _refresh_dining_table() -> void:
	if not is_instance_valid(dining_plate_prop) or not is_instance_valid(dining_water_prop): return
	var food: Dictionary = state.home_food
	var meal: Dictionary = business.life.state.meal
	var active := String(meal.get("key","")) in ["plato_casero","arroz_casero"]
	for child in dining_plate_prop.get_children():
		dining_plate_prop.remove_child(child)
		child.queue_free()
	if active and dining_seated:
		business.life.draw_home_plate(dining_plate_prop,meal.get("ingredients",["arroz"]),int(meal.get("food_bites",0)))
	elif not food.table_plate.is_empty():
		business.life.draw_home_plate(dining_plate_prop,food.table_plate,int(food.table_bites))
	elif bool(food.table_used_plate):
		business.life.draw_home_plate(dining_plate_prop,[],0)
		_draw_plate_residue(dining_plate_prop)
	for child in dining_water_prop.get_children():
		dining_water_prop.remove_child(child)
		child.queue_free()
	if int(food.table_water)>=0: _draw_home_water(dining_water_prop,int(food.table_water))

func _aim_dining_chair() -> bool:
	if not is_instance_valid(dining_chair_body): return false
	var cam: Camera3D = game.play_camera
	var ray := PhysicsRayQueryParameters3D.create(cam.global_position,cam.global_position-cam.global_basis.z*3.0,1|2)
	ray.exclude = [game.player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.collider!=dining_chair_body: return false
	return not _door_blocks_target(cam.global_position,Vector3(hit.position),dining_chair)

func _dining_action() -> String:
	if not inside or not game.adaptation_mode or not is_instance_valid(dining_chair): return ""
	var food: Dictionary = state.home_food
	if dining_seated:
		if dining_water_busy: return "[E] Bebiendo agua…"
		if business.life.bite_anim>0.0: return "[E] Comiendo…"
		if int(food.table_water)>0 and _aim_tool(dining_water_prop,Vector3(0,.11,0),Vector3(.07,.13,.07)): return "[E] Beber agua · %d sorbos" % int(food.table_water)
		if not business.life.state.meal.is_empty() or not food.table_plate.is_empty():
			if _aim_tool(dining_plate_prop,Vector3(0,.03,0),Vector3(.16,.055,.16)): return "[E] Comer"
			return "[E] Levantarse · mira el plato para comer"
		return "[E] Levantarse"
	if not String(food.hand).is_empty(): return ""
	if _aim_dining_chair():
		if _free_hands() or String(business.life.state.meal.get("key","")) in ["plato_casero","arroz_casero"]: return "[E] Sentarse a la mesa"
	if bool(food.table_used_plate) and food.table_plate.is_empty() and _free_hands() and _aim_tool(dining_plate_prop,Vector3(0,.025,0),Vector3(.15,.04,.15)): return "[E] Recoger plato sucio"
	if int(food.table_water)==0 and _free_hands() and _aim_tool(dining_water_prop,Vector3(0,.11,0),Vector3(.07,.13,.07)): return "[E] Recoger botella vacía"
	return ""

func _dining_interact() -> bool:
	var action := _dining_action()
	if action.is_empty(): return false
	if action=="[E] Sentarse a la mesa": _sit_at_dining()
	elif action.begins_with("[E] Levantarse"): _stand_from_dining()
	elif action.begins_with("[E] Beber agua"): _drink_dining_water()
	elif action=="[E] Comer":
		var food: Dictionary = state.home_food
		if business.life.state.meal.is_empty():
			if business.life.start_home_plate(food.table_plate,int(food.table_bites)):
				food.table_plate = []
				_refresh_dining_table()
				_save()
		if not business.life.state.meal.is_empty(): business.life.interact(game.player.global_position)
	elif action=="[E] Recoger plato sucio":
		state.home_food.table_used_plate = false
		state.home_food.hand = "plato"
		state.home_food.plate = []
		state.home_food.plate_dirty = true
		state.home_food.just_washed = false
		_refresh_dining_table()
		_refresh_carried()
		_save()
		business._notify("Plato sucio. Llévalo al fregadero y pulsa E para lavarlo.")
	elif action=="[E] Recoger botella vacía":
		state.home_food.table_water = -1
		state.waste_hand = {"kind":"empty_water","volume":1}
		_refresh_dining_table()
		_refresh_carried()
		_save()
	return true

func _sit_at_dining() -> void:
	if dining_seated or not is_instance_valid(dining_chair): return
	var actor: CharacterBody3D = game.player
	var seat := dining_chair.to_global(Vector3(0,.72,0))
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = game.player_shape.shape
	q.collision_mask = 1|2
	q.exclude = [actor.get_rid(),dining_chair_body.get_rid()]
	q.transform = Transform3D(Basis.IDENTITY,seat+Vector3.UP*.15)
	if not get_world_3d().direct_space_state.intersect_shape(q,1).is_empty():
		business._notify("El espacio de la silla está bloqueado. Intenta acercarte desde otro lado.")
		return
	dining_stand_position = actor.global_position
	dining_previous_first = game.first_person
	dining_previous_yaw = game.yaw
	dining_previous_pitch = game.pitch
	dining_seated = true
	game.player_shape.set_deferred("disabled",true)
	actor.velocity = Vector3.ZERO
	actor.global_position = seat
	game.first_person = true
	game.yaw = 0.0
	game.pitch = -.53
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	game.pivot.position.y = .45
	_refresh_dining_table()
	business._notify("Sentado. Mira el plato o la botella y pulsa E. Espacio para levantarte.")

func dining_look(relative: Vector2,sensitivity: float) -> void:
	if not dining_seated: return
	# Lock the view during a bite or sip; between actions allow just enough
	# movement to select the plate and the bottle, never look under the table.
	if dining_water_busy or business.life.bite_anim>0.0: return
	game.yaw = clampf(game.yaw-relative.x*sensitivity,-.58,.22)
	game.pitch = clampf(game.pitch-relative.y*sensitivity,-.68,-.20)
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)

func _stand_from_dining(force: bool = false) -> void:
	if not dining_seated: return
	if not force and (dining_water_busy or business.life.bite_anim>0.0): return
	var food: Dictionary = state.home_food
	var meal: Dictionary = business.life.state.meal
	if String(meal.get("key","")) in ["plato_casero","arroz_casero"]:
		food.table_plate = meal.get("ingredients",["arroz"]).duplicate()
		food.table_used_plate = true
		food.table_bites = int(meal.get("food_bites",0))
		business.life.state.meal = {}
		business.life.active_hand = -1
		business.life.bite_anim = 0.0
		business.life._refresh_meal()
	dining_seated = false
	game.player.global_position = dining_stand_position
	game.player_shape.set_deferred("disabled",false)
	game.player.velocity = Vector3.ZERO
	game.first_person = dining_previous_first
	game.yaw = dining_previous_yaw
	game.pitch = dining_previous_pitch
	game.pivot.rotation = Vector3(game.pitch,game.yaw,0)
	game._apply_camera_mode()
	_refresh_dining_table()
	_save()

func _configure_dining_arm(hand: Node3D) -> void:
	if not is_instance_valid(dining_chair) or not is_instance_valid(hand): return
	var shirt: MeshInstance3D = game.avatar.get_node("Shirt")
	hand.configure_body_arm(dining_chair,Vector3(.23,1.00,.09),Vector3(.31,.87,-.035),shirt.material_override)

func _dining_water_safe_pose(at: Vector3,model: Node3D) -> void:
	if is_instance_valid(model): model.position = InteractionHand.camera_safe_pose(game.play_camera,at,.09)

func _drink_dining_water() -> void:
	if not dining_seated or dining_water_busy or int(state.home_food.table_water)<=0: return
	dining_water_busy = true
	dining_water_prop.hide()
	var model := Node3D.new()
	game.play_camera.add_child(model)
	model.position = Vector3(.25,-.33,-.43)
	_draw_home_water(model,int(state.home_food.table_water))
	var drinking_hand = _attach_interaction_hand(model,Vector3(.048,.09,.025))
	_configure_dining_arm(drinking_hand)
	var sip := create_tween()
	sip.tween_method(_dining_water_safe_pose.bind(model),Vector3(.25,-.33,-.43),Vector3(.065,-.19,-.28),.38)
	sip.parallel().tween_property(model,"rotation:x",.85,.38)
	sip.tween_interval(.45)
	sip.tween_property(model,"rotation:x",0.0,.25)
	sip.parallel().tween_method(_dining_water_safe_pose.bind(model),Vector3(.065,-.19,-.28),Vector3(.25,-.33,-.43),.25)
	await sip.finished
	model.queue_free()
	state.home_food.table_water = maxi(0,int(state.home_food.table_water)-1)
	dining_water_busy = false
	_refresh_dining_table()
	dining_water_prop.show()
	_save()
	business._notify("Agua bebida · quedan %d sorbos." % int(state.home_food.table_water))

func _draw_home_raw_food(root: Node3D,key: String) -> void:
	if key=="carne":
		_rental_part(root,Vector3.ZERO,Vector3(.15,.015,.10),Color("#e0ded2"))
		for i in range(3):
			_rental_round(root,Vector3((float(i)-1.0)*.043,.025,0),Vector3(.054,.032,.072),Color("#a74e46"))
	else:
		_rental_round(root,Vector3(0,.031,0),Vector3(.045,.060,.045),Color("#e9d6b8"))

func _build_home_food_fridge() -> void:
	for key in ["carne","huevo","botella"]:
		var pos := Vector3(-.18,1.30,.05) if key=="carne" else (Vector3(.20,.49,.08) if key=="huevo" else Vector3(-.21,.89,.10))
		var prop := _rental_root(rental_fridge,pos)
		if key=="botella": _draw_home_water(prop,3)
		else: _draw_home_raw_food(prop,key)
		if key=="huevo":
			_rental_part(prop,Vector3(0,-.01,0),Vector3(.17,.028,.11),Color("#a99472"))
			for x in [-.055,.055]:
				_rental_round(prop,Vector3(float(x),.031,0),Vector3(.045,.060,.045),Color("#e9d6b8"))
		home_food_props[key] = prop
	_refresh_home_food()

func _draw_dish_sponge(root: Node3D) -> void:
	_rental_part(root,Vector3(0,.010,0),Vector3(.075,.020,.048),Color("#d9b94b"))
	_rental_part(root,Vector3(0,.023,0),Vector3(.075,.008,.048),Color("#4d7751"))

func _draw_plate_residue(root: Node3D) -> Node3D:
	var stains := _rental_root(root,Vector3.ZERO)
	_rental_round(stains,Vector3(-.026,.009,.018),Vector3(.095,.005,.068),Color("#a67d47"))
	_rental_round(stains,Vector3(.034,.010,-.026),Vector3(.065,.005,.045),Color("#816044"))
	for i in range(7):
		var a := float(i)*2.4
		_rental_round(stains,Vector3(cos(a)*.051,.014,sin(a)*.041),Vector3(.009,.006,.014),Color("#b8a480"))
	return stains

func _make_dish_hint() -> void:
	if is_instance_valid(dish_wash_hint): return
	dish_wash_hint = Label.new()
	business.layer.add_child(dish_wash_hint)
	dish_wash_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	dish_wash_hint.offset_left = -310
	dish_wash_hint.offset_right = 310
	dish_wash_hint.offset_top = -115
	dish_wash_hint.offset_bottom = -86
	dish_wash_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dish_wash_hint.add_theme_font_size_override("font_size",17)
	dish_wash_hint.add_theme_color_override("font_color",Color("#fff0bd"))
	dish_wash_hint.add_theme_color_override("font_outline_color",Color.BLACK)
	dish_wash_hint.add_theme_constant_override("outline_size",5)
	dish_wash_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dish_wash_hint.hide()

func _update_dish_hint() -> void:
	if not is_instance_valid(dish_wash_hint): return
	var food: Dictionary = state.home_food
	var message := ""
	if inside and not business.modal_open():
		if dish_washing: message = "Lavando el plato con agua y esponja…"
		elif String(food.hand)=="plato" and bool(food.plate_dirty):
			message = "Plato sucio · mira el fregadero y pulsa E para lavar"
		elif String(food.hand)=="plato" and bool(food.get("just_washed",false)):
			message = "Plato limpio · abre el armario superior derecho y pulsa E para guardar"
		elif bool(food.table_used_plate) and food.table_plate.is_empty() and business.life.state.meal.is_empty():
			message = "Terminaste de comer · levántate con Espacio y recoge el plato sucio" if dining_seated else "Recoge el plato sucio de la mesa y lávalo en el fregadero"
	if dish_wash_hint.text!=message: dish_wash_hint.text = message
	dish_wash_hint.visible = not message.is_empty()

func _aim_dish_sink() -> bool:
	# Target the accessible basin surface and the faucet, not the solid counter.
	return _aim_tool(kitchen_tap,Vector3(0,.06,.08),Vector3(.09,.16,.14)) or _aim_tool(rental_kitchen,Vector3(-.54,1.015,0),Vector3(.29,.052,.23))

func _wash_plate_async() -> void:
	if home_food_busy or not inside or not bool(state.home_food.plate_dirty) or String(state.home_food.hand)!="plato": return
	home_food_busy = true
	dish_washing = true
	var was_running: bool = tap_water.visible
	tap_water.show()
	dish_sponge.hide()
	carried_view.hide()
	# Keep the plate above the sink rim. The left hand grips the edge;
	# the right holds a sponge and passes over the inner surface.
	var plate := _rental_root(kitchen_tap,Vector3(0,.045,.19))
	business.life.draw_home_plate(plate,[],0)
	var stains := _draw_plate_residue(plate)
	_attach_interaction_hand(plate,Vector3(-.115,-.026,.035),true,true)
	var sponge := _rental_root(plate,Vector3(.045,.026,.02))
	_draw_dish_sponge(sponge)
	_attach_interaction_hand(sponge,Vector3(.025,.045,.017))
	var bubbles := _rental_root(plate,Vector3.ZERO)
	for i in range(10):
		var a := float(i)*2.4
		var size := .014+float(i%3)*.006
		_rental_round(bubbles,Vector3(cos(a)*.065,.024,sin(a)*.055),Vector3(size,size*.55,size),Color("#f4f6ec"))
	bubbles.hide()
	var wash := create_tween()
	for i in range(3):
		wash.tween_property(sponge,"position",Vector3(-.048,.026,-.036+float(i)*.030),.32)
		wash.tween_property(sponge,"position",Vector3(.048,.026,-.021+float(i)*.030),.32)
		if i==0: wash.tween_callback(bubbles.show)
		if i==1: wash.tween_callback(stains.hide)
	await wash.finished
	sponge.hide()
	bubbles.hide()
	var rinse := create_tween()
	rinse.tween_property(plate,"rotation:x",.22,.30)
	rinse.tween_interval(.45)
	rinse.tween_property(plate,"rotation:x",0.0,.25)
	await rinse.finished
	plate.queue_free()
	tap_water.visible = was_running
	dish_sponge.show()
	state.home_food.plate_dirty = false
	state.home_food.just_washed = true
	dish_washing = false
	home_food_busy = false
	_refresh_carried()
	carried_view.show()
	_save()
	business._notify("Plato limpio. Guárdalo en el armario superior derecho.")

func _build_home_plate_stack(kitchen: Node3D) -> void:
	home_plate_stack = _rental_root(kitchen,Vector3(.63,1.69,-.23))
	for i in range(3):
		var plate := _rental_root(home_plate_stack,Vector3(0,.017+float(i)*.022,0))
		business.life.draw_home_plate(plate,[],0)
		plate.scale = Vector3.ONE*.84

func _build_home_pan(kitchen: Node3D) -> void:
	home_pan = _rental_root(kitchen,Vector3(.39,1.034,.12))
	_rental_cylinder(home_pan,Vector3(0,.013,0),.101,.026,Color("#666d6b"))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(24):
		var a := TAU*float(i)/24.0
		var b := TAU*float(i+1)/24.0
		var p := Vector3(cos(a)*.103,.015,sin(a)*.103)
		var q := Vector3(cos(b)*.103,.015,sin(b)*.103)
		var u := Vector3(cos(a)*.113,.078,sin(a)*.113)
		var v := Vector3(cos(b)*.113,.078,sin(b)*.113)
		for vertex in [p,q,u,q,v,u]: surface.add_vertex(vertex)
	surface.generate_normals()
	var walls := MeshInstance3D.new()
	walls.mesh = surface.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#969e9a")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	walls.material_override = mat
	home_pan.add_child(walls)
	_rental_part(home_pan,Vector3(.16,.052,0),Vector3(.15,.031,.042),Color("#47443e"))
	home_pan_food = _rental_root(home_pan,Vector3(0,.027,0))
	home_pan_heat = _rental_cylinder(kitchen,Vector3(.39,1.035,.12),.098,.004,Color("#d96b32"))
	home_pan_heat.hide()
	home_pan_smoke = CPUParticles3D.new()
	home_pan.add_child(home_pan_smoke)
	home_pan_smoke.position.y = .09
	home_pan_smoke.amount = 14
	home_pan_smoke.lifetime = 1.2
	home_pan_smoke.direction = Vector3.UP
	home_pan_smoke.spread = 24.0
	home_pan_smoke.gravity = Vector3(0,.1,0)
	home_pan_smoke.initial_velocity_min = .16
	home_pan_smoke.initial_velocity_max = .4
	var smoke_mesh := SphereMesh.new()
	smoke_mesh.radius = .035
	smoke_mesh.height = .07
	smoke_mesh.radial_segments = 6
	smoke_mesh.rings = 3
	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smoke_mat.albedo_color = Color(.24,.22,.20,.30)
	smoke_mesh.material = smoke_mat
	home_pan_smoke.mesh = smoke_mesh
	home_pan_smoke.emitting = false
	_refresh_home_food()

func _refresh_home_food() -> void:
	var food: Dictionary = state.home_food
	for key in home_food_props:
		var prop: Node3D = home_food_props[key]
		prop.visible = int(food.stock.get(key,0))>0 and (String(food.hand)!=String(key) or int(food.stock.get(key,0))>1)
	if not is_instance_valid(home_pan_food): return
	for child in home_pan_food.get_children():
		home_pan_food.remove_child(child)
		child.queue_free()
	var key := String(food.pan)
	var cooked := float(food.remaining)<=0.0
	var burned := bool(food.burned)
	home_pan_heat.visible = bool(food.heat_on)
	home_pan_smoke.emitting = bool(food.heat_on) and cooked
	if key=="carne":
		for i in range(3):
			_rental_round(home_pan_food,Vector3((float(i)-1.0)*.048,.016,0),Vector3(.051,.03,.065),Color("#28221c") if burned else (Color("#805034") if cooked else Color("#a74e46")))
	elif key=="huevo":
		_rental_round(home_pan_food,Vector3.ZERO,Vector3(.145,.012,.120),Color("#393027") if burned else (Color("#eee6d5") if cooked else Color("#b9b3a0")))
		_rental_round(home_pan_food,Vector3(.02,.009,0),Vector3(.048,.021,.048),Color("#4f3823") if burned else Color("#e6a72b"))

func _home_shelf_aim(node: Node3D,door: Node3D,body: StaticBody3D,center: Vector3,extent: Vector3) -> bool:
	if not is_instance_valid(node) or not is_instance_valid(door) or not is_instance_valid(body): return false
	if absf(door.rotation.y)<.55: return false
	var cam: Camera3D = game.play_camera
	var start := cam.global_position
	var end := start-cam.global_basis.z*2.8
	var hit: Variant = AABB(center-extent,extent*2.0).intersects_segment(node.to_local(start),node.to_local(end))
	if hit==null: return false
	var point := node.to_global(Vector3(hit))
	if game.player.global_position.distance_to(point)>2.8 or _door_blocks_target(start,point,node): return false
	var ray := PhysicsRayQueryParameters3D.create(start,point,1|2)
	ray.exclude = [game.player.get_rid(),body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _home_food_action() -> String:
	if not inside or not is_instance_valid(home_pan) or dining_seated: return ""
	if dish_washing: return "[E] Lavando plato…"
	if home_food_busy: return "[E] Preparando comida…"
	var food: Dictionary = state.home_food
	var hand := String(food.hand)
	var pan := String(food.pan)
	var pan_aim := _aim_tool(home_pan,Vector3(0,.045,0),Vector3(.15,.075,.13))
	var plate_aim := _home_shelf_aim(home_plate_stack,home_plate_door,rice_cabinet_body,Vector3(0,.035,0),Vector3(.13,.055,.13))
	if hand=="plato" and bool(food.plate_dirty):
		if _aim_dish_sink(): return "[E] Lavar plato sucio"
		if plate_aim: return "[E] Lava el plato antes de guardarlo"
		return ""
	if pan_aim and not pan.is_empty() and hand in ["","plato"]:
		if bool(food.heat_on):
			if bool(food.burned): return "[E] Apagar fogón · comida quemada"
			if float(food.remaining)>0.0: return "[E] Apagar fogón · cocinando %s (%d s)" % [pan,ceili(float(food.remaining))]
			return "[E] Apagar fogón · %s listo · %d s antes de quemarse" % [pan,ceili(maxf(0.0,float(HOME_PAN_GRACE.get(pan,15.0))-float(food.overcook)))]
		if bool(food.burned): return "[E] Recoger comida quemada" if hand.is_empty() and _free_hands() else "[E] Devuelve el plato antes de retirar la comida quemada"
		if float(food.remaining)>0.0: return "[E] Encender fogón · continuar cocción"
	if hand=="plato":
		if _aim_tool(rice_lid,Vector3(0,.02,.15),Vector3(.19,.055,.19)) or _aim_tool(rice_cooker,Vector3(0,.16,0),Vector3(.22,.18,.21)):
			if int(state.rice_recipe.portions)>0 and bool(state.rice_recipe.lid): return "[E] Abrir arrocera"
			if int(state.rice_recipe.portions)>0 and "arroz" not in food.plate: return "[E] Echar arroz al plato"
			return "[E] Ya tienes arroz" if "arroz" in food.plate else "[E] No hay arroz listo"
		if pan_aim:
			if pan.is_empty(): return "[E] Cazuela vacía"
			if float(food.remaining)>0.0: return "[E] Cocinando "+pan+" · %d s" % ceili(float(food.remaining))
			if "carne" in food.plate or "huevo" in food.plate: return "[E] El plato ya tiene acompañamiento"
			return "[E] Servir "+pan+" al plato"
		if plate_aim and food.plate.is_empty(): return "[E] Devolver plato"
		if not storage_action(game.player.global_position).is_empty(): return ""
		if not food.plate.is_empty() and _aimed_furniture()=="mesa" and food.table_plate.is_empty() and not bool(food.table_used_plate): return "[E] Dejar plato en la mesa"
		return ""
	if hand=="botella":
		if _aimed_furniture()=="mesa" and int(food.table_water)<0: return "[E] Dejar botella de agua en la mesa"
	elif hand in ["carne","huevo"]:
		if pan_aim: return "[E] Cocinar "+hand if pan.is_empty() else "[E] La cazuela está ocupada"
	else:
		if not _free_hands(): return ""
		if plate_aim: return "[E] Recoger plato"
		if pan_aim:
			if pan.is_empty(): return "[E] Cazuela · busca carne o huevo en el refrigerador"
			if float(food.remaining)>0.0: return "[E] Cocinando "+pan+" · %d s" % ceili(float(food.remaining))
			return "[E] "+pan.capitalize()+" listo · recoge un plato"
	for key in home_food_props:
		var door: Node3D = rental_fridge_doors.get("pollo" if key=="carne" else "huevos")
		var prop: Node3D = home_food_props[key]
		var center := Vector3(0,.105,0) if key=="botella" else Vector3(0,.035,0)
		var extent := Vector3(.06,.12,.06) if key=="botella" else Vector3(.10,.065,.08)
		if not _home_shelf_aim(prop,door,home_food_fridge_body,center,extent): continue
		if hand==String(key): return "[E] Devolver "+String(key)
		if hand.is_empty() and int(food.stock.get(key,0))>0: return "[E] Recoger "+String(key)
	return ""

func _home_food_interact() -> bool:
	var action := _home_food_action()
	if action.is_empty(): return false
	if home_food_busy: return true
	var food: Dictionary = state.home_food
	var hand := String(food.hand)
	if action=="[E] Lavar plato sucio":
		_wash_plate_async()
		return true
	elif action=="[E] Lava el plato antes de guardarlo":
		business._notify("No puedes guardar un plato sucio. Mira el fregadero y pulsa E.")
		return true
	elif action.begins_with("[E] Apagar fogón"):
		food.heat_on = false
		business._notify("Fogón apagado.")
	elif action.begins_with("[E] Encender fogón"):
		food.heat_on = true
	elif action=="[E] Recoger comida quemada":
		if not _free_hands(): return true
		state.waste_hand = {"kind":"burned_food","volume":1}
		food.pan = ""
		food.remaining = 0.0
		food.overcook = 0.0
		food.burned = false
	elif action=="[E] Recoger plato":
		food.hand = "plato"
		food.plate_dirty = false
		food.just_washed = false
	elif action=="[E] Devolver plato":
		if bool(food.plate_dirty):
			business._notify("Primero lava el plato en el fregadero.")
			return true
		food.hand = ""
		food.plate_dirty = false
		food.just_washed = false
		business._notify("Plato limpio guardado en el armario.")
	elif action=="[E] Dejar botella de agua en la mesa":
		food.table_water = 3
		food.stock.botella = maxi(0,int(food.stock.botella)-1)
		food.hand = ""
		_refresh_dining_table()
	elif action.begins_with("[E] Recoger "):
		food.hand = action.trim_prefix("[E] Recoger ")
	elif action.begins_with("[E] Devolver "):
		food.hand = ""
	elif action.begins_with("[E] Cocinar ") and hand in ["carne","huevo"] and String(food.pan).is_empty():
		_home_food_transfer(hand,false)
		return true
	elif action=="[E] Abrir arrocera":
		_set_rice_lid(false)
		return true
	elif action=="[E] Echar arroz al plato":
		_home_food_transfer("arroz",true)
		return true
	elif action.begins_with("[E] Servir ") and hand=="plato":
		_home_food_transfer(String(food.pan),true)
		return true
	elif action=="[E] Dejar plato en la mesa":
		food.table_plate = food.plate.duplicate()
		food.table_used_plate = true
		food.table_bites = 3
		food.hand = ""
		food.plate = []
		food.just_washed = false
		_refresh_dining_table()
		business._notify("Plato servido. Busca agua si quieres y siéntate en la silla.")
	_refresh_home_food()
	_refresh_carried()
	_save()
	return true

func _home_food_transfer(key: String,serving: bool) -> void:
	if home_food_busy or (serving and bool(state.home_food.plate_dirty)): return
	home_food_busy = true
	var food: Dictionary = state.home_food
	var destination: Node3D = rice_cooker if key=="arroz" else home_pan
	var model := _rental_root(destination,Vector3(.24,.36,.14))
	if serving:
		business.life.draw_home_plate(model,food.plate)
		_attach_interaction_hand(model,Vector3(-.075,-.025,.06),true,true)
	else:
		_draw_home_raw_food(model,key)
		_attach_interaction_hand(model,Vector3(.055,-.015,.035))
	carried_view.hide()
	var motion := create_tween()
	motion.tween_property(model,"position",Vector3(.13,.23,.12),.45)
	if not serving: motion.parallel().tween_property(model,"rotation:z",1.25,.45)
	motion.tween_interval(.25)
	if not serving: motion.tween_property(model,"rotation:z",0.0,.20)
	motion.tween_property(model,"position",Vector3(.24,.36,.14),.35)
	await motion.finished
	model.queue_free()
	if serving:
		food.plate.append(key)
		if key=="arroz":
			state.rice_recipe.portions = maxi(0,int(state.rice_recipe.portions)-1)
			if int(state.rice_recipe.portions)==0: state.rice_recipe.added = []
			_refresh_rice_visuals()
		else:
			food.pan = ""
			food.remaining = 0.0
			food.heat_on = false
			food.overcook = 0.0
			food.burned = false
		business._notify("Añadiste "+key+" al plato. Mira la mesa o hacia tu plato para comer.")
	else:
		food.stock[key] = maxi(0,int(food.stock.get(key,0))-1)
		food.hand = ""
		food.pan = key
		food.remaining = float(HOME_PAN_TIME[key])
		food.heat_on = true
		food.overcook = 0.0
		food.burned = false
		business._notify("Cocinando "+key+"…")
	home_food_busy = false
	_refresh_home_food()
	_refresh_carried()
	carried_view.show()
	_save()

func _tick_home_pan(delta: float) -> void:
	if not is_instance_valid(home_pan): return
	var food: Dictionary = state.home_food
	if not bool(food.heat_on) or String(food.pan).is_empty(): return
	home_pan_save_clock += delta
	if home_pan_save_clock>=5.0:
		home_pan_save_clock = 0.0
		_save()
	if float(food.remaining)>0.0:
		food.remaining = maxf(0.0,float(food.remaining)-delta)
		if float(food.remaining)<=0.0:
			_refresh_home_food()
			_save()
			business._notify(String(food.pan).capitalize()+" listo. Apaga el fogón antes de que se queme.")
		return
	if bool(food.burned): return
	food.overcook = float(food.overcook)+delta
	if float(food.overcook)>=float(HOME_PAN_GRACE.get(String(food.pan),15.0)):
		food.burned = true
		_refresh_home_food()
		_save()
		business._notify("¡Se quemó la comida! Apaga el fogón y tira los restos a la basura.")

func _rice_prop_aim(key: String) -> bool:
	if not rice_pantry.has(key): return false
	var node: Node3D = rice_pantry[key]
	var door: Node3D = rice_doors.get(key)
	if not is_instance_valid(door) or absf(door.rotation.y)<.55: return false
	var cam: Camera3D = game.play_camera
	var start: Vector3 = cam.global_position
	var finish: Vector3 = start-cam.global_basis.z*2.8
	var hit: Variant = AABB(Vector3(-.075,-.005,-.06),Vector3(.15,.21,.12)).intersects_segment(node.to_local(start),node.to_local(finish))
	if hit==null: return false
	var point: Vector3 = node.to_global(Vector3(hit))
	if game.player.global_position.distance_to(point)>2.8: return false
	if _door_blocks_target(start,point,node): return false
	var ray := PhysicsRayQueryParameters3D.create(start,point,1|2)
	ray.exclude = [game.player.get_rid(),rice_cabinet_body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _rice_action() -> String:
	if not inside or not is_instance_valid(rice_cooker): return ""
	if not String(state.home_food.hand).is_empty(): return ""
	var recipe: Dictionary = state.rice_recipe
	var hand := String(recipe.hand)
	if rice_pouring: return "[E] Añadiendo ingrediente…"
	var aimed := _aim_tool(rice_cooker,Vector3(0,.16,0),Vector3(.22,.18,.21))
	var lid_aimed := _aim_tool(rice_lid,Vector3(0,.02,.15),Vector3(.19,.055,.19))
	if not hand.is_empty():
		if hand=="jarra" and _aim_tool(kitchen_tap,Vector3(0,.06,.08),Vector3(.13,.21,.16)): return "[E] Llenar jarra de agua"
		if hand!="jarra" and (aimed or lid_aimed): return "[E] Añadir "+hand if not bool(recipe.lid) else "[E] Abrir tapa de la arrocera"
		if hand in ["jarra","agua"] and _aim_tool(rice_jug,Vector3(0,.075,0),Vector3(.10,.10,.10)): return "[E] Devolver jarra"
		if hand in ["arroz","sal","aceite"] and _rice_prop_aim(hand): return "[E] Devolver "+hand
		return ""
	if aimed or lid_aimed:
		if float(recipe.remaining)>0.0: return "[E] Arroz cocinándose · %d s" % ceili(float(recipe.remaining))
		if int(recipe.portions)>0:
			if bool(recipe.lid): return "[E] Abrir arrocera"
			if lid_aimed: return "[E] Cerrar tapa"
			return "[E] Recoge un plato del armario superior"
		if bool(recipe.lid):
			return "[E] Cocinar arroz" if recipe.added.size()==4 else "[E] Abrir tapa de la arrocera"
		return "[E] Cerrar tapa" if recipe.added.size()==4 else "[E] Cerrar tapa · faltan "+_rice_missing()
	if not _free_hands(): return ""
	if _aim_tool(rice_jug,Vector3(0,.075,0),Vector3(.10,.10,.10)) and "agua" not in recipe.added and float(recipe.remaining)<=0.0 and int(recipe.portions)==0: return "[E] Recoger jarra"
	for key in rice_pantry:
		if _rice_prop_aim(String(key)) and int(recipe.stock.get(key,0))>0 and key not in recipe.added and float(recipe.remaining)<=0.0 and int(recipe.portions)==0:
			return "[E] Recoger "+String(key)
	return ""

func _rice_missing() -> String:
	var missing := PackedStringArray()
	for key in RICE_INGREDIENTS:
		if key not in state.rice_recipe.added: missing.append(key)
	return ", ".join(missing)

func _rice_interact() -> bool:
	var action := _rice_action()
	if action.is_empty(): return false
	if rice_pouring: return true
	var recipe: Dictionary = state.rice_recipe
	var hand := String(recipe.hand)
	if action.contains("Recoger jarra"): recipe.hand = "jarra"
	elif action.contains("Llenar jarra"):
		_fill_rice_jug_async()
		return true
	elif action.contains("Recoger "): recipe.hand = action.trim_prefix("[E] Recoger ")
	elif action.contains("Devolver "): recipe.hand = ""
	elif action.contains("Abrir tapa") or action.contains("Abrir arrocera"):
		_set_rice_lid(false)
		return true
	elif action.contains("Añadir "):
		if hand in RICE_INGREDIENTS and hand not in recipe.added and float(recipe.remaining)<=0.0 and int(recipe.portions)==0 and not bool(recipe.lid):
			_add_rice_async(hand)
		return true
	elif action.contains("Cerrar tapa"):
		_set_rice_lid(true)
		return true
	elif action=="[E] Cocinar arroz":
		if recipe.added.size()==4 and bool(recipe.lid):
			recipe.remaining = RICE_COOK_SECONDS
			business._notify("Arrocera encendida. Puedes hacer otras cosas mientras cocina.")
	elif action.contains("Recoge un plato"):
		business._notify("Abre el armario superior derecho y recoge un plato.")
	elif action.contains("faltan"): business._notify("Busca los ingredientes: "+_rice_missing())
	_refresh_rice_visuals()
	_refresh_carried()
	_save()
	return true

func _set_rice_lid(closed: bool) -> void:
	state.rice_recipe.lid = closed
	if is_instance_valid(rice_lid_tween): rice_lid_tween.kill()
	if is_instance_valid(rice_lid_hand): rice_lid_hand.queue_free()
	rice_lid_hand = _attach_interaction_hand(rice_lid,Vector3(.045,.080,.16))
	rice_lid_tween = create_tween()
	rice_lid_tween.tween_property(rice_lid,"rotation:x",0.0 if closed else -1.65,.35).set_trans(Tween.TRANS_SINE)
	rice_lid_tween.finished.connect(_clear_rice_lid_hand)
	_save()

func _clear_rice_lid_hand() -> void:
	if is_instance_valid(rice_lid_hand): rice_lid_hand.queue_free()
	rice_lid_hand = null

func _fill_rice_jug_async() -> void:
	if rice_pouring: return
	rice_pouring = true
	# Keep the jug and grip above the countertop rather than inside it.
	var jug := _rental_root(kitchen_tap,Vector3(0,-.085,.25))
	_draw_rice_ingredient(jug,"jarra")
	_attach_interaction_hand(jug,Vector3(.066,.075,.025))
	carried_view.hide()
	var was_running: bool = tap_water.visible
	tap_water.show()
	await get_tree().create_timer(.85).timeout
	tap_water.visible = was_running
	jug.queue_free()
	state.rice_recipe.hand = "agua"
	rice_pouring = false
	_refresh_rice_visuals()
	_refresh_carried()
	carried_view.show()
	_save()

func _add_rice_async(key: String) -> void:
	if rice_pouring: return
	rice_pouring = true
	var recipe: Dictionary = state.rice_recipe
	var ingredient := _rental_root(rice_cooker,Vector3(.24,.52,.12))
	_draw_rice_ingredient(ingredient,key)
	_attach_interaction_hand(ingredient,Vector3(.066,.075,.025) if key=="agua" else Vector3(.045,.055,.025))
	carried_view.hide()
	var pour := create_tween()
	pour.tween_property(ingredient,"position",Vector3(.10,.49,.05),.35)
	pour.parallel().tween_property(ingredient,"rotation:z",1.8,.35)
	await pour.finished
	var color := Color("#eae2c8")
	if key=="agua": color = Color("#8ab6cc")
	elif key=="aceite": color = Color("#d3ae50")
	var stream := _rental_cylinder(rice_cooker,Vector3(0,.335,0),.012,.14,color)
	await get_tree().create_timer(.50).timeout
	stream.queue_free()
	ingredient.queue_free()
	recipe.added.append(key)
	if key!="agua": recipe.stock[key] = maxi(0,int(recipe.stock.get(key,0))-1)
	recipe.hand = ""
	rice_pouring = false
	_refresh_rice_visuals(false)
	_refresh_carried()
	carried_view.show()
	_save()
	business._notify("Añadiste "+key+" · "+("ingredientes completos" if recipe.added.size()==4 else "faltan "+_rice_missing()))

func _tick_rice(delta: float) -> void:
	if not is_instance_valid(rice_cooker): return
	var recipe: Dictionary = state.rice_recipe
	if float(recipe.remaining)<=0.0: return
	recipe.remaining = maxf(0.0,float(recipe.remaining)-delta)
	if float(recipe.remaining)<=0.0:
		recipe.portions = 2
		_refresh_rice_visuals()
		_save()
		business._notify("Arroz listo · 2 platos. La arrocera pasó a mantener caliente.")

func _domestic_target() -> Dictionary:
	if not inside or not game.adaptation_mode: return {}
	if not String(state.held_furniture).is_empty() or not String(state.paint_tool).is_empty(): return {}
	for entry in home_windows:
		var root: Node3D = entry.root
		var width: float = entry.width
		for curtain in entry.curtains:
			if _aim_tool(curtain,Vector3.ZERO,Vector3(width*.25,.74,.12)): return {"kind":"curtain","window":entry}
		if _aim_tool(root,Vector3(0,0,.12),Vector3(width*.5,.58,.12)): return {"kind":"window","window":entry}
	if _aim_tool(bedside_drawer,Vector3(0,0,.25),Vector3(.24,.12,.10)): return {"kind":"drawer"}
	if _aim_tool(bedside_lamp,Vector3(0,.22,0),Vector3(.20,.25,.20)): return {"kind":"lamp"}
	if _aim_tool(television,Vector3(0,.98,.12),Vector3(.32,.26,.20)): return {"kind":"tv"}
	if _aim_tool(kitchen_tap,Vector3(0,.06,.08),Vector3(.08,.16,.14)): return {"kind":"tap"}
	if _coffee_machine_phase()=="idle" and _aim_tool(coffee_pot,Vector3(0,.15,0),Vector3(.14,.17,.12)): return {"kind":"brew"}
	if _aim_tool(coffee_cup,Vector3(0,.05,0),Vector3(.09,.07,.09)): return {"kind":"drink"}
	if _aimed_furniture()=="cama": return {"kind":"bed"}
	return {}

func domestic_action() -> String:
	var target := _domestic_target()
	if coffee_busy and String(target.get("kind","")) in ["brew","drink"]: return coffee_phase
	match String(target.get("kind","")):
		"curtain": return "[E] "+("Cerrar cortinas" if bool(target.window.curtain) else "Abrir cortinas")
		"window": return "[E] "+("Cerrar ventana" if bool(target.window.window) else "Abrir ventana")
		"drawer": return "[E] "+("Cerrar cajón" if bedside_drawer.position.z>.15 else "Abrir cajón")
		"lamp": return "[E] "+("Apagar lámpara" if bedside_glow.visible else "Encender lámpara")
		"tv": return "[E] "+("Apagar televisor" if bool(state.get("tv_on",false)) else "Encender televisor")
		"tap": return "[E] "+("Cerrar grifo" if tap_water.visible else "Abrir grifo")
		"brew":
			if int(business.life.state.coffee_cups)==0: return "[E] Preparar colada"
			if bool(business.life.state.coffee_served): return "Café servido · 1 taza"
			return "[E] Servir café · 1 taza"
		"drink":
			if _coffee_machine_phase() in ["heating","ready"]: return "Apaga el fogón cuando el café esté listo"
			if bool(business.life.state.coffee_served): return "[E] Tomar café"
			if int(business.life.state.coffee_cups)>0: return "[E] Servir una taza"
			return "Taza vacía · prepara una colada"
		"bed": return "[E] Cama · Dormir / tender / mover"
	return ""

func domestic_interact() -> bool:
	var target := _domestic_target()
	match String(target.get("kind","")):
		"curtain","window":
			var entry: Dictionary = target.window
			var kind: String = target.kind
			entry[kind] = not bool(entry[kind])
			var tween := create_tween().set_parallel(true)
			if kind=="window":
				for slat in entry.slats: tween.tween_property(slat,"rotation:x",-1.22 if entry.window else -.30,.35)
			else:
				for i in range(entry.curtains.size()):
					var curtain: Node3D = entry.curtains[i]
					var side := -1.0 if i==0 else 1.0
					tween.tween_property(curtain,"scale:x",.30 if entry.curtain else 1.0,.45)
					tween.tween_property(curtain,"position:x",side*float(entry.width)*(.45 if entry.curtain else .25),.45)
			if not state.has("window_states"): state.window_states = {}
			state.window_states[entry.id] = {"window":entry.window,"curtain":entry.curtain}
			game._update_visual_lighting(true)
			_save()
		"drawer":
			var goal := 0.0 if bedside_drawer.position.z>.15 else .30
			var tween := create_tween()
			tween.tween_property(bedside_drawer,"position:z",goal,.30)
		"lamp":
			bedside_glow.visible = not bedside_glow.visible
			state.bedside_light = bedside_glow.visible
			game._update_visual_lighting(true)
			_save()
		"tv":
			state.tv_on = not bool(state.get("tv_on",false))
			_refresh_tv_screen()
			_save()
		"tap": tap_water.visible = not tap_water.visible
		"brew":
			if int(business.life.state.coffee_cups)==0: _brew_coffee_async()
			elif not bool(business.life.state.coffee_served): _serve_coffee_async()
		"drink":
			if _coffee_machine_phase() in ["heating","ready"]:
				business._notify("Primero apaga el fogón cuando esté listo el café.")
			elif bool(business.life.state.coffee_served): _drink_coffee_async()
			elif int(business.life.state.coffee_cups)>0: _serve_coffee_async()
			else: business._notify("Prepara una colada en la cafetera.")
		"bed": _bed_menu()
		_: return false
	return true

func _brew_coffee_async() -> void:
	if coffee_busy or not _free_hands() or _coffee_machine_phase()!="idle": return
	if int(business.life.state.coffee_cups)>0: return
	state.coffee_machine.phase = "heating"
	state.coffee_machine.remaining = 5.0
	coffee_save_clock = 0.0
	_refresh_coffee_machine()
	_save()
	business._notify("Fogón encendido. Preparando una colada de una taza.")

func _serve_coffee_async() -> void:
	if coffee_busy or not _free_hands() or _coffee_machine_phase()!="idle": return
	if int(business.life.state.coffee_cups)<=0 or bool(business.life.state.coffee_served): return
	coffee_busy = true
	coffee_phase = "Sirviendo café…"
	var origin: Vector3 = coffee_pot.position
	var hand := _attach_interaction_hand(coffee_pot,Vector3(.122,.194,.025))
	var lift := create_tween()
	lift.tween_property(coffee_pot,"position",origin+Vector3.UP*.34,.30)
	lift.tween_property(coffee_pot,"position",Vector3(.285,1.28,.15),.45)
	lift.tween_property(coffee_pot,"rotation:z",1.25,.35)
	await lift.finished
	coffee_stream.show()
	coffee_liquid.show()
	coffee_liquid.position.y = .014
	var pour := create_tween()
	pour.tween_property(coffee_liquid,"position:y",.045,.70)
	await pour.finished
	coffee_stream.hide()
	var back := create_tween()
	back.tween_property(coffee_pot,"rotation:z",0.0,.35)
	back.tween_property(coffee_pot,"position",origin+Vector3.UP*.34,.45)
	back.tween_property(coffee_pot,"position",origin,.30)
	await back.finished
	hand.queue_free()
	business.life.serve_home_coffee()
	_refresh_coffee_visual()
	coffee_busy = false
	business._notify("Taza servida · apunta a la taza y pulsa E para beber.")

func _coffee_safe_pose(at: Vector3) -> void:
	if is_instance_valid(coffee_drink_view):
		coffee_drink_view.position = InteractionHand.camera_safe_pose(game.play_camera,at,.09)

func _drink_coffee_async() -> void:
	if coffee_busy or not _free_hands() or not bool(business.life.state.coffee_served): return
	coffee_busy = true
	coffee_phase = "Tomando café…"
	coffee_cup.hide()
	coffee_drink_view = Node3D.new()
	game.play_camera.add_child(coffee_drink_view)
	coffee_drink_view.position = Vector3(.27,-.35,-.52)
	var liquid := _make_coffee_cup(coffee_drink_view)
	_attach_interaction_hand(coffee_drink_view,Vector3(.065,.035,.018))
	liquid.show()
	var sip := create_tween()
	for i in range(3):
		sip.tween_method(_coffee_safe_pose,Vector3(.27,-.35,-.52),Vector3(.065,-.115,-.27),.34)
		sip.parallel().tween_property(coffee_drink_view,"rotation:x",.60,.34)
		sip.tween_interval(.35)
		sip.tween_property(liquid,"position:y",.045-float(i+1)*.010,.14)
		sip.tween_method(_coffee_safe_pose,Vector3(.065,-.115,-.27),Vector3(.27,-.35,-.52),.30)
		sip.parallel().tween_property(coffee_drink_view,"rotation:x",0.0,.30)
		sip.tween_interval(.15)
	await sip.finished
	if is_instance_valid(coffee_drink_view): coffee_drink_view.queue_free()
	business.life.drink_home_coffee()
	coffee_cup.show()
	_refresh_coffee_visual()
	coffee_busy = false
	business._notify("Café tomado · hasta +5 de energía. Prepara otra colada cuando quieras.")

func _bed_menu() -> void:
	var life = business.life
	var wake := int(float(life.state.minutes)+life.planned_sleep_minutes())
	business._open("Cama","Despertarás a las "+life.format_time(wake)+". Puedes cambiar la alarma en el móvil.")
	business._button("Dormir",_sleep_home,not _free_hands())
	business._button("Tender la cama",_make_home_bed,not bool(life.state.get("bed_unmade",false)))
	if not game.adaptation_mode: business._button("Mover cama",_take_bed,not _free_hands())
	business._button("Cerrar",business.close)

func _take_bed() -> void:
	if game.adaptation_mode: return
	if not _free_hands() or not furniture_nodes.has("cama"): return
	state.held_furniture = "cama"
	_refresh_furniture("cama")
	_refresh_carried()
	_save()
	business.close()

func _make_home_bed() -> void:
	business.life.state.bed_unmade = false
	_refresh_furniture("cama")
	_save()
	business.close()
	business._notify("Cama tendida.")

func _sleep_home() -> void:
	if not inside or not _free_hands(): return
	var message: String = business.life.sleep_at_home()
	_refresh_furniture("cama")
	_update_wall_clock()
	game._update_visual_lighting(true)
	business._open("Descanso",message+".")
	business._button("Levantarse",business.close)
	_save()

func action_text(at: Vector3) -> String:
	if riding: return "Frenando para bajar" if ride_exit_requested else "[E] Bajar"
	if inside:
		var dining_action := _dining_action()
		if not dining_action.is_empty(): return dining_action
		if not business.life.state.meal.is_empty(): return "[E] Comer / beber"
		var bath_action := _bath_action()
		if not bath_action.is_empty(): return bath_action
		if _home_exit_selected(at): return "[E] Salir de casa"
		var coffee_action := _coffee_special_action()
		if not coffee_action.is_empty(): return coffee_action
		var light_action := _switch_action()
		if not light_action.is_empty(): return light_action
		var food_action := _home_food_action()
		if not food_action.is_empty(): return food_action
		if not String(state.home_food.hand).is_empty(): return storage_action(at)
		var rice_action := _rice_action()
		if not rice_action.is_empty(): return rice_action
		var domestic := domestic_action()
		if not domestic.is_empty(): return domestic
		var storage := storage_action(at)
		if not storage.is_empty(): return storage
		var waste_action := _waste_action(at)
		if not waste_action.is_empty(): return waste_action
		var tool_action := _house_tool_action(at)
		if not tool_action.is_empty(): return tool_action
		if _aimed_project(at): return "[E] Mejorar / ensamblar "+String(Kit.KITS.get(String(state.project),{}).get("name","vehículo"))
		if game.adaptation_mode: return ""
		if not String(state.held_furniture).is_empty(): return "[E] Colocar mueble · llévalo afuera para desechar"
		var id := _aimed_furniture()
		return "[E] Mover "+String(FURNITURE[id].name) if not id.is_empty() else ""
	if not state.get("waste_hand",{}).is_empty():
		if not _nearest_bin(at).is_empty(): return "[E] Tirar basura"
		if not _aimed_home(at): return "Lleva la basura a un basurero de la calle"
	if not String(state.held_furniture).is_empty() and not _nearest_bin(at).is_empty(): return "[E] Desechar mueble"
	if _aimed_home(at): return "[E] Entrar a la casa alquilada" if game.adaptation_mode else "[E] Entrar a mi casa"
	if _near_coffee_market(at): return "[E] Mercado · artículos de cocina"
	if not _vendor_at(at).is_empty(): return "[E] Comprar repuestos"
	for kind in owned:
		var body: CharacterBody3D = owned[kind]
		if at.distance_to(body.global_position+Vector3.UP*.6)<2.8 and not _listed(String(kind)): return "[E] Montar "+String(Kit.KITS[kind].name)
	return ""

func interact(at: Vector3) -> bool:
	if riding:
		ride_exit_requested = true
		if absf(ride_speed)<.6: _dismount()
		return true
	if inside:
		if _dining_interact(): return true
		if not business.life.state.meal.is_empty(): return business.life.interact(at)
		elif _bath_interact(): return true
		elif _home_exit_selected(at):
			_exit()
		elif _coffee_special_interact(): pass
		elif _switch_interact(): pass
		elif _home_food_interact(): pass
		elif not String(state.home_food.hand).is_empty():
			if storage_interact(at): return true
			return true
		elif _rice_interact(): pass
		elif not String(state.rice_recipe.hand).is_empty():
			if storage_interact(at): return true
			business._notify("Lleva el ingrediente a la arrocera o devuélvelo a su estante.")
		elif domestic_interact(): pass
		elif storage_interact(at): pass
		elif _waste_interact(at): pass
		elif _house_tool_interact(at): pass
		elif _aimed_project(at):
			if _unlocked(String(state.project)):
				if not state.projects.has(String(state.project)): state.projects[String(state.project)] = {}
				_project_menu()
			else: _garage_menu()
		elif not game.adaptation_mode and not String(state.held_furniture).is_empty(): _place_furniture()
		elif not game.adaptation_mode:
			var id := _aimed_furniture()
			if not id.is_empty() and _free_hands():
				if id=="mesa" and (bool(state.home_food.table_used_plate) or not state.home_food.table_plate.is_empty() or int(state.home_food.table_water)>=0):
					business._notify("Retira la comida y la botella antes de mover la mesa.")
					return true
				state.held_furniture = id
				_refresh_furniture(id)
				_refresh_carried()
				_save()
		return true
	if not state.get("waste_hand",{}).is_empty():
		var disposal := _nearest_bin(at)
		if not disposal.is_empty():
			if game.monte_services.add_household_waste(disposal,state.waste_hand):
				state.waste_hand = {}
				_refresh_carried()
				_save()
				business._notify("Basura depositada.")
			return true
		if _aimed_home(at): _enter()
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
	if _near_coffee_market(at):
		_coffee_market_menu()
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

func riding_borrowed() -> bool:
	return riding and is_instance_valid(borrowed_body)

func _ride_body() -> CharacterBody3D:
	if riding_borrowed(): return borrowed_body
	return owned.get(ride_kind) as CharacterBody3D

# All player-controlled two/three-wheel vehicles use the actual protagonist,
# not a randomly styled street NPC. Fit the duplicated visual rig to the
# physical seat, grips and pedals once; no extra simulation or collision.
func _player_driver(body: CharacterBody3D,kind: String = "moto") -> Node3D:
	var source: Node3D = game.avatar
	var driver := source.duplicate(0) as Node3D
	body.add_child(driver)
	driver.name = "PlayerRider"
	var moto := kind=="moto"
	var tri := kind=="triciclo"
	driver.position = Vector3(0,1.26,-.32 if moto else -.23)
	driver.rotation = Vector3(.22 if moto else .30,0,0)
	driver.scale = Vector3.ONE
	driver.show()
	var spec: Dictionary = Kit.KITS[kind]
	var grip_z := .23 if moto else float(spec.length)*.35*.77
	var grip_x := .30 if moto else float(spec.width)*.36
	for i in range(2):
		var side := -1.0 if i==0 else 1.0
		var source_arm: Node3D = game.limb_arms[i]
		var source_leg: Node3D = game.limb_legs[i]
		var arm_node := driver.get_node(source.get_path_to(source_arm)) as Node3D
		var leg_node := driver.get_node(source.get_path_to(source_leg)) as Node3D
		arm_node.rotation = Vector3.ZERO
		leg_node.rotation = Vector3.ZERO
		# Do not duplicate food/drink or transient held props onto a rider.
		for node in arm_node.get_children():
			if node is MeshInstance3D: continue
			if node is Node3D: (node as Node3D).hide()
			else: node.queue_free()
		var shoulder := driver.to_local(arm_node.global_position)
		var grip := driver.to_local(body.to_global(Vector3(side*grip_x,1.16 if moto else 1.10,grip_z)))
		var elbow := _rider_bend(shoulder,grip,.32,.30,Vector3(side*.28,-1,0))
		var sleeve := arm_node.get_node("Sleeve") as MeshInstance3D
		var forearm := arm_node.get_node("Arm") as MeshInstance3D
		var palm := arm_node.get_node("Hand") as MeshInstance3D
		# Preserve the short sleeve with visible upper arm and forearm.
		var sleeve_end := shoulder.lerp(elbow,.55)
		var upper_skin := forearm.duplicate(0) as MeshInstance3D
		arm_node.add_child(upper_skin)
		_rider_segment(driver,sleeve,shoulder,sleeve_end)
		_rider_segment(driver,upper_skin,sleeve_end,elbow)
		_rider_segment(driver,forearm,elbow,grip)
		_rider_endpoint(driver,palm,grip)
		palm.rotation.x = PI*.5-driver.rotation.x
		var hip := driver.to_local(leg_node.global_position)
		var foot_z := .08 if moto or tri else side*.15
		var foot_x := .27 if moto or tri else .21
		var foot_y := .51 if moto or tri else .47
		var foot := driver.to_local(body.to_global(Vector3(side*foot_x,foot_y,foot_z)))
		var joint := _rider_bend(hip,foot,.34,.35,Vector3(side*.45,0,1))
		var thigh := leg_node.get_node("Leg") as MeshInstance3D
		var shoe := leg_node.get_node("Shoe") as MeshInstance3D
		var shin := thigh.duplicate(0) as MeshInstance3D
		leg_node.add_child(shin)
		_rider_segment(driver,thigh,hip,joint)
		_rider_segment(driver,shin,joint,foot)
		shin.scale.x *= .84
		shin.scale.z *= .86
		_rider_endpoint(driver,shoe,foot+Vector3(0,-.025,.045))
		shoe.rotation.x = -driver.rotation.x
	return driver

func mount_borrowed_moto(body: CharacterBody3D) -> bool:
	if riding or inside or game.driving or game.taxi_riding or game.bus_riding or not is_instance_valid(body) or not _free_hands(): return false
	borrowed_body = body
	body.remove_from_group("autonomous_traffic")
	body.remove_from_group("traffic_parked")
	body.set_meta("traffic_servicing",false)
	body.set_meta("junction_guard",false)
	rider = _player_driver(body)
	_begin_manual_ride(body,"moto")
	return true

func _mount(kind: String) -> void:
	if not _unlocked(kind) or _listed(kind):
		business._notify("Este vehículo está reservado o bloqueado.")
		return
	var body: CharacterBody3D = owned[kind]
	borrowed_body = null
	if kind!="carro": rider = _player_driver(body,kind)
	_begin_manual_ride(body,kind)

func _begin_manual_ride(body: CharacterBody3D,kind: String) -> void:
	riding = true
	ride_exit_requested = false
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
	var body := _ride_body()
	if not is_instance_valid(body): return
	var borrowed := riding_borrowed()
	var spec: Dictionary = Kit.KITS[ride_kind]
	var space := get_world_3d().direct_space_state
	var destination := Vector3.ZERO
	var found := false
	for offset in [Vector2(-1.0,0),Vector2(1.0,0),Vector2(-1.5,0),Vector2(1.5,0),Vector2(0,-1.9),Vector2(0,1.9)]:
		var local := Vector3(offset.x*(float(spec.width)*.5+.65),0,offset.y)
		var p := body.to_global(local)
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
		ride_exit_requested = false
		body.velocity = Vector3.ZERO
		business._notify("No hay espacio para bajar. Mueve el vehículo y vuelve a pulsar E.")
		return
	if borrowed:
		body.add_to_group("traffic_parked")
	else: _store_park(ride_kind)
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
	ride_exit_requested = false
	borrowed_body = null
	game.first_person = previous_first
	game._apply_camera_mode()
	if borrowed and game.yordi_mission!=null: game.yordi_mission.on_manual_bike_exit(force)

func reset() -> void:
	if not bath_mode.is_empty(): _finish_bath_action(false)
	if dining_seated: _stand_from_dining(true)
	_stop_home_paint()
	if riding: _dismount(true)
	inside = false
	garage_near = false

func drive(delta: float,movement: Vector2) -> void:
	var body := _ride_body()
	if not is_instance_valid(body): return
	var spec: Dictionary = Kit.KITS[ride_kind]
	var speed := float(spec.speed)*(1.0 if riding_borrowed() else 1.0+.08*float(state.upgrades.get(ride_kind,0)))
	var boost: bool = game.control_pressed(KEY_SHIFT) and movement.y<0.0 and game.gameplay_input()
	var target := -movement.y*(minf(45.0,speed*3.0) if boost else (speed if movement.y<=0 else speed*.28))
	var brake: bool = game.control_pressed(KEY_SPACE) or ride_exit_requested
	ride_speed = move_toward(ride_speed,0.0 if brake else target,delta*(16.0 if brake else (15.0 if boost else 4.0)))
	if ride_exit_requested and absf(ride_speed)<.3:
		_dismount()
		return
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
		if not riding_borrowed(): _store_park(ride_kind)

func _init_traffic() -> void:
	if game.monte_services==null or not game.monte_services.initialized: return
	var routes: Array = []
	if game.adaptation_mode:
		routes.append_array(game.monte_services.home_traffic_routes)
	if not game.monte_services.civilian_route.is_empty():
		routes.append(game.monte_services.civilian_route)
	if routes.is_empty():
		for vehicle in game.monte_services.vehicles:
			if not bool(vehicle.truck) and vehicle.route.size()>=5:
				routes.append(vehicle.route)
				break
	if routes.is_empty(): return
	var counts := {"bicicleta":0,"triciclo":0,"moto":0}
	for entry in traffic:
		if is_instance_valid(entry.body): counts[String(entry.kind)] += 1
	var desired := {"bicicleta":1,"triciclo":2,"moto":2} if game.adaptation_mode and not game.mobile_mode else {"bicicleta":1,"triciclo":1,"moto":1}
	for kind in ["bicicleta","triciclo","moto"]:
		if int(counts[kind])>=int(desired[kind]): continue
		# Try the neighborhood first, fall back to the existing main circuit.
		for route in routes:
			if _spawn_ambient_two_wheeler(String(kind),route,int(counts[kind])+traffic.size()):
				counts[kind] += 1
				print("MyCity tráfico: ",kind," ",counts[kind],"/",desired[kind])
				break
	traffic_ready = true
	for kind in desired:
		if int(counts[kind])<int(desired[kind]): traffic_ready = false

func _spawn_ambient_two_wheeler(kind: String,route: Array,slot: int) -> bool:
	if route.size()<5: return false
	var spec: Dictionary = Kit.KITS[kind]
	var preferred := floori(float(route.size())*float(posmod(slot,5))/5.0)
	for offset in range(route.size()):
		var i := (preferred+offset)%route.size()
		var p: Vector3 = route[i].p
		var actor_at: Vector3 = game.player.global_position
		if absf(actor_at.y-ROOM.y)<8.0 and not world.garage_home_site.is_empty():
			actor_at = world.garage_home_site.door
		if Vector2(p.x-actor_at.x,p.z-actor_at.z).length()<25.0: continue
		var separated := true
		for existing in get_tree().get_nodes_in_group("autonomous_traffic"):
			if not is_instance_valid(existing) or not existing is Node3D: continue
			if existing.global_position.distance_to(p)<12.0:
				separated = false
				break
		if not separated: continue
		var next: Vector3 = route[(i+1)%route.size()].p
		var d := (next-p).normalized()
		if d.length_squared()<.5 or not Bypass._on_road(world.street_geometry,p,d,float(spec.width),float(spec.length)): continue
		if not world.street_geometry.intersection_clear_for_stop(p,float(spec.length),float(spec.width)): continue
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
		_make_rider(body,kind,600+i+slot*7)
		body.add_to_group("autonomous_traffic")
		traffic.append({"body":body,"kind":kind,"route":route,"index":(i+1)%route.size(),"speed":0.0,"blocked":0.0,"cooldown":0.0,"detour":[],"detour_index":0,"resume":0})
		return true
	return false

func tick_ambient_traffic(delta: float) -> void:
	for i in range(traffic.size()-1,-1,-1):
		if not is_instance_valid(traffic[i].body):
			traffic.remove_at(i)
			traffic_ready = false
	if not traffic_ready:
		refresh_clock += delta
		if refresh_clock>=2.0:
			refresh_clock = 0.0
			_init_traffic()
	# Move existing vehicles even while a missing type is waiting for a berth.
	_traffic_tick(delta)

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
	_tick_rice(delta)
	if inside: _update_wall_clock()
	# Repair stale room state from older saves/mission teleports. Never move
	# the player here; just restore the house tools to their proper place.
	if inside and absf(game.player.global_position.y-ROOM.y)>12.0:
		inside = false
		garage_near = false
		_stop_home_paint()
		game.first_person = previous_first
		game._apply_camera_mode()
	elif not inside and has_home_tool():
		_stop_home_paint()
	_tick_listing(delta)
	if not game.ambient_city_suspended(): tick_ambient_traffic(delta)
	marker.position.y = 2.35+sin(Time.get_ticks_msec()*.003)*.12
	marker.visible = inside and _wheel_pending()
	_tick_home_paint(delta)
	_tick_paint_order(delta)
	if waypoint!=null:
		waypoint.visible = waypoint_active and not inside
		waypoint.global_position = waypoint_point+Vector3.UP*(2.7+sin(Time.get_ticks_msec()*.003)*.15)
	if carried_view!=null:
		carried_view.visible = not home_food_busy and not rice_pouring and not coffee_cleaning and not riding and not game.driving and not game.taxi_riding and not game.bus_riding
		if carried_view.visible and (not String(state.rice_recipe.hand).is_empty() or bool(state.coffee_machine.rag_held) or bool(state.coffee_machine.replacement)) and not coffee_cleaning:
			carried_view.position = InteractionHand.camera_safe_pose(game.play_camera,Vector3(.33,-.36,-.58),.15)
		if carried_view.visible and not String(state.home_food.hand).is_empty():
			var desired := Vector3(-.21,-.16,-.66) if String(state.home_food.hand)=="plato" else Vector3(.30,-.39,-.59)
			carried_view.position = InteractionHand.camera_safe_pose(game.play_camera,desired,.16)
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
	business.show_mission_reward("+Goma de bicicleta","","Bueno... por algo se empieza. Hay que dar gracias a Dios, hay quien tiene menos...","res://audio/carlos/player_wheel_reflection.mp3",_wheel_tutorial_after_reward)

func _wheel_tutorial_after_reward() -> void:
	if not inside or business.modal_open(): return
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
	if _door_blocks_target(origin,origin-cam.global_basis.z*depth): return false
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
	resting_broom.rotation = Vector3(.10,0,0)
	_make_broom_model(resting_broom)
	var saved_broom: Dictionary = state.get("broom_placement",{})
	var coords: Array = saved_broom.get("position",[])
	if coords.size()==3:
		var saved_pos := Vector3(float(coords[0]),float(coords[1]),float(coords[2]))
		if saved_pos.is_finite() and absf(saved_pos.x)<6.8 and absf(saved_pos.z)<5.8 and absf(saved_pos.y)<.2:
			resting_broom.position = saved_pos
			resting_broom.rotation = Vector3(-.145,float(saved_broom.get("yaw",0.0)),0)
	floor_image = Image.create(FLOOR_COLS*3,FLOOR_ROWS*3,false,Image.FORMAT_RGBA8)
	floor_image.fill(Color(0,0,0,0))
	floor_texture = ImageTexture.create_from_image(floor_image)
	var quad := QuadMesh.new()
	quad.size = Vector2(13.6,11.6)
	var visual := MeshInstance3D.new()
	visual.mesh = quad
	interior.add_child(visual)
	visual.position = Vector3(0,.052 if game.adaptation_mode else .036,0)
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
	_refresh_empty_cans()

func _make_empty_can(root: Node3D,color: String) -> void:
	var shell := CylinderMesh.new()
	shell.top_radius = .19
	shell.bottom_radius = .17
	shell.height = .34
	shell.radial_segments = 12
	shell.cap_top = false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#737c80")
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := MeshInstance3D.new()
	mesh.mesh = shell
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)
	business._box(root,Vector3(-.17,0,0),Vector3(.025,.14,.16),Color(PAINT_COLORS.get(color,"#a3abb3")))

func _refresh_empty_cans() -> void:
	if not is_instance_valid(paint_station): return
	var slot := 0
	for key in PAINT_COLORS:
		var color := String(key)
		var count := int(state.get("empty_paint",{}).get(color,0))
		var group: Node3D = empty_cans.get(color)
		if not is_instance_valid(group):
			group = Node3D.new()
			paint_station.add_child(group)
			group.position = Vector3(5.68,.18,1.85+float(slot)*.49)
			empty_cans[color] = group
		var shown := mini(count,3)
		while group.get_child_count()>shown:
			var old := group.get_child(group.get_child_count()-1)
			group.remove_child(old)
			old.queue_free()
		while group.get_child_count()<shown:
			var can := Node3D.new()
			group.add_child(can)
			can.position.y = float(group.get_child_count()-1)*.22
			_make_empty_can(can,color)
		group.visible = count>0
		slot += 1

func _aim_empty_can() -> String:
	for color in empty_cans:
		var group: Node3D = empty_cans[color]
		if not group.visible: continue
		for child in group.get_children():
			if _aim_tool(child,Vector3.ZERO,Vector3(.24,.20,.24)): return String(color)
	return ""

static func waste_volume(items: Array) -> int:
	var total := 0
	for item in items: total += int(item.get("volume",1))
	return total

# Shared entry point for future cooking, food packaging and other chores.
# A full bag never consumes the new item: it becomes recoverable floor waste.
func add_house_waste(kind: String,volume: int = 1,color: String = "") -> bool:
	var item := {"kind":kind,"volume":maxi(1,volume),"color":color}
	var fits := waste_volume(state.waste_items)+int(item.volume)<=WASTE_CAPACITY
	if fits: state.waste_items.append(item)
	else: state.waste_overflow.append(item)
	_refresh_waste()
	_save()
	if not fits: business._notify("La bolsa está llena. La basura cayó al suelo.")
	return fits

func _build_waste() -> void:
	waste_mesh.radius = .5
	waste_mesh.height = 1.0
	waste_mesh.radial_segments = 8
	waste_mesh.rings = 4
	waste_root = Node3D.new()
	interior.add_child(waste_root)
	waste_root.position = RENTAL_TRASH_POS if game.adaptation_mode else TRASH_POS
	waste_bag = Node3D.new()
	waste_root.add_child(waste_bag)
	waste_overflow = Node3D.new()
	waste_root.add_child(waste_overflow)
	_refresh_waste()

func _make_waste_item(root: Node3D,item: Dictionary) -> void:
	if String(item.get("kind",""))=="empty_water":
		_draw_home_water(root,0)
		return
	if String(item.get("kind",""))=="burned_food":
		for i in range(3):
			_rental_round(root,Vector3((float(i)-1.0)*.035,.01,0),Vector3(.045,.025,.055),Color("#33291f"))
		return
	if String(item.get("kind",""))=="broken_coffee":
		_draw_moka_model(root,true)
		return
	if String(item.get("kind",""))=="paint_can":
		_make_empty_can(root,String(item.get("color","")))
		return
	var mesh := MeshInstance3D.new()
	mesh.mesh = waste_mesh
	mesh.material_override = business._mat(Color("#343b35") if String(item.get("kind",""))=="bag" else Color("#9e8a63"))
	mesh.scale = Vector3(.43,.48,.39) if String(item.get("kind",""))=="bag" else Vector3(.17,.12,.18)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)

func _clear_waste_visual(root: Node3D) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()

func _refresh_waste() -> void:
	if not is_instance_valid(waste_bag): return
	_clear_waste_visual(waste_bag)
	_clear_waste_visual(waste_overflow)
	var fraction := clampf(float(waste_volume(state.waste_items))/WASTE_CAPACITY,0.0,1.0)
	var mesh := MeshInstance3D.new()
	mesh.mesh = waste_mesh
	mesh.material_override = business._mat(Color("#343b35"))
	mesh.scale = Vector3(.27+.24*fraction,.22+.43*fraction,.25+.22*fraction)
	mesh.position.y = mesh.scale.y*.5
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	waste_bag.add_child(mesh)
	business._box(waste_bag,Vector3(0,mesh.scale.y,.0),Vector3(.10,.08,.11),Color("#292e28"))
	for i in range(mini(state.waste_overflow.size(),12)):
		var prop := Node3D.new()
		waste_overflow.add_child(prop)
		prop.position = Vector3(.40+float(i%2)*.25,.12,.12+floorf(float(i)/2.0)*.22) if game.adaptation_mode else Vector3(-.50-float(i%4)*.42,.18,.18-float(i/4)*.32)
		_make_waste_item(prop,state.waste_overflow[i])

func _waste_action(at: Vector3) -> String:
	if not is_instance_valid(waste_bag): return ""
	var near_bag := at.distance_to(waste_root.global_position)<2.0
	var hand: Dictionary = state.get("waste_hand",{})
	if not hand.is_empty():
		if near_bag and _aim_tool(waste_bag,Vector3(0,.28,0),Vector3(.4,.4,.4)):
			return "[E] Echar basura en la bolsa" if String(hand.kind)!="bag" else "[E] Devolver bolsa"
		return "Lleva la basura al basurero" if String(hand.kind)=="bag" else "Lleva el envase vacío a la bolsa o al basurero"
	if not _free_hands(): return ""
	if not _aim_empty_can().is_empty(): return "[E] Recoger lata vacía"
	if near_bag and _aim_tool(waste_bag,Vector3(0,.28,0),Vector3(.4,.4,.4)):
		return "[E] Sacar bolsa · %d%% llena" % roundi(100.0*waste_volume(state.waste_items)/WASTE_CAPACITY) if not state.waste_items.is_empty() else "Bolsa vacía"
	for prop in waste_overflow.get_children():
		if _aim_tool(prop,Vector3.ZERO,Vector3(.23,.22,.23)): return "[E] Recoger basura del suelo"
	return ""

func _waste_interact(at: Vector3) -> bool:
	var action := _waste_action(at)
	if action.is_empty(): return false
	if action.contains("Recoger lata"):
		var color := _aim_empty_can()
		if color.is_empty(): return true
		state.empty_paint[color] = maxi(0,int(state.empty_paint[color])-1)
		state.waste_hand = {"kind":"paint_can","volume":3,"color":color}
		_refresh_empty_cans()
	elif action.contains("Sacar bolsa"):
		state.waste_hand = {"kind":"bag","volume":waste_volume(state.waste_items),"items":state.waste_items.duplicate(true)}
		state.waste_items = []
	elif action.contains("Devolver bolsa"):
		if not state.waste_items.is_empty():
			business._notify("Ya hay otra bolsa con basura. Lleva esta al basurero.")
			return true
		state.waste_items = state.waste_hand.get("items",[]).duplicate(true)
		state.waste_hand = {}
	elif action.contains("Echar basura"):
		var item: Dictionary = state.waste_hand.duplicate(true)
		state.waste_hand = {}
		add_house_waste(String(item.kind),int(item.volume),String(item.get("color","")))
	elif action.contains("Recoger basura del suelo"):
		var index := 0
		for prop in waste_overflow.get_children():
			if _aim_tool(prop,Vector3.ZERO,Vector3(.23,.22,.23)):
				state.waste_hand = state.waste_overflow.pop_at(index)
				break
			index += 1
	_refresh_waste()
	_refresh_carried()
	_save()
	return true

func _aim_tool(node: Node3D,center: Vector3,extent: Vector3) -> bool:
	if not is_instance_valid(node): return false
	var cam: Camera3D = game.play_camera
	var start := cam.global_position
	var finish := start-cam.global_basis.z*3.0
	var hit: Variant = AABB(center-extent,extent*2.0).intersects_segment(node.to_local(start),node.to_local(finish))
	if hit==null: return false
	var at := node.to_global(hit)
	if game.player.global_position.distance_to(at)>3.0: return false
	if _door_blocks_target(start,at,node): return false
	var ray := PhysicsRayQueryParameters3D.create(start,at,1|2)
	ray.exclude = [game.player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _aim_can() -> String:
	for color in paint_cans:
		var can: Node3D = paint_cans[color]
		if can.visible and _aim_tool(can,Vector3.ZERO,Vector3(.23,.19,.23)): return String(color)
	return ""

# Select the visible wall, then solve a grounded leaning pose below the aim.
func _broom_wall_pose() -> Dictionary:
	if not inside or not is_instance_valid(resting_broom): return {}
	var cam: Camera3D = game.play_camera
	var origin := cam.global_position
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(origin,origin-cam.global_basis.z*3.0,1|2|4|8|16|32)
	ray.exclude = [game.player.get_rid()]
	var hit := space.intersect_ray(ray)
	if hit.is_empty(): return {}
	var wall: Object = hit.collider
	if not wall.has_meta("home_paint_wall") and not wall.has_meta("broom_support_wall"): return {}
	var normal: Vector3 = hit.normal
	if absf(normal.y)>.12: return {}
	normal.y = 0.0
	normal = normal.normalized()
	var point: Vector3 = hit.position
	if _door_blocks_target(origin,point): return {}
	# Leave the exit doorway and its approach free.
	if is_instance_valid(guest_door) and AABB(Vector3(-.26,-.1,-.32),Vector3(1.72,2.5,.64)).has_point(guest_door.to_local(Vector3(point.x,ROOM.y+1.0,point.z))): return {}
	var base := Vector3(point.x,ROOM.y,point.z)+normal*.255
	if game.player.global_position.distance_to(base+Vector3.UP*.7)>3.0: return {}
	# Find the actual floor beneath the bristles.
	var down := PhysicsRayQueryParameters3D.create(base+Vector3.UP*.28,base-Vector3.UP*.15,2)
	var floor_hit := space.intersect_ray(down)
	if floor_hit.is_empty() or Vector3(floor_hit.normal).y<.8: return {}
	base.y = maxf(float(floor_hit.position.y),ROOM.y+.052)
	# Confirm that the top of the handle really has the same wall behind it.
	var support := base+Vector3.UP*1.38
	var support_ray := PhysicsRayQueryParameters3D.create(support,support-normal*.33,1)
	support_ray.exclude = [game.player.get_rid()]
	var top_hit := space.intersect_ray(support_ray)
	if top_hit.is_empty() or top_hit.collider!=wall: return {}
	var angle := atan2(normal.x,normal.z)
	var pose := Transform3D(Basis(Vector3.UP,angle)*Basis(Vector3.RIGHT,-.145),base)
	# Test the actual broom head and handle separately, leaving only a tiny
	# clearance at the wall. Reject furniture, the player and solid doors.
	for part in [
		[Vector3(0,.115,0),Vector3(.40,.20,.18)],
		[Vector3(0,.74,0),Vector3(.058,1.34,.058)]]:
		var shape := BoxShape3D.new()
		shape.size = part[1]
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 1|4|8|16|32
		query.transform = pose*Transform3D(Basis.IDENTITY,Vector3(part[0]))
		if not space.intersect_shape(query,1).is_empty(): return {}
	# Also reject visual-only cabinet doors at the broom's position.
	for entry in rental_storage_doors:
		var hinge: Node3D = entry.hinge
		if not is_instance_valid(hinge): continue
		var center: Vector3 = entry.center
		var size: Vector3 = entry.size
		var bounds := AABB(center-size*.5,size).grow(.09)
		for height in [.14,.45,.75,1.05,1.36]:
			if bounds.has_point(hinge.to_local(pose*Vector3(0,float(height),0))): return {}
	return {"position":base,"yaw":angle}

func _place_broom_at_wall() -> bool:
	var candidate := _broom_wall_pose()
	if candidate.is_empty():
		business._notify("Busca una pared libre y apunta hacia ella para apoyar la escoba.")
		return false
	var point: Vector3 = candidate.position
	var local := paint_station.to_local(point)
	resting_broom.position = local
	resting_broom.rotation = Vector3(-.145,float(candidate.yaw),0)
	state.broom_placement = {"position":[local.x,local.y,local.z],"yaw":float(candidate.yaw)}
	_stop_home_paint()
	business._notify("Escoba apoyada contra la pared.")
	return true

func _house_tool_action(at: Vector3) -> String:
	var tool := String(state.paint_tool)
	if not String(state.paint_carry).is_empty():
		if at.distance_to(ROOM+PAPER_POS)<2.5: return "[E] Dejar cubo de pintura"
		return ""
	if tool=="brush":
		if not _aim_can().is_empty(): return "[E] Embarrar brocha"
		if _aim_tool(resting_brush,Vector3.ZERO,Vector3(.38,.14,.28)): return "[E] Dejar brocha sobre el papel"
		return "Clic izquierdo: pintar · [X] Guardar brocha" if int(state.paint_charge)>0 else "Moja la brocha en un cubo de pintura · [X] Guardar"
	if tool=="broom":
		if not _broom_wall_pose().is_empty(): return "[E] Apoyar escoba en la pared"
		return "[E] Busca una pared libre · Clic izquierdo: barrer"
	if not _free_hands(): return ""
	if _aim_tool(resting_brush,Vector3.ZERO,Vector3(.27,.12,.24)): return "[E] Recoger brocha"
	if _aim_tool(resting_broom,Vector3(0,.72,0),Vector3(.23,.73,.13)): return "[E] Recoger escoba"
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
	elif String(state.paint_tool)=="broom": _place_broom_at_wall()
	elif action.contains("Dejar brocha"): _stop_home_paint()
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
		held_broom.position = Vector3(.42,-.62,-1.18)
		held_broom.rotation = Vector3(.95,0,0)
		_make_broom_model(held_broom)
	_refresh_tools()
	_save()

func _dip_home_brush(color: String) -> void:
	if String(state.paint_tool)!="brush" or not PAINT_COLORS.has(color): return
	var existing := int(state.paint_charge) if String(state.paint_active)==color else 0
	var amount := mini(BRUSH_LOAD-existing,int(state.paint_stock.get(color,0)))
	if amount<=0: return
	var before := int(state.paint_stock[color])
	var remaining := before-amount
	state.paint_stock[color] = remaining
	var emptied := ceili(float(before)/CAN_CAPACITY)-ceili(float(remaining)/CAN_CAPACITY)
	if emptied>0:
		if not state.has("empty_paint"): state.empty_paint = {}
		state.empty_paint[color] = int(state.empty_paint.get(color,0))+emptied
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

func has_home_tool() -> bool:
	return not String(state.get("paint_tool","")).is_empty()

# Manual emergency return: tools are domestic items and return to their
# actual resting place rather than being destroyed or dropped in the city.
func return_home_tool() -> bool:
	if not has_home_tool(): return false
	var tool := String(state.paint_tool)
	if tool=="broom" and inside:
		_place_broom_at_wall()
		return true
	_stop_home_paint()
	business._notify("Brocha devuelta al papel." if tool=="brush" else "Escoba devuelta a su última ubicación.")
	return true

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
	if not inside or String(state.paint_tool).is_empty() or business.modal_open() or not game.gameplay_input() or not game.primary_held(): return
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
