extends Node3D
# First playable local prototype. Static world, third-person movement.
const CITY_PATH = "res://city.glb"
const TouchControls = preload("res://mobile_controls.gd")
const GameMenu = preload("res://game_menu.gd")
var game_menu: GameMenu
var mobile_controls: TouchControls
var mobile_mode := false
const VehicleLights = preload("res://vehicle_lights.gd")
var road_headlight: SpotLight3D
const Shoe = preload("res://character_shoe.gd")
const CityBuilder = preload("res://city_builder.gd")
const CityWorld = preload("res://city_world.gd")
const CubaWorld = preload("res://cuba_world.gd")
const PilarEditor = preload("res://pilar_editor.gd")
const TaxiService = preload("res://taxi_service.gd")
const UrbanBuses = preload("res://urban_buses.gd")
const BusinessMission = preload("res://business_mission.gd")
const FirstStory = preload("res://albertico_story.gd")
const HomeGarage = preload("res://home_garage.gd")
const ArrivalStory = preload("res://arrival_story.gd")
var adaptation_mode := false
var deferred_vehicles_clock := 0.0
var deferred_vehicles_requested := false
var deferred_vehicles_done := false
var deferred_vehicles_ready: PackedScene
var home_exit_loading := false
var home_exit_layer: CanvasLayer
var perf_sample_clock := 0.0
var perf_samples: Dictionary = {}
var arrival_story: ArrivalStory
var garage: HomeGarage
const CarlosMission = preload("res://carlos_mission.gd")
var carlos_mission: CarlosMission
const YordiMission = preload("res://yordi_mission.gd")
var yordi_mission: YordiMission
const CityNavigation = preload("res://city_navigation.gd")
var city_navigation: CityNavigation
const StreetMarket = preload("res://street_market.gd")
var street_market: StreetMarket
const Backpack = preload("res://backpack.gd")
var backpack: Backpack
const CityIncidents = preload("res://city_incidents.gd")
var incidents: CityIncidents
const MontePedestrians = preload("res://monte_pedestrians.gd")
const MonteServices = preload("res://monte_services.gd")
var monte_pedestrians: MontePedestrians
var monte_services: MonteServices
var business: BusinessMission
var cargo_requested := false
var urban_buses: UrbanBuses
var taxis: TaxiService
var taxi_riding := false
var bus_riding := false
var bus_previous_first := false
var bus_reset_requested := false
var social_cooldown := 0.0
var chatting_with: Node3D
var taxi_previous_first := false
var taxi_reset_requested := false
var taxi_exit_retry := 0.0
var pilar_editor: PilarEditor
var context_requested := false
var cuba_world: CubaWorld
var first_person := false
var reticle: Label
var performance_label: Label
var diagnostics_panel: PanelContainer
var diagnostics_text: Label
var gps_label: Label
# 0: rendimiento, 1: equilibrado, 2: alto. Rendering remains GL Compatibility.
const GRAPHICS_NAMES := ["Bajo","Medio","Alto"]
# Intel UHD baseline: opt into expensive effects with F6.
var graphics_quality := 0
var low_graphics := true
var visual_environment: Environment
var visual_sun: DirectionalLight3D
var visual_sky: ProceduralSkyMaterial
var sky_minute := -100
var sky_indoor := false
var hud_time := 0.0
var fps_time := 0.0
var city_world: CityWorld
var native_city := true
var spawn_position := Vector3(-2.4,1.0,5.5)
var builder: CityBuilder
var play_camera: Camera3D
var building_mode := false
var player: CharacterBody3D
var pivot: Node3D
var arm: SpringArm3D
var avatar: Node3D
var yaw := 0.0
var pitch := -0.20
var status: Label
var controls_expanded := false
var map_credit: Label
var city_loaded := false
var van: CharacterBody3D
var van_visual: Node3D
var driver_door: Node3D
var door_closed := 0.0
var door_tween: Tween
var driving := false
var drive_speed := 0.0
var interact_requested := false
var reset_requested := false
var limb_arms: Array[Node3D] = []
var limb_legs: Array[Node3D] = []
var step_phase := 0.0
var avatar_idle_phase := 0.0
var avatar_stride_weight := 0.0
var avatar_sphere_mesh: SphereMesh
var player_shape: CollisionShape3D
var van_home := Transform3D.IDENTITY
var van_ground_initialized := false
const GROUND_LAYER = 2
const VAN_LAYER = 4
var exit_message := ""
var message_time := 0.0

func _web_map_error() -> void:
	# A missing map must never masquerade as a successful Havana demo.
	set_process(false)
	set_physics_process(false)
	set_process_input(false)
	set_process_unhandled_input(false)
	var layer := CanvasLayer.new()
	add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color("#14232c")
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	label.text = "MYCITY · LA HABANA\n\nNo se pudo cargar el mapa de Pilar-Atarés.\nLa exportación necesita pilar_atares_v2.osm.\nVuelve a exportar con MyCity Map Export activado."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",24)
	bg.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func _ready() -> void:
	adaptation_mode = bool(get_tree().get_meta("mycity_adaptation",false)) or OS.get_cmdline_user_args().has("--replay-home-arrival")
	var args := OS.get_cmdline_user_args()
	mobile_mode = OS.has_feature("android") or OS.has_feature("ios") or args.has("--touch-controls")
	if OS.has_feature("web"):
		var coarse = JavaScriptBridge.eval("window.matchMedia('(pointer: coarse)').matches",true)
		mobile_mode = mobile_mode or coarse==true
	if args.has("--low-graphics"): graphics_quality = 0
	elif args.has("--medium-graphics"): graphics_quality = 1
	elif args.has("--high-graphics"): graphics_quality = 2
	low_graphics = graphics_quality==0
	_setup_visual_environment()
	native_city = not args.has("--legacy-city")
	if native_city and not args.has("--classic-city") and (OS.has_feature("web") or FileAccess.file_exists("res://pilar_atares_v2.osm") or FileAccess.file_exists("res://pilar_atares.osm")):
		var candidate := CubaWorld.new()
		var map_started := Time.get_ticks_msec()
		if adaptation_mode: candidate.inventory_path = "user://mycity_adaptation_inventory_v1.json"
		var warmed: Dictionary = get_tree().get_meta("mycity_warmed_map",{})
		if get_tree().has_meta("mycity_warmed_map"): get_tree().remove_meta("mycity_warmed_map")
		var loaded := false
		if adaptation_mode and not warmed.is_empty():
			candidate.geography = warmed.geography
			candidate.street_geometry = warmed.streets
			candidate.market_topology = warmed.market
			candidate.prebuilt_topology = true
			candidate.prebuilt_street_surfaces = warmed.get("surfaces",{})
			if warmed.get("textures")!=null: candidate.havana_textures = warmed.textures
			loaded = true
		else:
			loaded = candidate.load_map()
		if loaded:
			print("MyCity carga (ms): mapa OSM=",Time.get_ticks_msec()-map_started)
			cuba_world = candidate
		else:
			candidate.free()
			push_warning("Mapa OSM no disponible o inválido.")
	if (OS.has_feature("web") or adaptation_mode) and cuba_world==null:
		_web_map_error()
		return
	builder = CityBuilder.new()
	builder.native_city = native_city
	if native_city:
		builder.save_path = "user://pilar_atares_buildings.json" if cuba_world != null else "user://mycity_v2_buildings.json"
	add_child(builder)
	if native_city:
		city_world = cuba_world if cuba_world != null else CityWorld.new()
		add_child(city_world)
		if cuba_world!=null: cuba_world.havana_textures.set_quality(graphics_quality)
		city_world.setup(builder)
		spawn_position = cuba_world.home_spawn if cuba_world != null else CityWorld.HOME_OUT
		var vehicles_started := Time.get_ticks_msec()
		if adaptation_mode and cuba_world!=null:
			# Empty hidden reference body, with no imported geometry.
			van = _new_van_body(Vector3(0,-100,0))
			van.hide()
			van.collision_layer = 0
			van.collision_mask = 0
			van_ground_initialized = true
		else:
			_restore_original_vehicles()
			if van == null:
				_make_demo_van()
				push_warning("MyCity: van original no disponible; exporta city.glb desde Blender.")
			van.global_position = cuba_world.van_spawn if cuba_world != null else CityWorld.VAN_PARK + Vector3.UP * .055
			if cuba_world != null:
				van.rotation.y = cuba_world.van_angle
		print("MyCity carga (ms): vehículos originales en inicio=",Time.get_ticks_msec()-vehicles_started)
		van_home = van.global_transform
		city_loaded = true
	elif ResourceLoader.exists(CITY_PATH):
		var packed := load(CITY_PATH) as PackedScene
		if packed != null:
			var city := packed.instantiate()
			add_child(city)
			_install_city_van(city)
			var terrain_count := _fix_terrain_materials(city)
			print("MyCity: terrain meshes recolored = ", terrain_count)
			if terrain_count == 0:
				push_warning("MyCity: terrain mesh not detected in city.glb.")
			_add_world_collision(city)
			city_loaded = true
	if not city_loaded:
		_make_demo_floor()
		_make_demo_van()
	_make_player()
	_make_hud()
	if cuba_world != null:
		pilar_editor = PilarEditor.new()
		add_child(pilar_editor)
		pilar_editor.setup(cuba_world)
		taxis = TaxiService.new()
		add_child(taxis)
		var services_started := Time.get_ticks_msec()
		taxis.setup(cuba_world.geography,cuba_world.street_geometry,cuba_world.home_spawn,van.global_position)
		urban_buses = UrbanBuses.new()
		add_child(urban_buses)
		var avoid: Array = [van.global_position,player.global_position]
		for taxi in taxis.taxis:
			var body: CharacterBody3D = taxi.body
			avoid.append(body.global_position)
		urban_buses.setup(cuba_world.geography,cuba_world.street_geometry,cuba_world.home_spawn,avoid,cuba_world)
		print("MyCity carga (ms): rutas de taxis y guaguas=",Time.get_ticks_msec()-services_started)
		services_started = Time.get_ticks_msec()
		business = BusinessMission.new()
		add_child(business)
		business.adaptation_mode = adaptation_mode
		business.setup(cuba_world,taxis,player,van,play_camera)
		business.phone_position = func() -> Vector3:
			if driving: return van.global_position
			if garage!=null and garage.inside and not cuba_world.garage_home_site.is_empty(): return cuba_world.garage_home_site.door
			if carlos_mission!=null and carlos_mission.inside and not carlos_mission.customer.is_empty(): return carlos_mission.customer.p
			return player.global_position
		business.phone_destination = func() -> Dictionary:
			if garage==null or not garage.waypoint_active: return {}
			var at: Vector3 = business.phone_position.call()
			var goal: Vector3 = garage.waypoint_point
			return {"label":garage.waypoint_label,"distance":Vector2(at.x,at.z).distance_to(Vector2(goal.x,goal.z))}
		business.life.attach_avatar(limb_arms)
		for bus in urban_buses.buses:
			var body: CharacterBody3D = bus.body
			avoid.append(body.global_position)
		monte_services = MonteServices.new()
		if mobile_mode: monte_services.civilian_limit = 14
		add_child(monte_services)
		var traffic_anchor: Vector3 = cuba_world.home_spawn
		if adaptation_mode and not cuba_world.garage_home_site.is_empty():
			traffic_anchor = cuba_world.garage_home_site.get("road",cuba_world.garage_home_site.door)
		monte_services.setup(cuba_world,traffic_anchor,avoid,player,play_camera,urban_buses.stops)
		monte_services.prioritize_home_traffic = adaptation_mode
		monte_pedestrians = MontePedestrians.new()
		add_child(monte_pedestrians)
		monte_pedestrians.setup(cuba_world,urban_buses,business.life)
		urban_buses.stop_priority.connect(taxis.yield_to_bus)
		urban_buses.stop_priority.connect(monte_pedestrians.yield_to_bus)
		urban_buses.stop_priority.connect(_bus_priority_notice)
		garage = HomeGarage.new()
		add_child(garage)
		garage.setup(self)
		business.garage_market = garage.open_phone_market
		street_market = StreetMarket.new()
		add_child(street_market)
		street_market.setup(self)
		business.street_inventory = street_market.open_inventory
		backpack = Backpack.new()
		add_child(backpack)
		backpack.setup(self)
		business.backpack_inventory = backpack.open_inventory
		carlos_mission = CarlosMission.new()
		add_child(carlos_mission)
		carlos_mission.setup(self)
		business.carlos_call = carlos_mission.open_call
		business.carlos_objective = carlos_mission.objective
		yordi_mission = YordiMission.new()
		add_child(yordi_mission)
		yordi_mission.setup(self)
		business.yordi_call = yordi_mission.open_call
		business.yordi_objective = yordi_mission.objective
		var first_story := FirstStory.new()
		business.add_child(first_story)
		business.first_story = first_story
		first_story.setup(self)
		city_navigation = CityNavigation.new()
		add_child(city_navigation)
		city_navigation.setup(self)
		business.city_map = _open_city_map
		incidents = CityIncidents.new()
		add_child(incidents)
		incidents.setup(self)
		print("MyCity carga (ms): negocios, interiores y sistemas=",Time.get_ticks_msec()-services_started)
		first_person = true
		_face_cuba_home()
		_apply_camera_mode()
	_apply_performance_mode()
	if mobile_mode:
		_enable_mobile_controls()
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if cuba_world!=null:
		game_menu = GameMenu.new()
		add_child(game_menu)
		game_menu.setup(self)
		if adaptation_mode:
			van.hide()
			van.collision_layer = 0
			van.collision_mask = 0
			van_ground_initialized = true
			# Register only when the real model has loaded.
			arrival_story = ArrivalStory.new()
			add_child(arrival_story)
			arrival_story.setup(self)
			if get_tree().has_meta("mycity_city_load_started"):
				print("MyCity carga (ms): inicialización ciudad y llegada=",Time.get_ticks_msec()-int(get_tree().get_meta("mycity_city_load_started")))
				get_tree().remove_meta("mycity_city_load_started")
		else:
			game_menu.open_menu(true)

func open_game_menu() -> void:
	if is_instance_valid(game_menu) and not touch_blocked(): game_menu.open_menu(false)

func recover_checkpoint() -> void:
	if taxi_riding: taxi_reset_requested = true
	elif bus_riding: bus_reset_requested = true
	else: reset_requested = true

func _enable_mobile_controls() -> void:
	if is_instance_valid(mobile_controls): return
	mobile_mode = true
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	mobile_controls = TouchControls.new()
	layer.add_child(mobile_controls)
	mobile_controls.setup(self)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func touch_blocked() -> bool:
	if arrival_story!=null and arrival_story.cinematic(): return true
	return (is_instance_valid(game_menu) and game_menu.menu_open) or building_mode or (business!=null and (business.modal_open() or business.story_active)) or (taxis!=null and taxis.dialog.visible) or (city_navigation!=null and city_navigation.active) or (street_market!=null and not street_market.active.is_empty())

func gameplay_input() -> bool:
	if home_exit_loading: return false
	if mobile_mode: return not touch_blocked()
	return Input.mouse_mode==Input.MOUSE_MODE_CAPTURED

func control_pressed(key: Key) -> bool:
	return Input.is_physical_key_pressed(key) or (is_instance_valid(mobile_controls) and mobile_controls.held(key))

func primary_held() -> bool:
	if mobile_mode: return is_instance_valid(mobile_controls) and mobile_controls.use_held
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)

func touch_action(key: Key) -> void:
	if home_exit_loading: return
	if arrival_story!=null and arrival_story.active():
		if key==KEY_E: arrival_story.interact()
		return
	if touch_blocked(): return
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	if key==KEY_M:
		_open_city_map()
	else:
		_unhandled_input(event)

func touch_look(relative: Vector2) -> void:
	if home_exit_loading: return
	if arrival_story!=null and arrival_story.active():
		arrival_story.handle_look(relative)
		return
	if touch_blocked() or pivot==null: return
	if is_instance_valid(garage) and garage.dining_seated:
		garage.dining_look(relative,.005)
		return
	yaw -= relative.x*.005
	var limit := -1.05
	var top := .35
	if driving or taxi_riding or bus_riding or (garage!=null and garage.riding):
		limit = -.95
		top = .30
	elif (garage!=null and garage.inside) or (carlos_mission!=null and carlos_mission.inside) or (yordi_mission!=null and yordi_mission.robbery_active()):
		limit = -1.48
	pitch = clampf(pitch-relative.y*.005,limit,top)
	pivot.rotation = Vector3(pitch,yaw,0)

func touch_use() -> void:
	if not touch_blocked() and yordi_mission!=null: yordi_mission.throw_stone()

# Recognize terrain even when GLB import renames its mesh node or wraps it
# in another Node3D. Never recolor roads, buildings or industrial platforms.
func _is_terrain_mesh(m: MeshInstance3D) -> bool:
	if m.mesh == null:
		return false
	var bounds := m.get_aabb()
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for i in range(8):
		var p := m.to_global(bounds.get_endpoint(i))
		low = low.min(p)
		high = high.max(p)
	var size := high - low
	if size.x >= 75.0 and size.z >= 80.0 and size.y < 25.0:
		return true
	var current: Node = m
	for i in range(3):
		if current == null:
			break
		var key := _normalized_name(String(current.name))
		if key.begins_with("terreno") or key.begins_with("relieve"):
			if size.x >= 30.0 and size.z >= 30.0:
				return true
		current = current.get_parent()
	for i in range(m.mesh.get_surface_count()):
		var material := m.mesh.surface_get_material(i)
		if material != null and String(material.resource_name).to_lower().contains("meadow"):
			return true
	return false

func _fix_terrain_materials(node: Node) -> int:
	var count := 0
	if node is MeshInstance3D:
		var m := node as MeshInstance3D
		if _is_terrain_mesh(m):
			# A global override takes precedence over imported surface materials,
			# vertex colors and any previous per-surface override.
			var shader := Shader.new()
			shader.code = """shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_disabled;
varying vec3 world_pos;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	float n = sin(world_pos.x * 0.31 + world_pos.z * 0.19) * 0.5 + cos(world_pos.z * 0.43 - world_pos.x * 0.11) * 0.5;
	float blend = smoothstep(-0.8, 0.8, n);
	ALBEDO = mix(vec3(0.085, 0.22, 0.038), vec3(0.19, 0.39, 0.075), blend);
	ROUGHNESS = 1.0;
}"""
			var grass := ShaderMaterial.new()
			grass.shader = shader
			m.material_override = grass
			m.material_overlay = null
			count += 1
			print("MyCity terrain fixed: ", m.get_path(), " | ", m.get_aabb().size)
	for child in node.get_children():
		count += _fix_terrain_materials(child)
	return count

func _add_world_collision(node: Node) -> void:
	# Only terrain and coarse building/road geometry are physical in this prototype.
	# Other imported detail remains visible without expensive collision shapes.
	if node is MeshInstance3D:
		var m := node as MeshInstance3D
		var name_key := String(m.name).to_lower()
		var solid := false
		for prefix in ["terreno", "calle", "boulevard", "casa", "industrial", "mobiliario", "arco"]:
			if name_key.begins_with(prefix):
				solid = true
				break
		for detail in ["joint", "paint", "yellow", "cristal", "hojas", "troncos", "agua", "sen al", "letter", "letra", "ventana", "glass", "césped", "cesped"]:
			if name_key.contains(detail):
				solid = false
		var terrain_mesh := _is_terrain_mesh(m)
		if (solid or terrain_mesh) and m.mesh != null and m.mesh.get_surface_count() > 0:
			m.create_trimesh_collision()
			var key := _normalized_name(name_key)
			var is_ground := terrain_mesh or key.begins_with("terreno") or key.begins_with("calleprincipalasphalt") or key.begins_with("calleprincipalconcrete") or key.begins_with("calleprincipalcurb") or key.begins_with("boulevardcalleprincipalasphalt") or key.begins_with("boulevardcalleprincipalconcrete") or key.begins_with("boulevardcalleprincipalcurb") or key.begins_with("boulevardboulevardasphalt") or key.begins_with("boulevardboulevardconcrete") or key.begins_with("boulevardboulevardcurb")
			if is_ground:
				for child in m.get_children():
					if child is StaticBody3D:
						(child as StaticBody3D).collision_layer = GROUND_LAYER
	for child in node.get_children():
		_add_world_collision(child)

func _make_demo_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = GROUND_LAYER
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(160, 0.4, 220)
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.60, 0.24)
	mesh.material_override = mat
	floor_body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	floor_body.add_child(col)
	add_child(floor_body)
	floor_body.position.y = -0.2

func _make_player() -> void:
	player = CharacterBody3D.new()
	player.name = "Player"
	player.collision_mask = 1 | GROUND_LAYER | VAN_LAYER | 8
	player.floor_snap_length = 0.30
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.6
	col.shape = capsule
	player.add_child(col)
	player_shape = col
	avatar = Node3D.new()
	player.add_child(avatar)
	_make_cartoon_avatar()
	pivot = Node3D.new()
	pivot.position.y = 0.65
	player.add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 4.5
	arm.margin = 0.15
	arm.collision_mask = 1 | GROUND_LAYER | 8
	pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.far = 320.0 if cuba_world != null else 800.0
	arm.add_child(cam)
	add_child(player)
	player.position = spawn_position
	arm.add_excluded_object(player.get_rid())
	if van != null:
		arm.add_excluded_object(van.get_rid())
	cam.current = true
	play_camera = cam
	pivot.rotation = Vector3(pitch, yaw, 0)

func _make_hud() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(18, 16)
	status.add_theme_font_size_override("font_size", 14)
	var status_style := StyleBoxFlat.new()
	status_style.bg_color = Color("#101b28df")
	status_style.set_corner_radius_all(8)
	status_style.content_margin_left = 10.0
	status_style.content_margin_right = 10.0
	status_style.content_margin_top = 7.0
	status_style.content_margin_bottom = 7.0
	status.add_theme_stylebox_override("normal",status_style)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.add_theme_color_override("font_shadow_color", Color.BLACK)
	status.add_theme_constant_override("shadow_offset_x", 2)
	status.add_theme_constant_override("shadow_offset_y", 2)
	canvas.add_child(status)
	reticle = Label.new()
	reticle.text = "·"
	reticle.add_theme_font_size_override("font_size",38)
	reticle.add_theme_color_override("font_shadow_color",Color.BLACK)
	reticle.add_theme_constant_override("shadow_offset_x",1)
	reticle.add_theme_constant_override("shadow_offset_y",1)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(reticle)
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.offset_left = -16
	reticle.offset_right = 16
	reticle.offset_top = -24
	reticle.offset_bottom = 24
	reticle.hide()
	performance_label = Label.new()
	performance_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(performance_label)
	performance_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	performance_label.offset_left = -240
	performance_label.offset_right = -12
	performance_label.offset_top = 8
	performance_label.offset_bottom = 36
	performance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	performance_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	performance_label.add_theme_constant_override("shadow_offset_x",2)
	performance_label.add_theme_constant_override("shadow_offset_y",2)
	performance_label.visible = false
	diagnostics_panel = PanelContainer.new()
	canvas.add_child(diagnostics_panel)
	diagnostics_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	diagnostics_panel.offset_left = -355
	diagnostics_panel.offset_right = -12
	diagnostics_panel.offset_top = 42
	var debug_style := StyleBoxFlat.new()
	debug_style.bg_color = Color(0.035,0.065,0.085,.92)
	debug_style.set_corner_radius_all(8)
	debug_style.content_margin_left = 12
	debug_style.content_margin_right = 12
	debug_style.content_margin_top = 9
	debug_style.content_margin_bottom = 9
	diagnostics_panel.add_theme_stylebox_override("panel",debug_style)
	diagnostics_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diagnostics_text = Label.new()
	diagnostics_text.add_theme_font_size_override("font_size",13)
	diagnostics_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	diagnostics_panel.add_child(diagnostics_text)
	diagnostics_panel.hide()
	gps_label = Label.new()
	gps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(gps_label)
	gps_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	gps_label.offset_left = -330
	gps_label.offset_right = -12
	gps_label.offset_top = -58
	gps_label.offset_bottom = -12
	gps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gps_label.add_theme_font_size_override("font_size",16)
	gps_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	gps_label.add_theme_constant_override("shadow_offset_x",2)
	gps_label.add_theme_constant_override("shadow_offset_y",2)
	gps_label.visible = false
	map_credit = Label.new()
	map_credit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(map_credit)
	map_credit.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	map_credit.offset_left = -400
	map_credit.offset_right = -12
	map_credit.offset_top = -24
	map_credit.offset_bottom = -6
	map_credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	map_credit.add_theme_font_size_override("font_size",11)
	map_credit.add_theme_color_override("font_shadow_color",Color.BLACK)
	map_credit.add_theme_constant_override("shadow_offset_x",1)
	map_credit.add_theme_constant_override("shadow_offset_y",1)
	map_credit.text = "© OpenStreetMap contributors · ODbL | openstreetmap.org/copyright"
	map_credit.visible = cuba_world!=null
	gps_label.offset_top = -72
	gps_label.offset_bottom = -27
	_update_hud()

func _setup_visual_environment() -> void:
	visual_environment = Environment.new()
	visual_environment.background_mode = Environment.BG_COLOR
	visual_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	visual_environment.ambient_light_sky_contribution = 0.0
	visual_sky = ProceduralSkyMaterial.new()
	visual_sky.sun_angle_max = 16.0
	var sky := Sky.new()
	sky.sky_material = visual_sky
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	visual_environment.sky = sky
	var world := WorldEnvironment.new()
	world.environment = visual_environment
	add_child(world)
	visual_sun = DirectionalLight3D.new()
	visual_sun.directional_shadow_blend_splits = true
	visual_sun.shadow_enabled = false
	add_child(visual_sun)
	_update_visual_lighting(true)

# Match the existing simulation clock; lighting never changes its speed.
# Rooms at y=110 have their own lights and must not inherit the outdoor night.
func _update_player_draw_distance() -> void:
	if not is_instance_valid(play_camera): return
	# The rental interior is at y=110 and is only 14 x 12 m. Avoid rendering
	# distant city geometry through its closed walls. Do not change world physics.
	var in_rental: bool = is_instance_valid(garage) and garage.inside and is_instance_valid(player) and absf(player.global_position.y-110.0)<8.0
	var distance := 38.0 if in_rental else (320.0 if low_graphics else (550.0 if graphics_quality==1 else 720.0))
	if not is_equal_approx(play_camera.far,distance): play_camera.far = distance

func _update_visual_lighting(force: bool = false) -> void:
	if visual_environment==null or visual_sun==null: return
	_update_player_draw_distance()
	var minute := 480.0
	if business!=null and business.life!=null:
		minute = fposmod(float(business.life.state.get("minutes",480.0)),1440.0)
	var indoors := is_instance_valid(player) and player.global_position.y>70.0
	if garage!=null and garage.inside: indoors = true
	if carlos_mission!=null and carlos_mission.inside: indoors = true
	var rental_home: bool = adaptation_mode and is_instance_valid(garage) and garage.inside and is_instance_valid(player) and player.global_position.y>70.0
	if not rental_home and is_instance_valid(garage) and garage.home_shadow_active: garage.update_home_lighting(0.0,false)
	# Update the sky in small time buckets instead of rebuilding its radiance every frame.
	var bucket := floori(minute/5.0)
	if not force and not rental_home and bucket==sky_minute and indoors==sky_indoor: return
	sky_minute = bucket
	sky_indoor = indoors
	var day := smoothstep(360.0,480.0,minute)*(1.0-smoothstep(1020.0,1140.0,minute))
	var dusk := smoothstep(330.0,390.0,minute)*(1.0-smoothstep(410.0,510.0,minute))
	dusk = maxf(dusk,smoothstep(990.0,1080.0,minute)*(1.0-smoothstep(1110.0,1170.0,minute)))
	var horizon := Color("#252d48").lerp(Color("#b9d9ef"),day).lerp(Color("#e5a273"),dusk*.66)
	var zenith := Color("#10182e").lerp(Color("#579bd5"),day).lerp(Color("#756c96"),dusk*.32)
	visual_environment.background_mode = Environment.BG_COLOR if low_graphics or indoors else Environment.BG_SKY
	visual_environment.background_color = horizon
	if not low_graphics and not indoors:
		visual_sky.sky_top_color = zenith
		visual_sky.sky_horizon_color = horizon
		visual_sky.ground_horizon_color = horizon
		visual_sky.ground_bottom_color = Color("#353a43").lerp(Color("#96968d"),day)
	visual_environment.ambient_light_color = Color("#93a6d0").lerp(Color("#d5e5fa"),day)
	visual_environment.ambient_light_energy = lerpf(.37,.63,day)
	visual_sun.light_color = Color("#fff1d9").lerp(Color("#ffc091"),dusk*.8)
	var arc := clampf((minute-360.0)/780.0,0.0,1.0)
	visual_sun.rotation_degrees = Vector3(-maxf(9.0,sin(arc*PI)*67.0),lerpf(-105.0,105.0,arc),0.0)
	visual_sun.light_energy = day*1.15+dusk*.16
	visual_sun.visible = not indoors and visual_sun.light_energy>.025
	visual_sun.shadow_enabled = not low_graphics and not indoors and day>.22
	if indoors:
		visual_environment.ambient_light_color = Color("#e8e2d5")
		visual_environment.ambient_light_energy = .70
		if rental_home:
			visual_environment.ambient_light_color = Color("#c5d2dd").lerp(Color("#e9e3d5"),day)
			visual_environment.ambient_light_energy = garage.update_home_lighting(day,true)
	visual_environment.fog_enabled = graphics_quality==2 and not indoors
	visual_environment.fog_light_color = horizon
	visual_environment.fog_density = lerpf(.0017,.0011,day)

func _apply_performance_mode() -> void:
	graphics_quality = clampi(graphics_quality,0,2)
	low_graphics = graphics_quality==0
	var window := get_window()
	# Quality controls shadows and scene detail, never the output resolution.
	# Canvas-items stretch keeps both HUD text and 3D at the window's native pixels.
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	window.content_scale_size = Vector2i(1280,720)
	window.scaling_3d_scale = 1.0
	_update_player_draw_distance()
	visual_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if graphics_quality==2 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	visual_sun.directional_shadow_max_distance = 105.0 if graphics_quality==2 else 55.0
	if cuba_world!=null: cuba_world.set_graphics_quality(graphics_quality)
	if pilar_editor != null:
		pilar_editor.camera.far = 1000.0 if low_graphics else 1800.0
	_update_visual_lighting(true)

func _refresh_diagnostics() -> void:
	if diagnostics_text==null or cuba_world==null: return
	var lines: PackedStringArray = ["MYCITY · DIAGNÓSTICO  |  F8"]
	lines.append("%d FPS · %.1f ms · RAM %.0f MB" % [Engine.get_frames_per_second(),1000.0/maxf(1.0,Engine.get_frames_per_second()),Performance.get_monitor(Performance.MEMORY_STATIC)/1048576.0])
	lines.append("Nodos %d · Draw calls %d" % [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))])
	if monte_pedestrians!=null:
		lines.append("Peatones %d · red %s (%d)" % [monte_pedestrians.walkers.size(),"lista" if monte_pedestrians.initialized else "cargando",monte_pedestrians.graph.get_point_count()])
	if monte_services!=null:
		var stopped := 0
		var detours := 0
		var nearest: Dictionary = {}
		var best := INF
		for car in monte_services.vehicles:
			if float(car.get("stalled",0.0))>1.0: stopped += 1
			if not car.get("detour",[]).is_empty(): detours += 1
			var body: Node3D = car.body
			if not is_instance_valid(body): continue
			var distance := body.global_position.distance_squared_to(play_camera.global_position)
			if distance<best:
				best = distance
				nearest = car
		lines.append("Tráfico %d · bloqueados %d · rodeos %d" % [monte_services.vehicles.size(),stopped,detours])
		if not nearest.is_empty():
			lines.append("Cercano: %.1f km/h · espera %.1fs" % [float(nearest.get("speed",0.0))*3.6,float(nearest.get("stalled",0.0))])
	if incidents!=null:
		lines.append("Heridos %d · %s / %s" % [incidents.injured.size(),String(incidents.scene.get("kind","sin incidente")),String(incidents.scene.get("phase",""))])
		if not incidents.injured.is_empty():
			var victim: Dictionary = incidents.injured[0]
			lines.append("Rescate %.0fs · ayuda %s" % [float(victim.time),"asignada" if victim.has("first_aid") else "pendiente"])
			var message := String(victim.get("rescue_status",""))
			if not message.is_empty(): lines.append(message.left(45))
	if business!=null and business.life!=null:
		for id in business.life.state.cafes:
			var cafe: Dictionary = business.life.state.cafes[id]
			lines.append("%s · %d CUP · deuda %d" % [String(id),int(cafe.cash),int(cafe.get("supplier_debt",0))])
			lines.append(" H%d Q%d T%d R%d P%d" % [int(cafe.get("harina",0)),int(cafe.get("queso",0)),int(cafe.get("tomate",0)),int(cafe.get("refresco",0)),int(cafe.get("perrito",0))])
	diagnostics_text.text = "\n".join(lines)

func _update_vehicle_lights() -> void:
	if business==null or business.life==null: return
	VehicleLights.update_time(get_tree(),float(business.life.state.get("minutes",480.0)))
	var body: Node3D
	if driving and is_instance_valid(van):
		body = van
	elif garage!=null and garage.riding:
		body = garage._ride_body()
	elif (taxi_riding or bus_riding) and is_instance_valid(pivot):
		body = pivot.get_parent() as Node3D
	if not VehicleLights.night or not is_instance_valid(body) or not body.has_meta("night_lamp_front"):
		if is_instance_valid(road_headlight): road_headlight.hide()
		return
	if not is_instance_valid(road_headlight):
		road_headlight = SpotLight3D.new()
		add_child(road_headlight)
		road_headlight.light_color = Color("#fff0d6")
		road_headlight.light_energy = 1.8
		road_headlight.spot_range = 22.0
		road_headlight.spot_angle = 37.0
		road_headlight.spot_attenuation = 1.4
		road_headlight.shadow_enabled = false
	var local_front: Vector3 = body.get_meta("night_lamp_front")
	var at := body.to_global(local_front+Vector3(0,0,.10))
	road_headlight.global_position = at
	road_headlight.look_at(at+body.global_basis.z*10.0-Vector3.UP*1.5,Vector3.UP)
	road_headlight.show()

var mission_tracker_clock := 0.0

func begin_home_exit_loading() -> void:
	if home_exit_loading or not adaptation_mode: return
	home_exit_loading = true
	interact_requested = false
	context_requested = false
	cargo_requested = false
	reset_requested = false
	player.velocity = Vector3.ZERO
	home_exit_layer = CanvasLayer.new()
	home_exit_layer.layer = 120
	add_child(home_exit_layer)
	var cover := ColorRect.new()
	home_exit_layer.add_child(cover)
	cover.color = Color("#111419")
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var label := Label.new()
	cover.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.text = "LA HABANA\nPreparando la ciudad…"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size",25)
	_finish_home_exit_loading.call_deferred()

func ambient_city_suspended() -> bool:
	return adaptation_mode and is_instance_valid(garage) and garage.inside and is_instance_valid(player) and player.global_position.y>70.0 and not home_exit_loading and (arrival_story==null or not arrival_story.active())

func _record_city_cost(key: String,started: int) -> void:
	var ms := float(Time.get_ticks_usec()-started)/1000.0
	perf_samples[key] = maxf(float(perf_samples.get(key,0.0)),ms)

func _tick_outdoor_free_play(delta: float) -> void:
	if ambient_city_suspended(): return
	var started := Time.get_ticks_usec()
	if city_world!=null: city_world.tick(delta)
	_record_city_cost("city",started)
	started = Time.get_ticks_usec()
	if urban_buses!=null: urban_buses.tick(delta)
	_record_city_cost("buses",started)
	started = Time.get_ticks_usec()
	if taxis!=null: taxis.tick(delta,cuba_world.cuba_clock)
	_record_city_cost("taxis",started)
	started = Time.get_ticks_usec()
	if monte_services!=null: monte_services.tick(delta)
	_record_city_cost("traffic",started)
	started = Time.get_ticks_usec()
	if monte_pedestrians!=null: monte_pedestrians.tick(delta)
	_record_city_cost("pedestrians",started)

func _finish_home_exit_loading() -> void:
	var started := Time.get_ticks_msec()
	# Render the outdoor view behind the cover to warm visibility and materials.
	_update_visual_lighting(true)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	if not is_inside_tree(): return
	if cuba_world!=null: await cuba_world.prepare_exit_infrastructure()
	# The cover lasts only for real infrastructure preparation and a rendered
	# exterior frame. There is no minimum artificial loading duration.
	if not is_inside_tree(): return
	await RenderingServer.frame_post_draw
	if not is_inside_tree(): return
	if is_instance_valid(home_exit_layer): home_exit_layer.queue_free()
	home_exit_layer = null
	home_exit_loading = false
	player.velocity = Vector3.ZERO
	print("MyCity: transición exterior (ms)=",Time.get_ticks_msec()-started)

func _process(delta: float) -> void:
	if adaptation_mode and not deferred_vehicles_done and not ambient_city_suspended():
		_tick_deferred_vehicles(delta)
	perf_sample_clock += delta
	if perf_sample_clock>=5.0:
		perf_sample_clock = 0.0
		if Engine.get_frames_per_second()<30:
			print("MyCity PERF: fps=",Engine.get_frames_per_second()," interior=",ambient_city_suspended()," draw calls=",Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)," max ms=",perf_samples)
		perf_samples.clear()
	if is_instance_valid(mobile_controls): mobile_controls.sync()
	if arrival_story!=null and arrival_story.active():
		_update_vehicle_lights()
		fps_time += delta
		if fps_time>=.5:
			fps_time = 0.0
			_update_visual_lighting()
		return
	_update_vehicle_lights()
	mission_tracker_clock += delta
	if mission_tracker_clock>=.15:
		mission_tracker_clock = 0.0
		if business!=null:
			business.refresh_mission_tracker(building_mode,city_navigation!=null and city_navigation.active,diagnostics_panel!=null and diagnostics_panel.visible)
	fps_time += delta
	if fps_time>=.5:
		fps_time = 0.0
		_update_visual_lighting()
		if diagnostics_panel!=null and diagnostics_panel.visible: _refresh_diagnostics()
		if performance_label != null and cuba_world != null and performance_label.visible:
			performance_label.text = "%d FPS | %s | F6" % [Engine.get_frames_per_second(),GRAPHICS_NAMES[graphics_quality]]
			if gps_label!=null and player!=null:
				var at := van.global_position if driving and van!=null else player.global_position
				var title := "Vehículo" if driving or taxi_riding else "Jugador"
				if pilar_editor!=null and pilar_editor.active:
					at = pilar_editor.gps_cursor
					title = "Cursor"
				gps_label.text = "%s · WGS84\n%s | F9 copiar" % [title,cuba_world.geography.coordinate_text(at)]

func _apply_camera_mode() -> void:
	if player == null or arm == null:
		return
	if garage!=null and garage.riding:
		arm.spring_length = 4.2
		avatar.hide()
	elif driving:
		arm.spring_length = 7.5
		avatar.hide()
	else:
		avatar.visible = not first_person
		arm.spring_length = 0.0 if first_person else (2.15 if city_world != null and (city_world.inside_home or (city_world.bakery != null and city_world.bakery.inside) or (cuba_world != null and cuba_world.current_room>=0)) else 4.5)
		pivot.position.y = .45 if garage!=null and (garage.dining_seated or garage.bath_mode=="sit") else .65
	if garage!=null and garage.inside and not first_person: arm.spring_length = 2.0
	_update_player_draw_distance()
	if reticle != null:
		reticle.visible = first_person and not driving and not building_mode and not (garage!=null and garage.riding)

func _open_city_map() -> void:
	if city_navigation==null or building_mode: return
	if business!=null and business.modal_open(): business.close()
	city_navigation.open()

func _input(event: InputEvent) -> void:
	if home_exit_loading:
		get_viewport().set_input_as_handled()
		return
	# In free play the home portal must not depend on mouse capture or legacy mission input.
	if adaptation_mode and player!=null and garage!=null and not driving and not taxi_riding and not bus_riding and not garage.riding and not touch_blocked() and (arrival_story==null or not arrival_story.active()) and event is InputEventKey and event.pressed and not event.echo and (event.keycode==KEY_E or event.physical_keycode==KEY_E):
		if garage.rental_entry_near(player.global_position) or (garage.inside and garage.action_text(player.global_position).begins_with("[E]")):
			garage.interact(player.global_position)
			interact_requested = false
			_update_hud()
			get_viewport().set_input_as_handled()
			return
	if arrival_story!=null and arrival_story.active() and event is InputEventKey:
		if event.pressed and not event.echo and (event.keycode==KEY_E or event.physical_keycode==KEY_E): arrival_story.interact()
		get_viewport().set_input_as_handled()
		return
	if player!=null and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		if not mobile_mode and event is InputEventScreenTouch and event.pressed: _enable_mobile_controls()
		if is_instance_valid(mobile_controls) and mobile_controls.handle_touch(event):
			get_viewport().set_input_as_handled()
			return
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode==KEY_F10 and is_instance_valid(game_menu) and not touch_blocked():
		open_game_menu()
		get_viewport().set_input_as_handled()
		return
	if event.keycode==KEY_F11:
		var window := get_window()
		window.mode = Window.MODE_WINDOWED if window.mode in [Window.MODE_FULLSCREEN,Window.MODE_EXCLUSIVE_FULLSCREEN] else Window.MODE_FULLSCREEN
		get_viewport().set_input_as_handled()
		return
	if city_navigation!=null and city_navigation.active:
		if event.keycode==KEY_ESCAPE or (event.keycode==KEY_M and not city_navigation.query.has_focus()):
			city_navigation.close()
			get_viewport().set_input_as_handled()
		return
	if event.keycode==KEY_M and city_navigation!=null and not building_mode and not (pilar_editor!=null and pilar_editor.active) and not (taxis!=null and taxis.dialog.visible) and not (business!=null and business.modal_open()) and not (street_market!=null and not street_market.active.is_empty()):
		_open_city_map()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if arrival_story!=null and arrival_story.active():
		if event is InputEventMouseMotion: arrival_story.handle_look(event.relative)
		return
	# Touch gestures own the camera; emulated mouse clicks still reach GUI
	# controls first, but must not trigger gameplay or browser pointer lock.
	if mobile_mode and (event is InputEventMouseButton or event is InputEventMouseMotion): return
	if city_navigation!=null and city_navigation.active: return
	if cuba_world!=null and diagnostics_panel!=null and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F8:
		diagnostics_panel.visible = not diagnostics_panel.visible
		if diagnostics_panel.visible: _refresh_diagnostics()
		return
	if street_market!=null and not street_market.active.is_empty():
		street_market.handle(event)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_H and not building_mode and not (business!=null and business.modal_open()) and not (taxis!=null and taxis.dialog.visible):
		controls_expanded = not controls_expanded
		_update_hud()
		return
	if business!=null and business.modal_open():
		if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE,KEY_P]:
			business.close()
		return
	if garage!=null and garage.riding:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode==KEY_E: interact_requested = true
			elif event.keycode==KEY_R: reset_requested = true
			elif event.keycode==KEY_P and garage.riding_borrowed():
				if absf(garage.ride_speed)<.6: business.open_phone()
				else: business._notify("Detén la moto antes de usar el teléfono.")
		if event is InputEventMouseMotion and gameplay_input():
			yaw -= event.relative.x*.003
			pitch = clampf(pitch-event.relative.y*.003,-.95,.30)
			pivot.rotation = Vector3(pitch,yaw,0)
		return
	if business!=null and not bus_riding and not building_mode and not (taxis!=null and taxis.dialog.visible) and event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_I and carlos_mission!=null and carlos_mission.inside: return
		if event.keycode==KEY_I and backpack!=null and not driving and not taxi_riding and not (garage!=null and garage.riding):
			backpack.open_inventory()
			return
		if event.keycode==KEY_P:
			business.open_phone()
			return
		if event.keycode==KEY_G and not driving and not taxi_riding and not city_world.seated and not (garage!=null and garage.inside):
			cargo_requested = true
			return
	if cuba_world!=null and player!=null and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F9 and not (pilar_editor!=null and pilar_editor.active) and not (taxis!=null and taxis.dialog.visible):
		var at := van.global_position if driving and van!=null else player.global_position
		DisplayServer.clipboard_set(cuba_world.geography.coordinate_text(at))
		exit_message = "GPS copiado al portapapeles."
		message_time = 2.0
		return
	if taxis != null and taxis.dialog.visible:
		if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
			taxis.close_dialog()
		return
	if bus_riding:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode==KEY_E: urban_buses.player_exit_requested = true
			elif event.keycode==KEY_R: bus_reset_requested = true
		if event is InputEventMouseMotion and gameplay_input():
			yaw -= event.relative.x*.003
			pitch = clampf(pitch-event.relative.y*.003,-.95,.30)
			pivot.rotation = Vector3(pitch,yaw,0)
		return
	if taxi_riding:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode==KEY_E:
				interact_requested = true
			elif event.keycode==KEY_R:
				taxi_reset_requested = true
			elif event.keycode==KEY_T:
				taxis.cycle_speed()
				_update_hud()
		if event is InputEventMouseMotion and gameplay_input():
			yaw -= event.relative.x*.003
			pitch = clampf(pitch-event.relative.y*.003,-.95,.30)
			pivot.rotation = Vector3(pitch,yaw,0)
		return
	if cuba_world != null and event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_F6:
		graphics_quality = (graphics_quality+1)%GRAPHICS_NAMES.size()
		_apply_performance_mode()
		return
	if pilar_editor != null and pilar_editor.active:
		pilar_editor.handle(event)
		return
	if pilar_editor != null and not driving and not (garage!=null and garage.inside) and event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT:
		if carlos_mission!=null and carlos_mission.inside: return
		context_requested = true
		return
	if builder != null and builder.active:
		builder.handle(event)
		return
	if building_mode:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		if (garage!=null and garage.inside) or (carlos_mission!=null and carlos_mission.inside): return
		if pilar_editor != null:
			if not driving:
				_open_pilar_editor(player.global_position,false)
			return
		if not driving and builder != null and (city_world == null or (not city_world.seated and not city_world.inside_home and not city_world.bakery.inside and not city_world.family_home.pool_inside)):
			building_mode = true
			player.velocity = Vector3.ZERO
			status.hide()
			reticle.hide()
			builder.open(player.global_position)
		else:
			exit_message = "Sal de la casa, piscina, banco o van antes de construir."
			message_time = 2.0
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_X and garage!=null and not driving and garage.return_home_tool():
			_update_hud()
			return
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_V and player != null and not driving and not (garage!=null and (garage.dining_seated or not garage.bath_mode.is_empty())):
			if (carlos_mission!=null and carlos_mission.inside) or (yordi_mission!=null and yordi_mission.robbery_active()): return
			first_person = not first_person
			_apply_camera_mode()
		elif event.keycode == KEY_R and player != null:
			reset_requested = true
		elif event.keycode == KEY_E and gameplay_input():
			interact_requested = true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and yordi_mission!=null and yordi_mission.throw_stone():
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and gameplay_input() and pivot != null:
		if is_instance_valid(garage) and garage.dining_seated:
			garage.dining_look(event.relative,.003)
			return
		yaw -= event.relative.x * 0.003
		var down_limit := -1.48 if (garage!=null and garage.inside) or (carlos_mission!=null and carlos_mission.inside) or (yordi_mission!=null and yordi_mission.robbery_active()) else -1.05
		pitch = clampf(pitch - event.relative.y * 0.003, down_limit, 0.35)
		pivot.rotation = Vector3(pitch, yaw, 0)

# Reuse the exact exported van hierarchy when present.
func _normalized_name(value: String) -> String:
	return value.to_lower().replace(" ", "").replace("_", "").replace("|", "").replace("-", "").replace(".", "")

func _find_named(node: Node, prefix: String) -> Node3D:
	if node is Node3D and _normalized_name(String(node.name)).begins_with(prefix):
		return node as Node3D
	for child in node.get_children():
		var found := _find_named(child, prefix)
		if found != null:
			return found
	return null

func _new_van_body(position_world: Vector3) -> CharacterBody3D:
	var car := CharacterBody3D.new()
	car.name = "DrivableVan"
	car.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	car.collision_layer = VAN_LAYER
	car.collision_mask = 1
	car.floor_snap_length = 0.0
	car.floor_max_angle = deg_to_rad(40.0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.18, 1.90, 5.12)
	collision.shape = shape
	collision.position.y = 1.12
	car.add_child(collision)
	add_child(car)
	car.global_position = position_world + Vector3.UP * 0.04
	VehicleLights.attach(car,Vector3(.76,.91,2.58),Vector3(.89,.91,-2.58),Vector3(.29,.17,.035),Vector3(.12,.28,.035))
	return car

# Reuse only the two original vehicles; do not attach the old city permanently.
func _tick_deferred_vehicles(delta: float) -> void:
	if not is_instance_valid(player) or not is_instance_valid(monte_services): return
	deferred_vehicles_clock += minf(delta,.1)
	if deferred_vehicles_clock<12.0: return
	if arrival_story!=null and arrival_story.phase in ["approach","arrival"]: return
	if not deferred_vehicles_requested:
		deferred_vehicles_requested = true
		if not ResourceLoader.exists(CITY_PATH):
			deferred_vehicles_done = true
			push_warning("MyCity: falta city.glb para recuperar la van original.")
			return
		var error := ResourceLoader.load_threaded_request(CITY_PATH,"PackedScene",false)
		if error!=OK:
			deferred_vehicles_done = true
			push_warning("MyCity: no se pudo solicitar el vehículo original: "+str(error))
		return
	if deferred_vehicles_ready==null:
		var result := ResourceLoader.load_threaded_get_status(CITY_PATH)
		if result==ResourceLoader.THREAD_LOAD_IN_PROGRESS: return
		if result!=ResourceLoader.THREAD_LOAD_LOADED:
			deferred_vehicles_done = true
			push_warning("MyCity: falló la carga diferida del vehículo original.")
			return
		deferred_vehicles_ready = ResourceLoader.load_threaded_get(CITY_PATH) as PackedScene
		if deferred_vehicles_ready==null:
			deferred_vehicles_done = true
			return
	# Prefer an indoor moment, but don't wait forever if the player stays outside.
	if not home_exit_loading and deferred_vehicles_clock<45.0: return
	deferred_vehicles_done = true
	var started := Time.get_ticks_msec()
	var source := deferred_vehicles_ready.instantiate()
	deferred_vehicles_ready = null
	if source==null: return
	# The old city never enters the scene tree; only its two vehicle subtrees do.
	var holder := Node3D.new()
	add_child(holder)
	var original := _find_named(source,"vancontrol")
	var school_bus := _find_named(source,"buscontrol")
	if original!=null: _extract_imported_vehicle(original,holder)
	if school_bus!=null: _extract_imported_vehicle(school_bus,holder)
	source.free()
	if original!=null:
		_install_city_van(holder)
		monte_services.story_van = van
		monte_services.story_van_retry = 0.0
		print("MyCity: van original cargada después del inicio; esperando un lugar seguro en el tráfico.")
	else: push_warning("MyCity: VAN | CONTROL no encontrado; no se inventa otro modelo.")
	if school_bus!=null: city_world.add_school_bus(school_bus)
	holder.queue_free()
	print("MyCity carga diferida (ms): extracción de vehículos=",Time.get_ticks_msec()-started)

func _extract_imported_vehicle(model: Node3D,holder: Node3D) -> void:
	var pose := model.transform
	var parent := model.get_parent()
	while parent!=null:
		if parent is Node3D: pose = parent.transform*pose
		parent = parent.get_parent()
	model.get_parent().remove_child(model)
	model.owner = null
	holder.add_child(model)
	model.transform = pose

func _restore_original_vehicles() -> void:
	var warmed: Resource = get_tree().get_meta("mycity_warmed_glb",null)
	if get_tree().has_meta("mycity_warmed_glb"): get_tree().remove_meta("mycity_warmed_glb")
	if warmed==null and not ResourceLoader.exists(CITY_PATH):
		push_warning("MyCity: falta game/city.glb. Exporta la ciudad original desde Blender.")
		return
	var packed := warmed as PackedScene if warmed!=null else load(CITY_PATH) as PackedScene
	if packed == null:
		push_warning("MyCity: no se pudo cargar city.glb.")
		return
	var source := packed.instantiate()
	add_child(source)
	_install_city_van(source)
	if van != null:
		print("MyCity: van original recuperada.")
	var school_bus := _find_named(source,"buscontrol")
	if school_bus != null:
		city_world.add_school_bus(school_bus)
	else:
		push_warning("MyCity: BUS | CONTROL no encontrado en city.glb.")
	# Both vehicles have been reparented into the new world. Release the
	# obsolete imported terrain and all other objects before the first frame.
	remove_child(source)
	source.queue_free()

func _install_city_van(city: Node) -> void:
	var original := _find_named(city, "vancontrol")
	if original == null:
		push_warning("No se encontro VAN | CONTROL en city.glb; la van no sera interactiva.")
		return
	var original_transform := original.global_transform
	if not adaptation_mode or not is_instance_valid(van):
		van = _new_van_body(original_transform.origin)
	# In adaptation the hidden body is reused; traffic places it on a road.
	# Blender -Y maps to Godot +Z in our GLB export.
	# Preserve imported transforms and mesh hierarchy, including door hinges.
	var forward := original_transform.basis.z
	if absf(forward.y) < 0.25 and Vector2(forward.x, forward.z).length() > 0.1:
		van.rotation.y = atan2(forward.x, forward.z)
	original.reparent(van, true)
	van_visual = original
	original.global_position = van.global_position
	# Correct any offset introduced by the importer from actual tire geometry.
	var tire_nodes: Array[MeshInstance3D] = []
	_collect_tires(original, tire_nodes)
	if not tire_nodes.is_empty():
		var bottom := INF
		for tire in tire_nodes:
			var bounds := tire.get_aabb()
			for index in range(8):
				var world_point := tire.to_global(bounds.get_endpoint(index))
				bottom = minf(bottom, van.to_local(world_point).y)
		if is_finite(bottom):
			original.position.y -= bottom
	van_home = van.global_transform
	driver_door = _find_named(original, "bisagrapuertadelantera")
	if driver_door != null:
		door_closed = driver_door.rotation.y

func _collect_tires(node: Node, result: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and _normalized_name(String(node.name)).begins_with("neum"):
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_tires(child, result)

# Independent ground support for arcade driving. No gravity-induced collision
# recovery against thin road meshes or accidental stacking on other objects.
func _support_van() -> bool:
	if van == null:
		return false
	var space := get_world_3d().direct_space_state
	var heights: Array[float] = []
	for offset in [Vector3.ZERO, Vector3(-0.98, 0, -1.63), Vector3(0.98, 0, -1.63), Vector3(-0.98, 0, 1.63), Vector3(0.98, 0, 1.63)]:
		var sample := van.to_global(offset)
		var ray := PhysicsRayQueryParameters3D.create(sample + Vector3.UP * 8.0, sample - Vector3.UP * 12.0, GROUND_LAYER | 8)
		ray.hit_back_faces = true
		var hit := space.intersect_ray(ray)
		if not hit.is_empty():
			heights.append(float(hit.position.y))
	if heights.size() < 3:
		return false
	var level := -INF
	for h in heights:
		level = maxf(level, h)
	van.global_position.y = level + 0.015
	van.velocity.y = 0.0
	return true

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	return mat

func _box(parent: Node3D, part_name: String, at: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = mat
	parent.add_child(instance)
	instance.position = at
	return instance

func _sphere(parent: Node3D, part_name: String, at: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	if avatar_sphere_mesh==null:
		avatar_sphere_mesh = SphereMesh.new()
		avatar_sphere_mesh.radius = .5
		avatar_sphere_mesh.height = 1.0
		avatar_sphere_mesh.radial_segments = 12
		avatar_sphere_mesh.rings = 6
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = avatar_sphere_mesh
	instance.material_override = mat
	parent.add_child(instance)
	instance.position = at
	instance.scale = size
	return instance

func _make_demo_van() -> void:
	van = _new_van_body(Vector3.ZERO)
	van_home = van.global_transform
	van_visual = Node3D.new()
	van.add_child(van_visual)
	var white := _material(Color(0.91, 0.93, 0.96))
	var dark := _material(Color(0.08, 0.10, 0.13))
	var glass := _material(Color(0.17, 0.40, 0.55))
	_box(van_visual, "Body", Vector3(0, 0.84, 0), Vector3(2.05, 1.03, 5.0), white)
	_box(van_visual, "Cab", Vector3(0, 1.65, -0.2), Vector3(1.98, 1.0, 4.0), white)
	_box(van_visual, "Windshield", Vector3(0, 1.69, 1.82), Vector3(1.68, 0.65, 0.05), glass)
	_box(van_visual, "BackGlass", Vector3(0, 1.69, -2.23), Vector3(1.67, 0.63, 0.06), glass)
	for side in [-1, 1]:
		_box(van_visual, "Window", Vector3(side * 1.0, 1.72, -0.65), Vector3(0.06, 0.56, 2.1), glass)
		for z in [-1.62, 1.62]:
			var wheel_mesh := CylinderMesh.new()
			wheel_mesh.top_radius = 0.42
			wheel_mesh.bottom_radius = 0.42
			wheel_mesh.height = 0.24
			wheel_mesh.radial_segments = 16
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.material_override = dark
			van_visual.add_child(wheel)
			wheel.position = Vector3(side * 1.01, 0.42, z)
			wheel.rotation.z = PI / 2.0
	driver_door = Node3D.new()
	van_visual.add_child(driver_door)
	driver_door.position = Vector3(-1.06, 0.65, 1.65)
	_box(driver_door, "DriverDoor", Vector3(0, 0.49, -0.68), Vector3(0.08, 0.9, 1.35), white)
	_box(driver_door, "DriverWindow", Vector3(0, 1.04, -0.68), Vector3(0.08, 0.47, 1.35), glass)

func _make_cartoon_avatar() -> void:
	var skin := _material(Color(0.84, 0.56, 0.36))
	var shirt := _material(Color(0.08, 0.46, 0.94))
	var jeans := _material(Color(0.10, 0.18, 0.34))
	var shoes := _material(Color(0.09, 0.10, 0.13))
	var hair := _material(Color(0.14, 0.085, 0.045))
	var eye := _material(Color(0.06, 0.07, 0.10))
	var eye_white := _material(Color(0.98, 0.98, 0.98))
	# Capsule collision remains the same. All limbs are purely visual.
	_sphere(avatar, "Shirt", Vector3(0, 0.05, 0), Vector3(0.58, 0.64, 0.35), shirt)
	_sphere(avatar, "Hip", Vector3(0, -0.23, 0), Vector3(0.44, 0.25, 0.30), jeans)
	_sphere(avatar, "Neck", Vector3(0,.36,0),Vector3(.19,.20,.19),skin)
	_sphere(avatar, "Head", Vector3(0, 0.53, 0), Vector3(0.48, 0.52, 0.44), skin)
	_sphere(avatar, "Hair", Vector3(0, 0.72, -0.035), Vector3(0.49, 0.22, 0.45), hair)
	for side in [-1, 1]:
		_sphere(avatar, "Ear", Vector3(side * 0.235, 0.53, 0), Vector3(0.075, 0.11, 0.08), skin)
		_sphere(avatar, "EyeWhite", Vector3(side * 0.096, 0.57, 0.194), Vector3(0.080, 0.055, 0.036), eye_white)
		_sphere(avatar, "Eye", Vector3(side * 0.096, 0.57, 0.213), Vector3(0.033, 0.042, 0.020), eye)
		_sphere(avatar, "Brow",Vector3(side*.096,.623,.193),Vector3(.087,.018,.019),hair)
		var shoulder := Node3D.new()
		avatar.add_child(shoulder)
		shoulder.position = Vector3(side * 0.255, 0.21, 0)
		limb_arms.append(shoulder)
		_sphere(shoulder, "Sleeve", Vector3(side*.015, -0.065, 0), Vector3(0.19, 0.28, 0.21), shirt)
		_sphere(shoulder, "Arm", Vector3(0, -0.30, 0), Vector3(0.13, 0.33, 0.15), skin)
		_sphere(shoulder, "Hand", Vector3(0, -0.46, 0), Vector3(0.17, 0.18, 0.16), skin)
		var hip := Node3D.new()
		avatar.add_child(hip)
		hip.position = Vector3(side * 0.13, -0.23, 0)
		limb_legs.append(hip)
		_sphere(hip, "Leg", Vector3(0, -0.23, 0), Vector3(0.22, 0.48, 0.23), jeans)
		var footwear := _sphere(hip, "Shoe", Vector3(0, -0.46, 0.075), Vector3(0.22, 0.16, 0.35), shoes)
		footwear.mesh = Shoe.mesh()
		footwear.material_override = Shoe.material(shoes)
	_sphere(avatar, "Nose", Vector3(0, 0.51, 0.218), Vector3(0.065, 0.085, 0.065), skin)
	_sphere(avatar, "Mouth", Vector3(0,.43,.204),Vector3(.085,.022,.015),_material(Color("#925b49")))

func _animate_avatar(delta: float, speed: float) -> void:
	var moving := speed > 0.1 and player.is_on_floor()
	var strength := lerpf(.45,.86,smoothstep(2.0,8.0,speed))
	avatar_stride_weight = move_toward(avatar_stride_weight,1.0 if moving else 0.0,delta*7.0)
	avatar_idle_phase = fposmod(avatar_idle_phase+delta*2.0,TAU)
	if moving:
		step_phase = fposmod(step_phase+delta*(5.5+speed*.9),TAU)
	for i in range(limb_legs.size()):
		var swing := sin(step_phase + i * PI) * strength * avatar_stride_weight
		if not player.is_on_floor():
			swing = -0.25 if i == 0 else 0.35
		limb_legs[i].rotation.x = lerpf(limb_legs[i].rotation.x, swing, minf(delta * 12.0, 1.0))
		limb_arms[i].rotation.x = lerpf(limb_arms[i].rotation.x, -swing * 0.85, minf(delta * 12.0, 1.0))
	var bob := absf(sin(step_phase))*.032*avatar_stride_weight
	avatar.position.y = lerpf(avatar.position.y,bob+sin(avatar_idle_phase)*.003,minf(delta*12.0,1.0))

func _near_van() -> bool:
	if adaptation_mode: return false
	if van == null or player == null:
		return false
	var local := van.to_local(player.global_position)
	return absf(local.x) < 3.4 and absf(local.z) < 4.1 and absf(local.y) < 2.5

func _door_cycle() -> void:
	if driver_door == null:
		return
	if door_tween != null and door_tween.is_valid():
		door_tween.kill()
	driver_door.rotation.y = door_closed
	door_tween = create_tween()
	door_tween.tween_property(driver_door, "rotation:y", door_closed - 1.0, 0.24)
	door_tween.tween_interval(0.18)
	door_tween.tween_property(driver_door, "rotation:y", door_closed, 0.28)

func _enter_van() -> void:
	if not _near_van():
		return
	driving = true
	drive_speed = 0.0
	player.velocity = Vector3.ZERO
	avatar.hide()
	player_shape.set_deferred("disabled", true)
	_door_cycle()
	pivot.reparent(van, false)
	pivot.position = Vector3(0, 1.55, 0)
	yaw = PI
	pitch = -0.24
	pivot.rotation = Vector3(pitch, yaw, 0)
	arm.spring_length = 7.5
	_apply_camera_mode()

func _safe_exit() -> bool:
	# Test both sides against ground and physical world, including the road.
	var space := get_world_3d().direct_space_state
	for side in [-1.0, 1.0]:
		var side_point := van.to_global(Vector3(side * 1.95, 0, 0.9))
		var ray := PhysicsRayQueryParameters3D.create(side_point + Vector3.UP * 3.0, side_point - Vector3.UP * 3.0)
		ray.exclude = [van.get_rid(), player.get_rid()]
		var hit := space.intersect_ray(ray)
		if hit.is_empty():
			continue
		if hit.normal.y < 0.65:
			continue
		var destination: Vector3 = hit.position + Vector3.UP * 0.86
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = player_shape.shape
		query.transform = Transform3D(Basis.IDENTITY, destination)
		query.exclude = [player.get_rid(), van.get_rid()]
		if not space.intersect_shape(query, 1).is_empty():
			continue
		_finish_exit(destination)
		return true
	return false

func _finish_exit(destination: Vector3) -> void:
	driving = false
	drive_speed = 0.0
	van.velocity = Vector3.ZERO
	_door_cycle()
	player.global_position = destination
	player.velocity = Vector3.ZERO
	avatar.show()
	player_shape.set_deferred("disabled", false)
	pivot.reparent(player, false)
	pivot.position = Vector3(0, 0.65, 0)
	yaw = van.rotation.y + PI
	pitch = -0.20
	pivot.rotation = Vector3(pitch, yaw, 0)
	_apply_camera_mode()

func _face_cuba_home() -> void:
	if cuba_world==null or cuba_world.home_root==null or pivot==null:
		return
	yaw = cuba_world.home_root.rotation.y
	pitch = -.06
	pivot.rotation = Vector3(pitch,yaw,0)

func _reset_player() -> void:
	if business!=null and business.first_story!=null and business.first_story.reset_checkpoint(): return
	if yordi_mission!=null and yordi_mission.checkpoint_reset(): return
	if carlos_mission!=null: carlos_mission.reset()
	if garage!=null: garage.reset()
	if monte_services!=null:
		monte_services.return_player_bag()
	if city_world != null:
		city_world.reset_interaction(avatar,limb_legs)
		_apply_camera_mode()
		player_shape.set_deferred("disabled",false)
	if driving and van != null:
		van.global_transform = van_home
		van.velocity = Vector3.ZERO
		_finish_exit(spawn_position)
	player.global_position = spawn_position
	player.velocity = Vector3.ZERO
	_face_cuba_home()

func _read_controls() -> Vector2:
	var movement := Vector2.ZERO
	if not gameplay_input():
		return movement
	if is_instance_valid(mobile_controls): movement = mobile_controls.movement
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		movement.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		movement.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		movement.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		movement.x += 1
	return movement.limit_length(1.0)

func _drive(delta: float, movement: Vector2) -> void:
	var boost := control_pressed(KEY_SHIFT) and movement.y<0.0 and gameplay_input()
	var target := -movement.y * ((39.0 if boost else 13.0) if movement.y <= 0 else 4.0)
	var brake := control_pressed(KEY_SPACE) or not gameplay_input()
	if brake:
		target = 0.0
	drive_speed = move_toward(drive_speed, target, delta * (18.0 if brake else (15.0 if boost else 5.0)))
	if absf(drive_speed) > 0.15:
		van.rotation.y -= movement.x * signf(drive_speed) * delta * 1.35 * minf(absf(drive_speed) / 3.0, 1.0)
	var prior := van.global_transform
	var impact_speed := drive_speed
	var forward := van.global_transform.basis.z.normalized()
	van.velocity.x = forward.x * drive_speed
	van.velocity.z = forward.z * drive_speed
	van.velocity.y = 0.0
	van.move_and_slide()
	if not _support_van():
		van.global_transform = prior
		van.velocity = Vector3.ZERO
		drive_speed = 0.0
	if incidents!=null:
		incidents.vehicle_motion(van,prior,impact_speed,2.18,5.12)
	if van.get_slide_collision_count() > 0:
		drive_speed *= 0.35
	if van.global_position.y < -8.0 or absf(van.global_position.x) > (1250.0 if cuba_world != null else (253.0 if native_city else 79.0)) or absf(van.global_position.z) > (1250.0 if cuba_world != null else (253.0 if native_city else 109.0)):
		van.global_transform = van_home
		van.velocity = Vector3.ZERO
		drive_speed = 0.0

func _update_hud() -> void:
	if status == null:
		return
	performance_label.visible = controls_expanded and cuba_world!=null and not building_mode
	gps_label.visible = controls_expanded and cuba_world!=null and not building_mode
	if business!=null:
		business.hud_expanded = controls_expanded
		business._update_hud()
	if not controls_expanded:
		_update_compact_hud()
		return
	if garage!=null and garage.riding:
		var ride_name := "Moto de Yordi · tú conduces" if garage.riding_borrowed() else "Vehículo"
		status.text = ride_name+" · %d km/h\nW/S: acelerar y retroceder | Shift: turbo | A/D: girar\nEspacio: frenar | E: bajar | H: ocultar controles" % roundi(absf(garage.ride_speed)*3.6)
		return
	if bus_riding:
		var bus: Dictionary = urban_buses.player_bus
		status.text = "GUAGUA | "+String(bus.get("line",""))+"\n"
		status.text += "Bajada solicitada · próxima parada" if urban_buses.player_exit_requested else "E: solicitar bajar en la siguiente parada"
		status.text += "\nShift: acelerar | R: regresar a casa | H: ocultar controles"
		if not bus.active_stop.is_empty(): status.text += "\nParada: "+String(bus.active_stop.name)
		return
	if taxi_riding:
		var ride_name := "MOTO DE YORDI" if yordi_mission!=null and yordi_mission.owns_passenger_trip() and yordi_mission.trip_role=="bike_out" else "TAXI"
		status.text = ride_name+" | "+taxis.ride_status+"\n"+taxis.speed_description()+" | T: cambiar velocidad | Shift: turbo\nE: detener y bajar | R: volver a casa si te bloqueas | H: ocultar controles"
		return
	var title := "PILAR-ATARÉS | La Habana" if cuba_world != null else ("VALDY JR TV | Ciudad 2.0" if native_city else "VALDY JR TV | Ciudad original")
	if not city_loaded:
		title = "MODO DE PRUEBA | Exporta city.glb desde Blender"
	if driving:
		status.text = title + "\nCONDUCIENDO | %d km/h" % roundi(absf(drive_speed) * 3.6)
		status.text += "\nW/S: acelerar y retroceder | Shift: turbo | A/D: girar | Espacio: frenar\nE: salir detenido | R: reiniciar | Esc: liberar mouse"
	else:
		status.text = title + "\nWASD / flechas: caminar | Mouse: mirar | Espacio: saltar\nShift: correr | R: regresar | Esc: liberar mouse"
		var action: String = garage.action_text(player.global_position) if adaptation_mode and garage!=null and (garage.inside or garage.rental_entry_near(player.global_position)) else ""
		if action.is_empty() and not adaptation_mode and business!=null and business.first_story!=null: action = business.first_story.action_text()
		if action.is_empty() and yordi_mission!=null: action = yordi_mission.action_text()
		if action.is_empty() and carlos_mission!=null: action = carlos_mission.action_text()
		if action.is_empty() and backpack!=null: action = backpack.action_text()
		if action.is_empty(): action = _albertico_action()
		if action.is_empty() and garage!=null: action = garage.action_text(player.global_position)
		if action.is_empty() and street_market!=null: action = street_market.action_text()
		if action.is_empty() and business!=null: action = business.aimed_text(player.global_position)
		if action.is_empty() and business!=null and business.life!=null: action = business.life.action_text(player.global_position)
		if action.is_empty() and backpack!=null and not backpack.empty_hands(): action = "[I] Objeto en mano · guardar / usar / soltar"
		if action.is_empty() and _aimed_person()!=null: action = "[E] Saludar"
		if action.is_empty() and urban_buses!=null and not urban_buses.nearby_boarding(player.global_position).is_empty(): action = "[E] Subir a la guagua"
		if action.is_empty(): action = monte_services.action_text(player.global_position) if monte_services!=null and (business==null or business.ledger.carry.is_empty()) else ""
		if action.is_empty() and business!=null:
			action = business.action_text(player.global_position)
		if action.is_empty() and city_world!=null:
			action = city_world.interaction_text(player.global_position)
		var aimed: String = cuba_world.aimed_text(play_camera,player) if cuba_world != null and action.is_empty() else ""
		if action != "":
			status.text += "\n" + action
		elif cuba_world != null and not aimed.is_empty():
			status.text += "\n"+aimed
		elif taxis != null and not taxis.nearby(player.global_position).is_empty():
			status.text += "\n[E] Tomar taxi"
		elif _near_van():
			status.text += "\n[E] Subir a la van"
		elif van == null:
			status.text += "\nVan no encontrada en la exportacion."
	status.text += "\nH: ocultar controles"
	if not driving:
		status.text += "\n[V] Primera / tercera persona"
		status.text += " | [B] Construir ciudad"
		if pilar_editor != null:
			status.text += "\nClic derecho: editar objeto o terreno | B y F8: GPS"
	if cuba_world != null:
		status.text += "\n© OpenStreetMap contributors | ODbL | openstreetmap.org/copyright"
		if not cuba_world.home_gps_status.is_empty():
			status.text += "\n"+cuba_world.home_gps_status
		if cuba_world.home_root!=null and not cuba_world.paired_landmarks:
			status.text += "\nLa Alborada: falta espacio junto a la casa."
		if cuba_world.prompt_time > 0.0:
			status.text += "\n"+cuba_world.prompt
	if monte_services!=null and monte_services.notice_time>0.0:
		status.text += "\n"+monte_services.notice
	if message_time > 0.0:
		status.text += "\n" + exit_message

# Gameplay prompts remain visible with the large help overlay collapsed.
func _update_compact_hud() -> void:
	var lines: Array[String] = ["[H] Controles · [M] Mapa · [F10] Menú · [F11] Pantalla completa" if city_navigation!=null else "[H] Controles · [F11] Pantalla completa"]
	if garage!=null and garage.riding:
		var ride_name := "Moto de Yordi · " if garage.riding_borrowed() else ""
		lines.append(ride_name+("%d km/h · [Shift] Turbo · [E] Bajar" % roundi(absf(garage.ride_speed)*3.6)))
		if garage.ride_exit_requested: lines.append("Frenando para bajar...")
	elif bus_riding:
		var bus: Dictionary = urban_buses.player_bus
		lines.append("Guagua "+String(bus.get("line",""))+" · "+("Bajada solicitada" if urban_buses.player_exit_requested else "[E] Bajar en próxima parada")+" · [Shift] Acelerar")
	elif taxi_riding:
		var ride_name := "Moto de Yordi" if yordi_mission!=null and yordi_mission.owns_passenger_trip() and yordi_mission.trip_role=="bike_out" else "Taxi"
		lines.append(ride_name+" · "+taxis.ride_status+" | "+taxis.speed_description()+" | [Shift] Turbo · [E] Bajar")
	elif driving:
		lines.append("%d km/h · [Shift] Turbo · [E] Bajar detenido" % roundi(absf(drive_speed)*3.6))
	else:
		var action: String = garage.action_text(player.global_position) if adaptation_mode and garage!=null and (garage.inside or garage.rental_entry_near(player.global_position)) else ""
		if action.is_empty() and not adaptation_mode and business!=null and business.first_story!=null: action = business.first_story.action_text()
		if action.is_empty() and yordi_mission!=null: action = yordi_mission.action_text()
		if action.is_empty() and carlos_mission!=null: action = carlos_mission.action_text()
		if action.is_empty() and backpack!=null: action = backpack.action_text()
		if action.is_empty(): action = _albertico_action()
		if action.is_empty() and garage!=null: action = garage.action_text(player.global_position)
		if action.is_empty() and street_market!=null: action = street_market.action_text()
		if action.is_empty() and business!=null: action = business.aimed_text(player.global_position)
		if action.is_empty() and business!=null and business.life!=null: action = business.life.action_text(player.global_position)
		if action.is_empty() and backpack!=null and not backpack.empty_hands(): action = "[I] Objeto en mano · guardar / usar / soltar"
		if action.is_empty() and _aimed_person()!=null: action = "[E] Saludar"
		if action.is_empty() and urban_buses!=null and not urban_buses.nearby_boarding(player.global_position).is_empty(): action = "[E] Subir a la guagua"
		if action.is_empty() and monte_services!=null and (business==null or business.ledger.carry.is_empty()):
			action = monte_services.action_text(player.global_position)
		if action.is_empty() and business!=null: action = business.action_text(player.global_position)
		if action.is_empty() and city_world!=null: action = city_world.interaction_text(player.global_position)
		if action.is_empty() and cuba_world!=null: action = cuba_world.aimed_text(play_camera,player)
		if action.is_empty() and taxis!=null and not taxis.nearby(player.global_position).is_empty(): action = "[E] Tomar taxi"
		if action.is_empty() and _near_van(): action = "[E] Subir a la van"
		if not action.is_empty(): lines.append(action)
	if garage!=null and not garage.gps_hint().is_empty(): lines.append(garage.gps_hint())
	if cuba_world!=null and cuba_world.prompt_time>0.0: lines.append(cuba_world.prompt)
	if monte_services!=null and monte_services.notice_time>0.0: lines.append(monte_services.notice)
	if message_time>0.0: lines.append(exit_message)
	status.text = "\n".join(lines)

# The reticle selects a nearby visible NPC; walls occlude greetings.
func _albertico_action() -> String:
	if business==null or player==null: return ""
	if garage!=null and (garage.inside or garage.riding or not String(garage.state.part).is_empty() or not String(garage.state.held_furniture).is_empty()): return ""
	if backpack!=null and not backpack.empty_hands(): return ""
	if monte_services!=null and monte_services.player_bag!=null: return ""
	if business.life!=null and not business.life.state.meal.is_empty(): return ""
	return business.aimed_albertico_text(player.global_position)

func _aimed_person() -> Node3D:
	if play_camera==null or player==null or cuba_world==null: return null
	var origin := play_camera.global_position
	var direction := -play_camera.global_transform.basis.z
	var best: Node3D
	var best_depth := INF
	for node in get_tree().get_nodes_in_group("social_people"):
		if not node is Node3D or not node.is_visible_in_tree(): continue
		var person := node as Node3D
		if person.has_meta("incident_role"): continue
		if player.global_position.distance_to(person.global_position)>3.7: continue
		var center := person.global_position+Vector3.UP*1.15
		var depth := (center-origin).dot(direction)
		if depth<=0.0 or depth>best_depth: continue
		var nearest := origin+direction*depth
		if absf(nearest.y-center.y)>.75 or Vector2(nearest.x-center.x,nearest.z-center.z).length()>.32: continue
		var ray := PhysicsRayQueryParameters3D.create(origin,nearest,1|4|8|16)
		ray.exclude = [player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): continue
		best = person
		best_depth = depth
	return best

func _greet_person() -> bool:
	var person := _aimed_person()
	if person==null: return false
	if social_cooldown>0.0: return true
	var female := bool(person.get_meta("female",false))
	var context := String(person.get_meta("social_context","street"))
	if person.get_script()==preload("res://street_person.gd"):
		female = bool(person.get("female"))
		context = String(person.get("social_context"))
	var greetings := ["¿Qué bolá, asere?","¿Cómo está la cosa, mi hermano?","¿Qué hay de nuevo?","¿Todo bien, socio?","¡Dime! ¿Cómo va eso?","¿En qué andas, compay?"]
	if female:
		greetings = ["¿Qué tal, mimi, cómo estás?","¿Qué hay de nuevo?","¡Hola, mi amiga! ¿Cómo va eso?","¿Todo bien por aquí?","¡Buenas! ¿Cómo te trata la vida?","¿Qué bolá, vecina?"]
	var replies := ["Todo bien, tú sabes, tirando.","En la misma, tú sabes.","Asere, tú sabes, en la pelea.","Aquí, luchando como siempre.","Todo tranquilo, gracias a Dios.","Aquí vamos, pa'lante."]
	if context=="bus_wait":
		replies = ["Aquí esperando la guagua.","Esperando a ver si llega la guagua.","Voy pa' casa, esperando el transporte.","Aquí en la parada, tú sabes.","A ver si pasa pronto la guagua."]
	elif context=="shopping":
		replies = ["Voy a comprar algo de comida.","Voy a ver qué tiene Albertico.","Aquí buscando algo pa' la casa.","Voy a resolver la comida de hoy.","De compras, tú sabes, en la lucha."]
	elif context=="homeward":
		replies = ["Voy pa' casa, ya terminé por hoy.","Ya toca descansar un rato."]
	elif context=="workward":
		replies = ["Voy camino al trabajo.","Tengo que llegar temprano al trabajo."]
	elif context=="worker":
		replies = ["Aquí trabajando, tú sabes.","En la faena, asere.","Resolviendo el trabajo de hoy.","Aquí, cumpliendo con lo mío.","En la lucha, como siempre."]
	var name_value := String(person.get_meta("citizen_name","Vecino"))
	var recognition := business.life.greet(person) if business!=null and business.life!=null else ""
	var answer := recognition if not recognition.is_empty() else String(replies.pick_random())
	exit_message = "Tú: "+String(greetings.pick_random())+"\n"+name_value+": "+answer
	message_time = 5.0
	if is_instance_valid(chatting_with): chatting_with.remove_meta("conversation_until")
	chatting_with = person
	person.set_meta("conversation_until",Time.get_ticks_msec()+4000)
	person.set_meta("conversation_at",player.global_position)
	social_cooldown = 4.0
	_update_hud()
	return true

func _start_bus_ride(bus: Dictionary) -> bool:
	if not urban_buses.board_player(bus): return false
	bus_riding = true
	bus_previous_first = first_person
	player.velocity = Vector3.ZERO
	player_shape.set_deferred("disabled",true)
	avatar.hide()
	reticle.hide()
	var body: CharacterBody3D = bus.body
	pivot.reparent(body,false)
	pivot.position = Vector3(.35,2.12,-1.8)
	yaw = PI
	pitch = -.12
	pivot.rotation = Vector3(pitch,yaw,0)
	arm.add_excluded_object(body.get_rid())
	arm.spring_length = 0.0
	_update_hud()
	return true

func _leave_bus(emergency: bool = false) -> bool:
	var result: Dictionary = {"position":spawn_position} if emergency else urban_buses.player_exit_position(player,player_shape.shape)
	if result.is_empty(): return false
	var body: CharacterBody3D = urban_buses.player_bus.body
	arm.remove_excluded_object(body.get_rid())
	pivot.reparent(player,false)
	player.global_position = result.position
	player.velocity = Vector3.ZERO
	player_shape.set_deferred("disabled",false)
	bus_riding = false
	bus_reset_requested = false
	first_person = bus_previous_first
	yaw = body.rotation.y+PI
	pitch = -.20
	pivot.rotation = Vector3(pitch,yaw,0)
	urban_buses.finish_player_ride()
	_apply_camera_mode()
	exit_message = "Bajaste de la guagua."
	message_time = 3.0
	_update_hud()
	return true

func _start_taxi_ride() -> void:
	taxi_riding = true
	taxi_exit_retry = 0.0
	interact_requested = false
	taxi_previous_first = first_person
	player.velocity = Vector3.ZERO
	player_shape.set_deferred("disabled",true)
	avatar.hide()
	reticle.hide()
	var taxi: CharacterBody3D = taxis.passenger.body
	pivot.reparent(taxi,false)
	pivot.position = Vector3(0,1.60,0)
	yaw = PI
	pitch = -.26
	pivot.rotation = Vector3(pitch,yaw,0)
	arm.add_excluded_object(taxi.get_rid())
	arm.spring_length = 5.5
	_update_hud()

func _leave_taxi(emergency: bool = false) -> bool:
	var result: Dictionary = {"position":spawn_position} if emergency else taxis.stop_position(player,player_shape.shape)
	if result.is_empty():
		return false
	var taxi: CharacterBody3D = taxis.passenger.body
	arm.remove_excluded_object(taxi.get_rid())
	pivot.reparent(player,false)
	pivot.position = Vector3(0,.65,0)
	player.global_position = result.position
	player.velocity = Vector3.ZERO
	player_shape.set_deferred("disabled",false)
	var mission_ride: bool = yordi_mission!=null and yordi_mission.owns_passenger_trip()
	var interrupted: bool = mission_ride and not emergency and not taxis.arrived
	if interrupted: yordi_mission.remember_interrupted_ride()
	taxi_riding = false
	first_person = taxi_previous_first
	yaw = taxi.rotation.y+PI
	pitch = -.20
	pivot.rotation = Vector3(pitch,yaw,0)
	var first_trip: bool = business!=null and business.first_story!=null and business.first_story.owns_trip()
	var reached := taxis.arrived
	if business!=null and not emergency and not mission_ride and not first_trip:
		business.taxi_arrival(player.global_position)
	taxis.finish_trip()
	if first_trip:
		business.first_story.ride_ended(reached and not emergency)
		if emergency: business.first_story.reset_checkpoint()
	_apply_camera_mode()
	if mission_ride: yordi_mission.on_ride_end(emergency,interrupted)
	exit_message = "Vuelve a subir para continuar la misión." if interrupted else "Viaje terminado."
	message_time = 3.0
	_update_hud()
	return true

func _open_pilar_editor(at: Vector3,context: bool) -> void:
	building_mode = true
	player.velocity = Vector3.ZERO
	status.hide()
	reticle.hide()
	pilar_editor.open(at,context)

func _bus_priority_notice(stop: Dictionary,bus: CharacterBody3D) -> void:
	if player==null or bus_riding or taxi_riding or (garage!=null and garage.inside): return
	var at := van.global_position if driving else player.global_position
	var center: Vector3 = stop.position
	var direction: Vector3 = stop.direction
	var side := Vector3(-direction.z,0,direction.x)
	var offset := at-center
	var approach := maxf(0.0,(center-bus.global_position).dot(direction))
	if absf(offset.dot(side))<2.1 and offset.dot(direction)>-approach-4.0 and offset.dot(direction)<7.0:
		exit_message = "La guagua está pidiendo paso. Deja libre la parada."
		message_time = 3.0

func _hold_story_input() -> bool:
	if business==null or not business.story_active: return false
	# Modal choices are the only active interactions during a story.
	player.velocity = Vector3.ZERO
	interact_requested = false
	context_requested = false
	cargo_requested = false
	reset_requested = false
	return true

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if arrival_story!=null and arrival_story.active():
		cuba_world.tick(delta)
		urban_buses.tick(delta)
		taxis.tick(delta,cuba_world.cuba_clock)
		monte_services.tick(delta)
		monte_pedestrians.tick(delta)
		# Ambient vehicles must run during the taxi, sleep and house scenes.
		# Do not run garage commerce, paint or mission systems here.
		if garage!=null: garage.tick_ambient_traffic(delta)
		arrival_story.tick(delta)
		return
	if _hold_story_input(): return
	if city_navigation!=null and city_navigation.active:
		player.velocity = Vector3.ZERO
		return
	if not adaptation_mode and business!=null and business.first_story!=null and not building_mode:
		business.first_story.tick(delta)
		if business.first_story.handshake_active():
			player.velocity = Vector3.ZERO
			interact_requested = false
			cargo_requested = false
			context_requested = false
			reset_requested = false
			return
	if _hold_story_input(): return
	if carlos_mission!=null and not building_mode: carlos_mission.tick(delta)
	if _hold_story_input(): return
	if not adaptation_mode and yordi_mission!=null and not building_mode: yordi_mission.tick(delta)
	if _hold_story_input(): return
	if not adaptation_mode and incidents!=null and not building_mode and not business.modal_open(): incidents.tick(delta)
	if backpack!=null and not building_mode: backpack.tick(delta)
	if street_market!=null:
		if not building_mode: street_market.tick(delta)
		if not street_market.active.is_empty():
			player.velocity = Vector3.ZERO
			cuba_world.tick(delta)
			urban_buses.tick(delta)
			taxis.tick(delta,cuba_world.cuba_clock)
			monte_services.tick(delta)
			monte_pedestrians.tick(delta)
			garage.tick(delta)
			business.tick(delta,false,false)
			return
	social_cooldown = maxf(0.0,social_cooldown-delta)
	if is_instance_valid(chatting_with):
		if Time.get_ticks_msec()>=int(chatting_with.get_meta("conversation_until",0)) or player.global_position.distance_to(chatting_with.global_position)>4.5:
			chatting_with.remove_meta("conversation_until")
			chatting_with = null
			social_cooldown = 0.0
		else:
			var facing := player.global_position-chatting_with.global_position
			chatting_with.rotation.y = lerp_angle(chatting_with.rotation.y,atan2(facing.x,facing.z),minf(1.0,delta*10.0))
	if garage!=null and not building_mode and not business.modal_open() and not (taxis!=null and taxis.dialog.visible):
		var garage_started := Time.get_ticks_usec()
		garage.tick(delta)
		_record_city_cost("house",garage_started)
	if garage!=null and garage.riding:
		if business!=null and business.modal_open():
			player.velocity = Vector3.ZERO
			return
		if reset_requested:
			reset_requested = false
			_reset_player()
			return
		if interact_requested:
			interact_requested = false
			garage.interact(player.global_position)
			if not garage.riding: return
		cuba_world.tick(delta)
		if urban_buses!=null: urban_buses.tick(delta)
		if monte_services!=null: monte_services.tick(delta)
		if monte_pedestrians!=null: monte_pedestrians.tick(delta)
		if taxis!=null: taxis.tick(delta,cuba_world.cuba_clock)
		if business!=null: business.tick(delta,true,false)
		garage.drive(delta,_read_controls())
		message_time = maxf(0.0,message_time-delta)
		hud_time += delta
		if hud_time>=.12:
			hud_time = 0.0
			_update_hud()
		return
	if bus_riding:
		if bus_reset_requested:
			_leave_bus(true)
			return
		cuba_world.tick(delta)
		urban_buses.tick(delta,control_pressed(KEY_SHIFT) and gameplay_input())
		if monte_services!=null: monte_services.tick(delta)
		if monte_pedestrians!=null: monte_pedestrians.tick(delta)
		if taxis!=null: taxis.tick(delta,cuba_world.cuba_clock)
		if business!=null: business.tick(delta,true,false)
		var body: CharacterBody3D = urban_buses.player_bus.body
		player.global_position = body.global_position+Vector3.UP*1.0
		if urban_buses.player_exit_requested and _leave_bus(): return
		hud_time += delta
		if hud_time>=.15:
			hud_time = 0.0
			_update_hud()
		return
	if business!=null:
		var business_started := Time.get_ticks_usec()
		business.tick(delta,driving or taxi_riding,building_mode)
		_record_city_cost("business",business_started)
		if business.modal_open():
			player.velocity = Vector3.ZERO
			return
	if taxis != null and taxis.dialog.visible:
		player.velocity = Vector3.ZERO
		if taxis.prepare_trip():
			_start_taxi_ride()
		return
	if taxi_riding:
		if taxi_reset_requested:
			taxi_reset_requested = false
			_leave_taxi(true)
			return
		cuba_world.tick(delta)
		if urban_buses!=null:
			urban_buses.tick(delta)
		if monte_services!=null:
			monte_services.tick(delta)
		if monte_pedestrians!=null:
			monte_pedestrians.tick(delta)
		if interact_requested:
			taxis.request_stop()
		interact_requested = false
		taxis.tick(delta,cuba_world.cuba_clock,control_pressed(KEY_SHIFT) and gameplay_input())
		var taxi: CharacterBody3D = taxis.passenger.body
		player.global_position = taxi.global_position+Vector3.UP*.8
		if taxis.ready_to_exit():
			taxi_exit_retry -= delta
			if taxi_exit_retry<=0.0:
				taxi_exit_retry = .35
				if _leave_taxi():
					return
				taxis.ride_status = "Taxi detenido. Buscando un lugar libre para bajar. R: regresar a casa."
		hud_time += delta
		if hud_time>=.15:
			hud_time=0.0
			_update_hud()
		return
	if context_requested:
		context_requested = false
		if not driving and not building_mode and pilar_editor != null:
			var origin := play_camera.global_position
			var direction := -play_camera.global_transform.basis.z
			var ray := PhysicsRayQueryParameters3D.create(origin,origin+direction*80.0,1|2|4|16)
			ray.exclude = [player.get_rid()]
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			var target: Vector3 = hit.position+direction*.10 if not hit.is_empty() else player.global_position+direction*6.0
			_open_pilar_editor(target,true)
	if building_mode:
		if pilar_editor != null and pilar_editor.active:
			pilar_editor.tick(delta)
			return
		if builder.active:
			builder.tick(delta)
			return
		building_mode = false
		play_camera.current = true
		status.show()
		_apply_camera_mode()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		interact_requested = false
		reset_requested = false
	_tick_outdoor_free_play(delta)
	if van != null and not van_ground_initialized:
		if _support_van():
			van_home = van.global_transform
			van_ground_initialized = true
	if reset_requested:
		reset_requested = false
		_reset_player()
	if cargo_requested:
		cargo_requested = false
		if backpack!=null and not backpack.empty_hands():
			business._notify("Guarda o deja el objeto que llevas en la mano con I.")
		elif business!=null and not driving and not taxi_riding and not building_mode and (monte_services==null or monte_services.player_bag==null):
			business.cargo_action(player.global_position)
			_update_hud()
	if interact_requested:
		interact_requested = false
		if driving:
			if absf(drive_speed) > 0.7:
				exit_message = "Deten la van antes de bajar."
				message_time = 2.0
			elif not _safe_exit():
				exit_message = "No hay espacio para salir. Mueve la van."
				message_time = 2.0
		elif adaptation_mode and garage!=null and (garage.rental_entry_near(player.global_position) or (garage.inside and garage.action_text(player.global_position).begins_with("[E]"))):
			garage.interact(player.global_position)
			player.velocity = Vector3.ZERO
			_update_hud()
			return
		elif not adaptation_mode and business!=null and business.first_story!=null and business.first_story.interact():
			player.velocity = Vector3.ZERO
			_update_hud()
			return
		elif not adaptation_mode and business!=null and business.first_story!=null and business.first_story.carrying_table():
			return
		elif not adaptation_mode and yordi_mission!=null and yordi_mission.interact():
			player.velocity = Vector3.ZERO
			_update_hud()
			return
		elif carlos_mission!=null and carlos_mission.interact():
			player.velocity = Vector3.ZERO
			_update_hud()
			return
		elif backpack!=null and backpack.interact():
			player.velocity = Vector3.ZERO
			return
		elif not _albertico_action().is_empty():
			if business.interact_albertico(player.global_position):
				player.velocity = Vector3.ZERO
				_update_hud()
				return
		elif garage!=null and garage.interact(player.global_position):
			player.velocity = Vector3.ZERO
			_update_hud()
			return
		elif business!=null and business.life!=null and not business.life.state.meal.is_empty():
			business.life.interact(player.global_position)
			return
		elif garage!=null and (not String(garage.state.held_furniture).is_empty() or not String(garage.state.part).is_empty()) and business!=null and not business.aimed_text(player.global_position).is_empty():
			business._notify("Primero deja el mueble o la pieza en casa.")
			return
		elif backpack!=null and not backpack.empty_hands() and not (street_market!=null and not street_market.action_text().is_empty()):
			business._notify("Usa I para guardar, usar o dejar el objeto que llevas en la mano.")
			return
		elif street_market!=null and street_market.interact():
			player.velocity = Vector3.ZERO
			return
		elif business!=null and business.take_aimed(player.global_position):
			_update_hud()
			return
		elif business!=null and business.life!=null and (garage==null or (String(garage.state.part).is_empty() and String(garage.state.held_furniture).is_empty())) and (monte_services==null or monte_services.player_bag==null) and business.life.interact(player.global_position):
			player.velocity = Vector3.ZERO
			return
		elif _greet_person():
			return
		elif urban_buses!=null and not urban_buses.nearby_boarding(player.global_position).is_empty() and (business==null or business.ledger.carry.is_empty()) and (monte_services==null or monte_services.player_bag==null):
			if _start_bus_ride(urban_buses.nearby_boarding(player.global_position)): return
		elif monte_services!=null and (business==null or business.ledger.carry.is_empty()) and monte_services.interact(player.global_position):
			player.velocity = Vector3.ZERO
			return
		elif monte_services!=null and monte_services.player_bag!=null:
			exit_message = "Entrega la bolsa al camión antes de hacer otra actividad."
			message_time = 2.0
		elif business!=null and business.interact(player.global_position):
			player.velocity = Vector3.ZERO
			return
		elif cuba_world != null and cuba_world.inspect_product(play_camera,player):
			pass
		elif city_world != null and city_world.interact(player,avatar,limb_legs,limb_arms):
			player_shape.set_deferred("disabled",city_world.seated)
			_apply_camera_mode()
		elif taxis != null and taxis.open_dialog(player.global_position):
			player.velocity = Vector3.ZERO
			return
		elif _near_van():
			_enter_van()
	if garage!=null and not garage.bath_mode.is_empty():
		player.velocity = Vector3.ZERO
		message_time = maxf(0.0,message_time-delta)
		_update_hud()
		return
	if garage!=null and garage.dining_seated:
		player.velocity = Vector3.ZERO
		if gameplay_input() and control_pressed(KEY_SPACE): garage._stand_from_dining()
		if business!=null and business.life!=null: business.life.pose_meal(first_person,delta)
		message_time = maxf(0.0,message_time-delta)
		_update_hud()
		return
	if city_world != null and city_world.seated:
		message_time = maxf(0.0,message_time-delta)
		_update_hud()
		return
	var movement := _read_controls()
	if driving:
		_drive(delta, movement)
	else:
		var direction := Vector3(movement.x, 0, movement.y).normalized().rotated(Vector3.UP, yaw)
		var speed: float = 8.0 if control_pressed(KEY_SHIFT) else 4.5
		# Fatigue affects sprinting gently, never forces a sleep or blocks walking.
		if adaptation_mode and control_pressed(KEY_SHIFT) and business!=null and business.life!=null:
			var tired: float = float(business.life.state.get("fatigue",0.0))
			speed *= lerpf(1.0,.78,smoothstep(70.0,100.0,tired))
		if business!=null and business.first_story!=null and business.first_story.carrying_table(): speed = 2.1
		if city_world != null and city_world.family_home != null and city_world.family_home.pool_inside:
			speed = 2.0
		player.velocity.x = direction.x * speed
		player.velocity.z = direction.z * speed
		if direction.length_squared() > 0.01:
			avatar.rotation.y = lerp_angle(avatar.rotation.y, atan2(direction.x, direction.z), minf(delta * 13.0, 1.0))
		if not player.is_on_floor():
			player.velocity.y -= 18.0 * delta
		elif gameplay_input() and control_pressed(KEY_SPACE):
			player.velocity.y = 5.5
		player.move_and_slide()
		if not first_person:
			_animate_avatar(delta, Vector2(player.velocity.x, player.velocity.z).length())
		if business!=null and business.life!=null: business.life.pose_meal(first_person,delta)
		if player.global_position.y < -15 or absf(player.global_position.x) > (1255.0 if cuba_world != null else (258.0 if native_city else 90.0)) or absf(player.global_position.z) > (1255.0 if cuba_world != null else (258.0 if native_city else 120.0)):
			_reset_player()
		# Parked vehicle stays grounded; no dynamic vertical collision recovery.
		if not adaptation_mode and van != null and (cuba_world == null or not van_ground_initialized):
			_support_van()
	message_time = maxf(0.0, message_time - delta)
	hud_time += delta
	if hud_time>=.12:
		hud_time = 0.0
		_update_hud()
