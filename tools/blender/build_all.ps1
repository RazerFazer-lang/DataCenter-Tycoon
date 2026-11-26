# Baut alle aktuellen Blender-Modelle mit einem Befehl (Erklaerung: tools/blender/README.md).
#
#   .\tools\blender\build_all.ps1                                  # nach assets/models
#   .\tools\blender\build_all.ps1 --out C:\temp\modelle            # Probelauf ausserhalb des Projekts
#   .\tools\blender\build_all.ps1 --out C:\temp\modelle --only build_desk,build_racks --no-previews
#   .\tools\blender\build_all.ps1 --list
#
# Blender: $env:BLENDER, sonst blender.exe im PATH, sonst "C:\Program Files\Blender Foundation\Blender*".
# Alle Argumente gehen unveraendert an build_all.py. Exit-Code 1, wenn ein Generator fehlschlaegt.

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$blender = $env:BLENDER
if (-not $blender) {
    $cmd = Get-Command blender.exe -ErrorAction SilentlyContinue
    if ($cmd) { $blender = $cmd.Source }
}
if (-not $blender) {
    $found = Get-ChildItem -Path "C:\Program Files\Blender Foundation\Blender*\blender.exe" -ErrorAction SilentlyContinue |
        Sort-Object FullName -Descending
    if ($found) { $blender = @($found)[0].FullName }
}
if (-not $blender -or -not (Test-Path $blender)) {
    Write-Host "Blender nicht gefunden. Pfad in `$env:BLENDER setzen." -ForegroundColor Red
    exit 2
}

# PowerShell macht aus "a,b" ein Array; fuer --only wieder zu "a,b" zusammenfuegen.
$pass = @()
foreach ($a in $args) {
    if ($a -is [array]) { $pass += ($a -join ',') } else { $pass += [string]$a }
}

& $blender -b --factory-startup --python-exit-code 1 --python (Join-Path $here 'build_all.py') -- @pass
exit $LASTEXITCODE
