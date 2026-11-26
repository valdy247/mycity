extends Node3D
const Ledger = preload("res://business_ledger.gd")
const World = preload("res://cuba_world.gd")
const Taxi = preload("res://taxi_service.gd")
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
var buyer: Node3D
var buyer_origin := Vector3.ZERO
var buyer_time := 0.0
var hud: Label
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
	_sync_visuals()
	_update_hud()
	if world.food_factory.is_empty() or world.home_root==null:
		_notify("La primera misión requiere una casa y una parcela libre para la fábrica.")
	else:
		taxis.set_business_points(world.food_factory.road,world.home_edge.get("a",world.home_spawn),true)

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

func _make_scene() -> void:
	if world.home_root==null or world.food_factory.is_empty(): return
	var home := world.home_root
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
	buyer_origin = home.to_global(Vector3(2.5,.105,3.15))
	buyer = _person(self,Color("#a19bca"))
	buyer.position = buyer_origin
	buyer.hide()
	var counter: Vector3 = world.food_factory.counter
	var clerk := _person(self,Color("#8196b0"))
	var basis: Basis = world.food_factory.basis
	clerk.position = counter+basis*Vector3(0,-.84,-2.05)
	clerk.rotation.y = basis.get_euler().y
	_label(clerk,"Mayorista",Vector3(0,2.02,0))
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
	hud.add_theme_font_size_override("font_size",16)
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
	var vehicle := _nearest_vehicle(at)
	if vehicle.is_empty():
		_notify("Acércate a la van o a un taxi detenido.")
		return true
	var id := String(vehicle.id)
	if not ledger.carry.is_empty():
		if ledger.load_vehicle(id):
			_notify("Caja cargada. Ahora viaja a casa o sigue comprando.")
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
			_notify("Llegaste a la fábrica. Habla con el mayorista.")
			_sync_visuals()

func action_text(at: Vector3) -> String:
	if albertico==null: return ""
	if _near(at,albertico.position,2.0):
		if ledger.stage==0: return "[E] Hablar con Albertico"
		if not ledger.carry.is_empty() and ledger.stage>=3: return "[E] Entregar caja a Albertico"
		if ledger.stage==3 and ledger.total(ledger.stock)>0: return "[E] Contratar a Albertico"
		return "[E] Hablar con Albertico"
	if not world.food_factory.is_empty():
		if _near(at,world.food_factory.pickup,1.55): return "[E] Recoger caja"
		if _near(at,world.food_factory.counter,1.65): return "[E] Comprar al por mayor"
	return ""

func interact(at: Vector3) -> bool:
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
			_open("Albertico","Trae las cajas de la fábrica, cárgalas en el carro y déjamelas aquí.\n\n"+_stock_text())
			_button("Cerrar",close)
	elif action.contains("Comprar"):
		_open_shop()
	else:
		_open_pickup()
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
		_open("Fábrica de alimentos","Primero habla con Albertico y llega aquí en taxi.")
		_button("Cerrar",close)
		return
	_open("Fábrica · Venta mayorista","Billetera: %d CUP. Cada caja contiene 10 unidades. Compra y recógelas en el mostrador de cajas." % ledger.cash)
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
	_button("Guardar y cerrar",close)

func _sync_visuals() -> void:
	if arrow==null: return
	arrow.visible = ledger.stage==0 or ledger.stage==3
	factory_arrow.visible = ledger.stage in [1,2]
	stand.visible = ledger.stage>=3 and ledger.total(ledger.stock)>0
	for root in [crate_rack,crate_view]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()
	var slot := 0
	for key in Ledger.PRODUCTS:
		for i in range(mini(int(ledger.pending.get(key,0)),6)):
			if slot>=9: break
			_crate(crate_rack,Vector3(-.58+float(slot%3)*.58,.17+floorf(float(slot)/3.0)*.35,0),String(key))
			slot += 1
	if not ledger.carry.is_empty():
		_crate(crate_view,Vector3.ZERO,ledger.carry)
	crate_view.visible = not ledger.carry.is_empty()
	taxis.business_enabled = ledger.stage>=1

func _objective() -> String:
	if albertico==null: return "Misión no disponible: falta la fábrica o vivienda."
	match ledger.stage:
		0: return "Habla con Albertico frente a tu casa."
		1: return "Toma un taxi y selecciona Fábrica de alimentos."
		2: return "Compra cajas y cárgalas en el carro con G."
		3:
			if ledger.total(ledger.stock)>0: return "Contrata a Albertico para vender."
			return "Vuelve a casa, descarga con G y entrega con E."
		4: return "Negocio activo · Repón mercancía cuando Albertico avise."
	return ""

func _update_hud() -> void:
	var carrying := " | Caja: "+_product_name(ledger.carry) if not ledger.carry.is_empty() else ""
	var phone := "P: teléfono"
	if ledger.unread>0: phone += " (%d nuevos)" % ledger.unread
	hud.text = "%d CUP%s\n%s\n%s | G: cargar / descargar" % [ledger.cash,carrying,_objective(),phone]
	if toast_time>0: hud.text += "\n"+toast

func tick(delta: float,in_vehicle: bool,editor: bool) -> void:
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
				if ledger.unread>before: _notify("Mensaje de Albertico · P para leer")
				if buyer!=null:
					buyer_time = 4.0
					buyer.position = buyer_origin
					buyer.show()
				_sync_visuals()
	if buyer!=null and buyer_time>0.0:
		buyer_time -= delta
		var target := stand.position+world.home_root.transform.basis.x*.9
		if buyer_time<1.5: target = buyer_origin
		buyer.position = buyer.position.move_toward(target,delta*1.5)
		var direction := target-buyer.position
		if direction.length()>.1: buyer.rotation.y = atan2(direction.x,direction.z)
		if buyer_time<=0.0: buyer.hide()
	refresh += delta
	if refresh>=.18:
		refresh = 0.0
		_update_hud()
