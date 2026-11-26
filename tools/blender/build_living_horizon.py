"""Blender 5.2 Generator fuer die logische Hintergrund-Infrastruktur & lebendige Horizont-Modelle:
  - assets/models/ext_wind_turbine.glb   (Deutsches Windrad mit separatem drehendem 'Rotor' + Warnleuchte)
  - assets/models/ext_power_pylon.glb    (Deutscher Hochspannungs-Gittermast mit Isolatoren)
  - assets/models/ext_tower_crane.glb    (Gelber Baukran mit separatem schwenkendem 'Jib'-Ausleger)
  - assets/models/ext_chp_plant.glb      (Heizkraftwerk / Industrie-Kesselhaus mit 2 Schornsteinen fuer Dampf)
  - assets/models/ext_forklift.glb       (Gelber Gabelstapler mit Palette & Warnleuchte fuer Logistikhof)
  - assets/models/ext_flagpole.glb       (Firmen-Fahnenmast mit separater 'Flag'-Flaeche fuer Wind-Shader)
  - assets/models/ext_dock_trailer.glb   (Abgesattelter 40t-Auflieger mit Stuetzbeinen fuer Laderampe)

Godot-Koordinaten: g(x, y, z) -> Blender (x, -z, y), Boden = Y 0.0.
"""

import math
import os
import sys
import traceback

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import dct_paths
from build_delivery_van import PartBuilder, g, make_solid_mat, make_tex_mat
from build_exterior_vehicles import _build_wheel, _gen_truck_curtain_tex, _shared_vehicle_mats
from build_exterior_world import (
    _export_glb,
    _reset_scene,
    ensure_exterior_textures,
    make_pbr_tex_mat,
)

OUT_MODELS_DIR = dct_paths.MODELS_DIR


# ---------------------------------------------------------------------------
# 1. Deutsches Windrad (Turm 34 m + separater drehbarer 'Rotor' bei Y = 34.0)
# ---------------------------------------------------------------------------

def build_wind_turbine():
    _reset_scene()
    root = bpy.data.objects.new("WindTurbineRoot", None)
    bpy.context.scene.collection.objects.link(root)

    white = make_solid_mat("WT_White", (0.90, 0.91, 0.92), rough=0.38, metal=0.12)
    red = make_solid_mat("WT_Red", (0.82, 0.14, 0.12), rough=0.40, metal=0.08)
    grey = make_solid_mat("WT_Grey", (0.34, 0.37, 0.40), rough=0.65, metal=0.35)
    beacon = make_solid_mat("WT_BeaconMat", (1.0, 0.14, 0.10), rough=0.15, metal=0.0,
                            emission=(1.0, 0.12, 0.08), em_strength=4.5)

    # Turm + Gondel
    pb = PartBuilder("Tower", origin_g=Vector((0, 0, 0)))
    pb.cyl((0.0, 0.45, 0.0), 2.2, 2.5, 0.90, grey, axis_g="y", seg=16) # Beton-Fundament
    pb.cyl((0.0, 17.2, 0.0), 0.72, 1.55, 33.4, white, axis_g="y", seg=16) # Verjuengter Rohrturm
    # Roter Flugsicherungs-Ring am Turm
    pb.cyl((0.0, 22.0, 0.0), 1.05, 1.12, 2.2, red, axis_g="y", seg=16)
    # Maschinenhaus (Gondel) bei Y = 34.0
    pb.box((0.0, 34.15, -0.35), (2.25, 2.15, 5.40), white, bevel=0.22)
    pb.box((0.0, 35.38, -1.65), (0.55, 0.40, 0.55), grey, bevel=0.04)
    pb.cyl((0.0, 35.75, -1.65), 0.22, 0.22, 0.36, beacon, axis_g="y", seg=10) # Rotes Blinklicht!
    pb.build(root)

    # Separater Rotor-Knoten bei (0, 34.15, +2.65) -> rotiert in Godot um Z!
    hub_pos = Vector((0.0, 34.15, 2.65))
    pb_r = PartBuilder("Rotor", origin_g=hub_pos)
    pb_r.cyl(hub_pos + Vector((0, 0, 0.35)), 0.18, 0.88, 1.75, white, axis_g="z", seg=14) # Spinner-Nase
    # 3 aerodynamische Rotorblaetter (14.5 m Radius, rot-weisse Fluegelspitzen!)
    for bi in range(3):
        ang = (bi / 3.0) * math.tau
        dx, dy = math.cos(ang), math.sin(ang)
        deg = math.degrees(ang)
        # Innenblatt + Mittelblatt + rote Spitze
        p1 = hub_pos + Vector((dx * 3.8, dy * 3.8, 0.15))
        p2 = hub_pos + Vector((dx * 9.2, dy * 9.2, 0.15))
        p3 = hub_pos + Vector((dx * 13.0, dy * 13.0, 0.15))
        pb_r.box(p1, (6.4, 0.92, 0.24), white, rot_g_deg=(10.0, 0.0, deg), bevel=0.04)
        pb_r.box(p2, (5.2, 0.62, 0.18), white, rot_g_deg=(6.0, 0.0, deg), bevel=0.03)
        pb_r.box(p3, (2.8, 0.34, 0.12), red,   rot_g_deg=(4.0, 0.0, deg), bevel=0.02)
    pb_r.build(root)

    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_wind_turbine.glb"))


# ---------------------------------------------------------------------------
# 2. Deutscher Hochspannungs-Gittermast (Hochspannungsmast 22 m, 2 Traversen)
# ---------------------------------------------------------------------------

def _add_strut(pb: PartBuilder, a: Vector, b: Vector, radius: float, mat):
    d = b - a
    ln = d.length
    if ln < 1e-4:
        return
    mid_g = (a + b) * 0.5
    # Zylinder entlang beliebiger Richtung direkt ueber bmesh
    mid_i = pb._mid(mat)
    ret = bmesh.ops.create_cone(pb.bm, cap_ends=True, segments=6, radius1=radius, radius2=radius, depth=ln)
    verts = ret["verts"]
    ab = pb._local_b(a)
    bb = pb._local_b(b)
    dir_b = (bb - ab).normalized()
    q = Vector((0, 0, 1)).rotation_difference(dir_b)
    mat4 = Matrix.Translation((ab + bb) * 0.5) @ q.to_matrix().to_4x4()
    bmesh.ops.transform(pb.bm, matrix=mat4, verts=verts)
    for f in {f for v in verts for f in v.link_faces}:
        f.material_index = mid_i
        f.smooth = False


def build_power_pylon():
    _reset_scene()
    root = bpy.data.objects.new("PowerPylonRoot", None)
    bpy.context.scene.collection.objects.link(root)

    galv = make_solid_mat("Pylon_Galv", (0.48, 0.52, 0.54), rough=0.48, metal=0.76)
    concrete = make_solid_mat("Pylon_Foot", (0.50, 0.51, 0.52), rough=0.88, metal=0.0)
    insul = make_solid_mat("Pylon_Insulator", (0.34, 0.46, 0.44), rough=0.22, metal=0.10, coat=0.7)

    pb = PartBuilder("PowerPylon", origin_g=Vector((0, 0, 0)))

    # 4 Eckstiele von Basis (2.4 m breit) bis Spitze (0.55 m breit, 21.5 m hoch)
    levels = [
        (0.0, 2.20), (4.0, 1.72), (8.0, 1.32), (12.0, 0.98), (15.5, 0.72), (18.8, 0.52), (21.5, 0.14),
    ]
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            pb.box((sx * 2.20, 0.35, sz * 2.20), (0.75, 0.70, 0.75), concrete, bevel=0.03)
    for k in range(len(levels) - 1):
        y0, w0 = levels[k]
        y1, w1 = levels[k + 1]
        c0 = [Vector((-w0, y0, -w0)), Vector((w0, y0, -w0)), Vector((w0, y0, w0)), Vector((-w0, y0, w0))]
        c1 = [Vector((-w1, y1, -w1)), Vector((w1, y1, -w1)), Vector((w1, y1, w1)), Vector((-w1, y1, w1))]
        for i in range(4):
            j = (i + 1) % 4
            _add_strut(pb, c0[i], c1[i], 0.085, galv)  # Eckstiel
            _add_strut(pb, c1[i], c1[j], 0.055, galv)  # Querverstrebung
            _add_strut(pb, c0[i], c1[j], 0.042, galv)  # Kreuz-Diagonale 1
            _add_strut(pb, c0[j], c1[i], 0.042, galv)  # Kreuz-Diagonale 2

    # 2 breite Hochspannungs-Traversen (Y = 14.5 m & Y = 18.2 m, entlang X!) + haengende Isolator-Ketten!
    for ty, span in ((14.5, 5.8), (18.2, 4.4)):
        pb.box((0.0, ty, 0.0), (span * 2.0, 0.24, 0.55), galv, bevel=0.01)
        for side in (-1.0, 1.0):
            _add_strut(pb, Vector((side * 0.75, ty + 1.15, 0.0)), Vector((side * span, ty, 0.0)), 0.065, galv)
            _add_strut(pb, Vector((side * 0.75, ty - 0.85, 0.0)), Vector((side * (span * 0.72), ty, 0.0)), 0.055, galv)
            # Haengender Isolator an jeder Traversen-Spitze
            pb.cyl((side * (span - 0.25), ty - 0.75, 0.0), 0.14, 0.14, 1.25, insul, axis_g="y", seg=10)

    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_power_pylon.glb"))


# ---------------------------------------------------------------------------
# 3. Gelber deutscher Baukran (Turm 26 m + schwenkbarer Ausleger 'Jib' bei Y = 25.0)
# ---------------------------------------------------------------------------

def build_tower_crane():
    _reset_scene()
    root = bpy.data.objects.new("TowerCraneRoot", None)
    bpy.context.scene.collection.objects.link(root)

    yellow = make_solid_mat("Crane_Yellow", (0.92, 0.68, 0.08), rough=0.40, metal=0.28)
    dark = make_solid_mat("Crane_Dark", (0.16, 0.18, 0.20), rough=0.55, metal=0.65)
    concrete = make_solid_mat("Crane_Concrete", (0.56, 0.57, 0.58), rough=0.88, metal=0.0)
    glass = make_solid_mat("Crane_Glass", (0.10, 0.18, 0.24), rough=0.08, metal=0.20, coat=0.9)
    beacon = make_solid_mat("Crane_BeaconMat", (1.0, 0.14, 0.10), rough=0.15, metal=0.0,
                            emission=(1.0, 0.12, 0.08), em_strength=4.5)

    # Vertikaler Gittermast + Beton-Kreuzfundament
    pb = PartBuilder("Mast", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.45, 0.0), (4.6, 0.90, 4.6), concrete, bevel=0.04)
    w = 0.85
    for seg_i in range(10):
        y0 = 0.9 + seg_i * 2.4
        y1 = y0 + 2.4
        c0 = [Vector((-w, y0, -w)), Vector((w, y0, -w)), Vector((w, y0, w)), Vector((-w, y0, w))]
        c1 = [Vector((-w, y1, -w)), Vector((w, y1, -w)), Vector((w, y1, w)), Vector((-w, y1, w))]
        for i in range(4):
            j = (i + 1) % 4
            _add_strut(pb, c0[i], c1[i], 0.08, yellow)
            _add_strut(pb, c1[i], c1[j], 0.055, yellow)
            _add_strut(pb, c0[i], c1[j], 0.042, yellow)
    pb.build(root)

    # Drehbarer Oberwagen + Ausleger ('Jib' bei Y = 25.0 -> dreht um Y!)
    piv = Vector((0.0, 25.0, 0.0))
    pb_j = PartBuilder("Jib", origin_g=piv)
    pb_j.cyl(piv, 0.95, 0.95, 0.70, dark, axis_g="y", seg=14) # Drehkranz
    # Fuehrerhaus seitlich
    pb_j.box(piv + Vector((0.8, 0.9, 1.55)), (1.9, 2.2, 1.35), yellow, bevel=0.04)
    pb_j.box(piv + Vector((1.72, 1.0, 1.55)), (0.08, 1.55, 1.10), glass, bevel=0.01)
    # Turmspitze (Katzenkopf) + rotes Warnlicht ganz oben
    pb_j.box(piv + Vector((0.0, 3.2, 0.0)), (1.2, 5.4, 1.2), yellow, bevel=0.03)
    pb_j.cyl(piv + Vector((0.0, 6.15, 0.0)), 0.22, 0.22, 0.40, beacon, axis_g="y", seg=10)
    # Langer Ausleger (+X: 0..24 m) + Gegenausleger (-X: -9..0 m)
    for k in range(11):
        x0 = -8.5 + k * 3.0
        x1 = x0 + 3.0
        for sz in (-0.65, 0.65):
            _add_strut(pb_j, piv + Vector((x0, 0.6, sz)), piv + Vector((x1, 0.6, sz)), 0.065, yellow)
            _add_strut(pb_j, piv + Vector((x0, 0.6, sz)), piv + Vector((x1, 1.85, 0.0)), 0.045, yellow)
            _add_strut(pb_j, piv + Vector((x1, 0.6, sz)), piv + Vector((x0, 1.85, 0.0)), 0.045, yellow)
        _add_strut(pb_j, piv + Vector((x0, 1.85, 0.0)), piv + Vector((x1, 1.85, 0.0)), 0.075, yellow)
    # Abspannseile zur Turmspitze
    _add_strut(pb_j, piv + Vector((0.0, 5.7, 0.0)), piv + Vector((18.5, 1.85, 0.0)), 0.04, dark)
    _add_strut(pb_j, piv + Vector((0.0, 5.7, 0.0)), piv + Vector((-8.2, 1.85, 0.0)), 0.04, dark)
    # Beton-Gegengewichte hinten (-X) + Laufkatze & Haken vorne (+X)
    pb_j.box(piv + Vector((-7.6, 1.15, 0.0)), (2.4, 1.8, 1.55), concrete, bevel=0.04)
    pb_j.box(piv + Vector((14.0, 0.35, 0.0)), (1.4, 0.45, 1.15), dark, bevel=0.02)
    pb_j.cyl(piv + Vector((14.0, -5.2, 0.0)), 0.03, 0.03, 11.0, dark, axis_g="y", seg=6)
    pb_j.box(piv + Vector((14.0, -10.8, 0.0)), (0.55, 0.65, 0.38), yellow, bevel=0.02)
    pb_j.build(root)

    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_tower_crane.glb"))


# ---------------------------------------------------------------------------
# 4. Deutsches Heizkraftwerk / Industrie-Werk mit 2 Schornsteinen (fuer Dampfwolken!)
# ---------------------------------------------------------------------------

def build_chp_plant(tex: dict):
    _reset_scene()
    root = bpy.data.objects.new("ChpPlantRoot", None)
    bpy.context.scene.collection.objects.link(root)

    clinker = make_pbr_tex_mat("CHP_Clinker", *tex["clinker"], rough=0.84, metal=0.0, normal_strength=1.0)
    concrete = make_pbr_tex_mat("CHP_Concrete", *tex["concrete"], rough=0.86, metal=0.0, normal_strength=0.9)
    trapez = make_pbr_tex_mat("CHP_Trapez", *tex["trapez"], rough=0.52, metal=0.38, normal_strength=1.0)
    steel_dark = make_solid_mat("CHP_Dark", (0.16, 0.19, 0.22), rough=0.45, metal=0.68)
    red = make_solid_mat("CHP_Red", (0.80, 0.16, 0.14), rough=0.45, metal=0.08)
    white = make_solid_mat("CHP_White", (0.90, 0.91, 0.92), rough=0.45, metal=0.08)
    glass = make_solid_mat("CHP_Glass", (0.12, 0.18, 0.24), rough=0.08, metal=0.20, coat=0.9)

    pb = PartBuilder("ChpPlant", origin_g=Vector((0, 0, 0)))
    # Haupt-Kesselhaus (18 m x 10.5 m x 12 m) + niedrigere Turbinenhalle + 2 Silos
    pb.box((-2.0, 5.25, 0.0), (16.0, 10.5, 11.5), clinker, bevel=0.04, uv_scale=2.6)
    pb.box((-2.0, 10.65, 0.0), (16.5, 0.45, 12.0), steel_dark, bevel=0.03)
    pb.box((9.5, 3.6, 0.5), (8.0, 7.2, 10.0), trapez, bevel=0.03, uv_scale=2.2)
    pb.box((9.5, 7.35, 0.5), (8.4, 0.35, 10.4), steel_dark, bevel=0.02)
    # Hohe Industrie-Fensterbaender
    for wx in (-6.5, -2.0, 2.5):
        pb.box((wx, 6.2, -5.80), (3.2, 4.6, 0.16), steel_dark, bevel=0.02)
        pb.box((wx, 6.2, -5.76), (2.9, 4.3, 0.08), glass, bevel=0.01)
    # 2 silberne Waermespeicher-Silos rechts
    for sz in (-3.2, 3.2):
        pb.cyl((16.2, 5.6, sz), 2.35, 2.35, 11.2, trapez, axis_g="y", seg=18)
        pb.cyl((16.2, 11.35, sz), 1.9, 2.45, 0.65, steel_dark, axis_g="y", seg=18)
    # 2 hohe Schornsteine mit rot-weissen Flugsicherungs-Ringen (Spitzen bei Y = 25.5 & 22.0 -> Dampf!)
    for sx, sh in ((-5.5, 25.5), (1.5, 22.0)):
        pb.cyl((sx, sh * 0.5, 4.8), 0.78, 1.38, sh, concrete, axis_g="y", seg=16)
        pb.cyl((sx, sh - 2.2, 4.8), 0.85, 0.90, 1.4, red, axis_g="y", seg=16)
        pb.cyl((sx, sh - 3.6, 4.8), 0.90, 0.94, 1.4, white, axis_g="y", seg=16)
        pb.cyl((sx, sh - 5.0, 4.8), 0.94, 0.98, 1.4, red, axis_g="y", seg=16)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_chp_plant.glb"))


# ---------------------------------------------------------------------------
# 5. Gelber Gabelstapler mit Palette & Warnleuchte (pendelt bei Nordkraft Logistik!)
# ---------------------------------------------------------------------------

def build_forklift():
    _reset_scene()
    root = bpy.data.objects.new("ForkliftRoot", None)
    bpy.context.scene.collection.objects.link(root)

    yellow = make_solid_mat("FL_Yellow", (0.94, 0.66, 0.06), rough=0.34, metal=0.22, coat=0.5)
    dark = make_solid_mat("FL_Dark", (0.12, 0.13, 0.15), rough=0.62, metal=0.45)
    tire = make_solid_mat("FL_Tire", (0.06, 0.065, 0.07), rough=0.88, metal=0.0)
    wood = make_solid_mat("FL_Wood", (0.66, 0.50, 0.30), rough=0.84, metal=0.0)
    box_m = make_solid_mat("FL_Crate", (0.58, 0.44, 0.28), rough=0.82, metal=0.0)
    beacon = make_solid_mat("FL_BeaconMat", (1.0, 0.62, 0.06), rough=0.14, metal=0.0,
                            emission=(1.0, 0.58, 0.04), em_strength=4.2)

    pb = PartBuilder("Forklift", origin_g=Vector((0, 0, 0)))
    # Fahrzeugkoerper + Gegengewicht (+X = vorne/Gabeln!)
    pb.box((-0.28, 0.62, 0.0), (1.75, 0.68, 1.12), yellow, bevel=0.04)
    pb.box((-1.08, 0.68, 0.0), (0.42, 0.72, 1.14), dark, bevel=0.05) # Gegengewicht
    # Fahrersitz + Lenkrad + Ueberrollkaefig (4 Pfosten + Dach)
    pb.box((-0.38, 1.08, 0.0), (0.46, 0.42, 0.48), dark, bevel=0.03)
    for sx in (-0.98, 0.46):
        for sz in (-0.48, 0.48):
            pb.cyl((sx, 1.50, sz), 0.035, 0.035, 1.16, dark, axis_g="y", seg=8)
    pb.box((-0.26, 2.08, 0.0), (1.52, 0.06, 1.02), dark, bevel=0.01)
    pb.cyl((-0.72, 2.22, 0.0), 0.08, 0.09, 0.20, beacon, axis_g="y", seg=12) # Gelbe Rundumleuchte!
    # Hubmast vorne (+X = 0.72) + Gabelzinken + geladene Europalette mit Karton!
    for sz in (-0.36, 0.36):
        pb.box((0.72, 1.32, sz), (0.14, 2.28, 0.12), dark, bevel=0.015)
        pb.box((1.35, 0.24, sz * 0.72), (1.18, 0.05, 0.11), dark, bevel=0.008)
    pb.box((1.36, 0.35, 0.0), (1.05, 0.14, 0.86), wood, bevel=0.01)
    pb.box((1.36, 0.78, 0.0), (0.94, 0.72, 0.78), box_m, bevel=0.02)
    # 4 massive Vollgummiraeder
    for wx, wr in ((0.42, 0.30), (-0.82, 0.24)):
        for sz in (-0.58, 0.58):
            pb.cyl((wx, wr, sz), wr, wr, 0.20, tire, axis_g="z", seg=16)
            pb.cyl((wx, wr, sz), wr * 0.50, wr * 0.50, 0.21, yellow, axis_g="z", seg=12)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_forklift.glb"))


# ---------------------------------------------------------------------------
# 6. Firmen-Fahnenmast mit wehender Flagge ('Flag' fuer Wind-Shader!)
# ---------------------------------------------------------------------------

def build_flagpole():
    _reset_scene()
    root = bpy.data.objects.new("FlagpoleRoot", None)
    bpy.context.scene.collection.objects.link(root)

    alu = make_solid_mat("Flag_PoleMat", (0.76, 0.78, 0.82), rough=0.26, metal=0.90)
    flag_mat = make_solid_mat("Flag_ClothMat", (0.12, 0.30, 0.58), rough=0.78, metal=0.0)

    pb_p = PartBuilder("Pole", origin_g=Vector((0, 0, 0)))
    pb_p.cyl((0.0, 3.6, 0.0), 0.036, 0.068, 7.2, alu, axis_g="y", seg=12)
    pb_p.cyl((0.0, 7.28, 0.0), 0.08, 0.08, 0.12, alu, axis_g="y", seg=12)
    pb_p.cyl((0.55, 7.05, 0.0), 0.018, 0.018, 1.12, alu, axis_g="x", seg=8) # Ausleger-Galgen
    pb_p.build(root)

    # Unterteilte vertikale Hissflagge ('Flag' -> wellt sich sauber im Wind-Shader!)
    pb_f = PartBuilder("Flag", origin_g=Vector((0, 0, 0)))
    mid = pb_f._mid(flag_mat)
    nx, ny = 6, 12
    grid = []
    for iy in range(ny + 1):
        row = []
        v = iy / ny
        yg = 4.55 + v * 2.45
        for ix in range(nx + 1):
            u = ix / nx
            xg = 0.08 + u * 0.98
            zg = math.sin(v * 5.0 + u * 2.5) * 0.04 * (1.0 - v * 0.6)
            row.append(pb_f.bm.verts.new(pb_f._local_b(Vector((xg, yg, zg)))))
        grid.append(row)
    for iy in range(ny):
        for ix in range(nx):
            f = pb_f.bm.faces.new((grid[iy][ix], grid[iy][ix + 1], grid[iy + 1][ix + 1], grid[iy + 1][ix]))
            f.material_index = mid
            f.smooth = True
    bmesh.ops.recalc_face_normals(pb_f.bm, faces=list(pb_f.bm.faces))
    pb_f.build(root)

    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_flagpole.glb"))


# ---------------------------------------------------------------------------
# 7. Abgesattelter 40t-Auflieger fuer Nordkraft-Laderampen (ext_dock_trailer.glb)
# ---------------------------------------------------------------------------

def build_dock_trailer():
    _reset_scene()
    root = bpy.data.objects.new("DockTrailerRoot", None)
    bpy.context.scene.collection.objects.link(root)

    mats = _shared_vehicle_mats("trailer", "D   NK 712", (0.14, 0.24, 0.40))
    curtain = make_tex_mat("Truck_CurtainMat", _gen_truck_curtain_tex(), rough=0.58, metal=0.04, coat=0.0)
    roof_m = make_solid_mat("Trailer_Roof", (0.88, 0.90, 0.92), rough=0.45, metal=0.10)

    pb = PartBuilder("TrailerBody", origin_g=Vector((0, 0, 0)))
    # 10 m Auflieger mit ausgefahrenen Stuetzbeinen vorne (+X)
    pb.box((0.0, 1.08, 0.0), (10.0, 0.22, 2.38), mats["chassis"], bevel=0.02)
    pb.box((0.0, 2.52, 0.0), (10.1, 2.66, 2.46), curtain, uv_mode="side_x", bevel=0.03)
    pb.box((0.0, 3.86, 0.0), (10.15, 0.09, 2.48), roof_m, bevel=0.015)
    # Ausgefahrene Stuetzbeine bis auf den Asphalt (Y = 0.0..1.05)!
    for s in (-1.0, 1.0):
        pb.box((3.2, 0.54, s * 0.90), (0.20, 1.04, 0.20), mats["chassis"], bevel=0.012)
        pb.box((3.2, 0.04, s * 0.90), (0.36, 0.08, 0.34), mats["trim"], bevel=0.01)
        for ly in (0.58, 0.82):
            pb.box((0.8, ly, s * 1.16), (3.8, 0.10, 0.05), mats["rim"], bevel=0.008)
    # Heckportaltueren
    pb.box((-5.05, 2.52, 0.0), (0.06, 2.62, 2.42), roof_m, bevel=0.015)
    pb.box((-5.05, 0.62, 0.0), (0.18, 0.18, 2.36), mats["rim"], bevel=0.015)
    pb.build(root)

    w_r, w_w = 0.51, 0.31
    for idx, tx in enumerate((-1.85, -3.05, -4.25), start=1):
        _build_wheel(f"Wheel_L{idx}", Vector((tx, w_r, -1.06)), w_r, w_w, mats, root, spokes=6)
        _build_wheel(f"Wheel_R{idx}", Vector((tx, w_r,  1.06)), w_r, w_w, mats, root, spokes=6)

    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_dock_trailer.glb"))


def main():
    tex = ensure_exterior_textures()
    build_wind_turbine()
    build_power_pylon()
    build_tower_crane()
    build_chp_plant(tex)
    build_forklift()
    build_flagpole()
    build_dock_trailer()
    print("[HORIZON] Alle 7 lebendigen Horizont- & Hof-Modelle erfolgreich gebaut!")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
