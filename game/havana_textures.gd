extends RefCounted
# Small original tileable albedo textures. No downloads or external assets.
var textures: Dictionary = {}
var materials: Dictionary = {}
var noise_images: Dictionary = {}
var prepared_albedo: Dictionary = {}
var prepared_surfaces: Dictionary = {}

# Produce only Image data on the worker; ImageTexture creation stays on
# the main thread, preserving the original resolution and material quality.
func prepare_images(with_detail: bool) -> void:
	for kind in ["plaster","asphalt","stone","tile","wood","cardboard"]:
		prepared_albedo[kind] = _albedo_image(kind)
		if with_detail: prepared_surfaces[kind] = _surface_images(kind)
var normal_textures: Dictionary = {}
var roughness_textures: Dictionary = {}
var material_kinds: Dictionary = {}
var quality := 1

func set_quality(value: int) -> void:
	quality = clampi(value,0,2)
	for key in materials:
		_apply_surface_detail(materials[key],String(material_kinds[key]))

func _map_texture(img: Image,normal: bool = false) -> ImageTexture:
	img.generate_mipmaps(normal)
	return ImageTexture.create_from_image(img)

func _surface_maps(kind: String) -> void:
	if normal_textures.has(kind): return
	var images: Array = prepared_surfaces.get(kind,[])
	if images.is_empty(): images = _surface_images(kind)
	normal_textures[kind] = _map_texture(images[0],true)
	roughness_textures[kind] = _map_texture(images[1])
	prepared_surfaces.erase(kind)

func _surface_images(kind: String) -> Array:
	var height := Image.create(256,256,false,Image.FORMAT_RGB8)
	var rough := Image.create(256,256,false,Image.FORMAT_RGB8)
	var fine := _noise(71,.21)
	var coarse := _noise(31,.035)
	var stains := _noise(92,.075)
	for y in range(256):
		for x in range(256):
			var f := fine.get_pixel(x,y).r
			var c := coarse.get_pixel(x,y).r
			var s := stains.get_pixel(x,y).r
			var h := .40+.15*f+.08*c
			var r := .81+.14*f
			match kind:
				"plaster":
					h -= .16*smoothstep(.60,.72,c+s*.20)
					r = .76+.20*s
				"asphalt","stone":
					var seam := 1.0-smoothstep(.008,.028,absf(c-.53))
					h -= seam*smoothstep(.48,.68,s)*.13
					r = .87+.10*f
				"tile":
					if posmod(x,64)<2 or posmod(y,64)<2: h -= .22
					r = .54+.22*s
				"wood":
					h += .035*sin(float(x)*.73+s*4.0)
					if posmod(x,64)<2: h -= .16
					r = .70+.21*s
			h = clampf(h,0.0,1.0)
			r = clampf(r,0.0,1.0)
			height.set_pixel(x,y,Color(h,h,h))
			rough.set_pixel(x,y,Color(r,r,r))
	height.bump_map_to_normal_map(1.0)
	return [height,rough]

func _apply_surface_detail(m: StandardMaterial3D,kind: String) -> void:
	m.normal_enabled = quality>0
	m.normal_scale = .58 if quality==2 else .34
	if quality>0:
		_surface_maps(kind)
		m.normal_texture = normal_textures[kind] as Texture2D
		m.roughness_texture = roughness_textures[kind] as Texture2D
	else:
		m.normal_texture = null
		m.roughness_texture = null
	m.roughness = 1.0 if quality>0 else (.70 if kind=="tile" else .91)
	m.metallic = 0.0

func _noise(seed_value: int,frequency: float) -> Image:
	var key := str(seed_value)+":"+str(frequency)
	if noise_images.has(key): return noise_images[key] as Image
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = frequency
	n.fractal_octaves = 3
	var img := n.get_seamless_image(256,256,false,false,.14)
	noise_images[key] = img
	return img

func _texture(kind: String) -> ImageTexture:
	if textures.has(kind):
		return textures[kind] as ImageTexture
	var img: Image = prepared_albedo.get(kind)
	if img==null: img = _albedo_image(kind)
	var tex := _map_texture(img)
	textures[kind] = tex
	prepared_albedo.erase(kind)
	return tex

func _albedo_image(kind: String) -> Image:
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
				var grime: float = smoothstep(.54,.79,s)*.22
				var exposed: float = smoothstep(.76,.86,c+s*.20)
				pixel = Color(.96,.95,.92).lerp(Color(.61,.57,.50),peeled)
				pixel = pixel.lerp(Color(.57,.43,.34),exposed*.7)
				pixel *= .93+.13*f-grime
			elif kind=="asphalt":
				var seam: float = 1.0-smoothstep(.006,.022,absf(c-.53))
				var crack: float = seam*smoothstep(.50,.68,s)
				var patched: float = smoothstep(.67,.79,c)*smoothstep(.42,.58,s)
				tone = .73+.21*f+.12*s-crack*.30-patched*.17
				pixel = Color(tone,tone,tone)
			elif kind=="stone":
				var crack: float = (1.0-smoothstep(.008,.028,absf(c-.51)))*smoothstep(.45,.68,s)
				var stain: float = smoothstep(.60,.78,s)
				tone = .88+.12*f-crack*.24-stain*.16
				pixel = Color(tone,tone*.99,tone*.96)
			elif kind=="tile":
				var xx: int = posmod(x,64)
				var yy: int = posmod(y,64)
				var joint: bool = xx<2 or yy<2
				var checker: bool = (floori(float(x)/64.0)+floori(float(y)/64.0))%2==0
				tone = (.94 if checker else .49)*(.87+.12*f)
				if joint: tone = .45
				pixel = Color(tone,tone,tone)
			elif kind=="cardboard":
				var fiber := .5+.5*sin(float(y)*1.9+s*4.0)
				tone = .82+.08*f+.05*c+.025*fiber
				pixel = Color(tone,tone*.985,tone*.95)
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
	return img

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
	materials[key] = m
	material_kinds[key] = kind
	_apply_surface_detail(m,kind)
	return m
