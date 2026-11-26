extends Node3D
# Local in-game world editor. OSM files remain read-only.
const World = preload("res://cuba_world.gd")
const SAVE := "user://pilar_atares_objects_v1.json"
const REF_DIR := "user://pilar_references"
var world: World
var active := false
var camera: Camera3D
var panel: PanelContainer
var hint: Label
var menu: PopupMenu
var file_dialog: FileDialog
var layer: CanvasLayer
var preview: MeshInstance3D
var outline_mat: StandardMaterial3D
var invalid_mat: StandardMaterial3D
var focus := Vector3.ZERO
var camera_size := 35.0
var view_mode := 0
var step_index := 1
var snaps: Array[float] = [.10,.50,1.0]
var records: Dictionary = {}
var objects: Dictionary = {}
var selected_id := ""
var selected_type := ""
var mode := ""
var kind := "Casa"
var angle := 0.0
var cursor_world := Vector3.ZERO
var click_world := Vector3.ZERO
var reference_id := ""
var ref_position := Vector3.ZERO
var measure_start := Vector3.ZERO
var measuring := false
var message := ""
var serial := 0
var elevation := 0.0
var drag_origin := Vector3.ZERO
var initial_angle := 0.0
var roof_hidden := false
var reference_pending := false
var colors: Array[String] = ["#b5b39f","#92a9a4","#b69a84","#a3b5bd","#c6b58e","#b7a1a0"]
var sizes: Dictionary = {
	"Casa":Vector3(5.5,3.2,6.0),"Edificio":Vector3(7.0,6.4,7.5),
	"Tienda":Vector3(5.8,3.3,5.0),"Parque":Vector3(6.0,.12,6.0),
	"Árbol":Vector3(1.9,3.4,1.9),"Banco":Vector3(1.6,.85,.65),
	"Poste":Vector3(.45,4.8,.45),"Lago":Vector3(5.5,.08,4.0),
	"Cama":Vector3(1.4,.65,2.0),"Inodoro":Vector3(.55,.78,.75),
	"Pared":Vector3(3.0,2.8,.16),"Mesa":Vector3(1.1,.80,.80)
}

func setup(value: World) -> void:
	world = value
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 1800.0
	add_child(camera)
	outline_mat = _transparent(Color(.18,.90,.48,.37))
	invalid_mat = _transparent(Color(.93,.19,.22,.43))
	preview = MeshInstance3D.new()
	preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(preview)
	preview.hide()
	_make_ui()
	_load_objects()

func _transparent(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _make_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	panel = PanelContainer.new()
	panel.position = Vector2(12,12)
	panel.custom_minimum_size = Vector2(308,0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,10)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",5)
	margin.add_child(column)
	var title := Label.new()
	title.text = "EDITOR | PILAR-ATARÉS"
	title.add_theme_font_size_override("font_size",20)
	column.add_child(title)
	var choices := HBoxContainer.new()
	column.add_child(choices)
	_button(choices,"Vista (V)",_cycle_view)
	_button(choices,"Medir (M)",_measure_mode)
	_button(choices,"Salir (B)",close)
	var grid := HBoxContainer.new()
	column.add_child(grid)
	_button(grid,"Precisión (G)",_cycle_grid)
	_button(grid,"Nivel (F)",_cycle_floor)
	_button(grid,"Techo (H)",_toggle_roof)
	hint = Label.new()
	hint.custom_minimum_size = Vector2(288,0)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	menu = PopupMenu.new()
	layer.add_child(menu)
	menu.id_pressed.connect(_menu_action)
	file_dialog = FileDialog.new()
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Imágenes"])
	file_dialog.title = "Seleccionar fotografía de fachada"
	file_dialog.file_selected.connect(_attach_reference)
	layer.add_child(file_dialog)
	panel.hide()

func _button(parent: Control,caption: String,action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	button.pressed.connect(action)
	parent.add_child(button)

func open(at: Vector3,context: bool = false) -> void:
	if active:
		return
	active = true
	focus = Vector3(at.x,0,at.z)
	camera_size = 28.0 if context else 45.0
	view_mode = 0
	mode = ""
	elevation = 3.2 if at.y>3.3 and world.inside_home else 0.0
	roof_hidden = world.inside_home
	_update_cutaway()
	_update_camera()
	camera.current = true
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if context:
		_context(at,Vector2i(get_viewport().get_visible_rect().size*.5))

func close() -> void:
	active = false
	roof_hidden = false
	_update_cutaway()
	preview.hide()
	panel.hide()
	menu.hide()
	file_dialog.hide()
	mode = ""
	measuring = false

func _cycle_view() -> void:
	view_mode = (view_mode+1)%3
	_update_camera()

func _cycle_grid() -> void:
	step_index = (step_index+1)%snaps.size()

func _cycle_floor() -> void:
	elevation = 3.2 if elevation==0.0 else 0.0
	roof_hidden = true
	_update_cutaway()
	message = "Nivel de colocación: %.2f m" % elevation

func _toggle_roof() -> void:
	roof_hidden = not roof_hidden
	_update_cutaway()

func _update_cutaway() -> void:
	world.set_home_cutaway(roof_hidden,elevation)
	for id in objects:
		var root: Node3D = objects[id]
		var record: Dictionary = records[id]
		var interior: bool = String(record.kind) in ["Cama","Inodoro","Pared","Mesa"]
		root.visible = not roof_hidden or not interior or absf(float(record.get("y",0.0))-elevation)<1.0

func _rotate(dir: int) -> void:
	angle += float(dir)*PI/12.0

func _measure_mode() -> void:
	mode = "measure"
	measuring = false
	message = "Marca dos puntos. Distancia horizontal en metros."

func _update_camera() -> void:
	camera.size = camera_size
	var offset := Vector3(0,maxf(camera_size,18),.01)
	if view_mode==1:
		offset = Vector3(camera_size*.65,camera_size*.85,camera_size*.75)
	elif view_mode==2:
		offset = Vector3(0,maxf(camera_size*.32,5.0),camera_size*.85)
	camera.position = focus+offset+Vector3.UP*elevation
	camera.look_at(focus+Vector3.UP*elevation,Vector3.UP)

func _point(mouse: Vector2) -> Vector3:
	var ray_origin := camera.project_ray_origin(mouse)
	var ray_normal := camera.project_ray_normal(mouse)
	var plane := Plane(Vector3.UP,elevation)
	var hit: Variant = plane.intersects_ray(ray_origin,ray_normal)
	if hit==null:
		return focus+Vector3.UP*elevation
	var p: Vector3 = hit
	return p

func _snap(p: Vector3) -> Vector3:
	var step: float = snaps[step_index]
	return Vector3(snappedf(p.x,step),elevation,snappedf(p.z,step))

func _rect(p: Vector3,size: Vector3,rot: float) -> PackedVector2Array:
	var poly := PackedVector2Array()
	var c := Vector2(p.x,p.z)
	for v in [Vector2(-size.x*.5,-size.z*.5),Vector2(size.x*.5,-size.z*.5),Vector2(size.x*.5,size.z*.5),Vector2(-size.x*.5,size.z*.5)]:
		poly.append(c+v.rotated(-rot))
	return poly

func _record_poly(record: Dictionary) -> PackedVector2Array:
	var p := Vector3(float(record.x),float(record.get("y",0.0)),float(record.z))
	var size: Vector3 = sizes.get(String(record.kind),Vector3.ONE)
	return _rect(p,size,float(record.angle))

func _target_poly(p: Vector3) -> PackedVector2Array:
	if mode=="mapped_move":
		var fp: Dictionary = world.original_footprints.get(selected_id,{})
		if fp.is_empty():
			return PackedVector2Array()
		var origin: Vector3 = fp.center
		var middle := Vector2(origin.x,origin.z)
		var result := PackedVector2Array()
		for q in fp.poly:
			result.append((q-middle).rotated(-angle)+Vector2(p.x,p.z))
		return result
	return _rect(p,sizes.get(kind,Vector3.ONE),angle)

func _interior_kind() -> bool:
	return kind in ["Cama","Inodoro","Pared","Mesa"]

func _allowed(poly: PackedVector2Array,p: Vector3) -> String:
	if _interior_kind() and mode!="mapped_move":
		if world.home_root==null:
			return "No hay vivienda editable"
		for q in poly:
			var local: Vector3 = world.home_root.to_local(Vector3(q.x,p.y,q.y))
			if absf(local.x)>4.15 or local.z< -4.2 or local.z>1.35:
				return "Mueble fuera del interior de casa"
		var size: Vector3 = sizes[kind]
		var shape := BoxShape3D.new()
		shape.size = size-Vector3(.04,.04,.04)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(Basis(Vector3.UP,angle),p+Vector3.UP*(size.y*.5+.06))
		query.collision_mask = 1|4
		var moving: Node3D = objects.get(selected_id,null)
		if mode=="move" and moving!=null:
			for body in moving.get_children():
				if body is CollisionObject3D:
					var exclude_ids: Array[RID] = query.exclude
					exclude_ids.append(body.get_rid())
					query.exclude = exclude_ids
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():
			return "Mueble o pared existente"
	else:
		if p.y>0.1:
			return "Construye exteriores en nivel 0"
		var reason: String = world.build_allowed(poly,selected_id if mode=="mapped_move" else "")
		if not reason.is_empty():
			return reason
	for id in records:
		if mode=="move" and id==selected_id:
			continue
		var r: Dictionary = records[id]
		if absf(float(r.get("y",0.0))-p.y)>1.0:
			continue
		if not Geometry2D.intersect_polygons(poly,_record_poly(r)).is_empty():
			return "Objeto colocado ocupa ese lugar"
	return ""

func _show_preview(poly: PackedVector2Array,p: Vector3,valid: bool) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices := Geometry2D.triangulate_polygon(poly)
	if indices.is_empty():
		preview.hide()
		return
	for idx in indices:
		var q := poly[idx]
		st.set_normal(Vector3.UP)
		st.add_vertex(Vector3(q.x,p.y+.13,q.y))
	preview.mesh = st.commit()
	preview.material_override = outline_mat if valid else invalid_mat
	preview.visible = true

func tick(delta: float) -> void:
	if not active:
		return
	if not menu.visible and not file_dialog.visible:
		var motion := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): motion.z -= 1
		if Input.is_physical_key_pressed(KEY_S): motion.z += 1
		if Input.is_physical_key_pressed(KEY_A): motion.x -= 1
		if Input.is_physical_key_pressed(KEY_D): motion.x += 1
		focus += motion.normalized()*camera_size*delta*.8
		focus.x = clampf(focus.x,-1250.0,1250.0)
		focus.z = clampf(focus.z,-1250.0,1250.0)
		_update_camera()
	cursor_world = _snap(_point(get_viewport().get_mouse_position()))
	var reason := ""
	if mode in ["place","move","mapped_move"]:
		var poly := _target_poly(cursor_world)
		reason = _allowed(poly,cursor_world)
		_show_preview(poly,cursor_world,reason.is_empty())
	else:
		preview.hide()
	var view_names: Array[String] = ["Aérea","Perspectiva","Calle"]
	hint.text = "%s | %.2f m | Nivel %.1f m\n%s\nWASD: mover vista · rueda: zoom\nClic derecho: opciones · clic izq.: aplicar\nV: vista · G: precisión · M: medir\nH: techo · F: piso · Q/E: girar · B: salir" % [view_names[view_mode],snaps[step_index],elevation,mode if not mode.is_empty() else "Seleccionar"]
	if not reason.is_empty():
		hint.text += "\nNO PERMITIDO: "+reason
	elif mode in ["place","move","mapped_move"]:
		hint.text += "\nPERMITIDO"
	if not message.is_empty():
		hint.text += "\n"+message
	if measuring:
		hint.text += "\nDistancia: %.2f m" % Vector2(cursor_world.x-measure_start.x,cursor_world.z-measure_start.z).length()

func handle(event: InputEvent) -> void:
	if not active or menu.visible or file_dialog.visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B: close()
			KEY_ESCAPE:
				mode = ""
				measuring = false
				message = "Acción cancelada"
			KEY_V: _cycle_view()
			KEY_G: _cycle_grid()
			KEY_F: _cycle_floor()
			KEY_H: _toggle_roof()
			KEY_M: _measure_mode()
			KEY_Q: _rotate(-1)
			KEY_E: _rotate(1)
	if event is InputEventMouseButton and event.pressed:
		if panel.get_global_rect().has_point(event.position):
			return
		if event.button_index==MOUSE_BUTTON_WHEEL_UP:
			camera_size = maxf(5.0,camera_size*.86)
		elif event.button_index==MOUSE_BUTTON_WHEEL_DOWN:
			camera_size = minf(500.0,camera_size*1.16)
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			_context(_point(event.position),Vector2i(event.position))
		elif event.button_index==MOUSE_BUTTON_LEFT:
			_click(_snap(_point(event.position)))

func _find_at(p: Vector3) -> void:
	selected_id = ""
	selected_type = "ground"
	var q := Vector2(p.x,p.z)
	for id in records:
		var r: Dictionary = records[id]
		if absf(float(r.get("y",0.0))-elevation)>1.0:
			continue
		if Geometry2D.is_point_in_polygon(q,_record_poly(r)):
			selected_id = String(id)
			selected_type = "object"
			return
	for fp in world.geography.footprints_near(p,2.0):
		var id := String(fp.id)
		if world.editable_buildings.has(id) and Geometry2D.is_point_in_polygon(q,fp.poly):
			selected_id = id
			selected_type = "mapped"
			return
	for lot in world._lots_near(p):
		if Geometry2D.is_point_in_polygon(q,world._lot_polygon(lot)):
			if roof_hidden and world.home_root!=null and world.home_root.global_position.distance_to(Vector3(p.x,0,p.z))<6.0:
				selected_type = "interior"
				return
			selected_type = "lot"
			selected_id = "lot_"+str(roundi(lot.center.x*10.0))+"_"+str(roundi(lot.center.z*10.0))
			return
	if world.street_geometry.point_on_road(p):
		selected_type = "street"
		return
	var tiny := _rect(p,Vector3(.12,.1,.12),0)
	if not world.street_geometry.clear(tiny):
		selected_type = "street"

func _context(p: Vector3,screen: Vector2i) -> void:
	click_world = p
	_find_at(p)
	menu.clear()
	menu.add_separator("Mapa real • "+selected_type)
	if selected_type in ["ground","interior"]:
		var i := 0
		for k in sizes:
			var furniture: bool = String(k) in ["Cama","Inodoro","Pared","Mesa"]
			if furniture==(selected_type=="interior"):
				menu.add_item("Colocar "+String(k),100+i)
			i += 1
	elif selected_type=="street":
		menu.add_item("Calle / acera protegida",90)
		menu.set_item_disabled(menu.get_item_index(90),true)
		menu.add_item("Medir distancia",7)
	elif selected_type=="object":
		menu.add_item("Mover",1)
		menu.add_item("Rotar",2)
		menu.add_item("Duplicar",3)
		menu.add_item("Eliminar",4)
		menu.add_item("Cambiar color",5)
		menu.add_item("Adjuntar foto de referencia",6)
	elif selected_type=="mapped":
		var fp: Dictionary = world.editable_buildings[selected_id]
		if not bool(fp.protected):
			menu.add_item("Mover edificio",1)
			menu.add_item("Rotar edificio",2)
			menu.add_item("Duplicar como edificio nuevo",3)
			menu.add_item("Eliminar edificio del juego",4)
		menu.add_item("Cambiar pintura de fachada",5)
		menu.add_item("Alternar portal / columnas",8)
		menu.add_item("Adjuntar foto de fachada",6)
	elif selected_type=="lot":
		menu.add_item("Adjuntar foto para corregir",6)
		menu.add_item("Copiar identificador",9)
	menu.add_item("Cancelar",0)
	menu.position = screen
	menu.popup()

func _menu_action(id: int) -> void:
	if id>=100:
		kind = String(sizes.keys()[id-100])
		mode = "place"
		angle = 0.0
		message = "Colocación de "+kind
		return
	match id:
		1,2,3:
			if selected_type=="object":
				var r: Dictionary = records[selected_id]
				kind = String(r.kind)
				angle = float(r.angle)
				elevation = float(r.get("y",0.0))
				mode = "place" if id==3 else "move"
			elif selected_type=="mapped":
				if id==3:
					kind = "Edificio"
					angle = 0.0
					mode = "place"
				else:
					mode = "mapped_move"
					kind = "Edificio"
					elevation = 0.0
					angle = float(world.map_edits.get(selected_id,{}).get("angle",0.0))
			if id==2:
				_rotate(1)
			message = "Sitúa la vista previa y confirma con clic izquierdo."
		4:
			if selected_type=="object":
				var removed: Node3D = objects[selected_id]
				remove_child(removed)
				removed.queue_free()
				objects.erase(selected_id)
				records.erase(selected_id)
				_save_objects()
				message = "Objeto eliminado."
			elif selected_type=="mapped":
				_set_edit("deleted",true)
		5:
			if selected_type=="object":
				var record: Dictionary = records[selected_id]
				var index := colors.find(String(record.get("paint","")))
				record.paint = colors[(index+1)%colors.size()]
				_replace_object(selected_id,record)
				_save_objects()
			elif selected_type=="mapped":
				var previous: Dictionary = world.map_edits.get(selected_id,{})
				var index := colors.find(String(previous.get("paint","")))
				_set_edit("paint",colors[(index+1)%colors.size()])
		6:
			reference_id = selected_id
			ref_position = click_world
			file_dialog.popup_centered_ratio(.75)
		7: _measure_mode()
		8:
			if selected_type=="mapped":
				var fp: Dictionary = world.editable_buildings[selected_id]
				var front: Dictionary = fp.front
				var normal_portal: bool = not front.is_empty() and bool(front.road.portal)
				var previous: Dictionary = world.map_edits.get(selected_id,{})
				_set_edit("portal",not bool(previous.get("portal",normal_portal)))
		9:
			DisplayServer.clipboard_set(selected_id)
			message = "Identificador copiado: "+selected_id
		0: pass

func _set_edit(key: String,value: Variant) -> void:
	var entry: Dictionary = world.map_edits.get(selected_id,{})
	entry[key] = value
	world.map_edits[selected_id] = entry
	if world.save_map_edits():
		# Baked original buildings are regenerated; source geography is unchanged.
		get_tree().call_deferred("reload_current_scene")
	else:
		message = "No se pudo guardar la modificación."

func _click(p: Vector3) -> void:
	if mode=="measure":
		if not measuring:
			measure_start = p
			measuring = true
		else:
			message = "Medida: %.2f metros" % Vector2(p.x-measure_start.x,p.z-measure_start.z).length()
			measuring = false
			mode = ""
		return
	if not mode in ["place","move","mapped_move"]:
		return
	var poly := _target_poly(p)
	var reason := _allowed(poly,p)
	if not reason.is_empty():
		message = reason
		return
	if mode=="mapped_move":
		var original: Dictionary = world.original_footprints[selected_id]
		var origin: Vector3 = original.center
		var record: Dictionary = world.map_edits.get(selected_id,{})
		record.dx = p.x-origin.x
		record.dz = p.z-origin.z
		record.angle = angle
		world.map_edits[selected_id] = record
		if world.save_map_edits():
			get_tree().call_deferred("reload_current_scene")
		else:
			message = "Error guardando el edificio."
		return
	var id := selected_id if mode=="move" else "user_"+str(Time.get_unix_time_from_system()).replace(".","_")+"_"+str(Time.get_ticks_usec())+"_"+str(serial)
	serial += 1
	var old: Dictionary = records.get(id,{})
	var record := {"kind":kind,"x":p.x,"y":p.y,"z":p.z,"angle":angle,"paint":old.get("paint",colors[0])}
	_replace_object(id,record)
	_save_objects()
	message = "Guardado: "+kind
	mode = ""

func _mat_for(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = .85
	return material

func _part(root: Node3D,p: Vector3,size: Vector3,color: Color,solid: bool = false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var view := MeshInstance3D.new()
	view.mesh = mesh
	view.material_override = _mat_for(color)
	root.add_child(view)
	view.position = p
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		root.add_child(body)
		body.position = p
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.add_child(col)

func _replace_object(id: String,record: Dictionary) -> void:
	if objects.has(id):
		var old: Node3D = objects[id]
		remove_child(old)
		old.queue_free()
	records[id] = record
	var root := Node3D.new()
	add_child(root)
	root.position = Vector3(float(record.x),float(record.get("y",0.0))+.065,float(record.z))
	root.rotation.y = float(record.angle)
	objects[id] = root
	var item: String = String(record.kind)
	var size: Vector3 = sizes[item]
	var paint := Color(String(record.get("paint",colors[0])))
	var wood := Color("#81684c")
	var trim := Color("#646962")
	if item in ["Casa","Edificio","Tienda"]:
		_part(root,Vector3(0,size.y*.5,0),size,paint,true)
		_part(root,Vector3(0,size.y-.10,0),Vector3(size.x,.20,size.z),trim)
		for x in [-.31,0.0,.31]:
			var px := float(x)*size.x
			_part(root,Vector3(px,1.17,size.z*.5+.015),Vector3(.90,2.26,.03),wood)
			if item=="Edificio":
				_part(root,Vector3(px,4.70,size.z*.5+.015),Vector3(1.1,1.65,.03),trim)
	elif item=="Árbol":
		_part(root,Vector3(0,.85,0),Vector3(.22,1.7,.22),wood,true)
		_part(root,Vector3(0,2.35,0),Vector3(1.8,1.8,1.8),Color("#59774a"))
	elif item=="Banco":
		_part(root,Vector3(0,.46,0),Vector3(size.x,.13,size.z),wood,true)
		_part(root,Vector3(0,.72,-.27),Vector3(size.x,.35,.09),wood)
		for x in [-.65,.65]:
			_part(root,Vector3(float(x),.22,0),Vector3(.12,.44,.48),trim,true)
	elif item=="Poste":
		_part(root,Vector3(0,2.4,0),Vector3(.18,4.8,.18),trim,true)
	elif item=="Parque" or item=="Lago":
		_part(root,Vector3(0,.03,0),Vector3(size.x,.06,size.z),Color("#708958") if item=="Parque" else Color("#43869b"))
	elif item=="Cama":
		_part(root,Vector3(0,.24,0),Vector3(size.x,.48,size.z),wood,true)
		_part(root,Vector3(0,.54,0),Vector3(size.x,.18,size.z),paint)
		_part(root,Vector3(0,.66,-.70),Vector3(size.x*.75,.13,.36),Color("#eee8d7"))
	elif item=="Inodoro":
		_part(root,Vector3(0,.26,0),Vector3(.40,.52,.48),Color("#d8d9d4"),true)
		_part(root,Vector3(0,.55,.16),Vector3(.55,.16,.58),Color("#e1e2dc"))
		_part(root,Vector3(0,.58,-.27),Vector3(.52,.41,.18),Color("#d8d9d4"))
	else:
		_part(root,Vector3(0,size.y*.5,0),size,paint,true)

func _save_objects() -> void:
	var f := FileAccess.open(SAVE,FileAccess.WRITE)
	if f!=null:
		f.store_string(JSON.stringify(records,"\t"))
		f.close()
	else:
		message = "No se pudo guardar."

func _load_objects() -> void:
	if not FileAccess.file_exists(SAVE):
		for id in world.home_defaults:
			_replace_object(String(id),world.home_defaults[id].duplicate(true))
		_save_objects()
		return
	var f := FileAccess.open(SAVE,FileAccess.READ)
	if f==null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		return
	for id in data:
		var r: Variant = data[id]
		if not r is Dictionary or not sizes.has(String(r.get("kind",""))):
			continue
		var p := Vector3(float(r.get("x",0)),float(r.get("y",0)),float(r.get("z",0)))
		if not p.is_finite():
			continue
		var poly := _record_poly(r)
		if String(r.kind) not in ["Cama","Inodoro","Pared","Mesa"] and not world.build_allowed(poly).is_empty():
			continue
		_replace_object(String(id),r)
	_update_cutaway()

func _attach_reference(path: String) -> void:
	var image := Image.new()
	if image.load(path)!=OK:
		message = "No se pudo abrir esa imagen."
		return
	var folder := ProjectSettings.globalize_path(REF_DIR)
	DirAccess.make_dir_recursive_absolute(folder)
	var safe_id := reference_id.validate_filename()
	var stem := safe_id+"_"+str(int(Time.get_unix_time_from_system()))
	var image_path := folder.path_join(stem+".jpg")
	if image.get_width()>1800 or image.get_height()>1800:
		var scale_value := minf(1800.0/float(image.get_width()),1800.0/float(image.get_height()))
		image.resize(maxi(1,roundi(image.get_width()*scale_value)),maxi(1,roundi(image.get_height()*scale_value)))
	if image.save_jpg(image_path,.90)!=OK:
		message = "No se pudo guardar la referencia."
		return
	var metadata := {"id":reference_id,"type":selected_type,"x_m":ref_position.x,"z_m":ref_position.z,"source":world.geography.source_path,"image":stem+".jpg"}
	var file := FileAccess.open(folder.path_join(stem+".json"),FileAccess.WRITE)
	if file!=null:
		file.store_string(JSON.stringify(metadata,"\t"))
		file.close()
	DisplayServer.clipboard_set(JSON.stringify(metadata))
	message = "Referencia guardada. ID y coordenadas copiados. Comparte la foto y el identificador para reconstruirla."
