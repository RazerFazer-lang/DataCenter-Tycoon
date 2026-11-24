"""Blender 5.2 AAA-Generator fuer den Grossstandort 'Halle Nord' (Tier-4 Enterprise Datacenter Campus):
  1. assets/models/halle_nord_exterior.glb      (Architektur-Fassade MIT durchgebrochenen Oberlicht-Baendern
                                                 passend zum Innenraum, Glas-NOC-Erker, Chiller-Farm, Dachkuehler)
  2. assets/models/halle_nord_diesel_gen.glb    (Massiver 2-MVA Notstrom-Dieselgenerator im Akustik-Container)
  3. assets/models/halle_nord_gatehouse.glb     (Sicherheits-Pfoertnerhaus, Schranke, Ausweis-Terminal & Pylon)
  4. assets/models/halle_nord_switchgear.glb    (High-Poly 3-Feld 400V/8.500W Rittal-Schaltanlage mit 2K-UI,
                                                 Kupfer-Sammelschienen hinter Glas, 16 CEE-Dosen & Busbar-Kamin)
  5. assets/models/halle_nord_core_rack.glb     (High-Poly 42U 10G/100G Optical-Fiber Core-Rack mit geschwungenen
                                                 3D-LWL-Patchkabel-Boegen, 19"-Schienen, Echtglastuer & USV)
  6. assets/models/halle_nord_noc_wall.glb      (High-Poly Stahl-Echtglas-NOC-Trennwand, Eichen-Akustiklamellen,
                                                 gebogene 3-Monitor-2K-Videowall, Sideboard & Aktenschrank)
  7. assets/models/halle_nord_shuttle_kiosk.glb (High-Poly gebuersteter Alu/Anthrazit Biometrie- & Shuttle-Kiosk)
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

from build_delivery_van import PartBuilder, _save_rgb, make_solid_mat
from build_exterior_world import (
    CACHE_DIR,
    _height_to_normal,
    ensure_exterior_textures,
    make_pbr_tex_mat,
)
from hall_pbr_kit import (
    OUT_MODELS_DIR,
    add_pipe_run,
    add_spoked_valve,
    build_glass_child,
    ensure_hall_pbr_library,
    export_glb,
    make_emissive_mat,
    make_orm_mat,
    make_real_glass_mat,
    make_screen_tex_mat,
    reset_scene,
)


def ensure_dark_trapez_textures():
    """Generiert edle anthrazitfarbene Architektur-Trapezblech-PBR-Texturen fuer Halle Nord."""
    os.makedirs(CACHE_DIR, exist_ok=True)
    p_alb = os.path.join(CACHE_DIR, "hn_trapez_dark_alb.png")
    p_nrm = os.path.join(CACHE_DIR, "hn_trapez_dark_nrm.png")
    if not (os.path.exists(p_alb) and os.path.exists(p_nrm)):
        s = 512
        rng = np.random.default_rng(707)
        xs = np.linspace(0.0, 14.0 * math.pi * 2.0, s, endpoint=False)
        wave = np.clip(np.sin(xs) * 1.45, -1.0, 1.0)
        hgt = (wave * 0.5 + 0.5)[None, :].repeat(s, axis=0).astype(np.float32)
        fine = rng.uniform(-0.015, 0.015, (s, s)).astype(np.float32)
        base = np.zeros((s, s, 3), dtype=np.float32)
        shade = 0.145 + hgt * 0.068 + fine
        base[:, :, 0] = shade * 0.92
        base[:, :, 1] = shade * 1.00
        base[:, :, 2] = shade * 1.14
        base[s // 2 - 1 : s // 2 + 1, :, :] *= 0.62
        hgt[s // 2 - 1 : s // 2 + 1, :] = 0.15
        _save_rgb(p_alb, np.clip(base, 0.0, 1.0))
        _save_rgb(p_nrm, _height_to_normal(hgt, strength=4.2))
    return (p_alb, p_nrm)


# ---------------------------------------------------------------------------
# 1. HALLE NORD EXTERIOR — MIT ECHTEN OBERLICHT-FENSTEROEFFNUNGEN (Y=3.56..4.36)
# ---------------------------------------------------------------------------

def build_halle_nord_exterior(tex: dict, dark_trapez, lib: dict):
    reset_scene()
    root = bpy.data.objects.new("HalleNordExteriorRoot", None)
    bpy.context.scene.collection.objects.link(root)

    clinker = make_pbr_tex_mat("HN_Clinker", *tex["clinker"], rough=0.82, metal=0.0, normal_strength=1.05)
    trapez = make_pbr_tex_mat("HN_DarkTrapez", *dark_trapez, rough=0.36, metal=0.58, normal_strength=1.35)
    concrete = make_orm_mat("HN_Concrete2K", lib["concrete"], normal_strength=1.0)
    steel_dark = make_orm_mat("HN_SteelDark", lib["steel_anthracite"], normal_strength=0.75)
    alu_brush = make_orm_mat("HN_AluBrush", lib["alu_anodized"], normal_strength=0.55)
    galv = make_orm_mat("HN_Galv", lib["galv"], normal_strength=0.80)
    rubber = make_orm_mat("HN_Rubber", lib["rubber_black"], normal_strength=0.85)
    amber = make_orm_mat("HN_Amber", lib["safety_yellow"], normal_strength=0.65)
    pipe_blue = make_orm_mat("HN_PipeBlue", lib["euro_blue"], normal_strength=0.65)

    accent_trim = make_solid_mat("HN_AccentTrim", (0.24, 0.30, 0.36), rough=0.34, metal=0.72)
    copper = make_solid_mat("HN_Copper", (0.74, 0.43, 0.22), rough=0.28, metal=0.90)
    green_led = make_emissive_mat("HN_GreenLed", (0.15, 0.94, 0.42), strength=1.5)
    red_led = make_emissive_mat("HN_RedLed", (0.94, 0.16, 0.14), strength=1.5)
    lamp_glow = make_emissive_mat("HN_LampGlow", (1.0, 0.95, 0.84), strength=1.25)
    glass_lobby = make_emissive_mat("HN_LobbyGlow", (0.94, 0.88, 0.74), strength=0.32, rough=0.25)
    glass_ext = make_real_glass_mat("HN_GlassExt", rgb=(0.14, 0.24, 0.34), alpha=0.32, rough=0.05, metal=0.18)

    pb = PartBuilder("HalleNordExterior", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # A. SUEDFASSADE (Z = +6.22) — Rolltor X=-2.25..+2.25, Y=0..3.25 frei!
    pb.box((-6.28, 0.62, 6.22), (7.98, 1.24, 0.14), clinker, bevel=0.015, uv_scale=1.8)
    pb.box(( 4.02, 0.62, 6.22), (3.44, 1.24, 0.14), clinker, bevel=0.015, uv_scale=1.8)
    pb.box((-6.28, 1.27, 6.25), (8.02, 0.08, 0.20), concrete, bevel=0.01, uv_scale=2.0)
    pb.box(( 4.02, 1.27, 6.25), (3.48, 0.08, 0.20), concrete, bevel=0.01, uv_scale=2.0)
    pb.box((-6.28, 3.20, 6.22), (7.98, 3.80, 0.12), trapez, bevel=0.015, uv_scale=1.7)
    pb.box(( 6.28, 3.20, 6.22), (7.98, 3.80, 0.12), trapez, bevel=0.015, uv_scale=1.7)
    pb.box(( 0.00, 4.18, 6.22), (4.60, 1.84, 0.12), trapez, bevel=0.015, uv_scale=1.7)

    for fx in (-9.7, -9.2, -8.7, -8.2, -3.55, -3.15, 3.15, 3.55, 4.75, 5.15):
        pb.box((fx, 3.30, 6.32), (0.075, 3.35, 0.16), alu_brush, bevel=0.008)
    pb.box((0.0, 4.96, 6.30), (20.52, 0.11, 0.07), accent_trim, bevel=0.005)
    pb.box((0.0, 4.82, 6.28), (20.56, 0.06, 0.08), alu_brush, bevel=0.005)

    # B. WEST-, OST- & NORDFASSADE MIT DURCHGEBROCHENEN OBERLICHTERN (Y = 3.56..4.36)!
    for side in (-1.0, 1.0):
        wx = side * 10.22
        pb.box((wx, 0.62, 0.0), (0.14, 1.24, 12.56), clinker, bevel=0.015, uv_scale=1.8)
        pb.box((wx, 1.27, 0.0), (0.20, 0.08, 12.60), concrete, bevel=0.01, uv_scale=2.0)
        # Unteres Trapezblech bis Y = 3.56 + oberes Trapezblech Y = 4.36..5.10 + Eckpfeiler -> Fenster Z=-5.4..+5.4 frei!
        pb.box((wx, 2.43, 0.0), (0.12, 2.26, 12.56), trapez, bevel=0.012, uv_scale=1.7)
        pb.box((wx, 4.73, 0.0), (0.12, 0.74, 12.56), trapez, bevel=0.012, uv_scale=1.7)
        for sz_end in (-1.0, 1.0):
            pb.box((wx, 3.96, sz_end * 5.84), (0.12, 0.80, 0.88), trapez, bevel=0.010, uv_scale=1.7)
        # Aeussere Alu-Fensterbank mit Tropfkante am Oberlichtband
        pb.box((side * 10.28, 3.54, 0.0), (0.14, 0.05, 10.96), alu_brush, bevel=0.005)
        pb.box((side * 10.29, 4.96, 0.0), (0.06, 0.11, 12.60), accent_trim, bevel=0.005)
        for pz in (-5.5, -2.75, 0.0, 2.75, 5.5):
            pb.box((side * 10.28, 1.78, pz), (0.14, 3.56, 0.18), steel_dark, bevel=0.012)
        # Außen-Wetterschutzgitter auf Y = 2.42 (unterhalb des Oberlichtbands!)
        for gz in (-3.2, 2.8):
            pb.box((side * 10.30, 2.42, gz), (0.08, 0.78, 2.30), steel_dark, bevel=0.01)
            for li in range(5):
                pb.box((side * 10.34, 2.12 + li * 0.15, gz), (0.03, 0.045, 2.16), alu_brush, bevel=0.003)

    # Nordfassade (Z = -6.22): Oberlicht X = -9.40..+9.40, Y = 3.56..4.36 komplett frei!
    pb.box((0.0, 0.62, -6.22), (20.58, 1.24, 0.14), clinker, bevel=0.015, uv_scale=1.8)
    pb.box((0.0, 1.27, -6.25), (20.62, 0.08, 0.20), concrete, bevel=0.01, uv_scale=2.0)
    pb.box((0.0, 2.43, -6.22), (20.58, 2.26, 0.12), trapez, bevel=0.012, uv_scale=1.7)
    pb.box((0.0, 4.73, -6.22), (20.58, 0.74, 0.12), trapez, bevel=0.012, uv_scale=1.7)
    for side in (-1.0, 1.0):
        pb.box((side * 9.84, 3.96, -6.22), (0.88, 0.80, 0.12), trapez, bevel=0.010, uv_scale=1.7)
    pb.box((0.0, 3.54, -6.28), (18.96, 0.05, 0.14), alu_brush, bevel=0.005)
    pb.box((0.0, 4.96, -6.29), (20.58, 0.11, 0.06), accent_trim, bevel=0.005)

    # C. VERGLASTER 2-GESCHOSSIGER EMPFANGS- & NOC-ERKER RECHTS
    pb.box((7.98, 2.75, 6.72), (4.56, 5.50, 0.96), steel_dark, bevel=0.02)
    pb.box((8.02, 3.92, 7.12), (4.06, 1.72, 0.03), glass_lobby, bevel=0.004)
    glass_panes.append(((8.02, 3.92, 7.18), (4.16, 1.84, 0.025), glass_ext, (0.0, 0.0, 0.0)))
    for mx in (6.65, 8.02, 9.38):
        pb.box((mx, 3.92, 7.21), (0.07, 1.92, 0.08), alu_brush, bevel=0.005)
    pb.box((8.02, 2.94, 7.21), (4.36, 0.12, 0.12), alu_brush, bevel=0.008)
    pb.box((6.95, 1.28, 7.18), (1.36, 2.48, 0.08), alu_brush, bevel=0.01)
    glass_panes.append(((6.95, 1.28, 7.21), (1.14, 2.26, 0.025), glass_ext, (0.0, 0.0, 0.0)))
    pb.box((7.42, 1.15, 7.26), (0.035, 0.72, 0.06), alu_brush, bevel=0.004)
    pb.box((6.06, 1.22, 7.26), (0.18, 0.34, 0.08), steel_dark, bevel=0.008)
    pb.box((6.06, 1.12, 7.31), (0.05, 0.03, 0.02), green_led, bevel=0.002)
    pb.box((8.92, 1.48, 7.13), (1.76, 2.02, 0.03), glass_lobby, bevel=0.004)
    glass_panes.append(((8.92, 1.48, 7.19), (1.88, 2.15, 0.025), glass_ext, (0.0, 0.0, 0.0)))
    pb.box((7.98, 0.07, 7.42), (4.65, 0.14, 0.62), concrete, bevel=0.015, uv_scale=1.8)
    pb.box((7.98, 2.74, 7.72), (4.50, 0.10, 1.18), steel_dark, rot_g_deg=(4.0, 0.0, 0.0), bevel=0.012)
    glass_panes.append(((7.98, 2.78, 7.74), (4.20, 0.03, 0.96), glass_ext, (4.0, 0.0, 0.0)))
    for lx in (6.95, 8.95):
        pb.box((lx, 2.67, 7.70), (0.45, 0.035, 0.14), lamp_glow, bevel=0.004)
    pb.box((7.98, 5.56, 6.72), (4.72, 0.18, 1.12), alu_brush, bevel=0.015)

    # D. DACH-ATTIKA + RUECKKUEHLWERK + WARTUNGSSTEG + FALLROHRE MIT ROHRBOFGEN
    pb.box((0.0, 5.26, 0.0), (20.88, 0.42, 12.84), steel_dark, bevel=0.025)
    pb.box((0.0, 5.50, 0.0), (20.98, 0.08, 12.94), alu_brush, bevel=0.012)
    for sz in (6.46, -6.46):
        pb.cyl((0.0, 5.04, sz), 0.08, 0.08, 20.88, galv, axis_g="x", seg=18)
    for dx, dz in ((-10.05, 6.38), (10.05, 6.38), (-10.05, -6.38), (10.05, -6.38)):
        out_z = 0.16 if dz > 0 else -0.16
        add_pipe_run(pb, [(dx, 5.02, dz), (dx, 0.22, dz), (dx, 0.10, dz + out_z)], 0.055, galv, seg=14, bend_r=0.10)

    pb.box((-1.5, 6.18, 3.25), (14.6, 1.32, 0.10), steel_dark, bevel=0.015)
    pb.box((-1.5, 6.18, -3.45), (14.6, 1.32, 0.10), steel_dark, bevel=0.015)
    pb.box((-8.8, 6.18, -0.10), (0.10, 1.32, 6.75), steel_dark, bevel=0.015)
    pb.box(( 5.8, 6.18, -0.10), (0.10, 1.32, 6.75), steel_dark, bevel=0.015)
    for li in range(4):
        pb.box((-1.5, 5.74 + li * 0.28, 3.31), (14.4, 0.06, 0.05), alu_brush, bevel=0.004)
    for rx in (-6.4, -3.1, 0.2, 3.5):
        pb.box((rx, 6.12, -0.55), (2.45, 1.24, 2.10), galv, bevel=0.03)
        pb.box((rx, 6.76, -0.55), (2.52, 0.08, 2.16), steel_dark, bevel=0.01)
        for fx in (-0.62, 0.62):
            pb.cyl((rx + fx, 6.96, -0.55), 0.48, 0.44, 0.34, steel_dark, axis_g="y", seg=22)
            pb.cyl((rx + fx, 7.12, -0.55), 0.42, 0.42, 0.03, rubber, axis_g="y", seg=22)
    pb.box((-1.5, 5.62, 1.65), (13.6, 0.08, 1.05), galv, bevel=0.01)
    pb.box((-1.5, 6.56, 2.15), (13.6, 0.045, 0.045), alu_brush, bevel=0.005)
    for gx in (-8.0, -5.0, -2.0, 1.0, 4.0, 5.2):
        pb.box((gx, 6.10, 2.15), (0.045, 0.96, 0.045), alu_brush, bevel=0.005)
    for kx in (-7.8, -6.5):
        pb.cyl((kx, 6.65, -4.4), 0.28, 0.26, 2.40, alu_brush, axis_g="y", seg=20)
        pb.cyl((kx, 7.88, -4.4), 0.36, 0.28, 0.18, steel_dark, axis_g="y", seg=20)
    pb.cyl((8.2, 7.25, 4.4), 0.075, 0.055, 3.60, alu_brush, axis_g="y", seg=16)
    pb.cyl((8.2, 8.65, 4.4), 0.04, 0.04, 0.95, alu_brush, axis_g="y", seg=12)
    pb.box((8.2, 8.20, 4.65), (0.20, 0.85, 0.10), alu_brush, bevel=0.01)
    pb.cyl((8.2, 9.18, 4.4), 0.07, 0.07, 0.14, red_led, axis_g="y", seg=14)

    # E. ROLLTOR-PORTAL, STAHL-GLAS-VORDACH, AMPEL & AUSSEN-CHILLER
    for s in (-1.0, 1.0):
        pb.box((s * 2.30, 1.64, 6.28), (0.18, 3.30, 0.22), steel_dark, bevel=0.012)
        pb.box((s * 2.22, 1.64, 6.18), (0.06, 3.24, 0.10), rubber, bevel=0.005)
        pb.cyl((s * 2.52, 0.58, 6.54), 0.095, 0.095, 1.16, amber, axis_g="y", seg=22)
        pb.cyl((s * 2.52, 0.92, 6.54), 0.098, 0.098, 0.14, rubber, axis_g="y", seg=22)
        pb.cyl((s * 2.52, 0.46, 6.54), 0.098, 0.098, 0.14, rubber, axis_g="y", seg=22)
    pb.box((2.58, 2.75, 6.38), (0.22, 0.48, 0.16), steel_dark, bevel=0.012)
    pb.cyl((2.58, 2.86, 6.47), 0.065, 0.065, 0.03, red_led, axis_g="z", seg=16)
    pb.cyl((2.58, 2.64, 6.47), 0.065, 0.065, 0.03, green_led, axis_g="z", seg=16)

    pb.box((0.0, 3.52, 7.12), (5.60, 0.14, 1.85), steel_dark, rot_g_deg=(4.0, 0.0, 0.0), bevel=0.015)
    glass_panes.append(((0.0, 3.58, 7.14), (5.16, 0.035, 1.56), glass_ext, (4.0, 0.0, 0.0)))
    for sx in (-2.35, 2.35):
        pb.box((sx, 4.18, 7.05), (0.045, 0.045, 1.95), alu_brush, rot_g_deg=(36.0, 0.0, 0.0), bevel=0.006)
    for lx in (-1.8, -0.6, 0.6, 1.8):
        pb.box((lx, 3.43, 7.10), (0.48, 0.04, 0.18), lamp_glow, bevel=0.005)

    pb.box((0.0, 4.30, 6.30), (5.40, 0.72, 0.09), steel_dark, bevel=0.015)
    pb.box((0.0, 4.66, 6.33), (5.44, 0.045, 0.05), alu_brush, bevel=0.004)
    pb.box((0.0, 3.94, 6.33), (5.44, 0.045, 0.05), alu_brush, bevel=0.004)
    for lx in (-6.6, -3.8, 3.8):
        pb.box((lx, 3.25, 6.32), (0.28, 0.42, 0.18), steel_dark, bevel=0.012)
        pb.box((lx, 3.04, 6.34), (0.20, 0.04, 0.12), lamp_glow, bevel=0.004)
        pb.box((lx, 3.46, 6.34), (0.20, 0.04, 0.12), lamp_glow, bevel=0.004)

    for cx in (-8.1, -5.2):
        pb.box((cx, 0.14, 7.05), (2.35, 0.28, 1.18), concrete, bevel=0.018, uv_scale=1.8)
        pb.box((cx, 1.24, 7.05), (2.16, 1.92, 0.96), steel_dark, bevel=0.03)
        pb.box((cx, 1.24, 7.50), (2.00, 1.66, 0.06), alu_brush, bevel=0.012)
        pb.box((cx, 2.24, 7.05), (2.22, 0.10, 1.02), alu_brush, bevel=0.012)
        for fx in (-0.54, 0.54):
            pb.cyl((cx + fx, 1.28, 7.55), 0.43, 0.43, 0.07, steel_dark, axis_g="z", seg=24)
            pb.cyl((cx + fx, 1.28, 7.58), 0.37, 0.37, 0.04, rubber, axis_g="z", seg=22)
            for b_ang in (0, 45, 90, 135):
                pb.box((cx + fx, 1.28, 7.59), (0.70, 0.045, 0.02), alu_brush, rot_g_deg=(0, 0, float(b_ang)), bevel=0.003)
        add_pipe_run(pb, [(cx + 0.85, 0.72, 6.80), (cx + 0.85, 0.72, 6.18)], 0.052, pipe_blue, seg=14)
        add_pipe_run(pb, [(cx + 0.85, 0.96, 6.80), (cx + 0.85, 0.96, 6.18)], 0.048, copper, seg=14)
        pb.box((cx - 0.85, 1.96, 7.54), (0.24, 0.14, 0.04), green_led, bevel=0.004)

    pb.build(root)
    build_glass_child(root, "HalleNordExterior_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "halle_nord_exterior.glb"))


# ---------------------------------------------------------------------------
# 2. NOTSTROM-DIESELGENERATOR 2 MVA (2K ORM-PBR)
# ---------------------------------------------------------------------------

def build_diesel_generator(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("DieselGenRoot", None)
    bpy.context.scene.collection.objects.link(root)

    concrete = make_orm_mat("DG_Concrete", lib["concrete"], normal_strength=1.0)
    body = make_orm_mat("DG_Body", lib["steel_grey"], normal_strength=0.75)
    steel_dark = make_orm_mat("DG_SteelDark", lib["steel_anthracite"], normal_strength=0.75)
    galv = make_orm_mat("DG_Galv", lib["galv"], normal_strength=0.80)
    yellow = make_orm_mat("DG_Yellow", lib["safety_yellow"], normal_strength=0.65)
    red_sign = make_orm_mat("DG_Red", lib["flame_red"], normal_strength=0.65)
    chrome = make_solid_mat("DG_Chrome", (0.80, 0.83, 0.86), rough=0.16, metal=0.95)
    green_led = make_emissive_mat("DG_GreenLed", (0.14, 0.94, 0.42), strength=2.0)
    meter = make_screen_tex_mat("DG_Meter", lib["meter_screen_tex"], em_strength=1.2)

    pb = PartBuilder("DieselGenerator", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.14, 0.0), (5.90, 0.28, 2.70), concrete, bevel=0.025, uv_scale=2.0)
    pb.box((0.0, 0.48, 0.0), (5.40, 0.42, 2.26), steel_dark, bevel=0.02)
    pb.box((0.0, 1.67, 0.0), (5.36, 1.96, 2.22), body, bevel=0.03)
    pb.box((0.0, 0.82, 0.0), (5.40, 0.16, 2.26), yellow, bevel=0.008)
    pb.box((0.0, 2.68, 0.0), (5.44, 0.12, 2.30), steel_dark, bevel=0.015)

    for sz in (-1.0, 1.0):
        for dx in (-1.55, 0.0, 1.55):
            pb.box((dx, 1.72, sz * 1.12), (1.32, 1.48, 0.04), steel_dark, bevel=0.01)
            pb.box((dx, 1.72, sz * 1.135), (1.24, 1.40, 0.03), body, bevel=0.008)
            pb.box((dx + 0.48, 1.66, sz * 1.16), (0.05, 0.22, 0.04), chrome, bevel=0.005)
        pb.box((2.15, 1.88, sz * 1.14), (0.58, 0.44, 0.05), steel_dark, bevel=0.008)
        pb.box((2.15, 1.88, sz * 1.17), (0.46, 0.30, 0.012), meter, uv_mode="front_y")
        pb.box((2.05, 2.16, sz * 1.16), (0.14, 0.05, 0.015), green_led, bevel=0.002)
        pb.box((2.15, 1.38, sz * 1.14), (0.34, 0.24, 0.02), red_sign, bevel=0.003)

    pb.box((-2.70, 1.72, 0.0), (0.08, 1.58, 1.86), steel_dark, bevel=0.012)
    for li in range(9):
        pb.box((-2.74, 1.04 + li * 0.17, 0.0), (0.04, 0.065, 1.74), galv, bevel=0.004)
    pb.box((2.70, 1.85, 0.0), (0.08, 1.24, 1.72), steel_dark, bevel=0.012)
    for li in range(7):
        pb.box((2.74, 1.34 + li * 0.17, 0.0), (0.04, 0.065, 1.60), galv, bevel=0.004)

    for ez in (-0.42, 0.42):
        pb.cyl((-0.35, 3.06, ez), 0.24, 0.24, 2.25, chrome, axis_g="x", seg=24)
        add_pipe_run(pb, [(-1.20, 3.06, ez), (-1.42, 3.22, ez), (-1.42, 4.28, ez)], 0.105, chrome, seg=18, bend_r=0.18)
        pb.box((-1.42, 4.32, ez), (0.28, 0.035, 0.24), steel_dark, rot_g_deg=(0, 0, 18.0), bevel=0.004)
        for rx in (-1.0, 0.3):
            pb.box((rx, 2.84, ez), (0.08, 0.28, 0.08), steel_dark, bevel=0.005)
    pb.box((1.55, 2.94, 0.0), (1.15, 0.42, 1.25), galv, bevel=0.02)

    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "halle_nord_diesel_gen.glb"))


# ---------------------------------------------------------------------------
# 3. SICHERHEITS-PFOERTNERHAUS + SCHRANKE + CAMPUS-PYLON
# ---------------------------------------------------------------------------

def build_gatehouse(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("GatehouseRoot", None)
    bpy.context.scene.collection.objects.link(root)

    concrete = make_orm_mat("GH_Concrete", lib["concrete"], normal_strength=1.0)
    steel_dark = make_orm_mat("GH_SteelDark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("GH_Alu", lib["alu_anodized"], normal_strength=0.55)
    amber = make_orm_mat("GH_Amber", lib["safety_yellow"], normal_strength=0.65)
    red = make_orm_mat("GH_Red", lib["flame_red"], normal_strength=0.65)
    white = make_solid_mat("GH_White", (0.94, 0.95, 0.96), rough=0.34, metal=0.05)
    glass = make_real_glass_mat("GH_Glass", rgb=(0.14, 0.24, 0.34), alpha=0.28, rough=0.05)
    green_led = make_emissive_mat("GH_GreenLed", (0.16, 0.94, 0.42), strength=2.0)
    screen = make_screen_tex_mat("GH_Screen", lib["noc_screen_tex"], em_strength=1.1)

    pb = PartBuilder("Gatehouse", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    pb.box((-4.75, 0.10, 0.0), (3.45, 0.20, 3.20), concrete, bevel=0.02, uv_scale=1.8)
    pb.box((-4.75, 0.68, 0.0), (2.95, 0.96, 2.55), steel_dark, bevel=0.02)
    glass_panes.append(((-4.75, 1.84, 0.0), (2.82, 1.36, 2.42), glass, (0.0, 0.0, 0.0)))
    for ex in (-6.12, -3.38):
        for ez in (-1.20, 1.20):
            pb.box((ex, 1.65, ez), (0.16, 2.90, 0.16), steel_dark, bevel=0.01)
    # Echte Inneneinrichtung im Pfoertnerhaus sichtbar durch das Echtglas!
    pb.box((-4.65, 0.96, 0.45), (1.85, 0.06, 0.72), alu, bevel=0.008)
    pb.box((-4.45, 1.28, 0.55), (0.76, 0.42, 0.04), steel_dark, bevel=0.006)
    pb.box((-4.45, 1.28, 0.52), (0.70, 0.36, 0.012), screen, uv_mode="front_y")
    pb.box((-3.85, 2.98, 0.0), (5.40, 0.26, 3.60), steel_dark, bevel=0.02)
    pb.box((-3.85, 3.13, 0.0), (5.48, 0.06, 3.68), alu, bevel=0.01)

    pb.box((-3.05, 0.56, 0.55), (0.44, 1.12, 0.40), amber, bevel=0.02)
    pb.box((-3.05, 1.14, 0.55), (0.48, 0.08, 0.44), steel_dark, bevel=0.01)
    pb.box((-3.05, 1.22, 0.55), (0.14, 0.10, 0.14), green_led, bevel=0.005)
    ang_deg = 76.0
    ang_rad = math.radians(ang_deg)
    pivot = Vector((-2.95, 0.96, 0.55))
    for seg_i in range(8):
        dist = 0.35 + seg_i * 0.56
        cx = pivot.x + math.cos(ang_rad) * dist
        cy = pivot.y + math.sin(ang_rad) * dist
        pb.box((cx, cy, pivot.z), (0.54, 0.095, 0.055), red if (seg_i % 2 == 0) else white,
               rot_g_deg=(0.0, 0.0, ang_deg), bevel=0.005)
    pb.box((3.05, 0.48, 0.55), (0.12, 0.96, 0.12), steel_dark, bevel=0.008)
    for px, pz in ((-3.25, 1.35), (-3.25, -0.35), (3.25, 1.35), (3.25, -0.35)):
        pb.cyl((px, 0.45, pz), 0.075, 0.075, 0.90, amber, axis_g="y", seg=18)

    pb.box((-3.15, 0.68, 2.05), (0.28, 1.36, 0.24), steel_dark, bevel=0.015)
    pb.box((4.65, 0.14, 0.30), (1.55, 0.28, 0.72), concrete, bevel=0.02)
    pb.box((4.65, 2.15, 0.30), (1.32, 3.85, 0.36), steel_dark, bevel=0.025)
    pb.box((4.65, 2.15, 0.30), (1.38, 3.88, 0.14), alu, bevel=0.012)

    pb.build(root)
    build_glass_child(root, "Gatehouse_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "halle_nord_gatehouse.glb"))


# ---------------------------------------------------------------------------
# 4. HIGH-POLY 3-FELD 400V / 8.500W RITTAL-SCHALTANLAGE (A9!)
# ---------------------------------------------------------------------------

def build_switchgear(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("SwitchgearRoot", None)
    bpy.context.scene.collection.objects.link(root)

    cab_light = make_orm_mat("SG_CabLight", lib["ral_light_grey"], normal_strength=0.70)
    cab_dark = make_orm_mat("SG_CabDark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("SG_Alu", lib["alu_anodized"], normal_strength=0.55)
    galv = make_orm_mat("SG_Galv", lib["galv"], normal_strength=0.80)
    yellow = make_orm_mat("SG_Yellow", lib["safety_yellow"], normal_strength=0.65)
    red = make_orm_mat("SG_Red", lib["flame_red"], normal_strength=0.65)
    rubber = make_orm_mat("SG_Rubber", lib["rubber_black"], normal_strength=0.85)
    copper = make_solid_mat("SG_Copper", (0.78, 0.44, 0.20), rough=0.22, metal=0.94)
    chrome = make_solid_mat("SG_Chrome", (0.82, 0.84, 0.87), rough=0.14, metal=0.96)
    green_led = make_emissive_mat("SG_GreenLed", (0.14, 0.95, 0.42), strength=2.2)
    amber_led = make_emissive_mat("SG_AmberLed", (0.98, 0.70, 0.12), strength=1.8)
    meter = make_screen_tex_mat("SG_MeterUI", lib["meter_screen_tex"], em_strength=1.45)
    win_glass = make_real_glass_mat("SG_WindowGlass", rgb=(0.55, 0.68, 0.78), alpha=0.24, rough=0.05)

    pb = PartBuilder("Switchgear", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # Schwerer 200mm Schaltschranksockel mit Gabelstapler-Blenden (2.48 x 0.16 x 0.68 m)
    pb.box((0.0, 0.08, 0.0), (2.48, 0.16, 0.68), cab_dark, bevel=0.012)
    for fx in (-1.12, 0.0, 1.12):
        pb.box((fx, 0.08, 0.342), (0.18, 0.10, 0.012), alu, bevel=0.003)

    # 3 Rittal-Schaltfelder (X = -0.80, 0.0, +0.80)
    for ix, cx in enumerate((-0.80, 0.0, 0.80)):
        pb.box((cx, 1.18, 0.0), (0.79, 2.06, 0.64), cab_dark, bevel=0.014)
        # Umlaufende schwarze EPDM-Tuerdichtung + abgesetztes lichtgraues Tuerblatt + 3 Aussenscharniere
        pb.box((cx, 1.18, 0.322), (0.74, 1.98, 0.012), rubber, bevel=0.004)
        if ix == 1:
            # Mittelfeld: Oberes & unteres Tuerblatt mit Sichtfenster auf echte 3D-Kupfer-Sammelschienen!
            pb.box((cx, 1.88, 0.334), (0.73, 0.58, 0.024), cab_light, bevel=0.008)
            pb.box((cx, 0.68, 0.334), (0.73, 1.00, 0.024), cab_light, bevel=0.008)
            pb.box((cx - 0.29, 1.38, 0.334), (0.15, 0.44, 0.024), cab_light, bevel=0.006)
            pb.box((cx + 0.29, 1.38, 0.334), (0.15, 0.44, 0.024), cab_light, bevel=0.006)
            pb.box((cx, 1.38, 0.323), (0.44, 0.40, 0.006), cab_dark)
            # 4 massive blanke Kupfer-Sammelschienen (L1, L2, L3, PEN) auf Stuetzisolatoren vor der Innenwand!
            for bi, by_bus in enumerate((1.50, 1.42, 1.34, 1.26)):
                pb.box((cx, by_bus, 0.333), (0.40, 0.026, 0.008), copper, bevel=0.002)
                for ins_x in (-0.15, 0.15):
                    pb.cyl((cx + ins_x, by_bus, 0.328), 0.013, 0.015, 0.010, red, axis_g="z", seg=12)
                    pb.cyl((cx + ins_x, by_bus, 0.339), 0.006, 0.006, 0.006, chrome, axis_g="z", seg=6)
            glass_panes.append(((cx, 1.38, 0.345), (0.42, 0.38, 0.006), win_glass, (0.0, 0.0, 0.0)))
        else:
            pb.box((cx, 1.18, 0.334), (0.73, 1.98, 0.024), cab_light, bevel=0.008)
            # Abschliessbarer Haupt-Lasttrennschalter (gelb/roter Knebelgriff)
            pb.box((cx - 0.18, 1.46, 0.352), (0.13, 0.13, 0.022), yellow, bevel=0.006)
            pb.cyl((cx - 0.18, 1.46, 0.368), 0.032, 0.036, 0.022, red, axis_g="z", seg=16)
            pb.box((cx - 0.18, 1.46, 0.384), (0.028, 0.11, 0.026), red, rot_g_deg=(0, 0, -28.0), bevel=0.004)

        for hy in (0.42, 1.18, 1.92):
            pb.cyl((cx - 0.365, hy, 0.342), 0.010, 0.010, 0.065, cab_dark, axis_g="y", seg=10)
        # Rittal-Schwenkhebelgriff mit Profilzylinder
        pb.box((cx + 0.30, 1.06, 0.354), (0.042, 0.20, 0.024), cab_dark, bevel=0.006)
        pb.box((cx + 0.30, 1.04, 0.370), (0.026, 0.13, 0.018), alu, bevel=0.004)

        # Oberes 3-Phasen-Netzanalyse-Instrument (gestochen scharfe 2K-Multimeter-UI!)
        pb.box((cx, 1.88, 0.352), (0.58, 0.30, 0.022), cab_dark, bevel=0.006)
        pb.box((cx - 0.09, 1.88, 0.366), (0.32, 0.18, 0.008), meter, uv_mode="side_x")
        pb.cyl((cx + 0.16, 1.93, 0.366), 0.014, 0.014, 0.010, green_led, axis_g="z", seg=14)
        pb.cyl((cx + 0.16, 1.87, 0.366), 0.014, 0.014, 0.010, green_led, axis_g="z", seg=14)
        pb.cyl((cx + 0.16, 1.81, 0.366), 0.014, 0.014, 0.010, amber_led if ix == 1 else green_led, axis_g="z", seg=14)

        # Gestanzte Filterluefter-Kiemen unten
        pb.box((cx, 0.44, 0.350), (0.34, 0.32, 0.016), cab_dark, bevel=0.006)
        for li in range(7):
            pb.box((cx, 0.32 + li * 0.040, 0.360), (0.29, 0.016, 0.010), ral_light := cab_light, bevel=0.002)

    # Durchgehende 16-fach 400V-CEE-Schwerlast-Abgangsleiste (exakt auf Y = 1.10, Z = 0.40 fuer Kabel-Port!)
    pb.box((0.0, 1.12, 0.362), (2.32, 0.20, 0.055), cab_dark, bevel=0.008)
    pb.box((0.0, 1.225, 0.368), (2.32, 0.036, 0.048), yellow, bevel=0.004)
    for si in range(16):
        sx = -1.05 + si * (2.10 / 15.0)
        # Schraeg nach unten geneigte rote 400V-CEE-Kraftsteckdose mit Klappdeckel!
        pb.box((sx, 1.11, 0.390), (0.072, 0.088, 0.018), alu, bevel=0.004)
        pb.cyl((sx, 1.10, 0.412), 0.028, 0.031, 0.046, red, axis_g="z", seg=16)
        pb.cyl((sx, 1.125, 0.434), 0.032, 0.032, 0.010, red, axis_g="z", seg=16)

    # Obere Schrankabdeckung + 3 verschraubte verzinkte Stromschienen-Steigkanaele mit Kran-Oesen!
    pb.box((0.0, 2.24, 0.0), (2.50, 0.06, 0.68), alu, bevel=0.008)
    for bx in (-0.80, 0.0, 0.80):
        pb.box((bx, 3.30, -0.05), (0.28, 2.10, 0.22), galv, bevel=0.010, uv_scale=1.5)
        for fy in (2.45, 3.15, 3.85):
            pb.box((bx, fy, -0.05), (0.32, 0.035, 0.26), cab_dark, bevel=0.004)
        pb.box((bx, 3.30, 0.065), (0.08, 1.96, 0.014), yellow, bevel=0.003)

    pb.build(root)
    build_glass_child(root, "Switchgear_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "halle_nord_switchgear.glb"))


# ---------------------------------------------------------------------------
# 5. HIGH-POLY 42U 10G/100G OPTICAL-FIBER CORE-RACK (GESCHWUNGENE LWL-BOEGEN!)
# ---------------------------------------------------------------------------

def build_core_rack(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("CoreRackRoot", None)
    bpy.context.scene.collection.objects.link(root)

    frame = make_orm_mat("CR_Frame", lib["steel_anthracite"], normal_strength=0.75)
    chassis = make_orm_mat("CR_Chassis", lib["steel_grey"], normal_strength=0.70)
    alu = make_orm_mat("CR_Alu", lib["alu_anodized"], normal_strength=0.55)
    tray_blue = make_orm_mat("CR_TrayBlue", lib["euro_blue"], normal_strength=0.65)
    fiber_yel = make_orm_mat("CR_FiberYel", lib["safety_yellow"], normal_strength=0.55)
    fiber_aqua = make_solid_mat("CR_FiberAqua", (0.12, 0.78, 0.88), rough=0.30, metal=0.05)
    lc_blue = make_solid_mat("CR_LcBlue", (0.16, 0.44, 0.86), rough=0.35, metal=0.05)
    green_led = make_emissive_mat("CR_GreenLed", (0.14, 0.96, 0.44), strength=2.2)
    cyan_led = make_emissive_mat("CR_CyanLed", (0.12, 0.78, 1.0), strength=1.8)
    ups_lcd = make_screen_tex_mat("CR_UpsLcd", lib["meter_screen_tex"], em_strength=1.3)
    glass_door = make_real_glass_mat("CR_GlassDoor", rgb=(0.12, 0.22, 0.30), alpha=0.22, rough=0.04, metal=0.12)

    pb = PartBuilder("CoreRack", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # 42U Schrankrahmen mit Nivellierfuessen & gelochten Seitenblechen (0.94 x 2.26 x 0.78 m)
    for fx in (-0.40, 0.40):
        for fz in (-0.32, 0.32):
            pb.cyl((fx, 0.02, fz), 0.028, 0.032, 0.04, alu, axis_g="y", seg=14)
    pb.box((0.0, 0.07, 0.0), (0.94, 0.08, 0.78), frame, bevel=0.012)
    pb.box((0.0, 2.22, 0.0), (0.94, 0.08, 0.78), frame, bevel=0.012)
    pb.box((-0.44, 1.14, 0.0), (0.06, 2.08, 0.76), frame, bevel=0.010)
    pb.box(( 0.44, 1.14, 0.0), (0.06, 2.08, 0.76), frame, bevel=0.010)
    pb.box((0.0, 1.14, -0.36), (0.84, 2.08, 0.05), frame, bevel=0.008)

    # 19"-EIA-Rasterschienen + seitliche Finger-Kabelfuehrungskanaele
    for sx in (-0.32, 0.32):
        pb.box((sx, 1.14, 0.26), (0.032, 1.98, 0.035), alu, bevel=0.003)
    for sx in (-0.38, 0.38):
        pb.box((sx, 1.14, 0.29), (0.055, 1.96, 0.065), frame, bevel=0.005)
        for fy in np.linspace(0.26, 2.00, 18):
            pb.box((sx, float(fy), 0.328), (0.058, 0.016, 0.022), frame, bevel=0.002)

    # Untere 2U Online-USV mit LCD-Display (Y = 0.24)
    pb.box((0.0, 0.24, -0.02), (0.62, 0.16, 0.62), chassis, bevel=0.008)
    pb.box((-0.14, 0.24, 0.295), (0.20, 0.08, 0.010), ups_lcd, uv_mode="side_x")
    pb.cyl((0.18, 0.24, 0.296), 0.012, 0.012, 0.010, green_led, axis_g="z", seg=12)

    # 6 hochdichte 10G/100G SFP28/QSFP28 Core-Switches & Patchpanels MIT GESCHWUNGENEN 3D-LWL-PATCHKABELN!
    for idx in range(6):
        sy = 0.50 + idx * 0.27
        pb.box((0.0, sy, -0.02), (0.62, 0.17, 0.60), chassis, bevel=0.006)
        pb.box((0.0, sy + 0.055, 0.285), (0.60, 0.026, 0.012), alu, bevel=0.002)
        for pi in range(10):
            px = -0.245 + pi * 0.054
            pb.box((px, sy - 0.015, 0.288), (0.038, 0.036, 0.018), frame, bevel=0.002)
            pb.box((px, sy - 0.015, 0.300), (0.020, 0.022, 0.014), lc_blue, bevel=0.002)
            pb.box((px, sy + 0.018, 0.292), (0.020, 0.008, 0.008), cyan_led if (idx + pi) % 3 != 0 else green_led)
            # Echte geschwungene LWL-Jumperkabel in die linken/rechten Fingerkanaele!
            if pi in (0, 2, 7, 9):
                target_x = -0.37 if pi < 5 else 0.37
                f_mat = fiber_yel if (idx % 2 == 0) else fiber_aqua
                add_pipe_run(pb, [
                    (px, sy - 0.015, 0.308),
                    (px, sy - 0.045, 0.348),
                    ((px + target_x) * 0.5, sy - 0.075, 0.342),
                    (target_x, sy - 0.085, 0.305),
                ], 0.0042, f_mat, seg=7, bend_r=0.035)

    # Elegante Alu-Rahmenglastuer mit Schwenkgriff & echtem Rauchglas (CoreRack_Glass)!
    pb.box((-0.41, 1.14, 0.378), (0.065, 2.06, 0.028), alu, bevel=0.006)
    pb.box(( 0.41, 1.14, 0.378), (0.065, 2.06, 0.028), alu, bevel=0.006)
    pb.box((0.0, 2.14, 0.378), (0.86, 0.065, 0.028), alu, bevel=0.006)
    pb.box((0.0, 0.14, 0.378), (0.86, 0.065, 0.028), alu, bevel=0.006)
    pb.box((0.39, 1.12, 0.398), (0.028, 0.18, 0.022), frame, bevel=0.005)
    glass_panes.append(((0.0, 1.14, 0.380), (0.75, 1.93, 0.010), glass_door, (0.0, 0.0, 0.0)))

    # Oberer blauer Glasfaser-Kabelkamin mit gelben LWL-Biegeradien-Fuehrungen
    pb.box((0.0, 3.30, -0.02), (0.36, 2.12, 0.24), tray_blue, bevel=0.012)
    for fy in (2.55, 3.25, 3.95):
        pb.box((0.0, fy, -0.02), (0.40, 0.035, 0.28), frame, bevel=0.004)
    pb.box((0.0, 2.34, 0.11), (0.30, 0.08, 0.06), fiber_yel, bevel=0.012)

    pb.build(root)
    build_glass_child(root, "CoreRack_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "halle_nord_core_rack.glb"))


# ---------------------------------------------------------------------------
# 6. VERGLASTE NOC-LEITSTAND-SUITE (ECHTGLAS + EICHENLAMELLEN + 2K VIDEOWALL)
# ---------------------------------------------------------------------------

def build_noc_wall(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("NocWallRoot", None)
    bpy.context.scene.collection.objects.link(root)

    steel_dark = make_orm_mat("NOC_SteelDark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("NOC_Alu", lib["alu_anodized"], normal_strength=0.55)
    wood_oak = make_orm_mat("NOC_WoodOak", lib["wood_oak"], normal_strength=1.0, coat=0.35)
    rubber = make_orm_mat("NOC_Rubber", lib["rubber_black"], normal_strength=0.80)
    folder_red = make_orm_mat("NOC_FolderRed", lib["flame_red"], normal_strength=0.5)
    folder_blu = make_orm_mat("NOC_FolderBlu", lib["euro_blue"], normal_strength=0.5)
    folder_grn = make_orm_mat("NOC_FolderGrn", lib["safety_green"], normal_strength=0.5)
    folder_yel = make_orm_mat("NOC_FolderYel", lib["safety_yellow"], normal_strength=0.5)
    chrome = make_solid_mat("NOC_Chrome", (0.84, 0.86, 0.89), rough=0.14, metal=0.96)
    mug_white = make_solid_mat("NOC_MugWhite", (0.95, 0.95, 0.93), rough=0.20, metal=0.0)
    center_scr = make_solid_mat("NOC_CenterScreen", (0.04, 0.08, 0.13), rough=0.12, metal=0.08,
                                emission=(0.05, 0.12, 0.20), em_strength=0.85)
    noc_ui = make_screen_tex_mat("NOC_TelemetryUI", lib["noc_screen_tex"], em_strength=1.35)
    glass_clear = make_real_glass_mat("NOC_GlassClear", rgb=(0.66, 0.80, 0.90), alpha=0.18, rough=0.03)
    glass_frost = make_real_glass_mat("NOC_GlassFrost", rgb=(0.82, 0.88, 0.94), alpha=0.44, rough=0.32)

    pb = PartBuilder("NocWall", origin_g=Vector((0, 0, 0)))
    glass_panes = []

    # A. SUEDLICHE STAHL-GLAS-TRENNWAND (Z = -2.65, Durchgang X = 4.85..6.45 offen, Edelstahl-Klemmbeschlaege!)
    pb.box((8.20, 0.04, -2.65), (3.54, 0.08, 0.09), steel_dark, bevel=0.008)
    pb.box((7.35, 2.72, -2.65), (5.26, 0.10, 0.10), steel_dark, bevel=0.008)
    pb.box((7.35, 3.16, -2.65), (5.26, 0.08, 0.09), steel_dark, bevel=0.008)
    for px in (4.76, 6.46, 8.20, 9.94):
        pb.box((px, 1.58, -2.65), (0.08, 3.16, 0.09), steel_dark, bevel=0.008)
    for gx in (7.33, 9.07):
        glass_panes.append(((gx, 1.38, -2.65), (1.65, 2.58, 0.014), glass_clear, (0.0, 0.0, 0.0)))
        glass_panes.append(((gx, 1.18, -2.65), (1.65, 0.28, 0.018), glass_frost, (0.0, 0.0, 0.0)))
        # 4 gebuerstete Edelstahl-Glasklemmbeschlaege pro Scheibe!
        for bx_off in (-0.76, 0.76):
            for by_c in (0.32, 2.42):
                pb.box((gx + bx_off, by_c, -2.65), (0.06, 0.045, 0.042), chrome, bevel=0.004)
    glass_panes.append(((7.35, 2.94, -2.65), (5.12, 0.35, 0.014), glass_clear, (0.0, 0.0, 0.0)))

    # B. WESTLICHE STAHL-GLAS-TRENNWAND (X = +4.76, Z = -5.94..-3.90)
    pb.box((4.76, 0.04, -4.92), (0.09, 0.08, 2.06), steel_dark, bevel=0.008)
    pb.box((4.76, 2.72, -4.30), (0.10, 0.10, 3.30), steel_dark, bevel=0.008)
    pb.box((4.76, 3.16, -4.30), (0.09, 0.08, 3.30), steel_dark, bevel=0.008)
    for pz in (-5.92, -3.90):
        pb.box((4.76, 1.58, pz), (0.08, 3.16, 0.09), steel_dark, bevel=0.008)
    glass_panes.append(((4.76, 1.38, -4.91), (0.014, 2.58, 1.93), glass_clear, (0.0, 0.0, 0.0)))
    glass_panes.append(((4.76, 1.18, -4.91), (0.018, 0.28, 1.93), glass_frost, (0.0, 0.0, 0.0)))
    glass_panes.append(((4.76, 2.94, -4.30), (0.014, 0.35, 3.16), glass_clear, (0.0, 0.0, 0.0)))

    # C. EDLE EICHEN-AKUSTIKLAMELLEN-WANDVERKLEIDUNG + GEBOGENE 3-SCREEN-2K-NOC-VIDEOWALL!
    pb.box((7.35, 1.78, -5.93), (4.60, 3.20, 0.022), rubber)
    for sx in np.linspace(5.12, 9.58, 42):
        pb.box((float(sx), 1.78, -5.905), (0.052, 3.16, 0.032), wood_oak, bevel=0.004, uv_scale=1.4)

    # VESA-Schwerlast-Traversenhalterung + 3 duennrahmige 55"-Monitore
    pb.box((7.35, 2.48, -5.86), (3.10, 0.24, 0.05), steel_dark, bevel=0.008)
    # Mittlerer Hauptmonitor (Hintergrund fuer das dynamische _halle_nord_noc_lbl bei Z = -5.79!)
    pb.box((7.35, 2.48, -5.825), (1.30, 0.98, 0.032), steel_dark, bevel=0.008)
    pb.box((7.35, 2.48, -5.805), (1.24, 0.92, 0.010), center_scr, bevel=0.002)
    # Linker & rechter eingewinkelter Telemetrie-Monitor mit gestochen scharfer 2K-NOC-Grafik!
    for lx, yaw in ((6.04, 12.0), (8.66, -12.0)):
        pb.box((lx, 2.48, -5.75), (1.16, 0.98, 0.032), steel_dark, rot_g_deg=(0, yaw, 0), bevel=0.008)
        pb.box((lx, 2.48, -5.730), (1.10, 0.92, 0.010), noc_ui, rot_g_deg=(0, yaw, 0), uv_mode="side_x")

    # D. KAFFEEBAR-SIDEBOARD MIT EICHENPLATTE & STAHL-AKTENSCHRANK MIT LEITZ-ORDNERN
    pb.box((9.28, 0.44, -5.12), (1.10, 0.84, 0.62), steel_dark, bevel=0.014)
    pb.box((9.28, 0.88, -5.12), (1.16, 0.048, 0.66), wood_oak, bevel=0.010, uv_scale=1.2)
    for dx in (8.99, 9.57):
        pb.box((dx, 0.44, -4.80), (0.51, 0.74, 0.020), alu, bevel=0.006)
        pb.box((dx, 0.72, -4.782), (0.18, 0.018, 0.022), chrome, bevel=0.004)
    for mx in (8.86, 8.99):
        pb.cyl((mx, 0.945, -5.02), 0.036, 0.033, 0.088, mug_white, axis_g="y", seg=18)
        add_pipe_run(pb, [(mx - 0.034, 0.965, -5.02), (mx - 0.056, 0.955, -5.02), (mx - 0.056, 0.930, -5.02), (mx - 0.034, 0.922, -5.02)],
                     0.005, mug_white, seg=8, bend_r=0.01)

    pb.box((9.62, 1.02, -3.65), (0.46, 2.04, 1.12), alu, bevel=0.012)
    f_mats = (folder_red, folder_blu, folder_grn, folder_yel, folder_blu, folder_red, folder_yel, folder_grn)
    for sy in (0.42, 0.84, 1.26, 1.68):
        pb.box((9.60, sy, -3.65), (0.42, 0.024, 1.06), steel_dark)
        for fi in range(8):
            fz = -4.08 + fi * 0.115
            pb.box((9.56, sy + 0.17, fz), (0.29, 0.30, 0.072), f_mats[fi], bevel=0.005)
            pb.box((9.412, sy + 0.22, fz), (0.004, 0.12, 0.052), mug_white)  # Rueckenschild + Griffloch
            pb.cyl((9.410, sy + 0.10, fz), 0.010, 0.010, 0.006, chrome, axis_g="x", seg=10)

    pb.cyl((8.15, 0.18, -4.55), 0.14, 0.11, 0.34, steel_dark, axis_g="y", seg=20)

    pb.build(root)
    build_glass_child(root, "NocWall_Glass", glass_panes)
    export_glb(os.path.join(OUT_MODELS_DIR, "halle_nord_noc_wall.glb"))


# ---------------------------------------------------------------------------
# 7. HIGH-POLY SHUTTLE- & BIOMETRIE-KIOSK
# ---------------------------------------------------------------------------

def build_shuttle_kiosk(lib: dict):
    reset_scene()
    root = bpy.data.objects.new("ShuttleKioskRoot", None)
    bpy.context.scene.collection.objects.link(root)

    steel_dark = make_orm_mat("SK_SteelDark", lib["steel_anthracite"], normal_strength=0.75)
    alu = make_orm_mat("SK_Alu", lib["alu_anodized"], normal_strength=0.55)
    chrome = make_solid_mat("SK_Chrome", (0.84, 0.86, 0.89), rough=0.14, metal=0.96)
    scr_bg = make_solid_mat("SK_Screen", (0.05, 0.12, 0.20), rough=0.10, metal=0.08,
                            emission=(0.08, 0.22, 0.36), em_strength=0.95)
    green_led = make_emissive_mat("SK_GreenLed", (0.16, 0.92, 0.44), strength=1.6)

    pb = PartBuilder("ShuttleKiosk", origin_g=Vector((0, 0, 0)))

    # Verschraubte Stahl-Bodenplatte mit 4 Sechskant-Ankern
    pb.box((0.0, 0.025, 0.0), (0.74, 0.05, 0.50), steel_dark, bevel=0.014)
    for bx in (-0.31, 0.31):
        for bz in (-0.19, 0.19):
            pb.cyl((bx, 0.056, bz), 0.012, 0.012, 0.014, chrome, axis_g="y", seg=6)
    # Gebuerstete Alu-Wangen + anthrazitfarbene Saeule
    pb.box((0.0, 0.80, -0.04), (0.54, 1.50, 0.22), steel_dark, bevel=0.024)
    for sx in (-0.29, 0.29):
        pb.box((sx, 0.82, -0.04), (0.045, 1.54, 0.25), alu, bevel=0.014)
    # Geneigtes 24"-Touch-Terminal (kompatibel mit _nord_shuttle_lbl auf Y=1.37, Z=0.135, rot_x=-12!)
    pb.box((0.0, 1.36, 0.075), (0.64, 0.72, 0.075), alu, rot_g_deg=(-12.0, 0.0, 0.0), bevel=0.018)
    pb.box((0.0, 1.36, 0.108), (0.58, 0.65, 0.020), steel_dark, rot_g_deg=(-12.0, 0.0, 0.0), bevel=0.008)
    pb.box((0.0, 1.36, 0.120), (0.53, 0.59, 0.008), scr_bg, rot_g_deg=(-12.0, 0.0, 0.0), bevel=0.003)
    # Ergonomisches RFID/NFC-Lesepult
    pb.box((0.0, 0.86, 0.17), (0.48, 0.055, 0.22), alu, rot_g_deg=(-18.0, 0.0, 0.0), bevel=0.012)
    pb.cyl((0.0, 0.892, 0.19), 0.068, 0.068, 0.012, steel_dark, axis_g="y", seg=24)
    pb.cyl((0.0, 0.898, 0.19), 0.052, 0.052, 0.008, green_led, axis_g="y", seg=24)

    pb.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "halle_nord_shuttle_kiosk.glb"))


def main():
    tex = ensure_exterior_textures()
    dark_trapez = ensure_dark_trapez_textures()
    lib = ensure_hall_pbr_library()
    build_halle_nord_exterior(tex, dark_trapez, lib)
    build_diesel_generator(lib)
    build_gatehouse(lib)
    build_switchgear(lib)
    build_core_rack(lib)
    build_noc_wall(lib)
    build_shuttle_kiosk(lib)
    print("[HALLE_NORD] Alle 7 Blender-5.2-AAA-Modelle inkl. Oberlicht-Durchbruechen & Echtglas gebaut!")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
