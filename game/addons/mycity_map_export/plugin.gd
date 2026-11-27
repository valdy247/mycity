@tool
extends EditorPlugin

var exporter: EditorExportPlugin

func _enter_tree() -> void:
	exporter = MapExport.new()
	add_export_plugin(exporter)

func _exit_tree() -> void:
	if exporter!=null:
		remove_export_plugin(exporter)
		exporter = null

class MapExport extends EditorExportPlugin:
	func _get_name() -> String:
		return "MyCityMapExport"

	func _export_begin(features: PackedStringArray,_debug: bool,path: String,_flags: int) -> void:
		if not features.has("web") and not path.to_lower().ends_with(".html"): return
		var source := "res://pilar_atares_v2.osm"
		if not FileAccess.file_exists(source):
			push_error("MYCITY WEB MAP: falta "+source)
			return
		var data := FileAccess.get_file_as_bytes(source)
		if data.is_empty():
			push_error("MYCITY WEB MAP: mapa vacío o ilegible")
			return
		add_file("res://web_map/pilar_atares_v2.osm",data,false)
		print("MYCITY WEB MAP: ",data.size()," bytes incluidos en PCK.")
