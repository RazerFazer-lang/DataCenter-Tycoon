"""Blender 5.2 AAA-Generator fuer alle 6 kaufbaren Einrichtungs-Items (DecorProp) & Lagerregale:
  1. assets/models/decor_storage_shelf.glb     (prop_storage_shelf — 4 echte Ablageebenen Y=0.22/0.78/1.34/1.90)
  2. assets/models/decor_esd_workbench.glb     (prop_esd_workbench — Eichenplatte, ESD-Matte, 2-Ch-Oszilloskop, Lochwand)
  3. assets/models/decor_parts_cabinet.glb     (prop_parts_cabinet — Stahlschrank mit Echtglastueren & gefuellten Sichtboxen)
  4. assets/models/decor_cold_aisle_gate.glb   (prop_cold_aisle_gate — Alu-Kaltgang-Schiebetuerportal mit Echtglasfluegeln)
  5. assets/models/decor_vending_lounge.glb    (prop_vending_lounge — Getraenkeautomat mit 3D-Dosen hinter Glas + Ficus-Pflanze)
  6. assets/models/decor_cctv_monitor.glb      (prop_cctv_monitor — Telemetrie-Stele + High-Poly 6kg-Feuerloescher)
  7. assets/models/decor_cctv_cam_head.glb     (Schwenkbarer PTZ-Sicherheitskamerakopf mit Sonnenblende & Optik)
  8. assets/models/halle_nord_stocked_shelf.glb (Voll bestuecktes Schwerlast-Werkstattregal fuer Halle Nord & Garage)
"""

import math
import os
import sys
import traceback

import bpy
import numpy as np
from mathutils import Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from build_delivery_van import PartBuilder, make_solid_mat
from build_workshop_models import _gen_pegboard_pbr, _gen_scope_screen
from hall_pbr_kit import (
    CACHE_DIR,
    OUT_MODELS_DIR,
    add_fire_extinguisher_hq,
    add_pipe_run,
    add_sculpted_leaf,
    build_glass_child,
    ensure_hall_pbr_library,
    export_glb,
    make_emissive_mat,
    make_orm_mat,
    make_real_glass_mat,
    make_screen_tex_mat,
    reset_scene,
)


# ---------------------------------------------------------------------------
# 1. Kaufbares Schwerlast-Lagerregal (prop_storage_shelf, 4 Ablageplaetze!)
# ---------------------------------------------------------------------------

def build_decor_storage_shelf(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("DecorStorageShelfRoot", None)
    bpy.context.scene.collection.objects.link(root)

    steel_anth = make_orm_mat("DSS_Steel", lib["steel_anthracite"], normal_strength=0.75)
    galv = make_orm_mat("DSS_Galv", lib["galv"], normal_strength=0.80)
    wood_oak = make_orm_mat("DSS_Oak", lib["wood_oak"], normal_strength=1.0)
    blue = make_orm_mat("DSS_Blue", lib["euro_blue"], normal_strength=0.65)
    rubber = make_orm_mat("DSS_Rubber", lib["rubber_black"], normal_strength=0.85)

    pb = PartBuilder("DecorStorageShelf", origin_g=Vector((0, 0, 0)))

    # 4 profilierte Eckpfosten mit Gummifuessen & seitlichen Fachwerkstreben (1.56 x 2.16 x 0.56 m)
    for sx in (-0.75, 0.75):
        for sz in (-0.25, 0.25):
            pb.box((sx, 0.015, sz), (0.065, 0.030, 0.065), rubber, bevel=0.004)
            pb.box((sx, 1.08, sz), (0.044, 2.12, 0.044), steel_anth, bevel=0.005)
        for ty in (0.22, 0.78, 1.34, 1.90):
            pb.box((sx, ty, 0.0), (0.028, 0.036, 0.48), galv, bevel=0.003)
        pb.box((sx, 0.50, 0.0), (0.016, 0.022, 0.54), galv, rot_g_deg=(44.0, 0.0, 0.0))
        pb.box((sx, 1.62, 0.0), (0.016, 0.022, 0.54), galv, rot_g_deg=(-44.0, 0.0, 0.0))

    # Diagonal-Kreuzverband hinten (Z = -0.26)
    pb.box((0.0, 1.08, -0.26), (0.022, 2.18, 0.010), galv, rot_g_deg=(0.0, 0.0, 34.0))
    pb.box((0.0, 1.08, -0.26), (0.022, 2.18, 0.010), galv, rot_g_deg=(0.0, 0.0, -34.0))

    # 4 Ebenen exakt auf Y = 0.22, 0.78, 1.34, 1.90 (Oberkante y + 0.018 passt exakt zu _shelf_crate_nodes!)
    for sy in (0.22, 0.78, 1.34, 1.90):
        pb.box((0.0, sy, 0.0), (1.48, 0.028, 0.50), wood_oak, bevel=0.004, uv_scale=1.2)
        pb.box((0.0, sy - 0.006,  0.262), (1.54, 0.046, 0.018), blue, bevel=0.004)
        pb.box((0.0, sy - 0.006, -0.262), (1.54, 0.046, 0.018), steel_anth, bevel=0.004)

    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "decor_storage_shelf.glb"))


# ---------------------------------------------------------------------------
# 2. Kaufbare ESD-Diagnose-Werkbank (prop_esd_workbench)
# ---------------------------------------------------------------------------

def build_decor_esd_workbench(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("DecorEsdWorkbenchRoot", None)
    bpy.context.scene.collection.objects.link(root)

    peg_maps = _gen_pegboard_pbr(CACHE_DIR)
    scope_path = _gen_scope_screen(CACHE_DIR)

    steel = make_orm_mat("DEW_Steel", lib["steel_anthracite"], normal_strength=0.75)
    ral_light = make_orm_mat("DEW_Light", lib["ral_light_grey"], normal_strength=0.70)
    alu = make_orm_mat("DEW_Alu", lib["alu_anodized"], normal_strength=0.55)
    wood_oak = make_orm_mat("DEW_Oak", lib["wood_oak"], normal_strength=1.0, coat=0.30)
    pegboard = make_orm_mat("DEW_Pegboard", peg_maps, normal_strength=1.2)
    esd_blue = make_orm_mat("DEW_EsdMat", lib["euro_blue"], normal_strength=0.55)
    red_t = make_orm_mat("DEW_Red", lib["flame_red"], normal_strength=0.6)
    yel_t = make_orm_mat("DEW_Yel", lib["safety_yellow"], normal_strength=0.6)
    rubber = make_orm_mat("DEW_Rubber", lib["rubber_black"], normal_strength=0.85)
    chrome = make_solid_mat("DEW_Chrome", (0.84, 0.86, 0.89), rough=0.14, metal=0.96)
    scope_scr = make_screen_tex_mat("DEW_ScopeScr", scope_path, em_strength=1.45)
    psu_scr = make_screen_tex_mat("DEW_PsuScr", lib["meter_screen_tex"], em_strength=1.25)
    led_bar = make_emissive_mat("DEW_Led", (0.98, 0.97, 0.94), strength=2.2)

    pb = PartBuilder("DecorEsdWorkbench", origin_g=Vector((0, 0, 0)))

    # Massives Vierkantrohr-Gestell + 50mm Eichen-Arbeitsplatte + unterer Ablageboden (1.56 x 0.80 m)
    for bx in (-0.72, 0.72):
        for bz in (-0.34, 0.34):
            pb.box((bx, 0.015, bz), (0.068, 0.030, 0.068), rubber, bevel=0.004)
            pb.box((bx, 0.42, bz), (0.052, 0.80, 0.052), steel, bevel=0.006)
        pb.box((bx, 0.22, 0.0), (0.044, 0.044, 0.66), steel, bevel=0.004)
    pb.box((0.0, 0.22, 0.0), (1.42, 0.030, 0.62), wood_oak, bevel=0.005, uv_scale=1.2)
    pb.box((0.0, 0.845, 0.0), (1.56, 0.052, 0.80), wood_oak, bevel=0.008, uv_scale=1.2)

    # Geerdete blaue ESD-Antistatikmatte mit Druckknopf & Spiralkabel
    pb.box((-0.06, 0.875, 0.06), (1.12, 0.008, 0.52), esd_blue, bevel=0.003)
    pb.cyl((-0.58, 0.882, -0.16), 0.012, 0.012, 0.006, yel_t, axis_g="y", seg=12)

    # Lochwand-Aufbau + geneigte LED-Arbeitsplatzleuchte
    for px in (-0.72, 0.72):
        pb.box((px, 1.32, -0.37), (0.044, 0.92, 0.044), steel, bevel=0.005)
    pb.box((0.0, 1.30, -0.37), (1.40, 0.74, 0.020), pegboard, bevel=0.004, uv_scale=0.8)
    pb.box((0.0, 1.70, -0.37), (1.48, 0.040, 0.050), steel, bevel=0.005)
    for ax in (-0.56, 0.56):
        add_pipe_run(pb, [(ax, 1.70, -0.37), (ax, 1.78, -0.30), (ax, 1.78, -0.12)], 0.015, alu, seg=10, bend_r=0.05)
    pb.box((0.0, 1.78, -0.14), (1.22, 0.042, 0.16), alu, rot_g_deg=(8.0, 0.0, 0.0), bevel=0.008)
    pb.box((0.0, 1.756, -0.14), (1.14, 0.014, 0.10), led_bar, rot_g_deg=(8.0, 0.0, 0.0))

    # Aufgehaengtes 3D-Werkzeug an der Lochwand (Schraubendreher, Maulschluessel, Zange)
    for si, tmat in enumerate((red_t, esd_blue, yel_t, red_t)):
        sx = -0.54 + si * 0.085
        pb.cyl((sx, 1.48, -0.345), 0.014, 0.012, 0.10, tmat, axis_g="y", seg=14)
        pb.cyl((sx, 1.36, -0.345), 0.004, 0.004, 0.14, chrome, axis_g="y", seg=10)
    for wi in range(4):
        wx = -0.10 + wi * 0.085
        wh = 0.17 + wi * 0.028
        pb.box((wx, 1.42, -0.348), (0.018, wh, 0.007), chrome, bevel=0.002)
        pb.cyl((wx, 1.42 + wh * 0.5, -0.348), 0.020, 0.020, 0.009, chrome, axis_g="z", seg=14)
        pb.cyl((wx, 1.42 - wh * 0.5, -0.348), 0.017, 0.017, 0.009, chrome, axis_g="z", seg=14)

    # 2-Kanal Digital-Speicheroszilloskop rechts (0.42, 1.00, -0.18) mit echter Wellenform-Textur & Drehreglern!
    pb.box((0.42, 0.99, -0.18), (0.36, 0.22, 0.19), ral_light, bevel=0.012)
    pb.box((0.35, 1.00, -0.082), (0.20, 0.14, 0.008), scope_scr, uv_mode="side_x")
    for ky in (1.04, 0.99, 0.94):
        for kx in (0.49, 0.54):
            pb.cyl((kx, ky, -0.080), 0.012, 0.014, 0.016, steel, axis_g="z", seg=14)
    for bx_bnc, bmat in ((0.48, yel_t), (0.54, esd_blue)):
        pb.cyl((bx_bnc, 0.90, -0.078), 0.009, 0.009, 0.020, chrome, axis_g="z", seg=12)

    # Labornetzteil links (-0.52, 0.96, -0.18) mit Messkabeln
    pb.box((-0.52, 0.955, -0.18), (0.24, 0.17, 0.22), ral_light, rot_g_deg=(0, 14.0, 0), bevel=0.010)
    pb.box((-0.52, 0.985, -0.068), (0.17, 0.065, 0.008), psu_scr, rot_g_deg=(0, 14.0, 0), uv_mode="side_x")

    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "decor_esd_workbench.glb"))


# ---------------------------------------------------------------------------
# 3. Kaufbarer Ersatzteil-Schrank (prop_parts_cabinet) MIT ECHTGLASTUEREN!
# ---------------------------------------------------------------------------

def build_decor_parts_cabinet(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("DecorPartsCabinetRoot", None)
    bpy.context.scene.collection.objects.link(root)

    dark = make_orm_mat("DPC_Dark", lib["steel_anthracite"], normal_strength=0.75)
    ral_light = make_orm_mat("DPC_Light", lib["ral_light_grey"], normal_strength=0.70)
    alu = make_orm_mat("DPC_Alu", lib["alu_anodized"], normal_strength=0.55)
    yellow = make_orm_mat("DPC_Yel", lib["safety_yellow"], normal_strength=0.65)
    blue = make_orm_mat("DPC_Blue", lib["euro_blue"], normal_strength=0.65)
    red = make_orm_mat("DPC_Red", lib["flame_red"], normal_strength=0.65)
    wood = make_orm_mat("DPC_Wood", lib["wood_pallet"], normal_strength=0.95)
    chrome = make_solid_mat("DPC_Chrome", (0.84, 0.86, 0.89), rough=0.14, metal=0.96)
    paper = make_solid_mat("DPC_Paper", (0.94, 0.94, 0.92), rough=0.80, metal=0.0)
    glass = make_real_glass_mat("DPC_Glass", rgb=(0.66, 0.80, 0.90), alpha=0.22, rough=0.04)

    pb = PartBuilder("DecorPartsCabinet", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # Aufgeschnittener Schrankkorpus (damit man durch die oberen Echtglas-Tueren ins beleuchtete Innere sieht!)
    pb.box((0.0, 0.04, 0.0), (1.12, 0.08, 0.56), dark, bevel=0.010)        # Sockel
    pb.box((0.0, 0.48, 0.0), (1.12, 0.82, 0.55), dark, bevel=0.010)        # Unterer geschlossener Teil
    pb.box((0.0, 1.46, -0.26), (1.12, 1.14, 0.04), ral_light, bevel=0.008) # Helle Rueckwand innen
    pb.box((-0.54, 1.46, 0.0), (0.04, 1.14, 0.55), dark, bevel=0.008)      # Linke Seitenwand
    pb.box(( 0.54, 1.46, 0.0), (0.04, 1.14, 0.55), dark, bevel=0.008)      # Rechte Seitenwand
    pb.box((0.0, 1.98, 0.02), (1.12, 0.14, 0.57), dark, bevel=0.010)       # Oberer Kopfsturz (Platz fuer Label3D auf Y=1.98!)

    # Untere gelbe Doppelfluegeltueren mit Stangengriff & Schlitzen
    for dx in (-0.265, 0.265):
        pb.box((dx, 0.48, 0.282), (0.50, 0.78, 0.020), yellow, bevel=0.008)
        pb.box((-0.04 if dx > 0 else 0.04, 0.50, 0.302), (0.022, 0.16, 0.020), dark, bevel=0.004)

    # 2 innere Fachboeden hinter Glas (Y = 0.92 & Y = 1.40) voll bestueckt mit Sichtlagerkaesten & Kabeltrommeln!
    pb.box((0.0, 0.91, 0.0), (1.04, 0.025, 0.50), alu, bevel=0.003)
    pb.box((0.0, 1.40, 0.0), (1.04, 0.025, 0.50), alu, bevel=0.003)

    # Ebene 1 (Y = 0.93): 4 blaue/rote Sichtlagerkaesten mit Etiketten
    for bi, bx in enumerate((-0.36, -0.12, 0.12, 0.36)):
        bmat = blue if bi % 2 == 0 else red
        pb.box((bx, 1.03, 0.02), (0.20, 0.18, 0.34), bmat, bevel=0.008)
        pb.box((bx, 1.00, 0.192), (0.12, 0.05, 0.004), paper)

    # Ebene 2 (Y = 1.42): 2 echte geflanschte Kabeltrommeln + Ersatzluefter-Kartons
    for rx, cmat in ((-0.26, yellow), (0.26, blue)):
        pb.cyl((rx - 0.11, 1.60, 0.02), 0.165, 0.165, 0.018, wood, axis_g="x", seg=22)
        pb.cyl((rx + 0.11, 1.60, 0.02), 0.165, 0.165, 0.018, wood, axis_g="x", seg=22)
        for ci in range(5):
            pb.cyl((rx - 0.08 + ci * 0.04, 1.60, 0.02), 0.135, 0.135, 0.034, cmat, axis_g="x", seg=22)
        pb.cyl((rx, 1.60, 0.02), 0.014, 0.014, 0.28, chrome, axis_g="x", seg=12)

    # Obere Alu-Rahmen-Glastueren links & rechts + Echtglasscheiben!
    for dx in (-0.265, 0.265):
        pb.box((dx - 0.23, 1.41, 0.278), (0.04, 0.96, 0.022), alu, bevel=0.004)
        pb.box((dx + 0.23, 1.41, 0.278), (0.04, 0.96, 0.022), alu, bevel=0.004)
        pb.box((dx, 1.87, 0.278), (0.50, 0.04, 0.022), alu, bevel=0.004)
        pb.box((dx, 0.95, 0.278), (0.50, 0.04, 0.022), alu, bevel=0.004)
        glass_panes.append(((dx, 1.41, 0.278), (0.42, 0.88, 0.010), glass, (0.0, 0.0, 0.0)))
    pb.box((-0.03, 1.38, 0.296), (0.016, 0.16, 0.020), chrome, bevel=0.004)
    pb.box(( 0.03, 1.38, 0.296), (0.016, 0.16, 0.020), chrome, bevel=0.004)

    pb.build(root)
    build_glass_child(root, "PartsCabinet_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "decor_parts_cabinet.glb"))


# ---------------------------------------------------------------------------
# 4. Kaufbares Kaltgang-Schiebetuer-Portal (prop_cold_aisle_gate)
# ---------------------------------------------------------------------------

def build_decor_cold_aisle_gate(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("DecorColdAisleGateRoot", None)
    bpy.context.scene.collection.objects.link(root)

    dark = make_orm_mat("DCG_Dark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("DCG_Alu", lib["alu_anodized"], normal_strength=0.55)
    rubber = make_orm_mat("DCG_Rubber", lib["rubber_black"], normal_strength=0.85)
    chrome = make_solid_mat("DCG_Chrome", (0.86, 0.88, 0.91), rough=0.12, metal=0.96)
    cyan_led = make_emissive_mat("DCG_Cyan", (0.14, 0.72, 1.0), strength=1.6)
    disp_bg = make_solid_mat("DCG_Disp", (0.04, 0.09, 0.14), rough=0.12, metal=0.08,
                             emission=(0.06, 0.16, 0.26), em_strength=0.8)
    glass = make_real_glass_mat("DCG_Glass", rgb=(0.62, 0.80, 0.92), alpha=0.20, rough=0.03)
    frost = make_real_glass_mat("DCG_Frost", rgb=(0.82, 0.90, 0.96), alpha=0.45, rough=0.30)

    pb = PartBuilder("DecorColdAisleGate", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # Seitenpfosten links & rechts bei X = +-1.05 (Mitte 1.45 m komplett frei zum Durchlaufen!)
    for sx in (-1.05, 1.05):
        pb.box((sx, 0.015, 0.0), (0.20, 0.030, 0.24), dark, bevel=0.005)
        pb.box((sx, 1.24, 0.0), (0.14, 2.44, 0.18), dark, bevel=0.012)
        pb.box((sx + (-0.075 if sx > 0 else 0.075), 1.22, 0.0), (0.025, 2.36, 0.14), alu, bevel=0.005)

    # Oberer Linearantrieb-Kopftraeger (Y = 2.48, Traeger fuer _temp_lbl auf Y=2.49, Z=0.115!)
    pb.box((0.0, 2.48, 0.0), (2.26, 0.20, 0.21), dark, bevel=0.014)
    pb.box((0.0, 2.49, 0.106), (0.76, 0.12, 0.012), disp_bg, bevel=0.004)
    pb.box((0.0, 2.375, 0.105), (2.16, 0.022, 0.018), cyan_led, bevel=0.003)

    # Halb geoeffnete Echtglas-Schiebetuerfluegel (X = +-0.76) mit Alu-Griffprofil & Edelstahl-Stossgriffen!
    for sgn in (-1.0, 1.0):
        gx = sgn * 0.76
        inner_x = sgn * 0.54
        pb.box((inner_x, 1.19, 0.0), (0.042, 2.34, 0.044), alu, bevel=0.006)
        pb.box((inner_x - sgn * 0.022, 1.19, 0.0), (0.012, 2.34, 0.020), rubber)  # Dichtlippe
        for z_side in (-1.0, 1.0):
            add_pipe_run(pb, [
                (inner_x + sgn * 0.04, 1.38, z_side * 0.022),
                (inner_x + sgn * 0.04, 1.38, z_side * 0.068),
                (inner_x + sgn * 0.04, 0.96, z_side * 0.068),
                (inner_x + sgn * 0.04, 0.96, z_side * 0.022),
            ], 0.011, chrome, seg=10, bend_r=0.02)
        glass_panes.append(((gx, 1.19, 0.0), (0.42, 2.32, 0.016), glass, (0.0, 0.0, 0.0)))
        glass_panes.append(((gx, 1.12, 0.0), (0.42, 0.18, 0.020), frost, (0.0, 0.0, 0.0)))

    pb.build(root)
    build_glass_child(root, "ColdAisleGate_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "decor_cold_aisle_gate.glb"))


# ---------------------------------------------------------------------------
# 5. Kaufbarer Getraenkeautomat & Lounge-Pflanze (prop_vending_lounge)
# ---------------------------------------------------------------------------

def build_decor_vending_lounge(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("DecorVendingLoungeRoot", None)
    bpy.context.scene.collection.objects.link(root)

    dark = make_orm_mat("DVL_Dark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("DVL_Alu", lib["alu_anodized"], normal_strength=0.55)
    red = make_orm_mat("DVL_Red", lib["flame_red"], normal_strength=0.60)
    blue = make_orm_mat("DVL_Blue", lib["euro_blue"], normal_strength=0.60)
    yellow = make_orm_mat("DVL_Yel", lib["safety_yellow"], normal_strength=0.60)
    green = make_orm_mat("DVL_Green", lib["safety_green"], normal_strength=0.65)
    pot_concrete = make_orm_mat("DVL_Pot", lib["concrete"], normal_strength=1.0)
    wood_stem = make_orm_mat("DVL_Stem", lib["wood_pallet"], normal_strength=0.9)
    soil = make_orm_mat("DVL_Soil", lib["rubber_black"], normal_strength=1.1)
    chrome = make_solid_mat("DVL_Chrome", (0.85, 0.87, 0.90), rough=0.14, metal=0.96)
    led_back = make_emissive_mat("DVL_LedBack", (0.96, 0.97, 1.0), strength=1.55)
    pay_scr = make_emissive_mat("DVL_PayScr", (0.14, 0.72, 0.98), strength=1.4)
    glass = make_real_glass_mat("DVL_Glass", rgb=(0.68, 0.82, 0.90), alpha=0.20, rough=0.03)

    pb = PartBuilder("DecorVendingLounge", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # A. Beleuchteter Glasfront-Getraenkeautomat links (X = -0.22, 0.96 x 1.96 x 0.72 m)
    vx = -0.22
    pb.box((vx, 0.03, 0.0), (0.94, 0.06, 0.70), dark, bevel=0.008)
    # Korpus mit offenem beleuchtetem Schaufenster-Fach vorne links!
    pb.box((vx, 1.00, -0.18), (0.96, 1.88, 0.36), dark, bevel=0.018)
    pb.box((vx - 0.44, 1.00, 0.18), (0.08, 1.88, 0.36), dark, bevel=0.012)
    pb.box((vx + 0.30, 1.00, 0.18), (0.36, 1.88, 0.36), dark, bevel=0.014)  # Rechtes Bedienpanel
    pb.box((vx - 0.14, 1.80, 0.18), (0.60, 0.28, 0.36), dark, bevel=0.012)
    pb.box((vx - 0.14, 0.28, 0.18), (0.60, 0.44, 0.36), dark, bevel=0.012)
    # Beleuchtete Innenrueckwand + 5 Getraenke-Etagen voller bunter 3D-Getraenkedosen!
    pb.box((vx - 0.14, 1.08, 0.02), (0.54, 1.14, 0.015), led_back)
    can_mats = (red, blue, yellow, green, chrome)
    for r_i, sy in enumerate((0.62, 0.84, 1.06, 1.28, 1.50)):
        pb.box((vx - 0.14, sy, 0.16), (0.52, 0.016, 0.26), alu, bevel=0.002)
        for c_i in range(5):
            cx = vx - 0.34 + c_i * 0.10
            cmat = can_mats[(r_i + c_i) % len(can_mats)]
            pb.cyl((cx, sy + 0.068, 0.20), 0.031, 0.031, 0.115, cmat, axis_g="y", seg=16)
            pb.cyl((cx, sy + 0.127, 0.20), 0.028, 0.031, 0.006, chrome, axis_g="y", seg=16)

    # Echtglas-Sichtscheibe + NFC-Kartenleser + Entnahmeklappe unten
    pb.box((vx, 1.84, 0.366), (0.90, 0.14, 0.018), red, bevel=0.006)
    glass_panes.append(((vx - 0.14, 1.08, 0.352), (0.54, 1.14, 0.012), glass, (0.0, 0.0, 0.0)))
    pb.box((vx + 0.30, 1.32, 0.368), (0.18, 0.26, 0.018), alu, bevel=0.006)
    pb.box((vx + 0.30, 1.36, 0.378), (0.12, 0.10, 0.008), pay_scr)
    pb.box((vx - 0.14, 0.28, 0.366), (0.50, 0.22, 0.022), alu, bevel=0.008)
    pb.box((vx - 0.14, 0.28, 0.355), (0.44, 0.16, 0.016), dark, rot_g_deg=(14.0, 0.0, 0.0), bevel=0.004)

    # B. Runde konische Designer-Pflanzschale + echte vielblaettrige Zimmerpflanze (0 % Kugel-Kloetze!)
    px, pz = 0.55, 0.04
    pb.cyl((px, 0.23, pz), 0.19, 0.145, 0.46, pot_concrete, axis_g="y", seg=28)
    pb.cyl((px, 0.455, pz), 0.20, 0.195, 0.03, pot_concrete, axis_g="y", seg=28)
    pb.cyl((px, 0.44, pz), 0.175, 0.175, 0.02, soil, axis_g="y", seg=24)
    # 3 verholzte verzweigte Pflanzenstaemme + 26 echte organisch gewoelbte Ficus/Dracaena-Blaetter!
    leaf_dark = make_solid_mat("DVL_LeafDark", (0.10, 0.34, 0.15), rough=0.42, metal=0.0, coat=0.25)
    leaf_lush = make_solid_mat("DVL_LeafLush", (0.16, 0.48, 0.20), rough=0.38, metal=0.0, coat=0.30)
    stems = (
        (-0.05, 1.06,  0.02, [(px, 0.44, pz), (px - 0.03, 0.74, pz + 0.02), (px - 0.05, 1.06, pz + 0.02)]),
        ( 0.06, 0.94, -0.03, [(px, 0.44, pz), (px + 0.04, 0.68, pz - 0.02), (px + 0.06, 0.94, pz - 0.03)]),
        ( 0.01, 0.80,  0.06, [(px, 0.44, pz), (px + 0.01, 0.62, pz + 0.04), (px + 0.01, 0.80, pz + 0.06)]),
    )
    for sx_top, sy_top, sz_top, st_pts in stems:
        add_pipe_run(pb, st_pts, 0.013, wood_stem, seg=10, bend_r=0.08)
        for li in range(9):
            yaw_l = li * 137.5 + sy_top * 90.0
            by = sy_top - 0.24 + (li / 8.0) * 0.28
            pitch_l = -28.0 + (li / 8.0) * 42.0
            lmat = leaf_lush if (li % 2 == 0) else leaf_dark
            add_sculpted_leaf(pb, (px + sx_top * (by / sy_top), by, pz + sz_top * (by / sy_top)),
                              yaw_deg=yaw_l, pitch_deg=pitch_l, length=0.24 - li * 0.006, width=0.085, arch=0.045, leaf_mat=lmat)

    pb.build(root)
    build_glass_child(root, "Vending_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "decor_vending_lounge.glb"))


# ---------------------------------------------------------------------------
# 6. Kaufbare CCTV- & Temperatur-Stele + separater PTZ-Kamerakopf
# ---------------------------------------------------------------------------

def build_decor_cctv(lib: dict):
    # A. Stele mit 27"-Hochformat-Display & seitlichem 6kg-Feuerloescher
    reset_scene()
    root = bpy.data.objects.new("DecorCctvRoot", None)
    bpy.context.scene.collection.objects.link(root)

    dark = make_orm_mat("DCC_Dark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("DCC_Alu", lib["alu_anodized"], normal_strength=0.55)
    red = make_orm_mat("DCC_Red", lib["flame_red"], normal_strength=0.65)
    rubber = make_orm_mat("DCC_Rubber", lib["rubber_black"], normal_strength=0.85)
    chrome = make_solid_mat("DCC_Chrome", (0.85, 0.87, 0.90), rough=0.14, metal=0.96)
    paper = make_solid_mat("DCC_Paper", (0.94, 0.94, 0.92), rough=0.80, metal=0.0)
    scr_bg = make_solid_mat("DCC_Scr", (0.04, 0.11, 0.18), rough=0.10, metal=0.08,
                            emission=(0.06, 0.22, 0.36), em_strength=0.95)
    green_led = make_emissive_mat("DCC_Led", (0.14, 0.95, 0.44), strength=1.8)

    pb = PartBuilder("DecorCctv", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.03, 0.0), (0.64, 0.06, 0.48), dark, bevel=0.012)
    for bx in (-0.26, 0.26):
        for bz in (-0.18, 0.18):
            pb.cyl((bx, 0.066, bz), 0.012, 0.012, 0.014, chrome, axis_g="y", seg=6)
    pb.box((0.0, 1.18, 0.0), (0.46, 2.24, 0.20), dark, bevel=0.020)
    for sx in (-0.24, 0.24):
        pb.box((sx, 1.18, 0.0), (0.032, 2.22, 0.22), alu, bevel=0.010)
    # 27"-Portrait-Monitorrahmen (kompatibel mit _temp_lbl auf Y=1.56, Z=0.138!)
    pb.box((0.0, 1.52, 0.112), (0.40, 0.58, 0.024), alu, bevel=0.010)
    pb.box((0.0, 1.52, 0.126), (0.36, 0.54, 0.008), scr_bg, bevel=0.003)
    pb.cyl((0.0, 1.86, 0.112), 0.014, 0.014, 0.012, green_led, axis_g="z", seg=14)
    # Kameramast oben bis exakt (0.0, 2.38, 0.06) fuer _cctv_cam!
    add_pipe_run(pb, [(0.0, 2.30, 0.0), (0.0, 2.38, 0.0), (0.0, 2.38, 0.06)], 0.024, alu, seg=14, bend_r=0.04)

    # Seitlicher Wandhalter + High-Poly 6kg ABC-Feuerloescher bei X = +0.34!
    pb.box((0.26, 0.58, 0.0), (0.06, 0.24, 0.08), alu, bevel=0.004)
    add_fire_extinguisher_hq(pb, (0.35, 0.30, 0.0), red, chrome, rubber, paper)

    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "decor_cctv_monitor.glb"))

    # B. Schwenkbarer PTZ-Sicherheitskamerakopf (decor_cctv_cam_head.glb)
    reset_scene()
    root = bpy.data.objects.new("DecorCctvCamHeadRoot", None)
    bpy.context.scene.collection.objects.link(root)
    alu = make_orm_mat("CAM_Alu", lib["alu_anodized"], normal_strength=0.55)
    dark = make_orm_mat("CAM_Dark", lib["steel_anthracite"], normal_strength=0.75)
    lens_mat = make_solid_mat("CAM_Lens", (0.02, 0.05, 0.10), rough=0.03, metal=0.35, coat=0.98)
    rec_led = make_emissive_mat("CAM_RecLed", (0.16, 0.96, 0.44), strength=2.2)
    ir_led = make_emissive_mat("CAM_IrLed", (0.85, 0.12, 0.14), strength=0.9)

    pb = PartBuilder("DecorCctvCamHead", origin_g=Vector((0, 0, 0)))
    pb.cyl((0.0, 0.0, 0.0), 0.028, 0.028, 0.06, dark, axis_g="y", seg=16)
    pb.cyl((0.0, 0.01, 0.11), 0.052, 0.048, 0.22, alu, axis_g="z", seg=24)
    # Obere Wetterschutz-Sonnenblende
    pb.box((0.0, 0.062, 0.12), (0.115, 0.014, 0.25), alu, bevel=0.005)
    # Schwarzer Objektivring + verguetete Glaslinse + IR-LED-Kranz + gruene Status-LED
    pb.cyl((0.0, 0.01, 0.222), 0.048, 0.050, 0.018, dark, axis_g="z", seg=24)
    pb.cyl((0.0, 0.01, 0.232), 0.030, 0.030, 0.008, lens_mat, axis_g="z", seg=22)
    for k in range(8):
        a = (k / 8.0) * math.pi * 2.0
        pb.cyl((math.cos(a) * 0.039, 0.01 + math.sin(a) * 0.039, 0.232), 0.0035, 0.0035, 0.005, ir_led, axis_g="z", seg=8)
    pb.cyl((0.0, 0.046, 0.232), 0.006, 0.006, 0.006, rec_led, axis_g="z", seg=10)
    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "decor_cctv_cam_head.glb"))


# ---------------------------------------------------------------------------
# 7. Voll bestuecktes Schwerlast-Werkstattregal (fuer Halle Nord & BuildingPropFactory!)
# ---------------------------------------------------------------------------

def build_halle_nord_stocked_shelf(lib: dict):
    """Orientiert entlang Z (0.56 x 2.14 x 1.56 m), exakt passend als 1:1 Drop-in fuer build_heavy_workshop_shelf()!"""
    reset_scene()
    root = bpy.data.objects.new("StockedShelfRoot", None)
    bpy.context.scene.collection.objects.link(root)

    steel = make_orm_mat("SS_Steel", lib["steel_anthracite"], normal_strength=0.75)
    galv = make_orm_mat("SS_Galv", lib["galv"], normal_strength=0.80)
    wood = make_orm_mat("SS_Wood", lib["wood_oak"], normal_strength=1.0)
    card = make_orm_mat("SS_Card", lib["cardboard"], normal_strength=1.15)
    red = make_orm_mat("SS_Red", lib["flame_red"], normal_strength=0.65)
    blue = make_orm_mat("SS_Blue", lib["euro_blue"], normal_strength=0.65)
    yel = make_orm_mat("SS_Yel", lib["safety_yellow"], normal_strength=0.65)
    rubber = make_orm_mat("SS_Rubber", lib["rubber_black"], normal_strength=0.85)
    chrome = make_solid_mat("SS_Chrome", (0.84, 0.86, 0.89), rough=0.14, metal=0.96)
    paper = make_solid_mat("SS_Paper", (0.94, 0.93, 0.90), rough=0.80, metal=0.0)

    pb = PartBuilder("StockedShelf", origin_g=Vector((0, 0, 0)))

    for sx in (-0.26, 0.26):
        for sz in (-0.76, 0.76):
            pb.box((sx, 0.015, sz), (0.06, 0.03, 0.06), rubber, bevel=0.004)
            pb.box((sx, 1.08, sz), (0.042, 2.12, 0.042), steel, bevel=0.005)
    for sz in (-0.76, 0.76):
        for ty in (0.22, 0.82, 1.42, 2.02):
            pb.box((0.0, ty, sz), (0.52, 0.032, 0.024), galv, bevel=0.003)
    pb.box((-0.265, 1.12, 0.0), (0.010, 0.022, 2.04), galv, rot_g_deg=(45.0, 0.0, 0.0))
    pb.box((-0.265, 1.12, 0.0), (0.010, 0.022, 2.04), galv, rot_g_deg=(-45.0, 0.0, 0.0))

    for sy in (0.22, 0.82, 1.42, 2.02):
        pb.box((0.0, sy + 0.008, 0.0), (0.50, 0.024, 1.50), wood, bevel=0.004, uv_scale=1.2)
        pb.box(( 0.26, sy, 0.0), (0.016, 0.044, 1.54), blue, bevel=0.004)
        pb.box((-0.26, sy, 0.0), (0.016, 0.044, 1.54), steel, bevel=0.004)

    # Ebene 1 (Y=0.24): Umreifte Versandkartons & 1U-Ersatz-Servergehaeuse
    for cz, rot_y in ((-0.38, 4.0), (0.34, -3.0)):
        pb.box((0.0, 0.38, cz), (0.42, 0.26, 0.52), card, rot_g_deg=(0, rot_y, 0), bevel=0.008)
        pb.box((0.0, 0.38, cz - 0.14), (0.43, 0.27, 0.014), rubber, rot_g_deg=(0, rot_y, 0))
        pb.box((0.0, 0.38, cz + 0.14), (0.43, 0.27, 0.014), rubber, rot_g_deg=(0, rot_y, 0))
        pb.box((0.214, 0.40, cz), (0.004, 0.11, 0.17), paper, rot_g_deg=(0, rot_y, 0))

    # Ebene 2 (Y=0.84): Roter Metall-Werkzeugkasten mit Rundgriff + 3 echte hohle Sichtlagerkaesten!
    pb.box((0.02, 0.96, -0.42), (0.30, 0.22, 0.48), red, bevel=0.012)
    pb.box((0.02, 1.08, -0.42), (0.31, 0.035, 0.49), red, bevel=0.008)
    add_pipe_run(pb, [(0.02, 1.09, -0.52), (0.02, 1.14, -0.52), (0.02, 1.14, -0.32), (0.02, 1.09, -0.32)], 0.010, rubber, seg=10, bend_r=0.02)
    for b_i, bz in enumerate((0.04, 0.32, 0.60)):
        bmat = blue if b_i < 2 else yel
        pb.box((0.02, 0.855, bz), (0.34, 0.018, 0.22), bmat, bevel=0.004)
        pb.box((-0.14, 0.935, bz), (0.020, 0.17, 0.22), bmat, bevel=0.004)
        pb.box((0.02, 0.935, bz - 0.10), (0.34, 0.17, 0.020), bmat, bevel=0.004)
        pb.box((0.02, 0.935, bz + 0.10), (0.34, 0.17, 0.020), bmat, bevel=0.004)
        pb.box((0.18, 0.895, bz), (0.020, 0.09, 0.22), bmat, bevel=0.004)
        pb.box((0.192, 0.895, bz), (0.004, 0.045, 0.11), paper)

    # Ebene 3 (Y=1.44): 2 geflanschte Kabeltrommeln auf Stahlwelle + Druckluftspray
    pb.cyl((0.0, 1.66, -0.18), 0.014, 0.014, 0.86, chrome, axis_g="z", seg=14)
    for rz, cmat in ((-0.40, yel), (0.04, blue)):
        pb.cyl((0.0, 1.66, rz - 0.11), 0.175, 0.175, 0.016, rubber, axis_g="z", seg=22)
        pb.cyl((0.0, 1.66, rz + 0.11), 0.175, 0.175, 0.016, rubber, axis_g="z", seg=22)
        for ti in range(5):
            pb.cyl((0.0, 1.66, rz - 0.08 + ti * 0.04), 0.142, 0.142, 0.034, cmat, axis_g="z", seg=22)
    pb.cyl((0.08, 1.55, 0.46), 0.035, 0.035, 0.21, blue, axis_g="y", seg=18)
    pb.cyl((0.08, 1.665, 0.46), 0.030, 0.034, 0.02, chrome, axis_g="y", seg=18)

    # Ebene 4 (Y=2.04): Ersatzteil-Karton & gestapelte 3.5"-Laufwerks-Caddies
    pb.box((0.0, 2.15, -0.34), (0.40, 0.21, 0.50), card, bevel=0.008)
    for hd in range(4):
        pb.box((0.02, 2.06 + hd * 0.038, 0.36), (0.18, 0.028, 0.26), galv, bevel=0.004)

    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "halle_nord_stocked_shelf.glb"))


def main():
    lib = ensure_hall_pbr_library()
    build_decor_storage_shelf(lib)
    build_decor_esd_workbench(lib)
    build_decor_parts_cabinet(lib)
    build_decor_cold_aisle_gate(lib)
    build_decor_vending_lounge(lib)
    build_decor_cctv(lib)
    build_halle_nord_stocked_shelf(lib)
    print("[DECOR_PROPS] Alle 8 High-Poly 2K-ORM-PBR Shop-Dekos & Regale erfolgreich gebaut!")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
