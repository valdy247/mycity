# My City

Ciudad 3D modular para Blender 4.2–5.x. Proyecto de construcción de escenarios y objetos reutilizables e interactivos, optimizado para laptops.

## Estructura
- `addon/mycity_studio.py`: panel de sincronización local.
- `scenes/district_01.py`: generador inicial del distrito (pendiente de incorporar desde el paquete inicial).
- `updates/`: scripts incrementales revisados.
- Los archivos .blend se guardan localmente, fuera del control de versiones por defecto.

## Flujo de trabajo
1. Clonar este repositorio en la laptop con Git.
2. Instalar el complemento My City Studio en Blender.
3. Seleccionar la carpeta local del repositorio en el panel My City.
4. Sincronizar con GitHub. La sincronización no ejecuta código.
5. Revisar y aplicar explícitamente el script de actualización. Guardar una copia del .blend antes.

El generador inicial se debe ejecutar en una escena vacía. Los cambios incrementales deben preservar los objetos existentes. No ejecutar código de fuentes no confiables.
