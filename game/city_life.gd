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
	"primary":{"pollo":12,"picadillo":10,"perrito":12,"huevos":12},
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
var sleep_label: Label
var sleep_bar: ProgressBar
const GAME_MINUTES_PER_SECOND := .4
const FULL_SLEEP_MINUTES := 480.0
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
var supply_clock := 0.0
const CAFE_INGREDIENTS := ["harina","queso","tomate","refresco","perrito"]
const CAFE_CREDIT_LIMIT := 3000
const CAFE_DELIVERY_DELAY := 45.0
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
	if not state.has("day"): state.day = 1
	if not state.has("fatigue"): state.fatigue = 15.0
	if not state.has("coffee_minutes"): state.coffee_minutes = 0.0
	if not state.has("coffee_cups"): state.coffee_cups = 0
	if not state.has("coffee_served"): state.coffee_served = false
	if not state.has("alarm_minute"): state.alarm_minute = -1
	if not state.has("supplies"): state.supplies = INITIAL.duplicate(true)
	if business.adaptation_mode and not state.supplies.get("primary",{}).has("aceite"):
		state.supplies.primary.aceite = 12
	for supplier in INITIAL:
		if not state.supplies.has(supplier): state.supplies[supplier] = INITIAL[supplier].duplicate(true)
		for ingredient in INITIAL[supplier]:
			if not state.supplies[supplier].has(ingredient): state.supplies[supplier][ingredient] = INITIAL[supplier][ingredient]
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
		if String(site.kind)=="cafe":
			if not state.cafes.has(id):
				state.cafes[id] = {"harina":8,"queso":4,"tomate":10,"refresco":12,"perrito":8,"cash":3600}
			var cafe: Dictionary = state.cafes[id]
			if not cafe.has("supplier_debt"): cafe.supplier_debt = 0
			if not cafe.has("supply_wait"): cafe.supply_wait = 0.0
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
	sleep_bar = ProgressBar.new()
	business.layer.add_child(sleep_bar)
	sleep_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	sleep_bar.offset_left = 12
	sleep_bar.offset_right = 196
	sleep_bar.offset_top = -168
	sleep_bar.offset_bottom = -152
	sleep_bar.max_value = 100
	sleep_bar.show_percentage = false
	sleep_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sleep_bar.add_theme_stylebox_override("background",bg)
	var rest_fill := StyleBoxFlat.new()
	rest_fill.bg_color = Color("#79c9ae")
	rest_fill.set_corner_radius_all(6)
	sleep_bar.add_theme_stylebox_override("fill",rest_fill)
	sleep_label = Label.new()
	business.layer.add_child(sleep_label)
	sleep_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	sleep_label.offset_left = 12
	sleep_label.offset_right = 320
	sleep_label.offset_top = -190
	sleep_label.offset_bottom = -169
	sleep_label.add_theme_font_size_override("font_size",12)
	sleep_label.add_theme_color_override("font_shadow_color",Color.BLACK)
	sleep_label.add_theme_constant_override("shadow_offset_y",2)
	sleep_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_update_hud()

func _update_hud() -> void:
	if fullness_bar==null: return
	var hunger := 100.0-float(state.fullness)
	fullness_bar.value = hunger
	clock_label.text = "Hambre %d%% · Día %d · %s" % [roundi(hunger),int(state.day),format_time(int(state.minutes))]
	var energy := clampf(100.0-float(state.fatigue),0.0,100.0)
	sleep_bar.value = energy
	sleep_label.text = "Energía %d%%" % roundi(energy)
	if float(state.coffee_minutes)>0.0: sleep_label.text += " · Café activo"

static func format_time(minute: int) -> String:
	minute = posmod(minute,1440)
	var hour := floori(float(minute)/60.0)
	return "%d:%02d %s" % [12 if hour%12==0 else hour%12,minute%60,"AM" if hour<12 else "PM"]

func advance_game_minutes(amount: float) -> void:
	var total := float(state.minutes)+maxf(0.0,amount)
	state.day = int(state.day)+floori(total/1440.0)
	state.minutes = fposmod(total,1440.0)

func planned_sleep_minutes() -> float:
	var alarm := int(state.alarm_minute)
	if alarm<0: return FULL_SLEEP_MINUTES
	var remaining := fposmod(float(alarm)-float(state.minutes),1440.0)
	return 1440.0 if remaining<.01 else remaining

func sleep_at_home() -> String:
	var duration := planned_sleep_minutes()
	advance_game_minutes(duration)
	state.fatigue = maxf(0.0,float(state.fatigue)-duration/FULL_SLEEP_MINUTES*100.0)
	state.fullness = maxf(0.0,float(state.fullness)-duration*.025)
	state.coffee_minutes = 0.0
	state.alarm_minute = -1
	state["bed_unmade"] = true
	_update_hud()
	ledger.save_game()
	return "Despertaste a las "+format_time(int(state.minutes))

func brew_home_coffee() -> bool:
	if int(state.coffee_cups)>0: return false
	state.coffee_cups = 4
	state.coffee_served = false
	ledger.save_game()
	return true

func serve_home_coffee() -> bool:
	if int(state.coffee_cups)<=0 or bool(state.coffee_served): return false
	state.coffee_served = true
	ledger.save_game()
	return true

func drink_home_coffee() -> bool:
	if int(state.coffee_cups)<=0 or not bool(state.coffee_served): return false
	state.coffee_cups = int(state.coffee_cups)-1
	state.coffee_served = false
	state.coffee_minutes = minf(180.0,float(state.coffee_minutes)+90.0)
	state.fatigue = maxf(0.0,float(state.fatigue)-5.0)
	_update_hud()
	ledger.save_game()
	return true

func open_alarm() -> void:
	var current := int(state.alarm_minute)
	business._open("Alarma","Hora de despertar: "+(format_time(current) if current>=0 else "Sin alarma · 8 horas de sueño"))
	var hours := SpinBox.new()
	hours.min_value = 0
	hours.max_value = 23
	hours.value = floori(float(current if current>=0 else 360)/60.0)
	hours.prefix = "Hora (24 h): "
	business.content.add_child(hours)
	var minutes := SpinBox.new()
	minutes.min_value = 0
	minutes.max_value = 59
	minutes.value = posmod(current if current>=0 else 360,60)
	minutes.prefix = "Minutos: "
	business.content.add_child(minutes)
	business._button("Guardar alarma",func(): _set_alarm(int(hours.value)*60+int(minutes.value)))
	business._button("Desactivar alarma",_set_alarm.bind(-1))
	business._button("Volver",business.open_phone_home)

func _set_alarm(value: int) -> void:
	state.alarm_minute = value
	ledger.save_game()
	open_alarm()

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
		var p := Vector3(-.885+float(i)*.59,.17,0) if primary else Vector3(-1.02+float(col)*1.02,1.24+float(row)*.48,-.15)
		if int(inventory.get(key,0))>0:
			business._selectable_crate(root,p,key,false,id)
		var amount := int(inventory.get(key,0))
		var caption := str(amount)+" cajas" if amount>0 else "AGOTADO"
		if amount<=0: caption = String(Ledger.PRODUCTS[key].name).split(" (")[0]+" · AGOTADO"
		var tag: Label3D = business._label(root,caption,p+Vector3(0,.24,.22),Color("#f4ecd8"))
		tag.font_size = 26
		tag.pixel_size = .0016
		tag.outline_size = 1
		tag.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		tag.visibility_range_end = 8.0
		tag.no_depth_test = false

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
	if not ledger.carry.is_empty(): return "[E] Ofrecer caja · "+String(site.name)
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
		_offer_delivery(id)
		return true
	_menu(id)
	return true

# The player may supply an actual paid crate carried from a wholesaler.
# Cafes pay the wholesale replacement value plus a transport premium.
# No free inventory, duplicate payout or bypass of the player wallet.
func _delivery_price(key: String) -> int:
	return roundi(float(ledger.product(key).cost)*1.12)

func _delivery_available(id: String,key: String) -> bool:
	if not state.cafes.has(id) or not CAFE_INGREDIENTS.has(key): return false
	var cafe: Dictionary = state.cafes[id]
	return int(cafe.get(key,0))<5 and int(cafe.cash)>=_cafe_cost(key) and float(cafe.get("delivery_cooldown",0.0))<=0.0

func _offer_delivery(id: String) -> void:
	var key := ledger.carry
	if not _delivery_available(id,key):
		business._notify("La cafetería no necesita esta caja o no puede pagarla ahora.")
		return
	var price := _delivery_price(key)
	business._open("Entregar mercancía",String(sites[id].name)+" necesita "+String(Ledger.PRODUCTS[key].name)+". Cobras "+str(price)+" CUP por la caja (incluye incentivo de transporte).")
	business._button("Entregar caja · "+str(price)+" CUP",_deliver_to_cafe.bind(id,key))
	business._button("Cancelar",business.close)

func _deliver_to_cafe(id: String,key: String) -> void:
	if ledger.carry!=key or not _delivery_available(id,key): return
	var cafe: Dictionary = state.cafes[id]
	var price := _delivery_price(key)
	cafe.cash = int(cafe.cash)-_cafe_cost(key)
	# A limited city logistics contract covers the transport difference.
	cafe.delivery_cooldown = 120.0
	cafe[key] = int(cafe.get(key,0))+int(ledger.product(key).units)
	ledger.carry = ""
	ledger.cash += price
	ledger.revenue += price
	state.cafe_deliveries = int(state.get("cafe_deliveries",0))+1
	ledger.save_game()
	business._sync_visuals()
	business.close()
	business._notify("Entrega completada · +"+str(price)+" CUP")

func open_supply_market() -> void:
	business._open("Abastecimiento","Oportunidades de entrega de mercancía. Compra una caja y llévala a la cafetería.")
	for id in sites:
		if not state.cafes.has(id): continue
		var cafe: Dictionary = state.cafes[id]
		var items: Array[String] = []
		for key in _cafe_needs(cafe):
			if not _delivery_available(String(id),String(key)): continue
			items.append(String(Ledger.PRODUCTS[key].name)+" · "+str(_delivery_price(String(key)))+" CUP")
		if not items.is_empty():
			var label := Label.new()
			label.text = String(sites[id].name)+"\n"+"\n".join(PackedStringArray(items))
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			business.content.add_child(label)
	if int(state.get("cafe_deliveries",0))>0:
		var count := Label.new()
		count.text = "Entregas completadas: "+str(int(state.cafe_deliveries))
		business.content.add_child(count)
	business._button("Inicio",business.open_phone_home)

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
	_cafe_sale(cafe,int(item.price))
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
		business._notify("Buen provecho · hambre %d%%" % roundi(100.0-float(state.fullness)))
	else:
		business._notify("Hambre %d%% · E para continuar" % roundi(100.0-float(state.fullness)))
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
			reply += "%s: %d cajas · %d CUP\n" % [Ledger.PRODUCTS[key].name,int(stock[key]),int(ledger.product(key).cost)]
	else:
		for key in MENU:
			if _can_make(id,String(key)): reply += String(MENU[key].name)+" · "+str(MENU[key].price)+" CUP\n"
	ledger.add_message(String(site.contact),reply.strip_edges())
	ledger.unread = 0
	ledger.save_game()
	business._phone_thread(String(site.contact))

func open_contacts() -> void:
	business._open("Contactos","Personas y negocios que has conocido en la ciudad.")
	if not bool(business.phone_mode):
		for id in state.contacts:
			if sites.has(id): business._button(String(sites[id].contact)+"  ·  "+String(sites[id].name),_contact_page.bind(String(id)))
	else:
		var search := LineEdit.new()
		search.placeholder_text = "Buscar persona o negocio"
		search.custom_minimum_size.y = 42
		business.content.add_child(search)
		var rows: Array = []
		for id in state.contacts:
			if not sites.has(id): continue
			var site: Dictionary = sites[id]
			var row := Button.new()
			row.text = String(site.contact)+"\n"+String(site.name)
			row.alignment = HORIZONTAL_ALIGNMENT_LEFT
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			row.custom_minimum_size.y = 66
			row.icon = business._phone_icon("contact",Color("#3d6dba"))
			row.add_theme_constant_override("icon_max_width",38)
			row.pressed.connect(_contact_page.bind(String(id)))
			business.content.add_child(row)
			rows.append({"node":row,"text":row.text.to_lower()})
		search.text_changed.connect(func(value: String):
			var term := value.strip_edges().to_lower()
			for entry in rows:
				if is_instance_valid(entry.node): entry.node.visible = term.is_empty() or String(entry.text).contains(term))
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

# Cafeterias buy wholesale at a negotiated commercial rate, not the
# player-facing crate price. All recipes remain profitable at menu prices.
func _cafe_cost(key: String) -> int:
	return ceili(float(ledger.product(key).cost)*.40)

# Visiting residents consume actual ingredients and pay from their profile.
# Returns the price only when a sale succeeded.
func citizen_purchase(id: String,budget: int) -> int:
	if not state.cafes.has(id) or not _clerk_present(id): return 0
	var cafe: Dictionary = state.cafes[id]
	var keys := MENU.keys()
	keys.shuffle()
	for key in keys:
		var price := int(MENU[key].price)
		if budget<price or not _can_make(id,String(key)): continue
		for ingredient in MENU[key].needs:
			cafe[ingredient] = int(cafe[ingredient])-int(MENU[key].needs[ingredient])
		_cafe_sale(cafe,price)
		return price
	return 0

func _cafe_sale(cafe: Dictionary,amount: int) -> void:
	var repayment := mini(int(cafe.get("supplier_debt",0)),floori(float(amount)*.25))
	cafe.supplier_debt = int(cafe.get("supplier_debt",0))-repayment
	cafe.cash = int(cafe.cash)+amount-repayment

func _cafe_can_buy(cafe: Dictionary,key: String) -> bool:
	return int(cafe.cash)+maxi(0,CAFE_CREDIT_LIMIT-int(cafe.get("supplier_debt",0)))>=_cafe_cost(key)

func _cafe_buy(id: String,supplier: String,key: String) -> bool:
	var cafe: Dictionary = state.cafes[id]
	if int(cafe.get(key,0))>=5 or not _cafe_can_buy(cafe,key) or not reserve_crate(supplier,key): return false
	var price := _cafe_cost(key)
	var paid := mini(maxi(0,int(cafe.cash)),price)
	cafe.cash = int(cafe.cash)-paid
	cafe.supplier_debt = int(cafe.get("supplier_debt",0))+price-paid
	cafe[key] = int(cafe.get(key,0))+int(ledger.product(key).units)
	refresh_supplier(supplier)
	return true

func _cafe_needs(cafe: Dictionary) -> Array:
	var needs: Array = []
	for key in CAFE_INGREDIENTS:
		if int(cafe.get(key,0))<5: needs.append(key)
	needs.sort_custom(func(a,b): return int(cafe.get(a,0))<int(cafe.get(b,0)))
	return needs

# Supplier delivery is the fallback for a blocked owner or disconnected
# pedestrian graph. Still transfers actual crates, debits cash or bounded
# trade credit and persists inventory; never creates free cafe stock.
func _supply_tick(delta: float) -> void:
	var changed := false
	for id in sites:
		if not state.cafes.has(id): continue
		var cafe: Dictionary = state.cafes[id]
		cafe.delivery_cooldown = maxf(0.0,float(cafe.get("delivery_cooldown",0.0))-delta)
		var needs := _cafe_needs(cafe)
		if needs.is_empty():
			cafe.supply_wait = 0.0
			continue
		cafe.supply_wait = float(cafe.get("supply_wait",0.0))+delta
		if float(cafe.supply_wait)<CAFE_DELIVERY_DELAY: continue
		var delivered := false
		for key in needs:
			for supplier in INITIAL:
				if not sites.has(supplier) or not available(supplier,key): continue
				if _cafe_buy(String(id),String(supplier),String(key)):
					delivered = true
					changed = true
					print("Abastecimiento: ",sites[id].name," recibió ",key," de ",sites[supplier].name)
					break
		if delivered: cafe.supply_wait = 0.0
		else: cafe.supply_wait = CAFE_DELIVERY_DELAY-10.0
	if changed: ledger.save_game()

func _owner_depart(agent: Dictionary) -> void:
	var cafe: Dictionary = state.cafes[agent.site]
	var person: Person = agent.node
	for key in _cafe_needs(cafe):
		if not _cafe_can_buy(cafe,key): continue
		for id in sites:
			if id=="primary" or String(sites[id].kind)!="wholesale" or not available(id,key): continue
			var site: Dictionary = sites[id]
			var dest: Vector3 = site.entrance
			if _plan(agent,dest,"supplier"):
				agent.supplier = id
				agent.ingredient = key
				person.social_context = "shopping"
				return

func _tick_agents(delta: float) -> void:
	var minute := int(state.minutes)%1440
	for agent in agents:
		var person: Person = agent.node
		if person.has_meta("incident_role"): continue
		if person.conversation_active(delta): continue
		var path: PackedVector3Array = agent.path
		var index := int(agent.index)
		if not path.is_empty():
			if index<path.size():
				var target: Vector3 = path[index]
				var next := person.global_position.move_toward(target,maxf(.12,1.35*delta))
				if world.pedestrian_segment_clear(person.global_position,next) and world.pedestrian_space_clear(person,next):
					agent.blocked_for = 0.0
					if person.walk_to(target,delta,1.35): agent.index = index+1
				else:
					agent.blocked_for = float(agent.get("blocked_for",0.0))+delta
					if float(agent.blocked_for)>8.0:
						agent.path = PackedVector3Array()
						agent.index = 0
						agent.task = "return_pending"
						agent.timer = 5.0
						agent.blocked_for = 0.0
				continue
			agent.path = PackedVector3Array()
			var task := String(agent.task)
			agent.task = ""
			if task=="supplier":
				var cafe: Dictionary = state.cafes[agent.site]
				var key := String(agent.ingredient)
				var supplier := String(agent.supplier)
				if _cafe_can_buy(cafe,key) and available(supplier,key):
					agent.delivery = {"key":key,"supplier":supplier}
				agent.timer = 3.0
				agent.task = "return_pending"
			elif task=="return":
				var delivery: Dictionary = agent.get("delivery",{})
				if not delivery.is_empty():
					if _cafe_buy(String(agent.site),String(delivery.supplier),String(delivery.key)):
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
	if sleep_label!=null: sleep_label.visible = not editor
	if sleep_bar!=null: sleep_bar.visible = not editor
	if editor: return
	bite_anim = maxf(0.0,bite_anim-delta)
	if active_hand>=0 and bite_anim<=0.0: _finish_bite()
	var passed := delta*GAME_MINUTES_PER_SECOND
	advance_game_minutes(passed)
	world.update_utility_lighting(float(state.minutes),delta)
	state.fullness = maxf(0.0,float(state.fullness)-passed/9.6)
	var stimulated := minf(passed,float(state.coffee_minutes))
	state.coffee_minutes = maxf(0.0,float(state.coffee_minutes)-passed)
	state.fatigue = minf(100.0,float(state.fatigue)+(passed-stimulated*.65)/9.6)
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
	# Remote storefront NPC movement can wait while the player is in the rental room.
	# Economy, hunger, energy and the game clock continue independently.
	var controller = business.get_parent()
	if controller.ambient_city_suspended():
		agent_tick_clock = 0.0
	else:
		agent_tick_clock += delta
		if agent_tick_clock>=.065:
			_tick_agents(agent_tick_clock)
			agent_tick_clock = 0.0
	supply_clock += delta
	if supply_clock>=5.0:
		_supply_tick(supply_clock)
		supply_clock = 0.0
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
				_cafe_sale(cafe,int(MENU[key].price))
				break
		# Small independent replenishment, not infinite shelf stock.
		for id in INITIAL:
			var inventory: Dictionary = state.supplies[id]
			var changed := false
			for key in INITIAL[id]:
				var before := int(inventory.get(key,0))
				if before>=int(INITIAL[id][key]): continue
				inventory[key] = mini(int(INITIAL[id][key]),before+2)
				changed = true
			if changed: refresh_supplier(String(id))
		ledger.save_game()
	save_clock += delta
	if save_clock>=15.0:
		save_clock = 0.0
		ledger.save_game()
	hud_tick_clock += delta
	if hud_tick_clock>=.20:
		hud_tick_clock = 0.0
		_update_hud()
