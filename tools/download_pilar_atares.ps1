# Download four adjoining OSM tiles and merge by entity ID, retaining all ways and nodes.
param([switch]$Force)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$target = Join-Path $root 'game\pilar_atares_v2.osm'
if (!$Force -and (Test-Path $target) -and ((Get-Item $target).Length -gt 1000)) {
    Write-Host "Map already downloaded: $target"
    return
}
$tiles = @(
    '-82.3770,23.1130,-82.3670,23.1220',
    '-82.3670,23.1130,-82.3570,23.1220',
    '-82.3770,23.1220,-82.3670,23.1310',
    '-82.3670,23.1220,-82.3570,23.1310'
)
$combined = New-Object System.Xml.XmlDocument
$combined.LoadXml('<osm version="0.6" generator="MyCity-OSM-Merge"><bounds minlat="23.1130" minlon="-82.3770" maxlat="23.1310" maxlon="-82.3570"/></osm>')
$seen = @{}
$tmp = "$target.tmp"
$part = "$target.part"
try {
    foreach ($bbox in $tiles) {
        Write-Host "Downloading OSM tile $bbox"
        $url = "https://api.openstreetmap.org/api/0.6/map?bbox=$bbox"
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $part -TimeoutSec 120 -UserAgent 'MyCity-Godot-map-import/2.0 (personal game prototype)'
        [xml]$tile = Get-Content -Raw -Encoding UTF8 $part
        if ($null -eq $tile.osm -or @($tile.osm.way).Count -lt 10) { throw "Incomplete OSM tile: $bbox" }
        foreach ($entity in $tile.DocumentElement.ChildNodes) {
            if ($entity.Name -notin @('node','way','relation')) { continue }
            $key = "$($entity.Name):$($entity.GetAttribute('id'))"
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            [void]$combined.DocumentElement.AppendChild($combined.ImportNode($entity,$true))
        }
        Remove-Item $part
    }
    $combined.Save($tmp)
    Move-Item -Force $tmp $target
    Write-Host "Saved: $target | Nodes: $(@($combined.osm.node).Count) | Ways: $(@($combined.osm.way).Count)"
    Write-Host 'Map data: (c) OpenStreetMap contributors - ODbL - https://www.openstreetmap.org/copyright'
} finally {
    if (Test-Path $tmp) { Remove-Item $tmp }
    if (Test-Path $part) { Remove-Item $part }
}
