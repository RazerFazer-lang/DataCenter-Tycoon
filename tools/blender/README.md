# Blender-Modelle bauen

Alle aktuellen Modelle mit einem Befehl (aus dem Projektordner, PowerShell):

```powershell
.\tools\blender\build_all.ps1                                   # baut nach assets/models
.\tools\blender\build_all.ps1 --out C:\temp\modelle             # Probelauf, schreibt nichts ins Projekt
.\tools\blender\build_all.ps1 --out C:\temp\modelle --only build_desk,build_racks
.\tools\blender\build_all.ps1 --list                            # Reihenfolge und ausgelassene Skripte
```

Ohne PowerShell: `blender -b --factory-startup --python tools/blender/build_all.py -- [Optionen]`.
Blender wird über `$env:BLENDER`, den PATH oder `C:\Program Files\Blender Foundation\Blender*` gefunden.

Jeder Generator läuft in einem eigenen, frischen Blender-Prozess (`--factory-startup`), immer in derselben
Reihenfolge (Liste `GENERATORS` in `build_all.py`). Schlägt einer fehl, laufen die übrigen weiter; am Ende
steht eine Zusammenfassung und der Exit-Code ist 1.

## Optionen

| Option | Bedeutung |
|---|---|
| `--out <ordner>` | Zielordner der `.glb` (Standard `assets/models`) |
| `--only a,b` | nur diese Generatoren (Namen ohne `.py`) |
| `--no-previews` | keine Vorschaubilder |
| `--clean` | alte `.glb` im Zielordner vorher löschen (für `assets/models` gesperrt) |
| `--fresh-cache` | PBR-Cache leer starten statt mit `tools/blender/_pbr_cache` (nur mit `--out`) |
| `--jobs N` | parallele Blender-Prozesse für die Vorschaubilder (Standard 4) |
| `--size PX` | Größe eines Vorschaubilds (Standard 256) |
| `--timeout MIN` | Zeitlimit je Generator (Standard 60) |

## Wo landet was

| | `--out` außerhalb von `assets/models` | Standard (`assets/models`) |
|---|---|---|
| Modelle | `<out>/*.glb` | `assets/models` |
| Kontaktbögen | `<out>/_previews/<generator>.png`, alt/neu: `_vergleich.png` | `tools/blender/_build/_previews` |
| Bericht | `<out>/_report.md` | `tools/blender/_build/_report.md` |
| Logs je Generator | `<out>/_build/logs` | `tools/blender/_build/logs` |
| Texturen (nature/, carton/) | `<out>/_build/textures` | `assets/textures` |
| PBR-Cache | `<out>/_build/pbr_cache` (Kopie von `_pbr_cache`) | `tools/blender/_pbr_cache` |
| `.blend`, Generator-Vorschauen | `<out>/_build/work` | `tools/blender` |

Die Generatoren lesen die Ordner aus `dct_paths.py` (Umgebungsvariablen `DCT_MODELS_OUT`,
`DCT_TEXTURES_OUT`, `DCT_PBR_CACHE`, `DCT_WORK_OUT`). Einzeln gestartet verhalten sie sich wie bisher.

Der Bericht vergleicht die gebauten Modelle mit `assets/models` (Stand vor dem Lauf): nur gebaut, nur in
`assets/models`, und für gleiche Namen Größe, Knoten, Meshes, Vertices, Dreiecke, Materialien und
Bounding-Box. Für abweichende Modelle zeigt `_vergleich.png` alt und neu nebeneinander (nur mit `--out`).

## Nach einem Lauf nach `assets/models`

1. `node tools/dedupe_glb_textures.js` – Blender bettet die Bilder wieder ein, das Skript legt sie
   gemeinsam nach `assets/textures/shared`.
2. `godot --headless --path . -s res://tools/build_merge_cache.gd` – Teile-Cache für MeshMerger.

## Ausgelassene Skripte

Aktuell ist ein Generator, wenn seine Modelle heute in `assets/models` liegen. Die übrigen `build_*.py`
stehen mit Grund in `EXCLUDED` (`build_all.py`): die Bibliothek `build_delivery_van.py`, Module von
`build_utilities.py` (`build_routers.py`, `build_hall_c.py`, dazu `export_models.py`) und überholte
Generatoren (`build_strip_props.py`, `build_player.py`, `build_characters.py`, `build_fp_arms.py`,
`build_fp_hand.py`). Weitere Bibliotheken ohne eigenen Lauf: `hall_pbr_kit.py`, `pbr_textures.py`,
`rack_pbr_textures.py`, `dct_paths.py`. Ein neues `build_*.py`, das in keiner der beiden Listen steht,
meldet `build_all.py` als Warnung.

`build_decor_props.py` baut noch sechs `decor_*`-Modelle, deren Spielfassung inzwischen aus
`build_paket_c.py` kommt; es läuft deshalb vorher und wird überschrieben (steht im Bericht).
