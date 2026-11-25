# -*- coding: utf-8 -*-
"""My City Studio: local Git synchronization and explicit scene operations."""
bl_info = {'name':'My City Studio','author':'My City','version':(0,3,1),'blender':(4,2,0),'location':'View3D > Sidebar > My City','description':'Synchronize a local My City repository and apply reviewed scripts','category':'3D View'}
import bpy
from pathlib import Path
import os, shutil, subprocess, threading, queue, runpy

_results = queue.Queue()
_busy = False
_status = 'Selecciona la carpeta local del repositorio.'

def root(context):
    value=context.scene.vmv_repo
    if not value: raise ValueError('Selecciona la carpeta local de mycity.')
    p=Path(bpy.path.abspath(value)).resolve()
    if not (p/'.git').exists(): raise ValueError('La carpeta no es un repositorio Git clonado.')
    return p

def git_binary():
    candidates=[shutil.which('git')]
    for base in (os.environ.get('ProgramFiles'),os.environ.get('ProgramFiles(x86)'),os.environ.get('LOCALAPPDATA')):
        if base:
            candidates.extend([str(Path(base)/'Git'/'cmd'/'git.exe'),str(Path(base)/'Programs'/'Git'/'cmd'/'git.exe')])
    for p in candidates:
        if p and Path(p).is_file(): return p
    raise ValueError('Instala Git for Windows y reinicia Blender.')

def git_worker(repo, git):
    try:
        env=dict(os.environ,GIT_TERMINAL_PROMPT='0',GCM_INTERACTIVE='never')
        def run(*args):
            result=subprocess.run([git,'-C',str(repo),*args],capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=35,env=env,creationflags=getattr(subprocess,'CREATE_NO_WINDOW',0))
            if result.returncode: raise RuntimeError((result.stderr or result.stdout or 'Git falló').strip())
            return result.stdout.strip()
        if run('status','--porcelain','--untracked-files=no'):
            raise RuntimeError('Hay cambios locales en archivos rastreados. Guárdalos en Git antes de sincronizar.')
        run('pull','--ff-only','--no-rebase')
        revision=run('rev-parse','--short','HEAD')
        _results.put('Sincronizado: '+revision+' | No se ejecutó ningún script.')
    except Exception as exc: _results.put('Error: '+str(exc))

def poll_git():
    global _busy,_status
    try: _status=_results.get_nowait()
    except queue.Empty: return .25
    _busy=False
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type=='VIEW_3D': area.tag_redraw()
    print('My City:',_status)
    return None

class VMV_OT_sync(bpy.types.Operator):
    bl_idname='vmv_city.sync'; bl_label='Sincronizar GitHub'; bl_description='Descarga cambios fast-forward sin ejecutar código'
    @classmethod
    def poll(cls,context): return not _busy
    def execute(self,context):
        global _busy,_status
        try: p=root(context); git=git_binary()
        except Exception as exc: self.report({'ERROR'},str(exc)); return {'CANCELLED'}
        _busy=True; _status='Sincronizando con GitHub...'
        threading.Thread(target=git_worker,args=(p,git),daemon=True).start()
        bpy.app.timers.register(poll_git,first_interval=.25)
        return {'FINISHED'}

class VMV_OT_build(bpy.types.Operator):
    bl_idname='vmv_city.build'; bl_label='Crear ciudad inicial'; bl_description='Ejecuta el generador inicial solo en una escena vacía'
    def invoke(self,context,event): return context.window_manager.invoke_confirm(self,event)
    def execute(self,context):
        global _status
        try:
            p=root(context)/'scenes'/'district_01.py'
            if not p.is_file(): raise ValueError('No existe scenes/district_01.py. Sincroniza el repositorio.')
            if len(context.scene.objects): raise ValueError('Usa una escena vacía en un archivo nuevo. No se reemplazará tu trabajo.')
            if context.scene.get('vmv_initialized'): raise ValueError('Esta escena ya fue inicializada.')
            runpy.run_path(str(p),run_name='__main__')
            context.scene['vmv_initialized']=True
            _status='Ciudad creada. Guarda el archivo .blend.'
        except Exception as exc: self.report({'ERROR'},str(exc)); return {'CANCELLED'}
        return {'FINISHED'}

class VMV_OT_apply(bpy.types.Operator):
    bl_idname='vmv_city.apply'; bl_label='Aplicar actualización revisada'; bl_description='Ejecuta un script incremental elegido explícitamente. Guarda una copia antes.'
    def invoke(self,context,event): return context.window_manager.invoke_confirm(self,event)
    def execute(self,context):
        global _status
        try:
            repo=root(context)
            name=context.scene.vmv_update.strip()
            if not name or Path(name).name!=name or not name.endswith('.py'): raise ValueError('Escribe el nombre del script .py dentro de updates/.')
            folder=(repo/'updates').resolve(); script=(folder/name).resolve()
            if script.parent!=folder or not script.is_file(): raise ValueError('Actualización no encontrada.')
            if not bpy.data.filepath: raise ValueError('Guarda primero una copia del archivo .blend.')
            key='vmv_update_'+name
            if context.scene.get(key): raise ValueError('Esta actualización ya fue aplicada a la escena.')
            runpy.run_path(str(script),run_name='__main__')
            context.scene[key]=True
            _status='Aplicada: '+name+' | Guarda tu escena.'
        except Exception as exc: self.report({'ERROR'},str(exc)); return {'CANCELLED'}
        return {'FINISHED'}

class VMV_PT_panel(bpy.types.Panel):
    bl_label='My City Studio'; bl_idname='VMV_PT_city'; bl_space_type='VIEW_3D'; bl_region_type='UI'; bl_category='My City'
    def draw(self,context):
        layout=self.layout; s=context.scene
        layout.label(text='Repositorio local'); layout.prop(s,'vmv_repo',text='Carpeta')
        layout.operator('vmv_city.sync',icon='FILE_REFRESH')
        box=layout.box()
        for i in range(0,len(_status),46): box.label(text=_status[i:i+46])
        col=layout.column(); col.enabled=not _busy
        col.operator('vmv_city.build',icon='WORLD_DATA')
        col.separator(); col.label(text='Cambios incrementales')
        col.prop(s,'vmv_update',text='Script'); col.label(text='Guarda una copia antes de aplicar.')
        col.operator('vmv_city.apply',icon='PLAY')


# Performance tools: explicit snapshots, no polling or background geometry scans.
_perf_cache = {}

def perf_key(context):
    return (context.scene.as_pointer(), context.view_layer.as_pointer(),
            context.area.as_pointer())

def collect_performance(context):
    total = [0, 0, 0, 0, 0]
    visible = [0, 0, 0, 0, 0]
    mesh_cache = {}
    visible_ids = set()
    for ob in context.scene.objects:
        total[0] += 1
        is_visible = (context.view_layer.objects.get(ob.name) is not None and
                      ob.visible_get(view_layer=context.view_layer, viewport=context.space_data))
        if is_visible:
            visible[0] += 1
        if ob.type != 'MESH' or ob.data is None:
            continue
        me = ob.data
        key = me.as_pointer()
        if key not in mesh_cache:
            nfaces = len(me.polygons)
            mesh_cache[key] = (len(me.vertices), nfaces, max(0, len(me.loops)-2*nfaces))
        counts = mesh_cache[key]
        total[1] += 1
        for i, n in enumerate(counts, 2):
            total[i] += n
        if is_visible:
            visible[1] += 1
            visible_ids.add(key)
            for i, n in enumerate(counts, 2):
                visible[i] += n
    return (total, visible, len(mesh_cache), len(visible_ids))

def perf_view(context):
    return context.area is not None and context.area.type == 'VIEW_3D'

def perf_mode(context):
    sh = context.space_data.shading
    if sh.type == 'RENDERED':
        return 'ULTRA'
    if sh.type != 'SOLID' or sh.color_type != 'MATERIAL':
        return 'CUSTOM'
    if sh.show_shadows and sh.show_cavity:
        return 'BALANCED'
    if not sh.show_shadows and not sh.show_cavity:
        return 'ECO'
    return 'CUSTOM'

class VMV_OT_perf_refresh(bpy.types.Operator):
    bl_idname = 'vmv_city.perf_refresh'
    bl_label = 'Medir escena'
    bl_description = 'Cuenta las mallas base de la escena y de la vista, sin evaluar modificadores'
    @classmethod
    def poll(cls, context):
        return perf_view(context) and not _busy
    def execute(self, context):
        try:
            _perf_cache[perf_key(context)] = collect_performance(context)
        except Exception as exc:
            self.report({'ERROR'}, str(exc))
            return {'CANCELLED'}
        context.area.tag_redraw()
        return {'FINISHED'}

class VMV_OT_perf_mode(bpy.types.Operator):
    bl_idname = 'vmv_city.perf_mode'
    bl_label = 'Calidad de la vista'
    bl_description = 'Cambia solo la visualizacion del visor, sin modificar la geometria ni el render final'
    mode: bpy.props.EnumProperty(items=[
        ('ECO','Economico','Solid sin sombras ni cavity'),
        ('BALANCED','Equilibrado','Solid con sombras y cavity'),
        ('ULTRA','Ultra','Rendered con el motor actual'),
    ], default='ECO')
    @classmethod
    def poll(cls, context):
        return perf_view(context) and not _busy
    def execute(self, context):
        sh = context.space_data.shading
        if self.mode == 'ULTRA':
            sh.type = 'RENDERED'
        else:
            sh.type = 'SOLID'
            sh.color_type = 'MATERIAL'
            sh.light = 'STUDIO'
            sh.show_shadows = self.mode == 'BALANCED'
            sh.show_cavity = self.mode == 'BALANCED'
            if self.mode == 'BALANCED':
                sh.cavity_type = 'WORLD'
        # Do not change overlays, selection, materials, modifiers or render settings.
        context.area.tag_redraw()
        return {'FINISHED'}

class VMV_PT_performance(bpy.types.Panel):
    bl_label = 'Performance | Rendimiento'
    bl_idname = 'VMV_PT_performance'
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'My City'
    bl_parent_id = 'VMV_PT_city'
    def draw(self, context):
        layout = self.layout
        active = perf_mode(context)
        row = layout.row(align=True)
        for mode,label in [('ECO','Eco'),('BALANCED','Equilibrado'),('ULTRA','Ultra')]:
            op = row.operator('vmv_city.perf_mode', text=label, depress=active==mode)
            op.mode = mode
        layout.label(text='Ultra puede ralentizar el visor.')
        layout.operator('vmv_city.perf_refresh',icon='FILE_REFRESH')
        data = _perf_cache.get(perf_key(context))
        if data is None:
            layout.label(text='Pulsa Medir escena para empezar.')
            return
        total,visible,unique,unique_vis = data
        box = layout.box()
        row = box.row(align=True)
        row.label(text='Metrica')
        row.label(text='Total')
        row.label(text='Visible')
        for i,label in enumerate(('Objetos','Obj. malla','Vertices','Caras','Triangulos*')):
            row = box.row(align=True)
            row.label(text=label)
            row.label(text=f'{total[i]:,}')
            row.label(text=f'{visible[i]:,}')
        row = box.row(align=True)
        row.label(text='Mallas unicas')
        row.label(text=f'{unique:,}')
        row.label(text=f'{unique_vis:,}')
        layout.label(text='*Estimacion de malla base.')
        layout.label(text='Sin modificadores ni instancias GN.')
        layout.label(text='Visible no significa dentro de camara.')
        layout.label(text='Vuelve a medir tras cada cambio.')


# V0.3: reversible, opt-in distance-based detail visibility.
# hide_set and LayerCollection.hide_viewport are viewport-only.
# No mesh modification, no global hide_render, no automatic disk loads.
from bpy.app.handlers import persistent
import time
from collections import deque

_lod = {}
_lod_hidden = {}
_draw_samples = {}
_draw_handle = None

# Only small details of the original van; keep its silhouette, doors,
# seats, wheels and windows. Future assets may opt in with mycity_lod_detail.
_DETAIL_PREFIXES = (
    'Tuerca rueda', 'Anillo rueda', 'Centro llanta', 'Costura cojín',
    'Guía cabecera', 'Inserto asiento', 'Inserto respaldo', 'Hebilla cinturón',
    'Botón hebilla', 'Indicador tablero', 'Carátula instrumento',
    'Control climatización', 'Marca instrumento', 'Aguja indicador',
    'Interfaz pantalla', 'Inserto banca', 'Anclaje carga', 'Pedal',
    'Aleta entrada aire', 'Aro proyector', 'Lente proyector',
    'Borde óptica', 'Detalle defensa', 'Detalle piloto trasero',
)

def _lookup_layer(scene_name, layer_name):
    sc = bpy.data.scenes.get(scene_name)
    return sc.view_layers.get(layer_name) if sc else None

def _restore_lod():
    # Only undo changes made by this tool, not objects already hidden by the user.
    for (scene_name, layer_name, obj_name), pointer in list(_lod_hidden.items()):
        try:
            layer = _lookup_layer(scene_name, layer_name)
            ob = layer.objects.get(obj_name) if layer else None
            if ob and ob.as_pointer() == pointer:
                ob.hide_set(False, view_layer=layer)
        except (RuntimeError, ReferenceError):
            pass
    _lod_hidden.clear()

def _stop_lod():
    _restore_lod()
    _restore_sectors()
    _lod.clear()
    _perf_cache.clear()

def _layer_collections(lc):
    for child in lc.children:
        yield child
        yield from _layer_collections(child)

def _districts(context):
    # Named asset sectors of district 01 and future DISTRICT collections.
    # Keep terrain, streets and lighting outside this manager.
    prefixes = ('01 | VAN', '02 | Autobús', '04 | Casas', '05 | Mobiliario',
                'DISTRICT |', 'DISTRITO |')
    for lc in _layer_collections(context.view_layer.layer_collection):
        if lc.name.startswith(prefixes) and not lc.exclude:
            yield lc


# Optional sector streaming in the viewport. It is intentionally disabled
# by default because an aerial overview should retain the whole city.
_sector_hidden = {}

def _restore_sectors():
    for (scene_name, layer_name, name), pointer in list(_sector_hidden.items()):
        try:
            layer = _lookup_layer(scene_name, layer_name)
            if layer:
                for lc in _layer_collections(layer.layer_collection):
                    if lc.name == name and lc.as_pointer() == pointer:
                        lc.hide_viewport = False
                        break
        except (RuntimeError, ReferenceError):
            pass
    _sector_hidden.clear()

def _sector_bounds(context):
    from mathutils import Vector
    result = []
    for lc in _districts(context):
        # Buildings and furniture are valid sectors. Vehicles stay visible;
        # their interiors and interactivity are handled separately.
        if not lc.name.startswith(('04 | Casas','05 | Mobiliario','DISTRICT |','DISTRITO |')):
            continue
        lo = [float('inf')]*3
        hi = [float('-inf')]*3
        for ob in lc.collection.all_objects:
            if ob.type not in {'MESH','CURVE','FONT','SURFACE'}:
                continue
            for corner in ob.bound_box:
                v = ob.matrix_world @ Vector(corner)
                for i in range(3):
                    lo[i] = min(lo[i],v[i])
                    hi[i] = max(hi[i],v[i])
        if all(lo[i] <= hi[i] for i in range(3)):
            result.append((lc.name,lc.as_pointer(),tuple(lo),tuple(hi)))
    return result

def _update_sectors(win, position, space):
    sc,layer=win.scene,win.view_layer
    if not sc.mycity_auto_sectors or space.region_3d.view_perspective == 'CAMERA':
        changed=bool(_sector_hidden)
        _restore_sectors()
        return changed
    # Only update cached bounds; refresh by restarting LOD after new construction.
    lookup={lc.name:lc for lc in _layer_collections(layer.layer_collection)}
    changed=False
    active=layer.objects.active
    for name,pointer,lo,hi in _lod.get('sectors',[]):
        lc=lookup.get(name)
        if not lc or lc.as_pointer()!=pointer or lc.exclude:
            continue
        key=(sc.name,layer.name,name)
        dist=sum(max(lo[i]-position[i],0,position[i]-hi[i])**2 for i in range(3))**.5
        # Protect the selected/active asset from being hidden while editing.
        protected=bool(active and lc.collection.all_objects.get(active.name))
        if key in _sector_hidden:
            if protected or dist<sc.mycity_sector_distance*.8:
                lc.hide_viewport=False
                del _sector_hidden[key]
                changed=True
        elif not protected and dist>sc.mycity_sector_distance and not lc.hide_viewport:
            lc.hide_viewport=True
            _sector_hidden[key]=pointer
            changed=True
    return changed

def _detail_candidates(scene):
    candidates = []
    van = scene.objects.get('VAN | CONTROL')
    if van:
        # Traverse descendants once; no repeated full-city scans in timer.
        stack = list(van.children)
        while stack:
            ob = stack.pop()
            stack.extend(ob.children)
            if ob.type == 'MESH' and ob.name.startswith(_DETAIL_PREFIXES):
                candidates.append((ob.name, ob.as_pointer(), van.name))
    seen = {c[0] for c in candidates}
    for ob in scene.objects:
        if ob.type == 'MESH' and ob.get('mycity_lod_detail') and ob.name not in seen:
            candidates.append((ob.name, ob.as_pointer(), ob.name))
    return candidates

def _viewport_position(space, scene):
    rv = space.region_3d
    if rv.view_perspective == 'CAMERA':
        cam = space.camera if space.use_local_camera else scene.camera
        if cam:
            return cam.matrix_world.translation.copy()
    return rv.view_matrix.inverted().translation.copy()

def _lod_tick():
    if not _lod:
        return None
    try:
        win = next((w for w in bpy.context.window_manager.windows
                    if w.as_pointer() == _lod['window']), None)
        if not win or win.scene.name != _lod['scene'] or win.view_layer.name != _lod['layer']:
            _stop_lod()
            return None
        area = next((a for a in win.screen.areas if a.as_pointer() == _lod['area']
                     and a.type == 'VIEW_3D'), None)
        if not area:
            _stop_lod()
            return None
        space = area.spaces.active
        # Never simplify a rendered preview, edit mode or local view.
        if space.shading.type == 'RENDERED' or space.local_view or win.view_layer.objects.active and win.view_layer.objects.active.mode != 'OBJECT':
            if _lod_hidden or _sector_hidden:
                _restore_lod()
                _restore_sectors()
                _perf_cache.clear()
                area.tag_redraw()
            return .75
        layer = win.view_layer
        sc = win.scene
        position = _viewport_position(space, sc)
        limit = sc.mycity_lod_distance
        van = sc.objects.get('VAN | CONTROL')
        # Keep full van detail when a door is open or its hierarchy is selected.
        van_open = bool(van and any(isinstance(van[k], (float,int)) and van[k] > .005
            for k in van.keys() if k[:2] in ('01','02','03','04','05')))
        van_selected = False
        active = layer.objects.active
        while active and van:
            if active == van:
                van_selected = True
                break
            active = active.parent
        changed = _update_sectors(win, position, space)
        dist_cache = {}
        for name,pointer,root_name in _lod['candidates']:
            ob = layer.objects.get(name)
            target = sc.objects.get(root_name)
            if not ob or not target or ob.as_pointer() != pointer:
                continue
            key = (sc.name, layer.name, name)
            if root_name not in dist_cache:
                dist_cache[root_name] = (position - target.matrix_world.translation).length
            dist = dist_cache[root_name]
            protected = ob.select_get(view_layer=layer) or (van and root_name == van.name and (van_open or van_selected))
            if key in _lod_hidden:
                if protected or dist < limit*.8:
                    ob.hide_set(False, view_layer=layer)
                    del _lod_hidden[key]
                    changed = True
            elif not protected and dist > limit and not ob.hide_get(view_layer=layer):
                ob.hide_set(True, view_layer=layer)
                _lod_hidden[key] = pointer
                changed = True
        if changed:
            _perf_cache.clear()
            area.tag_redraw()
    except Exception as exc:
        print('My City LOD paused:', exc)
        _stop_lod()
        return None
    return .75

class VMV_OT_lod_toggle(bpy.types.Operator):
    bl_idname = 'vmv_city.lod_toggle'
    bl_label = 'Activar / detener LOD'
    bl_description = 'LOD por distancia del visor, reversible. No modifica el render'
    @classmethod
    def poll(cls, context):
        return perf_view(context) and not _busy
    def execute(self, context):
        if _lod:
            _stop_lod()
            if bpy.app.timers.is_registered(_lod_tick):
                bpy.app.timers.unregister(_lod_tick)
        else:
            _lod.update(window=context.window.as_pointer(), area=context.area.as_pointer(),
                        scene=context.scene.name, layer=context.view_layer.name,
                        candidates=_detail_candidates(context.scene), sectors=_sector_bounds(context))
            if not bpy.app.timers.is_registered(_lod_tick):
                bpy.app.timers.register(_lod_tick, first_interval=.1)
        context.area.tag_redraw()
        return {'FINISHED'}

class VMV_OT_district_show(bpy.types.Operator):
    bl_idname = 'vmv_city.district_show'
    bl_label = 'Mostrar todos los sectores'
    bl_description = 'Hace visibles los sectores gestionados en esta capa de vista'
    @classmethod
    def poll(cls, context):
        return perf_view(context) and not _busy
    def execute(self, context):
        context.scene.mycity_auto_sectors = False
        _restore_sectors()
        for lc in _districts(context):
            lc.hide_viewport = False
        _perf_cache.clear()
        return {'FINISHED'}

# Draw intervals are a proxy for viewport refresh rate, not GPU FPS.
# No forced redraw; sample only actual draw callbacks.
def _sample_draw():
    area = bpy.context.area
    if area and area.type == 'VIEW_3D':
        key = area.as_pointer()
        samples = _draw_samples.setdefault(key, deque(maxlen=120))
        samples.append(time.monotonic())

def _recent_draw_rate(context):
    now = time.monotonic()
    arr = [t for t in _draw_samples.get(context.area.as_pointer(), ()) if now-t < 2.0]
    if len(arr) < 4 or arr[-1]-arr[0] < .25:
        return None
    return (len(arr)-1)/(arr[-1]-arr[0])

def _process_ram_mb():
    try:
        if os.name == 'nt':
            import ctypes as c
            from ctypes import wintypes as w
            class PMC(c.Structure):
                _fields_ = [('cb',w.DWORD),('PageFaultCount',w.DWORD)] + [
                    (n,c.c_size_t) for n in ('PeakWorkingSetSize','WorkingSetSize',
                    'QuotaPeakPagedPoolUsage','QuotaPagedPoolUsage','QuotaPeakNonPagedPoolUsage',
                    'QuotaNonPagedPoolUsage','PagefileUsage','PeakPagefileUsage')]
            k = c.WinDLL('kernel32',use_last_error=True)
            p = c.WinDLL('psapi',use_last_error=True)
            k.GetCurrentProcess.restype = w.HANDLE
            p.GetProcessMemoryInfo.argtypes = [w.HANDLE,c.POINTER(PMC),w.DWORD]
            p.GetProcessMemoryInfo.restype = w.BOOL
            mem = PMC()
            mem.cb = c.sizeof(mem)
            if p.GetProcessMemoryInfo(k.GetCurrentProcess(),c.byref(mem),mem.cb):
                return mem.WorkingSetSize / 1048576
        elif os.path.isfile('/proc/self/status'):
            with open('/proc/self/status',encoding='utf-8') as fp:
                for line in fp:
                    if line.startswith('VmRSS:'):
                        return int(line.split()[1])/1024
    except (OSError, ValueError, AttributeError):
        pass
    return None

_system_stats = {}

class VMV_OT_system_measure(bpy.types.Operator):
    bl_idname = 'vmv_city.system_measure'
    bl_label = 'Medir RAM y redibujado'
    bl_description = 'RAM residente del proceso y frecuencia reciente de redibujado, no FPS de GPU'
    @classmethod
    def poll(cls, context):
        return perf_view(context)
    def execute(self, context):
        _system_stats[perf_key(context)] = (_process_ram_mb(),_recent_draw_rate(context))
        return {'FINISHED'}

class VMV_PT_worldperf(bpy.types.Panel):
    bl_label = 'LOD y sectores'
    bl_idname = 'VMV_PT_worldperf'
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = 'My City'
    bl_parent_id = 'VMV_PT_city'
    def draw(self, context):
        layout = self.layout
        layout.prop(context.scene,'mycity_lod_distance',text='Distancia LOD (m)')
        layout.operator('vmv_city.lod_toggle', text='Detener LOD / restaurar' if _lod else 'Activar LOD automatico')
        if _lod:
            layout.label(text=f'Detalles ocultos: {len(_lod_hidden)}')
        layout.label(text='Selecciona VAN | CONTROL para detalle.')
        layout.label(text='Puertas abiertas: detalle completo.')
        layout.separator()
        layout.label(text='Sectores del visor')
        layout.prop(context.scene,'mycity_auto_sectors',text='Ocultar sectores lejanos')
        if context.scene.mycity_auto_sectors:
            layout.prop(context.scene,'mycity_sector_distance',text='Radio sectores (m)')
            layout.label(text='Requiere LOD activo; no en camara.')
            layout.label(text=f'Sectores auto ocultos: {len(_sector_hidden)}')
        for lc in _districts(context):
            row = layout.row(align=True)
            row.prop(lc,'hide_viewport',text='',icon='HIDE_ON' if lc.hide_viewport else 'HIDE_OFF',emboss=False)
            row.label(text=lc.name)
        layout.operator('vmv_city.district_show')
        layout.label(text='Ocultar no descarga RAM ni cambia render.')
        layout.separator()
        layout.operator('vmv_city.system_measure')
        stats = _system_stats.get(perf_key(context))
        if stats is not None:
            ram,rate = stats
            layout.label(text='RAM Blender: '+(f'{ram:,.0f} MiB' if ram is not None else 'No disponible'))
            layout.label(text='Redibujado: '+(f'{rate:.1f}/s aprox.' if rate is not None else 'Mueve el visor y vuelve a medir'))
        layout.label(text='Redibujado no es FPS de GPU.')

@persistent
def _mycity_before_save(*args):
    # Never save temporary LOD hide states into the .blend.
    _restore_lod()
    _restore_sectors()

@persistent
def _mycity_before_load(*args):
    _stop_lod()
    _draw_samples.clear()
    _system_stats.clear()
    if bpy.app.timers.is_registered(_lod_tick):
        bpy.app.timers.unregister(_lod_tick)

def _worldperf_register():
    global _draw_handle
    bpy.types.Scene.mycity_lod_distance = bpy.props.FloatProperty(
        name='Distancia LOD',default=28.0,min=8.0,max=500.0)
    bpy.types.Scene.mycity_auto_sectors = bpy.props.BoolProperty(name='Sectores automaticos',default=False)
    bpy.types.Scene.mycity_sector_distance = bpy.props.FloatProperty(name='Radio sectores',default=65.0,min=20.0,max=1000.0)
    bpy.app.handlers.save_pre.append(_mycity_before_save)
    bpy.app.handlers.load_pre.append(_mycity_before_load)
    _draw_handle = bpy.types.SpaceView3D.draw_handler_add(_sample_draw,(), 'WINDOW','POST_PIXEL')

def _worldperf_unregister():
    global _draw_handle
    _stop_lod()
    if bpy.app.timers.is_registered(_lod_tick):
        bpy.app.timers.unregister(_lod_tick)
    if _draw_handle is not None:
        bpy.types.SpaceView3D.draw_handler_remove(_draw_handle,'WINDOW')
        _draw_handle=None
    for handlers,fn in [(bpy.app.handlers.save_pre,_mycity_before_save),(bpy.app.handlers.load_pre,_mycity_before_load)]:
        if fn in handlers:
            handlers.remove(fn)
    _draw_samples.clear()
    _system_stats.clear()
    del bpy.types.Scene.mycity_lod_distance
    del bpy.types.Scene.mycity_auto_sectors
    del bpy.types.Scene.mycity_sector_distance

classes=(VMV_OT_sync,VMV_OT_build,VMV_OT_apply,VMV_PT_panel,VMV_OT_perf_refresh,VMV_OT_perf_mode,VMV_PT_performance,VMV_OT_lod_toggle,VMV_OT_district_show,VMV_OT_system_measure,VMV_PT_worldperf)
def register():
    for cls in classes: bpy.utils.register_class(cls)
    bpy.types.Scene.vmv_repo=bpy.props.StringProperty(name='Repositorio local',subtype='DIR_PATH')
    bpy.types.Scene.vmv_update=bpy.props.StringProperty(name='Archivo de actualización')
    _worldperf_register()
def unregister():
    _worldperf_unregister()
    _perf_cache.clear()
    if bpy.app.timers.is_registered(poll_git): bpy.app.timers.unregister(poll_git)
    del bpy.types.Scene.vmv_repo; del bpy.types.Scene.vmv_update
    for cls in reversed(classes): bpy.utils.unregister_class(cls)
if __name__=='__main__': register()
