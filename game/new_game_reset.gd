extends RefCounted
# Reset gameplay only. Preserve edited map, geometry caches and local audio.
const FILES := ["pilar_business_v1.json","pilar_atares_inventory.json","mycity_adaptation_v1.json","mycity_adaptation_inventory_v1.json","mycity_chapter1_v2.json"]
const SUFFIXES := ["",".bak",".tmp",".bak.tmp"]

static func reset() -> Dictionary:
	var folder := "user://new_game_backups/"+str(Time.get_unix_time_from_system()).replace(".","_")+"_"+str(Time.get_ticks_usec())
	var error := DirAccess.make_dir_recursive_absolute(folder)
	if error!=OK: return {"ok":false,"error":"No se pudo crear la carpeta de respaldo."}
	var files: Array[String] = []
	for base in FILES:
		for suffix in SUFFIXES:
			var name: String = base+suffix
			if not FileAccess.file_exists("user://"+name): continue
			if DirAccess.copy_absolute("user://"+name,folder+"/"+name)!=OK:
				return {"ok":false,"error":"No se pudo respaldar "+name}
			files.append(name)
	for name in files:
		if DirAccess.remove_absolute("user://"+name)!=OK:
			for original in files:
				if not FileAccess.file_exists("user://"+original):
					DirAccess.copy_absolute(folder+"/"+original,"user://"+original)
			return {"ok":false,"error":"No se pudo borrar "+name+"; se intentó recuperar el respaldo."}
	for base in FILES:
		for suffix in SUFFIXES:
			if FileAccess.file_exists("user://"+base+suffix):
				return {"ok":false,"error":"Todavía existe un archivo de progreso: "+base+suffix}
	print("MyCity NUEVA PARTIDA: ",files.size()," archivos retirados de ",OS.get_user_data_dir())
	print("MyCity respaldo: ",ProjectSettings.globalize_path(folder))
	return {"ok":true,"removed":files.size(),"backup":folder}
