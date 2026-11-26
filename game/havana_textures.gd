extends RefCounted
# Small original tileable albedo textures. No downloads or external assets.
var textures: Dictionary = {}
var materials: Dictionary = {}

func _noise(seed_value: int,frequency: float) -> Image:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	n.fractal_octaves = 3
	return n.get_seamless_image(256,256,false,false,.14)

func _texture(kind: String) -> ImageTexture:
	if textures.has(kind):
		return textures[kind] as ImageTexture
	var fine := _noise(71,.21)
	var coarse := _noise(31,.035)
	var stains := _noise(92,.075)
	var img := Image.create(256,256,false,Image.FORMAT_RGB8)
	for y in range(256):
		for x in range(256):
			var f: float = fine.get_pixel(x,y).r
			var c: float = coarse.get_pixel(x,y).r
			var s: float = stains.get_pixel(x,y).r
			var tone: float = .82+.14*f+.08*c
			var pixel := Color(tone,tone,tone)
			if kind=="plaster":
				# Irregular peeling paint and damp patches; neutral tint preserves wall colour.
				var peeled: float = smoothstep(.60,.72,c+s*.20)
				var grime: float = smoothstep(.54,.79,s)*.14
				pixel = Color(.96,.95,.92).lerp(Color(.61,.57,.50),peeled)
				pixel *= .93+.13*f-grime
			elif kind=="asphalt":
				var seam: float = 1.0-smoothstep(.006,.022,absf(c-.53))
				var crack: float = seam*smoothstep(.50,.68,s)
				tone = .73+.21*f+.12*s-crack*.30
				pixel = Color(tone,tone,tone)
			elif kind=="tile":
				var xx: int = posmod(x,64)
				var yy: int = posmod(y,64)
				var joint: bool = xx<2 or yy<2
				var checker: bool = (floori(float(x)/64.0)+floori(float(y)/64.0))%2==0
				tone = (.94 if checker else .49)*(.87+.12*f)
				if joint: tone = .45
				pixel = Color(tone,tone,tone)
			elif kind=="wood":
				var plank: int = posmod(x,64)
				var grain: float = .5+.5*sin(float(x)*.73+s*4.0)
				tone = .72+.17*grain+.11*f
				if plank<2: tone *= .58
				pixel = Color(tone,tone,tone)
			else:
				tone = .79+.18*f+.10*c
				pixel = Color(tone,tone,tone)
			img.set_pixel(x,y,Color(clampf(pixel.r,0,1),clampf(pixel.g,0,1),clampf(pixel.b,0,1)))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	textures[kind] = tex
	return tex

func material(base: StandardMaterial3D,kind: String) -> StandardMaterial3D:
	var key := str(base.get_instance_id())+":"+kind
	if materials.has(key):
		return materials[key] as StandardMaterial3D
	var m := base.duplicate() as StandardMaterial3D
	m.albedo_texture = _texture(kind)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var scale_value: float = .5 if kind=="tile" else (.35 if kind=="asphalt" else .65)
	m.uv1_scale = Vector3.ONE*scale_value
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	m.roughness = .91
	materials[key] = m
	return m
