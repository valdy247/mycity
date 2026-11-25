# -*- coding: utf-8 -*-
"""My City 01 | Blender 4.2–5.x | Escena estática editable.
Puertas: selecciona VAN | CONTROL en Outliner > Object Properties > Custom Properties.
Cada control va de 0 (cerrado) a 1 (abierto). No hay fotogramas animados.
Reemplaza la escena activa. Guarda el proyecto anterior antes de ejecutarlo.
Vista Solid ligera; Rendered opcional. Frente = -Y, altura = Z.
"""
import math, sys
from math import sin, cos, pi, radians, sqrt
from pathlib import Path

# Coordenadas verificables de ruedas y bisagras, sin depender de Blender.
WHEEL_Y=(-1.64,1.63); WHEEL_X=(-1.00,1.00); WHEEL_Z=.43
R=.43; ARCH=.51; SIDE=1.035

def local(p, pivot): return tuple(a-b for a,b in zip(p,pivot))
def swing(p,pivot,deg):
    x,y,z=local(p,pivot); a=radians(deg)
    return (pivot[0]+x*cos(a)-y*sin(a),pivot[1]+x*sin(a)+y*cos(a),pivot[2]+z)

def test():
    for s in (-1,1):
        p=(s*SIDE,-.42,1.3); h=(s*SIDE,-1.72,1.1)
        assert abs(swing(p,h,0)[0]-p[0])<1e-9
        assert s*swing(p,h,-s*67)[0]>1.9
        q=(0,2.52,1.35); h=(s*SIDE,2.52,1.2)
        assert swing(q,h,-s*102)[1]>3.4
    assert abs(WHEEL_Z-R)<1e-9 and ARCH>R
    print('OK: ruedas, altura al suelo y sentido de bisagras.')
test()
if '--test' in sys.argv: sys.exit(0)

import bpy
from mathutils import Vector
S=bpy.context.scene
S.name="My City | Distrito 01"
if bpy.context.object and bpy.context.object.mode!='OBJECT': bpy.ops.object.mode_set(mode='OBJECT')
for o in list(S.objects): bpy.data.objects.remove(o,do_unlink=True)
if S.sequence_editor: S.sequence_editor_clear()
S.timeline_markers.clear()
for data in list(bpy.data.meshes):
    if data.users == 0: bpy.data.meshes.remove(data)
S.frame_start=1; S.frame_end=1; S.render.fps=24; S.render.fps_base=1
S.render.resolution_x=960; S.render.resolution_y=540; S.render.resolution_percentage=100
S.render.engine='BLENDER_EEVEE'; S.render.film_transparent=False
S.view_settings.view_transform='AgX'; S.view_settings.exposure=0; S.view_settings.gamma=1
if hasattr(S,'eevee'):
    if hasattr(S.eevee,'use_raytracing'): S.eevee.use_raytracing=False
    for a in ('taa_render_samples','taa_samples'):
        if hasattr(S.eevee,a): setattr(S.eevee,a,16)
S.world=bpy.data.worlds.new('Estudio Van'); S.world.use_nodes=True
S.world.node_tree.nodes['Background'].inputs[0].default_value=(.37,.49,.62,1)
S.world.node_tree.nodes['Background'].inputs[1].default_value=.40

def mat(n,c,r=.35,m=0,coat=0):
    v=bpy.data.materials.new(n); v.diffuse_color=(*c,1); v.use_nodes=True
    p=v.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*c,1); p.inputs['Roughness'].default_value=r; p.inputs['Metallic'].default_value=m
    if 'Coat Weight' in p.inputs: p.inputs['Coat Weight'].default_value=coat
    return v
M={
 'paint':mat('Blanco perla',(.86,.88,.90),.29,.07,.32),
 'black':mat('Moldura grafito',(.025,.032,.042),.43),
 'rubber':mat('Caucho',(.018,.019,.022),.8),
 'metal':mat('Aluminio',(.58,.62,.67),.32,.72),
 'glass':mat('Cristal ahumado',(.085,.17,.23),.16,.10,.15),
 'seat':mat('Tapicería',(.11,.14,.18),.72),
 'cloth':mat('Tela gris',(.25,.29,.34),.8),
 'floor':mat('Piso interior',(.07,.08,.095),.8),
 'red':mat('Piloto rojo',(.65,.018,.028),.18,0,.2),
 'lamp':mat('Faro',(.82,.91,1),.15,.25,.3),
 'amber':mat('Intermitente',(.95,.29,.035),.25),
 'ground':mat('Estudio',(.12,.15,.19),.8),
 'screen':mat('Pantalla',(.025,.10,.18),.2),
 'chrome':mat('Cromo satinado',(.64,.69,.74),.23,.85),
 'tread':mat('Banda caucho',(.028,.03,.035),.82),
 'leather':mat('Tapicería gris cálido',(.23,.20,.18),.64),
 'stitch':mat('Costura',(.49,.45,.39),.85),
 'carpet':mat('Alfombra',(.045,.052,.06),.93),
 'led':mat('LED blanco',(.78,.90,1),.21),
 'blackgloss':mat('Negro piano',(.012,.018,.025),.22,0,.22),
 'gauge':mat('Instrumentos claros',(.65,.80,.90),.55),
}
# Subtle light signatures, not extra scene lights.
for key,col,strength in [('led',(.69,.84,1.0),.45),('gauge',(.48,.73,.92),.18)]:
    shader=M[key].node_tree.nodes.get('Principled BSDF')
    if 'Emission Color' in shader.inputs:
        shader.inputs['Emission Color'].default_value=(*col,1)
        shader.inputs['Emission Strength'].default_value=strength
# Glass is actual transparent shader for Eevee; in Solid it remains tinted.
g=M['glass']; nt=g.node_tree; p=nt.nodes.get('Principled BSDF'); out=nt.nodes.get('Material Output'); tr=nt.nodes.new('ShaderNodeBsdfTransparent'); mix=nt.nodes.new('ShaderNodeMixShader'); mix.inputs[0].default_value=.70; nt.links.new(p.outputs[0],mix.inputs[1]); nt.links.new(tr.outputs[0],mix.inputs[2]); nt.links.new(mix.outputs[0],out.inputs['Surface'])
if hasattr(g,'surface_render_method'): g.surface_render_method='DITHERED'
elif hasattr(g,'blend_method'): g.blend_method='HASHED'

mesh_cache={}; objects=[]
def mesh(n,verts,faces,material):
    d=bpy.data.meshes.new(n); d.from_pydata(verts,[],faces); d.update(); d.materials.append(M[material]); return d

def obj(n,d,loc=(0,0,0),parent=None):
    o=bpy.data.objects.new(n,d); S.collection.objects.link(o); o.parent=parent; o.location=loc; objects.append(o); return o

def empty(n,loc=(0,0,0)): return obj(n,None,loc)

def bevel(o,w):
    if w:
        b=o.modifiers.new('Bordes suaves','BEVEL'); b.width=w; b.segments=2
        if hasattr(b,'harden_normals'): b.harden_normals=True
    return o

def box(n,p,dim,m,parent=None,b=.025):
    key=('box',tuple(dim),m)
    if key not in mesh_cache:
        x,y,z=[i/2 for i in dim]; v=[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]; f=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]; mesh_cache[key]=mesh(n,v,f,m)
    return bevel(obj(n,mesh_cache[key],p,parent),b)

def panel(n,points,axis,level,thick,m,parent=None,pivot=(0,0,0),b=.018):
    # polygon in the two other axes. Mesh vertices stored in parent's local space.
    inds=[i for i in range(3) if i!=axis]; v=[]
    for a in (level-thick/2,level+thick/2):
        for u,w in points:
            q=[0.,0.,0.]; q[axis]=a; q[inds[0]]=u; q[inds[1]]=w; v.append(local(q,pivot))
    N=len(points); f=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]
    # ensure outward normals, independent of which axis is extruded
    p0,p1,p2=[Vector(v[i]) for i in (N,N+1,N+2)]; normal=(p1-p0).cross(p2-p1)
    # use signed polygon area to handle concave profiles correctly
    area=sum(points[i][0]*points[(i+1)%N][1]-points[(i+1)%N][0]*points[i][1] for i in range(N))
    if area*((-1)**axis)<0: f=[tuple(reversed(face)) for face in f]
    return bevel(obj(n,mesh(n,v,f,m),(0,0,0),parent),b)

def beam(n,a,b,wide,deep,m,parent=None,pivot=(0,0,0)):
    a,b=Vector(local(a,pivot)),Vector(local(b,pivot)); d=b-a
    o=box(n,(a+b)/2,(wide,deep,d.length),m,parent,min(wide,deep)*.22); o.rotation_euler=d.to_track_quat('Z','Y').to_euler(); return o

def cylinder(n,p,r,h,m,axis='Z',N=32,parent=None):
    key=('cyl',r,h,m,N)
    if key not in mesh_cache:
        v=[(r*cos(2*pi*i/N),r*sin(2*pi*i/N),z) for z in (-h/2,h/2) for i in range(N)]; f=[tuple(reversed(range(N))),tuple(range(N,2*N))]+[(i,(i+1)%N,(i+1)%N+N,i+N) for i in range(N)]; d=mesh(n,v,f,m)
        for q in list(d.polygons)[2:]: q.use_smooth=True
        mesh_cache[key]=d
    o=bevel(obj(n,mesh_cache[key],p,parent),.012)
    if axis=='X': o.rotation_euler.y=pi/2
    if axis=='Y': o.rotation_euler.x=pi/2
    return o

def ring(n,p,major,minor,m,axis='Z',N=32,K=8):
    v=[((major+minor*cos(2*pi*j/K))*cos(2*pi*i/N),(major+minor*cos(2*pi*j/K))*sin(2*pi*i/N),minor*sin(2*pi*j/K)) for i in range(N) for j in range(K)]
    f=[(i*K+j,((i+1)%N)*K+j,((i+1)%N)*K+(j+1)%K,i*K+(j+1)%K) for i in range(N) for j in range(K)]
    key=('ring',major,minor,m,N,K)
    if key not in mesh_cache:
        d=mesh(n,v,f,m)
        for q in d.polygons:q.use_smooth=True
        mesh_cache[key]=d
    o=obj(n,mesh_cache[key],p)
    if axis=='X': o.rotation_euler.y=pi/2
    if axis=='Y': o.rotation_euler.x=pi/2
    return o

# Lightweight custom mesh for curved vehicle sheet metal; cross sections in Y.
def loft(n,sections,m):
    verts=[(x,y,z) for y,outline in sections for x,z in outline]
    k=len(sections[0][1]); count=len(sections)
    faces=[tuple(reversed(range(k))),tuple((count-1)*k+j for j in range(k))]
    for i in range(count-1):
        for j in range(k): faces.append((i*k+j,i*k+(j+1)%k,(i+1)*k+(j+1)%k,(i+1)*k+j))
    # Cross section is counterclockwise viewed along -Y; recalc via signed volume.
    volume=0
    for face in faces:
        a=Vector(verts[face[0]])
        for j in range(1,len(face)-1): volume+=a.dot(Vector(verts[face[j]]).cross(Vector(verts[face[j+1]])))
    if volume<0: faces=[tuple(reversed(f)) for f in faces]
    return bevel(obj(n,mesh(n,verts,faces,m)),.022)

def shell_section(w,z0,z1,r=.13):
    return [(-w+r,z0),(w-r,z0),(w,z0+r),(w,z1-r),(w-r,z1),(-w+r,z1),(-w,z1-r),(-w,z0+r)]

# Floor and underframe are narrow at wheels. No solid block inside the cabin.
box('Chasis',(0,0,.56),(1.40,4.75,.22),'black',b=.055)
box('Piso de cabina',(0,.07,.755),(1.92,4.76,.14),'floor',b=.025)
loft('Capó moldeado',[(-2.60,shell_section(.93,.72,1.21,.09)),(-2.54,shell_section(.98,.72,1.24,.10)),(-2.38,shell_section(1.00,.73,1.25,.13)),(-2.08,shell_section(1.02,.79,1.25,.13)),(-1.98,shell_section(.99,.85,1.28,.12))],'paint')
# Sculpted lower bumper with contrasting lower grille.
loft('Defensa curva',[(-2.73,shell_section(.87,.48,.68,.065)),(-2.70,shell_section(.96,.46,.74,.08)),(-2.64,shell_section(1.02,.44,.77,.10)),(-2.52,shell_section(1.04,.46,.80,.10))],'black')
box('Parachoques trasero',(0,2.55,.58),(2.04,.22,.23),'black',b=.06)
# Continuous lower side skirt with genuine curved wheel openings, split in segments.
for s in (-1,1):
    x=s*SIDE
    for j,(lo,hi) in enumerate([(-2.51,-2.15),(-1.13,1.12),(2.14,2.52)]):
        panel('Faldón fijo',[(lo,.53),(hi,.53),(hi,.91),(lo,.91)],0,x,.10,'paint',b=.027)
    for y in WHEEL_Y:
        arc=[(y+ARCH*cos(pi-i*pi/16),WHEEL_Z+ARCH*sin(pi-i*pi/16)) for i in range(17)]
        # only the band ABOVE arch, not over the wheel itself
        panel('Aleta curva',arc+[(y+ARCH,.98),(y-ARCH,.98)],0,x,.10,'paint',b=.010)
        # thin black wheel trim follows the actual opening
        # A single continuous trim per wheel, replacing twelve separate objects.
        inner=[(y+ARCH*cos(pi-i*pi/24),WHEEL_Z+ARCH*sin(pi-i*pi/24)) for i in range(25)]
        outer=[(y+(ARCH+.045)*cos(i*pi/24),WHEEL_Z+(ARCH+.045)*sin(i*pi/24)) for i in range(25)]
        panel('Moldura continua paso rueda',inner+outer,0,s*1.09,.027,'black',b=.004)
# Roof and rear pillars, front angled pillars.
loft('Techo aerodinámico',[(-1.49,shell_section(.94,2.15,2.29,.045)),(-1.40,shell_section(.99,2.15,2.34,.07)),(-1.29,shell_section(1.02,2.16,2.38,.09)),(2.25,shell_section(1.02,2.16,2.38,.09)),(2.38,shell_section(1.00,2.15,2.34,.07)),(2.47,shell_section(.97,2.15,2.28,.045))],'paint')
for x in (-.71,.71):
    box('Canal longitudinal techo',(x,.48,2.385),(.045,3.30,.025),'black',b=.01)
box('Antena corta',(0,1.65,2.42),(.075,.20,.075),'black',b=.03)
for s in (-1,1):
    x=s*.99
    beam('Pilar A',(x,-2.03,1.18),(x,-1.43,2.19),.13,.13,'paint')
    beam('Pilar B',(x,-.36,.92),(x,-.36,2.20),.10,.12,'paint')
    beam('Pilar C',(x,1.23,.92),(x,1.23,2.20),.11,.12,'paint')
    beam('Pilar D',(x,2.45,.80),(x,2.45,2.20),.13,.13,'paint')
    # fixed rear side panel and glass
    panel('Cuarto trasero',[(1.29,.96),(2.45,.96),(2.45,1.49),(1.29,1.49)],0,s*SIDE,.11,'paint')
    panel('Cristal cuarto trasero',[(1.30,1.53),(2.39,1.53),(2.39,2.10),(1.30,2.10)],0,s*SIDE,.045,'glass',b=.02)
    beam('Marco alto',(x,1.24,2.16),(x,2.45,2.16),.12,.09,'paint')
    panel('Aleta delantera',[(-2.47,.96),(-1.76,.96),(-1.76,1.15),(-2.08,1.23),(-2.47,1.17)],0,s*SIDE,.10,'paint')
# Sloped windshield: genuinely slanted slab, not a cube filling the cabin.
v=[(-.94,-2.04,1.25),(.94,-2.04,1.25),(.94,-1.45,2.16),(-.94,-1.45,2.16)]
wind=obj('Parabrisas',mesh('Parabrisas',v,[(0,1,2,3)],'glass')); sol=wind.modifiers.new('Grosor cristal','SOLIDIFY'); sol.thickness=.024
for x in (-.47,.47): beam('Limpiaparabrisas',(x-.27,-2.06,1.28),(x+.25,-1.98,1.40),.026,.026,'black')
box('Travesaño trasero alto',(0,2.47,2.18),(1.96,.14,.13),'paint',b=.03)
box('Umbral carga',(0,2.46,.83),(1.92,.17,.13),'black',b=.02)

# Side doors: geometry in local coordinates relative to real hinge, or slider origin.
front_doors=[]; rear_doors=[]
for s in (-1,1):
    h=(s*SIDE,-1.72,1.10); d=empty('Bisagra puerta delantera '+str(s),h); front_doors.append((s,d))
    x=s*SIDE
    panel('Puerta delantera', [(-1.71,.96),(-.43,.96),(-.43,1.52),(-1.71,1.52)],0,x,.12,'paint',d,h)
    pts=[(-1.71,1.53),(-1.38,2.11),(-.43,2.11),(-.43,1.53)]
    panel('Cristal puerta',pts,0,x,.035,'glass',d,h)
    for a,b in zip(pts,pts[1:]+pts[:1]): beam('Marco puerta',(x,*a),(x,*b),.075,.075,'paint',d,h)
    box('Manija delantera',local((s*1.108,-.63,1.43),h),(.035,.18,.055),'black',d,.012)
    box('Panel interior puerta',local((s*.945,-1.04,1.22),h),(.055,1.13,.44),'black',d,.04)
    box('Apoyabrazos puerta',local((s*.89,-.97,1.35),h),(.12,.64,.075),'seat',d,.02)
    beam('Soporte espejo',(s*1.01,-1.59,1.58),(s*1.23,-1.59,1.58),.065,.065,'black',d,h)
    box('Espejo',local((s*1.25,-1.59,1.65),h),(.19,.13,.22),'black',d,.045)
    box('Cristal espejo',local((s*1.25,-1.51,1.65),h),(.15,.018,.17),'metal',d,.015)
# Passenger sliding door, actual aperture on visible side. Opposite side fixed matching panel.
slider=empty('Puerta lateral corredera',(0,0,0))
for s in (-1,1):
    x=s*SIDE; par=slider if s==-1 else None
    panel('Puerta lateral', [(-.29,.96),(1.17,.96),(1.17,1.51),(-.29,1.51)],0,x,.12,'paint',par)
    pts=[(-.29,1.55),(1.17,1.55),(1.17,2.11),(-.29,2.11)]
    panel('Ventana lateral',pts,0,x,.035,'glass',par)
    for a,b in zip(pts,pts[1:]+pts[:1]): beam('Marco lateral',(x,*a),(x,*b),.075,.075,'paint',par)
    box('Manija lateral',(s*1.108,-.10,1.43),(.036,.18,.055),'black',par,.012)
    box('Guía corredera',(s*1.10,1.75,1.47),(.018,1.15,.035),'black',b=.005)
# Rear twin swing doors, no rear wall covering the opening.
for s in (-1,1):
    h=(s*SIDE,2.52,1.1); d=empty('Bisagra portón '+str(s),h); rear_doors.append((s,d)); xa,xb=sorted((s*.99,s*.018))
    panel('Portón inferior',[(xa,.91),(xb,.91),(xb,1.53),(xa,1.53)],1,2.52,.12,'paint',d,h)
    pts=[(xa+.035,1.57),(xb-.035,1.57),(xb-.035,2.10),(xa+.035,2.10)]
    panel('Cristal portón',pts,1,2.52,.035,'glass',d,h)
    for a,b in zip(pts,pts[1:]+pts[:1]): beam('Marco portón',(a[0],2.52,a[1]),(b[0],2.52,b[1]),.08,.08,'paint',d,h)
    box('Panel interior portón',local((s*.50,2.435,1.22),h),(.87,.04,.46),'black',d,.025)
    box('Manija portón',local((s*.20,2.60,1.44),h),(.17,.035,.06),'black',d,.012)

# Wheels: cylinder axis X, exact world locations (no double parent translation).
for s in (-1,1):
    for y in WHEEL_Y:
        p=(s*1.00,y,WHEEL_Z)
        cylinder('Neumático',p,R,.29,'rubber','X',40)
        cylinder('Llanta aluminio',(s*1.15,y,WHEEL_Z),.255,.045,'metal','X',32)
        cylinder('Buje',(s*1.18,y,WHEEL_Z),.075,.045,'black','X',20)
        for j in range(5):
            a=j*2*pi/5; dy,dz=cos(a),sin(a)
            beam('Radio',(s*1.185,y+dy*.075,WHEEL_Z+dz*.075),(s*1.185,y+dy*.217,WHEEL_Z+dz*.217),.045,.045,'black')
        ring('Flanco de neumático',(s*1.155,y,WHEEL_Z),.34,.018,'rubber','X',32,6)
# Front fascia and lamps
box('Parrilla',(0,-2.585,.92),(1.11,.05,.27),'black',b=.035)
for z in (.84,.91,.98): box('Línea parrilla',(0,-2.616,z),(.99,.018,.022),'metal',b=.006)
for s in (-1,1):
    box('Faro',(s*.79,-2.57,1.12),(.39,.10,.20),'lamp',b=.055)
    box('Intermitente',(s*.93,-2.59,1.11),(.10,.025,.12),'amber',b=.015)
    box('Piloto trasero',(s*1.065,2.54,1.51),(.13,.12,.47),'red',b=.035)
    box('Luz reversa',(s*1.065,2.61,1.44),(.095,.018,.09),'lamp',b=.008)
box('Placa delantera',(0,-2.70,.62),(.36,.024,.13),'lamp',b=.008)
box('Placa trasera',(0,2.68,.57),(.36,.024,.13),'lamp',b=.008)
# Interior: open cabin, seats oriented towards front, rear cargo bay clear.
for s in (-1,1):
    x=s*.48; y=-.97
    box('Base asiento',(x,y,.95),(.47,.49,.15),'black',b=.035)
    box('Cojín',(x,y,1.08),(.50,.53,.17),'cloth',b=.075)
    o=box('Respaldo',(x,y+.245,1.40),(.48,.17,.57),'seat',b=.08); o.rotation_euler.x=-.10
    box('Cabecera',(x,y+.25,1.76),(.29,.18,.19),'cloth',b=.06)
    for dx in (-.13,.13): cylinder('Guía cabecera',(x+dx,y+.25,1.67),.017,.13,'metal',N=12)
box('Tablero',(0,-1.76,1.33),(1.87,.42,.24),'black',b=.08)
box('Pantalla central',(0,-1.52,1.43),(.32,.055,.18),'screen',b=.02)
for x in (-.38,.38): box('Salida de aire',(x,-1.52,1.43),(.23,.035,.065),'metal',b=.012)
ring('Volante',(-.48,-1.48,1.49),.145,.025,'black','Y',32,8)
for x in (-.12,.12): beam('Radio volante',(-.48,-1.48,1.49),(-.48+x,-1.48,1.49-.08),.028,.028,'black')
beam('Columna dirección',(-.48,-1.48,1.49),(-.48,-1.73,1.25),.055,.055,'metal')
box('Consola',(0,-.98,1.02),(.26,.60,.26),'black',b=.05)
box('Banca segunda fila',(0,.42,1.02),(1.48,.54,.18),'cloth',b=.07)
box('Respaldo banca',(0,.67,1.36),(1.48,.17,.58),'seat',b=.065)
for x in (-.49,0,.49): box('Cabecera banca',(x,.67,1.74),(.25,.14,.17),'cloth',b=.04)
for x in (-.72,.72): box('Paso rueda interior',(x,1.63,.92),(.40,.95,.27),'floor',b=.09)
for x in (-.40,0,.40): box('Guía piso de carga',(x,1.66,.835),(.035,1.35,.017),'metal',b=.003)

# Fine exterior and interior details. Mesh count stays small: no textures, no subdivision.
# Black window seals, rocker moldings, mirror indicator, door handles with backing.
for s,d in front_doors:
    h=tuple(d.location); x=s*1.063
    pts=[(-1.66,1.57),(-1.36,2.075),(-.47,2.075),(-.47,1.57)]
    for a,b in zip(pts,pts[1:]+pts[:1]): beam('Junta goma cristal',(x,*a),(x,*b),.023,.023,'black',d,h)
    box('Moldura puerta',local((s*1.103,-1.06,1.05),h),(.024,1.10,.075),'black',d,.009)
    box('Tirador satinado',local((s*1.132,-.63,1.44),h),(.026,.13,.024),'chrome',d,.008)
    box('Indicador espejo',local((s*1.25,-1.664,1.64),h),(.125,.013,.025),'led',d,.006)
    box('Inserto acolchado',local((s*.902,-1.07,1.22),h),(.03,.83,.19),'leather',d,.025)
    box('Botones elevalunas',local((s*.867,-1.18,1.39),h),(.07,.15,.018),'blackgloss',d,.006)
    # speaker cover with subtle perforation pattern, carried by the door
    cylinder('Altavoz puerta',local((s*.901,-1.44,1.10),h),.09,.018,'black','X',24,d)
for s in (-1,1):
    par=slider if s==-1 else None
    x=s*1.063; pts=[(-.25,1.59),(1.13,1.59),(1.13,2.07),(-.25,2.07)]
    for a,b in zip(pts,pts[1:]+pts[:1]): beam('Junta ventana lateral',(x,*a),(x,*b),.024,.024,'black',par)
    box('Moldura puerta corredera',(s*1.103,.44,1.05),(.024,1.30,.075),'black',par,.009)
    box('Tirador lateral satinado',(s*1.132,-.10,1.44),(.025,.13,.025),'chrome',par,.008)
    box('Panel interior corredera',(s*.949,.44,1.21),(.045,1.23,.43),'seat',par,.025)
    box('Inserto lateral',(s*.917,.44,1.24),(.023,.96,.17),'leather',par,.018)
    box('Moldura aleta trasera',(s*1.105,1.85,1.05),(.025,1.05,.075),'black',b=.009)
    box('Moldura delantera',(s*1.105,-2.11,1.05),(.022,.49,.075),'black',b=.007)
    box('Reflector lateral',(s*1.113,2.27,.82),(.023,.15,.05),'red',b=.008)
for s,d in rear_doors:
    h=tuple(d.location); xa,xb=sorted((s*.99,s*.018))
    pts=[(xa+.06,1.60),(xb-.06,1.60),(xb-.06,2.07),(xa+.06,2.07)]
    for a,b in zip(pts,pts[1:]+pts[:1]): beam('Junta portón',(a[0],2.557,a[1]),(b[0],2.557,b[1]),.024,.024,'black',d,h)
    box('Inserto portón',local((s*.50,2.406,1.22),h),(.65,.025,.22),'leather',d,.023)
    box('Bisagra exterior superior',local((s*.96,2.61,1.92),h),(.085,.035,.11),'black',d,.009)
    box('Bisagra exterior inferior',local((s*.96,2.61,1.13),h),(.085,.035,.11),'black',d,.009)
# Grille, air intake and more defined headlight optics.
box('Entrada aire inferior',(0,-2.738,.57),(.91,.016,.11),'blackgloss',b=.018)
for x in (-.39,-.26,-.13,0,.13,.26,.39): box('Aleta entrada aire',(x,-2.752,.57),(.018,.012,.086),'black',b=.003)
for s in (-1,1):
    box('Carcasa faro',(s*.79,-2.630,1.116),(.42,.025,.205),'blackgloss',b=.035)
    # rectangular slim DRL and individual projector lenses on actual front face
    box('Tira LED diurna',(s*.79,-2.650,1.186),(.35,.022,.028),'led',b=.010)
    for dx in (-.075,.075):
        cylinder('Aro proyector',(s*.79+dx,-2.65,1.105),.058,.024,'chrome','Y',24)
        cylinder('Lente proyector',(s*.79+dx,-2.667,1.105),.044,.020,'lamp','Y',24)
    box('Luz antiniebla',(s*.76,-2.70,.66),(.19,.028,.065),'lamp',b=.025)
    box('Firma luminosa trasera',(s*1.065,2.625,1.64),(.085,.025,.17),'red',b=.012)
    box('Detalle piloto trasero',(s*1.065,2.625,1.37),(.085,.020,.030),'red',b=.006)
box('Tercera luz de freno',(0,2.56,2.24),(.44,.035,.04),'red',b=.012)
box('Emblema frontal',(0,-2.644,1.02),(.16,.023,.045),'chrome',b=.012)
# Wheels use independent concentric geometry. Extra lugs and tread bands share meshes.
for s in (-1,1):
    for y in WHEEL_Y:
        for radius in (.273,.315,.395): ring('Anillo rueda',(s*1.16,y,WHEEL_Z),radius,.008,'chrome' if radius==.273 else 'tread','X',32,6)
        for j in range(5):
            a=2*pi*j/5+.35
            cylinder('Tuerca rueda',(s*1.208,y+.115*cos(a),WHEEL_Z+.115*sin(a)),.021,.022,'chrome','X',12)
        cylinder('Centro llanta',(s*1.212,y,WHEEL_Z),.055,.020,'chrome','X',24)
# Interior detail without thousands of objects: seat inserts, belts, buttons, mats.
for x in (-.48,.48):
    box('Inserto asiento',(x,-.97,1.175),(.30,.34,.032),'leather',b=.014)
    box('Inserto respaldo',(x,-.827,1.40),(.30,.024,.37),'leather',b=.025)
    for dx in (-.12,.12): box('Costura cojín',(x+dx,-.97,1.190),(.009,.28,.006),'stitch',b=.002)
    box('Alfombrilla',(x,-1.49,.837),(.43,.45,.025),'carpet',b=.035)
    box('Hebilla cinturón',(x+(.23 if x<0 else -.23),-.87,1.01),(.055,.075,.12),'black',b=.015)
    box('Botón hebilla',(x+(.23 if x<0 else -.23),-.87,1.075),(.042,.050,.012),'red',b=.004)
box('Instrumentación',(-.48,-1.545,1.435),(.35,.065,.14),'blackgloss',b=.028)
for x in (-.56,-.40):
    cylinder('Indicador tablero',(x,-1.497,1.435),.052,.014,'chrome','Y',24)
    cylinder('Carátula instrumento',(x,-1.487,1.435),.041,.013,'screen','Y',24)
for x in (-.11,0,.11): cylinder('Control climatización',(x,-1.527,1.29),.030,.022,'chrome','Y',16)
box('Palanca cambio',(0,-1.04,1.19),(.042,.042,.12),'chrome',b=.01)
box('Pomo cambio',(0,-1.04,1.26),(.08,.085,.065),'black',b=.022)
for x in (-.49,0,.49):
    box('Inserto banca',(x,.42,1.12),(.37,.38,.025),'leather',b=.022)
    box('Inserto respaldo banca',(x,.57,1.36),(.35,.024,.38),'leather',b=.022)
for x in (-.60,.60):
    box('Panel carga interior',(x*1.43,1.90,1.25),(.065,.66,.38),'seat',b=.03)
    box('Anclaje carga',(x,2.16,.847),(.12,.10,.024),'chrome',b=.012)
box('Luz techo cabina',(0,-.78,2.14),(.30,.15,.025),'led',b=.02)
box('Luz techo carga',(0,1.67,2.14),(.30,.15,.025),'led',b=.02)

# V5: extra visible detail, using the same lightweight primitives.
# A real windshield rubber surround (front-facing surface).
for a,b in zip([(-.94,-2.055,1.25),(.94,-2.055,1.25),(.94,-1.465,2.16),(-.94,-1.465,2.16)],
               [(.94,-2.055,1.25),(.94,-1.465,2.16),(-.94,-1.465,2.16),(-.94,-2.055,1.25)]):
    beam('Junta parabrisas',a,b,.033,.033,'black')
# Two fine front bumper accents and clearer lamp signature.
for s in (-1,1):
    box('Detalle defensa',(s*.65,-2.724,.59),(.27,.026,.045),'chrome',b=.012)
    box('Borde óptica',(s*.79,-2.655,1.046),(.30,.016,.015),'chrome',b=.005)
    # Seat side bolsters have rounded contours, not extra subdivisions.
    x=s*.48
    for dx in (-.19,.19):
        box('Apoyo lateral cojín',(x+dx,-.97,1.17),(.085,.43,.10),'seat',b=.04)
        o=box('Apoyo lumbar lateral',(x+dx,-.826,1.40),(.075,.07,.43),'seat',b=.031)
        o.rotation_euler.x=-.10
    # Pedals face the driver's footwell; only the left-hand drive position.
    if s==-1:
        for dx in (-.095,.065):
            o=box('Pedal', (x+dx,-1.69,.94),(.085,.042,.15),'rubber',b=.014)
            o.rotation_euler.x=-.28
    # Small fixed load-floor runners.
    box('Umbral puerta interior',(s*.91,.38,.845),(.075,1.30,.027),'metal',b=.008)
# Dashboard graphic ticks, screen UI made of geometry (no image textures).
for x in (-.56,-.40):
    for dx,dz in [(-.023,.017),(0,.029),(.023,.017)]:
        box('Marca instrumento',(x+dx,-1.477,1.435+dz),(.007,.004,.012),'gauge',b=.001)
    beam('Aguja indicador',(x,-1.475,1.435),(x+.018,-1.475,1.454),.006,.006,'amber')
for z,w in [(1.472,.21),(1.443,.25),(1.414,.15)]:
    box('Interfaz pantalla',(0,-1.488,z),(w,.006,.012),'gauge',b=.002)
# Two grab handles in the rear cabin, out of the door path.
for x in (-.83,.83):
    box('Asidero techo',(x,.42,2.09),(.055,.26,.045),'black',b=.018)

# Editable asset collections and door controls: drivers, no timeline keyframes.
def collection(name):
    c=bpy.data.collections.new(name); S.collection.children.link(c); return c

def move_to(o,c):
    if c not in o.users_collection: c.objects.link(o)
    for old in list(o.users_collection):
        if old!=c: old.objects.unlink(o)
    return o

van_collection=collection('01 | VAN - interactiva')
van_parts=list(objects)
van_root=move_to(empty('VAN | CONTROL'),van_collection)
van_root.empty_display_type='PLAIN_AXES'; van_root.empty_display_size=.5
for o in van_parts:
    if o.parent is None: o.parent=van_root
    move_to(o,van_collection)

def control(name,description):
    van_root[name]=0.0
    van_root.id_properties_ui(name).update(min=0.0,max=1.0,soft_min=0.0,soft_max=1.0,description=description)

def drive(o,path,index,prop,expression):
    d=o.driver_add(path,index).driver; d.type='SCRIPTED'; v=d.variables.new(); v.name='v'; v.type='SINGLE_PROP'; v.targets[0].id=van_root; v.targets[0].data_path='["'+prop+'"]'; d.expression=expression
for s,o in front_doors:
    name='01 Delantera izquierda' if s==-1 else '02 Delantera derecha'
    control(name,'0 cerrada, 1 abierta a 67 grados'); drive(o,'rotation_euler',2,name,f'{radians(-s*67):.12f}*v')
for s,o in rear_doors:
    name='04 Portón izquierdo' if s==-1 else '05 Portón derecho'
    control(name,'0 cerrado, 1 abierto a 102 grados'); drive(o,'rotation_euler',2,name,f'{radians(-s*102):.12f}*v')
control('03 Corredera lateral','Primero sale del marco y después se desliza hacia atrás')
drive(slider,'location',0,'03 Corredera lateral','-0.17*min(1.0,4.0*v)')
drive(slider,'location',1,'03 Corredera lateral','1.36*max(0.0,(v-0.25)/0.75)')

# Better highlight continuity on the major sheet-metal parts, not every detail.
for o in objects:
    if o.type=='MESH' and o.name.split('.')[0] in {'Capó moldeado','Techo aerodinámico','Defensa curva','Puerta delantera','Puerta lateral','Portón inferior'}:
        mod=o.modifiers.new('Normales de carrocería','WEIGHTED_NORMAL')
        mod.keep_sharp=True
# Clean studio, light viewport, modest 3 lights.
# Set urbano: geometría estática agrupada por material (sin texturas externas).
# Calle orientada en Y, casas únicamente en +X; lado -X libre para la cámara.
import random
rng=random.Random(23)
urban_palette={
 'asphalt':((.115,.125,.139),.94), 'asphalt_patch':((.085,.096,.108),.98),
 'concrete':((.47,.46,.43),.91), 'curb':((.61,.60,.55),.86),
 'joint':((.26,.26,.25),.96), 'brick_a':((.46,.19,.115),.86),
 'brick_b':((.34,.125,.083),.90), 'brick_c':((.56,.28,.17),.88),
 'stucco':((.68,.60,.45),.92), 'sage':((.39,.49,.40),.88),
 'cream':((.80,.76,.65),.85), 'roof':((.105,.125,.15),.91),
 'roof_edge':((.20,.22,.23),.83), 'window':((.08,.19,.26),.29),
 'window_light':((.22,.34,.39),.35), 'door':((.14,.20,.20),.62),
 'wood':((.27,.16,.10),.78), 'steel':((.26,.30,.32),.38),
 'bin_green':((.07,.22,.12),.62), 'bin_dark':((.055,.07,.08),.66),
 'lamp_warm':((1,.81,.40),.29), 'grass':((.16,.24,.105),.98),
 'mark':((.66,.61,.49),.89), 'drain':((.055,.065,.075),.82),
}
for k,(c,r) in urban_palette.items(): M['u_'+k]=mat('Callejón | '+k,c,r)
shader=M['u_lamp_warm'].node_tree.nodes.get('Principled BSDF')
if 'Emission Color' in shader.inputs:
    shader.inputs['Emission Color'].default_value=(1,.77,.37,1)
    shader.inputs['Emission Strength'].default_value=.6
# Every material gets one mesh, so dozens of details add very few scene objects.
urban={}
road_collection=collection('03 | Calles y aceras')
houses_collection=collection('04 | Casas - ampliables')
furniture_collection=collection('05 | Mobiliario urbano')
nature_collection=collection('06 | Terreno y vegetación')
bus_collection=collection('02 | Autobús escolar')

def flush_urban(label,c,root=None):
    count=sum(len(v) for v,f in urban.values())
    for k,(v,f) in urban.items():
        o=obj(label+' | '+k,mesh(label+' '+k,v,f,'u_'+k)); move_to(o,c)
        if root is not None: o.parent=root
    urban.clear()
    return count

def u_add(k,v,f):
    vs,fs=urban.setdefault(k,([],[])); off=len(vs); vs.extend(v); fs.extend(tuple(i+off for i in face) for face in f)
def u_box(k,p,d):
    x,y,z=[a/2 for a in d]; px,py,pz=p
    v=[(px+a,py+b,pz+c) for a,b,c in [(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]]
    u_add(k,v,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
def u_cyl(k,a,b,r,n=12,r2=None):
    a,b=Vector(a),Vector(b); direction=(b-a).normalized(); u=direction.cross(Vector((0,0,1)))
    if u.length<.001: u=direction.cross(Vector((0,1,0)))
    u.normalize(); w=direction.cross(u); r2=r if r2 is None else r2
    v=[tuple(p+rad*(cos(2*pi*i/n)*u+sin(2*pi*i/n)*w)) for p,rad in ((a,r),(b,r2)) for i in range(n)]
    u_add(k,v,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)])
def u_line(k,a,b,width=.015):
    a,b=Vector(a),Vector(b); d=b-a; mid=(a+b)/2
    # Thin rectangular ribbon for cracks / markings, flush with pavement.
    v=Vector((-d.y,d.x,0)).normalized()*width/2
    u_add(k,[tuple(a-v),tuple(b-v),tuple(b+v),tuple(a+v)],[(0,1,2,3)])
# Road top is Z=0; original wheels keep their contact at Z=0.
u_box('asphalt',(-.13,0,-.11),(6.68,84,.22))
u_box('concrete',(4.12,0,.075),(1.54,84,.15))
u_box('curb',(3.30,0,.075),(.18,84,.15))
# left verge: flush with road, not across the wheels
u_box('curb',(-3.56,0,.055),(.18,84,.11))
# Sidewalk slabs and curb joints; all below the door swing.
for y in range(-40,41,2):
    u_box('joint',(4.12,y,.151),(1.51,.018,.004))
    u_box('joint',(3.30,y,.151),(.17,.018,.004))
# Subtle asphalt repairs, edge drain and sparse cracks (no huge texture maps).
for x,y,dx,dy in [(-2.7,-5,1.1,1.8),(2.55,4.4,.65,1.25),(-3.2,7,1.4,2.2),(1.8,-10,.8,1.3)]:
    u_box('asphalt_patch',(x,y,.001),(dx,dy,.002))
for x,y in [(-2.9,-3.2),(2.8,-1.8),(2.5,4.6),(-2.5,5.5)]:
    a=(x,y,.004)
    for j in range(4):
        b=(a[0]+rng.uniform(-.28,.28),a[1]+rng.uniform(.13,.40),.004); u_line('asphalt_patch',a,b,.018); a=b
u_box('drain',(3.05,1.4,.006),(.35,.59,.012))
for j in range(8): u_box('steel',(3.05,1.14+j*.073,.014),(.30,.025,.012))
u_cyl('steel',(-2.15,3.8,.002),(-2.15,3.8,.012),.30,24)
for i in range(-3,4): u_box('drain',(-2.15,3.8+i*.065,.015),(.34,.012,.008))
flush_urban('Calle principal',road_collection)
# Six attached residential houses along just one side of the street.
# Each has its own doorway, window recesses, frames, sills, pitched roof and gutter.
for idx,cy in enumerate((-13.5,-8.1,-2.7,2.7,8.1,13.5)):
    xf=4.9; xb=9.1; ya=cy-2.58; yb=cy+2.58; h=4.65+(.18 if idx%2 else 0)
    wall=('brick_a','stucco','brick_c','sage','brick_a','stucco')[idx]
    u_box('concrete',((xf+xb)/2,cy,.06),(xb-xf,yb-ya,.20))
    u_box(wall,((xf+xb)/2,cy,h/2+.15),(xb-xf,yb-ya,h))
    u_box('concrete',(xf-.015,cy,.36),(.07,5.12,.43))
    u_box('cream',(xf-.045,cy,2.78),(.09,5.12,.075))
    u_box('cream',(xf-.055,cy,h+.14),(.15,5.30,.13))
    if wall.startswith('brick'):
        # Thin color variations on selected brick faces, not thousands of objects.
        for row in range(20):
            for j in range(9):
                yy=ya+.28+j*.56+(.22 if row%2 else 0); zz=.67+row*.19
                if yy>yb-.18 or rng.random()>.26: continue
                u_box(rng.choice(('brick_b','brick_c')),(xf-.013,yy,zz),(.025,.48,.145))
    # Two-storey facade. Facing street (negative X).
    for yy,zz,ww,hh in [(cy-1.45,1.65,1.10,1.18),(cy+.95,1.65,1.15,1.18),(cy-1.36,3.60,1.23,1.28),(cy+1.26,3.60,1.23,1.28)]:
        u_box('cream',(xf-.065,yy,zz),(.12,ww+.18,hh+.18))
        u_box('window',(xf-.133,yy,zz),(.025,ww,hh))
        u_box('window_light',(xf-.15,yy-.15,zz+.18),(.012,ww*.36,hh*.45))
        u_box('cream',(xf-.16,yy,zz),(.045,.047,hh))
        u_box('cream',(xf-.16,yy,zz),(.045,ww,.047))
        u_box('curb',(xf-.13,yy,zz-hh/2-.085),(.30,ww+.25,.11))
    yy=cy-.23
    u_box('cream',(xf-.10,yy,1.22),(.16,1.05,2.15))
    u_box('door' if idx%2 else 'wood',(xf-.19,yy,1.22),(.045,.86,1.98))
    u_box('window',(xf-.218,yy,1.73),(.02,.60,.52))
    u_box('steel',(xf-.24,yy+.29,1.11),(.06,.06,.12))
    u_box('concrete',(xf-.38,yy,.22),(.73,1.30,.17))
    u_box('concrete',(xf-.70,yy,.15),(.44,1.44,.12))
    # Doorway canopy and house-number plate without font dependencies.
    u_box('roof_edge',(xf-.35,yy,2.43),(.75,1.37,.12))
    u_box('steel',(xf-.20,yy+.70,2.13),(.18,.12,.24))
    u_box('lamp_warm',(xf-.30,yy+.70,2.13),(.035,.085,.15))
    # Roof ridge parallel to street, closed gable shape.
    z=h+.18; a=xf-.18; b=xb+.18; c=(a+b)/2
    v=[(a,ya-.12,z),(b,ya-.12,z),(c,ya-.12,z+1.03),(a,yb+.12,z),(b,yb+.12,z),(c,yb+.12,z+1.03)]
    u_add('roof',v,[(2,1,0),(3,4,5),(0,1,4,3),(0,3,5,2),(1,2,5,4)])
    u_box('roof_edge',(a-.04,cy,z),(.12,5.52,.12))
    u_cyl('steel',(xf-.12,yb-.15,.20),(xf-.12,yb-.15,z),.045,10)
    # Group each house independently, ready to duplicate or reposition.
    house_root=move_to(empty(f'CASA {idx+1:02d} | CONTROL'),houses_collection)
    house_root.empty_display_size=.4
    flush_urban(f'Casa {idx+1:02d}',houses_collection,house_root)
    # Move origin to its center without shifting the geometry.
    house_root.location=(7.0,cy,.15)
    for child in house_root.children: child.location-=house_root.location
# Two wheelie bins with molded lids, handles, wheels; placed out of door paths.
for y,k in [(2.85,'bin_green'),(3.58,'bin_dark')]:
    x=4.0
    # tapered box body, narrower at base.
    v=[(x+a,y+b,z) for z,wx,wy in [(.25,.23,.25),(.99,.30,.30)] for a,b in [(-wx,-wy),(wx,-wy),(wx,wy),(-wx,wy)]]
    u_add(k,v,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
    u_box(k,(x,y,1.015),(.67,.67,.085))
    u_box('bin_dark',(x-.30,y,1.064),(.10,.37,.035))
    u_cyl('steel',(x+.32,y-.28,.24),(x+.32,y+.28,.24),.028,12)
    for s in (-1,1): u_cyl('bin_dark',(x+.32,y+s*.29,.24),(x+.32,y+s*.34,.24),.105,16)
    u_box('mark',(x-.305,y,.76),(.014,.20,.12))
# Streetlight with tapered shaft, curved/segmented arm and luminous lens.
x,y=3.72,-3.8
u_cyl('steel',(x,y,.15),(x,y,.32),.20,16)
u_cyl('steel',(x,y,.32),(x,y,3.85),.075,16,.048)
arm=[(x,y,3.85),(x-.07,y,4.06),(x-.26,y,4.20),(x-.57,y,4.24),(x-.94,y,4.24)]
for a,b in zip(arm,arm[1:]): u_cyl('steel',a,b,.047,12)
u_box('steel',(x-1.06,y,4.22),(.45,.24,.13))
u_box('lamp_warm',(x-1.06,y,4.143),(.36,.18,.025))
# Utility box at house side, and two low bollards protecting the sidewalk.
u_box('steel',(4.72,5.55,.60),(.30,.49,.90))
for yy in (-4.5,4.55):
    u_cyl('steel',(3.5,yy,.15),(3.5,yy,.70),.055,12)
    u_cyl('mark',(3.5,yy,.58),(3.5,yy,.64),.057,12)
flush_urban('Mobiliario',furniture_collection)
# Autobús escolar estadounidense corto, estacionado detrás de la van.
# Todo el autobús (salvo rótulos) se agrega a los meshes estáticos por material.
BX,BY=1.85,8.65
bus_palette={
 'bus_yellow':((.98,.48,.018),.32), 'bus_gold':((1,.63,.025),.38),
 'bus_black':((.018,.022,.027),.47), 'bus_glass':((.065,.15,.205),.19),
 'bus_glint':((.20,.32,.40),.28), 'bus_rubber':((.022,.025,.028),.86),
 'bus_metal':((.55,.59,.62),.36), 'bus_red':((.75,.022,.025),.25),
 'bus_white':((.94,.94,.88),.32), 'bus_amber':((1,.30,.02),.27),
}
for k,(c,r) in bus_palette.items(): M['u_'+k]=mat('Bus | '+k,c,r)
def bp(p): return (p[0]+BX,p[1]+BY,p[2])
def bb(k,p,d): u_box('bus_'+k,bp(p),d)
def bc(k,a,b,r,n=20,r2=None): u_cyl('bus_'+k,bp(a),bp(b),r,n,r2)
def bm(k,v,f): u_add('bus_'+k,[bp(p) for p in v],f)
def sidepanel(k,s,pts,x=1.115,t=.07):
    # Outward-facing extruded profile in the YZ plane, including curved arches.
    n=len(pts); v=[(s*x+dx,y,z) for dx in (-t/2,t/2) for y,z in pts]
    f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    if sum(pts[i][0]*pts[(i+1)%n][1]-pts[(i+1)%n][0]*pts[i][1] for i in range(n))<0: f=[tuple(reversed(face)) for face in f]
    bm(k,v,f)
# dimensions: ~7.6 m long, 2.3 m wide, 3.1 m high, two axles.
bb('black',(0,0,.60),(1.50,6.90,.30))
bb('yellow',(0,.61,1.00),(2.19,5.94,.38))
bb('yellow',(0,.65,1.44),(2.20,5.90,.59))
# Upper cabin with a rounded shoulder and roof; closed, low-poly shell.
section=[(-1.10,1.68),(1.10,1.68),(1.10,2.68),(1.03,2.84),(.79,2.98),(-.79,2.98),(-1.03,2.84),(-1.10,2.68)]
v=[(x,y,z) for y in (-2.36,3.58) for x,z in section]; n=len(section)
f=[tuple(range(n)),tuple(reversed(range(n,2*n)))]+[(i,i+n,(i+1)%n+n,(i+1)%n) for i in range(n)]
bm('yellow',v,f)
# Front hood, with slightly tapered sloped top.
hood=[(-3.76,.84,.82,1.31),(-3.64,.91,.82,1.39),(-2.39,.99,.82,1.60)]
v=[(x,y,z) for y,w,low,high in hood for x,z in [(-w,low),(w,low),(w,high),(-w,high)]]
f=[(0,1,2,3),(11,10,9,8)]+[(4*i+j,4*(i+1)+j,4*(i+1)+(j+1)%4,4*i+(j+1)%4) for i in range(2) for j in range(4)]
bm('gold',v,f)
bb('black',(0,-3.80,.64),(2.08,.20,.25)); bb('black',(0,3.65,.64),(2.22,.19,.24))
# Fender lower panels, with genuine semicircular openings around each wheel.
axles=(-2.42,2.02); radius=.48; arch=.56
for side in (-1,1):
    for a,b in [(-3.64,-2.98),(-1.86,1.46),(2.58,3.58)]:
        sidepanel('yellow',side,[(a,.55),(b,.55),(b,1.09),(a,1.09)])
    for y in axles:
        arc=[(y+arch*cos(pi-i*pi/16),radius+arch*sin(pi-i*pi/16)) for i in range(17)]
        sidepanel('yellow',side,arc+[(y+arch,1.12),(y-arch,1.12)])
        outer=[(y+(arch+.045)*cos(i*pi/20),radius+(arch+.045)*sin(i*pi/20)) for i in range(21)]
        inner=[(y+arch*cos(pi-i*pi/20),radius+arch*sin(pi-i*pi/20)) for i in range(21)]
        sidepanel('black',side,inner+outer,1.16,.033)
        bc('rubber',(side*.87,y,radius),(side*1.20,y,radius),radius,32)
        bc('metal',(side*1.20,y,radius),(side*1.227,y,radius),.285,24)
        bc('black',(side*1.228,y,radius),(side*1.24,y,radius),.16,20)
        for j in range(6):
            a=j*pi/3; yy=y+.20*cos(a); zz=radius+.20*sin(a)
            bc('black',(side*1.226,yy,zz),(side*1.243,yy,zz),.030,10)
        bc('metal',(side*1.24,y,radius),(side*1.255,y,radius),.09,16)
    # recognizable black rub rails and full window row
    for z in (1.14,1.58): bb('black',(side*1.135,.65,z),(.044,5.80,.085))
    for j in range(7):
        y=-1.93+j*.76
        bb('black',(side*1.112,y,2.23),(.034,.67,.69))
        bb('glass',(side*1.135,y,2.23),(.023,.59,.61))
        bb('metal',(side*1.151,y,2.26),(.018,.59,.024))
        bb('glint',(side*1.151,y-.18,2.41),(.010,.14,.18))
    # a door outline on the passenger side and driver-side mirror.
    if side==1:
        bb('black',(1.148,-1.92,1.53),(.025,.66,.80))
        bb('yellow',(1.169,-1.92,1.50),(.020,.59,.70))
        bb('black',(1.187,-1.92,1.53),(.012,.025,.75))
    bc('black',(side*1.05,-2.52,2.00),(side*1.43,-2.82,2.14),.028,12)
    bb('black',(side*1.44,-2.83,2.14),(.16,.15,.34))
    bb('metal',(side*1.44,-2.745,2.14),(.13,.016,.28))
    bb('amber',(side*1.137,-2.18,2.74),(.045,.10,.08))
    bb('red',(side*1.137,3.40,2.74),(.045,.10,.08))
# Folded stop sign on the visible driver side. No protrusion into the road.
# Red octagon, white edge and lettering, attached against body.
for rad,k,x in [(.27,'white',-1.165),(.244,'red',-1.182)]:
    v=[(x,-1.03+rad*cos(pi/8+j*pi/4),1.95+rad*sin(pi/8+j*pi/4)) for j in range(8)]
    bm(k,v,[tuple(reversed(range(8)))])
bb('black',(-1.16,-1.32,1.95),(.045,.13,.10))
# Front windshield split into two panes, rear emergency door and windows.
for side in (-1,1):
    bb('black',(side*.52,-2.385,2.15),(.93,.047,.79))
    bb('glass',(side*.52,-2.414,2.15),(.85,.025,.69))
    bb('black',(side*.52,3.605,2.20),(.83,.045,.65))
    bb('glass',(side*.52,3.633,2.20),(.75,.025,.57))
    bb('white',(side*.69,-3.78,1.11),(.35,.05,.22))
    bb('amber',(side*.88,-3.80,.99),(.10,.04,.11))
    bb('red',(side*.93,3.62,1.19),(.19,.05,.30))
    bb('amber',(side*.72,3.62,1.19),(.13,.05,.13))
    for dx,k in [(.115,'red'),(-.115,'amber')]:
        xx=side*(.865+dx)
        bc('black',(xx,-2.38,2.75),(xx,-2.43,2.75),.13,20)
        bc(k,(xx,-2.43,2.75),(xx,-2.46,2.75),.10,20)
        bc('black',(xx,3.59,2.75),(xx,3.64,2.75),.13,20)
        bc(k,(xx,3.64,2.75),(xx,3.67,2.75),.10,20)
# Front grille and emergency-door seams.
bb('black',(0,-3.785,1.10),(.89,.05,.38))
for j in range(5): bb('metal',(0,-3.818,.95+j*.073),(.78,.022,.026))
for x in (-.45,.45): bb('black',(x,3.604,1.45),(.022,.035,1.05))
bb('black',(0,3.625,1.54),(.17,.045,.045))
bb('black',(0,3.76,.68),(.38,.025,.13)); bb('white',(0,3.776,.68),(.27,.012,.09))
bus_root=move_to(empty('BUS | CONTROL'),bus_collection)
bus_root.empty_display_size=.5
# Only five lightweight text objects, independent of the grouped geometry.
def bus_text(body,p,rot,size,k='black'):
    d=bpy.data.curves.new('Bus '+body,'FONT'); d.body=body; d.align_x='CENTER'; d.align_y='CENTER'; d.size=size; d.resolution_u=2; d.materials.append(M['u_bus_'+k]); o=obj('Bus | '+body,d,bp(p)); o.rotation_euler=rot; o.parent=bus_root; move_to(o,bus_collection)
bus_text('SCHOOL BUS',(0,-2.39,2.76),(pi/2,0,0),.17)
bus_text('SCHOOL BUS',(0,3.61,2.76),(pi/2,0,pi),.17)
bus_text('SCHOOL BUS',(-1.125,.85,1.81),(pi/2,0,-pi/2),.185)
bus_text('SCHOOL BUS',(1.125,.85,1.81),(pi/2,0,pi/2),.185)
bus_text('STOP',(-1.188,-1.03,1.95),(pi/2,0,-pi/2),.16,'white')
# Nearest bus bumper stays over one meter beyond the maximum van rear-door reach.
assert BY-3.90>3.55 and BX+1.53<3.40

# Link the grouped bus independently so it can be moved as an asset.
flush_urban('Bus escolar',bus_collection,bus_root)
bus_root.location=(BX,BY,0)
for child in bus_root.children: child.location-=bus_root.location

# 80 x 84 m terrain. Keep road and all existing foundations on a flat pad;
# hills rise smoothly away from the street, with small irregularities.
def smoothstep(v):
    v=max(0.0,min(1.0,v)); return v*v*(3-2*v)

def terrain_height(x,y):
    dist=max(-4.2-x,x-10.8,0.0)
    t=smoothstep(dist/8.0)
    hill=(2.1+1.15*sin(x*.135+y*.075)+.82*cos(y*.16-x*.08)+.35*sin(x*.48+y*.27))
    hill=max(.10,hill)
    # Small undulation on the distant banks, never beneath the pavement.
    return -.035+t*hill

assert all(abs(terrain_height(x,y)+.035)<1e-9 for x in (-4,-3,0,3.4,5,9.5,10.8) for y in (-42,0,42))
# Ground with lightly varied green materials and natural-looking smooth geometry.
for k,c in {'meadow_a':(.13,.27,.045),'meadow_b':(.18,.34,.060),'meadow_c':(.10,.22,.038),'meadow_d':(.22,.37,.085),'earth':(.20,.115,.055),'bark':(.18,.085,.038),'leaves_a':(.10,.27,.055),'leaves_b':(.16,.36,.075),'leaves_c':(.075,.20,.035),'leaves_d':(.25,.41,.085)}.items():
    M['u_'+k]=mat('Naturaleza | '+k,c,.88)
# Procedural grass mottling: no image textures or displacement render.
for k in ('meadow_a','meadow_b','meadow_c','meadow_d'):
    m=M['u_'+k]; nt=m.node_tree; p=nt.nodes.get('Principled BSDF'); base=tuple(m.diffuse_color[:3]); noise=nt.nodes.new('ShaderNodeTexNoise'); noise.inputs['Scale'].default_value=1.5; noise.inputs['Detail'].default_value=2.0
    coord=nt.nodes.new('ShaderNodeTexCoord'); nt.links.new(coord.outputs['Object'],noise.inputs['Vector'])
    ramp=nt.nodes.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].position=.17; ramp.color_ramp.elements[0].color=tuple(c*.68 for c in base)+(1,); ramp.color_ramp.elements[1].position=.83; ramp.color_ramp.elements[1].color=tuple(c*1.25 for c in base)+(1,)
    nt.links.new(noise.outputs['Fac'],ramp.inputs[0]); nt.links.new(ramp.outputs[0],p.inputs['Base Color'])
NX,NY=100,105
verts=[(-40+80*i/NX,-42+84*j/NY,terrain_height(-40+80*i/NX,-42+84*j/NY)) for j in range(NY+1) for i in range(NX+1)]
faces=[]; indices=[]
for j in range(NY):
    for i in range(NX):
        a=j*(NX+1)+i; faces.append((a,a+1,a+NX+2,a+NX+1)); x,y,_=verts[a]
        tone=sin(x*.37+y*.24)+.64*cos(y*.47-x*.11)+.27*sin(x*1.1+y*.8)
        indices.append(0 if tone<-.35 else 1 if tone<.65 else 3 if tone>1.25 else 2)
d=bpy.data.meshes.new('Relieve de la ciudad'); d.from_pydata(verts,[],faces); d.update()
for k in ('meadow_a','meadow_b','meadow_c','meadow_d'): d.materials.append(M['u_'+k])
for f,idx in zip(d.polygons,indices): f.material_index=idx; f.use_smooth=True
move_to(obj('TERRENO | 80 x 84 m',d),nature_collection)

# Low-poly leafy canopies; vegetation batched by material, not a particle system.
def foliage(k,p,s,seed):
    rr=random.Random(seed); x,y,z=p; sx,sy,sz=s; N=9; nr=5
    v=[(x,y,z-sz)]
    for j in range(1,nr):
        a=-pi/2+pi*j/nr
        for i in range(N):
            b=2*pi*i/N+j*.31; scale=rr.uniform(.85,1.12)
            v.append((x+sx*cos(a)*cos(b)*scale,y+sy*cos(a)*sin(b)*scale,z+sz*sin(a)*rr.uniform(.93,1.06)))
    v.append((x,y,z+sz)); top=len(v)-1
    f=[(0,1+(i+1)%N,1+i) for i in range(N)]
    for j in range(nr-2):
        a=1+j*N; b=a+N
        f.extend((a+i,a+(i+1)%N,b+(i+1)%N,b+i) for i in range(N))
    a=1+(nr-2)*N; f.extend((a+i,a+(i+1)%N,top) for i in range(N)); u_add(k,v,f)

def tree(x,y,h,seed):
    z=terrain_height(x,y); rr=random.Random(seed); trunk=h*.56
    u_cyl('bark',(x,y,z),(x+.08,y,z+trunk),h*.032,9,h*.017)
    for i in range(4):
        a=i*pi/2+rr.uniform(-.3,.3); reach=h*.20; px=x+cos(a)*reach; py=y+sin(a)*reach; pz=z+h*.73+rr.uniform(-.15,.15)
        u_cyl('bark',(x,y,z+trunk*.65),(px,py,pz),h*.015,7,h*.006)
        foliage(('leaves_a','leaves_b','leaves_c','leaves_d')[i],(px,py,pz),(h*.23,h*.22,h*.23),seed*7+i)
    foliage('leaves_b',(x,y,z+h*.88),(h*.24,h*.23,h*.25),seed*7+5)
# Keep the road, camera corridor and existing façades clear.
for i,(x,y,h) in enumerate([(-9,-24,4.4),(-11,21,5.0),(-17,-8,5.5),(-20,8,4.8),(-25,-27,5.6),(-27,25,5.2),(-33,3,5.8),(13,-17,4.0),(14,-5,4.4),(15,9,4.7),(14,21,4.4),(21,-27,5.0),(24,3,5.6),(30,19,5.8),(33,-11,5.3)]):
    tree(x,y,h,100+i)
# Sparse low bushes on grassy verges and behind the houses.
for i in range(65):
    x=rng.choice([rng.uniform(-35,-6),rng.uniform(11.5,35)]); y=rng.uniform(-38,38); z=terrain_height(x,y); r=rng.uniform(.25,.65)
    foliage('leaves_a' if i%2 else 'leaves_c',(x,y,z+r*.48),(r,r*.80,r*.70),900+i)
flush_urban('Vegetación',nature_collection)

S.world.color=(.28,.37,.47)
def aim(o,t): o.rotation_euler=(Vector(t)-o.location).to_track_quat('-Z','Y').to_euler()
for n,p,e,size in [('Principal',(0,-5,7),950,5),('Relleno',(-6,0,5),600,5)]:
    d=bpy.data.lights.new(n,'AREA'); d.energy=e; d.size=size; o=obj(n,d,p); aim(o,(0,0,1))
d=bpy.data.lights.new('Sol de tarde','SUN'); d.energy=2.0; d.angle=radians(12); d.color=(1,.89,.74); o=obj('Sol de tarde',d,(-8,-6,12)); aim(o,(0,0,0))
# Two stationary cameras: overview and vehicle detail. Change active camera in Scene.
cameras=collection('07 | Cámaras y luces')
for o in list(S.objects):
    if o.type=='LIGHT': move_to(o,cameras)
def static_camera(name,pos,target,scale):
    cam=move_to(obj(name,bpy.data.cameras.new(name),pos),cameras); cam.data.type='ORTHO'; cam.data.clip_end=350; cam.data.ortho_scale=scale; aim(cam,target); return cam
street=static_camera('CAM 01 | Calle y vehículos',(-15,-21,10),(2.0,4.0,1.4),25)
wide=static_camera('CAM 02 | Vista de ciudad',(-45,-48,48),(0,0,0),130)
detail=static_camera('CAM 03 | Interior de la van',(-6,1.4,2.9),(0,.1,1.3),8.0)
S.camera=street
OUT=Path.home()/'VMV_Videos'; OUT.mkdir(parents=True,exist_ok=True); S.render.filepath=str(OUT/'vmv_ciudad_01.png')
if hasattr(S.render.image_settings,'media_type'): S.render.image_settings.media_type='IMAGE'
S.render.image_settings.file_format='PNG'
S.frame_set(1)
# Select master van control, so its sliders are easy to access. Keep Solid mode.
for o in bpy.context.selected_objects: o.select_set(False)
van_root.select_set(True); bpy.context.view_layer.objects.active=van_root
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            sp=area.spaces.active; sp.overlay.show_overlays=False; sp.shading.type='SOLID'; sp.shading.color_type='MATERIAL'; sp.shading.light='STUDIO'; sp.shading.show_cavity=True; sp.shading.cavity_type='WORLD'; sp.shading.show_shadows=True; sp.shading.background_type='WORLD'; sp.region_3d.view_perspective='CAMERA'; sp.clip_end=350
print('My City 01 | objetos:',len(S.objects),'| terreno:',len(verts),'vértices | sin fotogramas animados.')
print('VAN | CONTROL > Object Properties > Custom Properties: 0 cerrado, 1 abierto.')
