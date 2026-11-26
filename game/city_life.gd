extends Node3D
# City life runs on the existing game wallet and pedestrian navigation.
const Person = preload("res://street_person.gd")
const Ledger = preload("res://business_ledger.gd")
const MENU := {
	"pizza":{"name":"Pizza","price":160,"food":"pizza","drink":"","fill":30,"needs":{"harina":1,"queso":1,"tomate":1}},
	"refresco":{"name":"Refresco","price":60,"food":"","drink":"refresco","fill":8,"needs":{"refresco":1}},
	"combo":{"name":"Pizza + refresco","price":210,"food":"pizza","drink":"refresco","fill":38,"needs":{"harina":1,"queso":1,"tomate":1,"refresco":1}},
	"pan":{"name":"Pan con perro","price":120,"food":"pan","drink":"","fill":22,"needs":{"harina":1,"perrito":1}}
}
const INITIAL := {
	"primary":{"pollo":12,"picadillo":10,"perrito":12},
	"mayorista_sol":{"harina":15,"queso":12,"tomate":14,"refresco":12},
	"mayorista_union":{"aceite":12,"pollo":8,"perrito":9,"harina":8,"refresco":18,"tomate":10}
}
var business
var world
var ledger: Ledger
var sites: Dictionary = {}
var racks: Dictionary = {}
var agents: Array = []
var fullness_bar: ProgressBar
var clock_label: Label
var meal_root: Node3D
var food_view: Node3D
var drink_view: Node3D
var avatar_food: Node3D
var avatar_drink: Node3D
var food_model := ""
var drink_model := ""
var bite_anim := 0.0
var active_hand := -1
var meal_arms: Array = []
var last_first_person := true
var save_clock := 0.0
var economy_clock := 0.0
var agent_tick_clock := 0.0
var hud_tick_clock := 0.0
var state: Dictionary = {}
var rng := RandomNumberGenerator.new()

func setup(mission) -> void:
	business = mission
	world = mission.world
	ledger = mission.ledger
	state = ledger.life_data
	rng.randomize()
	if not state.has("fullness"): state.fullness = 100.0
	if not state.has("minutes"): state.minutes = 480.0
	if not state.has("supplies"): state.supplies = INITIAL.duplicate(true)
	if not state.has("cafes"): state.cafes = {}
	if not state.has("contacts"): state.contacts = {}
	if not state.has("met"): state.met = {}
	if not state.has("order"): state.order = {}
	if not state.has("meal"): state.meal = {}
	if not world.food_factory.is_empty():
		sites["primary"] = {"id":"primary","name":"MIPYME DE ALIMENTOS","kind":"wholesale","contact":"Ismael","center":world.food_factory.center,"basis":world.food_factory.basis}
	for site in world.commerce_sites:
		var id := String(site.id)
		sites[id] = site
		if String(site.kind)=="cafe" and not state.cafes.has(id):
			state.cafes[id] = {"harina":8,"queso":4,"tomate":10,"refresco":12,"perrito":8,"cash":3600}
		_make_site(site)
	_make_hud()
	meal_root = Node3D.new()
	business.camera.add_child(meal_root)
	food_view = Node3D.new()
	drink_view = Node3D.new()
	meal_root.add_child(food_view)
	meal_root.add_child(drink_view)
	food_view.position = Vector3(-.29,-.36,-.74)
	drink_view.position = Vector3(.29,-.36,-.74)
	_refresh_meal()
	refresh_primary()
	ledger.save_game()

func attach_avatar(arms: Array) -> void:
	if arms.size()<2: return
	meal_arms = arms
	avatar_food = Node3D.new()
	avatar_drink = Node3D.new()
	arms[0].add_child(avatar_food)
	arms[1].add_child(avatar_drink)
	avatar_food.position = Vector3(0,-.48,.10)
	avatar_drink.position = Vector3(0,-.48,.10)
	_refresh_meal()

func pose_meal(first_person: bool,delta: float) -> void:
	last_first_person = first_person
	if meal_root!=null: meal_root.visible = first_person and not state.meal.is_empty()
	if meal_arms.size()<2 or state.meal.is_empty(): return
	for i in range(2):
		var held := not food_model.is_empty() if i==0 else not drink_model.is_empty()
		if held:
			var arm: Node3D = meal_arms[i]
			arm.rotation.x = lerpf(arm.rotation.x,-1.80 if bite_anim>.05 and active_hand==i else -.85,minf(1.0,delta*12.0))

func _make_hud() -> void:
	fullness_bar = ProgressBar.new()
	business.layer.add_child(fullness_bar)
	fullness_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	fullness_bar.offset_left = 12
	fullness_bar.offset_right = 196
	fullness_bar.offset_top = -121
	fullness_bar.offset_bottom = -105
	fullness_bar.max_value = 100.0
	fullness_bar.show_percentage = false
	fullness_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#222c31")
	bg.set_corner_radius_all(6)
	fullness_bar.add_theme_stylebox_override("background",bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color("#7fbc81")
	fill.set_corner_radius_all(6)
	fullness_bar.add_theme_stylebox_override("fill",fill)
	clock_label = Label.new()
	business.layer.add_child(clock_label)
	clock_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	clock_label.offset_left = 12
	clock_label.offset_right = 240
	clock_label.offset_top = -143
	clock_label.offset_bottom = -122
	clock_label.add_theme_font_size_override("font_size",12)
	clock_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	clock_label.add_theme_constant_override("shadow_offset_y",2)
	clock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_hud()

func _update_hud() -> void:
	if fullness_bar==null: return
	fullness_bar.value = float(state.fullness)
	var minute := int(state.minutes)%1440
	clock_label.text = "Saciedad %d%%   ·   %02d:%02d" % [roundi(float(state.fullness)),floori(float(minute)/60.0),minute%60]

func _person(site: Dictionary,role: String,style: int,local: Vector3) -> Person:
	var person := Person.new()
	add_child(person)
	person.setup(style)
	person.female = role=="clerk" and String(site.kind)=="cafe" or String(site.contact)=="Lidia"
	var basis: Basis = site.basis
	var c: Vector3 = site.center
	person.global_position = c+basis*local
	person.rotation.y = basis.get_euler().y
	var name_value := String(site.contact) if role=="clerk" else String(site.owner)
	person.set_meta("citizen_id",String(site.id)+"_"+role)
	person.set_meta("citizen_name",name_value)
	person.set_meta("contact_site",String(site.id))
	person.social_context = "worker"
	agents.append({"node":person,"site":site.id,"role":role,"home":person.global_position,"path":PackedVector3Array(),"index":0,"task":"","timer":0.0,"departed":false,"trip_done":false})
	return person

func _make_site(site: Dictionary) -> void:
	var c: Vector3 = site.center
	var basis: Basis = site.basis
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(basis,c)
	var clerk_style := 301+sites.size()*3 if String(site.kind)=="cafe" or String(site.contact)=="Lidia" else 300+sites.size()*3
	var clerk := _person(site,"clerk",clerk_style,Vector3(0,.11,-1.25))
	business._label(clerk,String(site.contact),Vector3(0,2.0,0),Color("#f4ecd8"))
	if String(site.kind)=="wholesale":
		racks[site.id] = root
		_refresh_rack(String(site.id),root,false)
	else:
		_person(site,"owner",312+sites.size()*3,Vector3(2.45,.11,1.6))
		for side in [-1.0,1.0]:
			business._box(root,Vector3(float(side)*2.9,.40,1.1),Vector3(.80,.08,.80),Color("#bda37e"))
			business._box(root,Vector3(float(side)*2.9,.22,1.1),Vector3(.10,.44,.10),Color("#77736b"))
		business._label(root,"PIZZA · PAN · REFRESCOS",Vector3(0,2.4,-2.7),Color("#f4ecd8"))

func _refresh_rack(id: String,root: Node3D,primary: bool) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	var inventory: Dictionary = state.supplies.get(id,{})
	var keys: Array = INITIAL[id].keys()
	for i in range(keys.size()):
		var key := String(keys[i])
		var row := floori(float(i)/3.0)
		var col := i%3
		var p := Vector3(-.72+float(col)*.72,.17+float(row)*.62,0) if primary else Vector3(-1.02+float(col)*1.02,1.24+float(row)*.48,-.15)
		if int(inventory.get(key,0))>0:
			business._selectable_crate(root,p,key,false,id)
		var caption := String(Ledger.PRODUCTS[key].name)+" · "+str(int(inventory.get(key,0)))+" cajas" if int(inventory.get(key,0))>0 else String(Ledger.PRODUCTS[key].name)+" · AGOTADO"
		business._label(root,caption,p+Vector3(0,.28,0),Color("#f4ecd8"))

func refresh_primary() -> void:
	if business.purchase_rack!=null:
		_refresh_rack("primary",business.purchase_rack,true)

func refresh_supplier(id: String) -> void:
	if id=="primary": refresh_primary()
	elif racks.has(id): _refresh_rack(id,racks[id],false)

func available(id: String,key: String) -> bool:
	var inventory: Dictionary = state.supplies.get(id,{})
	return int(inventory.get(key,0))>0

func reserve_crate(id: String,key: String) -> bool:
	if not available(id,key): return false
	var inventory: Dictionary = state.supplies[id]
	inventory[key] = int(inventory[key])-1
	return true

func restore_crate(id: String,key: String) -> void:
	var inventory: Dictionary = state.supplies.get(id,{})
	inventory[key] = int(inventory.get(key,0))+1

func _near_site(at: Vector3) -> Dictionary:
	for id in sites:
		var site: Dictionary = sites[id]
		if id=="primary": continue
		var basis: Basis = site.basis
		var center: Vector3 = site.center
		var local := basis.inverse()*(at-center)
		if absf(local.x)<3.2 and local.z>.33 and local.z<4.2 and absf(local.y)<2.2:
			return site
	return {}

func _clerk_present(id: String) -> bool:
	for agent in agents:
		if String(agent.site)==id and String(agent.role)=="clerk":
			return not bool(agent.departed) and String(agent.task).is_empty()
	return false

func action_text(at: Vector3) -> String:
	if not state.meal.is_empty(): return "[E] Comer / beber"
	var site := _near_site(at)
	if site.is_empty(): return ""
	if String(site.kind)=="wholesale": return "[E] Hablar con "+String(site.contact)+" · apunta a una caja para comprar"
	if not _clerk_present(String(site.id)): return "Cafetería cerrada · dependienta fuera"
	var order: Dictionary = state.order
	if not order.is_empty() and String(order.site)==String(site.id):
		return "[E] Recoger pedido" if float(order.remaining)<=0.0 else "Preparando tu pedido…"
	return "[E] Ver menú · "+String(site.name)

func interact(at: Vector3) -> bool:
	if not state.meal.is_empty():
		_eat()
		return true
	var site := _near_site(at)
	if site.is_empty(): return false
	var id := String(site.id)
	if not _clerk_present(id):
		business._notify("Ahora mismo no está la persona que atiende.")
		return true
	if String(site.kind)=="wholesale":
		_contact_page(id)
		return true
	var order: Dictionary = state.order
	if not order.is_empty():
		if String(order.site)!=id:
			business._notify("Tienes un pedido pendiente en "+String(sites.get(String(order.site),{}).get("name","otra cafetería"))+".")
		elif float(order.remaining)>0.0:
			business._notify("Todavía estamos preparando tu pedido.")
		else:
			state.meal = {"key":order.key,"food_bites":3 if not String(MENU[order.key].food).is_empty() else 0,"drink_sips":3 if not String(MENU[order.key].drink).is_empty() else 0}
			state.order = {}
			_refresh_meal()
			ledger.save_game()
			business._notify("Buen provecho. Pulsa E para comer o beber.")
		return true
	if not ledger.carry.is_empty():
		business._notify("Deja la caja en un vehículo antes de comer.")
		return true
	_menu(id)
	return true

func _can_make(id: String,key: String) -> bool:
	var cafe: Dictionary = state.cafes.get(id,{})
	for ingredient in MENU[key].needs:
		if int(cafe.get(ingredient,0))<int(MENU[key].needs[ingredient]): return false
	return true

func _menu(id: String) -> void:
	var site: Dictionary = sites[id]
	state.met[String(site.id)+"_clerk"] = true
	ledger.save_game()
	business._open(String(site.name),"Hola, soy "+String(site.contact)+". ¿Qué vas a pedir?\nBilletera: %d CUP" % ledger.cash)
	for key in MENU:
		var item: Dictionary = MENU[key]
		var ready := _can_make(id,String(key))
		business._button("%s  ·  %d CUP%s" % [item.name,item.price,"" if ready else " · Agotado"],_order.bind(id,String(key)),not ready or ledger.cash<int(item.price))
	business._button("Guardar contacto de "+String(site.contact),_save_contact.bind(id))
	business._button("Salir",business.close)

func _order(id: String,key: String) -> void:
	if not state.order.is_empty() or not state.meal.is_empty() or not _can_make(id,key): return
	var item: Dictionary = MENU[key]
	if ledger.cash<int(item.price): return
	var cafe: Dictionary = state.cafes[id]
	for ingredient in item.needs:
		cafe[ingredient] = int(cafe[ingredient])-int(item.needs[ingredient])
	cafe.cash = int(cafe.cash)+int(item.price)
	state.order = {"site":id,"key":key,"remaining":7.0+float(rng.randi_range(0,5)),"announced":false}
	ledger.spend(int(item.price))
	business.close()
	business._notify(String(["Dame un momentico, que ya sale.","Ahora mismo te lo preparo.","Espérame aquí, mi hermano.","Enseguida sale tu pedido.","Siéntete como en casa, ya te atiendo."].pick_random()))

func _refresh_meal() -> void:
	if meal_root==null: return
	var meal: Dictionary = state.meal
	var key := String(meal.get("key",""))
	var f := String(MENU[key].food) if MENU.has(key) and int(meal.get("food_bites",0))>0 else ""
	var d := String(MENU[key].drink) if MENU.has(key) and int(meal.get("drink_sips",0))>0 else ""
	food_model = f
	drink_model = d
	_draw_meal(food_view,f,int(meal.get("food_bites",0)))
	_draw_meal(drink_view,d,int(meal.get("drink_sips",0)))
	for view in [food_view,drink_view]:
		if view.get_child_count()>0:
			business._box(view,Vector3(0,-.07,.05),Vector3(.12,.07,.10),Color("#c59169"))
	if avatar_food!=null:
		_draw_meal(avatar_food,f,int(meal.get("food_bites",0)))
		_draw_meal(avatar_drink,d,int(meal.get("drink_sips",0)))

func _draw_meal(root: Node3D,kind: String,count: int) -> void:
	for child in root.get_children():
		root.remove_child(child)
		child.queue_free()
	if kind.is_empty(): return
	if kind=="refresco":
		business._box(root,Vector3.ZERO,Vector3(.095,.22,.095),Color("#ba3c3c"))
		business._box(root,Vector3(0,.11,0),Vector3(.093,.014,.093),Color("#d6d9db"))
		business._box(root,Vector3(0,.01,.049),Vector3(.067,.07,.004),Color("#fff0d9"))
	elif kind=="pizza":
		for i in range(count):
			var x := (float(i)-1.0)*.065
			business._box(root,Vector3(x,0,0),Vector3(.067,.026,.19),Color("#c68b42"))
			business._box(root,Vector3(x,.020,0),Vector3(.064,.016,.16),Color("#f0c666"))
			business._box(root,Vector3(x,.032,.025),Vector3(.037,.012,.033),Color("#a84e3f"))
	else:
		business._box(root,Vector3.ZERO,Vector3(.20*float(count)/3.0,.07,.08),Color("#d9aa6d"))
		business._box(root,Vector3(0,.04,0),Vector3(.20*float(count)/3.0,.035,.04),Color("#a95644"))

# Discarded food uses the same three-bite animation and fullness system,
# but records exposure for a future health/hospital module.
func start_found_meal(key: String,dirty: bool) -> bool:
	if not MENU.has(key) or not state.meal.is_empty() or not ledger.carry.is_empty(): return false
	var item: Dictionary = MENU[key]
	state.meal = {"key":key,"food_bites":3 if not String(item.food).is_empty() else 0,"drink_sips":3 if not String(item.drink).is_empty() else 0,"dirty":dirty}
	_refresh_meal()
	business._notify("Comida encontrada · E para comer" if dirty else "E para comer / beber")
	return true

func _eat() -> void:
	if bite_anim>0.0 or active_hand>=0: return
	var meal: Dictionary = state.meal
	var bites := int(meal.get("food_bites",0))
	var sips := int(meal.get("drink_sips",0))
	if bites<=0 and sips<=0: return
	active_hand = 0 if bites>0 and (bites>=sips or sips==0) else 1
	bite_anim = .65

func _finish_bite() -> void:
	var meal: Dictionary = state.meal
	var key := String(meal.get("key",""))
	if not MENU.has(key):
		active_hand = -1
		return
	var item: Dictionary = MENU[key]
	var portions := 6.0 if not String(item.food).is_empty() and not String(item.drink).is_empty() else 3.0
	var gain := float(item.fill)/portions
	if active_hand==0:
		meal.food_bites = maxi(0,int(meal.food_bites)-1)
	else:
		meal.drink_sips = maxi(0,int(meal.drink_sips)-1)
	active_hand = -1
	if bool(meal.get("dirty",false)):
		state["dirty_food_bites"] = int(state.get("dirty_food_bites",0))+1
	state.fullness = minf(100.0,float(state.fullness)+gain)
	if int(meal.food_bites)<=0 and int(meal.drink_sips)<=0:
		if bool(meal.get("dirty",false)): state["dirty_meals"] = int(state.get("dirty_meals",0))+1
		state.meal = {}
		business._notify("Buen provecho · saciedad %d%%" % roundi(float(state.fullness)))
	else:
		business._notify("Saciedad %d%% · E para continuar" % roundi(float(state.fullness)))
	_refresh_meal()
	ledger.save_game()

func _save_contact(id: String) -> void:
	if not sites.has(id): return
	state.contacts[id] = true
	ledger.save_game()
	_contact_page(id)

func _contact_page(id: String) -> void:
	if not sites.has(id): return
	var site: Dictionary = sites[id]
	state.met[id+"_clerk"] = true
	ledger.save_game()
	business._open(String(site.contact),String(site.name)+"\n"+("Contacto guardado" if state.contacts.has(id) else "Contacto nuevo"))
	if not state.contacts.has(id): business._button("Guardar contacto",_save_contact.bind(id))
	business._button("Enviar mensaje: ¿Qué tienes disponible?",_ask_stock.bind(id),not state.contacts.has(id))
	business._button("Ver ubicación GPS",_location.bind(id))
	business._button("Volver al teléfono",business.open_phone_home)
	business._button("Cerrar",business.close)

func _location(id: String) -> void:
	var site: Dictionary = sites[id]
	business._open(String(site.name),world.geography.coordinate_text(site.center))
	business._button("Volver",_contact_page.bind(id))
	business._button("Cerrar",business.close)

func _ask_stock(id: String) -> void:
	var site: Dictionary = sites[id]
	ledger.add_message("Tú → "+String(site.contact),"Hola, ¿qué tienes disponible ahora?")
	var reply := "Asere, te digo lo que tengo ahora mismo:\n"
	if String(site.kind)=="wholesale":
		var stock: Dictionary = state.supplies.get(id,{})
		for key in stock:
			reply += "%s: %d cajas · %d CUP\n" % [Ledger.PRODUCTS[key].name,int(stock[key]),int(Ledger.PRODUCTS[key].cost)]
	else:
		for key in MENU:
			if _can_make(id,String(key)): reply += String(MENU[key].name)+" · "+str(MENU[key].price)+" CUP\n"
	ledger.add_message(String(site.contact),reply.strip_edges())
	ledger.save_game()
	business.open_messages()

func open_contacts() -> void:
	business._open("CONTACTOS","Guarda los contactos cuando conozcas a las personas.")
	for id in state.contacts:
		if sites.has(id): business._button(String(sites[id].contact)+"  ·  "+String(sites[id].name),_contact_page.bind(String(id)))
	if state.contacts.is_empty():
		var label := Label.new()
		label.text = "Todavía no tienes contactos nuevos."
		business.content.add_child(label)
	business._button("Inicio",business.open_phone_home)

func greet(person: Node3D) -> String:
	var id := String(person.get_meta("citizen_id",""))
	if id.is_empty(): return ""
	var name_value := String(person.get_meta("citizen_name",""))
	var known := bool(state.met.get(id,false))
	state.met[id] = true
	ledger.save_game()
	if known:
		return String(["¡Muchacho! ¿Te acuerdas de mí? Soy "+name_value+".","¡Qué bolá! Soy "+name_value+", nos vimos en el negocio.","¡Mira quién está aquí! ¿Cómo te va? Soy "+name_value+"."].pick_random())
	return "Mucho gusto, soy "+name_value+"."

func _plan(agent: Dictionary,goal: Vector3,task: String) -> bool:
	if world.pedestrian_router==null: return false
	var person: Person = agent.node
	var site: Dictionary = sites[agent.site]
	var basis: Basis = site.basis
	var c: Vector3 = site.center
	var home: Vector3 = agent.home
	var entrance: Vector3 = site.entrance
	var local := basis.inverse()*(person.global_position-c)
	var start := person.global_position
	var finish := goal
	var prefix := PackedVector3Array()
	var suffix := PackedVector3Array()
	# Leave and enter the open storefront via its actual doorway,
	# walking around the counter rather than through its solid wall.
	if absf(local.x)<3.9 and local.z<4.05 and local.z> -4.0:
		var side := c+basis*Vector3(2.35,.11,local.z)
		var aisle := c+basis*Vector3(2.35,.11,3.65)
		prefix.append(start)
		prefix.append(side)
		prefix.append(aisle)
		prefix.append(entrance)
		start = entrance
	if goal.distance_to(home)<.2:
		finish = entrance
		var home_local := basis.inverse()*(home-c)
		suffix.append(c+basis*Vector3(2.35,.11,3.65))
		suffix.append(c+basis*Vector3(2.35,.11,home_local.z))
		suffix.append(home)
	var middle: PackedVector3Array = world.pedestrian_router.call("route_between",start,finish)
	if middle.size()<2: return false
	var path := prefix
	for point in middle: path.append(point)
	for point in suffix: path.append(point)
	for i in range(1,path.size()):
		if not world.pedestrian_segment_clear(path[i-1],path[i]): return false
	agent.path = path
	agent.index = 1
	agent.task = task
	return true

func _owner_depart(agent: Dictionary) -> void:
	var cafe: Dictionary = state.cafes[agent.site]
	var need := ""
	for key in ["harina","queso","tomate","refresco","perrito"]:
		if int(cafe.get(key,0))<5:
			need = key
			break
	if need.is_empty(): return
	var person: Person = agent.node
	for id in sites:
		if id=="primary" or String(sites[id].kind)!="wholesale" or not available(id,need): continue
		var site: Dictionary = sites[id]
		var dest: Vector3 = site.entrance
		if _plan(agent,dest,"supplier"):
			agent.supplier = id
			agent.ingredient = need
			person.social_context = "shopping"
			return

func _tick_agents(delta: float) -> void:
	var minute := int(state.minutes)%1440
	for agent in agents:
		var person: Person = agent.node
		if person.conversation_active(delta): continue
		var path: PackedVector3Array = agent.path
		var index := int(agent.index)
		if not path.is_empty():
			if index<path.size():
				var target: Vector3 = path[index]
				var next := person.global_position.move_toward(target,maxf(.12,1.35*delta))
				if world.pedestrian_segment_clear(person.global_position,next) and person.walk_to(target,delta,1.35):
					agent.index = index+1
				continue
			agent.path = PackedVector3Array()
			var task := String(agent.task)
			agent.task = ""
			if task=="supplier":
				var cafe: Dictionary = state.cafes[agent.site]
				var key := String(agent.ingredient)
				var supplier := String(agent.supplier)
				var price := int(Ledger.PRODUCTS[key].cost)
				if int(cafe.cash)>=price and available(supplier,key):
					agent.delivery = {"key":key,"units":10,"supplier":supplier,"price":price}
				agent.timer = 3.0
				agent.task = "return_pending"
			elif task=="return":
				var delivery: Dictionary = agent.get("delivery",{})
				if not delivery.is_empty():
					var cafe: Dictionary = state.cafes[agent.site]
					var key := String(delivery.key)
					if int(cafe.cash)>=int(delivery.price) and reserve_crate(String(delivery.supplier),key):
						cafe.cash = int(cafe.cash)-int(delivery.price)
						cafe[key] = int(cafe.get(key,0))+int(delivery.units)
						refresh_supplier(String(delivery.supplier))
						ledger.save_game()
					agent.delivery = {}
				person.social_context = "worker"
				agent.departed = false
			elif task=="break":
				agent.timer = 18.0
				agent.task = "return_pending"
			continue
		agent.timer = maxf(0.0,float(agent.timer)-delta)
		if float(agent.timer)>0.0: continue
		if String(agent.task)=="return_pending":
			if _plan(agent,agent.home,"return"): continue
			agent.timer = 5.0
			continue
		if String(agent.role)=="owner":
			agent.timer = 12.0
			_owner_depart(agent)
		elif String(agent.role)=="clerk" and String(sites[agent.site].kind)=="cafe":
			# One short outing per in-game day, never while preparing an order.
			if minute<720: agent.trip_done = false
			if minute>=720 and minute<1080 and not bool(agent.trip_done) and state.order.is_empty():
				for id in sites:
					if id==String(agent.site) or id=="primary": continue
					var dest: Vector3 = sites[id].entrance
					if _plan(agent,dest,"break"):
						agent.departed = true
						agent.trip_done = true
						person.social_context = "street"
						break
			agent.timer = 8.0

func tick(delta: float,in_vehicle: bool,editor: bool) -> void:
	if fullness_bar!=null: fullness_bar.visible = not editor
	if clock_label!=null: clock_label.visible = not editor
	if editor: return
	bite_anim = maxf(0.0,bite_anim-delta)
	if active_hand>=0 and bite_anim<=0.0: _finish_bite()
	state.minutes = fmod(float(state.minutes)+delta,1440.0)
	world.update_utility_lighting(float(state.minutes),delta)
	state.fullness = maxf(0.0,float(state.fullness)-delta/9.0)
	if meal_root!=null:
		meal_root.visible = not in_vehicle and last_first_person and not state.meal.is_empty()
		food_view.position.y = move_toward(food_view.position.y,-.12 if active_hand==0 else -.36,delta*1.2)
		drink_view.position.y = move_toward(drink_view.position.y,-.12 if active_hand==1 else -.36,delta*1.2)
	var order: Dictionary = state.order
	if not order.is_empty():
		order.remaining = maxf(0.0,float(order.remaining)-delta)
		if float(order.remaining)<=0.0 and not bool(order.announced):
			order.announced = true
			var name_value := String(sites.get(String(order.site),{}).get("contact","Dependienta"))
			var item := String(MENU[order.key].name).to_lower()
			business._notify(name_value+": "+String(["¡Muchacho, tu "+item+"!","¡Ya está listo tu pedido de "+item+"!","¡Ven a buscar tu "+item+"!","¡Mi hermano, aquí tienes tu "+item+"!","¡Orden lista, pasa por el mostrador!"].pick_random()))
			ledger.save_game()
	agent_tick_clock += delta
	if agent_tick_clock>=.065:
		_tick_agents(agent_tick_clock)
		agent_tick_clock = 0.0
	economy_clock += delta
	if economy_clock>=60.0:
		economy_clock = 0.0
		for id in state.cafes:
			var cafe: Dictionary = state.cafes[id]
			var choices := MENU.keys()
			choices.shuffle()
			for key in choices:
				if not _can_make(String(id),String(key)): continue
				for ingredient in MENU[key].needs:
					cafe[ingredient] = int(cafe[ingredient])-int(MENU[key].needs[ingredient])
				cafe.cash = int(cafe.cash)+int(MENU[key].price)
				break
		# Small independent replenishment, not infinite shelf stock.
		for id in state.supplies:
			var inventory: Dictionary = state.supplies[id]
			var keys := inventory.keys()
			if keys.is_empty(): continue
			var key := String(keys[rng.randi_range(0,keys.size()-1)])
			inventory[key] = mini(int(INITIAL[id][key]),int(inventory[key])+2)
			refresh_supplier(String(id))
		ledger.save_game()
	save_clock += delta
	if save_clock>=15.0:
		save_clock = 0.0
		ledger.save_game()
	hud_tick_clock += delta
	if hud_tick_clock>=.20:
		hud_tick_clock = 0.0
		_update_hud()
