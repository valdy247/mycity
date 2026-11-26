extends Node3D
const Ledger = preload("res://business_ledger.gd")
const World = preload("res://cuba_world.gd")
const Taxi = preload("res://taxi_service.gd")
const Person = preload("res://street_person.gd")
const CityLife = preload("res://city_life.gd")
var life: CityLife
var ledger := Ledger.new()
var world: World
var taxis: Taxi
var player: CharacterBody3D
var van: CharacterBody3D
var camera: Camera3D
var albertico: Node3D
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
var cargo_views: Dictionary = {}
var hud: Label
var hud_expanded := false
var panel: PanelContainer
var content: VBoxContainer
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

func _person(root: Node3D,shirt: Color) -> Node3D:
	var npc := Node3D.new()
	root.add_child(npc)
	var skin := Color("#b98762")
	_box(npc,Vector3(0,1.17,0),Vector3(.43,.62,.29),shirt)
	_box(npc,Vector3(0,1.67,0),Vector3(.29,.33,.28),skin)
	_box(npc,Vector3(0,1.86,0),Vector3(.30,.10,.29),Color("#3e332b"))
	for side in [-1.0,1.0]:
		var x := float(side)
		_box(npc,Vector3(x*.115,.47,0),Vector3(.18,.76,.23),Color("#465263"))
		_box(npc,Vector3(x*.115,.075,.06),Vector3(.19,.15,.30),Color("#33342e"))
		_box(npc,Vector3(x*.28,1.11,0),Vector3(.12,.51,.14),skin)
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

func _crate(root: Node3D,p: Vector3,key: String) -> Node3D:
	var node := Node3D.new()
	root.add_child(node)
	node.position = p
	var color := Color("#b79a72")
	_box(node,Vector3.ZERO,Vector3(.52,.34,.40),color)
	_box(node,Vector3(0,.174,0),Vector3(.085,.012,.40),Color("#ddd0a9"))
	var band := Color("#ac5348") if key=="pollo" else (Color("#63825b") if key=="picadillo" else Color("#487eaa"))
	_box(node,Vector3(0,0,.204),Vector3(.46,.105,.012),band)
	return node

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

func _make_scene() -> void:
	if world.business_frontage==null or world.food_factory.is_empty(): return
	var home := world.business_frontage
	albertico = _person(self,Color("#638e77"))
	albertico.position = home.to_global(Vector3(-2.55,.105,2.85))
	albertico.rotation.y = home.rotation.y
	_label(albertico,"Albertico",Vector3(0,2.03,0))
	arrow = _arrow(albertico,Vector3(0,2.68,0),Color("#49ff72"))
	stand = Node3D.new()
	add_child(stand)
	stand.position = home.to_global(Vector3(-2.55,.105,3.66))
	stand.rotation.y = home.rotation.y
	_box(stand,Vector3(0,.79,0),Vector3(1.45,.09,.62),Color("#a88b64"))
	for x in [-.61,.61]:
		for z in [-.23,.23]:
			_box(stand,Vector3(float(x),.39,float(z)),Vector3(.075,.78,.075),Color("#725f47"))
	_label(stand,"VENTA DE ALIMENTOS",Vector3(0,1.33,0))
	stock_display = Node3D.new()
	stand.add_child(stock_display)
	buyer = Person.new()
	add_child(buyer)
	buyer.setup(210)
	buyer.social_context = "shopping"
	buyer.hide()
	var counter: Vector3 = world.food_factory.counter
	var clerk := _person(self,Color("#8196b0"))
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
	crate_rack.position = pickup+basis*Vector3(0,-.10,-1.3)
	crate_rack.rotation.y = basis.get_euler().y
	purchase_rack = Node3D.new()
	add_child(purchase_rack)
	purchase_rack.position = counter+basis*Vector3(0,-.10,.05)
	purchase_rack.rotation.y = basis.get_euler().y
	var primary_products := ["pollo","picadillo","perrito"]
	for i in range(primary_products.size()):
		var key := String(primary_products[i])
		var product: Dictionary = Ledger.PRODUCTS[key]
		var at := Vector3(-.70+float(i)*.70,.17,0)
		_selectable_crate(purchase_rack,at,key,false)
		_label(purchase_rack,"%s · %d CUP" % [product.name,product.cost],at+Vector3(0,.43,0))
	crate_view = Node3D.new()
	camera.add_child(crate_view)
	crate_view.position = Vector3(.26,-.31,-.88)
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
	panel = PanelContainer.new()
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -240
	panel.offset_right = 240
	panel.offset_top = -200
	panel.offset_bottom = 200
	var margin := MarginContainer.new()
	for side in ["left","right","top","bottom"]:
		margin.add_theme_constant_override("margin_"+side,16)
	panel.add_child(margin)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation",9)
	margin.add_child(content)
	panel.hide()
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
	return panel!=null and panel.visible

func close() -> void:
	panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _open(title: String,body: String = "") -> void:
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size",23)
	content.add_child(heading)
	if not body.is_empty():
		var description := Label.new()
		description.text = body
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.custom_minimum_size.x = 390
		content.add_child(description)
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _button(text_value: String,callback: Callable,disabled_value: bool = false) -> void:
	var button := Button.new()
	button.text = text_value
	button.disabled = disabled_value
	button.pressed.connect(callback)
	content.add_child(button)

func _notify(value: String) -> void:
	toast = value
	toast_time = 5.0

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

func action_text(at: Vector3) -> String:
	if life!=null:
		var context := life.action_text(at)
		if not context.is_empty(): return context
	if albertico==null: return ""
	if _near(at,albertico.position,2.0):
		if ledger.stage==0: return "[E] Hablar con Albertico"
		if not ledger.carry.is_empty() and ledger.stage>=3: return "[E] Entregar caja a Albertico"
		if ledger.stage==3 and ledger.total(ledger.stock)>0: return "[E] Contratar a Albertico"
		return "[E] Hablar con Albertico"
	if not world.food_factory.is_empty():
		if _near(at,world.food_factory.pickup,2.0) or _near(at,world.food_factory.counter,2.0): return "MIPYME · Mira una caja y pulsa E"
	return ""

func interact(at: Vector3) -> bool:
	if take_aimed(at): return true
	if life!=null and life.interact(at): return true
	var action := action_text(at)
	if action.is_empty(): return false
	if action.contains("Albertico"):
		if ledger.stage==0:
			_open("Albertico","Asere, te tengo un bisne. Te voy a dar la luz: hay una gente que vende comida. Tú me la traes y yo la vendo. ¿Te sirve?")
			_button("Sí, vamos arriba",_accept)
			_button("No, ahora no",close)
		elif not ledger.carry.is_empty() and ledger.stage>=3:
			if ledger.deliver():
				_notify("Caja entregada. "+_stock_text())
				_sync_visuals()
		elif ledger.stage==3 and ledger.total(ledger.stock)>0:
			_open("Albertico","Déjame la mercancía aquí. Yo la vendo y me quedo con el 15% de cada venta. ¿Hacemos el negocio?")
			_button("Contratar a Albertico",_hire)
			_button("Ahora no",close)
		else:
			_open("Albertico","Trae las cajas de la MIPYME, cárgalas en el carro y déjamelas aquí.\n\n"+_stock_text())
			_button("Cerrar",close)
	else:
		if life!=null and life.sites.has("primary"):
			life._contact_page("primary")
		else: _notify("Mira directamente la caja que deseas y pulsa E.")
	return true

func _accept() -> void:
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
	_open("Mi teléfono","")
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color("#172432")
	skin.border_color = Color("#475867")
	skin.set_border_width_all(2)
	skin.set_corner_radius_all(24)
	skin.content_margin_left = 12
	skin.content_margin_right = 12
	skin.content_margin_top = 12
	skin.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel",skin)
	var balance := Label.new()
	balance.text = "%s CUP" % str(ledger.cash)
	balance.add_theme_font_size_override("font_size",28)
	content.add_child(balance)
	var apps := GridContainer.new()
	apps.columns = 2
	apps.add_theme_constant_override("h_separation",12)
	apps.add_theme_constant_override("v_separation",12)
	content.add_child(apps)
	_phone_tile(apps,"Mensajes · "+str(ledger.unread),open_messages)
	if life!=null: _phone_tile(apps,"Contactos",life.open_contacts)
	_phone_tile(apps,"Mi negocio",open_business_summary)
	_phone_tile(apps,"Cerrar",close)

func _phone_tile(root: Control,label_value: String,callback: Callable) -> void:
	var tile := Button.new()
	tile.text = label_value
	tile.custom_minimum_size = Vector2(184,76)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#304b62")
	style.set_corner_radius_all(15)
	tile.add_theme_stylebox_override("normal",style)
	tile.pressed.connect(callback)
	root.add_child(tile)

func open_business_summary() -> void:
	_open("MI NEGOCIO","Billetera: %d CUP\\nVendidas: %d | Ingresos: %d CUP | Comisión: %d CUP\\nStock: %s" % [ledger.cash,ledger.sold,ledger.revenue,ledger.wages,_stock_text()])
	_button("Inicio",open_phone_home)

func open_messages() -> void:
	ledger.unread = 0
	ledger.save_game()
	_open("TELÉFONO · Mensajes","Billetera: %d CUP\nVendidas: %d | Ingresos: %d CUP | Comisión: %d CUP\nStock: %s" % [ledger.cash,ledger.sold,ledger.revenue,ledger.wages,_stock_text()])
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(390,205)
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	if ledger.messages.is_empty():
		var empty := Label.new()
		empty.text = "No tienes mensajes."
		list.add_child(empty)
	for i in range(ledger.messages.size()-1,-1,-1):
		var message: Dictionary = ledger.messages[i]
		var entry := Label.new()
		entry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		entry.custom_minimum_size.x = 365
		entry.text = String(message.sender)+"\n"+String(message.body)+"\n"
		list.add_child(entry)
	_button("Inicio",open_phone_home)
	_button("Cerrar",close)

func _sync_visuals() -> void:
	if arrow==null: return
	arrow.visible = ledger.stage==0 or ledger.stage==3
	factory_arrow.visible = ledger.stage in [1,2]
	stand.visible = ledger.stage==4 or (ledger.stage==3 and ledger.total(ledger.stock)>0)
	for root in [crate_rack,crate_view,stock_display]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()
	var slot := 0
	for key in Ledger.PRODUCTS:
		for i in range(mini(int(ledger.pending.get(key,0)),6)):
			if slot>=9: break
			_selectable_crate(crate_rack,Vector3(-.58+float(slot%3)*.58,.17+floorf(float(slot)/3.0)*.35,0),String(key),true)
			slot += 1
	var product_slot := 0
	for key in Ledger.PRODUCTS:
		if int(ledger.stock.get(key,0))>0:
			_crate(stock_display,Vector3(-.48+float(product_slot)*.48,1.01,0),String(key))
			product_slot += 1
	if not ledger.carry.is_empty():
		_crate(crate_view,Vector3.ZERO,ledger.carry)
	crate_view.visible = not ledger.carry.is_empty()
	_sync_cargo_views()
	taxis.business_enabled = ledger.stage>=1

func _sync_cargo_views() -> void:
	# Crate count labels above the actual carrying vehicle, independent of
	# the imported vehicle mesh or whether its trunk can be animated.
	for key in cargo_views:
		var old: Label3D = cargo_views[key]
		if is_instance_valid(old): old.queue_free()
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
	if albertico==null: return "Misión no disponible: falta la MIPYME o el puesto."
	match ledger.stage:
		0: return "Habla con Albertico en su puesto de Monte."
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
	if toast_time>0: hud.text += "\n"+toast

# Sales and stock remain independent of the visual customer. If no
# verified doorway can reach the stall, do not fake a walk through a wall.
func _start_buyer() -> void:
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
	buyer.global_position = buyer_path[0]
	buyer.rotation.y = atan2(buyer_normal.x,buyer_normal.z)
	buyer.show()

func _tick_buyer(delta: float) -> void:
	if buyer==null or buyer_path.is_empty(): return
	if not buyer_returning and buyer_index>=buyer_path.size():
		buyer.animate(delta,false)
		buyer_time += delta
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
	phase += delta
	toast_time = maxf(0.0,toast_time-delta)
	hud.visible = not editor
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
				_start_buyer()
				_sync_visuals()
	if not editor: _tick_buyer(delta)
	refresh += delta
	if refresh>=.18:
		refresh = 0.0
		_update_hud()
