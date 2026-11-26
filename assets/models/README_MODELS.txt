# Eigene 3D-Modelle (.glb) für DataCenter Tycoon

Du kannst hier (oder neben der exportierten `.exe` im Ordner `custom_models/`) eigene `.glb`-Dateien aus Blender, Sketchfab oder Kenney ablegen. Das Spiel erkennt sie beim Start automatisch über `ModelLoader`!

Unterstützte Dateinamen:
- `rack.glb` (Standard 4U Rack — Maßstab ~0.9m × 2.1m × 0.9m, Boden bei Y=0)
- `rack_pro.glb` (Enterprise 6U Rack — ~0.9m × 2.48m × 0.9m)
- `cooler.glb` (Klimaanlage AC-1 — ~0.75m × 1.36m × 0.6m)
- `chiller.glb` (Industrie-Kühler AC-Pro — ~0.78m × 1.76m × 0.6m)
- `ups.glb` (USV-Notstrom-Batterie — ~0.7m × 1.28m × 0.6m)
- `cart.glb` (Schwerlast-Rollwagen — ~0.92m × 1.0m × 1.18m)
- `crate.glb` (Lieferkarton — ~0.62m × 0.48m × 0.62m)
- `deliver_van.glb`, `deliver_truck.glb`, `deliver_heavy.glb` (Lieferfahrzeuge der Stufen 1 bis 3, Erzeuger: `tools/blender/build_delivery_c.py`)
- `player.glb` (Co-op-Spielermodell — ~1.72m hoch, Boden bei Y=0, Front zeigt nach -Z. Braucht die Gelenke `Pivot_LegL`, `Pivot_LegR`, `Pivot_ArmL`, `Pivot_ArmR`, `Pivot_Head`. Das Material `DCT_Jacket` wird in der Spielerfarbe eingefärbt.)

Wenn eine Datei nicht vorhanden ist, nutzt das Spiel automatisch die eingebauten PBR-3D-Modelle.
