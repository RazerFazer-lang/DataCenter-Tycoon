"""Blender 5.2 Generator fuer 4 realistische deutsche Strassen- & Parkplatzfahrzeuge:
  - assets/models/ext_car_sedan.glb   (Moderner Kompaktwagen / Limousine)
  - assets/models/ext_car_suv.glb     (Moderner SUV / Kombi mit Dachreling)
  - assets/models/ext_car_van.glb     (Weisser Handwerker-Transporter mit Dachgepaecktraeger)
  - assets/models/ext_car_truck.glb   (40t-Sattelzug / LKW mit Zugmaschine & Planen-Auflieger)

Godot-Koordinaten (g(x, y, z) -> Blender (x, -z, y)):
    +X = Vorne (Fahrtrichtung), -X = Hinten
    +Y = Oben (Reifen-Aufstandspunkt bei Y = 0.0)
    Z  = Breite (Links / Rechts)

Benannte Knoten & Materialien fuer exterior_district.gd:
    Wheel_FL, Wheel_FR, Wheel_RL, Wheel_RR (+ weitere Achsen beim LKW) -> drehen um Z
    Car_PaintMat       -> dynamische Lackfarbe in Godot (Metallic Clearcoat)
    Truck_CurtainMat   -> dynamische Planenfarbe beim LKW
    Car_HeadlightMat   -> Scheinwerfer-Emission (nachts/bei Regen hell)
    Car_TaillightMat   -> Ruecklichter (nachts an)
    Car_BrakeMat       -> Bremslichter (leuchten stark rot beim Anhalten!)
"""

import math
import os
import sys
import traceback

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import dct_paths
import pbr_textures
from build_delivery_van import (
    PartBuilder,
    _save_rgb,
    g,
    make_solid_mat,
    make_tex_mat,
)

OUT_MODELS_DIR = dct_paths.MODELS_DIR
CACHE_DIR = dct_paths.PBR_CACHE


def _reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for img in list(bpy.data.images):
        bpy.data.images.remove(img)


def _gen_plate(name: str, text: str) -> str:
    os.makedirs(CACHE_DIR, exist_ok=True)
    p = os.path.join(CACHE_DIR, f"plate_{name}.png")
    w, h = 512, 128
    img = np.ones((h, w, 3), dtype=np.float32) * 0.96
    pbr_textures.stroke_rect(img, 2, 2, w - 3, h - 3, (0.06, 0.06, 0.07), thickness=5)
    pbr_textures.fill_rect(img, 7, 7, 68, h - 8, (0.06, 0.22, 0.66))
    pbr_textures.draw_text(img, 26, 74, "D", (0.98, 0.98, 0.98), scale=4)
    pbr_textures.draw_text(img, 92, 36, text, (0.05, 0.05, 0.06), scale=6)
    _save_rgb(p, img)
    return p


def _gen_truck_curtain_tex() -> str:
    os.makedirs(CACHE_DIR, exist_ok=True)
    p = os.path.join(CACHE_DIR, "ext_truck_curtain.png")
    w, h = 1024, 512
    img = np.zeros((h, w, 3), dtype=np.float32)
    img[:, :] = np.array([0.88, 0.90, 0.93], dtype=np.float32)
    # Leichte senkrechte Spanngurt-Falten in der LKW-Plane
    yy, xx = np.mgrid[0:h, 0:w]
    fold = 0.96 + 0.04 * np.sin(xx * (2.0 * math.pi / 42.0))
    img *= fold[:, :, None]
    # Dekor-Streifen (neutrales Logistik-Blau/Anthrazit)
    img[370:445, :] = np.array([0.12, 0.24, 0.42], dtype=np.float32)
    img[352:370, :] = np.array([0.92, 0.56, 0.10], dtype=np.float32)
    img[445:, :] = np.array([0.16, 0.17, 0.19], dtype=np.float32)
    pbr_textures.draw_text(img, 140, 145, "EURO-CARGO LOGISTIK", (0.12, 0.20, 0.34), scale=5)
    pbr_textures.draw_text(img, 145, 232, "FERNVERKEHR  •  SCHWERLAST", (0.28, 0.34, 0.44), scale=3)
    # Schnallen unten
    for bx in range(44, w - 20, 72):
        pbr_textures.fill_rect(img, bx, 448, bx + 12, 492, (0.58, 0.60, 0.64))
    _save_rgb(p, img)
    return p


def _shared_vehicle_mats(plate_id: str, plate_txt: str, default_paint):
    plate_path = _gen_plate(plate_id, plate_txt)
    return {
        "paint": make_solid_mat("Car_PaintMat", default_paint, rough=0.22, metal=0.42, coat=0.85),
        "trim": make_solid_mat("Car_TrimMat", (0.09, 0.10, 0.11), rough=0.72, metal=0.05),
        "grille": make_solid_mat("Car_GrilleMat", (0.05, 0.055, 0.06), rough=0.62, metal=0.22),
        "chrome": make_solid_mat("Car_ChromeMat", (0.82, 0.84, 0.88), rough=0.14, metal=0.96),
        "glass": make_solid_mat("Car_GlassMat", (0.06, 0.10, 0.14), rough=0.06, metal=0.12, coat=1.0),
        "tire": make_solid_mat("Car_TireMat", (0.065, 0.068, 0.072), rough=0.86, metal=0.0),
        "rim": make_solid_mat("Car_RimMat", (0.76, 0.78, 0.82), rough=0.22, metal=0.90),
        "rotor": make_solid_mat("Car_RotorMat", (0.46, 0.48, 0.52), rough=0.44, metal=0.85),
        "caliper": make_solid_mat("Car_CaliperMat", (0.68, 0.12, 0.10), rough=0.35, metal=0.40),
        "headlight": make_solid_mat("Car_HeadlightMat", (0.96, 0.97, 1.0), rough=0.08, metal=0.10,
                                    emission=(1.0, 0.96, 0.86), em_strength=0.4),
        "taillight": make_solid_mat("Car_TaillightMat", (0.64, 0.05, 0.05), rough=0.14, metal=0.05,
                                    emission=(0.95, 0.08, 0.05), em_strength=0.35),
        "brake": make_solid_mat("Car_BrakeMat", (0.76, 0.06, 0.05), rough=0.14, metal=0.05,
                                emission=(1.0, 0.10, 0.06), em_strength=0.18),
        "indicator": make_solid_mat("Car_IndicatorMat", (0.88, 0.46, 0.04), rough=0.18, metal=0.05),
        "plate": make_tex_mat("Car_PlateMat", plate_path, rough=0.32, metal=0.12, coat=0.25),
        "chassis": make_solid_mat("Car_ChassisMat", (0.08, 0.085, 0.095), rough=0.82, metal=0.30),
    }


def _build_wheel(name: str, pos_g: Vector, radius: float, width: float, mats: dict,
                 parent, spokes: int = 5, twin: bool = False):
    pb = PartBuilder(name, origin_g=pos_g)
    offsets = [-width * 0.56, width * 0.56] if twin else [0.0]
    for dz in offsets:
        c = pos_g + Vector((0.0, 0.0, dz))
        # Reifen-Laufflaeche + abgeschrägte Seitenflanke
        pb.cyl(c, radius, radius, width * 0.82, mats["tire"], axis_g="z", seg=26)
        pb.cyl(c + Vector((0.0, 0.0, width * 0.44)), radius * 0.94, radius, width * 0.08, mats["tire"], axis_g="z", seg=26)
        pb.cyl(c - Vector((0.0, 0.0, width * 0.44)), radius, radius * 0.94, width * 0.08, mats["tire"], axis_g="z", seg=26)
        # Alufelgen-Bett
        rim_r = radius * 0.64
        pb.cyl(c, rim_r, rim_r, width * 0.86, mats["rim"], axis_g="z", seg=22)
        # Dunkle Innen-Bremsscheibe
        pb.cyl(c, rim_r * 0.80, rim_r * 0.80, width * 0.40, mats["rotor"], axis_g="z", seg=18)
        # Radnabe + 5-Speichen-Stern aussen (beidseitig, damit links & rechts gut aussehen)
        for side in (-1.0, 1.0):
            sz = side * (width * 0.43)
            pb.cyl(c + Vector((0.0, 0.0, sz)), rim_r * 0.24, rim_r * 0.24, 0.035, mats["chrome"], axis_g="z", seg=14)
            for si in range(spokes):
                ang = (si / spokes) * math.tau
                mx = math.cos(ang) * (rim_r * 0.50)
                my = math.sin(ang) * (rim_r * 0.50)
                rot_z = math.degrees(ang)
                pb.box(c + Vector((mx, my, sz)), (rim_r * 0.72, rim_r * 0.16, 0.030),
                       mats["rim"], rot_g_deg=(0.0, 0.0, rot_z), bevel=0.005)
    return pb.build(parent)


def _rect_ring(y_bot: float, y_top: float, z_bot: float, z_top: float, y_mid: float = None, z_mid: float = None):
    """8-Punkt-Querschnitt (Uhrzeigersinn) fuer glatte Auto-Karosserie-Lofts."""
    if y_mid is None:
        y_mid = (y_bot + y_top) * 0.52
    if z_mid is None:
        z_mid = max(z_bot, z_top) + 0.035
    return [
        (y_bot, -z_bot),
        (y_mid, -z_mid),
        (y_top, -z_top),
        (y_top + 0.03, -z_top * 0.55),
        (y_top + 0.03, z_top * 0.55),
        (y_top, z_top),
        (y_mid, z_mid),
        (y_bot, z_bot),
    ]


def _export_glb(out_path: str):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_yup=True,
        export_apply=False,
    )
    size_kb = os.path.getsize(out_path) / 1024.0
    print(f"[VEHICLES] Exported {os.path.basename(out_path)} ({size_kb:.1f} KB)")


# ---------------------------------------------------------------------------
# 1. Kompaktwagen / Limousine (4.45 m x 1.84 m x 1.44 m)
# ---------------------------------------------------------------------------

def build_sedan():
    _reset_scene()
    root = bpy.data.objects.new("SedanRoot", None)
    bpy.context.scene.collection.objects.link(root)
    mats = _shared_vehicle_mats("sedan", "B   VT 428", (0.14, 0.24, 0.38))

    pb = PartBuilder("Body", origin_g=Vector((0, 0, 0)))

    # Unterboden / Chassis
    pb.box((0.0, 0.24, 0.0), (4.15, 0.14, 1.56), mats["chassis"], bevel=0.02)

    # Geschwungener Unterbau (Motorhaube -> Guertellinie -> Kofferraum)
    lower_stations = [
        (-2.22, _rect_ring(0.28, 0.88, 0.78, 0.74, 0.56, 0.84)),
        (-1.85, _rect_ring(0.24, 0.96, 0.84, 0.80, 0.58, 0.90)),
        (-1.05, _rect_ring(0.22, 0.97, 0.86, 0.82, 0.58, 0.91)),
        (0.85,  _rect_ring(0.22, 0.95, 0.86, 0.82, 0.57, 0.91)),
        (1.62,  _rect_ring(0.24, 0.86, 0.84, 0.78, 0.54, 0.89)),
        (2.08,  _rect_ring(0.26, 0.74, 0.80, 0.72, 0.48, 0.85)),
        (2.22,  _rect_ring(0.30, 0.64, 0.72, 0.66, 0.44, 0.76)),
    ]
    pb.loft_x(lower_stations, mats["paint"], cap_ends=True, smooth=True)

    # Geschwungene Kabine / Gewaechshaus (mit Schraegheck-Abfall)
    cabin_stations = [
        (-1.72, _rect_ring(0.95, 1.00, 0.76, 0.70, 0.97, 0.74)),
        (-1.20, _rect_ring(0.95, 1.38, 0.78, 0.62, 1.16, 0.72)),
        (-0.55, _rect_ring(0.95, 1.43, 0.79, 0.62, 1.19, 0.72)),
        (0.35,  _rect_ring(0.94, 1.42, 0.79, 0.62, 1.18, 0.72)),
        (1.06,  _rect_ring(0.91, 0.96, 0.76, 0.70, 0.93, 0.74)),
    ]
    pb.loft_x(cabin_stations, mats["glass"], cap_ends=True, smooth=True)

    # Dachhaut + A-/B-/C-Saeulen in Wagenfarbe ueber dem Glas
    roof_stations = [
        (-1.18, _rect_ring(1.37, 1.42, 0.63, 0.58, 1.39, 0.61)),
        (-0.55, _rect_ring(1.42, 1.46, 0.63, 0.58, 1.44, 0.61)),
        (0.35,  _rect_ring(1.41, 1.45, 0.63, 0.58, 1.43, 0.61)),
    ]
    pb.loft_x(roof_stations, mats["paint"], cap_ends=True, smooth=True)

    for s in (-1.0, 1.0):
        # A-, B-, C-Saeule
        pb.box((0.68, 1.17, s * 0.69), (0.09, 0.58, 0.05), mats["paint"], rot_g_deg=(0.0, 0.0, 48.0), bevel=0.01)
        pb.box((-0.18, 1.18, s * 0.70), (0.11, 0.48, 0.05), mats["trim"], bevel=0.008)
        pb.box((-1.36, 1.17, s * 0.68), (0.16, 0.54, 0.05), mats["paint"], rot_g_deg=(0.0, 0.0, -40.0), bevel=0.01)
        # Schwarze Seitenschweller & Radkasten-Blenden
        pb.box((0.0, 0.25, s * 0.89), (2.25, 0.11, 0.06), mats["trim"], bevel=0.01)
        for wx in (-1.34, 1.36):
            pb.cyl((wx, 0.34, s * 0.85), 0.39, 0.39, 0.16, mats["chassis"], axis_g="z", seg=20)
        # Seitenspiegel + Tuergriffe
        pb.box((0.52, 1.00, s * 0.98), (0.14, 0.11, 0.17), mats["paint"], bevel=0.018)
        pb.box((0.46, 0.99, s * 0.92), (0.08, 0.05, 0.10), mats["trim"], bevel=0.008)
        pb.box((0.12, 0.84, s * 0.91), (0.17, 0.045, 0.04), mats["chrome"], bevel=0.008)
        pb.box((-0.78, 0.85, s * 0.91), (0.17, 0.045, 0.04), mats["chrome"], bevel=0.008)

    # Front-Kuehlergrill, Lufteinlass, Chromleiste & Scheinwerfer
    pb.box((2.21, 0.54, 0.0), (0.08, 0.22, 0.92), mats["grille"], bevel=0.015)
    pb.box((2.23, 0.57, 0.0), (0.04, 0.035, 0.88), mats["chrome"], bevel=0.006)
    pb.box((2.18, 0.34, 0.0), (0.14, 0.14, 1.44), mats["trim"], bevel=0.018)
    for s in (-1.0, 1.0):
        pb.box((2.16, 0.65, s * 0.59), (0.16, 0.13, 0.34), mats["headlight"], rot_g_deg=(0.0, s * -10.0, 0.0), bevel=0.018)
        pb.box((2.16, 0.42, s * 0.62), (0.10, 0.07, 0.22), mats["grille"], bevel=0.01)
    pb.box((2.24, 0.42, 0.0), (0.03, 0.11, 0.50), mats["plate"], uv_mode="front_y", bevel=0.003)

    # Heck-Diffusor, Doppelauspuff, Ruecklichter & Bremslichter
    pb.box((-2.20, 0.34, 0.0), (0.14, 0.16, 1.54), mats["trim"], bevel=0.018)
    pb.cyl((-2.22, 0.28, -0.52), 0.045, 0.045, 0.14, mats["chrome"], axis_g="x", seg=12)
    pb.cyl((-2.22, 0.28, 0.52), 0.045, 0.045, 0.14, mats["chrome"], axis_g="x", seg=12)
    for s in (-1.0, 1.0):
        pb.box((-2.19, 0.78, s * 0.57), (0.12, 0.13, 0.40), mats["taillight"], bevel=0.015)
        pb.box((-2.20, 0.78, s * 0.52), (0.11, 0.07, 0.24), mats["brake"], bevel=0.01)
    # 3. Bremslicht oben an der Heckscheibe
    pb.box((-1.32, 1.37, 0.0), (0.06, 0.04, 0.38), mats["brake"], bevel=0.006)
    pb.box((-2.24, 0.55, 0.0), (0.03, 0.11, 0.50), mats["plate"], uv_mode="front_y", bevel=0.003)
    # Haifisch-Antenne
    pb.box((-0.92, 1.49, 0.0), (0.18, 0.07, 0.05), mats["trim"], bevel=0.01)

    pb.build(root)

    # 4 drehbare Raeder (Y = radius = 0.33 m)
    w_r, w_w = 0.33, 0.23
    _build_wheel("Wheel_FL", Vector((1.36, w_r, -0.82)), w_r, w_w, mats, root)
    _build_wheel("Wheel_FR", Vector((1.36, w_r,  0.82)), w_r, w_w, mats, root)
    _build_wheel("Wheel_RL", Vector((-1.34, w_r, -0.82)), w_r, w_w, mats, root)
    _build_wheel("Wheel_RR", Vector((-1.34, w_r,  0.82)), w_r, w_w, mats, root)

    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_car_sedan.glb"))


# ---------------------------------------------------------------------------
# 2. Moderner SUV / Kombi (4.68 m x 1.96 m x 1.72 m)
# ---------------------------------------------------------------------------

def build_suv():
    _reset_scene()
    root = bpy.data.objects.new("SuvRoot", None)
    bpy.context.scene.collection.objects.link(root)
    mats = _shared_vehicle_mats("suv", "M   DC 812", (0.72, 0.75, 0.79))

    pb = PartBuilder("Body", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.32, 0.0), (4.35, 0.16, 1.66), mats["chassis"], bevel=0.02)

    # Kraeftiger SUV-Unterbau
    lower_stations = [
        (-2.34, _rect_ring(0.38, 1.06, 0.86, 0.84, 0.70, 0.92)),
        (-1.90, _rect_ring(0.32, 1.12, 0.92, 0.88, 0.72, 0.97)),
        (1.05,  _rect_ring(0.32, 1.10, 0.92, 0.88, 0.70, 0.97)),
        (1.85,  _rect_ring(0.34, 1.04, 0.90, 0.84, 0.68, 0.94)),
        (2.26,  _rect_ring(0.38, 0.92, 0.84, 0.78, 0.64, 0.88)),
        (2.36,  _rect_ring(0.42, 0.80, 0.76, 0.72, 0.58, 0.80)),
    ]
    pb.loft_x(lower_stations, mats["paint"], cap_ends=True, smooth=True)

    # Hohe Kombi-/SUV-Kabine
    cabin_stations = [
        (-2.18, _rect_ring(1.06, 1.12, 0.84, 0.78, 1.09, 0.82)),
        (-1.82, _rect_ring(1.06, 1.66, 0.86, 0.72, 1.38, 0.80)),
        (0.55,  _rect_ring(1.06, 1.68, 0.86, 0.72, 1.38, 0.80)),
        (1.22,  _rect_ring(1.04, 1.10, 0.84, 0.78, 1.07, 0.82)),
    ]
    pb.loft_x(cabin_stations, mats["glass"], cap_ends=True, smooth=True)

    roof_stations = [
        (-1.80, _rect_ring(1.65, 1.71, 0.73, 0.68, 1.68, 0.71)),
        (0.55,  _rect_ring(1.67, 1.73, 0.73, 0.68, 1.70, 0.71)),
    ]
    pb.loft_x(roof_stations, mats["paint"], cap_ends=True, smooth=True)

    for s in (-1.0, 1.0):
        # Alu-Dachreling
        pb.box((-0.62, 1.76, s * 0.62), (2.10, 0.05, 0.05), mats["chrome"], bevel=0.01)
        for rx in (-1.52, -0.58, 0.34):
            pb.box((rx, 1.72, s * 0.62), (0.08, 0.08, 0.045), mats["trim"], bevel=0.008)
        # Saeulen
        pb.box((0.86, 1.36, s * 0.76), (0.10, 0.68, 0.055), mats["paint"], rot_g_deg=(0.0, 0.0, 40.0), bevel=0.01)
        pb.box((-0.18, 1.37, s * 0.77), (0.12, 0.58, 0.055), mats["trim"], bevel=0.008)
        pb.box((-1.15, 1.37, s * 0.77), (0.12, 0.58, 0.055), mats["trim"], bevel=0.008)
        pb.box((-1.96, 1.36, s * 0.76), (0.18, 0.62, 0.055), mats["paint"], rot_g_deg=(0.0, 0.0, -24.0), bevel=0.01)
        # Robuste SUV-Beplankung + Trittbrett
        pb.box((0.0, 0.34, s * 0.96), (2.40, 0.14, 0.08), mats["trim"], bevel=0.015)
        for wx in (-1.42, 1.44):
            pb.cyl((wx, 0.40, s * 0.90), 0.46, 0.46, 0.18, mats["chassis"], axis_g="z", seg=20)
        # Spiegel & Griffe
        pb.box((0.68, 1.15, s * 1.05), (0.16, 0.13, 0.19), mats["paint"], bevel=0.02)
        pb.box((0.20, 0.98, s * 0.97), (0.18, 0.05, 0.045), mats["chrome"], bevel=0.008)
        pb.box((-0.82, 0.99, s * 0.97), (0.18, 0.05, 0.045), mats["chrome"], bevel=0.008)

    # Markanter SUV-Kuehlergrill + Unterfahrschutz
    pb.box((2.34, 0.72, 0.0), (0.09, 0.30, 1.04), mats["grille"], bevel=0.018)
    for gy in (0.64, 0.72, 0.80):
        pb.box((2.37, gy, 0.0), (0.03, 0.025, 0.96), mats["chrome"], bevel=0.004)
    pb.box((2.30, 0.44, 0.0), (0.16, 0.18, 1.62), mats["trim"], bevel=0.02)
    pb.box((2.34, 0.37, 0.0), (0.10, 0.08, 0.92), mats["rim"], bevel=0.012)
    for s in (-1.0, 1.0):
        pb.box((2.30, 0.84, s * 0.67), (0.16, 0.14, 0.36), mats["headlight"], bevel=0.018)
    pb.box((2.38, 0.50, 0.0), (0.03, 0.11, 0.50), mats["plate"], uv_mode="front_y", bevel=0.003)

    # Heckleuchtenband + Bremslichter
    pb.box((-2.33, 0.44, 0.0), (0.15, 0.18, 1.66), mats["trim"], bevel=0.02)
    pb.box((-2.35, 0.95, 0.0), (0.09, 0.11, 1.54), mats["taillight"], bevel=0.014)
    for s in (-1.0, 1.0):
        pb.box((-2.36, 0.95, s * 0.62), (0.10, 0.13, 0.32), mats["brake"], bevel=0.012)
    pb.box((-1.90, 1.66, 0.0), (0.14, 0.06, 1.38), mats["paint"], bevel=0.012)
    pb.box((-1.97, 1.65, 0.0), (0.05, 0.04, 0.36), mats["brake"], bevel=0.006)
    pb.box((-2.37, 0.68, 0.0), (0.03, 0.11, 0.50), mats["plate"], uv_mode="front_y", bevel=0.003)

    pb.build(root)

    w_r, w_w = 0.39, 0.25
    _build_wheel("Wheel_FL", Vector((1.44, w_r, -0.89)), w_r, w_w, mats, root)
    _build_wheel("Wheel_FR", Vector((1.44, w_r,  0.89)), w_r, w_w, mats, root)
    _build_wheel("Wheel_RL", Vector((-1.42, w_r, -0.89)), w_r, w_w, mats, root)
    _build_wheel("Wheel_RR", Vector((-1.42, w_r,  0.89)), w_r, w_w, mats, root)

    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_car_suv.glb"))


# ---------------------------------------------------------------------------
# 3. Handwerker-/Gewerbe-Transporter (5.45 m x 2.02 m x 2.42 m)
# ---------------------------------------------------------------------------

def build_trades_van():
    _reset_scene()
    root = bpy.data.objects.new("VanRoot", None)
    bpy.context.scene.collection.objects.link(root)
    mats = _shared_vehicle_mats("van", "K   EL 509", (0.92, 0.93, 0.94))

    pb = PartBuilder("Body", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.34, 0.0), (5.15, 0.18, 1.72), mats["chassis"], bevel=0.02)

    # Kastenwagen-Karosserie (aerodynamische Lieferwagen-Schnauze + Hochdach)
    stations = [
        (-2.72, _rect_ring(0.42, 2.34, 0.95, 0.86, 1.35, 1.00)),
        (-2.45, _rect_ring(0.36, 2.40, 0.98, 0.88, 1.35, 1.02)),
        (1.05,  _rect_ring(0.36, 2.38, 0.98, 0.88, 1.35, 1.02)),
        (1.48,  _rect_ring(0.36, 2.24, 0.96, 0.86, 1.28, 1.00)),
        (2.08,  _rect_ring(0.36, 1.38, 0.94, 0.86, 0.90, 0.98)),
        (2.58,  _rect_ring(0.38, 1.18, 0.88, 0.82, 0.78, 0.92)),
        (2.72,  _rect_ring(0.42, 1.02, 0.80, 0.76, 0.70, 0.84)),
    ]
    pb.loft_x(stations, mats["paint"], cap_ends=True, smooth=True)

    # Windschutzscheibe & Seitenscheiben der Fahrerkabine
    pb.box((1.78, 1.80, 0.0), (0.10, 0.92, 1.66), mats["glass"], rot_g_deg=(0.0, 0.0, 34.0), bevel=0.015)
    for s in (-1.0, 1.0):
        pb.box((1.42, 1.66, s * 0.96), (0.86, 0.64, 0.06), mats["glass"], bevel=0.012)
        # Schwarze Seitenrammschutz-Leiste
        pb.box((-0.45, 0.56, s * 1.01), (4.20, 0.24, 0.06), mats["trim"], bevel=0.015)
        # Vertikale Blech-Sicken am Laderaum
        for vx in (-1.95, -0.95, 0.05, 0.85):
            pb.box((vx, 1.48, s * 1.005), (0.04, 1.30, 0.025), mats["trim"], bevel=0.005)
        # Grosse Transporter-Spiegel
        pb.box((1.84, 1.54, s * 1.13), (0.16, 0.30, 0.14), mats["trim"], bevel=0.018)
        pb.box((1.84, 1.54, s * 1.04), (0.07, 0.08, 0.14), mats["trim"], bevel=0.008)
        # Radkaesten
        for wx in (-1.62, 1.72):
            pb.cyl((wx, 0.38, s * 0.92), 0.45, 0.45, 0.20, mats["chassis"], axis_g="z", seg=20)

    # Alu-Dachgepaecktraeger (typischer Handwerker-Look!)
    for s in (-1.0, 1.0):
        pb.box((-0.65, 2.52, s * 0.72), (3.30, 0.055, 0.055), mats["rim"], bevel=0.008)
    for rx in (-2.20, -1.42, -0.65, 0.12, 0.90):
        pb.box((rx, 2.50, 0.0), (0.055, 0.045, 1.48), mats["rim"], bevel=0.008)
        for s in (-1.0, 1.0):
            pb.box((rx, 2.43, s * 0.72), (0.06, 0.14, 0.05), mats["trim"], bevel=0.006)

    # Front-Stossstange, Kuehlergrill & Lichter
    pb.box((2.68, 0.56, 0.0), (0.20, 0.34, 1.88), mats["trim"], bevel=0.025)
    pb.box((2.70, 0.94, 0.0), (0.10, 0.30, 1.12), mats["grille"], bevel=0.015)
    for s in (-1.0, 1.0):
        pb.box((2.66, 0.98, s * 0.74), (0.16, 0.22, 0.32), mats["headlight"], bevel=0.018)
    pb.box((2.79, 0.56, 0.0), (0.03, 0.11, 0.50), mats["plate"], uv_mode="front_y", bevel=0.003)

    # Heck-Stossstange, Fluegeltuer-Fuge & hohe Transporter-Ruecklichter
    pb.box((-2.72, 0.52, 0.0), (0.18, 0.26, 1.92), mats["trim"], bevel=0.022)
    pb.box((-2.73, 1.45, 0.0), (0.03, 1.65, 0.03), mats["trim"], bevel=0.004)
    for s in (-1.0, 1.0):
        pb.box((-2.72, 1.05, s * 0.84), (0.10, 0.52, 0.18), mats["taillight"], bevel=0.014)
        pb.box((-2.73, 1.16, s * 0.84), (0.10, 0.22, 0.15), mats["brake"], bevel=0.01)
    pb.box((-2.74, 2.34, 0.0), (0.06, 0.05, 0.38), mats["brake"], bevel=0.006)
    pb.box((-2.75, 0.88, -0.34), (0.03, 0.11, 0.50), mats["plate"], uv_mode="front_y", bevel=0.003)

    pb.build(root)

    w_r, w_w = 0.37, 0.24
    _build_wheel("Wheel_FL", Vector((1.72, w_r, -0.92)), w_r, w_w, mats, root)
    _build_wheel("Wheel_FR", Vector((1.72, w_r,  0.92)), w_r, w_w, mats, root)
    _build_wheel("Wheel_RL", Vector((-1.62, w_r, -0.92)), w_r, w_w, mats, root)
    _build_wheel("Wheel_RR", Vector((-1.62, w_r,  0.92)), w_r, w_w, mats, root)

    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_car_van.glb"))


# ---------------------------------------------------------------------------
# 4. 40t-Sattelzug / Fernverkehrs-LKW (12.4 m x 2.50 m x 3.85 m)
# ---------------------------------------------------------------------------

def build_semi_truck():
    _reset_scene()
    root = bpy.data.objects.new("SemiTruckRoot", None)
    bpy.context.scene.collection.objects.link(root)
    mats = _shared_vehicle_mats("truck", "HH  LG 400", (0.11, 0.20, 0.36))
    curtain_mat = make_tex_mat("Truck_CurtainMat", _gen_truck_curtain_tex(), rough=0.58, metal=0.04, coat=0.0)
    roof_mat = make_solid_mat("Truck_RoofMat", (0.86, 0.88, 0.90), rough=0.45, metal=0.10)

    pb = PartBuilder("Body", origin_g=Vector((0, 0, 0)))

    # 1. ZUGMASCHINE (X = +2.1 .. +6.0)
    # Schwerer Leiterrahmen + Dieseltanks + Sattelkupplung
    pb.box((3.2, 0.86, 0.0), (4.8, 0.28, 1.05), mats["chassis"], bevel=0.02)
    for s in (-1.0, 1.0):
        pb.box((3.25, 0.72, s * 0.92), (1.35, 0.54, 0.56), mats["rim"], bevel=0.03) # Alu-Dieseltank
        pb.box((3.25, 0.72, s * 0.92), (0.08, 0.56, 0.58), mats["trim"], bevel=0.01)

    # Hohes Fernverkehrs-Fahrerhaus (Cab-over)
    cab_stations = [
        (3.85, _rect_ring(0.95, 3.38, 1.18, 1.12, 2.20, 1.22)),
        (5.65, _rect_ring(0.95, 3.32, 1.18, 1.10, 2.15, 1.22)),
        (5.98, _rect_ring(0.95, 3.05, 1.12, 1.02, 1.95, 1.16)),
    ]
    pb.loft_x(cab_stations, mats["paint"], cap_ends=True, smooth=True)
    # Dachspoiler der Zugmaschine
    pb.box((4.42, 3.58, 0.0), (1.28, 0.42, 2.26), mats["paint"], rot_g_deg=(0.0, 0.0, -14.0), bevel=0.04)

    # Breite LKW-Windschutzscheibe + Sonnenblende + Seitenscheiben + Spiegel
    pb.box((5.92, 2.46, 0.0), (0.12, 0.92, 2.04), mats["glass"], rot_g_deg=(0.0, 0.0, 10.0), bevel=0.015)
    pb.box((5.98, 2.98, 0.0), (0.28, 0.16, 2.22), mats["trim"], rot_g_deg=(0.0, 0.0, -16.0), bevel=0.015)
    for s in (-1.0, 1.0):
        pb.box((5.12, 2.40, s * 1.21), (1.12, 0.78, 0.06), mats["glass"], bevel=0.012)
        # Grosse Doppel-Aussenspiegel an Stahlbuegeln
        pb.box((5.68, 2.34, s * 1.40), (0.14, 0.62, 0.12), mats["trim"], bevel=0.015)
        pb.box((5.62, 2.60, s * 1.30), (0.05, 0.05, 0.24), mats["trim"], bevel=0.006)
        pb.box((5.62, 2.08, s * 1.30), (0.05, 0.05, 0.24), mats["trim"], bevel=0.006)
        # Einstiegsstufen
        pb.box((5.08, 0.72, s * 1.12), (0.62, 0.34, 0.22), mats["trim"], bevel=0.015)

    # Markanter Mehr-Lamellen-Kuehlergrill + Stossstange + Scheinwerfer + Dach-Positionslichter
    pb.box((5.98, 1.54, 0.0), (0.10, 0.88, 1.66), mats["grille"], bevel=0.02)
    for gy in (1.24, 1.44, 1.64, 1.84):
        pb.box((6.02, gy, 0.0), (0.04, 0.055, 1.56), mats["chrome"], bevel=0.006)
    pb.box((5.96, 0.76, 0.0), (0.26, 0.44, 2.40), mats["trim"], bevel=0.025)
    for s in (-1.0, 1.0):
        pb.box((6.04, 0.78, s * 0.92), (0.14, 0.22, 0.42), mats["headlight"], bevel=0.015)
        pb.box((5.96, 3.16, s * 0.88), (0.10, 0.08, 0.18), mats["indicator"], bevel=0.008)
    pb.box((6.10, 0.68, 0.0), (0.03, 0.12, 0.52), mats["plate"], uv_mode="front_y", bevel=0.003)

    # 2. AUFLIEGER / TRAILER (X = -6.2 .. +3.55, Hoehe bis 3.88 m)
    pb.box((-1.32, 1.08, 0.0), (9.65, 0.22, 2.38), mats["chassis"], bevel=0.02)
    # Seiten-Unterfahrschutz (Alu-Leisten)
    for s in (-1.0, 1.0):
        for ly in (0.58, 0.82):
            pb.box((-0.15, ly, s * 1.16), (3.40, 0.10, 0.05), mats["rim"], bevel=0.008)
    # Grosser Planen-Aufbau (mit Textur-Seitenwand)
    pb.box((-1.32, 2.52, 0.0), (9.75, 2.66, 2.46), curtain_mat, uv_mode="side_x", bevel=0.03)
    pb.box((-1.32, 3.86, 0.0), (9.80, 0.09, 2.48), roof_mat, bevel=0.015)
    # Stuetzbeine (eingefahren)
    for s in (-1.0, 1.0):
        pb.box((1.35, 0.74, s * 0.88), (0.20, 0.68, 0.20), mats["chassis"], bevel=0.012)
    # Hintere Portaltueren + Stangenverschluesse + Unterfahrschutz + Ruecklichter
    pb.box((-6.20, 2.52, 0.0), (0.06, 2.62, 2.42), roof_mat, bevel=0.015)
    for rz in (-0.85, -0.35, 0.35, 0.85):
        pb.cyl((-6.24, 2.52, rz), 0.022, 0.022, 2.50, mats["chrome"], axis_g="y", seg=8)
    pb.box((-6.20, 0.62, 0.0), (0.18, 0.18, 2.36), mats["rim"], bevel=0.015)
    for s in (-1.0, 1.0):
        pb.box((-6.22, 0.96, s * 0.94), (0.10, 0.16, 0.44), mats["taillight"], bevel=0.012)
        pb.box((-6.23, 0.96, s * 0.82), (0.10, 0.14, 0.20), mats["brake"], bevel=0.01)
    pb.box((-6.24, 0.96, 0.0), (0.03, 0.12, 0.52), mats["plate"], uv_mode="front_y", bevel=0.003)

    pb.build(root)

    # 5 Achsen (Zugmaschine Front + Antriebs-Zwillingsachse + 3 Trailer-Achsen)
    w_r, w_w = 0.51, 0.31
    _build_wheel("Wheel_FL",  Vector((4.85, w_r, -1.08)), w_r, w_w, mats, root, spokes=6)
    _build_wheel("Wheel_FR",  Vector((4.85, w_r,  1.08)), w_r, w_w, mats, root, spokes=6)
    _build_wheel("Wheel_ML",  Vector((2.05, w_r, -1.00)), w_r, 0.26, mats, root, spokes=6, twin=True)
    _build_wheel("Wheel_MR",  Vector((2.05, w_r,  1.00)), w_r, 0.26, mats, root, spokes=6, twin=True)
    for idx, tx in enumerate((-2.85, -4.05, -5.25), start=1):
        _build_wheel(f"Wheel_RL{idx}", Vector((tx, w_r, -1.06)), w_r, w_w, mats, root, spokes=6)
        _build_wheel(f"Wheel_RR{idx}", Vector((tx, w_r,  1.06)), w_r, w_w, mats, root, spokes=6)

    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_car_truck.glb"))


def main():
    build_sedan()
    build_suv()
    build_trades_van()
    build_semi_truck()
    print("[VEHICLES] Alle 4 Blender-Fahrzeugmodelle erfolgreich gebaut!")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
