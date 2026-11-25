"""LAGO_01: natural lake from the exported urban plan.
Requires update 002 and a saved copy of the city. No animation or simulation.
"""
import bpy
from math import sin, cos, pi, sqrt, atan2, ceil
from mathutils import Vector
from bisect import bisect_right
import random

S = bpy.context.scene
terrain = S.objects.get("TERRENO | 160 x 220 m")
if not terrain or terrain.type != 'MESH':
    raise RuntimeError("Aplica primero la actualizacion 002 del bulevar.")
if bpy.data.collections.get("DISTRITO | LAGO_01"):
    raise RuntimeError("LAGO_01 ya existe. No se duplicara.")
CX,CY = -39.58014,75.40224
RX,RY = 12.16,9.14
old = terrain.data
mw = terrain.matrix_world.copy()
inv = mw.inverted()
# Read the existing height grid instead of regenerating other parts of the city.
coords = [mw @ v.co for v in old.vertices]
xs = sorted(set(round(v.x,4) for v in coords))
ys = sorted(set(round(v.y,4) for v in coords))
heights = {(round(v.x,4),round(v.y,4)):float(v.z) for v in coords}
if len(heights) != len(xs)*len(ys) or len(coords)!=len(heights):
    raise RuntimeError("El terreno ya no es una cuadricula regular; no se modificara.")
if not (xs[0]<CX-RX and CX+RX<xs[-1] and ys[0]<CY-RY and CY+RY<ys[-1]):
    raise RuntimeError("El marcador esta fuera del terreno.")
def bracket(grid,t):
    i=max(0,min(len(grid)-2,bisect_right(grid,t)-1))
    return i,(t-grid[i])/(grid[i+1]-grid[i])
def ground(x,y):
    i,u=bracket(xs,x); j,v=bracket(ys,y)
    a,b=xs[i:i+2]; c,d=ys[j:j+2]
    return ((1-u)*(1-v)*heights[a,c]+u*(1-v)*heights[b,c]
            +(1-u)*v*heights[a,d]+u*v*heights[b,d])
def smooth(t):
    t=max(0,min(1,t)); return t*t*(3-2*t)
def shape(a):
    return .91+.055*sin(3*a+.5)+.026*cos(5*a-1.1)
def point(a,r):
    q=r*shape(a)
    return CX+RX*q*cos(a),CY+RY*q*sin(a)
def radius(x,y):
    dx=(x-CX)/RX; dy=(y-CY)/RY
    return sqrt(dx*dx+dy*dy)/shape(atan2(dy,dx))
# Horizontal water, below every sampled outer bank.
level=min(ground(*point(2*pi*i/96,1.0)) for i in range(96))-.22
def sculpt(x,y):
    r=radius(x,y); original=ground(x,y)
    if r>=1.0:
        return original
    if r<=.74:
        return level-1.35*(1-smooth(r/.74))
    if r<=.84:
        return level+.28*smooth((r-.74)/.10)
    return (level+.28)*(1-smooth((r-.84)/.16))+original*smooth((r-.84)/.16)
# Retain every original grid line. Refine strips crossing the lake to 0.32 m.
def refine(grid,lo,hi):
    result=[grid[0]]
    for a,b in zip(grid,grid[1:]):
        n=ceil((b-a)/.32) if b>lo and a<hi else 1
        result.extend(a+(b-a)*k/n for k in range(1,n+1))
    return result
nx=refine(xs,CX-RX-.5,CX+RX+.5)
ny=refine(ys,CY-RY-.5,CY+RY+.5)
assert len(nx)*len(ny)<85000, "Presupuesto de terreno excedido"
# Original material per original quad, preserving the city palette.
old_mats=list(old.materials)
cell_material={}
for p in old.polygons:
    c=mw@p.center
    i,_=bracket(xs,c.x); j,_=bracket(ys,c.y)
    cell_material[i,j]=p.material_index

def material(name,color,rough=.8):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough
    return m
soil=material('LAGO_01 | Orilla humeda',(.24,.20,.12))
sand=material('LAGO_01 | Arena y grava',(.39,.33,.21))
water=material('LAGO_01 | Agua azul verdosa',(.035,.31,.36),.18)
p=water.node_tree.nodes.get('Principled BSDF')
# Inexpensive micro ripples, no displacement, transparency or water simulation.
nt=water.node_tree
noise=nt.nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value=6.0
noise.inputs['Detail'].default_value=2.0
tex=nt.nodes.new('ShaderNodeTexCoord')
nt.links.new(tex.outputs['Object'],noise.inputs['Vector'])
bump=nt.nodes.new('ShaderNodeBump')
bump.inputs['Strength'].default_value=.16
bump.inputs['Distance'].default_value=.028
nt.links.new(noise.outputs['Fac'],bump.inputs['Height'])
nt.links.new(bump.outputs['Normal'],p.inputs['Normal'])
if 'IOR' in p.inputs: p.inputs['IOR'].default_value=1.333

verts=[tuple(inv@Vector((x,y,sculpt(x,y)))) for y in ny for x in nx]
faces=[]; indices=[]
width=len(nx)
for j in range(len(ny)-1):
    y=(ny[j]+ny[j+1])/2
    iy,_=bracket(ys,y)
    for i in range(width-1):
        a=j*width+i
        faces.append((a,a+1,a+width+1,a+width))
        x=(nx[i]+nx[i+1])/2
        ix,_=bracket(xs,x)
        r=radius(x,y)
        indices.append(len(old_mats) if .69<r<.79 else len(old_mats)+1 if .79<=r<.86 else cell_material.get((ix,iy),0))
new=bpy.data.meshes.new('Relieve ciudad | cuenca LAGO_01')
new.from_pydata(verts,[],faces)
for m in old_mats+[soil,sand]:
    new.materials.append(m)
new.update()
for face,idx in zip(new.polygons,indices):
    face.material_index=idx
    face.use_smooth=True

# Build detached collection first, then commit the changes to the scene.
col=bpy.data.collections.new('DISTRITO | LAGO_01')
def obj_mesh(name,vs,fs,mat,smooth_faces=False):
    me=bpy.data.meshes.new(name)
    me.from_pydata(vs,[],fs); me.update()
    me.materials.append(mat)
    for f in me.polygons:
        f.use_smooth=smooth_faces
    ob=bpy.data.objects.new(name,me); col.objects.link(ob)
    return ob
# Water overlaps only the buried lip of the shore to avoid visible gaps.
N=144
wv=[(CX,CY,level)]+[(*point(2*pi*i/N,.82),level) for i in range(N)]
wf=[(0,1+i,1+(i+1)%N) for i in range(N)]
obj_mesh('LAGO_01 | Agua',wv,wf,water)

rng=random.Random(3101)
batches={}
def add(mat,vs,fs):
    v,f=batches.setdefault(mat.name,([],[]))
    off=len(v); v.extend(vs); f.extend(tuple(off+i for i in face) for face in fs)
def blob(mat,x,y,z,sx,sy,sz,n=10,rings=4):
    v=[(x,y,z-sz)]
    for j in range(1,rings):
        a=-pi/2+pi*j/rings
        for i in range(n):
            b=2*pi*i/n
            k=rng.uniform(.84,1.13)
            v.append((x+sx*cos(a)*cos(b)*k,y+sy*cos(a)*sin(b)*k,z+sz*sin(a)))
    v.append((x,y,z+sz))
    f=[(0,1+(i+1)%n,1+i) for i in range(n)]
    for j in range(rings-2):
        a=1+j*n; b=a+n
        f.extend((a+i,a+(i+1)%n,b+(i+1)%n,b+i) for i in range(n))
    a=1+(rings-2)*n
    f.extend((a+i,a+(i+1)%n,len(v)-1) for i in range(n))
    add(mat,v,f)
def trunk(mat,a,b,r1,r2,n=8):
    a,b=Vector(a),Vector(b)
    d=(b-a).normalized()
    u=d.cross(Vector((0,1,0))).normalized()
    if u.length<.01: u=d.cross(Vector((1,0,0))).normalized()
    w=d.cross(u)
    v=[tuple(p+r*(cos(2*pi*i/n)*u+sin(2*pi*i/n)*w)) for p,r in [(a,r1),(b,r2)] for i in range(n)]
    f=[tuple(reversed(range(n))),tuple(range(n,2*n))]
    f.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    add(mat,v,f)
rocks=[material('LAGO_01 | Piedra '+str(i),c) for i,c in enumerate([(.31,.32,.28),(.43,.41,.35),(.23,.26,.25)])]
bark=material('LAGO_01 | Corteza',(.18,.095,.045))
leaves=[material('LAGO_01 | Hojas '+str(i),c) for i,c in enumerate([(.10,.32,.065),(.16,.43,.09),(.24,.47,.12)])]
# Irregular groups of rocks, not a uniform decorative ring.
for i in range(30):
    a=rng.choice([.5,2.2,3.6,5.1])+rng.uniform(-.35,.35)
    x,y=point(a,rng.uniform(.79,.94))
    r=rng.uniform(.14,.46)
    blob(rocks[i%3],x,y,sculpt(x,y)+r*.23,r,r*rng.uniform(.7,1.2),r*.66,8,3)
# Six trees distributed along the bank; no roots or trunks inside the water.
for i,a in enumerate([.42,1.45,2.45,3.47,4.62,5.48]):
    x,y=point(a,.95)
    z=sculpt(x,y); h=rng.uniform(2.8,4.2)
    trunk(bark,(x,y,z-.10),(x,y,z+h*.70),.12,.045)
    for j in range(3):
        b=2*pi*j/3+a; xx=x+.55*cos(b); yy=y+.55*sin(b)
        trunk(bark,(x,y,z+h*.45),(xx,yy,z+h*.76),.047,.018,6)
        blob(leaves[(i+j)%3],xx,yy,z+h*.80,.72,.73,.87,9,4)
    blob(leaves[i%3],x,y,z+h*.99,.66,.68,.77,9,4)
for i in range(18):
    a=rng.uniform(0,2*pi); x,y=point(a,rng.uniform(.87,.97))
    r=rng.uniform(.18,.37)
    blob(leaves[i%3],x,y,sculpt(x,y)+r*.40,r,r*.8,r*.65,8,3)
for name,(vs,fs) in batches.items():
    obj_mesh(name,vs,fs,bpy.data.materials[name])
# A dedicated camera for the lake, keeping the old city camera intact.
cd=bpy.data.cameras.new('LAGO_01 | Camara')
cam=bpy.data.objects.new('CAM 05 | Lago natural',cd)
col.objects.link(cam)
cam.location=(CX-20,CY-25,level+25)
cam.rotation_euler=(Vector((CX,CY,level+.5))-cam.location).to_track_quat('-Z','Y').to_euler()
cd.type='ORTHO'; cd.ortho_scale=33; cd.clip_end=500

# Commit: replace terrain data, attach lake collection, preserve all other models.
S.collection.children.link(col)
terrain.data=new
if old.users==0:
    bpy.data.meshes.remove(old)
marker=S.objects.get('LAGO_01')
if marker and marker.get('mycity_plan_type')=='LAGO':
    marker['mycity_built']=True
    marker.hide_render=True
    if bpy.context.view_layer.objects.get(marker.name):
        marker.hide_set(True)
S.camera=cam
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            space=area.spaces.active
            if space.type=='VIEW_3D':
                space.region_3d.view_perspective='CAMERA'
                space.clip_end=max(space.clip_end,500)
                space.shading.type='SOLID'
                space.shading.color_type='MATERIAL'
S['lake_01_water_z']=level
print(f'LAGO_01 construido: 6 arboles, 30 piedras, 18 arbustos; terreno {len(verts)} vertices. Guarda el archivo.')
