"""Aussenbereich und Spind fuer Paket D. Nur einfache Materialien (OD_*), die Texturen kommen im Spiel dazu.

    locker, back_door (Frame, Leaf), gate (Frame, Panel), gate_post, roof_ladder, roof_rail, solar_panel, sat_dish (Base, Arm),
    weather_station (Mast, Cups, Vane), garden_bench, garden_table, grill (Body, Lid, Food), raised_bed, bird_feeder, bird_bath,
    bollard_lamp, wall_lamp, plant_tomato / plant_lettuce / plant_berry, snow_cap, leaf_pile

Aufruf: blender --background --factory-startup --python tools/blender/build_outdoor_d.py [-- name ...]
"""
import math
import os
import random
import sys

import bpy
import bmesh
from mathutils import Vector as V, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_human as H
from build_human import g, back, Blob, set_mats, join, box, tube, move, vcol, smoothstep

OUT = os.path.join(os.path.dirname(os.path.dirname(HERE)), "assets", "models")
P = {
    "OD_Wood": ((0.52, 0.36, 0.22), 0.8, 0.0), "OD_WoodDark": ((0.30, 0.20, 0.13), 0.8, 0.0), "OD_Steel": ((0.24, 0.26, 0.29), 0.5, 0.6), "OD_Galv": ((0.68, 0.70, 0.72), 0.4, 0.85),
    "OD_Black": ((0.05, 0.05, 0.06), 0.6, 0.1), "OD_White": ((0.92, 0.92, 0.90), 0.5, 0.0), "OD_Grey": ((0.55, 0.58, 0.61), 0.5, 0.1), "OD_Blue": ((0.10, 0.22, 0.42), 0.45, 0.1),
    "OD_Red": ((0.62, 0.08, 0.07), 0.4, 0.1), "OD_Yellow": ((0.92, 0.70, 0.08), 0.5, 0.0), "OD_Green": ((0.15, 0.36, 0.16), 0.6, 0.0), "OD_Concrete": ((0.62, 0.61, 0.58), 0.9, 0.0),
    "OD_Soil": ((0.16, 0.11, 0.08), 0.98, 0.0), "OD_Cell": ((0.03, 0.06, 0.16), 0.12, 0.35), "OD_Line": ((0.70, 0.73, 0.78), 0.3, 0.6), "OD_Glass": ((0.55, 0.65, 0.72), 0.06, 0.0),
    "OD_Lamp": ((1.0, 0.90, 0.70), 0.4, 0.0), "OD_LedRed": ((1.0, 0.12, 0.08), 0.4, 0.0), "OD_LedGreen": ((0.15, 1.0, 0.30), 0.4, 0.0), "OD_Coal": ((0.10, 0.09, 0.09), 1.0, 0.0), "OD_Ember": ((1.0, 0.32, 0.06), 0.8, 0.0),
    "OD_Meat": ((0.46, 0.20, 0.12), 0.6, 0.0), "OD_Sausage": ((0.60, 0.28, 0.14), 0.4, 0.0), "OD_Leaf": ((0.18, 0.42, 0.14), 0.7, 0.0), "OD_LeafLight": ((0.42, 0.66, 0.24), 0.7, 0.0), "OD_Tomato": ((0.82, 0.10, 0.06), 0.35, 0.0),
    "OD_Berry": ((0.80, 0.06, 0.12), 0.4, 0.0), "OD_Seed": ((0.62, 0.48, 0.28), 0.9, 0.0), "OD_Water": ((0.30, 0.45, 0.52), 0.05, 0.0), "OD_Snow": ((0.92, 0.95, 0.98), 0.8, 0.0), "OD_Fabric": ((0.20, 0.34, 0.52), 0.9, 0.0),
    "OD_LeafFall": ((0.70, 0.36, 0.10), 0.8, 0.0), "OD_Chrome": ((0.85, 0.86, 0.88), 0.15, 0.95), "OD_Terra": ((0.64, 0.34, 0.22), 0.85, 0.0),
}


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    H.MATS.clear()
    for k, (c, r, m) in P.items():
        H.mat(k, c, r, m, 2.0 if k in ("OD_Lamp", "OD_LedRed", "OD_LedGreen", "OD_Ember") else 0.0)


def at(ob, x, y, z):
    """Ursprung versetzen, ohne die Form zu bewegen."""
    d = V(g(x, y, z))
    for v in ob.data.vertices:
        v.co -= d
    ob.location = d
    return ob


def cyl(c, r, h, m, axis="y", seg=20, r2=None, bevel=0.0):
    """Zylinder mit Mitte c."""
    r2 = r if r2 is None else r2
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=seg, radius1=r, radius2=r2, depth=h)
    if bevel:
        ed = [e for e in bm.edges if len(e.link_faces) == 2 and (len(e.link_faces[0].verts) > 4 or len(e.link_faces[1].verts) > 4)]
        bmesh.ops.bevel(bm, geom=ed, offset=bevel, segments=2, affect="EDGES")
    me = bpy.data.meshes.new("c")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("c", me)
    bpy.context.scene.collection.objects.link(ob)
    for v in me.vertices:
        x, y, z = v.co       # Blender: Achse z = hoch
        if axis == "x":
            p = (z, x, y)
        elif axis == "z":
            p = (x, y, z)
        else:
            p = (x, z, -y)
        v.co = g(p[0] + c[0], p[1] + c[1], p[2] + c[2])
    for p in me.polygons:
        p.use_smooth = True
    set_mats(ob, [m])
    md = ob.modifiers.new("n", "EDGE_SPLIT")
    md.split_angle = math.radians(40)
    return H.apply_mods(ob)


def blob(b, m, voxel, faces, smooth=3):
    ob = b.mesh("b", voxel, smooth, 0.45, faces)
    set_mats(ob, [m])
    return ob


def export(name):
    for o in bpy.data.objects:
        if o.type == "MESH":
            md = o.modifiers.new("w", "WEIGHTED_NORMAL")
            md.keep_sharp = True
    bpy.ops.object.select_all(action="SELECT")
    path = os.path.join(OUT, name + ".glb")
    n = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=True, export_normals=True, export_tangents=False, export_animations=False, export_image_format="NONE")
    print("AUSSEN %s %d Flaechen %.2f MB" % (name, n, os.path.getsize(path) / 1048576.0))


ALL = {}


def model(fn):
    ALL[fn.__name__] = fn
    return fn


@model
def locker():
    """Zwei Spindtueren links (x -0.78..0.12), rechts Spiegel (x 0.22..0.78). Front +z."""
    o = [box("b", [((-0.33, 0.06, 0.0), (0.92, 0.12, 0.40)), ((-0.33, 0.99, -0.195), (0.92, 1.74, 0.02)), ((-0.78, 0.99, 0.0), (0.02, 1.74, 0.41)), ((0.12, 0.99, 0.0), (0.02, 1.74, 0.41)),
                  ((-0.33, 0.99, 0.0), (0.02, 1.74, 0.39)), ((-0.33, 1.865, 0.0), (0.92, 0.02, 0.41)), ((-0.33, 0.13, 0.0), (0.90, 0.02, 0.39))], "OD_Grey", 0.004)]
    o.append(box("t", [((-0.33, 1.895, 0.0), (0.94, 0.04, 0.43))], "OD_Steel", 0.008))
    for x in (-0.55, -0.10):
        o.append(box("s", [((x, 1.58, 0.0), (0.42, 0.015, 0.37))], "OD_Galv", 0.003))
        o.append(cyl((x, 1.50, 0.0), 0.012, 0.42, "OD_Galv", "x", 12))
    # Inhalt: Jacken auf Buegeln, Helm, Schuhe
    for x, m, dz in ((-0.64, "OD_Blue", 0.0), (-0.56, "OD_Yellow", 0.01), (-0.47, "OD_Fabric", -0.01), (-0.16, "OD_Red", 0.0), (-0.06, "OD_Green", 0.0)):
        b = Blob()
        b.ell((x, 1.18, dz), (0.030, 0.26, 0.135))
        b.ell((x, 1.40, dz), (0.028, 0.06, 0.12))
        o.append(blob(b, m, 0.012, 500))
        o.append(tube("h", [(x, 1.46, dz), (x, 1.50, dz), (x, 1.512, dz + 0.012)], 0.004, "OD_Chrome", 6))
    b = Blob(); b.ell((-0.10, 1.63, 0.0), (0.10, 0.085, 0.125)); o.append(blob(b, "OD_Yellow", 0.008, 500))
    for x in (-0.62, -0.50, -0.16, -0.05):
        b = Blob(); b.ell((x, 0.175, 0.02), (0.042, 0.035, 0.12)); b.ell((x, 0.22, -0.05), (0.040, 0.06, 0.05)); o.append(blob(b, "OD_Black" if x < -0.3 else "OD_WoodDark", 0.008, 300))
    # Spiegelrahmen und Bank darunter
    o.append(box("f", [((0.50, 1.06, 0.19), (0.66, 1.74, 0.035))], "OD_Steel", 0.010))
    o.append(box("fi", [((0.50, 1.06, 0.2085), (0.565, 1.645, 0.006))], "OD_Black", 0.001))
    o.append(box("w", [((0.50, 0.99, -0.005), (0.10, 1.80, 0.36))], "OD_Grey", 0.01))
    o.append(box("l", [((0.50, 1.965, 0.22), (0.50, 0.03, 0.06))], "OD_Steel", 0.006))
    o.append(box("ll", [((0.50, 1.948, 0.225), (0.44, 0.008, 0.035))], "OD_Lamp", 0.002))
    join("Body", o)
    for nme, x0, hinge in (("Door_A", -0.55, -0.77), ("Door_B", -0.10, 0.11)):
        s = 1 if nme == "Door_A" else -1
        d = [box("d", [((x0, 1.0, 0.205), (0.435, 1.70, 0.018))], "OD_Blue", 0.004)]
        for k in range(5):
            d.append(box("v", [((x0, 1.66 - k * 0.035, 0.2155), (0.20, 0.010, 0.006), (20, 0, 0))], "OD_Black", 0.001))
        d.append(box("h", [((x0 + s * 0.17, 1.02, 0.222), (0.030, 0.12, 0.016))], "OD_Galv", 0.004))
        d.append(box("k", [((x0, 1.80, 0.2155), (0.10, 0.045, 0.004))], "OD_White", 0.001))
        at(join(nme, d), hinge, 0, 0.205)
    export("locker")


@model
def back_door():
    """Aussentuer 1.00 x 2.10 in einer 0.5 m dicken Laibung. Blatt schwingt nach aussen (+z), Angel bei x -0.45."""
    o = [box("f", [((-0.49, 1.06, 0.0), (0.08, 2.14, 0.52)), ((0.49, 1.06, 0.0), (0.08, 2.14, 0.52)), ((0, 2.13, 0.0), (1.06, 0.08, 0.52)), ((0, 0.015, 0.0), (0.92, 0.03, 0.52))], "OD_Steel", 0.004)]
    for z in (-0.265, 0.265):
        o.append(box("t", [((-0.545, 1.08, z), (0.07, 2.22, 0.03)), ((0.545, 1.08, z), (0.07, 2.22, 0.03)), ((0, 2.19, z), (1.16, 0.07, 0.03))], "OD_Grey", 0.006))
    o.append(box("st", [((0, -0.03, 0.62), (1.4, 0.10, 0.72))], "OD_Concrete", 0.01))
    o.append(box("mat", [((0, 0.024, 0.60), (0.80, 0.012, 0.46))], "OD_Black", 0.004))
    o.append(box("ro", [((0, 2.42, 0.62), (1.5, 0.035, 0.78), (-6, 0, 0))], "OD_Glass", 0.004))
    o.append(box("rs", [((-0.70, 2.40, 0.62), (0.03, 0.05, 0.78), (-6, 0, 0)), ((0.70, 2.40, 0.62), (0.03, 0.05, 0.78), (-6, 0, 0))], "OD_Steel", 0.004))
    join("Frame", o)
    d = [box("d", [((0, 1.055, 0.22), (0.885, 2.05, 0.05))], "OD_Blue", 0.005)]
    d.append(box("gf", [((0, 1.52, 0.2475), (0.40, 0.72, 0.008)), ((0, 1.52, 0.1925), (0.40, 0.72, 0.008))], "OD_Steel", 0.004))
    d.append(box("gl", [((0, 1.52, 0.22), (0.33, 0.65, 0.062))], "OD_Glass", 0.002))
    for z, s in ((0.262, 1), (0.178, -1)):
        d.append(box("hp", [((0.375, 1.05, z - s * 0.012), (0.045, 0.22, 0.008))], "OD_Galv", 0.003))
        d.append(tube("h", [(0.375, 1.08, z - s * 0.01), (0.375, 1.08, z + s * 0.035), (0.27, 1.08, z + s * 0.035)], 0.0105, "OD_Galv", 10))
        d.append(cyl((0.375, 0.99, z - s * 0.006), 0.014, 0.012, "OD_Chrome", "z", 16))
    d.append(box("kp", [((0, 0.16, 0.2475), (0.80, 0.24, 0.004))], "OD_Galv", 0.002))
    at(join("Leaf", d), -0.445, 0, 0.22)
    export("back_door")


@model
def gate():
    """Schiebetor 8.0 m: laeuft nach +x auf. Feste Teile in Frame."""
    o = [box("r", [((4.0, -0.005, 0.0), (16.2, 0.02, 0.10))], "OD_Galv", 0.004)]
    for x in (4.02, 4.02):
        pass
    for z in (-0.16, 0.16):
        o.append(box("p", [((4.15, 1.05, z), (0.14, 2.10, 0.12))], "OD_Steel", 0.01))
    o.append(box("pt", [((4.15, 2.08, 0.0), (0.16, 0.10, 0.46))], "OD_Steel", 0.01))
    o.append(box("e", [((-4.10, 1.0, 0.0), (0.16, 2.0, 0.22))], "OD_Steel", 0.01))
    o.append(box("m", [((4.62, 0.38, 0.42), (0.36, 0.72, 0.30))], "OD_Grey", 0.02))
    o.append(box("ml", [((4.62, 0.76, 0.42), (0.40, 0.05, 0.34))], "OD_Black", 0.01))
    o.append(cyl((4.15, 2.22, 0.0), 0.055, 0.12, "OD_Yellow", "y", 18, None, 0.01))
    join("Frame", o)
    d = [box("f", [((0, 0.16, 0), (8.05, 0.12, 0.08)), ((0, 1.78, 0), (8.05, 0.07, 0.07)), ((-3.98, 0.97, 0), (0.08, 1.68, 0.08)), ((3.98, 0.97, 0), (0.08, 1.68, 0.08)), ((0, 0.97, 0), (0.06, 1.60, 0.06))], "OD_Steel", 0.006)]
    d.append(box("b", [((-3.9 + 0.13 * i, 0.98, 0), (0.028, 1.58, 0.028)) for i in range(61)], "OD_Steel", 0.0))
    d.append(box("z", [((-3.96 + 0.072 * i, 1.83, 0), (0.016, 0.05, 0.016), (0, 45, 0)) for i in range(111)], "OD_Steel", 0.0))
    d.append(box("w", [((0, 1.10, 0.045), (0.60, 0.40, 0.006))], "OD_White", 0.002))
    d.append(box("ws", [((0, 1.10, 0.0485), (0.56, 0.36, 0.002))], "OD_Yellow", 0.0))
    for x in (-3.4, 3.4):
        d.append(cyl((x, 0.05, 0), 0.06, 0.05, "OD_Black", "z", 20))
    join("Panel", d)
    export("gate")


@model
def gate_post():
    """Bedienstele mit Tastenfeld."""
    o = [cyl((0, 0.55, 0), 0.045, 1.10, "OD_Steel", "y", 20), cyl((0, 0.01, 0), 0.11, 0.02, "OD_Galv", "y", 24)]
    o.append(box("h", [((0, 1.18, 0.02), (0.18, 0.26, 0.10), (-12, 0, 0))], "OD_Steel", 0.014))
    o.append(box("p", [((0, 1.18, 0.072), (0.15, 0.22, 0.008), (-12, 0, 0))], "OD_Black", 0.004))
    for r in range(4):
        for c in range(3):
            o.append(box("k", [((-0.036 + c * 0.036, 1.215 - r * 0.030, 0.0835 - (1.18 - (1.215 - r * 0.030)) * 0.21), (0.026, 0.021, 0.006), (-12, 0, 0))], "OD_Galv", 0.002))
    o.append(box("g", [((-0.03, 1.262, 0.0955), (0.016, 0.010, 0.006), (-12, 0, 0))], "OD_LedGreen", 0.001))
    o.append(box("r", [((0.03, 1.262, 0.0955), (0.016, 0.010, 0.006), (-12, 0, 0))], "OD_LedRed", 0.001))
    o.append(box("d", [((0, 1.335, 0.06), (0.22, 0.02, 0.20), (-12, 0, 0))], "OD_Steel", 0.006))
    join("Body", o)
    export("gate_post")


@model
def roof_ladder():
    """Steigleiter 5.2 m hoch mit Rueckenschutz, Wand bei z 0, Leiter bei z 0.22."""
    o = []
    for x in (-0.23, 0.23):
        o.append(box("s", [((x, 2.62, 0.22), (0.055, 5.24, 0.028))], "OD_Galv", 0.006))
        o.append(tube("b", [(x, 5.20, 0.22), (x, 5.38, 0.16), (x, 5.40, -0.10), (x, 5.36, -0.55), (x, 4.40, -0.60)], 0.018, "OD_Galv", 10))
        for y in (0.5, 1.9, 3.3, 4.2):
            o.append(box("w", [((x, y, 0.10), (0.03, 0.05, 0.24))], "OD_Galv", 0.004))
    for i in range(18):
        o.append(cyl((0, 0.30 + i * 0.28, 0.22), 0.015, 0.46, "OD_Galv", "x", 10))
    for y in (2.4, 3.1, 3.8, 4.5, 5.1):
        pts = [(math.sin(a) * 0.36, y, 0.24 + (1 - math.cos(a)) * 0.36) for a in [math.radians(-112 + 224 * k / 16.0) for k in range(17)]]
        pts = [(-math.sin(math.radians(-112 + 224 * k / 16.0)) * 0.36, y, 0.40 + math.cos(math.radians(-112 + 224 * k / 16.0)) * 0.36) for k in range(17)]
        o.append(tube("r", pts, 0.012, "OD_Galv", 6))
    for a in (-60, -20, 20, 60):
        x, z = math.sin(math.radians(a)) * 0.36, 0.40 + math.cos(math.radians(a)) * 0.36
        o.append(box("v", [((x, 3.75, z), (0.03, 2.72, 0.008))], "OD_Galv", 0.0))
    join("Body", o)
    export("roof_ladder")


@model
def roof_rail():
    """Absturzsicherung, Feld 2 m."""
    o = []
    for x in (-1.0, 1.0):
        o.append(cyl((x, 0.52, 0), 0.021, 1.04, "OD_Galv", "y", 12))
        o.append(box("f", [((x, 0.01, 0.0), (0.12, 0.02, 0.12))], "OD_Galv", 0.004))
        o.append(box("w", [((x, 0.06, 0.42), (0.24, 0.10, 0.36))], "OD_Concrete", 0.015))
        o.append(tube("a", [(x, 0.05, 0.40), (x, 0.06, 0.02)], 0.016, "OD_Galv", 8))
    for y in (0.52, 1.02):
        o.append(cyl((0, y, 0), 0.019, 2.0, "OD_Galv", "x", 12))
    join("Body", o)
    export("roof_rail")


@model
def solar_panel():
    """Modul 1.05 x 1.75 aufgestaendert 15 Grad, Flaeche blickt nach +z."""
    o = []
    tilt = -18
    c, s = math.cos(math.radians(18)), math.sin(math.radians(18))

    def pt(u, v, w=0.0):
        return (u, 0.36 + v * s * -1.0 * -1.0 * 0 + (-v) * s + w * c, v * c + w * s)
    # Rahmen und Zellen ueber Punktverschiebung
    parts = [box("fr", [((0, 0, -0.86), (1.05, 0.035, 0.03)), ((0, 0, 0.86), (1.05, 0.035, 0.03)), ((-0.51, 0, 0), (0.03, 0.035, 1.75)), ((0.51, 0, 0), (0.03, 0.035, 1.75))], "OD_Galv", 0.003)]
    parts.append(box("cell", [((0, 0.004, 0), (0.99, 0.012, 1.69))], "OD_Cell", 0.0))
    ln = []
    for k in range(1, 6):
        ln.append(((-0.495 + 0.165 * k, 0.0106, 0), (0.004, 0.001, 1.69)))
    for k in range(1, 10):
        ln.append(((0, 0.0106, -0.845 + 0.169 * k), (0.99, 0.001, 0.004)))
    parts.append(box("ln", ln, "OD_Line", 0.0))
    for ob in parts:
        for v in ob.data.vertices:
            x, y, z = back(v.co)
            v.co = g(x, 0.40 - z * s + y * c, z * c + y * s)
    o += parts
    for x in (-0.42, 0.42):
        o.append(box("l", [((x, 0.33, -0.70), (0.03, 0.62, 0.03)), ((x, 0.08, 0.72), (0.03, 0.14, 0.03)), ((x, 0.03, 0.0), (0.04, 0.03, 1.62))], "OD_Galv", 0.003))
        o.append(box("b", [((x, 0.05, -0.74), (0.22, 0.08, 0.16)), ((x, 0.05, 0.76), (0.22, 0.08, 0.16))], "OD_Concrete", 0.012))
    join("Body", o)
    export("solar_panel")


@model
def sat_dish():
    o = [box("b", [((-0.35, 0.06, 0), (0.30, 0.12, 0.60)), ((0.35, 0.06, 0), (0.30, 0.12, 0.60)), ((0, 0.10, 0), (0.80, 0.05, 0.10))], "OD_Concrete", 0.02)]
    o.append(cyl((0, 0.62, 0), 0.038, 1.14, "OD_Galv", "y", 18))
    join("Base", o)
    # Schuessel um den Mastkopf (0, 1.15, 0) drehbar, blickt nach +z / oben
    pr = []
    for i in range(15):
        r = 0.60 * i / 14.0
        pr.append((r, 0.30 * (r / 0.60) ** 2))
    bm = bmesh.new()
    rows = []
    seg = 40
    for r, h in pr:
        rows.append([bm.verts.new((0, 0, 0))] if False else [bm.verts.new(g(math.cos(2 * math.pi * k / seg) * max(r, 0.001), math.sin(2 * math.pi * k / seg) * max(r, 0.001), h)) for k in range(seg)])
    for a, b in zip(rows, rows[1:]):
        for k in range(seg):
            bm.faces.new((a[k], a[(k + 1) % seg], b[(k + 1) % seg], b[k]))
    me = bpy.data.meshes.new("dish")
    bm.to_mesh(me)
    bm.free()
    dish = bpy.data.objects.new("dish", me)
    bpy.context.scene.collection.objects.link(dish)
    for p in me.polygons:
        p.use_smooth = True
    set_mats(dish, ["OD_White"])
    H.solidify(dish, 0.012)
    rim = tube("rim", [(math.cos(2 * math.pi * k / 40) * 0.60, math.sin(2 * math.pi * k / 40) * 0.60, 0.30) for k in range(41)], 0.011, "OD_Grey", 8)
    arm = [dish, rim, tube("a", [(0, -0.58, 0.27), (0, -0.30, 0.62), (0, -0.06, 0.74)], 0.014, "OD_Galv", 8), tube("a2", [(-0.50, 0.28, 0.25), (-0.05, -0.02, 0.74)], 0.008, "OD_Galv", 6), tube("a3", [(0.50, 0.28, 0.25), (0.05, -0.02, 0.74)], 0.008, "OD_Galv", 6)]
    arm.append(cyl((0, -0.03, 0.74), 0.035, 0.10, "OD_Grey", "z", 16, 0.05))
    arm.append(box("lnb", [((0, -0.03, 0.82), (0.07, 0.09, 0.08))], "OD_Grey", 0.01))
    arm.append(box("bk", [((0, 0, -0.06), (0.16, 0.20, 0.10))], "OD_Galv", 0.012))
    ob = join("Arm", arm)
    ob.location = V(g(0, 1.16, 0))
    export("sat_dish")


@model
def weather_station():
    o = [box("b", [((0, 0.04, 0), (0.44, 0.08, 0.44))], "OD_Concrete", 0.02), cyl((0, 1.05, 0), 0.026, 2.0, "OD_Galv", "y", 14), box("ar", [((0, 1.80, 0), (0.80, 0.03, 0.03))], "OD_Galv", 0.004)]
    for k in range(6):
        o.append(cyl((0, 1.18 + k * 0.035, 0.14), 0.075 - (0.012 if k == 5 else 0), 0.012, "OD_White", "y", 24))
    o.append(cyl((0, 1.28, 0.14), 0.045, 0.22, "OD_White", "y", 18))
    o.append(box("bx", [((0, 0.75, 0.07), (0.20, 0.28, 0.10))], "OD_White", 0.012))
    o.append(box("bl", [((0.06, 0.66, 0.122), (0.02, 0.012, 0.006))], "OD_LedGreen", 0.0))
    o.append(cyl((0.38, 1.83, 0), 0.012, 0.07, "OD_Black", "y", 10))
    o.append(cyl((-0.38, 1.83, 0), 0.012, 0.07, "OD_Black", "y", 10))
    o.append(cyl((-0.12, 1.50, 0.0), 0.05, 0.16, "OD_Grey", "y", 20, 0.065))
    join("Mast", o)
    c = []
    for k in range(3):
        a = k * 2.0944
        x, z = math.cos(a), math.sin(a)
        c.append(tube("a", [(0, 0, 0), (x * 0.11, 0, z * 0.11)], 0.005, "OD_Black", 6))
        b = Blob(); b.sph((x * 0.12, 0, z * 0.12), 0.028, 12)
        c.append(blob(b, "OD_Black", 0.005, 160))
    ob = join("Cups", c)
    ob.location = V(g(0.38, 1.88, 0))
    v = [tube("a", [(0, 0, -0.14), (0, 0, 0.12)], 0.006, "OD_Black", 6), box("f", [((0, 0.02, 0.15), (0.006, 0.09, 0.10))], "OD_Red", 0.0), cyl((0, 0, -0.15), 0.001, 0.05, "OD_Red", "z", 10, 0.016)]
    ob = join("Vane", v)
    ob.location = V(g(-0.38, 1.88, 0))
    export("weather_station")


@model
def garden_bench():
    """Sitzflaeche 0.45 hoch, 1.6 breit, Lehne hinten (-z), man blickt nach +z."""
    o = []
    for k in range(5):
        o.append(box("s", [((0, 0.44, -0.16 + k * 0.095), (1.60, 0.028, 0.080))], "OD_Wood", 0.006))
    for k in range(4):
        o.append(box("l", [((0, 0.56 + k * 0.095, -0.235 - k * 0.018), (1.60, 0.078, 0.026), (-11, 0, 0))], "OD_Wood", 0.006))
    for x in (-0.68, 0.68):
        o.append(tube("f", [(x, 0.0, 0.26), (x, 0.42, 0.24), (x, 0.42, -0.20), (x, 0.0, -0.30)], 0.020, "OD_Black", 10))
        o.append(tube("r", [(x, 0.42, -0.20), (x, 0.90, -0.31)], 0.019, "OD_Black", 10))
        o.append(tube("a", [(x, 0.42, 0.22), (x, 0.64, 0.24), (x, 0.66, 0.14), (x, 0.65, -0.24)], 0.017, "OD_Black", 10))
        o.append(box("p", [((x, 0.01, 0.26), (0.08, 0.02, 0.08)), ((x, 0.01, -0.30), (0.08, 0.02, 0.08))], "OD_Black", 0.003))
    join("Body", o)
    export("garden_bench")


@model
def garden_table():
    o = [box("t", [((0, 0.735, -0.36 + k * 0.145), (1.50, 0.032, 0.132)) for k in range(6)], "OD_Wood", 0.006)]
    o.append(box("u", [((-0.55, 0.69, 0), (0.07, 0.06, 0.82)), ((0.55, 0.69, 0), (0.07, 0.06, 0.82)), ((0, 0.40, 0), (1.10, 0.07, 0.05))], "OD_WoodDark", 0.006))
    for x in (-0.55, 0.55):
        o.append(box("l", [((x, 0.34, -0.27), (0.07, 0.74, 0.07), (-18, 0, 0)), ((x, 0.34, 0.27), (0.07, 0.74, 0.07), (18, 0, 0))], "OD_WoodDark", 0.006))
    # gedeckt: Kanne, Becher, Teller
    o.append(cyl((0.12, 0.83, 0.02), 0.055, 0.16, "OD_Chrome", "y", 24, 0.045, 0.006))
    for x, z in ((-0.35, 0.16), (0.40, -0.16)):
        o.append(cyl((x, 0.795, z), 0.034, 0.085, "OD_Terra", "y", 20, 0.040, 0.004))
    for x, z in ((-0.42, -0.10), (0.30, 0.18)):
        o.append(cyl((x, 0.757, z), 0.075, 0.012, "OD_White", "y", 28, 0.105, 0.003))
    join("Body", o)
    export("garden_table")


@model
def grill():
    """Kugelgrill. Lid am Scharnier hinten, Food wird nur beim Grillen gezeigt."""
    o = []
    b = Blob(); b.ell((0, 0.80, 0), (0.30, 0.24, 0.30))
    bowl = b.mesh("b", 0.012, 2, 0.4, 2400)
    H.bis(bowl, H.ypl(0.80))
    H.cut(bowl, lambda x, y, z: y < 0.80)
    set_mats(bowl, ["OD_Black"])
    H.solidify(bowl, 0.010)
    o.append(bowl)
    o.append(tube("r", [(math.cos(2 * math.pi * k / 36) * 0.302, 0.80, math.sin(2 * math.pi * k / 36) * 0.302) for k in range(37)], 0.009, "OD_Chrome", 8))
    for a in (90, 215, 325):
        x, z = math.cos(math.radians(a)), math.sin(math.radians(a))
        o.append(tube("l", [(x * 0.18, 0.62, z * 0.18), (x * 0.32, 0.06, z * 0.32)], 0.014, "OD_Galv", 10))
    for x in (-0.262, 0.262):
        o.append(cyl((x, 0.075, -0.185), 0.075, 0.03, "OD_Black", "x", 24, None, 0.006))
    o.append(box("sh", [((0.0, 0.30, 0.0), (0.46, 0.014, 0.36))], "OD_Galv", 0.004))
    o.append(tube("h", [(-0.10, 0.74, 0.30), (-0.10, 0.74, 0.36), (0.10, 0.74, 0.36), (0.10, 0.74, 0.30)], 0.013, "OD_Wood", 8))
    for k in range(17):
        x = -0.27 + k * 0.03375
        zl = math.sqrt(max(0.0, 0.285 ** 2 - x * x))
        o.append(tube("g", [(x, 0.792, -zl), (x, 0.792, zl)], 0.0032, "OD_Chrome", 6))
    rng = random.Random(3)
    co = []
    for k in range(46):
        a, r = rng.uniform(0, 6.28), 0.21 * math.sqrt(rng.random())
        bb = Blob(); bb.ell((math.cos(a) * r, 0.685 + rng.uniform(0, 0.03), math.sin(a) * r), (rng.uniform(0.020, 0.032), 0.018, rng.uniform(0.018, 0.028)), (rng.uniform(-30, 30), rng.uniform(0, 90), 0), 8)
        me = bpy.data.meshes.new("c"); me.from_pydata(bb.vs, [], bb.fs); ob = bpy.data.objects.new("c", me); bpy.context.scene.collection.objects.link(ob); set_mats(ob, ["OD_Coal"]); co.append(ob)
    o += co
    o.append(cyl((0, 0.672, 0), 0.20, 0.01, "OD_Ember", "y", 28))
    join("Body", o)
    b = Blob(); b.ell((0, 0.80, 0), (0.305, 0.22, 0.305))
    lid = b.mesh("l", 0.012, 2, 0.4, 2400)
    H.bis(lid, H.ypl(0.806))
    H.cut(lid, lambda x, y, z: y > 0.806)
    set_mats(lid, ["OD_Red"])
    H.solidify(lid, 0.010)
    ld = [lid, tube("h", [(-0.07, 1.00, 0.02), (-0.07, 1.06, 0.03), (0.07, 1.06, 0.03), (0.07, 1.00, 0.02)], 0.013, "OD_Wood", 8), cyl((0.14, 0.965, 0.10), 0.035, 0.02, "OD_Galv", "y", 18)]
    at(join("Lid", ld), 0, 0.81, -0.30)
    fo = []
    for x, z, a in ((-0.12, 0.10, 20), (-0.14, 0.02, 5), (-0.12, -0.07, -12)):
        bb = Blob(); bb.cap((x - 0.07, 0.815, z), 0.017, (x + 0.07, 0.815, z + a * 0.001), 0.017); fo.append(blob(bb, "OD_Sausage", 0.005, 260))
    for x, z in ((0.10, 0.10), (0.13, -0.06)):
        bb = Blob(); bb.ell((x, 0.808, z), (0.075, 0.016, 0.052), (0, 25, 0)); fo.append(blob(bb, "OD_Meat", 0.006, 240))
    for x, z in ((0.0, -0.14), (0.02, 0.18)):
        fo.append(cyl((x, 0.806, z), 0.035, 0.018, "OD_Tomato", "y", 20, None, 0.004))
    join("Food", fo)
    export("grill")


@model
def raised_bed():
    """Hochbeet 1.60 x 0.80 x 0.48."""
    o = []
    for k in range(3):
        y = 0.08 + k * 0.155
        o.append(box("b", [((0, y, 0.385), (1.60, 0.145, 0.030)), ((0, y, -0.385), (1.60, 0.145, 0.030)), ((-0.785, y, 0), (0.030, 0.145, 0.74)), ((0.785, y, 0), (0.030, 0.145, 0.74))], "OD_Wood", 0.006))
    for x in (-0.76, 0.76):
        for z in (-0.36, 0.36):
            o.append(box("p", [((x, 0.245, z), (0.06, 0.49, 0.06))], "OD_WoodDark", 0.006))
    bm = bmesh.new()
    nx, nz = 24, 12
    vs = [[bm.verts.new(g(-0.77 + 1.54 * i / nx, 0.425 + 0.022 * noise.noise(V((i * 0.6, j * 0.6, 0.0))) + 0.012 * math.sin(j * 2.1), -0.37 + 0.74 * j / nz)) for j in range(nz + 1)] for i in range(nx + 1)]
    for i in range(nx):
        for j in range(nz):
            bm.faces.new((vs[i][j], vs[i][j + 1], vs[i + 1][j + 1], vs[i + 1][j]))
    me = bpy.data.meshes.new("soil"); bm.to_mesh(me); bm.free()
    so = bpy.data.objects.new("soil", me); bpy.context.scene.collection.objects.link(so)
    for p in me.polygons:
        p.use_smooth = True
    set_mats(so, ["OD_Soil"])
    o.append(so)
    join("Body", o)
    export("raised_bed")


def leaf_poly(bm, o, d, up, ln, w, curl=0.2):
    """Gewoelbtes Blatt aus 6 Vierecken."""
    d = d.normalized()
    s = d.cross(up).normalized()
    n = s.cross(d).normalized()
    rows = []
    for i in range(5):
        t = i / 4.0
        c = o + d * ln * t + n * (-curl * ln * t * t + 0.06 * ln * math.sin(t * 3.1))
        ww = w * math.sin(math.pi * (0.08 + 0.90 * t)) ** 0.8
        rows.append([bm.verts.new(g(*(c - s * ww + n * ww * 0.3))), bm.verts.new(g(*c)), bm.verts.new(g(*(c + s * ww + n * ww * 0.3)))])
    for a, b in zip(rows, rows[1:]):
        for k in range(2):
            bm.faces.new((a[k], a[k + 1], b[k + 1], b[k]))


def leaves_ob(bm, m):
    me = bpy.data.meshes.new("lv"); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("lv", me); bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    set_mats(ob, [m])
    return ob


@model
def plant_tomato():
    rng = random.Random(5)
    o = [tube("st", [(0, 0, 0), (0.01, 0.3, 0.0), (-0.005, 0.62, 0.01)], 0.008, "OD_Leaf", 7), tube("k", [(0.03, 0, 0.0), (0.03, 0.72, 0.0)], 0.006, "OD_WoodDark", 6)]
    bm = bmesh.new()
    for i in range(22):
        a, y = i * 2.4, 0.06 + 0.56 * i / 22.0
        d = V((math.cos(a), 0.25, math.sin(a)))
        leaf_poly(bm, V((math.cos(a) * 0.01, y, math.sin(a) * 0.01)), d, V((0, 1, 0)), rng.uniform(0.11, 0.17), 0.045, 0.6)
    o.append(leaves_ob(bm, "OD_Leaf"))
    join("Green", o)
    f = []
    for i in range(7):
        a, y = i * 1.9, 0.18 + 0.06 * i
        b = Blob(); b.sph((math.cos(a) * 0.065, y, math.sin(a) * 0.065), rng.uniform(0.024, 0.034), 12); f.append(blob(b, "OD_Tomato", 0.006, 140))
    join("Fruit", f)
    export("plant_tomato")


@model
def plant_lettuce():
    bm = bmesh.new()
    rng = random.Random(6)
    for i in range(30):
        a = i * 2.4
        t = i / 30.0
        d = V((math.cos(a) * (1 - t * 0.8), 0.35 + t * 1.4, math.sin(a) * (1 - t * 0.8)))
        leaf_poly(bm, V((math.cos(a) * 0.015, 0.005, math.sin(a) * 0.015)), d, V((0, 1, 0)), 0.15 - 0.05 * t, 0.075 - 0.02 * t, -0.35)
    o = leaves_ob(bm, "OD_LeafLight")
    move(o, lambda x, y, z, n: (x + 0.006 * math.sin(x * 160 + y * 120), y + 0.006 * math.sin(z * 170), z + 0.006 * math.sin(z * 150 + y * 130)))
    join("Green", [o])
    export("plant_lettuce")


@model
def plant_berry():
    rng = random.Random(8)
    bm = bmesh.new()
    for i in range(20):
        a = i * 2.4
        st = V((math.cos(a) * 0.05, rng.uniform(0.08, 0.15), math.sin(a) * 0.05))
        for k in (-0.7, 0.0, 0.7):
            leaf_poly(bm, st, V((math.cos(a + k), 0.25, math.sin(a + k))), V((0, 1, 0)), 0.085, 0.034, 0.5)
    o = [leaves_ob(bm, "OD_Leaf")]
    join("Green", o)
    f = []
    for i in range(8):
        a = i * 0.8
        b = Blob(); b.cap((math.cos(a) * 0.13, 0.055, math.sin(a) * 0.13), 0.018, (math.cos(a) * 0.14, 0.028, math.sin(a) * 0.14), 0.008); f.append(blob(b, "OD_Berry", 0.005, 120))
    join("Fruit", f)
    export("plant_berry")


@model
def bird_feeder():
    o = [cyl((0, 0.65, 0), 0.030, 1.30, "OD_WoodDark", "y", 12)]
    o.append(box("t", [((0, 1.30, 0), (0.42, 0.018, 0.34)), ((0, 1.325, 0.165), (0.42, 0.04, 0.012)), ((0, 1.325, -0.165), (0.42, 0.04, 0.012)), ((0.205, 1.325, 0), (0.012, 0.04, 0.34)), ((-0.205, 1.325, 0), (0.012, 0.04, 0.34))], "OD_Wood", 0.004))
    o.append(box("p", [((x, 1.44, z), (0.022, 0.26, 0.022)) for x in (-0.17, 0.17) for z in (-0.13, 0.13)], "OD_Wood", 0.003))
    o.append(box("r", [((0, 1.625, 0.105), (0.50, 0.016, 0.28), (28, 0, 0)), ((0, 1.625, -0.105), (0.50, 0.016, 0.28), (-28, 0, 0))], "OD_Red", 0.004))
    for a in (30, 150, 270):
        o.append(box("f", [((math.cos(math.radians(a)) * 0.14, 0.10, math.sin(math.radians(a)) * 0.14), (0.04, 0.34, 0.04), (math.sin(math.radians(a)) * -38, 0, math.cos(math.radians(a)) * 38))], "OD_WoodDark", 0.004))
    join("Body", o)
    rng = random.Random(2)
    b = Blob(); b.ell((0, 1.314, 0), (0.15, 0.022, 0.12))
    sd = blob(b, "OD_Seed", 0.008, 500)
    move(sd, lambda x, y, z, n: (x, y + 0.006 * noise.noise(V((x * 60, 0, z * 60))), z))
    join("Seed", [sd])
    export("bird_feeder")


@model
def bird_bath():
    o = [cyl((0, 0.03, 0), 0.20, 0.06, "OD_Concrete", "y", 28, 0.18, 0.01), cyl((0, 0.36, 0), 0.10, 0.62, "OD_Concrete", "y", 24, 0.065)]
    ob = H.lathe("b", [(0.0, 0.66), (0.10, 0.665), (0.26, 0.72), (0.33, 0.765), (0.335, 0.785), (0.315, 0.785), (0.25, 0.742), (0.10, 0.700), (0.002, 0.695)], 1.0, 1.0, 0.0, 36)
    set_mats(ob, ["OD_Concrete"])
    o.append(ob)
    join("Body", o)
    w = cyl((0, 0.752, 0), 0.275, 0.002, "OD_Water", "y", 36)
    join("Water", [w])
    export("bird_bath")


@model
def bollard_lamp():
    o = [cyl((0, 0.42, 0), 0.055, 0.84, "OD_Steel", "y", 20), cyl((0, 0.01, 0), 0.10, 0.02, "OD_Galv", "y", 24), cyl((0, 0.98, 0), 0.085, 0.03, "OD_Steel", "y", 24, None, 0.006)]
    for k in range(3):
        o.append(cyl((0, 0.875 + k * 0.032, 0), 0.075, 0.006, "OD_Steel", "y", 24))
    join("Body", o)
    join("Glow", [cyl((0, 0.90, 0), 0.045, 0.13, "OD_Lamp", "y", 20)])
    export("bollard_lamp")


@model
def wall_lamp():
    """Strahler, Wand bei z 0, leuchtet nach vorn unten."""
    o = [box("p", [((0, 0, 0.012), (0.10, 0.14, 0.024))], "OD_Steel", 0.006), tube("a", [(0, 0, 0.02), (0, 0.02, 0.10)], 0.016, "OD_Steel", 10), box("h", [((0, 0.02, 0.16), (0.30, 0.20, 0.06), (28, 0, 0))], "OD_Steel", 0.014)]
    join("Body", o)
    join("Glow", [box("g", [((0, 0.008, 0.192), (0.26, 0.16, 0.006), (28, 0, 0))], "OD_Lamp", 0.002)])
    export("wall_lamp")


@model
def snow_cap():
    """Schneehaube 1 x 1 m, Dicke 0.12."""
    bm = bmesh.new()
    n = 20
    vs = []
    for i in range(n + 1):
        row = []
        for j in range(n + 1):
            x, z = -0.5 + i / n, -0.5 + j / n
            e = min(0.5 - abs(x), 0.5 - abs(z)) * 2
            y = 0.12 * smoothstep(0.0, 0.35, e) * (0.85 + 0.22 * noise.noise(V((x * 5, z * 5, 2.0)))) - 0.015 * (1 - smoothstep(0, 0.1, e))
            row.append(bm.verts.new(g(x, y, z)))
        vs.append(row)
    for i in range(n):
        for j in range(n):
            bm.faces.new((vs[i][j], vs[i][j + 1], vs[i + 1][j + 1], vs[i + 1][j]))
    me = bpy.data.meshes.new("Body"); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new("Body", me); bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    set_mats(ob, ["OD_Snow"])
    export("snow_cap")


@model
def leaf_pile():
    """Laubhaufen 1 x 1 m."""
    rng = random.Random(12)
    for part, m, cnt in (("A", "OD_LeafFall", 130), ("B", "OD_Seed", 70), ("C", "OD_Meat", 60)):
        bm = bmesh.new()
        for i in range(cnt):
            a, r = rng.uniform(0, 6.28), 0.46 * math.sqrt(rng.random())
            y = 0.10 * (1 - (r / 0.5) ** 2) * rng.random() + 0.008
            d = V((math.cos(rng.uniform(0, 6.28)), rng.uniform(-0.3, 0.3), math.sin(rng.uniform(0, 6.28))))
            leaf_poly(bm, V((math.cos(a) * r, y, math.sin(a) * r)), d, V((rng.uniform(-0.5, 0.5), 1, rng.uniform(-0.5, 0.5))), rng.uniform(0.07, 0.11), 0.032, rng.uniform(-0.4, 0.4))
        leaves_ob(bm, m).name = part
    export("leaf_pile")


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for n, fn in ALL.items():
        if args and n not in args:
            continue
        reset()
        fn()


if __name__ == "__main__":
    main()
