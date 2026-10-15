param(
    [string]$GodotPath = (Join-Path $env:USERPROFILE 'Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe')
)
$ErrorActionPreference = 'Stop'
$workspace = $PSScriptRoot
$project = Join-Path $workspace 'Voxel-main'
$template = Join-Path $workspace 'build-tools\windows_release_x86_64.exe'
if (-not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot 4.7.2 fehlt. Bitte -GodotPath mit dem Pfad zur Godot-EXE angeben.'
}
if (-not (Test-Path -LiteralPath $template -PathType Leaf)) {
    throw 'Exportvorlage fehlt: build-tools\windows_release_x86_64.exe (Godot 4.7.2).'
}
$buildRuntime = Join-Path $workspace 'build-tools\runtime'
foreach ($folder in @('Roaming', 'Local', 'Temp')) {
    New-Item -ItemType Directory -Force (Join-Path $buildRuntime $folder) | Out-Null
}
# Keep build/editor caches separate from actual game saves and user settings.
$env:APPDATA = Join-Path $buildRuntime 'Roaming'
$env:LOCALAPPDATA = Join-Path $buildRuntime 'Local'
$env:TEMP = Join-Path $buildRuntime 'Temp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force (Join-Path $workspace 'Spiel') | Out-Null
& $GodotPath --headless --editor --path $project --import --quit
if ($LASTEXITCODE -ne 0) { throw "Godot-Import fehlgeschlagen: $LASTEXITCODE" }
& $GodotPath --headless --path $project --export-release 'Windows Desktop' (Join-Path $workspace 'Spiel\Gruenweiten.exe')
if ($LASTEXITCODE -ne 0) { throw "Windows-Export fehlgeschlagen: $LASTEXITCODE" }
Write-Output ('Fertig: ' + (Join-Path $workspace 'Spiel\Gruenweiten.exe'))
