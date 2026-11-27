extends RefCounted
# One shared mesh per shoe, with a flat sole and rounded/chamfered toe.
static var cached: ArrayMesh
static var materials: Dictionary = {}

static func mesh() -> ArrayMesh:
	if cached!=null: return cached
	var ring := PackedVector2Array([Vector2(-.34,-.50),Vector2(.34,-.50),Vector2(.50,-.32),Vector2(.50,.30),Vector2(.34,.50),Vector2(-.34,.50),Vector2(-.50,.30),Vector2(-.50,-.32)])
	var levels: Array[PackedVector3Array] = []
	for level in range(3):
		var points := PackedVector3Array()
		for q in ring:
			var y := -.5 if level==0 else (-.24 if level==1 else (.38 if q.y<0.0 else .05))
			var shrink := .88 if level==2 else 1.0
			points.append(Vector3(q.x*shrink,y,q.y*shrink))
		levels.append(points)
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for level in range(2):
		var tone := Color(.42,.42,.42) if level==0 else Color.WHITE
		for i in range(ring.size()):
			var j := (i+1)%ring.size()
			for vertex in [levels[level][i],levels[level][j],levels[level+1][j],levels[level][i],levels[level+1][j],levels[level+1][i]]:
				surface.set_color(tone)
				surface.add_vertex(vertex)
	for i in range(1,ring.size()-1):
		for vertex in [levels[2][0],levels[2][i],levels[2][i+1]]:
			surface.set_color(Color.WHITE)
			surface.add_vertex(vertex)
		for vertex in [levels[0][0],levels[0][i+1],levels[0][i]]:
			surface.set_color(Color(.42,.42,.42))
			surface.add_vertex(vertex)
	surface.generate_normals()
	cached = surface.commit()
	return cached

static func material(base: StandardMaterial3D) -> StandardMaterial3D:
	var key := base.albedo_color.to_html()
	if not materials.has(key):
		var result := base.duplicate() as StandardMaterial3D
		result.vertex_color_use_as_albedo = true
		materials[key] = result
	return materials[key] as StandardMaterial3D
