"""Modular industrial campus. Local Z=0 is the installation plane.
Geometry only; no smoke, animation, lights or simulations.
"""
import bpy
from math import sin, cos, pi
import random

ASSET_ID="planta_industrial"
LABEL="Planta industrial"
SIZE=(30.0,20.0)
VERSION=1

def build(collection):
    rng=random.Random(715)
    batches={}
    def mat(key,color,rough=.72,metal=0):
        name="Industrial | "+key
        m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
        m.diffuse_color=(*color,1);m.use_nodes=True
        p=m.node_tree.nodes.get("Principled BSDF")
        p.inputs["Base Color"].default_value=(*color,1)
        p.inputs["Roughness"].default_value=rough
        p.inputs["Metallic"].default_value=metal
        return m
    grass=mat("Cesped",(.32,.56,.12))
    concrete=mat("Hormigon",(.60,.65,.66))
    white=mat("Fachada clara",(.83,.86,.85))
    dark=mat("Asfalto",(.12,.16,.19))
    roof=mat("Cubierta",(.36,.44,.48))
    glass=mat("Cristales",(.09,.25,.36),.25)
    steel=mat("Acero",(.34,.43,.48),.38,.5)
    rim=mat("Interior oscuro",(.07,.11,.13))
    stripe=mat("Franja azul",(.13,.32,.51))
    green=mat("Hojas",(.22,.46,.09))
    green2=mat("Hojas claras",(.43,.64,.13))
    bark=mat("Troncos",(.23,.13,.055))
    paint=mat("Senalizacion",(.91,.85,.48))
    water=mat("Agua tecnica",(.10,.58,.63),.22)
    def add(m,v,f):
        vs,fs=batches.setdefault(m.name,([],[]));n=len(vs)
        vs.extend(v);fs.extend(tuple(n+i for i in q) for q in f)
    def box(m,x,y,z,w,d,h):
        a,b,c=w/2,d/2,h/2
        v=[(x+i,y+j,z+k) for i,j,k in [(-a,-b,-c),(a,-b,-c),(a,b,-c),(-a,b,-c),(-a,-b,c),(a,-b,c),(a,b,c),(-a,b,c)]]
        add(m,v,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
    def rings(m,x,y,profile,n=24,cap=True):
        v=[(x+r*cos(2*pi*i/n),y+r*sin(2*pi*i/n),z) for z,r in profile for i in range(n)]
        f=[]
        for j in range(len(profile)-1):
            f.extend((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for i in range(n))
        if cap:f.extend([tuple(reversed(range(n))),tuple(range((len(profile)-1)*n,len(profile)*n))])
        add(m,v,f)
    # One continuous platform; bottom at installation plane, top .35 m.
    box(concrete,0,0,.15,30,20,.30)
    box(grass,0,0,.315,29.8,19.8,.03)
    box(dark,0,-6.7,.35,29.1,3.3,.04)
    box(dark,0,-.5,.35,3.0,13.4,.04)
    for x in range(-13,15,3):box(paint,x,-6.7,.38,1.45,.075,.018)
    # Two open cooling towers with inner lining.
    for x,y in [(-9.4,4.5),(-3.5,5.3)]:
        box(concrete,x,y,.49,5.5,5.5,.28)
        prof=[(.63,2.34),(1.0,2.27),(2.1,1.88),(3.6,1.49),(5.0,1.38),(6.4,1.52),(7.5,1.80)]
        rings(white,x,y,prof,32,False)
        rings(rim,x,y,[(7.5,1.65),(6.3,1.37),(5.4,1.25)],32,False)
        rings(steel,x,y,[(7.5,1.80),(7.5,1.65)],32,False)
    # Main industrial hall and administrative tower.
    box(concrete,7.6,3.6,2.35,11.6,9.7,4)
    box(white,7.6,3.6,4.45,12.0,10.1,.30)
    box(roof,7.6,3.6,4.64,11.7,9.8,.12)
    for x in [3,5,7,9,11,13]:
        for z in [1.6,3.05]:
            box(glass,x,-1.27,z,1.25,.06,.82)
    for y in [.2,2.2,4.2,6.2,8.2]:
        box(glass,13.43,y,2.45,.07,1.22,1.2)
    for x in [4,7.5,11]:
        box(steel,x,4,4.9,2.1,4,.45)
        for y in [2.5,3.4,4.3,5.2]:box(rim,x,y,5.14,1.55,.12,.045)
    box(white,10.8,5.5,5.2,4.4,5.4,9.7)
    box(roof,10.8,5.5,10.15,4.6,5.6,.25)
    for j in range(6):
        z=1.25+1.44*j
        for x in [9.45,10.8,12.15]:box(glass,x,2.76,z,.75,.07,.84)
        for y in [4,5.5,7]:box(glass,13.03,y,z,.07,.83,.84)
    # Exhaust stacks and blue bands.
    for x,y,h,r in [(5.4,7.4,12.0,.65),(2.8,6.7,9.2,.48),(-12.4,-3.7,6.1,.32)]:
        rings(concrete,x,y,[(.35,r*1.4),(.8,r),(h,r*.78)],20,False)
        for z in [h-2.0,h-.85]:
            rings(stripe,x,y,[(z,r*.88),(z+.38,r*.88)],20,False)
        rings(rim,x,y,[(h,r*.78),(h+.04,r*.55)],20,False)
    # Water treatment tanks, workshop and pipe racks.
    for x,y in [(-6.2,-3.6),(-3.4,-3.6)]:
        rings(white,x,y,[(.35,1.18),(2.05,1.18),(2.35,.94)],24)
        rings(steel,x,y,[(2.36,.82),(2.40,.82)],24)
    box(concrete,-10.6,-2.8,1.35,4.6,4.2,2.0)
    box(roof,-10.6,-2.8,2.45,4.9,4.5,.20)
    for x in [-12,-10.6,-9.2]:box(glass,x,-4.93,1.48,.8,.07,.9)
    for x in [-12,-9,-6,-3]:
        for y in [-.4,1.0]:box(steel,x,y,1.45,.17,.17,2.2)
        box(steel,x,.3,2.58,.22,1.65,.16)
    for y in [-.2,.4,.95]:box(steel,-7.5,y,2.78,10,.17,.17)
    box(concrete,-11.7,8.0,.42,5.1,2.5,.18)
    box(water,-11.7,8.0,.53,4.7,2.1,.045)
    # Green buffers, entrance and parking.
    for i,(x,y) in enumerate([(-13.7,8.6),(-7.1,8.6),(-.7,8.7),(14,8.5),(14,-3.6),(-13.7,-8.9),(-9,-8.9),(-3.8,-8.9),(4,-8.9),(9,-8.9),(13.7,-8.9)]):
        h=rng.uniform(1.3,2.1)
        rings(bark,x,y,[(.34,.075),(.34+h*.65,.045)],7)
        rings(green if i%2 else green2,x,y,[(.34+h*.30,.17),(.34+h*.48,.48),(.34+h*.75,.54),(.34+h,.30),(.34+h*1.17,.02)],9)
    box(concrete,10,-3.7,.42,6.8,2.3,.14)
    for x in [7.4,9.1,10.8,12.5]:box(paint,x,-3.7,.50,.06,2.0,.02)
    for name,(v,f) in batches.items():
        mesh=bpy.data.meshes.new(name+" | Plantilla")
        mesh.from_pydata(v,[],f);mesh.update()
        mesh.materials.append(bpy.data.materials[name])
        ob=bpy.data.objects.new(name,mesh);collection.objects.link(ob)
