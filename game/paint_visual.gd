extends RefCounted
# Visual-only high-resolution texture; the existing save dictionary remains authoritative.
const PIXELS := 24
const OLD_WALL := Color("#a99d88")
const OLD_DOOR := Color("#79644e")
const BLUE := Color("#4c92c9")
const YELLOW := Color("#e9bf43")

static func _noise(x: int,y: int,seed: int) -> float:
	return float(posmod(x*73+y*151+x*y*17+seed*199,257))/256.0

static func _index(x: int,y: int,cols: int,rows: int) -> int:
	return clampi(y,0,rows-1)*cols+clampi(x,0,cols-1)

static func _sample(code: int,x: int,y: int,door: bool,seed: int) -> Color:
	var grain := _noise(x,y,seed)
	var broad := .5+.5*sin(float(x)*.083+sin(float(y)*.11)*2.0+float(seed))
	if code==0:
		if door:
			var wood := .5+.5*sin(float(x)*.53+sin(float(y)*.09)*1.3)
			return OLD_DOOR*(.82+.12*wood+.07*grain)
		var worn := smoothstep(.71,.92,broad)*.16
		var damp := smoothstep(.72,.97,.5+.5*sin(float(x)*.044+float(y)*.07+float(seed)))*.11
		return OLD_WALL.lerp(Color("#746c60"),worn+damp)*(.91+.15*grain)
	var color := BLUE if code==1 else YELLOW
	var stroke := sin(float(x)*.36+sin(float(y)*.08))*.012
	return color*(.975+.035*grain+stroke)

static func new_surface(wall: int,cols: int,rows: int,painted: Dictionary,door: bool) -> Image:
	var img := Image.create(cols*PIXELS,rows*PIXELS,false,Image.FORMAT_RGB8)
	redraw(img,wall,cols,rows,painted,door)
	return img

static func redraw(img: Image,wall: int,cols: int,rows: int,painted: Dictionary,door: bool,changed: Vector2i = Vector2i(-1,-1)) -> void:
	var codes := PackedByteArray()
	codes.resize(cols*rows)
	for y in range(rows):
		for x in range(cols):
			var value := String(painted.get("%d:%d:%d" % [wall,x,y],""))
			codes[y*cols+x] = 1 if value=="blue" else (2 if value=="yellow" else 0)
	var x0 := 0 if changed.x<0 else maxi(0,(changed.x-1)*PIXELS)
	var y0 := 0 if changed.y<0 else maxi(0,(changed.y-1)*PIXELS)
	var x1 := cols*PIXELS if changed.x<0 else mini(cols*PIXELS,(changed.x+2)*PIXELS)
	var y1 := rows*PIXELS if changed.y<0 else mini(rows*PIXELS,(changed.y+2)*PIXELS)
	for py in range(y0,y1):
		for px in range(x0,x1):
			var cx := floori(float(px)/PIXELS)
			var cy := floori(float(py)/PIXELS)
			var code := int(codes[_index(cx,cy,cols,rows)])
			var color := _sample(code,px,py,door,wall)
			var dx := float(px%PIXELS)+.5
			var dy := float(py%PIXELS)+.5
			var nx := cx-1 if dx<PIXELS*.5 else cx+1
			var ny := cy-1 if dy<PIXELS*.5 else cy+1
			var edge_x := minf(dx,float(PIXELS)-dx)
			var edge_y := minf(dy,float(PIXELS)-dy)
			var other_x := int(codes[_index(nx,cy,cols,rows)])
			var other_y := int(codes[_index(cx,ny,cols,rows)])
			var width := 1.0+2.1*_noise(px,py,wall+9)
			if other_x!=code and edge_x<width:
				color = color.lerp(_sample(other_x,px,py,door,wall),.47*(1.0-smoothstep(0.0,width,edge_x)))
			if other_y!=code and edge_y<width:
				color = color.lerp(_sample(other_y,px,py,door,wall),.47*(1.0-smoothstep(0.0,width,edge_y)))
			img.set_pixel(px,py,Color(clampf(color.r,0.0,1.0),clampf(color.g,0.0,1.0),clampf(color.b,0.0,1.0)))
