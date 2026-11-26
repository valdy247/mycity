extends Node3D
# Physical small-item inventory; food keeps its origin so a future health
# system can distinguish discarded food from a normal cafeteria meal.
const CAPACITY := 12
const ITEMS := {
	"pizza":{"name":"Pizza de la basura","size":2,"color":Color("#be944f"),"meal":"pizza"},
	"pan":{"name":"Pan de la basura","size":1,"color":Color("#b18a54"),"meal":"pan"},
	"refresco":{"name":"Refresco encontrado","size":1,"color":Color("#9c554c"),"meal":"refresco"},
	"cargador":{"name":"Cargador usado","size":1,"color":Color("#353b40")},
	"cable":{"name":"Cable usado","size":1,"color":Color("#3f4042")},
	"radio":{"name":"Radio vieja","size":3,"color":Color("#797768")},
	"grabadora":{"name":"Grabadora usada","size":4,"color":Color("#46494a")},
	"audifonos":{"name":"Audífonos usados","size":1,"color":Color("#3b4447")},
	"control":{"name":"Control remoto","size":1,"color":Color("#515659")},
	"linterna":{"name":"Linterna","size":2,"color":Color("#687d68")},
	"pollo":{"name":"Pollo","size":2,"color":Color("#d8b398")},
	"picadillo":{"name":"Picadillo","size":2,"color":Color("#a65d55")},
	"perrito":{"name":"Perritos","size":2,"color":Color("#b77c52")},
	"huevo":{"name":"Huevos","size":2,"color":Color("#e8d9b4")},
	"aceite":{"name":"Aceite","size":2,"color":Color("#d9bc65")},
	"arroz":{"name":"Arroz","size":2,"color":Color("#e6d8c0")}
}
var game
var world
var business
var state: Dictionary = {}
var home_bag: Node3D
var worn_bag: Node3D
var hand_view: Node3D
var hand_avatar: Node3D
var finds: Array = []
var checked_sites: Dictionary = {}
var clock := 0.0

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	business = game.business
	var life: Dictionary = business.ledger.life_data
	if not life.has("backpack"): life.backpack = {"equipped":false,"items":{},"home":{},"held":"","held_dirty":false}
	state = life.backpack
	for key in ["items","home"]:
		if not state.has(key): state[key] = {}
	if not state.has("equipped"): state.equipped = false
	if not state.has("held"): state.held = ""
	if not state.has("held_dirty"): state.held_dirty = false
	home_bag = Node3D.new()
	game.garage.interior.add_child(home_bag)
	home_bag.position = Vector3(-2.05,.31,3.8)
	_bag_model(home_bag)
	worn_bag = Node3D.new()
	game.avatar.add_child(worn_bag)
	worn_bag.position = Vector3(0,1.12,-.23)
	_bag_model(worn_bag)
	hand_view = Node3D.new()
	game.play_camera.add_child(hand_view)
	hand_view.position = Vector3(.28,-.34,-.73)
	hand_avatar = Node3D.new()
	game.limb_arms[1].add_child(hand_avatar)
	hand_avatar.position = Vector3(0,-.48,.10)
	_refresh()

func _bag_model(root: Node3D) -> void:
	business._box(root,Vector3.ZERO,Vector3(.36,.46,.20),Color("#39474b"))
	business._box(root,Vector3(0,-.09,-.12),Vector3(.28,.19,.09),Color("#52605a"))
	business._box(root,Vector3(0,.25,0),Vector3(.14,.045,.055),Color("#222b2d"))
	for x in [-.14,.14]:
		business._box(root,Vector3(float(x),.02,.14),Vector3(.055,.40,.045),Color("#262d2e"))

func _model(root: Node3D,key: String,dirty: bool) -> void:
	var color: Color = ITEMS[key].color
	if key=="pizza" or key=="pan":
		business.life._draw_meal(root,key,2)
		if dirty:
			business._box(root,Vector3(.01,.035,-.04),Vector3(.045,.008,.04),Color("#716d41"))
	elif key=="refresco":
		business.life._draw_meal(root,key,1)
	else:
		business._box(root,Vector3.ZERO,Vector3(.18,.11,.24),color)
		business._box(root,Vector3(0,.06,-.03),Vector3(.10,.012,.09),color.lightened(.2))
		if key=="radio" or key=="grabadora":
			for x in [-.055,.055]:
				business._box(root,Vector3(float(x),0,.126),Vector3(.048,.065,.015),Color("#222728"))
		if key=="cargador":
			for x in [-.035,.035]:
				business._box(root,Vector3(float(x),.02,.15),Vector3(.018,.025,.06),Color("#c4c2b8"))

func _refresh() -> void:
	home_bag.visible = not bool(state.equipped)
	worn_bag.visible = bool(state.equipped)
	for root in [hand_view,hand_avatar]:
		for child in root.get_children():
			root.remove_child(child)
			child.queue_free()
		var held := String(state.held)
		if ITEMS.has(held): _model(root,held,bool(state.held_dirty))
	_update_visibility()

func _update_visibility() -> void:
	var walking: bool = not game.driving and not game.taxi_riding and not game.bus_riding and not game.garage.riding
	hand_view.visible = walking and game.first_person and not String(state.held).is_empty()
	hand_avatar.visible = walking and not game.first_person and not String(state.held).is_empty()

func occupied() -> int:
	var total := 0
	for token in state.items:
		var key := String(token).get_slice(":",0)
		if ITEMS.has(key): total += int(state.items[token])*int(ITEMS[key].size)
	return total

func empty_hands() -> bool:
	return String(state.held).is_empty()

func _physical_hands() -> bool:
	return empty_hands() and business.ledger.carry.is_empty() and business.life.state.meal.is_empty() and game.monte_services.player_bag==null and String(game.garage.state.part).is_empty() and String(game.garage.state.held_furniture).is_empty()

func can_receive(key: String) -> bool:
	if not ITEMS.has(key): return false
	if bool(state.equipped) and occupied()+int(ITEMS[key].size)<=CAPACITY: return true
	return _physical_hands()

func receive(key: String,dirty: bool = false) -> bool:
	if not can_receive(key): return false
	if bool(state.equipped) and occupied()+int(ITEMS[key].size)<=CAPACITY:
		var token := key+(":dirty" if dirty else ":clean")
		state.items[token] = int(state.items.get(token,0))+1
	else:
		state.held = key
		state.held_dirty = dirty
	_refresh()
	return true

func _bag_aimed() -> bool:
	return game.garage.inside and _aimed(home_bag.global_position,.38,2.8)

func _aimed(p: Vector3,radius: float,reach: float) -> bool:
	var actor: CharacterBody3D = game.player
	if actor.global_position.distance_to(p)>reach: return false
	var camera: Camera3D = game.play_camera
	var origin := camera.global_position
	var d := -camera.global_transform.basis.z
	var depth := (p-origin).dot(d)
	if depth<=0.0: return false
	if (origin+d*depth).distance_to(p)>radius: return false
	var ray := PhysicsRayQueryParameters3D.create(origin,origin+d*maxf(.01,depth-.15),1|4|16)
	ray.exclude = [actor.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func _find_aimed() -> Dictionary:
	for item in finds:
		var root: Node3D = item.root
		if not is_instance_valid(root) or not root.visible: continue
		if _aimed(root.global_position,.24,2.7): return item
	return {}

func action_text() -> String:
	if _bag_aimed(): return "[E] Equipar mochila" if not bool(state.equipped) else "[E] Guardar mochila"
	var item := _find_aimed()
	if not item.is_empty(): return "[E] Recoger "+String(ITEMS[item.key].name)
	if not empty_hands(): return "[I] Objeto en mano · guardar / usar / soltar"
	return ""

func interact() -> bool:
	if _bag_aimed() and not bool(state.equipped):
		state.equipped = true
		_refresh()
		business.ledger.save_game()
		business._notify("Mochila equipada · %d/%d espacios" % [occupied(),CAPACITY])
		return true
	var item := _find_aimed()
	if item.is_empty(): return false
	var key := String(item.key)
	if ITEMS[key].has("meal"):
		business._open(String(ITEMS[key].name),"Comida encontrada en el suelo. Puede estar contaminada.")
		business._button("Comer ahora",_eat_found.bind(item),not _physical_hands())
		business._button("Recoger",_take.bind(item),not can_receive(key))
		business._button("Dejar",business.close)
	else:
		_take(item)
	return true

func _erase_found(item: Dictionary) -> void:
	var root: Node3D = item.root
	finds.erase(item)
	if is_instance_valid(root): root.queue_free()

func _take(item: Dictionary) -> void:
	if not finds.has(item): return
	var key := String(item.key)
	if not receive(key,bool(item.dirty)):
		business._notify("No tienes espacio en la mochila ni las manos libres.")
		return
	_erase_found(item)
	business.ledger.save_game()
	if business.modal_open(): business.close()
	business._notify("Recogiste "+String(ITEMS[key].name))

func _eat_found(item: Dictionary) -> void:
	if not finds.has(item) or not _physical_hands(): return
	if not business.life.start_found_meal(String(ITEMS[item.key].meal),bool(item.dirty)): return
	_erase_found(item)
	business.close()

func _spawn_item(key: String,at: Vector3,dirty: bool,site: int = 0) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = at
	_model(root,key,dirty)
	finds.append({"root":root,"key":key,"dirty":dirty,"site":site})

func _spawn_site(site: Dictionary,id: int) -> void:
	var curb: Vector3 = site.curb
	var direction: Vector3 = site.direction
	var side := Vector3(-direction.z,0,direction.x)
	var keys := ["pizza","pan","cargador" if id%2==0 else "cable","refresco" if id%3==0 else "control"]
	for i in range(keys.size()):
		var p := curb+direction*(2.05+float(i)*.52)+side*.45
		if world.street_geometry.point_on_road(p): continue
		var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*1.0,p-Vector3.UP*.6,1|2)
		var hit := get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y<.85 or float(hit.position.y)>.3: continue
		var at: Vector3 = hit.position+Vector3.UP*.085
		_spawn_item(String(keys[i]),at,true,id)

func tick(delta: float) -> void:
	_update_visibility()
	clock += delta
	if clock<.6: return
	clock = 0.0
	for site in game.monte_services.sites:
		var root: Node3D = site.root
		var id := root.get_instance_id()
		var full: bool = float(site.refill)<=0.0 and not site.bags.is_empty()
		if full and not checked_sites.has(id):
			checked_sites[id] = true
			_spawn_site(site,id)
		elif not full and float(site.refill)>0.0 and checked_sites.has(id):
			checked_sites.erase(id)
			for i in range(finds.size()-1,-1,-1):
				var item: Dictionary = finds[i]
				if int(item.site)==id: _erase_found(item)

func _name(token: String) -> String:
	var key := token.get_slice(":",0)
	var title := String(ITEMS[key].name)
	if token.ends_with(":clean") and ITEMS[key].has("meal"):
		title = String(business.life.MENU[String(ITEMS[key].meal)].name)
	return title

func open_inventory() -> void:
	business._open("Mochila","%s · %d/%d espacios" % ["Equipada" if bool(state.equipped) else "En casa",occupied(),CAPACITY])
	var held := String(state.held)
	if ITEMS.has(held):
		var token := held+(":dirty" if bool(state.held_dirty) else ":clean")
		var line := Label.new()
		line.text = "En mano: "+_name(token)
		business.content.add_child(line)
		business._button("Guardar en mochila",_pack_held,not bool(state.equipped) or occupied()+int(ITEMS[held].size)>CAPACITY)
		if ITEMS[held].has("meal"): business._button("Comer / beber",_eat_held)
		business._button("Dejar en el suelo",_drop_held)
	if bool(state.equipped):
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(380,180)
		business.content.add_child(scroll)
		var list := VBoxContainer.new()
		scroll.add_child(list)
		for token in state.items:
			var key := String(token).get_slice(":",0)
			if not ITEMS.has(key) or int(state.items[token])<=0: continue
			var button := Button.new()
			button.text = "%s × %d · %s" % [_name(String(token)),int(state.items[token]),"Comer" if ITEMS[key].has("meal") else "Sacar"]
			button.disabled = not _physical_hands()
			button.pressed.connect(_use_item.bind(String(token)))
			list.add_child(button)
	if game.garage.inside:
		if bool(state.equipped): business._button("Quitar mochila y dejarla en casa",_unequip)
		else: business._button("Equipar mochila",_equip)
	business._button("Cerrar",business.close)

func _equip() -> void:
	if not game.garage.inside: return
	state.equipped = true
	_refresh()
	business.ledger.save_game()
	open_inventory()

func _unequip() -> void:
	if not game.garage.inside: return
	state.equipped = false
	_refresh()
	business.ledger.save_game()
	open_inventory()

func _pack_held() -> void:
	var key := String(state.held)
	if not ITEMS.has(key) or not bool(state.equipped) or occupied()+int(ITEMS[key].size)>CAPACITY: return
	var token := key+(":dirty" if bool(state.held_dirty) else ":clean")
	state.items[token] = int(state.items.get(token,0))+1
	state.held = ""
	state.held_dirty = false
	_refresh()
	business.ledger.save_game()
	open_inventory()

func _eat_held() -> void:
	var key := String(state.held)
	if not ITEMS.has(key) or not ITEMS[key].has("meal"): return
	if not business.ledger.carry.is_empty() or not business.life.state.meal.is_empty() or game.monte_services.player_bag!=null or not String(game.garage.state.part).is_empty() or not String(game.garage.state.held_furniture).is_empty(): return
	if business.life.start_found_meal(String(ITEMS[key].meal),bool(state.held_dirty)):
		state.held = ""
		state.held_dirty = false
		_refresh()
		business.ledger.save_game()
		business.close()

func _use_item(token: String) -> void:
	if not bool(state.equipped) or not _physical_hands() or int(state.items.get(token,0))<=0: return
	var key := token.get_slice(":",0)
	state.items[token] = int(state.items[token])-1
	state.held = key
	state.held_dirty = token.ends_with(":dirty")
	_refresh()
	business.ledger.save_game()
	if ITEMS[key].has("meal"): _eat_held()
	else: open_inventory()

func _drop_held() -> void:
	var key := String(state.held)
	if not ITEMS.has(key): return
	var actor: CharacterBody3D = game.player
	var cam: Camera3D = game.play_camera
	var d := -cam.global_transform.basis.z
	d.y = 0.0
	var p := actor.global_position+d.normalized()*.8
	var ray := PhysicsRayQueryParameters3D.create(p+Vector3.UP*.5,p-Vector3.UP*2.0,1|2)
	ray.exclude = [actor.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.y<.85: return
	var at: Vector3 = hit.position+Vector3.UP*.085
	_spawn_item(key,at,bool(state.held_dirty))
	state.held = ""
	state.held_dirty = false
	_refresh()
	business.ledger.save_game()
	business.close()
