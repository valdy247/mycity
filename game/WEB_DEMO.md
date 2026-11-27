# MyCity — demo web

El mapa de OpenStreetMap está excluido de Git y reside localmente. No desplegar el repositorio directamente como una web: primero exportar Godot, incluyendo el mapa local.

1. Actualizar main. Abrir el proyecto game en Godot (versión 4.3 o compatible).
2. Confirmar que game/pilar_atares_v2.osm existe y que el juego muestra la ciudad correcta.
3. Instalar las plantillas de exportación de la misma versión del editor.
4. Crear la carpeta game/exports/web y usar Proyecto > Exportar > Web > Exportar proyecto, con destino exports/web/index.html. El perfil incluye los archivos OSM y desactiva Thread Support para facilitar alojamiento estático.
5. Probar en el navegador con el botón de ejecución web de Godot. Verificar carga del mapa, controles, FPS y sonido. El rendimiento puede ser inferior al ejecutable nativo.
6. Publicar solo la carpeta game/exports/web (no el proyecto ni los archivos de guardado) en https://vercel.com/drop, con un nombre nuevo como mycity-demo si está disponible. Revisar acceso público y comprobar el enlace en una ventana privada.
7. Conservar la atribución de OpenStreetMap y respetar ODbL para los datos de mapa distribuidos.

No se cambian escenas, misiones, resolución ni renderer. Este perfil todavía necesita una exportación y prueba local. No publicar si la carga de la ciudad falla.

## Corrección: la demo abre Ciudad 2.0

Cerrar Godot antes de actualizar y reabrir el proyecto. Comprobar en Project Settings > Plugins que MyCity Map Export está activo. El plugin copia explícitamente el mapa local actualizado al PCK al exportar Web; la consola de exportación imprime MYCITY WEB MAP y el tamaño del archivo. El filtro *.osm se conserva como respaldo. Si falta el mapa actualizado o no se puede leer, el juego web muestra un error en vez de abrir Ciudad 2.0. Exportar nuevamente y probar antes de sustituir el despliegue. No se deben publicar archivos user:// ni partidas guardadas.
