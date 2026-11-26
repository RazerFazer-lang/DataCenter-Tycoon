<#
.SYNOPSIS
  Veröffentlicht DataCenter Tycoon Co-op mit einem Befehl (REL-03).

.DESCRIPTION
  Version setzen, testen, bauen, signieren (falls eingerichtet), Probelauf, packen,
  kleines Update (Delta) zur Vorversion, committen, auf GitHub hochladen und prüfen.
  Bricht bei jedem Fehler ab. Vor dem Push ändert das Skript nur lokale Dateien.

.EXAMPLE
  .\tools\release\release.ps1 -Version 3.5.0 -DryRun
  Alles bis zu den fertigen Zips, ohne Commit und ohne GitHub.

.EXAMPLE
  .\tools\release\release.ps1 -Version 3.5.0 -Include scripts,tests,launcher -Publish
  Komplett: committet die Versionsdateien und die genannten Pfade, lädt hoch und schaltet frei.
#>
param(
  [Parameter(Mandatory = $true)][string]$Version,
  # Changelog: tools/release/notes/v<Version>.json (title, items, roadmap) und optional .md für GitHub.
  [string]$Notes = "",
  # Weitere Pfade, die mit in den Release-Commit gehören (z. B. die Arbeit des Updates).
  [string[]]$Include = @(),
  [switch]$DryRun,
  [switch]$Publish,
  [switch]$SkipTests,
  [switch]$FullTests,
  [switch]$SkipSmoke,
  [switch]$NoDelta,
  [string]$Godot = "",
  # Zusätzliche Zeile am Ende der Commit-Nachricht (z. B. Co-Authored-By).
  [string]$Trailer = ""
)

# Windows PowerShell 5.1 macht aus jeder Fehlerausgabe eines Programms (git, gh) sonst einen Abbruch.
# Abgebrochen wird deshalb gezielt: Fail() und -ErrorAction Stop an den wichtigen Stellen.
$ErrorActionPreference = 'Continue'
$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$Dist = Join-Path $Root 'dist\release'
$Work = Join-Path $env:TEMP "dct_release\v$Version"
$Iso = Join-Path $env:TEMP 'dct_release\appdata'
$Tag = "v$Version"
$GameZip = "DataCenterTycoon-$Tag-win64.zip"
$LauncherZip = "DataCenterLauncher-$Tag-win64.zip"
$Repo = 'RazerFazer-lang/DataCenter-Tycoon'
$BumpFiles = @('export_presets.cfg', 'launcher/DataCenterLauncher.csproj', 'launcher/LauncherConfig.cs', 'project.godot', 'version.json', 'roadmap.json')
$script:StepNo = 0
$Started = Get-Date

function Step([string]$Text) {
  $script:StepNo++
  Write-Host ""
  Write-Host ("[{0,2}] {1}" -f $script:StepNo, $Text) -ForegroundColor Cyan
}
function Fail([string]$Text) { throw "ABBRUCH: $Text" }
function Run([string]$Exe, [string[]]$ArgList, [string]$Log, [hashtable]$Env = @{}) {
  $saved = @{}
  foreach ($k in $Env.Keys) { $saved[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $Env[$k]) }
  try {
    $p = Start-Process -FilePath $Exe -ArgumentList $ArgList -WorkingDirectory $Root -NoNewWindow -PassThru -Wait `
      -RedirectStandardOutput $Log -RedirectStandardError "$Log.err"
    return $p.ExitCode
  } finally {
    foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  }
}
function Q([string]$s) { return '"' + $s + '"' }
function Sha([string]$File) {
  $h = (Get-FileHash $File -Algorithm SHA256).Hash.ToLower()
  $n = Split-Path $File -Leaf
  [IO.File]::WriteAllText("$File.sha256", "$h  $n`n")
  return $h
}

# ---------------------------------------------------------------- Vorprüfung
Step "Vorprüfung"
if ($Version -notmatch '^\d+\.\d+\.\d+$') { Fail "Version muss X.Y.Z sein." }
if ($Notes -eq "") { $Notes = Join-Path $PSScriptRoot "notes\$Tag.json" }
if (-not (Test-Path $Notes)) { Fail "Changelog fehlt: $Notes (Vorlage: tools/release/notes/BEISPIEL.json)" }
if ($Godot -eq "") { $Godot = $env:DCT_GODOT }
if (-not $Godot) {
  foreach ($c in @("$env:USERPROFILE\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe", "$env:USERPROFILE\Desktop\Godot_v4.7.2-stable_win64.exe", "C:\Godot\Godot_v4.7.2-stable_win64.exe")) {
    if (Test-Path $c) { $Godot = $c; break }
  }
}
if (-not $Godot -or -not (Test-Path $Godot)) { Fail "Godot 4.7.2 nicht gefunden. Pfad mit -Godot oder Umgebungsvariable DCT_GODOT angeben." }
foreach ($tool in @('git', 'dotnet', 'node')) { if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) { Fail "$tool fehlt." } }
if (-not $DryRun) {
  if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { Fail "GitHub CLI (gh) fehlt." }
  $branch = (git -C $Root branch --show-current).Trim()
  if ($branch -ne 'main') { Fail "Veröffentlichen nur von main (jetzt: $branch)." }
  git -C $Root fetch -q origin
  $behind = (git -C $Root rev-list --count HEAD..origin/main).Trim()
  if ($behind -ne '0') { Fail "main ist $behind Commits hinter origin/main." }
  $null = gh release view $Tag --repo $Repo 2>$null
  if ($LASTEXITCODE -eq 0) { Fail "Release $Tag gibt es schon." }
}
$Prev = ""
if (-not $NoDelta) {
  $list = gh release list --repo $Repo --limit 5 --exclude-drafts --json tagName,isLatest 2>$null | ConvertFrom-Json
  $latest = $list | Where-Object { $_.isLatest } | Select-Object -First 1
  if ($latest) { $Prev = $latest.tagName }
  if ($Prev -eq $Tag) { $Prev = "" }
}
Write-Host "  Godot:     $Godot"
Write-Host "  Arbeit:    $Work"
Write-Host ("  Vorversion für kleines Update: " + $(if ($Prev) { $Prev } else { "keine" }))
Remove-Item -Recurse -Force $Work -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$Work\game", "$Work\launcher", "$Work\logs", $Iso, "$Iso\l", $Dist -ErrorAction Stop | Out-Null

# ---------------------------------------------------------------- Version
Step "Version $Version setzen und Changelog eintragen"
& node (Join-Path $PSScriptRoot 'bump_version.js') $Version $Notes
if ($LASTEXITCODE -ne 0) { Fail "Version setzen fehlgeschlagen." }
$NotesData = Get-Content $Notes -Raw -Encoding UTF8 | ConvertFrom-Json

# ---------------------------------------------------------------- Tests
$IsoEnv = @{ APPDATA = $Iso; LOCALAPPDATA = "$Iso\l" }
if (-not $SkipTests) {
  $tests = @('compile_check', 'translation_check')
  if ($FullTests) {
    $tests += Get-ChildItem (Join-Path $Root 'tests') -Filter '*_check.gd' | ForEach-Object { $_.BaseName } |
      Where-Object { $_ -notin @('compile_check', 'translation_check', 'workbench_check') }
  }
  Step ("Tests: " + ($tests -join ', '))
  foreach ($t in $tests) {
    $log = "$Work\logs\$t.log"
    $code = Run $Godot @('--headless', '--path', (Q $Root), '--script', "res://tests/$t.gd") $log $IsoEnv
    $fails = @(Select-String -Path $log -Pattern '^FAIL|SCRIPT ERROR|Parse Error' -ErrorAction SilentlyContinue).Count
    if ($code -ne 0 -or $fails -gt 0) { Fail "Test ${t}: Exitcode $code, $fails Fehlerzeilen (Log: $log)" }
    Write-Host "  ok  $t"
  }
}

# ---------------------------------------------------------------- Bauen
Step "Launcher bauen"
$code = Run 'dotnet' @('publish', (Q "$Root\launcher\DataCenterLauncher.csproj"), '-c', 'Release', '-o', (Q "$Work\lpub")) "$Work\logs\launcher.log"
if ($code -ne 0) { Fail "Launcher-Build fehlgeschlagen (Log: $Work\logs\launcher.log)" }

Step "Spiel exportieren"
# Der Export braucht das echte APPDATA, dort liegen die Export-Vorlagen.
$code = Run $Godot @('--headless', '--path', (Q $Root), '--export-release', (Q 'Windows Desktop'), (Q "$Work\game\DataCenterTycoon.exe")) "$Work\logs\export.log"
if ($code -ne 0 -or -not (Test-Path "$Work\game\DataCenterTycoon.pck")) { Fail "Export fehlgeschlagen (Log: $Work\logs\export.log)" }
Copy-Item "$Root\version.json", "$Root\roadmap.json" "$Work\game\" -ErrorAction Stop
Copy-Item "$Root\version.json", "$Root\roadmap.json", "$Work\lpub\DataCenterLauncher.exe" "$Work\launcher\" -ErrorAction Stop

# ---------------------------------------------------------------- Signieren (REL-04)
Step "Signieren"
& (Join-Path $PSScriptRoot 'sign.ps1') -Files @("$Work\game\DataCenterTycoon.exe", "$Work\game\DataCenterTycoon.console.exe", "$Work\launcher\DataCenterLauncher.exe")
if ($LASTEXITCODE -ne 0) { Fail "Signieren fehlgeschlagen." }

# ---------------------------------------------------------------- Probelauf
if (-not $SkipSmoke) {
  Step "Probelauf 30 s"
  $saved = @{ A = $env:APPDATA; L = $env:LOCALAPPDATA }
  $env:APPDATA = $Iso; $env:LOCALAPPDATA = "$Iso\l"
  try {
    $p = Start-Process -FilePath "$Work\game\DataCenterTycoon.exe" -ArgumentList '--resolution 1280x720' -PassThru `
      -RedirectStandardOutput "$Work\logs\smoke.log" -RedirectStandardError "$Work\logs\smoke.log.err"
    # Ohne den Handle liefert Windows PowerShell später keinen Exitcode.
    $null = $p.Handle
    Start-Sleep -Seconds 30
    if ($p.HasExited) { Fail "Spiel hat sich im Probelauf selbst beendet (Exitcode $($p.ExitCode))." }
    $null = $p.CloseMainWindow()
    if (-not $p.WaitForExit(30000)) { $p.Kill(); Fail "Spiel reagiert beim Schließen nicht." }
    $p.WaitForExit()
  } finally { $env:APPDATA = $saved.A; $env:LOCALAPPDATA = $saved.L }
  $errs = @(Select-String -Path "$Work\logs\smoke.log", "$Work\logs\smoke.log.err" -Pattern 'ERROR' -ErrorAction SilentlyContinue).Count
  if ($p.ExitCode -ne 0 -or $errs -gt 0) { Fail "Probelauf: Exitcode $($p.ExitCode), $errs Fehler im Log ($Work\logs\smoke.log)" }
  Write-Host "  ok  Exitcode 0, keine Fehler"
}

# ---------------------------------------------------------------- Packen
Step "Zips und Prüfsummen"
# Direkt nach dem Probelauf hält oft noch der Virenscanner die exe fest: ein paar Mal neu versuchen.
function Zip([string]$From, [string]$To) {
  for ($i = 1; $i -le 6; $i++) {
    try { Compress-Archive -Path $From -DestinationPath $To -Force -ErrorAction Stop; return }
    catch { if ($i -eq 6) { Fail "Packen von $To fehlgeschlagen: $($_.Exception.Message)" }; Start-Sleep -Seconds 5 }
  }
}
Zip "$Work\game\*" "$Dist\$GameZip"
Zip "$Work\launcher\*" "$Dist\$LauncherZip"
$Assets = @("$Dist\$GameZip", "$Dist\$LauncherZip")
foreach ($a in $Assets) { $h = Sha $a; Write-Host ("  {0}  {1:N1} MB  {2}" -f (Split-Path $a -Leaf), ((Get-Item $a).Length / 1MB), $h.Substring(0, 12)) }

# ---------------------------------------------------------------- Kleines Update (REL-02)
if ($Prev -and -not $NoDelta) {
  Step "Kleines Update von $Prev"
  $prevZip = "$Dist\DataCenterTycoon-$Prev-win64.zip"
  if (-not (Test-Path $prevZip)) {
    gh release download $Prev --repo $Repo --pattern "DataCenterTycoon-$Prev-win64.zip" --dir $Dist
    if ($LASTEXITCODE -ne 0) { Fail "Vorversion $Prev nicht ladbar." }
  }
  $delta = "$Dist\DataCenterTycoon-$Tag-from-$Prev-win64.delta"
  $code = Run 'dotnet' @('run', '--project', (Q "$Root\tools\delta\DeltaTool.csproj"), '-c', 'Release', '--', 'make', '--old', (Q $prevZip), '--new', (Q "$Work\game"), '--out', (Q $delta), '--from', $Prev.TrimStart('v'), '--to', $Version) "$Work\logs\delta.log"
  if ($code -ne 0 -or -not (Test-Path $delta)) { Fail "Delta fehlgeschlagen (Log: $Work\logs\delta.log)" }
  # Gegenprobe: Delta auf die Vorversion anwenden und mit dem neuen Ordner vergleichen.
  $check = "$Work\deltacheck"
  Expand-Archive -Path $prevZip -DestinationPath "$check\old" -Force -ErrorAction Stop
  $code = Run 'dotnet' @('run', '--project', (Q "$Root\tools\delta\DeltaTool.csproj"), '-c', 'Release', '--', 'apply', '--delta', (Q $delta), '--install', (Q "$check\old"), '--out', (Q "$check\new")) "$Work\logs\delta_apply.log"
  if ($code -ne 0) { Fail "Delta lässt sich nicht anwenden (Log: $Work\logs\delta_apply.log)" }
  foreach ($f in Get-ChildItem "$Work\game" -File) {
    $a = (Get-FileHash $f.FullName).Hash; $b = (Get-FileHash (Join-Path "$check\new" $f.Name)).Hash
    if ($a -ne $b) { Fail "Delta-Gegenprobe: $($f.Name) weicht ab." }
  }
  $null = Sha $delta
  $Assets += $delta
  Write-Host ("  ok  {0:N1} MB statt {1:N1} MB" -f ((Get-Item $delta).Length / 1MB), ((Get-Item "$Dist\$GameZip").Length / 1MB))
}

if ($DryRun) {
  Write-Host ""
  Write-Host "Probedurchlauf fertig ($([int]((Get-Date) - $Started).TotalMinutes) Min.). Nichts committet, nichts hochgeladen." -ForegroundColor Green
  Write-Host "Die Versionsdateien sind lokal schon auf $Version gesetzt (git diff zeigt sie)."
  exit 0
}

# ---------------------------------------------------------------- Commit
Step "Commit $Tag"
$msg = "$Tag`: $($NotesData.title)`n`n" + (($NotesData.items | ForEach-Object { "- " + ($_ -replace '^\[[^\]]*\]\s*', '') }) -join "`n") + "`n"
if ($Trailer) { $msg += "`n$Trailer`n" }
$msgFile = "$Work\commit.txt"
[IO.File]::WriteAllText($msgFile, $msg)
git -C $Root add -- @($BumpFiles + $Include)
if ($LASTEXITCODE -ne 0) { Fail "git add fehlgeschlagen." }
$staged = git -C $Root diff --cached --name-only
if ($staged | Where-Object { $_ -match '(?i)roadmap\.txt$|\.log$|^dist/|_build/|__pycache__' }) { Fail "Unerwünschte Dateien im Commit: $($staged -join ', ')" }
git -C $Root commit -q -F $msgFile
if ($LASTEXITCODE -ne 0) { Fail "Commit fehlgeschlagen." }
git -C $Root push -q origin main
if ($LASTEXITCODE -ne 0) { Fail "Push fehlgeschlagen." }

# ---------------------------------------------------------------- GitHub
Step "Release-Entwurf auf GitHub"
$notesMd = [IO.Path]::ChangeExtension($Notes, '.md')
if (-not (Test-Path $notesMd)) {
  $notesMd = "$Work\notes.md"
  $md = "## Update $Version – $($NotesData.title)`n`n" + (($NotesData.items | ForEach-Object { "- " + ($_ -replace '^\[[^\]]*\]\s*', '') }) -join "`n") + "`n`nCo-op: Alle Mitspieler brauchen $Tag.`n"
  [IO.File]::WriteAllText($notesMd, $md)
}
$up = @()
foreach ($a in $Assets) { $up += $a; $up += "$a.sha256" }
gh release create $Tag --repo $Repo --target main --draft --title "DataCenter Tycoon Co-op $Tag — $($NotesData.title)" --notes-file $notesMd @up
if ($LASTEXITCODE -ne 0) { Fail "Release-Entwurf fehlgeschlagen." }

if (-not $Publish) {
  Write-Host ""
  Write-Host "Entwurf $Tag liegt auf GitHub. Freischalten mit: gh release edit $Tag --repo $Repo --draft=false --latest" -ForegroundColor Green
  exit 0
}

Step "Freischalten und prüfen"
gh release edit $Tag --repo $Repo --draft=false --latest
if ($LASTEXITCODE -ne 0) { Fail "Freischalten fehlgeschlagen." }
$dl = "$Work\download"
New-Item -ItemType Directory -Force $dl | Out-Null
foreach ($a in $Assets) {
  $n = Split-Path $a -Leaf
  Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$Repo/releases/download/$Tag/$n" -OutFile "$dl\$n" -ErrorAction Stop
  if ((Get-FileHash "$dl\$n").Hash -ne (Get-FileHash $a).Hash) { Fail "Download von $n stimmt nicht." }
  Write-Host "  ok  $n"
}
Write-Host ""
Write-Host "$Tag ist veröffentlicht ($([int]((Get-Date) - $Started).TotalMinutes) Min.)." -ForegroundColor Green
