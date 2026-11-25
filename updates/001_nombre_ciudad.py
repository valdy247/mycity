"""My City - first incremental update. Rename the active district only."""
import bpy

scene = bpy.context.scene
if scene.objects.get("VAN | CONTROL") is None or scene.objects.get("BUS | CONTROL") is None:
    raise RuntimeError("Abre el distrito 01 de My City antes de aplicar esta prueba.")
scene.name = "My City | Distrito 01"
print("My City: primera actualizacion aplicada. No se modificaron modelos ni materiales.")
