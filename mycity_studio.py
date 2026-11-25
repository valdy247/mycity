# -*- coding: utf-8 -*-
"""My City Studio: local Git synchronization and explicit scene operations."""
bl_info = {'name':'My City Studio','author':'My City','version':(0,1,0),'blender':(4,2,0),'location':'View3D > Sidebar > My City','description':'Synchronize a local My City repository and apply reviewed scripts','category':'3D View'}
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

classes=(VMV_OT_sync,VMV_OT_build,VMV_OT_apply,VMV_PT_panel)
def register():
    for cls in classes: bpy.utils.register_class(cls)
    bpy.types.Scene.vmv_repo=bpy.props.StringProperty(name='Repositorio local',subtype='DIR_PATH')
    bpy.types.Scene.vmv_update=bpy.props.StringProperty(name='Archivo de actualización')
def unregister():
    if bpy.app.timers.is_registered(poll_git): bpy.app.timers.unregister(poll_git)
    del bpy.types.Scene.vmv_repo; del bpy.types.Scene.vmv_update
    for cls in reversed(classes): bpy.utils.unregister_class(cls)
if __name__=='__main__': register()
