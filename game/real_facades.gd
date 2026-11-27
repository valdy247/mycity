extends RefCounted
# First architectural batch. Only identified OSM footprints are replaced.
# No new renderer, high-resolution textures, terrain or animated objects.
var city
var selected: Dictionary = {}
const NAMES := {"pilar":"Iglesia del Pilar","abel":"Policlínico Abel Santamaría","cristina":"Estación Cristina · Museo del Ferrocarril","dependiente":"Hospital La Dependiente","tejas":"Torres de Tejas","cafe_tejas":"Cafetería Esquina de Tejas"}

static func profile(id: String,label: String,kind: String) -> String:
	if id=="437450994" or label.contains("iglesia del pilar") or label.contains("senora del pilar"): return "pilar"
	if id=="194910494" or label.contains("museo del ferrocarril") or label.contains("estacion cristina"): return "cristina"
	if id=="290017021" or label.contains("la dependiente"): return "dependiente"
	if id=="360422640": return "cafe_tejas"
	if id=="320464758" or label in ["tejas 1","tejas 2"]: return "tejas"
	if label.contains("abel santamaria") and (label.contains("policlinico") or kind in ["clinic","hospital","doctors"]): return "abel"
	return ""

func _kind(tags: Dictionary) -> String:
	return String(tags.get("healthcare",tags.get("amenity","")))

func prepare(world) -> void:
	city = world
	selected.clear()
	var candidates: Dictionary = {}
	for fp in city.geography.footprints:
		var tags: Dictionary = fp.tags
		var label: String = city.geography.normalized(String(tags.get("name","")))
		var key := profile(String(fp.id),label,_kind(tags))
		if key.is_empty(): continue
		if city._market_reserved(fp.poly): continue
		if key=="tejas" and Vector3(fp.center).distance_to(city.geography.project(23.11739,-82.37114))>180.0: continue
		if key=="abel" and Vector3(fp.center).distance_to(city.geography.project(23.1195,-82.3690))>450.0: continue
		selected[String(fp.id)] = key
		candidates[key] = true
	# Named clinic node, if present, must lie inside exactly one building.
	if not candidates.has("abel"):
		for poi in city.geography.poi:
			var tags: Dictionary = poi.tags
			var label: String = city.geography.normalized(String(tags.get("name","")))
			if profile("",label,_kind(tags))!="abel": continue
			var pos: Vector3 = poi.position
			if pos.distance_to(city.geography.project(23.1195,-82.3690))>450.0: continue
			var matches: Array = []
			for fp in city.geography.footprints_near(pos,12.0):
				if Geometry2D.is_point_in_polygon(Vector2(pos.x,pos.z),fp.poly) and not city._market_reserved(fp.poly): matches.append(fp)
			if matches.size()==1:
				selected[String(matches[0].id)] = "abel"
				candidates["abel"] = true
				break
	# Player-confirmed pin from the city editor. Accept only an unambiguous
	# containing footprint, never snap to a nearby unrelated building.
	if not candidates.has("abel"):
		var pin: Vector3 = city.geography.project(23.1190534,-82.3687006)
		var matches: Array = []
		for fp in city.geography.footprints_near(pin,12.0):
			if not Geometry2D.is_point_in_polygon(Vector2(pin.x,pin.z),fp.poly): continue
			if city._market_reserved(fp.poly): continue
			matches.append(fp)
		if matches.size()==1:
			var fp: Dictionary = matches[0]
			var tags: Dictionary = fp.tags
			var label: String = city.geography.normalized(String(tags.get("name","")))
			var id := String(fp.id)
			if not selected.has(id) and (label.is_empty() or profile(id,label,_kind(tags))=="abel"):
				selected[id] = "abel"
				candidates["abel"] = true
				print("Abel Santamaría: huella OSM ",id," identificada mediante GPS del editor.")
		if not candidates.has("abel"):
			push_warning("Abel Santamaría: GPS sin huella inequívoca; no se sustituye un edificio vecino.")
	for key in NAMES:
		if not candidates.has(key): push_warning("Fachada real pendiente: "+String(NAMES[key])+" (sin huella identificada en OSM local)")

func reserved(poly: PackedVector2Array) -> bool:
	if city==null or selected.is_empty(): return false
	var rect: Rect2 = city.street_geometry.bounds(poly)
	var center := rect.get_center()
	for fp in city.geography.footprints_near(Vector3(center.x,0,center.y),rect.size.length()*.5+2.0):
		if selected.has(String(fp.id)) and not Geometry2D.intersect_polygons(poly,fp.poly).is_empty(): return true
	return false

func _mat(name: String,color: String) -> StandardMaterial3D:
	return city._mat("landmark_"+name,Color(color))

func _box(p: Vector3,n: Vector3,w: float,h: float,depth: float,material: StandardMaterial3D,solid: bool = false) -> void:
	city._cube(p,Vector3(w,h,depth),material,atan2(n.x,n.z),solid)

func _front(fp: Dictionary,key: String) -> Dictionary:
	var poly: PackedVector2Array = fp.poly
	var fallback: Dictionary = city._front_edge(poly)
	var wanted := "estevez" if key=="pilar" else ("monte" if key=="abel" else ("cristina" if key=="cristina" else ""))
	if not wanted.is_empty():
		for face in city._street_facing_walls(poly):
			if city._market_named(face.road,wanted): return face
	if not fallback.is_empty(): return fallback
	# Set the normal outward even for a recessed footprint without a road.
	var longest := 0.0
	var result: Dictionary = {}
	for i in range(poly.size()):
		var a := Vector3(poly[i].x,0,poly[i].y)
		var b := Vector3(poly[(i+1)%poly.size()].x,0,poly[(i+1)%poly.size()].y)
		if a.distance_to(b)<=longest: continue
		longest = a.distance_to(b)
		var mid := (a+b)*.5
		var t := (b-a).normalized()
		var n := Vector3(-t.z,0,t.x)
		var probe := mid+n*.15
		if Geometry2D.is_point_in_polygon(Vector2(probe.x,probe.z),poly): n = -n
		result = {"a":a,"b":b,"mid":mid,"normal":n}
	return result

func _safe_front(point: Vector3) -> bool:
	return not city.street_geometry.point_on_road(point)

func _sign(words: String,p: Vector3,n: Vector3,width: float,color: Color) -> void:
	var label: Label3D = city._label(words,p,minf(.013,width/maxf(1.0,float(words.length())*27.0)),atan2(n.x,n.z),color)
	label.outline_size = 0

func _arch(p: Vector3,n: Vector3,t: Vector3,w: float,h: float,trim: StandardMaterial3D,glass: StandardMaterial3D) -> void:
	city._market_arch(p+n*.045,n,t,w,h,trim)
	city._market_arch(p+n*.072+Vector3.UP*.12,n,t,w*.82,h-.19,glass)

func _roof(poly: PackedVector2Array,center: Vector3,h: float,rise: float,tile: Vector2i,mat: StandardMaterial3D) -> void:
	var mid := Vector2(center.x,center.z)
	if not Geometry2D.is_point_in_polygon(mid,poly): return
	var upper: PackedVector2Array = city._market_scaled(poly,mid,.43)
	for q in upper:
		if not Geometry2D.is_point_in_polygon(q,poly): return
	city._market_roof_band(poly,upper,h,h+rise,mat,tile)
	city._extrude(upper,h+rise-.10,h+rise,mat,tile)

func _church(fp: Dictionary,face: Dictionary,tile: Vector2i,h: float) -> void:
	var n: Vector3 = face.normal
	var t: Vector3 = (Vector3(face.b)-Vector3(face.a)).normalized()
	var mid: Vector3 = face.mid
	var width: float = face.a.distance_to(face.b)
	var plaster := _mat("church_white","#ddd9c9")
	var stone := _mat("church_trim","#e5dfcf")
	var dark := _mat("church_door","#353c36")
	var tiles := _mat("church_roof","#756655")
	var poly: PackedVector2Array = fp.poly
	var center: Vector3 = fp.center
	_roof(poly,center,h,2.35,tile,tiles)
	_box(mid+Vector3.UP*(h-.10)+n*.09,n,width,.25,.23,stone)
	_box(mid+Vector3.UP*3.65+n*.06,n,width,.12,.13,stone)
	for side in [-1.0,1.0]:
		var p := mid+t*float(side)*width*.23
		_arch(p,n,t,minf(2.1,width*.24),3.5,stone,dark)
		var steps_width := minf(2.7,width*.31)
		for i in range(3):
			var at := p+n*(.22+float(i)*.27)
			if _safe_front(at): _box(at+Vector3.UP*(.27-float(i)*.08),n,steps_width,.18,.34,stone,true)
	for i in range(poly.size()):
		var a := Vector3(poly[i].x,0,poly[i].y)
		var b := Vector3(poly[(i+1)%poly.size()].x,0,poly[(i+1)%poly.size()].y)
		var length := a.distance_to(b)
		if length<5.0 or ((a+b)*.5).distance_to(mid)<1.0: continue
		var axis := (b-a).normalized()
		var out := Vector3(-axis.z,0,axis.x)
		var probe := (a+b)*.5+out*.10
		if Geometry2D.is_point_in_polygon(Vector2(probe.x,probe.z),poly): out = -out
		_box((a+b)*.5+out*.07+Vector3.UP*(h-.1),out,length,.18,.18,stone)
		for j in range(clampi(floori(length/6.0),1,8)):
			var q := a.lerp(b,(float(j)+.5)/float(clampi(floori(length/6.0),1,8)))
			_arch(q+Vector3.UP*2.3,out,axis,1.05,2.7,stone,dark)
	# Single square bell tower with dark domed crown and cross, like the photo.
	var tower_width := minf(4.2,width*.34)
	var tower := mid-t*width*.26-n*(tower_width*.5+.22)
	var fits := true
	for x in [-.5,.5]:
		for z in [-.5,.5]:
			var p := tower+t*float(x)*tower_width+n*float(z)*tower_width
			if not Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),poly): fits = false
	if fits:
		_box(tower+Vector3.UP*(h+1.65),n,tower_width,3.3,tower_width,plaster,true)
		for out in [n,-n,t,-t]:
			var axis := Vector3(-out.z,0,out.x)
			var p: Vector3 = tower+out*(tower_width*.5+.025)+Vector3.UP*(h+.65)
			for side in [-1.0,1.0]:
				_arch(p+axis*float(side)*tower_width*.24,out,axis,tower_width*.32,1.95,stone,dark)
		var dome := SphereMesh.new()
		dome.radial_segments = 12
		dome.rings = 6
		dome.radius = .5
		dome.height = 1.0
		var visual := MeshInstance3D.new()
		visual.mesh = dome
		visual.material_override = tiles
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		city.add_child(visual)
		visual.position = tower+Vector3.UP*(h+3.55)
		visual.scale = Vector3(tower_width,2.1,tower_width)
		_box(tower+Vector3.UP*(h+5.10),n,.12,1.3,.12,dark)
		_box(tower+Vector3.UP*(h+5.30),n,.78,.12,.12,dark)
	_sign("IGLESIA DEL PILAR",mid+n*.10+Vector3.UP*4.12,n,width*.7,Color("#57584f"))

func _clinic(face: Dictionary,h: float,recess: bool) -> void:
	var mid: Vector3 = face.mid
	var n: Vector3 = face.normal
	var t: Vector3 = (Vector3(face.b)-Vector3(face.a)).normalized()
	var width: float = face.a.distance_to(face.b)
	var blue := _mat("abel_blue","#538b9b")
	var dark := _mat("abel_glass","#354c53")
	var grille := _mat("abel_lattice","#aa8576")
	var count := clampi(roundi(width/3.4),3,12)
	var bay := width/float(count)
	for i in range(count):
		var p := mid+t*((float(i)+.5)*bay-width*.5)
		_box(p+n*(-1.55 if recess else .05)+Vector3.UP*1.6,n,bay*.79,3.0,.09,dark)
		_box(p+t*bay*.48+n*.10+Vector3.UP*1.6,n,.28,3.2,.25,blue,recess)
		for floor in [4.55,7.1]:
			_box(p+n*.055+Vector3.UP*float(floor),n,bay*.84,1.40,.07,dark)
			_box(p+n*.085+Vector3.UP*float(floor),n,bay*.80,1.24,.05,grille)
			for j in range(5):
				_box(p+n*.12+t*((float(j)-2.0)*bay*.145)+Vector3.UP*float(floor),n,.055,1.24,.045,dark)
			for j in range(4):
				_box(p+n*.13+Vector3.UP*(float(floor)+(float(j)-1.5)*.27),n,bay*.80,.05,.04,dark)
	for y in [3.3,5.65,8.1,h-.15]:
		_box(mid+n*.09+Vector3.UP*float(y),n,width,.20,.24,blue)
	_sign("POLICLÍNICO ABEL SANTAMARÍA",mid+n*.18+Vector3.UP*(h-.75),n,width*.92,Color("#e4e9e4"))

func _station(face: Dictionary,h: float,lowered: bool) -> void:
	var mid: Vector3 = face.mid
	var n: Vector3 = face.normal
	var t: Vector3 = (Vector3(face.b)-Vector3(face.a)).normalized()
	var width: float = face.a.distance_to(face.b)
	var cream := _mat("station_cream","#e0d8bc")
	var trim := _mat("station_trim","#c4b79a")
	var dark := _mat("station_window","#354849")
	var count := clampi(roundi(width/4.6),3,12)
	var bay := width/float(count)
	var depth := -1.7 if lowered else .045
	for i in range(count):
		var p := mid+t*((float(i)+.5)*bay-width*.5)
		_arch(p+n*depth+Vector3.UP*.22,n,t,bay*.76,3.9,trim,dark)
		var column := p+t*bay*.48-n*.20
		_box(column+Vector3.UP*2.30,n,.44,4.6,.44,cream,lowered)
		for y in [.22,4.48]:
			_box(column+Vector3.UP*float(y),n,.68,.28,.68,trim)
	for y in [4.85,h-.12]:
		_box(mid+n*.07+Vector3.UP*float(y),n,width,.38,.40,trim)
	_sign("FERROCARRIL DEL OESTE",mid+n*.31+Vector3.UP*5.33,n,width*.82,Color("#786347"))

func _hospital(face: Dictionary,h: float) -> void:
	var mid: Vector3 = face.mid
	var n: Vector3 = face.normal
	var t: Vector3 = (Vector3(face.b)-Vector3(face.a)).normalized()
	var width: float = face.a.distance_to(face.b)
	var stone := _mat("hospital_stone","#d3cdbd")
	var dark := _mat("hospital_window","#3e4d49")
	var count := clampi(roundi(width/3.2),3,18)
	var bay := width/float(count)
	for i in range(count):
		var p := mid+t*((float(i)+.5)*bay-width*.5)
		_arch(p+Vector3.UP*.28,n,t,bay*.60,3.15,stone,dark)
		if h>6.0: _arch(p+Vector3.UP*4.25,n,t,bay*.60,2.35,stone,dark)
		_box(p+t*bay*.47+n*.06+Vector3.UP*(h*.5),n,.22,h,.21,stone)
	_box(mid+n*.11+Vector3.UP*(h-.20),n,width,.30,.34,stone)
	_sign("HOSPITAL LA DEPENDIENTE",mid+n*.17+Vector3.UP*3.75,n,width*.88,Color("#596963"))

func _tower(fp: Dictionary,h: float) -> void:
	var poly: PackedVector2Array = fp.poly
	var wall := _mat("tejas_band","#b9bab3")
	var glass := _mat("tejas_windows","#4b585b")
	var levels := clampi(roundi(h/3.1),12,24)
	var step := h/float(levels)
	for i in range(poly.size()):
		var a := Vector3(poly[i].x,0,poly[i].y)
		var b := Vector3(poly[(i+1)%poly.size()].x,0,poly[(i+1)%poly.size()].y)
		var width := a.distance_to(b)
		if width<2.5: continue
		var t := (b-a).normalized()
		var n := Vector3(-t.z,0,t.x)
		var mid := (a+b)*.5
		var probe := mid+n*.10
		if Geometry2D.is_point_in_polygon(Vector2(probe.x,probe.z),poly): n = -n
		# Long horizontal window ribbons visible from a distance. At most
		# three vertical subdivisions, not a window mesh for each apartment.
		for floor in range(1,levels):
			var y := (float(floor)+.47)*step
			_box(mid+n*.035+Vector3.UP*y,n,width*.86,step*.34,.17,glass)
			_box(mid+n*.08+Vector3.UP*(y-step*.24),n,width*.98,.18,.16,wall)
			for divider in [-.22,0.0,.22]:
				_box(mid+t*width*float(divider)+n*.09+Vector3.UP*y,n,.19,step*.40,.18,wall)

# Two-storey historic corner café, based on the player's reference.
# All columns, balusters and window trim use the city's batched boxes.
func _tejas_cafe(fp: Dictionary,face: Dictionary,tile: Vector2i,h: float) -> bool:
	var poly: PackedVector2Array = fp.poly
	var cream := _mat("cafe_tejas_cream","#d1cbbb")
	var blue := _mat("cafe_tejas_blue","#35657c")
	var dark := _mat("cafe_tejas_dark","#35443f")
	var green := _mat("cafe_tejas_green","#61766a")
	var stone := _mat("cafe_tejas_stone","#b7b3a0")
	var ground := h*.46
	var depth := 2.0
	var faces: Array = [face]
	var first_normal: Vector3 = face.normal
	var best_score := INF
	var second: Dictionary = {}
	for other in city._street_facing_walls(poly):
		var normal: Vector3 = other.normal
		if absf(normal.dot(first_normal))>.65: continue
		var score: float = float(other.score)
		if score<best_score:
			best_score = score
			second = other
	if not second.is_empty(): faces.append(second)
	# Clip both sides before extruding the solid lower floor, keeping the
	# original mapped footprint for the upper storey and roof.
	var lower := poly
	var recessed: Array = []
	for wall in faces:
		var cut: PackedVector2Array = city._arcade_cut(lower,wall,depth)
		if cut.size()>=3 and not Geometry2D.triangulate_polygon(cut).is_empty():
			lower = cut
			recessed.append(wall)
	if not recessed.is_empty():
		city._extrude(lower,0.0,ground,blue,tile)
	if not city._extrude(poly,ground if not recessed.is_empty() else 0.0,h,cream,tile): return false
	var columns: Array[Vector3] = []
	for wall in faces:
		var a: Vector3 = wall.a
		var b: Vector3 = wall.b
		var n: Vector3 = wall.normal
		var tangent := (b-a).normalized()
		var width := a.distance_to(b)
		var mid := (a+b)*.5
		var bay_count := clampi(roundi(width/3.7),2,12)
		var bay := width/float(bay_count)
		var open_portal := wall in recessed
		# Deep blue fascia, pale stone balcony and roof cornice.
		_box(mid+n*.07+Vector3.UP*(ground-.25),n,width,.58,.24,blue)
		_box(mid+n*.16+Vector3.UP*(ground+.08),n,width,.20,.40,stone)
		_box(mid+n*.12+Vector3.UP*(h-.17),n,width,.28,.32,stone)
		_box(mid+n*.09+Vector3.UP*(h-.44),n,width,.12,.20,cream)
		for i in range(bay_count):
			var p := a+tangent*(float(i)+.5)*bay
			var back := p-n*(depth-.07) if open_portal else p+n*.06
			if city._wall_has_opening(lower,back,n):
				_box(back+Vector3.UP*(ground*.48),n,bay*.77,ground*.77,.09,dark)
				_box(back+n*.08+Vector3.UP*(ground*.48),n,.11,ground*.77,.14,green)
			var sill := ground+.85
			var arch_height := h-sill-.60
			_arch(p+Vector3.UP*sill,n,tangent,minf(1.58,bay*.68),arch_height,green,dark)
			_box(p+n*.105+Vector3.UP*(sill+arch_height*.40),n,.065,arch_height*.74,.08,green)
			_box(p+n*.11+Vector3.UP*(sill-.07),n,minf(1.85,bay*.80),.12,.20,stone)
		for i in range(bay_count+1):
			var p := a+tangent*clampf(float(i)*bay,.26,width-.26)-n*.22
			var duplicate := false
			for old in columns:
				if old.distance_to(p)<.72: duplicate = true
			if duplicate or not _safe_front(p): continue
			columns.append(p)
			_box(p+Vector3.UP*(ground*.5),n,.40,ground,.40,blue,open_portal)
			_box(p+Vector3.UP*.23,n,.57,.46,.57,stone)
			_box(p+Vector3.UP*(ground-.16),n,.57,.28,.57,blue)
		# Continuous balustrade across the visible upper façades.
		_box(mid+n*.22+Vector3.UP*(ground+.66),n,width,.13,.26,stone)
		var railing_count := clampi(roundi(width/.39),3,100)
		for i in range(railing_count):
			var p := a+tangent*(float(i)+.5)*width/float(railing_count)+n*.22
			_box(p+Vector3.UP*(ground+.37),n,.12,.48,.16,stone)
		var sign_at := mid+n*.22+Vector3.UP*(ground-.28)
		_box(sign_at,n,minf(width*.65,8.0),.43,.12,blue)
		_sign("Esquina de Tejas",sign_at+n*.075,n,minf(width*.60,7.7),Color("#f1dfc6"))
	return true

func build(fp: Dictionary,tile: Vector2i) -> bool:
	var key := String(selected.get(String(fp.id),""))
	if key.is_empty(): return false
	var poly: PackedVector2Array = fp.poly
	var face := _front(fp,key)
	if face.is_empty() or Geometry2D.triangulate_polygon(poly).is_empty(): return false
	var tags: Dictionary = fp.tags
	var h := 7.8
	var material := _mat("church_white","#ddd9c9")
	match key:
		"abel":
			h = 10.0
			material = _mat("abel_blue","#538b9b")
		"cristina":
			h = 6.5
			material = _mat("station_cream","#e0d8bc")
		"dependiente":
			h = 7.4
			material = _mat("hospital_stone","#d3cdbd")
		"cafe_tejas":
			h = 8.1
			material = _mat("cafe_tejas_cream","#d1cbbb")
		"tejas":
			h = 22.0*3.1
			var levels := String(tags.get("building:levels",""))
			if levels.is_valid_float() and float(levels)>=12.0: h = float(levels)*3.1
			material = _mat("tejas_concrete","#c6c5b9")
	var raw := String(tags.get("height","")).trim_suffix("m").strip_edges()
	if raw.is_valid_float() and key=="tejas" and float(raw)>35.0: h = clampf(float(raw),35.0,85.0)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if key=="cafe_tejas":
		if not _tejas_cafe(fp,face,tile,h): return false
	else:
		if not _standard_landmark(fp,face,tile,h,material,key): return false
	var name_value := String(NAMES[key])
	if key=="tejas": name_value = String(tags.get("name","Torre de Tejas"))
	var mid: Vector3 = face.mid
	var n: Vector3 = face.normal
	var at := mid+n*.85
	city.editable_buildings[String(fp.id)] = {"poly":poly,"center":fp.center,"height":h,"name":name_value,"protected":true,"front":face,"height_source":"photo_estimate" if key=="cafe_tejas" else "landmark"}
	city.real_facade_sites.append({"name":name_value,"p":at})
	for place in city.geographic_by_building.get(String(fp.id),[]): city._geo_mark(place,at)
	if key=="dependiente": city.incident_services["hospital"] = at
	print("Fachada real: ",name_value," · OSM ",fp.id)
	return true

func _standard_landmark(fp: Dictionary,face: Dictionary,tile: Vector2i,h: float,material: StandardMaterial3D,key: String) -> bool:
	var poly: PackedVector2Array = fp.poly
	var lower := poly
	var recess := false
	if key=="cristina" or key=="abel":
		var clipped: PackedVector2Array = city._clip_inward(poly,face,1.8 if key=="cristina" else 1.65)
		if clipped.size()>=3 and not Geometry2D.triangulate_polygon(clipped).is_empty():
			lower = clipped
			recess = true
	var portal_height := 3.3 if key=="abel" else 4.65
	if recess: city._extrude(lower,0.0,portal_height,material,tile)
	if not city._extrude(poly,portal_height if recess else 0.0,h,material,tile): return false
	match key:
		"pilar": _church(fp,face,tile,h)
		"abel": _clinic(face,h,recess)
		"cristina": _station(face,h,recess)
		"dependiente":
			_hospital(face,h)
			_roof(poly,fp.center,h,1.35,tile,_mat("hospital_tile","#90725c"))
		"tejas": _tower(fp,h)
	return true
