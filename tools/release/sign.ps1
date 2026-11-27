<#
.SYNOPSIS
  Signiert exe-Dateien mit Authenticode (REL-04), sobald ein Zertifikat eingerichtet ist.

.DESCRIPTION
  Ohne Einrichtung tut das Skript nichts und meldet das (Exitcode 0). Eingerichtet wird über
  Umgebungsvariablen, nie über Dateien im Repo:

  Gekauftes Zertifikat als .pfx:
    DCT_SIGN_PFX           Pfad zur .pfx-Datei
    DCT_SIGN_PFX_PASSWORD  Passwort dazu

  Azure Trusted Signing:
    DCT_SIGN_AZURE_DLIB      Pfad zu Azure.CodeSigning.Dlib.dll
    DCT_SIGN_AZURE_METADATA  Pfad zur metadata.json (Endpoint, Konto, Zertifikatprofil)

  Optional:
    DCT_SIGNTOOL           Pfad zu signtool.exe (sonst aus dem Windows SDK gesucht)
    DCT_SIGN_TIMESTAMP     Zeitstempel-Server (Standard je nach Art)

  Mehr in tools/release/README.md.
#>
param([string[]]$Files)

$ErrorActionPreference = 'Continue'
$pfx = $env:DCT_SIGN_PFX
$dlib = $env:DCT_SIGN_AZURE_DLIB
$meta = $env:DCT_SIGN_AZURE_METADATA

if (-not $pfx -and -not ($dlib -and $meta)) {
  Write-Host "  Nicht signiert: kein Zertifikat eingerichtet (siehe tools/release/README.md). Windows SmartScreen warnt weiter." -ForegroundColor Yellow
  exit 0
}

$signtool = $env:DCT_SIGNTOOL
if (-not $signtool) {
  $kits = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
  if (Test-Path $kits) {
    $signtool = Get-ChildItem $kits -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match '\\x64\\' } | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
  }
}
if (-not $signtool -or -not (Test-Path $signtool)) {
  Write-Host "  signtool.exe nicht gefunden. Windows SDK installieren oder DCT_SIGNTOOL setzen." -ForegroundColor Red
  exit 1
}

foreach ($f in $Files) {
  if (-not (Test-Path $f)) { Write-Host "  fehlt: $f" -ForegroundColor Red; exit 1 }
  if ($pfx) {
    $ts = if ($env:DCT_SIGN_TIMESTAMP) { $env:DCT_SIGN_TIMESTAMP } else { 'http://timestamp.digicert.com' }
    & $signtool sign /fd SHA256 /td SHA256 /tr $ts /f $pfx /p $env:DCT_SIGN_PFX_PASSWORD /d "DataCenter Together" $f | Out-Null
  } else {
    $ts = if ($env:DCT_SIGN_TIMESTAMP) { $env:DCT_SIGN_TIMESTAMP } else { 'http://timestamp.acs.microsoft.com' }
    & $signtool sign /fd SHA256 /td SHA256 /tr $ts /dlib $dlib /dmdf $meta /d "DataCenter Together" $f | Out-Null
  }
  if ($LASTEXITCODE -ne 0) { Write-Host "  Signieren fehlgeschlagen: $f" -ForegroundColor Red; exit 1 }
  & $signtool verify /pa $f | Out-Null
  if ($LASTEXITCODE -ne 0) { Write-Host "  Signatur ungültig: $f" -ForegroundColor Red; exit 1 }
  Write-Host "  signiert  $(Split-Path $f -Leaf)"
}
exit 0
