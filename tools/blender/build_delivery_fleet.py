"""Blender 5.2 Generator fuer die erweiterte CLOUD-LOGISTICS Lieferflotte (Stufe 2 & Stufe 3):
  - assets/models/delivery_truck_medium.glb  (Stufe 2: 7,5t Kastenwagen, 2 Mitarbeiter, Ausklapp-Rampe)
  - assets/models/delivery_truck_heavy.glb   (Stufe 3: 18t Schwerlast-LKW, 6 Raeder, 3 Logistiker, Hydraulik-Ladebordwand)

Godot-Koordinaten (g(x, y, z) -> Blender (x, -z, y)):
    +X = Vorne (Fahrtrichtung), -X = Hinten
    +Y = Oben (Boden Y = 0.0)
    -Z = Links (Garage / Entladeseite), +Z = Rechts (Strasse)
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

import pbr_textures
from build_delivery_van import (
    PartBuilder,
    _gen_dash_tex,
    _gen_eu_plate,
    _save_rgb,
    g,
    make_solid_mat,
    make_tex_mat,
)

OUT_MODELS_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models"))
CACHE_DIR = os.path.join(SCRIPT_DIR, "_pbr_cache")


def _gen_medium_livery(cache_dir: str) -> str:
    p = os.path.join(cache_dir, "truck_medium_livery.png")
    w, h = 1024, 512
    img = np.zeros((h, w, 3), dtype=np.float32)
    img[:, :] = np.array([0.94, 0.95, 0.96], dtype=np.float32)
    # Markante zweifarbige Logistik-Banderole (Tiefblau + Sicherheits-Orange)
    img[340:445, :] = np.array([0.07, 0.22, 0.46], dtype=np.float32)
    img[316:342, :] = np.array([0.94, 0.52, 0.08], dtype=np.float32)
    img[445:, :] = np.array([0.14, 0.15, 0.18], dtype=np.float32)
    # Schraege Dynamik-Streifen links
    yy, xx = np.mgrid[0:h, 0:w]
    diag = xx * 0.48 + yy
    img[(diag > 210) & (diag < 290) & (yy < 320)] = np.array([0.07, 0.22, 0.46], dtype=np.float32)
    img[(diag >= 290) & (diag < 322) & (yy < 320)] = np.array([0.94, 0.52, 0.08], dtype=np.float32)
    # Typografie
    pbr_textures.fill_rect(img, 170, 96, 870, 198, (0.06, 0.19, 0.42))
    pbr_textures.fill_rect(img, 170, 198, 870, 210, (0.94, 0.54, 0.08))
    pbr_textures.draw_text(img, 196, 122, "CLOUD LOGISTICS 7.5T", (0.97, 0.98, 1.0), scale=4)
    pbr_textures.draw_text(img, 196, 232, "TEAM EXPRESS  •  2 MANN + RAMPE", (0.12, 0.20, 0.36), scale=3)
    for sx in (256, 512, 768):
        img[16:445, sx:sx + 2] *= 0.80
    _save_rgb(p, img)
    return p


def _gen_heavy_livery(cache_dir: str) -> str:
    p = os.path.join(cache_dir, "truck_heavy_livery.png")
    w, h = 1024, 512
    img = np.zeros((h, w, 3), dtype=np.float32)
    # Edles Schwerlast-Anthrazit-Navy mit Gold/Amber-Akzenten!
    img[:, :] = np.array([0.09, 0.14, 0.24], dtype=np.float32)
    img[355:445, :] = np.array([0.94, 0.64, 0.08], dtype=np.float32)
    img[338:355, :] = np.array([0.96, 0.97, 0.99], dtype=np.float32)
    img[445:, :] = np.array([0.11, 0.12, 0.14], dtype=np.float32)
    # Diagonale Schwerlast-Warnstreifen hinten
    yy, xx = np.mgrid[0:h, 0:w]
    stripe = (((xx + yy) // 26) % 2) == 0
    mask = (xx < 150) & (yy > 355) & (yy < 445)
    img[mask & stripe] = np.array([0.10, 0.10, 0.11], dtype=np.float32)
    pbr_textures.fill_rect(img, 96, 86, 940, 198, (0.04, 0.08, 0.16))
    pbr_textures.stroke_rect(img, 96, 86, 940, 198, (0.94, 0.66, 0.10), thickness=5)
    pbr_textures.draw_text(img, 124, 114, "CLOUD HEAVY FREIGHT 18T", (0.98, 0.98, 1.0), scale=4)
    pbr_textures.draw_text(img, 128, 232, "DATACENTER CARGOLINE  •  3 LOGISTIKER", (0.94, 0.78, 0.36), scale=3)
    for sx in (205, 410, 615, 820):
        img[14:338, sx:sx + 2] *= 0.84
    _save_rgb(p, img)
    return p


def _gen_hazard_stripes(cache_dir: str) -> str:
    p = os.path.join(cache_dir, "truck_hazard_stripes.png")
    w, h = 512, 128
    img = np.zeros((h, w, 3), dtype=np.float32)
    yy, xx = np.mgrid[0:h, 0:w]
    stripe = (((xx + yy) // 32) % 2) == 0
    img[stripe] = np.array([0.95, 0.72, 0.08], dtype=np.float32)
    img[~stripe] = np.array([0.08, 0.08, 0.09], dtype=np.float32)
    _save_rgb(p, img)
    return p


def _build_heavy_wheel(name: str, center_g: Vector, radius: float, width: float, M: dict, is_left: bool):
    W = PartBuilder(name, origin_g=center_g)
    W.cyl(center_g, radius, radius, width * 0.86, M["tire"], axis_g="z", seg=32)
    W.cyl(center_g + Vector((0, 0, -width * 0.45)), radius * 0.94, radius, width * 0.12, M["tire"], axis_g="z", seg=32)
    W.cyl(center_g + Vector((0, 0, width * 0.45)), radius, radius * 0.94, width * 0.12, M["tire"], axis_g="z", seg=32)
    side = -1.0 if is_left else 1.0
    W.cyl(center_g + Vector((0, 0, side * width * 0.46)), radius * 0.62, radius * 0.62, 0.045, M["alloy"], axis_g="z", seg=26)
    W.cyl(center_g + Vector((0, 0, side * width * 0.49)), radius * 0.46, radius * 0.46, 0.032, M["dark_metal"], axis_g="z", seg=22)
    W.cyl(center_g + Vector((0, 0, side * width * 0.52)), radius * 0.22, radius * 0.22, 0.055, M["alloy"], axis_g="z", seg=18)
    # 8 LKW-Radmuttern auf dem Felgenring (deutlich sichtbare Raddrehung!)
    for k in range(8):
        ang = math.radians(k * 45.0)
        sx = math.cos(ang) * radius * 0.36
        sy = math.sin(ang) * radius * 0.36
        W.cyl(center_g + Vector((sx, sy, side * width * 0.53)), 0.024, 0.024, 0.032, M["chrome"], axis_g="z", seg=8)
    return W.build()


def _base_truck_materials(livery_path: str, cab_col, accent_col):
    return {
        "cab": make_solid_mat("Truck_CabPaint", cab_col, rough=0.20, metal=0.18, coat=0.78),
        "box_white": make_solid_mat("Truck_BoxPaint", (0.94, 0.95, 0.97), rough=0.24, metal=0.14, coat=0.55),
        "box_navy": make_solid_mat("Truck_BoxNavy", (0.08, 0.13, 0.23), rough=0.26, metal=0.20, coat=0.60),
        "accent": make_solid_mat("Truck_Accent", accent_col, rough=0.26, metal=0.16, coat=0.55),
        "livery": make_tex_mat("Truck_Livery", livery_path, rough=0.24, metal=0.14, coat=0.55),
        "hazard_tex": make_tex_mat("Truck_HazardTex", _gen_hazard_stripes(CACHE_DIR), rough=0.38, metal=0.15, coat=0.2),
        "plate": make_tex_mat("Van_Plate", _gen_eu_plate(CACHE_DIR), rough=0.28, metal=0.18, coat=0.2),
        "dash": make_tex_mat("Van_Dash", _gen_dash_tex(CACHE_DIR), rough=0.25, metal=0.0, coat=0.1, em_strength=1.4),
        "bumper": make_solid_mat("Van_Bumper", (0.09, 0.095, 0.11), rough=0.56, metal=0.08),
        "grille": make_solid_mat("Van_Grille", (0.05, 0.055, 0.065), rough=0.46, metal=0.28),
        "chrome": make_solid_mat("Van_Chrome", (0.86, 0.89, 0.92), rough=0.10, metal=0.98),
        "alloy": make_solid_mat("Van_Alloy", (0.76, 0.79, 0.83), rough=0.22, metal=0.92),
        "alu": make_solid_mat("Truck_AluPlate", (0.72, 0.75, 0.79), rough=0.34, metal=0.88),
        "dark_metal": make_solid_mat("Van_DarkMetal", (0.14, 0.15, 0.17), rough=0.46, metal=0.80),
        "tire": make_solid_mat("Van_Tire", (0.055, 0.058, 0.064), rough=0.88, metal=0.02),
        "glass": make_solid_mat("Van_Glass", (0.12, 0.22, 0.30), rough=0.06, metal=0.10, coat=0.8, alpha=0.42),
        "interior": make_solid_mat("Van_Interior", (0.14, 0.15, 0.17), rough=0.78, metal=0.02),
        "seat": make_solid_mat("Van_Seat", (0.18, 0.20, 0.24), rough=0.84, metal=0.0),
        "plywood": make_solid_mat("Van_Plywood", (0.64, 0.52, 0.36), rough=0.76, metal=0.0),
        "headlight": make_solid_mat("Van_Headlight", (0.98, 0.98, 1.0), rough=0.08, metal=0.1, emission=(0.96, 0.98, 1.0), em_strength=3.4),
        "beacon": make_solid_mat("Van_BeaconMat", (0.98, 0.62, 0.06), rough=0.15, metal=0.0, emission=(1.0, 0.56, 0.05), em_strength=2.6),
        "hazard": make_solid_mat("Van_HazardMat", (0.98, 0.56, 0.06), rough=0.20, metal=0.0, emission=(1.0, 0.52, 0.04), em_strength=1.8),
        "brake": make_solid_mat("Van_BrakeMat", (0.85, 0.06, 0.06), rough=0.18, metal=0.0, emission=(0.95, 0.08, 0.06), em_strength=1.6),
    }


# ---------------------------------------------------------------------------
# STUFE 2: 7,5t KASTENWAGEN (delivery_truck_medium.glb)
# ---------------------------------------------------------------------------

def build_medium_truck():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    M = _base_truck_materials(_gen_medium_livery(CACHE_DIR), (0.07, 0.24, 0.52), (0.94, 0.54, 0.08))

    B = PartBuilder("MediumTruck_Body")

    # 1. Schwerer Leiterrahmen-Chassis, Dieseltank & Unterfahrschutz (X = -3.65 .. +3.55)
    B.box((-0.10, 0.68, 0.0), (7.10, 0.22, 1.98), M["dark_metal"], bevel=0.015)
    B.box((-0.45, 0.54, 1.02), (1.35, 0.40, 0.36), M["alu"], bevel=0.020) # Alu-Dieseltank rechts
    B.box((-0.45, 0.52, -1.04), (1.40, 0.14, 0.08), M["alu"], bevel=0.008) # Seiten-Unterfahrschutz links
    B.box((-3.68, 0.56, 0.0), (0.18, 0.24, 2.26), M["bumper"], bevel=0.018)

    # 2. Frontlenker-Kabine (X = 1.65 .. 3.55, Y = 0.72 .. 2.70) in Royal-Blau mit Dachspoiler!
    B.box((2.62, 1.18, 0.0), (1.84, 0.90, 2.22), M["cab"], bevel=0.032)
    B.box((2.52, 2.58, 0.0), (1.76, 0.18, 2.18), M["cab"], bevel=0.036)
    # Aerodynamischer Dachspoiler ueber der Kabine glatt nach hinten zur Kofferhoehe (Y = 3.12)
    B.box((2.18, 2.84, 0.0), (1.16, 0.44, 2.16), M["cab"], rot_g_deg=(0.0, 0.0, -22.0), bevel=0.030)
    # A- & B-Saeulen + Rueckwand Kabine
    B.box((1.72, 1.95, 0.0), (0.12, 1.32, 2.18), M["cab"], bevel=0.016)
    for sz in (-1.05, 1.05):
        B.box((3.42, 2.02, sz), (0.12, 0.96, 0.10), M["cab"], rot_g_deg=(0.0, 0.0, 10.0), bevel=0.014)
        B.box((1.88, 2.02, sz), (0.18, 0.96, 0.10), M["cab"], bevel=0.014)
    # Rechte Kabinentuer (+Z geschlossen mit Fenster)
    B.box((2.62, 1.24, 1.09), (1.28, 1.04, 0.07), M["cab"], bevel=0.018)
    B.box((2.62, 2.02, 1.08), (1.16, 0.74, 0.03), M["glass"], bevel=0.004)
    B.box((2.18, 1.46, 1.14), (0.16, 0.045, 0.04), M["bumper"], bevel=0.005)
    # Grosse Panoramascheibe vorne + Scheibenwischer
    B.box((3.44, 2.04, 0.0), (0.035, 0.88, 2.02), M["glass"], rot_g_deg=(0.0, 0.0, 10.0), bevel=0.004)
    for wz in (-0.44, 0.42):
        B.box((3.52, 1.66, wz), (0.02, 0.025, 0.64), M["bumper"], bevel=0.002)

    # Frontstossstange, Kuehlergrill mit Chromstreben, LED-Scheinwerfer, Kennzeichen
    B.box((3.52, 0.66, 0.0), (0.28, 0.36, 2.24), M["bumper"], bevel=0.024)
    B.box((3.55, 1.24, 0.0), (0.08, 0.52, 1.48), M["grille"], bevel=0.012)
    for gy in (1.08, 1.24, 1.40):
        B.box((3.59, gy, 0.0), (0.025, 0.032, 1.38), M["chrome"], bevel=0.004)
    B.box((3.59, 1.56, 0.0), (0.02, 0.08, 1.62), M["accent"], bevel=0.004)
    B.box((3.665, 0.64, 0.0), (0.018, 0.14, 0.56), M["plate"], bevel=0.002, uv_mode="front_y")
    for lz in (-0.86, 0.86):
        B.box((3.55, 0.72, lz), (0.12, 0.22, 0.38), M["headlight"], bevel=0.014)
        B.box((3.56, 0.90, lz * 1.05), (0.10, 0.08, 0.24), M["hazard"], bevel=0.008)
    # Grosse LKW-Aussenspiegel + Einstiegstritte
    for sz in (-1.0, 1.0):
        B.box((3.34, 1.92, sz * 1.26), (0.12, 0.44, 0.14), M["bumper"], bevel=0.018)
        B.box((3.34, 1.82, sz * 1.15), (0.04, 0.035, 0.22), M["dark_metal"], bevel=0.004)
        B.box((3.34, 2.04, sz * 1.15), (0.04, 0.035, 0.22), M["dark_metal"], bevel=0.004)
        B.box((2.52, 0.52, sz * 1.08), (0.72, 0.05, 0.22), M["alu"], bevel=0.004)
    # 2 Dach-Rundumleuchten (Team-Delivery Warnbalken)
    for bz in (-0.52, 0.52):
        B.cyl((2.46, 2.74, bz), 0.11, 0.095, 0.16, M["beacon"], axis_g="y", seg=20)
        B.cyl((2.46, 2.66, bz), 0.13, 0.13, 0.05, M["bumper"], axis_g="y", seg=20)

    # Kabinen-Interieur (2 Sitze fuer Fahrer + Beifahrer, Armaturenbrett, Lenkrad)
    B.box((3.10, 1.46, 0.0), (0.54, 0.34, 2.02), M["interior"], bevel=0.016)
    B.box((2.86, 1.54, -0.52), (0.04, 0.16, 0.52), M["dash"], bevel=0.004, uv_mode="front_y")
    B.cyl((2.76, 1.50, -0.54), 0.028, 0.028, 0.26, M["dark_metal"], axis_g="x", seg=12)
    B.cyl((2.64, 1.54, -0.54), 0.21, 0.21, 0.04, M["bumper"], axis_g="x", seg=24)
    for sz in (-0.54, 0.54):
        B.box((2.28, 1.14, sz), (0.50, 0.14, 0.50), M["seat"], bevel=0.022)
        B.box((2.06, 1.56, sz), (0.14, 0.72, 0.48), M["seat"], rot_g_deg=(0.0, 0.0, -8.0), bevel=0.022)
        B.box((2.02, 2.02, sz), (0.11, 0.20, 0.26), M["seat"], bevel=0.016)

    # 3. Grosser Aluminium-Kofferaufbau (X = -3.62 .. +1.56, Y = 0.80 .. 3.14, Breite = 2.34 m)
    B.box((-1.03, 0.82, 0.0), (5.18, 0.08, 2.34), M["plywood"], bevel=0.006)
    B.box((-1.03, 3.12, 0.0), (5.20, 0.10, 2.36), M["box_white"], bevel=0.024)
    # Alurahmen-Kanten rund um den Koffer
    for sz in (-1.16, 1.16):
        B.box((-1.03, 3.10, sz), (5.22, 0.08, 0.06), M["alu"], bevel=0.008)
        B.box((-1.03, 0.82, sz), (5.22, 0.08, 0.06), M["alu"], bevel=0.008)
    B.box((1.52, 1.97, 0.0), (0.09, 2.26, 2.32), M["box_white"], bevel=0.012) # Stirnwand
    # Rechte Seitenwand (+Z geschlossen mit 2K CLOUD LOGISTICS 7.5T Livery)
    B.box((-1.03, 1.97, 1.15), (5.16, 2.26, 0.08), M["box_white"], bevel=0.014)
    B.box((-1.03, 1.97, 1.20), (4.98, 2.08, 0.012), M["livery"], bevel=0.0, uv_mode="side_x")
    # Linke Seitenwand (-Z) mit breiter Entlade-Oeffnung (X = -1.25 .. +0.85, Breite = 2.10 m!)
    B.box((-2.44, 1.97, -1.15), (2.36, 2.26, 0.08), M["box_white"], bevel=0.014)
    B.box((-2.44, 1.97, -1.20), (2.22, 2.08, 0.012), M["livery"], bevel=0.0, uv_mode="side_x")
    B.box((1.20, 1.97, -1.15), (0.72, 2.26, 0.08), M["box_white"], bevel=0.014)
    B.box((-0.20, 2.98, -1.15), (2.14, 0.24, 0.08), M["box_white"], bevel=0.010)
    # Innenverkleidung Koffer
    B.box((-1.03, 1.97, 1.09), (5.04, 2.14, 0.03), M["plywood"], bevel=0.004)
    B.box((-2.44, 1.97, -1.09), (2.26, 2.14, 0.03), M["plywood"], bevel=0.004)
    # Hecktueren + LED-Rueckleuchten
    B.box((-3.60, 1.97, -0.57), (0.08, 2.22, 1.12), M["box_white"], bevel=0.014)
    B.box((-3.60, 1.97, 0.57), (0.08, 2.22, 1.12), M["box_white"], bevel=0.014)
    B.box((-3.65, 1.97, 0.0), (0.014, 0.28, 2.20), M["accent"], bevel=0.0)
    B.box((-3.66, 0.88, 0.0), (0.018, 0.14, 0.54), M["plate"], bevel=0.002, uv_mode="front_y")
    for lz in (-0.96, 0.96):
        B.box((-3.68, 0.62, lz), (0.06, 0.16, 0.34), M["brake"], bevel=0.008)
        B.box((-3.68, 0.62, lz * 1.14), (0.06, 0.16, 0.12), M["hazard"], bevel=0.008)

    B.build()

    # 4. Bewegliche Seiten-Rolltuer (Side_Door, faehrt nach oben auf!)
    SD = PartBuilder("Side_Door", origin_g=Vector((-0.20, 1.88, -1.19)))
    SD.box((-0.20, 1.88, -1.19), (2.10, 2.02, 0.06), M["alu"], bevel=0.010)
    for ry in (1.10, 1.45, 1.80, 2.15, 2.50):
        SD.box((-0.20, ry, -1.225), (2.06, 0.022, 0.012), M["dark_metal"], bevel=0.002)
    SD.box((-0.20, 1.02, -1.23), (0.42, 0.05, 0.03), M["accent"], bevel=0.004)
    SD.build()

    # 5. Ausklappbare Alu-Laderampe (Side_Ramp, Scharnier bei (-0.20, 0.80, -1.18))
    # Im eingeklappten Zustand steht sie aufrecht innen/seitlich; beim Entladen klappt sie nach -Z auf den Boden!
    RP = PartBuilder("Side_Ramp", origin_g=Vector((-0.20, 0.80, -1.18)))
    RP.box((-0.20, 0.80 + 0.72, -1.18), (1.92, 1.44, 0.055), M["alu"], bevel=0.008)
    for rx in (-0.78, -0.39, 0.0, 0.39, 0.78):
        RP.box((-0.20 + rx, 0.80 + 0.72, -1.145), (0.032, 1.38, 0.014), M["dark_metal"], bevel=0.002)
    RP.box((-0.20, 0.80 + 1.40, -1.18), (1.92, 0.08, 0.065), M["hazard_tex"], bevel=0.004, uv_mode="side_x")
    RP.build()

    # 6. Bewegliche Fahrertuer links (Cab_Door_L)
    CD = PartBuilder("Cab_Door_L", origin_g=Vector((3.26, 1.24, -1.09)))
    CD.box((2.62, 1.24, -1.09), (1.28, 1.04, 0.07), M["cab"], bevel=0.018)
    CD.box((2.62, 2.02, -1.08), (1.16, 0.74, 0.03), M["glass"], bevel=0.004)
    CD.box((2.18, 1.46, -1.14), (0.16, 0.045, 0.04), M["bumper"], bevel=0.005)
    CD.build()

    # 7. 4 schwere 7,5t-LKW-Raeder (R = 0.46 m, sauber buendig sichtbar!)
    _build_heavy_wheel("Wheel_FL", Vector((2.28, 0.46, -1.08)), 0.46, 0.28, M, True)
    _build_heavy_wheel("Wheel_FR", Vector((2.28, 0.46, 1.08)), 0.46, 0.28, M, False)
    _build_heavy_wheel("Wheel_RL", Vector((-2.15, 0.46, -1.14)), 0.46, 0.34, M, True)
    _build_heavy_wheel("Wheel_RR", Vector((-2.15, 0.46, 1.14)), 0.46, 0.34, M, False)

    out_path = os.path.join(OUT_MODELS_DIR, "delivery_truck_medium.glb")
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_materials="EXPORT", export_yup=True, export_apply=True)
    print(f"EXPORTED MEDIUM TRUCK: {out_path} ({os.path.getsize(out_path)} bytes)")


# ---------------------------------------------------------------------------
# STUFE 3: 18t SCHWERLAST-LKW (delivery_truck_heavy.glb)
# ---------------------------------------------------------------------------

def build_heavy_truck():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(CACHE_DIR, exist_ok=True)
    M = _base_truck_materials(_gen_heavy_livery(CACHE_DIR), (0.08, 0.13, 0.24), (0.95, 0.66, 0.08))

    B = PartBuilder("HeavyTruck_Body")

    # 1. Schwerlast-3-Achs-Leiterrahmen, Doppel-Dieseltank, Druckluftkessel & Batteriekasten (X = -5.15 .. +4.55)
    B.box((-0.30, 0.80, 0.0), (9.55, 0.28, 2.16), M["dark_metal"], bevel=0.018)
    B.box((0.20, 0.62, 1.12), (2.10, 0.48, 0.46), M["alu"], bevel=0.026) # Grosser Alu-Tank rechts
    B.box((0.55, 0.58, -1.10), (1.35, 0.42, 0.40), M["dark_metal"], bevel=0.020) # Werkzeug-/Batteriekasten
    B.cyl((-0.90, 0.56, 1.04), 0.14, 0.14, 0.88, M["dark_metal"], axis_g="x", seg=16) # Druckluftkessel
    B.box((-5.18, 0.60, 0.0), (0.22, 0.26, 2.46), M["bumper"], bevel=0.018)

    # 2. Hohe Schwerlast-Fernverkehr-Kabine (X = 2.25 .. 4.52, Y = 0.86 .. 3.45)
    B.box((3.40, 1.46, 0.0), (2.22, 1.18, 2.40), M["cab"], bevel=0.040)
    B.box((3.30, 3.12, 0.0), (2.16, 0.26, 2.34), M["cab"], bevel=0.044)
    # Grosser aerodynamischer Dach-Windabweiser glatt nach hinten + Sonnenblende vorne
    B.box((2.82, 3.38, 0.0), (1.36, 0.40, 2.32), M["cab"], rot_g_deg=(0.0, 0.0, -16.0), bevel=0.036)
    B.box((4.48, 2.94, 0.0), (0.22, 0.18, 2.36), M["bumper"], rot_g_deg=(0.0, 0.0, -24.0), bevel=0.012)
    for cz in (-0.82, -0.32, 0.32, 0.82):
        B.box((4.57, 2.98, cz), (0.04, 0.055, 0.12), M["beacon"], bevel=0.004)
    # Vertikale Chrom-Auspuffrohre hinter der Kabine links & rechts!
    for sz in (-1.18, 1.18):
        B.cyl((2.14, 2.30, sz), 0.068, 0.068, 2.48, M["chrome"], axis_g="y", seg=18)
        B.cyl((2.14, 3.55, sz), 0.068, 0.056, 0.18, M["chrome"], axis_g="y", seg=16)

    # Kabinen-Rueckwand, Saeulen, rechte Tuer, riesige Frontscheibe
    B.box((2.32, 2.36, 0.0), (0.14, 1.56, 2.36), M["cab"], bevel=0.018)
    for sz in (-1.14, 1.14):
        B.box((4.38, 2.48, sz), (0.14, 1.06, 0.12), M["cab"], rot_g_deg=(0.0, 0.0, 8.0), bevel=0.016)
        B.box((2.50, 2.48, sz), (0.22, 1.06, 0.12), M["cab"], bevel=0.016)
    B.box((3.42, 1.54, 1.18), (1.48, 1.16, 0.08), M["cab"], bevel=0.020)
    B.box((3.42, 2.46, 1.17), (1.32, 0.82, 0.03), M["glass"], bevel=0.004)
    B.box((2.88, 1.76, 1.24), (0.18, 0.05, 0.045), M["chrome"], bevel=0.006)
    B.box((4.40, 2.48, 0.0), (0.04, 1.02, 2.20), M["glass"], rot_g_deg=(0.0, 0.0, 8.0), bevel=0.004)

    # Markanter LKW-Kuehlergrill (gestufte Chrom-Lamellen + Gold-Akzent + schwere Stossstange)
    B.box((4.50, 0.72, 0.0), (0.34, 0.44, 2.44), M["bumper"], bevel=0.028)
    B.box((4.52, 1.48, 0.0), (0.10, 0.84, 1.74), M["grille"], bevel=0.016)
    for gy in (1.18, 1.34, 1.50, 1.66, 1.82):
        B.box((4.57, gy, 0.0), (0.03, 0.036, 1.62), M["chrome"], bevel=0.005)
    B.box((4.57, 1.96, 0.0), (0.03, 0.10, 1.92), M["accent"], bevel=0.006)
    B.box((4.68, 0.70, 0.0), (0.02, 0.15, 0.58), M["plate"], bevel=0.002, uv_mode="front_y")
    for lz in (-0.94, 0.94):
        B.box((4.56, 0.78, lz), (0.14, 0.24, 0.44), M["headlight"], bevel=0.014)
        B.box((4.57, 0.98, lz * 1.04), (0.10, 0.08, 0.28), M["hazard"], bevel=0.008)

    # Doppel-Spiegel, Einstiegsleiter & Schwerlast-Rundumleuchten auf dem Dach
    for sz in (-1.0, 1.0):
        B.box((4.28, 2.34, sz * 1.40), (0.14, 0.58, 0.16), M["bumper"], bevel=0.020)
        B.box((4.28, 2.18, sz * 1.26), (0.045, 0.04, 0.26), M["chrome"], bevel=0.004)
        B.box((4.28, 2.52, sz * 1.26), (0.045, 0.04, 0.26), M["chrome"], bevel=0.004)
        # Zweistufige Einstiegsleiter
        B.box((3.24, 0.56, sz * 1.18), (0.78, 0.05, 0.22), M["alu"], bevel=0.004)
        B.box((3.24, 0.84, sz * 1.18), (0.78, 0.05, 0.20), M["alu"], bevel=0.004)
    # Breiter LED-Schwerlast-Warnbalken auf dem Kabinendach
    B.box((3.36, 3.30, 0.0), (0.28, 0.14, 1.54), M["beacon"], bevel=0.018)
    B.box((3.36, 3.30, 0.0), (0.30, 0.15, 0.36), M["bumper"], bevel=0.010)

    # Kabinen-Interieur (3 Sitze!)
    B.box((3.98, 1.80, 0.0), (0.58, 0.36, 2.18), M["interior"], bevel=0.016)
    B.box((3.72, 1.88, -0.62), (0.04, 0.18, 0.56), M["dash"], bevel=0.004, uv_mode="front_y")
    B.cyl((3.58, 1.84, -0.64), 0.030, 0.030, 0.28, M["dark_metal"], axis_g="x", seg=12)
    B.cyl((3.44, 1.90, -0.64), 0.23, 0.23, 0.045, M["bumper"], axis_g="x", seg=24)
    for sz in (-0.64, 0.0, 0.64):
        B.box((3.04, 1.44, sz), (0.50, 0.14, 0.48), M["seat"], bevel=0.020)
        B.box((2.82, 1.88, sz), (0.14, 0.74, 0.46), M["seat"], rot_g_deg=(0.0, 0.0, -6.0), bevel=0.020)

    # 3. Riesiger 7,1m Schwerlast-Frachtkoffer (X = -5.12 .. +2.02, Y = 1.04 .. 3.60, Breite = 2.50 m)
    B.box((-1.55, 1.06, 0.0), (7.14, 0.10, 2.48), M["plywood"], bevel=0.006)
    B.box((-1.55, 3.58, 0.0), (7.16, 0.12, 2.50), M["box_navy"], bevel=0.028)
    for sz in (-1.24, 1.24):
        B.box((-1.55, 3.56, sz), (7.18, 0.09, 0.07), M["alu"], bevel=0.008)
        B.box((-1.55, 1.04, sz), (7.18, 0.09, 0.07), M["alu"], bevel=0.008)
    B.box((1.98, 2.32, 0.0), (0.10, 2.48, 2.46), M["box_navy"], bevel=0.014)
    # Rechte Seitenwand (+Z geschlossen mit 2K CLOUD HEAVY FREIGHT 18T Livery)
    B.box((-1.55, 2.32, 1.23), (7.12, 2.48, 0.08), M["box_navy"], bevel=0.016)
    B.box((-1.55, 2.32, 1.285), (6.92, 2.30, 0.012), M["livery"], bevel=0.0, uv_mode="side_x")
    # Linke Seitenwand (-Z) mit breiter Schwerlast-Hubbuehnen-Oeffnung (X = -1.78 .. +0.88, Breite = 2.66 m!)
    B.box((-3.45, 2.32, -1.23), (3.34, 2.48, 0.08), M["box_navy"], bevel=0.016)
    B.box((-3.45, 2.32, -1.285), (3.18, 2.30, 0.012), M["livery"], bevel=0.0, uv_mode="side_x")
    B.box((1.45, 2.32, -1.23), (1.14, 2.48, 0.08), M["box_navy"], bevel=0.016)
    B.box((-0.45, 3.42, -1.23), (2.70, 0.26, 0.08), M["box_navy"], bevel=0.010)
    # Innenverkleidung
    B.box((-1.55, 2.32, 1.16), (6.96, 2.36, 0.03), M["plywood"], bevel=0.004)
    B.box((-3.45, 2.32, -1.16), (3.20, 2.36, 0.03), M["plywood"], bevel=0.004)
    # Hecktueren + Schwerlast-Warnstreifen + LED-Rueckleuchten
    B.box((-5.10, 2.32, -0.61), (0.09, 2.44, 1.20), M["box_navy"], bevel=0.014)
    B.box((-5.10, 2.32, 0.61), (0.09, 2.44, 1.20), M["box_navy"], bevel=0.014)
    B.box((-5.16, 1.32, 0.0), (0.016, 0.26, 2.36), M["hazard_tex"], bevel=0.0, uv_mode="front_y")
    B.box((-5.16, 0.88, 0.0), (0.018, 0.15, 0.56), M["plate"], bevel=0.002, uv_mode="front_y")
    for lz in (-1.04, 1.04):
        B.box((-5.18, 0.66, lz), (0.07, 0.18, 0.38), M["brake"], bevel=0.008)
        B.box((-5.18, 0.66, lz * 1.14), (0.07, 0.18, 0.14), M["hazard"], bevel=0.008)

    B.build()

    # 4. Bewegliche breite Seiten-Rolltuer (Side_Door, faehrt nach oben auf!)
    SD = PartBuilder("Side_Door", origin_g=Vector((-0.45, 2.24, -1.27)))
    SD.box((-0.45, 2.24, -1.27), (2.66, 2.22, 0.06), M["alu"], bevel=0.010)
    for ry in (1.30, 1.72, 2.14, 2.56, 2.98):
        SD.box((-0.45, ry, -1.308), (2.60, 0.025, 0.012), M["dark_metal"], bevel=0.002)
    SD.box((-0.45, 1.22, -1.312), (0.56, 0.06, 0.035), M["accent"], bevel=0.004)
    SD.build()

    # 5. Hydraulische Ladebordwand / Hubbuehne (Tail_Lift, faehrt an -Z vertikal herunter & klappt auf!)
    TL = PartBuilder("Tail_Lift", origin_g=Vector((-0.45, 1.04, -1.28)))
    # Plattform (2.56m breit x 1.18m tief) mit Anti-Rutsch-Riffelblech, Warnkante & Sicherheits-Gelaenderpfosten
    TL.box((-0.45, 1.04, -1.28 - 0.59), (2.56, 0.075, 1.18), M["alu"], bevel=0.008)
    TL.box((-0.45, 1.04, -1.28 - 1.17), (2.56, 0.085, 0.07), M["hazard_tex"], bevel=0.004, uv_mode="side_x")
    # 2 Hydraulik-Fuehrungssaeulen + gelbe Seiten-Abrollsicherung
    for sx in (-1.24, 1.24):
        TL.box((-0.45 + sx, 1.12, -1.28 - 0.56), (0.05, 0.14, 1.12), M["accent"], bevel=0.005)
        TL.cyl((-0.45 + sx * 0.85, 0.86, -1.28 - 0.12), 0.045, 0.045, 0.42, M["chrome"], axis_g="y", seg=14)
    TL.build()

    # 6. Bewegliche Fahrertuer links (Cab_Door_L)
    CD = PartBuilder("Cab_Door_L", origin_g=Vector((4.16, 1.54, -1.18)))
    CD.box((3.42, 1.54, -1.18), (1.48, 1.16, 0.08), M["cab"], bevel=0.020)
    CD.box((3.42, 2.46, -1.17), (1.32, 0.82, 0.03), M["glass"], bevel=0.004)
    CD.box((2.88, 1.76, -1.24), (0.18, 0.05, 0.045), M["chrome"], bevel=0.006)
    CD.build()

    # 7. 6 schwere 18t-LKW-Raeder (3 Achsen / Tandem-Hinterachse, R = 0.52 m!)
    _build_heavy_wheel("Wheel_FL", Vector((3.20, 0.52, -1.16)), 0.52, 0.32, M, True)
    _build_heavy_wheel("Wheel_FR", Vector((3.20, 0.52, 1.16)), 0.52, 0.32, M, False)
    _build_heavy_wheel("Wheel_ML", Vector((-2.25, 0.52, -1.22)), 0.52, 0.38, M, True)
    _build_heavy_wheel("Wheel_MR", Vector((-2.25, 0.52, 1.22)), 0.52, 0.38, M, False)
    _build_heavy_wheel("Wheel_RL", Vector((-3.65, 0.52, -1.22)), 0.52, 0.38, M, True)
    _build_heavy_wheel("Wheel_RR", Vector((-3.65, 0.52, 1.22)), 0.52, 0.38, M, False)

    out_path = os.path.join(OUT_MODELS_DIR, "delivery_truck_heavy.glb")
    bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_materials="EXPORT", export_yup=True, export_apply=True)
    print(f"EXPORTED HEAVY TRUCK: {out_path} ({os.path.getsize(out_path)} bytes)")


def main():
    build_medium_truck()
    build_heavy_truck()
    print("DELIVERY FLEET DONE!")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
