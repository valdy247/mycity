param([string]$Repo='C:\mycity',[switch]$NoLaunch)
$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath (Join-Path $Repo '.git'))) { throw "No se encuentra el repositorio: $Repo" }
if (Get-Process -Name 'godot*' -ErrorAction SilentlyContinue) { throw 'Cierra Godot y el juego antes de reiniciar para evitar que vuelvan a guardar la partida.' }
Set-Location -LiteralPath $Repo
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw 'Git pull falló. No se cambió la partida.' }
$saveRoot = Join-Path $env:APPDATA 'Godot\app_userdata\Valdy Jr TV - The Game'
$files = @('pilar_business_v1.json','pilar_atares_inventory.json','mycity_adaptation_v1.json','mycity_adaptation_inventory_v1.json','mycity_chapter1_v2.json')
$backup = Join-Path $env:USERPROFILE ('mycity-save-backup-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6))
New-Item -ItemType Directory -Path $backup -Force | Out-Null
$targets = @()
foreach ($base in $files) {
    foreach ($suffix in @('','.bak','.tmp','.bak.tmp')) {
        $name = $base+$suffix
        $path = Join-Path $saveRoot $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Copy-Item -LiteralPath $path -Destination (Join-Path $backup $name)
            $targets += $path
        }
    }
}
try {
    foreach ($path in $targets) { Remove-Item -LiteralPath $path -ErrorAction Stop }
} catch {
    foreach ($path in $targets) {
        if (!(Test-Path -LiteralPath $path)) { Copy-Item -LiteralPath (Join-Path $backup (Split-Path $path -Leaf)) -Destination $path }
    }
    throw
}
Write-Host 'Partida reiniciada: aeropuerto, 0 CUP, misiones, casa, cafetera, inventarios y relaciones.' -ForegroundColor Green
Write-Host "Respaldo: $backup"
Write-Host 'Mapa, edificios editados, musica y voces conservados.'
if (!$NoLaunch) {
    & godot --path (Join-Path $Repo 'game') res://airport.tscn -- --new-story
}
