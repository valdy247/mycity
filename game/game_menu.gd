extends CanvasLayer
const Ledger = preload("res://business_ledger.gd")
const SAVE_FILES := [Ledger.SAVE_PATH,"user://pilar_atares_inventory.json"]
const ADAPTATION_FILES := ["user://mycity_adaptation_v1.json","user://mycity_adaptation_inventory_v1.json","user://mycity_chapter1_v2.json"]
var game
var menu_open := false
var root: ColorRect
var heading: Label
var info: Label
var actions: VBoxContainer
var confirming := false

func setup(controller) -> void:
	game = controller
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = ColorRect.new()
	root.color = Color("#101e2aef")
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	root.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	actions = VBoxContainer.new()
	actions.custom_minimum_size.x = 340.0
	actions.add_theme_constant_override("separation",10)
	center.add_child(actions)
	root.hide()

func _button(label_value: String,callback: Callable) -> void:
	var button := Button.new()
	button.text = label_value
	button.custom_minimum_size = Vector2(340,47)
	button.add_theme_font_size_override("font_size",18)
	button.pressed.connect(callback)
	actions.add_child(button)

func _render(startup: bool) -> void:
	for child in actions.get_children():
		actions.remove_child(child)
		child.queue_free()
	heading = Label.new()
	heading.text = "MYCITY · LA HABANA"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size",28)
	actions.add_child(heading)
	info = Label.new()
	info.text = "Partida guardada" if FileAccess.file_exists(Ledger.SAVE_PATH) else "Tu historia comienza aquí"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	actions.add_child(info)
	if confirming:
		info.text = "Reiniciar dinero, inventario, casa, cafetera y todas las misiones.\nTus edificios y mapa se conservan. Se crea una copia de respaldo."
		_button("Confirmar nueva partida",_new_game)
		_button("Cancelar",func(): confirming = false; _render(false))
	else:
		_button("Continuar partida" if FileAccess.file_exists(Ledger.SAVE_PATH) else "Jugar",close_menu)
		if not startup: _button("Recuperar punto de control",_recover)
		_button("Nueva partida",func(): confirming = true; _render(false))

func open_menu(startup: bool = false) -> void:
	if menu_open: return
	menu_open = true
	confirming = false
	_render(startup)
	root.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_instance_valid(game.mobile_controls): game.mobile_controls.sync()
	get_tree().paused = true

func close_menu() -> void:
	menu_open = false
	confirming = false
	root.hide()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if game.mobile_mode else Input.MOUSE_MODE_CAPTURED
	if is_instance_valid(game.mobile_controls): game.mobile_controls.sync()

func _recover() -> void:
	close_menu()
	game.recover_checkpoint()

func _new_game() -> void:
	var suffix := "."+str(Time.get_unix_time_from_system()).replace(".","_")+".bak"
	var copied: Array[String] = []
	var files: Array[String] = []
	for base in SAVE_FILES+ADAPTATION_FILES:
		for ending in ["",".bak",".tmp",".bak.tmp"]:
			files.append(String(base)+ending)
	for path in files:
		if not FileAccess.file_exists(path): continue
		if DirAccess.copy_absolute(path,path+suffix)!=OK:
			info.text = "No se pudo crear el respaldo. La partida sigue intacta."
			return
		copied.append(path)
	for path in copied:
		if DirAccess.remove_absolute(path)!=OK:
			for original in copied:
				if not FileAccess.file_exists(original): DirAccess.copy_absolute(original+suffix,original)
			info.text = "No se pudo reiniciar la partida. Se conservan los respaldos."
			return
	if game.business!=null: game.business.ledger.persistence_enabled = false
	call_deferred("_reload")

func _reload() -> void:
	var tree := get_tree()
	var error: Error
	if tree.has_meta("mycity_adaptation"): tree.remove_meta("mycity_adaptation")
	if tree.has_meta("mycity_warmed_map"): tree.remove_meta("mycity_warmed_map")
	error = tree.change_scene_to_file("res://airport.tscn")
	tree.paused = false
	if error!=OK:
		if game.business!=null: game.business.ledger.persistence_enabled = true
		info.text = "No se pudo recargar la escena. Reinicia el juego."
		tree.paused = true

func _input(event: InputEvent) -> void:
	if menu_open and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_ESCAPE,KEY_F10]:
		close_menu()
		get_viewport().set_input_as_handled()
