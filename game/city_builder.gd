extends Node3D
# Local sandbox construction. Independent of the Blender source scene.
const GRID := 8.0
const ROAD_STEP := 0.25
const ROAD_N := 33
const ROAD_LIFT := 0.18
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
	# Load when physics queries are available, not during _ready.
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	set_physics_process(false)
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
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + dir * 300.0, 2 | 8)
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
	var out := {"ok": false, "y": y, "bottom": low - 0.08, "reason": "", "road_heights": []}
	# Reserve original boulevard, houses, lake and park (Blender Y maps to -Z).
	if absf(x) < 7.0 or (x > 0 and x < 15 and absf(z) < 22) or (x < -22 and x > -60 and z < -61 and z > -103):
		out.reason = "Zona original protegida"
		return out
	if pieces.size() >= LIMIT:
		out.reason = "Limite de 300 piezas"
		return out
	var road := selected == "road" or selected == "cross"
	if not road and high - low > 2.0:
		out.reason = "Terreno demasiado inclinado"
		return out
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(7.7, 5.2, 7.7)
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, Vector3(x, y + 2.8, z))
	query.collision_mask = 1 | 4
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		out.reason = "Hay un objeto en ese lugar"
		return out
	if road:
		# Shared 2 m sample coordinates mean adjacent new tiles meet at
		# exactly the same elevation, regardless of placement order.
		var samples: Array = []
		for j in range(5):
			for i in range(5):
				var xx := x - 4.0 + i * 2.0
				var zz := z - 4.0 + j * 2.0
				var surface := _hit_ground(xx, zz)
				if surface.is_empty():
					out.reason = "No hay suelo bajo la calle"
					return out
				var h := float(surface.position.y) + ROAD_LIFT
				samples.append(h)
		for j in range(5):
			for i in range(5):
				var h := float(samples[j*5+i])
				if (i > 0 and absf(h - float(samples[j*5+i-1])) > 1.7) or (j > 0 and absf(h - float(samples[(j-1)*5+i])) > 1.7):
					out.reason = "Pendiente extrema: elige una zona mas suave"
					return out
		out.y = float(samples[12])
		out.bottom = float(samples.min()) - 0.08
		out.road_heights = samples
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
				if _add_piece(selected, cell.x, cell.y, float(result.y), float(result.bottom), rotation_step, result.get("road_heights", [])):
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

# Dense height sampling only on confirmed placement or when restoring a save.
# All neighbouring road tiles share the same world coordinates along their edges.
func _dense_road_samples(grid_x: int, grid_z: int) -> Array:
	var samples: Array = []
	for j in range(ROAD_N):
		for i in range(ROAD_N):
			var x: float = grid_x * GRID - 4.0 + i * ROAD_STEP
			var z: float = grid_z * GRID - 4.0 + j * ROAD_STEP
			var hit := _hit_ground(x, z)
			if hit.is_empty():
				return []
			samples.append(float(hit.position.y) + ROAD_LIFT)
	return samples

func _road_height(samples: Array, x: float, z: float) -> float:
	var n: int = ROAD_N if samples.size() == ROAD_N * ROAD_N else 5
	var step: float = GRID / float(n - 1)
	var gx := clampf((x + 4.0) / step, 0.0, float(n-1))
	var gz := clampf((z + 4.0) / step, 0.0, float(n-1))
	var i := mini(int(floor(gx)), n-2)
	var j := mini(int(floor(gz)), n-2)
	var u := gx - i
	var v := gz - j
	var a := float(samples[j*n+i])
	var b := float(samples[j*n+i+1])
	var c := float(samples[(j+1)*n+i])
	var d := float(samples[(j+1)*n+i+1])
	if u+v <= 1.0:
		return a + u*(b-a) + v*(c-a)
	return d + (1.0-u)*(c-d) + (1.0-v)*(b-d)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for p in [a,b,c,b,d,c]:
		st.add_vertex(p)

func _paint_strip(st: SurfaceTool, samples: Array, base_y: float, center: Vector2, width: float, length: float, angle: float) -> void:
	var segments := maxi(1, ceili(length / ROAD_STEP))
	for i in range(segments):
		var start: float = -length * 0.5 + length * float(i) / segments
		var finish: float = -length * 0.5 + length * float(i+1) / segments
		var corners: Array[Vector3] = []
		for p in [Vector2(-width/2,start),Vector2(width/2,start),Vector2(-width/2,finish),Vector2(width/2,finish)]:
			var point: Vector2 = (center + p).rotated(-angle)
			corners.append(Vector3(point.x, _road_height(samples,point.x,point.y)-base_y+0.035,point.y))
		_quad(st,corners[0],corners[1],corners[2],corners[3])

func _road_mesh(parent: Node3D, samples: Array, base_y: float, grid_x: int, grid_z: int, turn: int, kind: String) -> void:
	var road := Node3D.new()
	parent.add_child(road)
	road.rotation.y = -parent.rotation.y
	var n: int = ROAD_N if samples.size() == ROAD_N * ROAD_N else 5
	var step: float = GRID / float(n-1)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(n-1):
		for i in range(n-1):
			var x: float = -4.0 + i*step
			var z: float = -4.0 + j*step
			_quad(st, Vector3(x,float(samples[j*n+i])-base_y,z), Vector3(x+step,float(samples[j*n+i+1])-base_y,z), Vector3(x,float(samples[(j+1)*n+i])-base_y,z+step), Vector3(x+step,float(samples[(j+1)*n+i+1])-base_y,z+step))
	# Connector reaches the existing asphalt without forcing the inner road
	# edge underneath the natural terrain. Sample the ramp itself as well.
	if abs(grid_x) == 1:
		var inner: float = -4.0 if grid_x > 0 else 4.0
		var outer: float = -5.0 if grid_x > 0 else 5.0
		for j in range(n-1):
			var z: float = -4.0 + j*step
			var h1 := _road_height(samples,inner,z)-base_y
			var h2 := _road_height(samples,inner,z+step)-base_y
			var p1 := _hit_ground(grid_x*GRID+outer,grid_z*GRID+z)
			var p2 := _hit_ground(grid_x*GRID+outer,grid_z*GRID+z+step)
			var o1: float = float(p1.position.y)+0.035-base_y if not p1.is_empty() else 0.035-base_y
			var o2: float = float(p2.position.y)+0.035-base_y if not p2.is_empty() else 0.035-base_y
			if grid_x > 0:
				_quad(st, Vector3(outer,o1,z),Vector3(inner,h1,z),Vector3(outer,o2,z+step),Vector3(inner,h2,z+step))
			else:
				_quad(st, Vector3(inner,h1,z),Vector3(outer,o1,z),Vector3(inner,h2,z+step),Vector3(outer,o2,z+step))
	st.index()
	st.generate_normals()
	var instance := MeshInstance3D.new()
	instance.mesh = st.commit()
	instance.material_override = _color("asphalt", Color(0.20,0.23,0.27))
	road.add_child(instance)
	instance.create_trimesh_collision()
	for child in instance.get_children():
		if child is StaticBody3D:
			(child as StaticBody3D).collision_layer = 8
			(child as StaticBody3D).collision_mask = 0
	var markings := SurfaceTool.new()
	markings.begin(Mesh.PRIMITIVE_TRIANGLES)
	if kind == "road":
		for pos in [-3.0,0.0,3.0]:
			_paint_strip(markings,samples,base_y,Vector2(0,float(pos)),0.12,1.3,turn*PI/2.0)
	else:
		for side in [-1.0,1.0]:
			for k in range(4):
				_paint_strip(markings,samples,base_y,Vector2(-1.5+k,float(side)*3.0),0.44,0.76,turn*PI/2.0)
	markings.index()
	markings.generate_normals()
	var paint := MeshInstance3D.new()
	paint.mesh = markings.commit()
	paint.material_override = _color("line",Color(0.96,0.78,0.15))
	road.add_child(paint)

func _add_piece(kind: String, x: int, z: int, y: float, bottom: float, turn: int, road_heights: Array = []) -> bool:
	var road: bool = kind in ["road","cross"]
	var dense: Array = []
	if road:
		dense = _dense_road_samples(x,z)
		if dense.size() != ROAD_N * ROAD_N:
			pending_message = "No se pudo ajustar la calle al terreno."
			message_timer = 3.0
			# Preserve existing saved roads with their old geometry if necessary.
			if road_heights.size() != 25:
				return false
			dense = road_heights
		else:
			y = float(dense[floori(float(ROAD_N * ROAD_N) / 2.0)])
			bottom = float(dense.min()) - 0.08
	var root := Node3D.new()
	root.name = "Built_" + kind + "_" + str(pieces.size())
	add_child(root)
	root.position = Vector3(x * GRID, y, z * GRID)
	root.rotation.y = turn * PI / 2.0
	if road:
		_road_mesh(root, dense, y, x, z, turn, kind)
	else:
		_make_model(root, kind, true, y-bottom)
	# Keep the compact old format; dense road meshes are regenerated on load.
	pieces[_key(x,z)] = {"kind": kind, "x": x, "z": z, "y": y, "bottom": bottom, "turn": turn, "road_heights": road_heights, "node": root}
	return true

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
		if abs(x) > 9 or abs(z) > 13 or not is_finite(y) or not is_finite(bottom) or absf(y) > 20 or y-bottom < 0 or (y-bottom > 3.0 and not kind in ["road","cross"]) or turn < 0 or turn > 3 or pieces.has(_key(x,z)):
			continue
		var samples: Array = []
		if raw.get("road_heights") is Array:
			var candidate: Array = raw.road_heights
			if candidate.size() == 25:
				var sane := true
				for h in candidate:
					if not (h is float or h is int) or not is_finite(float(h)) or absf(float(h)) > 20.0:
						sane = false
				if sane:
					samples = candidate
		_add_piece(kind, x, z, y, bottom, turn, samples)
