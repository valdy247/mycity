"""PARQUE_01 - park on the northern shore of LAGO_01.
Uses the confirmed marker's XY footprint, projected onto the existing terrain.
No changes to terrain, lake, road, houses, vehicles or their interactions.
"""
import bpy
from math import sin, cos, pi
from mathutils import Vector
from mathutils.bvhtree import BVHTree
import random

S=bpy.context.scene
terrain=S.objects.get("TERRENO | 160 x 220 m")
if not terrain or terrain.type!='MESH':
    raise RuntimeError("Aplica primero la actualizacion 002.")
if not S.objects.get("LAGO_01 | Agua"):
    raise RuntimeError("Aplica primero 003_lago_01.py.")
NAME="DISTRITO | PARQUE_01"
if bpy.data.collections.get(NAME):
    raise RuntimeError("El parque ya existe. No se duplicara.")
# Marker bounds: X [-54.87027,-30.87027], Y [74.00175,98.00175].
# Southern area overlaps lake. The buildable park stays north of Y=84.65.
CX,CY=-42.87027,86.00175
XMIN,XMAX=CX-12,CX+12
YMIN,YMAX=CY-12,CY+12
mw=terrain.matrix_world
verts=[mw@v.co for v in terrain.data.vertices]
tree=BVHTree.FromPolygons(verts,[tuple(p.vertices) for p in terrain.data.polygons])
def ground(x,y):
    hit,_,_,_=tree.ray_cast(Vector((x,y,1000)),Vector((0,0,-1)),2000)
    if hit is None:
        raise RuntimeError("No se encontro terreno bajo el parque.")
    return hit.z

# Paths and fixtures are built in a detached collection.
col=bpy.data.collections.new(NAME)
def mat(name,color,rough=.8,metal=0):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    p=m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value=(*color,1)
    p.inputs["Roughness"].default_value=rough
    p.inputs["Metallic"].default_value=metal
    return m
gravel=mat("Parque | Sendero arena",(.48,.39,.25))
edge=mat("Parque | Borde sendero",(.33,.31,.24))
wood=mat("Parque | Madera",(.32,.14,.055))
metal=mat("Parque | Metal grafito",(.045,.063,.055),.42,.45)
stone=mat("Parque | Piedra",(.48,.49,.43))
bark=mat("Parque | Corteza",(.15,.075,.032))
leaves=[mat("Parque | Hojas "+str(i),c) for i,c in enumerate([(.12,.34,.055),(.22,.43,.075),(.075,.25,.038)])]
flowers=[mat("Parque | Flores "+str(i),c) for i,c in enumerate([(.85,.45,.09),(.65,.12,.25),(.88,.85,.64)])]
lamp=mat("Parque | Difusor",(.94,.82,.52),.38)
batches={}
def add(m,vs,fs):
    v,f=batches.setdefault(m.name,([],[]))
    off=len(v);v.extend(vs);f.extend(tuple(off+i for i in face) for face in fs)
def box(m,p,d,yaw=0):
    x,y,z=p;a,b,c=[q/2 for q in d]
    v=[(x+i*cos(yaw)-j*sin(yaw),y+i*sin(yaw)+j*cos(yaw),z+k)
       for i,j,k in [(-a,-b,-c),(a,-b,-c),(a,b,-c),(-a,b,-c),(-a,-b,c),(a,-b,c),(a,b,c),(-a,b,c)]]
    add(m,v,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
def tube(m,a,b,r1,r2,n=8):
    a,b=Vector(a),Vector(b)
    d=(b-a).normalized()
    u=d.cross(Vector((0,1,0)))
    if u.length<.01:u=d.cross(Vector((1,0,0)))
    u.normalize();w=d.cross(u)
    v=[tuple(p+r*(cos(2*pi*i/n)*u+sin(2*pi*i/n)*w)) for p,r in [(a,r1),(b,r2)] for i in range(n)]
    f=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    f.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    add(m,v,f)
rng=random.Random(401)
def foliage(m,x,y,z,sx,sy,sz,n=9):
    v=[(x,y,z-sz)]
    for j in range(1,4):
        a=-pi/2+pi*j/4
        for i in range(n):
            t=2*pi*i/n+.13*j
            k=rng.uniform(.88,1.12)
            v.append((x+sx*cos(a)*cos(t)*k,y+sy*cos(a)*sin(t)*k,z+sz*sin(a)))
    v.append((x,y,z+sz))
    f=[(0,1+(i+1)%n,1+i) for i in range(n)]
    for j in range(2):
        a=1+j*n;b=a+n
        f.extend((a+i,a+(i+1)%n,b+(i+1)%n,b+i) for i in range(n))
    a=1+2*n
    f.extend((a+i,a+(i+1)%n,len(v)-1) for i in range(n))
    add(m,v,f)
# A gently winding elliptical walking loop, all above the actual terrain.
# North side is open green space; lake remains intact.
PCX,PCY=CX,90.65
A,B=8.9,5.0
N=160
for m,l,r in [(edge,-.89,-.75),(gravel,-.75,.75),(edge,.75,.89)]:
    vs=[]
    for i in range(N):
        t=2*pi*i/N
        x=PCX+A*cos(t);y=PCY+B*sin(t)
        normal=Vector((cos(t)/A,sin(t)/B)).normalized()
        # several transverse samples for contour-following surfaces
        for j in range(5):
            offset=l+(r-l)*j/4
            xx=x+normal.x*offset;yy=y+normal.y*offset
            assert XMIN<xx<XMAX and 84.65<yy<YMAX
            vs.append((xx,yy,ground(xx,yy)+.075))
    fs=[]
    for i in range(N):
        for j in range(4):
            a=i*5+j;b=((i+1)%N)*5+j
            fs.append((a,a+1,b+1,b))
    add(m,vs,fs)
# Three benches, facing south toward the lake. Individually grounded legs.
for x,y in [(CX-4.6,88.8),(CX,88.2),(CX+4.6,88.8)]:
    z=max(ground(x+dx,y+dy) for dx in (-.75,.75) for dy in (-.28,.28))
    for dx in (-.72,.72):
        for dy in (-.23,.23):
            g=ground(x+dx,y+dy)
            box(metal,(x+dx,y+dy,(g+z+.48)/2),(.09,.09,z+.48-g))
        box(metal,(x+dx,y+.24,z+.70),(.07,.07,.80))
    for j in range(5):
        box(wood,(x,y-.25+j*.12,z+.50),(1.85,.105,.055))
    for j in range(3):
        box(wood,(x,y+.27,z+.72+j*.13),(1.85,.055,.105))
# Four trees outside the walking loop and away from the existing lake trees.
for i,(dx,dy) in enumerate([(-9.7,9.1),(9.7,9.0),(-3.8,7.1),(4.0,7.0)]):
    x,y=CX+dx,CY+dy
    z=ground(x,y);h=rng.uniform(2.9,3.8)
    tube(bark,(x,y,z-.08),(x+.05,y,z+h*.68),.13,.052)
    for j in range(3):
        a=2*pi*j/3+i
        xx=x+.58*cos(a);yy=y+.58*sin(a)
        tube(bark,(x,y,z+h*.42),(xx,yy,z+h*.74),.046,.018,6)
        foliage(leaves[(i+j)%3],xx,yy,z+h*.80,.76,.73,.83)
    foliage(leaves[i%3],x,y,z+h*.99,.70,.69,.77)
# Small flowering beds in the central grass area; no heavy particle systems.
for bx,by in [(CX-2.7,91.0),(CX+2.7,91.0)]:
    for j in range(13):
        a=rng.uniform(0,2*pi);r=rng.uniform(.05,1.0)
        x=bx+r*cos(a);y=by+r*.6*sin(a);z=ground(x,y)
        foliage(leaves[j%3],x,y,z+.15,.22,.18,.22,7)
        foliage(flowers[j%3],x,y,z+.33,.09,.09,.06,6)
# Two bins and four ornamental lamp posts (geometry only, no added lights).
for x,y in [(CX-7,89.3),(CX+7,89.3)]:
    z=ground(x,y)
    tube(metal,(x,y,z),(x,y,z+.70),.20,.22,12)
    tube(wood,(x,y,z+.69),(x,y,z+.75),.24,.24,12)
for dx,dy in [(-8.9,2.2),(8.9,2.2),(-7.1,8.8),(7.1,8.8)]:
    x,y=CX+dx,CY+dy;z=ground(x,y)
    tube(metal,(x,y,z-.03),(x,y,z+.20),.17,.12)
    tube(metal,(x,y,z+.20),(x,y,z+2.8),.055,.04)
    tube(lamp,(x,y,z+2.78),(x,y,z+3.02),.13,.15,10)
    tube(metal,(x,y,z+3.02),(x,y,z+3.13),.20,.06,10)
# Batch all geometry by material to keep draw-call/object counts low.
for name,(vs,fs) in batches.items():
    me=bpy.data.meshes.new(name+" | PARQUE_01")
    me.from_pydata(vs,[],fs);me.update()
    me.materials.append(bpy.data.materials[name])
    ob=bpy.data.objects.new(name,me);col.objects.link(ob)
    if "Hojas" in name or "Flores" in name:
        for p in me.polygons:p.use_smooth=True
# Dedicated camera; preserve existing lake and city cameras.
cd=bpy.data.cameras.new("PARQUE_01 | Camara")
cam=bpy.data.objects.new("CAM 06 | Parque y lago",cd);col.objects.link(cam)
target=Vector((CX+1,82.5,ground(CX,90)+.6))
cam.location=target+Vector((-22,-32,37))
cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
cd.type='ORTHO';cd.ortho_scale=51;cd.clip_end=500
# The original terrain is unchanged.
S.collection.children.link(col)
bpy.context.view_layer.update()
marker=S.objects.get("PARQUE_01")
if marker and marker.get("mycity_plan_type")=="PARQUE":
    marker["mycity_built"]=True
    marker.hide_render=True
    if bpy.context.view_layer.objects.get(marker.name):marker.hide_set(True)
S.camera=cam
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=="VIEW_3D":
            sp=area.spaces.active
            sp.region_3d.view_perspective="CAMERA"
            sp.shading.type="SOLID";sp.shading.color_type="MATERIAL"
print("PARQUE_01 construido junto al lago. Guarda My City.")
