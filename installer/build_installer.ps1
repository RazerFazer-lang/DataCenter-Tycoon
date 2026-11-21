# Baut dist\DataCenterTycoon-Setup-<Version>.exe mit Inno Setup 6.
# Aufruf: powershell -ExecutionPolicy Bypass -File installer\build_installer.ps1
$ErrorActionPreference = "Stop"

$script = Join-Path $PSScriptRoot "DataCenterTycoon.iss"
$candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
)
$iscc = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $iscc) {
    $cmd = Get-Command iscc -ErrorAction SilentlyContinue
    if ($cmd) { $iscc = $cmd.Source }
}
if (-not $iscc) {
    Write-Error "Inno Setup 6 nicht gefunden. Installieren mit: winget install --id JRSoftware.InnoSetup -e"
    exit 1
}

& $iscc $script
if ($LASTEXITCODE -ne 0) {
    Write-Error "ISCC ist mit Code $LASTEXITCODE fehlgeschlagen."
    exit $LASTEXITCODE
}
Write-Host "Fertig. Setup liegt in: $(Resolve-Path (Join-Path $PSScriptRoot '..\dist'))"