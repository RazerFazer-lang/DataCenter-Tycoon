"""Exportiert jedes DCT-Modell (Root-Empty mit Property "dct_model_id") als eigene .glb nach assets/models/.

Aufruf in Blender:
    p = r"<pfad>/export_models.py"
    exec(compile(open(p, encoding="utf-8").read(), p, "exec"), {"__name__": "__main__", "__file__": p})

Der Root wird fuer den Export auf den Ursprung gesetzt, damit der Modellursprung dem Node3D-Ursprung im
Spiel entspricht. Blender Z oben / Front -Y wird beim Export (export_yup) zu Godot Y oben / Front +Z.
Custom Properties (dct_*) landen als glTF-Extras im Modell.
"""
import os

import bpy

COLLECTIONS = ("DCT_Racks", "DCT_Utilities")
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models"))


def model_roots():
    found = []
    for cn in COLLECTIONS:
        coll = bpy.data.collections.get(cn)
        if coll is None:
            raise RuntimeError(f"Collection {cn} fehlt. Erst build_racks.py bzw. build_utilities.py ausfuehren.")
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