extends Node3D
# El Latino: architectural scale, walkable stadium, no event simulation yet.
# All large surfaces are batched by material; stairs/ramps share one
# static walkable collision mesh. No seat-per-node or real-time lights.
const OUTLINE := [Vector2(-.18,-1.0),Vector2(.18,-1.0),Vector2(.53,-.83),Vector2(.90,-.43),Vector2(1.0,-.12),Vector2(.95,.35),Vector2(.66,.82),Vector2(.35,1.0),Vector2(-.35,1.0),Vector2(-.66,.82),Vector2(-.95,.35),Vector2(-1.0,-.12),Vector2(-.90,-.43),Vector2(-.53,-.83)]
const GATE_EDGES := [0,1,3,5,7,9,11,13]
const ROWS := 24
var gates: Array = []
var ring := PackedVector2Array()
var center := Vector3.ZERO
var stadium_basis := Basis.IDENTITY
var half_x := 84.0
var half_z := 94.0
var surfaces: Dictionary = {}
var floor_faces := PackedVector3Array()
var shell_faces := PackedVector3Array()
var structural_concrete: StandardMaterial3D
var world
var grass: StandardMaterial3D
var dirt: StandardMaterial3D
var blue: StandardMaterial3D
var concrete: StandardMaterial3D
var light_concrete: StandardMaterial3D
var dark: StandardMaterial3D
var roof: StandardMaterial3D
var paint: StandardMaterial3D
var warning_track: StandardMaterial3D

static func make_ring(at: Vector3,rotation: Basis,hx: float,hz: float) -> PackedVector2Array:
	var result := PackedVector2Array()
	for q in OUTLINE:
		var p := at+rotation*Vector3(q.x*hx,0,q.y*hz)
		result.append(Vector2(p.x,p.z))
	return result

func _safe_site(poly: PackedVector2Array,anchor: Vector3) -> bool:
	var boundary: PackedVector2Array = world.geography.stadium_boundary
	if not boundary.is_empty():
		for i in range(poly.size()):
			var a := poly[i]
			var b := poly[(i+1)%poly.size()]
			for t in [0.0,.25,.5,.75]:
				if not Geometry2D.is_point_in_polygon(a.lerp(b,float(t)),boundary): return false
	# Preserve every motor road, its curb and sidewalk. Internal pedestrian
	# footpaths in the stadium parcel may become the new concourse.
	for edge in world.geography.roads_near(anchor,155.0):
		if not bool(edge.driveable): continue
		var protected: PackedVector2Array = world.street_geometry.rect(edge.a,edge.b,float(edge.width)+3.2,.10)
		if not Geometry2D.intersect_polygons(poly,protected).is_empty(): return false
	return true

func reserve(city) -> PackedVector2Array:
	world = city
	var anchor: Vector3 = city.geography.project(23.11839,-82.37600)
	var source: PackedVector2Array = city.geography.stadium_boundary
	if source.is_empty():
		# Older local OSM exports may omit leisure polygons. Require the
		# large grandstand footprint visible in the user's existing map.
		var biggest := 0.0
		for fp in city.geography.footprints_near(anchor,145.0):
			var extent: Vector3 = fp.high-fp.low
			var area := extent.x*extent.z
			if area>biggest and minf(extent.x,extent.z)>65.0:
				biggest = area
				source = fp.poly
		if biggest<=0.0:
			push_warning("Latinoamericano: no stadium footprint in local OSM; preserving city.")
			return PackedVector2Array()
	var box: Rect2 = city.street_geometry.bounds(source)
	var mid := box.get_center()
	var original := Vector3(mid.x,0,mid.y)
	# Home plate lies toward the roofed southwest side in the supplied
	# reference; search nearby rotations to fit the mapped site.
	var best_score := 0.0
	for yaw in [2.55,2.35,2.75,2.15,2.95,1.95,3.10]:
		var rotation := Basis(Vector3.UP,float(yaw))
		var low := Vector2(INF,INF)
		var high := Vector2(-INF,-INF)
		for point in source:
			var local := rotation.inverse()*(Vector3(point.x,0,point.y)-original)
			low = low.min(Vector2(local.x,local.z))
			high = high.max(Vector2(local.x,local.z))
		var span := high-low
		var at := original+rotation*Vector3((low.x+high.x)*.5,0,(low.y+high.y)*.5)
		var hx := clampf(span.x*.49,48.0,98.0)
		var hz := clampf(span.y*.49,55.0,110.0)
		for factor in [1.0,.94,.88,.82,.76,.70,.64]:
			var area := hx*hz*float(factor)*float(factor)
			if area<=best_score: break
			var candidate := make_ring(at,rotation,hx*float(factor),hz*float(factor))
			if not _safe_site(candidate,anchor): continue
			best_score = area
			center = at
			stadium_basis = rotation
			half_x = hx*float(factor)
			half_z = hz*float(factor)
			ring = candidate
			break
	if ring.is_empty(): push_warning("Latinoamericano: unable to fit stadium without crossing mapped streets.")
	return ring

func _mat(key: String,color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = world._mat("latino_"+key,color)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat

func _point(q: Vector2,y: float = 0.0) -> Vector3:
	return center+stadium_basis*Vector3(q.x*half_x,y,q.y*half_z)

func _surface(mat: StandardMaterial3D) -> SurfaceTool:
	var id := mat.get_instance_id()
	if not surfaces.has(id):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		st.set_material(mat)
		surfaces[id] = st
	return surfaces[id]

func _tri(a: Vector3,b: Vector3,c: Vector3,mat: StandardMaterial3D,walk: bool = false) -> void:
	var st := _surface(mat)
	var normal := (c-a).cross(b-a).normalized()
	if walk and normal.y<0.0: normal = -normal
	for point in [a,b,c]:
		st.set_normal(normal)
		st.add_vertex(point-center)
	if walk:
		# Concave floor faces must point upward for player floor snapping.
		if (c-a).cross(b-a).y>=0.0: floor_faces.append_array([a-center,b-center,c-center])
		else: floor_faces.append_array([a-center,c-center,b-center])

func _quad(a: Vector3,b: Vector3,c: Vector3,d: Vector3,mat: StandardMaterial3D,walk: bool = false) -> void:
	_tri(a,b,c,mat,walk)
	_tri(a,c,d,mat,walk)

# Batched solid walls close exposed sides and undercroft. Keep them
# separate from walkable floors, using the city's obstacle layer.
func _shell(a: Vector3,b: Vector3,c: Vector3,d: Vector3,mat: StandardMaterial3D) -> void:
	_quad(a,b,c,d,mat)
	shell_faces.append_array([a-center,b-center,c-center,a-center,c-center,d-center])

func _end_wall(q: Vector2,inner: float,outer: float,top_inner: float,top_outer: float) -> void:
	_shell(_point(q*inner,.045),_point(q*outer,.045),_point(q*outer,top_outer),_point(q*inner,top_inner),structural_concrete)

func _rear_wall(a: Vector2,b: Vector2,height: float) -> void:
	_shell(_point(a*.99,.045),_point(b*.99,.045),_point(b*.99,height),_point(a*.99,height),structural_concrete)
	# Low concrete parapet behind the outer landing.
	_shell(_point(a*.99,height),_point(b*.99,height),_point(b*.99,height+.85),_point(a*.99,height+.85),blue)

func _poly(points: PackedVector2Array,y: float,mat: StandardMaterial3D,walk: bool = false) -> void:
	var ids := Geometry2D.triangulate_polygon(points)
	for i in range(0,ids.size(),3):
		_tri(_point(points[ids[i]],y),_point(points[ids[i+1]],y),_point(points[ids[i+2]],y),mat,walk)

func _box(at: Vector3,size: Vector3,angle: float,mat: StandardMaterial3D,solid: bool = false) -> void:
	world._cube(at,size,mat,angle,solid)

func _beam(a: Vector3,b: Vector3,wide: float,mat: StandardMaterial3D) -> void:
	# Local sloped truss beam, one mesh surface with all supports.
	var d := (b-a).normalized()
	var side := d.cross(Vector3.UP).normalized()
	if side.length_squared()<.1: side = Vector3.RIGHT
	var up := d.cross(side).normalized()
	var x := side*wide*.5
	var y := up*wide*.5
	_quad(a-x-y,b-x-y,b+x-y,a+x-y,mat)
	_quad(a-x+y,a+x+y,b+x+y,b-x+y,mat)
	_quad(a-x-y,a-x+y,b-x+y,b-x-y,mat)
	_quad(a+x-y,b+x-y,b+x+y,a+x+y,mat)

func _wall(a: Vector3,b: Vector3,bottom: float,height: float,mat: StandardMaterial3D,solid: bool = true) -> void:
	var d := b-a
	if d.length()<.05: return
	_box((a+b)*.5+Vector3.UP*(bottom+height*.5),Vector3(.44,height,d.length()+.06),atan2(d.x,d.z),mat,solid)

func _field() -> void:
	var field := PackedVector2Array()
	for q in OUTLINE: field.append(q*.65)
	_poly(PackedVector2Array(OUTLINE),.045,concrete,true)
	_poly(field,.065,warning_track)
	var greens := PackedVector2Array()
	for q in OUTLINE: greens.append(q*.60)
	_poly(greens,.081,grass)
	var home := Vector2(0,-.46)
	var base_distance := 27.43*minf(1.0,half_z/94.0)
	var dx := base_distance/sqrt(2.0)/half_x
	var dz := base_distance/sqrt(2.0)/half_z
	var first := home+Vector2(dx,dz)
	var second := home+Vector2(0,dz*2.0)
	var third := home+Vector2(-dx,dz)
	var dirt_shape := PackedVector2Array([home+Vector2(0,-.06),first+Vector2(.07,0),second+Vector2(.14,.09),second+Vector2(0,.14),second+Vector2(-.14,.09),third-Vector2(.07,0)])
	_poly(dirt_shape,.098,dirt)
	_poly(PackedVector2Array([home+Vector2(0,.045),first-Vector2(.045,0),second-Vector2(0,.045),third+Vector2(.045,0)]),.104,grass)
	for base in [home,first,second,third]:
		var at := _point(base,.12)
		_box(at,Vector3(.40,.08,.40),atan2(stadium_basis.z.x,stadium_basis.z.z)+PI*.25,paint)
	var mound := _point(home+Vector2(0,dz*.96),.11)
	var circle := PackedVector2Array()
	for i in range(16):
		var angle := TAU*float(i)/16.0
		circle.append(home+Vector2(0,dz*.96)+Vector2(cos(angle)*2.7/half_x,sin(angle)*2.7/half_z))
	_poly(circle,.116,dirt)
	_box(mound+Vector3.UP*.04,Vector3(.62,.035,.15),atan2(stadium_basis.z.x,stadium_basis.z.z),paint)
	# Foul lines follow the exact 45-degree diamond axes in world metres.
	var h := _point(home,.125)
	for side in [-1.0,1.0]:
		var end := h
		for metres in range(1,130):
			var q := home+Vector2(float(side)*float(metres)/sqrt(2.0)/half_x,float(metres)/sqrt(2.0)/half_z)
			if not Geometry2D.is_point_in_polygon(q,field): break
			end = _point(q,.125)
		var d := (end-h).normalized()
		var cross := Vector3(-d.z,0,d.x)*.055
		_quad(h-cross,end-cross,end+cross,h+cross,paint)
		_box(end+Vector3.UP*5.0,Vector3(.14,10.0,.14),0.0,_mat("foul",Color("#d6b33c")))
	# Dugouts, low blue structures near the two foul sides.
	for side in [-1.0,1.0]:
		var q := Vector2(float(side)*.42,-.29)
		var a := _point(q,.0)
		var yaw := atan2(stadium_basis.z.x,stadium_basis.z.z)-float(side)*.65
		_box(a+Vector3.UP*2.0,Vector3(12.0,.23,2.8),yaw,blue)
		_box(a+Vector3.UP*.45,Vector3(11.5,.25,.55),yaw,light_concrete)
		for x in [-5.7,5.7]:
			_box(a+Basis(Vector3.UP,yaw)*Vector3(float(x),1.0,0),Vector3(.24,2.0,.24),yaw,blue,true)

func _seat_strip(a: Vector2,b: Vector2,covered: bool) -> void:
	if a.distance_to(b)<.005: return
	var height := 11.5 if covered else 9.2
	for row in range(ROWS):
		var u := float(row)/float(ROWS)
		var v := float(row+1)/float(ROWS)
		var inner := lerpf(.69,.96,u)
		var outer := lerpf(.69,.96,v)
		var y := .12+height*u
		var top := .12+height*v
		var p := _point(a*inner,y)
		var q := _point(b*inner,y)
		var r := _point(b*outer,y)
		var s := _point(a*outer,y)
		_quad(p,q,r,s,light_concrete if row%4!=0 else blue,true)
		_quad(s,r,_point(b*outer,top),_point(a*outer,top),blue if row%4==0 else concrete)
		# Actual stepped side profile down to the foundation. No visible
		# gaps when looking from the entrances or from below a grandstand.
		_end_wall(a,inner,outer,y,y)
		_end_wall(b,inner,outer,y,y)
		var lip := lerpf(inner,outer,.83)
		_quad(_point(a*lip,y+.008),_point(b*lip,y+.008),_point(b*outer,y+.008),_point(a*outer,y+.008),blue if row%4==0 else structural_concrete)
	# Outer landing and closed underside behind the seats.
	_quad(_point(a*.96,.12+height),_point(b*.96,.12+height),_point(b*.99,.12+height),_point(a*.99,.12+height),blue,true)
	_end_wall(a,.96,.99,.12+height,.12+height)
	_end_wall(b,.96,.99,.12+height,.12+height)
	_rear_wall(a,b,.12+height)
	_shell(_point(a*.69,.045),_point(b*.69,.045),_point(b*.69,.12),_point(a*.69,.12),concrete)

func _aisle(a: Vector2,b: Vector2,covered: bool) -> void:
	var height := 11.5 if covered else 9.2
	_quad(_point(a*.69,.12),_point(b*.69,.12),_point(b*.96,.12+height),_point(a*.96,.12+height),concrete,true)
	_quad(_point(a*.96,.12+height),_point(b*.96,.12+height),_point(b*.99,.12+height),_point(a*.99,.12+height),concrete,true)
	_end_wall(a,.69,.96,.12,.12+height)
	_end_wall(b,.69,.96,.12,.12+height)
	_end_wall(a,.96,.99,.12+height,.12+height)
	_end_wall(b,.96,.99,.12+height,.12+height)
	_rear_wall(a,b,.12+height)

func _sector(i: int) -> void:
	var a: Vector2 = OUTLINE[i]
	var b: Vector2 = OUTLINE[(i+1)%OUTLINE.size()]
	var mid := (a+b)*.5
	var covered := mid.y<.24
	var start := _point(a)
	var finish := _point(b)
	var length := start.distance_to(finish)
	var gap := minf(.36,6.0/maxf(length,1.0)) if i in GATE_EDGES else 0.0
	var left := .5-gap*.5
	var right := .5+gap*.5
	var wall_height := 13.0 if covered else 10.8
	if gap>0.0:
		_wall(start,_point(a.lerp(b,left)),0,4.25,_mat("base_facade",Color("#73a4c2")))
		_wall(_point(a.lerp(b,right)),finish,0,4.25,_mat("base_facade",Color("#73a4c2")))
		_wall(_point(a.lerp(b,left)),_point(a.lerp(b,right)),4.6,.75,blue)
		var door := _point(mid)
		var outward := (door-center).normalized()
		var p := door+outward*1.2
		# Physical lintel and corridor roof above the open entrance. The
		# sides are enclosed by the neighboring grandstand foundations.
		var ga := a.lerp(b,left)
		var gb := a.lerp(b,right)
		_quad(_point(ga*.69,4.55),_point(gb*.69,4.55),_point(gb*.99,4.55),_point(ga*.99,4.55),structural_concrete)
		var label_value := "Entrada principal" if i==0 else "Acceso "+str(gates.size()+1)
		gates.append({"label":label_value,"p":p,"inside":_point(mid*.69,.1),"sector":i})
		var sign: Label3D = world._label(label_value.to_upper(),door+outward*.30+Vector3.UP*5.35,.032,atan2(outward.x,outward.z),Color("#edf2ef"))
		sign.visibility_range_end = 115.0
	else: _wall(start,finish,0,4.25,_mat("base_facade",Color("#73a4c2")))
	# The tall upper grandstand has a blue perimeter beam and an open
	# structural middle, rather than a continuous generic building wall.
	_wall(start,finish,wall_height-2.5,2.5,blue)
	_wall(start,finish,5.45,.55,blue,false)
	# Gate corridors remain completely open at ground level. The adjacent
	# aisles rise to the seating rows and perimeter landing.
	for segment in [[0.0,left],[right,1.0]] if gap>0.0 else [[0.0,1.0]]:
		var u := float(segment[0])
		var v := float(segment[1])
		var aisle_end := minf(v,u+maxf(.055,1.5/maxf(length,1.0)))
		_aisle(a.lerp(b,u),a.lerp(b,aisle_end),covered)
		_seat_strip(a.lerp(b,aisle_end),a.lerp(b,v),covered)
	# Structural outer facade, horizontal white strips and prominent piers.
	for y in [3.1,wall_height-.55]:
		if gap>0.0 and float(y)<4.6:
			_wall(start,_point(a.lerp(b,left)),float(y),.28,light_concrete,false)
			_wall(_point(a.lerp(b,right)),finish,float(y),.28,light_concrete,false)
		else: _wall(start,finish,float(y),.28,light_concrete,false)
	var count := maxi(1,roundi(length/8.0))
	for j in range(count):
		var u := (float(j)+.5)/float(count)
		if gap>0.0 and u>left-.02 and u<right+.02: continue
		var q := a.lerp(b,u)
		var pier := _point(q*.997)
		var n := (pier-center).normalized()
		_box(pier+Vector3.UP*(wall_height*.5),Vector3(.75,wall_height,.78),atan2(n.x,n.z),blue,true)
		# Raked concrete supports read clearly from the surrounding streets.
		_beam(_point(q*.985,4.4),_point(q*.78,7.5),.48,light_concrete)
		_beam(_point(q*.985,wall_height-1.5),_point(q*.86,wall_height-4.1),.52,blue)
	if covered:
		# Broad blue metal canopy, open in front of the spectators.
		var outer_a := _point(a*.998,17.2)
		var outer_b := _point(b*.998,17.2)
		var inner_a := _point(a*.76,16.0)
		var inner_b := _point(b*.76,16.0)
		_quad(outer_a,outer_b,inner_b,inner_a,roof)
		_quad(outer_a-Vector3.UP*.22,inner_a-Vector3.UP*.22,inner_b-Vector3.UP*.22,outer_b-Vector3.UP*.22,blue)
		_quad(inner_a,inner_b,inner_b-Vector3.UP*.32,inner_a-Vector3.UP*.32,blue)
		for j in range(count):
			var u := (float(j)+.5)/float(count)
			if gap>0.0 and u>left-.02 and u<right+.02: continue
			var q := a.lerp(b,u)
			_beam(_point(q*.98,wall_height),_point(q*.98,17.0),.45,blue)
			_beam(_point(q*.98,16.9),_point(q*.76,15.8),.31,blue)
			_beam(_point(q*.98,wall_height),_point(q*.82,16.0),.25,blue)

func _tower(q: Vector2) -> void:
	var bottom := _point(q)
	var d := (bottom-center).normalized()
	var side := Vector3(-d.z,0,d.x)
	var lean := -d*3.0
	var height := 24.5
	for sign_value in [-1.0,1.0]:
		var a := bottom+side*float(sign_value)*1.75
		var b := a+Vector3.UP*height+lean
		_beam(a,b,.50,blue)
	for i in range(6):
		var low := float(i)*height/6.0
		var high := float(i+1)*height/6.0
		var a := bottom+Vector3.UP*low+lean*(low/height)
		var b := bottom+Vector3.UP*high+lean*(high/height)
		_beam(a-side*1.75,b+side*1.75,.18,blue)
		_beam(a+side*1.75,b-side*1.75,.18,blue)
		_beam(b-side*1.75,b+side*1.75,.20,blue)
	var top := bottom+Vector3.UP*height+lean
	var angle := atan2(-d.x,-d.z)
	_box(top,Vector3(5.8,2.4,.42),angle,dark)
	var lens := _mat("lamp",Color("#e6e7de"))
	for row in range(2):
		for col in range(6):
			_box(top-d*.25+side*(float(col)-2.5)*.83+Vector3.UP*(float(row)-.5)*.93,Vector3(.68,.72,.12),angle,lens)

func _signs() -> void:
	var at := _point(Vector2(0,-.99),6.0)
	var outward := -stadium_basis.z
	var yaw := atan2(outward.x,outward.z)
	_box(at+outward*.35,Vector3(25.0,2.2,.45),yaw,dark)
	var label: Label3D = world._label("ESTADIO LATINOAMERICANO",at+outward*.62,.062,yaw,Color("#f5f4e8"))
	label.visibility_range_end = 180.0
	var board := _point(Vector2(0,.94),14.2)
	var board_yaw := atan2(-stadium_basis.z.x,-stadium_basis.z.z)
	_box(board,Vector3(20.0,8.0,.70),board_yaw,dark,true)
	_box(board-stadium_basis.z*.40,Vector3(19.0,6.9,.16),board_yaw,_mat("screen",Color("#232d37")))
	var title: Label3D = world._label("LATINOAMERICANO",board-stadium_basis.z*.52+Vector3.UP*2.25,.042,board_yaw,Color("#e6e9e3"))
	title.visibility_range_end = 190.0
	var status: Label3D = world._label("INDUSTRIALES  ·  0   |   0",board-stadium_basis.z*.53,.046,board_yaw,Color("#c0dce5"))
	status.visibility_range_end = 190.0

func build(city) -> void:
	world = city
	if ring.is_empty(): return
	grass = _mat("grass",Color("#57833e"))
	dirt = _mat("clay",Color("#b98149"))
	warning_track = _mat("warning",Color("#a98d65"))
	blue = _mat("blue",Color("#235d98"))
	concrete = _mat("concrete",Color("#a9aeae"))
	structural_concrete = _mat("foundation",Color("#89949c"))
	light_concrete = _mat("seat",Color("#d0d3d0"))
	dark = _mat("dark",Color("#18374c"))
	roof = _mat("roof",Color("#397fb9"))
	paint = _mat("chalk",Color("#eee9d3"))
	_field()
	for i in range(OUTLINE.size()): _sector(i)
	for q in [Vector2(-.95,-.12),Vector2(.95,-.12),Vector2(-.78,.57),Vector2(.78,.57),Vector2(-.45,.90),Vector2(.45,.90)]: _tower(q)
	_signs()
	for st in surfaces.values():
		var visual := MeshInstance3D.new()
		visual.mesh = st.commit()
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 520.0
		visual.visibility_range_end_margin = 20.0
		add_child(visual)
		visual.global_position = center
	surfaces.clear()
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	add_child(body)
	body.global_position = center
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(floor_faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	floor_faces.clear()
	if not shell_faces.is_empty():
		var walls := StaticBody3D.new()
		walls.collision_layer = 1
		walls.collision_mask = 0
		add_child(walls)
		walls.global_position = center
		var wall_shape := ConcavePolygonShape3D.new()
		wall_shape.backface_collision = true
		wall_shape.set_faces(shell_faces)
		var wall_collision := CollisionShape3D.new()
		wall_collision.shape = wall_shape
		walls.add_child(wall_collision)
		shell_faces.clear()
	world.editable_buildings["landmark_latinoamericano"] = {"poly":ring,"center":center,"height":25.0,"name":"Estadio Latinoamericano","protected":true,"front":{}}
	print("Latinoamericano: ",gates.size()," accessible gates; grandstands, canopy, field and scoreboard generated.")
