extends Node3D
# Deterministic, vertex-colored street wear. A single mesh per 96 m tile,
# no decals, new colliders, reflection probes, lights or per-frame updates.
const TILE := 96.0
const LIMIT_PER_TILE := 105
var surfaces: Dictionary = {}
var counts: Dictionary = {}
var material := StandardMaterial3D.new()

static func spacing(major: bool) -> float:
	return 7.5 if major else 4.1

func _triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,tone: Color) -> void:
	for point in [a,b,c]:
		st.set_color(tone)
		st.set_normal(Vector3.UP)
		st.add_vertex(point)

func _surface(p: Vector3) -> SurfaceTool:
	var tile := Vector2i(floori(p.x/TILE),floori(p.z/TILE))
	if not surfaces.has(tile):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		surfaces[tile] = st
	return surfaces[tile]

func _damage(p: Vector3,d: Vector3,rx: float,rz: float,rng: RandomNumberGenerator,streets,wet: bool) -> bool:
	var right := Vector3(-d.z,0,d.x)
	var outer := PackedVector3Array()
	var inner := PackedVector3Array()
	var n := 9
	for i in range(n):
		var angle := TAU*float(i)/float(n)
		var jitter := rng.randf_range(.77,1.18)
		var v := right*cos(angle)*rx*jitter+d*sin(angle)*rz*jitter
		var q := p+v
		if not streets.point_on_road(q): return false
		outer.append(Vector3(q.x,.044,q.z))
		inner.append(Vector3(p.x+v.x*.70,.045,p.z+v.z*.70))
	var tile := Vector2i(floori(p.x/TILE),floori(p.z/TILE))
	if int(counts.get(tile,0))>=LIMIT_PER_TILE: return false
	counts[tile] = int(counts.get(tile,0))+1
	var st := _surface(p)
	var center := Vector3(p.x,.046,p.z)
	var inside := Color("#454440") if not wet else Color("#777d78")
	var rim := Color("#77736a")
	for i in range(n):
		var j := (i+1)%n
		_triangle(st,outer[i],outer[j],inner[j],rim.darkened(rng.randf_range(0.0,.25)))
		_triangle(st,outer[i],inner[j],inner[i],rim.darkened(rng.randf_range(0.0,.25)))
		_triangle(st,center,inner[i],inner[j],inside.darkened(rng.randf_range(0.0,.19)))
	if wet:
		var q := center+Vector3.UP*.002
		_triangle(st,q-right*rx*.36,q+right*rx*.30+d*rz*.15,q+d*rz*.42,Color("#a5aaa4"))
	# Small irregular cracks emerging from the broken asphalt.
	for i in range(2):
		var start := outer[rng.randi_range(0,n-1)]
		var end := start+(start-center).normalized()*rng.randf_range(.28,.85)
		if not streets.point_on_road(end): continue
		var across := Vector3(-(end-start).z,0,(end-start).x).normalized()*.025
		_triangle(st,start-across,start+across,end,Color("#383936"))
	return true

func build(geography,streets) -> void:
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.roughness = .94
	var rng := RandomNumberGenerator.new()
	rng.seed = 7142026
	var used: Dictionary = {}
	for edge in geography.roads:
		if not bool(edge.driveable): continue
		var first := String(edge.a_id)
		var last := String(edge.b_id)
		var key := first+":"+last if first<last else last+":"+first
		if used.has(key): continue
		used[key] = true
		var a: Vector3 = edge.a
		var b: Vector3 = edge.b
		var length := a.distance_to(b)
		var width := float(edge.width)
		if length<5.0 or width<3.0: continue
		var d := (b-a).normalized()
		var right := Vector3(-d.z,0,d.x)
		var major := int(edge.get("lanes_per_direction",1))>=2 or width>=9.0
		var cursor := rng.randf_range(1.8,spacing(major))
		while cursor<length-1.3:
			var side := -1.0 if rng.randf()<.5 else 1.0
			var lateral := rng.randf_range(.7,maxf(.71,width*.5-.90))*side
			var p := a+d*cursor+right*lateral
			var rx := rng.randf_range(.30,.85 if major else 1.15)
			var rz := rng.randf_range(.38,1.35 if major else 1.8)
			_damage(p,d,rx,rz,rng,streets,rng.randf()<(.23 if major else .37))
			cursor += rng.randf_range(.65,1.40)*spacing(major)
	for tile in surfaces:
		var st: SurfaceTool = surfaces[tile]
		var visual := MeshInstance3D.new()
		visual.mesh = st.commit()
		visual.material_override = material
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		visual.visibility_range_end = 100.0
		visual.visibility_range_end_margin = 8.0
		add_child(visual)
	surfaces.clear()
	counts.clear()
