# -*- coding: utf-8 -*-
"""My City Studio: local Git synchronization and explicit scene operations."""
bl_info = {'name':'My City Studio','author':'My City','version':(0,6,0),'blender':(4,2,0),'location':'View3D > Sidebar > My City','description':'Synchronize a local My City repository and apply reviewed scripts','category':'3D View'}
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


# V0.4 - lightweight construction planning markers and explicit exports.
import json
from datetime import datetime, timezone
from math import degrees
from mathutils import Vector
from bpy_extras.io_utils import ExportHelper

_PLAN_TYPES = {
    'LAGO': ('Lago',(24,18,.30),(.12,.56,.92,1)),
    'PARQUE': ('Parque',(24,24,.30),(.20,.72,.28,1)),
    'CASA': ('Casa',(8,10,5),(.92,.60,.25,1)),
    'EDIFICIO': ('Edificio',(14,14,12),(.65,.44,.90,1)),
    'GASOLINERA': ('Gasolinera',(20,18,.30),(.91,.25,.16,1)),
    'ESTACIONAMIENTO': ('Estacionamiento',(18,12,.30),(.68,.72,.77,1)),
    'OTRO': ('Otro',(10,10,.30),(.94,.79,.18,1)),
}
_PLAN_VERTS = [(-.5,-.5,-.5),(.5,-.5,-.5),(.5,.5,-.5),(-.5,.5,-.5),
               (-.5,-.5,.5),(.5,-.5,.5),(.5,.5,.5),(-.5,.5,.5)]
_PLAN_EDGES = [(0,1),(1,2),(2,3),(3,0),(4,5),(5,6),(6,7),(7,4),
               (0,4),(1,5),(2,6),(3,7)]

def _plan_collection(scene):
    name = '09 | Planificacion urbana'
    col = scene.collection.children.get(name)
    if col is None:
        col = bpy.data.collections.new(name)
        scene.collection.children.link(col)
    col.hide_render = True
    return col

def _is_marker(ob):
    return bool(ob and ob.get('mycity_plan_type') in _PLAN_TYPES and ob.type=='MESH')

def _plan_markers(scene):
    return sorted((ob for ob in scene.objects if _is_marker(ob)),key=lambda o:o.name)

def _plan_payload(context):
    context.view_layer.update()
    scene=context.scene
    def rounded(values):
        return [round(float(x),5) for x in values]
    markers=[]
    for ob in _plan_markers(scene):
        mw=ob.matrix_world.copy()
        # The eight original cube vertices define the exact world footprint.
        # Using the transformed vertices also supports rotation and applied scale.
        if len(ob.data.vertices)!=8:
            raise ValueError(ob.name+': el marcador debe conservar sus ocho vertices.')
        corners=[mw@v.co for v in ob.data.vertices]
        axes=[(corners[b]-corners[a]).length for a,b in [(0,1),(0,3),(0,4)]]
        center=sum(corners,Vector((0,0,0)))/8
        rotation=mw.to_quaternion().to_euler('XYZ')
        markers.append({
            'name':ob.name,
            'type':ob['mycity_plan_type'],
            'note':str(ob.get('mycity_plan_note','')),
            'center_xyz':rounded(center),
            'size_local_xyz':rounded(axes),
            'rotation_xyz_deg':rounded(degrees(a) for a in rotation),
            'world_corners_xyz':[rounded(c) for c in corners],
        })
    return {
        'schema':'mycity.plan.v1',
        'scene':scene.name,
        'coordinate_system':'Blender XYZ, Z up',
        'unit_system':scene.unit_settings.system,
        'meters_per_blender_unit':scene.unit_settings.scale_length if scene.unit_settings.system!='NONE' else 1.0,
        'coordinate_units':'Blender units; default My City uses 1 unit = 1 meter',
        'markers':markers,
    }

class VMV_OT_plan_add(bpy.types.Operator):
    bl_idname='vmv_city.plan_add'
    bl_label='Agregar marcador'
    bl_description='Crea una caja guia en el cursor 3D; no construye ni modifica el terreno'
    bl_options={'REGISTER','UNDO'}
    kind: bpy.props.EnumProperty(items=[(key,val[0],val[0]) for key,val in _PLAN_TYPES.items()],default='LAGO')
    @classmethod
    def poll(cls,context):
        return perf_view(context) and context.mode=='OBJECT' and not _busy
    def execute(self,context):
        label,size,color=_PLAN_TYPES[self.kind]
        col=_plan_collection(context.scene)
        n=1
        while bpy.data.objects.get(f'{self.kind}_{n:02d}'):
            n+=1
        name=f'{self.kind}_{n:02d}'
        me=bpy.data.meshes.new(name+' | guia')
        me.from_pydata(_PLAN_VERTS,_PLAN_EDGES,[])
        me.update()
        ob=bpy.data.objects.new(name,me)
        col.objects.link(ob)
        ob.location=context.scene.cursor.location.copy()
        ob.scale=size
        # Buildings rise from the cursor; thin footprint markers sit above it.
        ob.location.z+=size[2]/2
        ob.color=color
        ob.show_in_front=True
        ob.show_name=True
        ob.display_type='WIRE'
        ob.hide_render=True
        ob['mycity_plan_type']=self.kind
        ob['mycity_plan_note']=''
        for selected in context.selected_objects:
            selected.select_set(False)
        context.view_layer.update()
        if context.view_layer.objects.get(ob.name) is not None and ob.visible_get(view_layer=context.view_layer):
            ob.select_set(True)
            context.view_layer.objects.active=ob
        else:
            self.report({'WARNING'},'Marcador creado; muestra la coleccion 09 para seleccionarlo.')
        _perf_cache.clear()
        self.report({'INFO'},name+' creado. G mover, S escalar, R rotar.')
        return {'FINISHED'}

class VMV_OT_plan_copy(bpy.types.Operator):
    bl_idname='vmv_city.plan_copy'
    bl_label='Copiar plan para ChatGPT'
    bl_description='Copia el JSON de todos los marcadores al portapapeles'
    @classmethod
    def poll(cls,context):
        return perf_view(context) and bool(_plan_markers(context.scene))
    def execute(self,context):
        try:
            payload=_plan_payload(context)
            context.window_manager.clipboard=json.dumps(payload,ensure_ascii=False,indent=2)
        except Exception as exc:
            self.report({'ERROR'},str(exc))
            return {'CANCELLED'}
        self.report({'INFO'},f'{len(payload["markers"])} marcadores copiados. Pegalos en el chat.')
        return {'FINISHED'}

class VMV_OT_plan_export(bpy.types.Operator,ExportHelper):
    bl_idname='vmv_city.plan_export'
    bl_label='Exportar plan JSON'
    bl_description='Guarda una copia del plan para compartir; no sube archivos a GitHub'
    filename_ext='.json'
    filter_glob: bpy.props.StringProperty(default='*.json',options={'HIDDEN'})
    @classmethod
    def poll(cls,context):
        return perf_view(context) and bool(_plan_markers(context.scene))
    def invoke(self,context,event):
        folder=Path(bpy.data.filepath).parent if bpy.data.filepath else Path.home()
        stamp=datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')
        self.filepath=str(folder/f'mycity_plan_{stamp}.json')
        return ExportHelper.invoke(self,context,event)
    def execute(self,context):
        try:
            payload=_plan_payload(context)
            Path(self.filepath).write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
        except Exception as exc:
            self.report({'ERROR'},str(exc))
            return {'CANCELLED'}
        self.report({'INFO'},f'{len(payload["markers"])} marcadores exportados.')
        return {'FINISHED'}

class VMV_PT_planner(bpy.types.Panel):
    bl_label='Planificador urbano'
    bl_idname='VMV_PT_planner'
    bl_space_type='VIEW_3D'
    bl_region_type='UI'
    bl_category='My City'
    bl_parent_id='VMV_PT_city'
    def draw(self,context):
        layout=self.layout
        layout.label(text='1. Coloca el cursor 3D (Shift + clic derecho).')
        grid=layout.grid_flow(columns=2,even_columns=True,align=True)
        for key,(label,size,color) in _PLAN_TYPES.items():
            op=grid.operator('vmv_city.plan_add',text=label)
            op.kind=key
        layout.label(text='2. G mover | S escalar | R rotar.')
        layout.label(text='F2 renombra. X elimina una guia.')
        ob=context.view_layer.objects.active
        if _is_marker(ob):
            box=layout.box()
            box.prop(ob,'name',text='Nombre')
            box.prop(ob,'location',text='Posicion')
            box.prop(ob,'dimensions',text='Dimensiones')
            box.prop(ob,'rotation_euler',text='Rotacion')
            box.prop(ob,'["mycity_plan_note"]',text='Instrucciones')
        layout.separator()
        layout.label(text=f'Marcadores: {len(_plan_markers(context.scene))}')
        layout.operator('vmv_city.plan_copy',icon='COPYDOWN')
        layout.operator('vmv_city.plan_export',icon='EXPORT')
        layout.label(text='Las guias no aparecen en el render.')


# V0.5 - modular asset library and terrain-aware placement.
from math import cos, sin, hypot, sqrt
from mathutils.bvhtree import BVHTree

_asset_catalog={}
def _library_files(context):
    # Refresh after a Git sync or when a different repository is selected.
    key=(context.scene.vmv_repo,_status)
    if key not in _asset_catalog:
        try:
            folder=root(context)/'assets'
            result=tuple((p.stem,p.stem.replace('_',' ').capitalize())
                         for p in sorted(folder.glob('*.py'))
                         if p.stem.isidentifier() and not p.stem.startswith('_'))
        except Exception:
            result=()
        _asset_catalog.clear()
        _asset_catalog[key]=result
    return _asset_catalog[key]

def _asset_terrain(context):
    ob=context.scene.objects.get('TERRENO | 160 x 220 m')
    if not ob or ob.type!='MESH':
        raise ValueError('Se necesita el terreno de la actualizacion 002.')
    if ob.modifiers:
        raise ValueError('Este terreno tiene modificadores; no se nivelara.')
    return ob

def _preview(context):
    return next((ob for ob in context.scene.objects if ob.get('mycity_asset_state')=='PREVIEW'),None)

def _surface(terrain):
    mw=terrain.matrix_world.copy()
    vertices=[mw@v.co for v in terrain.data.vertices]
    faces=[tuple(p.vertices) for p in terrain.data.polygons]
    if not vertices or not faces:raise ValueError('Terreno sin geometria.')
    return vertices,BVHTree.FromPolygons(vertices,faces)

def _ground(tree,x,y):
    hit,_,_,_=tree.ray_cast(Vector((x,y,10000)),Vector((0,0,-1)),20000)
    if hit is None:raise ValueError('La ubicacion esta fuera del terreno.')
    return float(hit.z)

def _asset_ready(context):
    return perf_view(context) and context.mode=='OBJECT' and not _busy

def _select_asset(context,ob):
    for selected in context.selected_objects:selected.select_set(False)
    context.view_layer.update()
    ob.select_set(True);context.view_layer.objects.active=ob

def _asset_template(context,asset_id):
    if not asset_id.isidentifier() or asset_id.startswith('_'):
        raise ValueError('Identificador de modelo no valido.')
    folder=(root(context)/'assets').resolve()
    file=(folder/(asset_id+'.py')).resolve()
    if file.parent!=folder or not file.is_file():
        raise ValueError('Modelo no encontrado. Sincroniza GitHub.')
    module=runpy.run_path(str(file))
    if module.get('ASSET_ID')!=asset_id or not callable(module.get('build')):
        raise ValueError('Formato de modelo no valido.')
    width,depth=map(float,module['SIZE'])
    if not (0<width<=100 and 0<depth<=100):
        raise ValueError('Dimensiones de modelo no validas.')
    name=f'MYCITY TEMPLATE | {asset_id} v{int(module["VERSION"])}'
    col=bpy.data.collections.get(name)
    if col is None:
        col=bpy.data.collections.new(name)
        try:
            module['build'](col)
            if not col.objects:raise ValueError('El modelo no contiene geometria.')
            col.use_fake_user=True
        except Exception:
            for ob in list(col.objects):
                me=ob.data
                bpy.data.objects.remove(ob,do_unlink=True)
                if me and isinstance(me,bpy.types.Mesh) and me.users==0:bpy.data.meshes.remove(me)
            bpy.data.collections.remove(col)
            raise
    return col,width,depth,str(module.get('LABEL',asset_id))

class VMV_OT_asset_preview(bpy.types.Operator):
    bl_idname='vmv_city.asset_preview'
    bl_label='Previsualizar modelo'
    bl_description='Carga un modelo sincronizado y lo coloca en el cursor, sin cambiar el suelo'
    bl_options={'REGISTER','UNDO'}
    asset_id:bpy.props.StringProperty()
    @classmethod
    def poll(cls,context):
        return _asset_ready(context) and _preview(context) is None
    def execute(self,context):
        try:
            terrain=_asset_terrain(context)
            _,tree=_surface(terrain)
            p=context.scene.cursor.location.copy()
            p.z=_ground(tree,p.x,p.y)+.01
            col,w,d,label=_asset_template(context,self.asset_id)
            ob=bpy.data.objects.new(label+' | PREVIEW',None)
            ob.instance_type='COLLECTION';ob.instance_collection=col
            ob.empty_display_type='PLAIN_AXES';ob.empty_display_size=1.2
            ob.show_name=True;ob.hide_render=True
            ob['mycity_asset_state']='PREVIEW'
            ob['mycity_asset_id']=self.asset_id
            ob['mycity_width']=w;ob['mycity_depth']=d
            context.scene.collection.objects.link(ob)
            ob.location=p
            ob.lock_rotation=(True,True,False)
            _select_asset(context,ob)
            _perf_cache.clear()
            self.report({'INFO'},'Modelo listo. G X/Y, R Z; confirma para nivelar.')
        except Exception as exc:
            self.report({'ERROR'},str(exc));return {'CANCELLED'}
        return {'FINISHED'}

class VMV_OT_asset_snap(bpy.types.Operator):
    bl_idname='vmv_city.asset_snap'
    bl_label='Ajustar altura al suelo'
    bl_description='Alinea la previsualizacion con el suelo bajo su centro, sin modificarlo'
    bl_options={'REGISTER','UNDO'}
    @classmethod
    def poll(cls,context):return _asset_ready(context) and _preview(context) is not None
    def execute(self,context):
        try:
            ob=_preview(context)
            _,tree=_surface(_asset_terrain(context))
            ob.location.z=_ground(tree,ob.location.x,ob.location.y)+.01
            _select_asset(context,ob)
        except Exception as exc:
            self.report({'ERROR'},str(exc));return {'CANCELLED'}
        return {'FINISHED'}

def _overlap(a,b):
    return a[0]<b[2] and a[2]>b[0] and a[1]<b[3] and a[3]>b[1]

def _asset_grade(context,ob):
    terrain=_asset_terrain(context)
    context.view_layer.update()
    if ob.parent or abs(ob.rotation_euler.x)>.001 or abs(ob.rotation_euler.y)>.001:
        raise ValueError('Usa solo rotacion Z y un modelo sin padre.')
    sx,sy,sz=ob.scale
    if min(sx,sy,sz)<.5 or max(sx,sy,sz)>2 or max(sx,sy,sz)-min(sx,sy,sz)>.001:
        raise ValueError('Usa escala uniforme entre 0.5 y 2.')
    cx,cy=ob.location.x,ob.location.y
    angle=ob.rotation_euler.z
    c,s=cos(angle),sin(angle)
    a=float(ob['mycity_width'])*sx/2;b=float(ob['mycity_depth'])*sy/2
    verts,tree=_surface(terrain)
    # Identify grid spacing so every face under the base becomes flat,
    # including cells whose corners fall just outside the footprint.
    xs=sorted(set(round(v.x,4) for v in verts))
    ys=sorted(set(round(v.y,4) for v in verts))
    if len(xs)*len(ys)!=len(verts) or len(xs)<2 or len(ys)<2:
        raise ValueError('Se requiere la cuadricula regular de My City.')
    cellx=max(y-x for x,y in zip(xs,xs[1:]))
    celly=max(y-x for x,y in zip(ys,ys[1:]))
    if max(cellx,celly)>2.1:raise ValueError('Cuadricula demasiado gruesa para nivelar.')
    flat=hypot(cellx,celly)+.05
    blend=4.0
    margin=flat+blend
    ex=abs(c)*(a+margin)+abs(s)*(b+margin)
    ey=abs(s)*(a+margin)+abs(c)*(b+margin)
    bounds=(cx-ex,cy-ey,cx+ex,cy+ey)
    if bounds[0]<xs[0] or bounds[1]<ys[0] or bounds[2]>xs[-1] or bounds[3]>ys[-1]:
        raise ValueError('Deja mas espacio entre el modelo y el borde de la ciudad.')
    # Conservative XY protection: avoid existing built sectors, roads and
    # grouped vegetation. False positives are intentional for this first release.
    protected=[
        (-15,ys[0],15,ys[-1],'Boulevard y casas'),
        (-53,65,-26,86,'Lago'),
        (-56,83,-29,100,'Parque'),
    ]
    for x0,y0,x1,y1,label in protected:
        if _overlap(bounds,(x0,y0,x1,y1)):
            raise ValueError('Zona protegida: '+label+'. Mueve el modelo mas lejos.')
    for other in context.scene.objects:
        if other==ob or other==terrain or _is_marker(other):continue
        if other.get('mycity_asset_state')=='PLACED':
            prior=other.get('mycity_grade_bounds')
            if prior and _overlap(bounds,tuple(prior)):
                raise ValueError('Demasiado cerca de '+other.name)
        if other.type!='MESH':continue
        corners=[other.matrix_world@Vector(p) for p in other.bound_box]
        bb=(min(v.x for v in corners),min(v.y for v in corners),
            max(v.x for v in corners),max(v.y for v in corners))
        if _overlap(bounds,bb):
            raise ValueError('Zona ocupada por '+other.name+'. Elige otro lugar.')
    heights=[]
    for i in range(5):
        for j in range(5):
            u=a*(i/2-1);v=b*(j/2-1)
            heights.append(_ground(tree,cx+c*u-s*v,cy+s*u+c*v))
    level=sum(heights)/len(heights)
    inv=terrain.matrix_world.inverted()
    changes=[]
    for i,v in enumerate(verts):
        dx,dy=v.x-cx,v.y-cy
        u=abs(c*dx+s*dy);w=abs(-s*dx+c*dy)
        distance=hypot(max(0,u-a),max(0,w-b))
        if distance>=margin:continue
        t=max(0,min(1,(distance-flat)/blend))
        t=t*t*(3-2*t)
        z=level*(1-t)+v.z*t
        changes.append((i,inv@Vector((v.x,v.y,z))))
    if not changes:raise ValueError('No se encontro superficie que nivelar.')
    return terrain,changes,level,bounds

class VMV_OT_asset_place(bpy.types.Operator):
    bl_idname='vmv_city.asset_place'
    bl_label='Construir y nivelar terreno'
    bl_description='Confirma la posicion y crea una plataforma plana con transicion suave; Ctrl+Z deshace'
    bl_options={'REGISTER','UNDO'}
    @classmethod
    def poll(cls,context):return _asset_ready(context) and _preview(context) is not None
    def invoke(self,context,event):return context.window_manager.invoke_confirm(self,event)
    def execute(self,context):
        ob=_preview(context)
        try:
            if not bpy.data.filepath:raise ValueError('Guarda primero la ciudad en un archivo .blend.')
            terrain,changes,level,bounds=_asset_grade(context,ob)
        except Exception as exc:
            self.report({'ERROR'},str(exc));return {'CANCELLED'}
        # Preserve topology/materials and keep the original data until commit.
        old=terrain.data
        new=old.copy()
        try:
            for i,co in changes:new.vertices[i].co=co
            new.update()
        except Exception as exc:
            bpy.data.meshes.remove(new)
            self.report({'ERROR'},str(exc));return {'CANCELLED'}
        new.name='Relieve | Plataforma '+ob['mycity_asset_id']
        col=bpy.data.collections.new('DISTRITO | '+ob['mycity_asset_id'])
        context.scene.collection.children.link(col)
        col.objects.link(ob)
        context.scene.collection.objects.unlink(ob)
        terrain.data=new
        ob.location.z=level+.008
        ob.name=ob.name.replace(' | PREVIEW',' | Construido')
        ob.hide_render=False;ob.show_name=False
        ob['mycity_asset_state']='PLACED'
        ob['mycity_grade_bounds']=list(bounds)
        ob.lock_location=(True,True,True)
        ob.lock_rotation=(True,True,True)
        ob.lock_scale=(True,True,True)
        if old.users==0:bpy.data.meshes.remove(old)
        _perf_cache.clear()
        self.report({'INFO'},'Construccion colocada. Guarda el archivo.')
        return {'FINISHED'}

class VMV_OT_asset_cancel(bpy.types.Operator):
    bl_idname='vmv_city.asset_cancel'
    bl_label='Cancelar previsualizacion'
    bl_options={'REGISTER','UNDO'}
    @classmethod
    def poll(cls,context):return _asset_ready(context) and _preview(context) is not None
    def execute(self,context):
        bpy.data.objects.remove(_preview(context),do_unlink=True)
        _perf_cache.clear()
        return {'FINISHED'}

class VMV_OT_asset_select(bpy.types.Operator):
    bl_idname='vmv_city.asset_select'
    bl_label='Seleccionar modelo'
    @classmethod
    def poll(cls,context):return _asset_ready(context) and _preview(context) is not None
    def execute(self,context):
        _select_asset(context,_preview(context))
        return {'FINISHED'}

class VMV_PT_library(bpy.types.Panel):
    bl_label='Biblioteca de construcciones'
    bl_idname='VMV_PT_library'
    bl_space_type='VIEW_3D'
    bl_region_type='UI'
    bl_category='My City'
    bl_parent_id='VMV_PT_city'
    def draw(self,context):
        layout=self.layout
        ob=_preview(context)
        if not ob:
            layout.label(text='1. Coloca el cursor 3D en terreno libre.')
            layout.label(text='Shift + clic derecho')
            assets=_library_files(context)
            if not assets:layout.label(text='Sin modelos. Sincroniza GitHub.')
            for asset_id,label in assets:
                op=layout.operator('vmv_city.asset_preview',text=label,icon='MESH_CUBE')
                op.asset_id=asset_id
        else:
            layout.label(text='Previsualizacion: '+ob['mycity_asset_id'])
            layout.operator('vmv_city.asset_select',icon='RESTRICT_SELECT_OFF')
            layout.label(text='G X / G Y mover; R Z rotar; S escalar.')
            layout.prop(ob,'location',text='Posicion')
            layout.operator('vmv_city.asset_snap',icon='SNAP_FACE')
            layout.operator('vmv_city.asset_place',icon='CHECKMARK')
            layout.operator('vmv_city.asset_cancel',icon='X')
            layout.label(text='Guarda una copia antes de construir.')
        layout.label(text='Ctrl+Z revierte la ultima construccion.')


# V0.6 - export a local game snapshot. No changes to city geometry.
class VMV_OT_game_export(bpy.types.Operator):
    bl_idname='vmv_city.game_export'
    bl_label='Exportar al videojuego'
    bl_description='Exporta la ciudad actual a game/city.glb, sin subirla a GitHub'
    @classmethod
    def poll(cls,context):
        return perf_view(context) and context.mode=='OBJECT' and not _busy
    def invoke(self,context,event):
        return context.window_manager.invoke_confirm(self,event)
    def execute(self,context):
        global _status
        temp=None
        try:
            folder=root(context)/'game'
            if not (folder/'project.godot').is_file():
                raise ValueError('Sincroniza GitHub primero: falta el proyecto Godot.')
            if not bpy.data.filepath:
                raise ValueError('Guarda primero tu ciudad .blend.')
            if _preview(context):
                raise ValueError('Confirma o cancela el modelo en previsualizacion antes de exportar.')
            # Restore automatic viewport-only hiding before the exporter evaluates the scene.
            _restore_lod()
            _restore_sectors()
            context.view_layer.update()
            temp=folder/'city_export_tmp.glb'
            result=bpy.ops.export_scene.gltf(
                filepath=str(temp),export_format='GLB',
                use_selection=False,use_visible=False,use_renderable=True,
                use_active_scene=True,export_yup=True,export_apply=True,
                export_cameras=False,export_lights=False,export_animations=False,
                export_extras=False,export_gpu_instances=False)
            if 'FINISHED' not in result or not temp.is_file() or temp.stat().st_size<20:
                raise ValueError('La exportacion GLB no termino correctamente.')
            os.replace(temp,folder/'city.glb')
            _status='Videojuego: city.glb actualizado. Abre Godot y pulsa F5.'
            self.report({'INFO'},'Ciudad exportada a game/city.glb. Abre Godot y pulsa F5.')
            return {'FINISHED'}
        except Exception as exc:
            if temp is not None:
                try:temp.unlink(missing_ok=True)
                except OSError:pass
            self.report({'ERROR'},str(exc))
            return {'CANCELLED'}

class VMV_PT_game(bpy.types.Panel):
    bl_label='Videojuego | Valdy Jr TV'
    bl_idname='VMV_PT_game'
    bl_space_type='VIEW_3D'
    bl_region_type='UI'
    bl_category='My City'
    bl_parent_id='VMV_PT_city'
    def draw(self,context):
        layout=self.layout
        layout.operator('vmv_city.game_export',icon='EXPORT')
        layout.label(text='Godot: game/project.godot')
        layout.label(text='Exporta de nuevo al cambiar la ciudad.')
        layout.label(text='Solo geometria y materiales compatibles.')

classes=(VMV_OT_sync,VMV_OT_build,VMV_OT_apply,VMV_PT_panel,VMV_OT_perf_refresh,VMV_OT_perf_mode,VMV_PT_performance,VMV_OT_lod_toggle,VMV_OT_district_show,VMV_OT_system_measure,VMV_PT_worldperf,VMV_OT_plan_add,VMV_OT_plan_copy,VMV_OT_plan_export,VMV_PT_planner,VMV_OT_asset_preview,VMV_OT_asset_snap,VMV_OT_asset_place,VMV_OT_asset_cancel,VMV_OT_asset_select,VMV_PT_library,VMV_OT_game_export,VMV_PT_game)
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
