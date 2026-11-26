extends Node3D
# First playable local prototype. Static world, third-person movement.
const CITY_PATH = "res://city.glb"
const SPAWN = Vector3(-1.5, 1.0, 30.0)
var player: CharacterBody3D
var pivot: Node3D
var arm: SpringArm3D
var avatar: Node3D
var yaw := 0.0
var pitch := -0.20
var status: Label
var city_loaded := false

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
	if ResourceLoader.exists(CITY_PATH):
		var packed := load(CITY_PATH) as PackedScene
		if packed != null:
			var city := packed.instantiate()
			add_child(city)
			_add_world_collision(city)
			city_loaded = true
	if not city_loaded:
		_make_demo_floor()
	_make_player()
	_make_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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
		if solid and m.mesh != null and m.mesh.get_surface_count() > 0:
			m.create_trimesh_collision()
	for child in node.get_children():
		_add_world_collision(child)

func _make_demo_floor() -> void:
	var floor_body := StaticBody3D.new()
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
	player.floor_snap_length = 0.30
	var col := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.33
	capsule.height = 1.6
	col.shape = capsule
	player.add_child(col)
	avatar = Node3D.new()
	player.add_child(avatar)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.32
	body_mesh.height = 1.25
	body.mesh = body_mesh
	var blue := StandardMaterial3D.new()
	blue.albedo_color = Color(0.12, 0.48, 0.93)
	body.material_override = blue
	body.position.y = -0.12
	avatar.add_child(body)
	var head := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.26
	sphere.height = 0.52
	head.mesh = sphere
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.92, 0.70, 0.48)
	head.material_override = skin
	head.position.y = 0.59
	avatar.add_child(head)
	pivot = Node3D.new()
	pivot.position.y = 0.65
	player.add_child(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 4.5
	arm.margin = 0.15
	pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.fov = 68.0
	cam.far = 350.0
	arm.add_child(cam)
	add_child(player)
	player.position = SPAWN
	arm.add_excluded_object(player.get_rid())
	cam.current = true
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
	var title := "VALDY JR TV | Explora tu ciudad"
	if not city_loaded:
		title = "MODO DE PRUEBA | Exporta city.glb desde Blender"
	status.text = title + "\nWASD / flechas: caminar | Mouse: mirar | Espacio: saltar\nShift: correr | R: regresar | Esc: liberar mouse"
	canvas.add_child(status)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_R and player != null:
			_reset_player()
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and pivot != null:
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -1.05, 0.35)
		pivot.rotation = Vector3(pitch, yaw, 0)

func _reset_player() -> void:
	player.global_position = SPAWN
	player.velocity = Vector3.ZERO

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var input := Vector2.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			input.y -= 1
		if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			input.y += 1
		if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			input.x -= 1
		if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			input.x += 1
	var direction := Vector3(input.x, 0, input.y).normalized().rotated(Vector3.UP, yaw)
	var speed := 8.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 4.5
	player.velocity.x = direction.x * speed
	player.velocity.z = direction.z * speed
	if direction.length_squared() > 0.01:
		avatar.rotation.y = atan2(direction.x, direction.z)
	if not player.is_on_floor():
		player.velocity.y -= 18.0 * delta
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_physical_key_pressed(KEY_SPACE):
		player.velocity.y = 5.5
	player.move_and_slide()
	if player.global_position.y < -15 or absf(player.global_position.x) > 90 or absf(player.global_position.z) > 120:
		_reset_player()
