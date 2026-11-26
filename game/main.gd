extends Node3D
# First playable local prototype. Static world, third-person movement.
const CITY_PATH = "res://city.glb"
const CityBuilder = preload("res://city_builder.gd")
const CityWorld = preload("res://city_world.gd")
const CubaWorld = preload("res://cuba_world.gd")
var cuba_world: CubaWorld
var first_person := false
var reticle: Label
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
var player_shape: CollisionShape3D
var van_home := Transform3D.IDENTITY
var van_ground_initialized := false
const GROUND_LAYER = 2
const VAN_LAYER = 4
var exit_message := ""
var message_time := 0.0

func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.81, 0.95)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.78, 0.85, 0.95)
	env.ambient_light_energy = 0.70
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	add_child(sun)
	var args := OS.get_cmdline_user_args()
	native_city = not args.has("--legacy-city")
	if native_city and not args.has("--classic-city") and FileAccess.file_exists("res://pilar_atares.osm"):
		var candidate := CubaWorld.new()
		if candidate.load_map():
			cuba_world = candidate
		else:
			candidate.free()
			push_warning("Mapa OSM invalido; se conserva Ciudad 2.0.")
	builder = CityBuilder.new()
	builder.native_city = native_city
	if native_city:
		builder.save_path = "user://pilar_atares_buildings.json" if cuba_world != null else "user://mycity_v2_buildings.json"
	add_child(builder)
	if native_city:
		city_world = cuba_world if cuba_world != null else CityWorld.new()
		add_child(city_world)
		city_world.setup(builder)
		spawn_position = cuba_world.home_spawn if cuba_world != null else CityWorld.HOME_OUT
		_restore_original_vehicles()
		if van == null:
			_make_demo_van()
			push_warning("MyCity: van original no disponible; exporta city.glb desde Blender.")
		van.global_position = cuba_world.van_spawn if cuba_world != null else CityWorld.VAN_PARK + Vector3.UP * .055
		if cuba_world != null:
			van.rotation.y = cuba_world.van_angle
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
		first_person = true
		_apply_camera_mode()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
	cam.far = 800.0
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
	status.add_theme_font_size_override("font_size", 19)
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
	_update_hud()

func _apply_camera_mode() -> void:
	if player == null or arm == null:
		return
	if driving:
		arm.spring_length = 7.5
		avatar.hide()
	else:
		avatar.visible = not first_person
		arm.spring_length = 0.0 if first_person else (2.15 if city_world != null and (city_world.inside_home or (city_world.bakery != null and city_world.bakery.inside) or (cuba_world != null and cuba_world.current_room>=0)) else 4.5)
		pivot.position.y = .65
	if reticle != null:
		reticle.visible = first_person and not driving and not building_mode

func _unhandled_input(event: InputEvent) -> void:
	if builder != null and builder.active:
		builder.handle(event)
		return
	if building_mode:
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		if cuba_world != null:
			exit_message = "Editor de Pilar-Atarés pendiente; las calles reales estan protegidas."
			message_time = 3.0
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
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_V and player != null and not driving:
			first_person = not first_person
			_apply_camera_mode()
		elif event.keycode == KEY_R and player != null:
			reset_requested = true
		elif event.keycode == KEY_E and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			interact_requested = true
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and pivot != null:
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -1.05, 0.35)
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
	return car

# Reuse only the two original vehicles; do not attach the old city permanently.
func _restore_original_vehicles() -> void:
	if not ResourceLoader.exists(CITY_PATH):
		push_warning("MyCity: falta game/city.glb. Exporta la ciudad original desde Blender.")
		return
	var packed := load(CITY_PATH) as PackedScene
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
	van = _new_van_body(original_transform.origin)
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
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	var instance := MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
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
	_sphere(avatar, "Head", Vector3(0, 0.53, 0), Vector3(0.52, 0.55, 0.48), skin)
	_sphere(avatar, "Hair", Vector3(0, 0.73, -0.045), Vector3(0.53, 0.26, 0.49), hair)
	for side in [-1, 1]:
		_sphere(avatar, "Ear", Vector3(side * 0.25, 0.53, 0), Vector3(0.10, 0.14, 0.11), skin)
		_sphere(avatar, "EyeWhite", Vector3(side * 0.105, 0.57, 0.212), Vector3(0.115, 0.14, 0.075), eye_white)
		_sphere(avatar, "Eye", Vector3(side * 0.105, 0.57, 0.245), Vector3(0.053, 0.078, 0.035), eye)
		var shoulder := Node3D.new()
		avatar.add_child(shoulder)
		shoulder.position = Vector3(side * 0.32, 0.21, 0)
		limb_arms.append(shoulder)
		_sphere(shoulder, "Sleeve", Vector3(0, -0.10, 0), Vector3(0.20, 0.24, 0.22), shirt)
		_sphere(shoulder, "Arm", Vector3(0, -0.30, 0), Vector3(0.13, 0.33, 0.15), skin)
		_sphere(shoulder, "Hand", Vector3(0, -0.46, 0), Vector3(0.17, 0.18, 0.16), skin)
		var hip := Node3D.new()
		avatar.add_child(hip)
		hip.position = Vector3(side * 0.13, -0.23, 0)
		limb_legs.append(hip)
		_sphere(hip, "Leg", Vector3(0, -0.23, 0), Vector3(0.22, 0.48, 0.23), jeans)
		_sphere(hip, "Shoe", Vector3(0, -0.46, 0.075), Vector3(0.24, 0.18, 0.36), shoes)
	_sphere(avatar, "Nose", Vector3(0, 0.48, 0.247), Vector3(0.09, 0.10, 0.09), skin)

func _animate_avatar(delta: float, speed: float) -> void:
	var moving := speed > 0.1 and player.is_on_floor()
	var strength := 0.68 if speed < 6.0 else 0.95
	if moving:
		step_phase += delta * (6.5 + speed * 0.8)
	for i in range(limb_legs.size()):
		var swing := sin(step_phase + i * PI) * strength if moving else 0.0
		if not player.is_on_floor():
			swing = -0.25 if i == 0 else 0.35
		limb_legs[i].rotation.x = lerpf(limb_legs[i].rotation.x, swing, minf(delta * 12.0, 1.0))
		limb_arms[i].rotation.x = lerpf(limb_arms[i].rotation.x, -swing * 0.85, minf(delta * 12.0, 1.0))
	avatar.position.y = lerpf(avatar.position.y, absf(sin(step_phase)) * 0.045 if moving else 0.0, minf(delta * 12.0, 1.0))

func _near_van() -> bool:
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

func _reset_player() -> void:
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

func _read_controls() -> Vector2:
	var movement := Vector2.ZERO
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return movement
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		movement.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		movement.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		movement.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		movement.x += 1
	return movement

func _drive(delta: float, movement: Vector2) -> void:
	var target := -movement.y * (13.0 if movement.y <= 0 else 4.0)
	var brake := Input.is_physical_key_pressed(KEY_SPACE) or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED
	if brake:
		target = 0.0
	drive_speed = move_toward(drive_speed, target, delta * (14.0 if brake else 5.0))
	if absf(drive_speed) > 0.15:
		van.rotation.y -= movement.x * signf(drive_speed) * delta * 1.35 * minf(absf(drive_speed) / 3.0, 1.0)
	var prior := van.global_transform
	var forward := van.global_transform.basis.z.normalized()
	van.velocity.x = forward.x * drive_speed
	van.velocity.z = forward.z * drive_speed
	van.velocity.y = 0.0
	van.move_and_slide()
	if not _support_van():
		van.global_transform = prior
		van.velocity = Vector3.ZERO
		drive_speed = 0.0
	if van.get_slide_collision_count() > 0:
		drive_speed *= 0.35
	if van.global_position.y < -8.0 or absf(van.global_position.x) > (610.0 if cuba_world != null else (253.0 if native_city else 79.0)) or absf(van.global_position.z) > (610.0 if cuba_world != null else (253.0 if native_city else 109.0)):
		van.global_transform = van_home
		van.velocity = Vector3.ZERO
		drive_speed = 0.0

func _update_hud() -> void:
	if status == null:
		return
	var title := "PILAR-ATARÉS | La Habana" if cuba_world != null else ("VALDY JR TV | Ciudad 2.0" if native_city else "VALDY JR TV | Ciudad original")
	if not city_loaded:
		title = "MODO DE PRUEBA | Exporta city.glb desde Blender"
	if driving:
		status.text = title + "\nCONDUCIENDO | %d km/h" % roundi(absf(drive_speed) * 3.6)
		status.text += "\nW/S: acelerar y retroceder | A/D: girar | Espacio: frenar\nE: salir detenido | R: reiniciar | Esc: liberar mouse"
	else:
		status.text = title + "\nWASD / flechas: caminar | Mouse: mirar | Espacio: saltar\nShift: correr | R: regresar | Esc: liberar mouse"
		var action := city_world.interaction_text(player.global_position) if city_world != null else ""
		if action != "":
			status.text += "\n" + action
		elif cuba_world != null and not cuba_world.aimed_text(play_camera,player).is_empty():
			status.text += "\n"+cuba_world.aimed_text(play_camera,player)
		elif _near_van():
			status.text += "\n[E] Subir a la van"
		elif van == null:
			status.text += "\nVan no encontrada en la exportacion."
	if not driving:
		status.text += "\n[V] Primera / tercera persona"
		if cuba_world == null:
			status.text += " | [B] Construir ciudad"
	if cuba_world != null:
		status.text += "\n© OpenStreetMap contributors | ODbL | openstreetmap.org/copyright"
		if cuba_world.prompt_time > 0.0:
			status.text += "\n"+cuba_world.prompt
	if message_time > 0.0:
		status.text += "\n" + exit_message

func _physics_process(delta: float) -> void:
	if player == null:
		return
	if building_mode:
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
	if city_world != null:
		city_world.tick(delta)
	if van != null and not van_ground_initialized:
		if _support_van():
			van_home = van.global_transform
			van_ground_initialized = true
	if reset_requested:
		reset_requested = false
		_reset_player()
	if interact_requested:
		interact_requested = false
		if driving:
			if absf(drive_speed) > 0.7:
				exit_message = "Deten la van antes de bajar."
				message_time = 2.0
			elif not _safe_exit():
				exit_message = "No hay espacio para salir. Mueve la van."
				message_time = 2.0
		elif cuba_world != null and cuba_world.inspect_product(play_camera,player):
			pass
		elif city_world != null and city_world.interact(player,avatar,limb_legs,limb_arms):
			player_shape.set_deferred("disabled",city_world.seated)
			_apply_camera_mode()
		elif _near_van():
			_enter_van()
	if city_world != null and city_world.seated:
		message_time = maxf(0.0,message_time-delta)
		_update_hud()
		return
	var movement := _read_controls()
	if driving:
		_drive(delta, movement)
	else:
		var direction := Vector3(movement.x, 0, movement.y).normalized().rotated(Vector3.UP, yaw)
		var speed: float = 8.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 4.5
		if city_world != null and city_world.family_home != null and city_world.family_home.pool_inside:
			speed = 2.0
		player.velocity.x = direction.x * speed
		player.velocity.z = direction.z * speed
		if direction.length_squared() > 0.01:
			avatar.rotation.y = lerp_angle(avatar.rotation.y, atan2(direction.x, direction.z), minf(delta * 13.0, 1.0))
		if not player.is_on_floor():
			player.velocity.y -= 18.0 * delta
		elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_physical_key_pressed(KEY_SPACE):
			player.velocity.y = 5.5
		player.move_and_slide()
		_animate_avatar(delta, Vector2(player.velocity.x, player.velocity.z).length())
		if player.global_position.y < -15 or absf(player.global_position.x) > (615.0 if cuba_world != null else (258.0 if native_city else 90.0)) or absf(player.global_position.z) > (615.0 if cuba_world != null else (258.0 if native_city else 120.0)):
			_reset_player()
		# Parked vehicle stays grounded; no dynamic vertical collision recovery.
		if van != null:
			_support_van()
	message_time = maxf(0.0, message_time - delta)
	_update_hud()
