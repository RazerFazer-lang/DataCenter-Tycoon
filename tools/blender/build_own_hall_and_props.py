"""Blender 5.2 AAA-Generator fuer die eigene Start-Halle (Garage + Halle B + Halle C) & Wand-Technik:
  - assets/models/own_hall_exterior.glb        (Aussenfassade MIT echten durchgebrochenen Oberlicht-Oeffnungen!)
  - assets/models/own_hall_interior.glb        (Kompletter 2K-ORM-PBR Innenausbau fuer Garage + Halle B + C:
                                                2K-Epoxidboden, Sichtbeton-Sockel, Sandwichpaneele, echte
                                                Glas-Oberlichter, 3D-Trapezblechdach, HEB-Stahlrahmen, Wickelfalz-HVAC,
                                                Kabelpritschen, Sprinkler, 3D-Torsionsfedern & Werkstatt-Treteimer)
  - assets/models/garage_door_panel_solid.glb  (High-Poly Sektionaltor-Paneel geschlossen mit Sicken & Laufrollen)
  - assets/models/garage_door_panel_window.glb (High-Poly Sektionaltor-Paneel mit 4 echten Glas-Sichtfenstern)
  - assets/models/hall_c_subpanel_power.glb    (High-Poly Halle-C 400V-Unterverteilerkasten)
  - assets/models/hall_c_subpanel_fiber.glb    (High-Poly Halle-C 10G-Glasfaser-Wandverteiler)
  - assets/models/garage_shuttle_wall.glb      (High-Poly Alu-Touchscreen-Wandterminal fuer Standort-Shuttle)
  - assets/models/prop_coffee_machine.glb      (Edelstahl/Schwarz-Kaffeevollautomat auf Eichen-Beistelltisch)
  - assets/models/prop_whiteboard.glb          (Eloxiertes Alu-Magnet-Whiteboard mit Stiften & Wischer)
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
from build_exterior_world import ensure_exterior_textures, make_pbr_tex_mat
from hall_pbr_kit import (
    OUT_MODELS_DIR,
    add_heb_beam_z,
    add_heb_column,
    add_pipe_run,
    add_spoked_valve,
    add_torsion_spring_x,
    add_trapezoidal_deck,
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
# 1. AUSSENFASSADE (Garage + Halle B + C) MIT ECHTEN FENSTER-DURCHBRUECHEN!
# ---------------------------------------------------------------------------

def build_own_hall_exterior(tex: dict, lib: dict):
    reset_scene()
    root = bpy.data.objects.new("OwnHallExteriorRoot", None)
    bpy.context.scene.collection.objects.link(root)

    clinker = make_pbr_tex_mat("Own_Clinker", *tex["clinker"], rough=0.84, metal=0.0, normal_strength=1.1)
    trapez = make_pbr_tex_mat("Own_Trapez", *tex["trapez"], rough=0.44, metal=0.45, normal_strength=1.15)
    concrete = make_orm_mat("Own_Concrete2K", lib["concrete"], normal_strength=1.0)
    steel_dark = make_orm_mat("Own_SteelDark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("Own_Alu", lib["alu_anodized"], normal_strength=0.55)
    galv = make_orm_mat("Own_Galv", lib["galv"], normal_strength=0.80)
    rubber = make_orm_mat("Own_Rubber", lib["rubber_black"], normal_strength=0.85)
    amber = make_orm_mat("Own_Amber", lib["safety_yellow"], normal_strength=0.65)
    copper = make_solid_mat("Own_Copper", (0.74, 0.43, 0.22), rough=0.30, metal=0.90)
    lamp_glow = make_emissive_mat("Own_LampGlow", (1.0, 0.94, 0.80), strength=0.95)
    glass_canopy = make_real_glass_mat("Own_CanopyGlass", rgb=(0.16, 0.26, 0.36), alpha=0.28, rough=0.05)

    pb = PartBuilder("OwnHallExterior", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # A. SUEDFASSADE (Z = +4.77)
    # Klinker-Sockel Y=0..1.32 + Tropfkante
    pb.box((-4.00, 0.66, 4.77), (3.56, 1.32, 0.10), clinker, bevel=0.015, uv_scale=1.9)
    pb.box((12.00, 0.66, 4.77), (19.56, 1.32, 0.10), clinker, bevel=0.015, uv_scale=1.9)
    pb.box((-4.00, 1.34, 4.81), (3.58, 0.07, 0.16), concrete, bevel=0.01, uv_scale=1.8)
    pb.box((12.00, 1.34, 4.81), (19.58, 0.07, 0.16), concrete, bevel=0.01, uv_scale=1.8)

    # Trapezblech MIT ECHTEN FENSTER-AUSSCHNITTEN in Halle B & C bei wx = (8.8, 15.2, 18.8), Breite 2.60, Y=2.52..3.24!
    pb.box((-4.00, 2.70, 4.77), (3.56, 2.66, 0.09), trapez, bevel=0.012, uv_scale=1.8)
    pb.box(( 0.00, 3.52, 4.77), (4.48, 1.02, 0.09), trapez, bevel=0.012, uv_scale=1.8)
    # Unterer Streifen (Y=1.37..2.52) & oberer Streifen (Y=3.24..4.03) rechts vom Tor
    pb.box((12.00, 1.945, 4.77), (19.56, 1.15, 0.09), trapez, bevel=0.010, uv_scale=1.8)
    pb.box((12.00, 3.635, 4.77), (19.56, 0.79, 0.09), trapez, bevel=0.010, uv_scale=1.8)
    # Pfeiler zwischen den 3 Sued-Oberlichtern (2.22..7.50, 10.10..13.90, 16.50..17.50, 20.10..21.78)
    for x0, x1 in ((2.22, 7.50), (10.10, 13.90), (16.50, 17.50), (20.10, 21.78)):
        pb.box(((x0 + x1) * 0.5, 2.88, 4.77), (x1 - x0, 0.74, 0.09), trapez, bevel=0.008, uv_scale=1.8)
    for wx in (8.8, 15.2, 18.8):
        pb.box((wx, 2.50, 4.85), (2.72, 0.05, 0.14), alu, bevel=0.005)  # Aeussere Alu-Fensterbank

    # B. WEST- & OSTFASSADE (X = -5.77 & +21.77) MIT ECHTEN OBERLICHT-AUSSCHNITTEN (Z=-3.20..+3.20, Y=2.68..3.36)!
    for wx, sgn in ((-5.77, -1.0), (21.77, 1.0)):
        pb.box((wx, 0.66, 0.0), (0.10, 1.32, 9.64), clinker, bevel=0.015, uv_scale=1.9)
        pb.box((wx + sgn * 0.03, 1.34, 0.0), (0.16, 0.07, 9.66), concrete, bevel=0.01, uv_scale=1.8)
        pb.box((wx, 2.025, 0.0), (0.09, 1.31, 9.64), trapez, bevel=0.010, uv_scale=1.8)
        pb.box((wx, 3.695, 0.0), (0.09, 0.67, 9.64), trapez, bevel=0.010, uv_scale=1.8)
        for z0, z1 in ((-4.82, -3.20), (3.20, 4.82)):
            pb.box((wx, 3.02, (z0 + z1) * 0.5), (0.09, 0.70, z1 - z0), trapez, bevel=0.008, uv_scale=1.8)
        pb.box((wx + sgn * 0.06, 2.66, 0.0), (0.14, 0.05, 6.52), alu, bevel=0.005)

    # C. NORDFASSADE (Z = -4.77)
    pb.box((8.00, 0.66, -4.77), (27.64, 1.32, 0.10), clinker, bevel=0.015, uv_scale=1.9)
    pb.box((8.00, 2.70, -4.77), (27.64, 2.66, 0.09), trapez, bevel=0.012, uv_scale=1.8)

    # Vertikale Stahl-Lisenen, Attika, Regenrinne & 4 gebogene Fallrohre
    for px in (-5.78, -2.26, 2.26, 5.50, 12.50, 21.78):
        pb.box((px, 2.04, 4.82), (0.18, 4.08, 0.14), steel_dark, bevel=0.012)
    for cx in (-5.78, 21.78):
        pb.box((cx, 2.04, -4.78), (0.20, 4.08, 0.20), steel_dark, bevel=0.012)

    pb.box((8.00, 4.18, 0.0), (27.95, 0.34, 9.95), steel_dark, bevel=0.025)
    pb.box((8.00, 4.36, 0.0), (28.05, 0.07, 10.05), alu, bevel=0.012)
    for sz in (4.98, -4.98):
        pb.cyl((8.00, 4.00, sz), 0.075, 0.075, 27.9, galv, axis_g="x", seg=16)
    for dx, dz in ((-5.60, 4.92), (5.38, 4.92), (21.60, 4.92), (-5.60, -4.92)):
        out_z = 0.16 if dz > 0 else -0.16
        add_pipe_run(pb, [(dx, 3.96, dz), (dx, 0.22, dz), (dx, 0.10, dz + out_z)], 0.052, galv, seg=14, bend_r=0.09)

    # Garagentor-Portal, Echtglas-Vordach & Aussen-Rueckkuehler an Halle B/C
    for s in (-1.0, 1.0):
        pb.box((s * 2.24, 1.50, 4.82), (0.12, 3.04, 0.16), steel_dark, bevel=0.01)
        pb.box((s * 2.18, 1.50, 4.74), (0.05, 3.00, 0.08), rubber, bevel=0.005)
        pb.cyl((s * 2.42, 0.52, 4.95), 0.088, 0.088, 1.04, amber, axis_g="y", seg=20)
        pb.cyl((s * 2.42, 0.82, 4.95), 0.091, 0.091, 0.12, rubber, axis_g="y", seg=20)
        pb.cyl((s * 2.42, 0.38, 4.95), 0.091, 0.091, 0.12, rubber, axis_g="y", seg=20)
    pb.box((0.0, 3.04, 4.82), (4.60, 0.14, 0.18), steel_dark, bevel=0.012)
    pb.box((0.0, 3.22, 5.42), (4.85, 0.10, 1.28), steel_dark, rot_g_deg=(5.0, 0.0, 0.0), bevel=0.015)
    glass_panes.append(((0.0, 3.26, 5.44), (4.45, 0.035, 1.06), glass_canopy, (5.0, 0.0, 0.0)))
    for sx in (-2.10, 2.10):
        pb.cyl((sx, 3.55, 5.40), 0.020, 0.020, 1.25, alu, axis_g="z", seg=12)
    for lx in (-1.35, 1.35):
        pb.box((lx, 3.14, 5.42), (0.48, 0.04, 0.18), lamp_glow, bevel=0.006)
    for lx in (-3.85, 7.2, 14.5):
        pb.box((lx, 2.85, 4.86), (0.34, 0.16, 0.16), steel_dark, bevel=0.015)
        pb.box((lx, 2.82, 4.92), (0.26, 0.09, 0.06), lamp_glow, bevel=0.006)

    pb.box((0.0, 3.68, 4.84), (4.10, 0.56, 0.06), steel_dark, bevel=0.012)
    for cx in (11.4, 17.6):
        pb.box((cx, 0.12, 5.32), (1.85, 0.24, 0.92), concrete, bevel=0.015, uv_scale=1.8)
        pb.box((cx, 0.94, 5.32), (1.65, 1.40, 0.72), galv, bevel=0.025)
        pb.box((cx, 1.66, 5.32), (1.70, 0.06, 0.76), steel_dark, bevel=0.01)
        for fx in (-0.42, 0.42):
            pb.cyl((cx + fx, 0.96, 5.69), 0.34, 0.34, 0.05, steel_dark, axis_g="z", seg=22)
            pb.cyl((cx + fx, 0.96, 5.71), 0.29, 0.29, 0.03, rubber, axis_g="z", seg=20)
            for b_ang in (0, 60, 120):
                pb.box((cx + fx, 0.96, 5.72), (0.56, 0.045, 0.02), alu, rot_g_deg=(0, 0, float(b_ang)), bevel=0.003)
        for py in (0.48, 0.62):
            add_pipe_run(pb, [(cx + 0.65, py, 5.10), (cx + 0.65, py, 4.72)], 0.028, copper, seg=12)

    pb.box((-3.85, 1.48, 4.86), (0.64, 0.78, 0.22), galv, bevel=0.015)
    pb.box((-3.85, 1.48, 4.98), (0.56, 0.70, 0.02), steel_dark, bevel=0.004)
    pb.box((2.58, 1.32, 4.86), (0.14, 0.24, 0.09), steel_dark, bevel=0.008)
    pb.box((2.58, 1.36, 4.91), (0.05, 0.05, 0.02), amber, bevel=0.003)

    pb.build(root)
    build_glass_child(root, "OwnHallExterior_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "own_hall_exterior.glb"))


# ---------------------------------------------------------------------------
# 2. KOMPLETTER 2K-ORM-PBR INNENAUSBAU FUER START-GARAGE + HALLE B + HALLE C!
# ---------------------------------------------------------------------------

def build_own_hall_interior(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("OwnHallInteriorRoot", None)
    bpy.context.scene.collection.objects.link(root)

    epoxy_floor = make_orm_mat("OHI_EpoxyFloor2K", lib["epoxy_floor"], normal_strength=1.15, coat=0.34, coat_rough=0.18)
    sandwich_wall = make_orm_mat("OHI_SandwichWall2K", lib["sandwich_wall"], normal_strength=1.05)
    concrete_dado = make_orm_mat("OHI_ConcreteDado2K", lib["concrete"], normal_strength=1.12)
    treadplate = make_orm_mat("OHI_Treadplate1K", lib["treadplate"], normal_strength=1.35)
    galv = make_orm_mat("OHI_Galv1K", lib["galv"], normal_strength=0.85)
    steel_anth = make_orm_mat("OHI_SteelAnth", lib["steel_anthracite"], normal_strength=0.75)
    steel_grey = make_orm_mat("OHI_SteelGrey", lib["steel_grey"], normal_strength=0.75)
    ral_light = make_orm_mat("OHI_RalLight", lib["ral_light_grey"], normal_strength=0.70)
    alu = make_orm_mat("OHI_Alu", lib["alu_anodized"], normal_strength=0.55)
    safety_yel = make_orm_mat("OHI_Yellow", lib["safety_yellow"], normal_strength=0.65)
    flame_red = make_orm_mat("OHI_Red", lib["flame_red"], normal_strength=0.65)
    euro_blue = make_orm_mat("OHI_Blue", lib["euro_blue"], normal_strength=0.65)
    safety_grn = make_orm_mat("OHI_Green", lib["safety_green"], normal_strength=0.65)
    rubber = make_orm_mat("OHI_Rubber", lib["rubber_black"], normal_strength=0.88)
    chrome = make_solid_mat("OHI_Chrome", (0.82, 0.84, 0.87), rough=0.14, metal=0.96)
    brass = make_solid_mat("OHI_Brass", (0.80, 0.62, 0.26), rough=0.26, metal=0.90)
    cable_orange = make_solid_mat("OHI_CableOrg", (0.88, 0.38, 0.08), rough=0.42, metal=0.02)
    skylight_glass = make_real_glass_mat("OHI_SkylightGlass", rgb=(0.70, 0.82, 0.92), alpha=0.18, rough=0.04)

    pb = PartBuilder("OwnHallInterior", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # 1. 2K QUARZ-EPOXIDBODEN UEBER ALLE 3 HALLEN (X = -5.50..+21.50, Z = -4.50..+4.50, Oberkante exakt Y = 0.000!)
    pb.box((8.0, -0.025, 0.0), (27.08, 0.05, 9.08), epoxy_floor, bevel=0.0, uv_scale=3.0)
    # Eingelassener 5-Rippen-Traenenblech-Kabelkanal entlang der Nordwand (Z = -4.12) + Bodenlueftungsgitter in Halle C
    pb.box((8.0, 0.002, -4.14), (25.6, 0.004, 0.38), steel_anth)
    pb.box((8.0, 0.004, -4.14), (25.5, 0.005, 0.34), treadplate, bevel=0.001, uv_scale=1.5)
    for gx in (14.5, 17.0, 19.5):
        for gz in (-1.6, 1.8):
            pb.box((gx, 0.002, gz), (0.58, 0.004, 0.58), steel_anth)
            for li in range(7):
                pb.box((gx, 0.005, gz - 0.21 + li * 0.07), (0.50, 0.004, 0.02), alu)

    # 2. INNENWAENDE + SICHTBETON-SOCKEL + ECHTE DURCHGEBROCHENE GLAS-OBERLICHTER!
    # A. Nordwand (Innenflaeche Z = -4.48, laesst alle Wand-Geraete bei Z = -4.38..-4.45 zu 100 % frei!)
    pb.box((8.0, 1.92, -4.56), (27.16, 3.84, 0.14), sandwich_wall, bevel=0.006, uv_scale=3.0)
    pb.box((8.0, 0.54, -4.475), (27.00, 1.08, 0.03), concrete_dado, bevel=0.005, uv_scale=2.2)
    pb.box((8.0, 1.095, -4.468), (27.00, 0.032, 0.035), steel_anth, bevel=0.004)

    # B. Westwand (Garage X = -5.48) & Ostwand (Halle C X = +21.48) MIT OBERLICHT Z=-3.20..+3.20, Y=2.68..3.36!
    for wx_in, wx_mid, sgn in ((-5.55, -5.64, -1.0), (21.55, 21.64, 1.0)):
        pb.box((wx_in, 1.34, 0.0), (0.14, 2.68, 9.16), sandwich_wall, bevel=0.006, uv_scale=3.0)
        pb.box((wx_in, 3.60, 0.0), (0.14, 0.48, 9.16), sandwich_wall, bevel=0.006, uv_scale=3.0)
        for z0, z1 in ((-4.58, -3.20), (3.20, 4.58)):
            pb.box((wx_in, 3.02, (z0 + z1) * 0.5), (0.14, 0.68, z1 - z0), sandwich_wall, bevel=0.005, uv_scale=3.0)
        # Sichtbeton-Sockel innen
        pb.box((wx_in - sgn * 0.08, 0.54, 0.0), (0.03, 1.08, 8.96), concrete_dado, bevel=0.005, uv_scale=2.2)
        pb.box((wx_in - sgn * 0.085, 1.095, 0.0), (0.035, 0.032, 8.96), steel_anth, bevel=0.004)
        # 3D-Alu-Fensterlaibung + Sprossen + Echtglas!
        pb.box((wx_mid, 2.67, 0.0), (0.36, 0.05, 6.46), alu, bevel=0.005)
        pb.box((wx_mid, 3.37, 0.0), (0.36, 0.05, 6.46), alu, bevel=0.005)
        for mz in np.linspace(-3.20, 3.20, 5):
            pb.box((wx_mid, 3.02, float(mz)), (0.32, 0.68, 0.055), steel_anth, bevel=0.004)
            pb.box((wx_in - sgn * 0.06, 3.02, float(mz)), (0.025, 0.68, 0.072), rubber, bevel=0.003)
        glass_panes.append(((wx_mid, 3.02, 0.0), (0.018, 0.64, 6.36), skylight_glass, (0.0, 0.0, 0.0)))

    # C. Suedwand (Innenflaeche Z = +4.48): Garagentor X=-2.20..+2.20 frei + 3 echte Fenster wx=(8.8, 15.2, 18.8), Y=2.52..3.24!
    pb.box((-3.89, 1.92, 4.56), (3.38, 3.84, 0.14), sandwich_wall, bevel=0.006, uv_scale=3.0)
    pb.box(( 0.00, 3.42, 4.56), (4.42, 0.84, 0.14), sandwich_wall, bevel=0.006, uv_scale=3.0)
    pb.box((11.89, 1.26, 4.56), (19.38, 2.52, 0.14), sandwich_wall, bevel=0.006, uv_scale=3.0)
    pb.box((11.89, 3.54, 4.56), (19.38, 0.60, 0.14), sandwich_wall, bevel=0.006, uv_scale=3.0)
    for x0, x1 in ((2.20, 7.50), (10.10, 13.90), (16.50, 17.50), (20.10, 21.58)):
        pb.box(((x0 + x1) * 0.5, 2.88, 4.56), (x1 - x0, 0.72, 0.14), sandwich_wall, bevel=0.005, uv_scale=3.0)
    for wx in (8.8, 15.2, 18.8):
        pb.box((wx, 2.51, 4.66), (2.66, 0.05, 0.36), alu, bevel=0.005)
        pb.box((wx, 3.25, 4.66), (2.66, 0.05, 0.36), alu, bevel=0.005)
        for mx_off in (-1.30, 0.0, 1.30):
            pb.box((wx + mx_off, 2.88, 4.66), (0.055, 0.72, 0.32), steel_anth, bevel=0.004)
            pb.box((wx + mx_off, 2.88, 4.49), (0.072, 0.72, 0.025), rubber, bevel=0.003)
        glass_panes.append(((wx, 2.88, 4.66), (2.56, 0.68, 0.018), skylight_glass, (0.0, 0.0, 0.0)))

    # Suedwand Sichtbeton-Sockel links & rechts vom Tor
    pb.box((-3.86, 0.54, 4.475), (3.28, 1.08, 0.03), concrete_dado, bevel=0.005, uv_scale=2.2)
    pb.box((11.86, 0.54, 4.475), (19.28, 1.08, 0.03), concrete_dado, bevel=0.005, uv_scale=2.2)
    pb.box((-3.86, 1.095, 4.468), (3.28, 0.032, 0.035), steel_anth, bevel=0.004)
    pb.box((11.86, 1.095, 4.468), (19.28, 0.032, 0.035), steel_anth, bevel=0.004)

    # 3. 3D-TRAPEZBLECHDACH (Y = 3.82) & ECHTE HEB/IPE-STAHLRAHMEN!
    add_trapezoidal_deck(pb, (8.0, 3.82, 0.0), 27.16, 9.16, y_base=3.80, rib_h=0.09, pitch_z=0.48, mat=ral_light, uv_scale=2.0)

    # HEB-Wandstuetzen & IPE-Dachtraeger (exakt platziert ohne Konflikt mit Wandgeraeten!)
    for bx in (-5.28, -2.05, 1.85, 5.50, 9.00, 12.50, 17.85, 21.28):
        is_portal = bx in (5.50, 12.50)
        col_w = 0.22 if is_portal else 0.16
        for wz in (-4.34, 4.34):
            # Kein Stuetzenfuss mitten im Garagentor (-2.2..+2.2 auf +Z)!
            if wz > 0 and abs(bx) < 2.30:
                continue
            add_heb_column(pb, bx, wz, h=3.70, width=col_w, depth=0.18, steel_mat=steel_grey, plate_mat=steel_anth, bolt_mat=chrome)
        add_heb_beam_z(pb, bx, 3.70, -4.38, 4.38, width=col_w, height=0.18 if is_portal else 0.14,
                       steel_mat=steel_grey, plate_mat=steel_anth, bolt_mat=chrome)

    # 4. WICKELFALZ-LUEFTUNGSROHRE, VERZINKTE KABELPRITSCHEN & SPRINKLERLEITUNGEN UEBER ALLE 3 HALLEN!
    pb.cyl((8.0, 3.52, -0.15), 0.18, 0.18, 25.8, galv, axis_g="x", seg=24)
    for rx in range(-4, 21, 2):
        pb.cyl((float(rx), 3.52, -0.15), 0.195, 0.195, 0.025, alu, axis_g="x", seg=24)
        pb.cyl((float(rx), 3.68, -0.15), 0.010, 0.010, 0.28, galv, axis_g="y", seg=8)
    for dx in (-2.6, 2.2, 7.6, 11.2, 15.2, 19.4):
        pb.cyl((dx, 3.31, -0.15), 0.10, 0.16, 0.09, alu, axis_g="y", seg=18)

    for tz in (-3.55, 1.35):
        pb.box((8.0, 3.42, tz), (25.6, 0.020, 0.34), galv, bevel=0.003, uv_scale=1.5)
        pb.box((8.0, 3.455, tz - 0.165), (25.6, 0.065, 0.018), galv)
        pb.box((8.0, 3.455, tz + 0.165), (25.6, 0.065, 0.018), galv)
        pb.cyl((8.0, 3.45, tz - 0.08), 0.020, 0.020, 25.4, rubber, axis_g="x", seg=10)
        pb.cyl((8.0, 3.45, tz + 0.02), 0.017, 0.017, 25.4, cable_orange, axis_g="x", seg=10)
        pb.cyl((8.0, 3.45, tz + 0.10), 0.015, 0.015, 25.4, euro_blue, axis_g="x", seg=10)
        for hx in range(-4, 21, 4):
            pb.cyl((float(hx), 3.64, tz), 0.010, 0.010, 0.40, galv, axis_g="y", seg=8)

    # Rote Sprinklerleitung + Messing-Sprinklerkoepfe
    for sz in (-2.2, 2.6):
        pb.cyl((8.0, 3.62, sz), 0.024, 0.024, 25.8, flame_red, axis_g="x", seg=12)
        for spx in range(-4, 21, 4):
            pb.cyl((float(spx), 3.55, sz), 0.012, 0.018, 0.09, brass, axis_g="y", seg=10)

    # 5. SEKTIONALTOR-LAUFSCHIENEN, SPIRAL-TORSIONSFEDERN & ANTRIEBSMOTOR IN DER START-GARAGE!
    for s in (-1.0, 1.0):
        pb.box((s * 2.22, 1.52, 4.44), (0.075, 3.04, 0.10), galv, bevel=0.005)
        add_pipe_run(pb, [(s * 2.22, 2.86, 4.44), (s * 2.22, 3.14, 4.44), (s * 2.22, 3.14, 1.15)], 0.032, galv, seg=12, bend_r=0.20)
        for hz in (3.6, 2.4, 1.25):
            pb.box((s * 2.22, 3.48, hz), (0.035, 0.64, 0.035), galv, bevel=0.003)
    pb.cyl((0.0, 3.24, 4.40), 0.022, 0.022, 4.65, chrome, axis_g="x", seg=16)
    for fx in (-1.08, 1.08):
        add_torsion_spring_x(pb, (fx, 3.24, 4.40), length_x=0.66, coil_r=0.056, wire_r=0.008, turns=20, mat=steel_anth)
        pb.cyl((fx - 0.35, 3.24, 4.40), 0.066, 0.066, 0.035, alu, axis_g="x", seg=16)
        pb.cyl((fx + 0.35, 3.24, 4.40), 0.066, 0.066, 0.035, alu, axis_g="x", seg=16)
    pb.box((2.46, 3.24, 4.34), (0.26, 0.32, 0.22), steel_anth, bevel=0.014)

    # 6. HIGH-POLY WERKSTATT-TRETMUELLEIMER NEBEN DER WERKBANK (-4.95, 0.0, 3.38)
    pb.box((-4.95, 0.34, 3.38), (0.42, 0.64, 0.38), steel_grey, bevel=0.025)
    pb.box((-4.95, 0.68, 3.38), (0.45, 0.045, 0.41), safety_grn, bevel=0.014)
    pb.box((-4.72, 0.04, 3.38), (0.06, 0.025, 0.16), rubber, bevel=0.004)  # Fusspedal

    pb.build(root)
    build_glass_child(root, "OwnHallInterior_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "own_hall_interior.glb"))


# ---------------------------------------------------------------------------
# 3. ANIMIERBARE HIGH-POLY SEKTIONALTOR-PANEELE (SOLID & MIT 4 GLASFENSTERN)
# ---------------------------------------------------------------------------

def build_garage_door_panels(lib: dict):
    for with_windows, fname in ((False, "garage_door_panel_solid.glb"), (True, "garage_door_panel_window.glb")):
        reset_scene()
        root = bpy.data.objects.new("GarageDoorPanelRoot", None)
        bpy.context.scene.collection.objects.link(root)

        panel_mat = make_orm_mat("GDP_Panel", lib["ral_light_grey"], normal_strength=0.65)
        galv = make_orm_mat("GDP_Galv", lib["galv"], normal_strength=0.80)
        rubber = make_orm_mat("GDP_Rubber", lib["rubber_black"], normal_strength=0.85)
        glass = make_real_glass_mat("GDP_Glass", rgb=(0.68, 0.80, 0.90), alpha=0.22, rough=0.04)

        pb = PartBuilder("GarageDoorPanel", origin_g=Vector((0, 0, 0)))
        glass_panes = []

        if with_windows:
            pb.box((0.0, 0.21, 0.0), (4.32, 0.14, 0.058), panel_mat, bevel=0.008)
            pb.box((0.0, -0.21, 0.0), (4.32, 0.14, 0.058), panel_mat, bevel=0.008)
            for px in (-1.96, -0.96, 0.0, 0.96, 1.96):
                pb.box((px, 0.0, 0.0), (0.34 if abs(px) < 1.8 else 0.40, 0.30, 0.058), panel_mat, bevel=0.006)
            for wx in (-1.45, -0.48, 0.48, 1.45):
                pb.box((wx, 0.135, 0.0), (0.66, 0.025, 0.068), rubber, bevel=0.004)
                pb.box((wx, -0.135, 0.0), (0.66, 0.025, 0.068), rubber, bevel=0.004)
                glass_panes.append(((wx, 0.0, 0.0), (0.62, 0.24, 0.018), glass, (0.0, 0.0, 0.0)))
        else:
            pb.box((0.0, 0.0, 0.0), (4.32, 0.56, 0.058), panel_mat, bevel=0.010)
            for ry in (-0.16, 0.0, 0.16):
                pb.box((0.0, ry, -0.030), (4.28, 0.024, 0.010), galv)
                pb.box((0.0, ry,  0.030), (4.28, 0.024, 0.010), galv)

        pb.box((0.0, -0.282, 0.0), (4.32, 0.016, 0.062), rubber)
        for hx in (-2.10, -0.72, 0.72, 2.10):
            pb.box((hx, 0.26, -0.038), (0.048, 0.09, 0.024), galv, bevel=0.003)
        for sx in (-2.18, 2.18):
            pb.cyl((sx, 0.0, -0.045), 0.022, 0.022, 0.024, rubber, axis_g="x", seg=14)

        pb.build(root)
        if glass_panes:
            build_glass_child(root, "GarageDoorPanel_Glass", glass_panes)
        export_glb(os.path.join(OUT_MODELS_DIR, fname))


# ---------------------------------------------------------------------------
# 4. HALLE-C UNTERVERTEILER & SHUTTLE-WANDPANEL
# ---------------------------------------------------------------------------

def build_hall_c_and_shuttle_panels(lib: dict):
    # A. Halle-C 400V Unterverteiler (Ursprung 14.6, 1.55, -4.38 -> 2x7 Buchsen bei y=-0.20/-0.33, z=+0.126 bleiben frei!)
    reset_scene()
    root = bpy.data.objects.new("HallCPowerRoot", None)
    bpy.context.scene.collection.objects.link(root)
    cab_light = make_orm_mat("HCP_Light", lib["ral_light_grey"], normal_strength=0.70)
    cab_dark = make_orm_mat("HCP_Dark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("HCP_Alu", lib["alu_anodized"], normal_strength=0.55)
    galv = make_orm_mat("HCP_Galv", lib["galv"], normal_strength=0.80)
    yellow = make_orm_mat("HCP_Yel", lib["safety_yellow"], normal_strength=0.65)
    red = make_orm_mat("HCP_Red", lib["flame_red"], normal_strength=0.65)
    meter = make_screen_tex_mat("HCP_Meter", lib["meter_screen_tex"], em_strength=1.35)

    pb = PartBuilder("HallCPower", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.0, 0.0), (0.74, 0.96, 0.20), cab_dark, bevel=0.012)
    pb.box((0.0, 0.08, 0.102), (0.68, 0.74, 0.016), cab_light, bevel=0.008)
    pb.box((0.0, 0.12, 0.114), (0.36, 0.18, 0.010), meter, uv_mode="side_x")
    pb.box((-0.24, 0.12, 0.116), (0.09, 0.09, 0.016), yellow, bevel=0.004)
    pb.box((-0.24, 0.12, 0.130), (0.025, 0.075, 0.020), red, rot_g_deg=(0, 0, -25.0), bevel=0.003)
    pb.box((0.28, 0.08, 0.118), (0.028, 0.14, 0.018), alu, bevel=0.004)
    pb.box((0.0, -0.265, 0.108), (0.66, 0.26, 0.018), yellow, bevel=0.006)
    for cx in (-0.20, 0.20):
        pb.cyl((cx, 1.15, -0.02), 0.026, 0.026, 1.38, galv, axis_g="y", seg=16)
    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "hall_c_subpanel_power.glb"))

    # B. Halle-C 10G Fiber-Wandverteiler (Ursprung 16.6, 1.62, -4.38 -> Port bei y=-0.10, z=+0.158!)
    reset_scene()
    root = bpy.data.objects.new("HallCFiberRoot", None)
    bpy.context.scene.collection.objects.link(root)
    cab_dark = make_orm_mat("HCF_Dark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("HCF_Alu", lib["alu_anodized"], normal_strength=0.55)
    blue = make_orm_mat("HCF_Blue", lib["euro_blue"], normal_strength=0.65)
    yellow = make_orm_mat("HCF_Yel", lib["safety_yellow"], normal_strength=0.65)
    green_led = make_emissive_mat("HCF_Led", (0.14, 0.94, 0.44), strength=2.0)

    pb = PartBuilder("HallCFiber", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.0, 0.0), (0.76, 0.48, 0.24), cab_dark, bevel=0.012)
    pb.box((0.0, 0.08, 0.124), (0.68, 0.16, 0.014), alu, bevel=0.005)
    pb.box((0.0, -0.10, 0.128), (0.58, 0.11, 0.042), blue, bevel=0.006)
    for pi in range(8):
        px = -0.22 + pi * 0.063
        pb.box((px, -0.10, 0.152), (0.036, 0.032, 0.012), cab_dark, bevel=0.002)
        pb.box((px, -0.062, 0.150), (0.020, 0.008, 0.006), green_led)
    for cx in (-0.18, 0.18):
        pb.cyl((cx, 1.05, -0.02), 0.020, 0.020, 1.65, yellow, axis_g="y", seg=14)
    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "hall_c_subpanel_fiber.glb"))

    # C. Gebuerstetes Alu-Shuttle-Wandterminal fuer Start-Garage
    reset_scene()
    root = bpy.data.objects.new("GarageShuttleRoot", None)
    bpy.context.scene.collection.objects.link(root)
    alu = make_orm_mat("GS_Alu", lib["alu_anodized"], normal_strength=0.55)
    dark = make_orm_mat("GS_Dark", lib["steel_anthracite"], normal_strength=0.75)
    scr = make_solid_mat("GS_Scr", (0.05, 0.14, 0.24), rough=0.10, metal=0.08,
                         emission=(0.08, 0.28, 0.46), em_strength=0.95)
    green_led = make_emissive_mat("GS_Green", (0.16, 0.94, 0.44), strength=1.8)
    pb = PartBuilder("GarageShuttle", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.0, 0.0), (0.70, 0.94, 0.065), alu, bevel=0.016)
    pb.box((0.0, 0.06, 0.032), (0.62, 0.62, 0.016), dark, bevel=0.008)
    pb.box((0.0, 0.06, 0.043), (0.56, 0.56, 0.008), scr, bevel=0.003)
    pb.cyl((0.0, -0.34, 0.038), 0.052, 0.052, 0.014, dark, axis_g="z", seg=20)
    pb.cyl((0.0, -0.34, 0.046), 0.038, 0.038, 0.008, green_led, axis_g="z", seg=20)
    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "garage_shuttle_wall.glb"))


# ---------------------------------------------------------------------------
# 5. KAFFEEVOLLAUTOMAT & ALU-WHITEBOARD (2K ORM UPGRADE)
# ---------------------------------------------------------------------------

def build_coffee_and_whiteboard(lib: dict):
    # Kaffee-Station
    reset_scene()
    root = bpy.data.objects.new("CoffeeStationRoot", None)
    bpy.context.scene.collection.objects.link(root)
    wood_oak = make_orm_mat("CF_WoodOak", lib["wood_oak"], normal_strength=1.0, coat=0.35)
    steel_dark = make_orm_mat("CF_SteelDark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("CF_Alu", lib["alu_anodized"], normal_strength=0.55)
    chrome = make_solid_mat("CF_Chrome", (0.84, 0.86, 0.89), rough=0.14, metal=0.96)
    ceramic = make_solid_mat("CF_Ceramic", (0.95, 0.95, 0.93), rough=0.18, metal=0.0)
    coffee_liq = make_solid_mat("CF_Coffee", (0.14, 0.07, 0.03), rough=0.08, metal=0.0)
    oled = make_emissive_mat("CF_Oled", (0.18, 0.72, 0.98), strength=1.5)

    pb = PartBuilder("CoffeeStation", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.75, 0.0), (0.66, 0.042, 0.48), wood_oak, bevel=0.008, uv_scale=1.1)
    pb.box((0.0, 0.24, 0.0), (0.60, 0.028, 0.42), wood_oak, bevel=0.005, uv_scale=1.1)
    for lx in (-0.28, 0.28):
        for lz in (-0.20, 0.20):
            pb.box((lx, 0.37, lz), (0.036, 0.74, 0.036), steel_dark, bevel=0.004)
    pb.box((-0.08, 0.96, -0.02), (0.28, 0.38, 0.34), steel_dark, bevel=0.018)
    pb.box((-0.08, 0.99, 0.152), (0.24, 0.30, 0.02), alu, bevel=0.008)
    pb.box((-0.08, 1.07, 0.165), (0.11, 0.065, 0.01), oled, bevel=0.002)
    pb.box((-0.08, 0.79, 0.18), (0.24, 0.035, 0.12), chrome, bevel=0.006)
    for sx in (-0.105, -0.055):
        pb.cyl((sx, 0.92, 0.175), 0.009, 0.007, 0.045, chrome, axis_g="y", seg=12)
    pb.cyl((-0.08, 0.845, 0.18), 0.036, 0.030, 0.075, ceramic, axis_g="y", seg=20)
    pb.cyl((-0.08, 0.878, 0.18), 0.032, 0.032, 0.006, coffee_liq, axis_g="y", seg=18)
    for cx, cz in ((0.18, 0.08), (0.20, -0.08)):
        pb.cyl((cx, 0.81, cz), 0.036, 0.032, 0.082, ceramic, axis_g="y", seg=18)
    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "prop_coffee_machine.glb"))

    # Alu-Whiteboard
    reset_scene()
    root = bpy.data.objects.new("WhiteboardRoot", None)
    bpy.context.scene.collection.objects.link(root)
    alu = make_orm_mat("WB_Alu", lib["alu_anodized"], normal_strength=0.55)
    dark = make_orm_mat("WB_Dark", lib["steel_anthracite"], normal_strength=0.75)
    enamel = make_solid_mat("WB_Enamel", (0.95, 0.96, 0.97), rough=0.12, metal=0.04, coat=0.75)
    m_red = make_orm_mat("WB_Red", lib["flame_red"], normal_strength=0.5)
    m_blu = make_orm_mat("WB_Blu", lib["euro_blue"], normal_strength=0.5)
    m_grn = make_orm_mat("WB_Grn", lib["safety_green"], normal_strength=0.5)

    pb = PartBuilder("Whiteboard", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.0, 0.012), (1.82, 1.08, 0.018), enamel, bevel=0.004)
    pb.box((0.0,  0.555, 0.016), (1.88, 0.038, 0.032), alu, bevel=0.006)
    pb.box((0.0, -0.555, 0.016), (1.88, 0.038, 0.032), alu, bevel=0.006)
    pb.box((-0.925, 0.0, 0.016), (0.038, 1.14, 0.032), alu, bevel=0.006)
    pb.box(( 0.925, 0.0, 0.016), (0.038, 1.14, 0.032), alu, bevel=0.006)
    for cx in (-0.925, 0.925):
        for cy in (-0.555, 0.555):
            pb.box((cx, cy, 0.018), (0.052, 0.052, 0.036), dark, bevel=0.006)
    pb.box((0.0, -0.565, 0.055), (1.20, 0.018, 0.065), alu, bevel=0.004)
    for mx, mmat in ((-0.32, m_red), (-0.12, m_blu), (0.08, m_grn)):
        pb.cyl((mx, -0.546, 0.055), 0.009, 0.009, 0.13, mmat, axis_g="x", seg=12)
    pb.box((0.36, -0.542, 0.055), (0.14, 0.032, 0.052), dark, bevel=0.006)
    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "prop_whiteboard.glb"))


def main():
    tex = ensure_exterior_textures()
    lib = ensure_hall_pbr_library()
    build_own_hall_exterior(tex, lib)
    build_own_hall_interior(lib)
    build_garage_door_panels(lib)
    build_hall_c_and_shuttle_panels(lib)
    build_coffee_and_whiteboard(lib)
    print("[OWN_HALL] Alle 9 Blender-5.2-Modelle fuer Start-Garage + Halle B/C gebaut!")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
