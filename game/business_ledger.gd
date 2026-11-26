extends RefCounted
# All prices are fictional gameplay values in CUP, not actual market data.
const PRODUCTS := {
	"pollo":{"name":"Pollo","cost":2200,"retail":300,"units":10},
	"picadillo":{"name":"Picadillo","cost":1500,"retail":210,"units":10},
	"perrito":{"name":"Perrito (salchicha)","cost":1200,"retail":170,"units":10}
}
const COMMISSION_PERCENT := 15
const VEHICLE_CAPACITY := 8
const SAVE_PATH := "user://pilar_business_v1.json"
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

func load_game() -> void:
	if not persistence_enabled: return
	if not FileAccess.file_exists(SAVE_PATH): return
	var f := FileAccess.open(SAVE_PATH,FileAccess.READ)
	if f==null: return
	var value: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not value is Dictionary: return
	cash = maxi(0,int(value.get("cash",10000)))
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
			add_message("Fábrica","Tus cajas que estaban en vehículos se guardaron en la fábrica al reiniciar.")
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
	var data := {"cash":cash,"stage":stage,"pending":pending,"carry":carry,"cargo":cargo,"stock":stock,"sold":sold,"revenue":revenue,"wages":wages,"expenses":expenses,"messages":messages,"unread":unread,"low_alert":low_alert}
	var f := FileAccess.open(SAVE_PATH,FileAccess.WRITE)
	if f!=null:
		f.store_string(JSON.stringify(data))
		f.close()

func total(counts: Dictionary) -> int:
	var result := 0
	for key in counts:
		result += int(counts[key])
	return result

func add_message(sender: String,body: String) -> void:
	messages.append({"sender":sender,"body":body})
	if messages.size()>50: messages.pop_front()
	unread = mini(50,unread+1)

func accept() -> void:
	if stage!=0: return
	stage = 1
	add_message("Albertico","Asere, coge un taxi pa' la fábrica. Allí venden pollo, picadillo y perrito por cajas.")
	save_game()

func factory_arrival() -> void:
	if stage==1:
		stage = 2
		save_game()

func buy(key: String,boxes: int) -> bool:
	if stage<2 or not PRODUCTS.has(key) or boxes<1 or boxes>8: return false
	var product: Dictionary = PRODUCTS[key]
	var cost := int(product.cost)*boxes
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

func deliver() -> bool:
	if carry.is_empty() or stage<3: return false
	var product: Dictionary = PRODUCTS[carry]
	stock[carry] = int(stock.get(carry,0))+int(product.units)
	low_alert[carry] = false
	carry = ""
	save_game()
	return true

func hire() -> bool:
	if stage!=3 or total(stock)<=0: return false
	stage = 4
	add_message("Albertico","¡Ya estamos montados! Yo vendo aquí afuera. Te aviso cuando quede poca mercancía. Mi parte es el 15% de cada venta.")
	save_game()
	return true

func sell_one() -> Dictionary:
	if stage!=4: return {}
	for key in PRODUCTS:
		if int(stock.get(key,0))<=0: continue
		var product: Dictionary = PRODUCTS[key]
		var price := int(product.retail)
		var pay := roundi(float(price)*float(COMMISSION_PERCENT)/100.0)
		stock[key] = int(stock[key])-1
		cash += price-pay
		revenue += price
		wages += pay
		sold += 1
		if int(stock[key])<=2 and not bool(low_alert.get(key,false)):
			low_alert[key] = true
			add_message("Albertico","Oye, se está acabando el "+String(product.name).to_lower()+". Quedan "+str(stock[key])+" unidades. Trae otra caja cuando puedas.")
		save_game()
		return {"product":product.name,"net":price-pay}
	return {}
