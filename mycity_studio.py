# -*- coding: utf-8 -*-
"""My City Studio: local Git synchronization and explicit scene operations."""
bl_info = {'name':'My City Studio','author':'My City','version':(0,2,0),'blender':(4,2,0),'location':'View3D > Sidebar > My City','description':'Synchronize a local My City repository and apply reviewed scripts','category':'3D View'}
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

classes=(VMV_OT_sync,VMV_OT_build,VMV_OT_apply,VMV_PT_panel,VMV_OT_perf_refresh,VMV_OT_perf_mode,VMV_PT_performance)
def register():
    for cls in classes: bpy.utils.register_class(cls)
    bpy.types.Scene.vmv_repo=bpy.props.StringProperty(name='Repositorio local',subtype='DIR_PATH')
    bpy.types.Scene.vmv_update=bpy.props.StringProperty(name='Archivo de actualización')
def unregister():
    _perf_cache.clear()
    if bpy.app.timers.is_registered(poll_git): bpy.app.timers.unregister(poll_git)
    del bpy.types.Scene.vmv_repo; del bpy.types.Scene.vmv_update
    for cls in reversed(classes): bpy.utils.unregister_class(cls)
if __name__=='__main__': register()
