# Startet feature_off_probe.gd einmal pro Effekt in einem frischen Godot-Prozess und sammelt die Ergebnisse.
$ErrorActionPreference = 'Continue'
$godot = "C:\Users\nicoh\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe"
$root = "C:\Users\nicoh\.gemini\antigravity\scratch\datacenter-tycoon"
$log = Join-Path $root "tests\_feature_off.log"
Set-Content -Path $log -Value "start $(Get-Date -Format o)"
$features = 'none','sdfgi','omni_shadows','sun_shadow','probes','subviewports','ssil','ssr','ssao','vol_fog','glow','taa','sky_radiance','half_res','all'
foreach ($f in $features) {
    $out = Join-Path $root "tests\_off_$f.out.log"
    $err = Join-Path $root "tests\_off_$f.err.log"
    $p = Start-Process -FilePath $godot -ArgumentList '--path', $root, '--resolution', '1600x900', '--script', 'res://tests/feature_off_probe.gd', '--', 'q=3', "off=$f" -RedirectStandardOutput $out -RedirectStandardError $err -WorkingDirectory $root -PassThru
    if (-not $p.WaitForExit(45000)) {
        Stop-Process -Id $p.Id -Force
        Add-Content -Path $log -Value "$f TIMEOUT"
        continue
    }
    $lines = Get-Content $out -ErrorAction SilentlyContinue | Where-Object { $_ -match '^OFF |SCRIPT ERROR|Parse Error' }
    if ($lines) { Add-Content -Path $log -Value ($lines -join "`n") } else { Add-Content -Path $log -Value "$f keine Ausgabe (exit $($p.ExitCode))" }
}
Add-Content -Path $log -Value "fertig $(Get-Date -Format o)"