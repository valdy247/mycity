# Start a fresh gameplay save while preserving map edits and placement.
# Close Godot's running game before executing.
$saveDir = Join-Path $env:APPDATA 'Godot\app_userdata\Valdy Jr TV - The Game'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
foreach ($name in @('pilar_business_v1.json','pilar_atares_inventory.json')) {
    $file = Join-Path $saveDir $name
    if (Test-Path -LiteralPath $file) {
        $backup = "$file.backup-$stamp"
        if (Test-Path -LiteralPath $backup) { throw "Backup already exists: $backup" }
        Move-Item -LiteralPath $file -Destination $backup -ErrorAction Stop
        Write-Host "Backup: $backup"
    }
}
Write-Host 'Nueva partida: abre el juego con F5. Se conservan los cambios del mapa.'
