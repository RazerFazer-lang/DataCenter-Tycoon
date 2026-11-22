# Startet coop_pose_probe.gd als Host und als Client und zeigt die wichtigen Zeilen beider Logs.
$ErrorActionPreference = 'Continue'
$godot = "C:\Users\nicoh\OneDrive\Desktop\Godot_v4.7.2-stable_win64.exe"
$root = "C:\Users\nicoh\.gemini\antigravity\scratch\datacenter-tycoon"
$probe = 'res://tests/coop_pose_probe.gd'

function Start-Probe([string]$role) {
    $out = Join-Path $root "tests\_coop_$role.out.log"
    $err = Join-Path $root "tests\_coop_$role.err.log"
    Start-Process -FilePath $godot -ArgumentList '--path', $root, '--resolution', '1280x720', '--script', $probe, '--', "role=$role" -RedirectStandardOutput $out -RedirectStandardError $err -WorkingDirectory $root -PassThru
}

$hostProc = Start-Probe 'host'
Start-Sleep -Seconds 5
$joinProc = Start-Probe 'join'

foreach ($pair in @(@('host', $hostProc, 45000), @('join', $joinProc, 5000))) {
    $role, $p, $ms = $pair
    if (-not $p.WaitForExit($ms)) {
        Stop-Process -Id $p.Id -Force
        Write-Output "$role TIMEOUT"
    }
}

foreach ($role in 'host', 'join') {
    Write-Output "===== $role (exit $((Get-Variable "${role}Proc" -ValueOnly).ExitCode)) ====="
    foreach ($kind in 'out', 'err') {
        $file = Join-Path $root "tests\_coop_$role.$kind.log"
        Get-Content $file -ErrorAction SilentlyContinue |
            Where-Object { $_ -match '^COOP |\[Pose\]|SCRIPT ERROR|Parse Error|^ERROR|^WARNING' } |
            Select-Object -First 40
    }
}