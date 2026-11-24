"""Konvertiert heruntergeladene Mixamo- / MakeHuman-FBX-Charaktere automatisch in Godot-fertige .glb-Dateien!

Verwendung:
    1. Lege deine heruntergeladene Mixamo-.fbx-Datei ab unter:
         assets/models/import/player_realistic.fbx
         assets/models/import/delivery_driver_realistic.fbx
    2. Starte dieses Skript mit Blender:
         blender --background --factory-startup --python tools/blender/convert_mixamo_to_glb.py
    3. Ergebnis landet automatisch als .glb in assets/models/ und wird im Spiel sofort erkannt!
"""

import os
import sys
import traceback
import bpy

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
MODELS_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models"))
IMPORT_DIR = os.path.join(MODELS_DIR, "import")

TARGETS = [
    ("player_realistic.fbx", "player_realistic.glb"),
    ("delivery_driver_realistic.fbx", "delivery_driver_realistic.glb"),
]


def convert_one(src_fbx: str, dst_glb: str):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=src_fbx, automatic_bone_orientation=True)
    bpy.ops.export_scene.gltf(
        filepath=dst_glb,
        export_format="GLB",
        export_materials="EXPORT",
        export_yup=True,
        export_skins=True,
        export_animations=True,
    )
    print(f"CONVERTED: {src_fbx} -> {dst_glb} ({os.path.getsize(dst_glb)} bytes)")


def main():
    os.makedirs(IMPORT_DIR, exist_ok=True)
    converted = 0
    for src_name, dst_name in TARGETS:
        src = os.path.join(IMPORT_DIR, src_name)
        dst = os.path.join(MODELS_DIR, dst_name)
        if os.path.isfile(src):
            convert_one(src, dst)
            converted += 1
        else:
            print(f"SKIP (nicht gefunden): {src}")
    print(f"FERTIG: {converted} Charakter(e) konvertiert.")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
