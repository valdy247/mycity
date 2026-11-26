extends Node3D
const Person = preload("res://street_person.gd")
const GOODS := {
	"pollo":{"name":"Pollo","price":300,"color":Color("#d8b398")},
	"picadillo":{"name":"Picadillo","price":210,"color":Color("#a65d55")},
	"perrito":{"name":"Perritos","price":170,"color":Color("#b77c52")},
	"huevo":{"name":"Huevos (6)","price":180,"color":Color("#e8d9b4")},
	"aceite":{"name":"Aceite","price":195,"color":Color("#d9bc65")},
	"arroz":{"name":"Arroz","price":150,"color":Color("#e6d8c0")},
	"refresco":{"name":"Refresco","price":65,"color":Color("#9b3e3d")},
	"cargador":{"name":"Cargador usado","price":350,"color":Color("#45474a")},
	"radio":{"name":"Radio vieja","price":750,"color":Color("#817969")},
	"grabadora":{"name":"Grabadora de casete","price":1100,"color":Color("#474b50")},
	"cable":{"name":"Cable USB usado","price":150,"color":Color("#42403d")},
	"audifonos":{"name":"Audífonos usados","price":400,"color":Color("#3d4547")},
	"control":{"name":"Control remoto","price":250,"color":Color("#55595d")},
	"linterna":{"name":"Linterna usada","price":300,"color":Color("#687d68")}
}
const FOOD_SETS := [["pollo"],["huevo","perrito","picadillo"],["picadillo","pollo","huevo"],["arroz","aceite"],["refresco","perrito"]]
const USED := ["cargador","radio","grabadora","cable","audifonos","control","linterna"]
var game
var world
var business
var state: Dictionary
var stalls: Array = []
var active: Dictionary = {}
var selected := 0
var view: Camera3D
var overlay: CanvasLayer
var info: Label
var highlight: Node3D
var spawn_wait := .8
var initialized := false
var clock := 0.0
var rng := RandomNumberGenerator.new()

func setup(controller) -> void:
	game = controller
	world = game.cuba_world
	business = game.business
	var life: Dictionary = business.ledger.life_data
	if not life.has("street_market"): life.street_market = {"inventory":{},"stocks":{}}
	state = life.street_market
	rng.randomize()
	view = Camera3D.new()
	add_child(view)
	view.projection = Camera3D.PROJECTION_ORTHOGONAL
	view.size = 3.6
	view.near = .05
	overlay = CanvasLayer.new()
	overlay.layer = 30
	add_child(overlay)
	var panel := PanelContainer.new()
	overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 20
	panel.offset_right = -20
	panel.offset_top = -106
	panel.offset_bottom = -14
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var skin := StyleBoxFlat.new()
	skin.bg_color = Color(.07,.10,.13,.94)
	skin.set_corner_radius_all(12)
	skin.content_margin_left = 16
	skin.content_margin_top = 10
	skin.content_margin_right = 16
	skin.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel",skin)
	info = Label.new()
	info.add_theme_font_size_override("font_size",17)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(info)
	overlay.hide()
	highlight = Node3D.new()
	add_child(highlight)
	for sign_value in [-1.0,1.0]:
		business._box(highlight,Vector3(0,0,float(sign_value)*.26),Vector3(.53,.016,.025),Color("#ffe58e"))
		business._box(highlight,Vector3(float(sign_value)*.26,0,0),Vector3(.025,.016,.53),Color("#ffe58e"))
	highlight.hide()

func _ground(p: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(p+Vector3.UP*2.0,p-Vector3.UP*.65,1|2)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty() or hit.normal.y<.85 or float(hit.position.y)>.35: return {}
	return hit

func _clear_patch(p: Vector3,d: Vector3,outward: Vector3) -> bool:
	# Leave the entire 1.4 m public sidewalk free. Only use setbacks
	# and vacant corner space behind it, never asphalt or a doorway.
	for x in [-1.05,0.0,1.05]:
		for z in [-.80,0.0,.80,1.42]:
			var q := p+d*float(x)+outward*float(z)
			if world.street_geometry.point_on_road(q) or not world._utility_open(q) or _ground(q).is_empty(): return false
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.12,1.8,2.30)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP,atan2(outward.x,outward.z)),p+outward*.24+Vector3.UP*1.12)
	# Symmetric corner sampling above also protects the footprints.
	query.collision_mask = 1|4|8|16
	if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return false
	var space := get_world_3d().direct_space_state
	for x in [-.8,0.0,.8]:
		var a := p+d*float(x)-outward*.75
		var b := a-outward*2.0
		var ray := PhysicsRayQueryParameters3D.create(a+Vector3.UP*.85,b+Vector3.UP*.85,1|4|16)
		if not space.intersect_ray(ray).is_empty(): return false
	return true

func _generate() -> void:
	var candidates: Array = []
	var anchor: Vector3 = world.home_spawn
	for id in world.geography.junctions:
		var center: Vector3 = world.geography.points[id]
		var distance := center.distance_to(anchor)
		if distance<18.0 or distance>850.0: continue
		var incident: Array = world.geography.junctions[id]
		var drivable := 0
		for edge in incident:
			if bool(edge.driveable): drivable += 1
		if drivable<3: continue
		candidates.append({"id":String(id),"p":center,"edges":incident,"distance":distance})
	candidates.sort_custom(func(a,b): return float(a.distance)<float(b.distance))
	var examined := 0
	for corner in candidates:
		if stalls.size()>=10: break
		examined += 1
		if examined%3==0: await get_tree().physics_frame
		var center: Vector3 = corner.p
		var separate := true
		for stall in stalls:
			if center.distance_to(stall.root.global_position)<26.0: separate = false
		if not separate: continue
		var made := false
		for edge in corner.edges:
			if not bool(edge.driveable): continue
			var other: Vector3 = edge.b if String(edge.a_id)==String(corner.id) else edge.a
			var d := (other-center).normalized()
			var side := Vector3(-d.z,0,d.x)
			for along in [7.5,10.5,14.0,18.0]:
				if float(along)>center.distance_to(other)-2.0: continue
				for sign_value in [-1.0,1.0]:
					var outward := side*float(sign_value)
					for setback in [2.5,3.1,4.0]:
						var p := center+d*float(along)+outward*(float(edge.width)*.5+float(setback))
						if not _clear_patch(p,d,outward): continue
						var ground := _ground(p)
						p.y = float(ground.position.y)+.025
						_make_stall(String(corner.id),p,d,outward,stalls.size())
						made = true
						break
					if made: break
				if made: break
			if made: break
	print("Mercado callejero: ",stalls.size()," puestos en espacios libres.")

func _make_stall(id: String,p: Vector3,d: Vector3,outward: Vector3,index: int) -> void:
	var root := Node3D.new()
	add_child(root)
	# Local +Z faces the seller, local -Z faces the sidewalk.
	root.global_transform = Transform3D(Basis(Vector3.UP,atan2(outward.x,outward.z)),p)
	var used := index%2==1
	var names := ["Pavel","Rosa","Chino","Marta","Luis","Odalys","Rogelio","Ana","Tito","Nena"]
	var name_value := String(names[index%names.size()])
	var person := Person.new()
	root.add_child(person)
	person.setup(750+index)
	person.position = Vector3(0,0,1.08)
	person.rotation.y = PI
	person.social_context = "worker"
	person.set_meta("citizen_id","street_"+id)
	person.set_meta("citizen_name",name_value)
	if used:
		# Worn clothes, uneven patches, scuffed shoes.
		for i in range(5):
			person._part(person,"box",Vector3(-.13+float(i%3)*.13,1.01+float(i%2)*.20,.141),Vector3(.065,.065,.012),Color("#726b55"))
		for leg in person.limbs:
			person._part(leg,"box",Vector3(0,-.57,.075),Vector3(.085,.12,.014),Color("#766c56"))
	var surface := .055 if used else .82
	if used:
		business._box(root,Vector3(0,.018,0),Vector3(2.05,.035,1.48),Color("#867b68"))
		for z in [-.64,.64]:
			business._box(root,Vector3(0,.039,float(z)),Vector3(1.99,.012,.045),Color("#c1b59a"))
	else:
		business._box(root,Vector3(0,.78,0),Vector3(1.92,.08,1.30),Color("#a18a6b"))
		for x in [-.81,.81]:
			for z in [-.49,.49]:
				business._box(root,Vector3(float(x),.38,float(z)),Vector3(.075,.76,.075),Color("#6d665a"))
		business._label(root,name_value+" · alimentos",Vector3(0,1.93,1.08),Color("#f5e5c6"))
	var keys: Array = []
	if used:
		for i in range(6): keys.append(USED[(index+i*2)%USED.size()])
	else:
		keys = FOOD_SETS[floori(float(index)/2.0)%FOOD_SETS.size()].duplicate()
	var stock: Dictionary = state.stocks.get(id,{})
	for key in keys:
		if not stock.has(key): stock[key] = 1+posmod(index+String(key).length(),4) if used else 4+posmod(index+String(key).length(),6)
	state.stocks[id] = stock
	var items: Array = []
	for i in range(keys.size()):
		var key := String(keys[i])
		var pos := Vector3((float(i%3)-1.0)*.65,surface+.10,(float(floori(float(i)/3.0))-.5)*.62)
		var item := Node3D.new()
		root.add_child(item)
		item.position = pos
		_model(item,key)
		item.visible = int(stock[key])>0
		items.append({"key":key,"node":item})
	var minute := int(business.life.state.minutes)%1440
	var open_now := minute>=420+index%3*45 and minute<1230+index%3*45
	root.visible = open_now
	stalls.append({"id":id,"root":root,"person":person,"name":name_value,"used":used,"items":items,"surface":surface,"stock":stock,"open":open_now,"index":index})

func _model(root: Node3D,key: String) -> void:
	var color: Color = GOODS[key].color
	match key:
		"radio","grabadora":
			business._box(root,Vector3.ZERO,Vector3(.45,.20,.26),color)
			for x in [-.13,.13]:
				business._box(root,Vector3(float(x),.01,-.137),Vector3(.12,.11,.02),Color("#25272a"))
			business._box(root,Vector3(0,.105,0),Vector3(.22,.02,.06),Color("#b3aca0"))
			if key=="radio": business._box(root,Vector3(.19,.16,.05),Vector3(.018,.30,.018),Color("#b4b6b4"))
			else: business._box(root,Vector3(0,.015,-.15),Vector3(.12,.085,.025),Color("#9d9b87"))
		"cargador","control","linterna":
			business._box(root,Vector3.ZERO,Vector3(.17,.10,.30),color)
			for i in range(3):
				business._box(root,Vector3(0,.06,-.075+float(i)*.07),Vector3(.07,.02,.025),Color("#b5b1a3"))
		"cable","audifonos":
			for i in range(12):
				var a := float(i)*TAU/12.0
				var obj: MeshInstance3D = business._box(root,Vector3(cos(a)*.13,0,sin(a)*.13),Vector3(.08,.035,.035),color)
				obj.rotation.y = -a+PI*.5
			for x in [-.13,.13]: business._box(root,Vector3(float(x),.03,.03),Vector3(.055,.055,.07),Color("#a5a5a0"))
		"huevo":
			business._box(root,Vector3(0,-.04,0),Vector3(.42,.06,.28),Color("#9a8b73"))
			for i in range(6):
				var mesh := MeshInstance3D.new()
				var egg := SphereMesh.new()
				egg.radius = .055
				egg.height = .14
				egg.radial_segments = 8
				egg.rings = 4
				mesh.mesh = egg
				mesh.material_override = business._mat(color)
				root.add_child(mesh)
				mesh.position = Vector3((float(i%3)-1.0)*.12,.035,(float(floori(float(i)/3.0))-.5)*.12)
		"refresco","aceite":
			business._box(root,Vector3(0,.03,0),Vector3(.13,.25,.13),color)
			business._box(root,Vector3(0,.17,0),Vector3(.07,.035,.07),Color("#e5dfcb"))
		_:
			business._box(root,Vector3.ZERO,Vector3(.37,.14,.26),color)
			business._box(root,Vector3(0,.077,0),Vector3(.15,.012,.12),Color("#e8e0cd"))

func _aimed() -> Dictionary:
	if not initialized or not active.is_empty(): return {}
	var cam: Camera3D = game.play_camera
	var at: Vector3 = game.player.global_position
	var origin := cam.global_position
	var direction := -cam.global_transform.basis.z
	var best: Dictionary = {}
	var nearest := INF
	for stall in stalls:
		if not bool(stall.open): continue
		var root: Node3D = stall.root
		if root.global_position.distance_to(at)>3.7: continue
		var local := root.to_local(origin)
		var ray := root.global_transform.basis.inverse()*direction
		if absf(ray.y)<.015: continue
		var depth := (float(stall.surface)-local.y)/ray.y
		if depth<0.0 or depth>8.0 or depth>=nearest: continue
		var point := local+ray*depth
		if absf(point.x)>1.12 or absf(point.z)>.83: continue
		var check := PhysicsRayQueryParameters3D.create(origin,root.to_global(point),1|4|16)
		check.exclude = [game.player.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(check).is_empty(): continue
		best = stall
		nearest = depth
	return best

func action_text() -> String:
	var stall := _aimed()
	if stall.is_empty(): return ""
	return "[E] Revisar manta" if bool(stall.used) else "[E] Ver productos de "+String(stall.name)

func interact() -> bool:
	var stall := _aimed()
	if stall.is_empty(): return false
	active = stall
	selected = 0
	var root: Node3D = stall.root
	view.global_position = root.to_global(Vector3(0,float(stall.surface)+3.2,0))
	view.look_at(root.to_global(Vector3(0,float(stall.surface),0)),-root.global_transform.basis.z)
	view.current = true
	game.reticle.hide()
	game.status.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	overlay.show()
	highlight.show()
	_refresh()
	return true

func _refresh() -> void:
	var items: Array = active.items
	var item: Dictionary = items[selected]
	var key := String(item.key)
	var node: Node3D = item.node
	var root: Node3D = active.root
	highlight.global_transform = Transform3D(root.global_transform.basis,node.global_position-Vector3.UP*.09)
	var count := int(active.stock.get(key,0))
	var availability := "%d disponibles" % count if count>0 else "AGOTADO"
	info.text = "%s  ·  %s  ·  %d CUP  ·  %s\nDinero: %d CUP  |  WASD / mouse: seleccionar  |  E / clic: comprar  |  Esc: salir" % [active.name,GOODS[key].name,GOODS[key].price,availability,business.ledger.cash]

func _buy() -> void:
	var item: Dictionary = active.items[selected]
	var key := String(item.key)
	var stock: Dictionary = active.stock
	if int(stock.get(key,0))<=0:
		_refresh()
		return
	var price := int(GOODS[key].price)
	if game.backpack!=null and not game.backpack.can_receive(key):
		info.text = "No tienes espacio en la mochila ni las manos libres."
		return
	if business.ledger.cash<price:
		info.text = "No tienes suficiente dinero. Esc para salir."
		return
	stock[key] = int(stock[key])-1
	var inventory: Dictionary = state.inventory
	inventory[key] = int(inventory.get(key,0))+1
	if not business.ledger.spend(price):
		stock[key] = int(stock[key])+1
		inventory[key] = int(inventory[key])-1
		return
	if game.backpack!=null:
		game.backpack.receive(key,false)
		business.ledger.save_game()
	item.node.visible = int(stock[key])>0
	_refresh()
	info.text += "\n"+String(["Gracias, mi hermano.","Que lo disfrutes.","Dale, aquí estamos.","Gracias, vuelve cuando quieras."].pick_random())

func _mouse_select(position: Vector2) -> void:
	var root: Node3D = active.root
	var origin := root.to_local(view.project_ray_origin(position))
	var ray := root.global_transform.basis.inverse()*view.project_ray_normal(position)
	if absf(ray.y)<.001: return
	var at := origin+ray*((float(active.surface)+.1-origin.y)/ray.y)
	var closest := .34
	for i in range(active.items.size()):
		var item: Node3D = active.items[i].node
		var dist := Vector2(at.x-item.position.x,at.z-item.position.z).length()
		if dist<closest:
			closest = dist
			selected = i
	if closest<.34: _refresh()

func handle(event: InputEvent) -> void:
	if active.is_empty(): return
	if event is InputEventMouseMotion:
		_mouse_select(event.position)
	elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		_mouse_select(event.position)
		# Only buy when clicking directly on the selected item's cell.
		var item: Node3D = active.items[selected].node
		if view.unproject_position(item.global_position).distance_to(event.position)<get_viewport().get_visible_rect().size.y*.10: _buy()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE,KEY_P: close()
			KEY_E,KEY_ENTER: _buy()
			KEY_A,KEY_LEFT: selected = maxi(0,selected-1)
			KEY_D,KEY_RIGHT: selected = mini(active.items.size()-1,selected+1)
			KEY_W,KEY_UP: selected = maxi(0,selected-3)
			KEY_S,KEY_DOWN: selected = mini(active.items.size()-1,selected+3)
		if not active.is_empty() and event.keycode not in [KEY_E,KEY_ENTER]: _refresh()

func close() -> void:
	active = {}
	overlay.hide()
	highlight.hide()
	game.play_camera.current = true
	game.status.show()
	game._apply_camera_mode()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func open_inventory() -> void:
	business._open("Mis compras","Productos comprados a vendedores de esquina y de manta.")
	for key in state.inventory:
		if not GOODS.has(key) or int(state.inventory[key])<=0: continue
		var line := Label.new()
		line.text = "%s × %d" % [GOODS[key].name,int(state.inventory[key])]
		business.content.add_child(line)
	business._button("Inicio",business.open_phone_home)
	business._button("Cerrar",business.close)

func tick(delta: float) -> void:
	if not initialized:
		spawn_wait -= delta
		if spawn_wait<=0.0:
			initialized = true
			_generate()
		return
	clock += delta
	if clock<2.0: return
	clock = 0.0
	var minute := int(business.life.state.minutes)%1440
	var previous := int(state.get("last_minute",minute))
	var next_day := minute+720<previous
	state.last_minute = minute
	for stall in stalls:
		if next_day:
			for item in stall.items:
				var key := String(item.key)
				var quantity := int(stall.stock.get(key,0))
				stall.stock[key] = mini(4 if bool(stall.used) else 9,quantity+rng.randi_range(1,2))
				item.node.visible = int(stall.stock[key])>0
		if not active.is_empty() and stall==active: continue
		var start := 420+int(stall.index)%3*45
		var finish := 1230+int(stall.index)%3*45
		stall.open = minute>=start and minute<finish
		stall.root.visible = stall.open
	if next_day: business.ledger.save_game()
