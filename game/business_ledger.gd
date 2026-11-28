extends RefCounted
# All prices are fictional gameplay values in CUP, not actual market data.
const PRODUCTS := {
	"pollo":{"name":"Pollo","cost":2200,"retail":300,"units":10},
	"huevos":{"name":"Huevos","cost":1000,"retail":140,"units":10},
	"picadillo":{"name":"Picadillo","cost":1500,"retail":210,"units":10},
	"perrito":{"name":"Perrito (salchicha)","cost":1200,"retail":170,"units":10},
	"harina":{"name":"Harina","cost":850,"retail":120,"units":10},
	"queso":{"name":"Queso","cost":1850,"retail":260,"units":10},
	"refresco":{"name":"Refrescos","cost":950,"retail":135,"units":10},
	"aceite":{"name":"Aceite","cost":1400,"retail":195,"units":10},
	"tomate":{"name":"Salsa de tomate","cost":750,"retail":105,"units":10}
}
const ADAPTATION_PRODUCTS := {
	"pollo":{"name":"Pollo","cost":80000,"retail":9000,"units":10},
	"huevos":{"name":"Huevos","cost":10000,"retail":120,"units":100},
	"aceite":{"name":"Aceite","cost":23000,"retail":2600,"units":10},
	"picadillo":{"name":"Picadillo","cost":6000,"retail":800,"units":10},
	"perrito":{"name":"Perrito (salchicha)","cost":10000,"retail":1200,"units":10}
}
const ADAPTATION_INTERVALS := {"huevos":5.0,"aceite":27.0,"pollo":65.0,"picadillo":18.0,"perrito":22.0}
func product(key: String) -> Dictionary:
	if save_path=="user://mycity_adaptation_v1.json" and ADAPTATION_PRODUCTS.has(key): return ADAPTATION_PRODUCTS[key]
	return PRODUCTS.get(key,{})

func adaptation_sales() -> bool:
	return save_path=="user://mycity_adaptation_v1.json"

func advance_sales(delta: float) -> void:
	if not adaptation_sales() or stage!=4: return
	if not life_data.has("adaptation_sale_clocks"): life_data.adaptation_sale_clocks = {}
	for key in stock:
		if int(stock[key])<=0: continue
		var interval := float(ADAPTATION_INTERVALS.get(key,35.0))
		life_data.adaptation_sale_clocks[key] = minf(interval,float(life_data.adaptation_sale_clocks.get(key,0.0))+delta)

func sale_ready() -> bool:
	if not adaptation_sales(): return total(stock)>0
	var clocks: Dictionary = life_data.get("adaptation_sale_clocks",{})
	for key in stock:
		if int(stock[key])>0 and float(clocks.get(key,0.0))>=float(ADAPTATION_INTERVALS.get(key,35.0)): return true
	return false

const COMMISSION_PERCENT := 15
const VEHICLE_CAPACITY := 8
const SAVE_PATH := "user://pilar_business_v1.json"
var save_path := SAVE_PATH
var persistence_enabled := true
var cash := 10000
var stage := 0
var pending: Dictionary = {}
var carry := ""
var cargo: Dictionary = {}
var stock: Dictionary = {}
var sold := 0
var revenue := 0
var wages := 0
var expenses := 0
var messages: Array = []
var unread := 0
var low_alert: Dictionary = {}
var sales_clock := 0.0
var life_data: Dictionary = {}

func load_game() -> void:
	if not persistence_enabled: return
	if not FileAccess.file_exists(save_path): return
	var f := FileAccess.open(save_path,FileAccess.READ)
	if f==null: return
	var value: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not value is Dictionary: return
	cash = maxi(0,int(value.get("cash",10000)))
	var life: Variant = value.get("city_life",{})
	life_data = life if life is Dictionary else {}
	stage = clampi(int(value.get("stage",0)),0,4)
	pending = _counts(value.get("pending",{}))
	stock = _counts(value.get("stock",{}))
	carry = String(value.get("carry",""))
	if not PRODUCTS.has(carry): carry = ""
	# Taxis and van respawn with the city scene. Recover every saved
	# vehicle crate at the warehouse rather than losing paid inventory.
	var saved_cargo: Variant = value.get("cargo",{})
	if saved_cargo is Dictionary:
		for vehicle in saved_cargo:
			var counts := _counts(saved_cargo[vehicle])
			for key in counts:
				pending[key] = int(pending.get(key,0))+int(counts[key])
		if not saved_cargo.is_empty():
			add_message("MIPYME","Tus cajas que estaban en vehículos se guardaron en la MIPYME al reiniciar.")
	cargo = {}
	sold = maxi(0,int(value.get("sold",0)))
	revenue = maxi(0,int(value.get("revenue",0)))
	wages = maxi(0,int(value.get("wages",0)))
	expenses = maxi(0,int(value.get("expenses",0)))
	var old_messages: Variant = value.get("messages",[])
	var recovered := messages.duplicate()
	messages = old_messages if old_messages is Array else []
	messages.append_array(recovered)
	unread = maxi(0,int(value.get("unread",0)))+recovered.size()
	var alerts: Variant = value.get("low_alert",{})
	low_alert = alerts if alerts is Dictionary else {}
	if not recovered.is_empty(): save_game()

func _counts(value: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not value is Dictionary: return result
	for key in PRODUCTS:
		var count := clampi(int(value.get(key,0)),0,100000)
		if count>0: result[key] = count
	return result

func save_game() -> void:
	if not persistence_enabled: return
	var data := {"cash":cash,"stage":stage,"pending":pending,"carry":carry,"cargo":cargo,"stock":stock,"sold":sold,"revenue":revenue,"wages":wages,"expenses":expenses,"messages":messages,"unread":unread,"low_alert":low_alert,"city_life":life_data}
	# Write beside the live save, then replace it only after a complete write.
	var temp := save_path+".tmp"
	var f := FileAccess.open(temp,FileAccess.WRITE)
	if f==null:
		push_warning("MyCity: no se pudo abrir guardado temporal.")
		return
	f.store_string(JSON.stringify(data))
	f.flush()
	var error := f.get_error()
	f.close()
	if error!=OK:
		push_warning("MyCity: escritura de partida incompleta; se conserva la anterior.")
		return
	if DirAccess.rename_absolute(temp,save_path)!=OK:
		push_warning("MyCity: no se pudo reemplazar la partida; se conserva el archivo temporal.")

# City purchases share the same wallet and save transaction as missions.
func spend(amount: int) -> bool:
	if amount<0 or cash<amount: return false
	cash -= amount
	expenses += amount
	save_game()
	return true

func total(counts: Dictionary) -> int:
	var result := 0
	for key in counts:
		result += int(counts[key])
	return result

func add_message(sender: String,body: String) -> void:
	messages.append({"sender":sender,"body":body})
	if messages.size()>50: messages.pop_front()
	unread = mini(50,unread+1)

# The invitation and meeting are saved separately from mission acceptance.
func albertico_visible() -> bool:
	return stage>0 or bool(life_data.get("albertico_meeting",false))

func invite_albertico() -> bool:
	if stage!=0 or albertico_visible() or bool(life_data.get("albertico_invited",false)): return false
	life_data["albertico_invited"] = true
	add_message("Albertico","Asere, te tengo un bisne. Avísame por aquí y nos vemos afuera de tu casa.")
	save_game()
	return true

func meet_albertico() -> bool:
	if stage!=0 or albertico_visible() or not bool(life_data.get("albertico_invited",false)): return false
	life_data["albertico_meeting"] = true
	add_message("Tú → Albertico","Dale, nos vemos afuera.")
	save_game()
	return true

func accept() -> void:
	if stage!=0: return
	stage = 1
	add_message("Albertico","Asere, vamos juntos a la MIPYME. Compramos una caja de huevos, perritos, pollo y picadillo. Yo te ayudo a cargarlas." if life_data.has("albertico_story") else "Asere, coge un taxi pa' la MIPYME. Allí venden pollo, picadillo y perrito por cajas.")
	save_game()

func factory_arrival() -> void:
	if stage==1:
		stage = 2
		save_game()

func buy(key: String,boxes: int) -> bool:
	if stage<2 or not PRODUCTS.has(key) or boxes<1 or boxes>8: return false
	var item: Dictionary = product(key)
	var cost := int(item.cost)*boxes
	if cash<cost: return false
	cash -= cost
	expenses += cost
	pending[key] = int(pending.get(key,0))+boxes
	save_game()
	return true

func pick_up(key: String) -> bool:
	if not carry.is_empty() or int(pending.get(key,0))<=0: return false
	pending[key] = int(pending[key])-1
	carry = key
	save_game()
	return true

func load_vehicle(id: String) -> bool:
	if carry.is_empty() or id.is_empty(): return false
	var counts: Dictionary = cargo.get(id,{})
	if total(counts)>=VEHICLE_CAPACITY: return false
	counts[carry] = int(counts.get(carry,0))+1
	cargo[id] = counts
	carry = ""
	if stage==2: stage = 3
	save_game()
	return true

func unload_vehicle(id: String) -> bool:
	if not carry.is_empty(): return false
	var counts: Dictionary = cargo.get(id,{})
	for key in PRODUCTS:
		if int(counts.get(key,0))<=0: continue
		counts[key] = int(counts[key])-1
		carry = key
		if total(counts)==0: cargo.erase(id)
		else: cargo[id] = counts
		save_game()
		return true
	return false

# Move exactly one paid vehicle crate to the stall in a single save.
func deliver_vehicle_box(id: String,key: String) -> bool:
	if stage!=4 or not PRODUCTS.has(key): return false
	var counts: Dictionary = cargo.get(id,{})
	if int(counts.get(key,0))<=0: return false
	counts[key] = int(counts[key])-1
	if total(counts)==0: cargo.erase(id)
	else: cargo[id] = counts
	stock[key] = int(stock.get(key,0))+int(product(key).units)
	low_alert[key] = false
	save_game()
	return true

func deliver() -> bool:
	if carry.is_empty() or stage<3: return false
	var item: Dictionary = product(carry)
	stock[carry] = int(stock.get(carry,0))+int(item.units)
	low_alert[carry] = false
	carry = ""
	save_game()
	return true

func hire() -> bool:
	if life_data.has("albertico_story"): return false
	if stage!=3 or total(stock)<=0: return false
	stage = 4
	add_message("Albertico","¡Ya estamos montados! Yo vendo aquí afuera. Te aviso cuando quede poca mercancía. Mi parte es el 15% de cada venta.")
	save_game()
	return true

func sell_one() -> Dictionary:
	if stage!=4: return {}
	for key in PRODUCTS:
		if int(stock.get(key,0))<=0: continue
		if adaptation_sales():
			var clocks: Dictionary = life_data.get("adaptation_sale_clocks",{})
			if float(clocks.get(key,0.0))<float(ADAPTATION_INTERVALS.get(key,35.0)): continue
			clocks[key] = 0.0
		var item: Dictionary = product(key)
		var price := int(item.retail)
		# No unapproved commission: the agreed first lot has 15,000 CUP gross profit.
		var pay := 0 if adaptation_sales() else roundi(float(price)*float(COMMISSION_PERCENT)/100.0)
		stock[key] = int(stock[key])-1
		cash += price-pay
		revenue += price
		wages += pay
		sold += 1
		if int(stock[key])<=maxi(2,floori(float(item.units)*.2)) and not bool(low_alert.get(key,false)):
			low_alert[key] = true
			add_message("Albertico","Oye, se está acabando el "+String(item.name).to_lower()+". Quedan "+str(stock[key])+" unidades. Trae otra caja cuando puedas.")
		save_game()
		return {"product":item.name,"net":price-pay}
	return {}
