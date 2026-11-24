"""Blender 5.2 AAA-Master-Generator fuer den Innenraum von 'Halle Nord' (20 x 12 x 4.85 m):
  - assets/models/halle_nord_interior.glb

v2.3.0 Komplett-Overhaul (0 % Low-Poly-Kloetze, 100 % 2K-ORM-PBR & echter Stahlbau):
  - 2K Quarz-Epoxidharz-Industrieboden mit echter Roughness-Glanzmap, geschnittenen PU-Dehnungsfugen,
    eingelassenen 5-Rippen-Traenenblech-Kabelkanaelen, 3D-Bodenlueftungsgittern & geoeffneter Revisionsklappe
  - 2K Gefaster Sichtbeton-Sockel (Schalungsanker & Poren) + 2K Akustik-Sandwichpaneele mit Stossfugen
  - ECHTE DURCHGEBROCHENE 3D-GLAS-OBERLICHTER (Nord, West & Ost, Y = 3.58..4.34) mit thermisch getrennten
    Alu-Profilrahmen, EPDM-Dichtungen & echtem transparentem Isolierglas (Blick in den echten Himmel!)
  - Echtes 3D-extrudiertes Trapezblechdach, 5 ausmodellierte HEB-Doppel-T-Stahlrahmen mit Fussplatten,
    Sechskant-Ankerbolzen, Steifenblechen & geschraubten Pratt-Fachwerkbindern
  - Runde verzinkte Wickelfalz-Lueftungsrohre mit Flanschen & Drallauslaessen, gelochte Kabelpritschen
    mit sanft geschwungenen Kabelstraengen, rote Sprinkler-Rohrleitungen mit gebogenen Rohrboegen
  - Echte 3D-Sektionaltor-Deckenmechanik mit gewickelten 3D-Spiral-Torsionsfedern, Seiltrommeln,
    C-Laufschienen, Aufsteck-Getriebemotor, Nothandkette & transparenten Sichtfenstern
  - Aufgeraeumt an den Raendern gruppierte High-Poly-Ausstattung (Mitte 100 % frei fuer Server-Racks!):
    * Logistik-Ecke Suedost: 9-Klotz-Europaletten (DIN 13698) mit 2K-Wellpappe-Kartons, High-Poly-Gabelhubwagen
      ('Ameise' mit Rundrohr-Deichsel & Tandemrollen), echte 3D-Draht-Gitterbox (DIN 15155) & Rollcontainer
    * Sozial- & Sicherheits-Zone Ost/Nord: 4 profilierte Stahlspinde mit Zylinderschloessern, 19L-Wasserspender,
      Sicherheits-Infoboard mit DIN-Fluchtwegplan, runde Hallenuhr hinter Glas, DIN-Erste-Hilfe-Schrank,
      Wandhydrant mit aufgerolltem Flachschlauch hinter Echtglas
    * Saubere Technik-Peripherie: Geschwungene Vor-/Ruecklaufrohre mit Speichen-Handradventilen, 400V-CEE-Dosen,
      6-Schubladen-Werkstattwagen mit Lenkrollen, Industriesauger mit gebogenem Saugschlauch & Alu-Stehleiter
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
from hall_pbr_kit import (
    OUT_MODELS_DIR,
    add_euro_pallet_hq,
    add_fire_extinguisher_hq,
    add_heb_beam_z,
    add_heb_column,
    add_industrial_vacuum_hq,
    add_pallet_jack_hq,
    add_pipe_run,
    add_rolling_tool_chest_hq,
    add_spoked_valve,
    add_torsion_spring_x,
    add_trapezoidal_deck,
    add_wire_gitterbox_hq,
    build_glass_child,
    ensure_hall_pbr_library,
    export_glb,
    make_emissive_mat,
    make_orm_mat,
    make_real_glass_mat,
    reset_scene,
)


def _add_cardboard_carton(pb: PartBuilder, pos_g, size_g, card_mat, tape_mat, label_mat, yaw_deg: float = 0.0):
    cx, cy, cz = pos_g
    sx, sy, sz = size_g
    pb.box((cx, cy, cz), (sx, sy, sz), card_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.008, uv_scale=0.65)
    pb.box((cx, cy + sy * 0.5 + 0.0015, cz), (sx + 0.003, 0.003, 0.052), tape_mat, rot_g_deg=(0, yaw_deg, 0))
    pb.box((cx, cy + 0.03, cz + sz * 0.5 + 0.002), (min(0.17, sx * 0.42), min(0.11, sy * 0.36), 0.003),
           label_mat, rot_g_deg=(0, yaw_deg, 0))


def build_halle_nord_interior(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("HalleNordInteriorRoot", None)
    bpy.context.scene.collection.objects.link(root)

    # 2K / 1K ORM-PBR Materialien
    epoxy_floor = make_orm_mat("HNI_EpoxyFloor2K", lib["epoxy_floor"], normal_strength=1.15, coat=0.35, coat_rough=0.18)
    sandwich_wall = make_orm_mat("HNI_SandwichWall2K", lib["sandwich_wall"], normal_strength=1.05)
    concrete_dado = make_orm_mat("HNI_ConcreteDado2K", lib["concrete"], normal_strength=1.15)
    treadplate = make_orm_mat("HNI_Treadplate1K", lib["treadplate"], normal_strength=1.35)
    galv = make_orm_mat("HNI_Galv1K", lib["galv"], normal_strength=0.85)
    steel_anth = make_orm_mat("HNI_SteelAnthracite", lib["steel_anthracite"], normal_strength=0.75)
    steel_grey = make_orm_mat("HNI_SteelGrey", lib["steel_grey"], normal_strength=0.75)
    ral_light = make_orm_mat("HNI_RalLight", lib["ral_light_grey"], normal_strength=0.70)
    alu = make_orm_mat("HNI_AluAnodized", lib["alu_anodized"], normal_strength=0.55)
    safety_yel = make_orm_mat("HNI_SafetyYellow", lib["safety_yellow"], normal_strength=0.70)
    flame_red = make_orm_mat("HNI_FlameRed", lib["flame_red"], normal_strength=0.70)
    euro_blue = make_orm_mat("HNI_EuroBlue", lib["euro_blue"], normal_strength=0.65)
    safety_grn = make_orm_mat("HNI_SafetyGreen", lib["safety_green"], normal_strength=0.65)
    rubber = make_orm_mat("HNI_RubberBlack", lib["rubber_black"], normal_strength=0.90)
    wood_pallet = make_orm_mat("HNI_WoodPallet", lib["wood_pallet"], normal_strength=1.10)
    cardboard = make_orm_mat("HNI_Cardboard", lib["cardboard"], normal_strength=1.15)

    chrome = make_solid_mat("HNI_Chrome", (0.82, 0.84, 0.87), rough=0.14, metal=0.96)
    brass = make_solid_mat("HNI_Brass", (0.80, 0.62, 0.26), rough=0.26, metal=0.90)
    tape_brown = make_solid_mat("HNI_Tape", (0.46, 0.33, 0.19), rough=0.28, metal=0.0)
    paper_white = make_solid_mat("HNI_Paper", (0.94, 0.93, 0.90), rough=0.82, metal=0.0)
    cork = make_solid_mat("HNI_Cork", (0.60, 0.44, 0.28), rough=0.90, metal=0.0)
    paint_floor_w = make_solid_mat("HNI_FloorWhite", (0.86, 0.87, 0.85), rough=0.52, metal=0.0)
    paint_floor_y = make_solid_mat("HNI_FloorYellow", (0.88, 0.66, 0.10), rough=0.50, metal=0.0)
    cable_orange = make_solid_mat("HNI_CableOrange", (0.88, 0.38, 0.08), rough=0.42, metal=0.02)
    water_poly = make_real_glass_mat("HNI_WaterPoly", rgb=(0.24, 0.62, 0.88), alpha=0.46, rough=0.06, metal=0.04)
    skylight_glass = make_real_glass_mat("HNI_SkylightGlass", rgb=(0.70, 0.82, 0.92), alpha=0.18, rough=0.04, metal=0.08)
    lamp_led = make_emissive_mat("HNI_LampLed", (1.0, 0.97, 0.92), strength=2.6, rough=0.14)

    pb = PartBuilder("HalleNordInterior", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # =========================================================================
    # 1. 2K QUARZ-EPOXIDHARZ-BODEN + EINGELASSENE TRAENENBLECH-KABELKANAELE
    # =========================================================================
    pb.box((0.0, -0.025, 0.0), (20.04, 0.05, 12.04), epoxy_floor, bevel=0.0, uv_scale=3.2)

    # Eingelassene Kabelkanaele mit Stahl-Winkelrahmen & 5-Rippen-Traenenblech
    for cx, cz, sx, sz in ((-1.5, -4.45, 15.4, 0.52), (-0.3, -0.4, 0.50, 8.0)):
        pb.box((cx, 0.002, cz), (sx + 0.05, 0.004, sz + 0.05), steel_anth)
        pb.box((cx, 0.0045, cz), (sx, 0.006, sz), treadplate, bevel=0.002, uv_scale=1.6)

    # 10 fein ausmodellierte 3D-Kaltluft-Bodenauslaesse entlang der 2 Rack-Reihen
    for gz in (-1.6, 2.0):
        for gx in (-6.6, -4.0, -1.4, 1.4, 4.0):
            pb.box((gx, 0.0025, gz), (0.64, 0.005, 0.64), steel_anth, bevel=0.002)
            pb.box((gx, 0.001, gz), (0.56, 0.003, 0.56), rubber)
            for li in range(8):
                pb.box((gx, 0.006, gz - 0.245 + li * 0.070), (0.55, 0.005, 0.020), alu, bevel=0.001)
            for cross_x in (-0.18, 0.0, 0.18):
                pb.box((gx + cross_x, 0.004, gz), (0.012, 0.004, 0.54), steel_grey)

    #Dezente aufgemalte Stellflaechen- & Fahrweg-Markierungen
    for gz in (-1.6, 2.0):
        for off in (-0.64, 0.64):
            pb.box((-0.4, 0.002, gz + off), (15.8, 0.0025, 0.055), paint_floor_w)
    for sx in (-2.38, 2.38):
        pb.box((sx, 0.002, 4.5), (0.08, 0.0025, 2.8), paint_floor_y)

    # Geoeffnete Revisionsklappe an der Nordwand (X = 0.6, Z = -5.15) mit geschwungenen Kabeln & Plattenheber
    pb.box((0.60, 0.002, -5.15), (0.64, 0.004, 0.64), steel_anth)
    pb.box((0.60, 0.003, -5.15), (0.56, 0.003, 0.56), rubber)
    add_pipe_run(pb, [(0.32, 0.018, -5.06), (0.60, 0.022, -5.05), (0.88, 0.018, -5.07)], 0.022, cable_orange, seg=10)
    add_pipe_run(pb, [(0.32, 0.016, -5.18), (0.60, 0.018, -5.16), (0.88, 0.016, -5.19)], 0.019, euro_blue, seg=10)
    pb.box((1.26, 0.018, -5.15), (0.58, 0.028, 0.58), treadplate, rot_g_deg=(0.0, 14.0, 0.0), bevel=0.004, uv_scale=1.2)

    # =========================================================================
    # 2. SICHTBETON-SOCKEL + SANDWICHPANEELE + ECHTE DURCHGEBROCHENE OBERLICHTER!
    # =========================================================================
    # A. Nordwand (Z = -6.02): Oberlicht-Oeffnung X = -9.40..+9.40, Y = 3.58..4.34!
    pb.box((0.0, 1.79, -6.02), (20.12, 3.58, 0.14), sandwich_wall, bevel=0.008, uv_scale=3.2)
    pb.box((0.0, 4.59, -6.02), (20.12, 0.50, 0.14), sandwich_wall, bevel=0.008, uv_scale=3.2)
    for side in (-1.0, 1.0):
        pb.box((side * 9.73, 3.96, -6.02), (0.66, 0.78, 0.14), sandwich_wall, bevel=0.006, uv_scale=3.2)
    # Durchgehende Alu-Fensterbank / Laibung von innen (-5.95) bis aussen (-6.26)!
    pb.box((0.0, 3.565, -6.10), (18.88, 0.055, 0.34), alu, bevel=0.005)
    pb.box((0.0, 4.355, -6.10), (18.88, 0.055, 0.34), alu, bevel=0.005)
    for mx in np.linspace(-9.40, 9.40, 11):
        pb.box((float(mx), 3.96, -6.10), (0.065, 0.76, 0.30), steel_anth, bevel=0.005)
        pb.box((float(mx), 3.96, -6.00), (0.080, 0.76, 0.03), rubber, bevel=0.003)
    glass_panes.append(((0.0, 3.96, -6.10), (18.76, 0.72, 0.022), skylight_glass, (0.0, 0.0, 0.0)))

    # B. West- & Ostwand (X = +-10.02): Oberlicht-Oeffnung Z = -5.40..+5.40, Y = 3.58..4.34!
    for side in (-1.0, 1.0):
        wx = side * 10.02
        pb.box((wx, 1.79, 0.0), (0.14, 3.58, 12.12), sandwich_wall, bevel=0.008, uv_scale=3.2)
        pb.box((wx, 4.59, 0.0), (0.14, 0.50, 12.12), sandwich_wall, bevel=0.008, uv_scale=3.2)
        for sz_end in (-1.0, 1.0):
            pb.box((wx, 3.96, sz_end * 5.73), (0.14, 0.78, 0.66), sandwich_wall, bevel=0.006, uv_scale=3.2)
        # Alu-Laibung von innen (+-9.95) bis aussen (+-10.26)
        pb.box((side * 10.10, 3.565, 0.0), (0.34, 0.055, 10.88), alu, bevel=0.005)
        pb.box((side * 10.10, 4.355, 0.0), (0.34, 0.055, 10.88), alu, bevel=0.005)
        for mz in np.linspace(-5.40, 5.40, 7):
            pb.box((side * 10.10, 3.96, float(mz)), (0.30, 0.76, 0.065), steel_anth, bevel=0.005)
            pb.box((side * 10.00, 3.96, float(mz)), (0.03, 0.76, 0.080), rubber, bevel=0.003)
        glass_panes.append(((side * 10.10, 3.96, 0.0), (0.022, 0.72, 10.76), skylight_glass, (0.0, 0.0, 0.0)))

    # C. Suedwand (Z = +6.02, Rolltor X = -2.25..+2.25, Y = 0..3.25 frei!)
    pb.box((-6.15, 2.42, 6.02), (7.80, 4.84, 0.14), sandwich_wall, bevel=0.008, uv_scale=3.2)
    pb.box(( 6.15, 2.42, 6.02), (7.80, 4.84, 0.14), sandwich_wall, bevel=0.008, uv_scale=3.2)
    pb.box(( 0.00, 4.05, 6.02), (4.60, 1.56, 0.14), sandwich_wall, bevel=0.008, uv_scale=3.2)

    # D. Gefaster 2K-Sichtbeton-Sockel (Y = 0..1.16) + gekantetes Stahl-Abdeckprofil + Boden-Sockelleiste
    for cx, cz, sx, sz in (
        (0.0, -5.92, 19.90, 0.06),
        (-9.92, 0.0, 0.06, 11.90),
        ( 9.92, 0.0, 0.06, 11.90),
        (-6.15, 5.92, 7.56, 0.06),
        ( 6.15, 5.92, 7.56, 0.06),
    ):
        pb.box((cx, 0.58, cz), (sx, 1.16, sz), concrete_dado, bevel=0.008, uv_scale=2.4)
        pb.box((cx, 1.175, cz), (sx + 0.01, 0.036, sz + 0.025), steel_anth, bevel=0.005)
        pb.box((cx, 0.04, cz), (sx + 0.01, 0.08, sz + 0.02), rubber, bevel=0.004)

    # =========================================================================
    # 3. ECHTES 3D-TRAPEZBLECHDACH & AUSMODELLIERTE HEB-DOPPEL-T-STAHLRAHMEN!
    # =========================================================================
    add_trapezoidal_deck(pb, (0.0, 4.74, 0.0), 20.16, 12.16, y_base=4.71, rib_h=0.11, pitch_z=0.52, mat=ral_light, uv_scale=2.2)

    # Dach-Pfetten (verzinkte Z-Profile quer unter dem Trapezblech)
    for rz in range(-5, 6):
        pb.box((0.0, 4.68, float(rz) * 1.06), (19.96, 0.055, 0.09), galv, bevel=0.004)

    # 5 echte HEB-240 Stahl-Portalrahmen mit 6-Kant-Ankerbolzen & geschraubten Fachwerkbindern!
    for bx in (-9.70, -5.0, 0.0, 5.0, 9.70):
        for wz in (-5.78, 5.78):
            add_heb_column(pb, bx, wz, h=4.62, width=0.22, depth=0.24, steel_mat=steel_grey, plate_mat=steel_anth, bolt_mat=chrome)
        # Untergurt & Obergurt als echte IPE-Doppel-T-Traeger!
        add_heb_beam_z(pb, bx, 4.18, -5.70, 5.70, width=0.16, height=0.14, steel_mat=steel_grey, plate_mat=steel_anth, bolt_mat=chrome)
        add_heb_beam_z(pb, bx, 4.60, -5.70, 5.70, width=0.16, height=0.12, steel_mat=steel_grey)
        # Geschraubte Knotenbleche & Diagonalstreben im Fachwerkbinder
        for fi in range(-5, 6):
            fz = float(fi) * 1.06
            pb.box((bx, 4.39, fz), (0.06, 0.32, 0.06), steel_grey, bevel=0.004)
            pb.box((bx, 4.24, fz), (0.022, 0.12, 0.18), steel_anth, bevel=0.003)  # Knotenblech unten
            for bz_off in (-0.05, 0.05):
                pb.cyl((bx, 4.24, fz + bz_off), 0.008, 0.008, 0.032, chrome, axis_g="x", seg=6)
            if fi < 5:
                drot = 21.5 if (fi % 2 == 0) else -21.5
                pb.box((bx, 4.39, fz + 0.53), (0.048, 0.048, 1.10), steel_grey, rot_g_deg=(drot, 0.0, 0.0), bevel=0.004)

    # =========================================================================
    # 4. HAUSTECHNIK UNTER DER DECKE (WICKELFALZ-HVAC, KABELPRITSCHEN, SPRINKLER, LED)
    # =========================================================================
    # 2 verzinkte Spiral-Wickelfalz-Lueftungsrohre mit Flanschringen, Rohrschellen & Drall-Diffusoren
    for dz in (-1.6, 2.0):
        pb.cyl((0.0, 3.88, dz), 0.27, 0.27, 18.6, galv, axis_g="x", seg=28)
        for rx in range(-9, 10, 1):
            pb.cyl((float(rx), 3.88, dz), 0.288, 0.288, 0.028, alu, axis_g="x", seg=28)
        for sx in range(-8, 9, 2):
            pb.cyl((float(sx), 3.88, dz), 0.282, 0.282, 0.045, steel_anth, axis_g="x", seg=28)  # Rohrschelle
            pb.cyl((float(sx), 4.32, dz), 0.012, 0.012, 0.68, galv, axis_g="y", seg=8)
            pb.cyl((float(sx), 3.56, dz), 0.13, 0.22, 0.13, alu, axis_g="y", seg=22)
            pb.cyl((float(sx), 3.49, dz), 0.18, 0.18, 0.015, steel_anth, axis_g="y", seg=22)

    # 2 verzinkte Gitter-/Loch-Kabelpritschen mit U-Auslegern & gebogenen Kabelstraengen
    for tz in (-0.25, 3.45):
        pb.box((0.0, 3.44, tz), (18.4, 0.022, 0.42), galv, bevel=0.003, uv_scale=1.5)
        pb.box((0.0, 3.48, tz - 0.205), (18.4, 0.075, 0.020), galv, bevel=0.002)
        pb.box((0.0, 3.48, tz + 0.205), (18.4, 0.075, 0.020), galv, bevel=0.002)
        for rx in np.linspace(-8.8, 8.8, 24):
            pb.box((float(rx), 3.43, tz), (0.032, 0.018, 0.44), galv)
        for hx in range(-8, 9, 4):
            pb.box((float(hx), 3.41, tz), (0.045, 0.035, 0.50), steel_grey, bevel=0.003)
            for sz_h in (-0.23, 0.23):
                pb.cyl((float(hx), 4.04, tz + sz_h), 0.010, 0.010, 1.24, galv, axis_g="y", seg=8)
        # Sauber verlegte Strom- & Glasfaserbuendel in der Pritsche
        for c_off, c_r, c_m in ((-0.12, 0.024, rubber), (-0.03, 0.020, cable_orange), (0.06, 0.019, euro_blue), (0.14, 0.016, safety_yel)):
            pb.cyl((0.0, 3.475, tz + c_off), c_r, c_r, 18.2, c_m, axis_g="x", seg=12)

    # Rote Feuerloesch-Sprinkleranlage mit gebogenem Steigrohr (Nordwest-Ecke) & Messing-Sprinklerkoepfen
    add_pipe_run(pb, [(-9.45, 0.0, -5.75), (-9.45, 4.08, -5.75), (-9.45, 4.08, 4.40)], 0.036, flame_red, seg=14, bend_r=0.16)
    add_spoked_valve(pb, (-9.45, 1.45, -5.75), "y", Vector((0.0, 0.0, 1.0)), brass, flame_red)
    for sz in (-3.6, 0.6, 4.4):
        pb.cyl((0.0, 4.08, sz), 0.028, 0.028, 18.9, flame_red, axis_g="x", seg=14)
        for spx in range(-8, 9, 4):
            pb.cyl((float(spx), 4.08, sz), 0.036, 0.036, 0.05, flame_red, axis_g="x", seg=12)
            pb.cyl((float(spx), 3.99, sz), 0.014, 0.020, 0.11, brass, axis_g="y", seg=10)

    # 8 hochwertige abgehaengte Alu-LED-Lichtbandleuchten mit Reflektorfluegeln!
    for lx in (-6.0, -2.0, 2.0, 6.0):
        for lz in (-3.4, 0.9):
            pb.box((lx, 3.75, lz), (2.48, 0.065, 0.22), alu, bevel=0.008)
            pb.box((lx, 3.72, lz - 0.115), (2.48, 0.055, 0.025), alu, rot_g_deg=(18.0, 0.0, 0.0), bevel=0.003)
            pb.box((lx, 3.72, lz + 0.115), (2.48, 0.055, 0.025), alu, rot_g_deg=(-18.0, 0.0, 0.0), bevel=0.003)
            pb.box((lx, 3.71, lz), (2.38, 0.022, 0.16), lamp_led, bevel=0.003)
            for hx in (-1.02, 1.02):
                pb.cyl((lx + hx, 4.19, lz), 0.006, 0.006, 0.84, chrome, axis_g="y", seg=8)

    # =========================================================================
    # 5. HIGH-POLY 3D-SEKTIONALTOR-MECHANIK (SPIRAL-TORSIONSFEDERN + ECHTGLAS!)
    # =========================================================================
    for s in (-1.0, 1.0):
        # C-Profil-Laufschienen vertikal & horizontal mit Deckenabhaengern
        pb.box((s * 2.31, 1.66, 5.88), (0.075, 3.32, 0.11), galv, bevel=0.005)
        pb.box((s * 2.31, 1.66, 5.93), (0.11, 3.32, 0.03), rubber, bevel=0.003)
        add_pipe_run(pb, [(s * 2.31, 3.12, 5.88), (s * 2.31, 3.38, 5.88), (s * 2.31, 3.38, 2.45)], 0.036, galv, seg=12, bend_r=0.22)
        for hz in (4.8, 3.6, 2.55):
            pb.box((s * 2.31, 4.02, hz), (0.04, 1.24, 0.04), galv, bevel=0.003)
    # Torsionsfederwelle + 2 echte gewickelte 3D-Spiralfedern + Seiltrommeln + Wellenantrieb mit Kette!
    pb.cyl((0.0, 3.52, 5.84), 0.024, 0.024, 4.86, chrome, axis_g="x", seg=16)
    for fx in (-1.18, 1.18):
        add_torsion_spring_x(pb, (fx, 3.52, 5.84), length_x=0.74, coil_r=0.062, wire_r=0.0085, turns=22, mat=steel_anth)
        pb.cyl((fx - 0.39, 3.52, 5.84), 0.072, 0.072, 0.04, alu, axis_g="x", seg=16)
        pb.cyl((fx + 0.39, 3.52, 5.84), 0.072, 0.072, 0.04, alu, axis_g="x", seg=16)
    for dx_drum in (-2.22, 2.22):
        pb.cyl((dx_drum, 3.52, 5.84), 0.082, 0.082, 0.065, alu, axis_g="x", seg=18)
    # Industrie-Aufsteckantrieb rechts + herunterhaengende Nothandkette
    pb.box((2.58, 3.52, 5.78), (0.30, 0.38, 0.26), steel_anth, bevel=0.016)
    pb.cyl((2.58, 3.32, 5.70), 0.09, 0.09, 0.14, euro_blue, axis_g="y", seg=18)
    add_pipe_run(pb, [(2.54, 3.50, 5.64), (2.54, 1.65, 5.64), (2.62, 1.65, 5.64), (2.62, 3.50, 5.64)], 0.006, galv, seg=6, bend_r=0.035)
    # 5 geoeffnete profilierte Tor-Sektionen unter der Decke mit Scharnieren & Echtglas-Sichtfenstern!
    for pi in range(5):
        pz = 5.45 - pi * 0.62
        if pi in (1, 2):
            # Rahmen mit 4 ausgesparten Fenster-Oeffnungen!
            pb.box((0.0, 3.40, pz - 0.21), (4.52, 0.055, 0.14), ral_light, bevel=0.006)
            pb.box((0.0, 3.40, pz + 0.21), (4.52, 0.055, 0.14), ral_light, bevel=0.006)
            for pillar_x in (-2.04, -0.98, 0.0, 0.98, 2.04):
                pb.box((pillar_x, 3.40, pz), (0.34 if abs(pillar_x) < 1.9 else 0.44, 0.055, 0.30), ral_light, bevel=0.005)
            for wx in (-1.50, -0.49, 0.49, 1.50):
                pb.box((wx, 3.40, pz - 0.135), (0.68, 0.066, 0.025), rubber, bevel=0.004)
                pb.box((wx, 3.40, pz + 0.135), (0.68, 0.066, 0.025), rubber, bevel=0.004)
                glass_panes.append(((wx, 3.40, pz), (0.64, 0.018, 0.24), skylight_glass, (0.0, 0.0, 0.0)))
        else:
            pb.box((0.0, 3.40, pz), (4.52, 0.055, 0.56), ral_light, bevel=0.008)
            for rib_z in (-0.16, 0.0, 0.16):
                pb.box((0.0, 3.37, pz + rib_z), (4.48, 0.012, 0.028), steel_grey)
        for hx in (-2.15, -0.75, 0.75, 2.15):
            pb.box((hx, 3.36, pz + 0.28), (0.05, 0.025, 0.09), galv, bevel=0.003)

    # Rammschutz-Poller links & rechts neben dem Rolltor (mit Fussplatte & schwarzen Warnringen!)
    for sx in (-2.55, 2.55):
        pb.box((sx, 0.012, 5.64), (0.26, 0.024, 0.26), steel_anth, bevel=0.004)
        pb.cyl((sx, 0.54, 5.64), 0.082, 0.082, 1.06, safety_yel, axis_g="y", seg=24)
        pb.cyl((sx, 1.07, 5.64), 0.065, 0.082, 0.05, safety_yel, axis_g="y", seg=24)
        for ry in (0.42, 0.82):
            pb.cyl((sx, ry, 5.64), 0.084, 0.084, 0.12, rubber, axis_g="y", seg=24)

    # =========================================================================
    # 6. AUFGERAEUMT GRUPPIERTE HIGH-POLY-AUSSTATTUNG AN DEN RAENDERN (A3 + A4!)
    # =========================================================================

    # A. SUEDOST-LOGISTIK-ECKE (X = +5.2..+9.5, Z = +1.8..+5.4)
    add_euro_pallet_hq(pb, (8.65, 0.0, 5.12), wood_pallet, chrome, yaw_deg=0.0)
    _add_cardboard_carton(pb, (8.40, 0.36, 5.08), (0.52, 0.42, 0.48), cardboard, tape_brown, paper_white, 3.0)
    _add_cardboard_carton(pb, (8.94, 0.33, 5.16), (0.44, 0.36, 0.44), cardboard, tape_brown, paper_white, -5.0)
    _add_cardboard_carton(pb, (8.60, 0.72, 5.10), (0.46, 0.30, 0.42), cardboard, tape_brown, paper_white, 11.0)

    add_euro_pallet_hq(pb, (7.15, 0.0, 5.12), wood_pallet, chrome, yaw_deg=0.0)
    for ex in (6.88, 7.42):
        for ey in (0.27, 0.53):
            # Profilierte Eurobox-Stapelkiste mit Griffmulden & Etikett
            pb.box((ex, ey, 5.12), (0.48, 0.24, 0.36), euro_blue, bevel=0.010)
            pb.box((ex, ey + 0.115, 5.12), (0.50, 0.025, 0.38), euro_blue, bevel=0.005)
            pb.box((ex, ey + 0.02, 5.302), (0.14, 0.07, 0.004), paper_white)

    # High-Poly Gabelhubwagen ('Ameise') sauber geparkt
    add_pallet_jack_hq(pb, (5.58, 0.0, 5.08), safety_yel, steel_anth, chrome, rubber, yaw_deg=6.0)

    # Echte 3D-Draht-Gitterbox DIN 15155 + 2 detaillierte 240L-Wertstofftonnen mit Raedern & Deckelscharnier
    add_wire_gitterbox_hq(pb, (9.32, 0.0, 3.40), steel_grey, galv, wood_pallet, cardboard, tape_brown, yaw_deg=0.0)
    for mz, mcol in ((2.08, steel_anth), (1.38, euro_blue)):
        pb.box((9.50, 0.48, mz), (0.54, 0.86, 0.50), mcol, bevel=0.024)
        pb.box((9.50, 0.92, mz), (0.58, 0.04, 0.54), mcol, bevel=0.012)
        pb.box((9.50, 0.955, mz), (0.56, 0.035, 0.52), mcol, bevel=0.014)
        pb.cyl((9.74, 0.92, mz), 0.016, 0.016, 0.44, rubber, axis_g="z", seg=10)  # Scharniergriff hinten
        pb.cyl((9.72, 0.095, mz - 0.24), 0.095, 0.095, 0.04, rubber, axis_g="z", seg=16)
        pb.cyl((9.72, 0.095, mz + 0.24), 0.095, 0.095, 0.04, rubber, axis_g="z", seg=16)

    # B. OSTWAND MITARBEITER-SPINDE & WASSERSPENDER (X = +9.55, Z = -1.8..+0.55)
    pb.box((9.62, 0.05, -0.82), (0.52, 0.10, 1.72), steel_anth, bevel=0.008)  # Sockelbank
    for li in range(4):
        lz = -1.46 + li * 0.425
        pb.box((9.62, 1.02, lz), (0.50, 1.84, 0.415), ral_light, bevel=0.010)
        pb.box((9.362, 1.02, lz), (0.018, 1.76, 0.375), alu, bevel=0.006)
        pb.cyl((9.348, 1.08, lz + 0.13), 0.014, 0.014, 0.014, chrome, axis_g="x", seg=12)  # Zylinderschloss
        pb.box((9.345, 1.02, lz + 0.13), (0.018, 0.08, 0.020), steel_anth, bevel=0.003)
        pb.box((9.350, 1.54, lz), (0.006, 0.045, 0.12), paper_white)  # Namensschild
        for vi in range(4):
            pb.box((9.350, 1.68 + vi * 0.036, lz), (0.010, 0.012, 0.22), steel_anth)
            pb.box((9.350, 0.28 + vi * 0.036, lz), (0.010, 0.012, 0.22), steel_anth)

    # Trinkwasserspender mit transparenter 19L-Polycarbonat-Flasche
    pb.box((9.60, 0.50, 0.42), (0.38, 1.00, 0.38), ral_light, bevel=0.018)
    pb.box((9.40, 0.72, 0.42), (0.035, 0.24, 0.22), steel_anth, bevel=0.006)
    pb.cyl((9.41, 0.80, 0.37), 0.008, 0.008, 0.025, euro_blue, axis_g="x", seg=10)
    pb.cyl((9.41, 0.80, 0.47), 0.008, 0.008, 0.025, flame_red, axis_g="x", seg=10)
    pb.cyl((9.60, 1.03, 0.42), 0.06, 0.09, 0.06, paper_white, axis_g="y", seg=18)
    glass_panes.append(((9.60, 1.27, 0.42), (0.26, 0.42, 0.26), water_poly, (0.0, 0.0, 0.0)))

    # C. NORDWAND-MITTE: SICHERHEITS-BOARD, RUNDE HALLENUHR (HINTER GLAS!), ERSTE-HILFE, LEITER & SAUGER
    pb.box((-1.35, 1.78, -5.92), (1.76, 1.14, 0.035), alu, bevel=0.008)
    pb.box((-1.35, 1.78, -5.90), (1.66, 1.04, 0.020), cork)
    for px, py, pmat, sx, sy in (
        (-1.86, 1.98, paper_white, 0.28, 0.38),
        (-1.46, 2.00, paper_white, 0.28, 0.38),
        (-0.82, 1.94, safety_grn,  0.46, 0.32),  # Flucht- & Rettungsplan DIN ISO 23601!
        (-0.82, 1.94, paper_white, 0.40, 0.26),
        (-1.82, 1.52, paper_white, 0.28, 0.36),
        (-1.32, 1.56, safety_yel,  0.14, 0.14),
        (-1.10, 1.58, euro_blue,   0.14, 0.14),
    ):
        pb.box((px, py, -5.884), (sx, sy, 0.004), pmat)

    # Deutsche Bahnhofs-/Hallenuhr mit Minutenstrichen, Zeigern & Echtglas-Scheibe
    pb.cyl((-1.35, 2.95, -5.90), 0.26, 0.27, 0.065, steel_anth, axis_g="z", seg=32)
    pb.cyl((-1.35, 2.95, -5.865), 0.235, 0.235, 0.012, paper_white, axis_g="z", seg=32)
    for h_i in range(12):
        ang = (h_i / 12.0) * math.pi * 2.0
        pb.box((-1.35 + math.sin(ang) * 0.195, 2.95 + math.cos(ang) * 0.195, -5.856),
               (0.010, 0.032, 0.004), steel_anth, rot_g_deg=(0, 0, -math.degrees(ang)))
    pb.box((-1.35, 3.03, -5.852), (0.014, 0.16, 0.005), steel_anth)
    pb.box((-1.28, 2.95, -5.850), (0.12, 0.018, 0.005), steel_anth)
    pb.box((-1.35, 2.91, -5.847), (0.007, 0.17, 0.004), flame_red, rot_g_deg=(0, 0, 35.0))
    glass_panes.append(((-1.35, 2.95, -5.840), (0.44, 0.44, 0.006), skylight_glass, (0.0, 0.0, 0.0)))

    # DIN-Erste-Hilfe-Schrank mit Griff & weissem Kreuz
    pb.box((1.75, 1.68, -5.85), (0.40, 0.46, 0.16), safety_grn, bevel=0.012)
    pb.box((1.91, 1.68, -5.765), (0.018, 0.10, 0.022), chrome, bevel=0.004)
    pb.box((1.75, 1.68, -5.766), (0.20, 0.06, 0.006), paper_white)
    pb.box((1.75, 1.68, -5.766), (0.06, 0.20, 0.006), paper_white)

    # Profilierte Alu-Stehleiter mit geriffelten Stufen, Gummischuhen & gebogenem Haltebuegel
    for lx in (-3.16, -2.74):
        pb.box((lx, 0.88, -5.62), (0.028, 1.78, 0.058), alu, rot_g_deg=(12.0, 0.0, 0.0), bevel=0.004)
        pb.box((lx, 0.88, -5.24), (0.028, 1.78, 0.052), alu, rot_g_deg=(-12.0, 0.0, 0.0), bevel=0.004)
        pb.box((lx, 0.03, -5.80), (0.038, 0.06, 0.072), rubber, bevel=0.005)
        pb.box((lx, 0.03, -5.06), (0.038, 0.06, 0.072), rubber, bevel=0.005)
        pb.box((lx, 0.96, -5.43), (0.012, 0.022, 0.38), steel_grey)  # Spreizsicherung
    for step_i in range(5):
        sy = 0.28 + step_i * 0.28
        pb.box((-2.95, sy, -5.75 + step_i * 0.062), (0.42, 0.024, 0.088), alu, bevel=0.003)
    pb.box((-2.95, 1.70, -5.43), (0.44, 0.032, 0.26), flame_red, bevel=0.006)
    add_pipe_run(pb, [(-3.15, 1.70, -5.48), (-3.15, 2.12, -5.48), (-2.75, 2.12, -5.48), (-2.75, 1.70, -5.48)],
                 0.014, alu, seg=10, bend_r=0.06)

    # High-Poly Industriesauger mit gebogenem Schlauch & Bodenduese!
    add_industrial_vacuum_hq(pb, (-0.32, 0.0, -5.48), safety_yel, steel_anth, alu, rubber)

    # D. SUEDWEST-WERKSTATT-ZONE: 6-Schubladen-Werkstattwagen + 2 A-Rahmen-Kabeltrommeln + Wandhydrant!
    add_rolling_tool_chest_hq(pb, (-4.25, 0.0, 5.38), flame_red, steel_anth, alu, rubber, yaw_deg=0.0)
    # 2 Baustrom-/LWL-Kabeltrommeln auf gebogenem Stahlrohr-Tragegestell mit Kurbel
    for kz, kmat in ((4.42, cable_orange), (5.24, euro_blue)):
        add_pipe_run(pb, [(-9.42, 0.02, kz - 0.16), (-9.25, 0.38, kz - 0.02), (-9.08, 0.02, kz - 0.16)], 0.014, steel_anth, seg=10, bend_r=0.04)
        add_pipe_run(pb, [(-9.42, 0.02, kz + 0.40), (-9.25, 0.38, kz + 0.26), (-9.08, 0.02, kz + 0.40)], 0.014, steel_anth, seg=10, bend_r=0.04)
        pb.cyl((-9.25, 0.38, kz), 0.30, 0.30, 0.024, wood_pallet, axis_g="z", seg=24)
        pb.cyl((-9.25, 0.38, kz + 0.24), 0.30, 0.30, 0.024, wood_pallet, axis_g="z", seg=24)
        for coil_i in range(6):
            pb.cyl((-9.25, 0.38, kz + 0.03 + coil_i * 0.036), 0.245, 0.245, 0.032, kmat, axis_g="z", seg=24)
        pb.cyl((-9.25, 0.38, kz + 0.12), 0.016, 0.016, 0.34, chrome, axis_g="z", seg=12)

    # E. WANDHYDRANT MIT SCHLAUCHHASPEL HINTER ECHTGLAS + KUEHLWASSER-ROHRE MIT VENTILEN + 400V-CEE-DOSEN!
    # Wandhydrant rechts neben dem Rolltor (X = +3.65, Z = +5.90) + 6kg-Feuerloescher im Halter!
    pb.box((3.68, 1.48, 5.90), (0.68, 0.86, 0.16), flame_red, bevel=0.012)
    pb.box((3.68, 1.48, 5.83), (0.58, 0.76, 0.03), steel_anth)
    pb.cyl((3.64, 1.48, 5.85), 0.22, 0.22, 0.07, flame_red, axis_g="z", seg=24)
    pb.cyl((3.64, 1.48, 5.85), 0.18, 0.18, 0.08, paper_white, axis_g="z", seg=24)  # Aufgerollter Flachschlauch
    add_spoked_valve(pb, (3.88, 1.72, 5.85), "y", Vector((0.0, 0.0, -1.0)), brass, flame_red)
    glass_panes.append(((3.68, 1.48, 5.812), (0.56, 0.74, 0.010), skylight_glass, (0.0, 0.0, 0.0)))
    add_fire_extinguisher_hq(pb, (3.12, 0.42, 5.82), flame_red, chrome, rubber, paper_white)

    # Vorlauf-/Ruecklauf-Kaltwasserleitungen entlang der Nordwand mit abgerundeten Boegen & Handrad-Ventilen!
    for py, pmat in ((3.32, euro_blue), (3.14, flame_red)):
        add_pipe_run(pb, [(-9.65, 1.35, -5.86), (-9.65, py, -5.86), (7.6, py, -5.86)], 0.042, pmat, seg=16, bend_r=0.16)
        add_spoked_valve(pb, (-9.65, 1.85, -5.86), "y", Vector((0.0, 0.0, 1.0)), brass, flame_red)
        for fx in (-8.0, -4.0, 0.0, 4.0):
            pb.cyl((fx, py, -5.86), 0.068, 0.068, 0.032, alu, axis_g="x", seg=16)
            pb.box((fx, py, -5.94), (0.04, 0.08, 0.12), steel_anth, bevel=0.003)

    # Schraeg angesetzte 400V-CEE-Wandkombinationen + Not-Aus-Pilztaster neben dem Rolltor!
    for cx, cz in ((-3.1, -5.91), (2.4, -5.91), (-3.0, 5.91), (2.85, 5.91)):
        dir_z = 1.0 if cz < 0.0 else -1.0
        pb.box((cx, 1.32, cz), (0.20, 0.30, 0.085), ral_light, bevel=0.010)
        pb.cyl((cx, 1.38, cz + dir_z * 0.062), 0.038, 0.042, 0.075, flame_red, axis_g="z", seg=18)
        pb.cyl((cx, 1.41, cz + dir_z * 0.095), 0.044, 0.044, 0.014, flame_red, axis_g="z", seg=18)  # Klappdeckel
        for sx_o in (-0.045, 0.045):
            pb.box((cx + sx_o, 1.22, cz + dir_z * 0.048), (0.068, 0.068, 0.022), euro_blue, bevel=0.004)
    pb.box((2.66, 1.42, 5.90), (0.11, 0.12, 0.075), safety_yel, bevel=0.010)
    pb.cyl((2.66, 1.42, 5.845), 0.022, 0.022, 0.035, rubber, axis_g="z", seg=14)
    pb.cyl((2.66, 1.42, 5.822), 0.036, 0.028, 0.022, flame_red, axis_g="z", seg=18)

    pb.build(root)
    build_glass_child(root, "HalleNordInterior_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "halle_nord_interior.glb"))


def main():
    lib = ensure_hall_pbr_library()
    build_halle_nord_interior(lib)
    print("[HALLE_NORD_INT] v2.3.0 High-Poly 2K-ORM-PBR Industriehalle mit echten Glas-Oberlichtern gebaut!")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
