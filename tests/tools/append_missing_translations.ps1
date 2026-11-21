param([Parameter(Mandatory = $true)][string]$Proj)
# Haengt die fehlenden tr()-Texte an translations/strings.csv an.
# Schluessel: tests/out/missing_tr.txt (Datei:Zeile<TAB>Text, direkt aus dem Code).
# Englisch:   tests/out/missing_tr_en.txt (gleiche Reihenfolge, eine Zeile pro Eintrag).
$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding($false)
$csvPath = Join-Path $Proj 'translations\strings.csv'
$missPath = Join-Path $Proj 'tests\out\missing_tr.txt'
$enPath = Join-Path $Proj 'tests\out\missing_tr_en.txt'

$keys = @([System.IO.File]::ReadAllLines($missPath, $utf8) | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $_.Substring($_.IndexOf("`t") + 1) })
$ens = @([System.IO.File]::ReadAllLines($enPath, $utf8) | Where-Object { $_.Trim() -ne '' })
if ($keys.Count -ne $ens.Count) { throw ("Anzahl passt nicht: {0} Schluessel, {1} englische Texte" -f $keys.Count, $ens.Count) }

$spec = [regex]'%[-+0#]*[0-9]*(\.[0-9]+)?[a-zA-Z%]'
function Get-Specs([string]$s) { (@($spec.Matches($s) | ForEach-Object { $_.Value })) -join ' ' }
function Unescape([string]$s) { $s.Replace('\n', "`n").Replace('\"', '"') }
function Quote([string]$s) { '"' + $s.Replace('"', '""') + '"' }

$rows = Import-Csv $csvPath -Encoding UTF8
$known = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($r in $rows) { [void]$known.Add([string]$r.keys) }

$errors = 0
$lines = New-Object System.Collections.Generic.List[string]
for ($i = 0; $i -lt $keys.Count; $i++) {
    $k = Unescape $keys[$i]
    $e = Unescape $ens[$i]
    if ((Get-Specs $k) -ne (Get-Specs $e)) {
        Write-Output ("PLATZHALTER Eintrag {0}: '{1}' vs '{2}'" -f ($i + 1), (Get-Specs $k), (Get-Specs $e))
        $errors++
        continue
    }
    if ($known.Contains($k)) { continue }
    [void]$known.Add($k)
    $lines.Add((Quote $k) + ',' + (Quote $e))
}
if ($errors -gt 0) { throw ("{0} Platzhalter-Fehler, strings.csv nicht geaendert" -f $errors) }

Copy-Item $csvPath (Join-Path $Proj 'tests\out\strings.csv.bak') -Force
$text = [System.IO.File]::ReadAllText($csvPath, $utf8)
if (-not $text.EndsWith("`n")) { $text += "`n" }
$text += ($lines -join "`n") + "`n"
[System.IO.File]::WriteAllText($csvPath, $text, $utf8)
Write-Output ("angehaengt: {0} Eintraege, Sicherung in tests\out\strings.csv.bak" -f $lines.Count)