"""Modelle fuer Gameplay & Wirtschaft (Roadmap GAME):

    decor_diesel_gen   Kompaktes Notstromaggregat 40 kVA mit 200-l-Tankwanne (GAME-01), steht draussen
                       auf dem Rasen. Vorderseite +Z (Spiel), Auspuff hinten links oben (Knoten Exhaust_Tip).

Eigenstaendig (keine Hilfen aus anderen Generatoren), einfache Materialien GG_*.
Aufruf: blender --background --factory-startup --python tools/blender/build_gameplay_g.py
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dct_paths  # noqa: E402

OUT = dct_paths.MODELS_DIR

# Name: (Farbe, Rauheit, Metall, Leuchten)
P = {
    "GG_Body": ((0.80, 0.80, 0.76), 0.55, 0.35, 0.0),
    "GG_Trim": ((0.16, 0.17, 0.19), 0.6, 0.5, 0.0),
    "GG_Tank": ((0.22, 0.24, 0.26), 0.7, 0.4, 0.0),
    "GG_Louver": ((0.07, 0.07, 0.08), 0.7, 0.3, 0.0),
    "GG_Steel": ((0.62, 0.64, 0.66), 0.35, 0.9, 0.0),
    "GG_Exhaust": ((0.30, 0.27, 0.24), 0.5, 0.8, 0.0),
    "GG_Panel": ((0.28, 0.30, 0.33), 0.5, 0.3, 0.0),
    "GG_Red": ((0.75, 0.06, 0.05), 0.4, 0.0, 0.0),
    "GG_Yellow": ((0.95, 0.74, 0.06), 0.5, 0.0, 0.0),
    "GG_White": ((0.92, 0.92, 0.90), 0.5, 0.0, 0.0),
    "GG_Rubber": ((0.04, 0.04, 0.04), 0.9, 0.0, 0.0),
    "LIVE_GG_Display": ((0.12, 0.85, 0.35), 0.4, 0.0, 2.5),
    "LIVE_GG_Led": ((0.2, 1.0, 0.3), 0.4, 0.0, 3.0),
}
MATS = {}


def g(x, y, z):
    """Spiel (x, y hoch, z vorne) -> Blender (x, -z, y)."""
    return Vector((x, -z, y))


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    MATS.clear()
    for name, (col, rough, metal, emit) in P.items():
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        b = m.node_tree.nodes.get("Principled BSDF")
        b.inputs["Base Color"].default_value = (*col, 1.0)
        b.inputs["Roughness"].default_value = rough
        b.inputs["Metallic"].default_value = metal
        if emit > 0.0:
            b.inputs["Emission Color"].default_value = (*col, 1.0)
            b.inputs["Emission Strength"].default_value = emit
        MATS[name] = m


def _finish(bm, name, mat, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    me.materials.append(MATS[mat])
    for p in me.polygons:
        p.use_smooth = smooth
    return ob


def box(name, c, s, mat, bevel=0.0):
    """Quader mit Mitte c und Groesse s (Spielkoordinaten)."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = g(c[0] + v.co.x * s[0], c[1] + v.co.z * s[1], c[2] - v.co.y * s[2])
    if bevel > 0.0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES")
    return _finish(bm, name, mat)


def cyl(name, c, r, h, mat, axis="y", seg=20, r2=None):
    """Zylinder mit Mitte c, Achse im Spiel (x, y oder z)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    for v in bm.verts:
        x, y, z = v.co.x, v.co.y, v.co.z
        if axis == "x":
            p = (z, x, y)
        elif axis == "z":
            p = (x, y, z)
        else:
            p = (x, z, y)
        v.co = g(c[0] + p[0], c[1] + p[1], c[2] + p[2])
    return _finish(bm, name, mat, smooth=True)


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def export(root_name, objs, path):
    root = bpy.data.objects.new(root_name, None)
    bpy.context.scene.collection.objects.link(root)
    for o in objs:
        o.parent = root
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for o in objs:
        o.select_set(True)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True, export_normals=True, export_tangents=False, export_animations=False)
    print("MODELL %s %.0f KB" % (os.path.basename(path), os.path.getsize(path) / 1024.0))


def build_diesel_gen():
    reset()
    W, D = 1.86, 0.96          # Gehaeuse Breite (x) und Tiefe (z)
    TANK_H = 0.30
    BODY_H = 1.05
    top = TANK_H + BODY_H
    parts = []
    # Tankwanne mit Fuessen und Einfuellstutzen
    parts.append(box("tank", (0, TANK_H * 0.5, 0), (W + 0.06, TANK_H, D + 0.06), "GG_Tank", 0.012))
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(box("foot", (sx * (W * 0.5 - 0.06), 0.015, sz * (D * 0.5 - 0.05)), (0.12, 0.03, 0.10), "GG_Rubber"))
    parts.append(cyl("filler", (W * 0.5 - 0.22, TANK_H + 0.035, D * 0.5 - 0.10), 0.045, 0.07, "GG_Steel", seg=16))
    parts.append(cyl("gauge", (-W * 0.5 + 0.30, TANK_H * 0.5, D * 0.5 + 0.032), 0.055, 0.01, "GG_White", axis="z", seg=20))
    parts.append(box("gauge_needle", (-W * 0.5 + 0.30, TANK_H * 0.5 + 0.015, D * 0.5 + 0.039), (0.006, 0.04, 0.003), "GG_Red"))
    # Schallschutzhaube
    parts.append(box("body", (0, TANK_H + BODY_H * 0.5, 0), (W, BODY_H, D), "GG_Body", 0.03))
    parts.append(box("roof", (0, top + 0.018, 0), (W + 0.02, 0.036, D + 0.02), "GG_Trim", 0.01))
    parts.append(box("base_trim", (0, TANK_H + 0.02, 0), (W + 0.01, 0.04, D + 0.01), "GG_Trim"))
    # Lueftungsgitter vorn links und hinten (Lamellen)
    for side in (1, -1):
        zf = side * (D * 0.5 + 0.004)
        parts.append(box("louver_frame", (-0.38, TANK_H + 0.56, zf), (0.86, 0.70, 0.01), "GG_Trim"))
        for i in range(9):
            y = TANK_H + 0.26 + i * 0.075
            parts.append(box("slat", (-0.38, y, zf + side * 0.008), (0.80, 0.026, 0.012), "GG_Louver"))
    # Seitliche Lueftung
    for sx in (-1, 1):
        for i in range(6):
            parts.append(box("side_slat", (sx * (W * 0.5 + 0.006), TANK_H + 0.32 + i * 0.09, 0), (0.01, 0.03, D * 0.7), "GG_Louver"))
    # Bedienfeld rechts vorne: Tuer, Display, Not-Aus, Schalter, Warnschild
    zf = D * 0.5 + 0.006
    parts.append(box("panel_door", (0.52, TANK_H + 0.56, zf), (0.66, 0.78, 0.012), "GG_Panel", 0.004))
    parts.append(box("panel_window", (0.52, TANK_H + 0.70, zf + 0.008), (0.40, 0.24, 0.006), "GG_Trim"))
    parts.append(box("display", (0.44, TANK_H + 0.72, zf + 0.013), (0.18, 0.10, 0.004), "LIVE_GG_Display"))
    parts.append(box("led", (0.66, TANK_H + 0.76, zf + 0.013), (0.03, 0.03, 0.004), "LIVE_GG_Led"))
    parts.append(cyl("estop_base", (0.66, TANK_H + 0.66, zf + 0.016), 0.035, 0.012, "GG_Yellow", axis="z", seg=20))
    parts.append(cyl("estop", (0.66, TANK_H + 0.66, zf + 0.030), 0.024, 0.02, "GG_Red", axis="z", seg=20))
    parts.append(box("handle", (0.82, TANK_H + 0.50, zf + 0.02), (0.025, 0.14, 0.025), "GG_Steel"))
    parts.append(box("warn", (0.40, TANK_H + 0.40, zf + 0.008), (0.12, 0.10, 0.003), "GG_Yellow"))
    # Haubengriffe vorne und hinten
    for side in (1, -1):
        parts.append(box("hood_handle", (-0.38, top - 0.10, side * (D * 0.5 + 0.02)), (0.22, 0.025, 0.025), "GG_Steel"))
    # Krankoesen auf dem Dach
    for sx in (-1, 1):
        for sz in (-1, 1):
            parts.append(box("eye", (sx * (W * 0.5 - 0.10), top + 0.06, sz * (D * 0.5 - 0.10)), (0.05, 0.06, 0.02), "GG_Steel"))
    # Schalldaempfer und Auspuff hinten links mit Regenkappe
    parts.append(cyl("muffler", (-0.55, top + 0.12, -0.18), 0.09, 0.40, "GG_Exhaust", axis="x", seg=20))
    parts.append(cyl("pipe", (-0.72, top + 0.30, -0.18), 0.04, 0.36, "GG_Exhaust", seg=16))
    parts.append(box("rain_cap", (-0.72, top + 0.49, -0.16), (0.10, 0.012, 0.10), "GG_Exhaust"))
    body = join(parts, "DieselGen")
    tip = bpy.data.objects.new("Exhaust_Tip", None)
    bpy.context.scene.collection.objects.link(tip)
    tip.location = g(-0.72, top + 0.50, -0.18)
    export("DieselGenRoot", [body, tip], os.path.join(OUT, "decor_diesel_gen.glb"))


if __name__ == "__main__":
    build_diesel_gen()
