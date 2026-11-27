# Veröffentlichen mit einem Befehl (REL-03)

```powershell
.\tools\release\release.ps1 -Version 3.5.0 -DryRun
.\tools\release\release.ps1 -Version 3.5.0 -Include scripts,tests,launcher -Publish
```

Vorher die Notizen anlegen: `tools/release/notes/v3.5.0.json` (Vorlage `BEISPIEL.json`):
`title`, `items` (erscheinen im Spiel unter „Was ist neu?“, im Launcher und im Changelog) und `roadmap`.
Liegt daneben `v3.5.0.md`, ist das der Text des GitHub-Releases, sonst wird er aus `items` gebaut.

## Was das Skript macht

1. Vorprüfung: Godot, dotnet, node, git und gh vorhanden, auf `main`, nichts hinter `origin/main`, Tag noch frei.
2. Version setzen (`bump_version.js`): project.godot, export_presets.cfg, Launcher-Projekt, version.json mit Changelog, roadmap.json.
3. Tests: `compile_check` und `translation_check`, mit `-FullTests` alle `tests/*_check.gd` außer der langen Werkbank. Läuft in einem eigenen APPDATA, deine Spielstände bleiben unberührt.
4. Launcher bauen (`dotnet publish`) und Spiel exportieren (Godot, Vorlage „Windows Desktop“).
5. Signieren mit `sign.ps1` (siehe unten). Ohne Zertifikat wird das übersprungen.
6. Probelauf: Das fertige Spiel läuft 30 s, wird geschlossen und darf keinen Fehler im Log haben.
7. Zips mit `.sha256` nach `dist/release/`.
8. Kleines Update (REL-02): Delta von der letzten veröffentlichten Version (`tools/delta`). Gegenprobe: Delta auf die Vorversion anwenden und jede Datei vergleichen.
9. Commit (nur Versionsdateien plus `-Include`), Push nach `main`, Release-Entwurf mit allen Dateien.
10. Mit `-Publish`: freischalten als „Latest“ und jede Datei von GitHub laden und vergleichen.

Schalter: `-DryRun` (bis Schritt 8, nichts wird committet oder hochgeladen), `-SkipTests`, `-FullTests`, `-SkipSmoke`, `-NoDelta`, `-Godot <pfad>` (oder Umgebungsvariable `DCT_GODOT`).

Bricht bei jedem Fehler ab. Logs liegen in `dist\work\v<Version>\logs`.
`Roadmap.txt`, Logs, `dist/` und Build-Ordner können nicht in den Commit geraten.

## Signieren (REL-04)

Gegen die SmartScreen-Warnung hilft nur ein Code-Signing-Zertifikat einer anerkannten Stelle.
Das Skript ist fertig, es fehlt nur das Zertifikat. Zwei Wege:

**Azure Trusted Signing** (Microsoft, rund 10 US-$ im Monat, Identitätsprüfung nötig):
1. Im Azure-Portal ein Trusted-Signing-Konto und ein Zertifikatprofil („Public Trust“) anlegen.
2. Windows SDK (für `signtool.exe`) und das Paket „Microsoft.Trusted.Signing.Client“ (enthält `Azure.CodeSigning.Dlib.dll`) installieren.
3. `metadata.json` anlegen: `{ "Endpoint": "...", "CodeSigningAccountName": "...", "CertificateProfileName": "..." }`.
4. Anmelden (`az login`) und setzen: `DCT_SIGN_AZURE_DLIB` und `DCT_SIGN_AZURE_METADATA`.

**Gekauftes Zertifikat** (OV oder EV, als .pfx):
`DCT_SIGN_PFX` und `DCT_SIGN_PFX_PASSWORD` setzen. EV-Zertifikate auf einem USB-Token brauchen stattdessen den Zertifikatsspeicher. Dann `sign.ps1` um `/sha1 <Fingerabdruck>` erweitern.

Zertifikate, Passwörter und `metadata.json` gehören nie ins Repo. Signiert werden `DataCenterTycoon.exe`, `DataCenterTycoon.console.exe` und `DataCenterLauncher.exe`, jeweils mit Zeitstempel. Danach prüft `signtool verify` die Signatur.
