"""Exportiert jedes DCT-Modell (Root-Empty mit Property "dct_model_id") als eigene .glb nach assets/models/
(bzw. dct_paths.MODELS_DIR). Fehlt eine der Collections, wird nur die vorhandene exportiert.

Ohne GUI (so ruft build_all.py es auf):
    blender -b --factory-startup --python build_utilities.py --python export_models.py

Aufruf in Blender:
    p = r"<pfad>/export_models.py"
    exec(compile(open(p, encoding="utf-8").read(), p, "exec"), {"__name__": "__main__", "__file__": p})

Der Root wird fuer den Export auf den Ursprung gesetzt, damit der Modellursprung dem Node3D-Ursprung im
Spiel entspricht. Blender Z oben / Front -Y wird beim Export (export_yup) zu Godot Y oben / Front +Z.
Custom Properties (dct_*) landen als glTF-Extras im Modell.
"""
import os
import sys

import bpy

COLLECTIONS = ("DCT_Racks", "DCT_Utilities")
HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import dct_paths  # noqa: E402

OUT_DIR = dct_paths.MODELS_DIR


def model_roots():
    found = []
    colls = [bpy.data.collections.get(cn) for cn in COLLECTIONS]
    if all(c is None for c in colls):
        raise RuntimeError(f"Collections {COLLECTIONS} fehlen. Erst build_racks.py bzw. build_utilities.py ausfuehren.")
    for cn, coll in zip(COLLECTIONS, colls):
        if coll is None:
            print(f"Collection {cn} fehlt, uebersprungen.")
            continue
        for ob in coll.all_objects:
            if ob.parent is None and "dct_model_id" in ob:
                found.append(ob)
    return found


def export_root(root):
    objs = [root] + list(root.children_recursive)
    saved_loc = root.location.copy()
    saved_sel = [o for o in bpy.context.view_layer.objects if o.select_get()]
    saved_active = bpy.context.view_layer.objects.active
    path = os.path.join(OUT_DIR, str(root["dct_model_id"]) + ".glb")
    try:
        root.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        for o in objs:
            o.hide_set(False)
            o.hide_select = False
            o.select_set(True)
        bpy.context.view_layer.objects.active = root
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=True,
            export_extras=True,
        )
    finally:
        root.location = saved_loc
        for o in bpy.context.view_layer.objects:
            o.select_set(o in saved_sel)
        bpy.context.view_layer.objects.active = saved_active
    return path


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    for root in model_roots():
        path = export_root(root)
        print(f"{root['dct_model_id']:<22} {os.path.getsize(path) / 1024.0:8.1f} KB  {path}")


if __name__ == "__main__":
    main()