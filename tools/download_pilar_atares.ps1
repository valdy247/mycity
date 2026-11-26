# One-time download of public OpenStreetMap data; no API keys or Python.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'game\pilar_atares.osm'
if ((Test-Path $target) -and ((Get-Item $target).Length -gt 1000)) {
    Write-Host "Existing map: $target. Delete or rename it only if you want a fresh download."
    return
}
$bbox = '-82.3720,23.1162,-82.3608,23.1261'
$url = "https://api.openstreetmap.org/api/0.6/map?bbox=$bbox"
$tmp = "$target.tmp"
try {
    Write-Host 'Downloading Pilar-Atarés / Esquina de Tejas (OpenStreetMap)...'
    Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $tmp -TimeoutSec 90 -UserAgent 'MyCity-Godot-map-import/1.0 (personal game prototype)'
    [xml]$map = Get-Content -Raw -Encoding UTF8 $tmp
    if ($null -eq $map.osm -or @($map.osm.way).Count -lt 10) { throw 'Map response is incomplete.' }
    Move-Item -Force $tmp $target
    Write-Host "Map saved: $target. Ways: $(@($map.osm.way).Count)."
    Write-Host 'Map data: (c) OpenStreetMap contributors - ODbL - https://www.openstreetmap.org/copyright'
} catch {
    if (Test-Path $tmp) { Remove-Item $tmp }
    throw
}
