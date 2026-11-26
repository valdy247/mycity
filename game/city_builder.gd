extends Node3D
# Local sandbox construction. Independent of the Blender source scene.
const GRID := 8.0
const LIMIT := 300
const SAVE_PATH := "user://mycity_buildings_v1.json"
const TYPES := ["road", "cross", "house", "shop", "school", "park"]
const LABELS := ["Calle", "Cruce", "Casa", "Tienda", "Escuela", "Parque"]
var active := false
var selected := "road"
var rotation_step := 0
var camera: Camera3D
var panel: Control
var hint: Label
var preview: Node3D
var indicator: MeshInstance3D
var valid_mat: StandardMaterial3D
var invalid_mat: StandardMaterial3D
var pieces: Dictionary = {}
var materials: Dictionary = {}
var focus := Vector3.ZERO
var requested := ""
var pending_message := ""
var message_timer := 0.0

func _ready() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 55.0
	camera.far = 350.0
	add_child(camera)
	valid_mat = _color("valid", Color(0.18, 0.9, 0.42, 0.45), true)
	invalid_mat = _color("invalid", Color(0.95, 0.18, 0.20, 0.48), true)
	_make_ui()
	_load_city()

func _color(key: String, color: Color, transparent: bool = false) -> StandardMaterial3D:
	if materials.has(key):
		return materials[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	if transparent:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	materials[key] = mat
	return mat

func _box(parent: Node3D, p: Vector3, size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var ob := MeshInstance3D.new()
	ob.mesh = mesh
	ob.material_override = mat
	parent.add_child(ob)
	ob.position = p
	return ob

func _make_ui() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 5
	add_child(canvas)
	var root := PanelContainer.new()
	root.position = Vector2(14, 14)
	root.custom_minimum_size = Vector2(300, 0)
	canvas.add_child(root)
	panel = root
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	root.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var title := Label.new()
	title.text = "MODO CONSTRUCCION"
	title.add_theme_font_size_override("font_size", 21)
	column.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for i in range(TYPES.size()):
		var button := Button.new()
		button.text = LABELS[i]
		button.custom_minimum_size = Vector2(130, 38)
		button.pressed.connect(_choose.bind(TYPES[i]))
		grid.add_child(button)
	var rotate := Button.new()
	rotate.text = "Girar 90 grados (Q)"
	rotate.pressed.connect(_rotate)
	column.add_child(rotate)
	var remove := Button.new()
	remove.text = "Eliminar pieza (X)"
	remove.pressed.connect(_choose.bind("delete"))
	column.add_child(remove)
	var done := Button.new()
	done.text = "Volver a jugar (B)"
	done.pressed.connect(close)
	column.add_child(done)
	hint = Label.new()
	hint.custom_minimum_size = Vector2(280, 0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	panel.hide()

func open(at: Vector3) -> void:
	if active:
		return
	active = true
	focus = Vector3(at.x, 0, at.z)
	camera.size = 55.0
	_update_camera()
	camera.current = true
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_choose(selected)

func close() -> void:
	if not active:
		return
	active = false
	panel.hide()
	if preview != null:
		preview.hide()
	# Main scene restores its player camera in the next physics frame.
	requested = ""
	_save_city()

func _choose(kind: String) -> void:
	selected = kind
	if is_instance_valid(preview):
		remove_child(preview)
		preview.queue_free()
	preview = Node3D.new()
	add_child(preview)
	if kind != "delete":
		_make_model(preview, kind, false, 0.0)
	indicator = _box(preview, Vector3(0, 0.08, 0), Vector3(7.95, 0.035, 7.95), valid_mat)
	preview.hide()

func _rotate() -> void:
	rotation_step = (rotation_step + 1) % 4

func handle(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B, KEY_ESCAPE: close()
			KEY_Q, KEY_E: _rotate()
			KEY_X: _choose("delete")
			KEY_1: _choose("road")
			KEY_2: _choose("cross")
			KEY_3: _choose("house")
			KEY_4: _choose("shop")
			KEY_5: _choose("school")
			KEY_6: _choose("park")
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			requested = "place"
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			requested = "delete"
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera.size = maxf(22.0, camera.size - 6.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera.size = minf(115.0, camera.size + 6.0)

func _update_camera() -> void:
	camera.position = focus + Vector3(0, 48, 34)
	camera.look_at(focus, Vector3.UP)

func _key(x: int, z: int) -> String:
	return "%d:%d" % [x, z]

func _hit_ground(x: float, z: float) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(Vector3(x, 100, z), Vector3(x, -100, z), 2)
	ray.hit_back_faces = true
	return get_world_3d().direct_space_state.intersect_ray(ray)

func _cell() -> Vector2i:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var dir := camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP, 0.0)
	var intersection: Variant = plane.intersects_ray(origin, dir)
	if intersection == null:
		return Vector2i(999, 999)
	# Prefer actual terrain hit to the mathematical ground plane.
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + dir * 300.0, 2)
	ray.hit_back_faces = true
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var p: Vector3 = hit.position if not hit.is_empty() else intersection
	return Vector2i(roundi(p.x / GRID), roundi(p.z / GRID))

func _assessment(cell: Vector2i) -> Dictionary:
	var x := cell.x * GRID
	var z := cell.y * GRID
	var key := _key(cell.x, cell.y)
	if selected == "delete":
		return {"ok": pieces.has(key), "y": float(pieces[key]["y"]) if pieces.has(key) else 0.0, "reason": "Eliminar pieza" if pieces.has(key) else "Solo puedes borrar tus construcciones"}
	if absf(x) > 72.0 or absf(z) > 104.0:
		return {"ok": false, "y": 0.0, "reason": "Fuera de la ciudad"}
	if pieces.has(key):
		return {"ok": false, "y": float(pieces[key]["y"]), "reason": "Casilla ocupada"}
	var heights: Array[float] = []
	for dx in [-3.7, 0.0, 3.7]:
		for dz in [-3.7, 0.0, 3.7]:
			var hit := _hit_ground(x + dx, z + dz)
			if hit.is_empty():
				return {"ok": false, "y": 0.0, "reason": "No hay suelo"}
			heights.append(float(hit.position.y))
	var high: float = heights.max()
	var low: float = heights.min()
	var y := high + 0.035
	var out := {"ok": false, "y": y, "bottom": low - 0.08, "reason": ""}
	# Reserve original boulevard, houses, lake and park (Blender Y maps to -Z).
	if absf(x) < 7.0 or (x > 0 and x < 15 and absf(z) < 22) or (x < -22 and x > -60 and z < -61 and z > -103):
		out.reason = "Zona original protegida"
		return out
	if pieces.size() >= LIMIT:
		out.reason = "Limite de 300 piezas"
		return out
	var road := selected == "road" or selected == "cross"
	if high - low > (0.65 if road else 2.0):
		out.reason = "Terreno demasiado inclinado"
		return out
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.7, 5.2, 7.7)
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + 2.55, z))
	query.collision_mask = 1 | 4
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		out.reason = "Hay un objeto en ese lugar"
		return out
	if road:
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var other_key := _key(cell.x + offset.x, cell.y + offset.y)
			if pieces.has(other_key):
				var other: Dictionary = pieces[other_key]
				if String(other.kind) in ["road", "cross"] and absf(float(other.y) - y) > 0.28:
					out.reason = "Desnivel con la calle vecina"
					return out
	out.ok = true
	out.reason = "Listo para construir"
	return out

func tick(delta: float) -> void:
	if not active:
		return
	var move := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): move.z -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): move.z += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): move.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): move.x += 1
	focus += move.normalized() * camera.size * delta * 0.65
	focus.x = clampf(focus.x, -78.0, 78.0)
	focus.z = clampf(focus.z, -108.0, 108.0)
	_update_camera()
	var cell := _cell()
	var result := _assessment(cell)
	preview.visible = abs(cell.x) < 100 and abs(cell.y) < 100 and not panel.get_global_rect().has_point(get_viewport().get_mouse_position())
	preview.position = Vector3(cell.x * GRID, float(result.y), cell.y * GRID)
	preview.rotation.y = rotation_step * PI / 2.0
	indicator.material_override = valid_mat if result.ok else invalid_mat
	if requested != "":
		if preview.visible:
			var key := _key(cell.x, cell.y)
			if requested == "delete" or selected == "delete":
				if pieces.has(key):
					_delete(key)
			elif result.ok:
				_add_piece(selected, cell.x, cell.y, float(result.y), float(result.bottom), rotation_step)
				_save_city()
		requested = ""
	message_timer = maxf(0.0, message_timer - delta)
	var name_index := TYPES.find(selected)
	var label: String = LABELS[name_index] if name_index >= 0 else "Eliminar"
	hint.text = "%s | %d/%d piezas\n%s\nWASD: mover vista | Rueda: zoom\nClic: colocar | Clic derecho: borrar\nQ/E: girar | B: volver" % [label, pieces.size(), LIMIT, result.reason]
	if message_timer > 0:
		hint.text += "\n" + pending_message

func _make_model(root: Node3D, kind: String, physical: bool, foundation: float) -> void:
	var asphalt := _color("asphalt", Color(0.20, 0.23, 0.27))
	var line := _color("line", Color(0.96, 0.78, 0.15))
	var grass := _color("grass", Color(0.32, 0.62, 0.19))
	var concrete := _color("concrete", Color(0.65, 0.65, 0.60))
	var white := _color("white", Color(0.94, 0.85, 0.66))
	var roof := _color("roof", Color(0.65, 0.22, 0.13))
	var glass := _color("glass", Color(0.16, 0.38, 0.54))
	var wood := _color("wood", Color(0.34, 0.19, 0.08))
	var leaf := _color("leaf", Color(0.18, 0.48, 0.12))
	var road := kind in ["road", "cross"]
	var base_depth := maxf(0.12, foundation)
	_box(root, Vector3(0, -base_depth / 2.0, 0), Vector3(8, base_depth, 8), asphalt if road else concrete)
	if physical:
		_solid(root, Vector3(0, -base_depth / 2.0, 0), Vector3(8, base_depth, 8), 2)
	if road:
		if kind == "road":
			for z in [-3.0, 0.0, 3.0]:
				_box(root, Vector3(0, 0.012, z), Vector3(0.10, 0.024, 1.5), line)
		else:
			for side in [-1, 1]:
				for j in range(4):
					_box(root, Vector3(-1.5 + j, 0.014, side * 3.0), Vector3(0.45, 0.028, 0.85), concrete)
					_box(root, Vector3(side * 3.0, 0.014, -1.5 + j), Vector3(0.85, 0.028, 0.45), concrete)
		return
	_box(root, Vector3(0, 0.025, 0), Vector3(7.85, 0.05, 7.85), grass)
	if kind == "park":
		_box(root, Vector3(0, 0.06, 0), Vector3(1.2, 0.09, 7.6), concrete)
		_box(root, Vector3(0, 0.06, 0), Vector3(7.6, 0.09, 1.2), concrete)
		for x in [-2.6, 2.6]:
			for z in [-2.6, 2.6]:
				_box(root, Vector3(x, 0.9, z), Vector3(0.20, 1.8, 0.20), wood)
				var mesh := SphereMesh.new()
				mesh.radius = 0.86
				mesh.height = 1.72
				mesh.radial_segments = 10
				mesh.rings = 5
				var tree := MeshInstance3D.new()
				tree.mesh = mesh
				tree.material_override = leaf
				root.add_child(tree)
				tree.position = Vector3(x, 2.0, z)
		for x in [-1.8, 1.8]:
			_box(root, Vector3(x, 0.47, 0.9), Vector3(1.3, 0.12, 0.45), wood)
			_box(root, Vector3(x, 0.76, 1.13), Vector3(1.3, 0.42, 0.09), wood)
			for dx in [-0.48, 0.48]:
				_box(root, Vector3(x + dx, 0.24, 0.9), Vector3(0.10, 0.48, 0.38), concrete)
		return
	var width := 5.0 if kind == "house" else 6.5
	var depth := 4.8 if kind == "house" else 5.1
	var height := 3.0 if kind == "house" else 3.5 if kind == "shop" else 4.6
	var facade := white if kind == "house" else _color(kind, Color(0.78, 0.88, 0.93) if kind == "shop" else Color(0.91, 0.70, 0.38))
	_box(root, Vector3(0, height/2, 0), Vector3(width, height, depth), facade)
	if physical:
		_solid(root, Vector3(0, height/2, 0), Vector3(width, height, depth), 1)
	if kind == "house":
		for side in [-1, 1]:
			var slab := _box(root, Vector3(side * width * 0.25, height + 0.60, 0), Vector3(width * 0.61, 0.18, depth + 0.45), roof)
			slab.rotation.z = -side * 0.39
	else:
		_box(root, Vector3(0, height + 0.12, 0), Vector3(width + 0.35, 0.24, depth + 0.35), roof)
		_box(root, Vector3(0, height - 0.30, depth/2 + 0.20), Vector3(width + 0.12, 0.26, 0.5), roof)
	_box(root, Vector3(0, 0.99, depth/2 + 0.025), Vector3(0.9, 1.98, 0.08), wood)
	for x in [-width * 0.30, width * 0.30]:
		_box(root, Vector3(x, 1.58, depth/2 + 0.04), Vector3(1.2, 1.15, 0.09), glass)
		_box(root, Vector3(x, 1.58, depth/2 + 0.095), Vector3(0.065, 1.15, 0.045), white)
		if kind == "school":
			_box(root, Vector3(x, 3.52, depth/2 + 0.04), Vector3(1.3, 0.85, 0.08), glass)
	_box(root, Vector3(0, 0.06, 3.2), Vector3(1.15, 0.08, 1.5), concrete)

func _solid(root: Node3D, p: Vector3, size: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.collision_mask = 0
	root.add_child(body)
	body.position = p
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)

func _add_piece(kind: String, x: int, z: int, y: float, bottom: float, turn: int) -> void:
	var root := Node3D.new()
	root.name = "Built_" + kind + "_" + str(pieces.size())
	add_child(root)
	root.position = Vector3(x * GRID, y, z * GRID)
	root.rotation.y = turn * PI / 2.0
	_make_model(root, kind, true, y-bottom)
	pieces[_key(x,z)] = {"kind": kind, "x": x, "z": z, "y": y, "bottom": bottom, "turn": turn, "node": root}

func _delete(key: String) -> void:
	var root: Node3D = pieces[key]["node"]
	remove_child(root)
	root.queue_free()
	pieces.erase(key)
	_save_city()

func _save_city() -> void:
	var records: Array = []
	for value in pieces.values():
		var record: Dictionary = value.duplicate()
		record.erase("node")
		records.append(record)
	var file := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		pending_message = "No se pudo guardar."
		message_timer = 4.0
		return
	file.store_string(JSON.stringify({"version": 1, "pieces": records}))
	file.close()
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"), ProjectSettings.globalize_path(SAVE_PATH))
	pending_message = "Ciudad guardada" if err == OK else "Error al guardar la ciudad"
	message_timer = 2.0

func _load_city() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not data is Dictionary or int(data.get("version", 0)) != 1 or not data.get("pieces") is Array:
		return
	for raw in data.pieces:
		if pieces.size() >= LIMIT: break
		if not raw is Dictionary: continue
		var kind := String(raw.get("kind", ""))
		if not kind in TYPES: continue
		var x := int(raw.get("x", 999))
		var z := int(raw.get("z", 999))
		var y := float(raw.get("y", 999))
		var bottom := float(raw.get("bottom", 999))
		var turn := int(raw.get("turn", 0))
		if abs(x) > 9 or abs(z) > 13 or not is_finite(y) or not is_finite(bottom) or absf(y) > 20 or y-bottom < 0 or y-bottom > 3.0 or turn < 0 or turn > 3 or pieces.has(_key(x,z)):
			continue
		_add_piece(kind, x, z, y, bottom, turn)
