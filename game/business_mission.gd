extends Node3D
const Ledger = preload("res://business_ledger.gd")
const World = preload("res://cuba_world.gd")
const Taxi = preload("res://taxi_service.gd")
const Person = preload("res://street_person.gd")
const CityLife = preload("res://city_life.gd")
const StoryCamera = preload("res://story_camera.gd")
const Interface = preload("res://interface_style.gd")
var first_story
var phone_destination: Callable
var notice_panel: PanelContainer
var notice_title: Label
var notice_body: Label
var story_camera: StoryCamera
var story_active := false
var story_lines: Array = []
var story_index := 0
var story_title := ""
var story_accept_label := ""
var story_cancel_label := ""
var story_callback: Callable
var story_confirming := false
var story_voice_enabled := false
var story_voice_playing := false
var story_voice_id := ""
var life: CityLife
var garage_market: Callable
var city_map: Callable
var carlos_call: Callable
var carlos_objective: Callable
var yordi_call: Callable
var yordi_objective: Callable
var street_inventory: Callable
var backpack_inventory: Callable
var phone_position: Callable
var ledger := Ledger.new()
var world: World
var taxis: Taxi
var player: CharacterBody3D
var van: CharacterBody3D
var camera: Camera3D
var albertico: Node3D
var albertico_intro_clock := 0.0
const ALBERTICO_INVITE_DELAY := 15.0
var arrow: Node3D
var stand: Node3D
var factory_arrow: Node3D
var crate_view: Node3D
var crate_rack: Node3D
var purchase_rack: Node3D
var buyer: Person
var buyer_time := 0.0
var buyer_path := PackedVector3Array()
var buyer_index := 0
var buyer_returning := false
var buyer_normal := Vector3.ZERO
var buyer_blocked := 0.0
var phone_ring: AudioStreamPlayer
var stock_display: Node3D
var stall_sign: Label3D
var stall_growth: Array[Node3D] = []
var stock_visual_key := ""
var pending_visual_key := ""
var carry_visual_key := ""
var cargo_visual_key := ""
var carry_tween: Tween
var buyer_product := ""
var buyer_served := false
var delivery_gesture := 0.0
var cargo_views: Dictionary = {}
const CARRY_REST := Vector3(.26,-.31,-.88)
var hud: Label
var hud_expanded := false
var panel: PanelContainer
var content: VBoxContainer
var dialog_content: VBoxContainer
var phone_panel: PanelContainer
var phone_content: VBoxContainer
var phone_scroll: ScrollContainer
var phone_clock: Label
var phone_title: Label
var phone_mode := false
var phone_icons: Dictionary = {}
var phone_balance: Label
var layer: CanvasLayer
var toast := ""
var toast_time := 0.0
var refresh := 0.0
var phase := 0.0
var materials: Dictionary = {}
var box_mesh := BoxMesh.new()

func setup(city: World,taxi_service: Taxi,actor: CharacterBody3D,vehicle: CharacterBody3D,view: Camera3D) -> void:
	world = city
	taxis = taxi_service
	player = actor
	van = vehicle
	camera = view
	ledger.load_game()
	box_mesh.size = Vector3.ONE
	_make_ui()
	story_camera = StoryCamera.new()
	add_child(story_camera)
	_make_scene()
	life = CityLife.new()
	add_child(life)
	life.setup(self)
	_sync_visuals()
	_update_hud()
	if world.food_factory.is_empty() or world.business_frontage==null:
		_notify("La primera misión requiere un puesto de venta y una parcela libre para la MIPYME.")
	else:
		taxis.set_business_points(world.food_factory.road,world.van_spawn,ledger.stage>=1)

func _mat(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not materials.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = color
		m.roughness = .88
		materials[key] = m
	return materials[key] as StandardMaterial3D

func _box(root: Node3D,p: Vector3,size_value: Vector3,color: Color) -> MeshInstance3D:
	var obj := MeshInstance3D.new()
	obj.mesh = box_mesh
	obj.material_override = _mat(color)
	obj.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(obj)
	obj.position = p
	obj.scale = size_value
	return obj

func _label(root: Node3D,value: String,p: Vector3,color: Color = Color.WHITE) -> Label3D:
	var label := Label3D.new()
	label.text = value
	label.font_size = 48
	label.pixel_size = .0045
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.visibility_range_end = 95.0
	root.add_child(label)
	label.position = p
	return label

func _person(root: Node3D,style: int) -> Person:
	var npc := Person.new()
	root.add_child(npc)
	npc.setup(style)
	# Stationary mission merchants must not be treated as ordinary greetings.
	npc.remove_from_group("social_people")
	npc.remove_from_group("pedestrian_spacing")
	npc.social_context = "shopping"
	return npc

func _arrow(root: Node3D,p: Vector3,color: Color) -> Node3D:
	var marker := Node3D.new()
	root.add_child(marker)
	marker.position = p
	var cone := CylinderMesh.new()
	cone.top_radius = .27
	cone.bottom_radius = 0.0
	cone.height = .48
	cone.radial_segments = 10
	var mesh := MeshInstance3D.new()
	mesh.mesh = cone
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	marker.add_child(mesh)
	var shaft := _box(marker,Vector3(0,.32,0),Vector3(.17,.30,.17),color)
	shaft.material_override = material
	return marker

static func crate_band(key: String) -> Color:
	match key:
		"pollo": return Color("#ac5348")
		"huevos": return Color("#d4c7a3")
		"picadillo": return Color("#63825b")
		"perrito": return Color("#487eaa")
		"harina": return Color("#c6aa71")
		"queso": return Color("#e0b34f")
		"refresco": return Color("#398b91")
		"aceite": return Color("#b77a40")
		"tomate": return Color("#a05070")
	return Color("#777b7e")

static func stall_tier(sold_count: int) -> int:
	return 2 if sold_count>=20 else (1 if sold_count>=5 else 0)

func _crate(root: Node3D,p: Vector3,key: String) -> Node3D:
	var node := Node3D.new()
	root.add_child(node)
	node.position = p
	var box := _box(node,Vector3.ZERO,Vector3(.52,.34,.40),Color("#b79a72"))
	# Reuse existing cached materials and one unit cube; no new collision.
	if world!=null:
		var cardboard := box.material_override as StandardMaterial3D
		if cardboard!=null: box.material_override = world.havana_textures.material(cardboard,"cardboard")
	_box(node,Vector3(0,.174,0),Vector3(.085,.012,.40),Color("#ddd0a9"))
	var band := crate_band(key)
	_box(node,Vector3(0,0,.204),Vector3(.46,.105,.012),band)
	var tag := _label(node,_product_name(key).to_upper(),Vector3(0,0,.214),Color("#fff4d9"))
	tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	tag.font_size = 26
	tag.pixel_size = .0013
	tag.visibility_range_end = 9.0
	tag.no_depth_test = false
	return node

# Batch small static decorations by color: one draw call per material.
# These meshes are cosmetic and never change the existing path or collider.
func _prop_batch(root: Node3D,items: Array) -> void:
	var by_color: Dictionary = {}
	for item in items:
		var color: Color = item[2]
		var key := color.to_html()
		if not by_color.has(key): by_color[key] = {"color":color,"parts":[]}
		by_color[key].parts.append(Transform3D(Basis.IDENTITY.scaled(item[1]),item[0]))
	for entry in by_color.values():
		var multi := MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = box_mesh
		multi.instance_count = entry.parts.size()
		for i in range(entry.parts.size()): multi.set_instance_transform(i,entry.parts[i])
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = multi
		visual.material_override = _mat(entry.color)
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 42.0
		visual.visibility_range_end_margin = 5.0
		root.add_child(visual)

func _make_stall_details() -> void:
	var wood := Color("#8c7254")
	var dark := Color("#554e42")
	var cream := Color("#e3d4b0")
	var green := Color("#638e77")
	# Everything stays within the original table footprint.
	_prop_batch(stand,[
		[Vector3(0,.22,0),Vector3(1.30,.055,.52),wood],
		[Vector3(0,.58,.27),Vector3(1.30,.24,.035),wood],
		[Vector3(0,.45,-.25),Vector3(1.20,.055,.035),dark],
		[Vector3(0,.59,.295),Vector3(1.08,.16,.014),cream]
	])
	stall_sign = _label(stand,"ALIMENTOS · ALBERTICO",Vector3(0,.59,.307),dark)
	stall_sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	stall_sign.pixel_size = .002
	stall_sign.font_size = 30
	stall_sign.visibility_range_end = 20.0
	# Add business upgrades only as the existing sales counter grows.
	for tier in [1,2]:
		var group := Node3D.new()
		stand.add_child(group)
		stall_growth.append(group)
		if tier==1:
			_prop_batch(group,[
				[Vector3(-.61,1.48,-.25),Vector3(.04,1.34,.04),dark],
				[Vector3(.61,1.48,-.25),Vector3(.04,1.34,.04),dark],
				[Vector3(0,2.18,0),Vector3(1.45,.045,.62),green],
				[Vector3(0,2.11,.28),Vector3(1.45,.12,.025),green]
			])
		else:
			_prop_batch(group,[
				[Vector3(-.48,2.08,.30),Vector3(.24,.105,.015),cream],
				[Vector3(0,2.08,.30),Vector3(.24,.105,.015),cream],
				[Vector3(.48,2.08,.30),Vector3(.24,.105,.015),cream],
				[Vector3(0,.44,.296),Vector3(.92,.035,.008),green]
			])
		group.hide()

func _make_warehouse_details() -> void:
	var root := Node3D.new()
	add_child(root)
	var center: Vector3 = world.food_factory.center
	var basis: Basis = world.food_factory.basis
	root.global_transform = Transform3D(basis,center)
	var metal := Color("#626f72")
	var shelf := Color("#88877c")
	var carton := Color("#a98a62")
	var items: Array = []
	# At the rear wall, away from both counters, doors and clerk.
	for x in [-2.55,2.55]:
		for dx in [-.72,.72]:
			items.append([Vector3(x+dx,1.05,-3.96),Vector3(.065,1.92,.10),metal])
		for y in [.22,.86,1.50]:
			items.append([Vector3(x,y,-3.86),Vector3(1.52,.055,.52),shelf])
			for dx in [-.42,.20]:
				items.append([Vector3(x+dx,y+.18,-3.86),Vector3(.44,.30,.36),carton])
	_prop_batch(root,items)
	var sign := _label(root,"ALMACÉN · MAYORISTA",Vector3(0,2.35,-4.13),Color("#e7e1cc"))
	sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	sign.pixel_size = .003
	sign.visibility_range_end = 25.0
	# Fixed visual-only pallet directly beneath the paid-crate area.
	var pallet := Node3D.new()
	add_child(pallet)
	pallet.global_transform = crate_rack.global_transform
	_prop_batch(pallet,[
		[Vector3(0,.018,0),Vector3(1.68,.036,.55),Color("#927656")]
	])

func _selectable_crate(root: Node3D,p: Vector3,key: String,paid: bool,supplier: String = "primary") -> void:
	var node := _crate(root,p,key)
	var target := StaticBody3D.new()
	target.collision_layer = 16
	target.collision_mask = 0
	node.add_child(target)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(.52,.34,.40)
	collider.shape = shape
	target.add_child(collider)
	target.set_meta("mipyme_key",key)
	target.set_meta("paid",paid)
	target.set_meta("supplier",supplier)

func _aimed_crate(at: Vector3) -> Node3D:
	if camera==null or player==null: return null
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var query := PhysicsRayQueryParameters3D.create(origin,origin+direction*8.0,1|4|16)
	query.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return null
	var node := hit.collider as Node3D
	if node!=null and node.has_meta("mipyme_key") and at.distance_to(node.global_position)<3.0:
		return node
	return null

func aimed_text(at: Vector3) -> String:
	var target := _aimed_crate(at)
	if target==null: return ""
	var key := String(target.get_meta("mipyme_key"))
	if bool(target.get_meta("paid")): return "[E] Recoger caja de "+_product_name(key)
	return "[E] Comprar y recoger "+_product_name(key)+" · %d CUP" % int(Ledger.PRODUCTS[key].cost)

func take_aimed(at: Vector3) -> bool:
	var target := _aimed_crate(at)
	if target==null: return false
	if life!=null and not life.state.meal.is_empty():
		_notify("Termina de comer antes de recoger una caja.")
		return true
	if not ledger.carry.is_empty():
		_notify("Ya llevas una caja. G para cargarla en un vehículo.")
		return true
	if ledger.stage<2:
		_notify("Primero acepta la misión de Albertico y llega a la MIPYME.")
		return true
	var key := String(target.get_meta("mipyme_key"))
	if first_story!=null and first_story.active():
		first_story.buy(key,String(target.get_meta("supplier","primary")),bool(target.get_meta("paid")))
		return true
	if not bool(target.get_meta("paid")):
		var supplier := String(target.get_meta("supplier","primary"))
		if life!=null and not life.reserve_crate(supplier,key):
			_notify("No quedan cajas de este producto.")
			return true
		if not ledger.buy(key,1):
			if life!=null: life.restore_crate(supplier,key)
			_notify("No tienes suficiente dinero para esta caja.")
			return true
		if life!=null: life.refresh_supplier(supplier)
	if ledger.pick_up(key):
		_notify("Llevas una caja de "+_product_name(key)+". G para cargarla.")
		_sync_visuals()
	return true

# Move the entire stall sideways, leaving an open approach to nearby doors.
# Keep the original map frontage and use the existing sidewalk geometry.
func _albertico_side_offset(home: Node3D) -> float:
	var best_offset := 0.0
	var best_clearance := -INF
	for value in [2.3,-2.3,3.1,-3.1,4.0,-4.0,1.8,-1.8,0.0]:
		var shift := float(value)
		var person: Vector3 = home.to_global(Vector3(-2.55+shift,.105,2.85))
		var table: Vector3 = home.to_global(Vector3(-2.55+shift,.105,3.66))
		var points: Array[Vector3] = [person,table,table+home.global_basis.x*.78,table-home.global_basis.x*.78]
		var valid := true
		for p in points:
			if world.street_geometry.point_on_road(p) or not world.pedestrian_segment_clear(p,p):
				valid = false
				break
		if not valid: continue
		var clearance := INF
		for entry in world.npc_doorways:
			var door: Vector3 = entry.threshold
			var normal: Vector3 = entry.normal
			if door.distance_to(person)>8.0: continue
			var end: Vector3 = door+normal*2.8
			for p in points:
				var flat := Vector3(p.x,door.y,p.z)
				var nearest := Geometry3D.get_closest_point_to_segment(flat,door,end)
				clearance = minf(clearance,flat.distance_to(nearest))
		if absf(shift)>=1.8 and clearance>=1.15: return shift
		if clearance>best_clearance:
			best_clearance = clearance
			best_offset = shift
	return best_offset

func _make_scene() -> void:
	if world.business_frontage==null or world.food_factory.is_empty(): return
	var home := world.business_frontage
	var side_offset := _albertico_side_offset(home)
	albertico = _person(self,810)
	albertico.position = home.to_global(Vector3(-2.55+side_offset,.105,2.85))
	albertico.rotation.y = home.rotation.y
	_label(albertico,"Albertico",Vector3(0,2.03,0))
	arrow = _arrow(albertico,Vector3(0,2.68,0),Color("#49ff72"))
	stand = Node3D.new()
	add_child(stand)
	stand.position = home.to_global(Vector3(-2.55+side_offset,.105,3.66))
	stand.rotation.y = home.rotation.y
	_box(stand,Vector3(0,.79,0),Vector3(1.45,.09,.62),Color("#a88b64"))
	for x in [-.61,.61]:
		for z in [-.23,.23]:
			_box(stand,Vector3(float(x),.39,float(z)),Vector3(.075,.78,.075),Color("#725f47"))
	_make_stall_details()
	stock_display = Node3D.new()
	stand.add_child(stock_display)
	buyer = Person.new()
	add_child(buyer)
	buyer.setup(210)
	buyer.social_context = "shopping"
	buyer.hide()
	var counter: Vector3 = world.food_factory.counter
	var clerk := _person(self,813)
	clerk.add_to_group("mission_merchant_visuals")
	albertico.add_to_group("mission_merchant_visuals")
	var basis: Basis = world.food_factory.basis
	clerk.position = counter+basis*Vector3(0,-.84,-2.05)
	clerk.rotation.y = basis.get_euler().y
	_label(clerk,"MIPYME",Vector3(0,2.02,0))
	var pickup: Vector3 = world.food_factory.pickup
	var sign := Node3D.new()
	add_child(sign)
	sign.position = pickup
	_label(sign,"RECOGER CAJAS",Vector3(0,1.25,0),Color("#f0dfa3"))
	factory_arrow = _arrow(sign,Vector3(0,1.9,0),Color("#49ff72"))
	crate_rack = Node3D.new()
	add_child(crate_rack)
	# Pickup counter top: .43+.78/2=.82; place the pallet and crates on it.
	crate_rack.position = pickup+basis*Vector3(0,-.14,-1.35)
	crate_rack.rotation.y = basis.get_euler().y
	purchase_rack = Node3D.new()
	add_child(purchase_rack)
	# Counter top: .56+1.02/2=1.07; not the interaction point in the aisle.
	purchase_rack.position = counter+basis*Vector3(0,.11,-1.37)
	purchase_rack.rotation.y = basis.get_euler().y
	var primary_products := ["pollo","picadillo","perrito"]
	for i in range(primary_products.size()):
		var key := String(primary_products[i])
		var product: Dictionary = Ledger.PRODUCTS[key]
		var at := Vector3(-.70+float(i)*.70,.17,0)
		_selectable_crate(purchase_rack,at,key,false)
		var tag := _label(purchase_rack,"%d CUP" % int(product.cost),at+Vector3(0,.24,.21),Color("#f4ecd8"))
		tag.pixel_size = .0016
		tag.font_size = 26
		tag.outline_size = 1
		tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		tag.visibility_range_end = 8.0
	_make_warehouse_details()
	crate_view = Node3D.new()
	camera.add_child(crate_view)
	crate_view.position = CARRY_REST
	crate_view.rotation_degrees = Vector3(-8,-12,0)

func _make_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 17
	add_child(layer)
	hud = Label.new()
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hud.offset_left = 12
	hud.offset_top = -100
	hud.offset_right = 540
	hud.offset_bottom = -10
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_theme_font_size_override("font_size",14)
	hud.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	hud.add_theme_color_override("font_shadow_color",Color.BLACK)
	hud.add_theme_constant_override("shadow_offset_x",2)
	hud.add_theme_constant_override("shadow_offset_y",2)
	hud.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud.add_theme_stylebox_override("normal",_phone_style(Color("#101b28e8"),9,Color("#34485c"),1,10))
	notice_panel = PanelContainer.new()
	layer.add_child(notice_panel)
	notice_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	notice_panel.offset_left = -345
	notice_panel.offset_right = -12
	notice_panel.offset_top = -170
	notice_panel.offset_bottom = -80
	notice_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_panel.add_theme_stylebox_override("panel",_phone_style(Color("#182737f5"),10,Color("#52677d"),1,10))
	var notice_stack := VBoxContainer.new()
	notice_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_panel.add_child(notice_stack)
	notice_title = Label.new()
	notice_title.add_theme_font_size_override("font_size",12)
	notice_title.add_theme_color_override("font_color",Color("#edcd8c"))
	notice_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_stack.add_child(notice_title)
	notice_body = Label.new()
	notice_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice_body.add_theme_font_size_override("font_size",14)
	notice_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice_stack.add_child(notice_body)
	notice_panel.hide()
	panel = PanelContainer.new()
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -200
	panel.offset_bottom = 200
	panel.add_theme_stylebox_override("panel",_phone_style(Color("#152130f5"),14,Color("#40536a"),1,4))
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,16)
	panel.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation",9)
	margin.add_child(content)
	dialog_content = content
	panel.hide()
	_make_phone()
	phone_ring = AudioStreamPlayer.new()
	add_child(phone_ring)
	var audio := AudioStreamWAV.new()
	audio.format = AudioStreamWAV.FORMAT_16_BITS
	audio.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(22050*2)
	for i in range(22050):
		var t := float(i)/22050.0
		var gate := 1.0 if t<.22 or (t>.36 and t<.60) else 0.0
		var value := int(sin(t*TAU*740.0)*sin(t*TAU*4.0)*gate*2200.0)
		samples.encode_s16(i*2,value)
	audio.data = samples
	phone_ring.stream = audio
	phone_ring.volume_db = -7.0

func modal_open() -> bool:
	return (panel!=null and panel.visible) or (phone_panel!=null and phone_panel.visible)

func close() -> void:
	_end_story()
	panel.hide()
	if phone_panel!=null: phone_panel.hide()
	phone_mode = false
	phone_balance = null
	content = dialog_content
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_refresh_notice()

func _open(title: String,body: String = "") -> void:
	_end_story()
	content = phone_content if phone_mode else dialog_content
	phone_balance = null
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	if phone_mode:
		phone_title.text = title
		phone_scroll.scroll_vertical = 0
		panel.hide()
		_resize_phone()
		phone_panel.show()
		_update_phone_status()
	else:
		var heading := Label.new()
		heading.text = title
		heading.add_theme_font_size_override("font_size",23)
		content.add_child(heading)
		panel.show()
	if not body.is_empty():
		var description := Label.new()
		description.text = body
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size.x = 390 if not phone_mode else 0
		if phone_mode: description.add_theme_color_override("font_color",Color("#b3c4d6"))
		content.add_child(description)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_notice()

# Story dialogues use the existing modal so mission ticks and controls
# obey the same pause/resume rules as the original interactions.
func open_story(actor: Node3D,title: String,lines: Array,accept_label: String,callback: Callable,cancel_label: String = "") -> void:
	phone_mode = false
	_open(title)
	story_active = true
	story_title = title
	story_lines = lines.duplicate()
	if story_lines.is_empty(): story_lines.append(title)
	story_index = 0
	story_accept_label = accept_label
	story_cancel_label = cancel_label
	story_callback = callback
	story_confirming = false
	if phone_panel!=null: phone_panel.hide()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -360
	panel.offset_right = 360
	panel.offset_top = -238
	panel.offset_bottom = -12
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#151c27ee")
	style.border_color = Color("#536276")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel",style)
	if is_instance_valid(story_camera): story_camera.begin(actor,player,camera)
	_render_story()

static func story_line_parts(raw: String,fallback: String) -> PackedStringArray:
	var colon := raw.find(":")
	if colon>0 and colon<=24: return PackedStringArray([raw.left(colon).strip_edges(),raw.substr(colon+1).strip_edges()])
	return PackedStringArray([fallback,raw])

func _story_voice_available() -> bool:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH): return false
	if story_voice_id.is_empty():
		var voices := DisplayServer.tts_get_voices_for_language("es")
		if not voices.is_empty(): story_voice_id = voices[0]
	return not story_voice_id.is_empty()

func _stop_story_voice() -> void:
	if story_voice_playing and DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		DisplayServer.tts_stop()
	story_voice_playing = false

func _speak_story() -> void:
	_stop_story_voice()
	if not story_voice_enabled or not _story_voice_available() or story_index>=story_lines.size(): return
	var parts := story_line_parts(String(story_lines[story_index]),story_title)
	DisplayServer.tts_speak(parts[1],story_voice_id,75,1.0,1.0,0,true)
	story_voice_playing = true

func _toggle_story_voice() -> void:
	if not story_active: return
	story_voice_enabled = not story_voice_enabled
	_render_story()

func _render_story() -> void:
	if not story_active: return
	content = dialog_content
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	var final_page := story_index>=story_lines.size()
	var parts := story_line_parts(String(story_lines[mini(story_index,story_lines.size()-1)]),story_title)
	heading.text = story_title+"  ·  Decisión" if final_page else parts[0]+"  ·  %d/%d" % [story_index+1,story_lines.size()]
	heading.add_theme_font_size_override("font_size",20)
	heading.add_theme_color_override("font_color",Color("#f0d49a"))
	content.add_child(heading)
	var subtitle := Label.new()
	if final_page:
		var recap := PackedStringArray()
		for line in story_lines: recap.append(String(line))
		subtitle.text = "\n".join(recap)
	else: subtitle.text = parts[1]
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.custom_minimum_size.x = 650
	subtitle.add_theme_font_size_override("font_size",16)
	content.add_child(subtitle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	content.add_child(row)
	var next := Button.new()
	next.text = story_accept_label if final_page else "Continuar"
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next.pressed.connect(_confirm_story if final_page else _next_story)
	row.add_child(next)
	if not final_page:
		var skip := Button.new()
		skip.text = "Omitir diálogo"
		skip.pressed.connect(_skip_story)
		row.add_child(skip)
	if not story_cancel_label.is_empty():
		var cancel := Button.new()
		cancel.text = story_cancel_label
		cancel.pressed.connect(close)
		row.add_child(cancel)
	if _story_voice_available() and not final_page:
		var voice := Button.new()
		voice.text = "Voz: sí" if story_voice_enabled else "Voz: no"
		voice.pressed.connect(_toggle_story_voice)
		row.add_child(voice)
	_speak_story()

func _next_story() -> void:
	if not story_active: return
	story_index = mini(story_index+1,story_lines.size())
	_render_story()

func _skip_story() -> void:
	if not story_active: return
	story_index = story_lines.size()
	_render_story()

func _confirm_story() -> void:
	# Skip only reveals the explicit decision; it cannot buy or accept anything.
	if not story_active or story_index<story_lines.size() or story_confirming or not story_callback.is_valid(): return
	story_confirming = true
	var callback := story_callback
	callback.call()
	story_confirming = false

func _end_story() -> void:
	if not story_active: return
	story_active = false
	_stop_story_voice()
	if is_instance_valid(story_camera): story_camera.finish()
	story_lines.clear()
	story_callback = Callable()
	story_confirming = false
	panel.add_theme_stylebox_override("panel",_phone_style(Color("#152130f5"),14,Color("#40536a"),1,4))
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -200
	panel.offset_bottom = 200

func _button(text_value: String,callback: Callable,disabled_value: bool = false) -> void:
	var button := Button.new()
	button.text = text_value
	if phone_mode:
		button.custom_minimum_size.y = 44
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.disabled = disabled_value
	button.pressed.connect(callback)
	content.add_child(button)

func _notify(value: String) -> void:
	toast = value
	toast_time = 5.0
	_refresh_notice()

func _refresh_notice() -> void:
	if not is_instance_valid(notice_panel): return
	var show_notice := toast_time>0.0 and not modal_open() and hud.visible
	if notice_panel.visible!=show_notice: notice_panel.visible = show_notice
	if show_notice:
		var heading := Interface.notice_title(toast)
		if notice_title.text!=heading: notice_title.text = heading
		if notice_body.text!=toast: notice_body.text = toast

func _flat_distance(a: Vector3,b: Vector3) -> float:
	return Vector2(a.x,a.z).distance_to(Vector2(b.x,b.z))

func _near(at: Vector3,p: Vector3,radius: float) -> bool:
	return absf(at.y-p.y)<2.0 and _flat_distance(at,p)<radius

func _product_name(key: String) -> String:
	return String(Ledger.PRODUCTS.get(key,{}).get("name",key))

func _stock_text() -> String:
	var lines: Array[String] = []
	for key in Ledger.PRODUCTS:
		lines.append("%s: %d" % [_product_name(key),int(ledger.stock.get(key,0))])
	return " | ".join(lines)

func _nearest_vehicle(at: Vector3) -> Dictionary:
	var nearest: Dictionary = {}
	var distance := 4.0
	if is_instance_valid(van):
		var d := _flat_distance(at,van.global_position)
		if d<distance and van.velocity.length()<.8:
			nearest = {"id":"van","body":van}
			distance = d
	for i in range(taxis.taxis.size()):
		var taxi: Dictionary = taxis.taxis[i]
		var body: CharacterBody3D = taxi.body
		var d := _flat_distance(at,body.global_position)
		if d<distance and body.velocity.length()<.8 and taxi.path.is_empty():
			nearest = {"id":"taxi_"+str(i),"body":body}
			distance = d
	return nearest

func cargo_action(at: Vector3) -> bool:
	if first_story!=null and first_story.active(): return first_story.cargo_action()
	if life!=null and not life.state.meal.is_empty():
		_notify("Termina de comer antes de cargar mercancía.")
		return true
	var vehicle := _nearest_vehicle(at)
	if vehicle.is_empty():
		_notify("Acércate a la van o a un taxi detenido.")
		return true
	var id := String(vehicle.id)
	if not ledger.carry.is_empty():
		if ledger.load_vehicle(id):
			_notify("Caja cargada. Ahora viaja al puesto o sigue comprando.")
		else:
			_notify("El vehículo está lleno: máximo 8 cajas.")
	elif ledger.unload_vehicle(id):
		_notify("Caja descargada. Llévasela a Albertico.")
	else:
		_notify("No hay cajas en este vehículo.")
	_sync_visuals()
	return true

func taxi_arrival(at: Vector3) -> void:
	if ledger.stage==1 and not world.food_factory.is_empty():
		var factory: Vector3 = world.food_factory.counter
		if _flat_distance(at,factory)<=50.0:
			ledger.factory_arrival()
			_notify("Llegaste a la MIPYME. Mira una caja y pulsa E.")
			_sync_visuals()

# Test only the visible body meshes, not the floating name or mission arrow.
# Albertico has no physics collider; a ray against his mesh bounds provides
# precise selection without adding a collision body or continuous physics.
func aimed_albertico_text(at: Vector3) -> String:
	if not is_instance_valid(albertico) or not albertico.is_visible_in_tree() or camera==null or player==null: return ""
	if not _near(at,albertico.global_position,2.0): return ""
	var origin := camera.global_position
	var direction := -camera.global_transform.basis.z
	var finish := origin+direction*8.0
	var depth := INF
	var parts := albertico.find_children("*","MeshInstance3D",true,false)
	for child in parts:
		if not child is MeshInstance3D or not child.is_visible_in_tree(): continue
		if is_instance_valid(arrow) and arrow.is_ancestor_of(child): continue
		var part := child as MeshInstance3D
		var local_hit: Variant = part.get_aabb().intersects_segment(part.to_local(origin),part.to_local(finish))
		if local_hit==null: continue
		var hit: Vector3 = part.to_global(local_hit)
		depth = minf(depth,(hit-origin).dot(direction))
	if not is_finite(depth) or depth<0.0: return ""
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+direction*depth,1|4|8|16|32)
	ray.exclude = [player.get_rid()]
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return ""
	if ledger.stage==0: return "[E] Hablar con Albertico"
	if first_story!=null and first_story.active(): return first_story.companion_action()
	if not ledger.carry.is_empty() and ledger.stage>=3: return "[E] Entregar caja a Albertico"
	if ledger.stage==3 and ledger.total(ledger.stock)>0: return "[E] Contratar a Albertico"
	return "[E] Hablar con Albertico"

func action_text(at: Vector3) -> String:
	if life!=null:
		var context := life.action_text(at)
		if not context.is_empty(): return context
	var aimed := aimed_albertico_text(at)
	if not aimed.is_empty(): return aimed
	if not world.food_factory.is_empty():
		if _near(at,world.food_factory.pickup,2.0) or _near(at,world.food_factory.counter,2.0): return "MIPYME · Mira una caja y pulsa E"
	return ""

func interact(at: Vector3) -> bool:
	if take_aimed(at): return true
	if life!=null and life.interact(at): return true
	var action := action_text(at)
	if action.is_empty(): return false
	if action.contains("Albertico"):
		return interact_albertico(at)
	if life!=null and life.sites.has("primary"):
		life._contact_page("primary")
	else: _notify("Mira directamente la caja que deseas y pulsa E.")
	return true

func interact_albertico(at: Vector3) -> bool:
	if aimed_albertico_text(at).is_empty(): return false
	if ledger.stage==0:
		open_story(albertico,"Albertico",["Albertico: Asere, te tengo un bisne. Hay una gente que vende comida por cajas.","Albertico: Vamos juntos a la MIPYME. Ya hay un taxi cerca. Compramos huevos, perritos, pollo y picadillo.","Albertico: Yo te ayudo a cargar las cajas y luego montamos el puesto. Mi parte es el 15% de cada venta. ¿Te sirve?"],"Sí, vamos arriba",_accept,"No, ahora no")
	elif first_story!=null and first_story.active():
		first_story.talk()
	elif not ledger.carry.is_empty() and ledger.stage>=3:
		if ledger.deliver():
			delivery_gesture = .65
			_notify("Caja entregada. "+_stock_text())
			_sync_visuals()
	elif ledger.stage==3 and ledger.total(ledger.stock)>0:
		open_story(albertico,"Albertico",["Albertico: Déjame la mercancía aquí. Yo la vendo y me quedo con el 15% de cada venta.","Albertico: ¿Hacemos el negocio?"],"Contratar a Albertico",_hire,"Ahora no")
	else:
		_open("Albertico","Trae las cajas de la MIPYME, cárgalas en el carro y déjamelas aquí.\n\n"+_stock_text())
		_button("Cerrar",close)
	return true

func _accept() -> void:
	if first_story!=null and not first_story.begin(): return
	ledger.accept()
	close()
	_notify("MISIÓN INICIADA · Te tengo un bisne")
	_sync_visuals()

func _hire() -> void:
	if ledger.hire():
		close()
		_notify("¡MISIÓN CUMPLIDA! · Te tengo un bisne")
		_sync_visuals()

func _open_shop() -> void:
	if first_story!=null and first_story.active():
		_notify(first_story.objective())
		return
	if ledger.stage<2:
		_open("MIPYME de alimentos","Primero habla con Albertico y llega aquí en taxi.")
		_button("Cerrar",close)
		return
	_open("MIPYME · Venta mayorista","Billetera: %d CUP. Cada caja contiene 10 unidades. Compra y recógelas en el mostrador de cajas." % ledger.cash)
	for key in Ledger.PRODUCTS:
		var product: Dictionary = Ledger.PRODUCTS[key]
		var k := String(key)
		_button("%s · caja %d CUP" % [product.name,product.cost],_buy.bind(k),ledger.cash<int(product.cost))
	_button("Salir",close)

func _buy(key: String) -> void:
	if first_story!=null and first_story.active(): return
	if ledger.buy(key,1):
		_notify("Compraste una caja de "+_product_name(key)+". Recógela al lado.")
		_sync_visuals()
	_open_shop()

func _open_pickup() -> void:
	if not ledger.carry.is_empty():
		_open("Recoger mercancía","Ya llevas una caja. Cárgala en un vehículo con G.")
		_button("Cerrar",close)
		return
	_open("Recoger mercancía","Cajas pagadas. Puedes transportar una cada vez.")
	for key in Ledger.PRODUCTS:
		var count := int(ledger.pending.get(key,0))
		if count>0:
			_button("%s · %d cajas" % [_product_name(key),count],_pickup.bind(String(key)))
	_button("Cerrar",close)

func _pickup(key: String) -> void:
	if first_story!=null and first_story.active(): return
	if ledger.pick_up(key):
		close()
		_notify("Llevas una caja de "+_product_name(key)+". G para cargarla.")
		_sync_visuals()

func open_phone() -> void:
	if modal_open():
		close()
		return
	open_phone_home()

func open_phone_home() -> void:
	phone_mode = true
	_open("Inicio")
	var greeting := Label.new()
	greeting.text = "LA HABANA  /  MYCITY"
	greeting.add_theme_font_size_override("font_size",12)
	greeting.add_theme_color_override("font_color",Color("#93b2c7"))
	content.add_child(greeting)
	var wallet := PanelContainer.new()
	wallet.add_theme_stylebox_override("panel",_phone_style(Color("#173b41"),18,Color("#396b6c"),1,14))
	content.add_child(wallet)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation",3)
	wallet.add_child(stack)
	var caption := Label.new()
	caption.text = "DINERO DISPONIBLE"
	caption.add_theme_font_size_override("font_size",12)
	caption.add_theme_color_override("font_color",Color("#a5d5cd"))
	stack.add_child(caption)
	phone_balance = Label.new()
	phone_balance.add_theme_font_size_override("font_size",32)
	stack.add_child(phone_balance)
	_update_phone_status()
	var missions := Button.new()
	missions.text = "Misiones · Ver objetivos"
	missions.custom_minimum_size.y = 40
	missions.pressed.connect(open_mission_log)
	content.add_child(missions)
	var apps := GridContainer.new()
	apps.columns = 3
	apps.add_theme_constant_override("h_separation",9)
	apps.add_theme_constant_override("v_separation",9)
	content.add_child(apps)
	_phone_tile(apps,"Mensajes",open_messages,"message",Color("#247a63"),ledger.unread)
	if life!=null: _phone_tile(apps,"Contactos",life.open_contacts,"contact",Color("#3d6dba"))
	_phone_tile(apps,"Mi negocio",open_business_summary,"business",Color("#b77a38"))
	if carlos_call.is_valid() and int(ledger.life_data.get("carlos_paint",{}).get("stage",0))>0:
		_phone_tile(apps,"Carlos",carlos_call,"contact",Color("#457e91"))
	if yordi_call.is_valid() and int(ledger.life_data.get("yordi_ps5",{}).get("stage",0))>0:
		_phone_tile(apps,"Yordi",yordi_call,"contact",Color("#527699"))
	if life!=null: _phone_tile(apps,"Entregas",life.open_supply_market,"bag",Color("#377e73"))
	if garage_market.is_valid(): _phone_tile(apps,"Marketplace",garage_market,"shop",Color("#6d58ad"))
	if street_inventory.is_valid(): _phone_tile(apps,"Mis compras",street_inventory,"bag",Color("#a85875"))
	if backpack_inventory.is_valid(): _phone_tile(apps,"Mochila",backpack_inventory,"pack",Color("#587d64"))
	_phone_tile(apps,"Mapa",city_map if city_map.is_valid() else open_phone_gps,"pin",Color("#397c96"))
	_phone_tile(apps,"GPS",open_phone_gps,"pin",Color("#397c96"))
	var footer := Label.new()
	footer.text = "P / Esc · Guardar teléfono"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color",Color("#8799ad"))
	footer.add_theme_font_size_override("font_size",12)
	content.add_child(footer)

func _phone_tile(root: Control,label_value: String,callback: Callable,key: String,color: Color,count: int = 0) -> void:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(0,82)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("normal",_phone_style(Color("#202c3d"),15,Color("#344558"),1,5))
	tile.add_theme_stylebox_override("hover",_phone_style(Color("#2d3e52"),15,Color("#7494ac"),1,5))
	tile.add_theme_stylebox_override("pressed",_phone_style(Color("#344b60"),15,Color("#7494ac"),1,5))
	tile.pressed.connect(callback)
	root.add_child(tile)
	var stack := VBoxContainer.new()
	tile.add_child(stack)
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.offset_top = 9
	stack.offset_bottom = -8
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation",5)
	var icon := TextureRect.new()
	icon.texture = _phone_icon(key,color)
	icon.custom_minimum_size = Vector2(36,36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	var name_label := Label.new()
	name_label.text = label_value
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size",13)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(name_label)
	if count>0:
		var badge := Label.new()
		badge.text = str(mini(99,count))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.add_theme_font_size_override("font_size",12)
		badge.add_theme_stylebox_override("normal",_phone_style(Color("#c44955"),10,Color.TRANSPARENT,0,3))
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tile.add_child(badge)
		badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
		badge.offset_left = -31
		badge.offset_right = -6
		badge.offset_top = 5
		badge.offset_bottom = 25

func open_mission_log() -> void:
	phone_mode = true
	_open("Misiones","Objetivos actuales y progreso")
	_phone_metric("01 · Albertico",_objective())
	var carlos_stage := int(ledger.life_data.get("carlos_paint",{}).get("stage",0))
	var carlos_text := String(carlos_objective.call()) if carlos_objective.is_valid() else ""
	_phone_metric("02 · Carlos",carlos_text if not carlos_text.is_empty() else ("Trabajo completado" if carlos_stage>=5 else "Disponible tras el negocio de Albertico"))
	var yordi_stage := int(ledger.life_data.get("yordi_ps5",{}).get("stage",0))
	var yordi_text := String(yordi_objective.call()) if yordi_objective.is_valid() else ""
	_phone_metric("03 · Yordi",yordi_text if not yordi_text.is_empty() else ("Misión completada" if yordi_stage>=14 else "Pendiente de desbloquear"))
	if city_map.is_valid(): _button("Abrir mapa",city_map)
	_button("Inicio",open_phone_home)

func open_business_summary() -> void:
	_open("Mi negocio","Resumen de tu actividad comercial")
	_phone_metric("Dinero disponible","%d CUP" % ledger.cash)
	_phone_metric("Ventas realizadas",str(ledger.sold))
	_phone_metric("Ingresos acumulados","%d CUP" % ledger.revenue)
	_phone_metric("Comisiones pagadas","%d CUP" % ledger.wages)
	_phone_metric("Mercancía disponible",_stock_text())
	_button("Inicio",open_phone_home)

func open_messages() -> void:
	phone_mode = true
	ledger.unread = 0
	ledger.save_game()
	_open("Mensajes","Conversaciones")
	var threads: Dictionary = {}
	var order: Array = []
	for i in range(ledger.messages.size()-1,-1,-1):
		var item: Dictionary = ledger.messages[i]
		var sender := String(item.get("sender",""))
		var name_value := sender.trim_prefix("Tú → ") if sender.begins_with("Tú → ") else sender
		if not threads.has(name_value):
			threads[name_value] = String(item.get("body","")).replace("\n"," ")
			order.append(name_value)
	for name_value in order:
		var preview := String(threads[name_value])
		if preview.length()>60: preview = preview.left(60)+"…"
		var row := Button.new()
		row.text = String(name_value)+"\n"+preview
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.custom_minimum_size.y = 70
		row.icon = _phone_icon("contact",Color("#46647f"))
		row.add_theme_constant_override("icon_max_width",38)
		row.pressed.connect(_phone_thread.bind(String(name_value)))
		content.add_child(row)
	if order.is_empty(): _phone_metric("No tienes mensajes","Las conversaciones aparecerán aquí.")

# The phone is its own canvas panel; in-world menus retain their original layout.
func _phone_style(color: Color,radius: int,border: Color = Color.TRANSPARENT,width: int = 0,pad: int = 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad
	style.content_margin_bottom = pad
	return style

func _make_phone() -> void:
	phone_panel = PanelContainer.new()
	layer.add_child(phone_panel)
	phone_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	_resize_phone()
	get_viewport().size_changed.connect(_resize_phone)
	var frame := _phone_style(Color("#101822"),30,Color("#5b6877"),3,16)
	frame.shadow_color = Color(0,0,0,.45)
	frame.shadow_size = 12
	phone_panel.add_theme_stylebox_override("panel",frame)
	var theme := Theme.new()
	theme.default_font_size = 15
	theme.set_color("font_color","Label",Color("#edf4fa"))
	theme.set_color("font_color","Button",Color("#f3f7fa"))
	theme.set_color("font_hover_color","Button",Color.WHITE)
	theme.set_color("font_disabled_color","Button",Color("#758596"))
	theme.set_stylebox("normal","Button",_phone_style(Color("#243449"),12,Color("#394c60"),1,10))
	theme.set_stylebox("hover","Button",_phone_style(Color("#31485d"),12,Color("#6c879c"),1,10))
	theme.set_stylebox("pressed","Button",_phone_style(Color("#3b586c"),12,Color("#7d9ab1"),1,10))
	theme.set_stylebox("disabled","Button",_phone_style(Color("#1b2634"),12,Color("#273849"),1,10))
	theme.set_stylebox("focus","Button",_phone_style(Color.TRANSPARENT,12,Color("#9ac6da"),2,0))
	phone_panel.theme = theme
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation",9)
	phone_panel.add_child(shell)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	shell.add_child(top)
	phone_clock = Label.new()
	phone_clock.text = "08:00"
	phone_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phone_clock.add_theme_font_size_override("font_size",14)
	top.add_child(phone_clock)
	var camera_cutout := PanelContainer.new()
	camera_cutout.custom_minimum_size = Vector2(68,17)
	camera_cutout.add_theme_stylebox_override("panel",_phone_style(Color("#05090e"),10,Color("#25313d"),1,0))
	top.add_child(camera_cutout)
	var network := Label.new()
	network.text = "MyCity"
	network.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	network.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	network.add_theme_font_size_override("font_size",12)
	top.add_child(network)
	var nav := HBoxContainer.new()
	shell.add_child(nav)
	var home := Button.new()
	home.text = "Inicio"
	home.pressed.connect(open_phone_home)
	nav.add_child(home)
	phone_title = Label.new()
	phone_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phone_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phone_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	phone_title.add_theme_font_size_override("font_size",18)
	nav.add_child(phone_title)
	var quit := Button.new()
	quit.text = "×"
	quit.custom_minimum_size.x = 42
	quit.pressed.connect(close)
	nav.add_child(quit)
	phone_scroll = ScrollContainer.new()
	phone_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	phone_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	shell.add_child(phone_scroll)
	phone_content = VBoxContainer.new()
	phone_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	phone_content.add_theme_constant_override("separation",10)
	phone_scroll.add_child(phone_content)
	var bar := Button.new()
	bar.text = "━━━━━━"
	bar.custom_minimum_size.y = 29
	bar.flat = true
	bar.add_theme_color_override("font_color",Color("#b4c4d2"))
	bar.pressed.connect(open_phone_home)
	shell.add_child(bar)
	phone_panel.hide()

func _resize_phone() -> void:
	if not is_instance_valid(phone_panel): return
	var dimensions := Interface.phone_size(get_viewport().get_visible_rect().size)
	phone_panel.offset_left = -dimensions.x-12.0
	phone_panel.offset_right = -12.0
	phone_panel.offset_top = -dimensions.y*.5
	phone_panel.offset_bottom = dimensions.y*.5
	# Keep the explicit target size rather than shrinking to content minimum.

func _update_phone_status() -> void:
	if not phone_mode or not is_instance_valid(phone_clock): return
	var minute := int(life.state.get("minutes",480))%1440 if life!=null else 480
	phone_clock.text = "%02d:%02d" % [floori(float(minute)/60.0),minute%60]
	if is_instance_valid(phone_balance): phone_balance.text = "%d CUP" % ledger.cash

func _phone_icon(key: String,color: Color) -> Texture2D:
	var cache_key := key+color.to_html()
	if phone_icons.has(cache_key): return phone_icons[cache_key]
	var paths := {
		"message":"<path d='M12 13h24v17H22l-7 6v-6h-3z'/><path d='M18 20h12M18 25h8'/>",
		"contact":"<circle cx='24' cy='17' r='6'/><path d='M13 35v-3a11 11 0 0 1 22 0v3z'/>",
		"business":"<path d='M12 35h24M15 31V22M23 31V14M31 31V18'/><path d='M13 17l9-6 8 2 6-5'/>",
		"shop":"<path d='M12 20h24l-3-9H15zM15 20v16h18V20M20 36V25h8v11'/>",
		"bag":"<path d='M13 18h22l2 19H11zM19 18v-4a5 5 0 0 1 10 0v4'/>",
		"pack":"<rect x='13' y='15' width='22' height='23' rx='5'/><path d='M20 15v-3h8v3M17 27h14v7H17z'/>",
		"pin":"<path d='M24 39s-12-13-12-21a12 12 0 0 1 24 0c0 8-12 21-12 21z'/><circle cx='24' cy='18' r='4'/>"
	}
	var svg := "<svg xmlns='http://www.w3.org/2000/svg' width='48' height='48' viewBox='0 0 48 48'><rect width='48' height='48' rx='12' fill='#"+color.to_html(false)+"'/><g fill='none' stroke='white' stroke-width='2.1' stroke-linecap='round' stroke-linejoin='round'>"+String(paths.get(key,paths.contact))+"</g></svg>"
	var img := Image.new()
	img.load_svg_from_string(svg,2.0)
	var texture := ImageTexture.create_from_image(img)
	phone_icons[cache_key] = texture
	return texture

func _phone_metric(label_value: String,value: String) -> void:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel",_phone_style(Color("#1b2a39"),13,Color("#34485c"),1,12))
	content.add_child(card)
	var stack := VBoxContainer.new()
	card.add_child(stack)
	var label := Label.new()
	label.text = label_value
	label.add_theme_color_override("font_color",Color("#a4bed0"))
	label.add_theme_font_size_override("font_size",12)
	stack.add_child(label)
	var result := Label.new()
	result.text = value
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.add_theme_font_size_override("font_size",20)
	stack.add_child(result)

func _phone_thread(name_value: String) -> void:
	phone_mode = true
	_open(name_value,"Historial de conversación")
	for item in ledger.messages:
		var sender := String(item.get("sender",""))
		var outgoing := sender.begins_with("Tú → ")
		var other := sender.trim_prefix("Tú → ") if outgoing else sender
		if other!=name_value: continue
		var bubble := PanelContainer.new()
		bubble.size_flags_horizontal = Control.SIZE_SHRINK_END if outgoing else Control.SIZE_SHRINK_BEGIN
		bubble.custom_minimum_size.x = 0
		bubble.add_theme_stylebox_override("panel",_phone_style(Color("#245b51") if outgoing else Color("#25374b"),15,Color.TRANSPARENT,0,11))
		content.add_child(bubble)
		var message := Label.new()
		message.text = String(item.get("body",""))
		message.custom_minimum_size.x = minf(260.0,maxf(150.0,Interface.phone_size(get_viewport().get_visible_rect().size).x-100.0))
		message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bubble.add_child(message)
	if life!=null:
		for id in life.state.contacts:
			if life.sites.has(id) and String(life.sites[id].contact)==name_value:
				_button("Preguntar qué tiene disponible",life._ask_stock.bind(String(id)))
				_button("Ver contacto",life._contact_page.bind(String(id)))
				break
	if name_value=="Albertico" and ledger.stage==0 and bool(ledger.life_data.get("albertico_invited",false)) and not ledger.albertico_visible():
		_button("Quedar con Albertico",_meet_albertico)
	if name_value=="Carlos" and carlos_call.is_valid(): _button("Llamar a Carlos",carlos_call)
	if name_value=="Yordi" and yordi_call.is_valid(): _button("Llamar a Yordi",yordi_call)
	_button("Volver a mensajes",open_messages)
	phone_scroll.set_deferred("scroll_vertical",100000)

func _meet_albertico() -> void:
	if not is_instance_valid(albertico): return
	if ledger.meet_albertico():
		close()
		_sync_visuals()
		_notify("Albertico te espera afuera de tu casa.")
		if first_story!=null: first_story.prepare_meeting()

func open_phone_gps() -> void:
	phone_mode = true
	_open("GPS","Coordenadas del mapa de la ciudad")
	if city_map.is_valid(): _button("Abrir mapa de la ciudad",city_map)
	var at: Vector3 = phone_position.call() if phone_position.is_valid() else player.global_position
	var current := world.geography.coordinate_text(at)
	_phone_metric("Ubicación actual",current)
	if phone_destination.is_valid():
		var destination: Dictionary = phone_destination.call()
		if not destination.is_empty():
			_phone_metric("Destino activo",String(destination.label)+" · "+Interface.distance_text(float(destination.distance)))
	_button("Copiar coordenadas",_copy_phone_gps.bind(current))
	if not world.garage_home_site.is_empty():
		var door: Vector3 = world.garage_home_site.door
		var home := world.geography.coordinate_text(door)
		_phone_metric("Mi casa",home)
		_button("Copiar ubicación de casa",_copy_phone_gps.bind(home))
	_button("Inicio",open_phone_home)

func _copy_phone_gps(value: String) -> void:
	DisplayServer.clipboard_set(value)
	_notify("Coordenadas copiadas.")

func _clear_visual_children(root: Node3D) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()

func _sync_visuals() -> void:
	if arrow==null: return
	albertico.visible = ledger.albertico_visible() and (first_story==null or (not first_story.rider_trip and first_story.fetch_phase!="inside"))
	arrow.visible = ledger.albertico_visible() and (ledger.stage==0 or (ledger.stage==3 and (first_story==null or not first_story.active())))
	factory_arrow.visible = ledger.stage in [1,2]
	stand.visible = ledger.stage==4 or (first_story!=null and first_story._phase()=="handshake") or (ledger.stage>=1 and not ledger.life_data.has("albertico_story"))
	var tier := stall_tier(ledger.sold) if ledger.stage==4 else 0
	for i in range(stall_growth.size()): stall_growth[i].visible = tier>=i+1
	if is_instance_valid(stall_sign):
		stall_sign.text = "ALBERTICO · ABIERTO" if ledger.stage==4 else "ALIMENTOS · ALBERTICO"
	# Refresh only what changed; sales must not recreate paid boxes, cargo or hands.
	var pending_key := JSON.stringify(ledger.pending)
	if pending_visual_key!=pending_key:
		pending_visual_key = pending_key
		_clear_visual_children(crate_rack)
		var slot := 0
		for key in Ledger.PRODUCTS:
			for i in range(mini(int(ledger.pending.get(key,0)),6)):
				if slot>=9: break
				_selectable_crate(crate_rack,Vector3(-.55+float(slot%3)*.55,.206+floorf(float(slot)/3.0)*.34,0),String(key),true)
				slot += 1
	var stock_key := JSON.stringify(ledger.stock)
	if stock_visual_key!=stock_key:
		stock_visual_key = stock_key
		_clear_visual_children(stock_display)
		var product_slot := 0
		# Three compact packages fit the original surface. The ledger retains all products.
		for key in Ledger.PRODUCTS:
			if int(ledger.stock.get(key,0))<=0 or product_slot>=3: continue
			var visual := _crate(stock_display,Vector3(-.46+float(product_slot)*.46,.98,0),String(key))
			visual.scale = Vector3.ONE*.78
			product_slot += 1
	if carry_visual_key!=ledger.carry:
		carry_visual_key = ledger.carry
		_clear_visual_children(crate_view)
		if is_instance_valid(carry_tween): carry_tween.kill()
		crate_view.position = CARRY_REST
		if not ledger.carry.is_empty():
			_crate(crate_view,Vector3.ZERO,ledger.carry)
			# Quick lift into the player's view. The purchase is already committed.
			crate_view.position = CARRY_REST+Vector3(0,-.23,.08)
			carry_tween = create_tween()
			carry_tween.tween_property(crate_view,"position",CARRY_REST,.24).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	crate_view.visible = not ledger.carry.is_empty()
	var cargo_key := JSON.stringify(ledger.cargo)
	if cargo_visual_key!=cargo_key:
		cargo_visual_key = cargo_key
		_sync_cargo_views()
	taxis.business_enabled = ledger.stage>=1

func _sync_cargo_views() -> void:
	# Crate count labels above the actual carrying vehicle, independent of
	# the imported vehicle mesh or whether its trunk can be animated.
	for key in cargo_views:
		var old: Label3D = cargo_views[key]
		if is_instance_valid(old):
			old.hide()
			old.queue_free()
	cargo_views.clear()
	for key in ledger.cargo:
		var count := ledger.total(ledger.cargo[key])
		if count<=0: continue
		var body: CharacterBody3D = null
		if key=="van":
			body = van
		elif String(key).begins_with("taxi_"):
			var index := int(String(key).trim_prefix("taxi_"))
			if index>=0 and index<taxis.taxis.size():
				body = taxis.taxis[index].body
		if body==null: continue
		cargo_views[key] = _label(body,"%d cajas · G" % count,Vector3(0,2.65,0),Color("#ffe19a"))

func _objective() -> String:
	if first_story!=null and first_story.active(): return first_story.objective()
	if albertico==null: return "Misión no disponible: falta la MIPYME o el puesto."
	match ledger.stage:
		0:
			if ledger.albertico_visible(): return "Habla con Albertico afuera de tu casa."
			if bool(ledger.life_data.get("albertico_invited",false)): return "P · Mensajes · Responde a Albertico."
			return "Explora la ciudad. Pronto recibirás un mensaje."
		1: return "Toma un taxi y selecciona MIPYME de alimentos."
		2: return "Compra cajas y cárgalas en el carro con G."
		3:
			if ledger.total(ledger.stock)>0: return "Contrata a Albertico para vender."
			return "Vuelve al puesto, descarga con G y entrega con E."
		4: return "Negocio activo · Repón mercancía cuando Albertico avise."
	return ""

func _update_hud() -> void:
	var carrying := " | Caja: "+_product_name(ledger.carry) if not ledger.carry.is_empty() else ""
	var phone := "P: teléfono"
	if ledger.unread>0: phone += " (%d nuevos)" % ledger.unread
	if hud_expanded:
		hud.text = "%d CUP%s\n%s\n%s | G: cargar / descargar" % [ledger.cash,carrying,_objective(),phone]
	else:
		hud.text = "%d CUP%s | %s" % [ledger.cash,carrying,phone]
		if first_story!=null and first_story.active(): hud.text += "\n"+first_story.objective()
	if carlos_objective.is_valid():
		var job: String = carlos_objective.call()
		if not job.is_empty(): hud.text += "\n"+job
	if yordi_objective.is_valid():
		var yordi_job: String = yordi_objective.call()
		if not yordi_job.is_empty(): hud.text += "\n"+yordi_job
	_refresh_notice()

# Sales and stock remain independent of the visual customer. If no
# verified doorway can reach the stall, do not fake a walk through a wall.
func _start_buyer(product_key: String = "") -> void:
	if buyer==null or not buyer_path.is_empty() or stand==null or world.pedestrian_router==null: return
	var trip: Dictionary = world.pedestrian_router.call("customer_trip",stand.global_position,world.business_frontage.global_transform.basis)
	if trip.is_empty(): return
	var path: PackedVector3Array = trip.path
	if path.size()<2 or not world.pedestrian_segment_clear(path[0],path[0]): return
	var door: Dictionary = trip.door
	buyer_normal = door.normal
	buyer_path = path
	buyer_index = 1
	buyer_time = 0.0
	buyer_returning = false
	buyer_blocked = 0.0
	buyer_product = product_key
	buyer_served = false
	buyer.set_bag(false)
	buyer.global_position = buyer_path[0]
	buyer.rotation.y = atan2(buyer_normal.x,buyer_normal.z)
	buyer.show()

func _tick_buyer(delta: float) -> void:
	if buyer==null or buyer_path.is_empty(): return
	if buyer.conversation_active(delta): return
	if not buyer_returning and buyer_index>=buyer_path.size():
		buyer.animate(delta,false)
		var facing := stand.global_position-buyer.global_position
		facing.y = 0.0
		if facing.length_squared()>.01: buyer.rotation.y = lerp_angle(buyer.rotation.y,atan2(facing.x,facing.z),minf(delta*8.0,1.0))
		buyer_time += delta
		if buyer_time>=.5 and not buyer_served:
			buyer_served = true
			buyer.set_bag(true)
			if is_instance_valid(buyer.carried):
				var key := buyer_product
				for product_key in Ledger.PRODUCTS:
					if String(Ledger.PRODUCTS[product_key].name)==buyer_product:
						key = String(product_key)
						break
				_box(buyer.carried,Vector3(0,.025,.19),Vector3(.15,.10,.015),crate_band(key))
		if is_instance_valid(albertico) and albertico is Person:
			albertico.arms[1].rotation.x = lerpf(albertico.arms[1].rotation.x,-.85,minf(delta*8.0,1.0))
		if buyer_time>=2.0:
			buyer_returning = true
			buyer_index = buyer_path.size()-2
		return
	if buyer_returning and buyer_index<0:
		# The entire return route has been completed. Disappear only at
		# the same registered doorway, never at an arbitrary wall or timer.
		if buyer.global_position.distance_to(buyer_path[0])<.14:
			buyer.rotation.y = atan2(-buyer_normal.x,-buyer_normal.z)
			buyer.hide()
			buyer.set_bag(false)
			buyer_path = PackedVector3Array()
		return
	var target: Vector3 = buyer_path[buyer_index]
	var next := buyer.global_position.move_toward(target,maxf(.12,1.5*delta))
	if not world.pedestrian_segment_clear(buyer.global_position,next):
		buyer.animate(delta,false)
		buyer_blocked += delta
		# A blocked customer can abort the approach and return to the
		# previous waypoint; if the way home is blocked, wait visibly.
		if not buyer_returning and buyer_blocked>2.0:
			buyer_returning = true
			buyer_index = maxi(0,buyer_index-1)
			buyer_blocked = 0.0
		return
	buyer_blocked = 0.0
	if buyer.walk_to(target,delta,1.5):
		buyer_index += -1 if buyer_returning else 1

func tick(delta: float,in_vehicle: bool,editor: bool) -> void:
	if life!=null: life.tick(delta,in_vehicle,editor)
	if ledger.stage==0 and not ledger.albertico_visible() and not bool(ledger.life_data.get("albertico_invited",false)) and not editor and not in_vehicle and not modal_open() and is_instance_valid(albertico):
		albertico_intro_clock += delta
		if albertico_intro_clock>=ALBERTICO_INVITE_DELAY and ledger.invite_albertico():
			phone_ring.play()
			_notify("Nuevo mensaje de Albertico · P para leerlo")
	phase += delta
	# Only two stationary merchants; animate when near the camera.
	if not editor and is_instance_valid(camera):
		for merchant in get_tree().get_nodes_in_group("mission_merchant_visuals"):
			if merchant is Person and merchant.is_visible_in_tree() and merchant.global_position.distance_squared_to(camera.global_position)<625.0:
				merchant.animate(delta,false)
	delivery_gesture = maxf(0.0,delivery_gesture-delta)
	if delivery_gesture>0.0 and is_instance_valid(albertico) and albertico is Person:
		for arm in albertico.arms: arm.rotation.x = lerpf(arm.rotation.x,-.9,minf(delta*10.0,1.0))
	toast_time = maxf(0.0,toast_time-delta)
	hud.visible = not editor
	_refresh_notice()
	if crate_view!=null: crate_view.visible = not in_vehicle and not editor and not ledger.carry.is_empty()
	if arrow!=null:
		arrow.position.y = 2.68+sin(phase*3.0)*.13
		factory_arrow.position.y = 1.90+sin(phase*3.0)*.13
	if ledger.stage==4 and not editor:
		ledger.sales_clock += delta
		if ledger.sales_clock>=18.0:
			ledger.sales_clock = 0.0
			var before := ledger.unread
			var sale := ledger.sell_one()
			if not sale.is_empty():
				_notify("Albertico vendió "+String(sale.product)+" · +%d CUP" % int(sale.net))
				if ledger.unread>before:
					_notify("Albertico te llama · P para leer su mensaje")
					phone_ring.play()
				_start_buyer(String(sale.product))
				_sync_visuals()
	if not editor: _tick_buyer(delta)
	refresh += delta
	if refresh>=.18:
		refresh = 0.0
		_update_hud()
		_update_phone_status()
