extends RefCounted
# Disposable derived data only. Never reads or writes gameplay saves.
const MAX_BYTES := 192*1024*1024

static func digest(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()

static func key_for(value: Variant) -> String:
	return digest(var_to_bytes(value))

static func read(path: String,key: String) -> Dictionary:
	if key.is_empty() or not FileAccess.file_exists(path): return {}
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return {}
	if file.get_length()>MAX_BYTES+512 or file.get_line()!=key: return {}
	var checksum := file.get_line()
	if file.get_length()-file.get_position()<8: return {}
	var size := file.get_64()
	if size<=0 or size>MAX_BYTES or size!=file.get_length()-file.get_position(): return {}
	var bytes := file.get_buffer(size)
	if digest(bytes)!=checksum: return {}
	var decoded: Variant = bytes_to_var(bytes)
	return decoded if decoded is Dictionary else {}

static func write(path: String,key: String,data: Dictionary) -> void:
	if key.is_empty(): return
	var bytes := var_to_bytes(data)
	if bytes.is_empty() or bytes.size()>MAX_BYTES: return
	var temp := path+"."+str(OS.get_process_id())+".tmp"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return
	file.store_line(key)
	file.store_line(digest(bytes))
	file.store_64(bytes.size())
	file.store_buffer(bytes)
	file.close()
	if DirAccess.rename_absolute(temp,path)!=OK:
		DirAccess.remove_absolute(temp)
