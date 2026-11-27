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
var leaf_mesh := SphereMesh.new()
var leaf_mat: StandardMaterial3D

static func area(poly: PackedVector2Array) -> float:
	var result := 0.0
	for i in range(poly.size()):
		result += poly[i].cross(poly[(i+1)%poly.size()])
	return absf(result)*.5

func reserve(city) -> void:
	world = city
	for source in city.geography.park_areas:
		var poly: PackedVector2Array = source.poly
		if area(poly)<35.0 or area(poly)>85000.0: continue
		if city._stadium_reserved(poly): continue
		if not city.market_reservation.is_empty() and not Geometry2D.intersect_polygons(poly,city.market_reservation).is_empty(): continue
		areas.append(source)
		city.street_geometry._register(index,poly)
		if areas.size()>=MAX_PARKS: break
	for id in ["373927999","23917140"]:
		var found := false
		for item in areas:
			if String(item.id)==id: found = true
		if not found: push_warning("MyCity parques: falta polígono OSM "+id+" en el mapa local; no se inventa perímetro.")

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

func _lamp(p: Vector2) -> void:
	var metal := _mat("iron",Color("#424b45"))
	world._cube(_v(p,1.65),Vector3(.12,3.30,.12),metal,0.0,true)
	world._cube(_v(p,3.40),Vector3(.28,.35,.28),_mat("lamp",Color("#e2dcb7")))
	world._cube(_v(p,3.62),Vector3(.38,.12,.38),metal)

func build() -> void:
	var lawn := _mat("lawn",Color("#687d49"))
	var paving := _mat("path",Color("#b6ad97"))
	leaf_mesh.radial_segments = 8
	leaf_mesh.rings = 4
	leaf_mesh.radius = .5
	leaf_mesh.height = 1.0
	leaf_mat = StandardMaterial3D.new()
	leaf_mat.vertex_color_use_as_albedo = true
	leaf_mat.roughness = 1.0
	for item in areas:
		var poly: PackedVector2Array = item.poly
		var hub := _hub(poly)
		_paint(poly,.048,lawn,"park_grass")
		if not hub.is_finite(): continue
		var rng := RandomNumberGenerator.new()
		rng.seed = String(item.id).hash()
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
					_path(hub,entry,poly,paving)
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
		for route in routes:
			var direction: Vector2 = (route.b-route.a).normalized()
			var side := Vector2(-direction.y,direction.x)
			for sign_value in [-1.0,1.0]:
				var point: Vector2 = route.a.lerp(route.b,.58)+side*2.0*float(sign_value)
				if _free(point,poly,1.1) and seats<8:
					_bench(point,-side*float(sign_value))
					seats += 1
			var lamp_at: Vector2 = route.a.lerp(route.b,.82)+side*1.7
			if _free(lamp_at,poly,.65): _lamp(lamp_at)
		var transforms: Array[Transform3D] = []
		var colors: Array[Color] = []
		var planted: Array[Vector2] = []
		var rect: Rect2 = world.street_geometry.bounds(poly)
		var target := clampi(roundi(area(poly)/110.0),2,MAX_TREES)
		for i in range(target*8):
			if planted.size()>=target: break
			var point := Vector2(rng.randf_range(rect.position.x,rect.end.x),rng.randf_range(rect.position.y,rect.end.y))
			if not _free(point,poly,1.65) or point.distance_to(hub)<3.0: continue
			var safe := true
			for route in routes:
				if Geometry2D.get_closest_point_to_segment(point,route.a,route.b).distance_to(point)<2.7: safe = false
			for old in planted:
				if old.distance_to(point)<4.0: safe = false
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
		var text: Label3D = world._label(String(item.name).to_upper(),_v(gps,2.35),.021,0.0,Color("#f3ecd8"))
		text.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		text.visibility_range_end = 55.0
	print("MyCity: ",sites.size()," parques públicos del OSM local, ",walkways.size()," caminos peatonales.")
