extends Node3D
# OSM parks are reserved before procedural building infill. The original
# cartography and user's saved map edits are never changed.
const MAX_PARKS := 48
const MAX_TREES := 32
var world
var areas: Array = []
var sites: Array = []
var walkways: Array = []
var index: Dictionary = {}
const PONTON_ID := "23918119"
var ponton_boundary := PackedVector2Array()
var leaf_mesh := SphereMesh.new()
var leaf_mat: StandardMaterial3D

static func area(poly: PackedVector2Array) -> float:
	var result := 0.0
	for i in range(poly.size()):
		result += poly[i].cross(poly[(i+1)%poly.size()])
	return absf(result)*.5

func reserve(city) -> void:
	world = city
	# Reserve the named sports centre before the generic park limit.
	for source in city.geography.park_areas:
		if String(source.id)==PONTON_ID:
			ponton_boundary = source.poly
			break
	if ponton_boundary.is_empty(): ponton_boundary = _ponton_from_streets()
	if not ponton_boundary.is_empty():
		areas.append({"id":PONTON_ID,"name":"El Pontón","poly":ponton_boundary,"ponton":true})
		city.street_geometry._register(index,ponton_boundary)
	else:
		push_warning("MyCity El Pontón: no verified local boundary; neighbouring buildings preserved.")
	for source in city.geography.park_areas:
		if String(source.id)==PONTON_ID: continue
		var poly: PackedVector2Array = source.poly
		if area(poly)<35.0 or area(poly)>85000.0: continue
		if city._stadium_reserved(poly): continue
		if not city.market_reservation.is_empty() and not Geometry2D.intersect_polygons(poly,city.market_reservation).is_empty(): continue
		areas.append(source)
		city.street_geometry._register(index,poly)
		if areas.size()>=MAX_PARKS: break
	_identify_alcobenda()
	_identify_dump()
	for id in ["373927999","23917140"]:
		var found := false
		for item in areas:
			if String(item.id)==id: found = true
		if not found: push_warning("MyCity parques: falta polígono OSM "+id+" en el mapa local; no se inventa perímetro.")

# The user identified the park by Monte / Estévez. Match its existing
# polygon rather than guessing a new parcel or deleting adjacent houses.
func _ponton_from_streets() -> PackedVector2Array:
	# Older local exports may omit the sports centre way. Only reconstruct
	# a block when four mapped intersections actually enclose the OSM pin.
	var anchor: Vector3 = world.geography.project(23.12511,-82.36973)
	var north: Vector3 = world._market_corner("oquendo","santo tomas",anchor)
	var east: Vector3 = world._market_corner("nueva","santo tomas",anchor)
	for south_name in ["arroyo","manglar"]:
		var se: Vector3 = world._market_corner("nueva",String(south_name),anchor)
		var sw: Vector3 = world._market_corner("oquendo",String(south_name),anchor)
		if not north.is_finite() or not east.is_finite() or not se.is_finite() or not sw.is_finite(): continue
		var poly := PackedVector2Array([Vector2(north.x,north.z),Vector2(east.x,east.z),Vector2(se.x,se.z),Vector2(sw.x,sw.z)])
		if area(poly)<2500.0 or area(poly)>45000.0 or Geometry2D.triangulate_polygon(poly).is_empty(): continue
		if not Geometry2D.is_point_in_polygon(Vector2(anchor.x,anchor.z),poly): continue
		for inset in Geometry2D.offset_polygon(poly,-6.0):
			if Geometry2D.is_point_in_polygon(Vector2(anchor.x,anchor.z),inset):
				print("MyCity El Pontón: block inferred from verified local street intersections.")
				return inset
	return PackedVector2Array()

func _identify_alcobenda() -> void:
	for item in areas:
		if world.geography.normalized(String(item.name)).contains("alcobenda"):
			item.name = "Parque Alcobenda"
			item["neglected"] = true
			return
	var anchor: Vector3 = world.texture_anchor
	var corner: Vector3 = world._market_corner("monte","estevez",anchor)
	if not corner.is_finite(): return
	var q := Vector2(corner.x,corner.z)
	var best := 55.0
	var chosen: Dictionary = {}
	for item in areas:
		var label: String = world.geography.normalized(String(item.name))
		if label not in ["parque publico","parque",""]: continue
		var poly: PackedVector2Array = item.poly
		var distance := INF
		for i in range(poly.size()):
			var edge_point := Geometry2D.get_closest_point_to_segment(q,poly[i],poly[(i+1)%poly.size()])
			distance = minf(distance,q.distance_to(edge_point))
		if Geometry2D.is_point_in_polygon(q,poly): distance = 0.0
		if distance<best:
			best = distance
			chosen = item
	if chosen.is_empty():
		push_warning("Alcobenda: no se encontró un parque público sin nombre cerca de Monte y Estévez.")
		return
	chosen.name = "Parque Alcobenda"
	chosen["neglected"] = true
	print("Alcobenda: parcela OSM ",chosen.id," identificada por Monte y Estévez.")

# Exact location supplied by the player in the editor.
func _identify_dump() -> void:
	var pin: Vector3 = world.geography.project(23.1221716,-82.3671415)
	var point := Vector2(pin.x,pin.z)
	var matches: Array = []
	for item in areas:
		if Geometry2D.is_point_in_polygon(point,item.poly): matches.append(item)
	if matches.size()!=1:
		push_warning("Parque vertedero: GPS sin perímetro único; no se modifican parcelas vecinas.")
		return
	var chosen: Dictionary = matches[0]
	chosen["neglected"] = true
	chosen["dump"] = true
	print("Parque vertedero: OSM ",chosen.id," identificado por GPS.")

static func normal_style(id: String) -> bool:
	return id in ["373927999","23917140"]

func reserved(poly: PackedVector2Array) -> bool:
	for park in world.street_geometry.near(index,poly):
		if not Geometry2D.intersect_polygons(poly,park).is_empty(): return true
	return false

# Remove clearly misplaced generic solids only, not named real buildings,
# manually edited buildings or structures straddling a park boundary.
func suppress_building(fp: Dictionary) -> bool:
	var tags: Dictionary = fp.tags
	if world.map_edits.has(String(fp.id)) or tags.has("name") or tags.has("amenity") or tags.has("shop") or tags.has("historic"): return false
	if String(tags.get("building","")) not in ["yes","residential","house","apartments",""]: return false
	var poly: PackedVector2Array = fp.poly
	var original := area(poly)
	if original<.1: return false
	for park in world.street_geometry.near(index,poly):
		# The sports complex includes real auxiliary buildings and a neighbouring school.
		if park==ponton_boundary: continue
		var overlap := 0.0
		for piece in Geometry2D.intersect_polygons(poly,park): overlap += area(piece)
		if overlap/original>=.90: return true
	return false

func _mat(key: String,color: Color) -> StandardMaterial3D:
	return world._mat("park_"+key,color)

func _v(p: Vector2,y: float = 0.0) -> Vector3:
	return Vector3(p.x,y,p.y)

func _free(p: Vector2,poly: PackedVector2Array,margin: float = .5) -> bool:
	for dx in [-margin,margin]:
		for dz in [-margin,margin]:
			var q := p+Vector2(float(dx),float(dz))
			if not Geometry2D.is_point_in_polygon(q,poly): return false
			if world.street_geometry.point_on_road(_v(q)): return false
	for fp in world.geography.footprints_near(_v(p),margin+2.0):
		if suppress_building(fp): continue
		var shape := PackedVector2Array([p+Vector2(-margin,-margin),p+Vector2(margin,-margin),p+Vector2(margin,margin),p+Vector2(-margin,margin)])
		if not Geometry2D.intersect_polygons(shape,fp.poly).is_empty(): return false
	return true

func _clear_segment(a: Vector2,b: Vector2,poly: PackedVector2Array) -> bool:
	var count := maxi(1,ceili(a.distance_to(b)/1.1))
	for i in range(count+1):
		if not _free(a.lerp(b,float(i)/float(count)),poly,.65): return false
	return true

func _hub(poly: PackedVector2Array) -> Vector2:
	var mid: Vector2 = world.street_geometry.bounds(poly).get_center()
	if _free(mid,poly,1.0): return mid
	var tris := Geometry2D.triangulate_polygon(poly)
	var best := Vector2.INF
	var distance := INF
	for i in range(0,tris.size(),3):
		var q := (poly[tris[i]]+poly[tris[i+1]]+poly[tris[i+2]])/3.0
		if q.distance_to(mid)<distance and _free(q,poly,1.0):
			best = q
			distance = q.distance_to(mid)
	return best

func _paint(poly: PackedVector2Array,y: float,mat: StandardMaterial3D,key: String) -> void:
	# Clip each triangle against existing streets and sidewalks; never
	# cover a mapped lane or its collision with greenery.
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in range(0,tris.size(),3):
		var tri := PackedVector2Array([poly[tris[i]],poly[tris[i+1]],poly[tris[i+2]]])
		if Geometry2D.is_polygon_clockwise(tri): tri.reverse()
		for part in world.street_geometry.subtract(tri,world.street_geometry.protected_index):
			world._draw_street_polygon(part,y,mat,key)

func _path(a: Vector2,b: Vector2,poly: PackedVector2Array,mat: StandardMaterial3D) -> void:
	var direction := (b-a).normalized()
	var side := Vector2(-direction.y,direction.x)*1.05
	var strip := PackedVector2Array([a-side,b-side,b+side,a+side])
	for piece in Geometry2D.intersect_polygons(strip,poly): _paint(piece,.064,mat,"park_path")
	walkways.append({"a":_v(a,.065),"b":_v(b,.065)})

func _tree(p: Vector2,rng: RandomNumberGenerator,transforms: Array[Transform3D],colors: Array[Color]) -> void:
	var h := rng.randf_range(3.0,5.2)
	var radius := rng.randf_range(1.25,2.25)
	world._cube(_v(p,h*.5),Vector3(.26,h,.26),_mat("trunk",Color("#685441")),rng.randf_range(0.0,TAU),true)
	for j in range(2):
		var at := _v(p,h+float(j)*.65)+Vector3(rng.randf_range(-.45,.45),0,rng.randf_range(-.45,.45))
		var dims := Vector3(radius*1.9,radius*1.25,radius*1.8)*(1.0 if j==0 else .78)
		transforms.append(Transform3D(Basis(Vector3.UP,rng.randf_range(0.0,TAU)).scaled_local(dims),at))
		colors.append(Color("#41683b").lerp(Color("#81904b"),rng.randf()))

func _bench(p: Vector2,heading: Vector2) -> void:
	var angle := atan2(heading.x,heading.y)
	var basis := Basis(Vector3.UP,angle)
	var at := _v(p,.055)
	var metal := _mat("iron",Color("#424b45"))
	var wood := _mat("bench",Color("#8d8064"))
	world._local_cube(at,basis,Vector3(0,.46,0),Vector3(1.65,.10,.46),wood,true)
	world._local_cube(at,basis,Vector3(0,.77,-.20),Vector3(1.65,.35,.08),wood)
	for x in [-.65,.65]:
		world._local_cube(at,basis,Vector3(float(x),.22,0),Vector3(.12,.44,.44),metal)
		world._local_cube(at,basis,Vector3(float(x),.70,-.20),Vector3(.09,.55,.09),metal)

# La Normal: a continuous blue concrete base, pale slab and black
# steel backrest. Straight and curved units share the same geometry.
func _normal_segment(a: Vector2,b: Vector2,inward: Vector2) -> void:
	var length := a.distance_to(b)
	var mid := (a+b)*.5
	var angle := atan2(inward.x,inward.y)
	var frame := Basis(Vector3.UP,angle)
	var at := _v(mid,.055)
	var blue := _mat("normal_blue",Color("#287eae"))
	var seat := _mat("normal_seat",Color("#bcbab0"))
	var iron := _mat("normal_iron",Color("#252b2a"))
	world._local_cube(at,frame,Vector3(0,.20,0),Vector3(length+.025,.40,.57),blue,true)
	world._local_cube(at,frame,Vector3(0,.43,0),Vector3(length+.03,.09,.62),seat)
	for y in [.69,.96]:
		world._local_cube(at,frame,Vector3(0,float(y),-.27),Vector3(length+.04,.045,.035),iron)
	for x in [-.34,.34]:
		world._local_cube(at,frame,Vector3(length*float(x),.73,-.27),Vector3(.035,.66,.045),iron)

func _normal_bench(points: PackedVector2Array,heading: Vector2,poly: PackedVector2Array,routes: Array,occupied: Array[Vector2]) -> bool:
	# Validate the whole unit before creating any collision shapes.
	for i in range(points.size()-1):
		var a := points[i]
		var b := points[i+1]
		for fraction in [0.0,.5,1.0]:
			var p := a.lerp(b,float(fraction))
			if not _free(p,poly,.65): return false
			for route in routes:
				if Geometry2D.get_closest_point_to_segment(p,route.a,route.b).distance_to(p)<1.6: return false
			for old in occupied:
				if old.distance_to(p)<1.1: return false
	for i in range(points.size()-1):
		var a := points[i]
		var b := points[i+1]
		var axis := (b-a).normalized()
		var inward := Vector2(-axis.y,axis.x)
		if inward.dot(heading)<0.0: inward = -inward
		_normal_segment(a,b,inward)
		occupied.append((a+b)*.5)
	return true

func _normal_straight(p: Vector2,heading: Vector2,poly: PackedVector2Array,routes: Array,occupied: Array[Vector2]) -> bool:
	var side := Vector2(-heading.y,heading.x)
	return _normal_bench(PackedVector2Array([p-side*1.8,p-side*.6,p+side*.6,p+side*1.8]),heading,poly,routes,occupied)

func _normal_curve(p: Vector2,heading: Vector2,poly: PackedVector2Array,routes: Array,occupied: Array[Vector2]) -> bool:
	var side := Vector2(-heading.y,heading.x)
	var points := PackedVector2Array()
	# A shallow semicircular bench facing the adjacent clearing.
	for i in range(9):
		var angle := lerpf(-1.10,1.10,float(i)/8.0)
		points.append(p+side*sin(angle)*2.5+heading*(1.0-cos(angle))*2.5)
	return _normal_bench(points,heading,poly,routes,occupied)

func _normal_ground(poly: PackedVector2Array,hub: Vector2,rng: RandomNumberGenerator) -> void:
	# Irregular grass islands in a broad, pale worn clearing, as in the
	# supplied aerial photograph. This is an approximation, not a survey.
	var lawn := _mat("normal_grass",Color("#78894d"))
	var rect: Rect2 = world.street_geometry.bounds(poly)
	for i in range(clampi(roundi(area(poly)/95.0),4,18)):
		var p := Vector2(rng.randf_range(rect.position.x,rect.end.x),rng.randf_range(rect.position.y,rect.end.y))
		if not _free(p,poly,1.0) or p.distance_to(hub)<3.0: continue
		var radius := rng.randf_range(2.4,5.8)
		var patch := PackedVector2Array()
		for j in range(9):
			var angle := TAU*float(j)/9.0
			patch.append(p+Vector2(cos(angle),sin(angle))*radius*rng.randf_range(.70,1.1))
		for part in Geometry2D.intersect_polygons(patch,poly): _paint(part,.052,lawn,"park_normal_grass")

func _lamp(p: Vector2) -> void:
	var metal := _mat("iron",Color("#424b45"))
	world._cube(_v(p,1.65),Vector3(.12,3.30,.12),metal,0.0,true)
	world._cube(_v(p,3.40),Vector3(.28,.35,.28),_mat("lamp",Color("#e2dcb7")))
	world._cube(_v(p,3.62),Vector3(.38,.12,.38),metal)

# Three reused mesh batches for debris: bags, broken masonry and scrap.
# No rigid bodies, lights, or per-frame simulation.
func _debris(poly: PackedVector2Array,routes: Array,hub: Vector2,rng: RandomNumberGenerator,dump: bool = false) -> void:
	var rect: Rect2 = world.street_geometry.bounds(poly)
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	var bag := SphereMesh.new()
	bag.radius = .5
	bag.height = 1.0
	bag.radial_segments = 6
	bag.rings = 3
	var block := BoxMesh.new()
	block.size = Vector3.ONE
	var palette := [Color("#252923"),Color("#43473c"),Color("#737364"),Color("#8b8270"),Color("#b4ac94"),Color("#755741"),Color("#52666a")]
	var centers: Array[Vector2] = []
	for attempt in range(800 if dump else 80):
		var point := Vector2(rng.randf_range(rect.position.x,rect.end.x),rng.randf_range(rect.position.y,rect.end.y))
		if not _free(point,poly,.75 if dump else 1.25) or (not dump and point.distance_to(hub)<2.0): continue
		var clear := true
		for route in routes:
			if Geometry2D.get_closest_point_to_segment(point,route.a,route.b).distance_to(point)<2.1: clear = false
		for old in centers:
			if old.distance_to(point)<(1.55 if dump else 3.0): clear = false
		if clear: centers.append(point)
		if centers.size()>= (clampi(roundi(area(poly)/3.5),12,110) if dump else clampi(roundi(area(poly)/22.0),5,24)): break
	for kind in range(3):
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		for pile in centers:
			for j in range((15 if kind==0 else (10 if kind==1 else 15)) if dump else (9 if kind==0 else (8 if kind==1 else 12))):
				var point := pile+Vector2(rng.randf_range(-1.1,1.1),rng.randf_range(-1.1,1.1))
				if not _free(point,poly,.55): continue
				var clear := true
				for route in routes:
					if Geometry2D.get_closest_point_to_segment(point,route.a,route.b).distance_to(point)<1.45: clear = false
				if not clear: continue
				var dims := Vector3(rng.randf_range(.28,.65),rng.randf_range(.20,.48),rng.randf_range(.25,.58))
				if kind==1: dims = Vector3(rng.randf_range(.32,.85),rng.randf_range(.15,.38),rng.randf_range(.20,.52))
				if kind==2: dims = Vector3(rng.randf_range(.12,.48),.035,rng.randf_range(.14,.55))
				if dump and kind!=2: dims *= rng.randf_range(1.0,1.40)
				var at := _v(point,.055+dims.y*.5)
				if kind!=2 and j%4==0: at.y += (.38 if dump else .12)
				if dump and kind!=2 and j%5==0: at.y += .28
				var tilt := rng.randf_range(-.22,.22) if kind==1 else 0.0
				var rotation := Basis.from_euler(Vector3(tilt,rng.randf_range(0.0,TAU),tilt*.5))
				transforms.append(Transform3D(rotation.scaled_local(dims),at))
				colors.append(palette[rng.randi_range(0,1)] if kind==0 else palette[rng.randi_range(2,6)])
		if transforms.is_empty(): continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = bag if kind==0 else block
		batch.instance_count = transforms.size()
		for i in range(transforms.size()):
			batch.set_instance_transform(i,transforms[i])
			batch.set_instance_color(i,colors[i])
		var visual := MultiMeshInstance3D.new()
		visual.multimesh = batch
		visual.material_override = material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 85.0
		add_child(visual)

# El Pontón: worn neighbourhood baseball grounds and concrete sports
# courts, based on the aerial references, not a modern spectator stadium.
# Everything is static and clipped to mapped ground; no per-frame work.
func _ponton_circle(center: Vector2,radius: float,poly: PackedVector2Array,mat: StandardMaterial3D,key: String,y: float) -> void:
	var patch := PackedVector2Array()
	for i in range(16):
		var angle := TAU*float(i)/16.0
		patch.append(center+Vector2(cos(angle),sin(angle))*radius)
	for part in Geometry2D.intersect_polygons(patch,poly): _paint(part,y,mat,key)

func _ponton_strip(a: Vector2,b: Vector2,width: float,poly: PackedVector2Array,mat: StandardMaterial3D,key: String,y: float) -> void:
	if a.distance_to(b)<.05: return
	var axis := (b-a).normalized()
	var side := Vector2(-axis.y,axis.x)*width*.5
	var strip := PackedVector2Array([a-side,b-side,b+side,a+side])
	for part in Geometry2D.intersect_polygons(strip,poly): _paint(part,y,mat,key)

func _ponton_open_rect(center: Vector2,axis: Vector2,hx: float,hz: float,poly: PackedVector2Array) -> bool:
	var side := Vector2(-axis.y,axis.x)
	# Check corners, edges and interior against the actual mapped buildings
	# and streets before drawing a sports feature.
	for x in range(-2,3):
		for z in range(-2,3):
			if not _free(center+side*hx*float(x)*.5+axis*hz*float(z)*.5,poly,.75): return false
	return true

func _ponton_diamond(anchor: Vector2,poly: PackedVector2Array,occupied: Array[Vector2],forward: Vector2) -> bool:
	var dirt := _mat("ponton_infield",Color("#ad8c60"))
	var chalk := _mat("ponton_chalk",Color("#c6bba0"))
	var base_mat := _mat("ponton_bases",Color("#ded4bd"))
	var side := Vector2(-forward.y,forward.x)
	for scale_value in [18.0,15.0,12.0,9.0]:
		var distance := float(scale_value)
		for shift in [Vector2.ZERO,Vector2(-6,0),Vector2(6,0),Vector2(0,-6),Vector2(0,6),Vector2(-12,0),Vector2(12,0),Vector2(0,-12),Vector2(0,12)]:
			var center: Vector2 = anchor+shift
			var separated := true
			for old in occupied:
				if old.distance_to(center)<distance*1.55+8.0: separated = false
			if not separated: continue
			var half := distance/sqrt(2.0)
			if not _ponton_open_rect(center,forward,half+2.0,half+2.0,poly): continue
			var home := center-forward*half
			var first := center+side*half
			var second := center+forward*half
			var third := center-side*half
			for base in [home,first,second,third]:
				_ponton_circle(base,1.65,poly,dirt,"ponton_infield",.064)
				world._cube(_v(base,.085),Vector3(.38,.025,.38),base_mat,atan2(forward.x,forward.y)+PI*.25)
			for pair in [[home,first],[first,second],[second,third],[third,home]]:
				_ponton_strip(pair[0],pair[1],.85,poly,dirt,"ponton_infield",.064)
			_ponton_circle(center,2.0,poly,dirt,"ponton_infield",.064)
			world._cube(_v(center,.087),Vector3(.58,.025,.15),base_mat,atan2(forward.x,forward.y))
			for base in [first,third]:
				var direction: Vector2 = (base-home).normalized()
				var end := base
				for metre in range(1,35):
					var q: Vector2 = base+direction*float(metre)
					if not _free(q,poly,.55): break
					end = q
				_ponton_strip(home,end,.075,poly,chalk,"ponton_chalk",.074)
			occupied.append(center)
			return true
	return false

func _ponton_court(anchor: Vector2,poly: PackedVector2Array,occupied: Array[Vector2]) -> bool:
	var axis := Vector2(0,-1)
	var side := Vector2(-axis.y,axis.x)
	var concrete := _mat("ponton_court",Color("#a4a397"))
	var chalk := _mat("ponton_court_lines",Color("#cbc4ae"))
	for dims in [Vector2(8,14),Vector2(6,10),Vector2(4,7)]:
		for shift in [Vector2.ZERO,Vector2(0,-8),Vector2(0,8),Vector2(-8,0),Vector2(8,0)]:
			var center := anchor+shift
			var safe := true
			for old in occupied:
				if old.distance_to(center)<maxf(dims.x,dims.y)+18.0: safe = false
			if not safe or not _ponton_open_rect(center,axis,dims.x,dims.y,poly): continue
			var a: Vector2 = center-side*dims.x-axis*dims.y
			var b: Vector2 = center+side*dims.x-axis*dims.y
			var c: Vector2 = center+side*dims.x+axis*dims.y
			var d: Vector2 = center-side*dims.x+axis*dims.y
			_paint(PackedVector2Array([a,b,c,d]),.062,concrete,"ponton_court")
			for pair in [[a,b],[b,c],[c,d],[d,a],[center-side*dims.x,center+side*dims.x]]:
				_ponton_strip(pair[0],pair[1],.075,poly,chalk,"ponton_court_lines",.072)
			occupied.append(center)
			return true
	return false

func _build_ponton(item: Dictionary) -> void:
	var poly: PackedVector2Array = item.poly
	var rect: Rect2 = world.street_geometry.bounds(poly)
	var grass := _mat("ponton_grass",Color("#69794e"))
	var worn := _mat("ponton_worn",Color("#93856a"))
	var dark_grass := _mat("ponton_grass_dark",Color("#576d47"))
	_paint(poly,.048,grass,"ponton_grass")
	var rng := RandomNumberGenerator.new()
	rng.seed = 23918119
	# Sparse irregular worn patches, not perfectly manicured grass.
	for i in range(24):
		var p := rect.position+Vector2(rng.randf(),rng.randf())*rect.size
		if not _free(p,poly,1.4): continue
		_ponton_circle(p,rng.randf_range(1.8,4.2),poly,dark_grass if i%3==0 else worn,"ponton_dark" if i%3==0 else "ponton_worn",.055)
	var occupied: Array[Vector2] = []
	var field_count := 0
	# Aerial reference: two worn diamonds across the western/central
	# clearing and rectangular paved sports areas towards the east.
	for fraction in [Vector2(.40,.66),Vector2(.38,.29)]:
		var anchor: Vector2 = rect.position+fraction*rect.size
		if _ponton_diamond(anchor,poly,occupied,Vector2(.86,-.51).normalized()): field_count += 1
	var court_count := 0
	for fraction in [Vector2(.78,.66),Vector2(.78,.37)]:
		if _ponton_court(rect.position+fraction*rect.size,poly,occupied): court_count += 1
	# Choose a real road-facing access near Clavel where available.
	var gps := _hub(poly)
	var best := INF
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[(i+1)%poly.size()]
		var mid := (a+b)*.5
		var inward := (rect.get_center()-mid).normalized()
		for offset in [2.0,4.0,6.0]:
			var entry := mid+inward*float(offset)
			if not _free(entry,poly,.8): continue
			for edge in world.geography.roads_near(_v(entry),25.0):
				if not bool(edge.driveable): continue
				var nearest := Geometry3D.get_closest_point_to_segment(_v(entry),edge.a,edge.b)
				var score := nearest.distance_to(_v(entry))
				if world._market_named(edge,"clavel"): score -= 30.0
				if score<best:
					best = score
					gps = entry
			break
	if gps.is_finite(): sites.append({"name":"El Pontón","p":_v(gps,.065),"id":PONTON_ID})
	print("MyCity El Pontón: ",field_count," diamonds, ",court_count," courts; mapped buildings preserved.")

func build() -> void:
	var lawn := _mat("lawn",Color("#687d49"))
	var paving := _mat("path",Color("#b6ad97"))
	var bare := _mat("bare_dirt",Color("#81765f"))
	var damaged := _mat("damaged_path",Color("#8d887a"))
	leaf_mesh.radial_segments = 8
	leaf_mesh.rings = 4
	leaf_mesh.radius = .5
	leaf_mesh.height = 1.0
	leaf_mat = StandardMaterial3D.new()
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.roughness = 1.0
	for item in areas:
		var poly: PackedVector2Array = item.poly
		if bool(item.get("ponton",false)):
			_build_ponton(item)
			continue
		var hub := _hub(poly)
		var neglected := bool(item.get("neglected",false))
		var dump := bool(item.get("dump",false))
		var normal := normal_style(String(item.id)) and not neglected
		var ground := _mat("dump_ground",Color("#655e4e")) if dump else (bare if neglected else (paving if normal else lawn))
		_paint(poly,.048,ground,"park_dump" if dump else ("park_bare" if neglected else "park_grass"))
		if not hub.is_finite(): continue
		var rng := RandomNumberGenerator.new()
		rng.seed = String(item.id).hash()
		if dump:
			# No tidy paths or usable seating through a completely filled dump.
			_debris(poly,[],hub,rng,true)
			sites.append({"name":item.name,"p":_v(hub,.065),"id":item.id})
			continue
		if normal: _normal_ground(poly,hub,rng)
		var routes: Array = []
		var entries: Array[Vector2] = []
		for i in range(poly.size()):
			var a := poly[i]
			var b := poly[(i+1)%poly.size()]
			if a.distance_to(b)<6.0: continue
			var mid := (a+b)*.5
			var direction := (hub-mid).normalized()
			for offset in [1.5,3.0,5.0,7.0]:
				var entry := mid+direction*float(offset)
				if not _clear_segment(hub,entry,poly): continue
				var separated := true
				for old in entries:
					if old.distance_to(entry)<8.0: separated = false
				if separated:
					entries.append(entry)
					routes.append({"a":hub,"b":entry})
					_path(hub,entry,poly,damaged if neglected else paving)
				break
			if entries.size()>=6: break
		var gps := hub
		if not entries.is_empty():
			gps = entries[0]
			var best := INF
			for entry in entries:
				for edge in world.geography.roads_near(_v(entry),25.0):
					if not bool(edge.driveable): continue
					var d: float = Geometry3D.get_closest_point_to_segment(_v(entry),edge.a,edge.b).distance_to(_v(entry))
					if d<best:
						best = d
						gps = entry
		sites.append({"name":item.name,"p":_v(gps,.065),"id":item.id})
		# Seats beside paths; avoid making the pedestrian routes narrower.
		var seats := 0
		var occupied: Array[Vector2] = []
		for route in routes:
			var direction: Vector2 = (route.b-route.a).normalized()
			var side := Vector2(-direction.y,direction.x)
			for sign_value in [-1.0,1.0]:
				var point: Vector2 = route.a.lerp(route.b,.58)+side*2.0*float(sign_value)
				if _free(point,poly,1.1) and seats<(1 if neglected else 8):
					var heading := -side*float(sign_value)
					if normal:
						var placed := false
						if seats%2==1:
							placed = _normal_curve(point,heading,poly,routes,occupied)
						if not placed: placed = _normal_straight(point,heading,poly,routes,occupied)
						if placed: seats += 1
					else:
						_bench(point,heading)
						seats += 1
			var lamp_at: Vector2 = route.a.lerp(route.b,.82)+side*1.7
			if not neglected and _free(lamp_at,poly,.65): _lamp(lamp_at)
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		var planted: Array[Vector2] = []
		var rect: Rect2 = world.street_geometry.bounds(poly)
		var target := clampi(roundi(area(poly)/(240.0 if neglected else (85.0 if normal else 110.0))),2,MAX_TREES)
		for i in range(target*8):
			if planted.size()>=target: break
			var point := Vector2(rng.randf_range(rect.position.x,rect.end.x),rng.randf_range(rect.position.y,rect.end.y))
			if not _free(point,poly,1.65) or point.distance_to(hub)<3.0: continue
			var safe := true
			for route in routes:
				if Geometry2D.get_closest_point_to_segment(point,route.a,route.b).distance_to(point)<2.7: safe = false
			for old in planted:
				if old.distance_to(point)<4.0: safe = false
			for seat_point in occupied:
				if seat_point.distance_to(point)<1.35: safe = false
			if not safe: continue
			planted.append(point)
			_tree(point,rng,transforms,colors)
		if not transforms.is_empty():
			var multi := MultiMesh.new()
			multi.transform_format = MultiMesh.TRANSFORM_3D
			multi.use_colors = true
			multi.mesh = leaf_mesh
			multi.instance_count = transforms.size()
			for i in range(transforms.size()):
				multi.set_instance_transform(i,transforms[i])
				multi.set_instance_color(i,colors[i])
			var visual := MultiMeshInstance3D.new()
			visual.multimesh = multi
			visual.material_override = leaf_mat
			visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			visual.visibility_range_end = 220.0
			add_child(visual)
		if neglected: _debris(poly,routes,hub,rng)
		# Names remain in the GPS. No floating world-space park labels.
	print("MyCity: ",sites.size()," parques públicos del OSM local, ",walkways.size()," caminos peatonales.")
