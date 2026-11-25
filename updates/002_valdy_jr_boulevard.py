"""My City 002: continuous boulevard, larger green terrain and two gateways.
Preserves the existing buildings, vehicles, door drivers and street geometry.
Run from My City Studio on a saved copy of district 01.
"""
import bpy
from math import sin, cos, pi
from mathutils import Vector

scene = bpy.context.scene
terrain = scene.objects.get("TERRENO | 80 x 84 m")
street = scene.objects.get("Calle principal | asphalt")
if terrain is None or terrain.type != 'MESH' or street is None:
    raise RuntimeError("Abre el distrito 01 original antes de aplicar.")
if bpy.data.collections.get("08 | Valdy Jr TV - Boulevard"):
    raise RuntimeError("El bulevar ya existe en el archivo.")
if bpy.data.collections.get("08 | Cocacola Boulevard"):
    raise RuntimeError("Abre una copia anterior a la expansion experimental para evitar duplicados.")
old_mesh = terrain.data
grass = list(old_mesh.materials)
if len(grass) < 4:
    raise RuntimeError("No se encontraron los cuatro materiales del terreno.")

# The original 80 x 84 m grid is preserved exactly in its central region.
# Outside it, a coarser grid is sufficient for gently rolling hills.
xs = [-80 + 2*i for i in range(20)] + [-40 + .8*i for i in range(101)] + [42 + 2*i for i in range(20)]
ys = [-110 + 2*i for i in range(34)] + [-42 + .8*i for i in range(106)] + [44 + 2*i for i in range(34)]

def height(x, y):
    t = max(0.0, min(1.0, max(-4.2-x, x-10.8, 0.0)/8.0))
    t = t*t*(3-2*t)
    hill = max(.10, 2.1+1.15*sin(x*.135+y*.075)+.82*cos(y*.16-x*.08)+.35*sin(x*.48+y*.27))
    return -.035 + t*hill

v = [(x,y,height(x,y)) for y in ys for x in xs]
nx = len(xs)
f = []
tones = []
for j in range(len(ys)-1):
    for i in range(nx-1):
        a = j*nx+i
        f.append((a,a+1,a+nx+1,a+nx))
        x,y = xs[i],ys[j]
        tone = sin(x*.37+y*.24)+.64*cos(y*.47-x*.11)+.27*sin(x*1.1+y*.8)
        tones.append(0 if tone<-.35 else 1 if tone<.65 else 3 if tone>1.25 else 2)
mesh = bpy.data.meshes.new("Relieve continuo 160 x 220 m")
mesh.from_pydata(v, [], f)
for m in grass:
    mesh.materials.append(m)
mesh.update()
for poly, tone in zip(mesh.polygons, tones):
    poly.use_smooth = True
    poly.material_index = tone

col = bpy.data.collections.new("08 | Valdy Jr TV - Boulevard")
scene.collection.children.link(col)

def material(name, color, rough=.65, metallic=0):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.diffuse_color = (*color,1)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = (*color,1)
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metallic
    return m

def original_material(key, color):
    ob = scene.objects.get("Calle principal | "+key)
    if ob and len(ob.data.materials):
        return ob.data.materials[0]
    return material("Boulevard | "+key,color)

asphalt = original_material("asphalt",(.115,.125,.139))
concrete = original_material("concrete",(.47,.46,.43))
curb = original_material("curb",(.61,.60,.55))
joint = original_material("joint",(.26,.26,.25))
yellow = material("Boulevard | yellow paint",(.92,.68,.045),.8)
steel = material("Gateway | graphite",(.055,.085,.11),.4,.5)
gold = material("Gateway | champagne trim",(.78,.52,.17),.38,.55)
cream = material("Gateway | ivory lettering",(.96,.94,.84),.45)
red = material("Gateway | deep red sign",(.46,.025,.028),.45)

# Combine details by material to limit the number of objects.
batches = {}
def add(mat, verts, faces):
    vs,fs = batches.setdefault(mat.name,([],[]))
    off = len(vs)
    vs.extend(verts)
    fs.extend(tuple(off+i for i in face) for face in faces)

def box(mat, p, d):
    x,y,z = p
    a,b,c = [q/2 for q in d]
    verts = [(x+i,y+j,z+k) for i,j,k in [(-a,-b,-c),(a,-b,-c),(a,b,-c),(-a,b,-c),(-a,-b,c),(a,-b,c),(a,b,c),(-a,b,c)]]
    add(mat,verts,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])

# Original roadway runs from -42 to +42 m. Extend it at both ends,
# exactly matching its width, curb locations and road elevation.
for s in (-1,1):
    y = s*76
    box(asphalt,(-.13,y,-.11),(6.68,68,.22))
    box(concrete,(4.12,y,.075),(1.54,68,.15))
    box(curb,(3.30,y,.075),(.18,68,.15))
    box(curb,(-3.56,y,.055),(.18,68,.11))
    for j in range(42,110,2):
        box(joint,(4.12,s*j,.151),(1.51,.018,.004))
        box(joint,(3.30,s*j,.151),(.17,.018,.004))

# Dashed centre stripe, no second road.
for y in range(-105,106,5):
    box(yellow,(-.13,y,.004),(.10,2.5,.006))

def text_obj(name, body, loc, size, face, maxwidth):
    d = bpy.data.curves.new(name,'FONT')
    d.body = body
    d.align_x = 'CENTER'
    d.align_y = 'CENTER'
    d.size = size
    d.extrude = .018
    d.resolution_u = 5
    d.materials.append(cream)
    o = bpy.data.objects.new(name,d)
    col.objects.link(o)
    o.location = loc
    o.rotation_euler = (pi/2,0,0 if face == -1 else pi)
    bpy.context.view_layer.update()
    if o.dimensions.x > maxwidth:
        d.size *= maxwidth/o.dimensions.x
    return o

# Curved arch with solid rectangular section (no modifiers).
def arch_ring(y, mat, outer, inner, depth):
    vv=[]
    for i in range(49):
        t=pi*i/48
        for rx,rz,dy in [(outer[0],outer[1],-depth/2),(inner[0],inner[1],-depth/2),(inner[0],inner[1],depth/2),(outer[0],outer[1],depth/2)]:
            vv.append((-.13+rx*cos(t),y+dy,5.25+rz*sin(t)))
    ff=[]
    for i in range(48):
        for j in range(4):
            a=4*i+j
            b=4*i+(j+1)%4
            ff.append((a,b,b+4,a+4))
    ff.extend([(3,2,1,0),(192,193,194,195)])
    add(mat,vv,ff)

for y, label in [(-106,"Sur"),(106,"Norte")]:
    for side in (-1,1):
        x = -.13+side*5.35
        z = height(x,y)
        box(concrete,(x,y,z+.23),(1.14,1.16,.66))
        box(steel,(x,y,2.52),(.76,.80,5.46))
        box(gold,(x,y,4.99),(.82,.86,.13))
        box(gold,(x,y,.65),(.81,.85,.12))
    arch_ring(y,steel,(5.73,3.05),(4.97,2.48),.76)
    # Thin front/rear decorative arc and two-sided city name.
    for face in (-1,1):
        arch_ring(y+face*.397,gold,(5.47,2.86),(5.32,2.72),.04)
    box(steel,(-.13,y,7.02),(6.8,.42,1.62))
    box(red,(-.13,y,7.02),(6.55,.48,1.39))
    for face in (-1,1):
        yy=y+face*.255
        text_obj("Arco "+label+" | Ciudad "+str(face),"Valdy Jr TV",(-.13,yy,7.28),.76,face,6.05)
        text_obj("Arco "+label+" | Calle "+str(face),"Cocacola Boulevard",(-.13,yy,6.73),.37,face,6.05)

for name,(verts,faces) in batches.items():
    me=bpy.data.meshes.new(name+" | geometria")
    me.from_pydata(verts,[],faces)
    me.update()
    me.materials.append(bpy.data.materials[name])
    ob=bpy.data.objects.new("Boulevard | "+name,me)
    col.objects.link(ob)

# Swap only the ground mesh after building the extension.
terrain.data=mesh
terrain.name="TERRENO | 160 x 220 m"
scene.name="Valdy Jr TV | My City"
scene["city_name"]="Valdy Jr TV"
scene["street_name"]="Cocacola Boulevard"

# Preserve original detail cameras and add a separate overview.
cam_data=bpy.data.cameras.new("Valdy Jr TV | Vista general")
cam=bpy.data.objects.new("CAM 04 | Boulevard completo",cam_data)
col.objects.link(cam)
cam.location=(-20,-170,150)
cam.rotation_euler=(Vector((0,0,0))-cam.location).to_track_quat('-Z','Y').to_euler()
cam_data.type='ORTHO'
cam_data.ortho_scale=320
cam_data.clip_end=1000
scene.camera=cam
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            for space in area.spaces:
                if space.type=='VIEW_3D':
                    space.clip_end=1000
                    space.region_3d.view_perspective='CAMERA'
                    space.shading.type='SOLID'
                    space.shading.color_type='MATERIAL'
print("My City: Valdy Jr TV, Cocacola Boulevard 220 m. Guarda el proyecto.")
