# Download through Pixabay's official interface, then select each local MP3/OGG.
# Music stays in Godot user data; no standalone redistribution or network at play time.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
$dest = Join-Path $env:APPDATA 'Godot\app_userdata\Valdy Jr TV - The Game\daniel_music'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
$tracks = @(
    @{ Name = '01_fuego'; Title = 'Fuego - Cuban Latin Instrumental'; Url = 'https://pixabay.com/music/urban-latin-fuego-cuban-latin-instrumental-reggaeton-x-spanish-guitar-x-brass-450580/' }
    @{ Name = '02_my_oxygen'; Title = 'My oxygen'; Url = 'https://pixabay.com/music/beats-reggaeton-instrumental-latin-x-cuba-x-hot-my-oxygen-306283/' }
    @{ Name = '03_reggaeton_fiesta'; Title = 'Reggaeton Fiesta'; Url = 'https://pixabay.com/music/urban-latin-reggaeton-fiesta-upbeat-vlog-mexican-afrobeat-367119/' }
    @{ Name = '04_music_box'; Title = 'Music Box'; Url = 'https://pixabay.com/music/reggae-real-reggaeton-instrumental-love-x-tropical-x-melodic-music-box-306286/' }
    @{ Name = '05_tumbao'; Title = 'Reciprocity Cuban Tumbao'; Url = 'https://pixabay.com/music/salsa-reciprocity-cuban-tumbao-mango-music-project-510194/' }
    @{ Name = '06_old_school_salsa'; Title = 'Old School Salsa 03'; Url = 'https://pixabay.com/music/salsa-old-school-salsa-03-499570/' }
    @{ Name = '07_rumba'; Title = 'Tumbao Rumba'; Url = 'https://pixabay.com/music/samba-latin-tumbao-rumba-207715/' }
    @{ Name = '08_afro_cuban'; Title = 'Afro-Cuban Latin Salsa'; Url = 'https://pixabay.com/es/music/lat%C3%ADn-afro-cuban-latin-salsa-467057/' }
    @{ Name = '09_bailando'; Title = 'Bailando en tu Piel'; Url = 'https://pixabay.com/music/upbeat-bailando-en-tu-piel-461719/' }
    @{ Name = '10_bajo_la_luna'; Title = 'Bajo la Luna Bailando'; Url = 'https://pixabay.com/music/bachata-bajo-la-luna-bailando-461721/' }
)
Write-Host 'MUSICA DE DANIEL - descarga oficial y carga local'
Write-Host 'Para cada tema, confirma la licencia en Pixabay y descarga el audio. Puedes saltar los que no quieras.'
foreach ($track in $tracks) {
    if ((Test-Path (Join-Path $dest ($track.Name+'.mp3'))) -or (Test-Path (Join-Path $dest ($track.Name+'.ogg')))) { continue }
    $choice = Read-Host ("Instalar "+$track.Title+"? [S]i / [N]o / [Q]uit")
    if ($choice -match '^[Qq]') { break }
    if ($choice -match '^[Nn]') { continue }
    Start-Process $track.Url
    Read-Host 'Descarga la pista desde su pagina oficial, guarda su comprobante de licencia si esta disponible, y pulsa Enter' | Out-Null
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = 'Selecciona el archivo de '+$track.Title
    $dialog.Filter = 'Audio MP3 u OGG|*.mp3;*.ogg'
    $dialog.InitialDirectory = Join-Path $env:USERPROFILE 'Downloads'
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) { $dialog.Dispose(); continue }
    $source = $dialog.FileName
    $ext = [IO.Path]::GetExtension($source).ToLowerInvariant()
    if ($ext -in @('.mp3','.ogg') -and (Get-Item $source).Length -gt 1024) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $dest ($track.Name+$ext)) -Force
        Add-Content -Path (Join-Path $dest 'sources.txt') -Value ($track.Name+' | '+$track.Title+' | '+$track.Url+' | '+(Get-Date -Format yyyy-MM-dd))
        Write-Host ('Instalado: '+$track.Title)
    }
    $dialog.Dispose()
}
Write-Host ('Musica local: '+$dest)
Write-Host ('Pistas instaladas: '+@(Get-ChildItem $dest -File | Where-Object Extension -in '.mp3','.ogg').Count)
