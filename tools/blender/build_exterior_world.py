"""Blender 5.2 Generator fuer die komplette deutsche Gewerbegebiets-Aussenwelt (Außenwelt 3.0):
  Gebaeude:
    - assets/models/ext_logistics_hall.glb      (Deutsche Logistikhalle mit 3 Laderampen, Sektionaltoren, Dachlueftern)
    - assets/models/ext_office_tech.glb         (2-stoeckiges Klinker/Beton-Buerogebaeude mit tiefen Glasfenstern)
    - assets/models/ext_substation_20kv.glb     (20-kV-Umspannwerk mit Aussen-Oeltrafo, Kuehlrippen & Isolatoren)
    - assets/models/ext_shipping_container.glb  (20ft Wellblech-Ueberseecontainer mit Eckbeschlaegen & Riegelstangen)
    - assets/models/ext_house_suburban.glb      (Deutsches Satteldach-Haus / kleine Werkstatt fuer Horizont)
  Begruenung (Baeume kommen aus build_nature_d.py):
    - assets/models/ext_hedge_bush.glb          (Organisch geformtes Hecken-Segment 2.4 m + Einzelbusch)
    - assets/models/ext_grass_tuft.glb          (Gras- & Unkrautbueschel fuer Bordstein & Zaunrand)
  Strasse & Details:
    - assets/models/ext_street_lamp.glb         (Deutsche Peitschen-Strassenlaterne mit LED-Kopf)
    - assets/models/ext_fence_panel.glb         (Anthrazit-Doppelstabmattenzaun 2.5 m mit Betonsockel)
    - assets/models/ext_hydrant.glb             (Deutscher roter Ueberflurhydrant)
    - assets/models/ext_manhole.glb             (Gusseiserner Gullydeckel / Kanaldeckel)
    - assets/models/ext_trash_bin.glb           (Deutsche 240L-Muelltonne + 1100L-Industriecontainer)
    - assets/models/ext_pallet_stack.glb        (Gestapelte Europaletten)
    - assets/models/ext_utility_box.glb         (Grauer deutscher Kabelverzweiger / Stromkasten)

Godot-Koordinaten: g(x, y, z) -> Blender (x, -z, y), Boden = Y 0.0.
"""

import math
import os
import random
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
    _load_img,
    _new_mat,
    _save_rgb,
    g,
    make_solid_mat,
)

OUT_MODELS_DIR = dct_paths.MODELS_DIR
CACHE_DIR = dct_paths.PBR_CACHE


def _reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for img in list(bpy.data.images):
        bpy.data.images.remove(img)


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
    print(f"[EXT_WORLD] Exported {os.path.basename(out_path)} ({size_kb:.1f} KB)")


def _height_to_normal(height: np.ndarray, strength: float = 3.0) -> np.ndarray:
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * strength
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * strength
    nz = np.ones_like(height)
    ln = np.sqrt(gx * gx + gy * gy + nz * nz) + 1e-6
    out = np.stack([(-gx / ln) * 0.5 + 0.5, (-gy / ln) * 0.5 + 0.5, (nz / ln) * 0.5 + 0.5], axis=-1)
    return np.clip(out, 0.0, 1.0)


def make_pbr_tex_mat(name: str, alb_path: str, norm_path: str = None, rough: float = 0.78,
                     metal: float = 0.0, normal_strength: float = 1.0):
    mat, nt, bsdf = _new_mat(name)
    t_alb = nt.nodes.new("ShaderNodeTexImage")
    t_alb.image = _load_img(alb_path, "sRGB")
    nt.links.new(t_alb.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if norm_path:
        t_nrm = nt.nodes.new("ShaderNodeTexImage")
        t_nrm.image = _load_img(norm_path, "Non-Color")
        nrm_node = nt.nodes.new("ShaderNodeNormalMap")
        nrm_node.inputs["Strength"].default_value = normal_strength
        nt.links.new(t_nrm.outputs["Color"], nrm_node.inputs["Color"])
        nt.links.new(nrm_node.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


# ---------------------------------------------------------------------------
# Prozedurale 1K PBR-Texturen (Klinker, Trapezblech, Beton, Dachziegel)
# ---------------------------------------------------------------------------

def ensure_exterior_textures() -> dict:
    os.makedirs(CACHE_DIR, exist_ok=True)
    paths = {}

    # 1. Deutscher Rot-Brauner Industrie-Klinker (Albedo + Normal)
    p_alb = os.path.join(CACHE_DIR, "ext_clinker_alb.png")
    p_nrm = os.path.join(CACHE_DIR, "ext_clinker_nrm.png")
    if not (os.path.exists(p_alb) and os.path.exists(p_nrm)):
        s = 512
        rng = np.random.default_rng(101)
        alb = np.zeros((s, s, 3), dtype=np.float32)
        hgt = np.ones((s, s), dtype=np.float32) * 0.85
        rows, cols = 16, 8
        rh, cw = s // rows, s // cols
        mortar = np.array([0.48, 0.46, 0.43], dtype=np.float32)
        alb[:, :] = mortar
        hgt[:, :] = 0.25
        noise = pbr_textures.fbm_tile(s, s, 16, 16, 4, seed=11)
        for r in range(rows):
            off = (cw // 2) if (r % 2 == 1) else 0
            y0, y1 = r * rh + 3, (r + 1) * rh - 2
            for c in range(cols + 1):
                x0 = (c * cw + off) % s
                base_col = np.array([
                    rng.uniform(0.38, 0.54),
                    rng.uniform(0.18, 0.27),
                    rng.uniform(0.13, 0.20),
                ], dtype=np.float32)
                for dx in range(3, cw - 2):
                    xx = (x0 + dx) % s
                    alb[y0:y1, xx] = base_col * (0.86 + 0.26 * noise[y0:y1, xx, None])
                    hgt[y0:y1, xx] = 0.82 + 0.14 * noise[y0:y1, xx]
        _save_rgb(p_alb, alb)
        _save_rgb(p_nrm, _height_to_normal(hgt, 3.8))
    paths["clinker"] = (p_alb, p_nrm)

    # 2. Industrie-Trapezblech (senkrechte Rippen fuer Hallen & Container)
    p_alb = os.path.join(CACHE_DIR, "ext_trapez_alb.png")
    p_nrm = os.path.join(CACHE_DIR, "ext_trapez_nrm.png")
    if not (os.path.exists(p_alb) and os.path.exists(p_nrm)):
        s = 512
        yy, xx = np.mgrid[0:s, 0:s]
        phase = (xx % 32) / 32.0
        rib = np.clip(1.0 - np.abs(phase - 0.5) * 4.5, 0.0, 1.0)
        grime = pbr_textures.fbm_tile(s, s, 8, 8, 4, seed=22)
        base = 0.72 + 0.14 * rib - 0.09 * (1.0 - grime)
        alb = np.stack([base * 0.96, base * 0.98, base * 1.02], axis=-1)
        # Dezente vertikale Schmutz-Ablaufstreifen
        streak = pbr_textures.fbm_tile(s, s, 4, 32, 3, seed=23)
        alb *= (0.92 + 0.10 * streak[:, :, None])
        _save_rgb(p_alb, alb)
        _save_rgb(p_nrm, _height_to_normal(rib * 0.85 + grime * 0.15, 5.2))
    paths["trapez"] = (p_alb, p_nrm)

    # 3. Sichtbeton / Fertigteil-Platten (fuer Logistikhalle, Bueros & Trafo)
    p_alb = os.path.join(CACHE_DIR, "ext_concrete_alb.png")
    p_nrm = os.path.join(CACHE_DIR, "ext_concrete_nrm.png")
    if not (os.path.exists(p_alb) and os.path.exists(p_nrm)):
        s = 512
        n = pbr_textures.fbm_tile(s, s, 8, 8, 5, seed=33)
        fine = pbr_textures.fbm_tile(s, s, 32, 32, 3, seed=34)
        base = 0.56 + 0.14 * n + 0.05 * fine
        hgt = 0.75 + 0.15 * n + 0.06 * fine
        # Fertigteil-Fugen + Schalungsloecher
        for jy in (0, 256):
            base[jy:jy + 3, :] *= 0.68
            hgt[jy:jy + 3, :] = 0.25
        for jx in (0, 256):
            base[:, jx:jx + 3] *= 0.68
            hgt[:, jx:jx + 3] = 0.25
        alb = np.stack([base * 0.99, base * 0.99, base * 0.97], axis=-1)
        _save_rgb(p_alb, alb)
        _save_rgb(p_nrm, _height_to_normal(hgt, 2.8))
    paths["concrete"] = (p_alb, p_nrm)

    # 4. Rote deutsche Dachziegel (fuer Wohnhaeuser im Hintergrund)
    p_alb = os.path.join(CACHE_DIR, "ext_rooftile_alb.png")
    p_nrm = os.path.join(CACHE_DIR, "ext_rooftile_nrm.png")
    if not (os.path.exists(p_alb) and os.path.exists(p_nrm)):
        s = 512
        yy, xx = np.mgrid[0:s, 0:s]
        wave_x = 0.5 + 0.5 * np.sin(xx * (2.0 * math.pi / 32.0))
        step_y = (yy % 42) / 42.0
        n = pbr_textures.fbm_tile(s, s, 16, 16, 4, seed=44)
        hgt = 0.35 + 0.40 * wave_x + 0.25 * (1.0 - step_y)
        r = 0.54 + 0.14 * n - 0.10 * step_y
        g_ch = 0.20 + 0.07 * n - 0.05 * step_y
        b = 0.13 + 0.05 * n - 0.04 * step_y
        alb = np.stack([r, g_ch, b], axis=-1)
        _save_rgb(p_alb, alb)
        _save_rgb(p_nrm, _height_to_normal(hgt, 4.5))
    paths["rooftile"] = (p_alb, p_nrm)

    return paths


# ---------------------------------------------------------------------------
# 1. Große deutsche Logistikhalle (22 m x 7.2 m x 13 m)
#    Front schaut Richtung -Z (zur Strasse!), Ursprung mittig auf Y=0
# ---------------------------------------------------------------------------

def build_logistics_hall(tex: dict):
    _reset_scene()
    root = bpy.data.objects.new("LogisticsHallRoot", None)
    bpy.context.scene.collection.objects.link(root)

    concrete = make_pbr_tex_mat("Log_Concrete", *tex["concrete"], rough=0.86, metal=0.0, normal_strength=0.9)
    trapez = make_pbr_tex_mat("Log_Trapez", *tex["trapez"], rough=0.52, metal=0.35, normal_strength=1.1)
    clinker = make_pbr_tex_mat("Log_Clinker", *tex["clinker"], rough=0.84, metal=0.0, normal_strength=1.0)
    steel_dark = make_solid_mat("Log_SteelDark", (0.16, 0.19, 0.23), rough=0.45, metal=0.65)
    galv = make_solid_mat("Log_Galv", (0.62, 0.65, 0.68), rough=0.38, metal=0.78)
    amber = make_solid_mat("Log_Amber", (0.90, 0.56, 0.08), rough=0.42, metal=0.12)
    door_mat = make_solid_mat("Log_SecDoor", (0.28, 0.31, 0.35), rough=0.48, metal=0.55)
    rubber = make_solid_mat("Log_Rubber", (0.07, 0.075, 0.08), rough=0.85, metal=0.0)
    glass = make_solid_mat("Log_WindowGlass", (0.10, 0.16, 0.22), rough=0.08, metal=0.18, coat=0.95)
    roof_mat = make_solid_mat("Log_Roof", (0.22, 0.24, 0.26), rough=0.88, metal=0.10)

    pb = PartBuilder("LogisticsHall", origin_g=Vector((0, 0, 0)))

    # Betonsockel (Y = 0..1.55) + Trapezblech-Hallenkoerper (Y = 1.55..6.8)
    pb.box((0.0, 0.78, 0.0), (22.0, 1.56, 13.0), concrete, bevel=0.02, uv_scale=2.6)
    pb.box((0.0, 4.18, 0.0), (21.9, 5.26, 12.9), trapez, bevel=0.02, uv_scale=2.2)
    # Markante anthrazitfarbene Dach-Attika & gelber Firmenstreifen
    pb.box((0.0, 6.96, 0.0), (22.5, 0.42, 13.5), steel_dark, bevel=0.03)
    pb.box((0.0, 6.80, 0.0), (21.6, 0.12, 12.6), roof_mat, bevel=0.01)
    pb.box((0.0, 5.95, -6.48), (22.0, 0.34, 0.08), amber, bevel=0.012)
    # Stahlstuetzen (Pilaster) an der Fassade
    for px in (-10.8, -5.2, 0.4, 5.4, 10.8):
        pb.box((px, 3.45, -6.50), (0.28, 6.80, 0.18), steel_dark, bevel=0.015)

    # 3 vertiefte Laderampen / Sektionaltore (links/mitte, X = -7.8, -2.6, +2.6)
    for tx in (-7.8, -2.6, 2.6):
        # Tor-Rahmen + dunkle Torabdichtung (Dock Shelter)
        pb.box((tx, 2.15, -6.54), (3.65, 4.20, 0.28), rubber, bevel=0.02)
        pb.box((tx, 2.05, -6.48), (3.25, 3.90, 0.14), door_mat, bevel=0.015)
        # Horizontale Sektionaltor-Sicken + 4 Sichtfenster
        for sy in (0.75, 1.45, 2.15, 2.85, 3.45):
            pb.box((tx, sy, -6.56), (3.22, 0.05, 0.04), steel_dark, bevel=0.005)
        for wx in (-1.05, -0.35, 0.35, 1.05):
            pb.box((tx + wx, 2.52, -6.56), (0.52, 0.34, 0.04), glass, bevel=0.006)
        # Ueberlade-Vordach ueber jedem Tor + gelbe Anfahrschutz-Poller!
        pb.box((tx, 4.48, -7.25), (3.95, 0.16, 1.55), steel_dark, rot_g_deg=(6.0, 0.0, 0.0), bevel=0.015)
        for side in (-1.95, 1.95):
            pb.cyl((tx + side, 0.52, -7.05), 0.10, 0.10, 1.04, amber, axis_g="y", seg=12)
            pb.cyl((tx + side, 0.84, -7.05), 0.105, 0.105, 0.14, rubber, axis_g="y", seg=12)
        # Gummipuffer unten an der Rampe
        for side in (-1.25, 1.25):
            pb.box((tx + side, 0.55, -6.68), (0.28, 0.44, 0.22), rubber, bevel=0.02)

    # Rechter Buerotrakt (X = +5.6 .. +10.8): Klinker-Verkleidung + 2 Etagen echte gerahmte Fenster!
    pb.box((8.15, 3.40, -6.48), (5.15, 6.70, 0.14), clinker, bevel=0.02, uv_scale=2.0)
    for fy in (1.95, 4.45):
        for wx in (6.75, 9.45):
            pb.box((wx, fy, -6.56), (2.05, 1.38, 0.14), steel_dark, bevel=0.015)
            pb.box((wx, fy, -6.54), (1.84, 1.18, 0.08), glass, bevel=0.006)
            pb.box((wx, fy, -6.59), (0.06, 1.20, 0.06), steel_dark, bevel=0.004)
            pb.box((wx, fy - 0.72, -6.63), (2.15, 0.08, 0.18), galv, bevel=0.008) # Fensterbank

    # Regenrinne + 3 verzinkte Fallrohre
    pb.cyl((0.0, 6.72, -6.72), 0.08, 0.08, 22.4, galv, axis_g="x", seg=12)
    for dx in (-10.85, 5.45, 10.85):
        pb.cyl((dx, 3.36, -6.68), 0.06, 0.06, 6.72, galv, axis_g="y", seg=10)

    # 3 detaillierte Dach-Klima-/Lueftungsanlagen + Abluftkamine
    for hx, hz in ((-6.5, -1.5), (0.5, 1.2), (6.2, -0.5)):
        pb.box((hx, 7.52, hz), (2.6, 1.10, 1.9), galv, bevel=0.03)
        pb.box((hx, 7.52, hz - 0.96), (2.1, 0.72, 0.06), steel_dark, bevel=0.01)
        pb.cyl((hx - 0.65, 8.15, hz), 0.42, 0.42, 0.22, steel_dark, axis_g="y", seg=16)
        pb.cyl((hx + 0.65, 8.15, hz), 0.42, 0.42, 0.22, steel_dark, axis_g="y", seg=16)

    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_logistics_hall.glb"))


# ---------------------------------------------------------------------------
# 2. 2-stoeckiges deutsches Buerogebaeude / Tech-Zentrum (20 m x 8.4 m x 12 m)
# ---------------------------------------------------------------------------

def build_office_tech(tex: dict):
    _reset_scene()
    root = bpy.data.objects.new("OfficeTechRoot", None)
    bpy.context.scene.collection.objects.link(root)

    clinker = make_pbr_tex_mat("Off_Clinker", *tex["clinker"], rough=0.84, metal=0.0, normal_strength=1.0)
    concrete = make_pbr_tex_mat("Off_Concrete", *tex["concrete"], rough=0.80, metal=0.0, normal_strength=0.8)
    alu_dark = make_solid_mat("Off_AluDark", (0.14, 0.17, 0.22), rough=0.38, metal=0.72)
    alu_light = make_solid_mat("Off_AluLight", (0.68, 0.71, 0.75), rough=0.32, metal=0.82)
    glass = make_solid_mat("Off_WindowGlass", (0.10, 0.18, 0.26), rough=0.06, metal=0.22, coat=1.0)
    roof_mat = make_solid_mat("Off_Roof", (0.20, 0.22, 0.24), rough=0.88, metal=0.10)
    solar = make_solid_mat("Off_Solar", (0.06, 0.10, 0.20), rough=0.18, metal=0.50, coat=0.8)

    pb = PartBuilder("OfficeTech", origin_g=Vector((0, 0, 0)))

    # Erdgeschoss in Klinker, Obergeschoss in hellem Sichtbeton/Architektur-Putz
    pb.box((0.0, 2.05, 0.0), (20.0, 4.10, 12.0), clinker, bevel=0.02, uv_scale=2.2)
    pb.box((0.0, 6.05, 0.0), (20.2, 4.00, 12.2), concrete, bevel=0.02, uv_scale=2.6)
    # Stockwerk-Gesims + Dach-Attika
    pb.box((0.0, 4.08, 0.0), (20.5, 0.26, 12.5), alu_dark, bevel=0.02)
    pb.box((0.0, 8.20, 0.0), (20.6, 0.36, 12.6), alu_dark, bevel=0.025)
    pb.box((0.0, 8.05, 0.0), (19.6, 0.10, 11.6), roof_mat, bevel=0.01)

    # Tiefe gerahmte Fensterbaender an Front (-Z) und beiden Seiten (-X / +X)
    for fy in (2.15, 6.05):
        for wx in (-7.2, -3.8, 0.0, 3.8, 7.2):
            if fy < 3.0 and abs(wx) < 1.0:
                continue # Mitte EG = Haupteingang!
            pb.box((wx, fy, -6.12), (2.75, 1.85, 0.18), alu_dark, bevel=0.018)
            pb.box((wx, fy, -6.08), (2.52, 1.62, 0.08), glass, bevel=0.006)
            for mx in (-0.84, 0.84):
                pb.box((wx + mx, fy, -6.16), (0.06, 1.66, 0.06), alu_dark, bevel=0.004)
            pb.box((wx, fy - 0.96, -6.20), (2.86, 0.09, 0.22), alu_light, bevel=0.008)
        for side in (-1.0, 1.0):
            for wz in (-3.2, 0.0, 3.2):
                pb.box((side * 10.12, fy, wz), (0.18, 1.80, 2.35), alu_dark, bevel=0.015)
                pb.box((side * 10.08, fy, wz), (0.08, 1.58, 2.12), glass, bevel=0.006)

    # Moderner Glas-Haupteingang + freitragendes Vordach + Treppenstufen (Mitte -Z)
    pb.box((0.0, 1.60, -6.10), (3.20, 3.10, 0.18), alu_dark, bevel=0.018)
    pb.box((0.0, 1.60, -6.06), (2.92, 2.86, 0.08), glass, bevel=0.006)
    pb.box((0.0, 1.40, -6.14), (0.07, 2.80, 0.06), alu_light, bevel=0.004)
    pb.box((0.0, 3.40, -7.15), (4.20, 0.18, 2.15), alu_dark, bevel=0.02)
    for sx in (-1.85, 1.85):
        pb.cyl((sx, 1.70, -7.95), 0.075, 0.075, 3.40, alu_light, axis_g="y", seg=12)
    pb.box((0.0, 0.12, -6.95), (3.80, 0.24, 1.65), concrete, bevel=0.015)

    # Aufgestaenderte Solarmodule auf dem Flachdach (sichtbar aus der Ferne!)
    for row_z in (-2.5, 1.5):
        for sx in (-6.5, -2.2, 2.2, 6.5):
            pb.box((sx, 8.72, row_z), (3.6, 0.07, 1.8), solar, rot_g_deg=(24.0, 0.0, 0.0), bevel=0.01)
            pb.box((sx, 8.38, row_z + 0.45), (3.4, 0.52, 0.08), alu_light, bevel=0.006)

    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_office_tech.glb"))


# ---------------------------------------------------------------------------
# 3. Detailliertes 20-kV-Umspannwerk / Trafohaeuschen + Aussen-Oeltrafo
# ---------------------------------------------------------------------------

def build_substation_20kv(tex: dict):
    _reset_scene()
    root = bpy.data.objects.new("Substation20kVRoot", None)
    bpy.context.scene.collection.objects.link(root)

    concrete = make_pbr_tex_mat("Sub_Concrete", *tex["concrete"], rough=0.88, metal=0.0, normal_strength=1.0)
    steel_dark = make_solid_mat("Sub_SteelDark", (0.19, 0.22, 0.26), rough=0.48, metal=0.65)
    trafo_grey = make_solid_mat("Sub_TrafoGrey", (0.36, 0.40, 0.44), rough=0.45, metal=0.72)
    ceramic = make_solid_mat("Sub_Ceramic", (0.46, 0.24, 0.14), rough=0.20, metal=0.05, coat=0.7)
    copper = make_solid_mat("Sub_Copper", (0.78, 0.44, 0.22), rough=0.28, metal=0.92)
    warn_yel = make_solid_mat("Sub_WarnYellow", (0.94, 0.74, 0.08), rough=0.38, metal=0.05)

    pb = PartBuilder("Substation20kV", origin_g=Vector((0, 0, 0)))

    # Gemeinsame Beton-Bodenplatte (7.6 m x 4.6 m)
    pb.box((0.0, 0.10, 0.0), (7.6, 0.20, 4.6), concrete, bevel=0.02, uv_scale=2.0)

    # Linker Teil: Beton-Schaltstation (X = -1.65)
    pb.box((-1.65, 1.58, 0.0), (4.0, 2.85, 3.4), concrete, bevel=0.025, uv_scale=2.0)
    pb.box((-1.65, 3.12, 0.0), (4.35, 0.26, 3.75), steel_dark, bevel=0.02)
    # Doppel-Stahltuer + Lueftungslamellen + Hochspannungs-Warnschild
    pb.box((-2.45, 1.32, -1.72), (1.32, 2.24, 0.08), steel_dark, bevel=0.012)
    pb.box((-2.45, 1.80, -1.77), (0.34, 0.30, 0.02), warn_yel, bevel=0.004)
    pb.box((-0.62, 1.48, -1.72), (1.35, 1.15, 0.09), steel_dark, bevel=0.012)
    for ly in np.linspace(1.00, 1.96, 8):
        pb.box((-0.62, float(ly), -1.78), (1.22, 0.05, 0.05), trafo_grey, rot_g_deg=(28.0, 0.0, 0.0), bevel=0.004)

    # Rechter Teil: Echter Aussen-Oeltransformator mit 16 Kuehlrippen, Ausdehnungsgefaess & 3 Keramik-Isolatoren!
    tx = 1.95
    pb.box((tx, 1.35, 0.0), (2.20, 2.10, 1.55), trafo_grey, bevel=0.03) # Hauptkessel
    pb.box((tx, 0.28, 0.0), (2.40, 0.16, 1.75), steel_dark, bevel=0.015) # Auffangwanne
    # 16 echte Kuehlrippen vorne & hinten
    for fi in range(8):
        fx = tx - 0.88 + fi * 0.25
        for side in (-1.0, 1.0):
            pb.box((fx, 1.35, side * 0.96), (0.045, 1.78, 0.34), trafo_grey, bevel=0.006)
    # Zylindrisches Oel-Ausdehnungsgefaess oben drauf
    pb.cyl((tx, 2.86, 0.42), 0.28, 0.28, 1.85, trafo_grey, axis_g="x", seg=16)
    for sx in (tx - 0.65, tx + 0.65):
        pb.box((sx, 2.55, 0.42), (0.10, 0.38, 0.14), steel_dark, bevel=0.008)
    # 3 gerippte Hochspannungs-Keramik-Isolatoren (20 kV Durchfuehrungen) + Kupfer-Sammelschienen!
    for ix in (tx - 0.62, tx, tx + 0.62):
        pb.cyl((ix, 2.82, -0.35), 0.075, 0.10, 0.92, ceramic, axis_g="y", seg=14)
        for ry in (2.52, 2.66, 2.80, 2.94, 3.08):
            pb.cyl((ix, ry, -0.35), 0.145, 0.12, 0.045, ceramic, axis_g="y", seg=14)
        pb.cyl((ix, 3.36, -0.35), 0.045, 0.045, 0.20, copper, axis_g="y", seg=10)
    # Kupfer-Verbindungsschiene zur Schaltstation
    pb.box((0.85, 3.42, -0.35), (2.40, 0.05, 0.08), copper, bevel=0.005)

    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_substation_20kv.glb"))


# ---------------------------------------------------------------------------
# 4. 20ft Wellblech-Ueberseecontainer (6.05 m x 2.59 m x 2.44 m)
# ---------------------------------------------------------------------------

def build_shipping_container(tex: dict):
    _reset_scene()
    root = bpy.data.objects.new("ContainerRoot", None)
    bpy.context.scene.collection.objects.link(root)

    paint = make_pbr_tex_mat("Container_PaintMat", *tex["trapez"], rough=0.62, metal=0.45, normal_strength=1.35)
    steel = make_solid_mat("Container_SteelMat", (0.20, 0.22, 0.24), rough=0.52, metal=0.72)
    chrome = make_solid_mat("Container_LatchMat", (0.68, 0.70, 0.73), rough=0.35, metal=0.88)

    pb = PartBuilder("Container", origin_g=Vector((0, 0, 0)))
    # Hauptkoerper + starke Eckrahmen
    pb.box((0.0, 1.30, 0.0), (5.96, 2.48, 2.36), paint, bevel=0.02, uv_scale=1.4)
    # 4 massive Eckpfosten + obere/untere Laengstraeger + ISO-Eckbeschlaege
    for sx in (-2.96, 2.96):
        for sz in (-1.16, 1.16):
            pb.box((sx, 1.30, sz), (0.14, 2.58, 0.14), paint, bevel=0.012)
            for sy in (0.09, 2.51):
                pb.box((sx, sy, sz), (0.18, 0.18, 0.18), steel, bevel=0.012)
    for sy in (0.08, 2.52):
        for sz in (-1.16, 1.16):
            pb.box((0.0, sy, sz), (6.02, 0.14, 0.14), paint, bevel=0.012)
    # 4 verzinkte Verriegelungsstangen an der Stirnseite (+X)
    for rz in (-0.78, -0.32, 0.32, 0.78):
        pb.cyl((3.04, 1.30, rz), 0.024, 0.024, 2.34, chrome, axis_g="y", seg=8)
        pb.box((3.05, 1.05, rz + 0.08), (0.04, 0.05, 0.22), chrome, bevel=0.005)

    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_shipping_container.glb"))


# ---------------------------------------------------------------------------
# 5. Deutsches Satteldach-Haus / kleine Werkstatt (fuer Hintergrund-Horizont)
# ---------------------------------------------------------------------------

def build_suburban_house(tex: dict):
    _reset_scene()
    root = bpy.data.objects.new("SuburbanHouseRoot", None)
    bpy.context.scene.collection.objects.link(root)

    plaster = make_solid_mat("House_PlasterMat", (0.86, 0.84, 0.79), rough=0.88, metal=0.0)
    clinker = make_pbr_tex_mat("House_BaseMat", *tex["clinker"], rough=0.85, metal=0.0, normal_strength=0.9)
    roof_mat = make_pbr_tex_mat("House_RoofMat", *tex["rooftile"], rough=0.76, metal=0.0, normal_strength=1.2)
    frame = make_solid_mat("House_FrameMat", (0.20, 0.22, 0.25), rough=0.45, metal=0.25)
    glass = make_solid_mat("House_GlassMat", (0.10, 0.16, 0.22), rough=0.08, metal=0.18, coat=0.9)
    wood = make_solid_mat("House_WoodMat", (0.34, 0.22, 0.14), rough=0.75, metal=0.0)

    pb = PartBuilder("SuburbanHouse", origin_g=Vector((0, 0, 0)))

    # Klinker-Sockel + 2-geschossiger Putzbau (11.5 m x 5.8 m x 8.4 m)
    pb.box((0.0, 0.55, 0.0), (11.5, 1.10, 8.4), clinker, bevel=0.02, uv_scale=2.0)
    pb.box((0.0, 3.35, 0.0), (11.4, 4.60, 8.3), plaster, bevel=0.02)

    # Echtes Satteldach (35 Grad Neigung) inkl. Giebel-Dreiecke & Dachueberstand!
    gable_stations = [
        (-6.20, [(5.55, -4.65), (8.65, 0.0), (5.55, 4.65)]),
        (6.20,  [(5.55, -4.65), (8.65, 0.0), (5.55, 4.65)]),
    ]
    pb.loft_x(gable_stations, plaster, cap_ends=True, smooth=False)
    # Zwei geneigte Ziegel-Dachflaechen mit Ueberstand
    pb.box((0.0, 7.18, -2.42), (12.8, 0.22, 5.70), roof_mat, rot_g_deg=(33.5, 0.0, 0.0), bevel=0.02, uv_scale=2.2)
    pb.box((0.0, 7.18,  2.42), (12.8, 0.22, 5.70), roof_mat, rot_g_deg=(-33.5, 0.0, 0.0), bevel=0.02, uv_scale=2.2)
    pb.box((0.0, 8.78, 0.0), (12.85, 0.22, 0.30), roof_mat, bevel=0.02) # Firstziegel
    # Schornstein
    pb.box((3.2, 8.45, 1.35), (0.72, 2.2, 0.72), clinker, bevel=0.015)

    # Gerahmte Fenster auf Vorder- & Rueckseite + Giebel
    for side in (-1.0, 1.0):
        for fy in (2.15, 4.45):
            for wx in (-3.6, 0.0, 3.6):
                if side < 0 and fy < 3.0 and abs(wx) < 0.5:
                    # Haustuer + Vordach
                    pb.box((0.0, 1.25, -4.20), (1.35, 2.30, 0.14), wood, bevel=0.015)
                    pb.box((0.0, 2.65, -4.75), (2.10, 0.12, 1.20), frame, bevel=0.012)
                    continue
                pb.box((wx, fy, side * 4.18), (1.55, 1.35, 0.14), frame, bevel=0.012)
                pb.box((wx, fy, side * 4.16), (1.36, 1.16, 0.08), glass, bevel=0.005)
                pb.box((wx, fy, side * 4.22), (0.05, 1.18, 0.05), frame, bevel=0.004)
    # Anbau-Garage seitlich (+X)
    pb.box((7.55, 1.55, 0.5), (3.8, 3.10, 6.0), plaster, bevel=0.02)
    pb.box((7.55, 3.16, 0.5), (4.05, 0.18, 6.25), frame, bevel=0.015)
    pb.box((7.55, 1.25, -2.52), (2.85, 2.25, 0.10), frame, bevel=0.012)

    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_house_suburban.glb"))


# ---------------------------------------------------------------------------
# 6. Geometrie-Helfer: gebogene Rohre (Laternenmast) und Laub-Cluster (Hecke)
# ---------------------------------------------------------------------------

def _add_branch_tube(pb: PartBuilder, pts_g: list, r_start: float, r_end: float, mat, seg: int = 8):
    mid = pb._mid(mat)
    rings = []
    n_pts = len(pts_g)
    for idx, p in enumerate(pts_g):
        t = idx / max(n_pts - 1, 1)
        r = r_start * (1.0 - t) + r_end * t
        if idx < n_pts - 1:
            tang = (pts_g[idx + 1] - p).normalized()
        else:
            tang = (p - pts_g[idx - 1]).normalized()
        ref = Vector((1, 0, 0)) if abs(tang.x) < 0.85 else Vector((0, 0, 1))
        u = tang.cross(ref).normalized()
        v = tang.cross(u).normalized()
        ring = []
        for s in range(seg):
            ang = (s / seg) * math.tau
            pos = p + (u * math.cos(ang) + v * math.sin(ang)) * r
            ring.append(pb.bm.verts.new(pb._local_b(pos)))
        rings.append(ring)
    faces = []
    for k in range(len(rings) - 1):
        r0, r1 = rings[k], rings[k + 1]
        for s in range(seg):
            sn = (s + 1) % seg
            try:
                f = pb.bm.faces.new((r0[s], r0[sn], r1[sn], r1[s]))
                f.material_index = mid
                f.smooth = True
                faces.append(f)
            except ValueError:
                pass
    try:
        f_top = pb.bm.faces.new(rings[-1])
        f_top.material_index = mid
        faces.append(f_top)
    except ValueError:
        pass
    bmesh.ops.recalc_face_normals(pb.bm, faces=faces)
    pb.bm.normal_update()
    pb._uv_box(faces, 0.8)


def _add_foliage_cluster(pb: PartBuilder, center_g: Vector, scale_g: Vector, mat, rng: random.Random, subdiv: int = 2):
    """Fein verbeulter, weich schattierter Laub-Cluster fuer realistische, dichte Baumkronen (kein Low-Poly-Look!)."""
    mid = pb._mid(mat)
    ret = bmesh.ops.create_icosphere(pb.bm, subdivisions=subdiv, radius=1.0)
    verts = ret["verts"]
    rot_m = Euler((rng.uniform(0, 6.28), rng.uniform(0, 6.28), rng.uniform(0, 6.28)), "XYZ").to_matrix().to_4x4()
    cb = pb._local_b(center_g)
    ph1 = rng.uniform(0.0, 6.28)
    ph2 = rng.uniform(0.0, 6.28)
    for v in verts:
        p = v.co.copy()
        bump = (
            1.0
            + 0.17 * math.sin(p.x * 5.2 + ph1) * math.cos(p.y * 4.8 + ph2)
            + 0.13 * math.sin(p.z * 6.4 + p.x * 3.5)
            + rng.uniform(-0.07, 0.08)
        )
        p.x *= scale_g.x * bump
        p.y *= scale_g.z * bump
        p.z *= scale_g.y * bump
        if p.z < 0.0:
            p.z *= 0.78
        v.co = (rot_m @ p) + cb
    faces = list({f for v in verts for f in v.link_faces})
    for f in faces:
        f.material_index = mid
        f.smooth = True
    pb.bm.normal_update()
    pb._uv_box(faces, 1.0)


# ---------------------------------------------------------------------------
# 7. Organisches Hecken-Segment (2.4 m) & Grasbueschel (fuer Wind-Shader!)
# ---------------------------------------------------------------------------

def build_hedge_and_grass():
    # A. Hecke
    _reset_scene()
    root = bpy.data.objects.new("HedgeRoot", None)
    bpy.context.scene.collection.objects.link(root)
    rng = random.Random(4041)
    leaf_d = make_solid_mat("Hedge_Dark", (0.14, 0.28, 0.12), rough=0.82, metal=0.0)
    leaf_m = make_solid_mat("Hedge_Mid", (0.19, 0.37, 0.15), rough=0.78, metal=0.0)
    leaf_l = make_solid_mat("Hedge_Light", (0.26, 0.44, 0.18), rough=0.75, metal=0.0)
    pb = PartBuilder("Canopy", origin_g=Vector((0, 0, 0)))
    # 28 feinere, weich schattierte Laub-Bueschel ueber 2.4 m Breite (dicht & natuerlich!)
    for i in range(28):
        x = -1.12 + (i / 27.0) * 2.24 + rng.uniform(-0.06, 0.06)
        y = rng.uniform(0.24, 0.66)
        z = rng.uniform(-0.22, 0.22)
        sc = Vector((rng.uniform(0.22, 0.34), rng.uniform(0.24, 0.38), rng.uniform(0.22, 0.34)))
        _add_foliage_cluster(pb, Vector((x, y, z)), sc, [leaf_d, leaf_m, leaf_l][i % 3], rng, subdiv=2)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_hedge_bush.glb"))

    # B. Gras-/Unkrautbueschel fuer Bordstein & Zaunrand
    _reset_scene()
    root = bpy.data.objects.new("GrassTuftRoot", None)
    bpy.context.scene.collection.objects.link(root)
    rng = random.Random(4042)
    g1 = make_solid_mat("Grass_Blade1", (0.20, 0.36, 0.14), rough=0.80, metal=0.0)
    g2 = make_solid_mat("Grass_Blade2", (0.30, 0.44, 0.18), rough=0.78, metal=0.0)
    pb = PartBuilder("Canopy", origin_g=Vector((0, 0, 0)))
    for bi in range(12):
        ang = (bi / 12.0) * math.tau + rng.uniform(-0.2, 0.2)
        tilt = rng.uniform(14.0, 34.0)
        h = rng.uniform(0.18, 0.36)
        r = rng.uniform(0.02, 0.14)
        bx, bz = math.cos(ang) * r, math.sin(ang) * r
        pb.box((bx, h * 0.45, bz), (0.045, h, 0.012), g1 if bi % 2 == 0 else g2,
               rot_g_deg=(tilt * math.sin(ang), math.degrees(ang), tilt * math.cos(ang)), bevel=0.0)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_grass_tuft.glb"))


# ---------------------------------------------------------------------------
# 8. Deutsche Peitschen-Strassenlaterne + Doppelstabmattenzaun + Strassen-Props
# ---------------------------------------------------------------------------

def build_street_lamp():
    _reset_scene()
    root = bpy.data.objects.new("StreetLampRoot", None)
    bpy.context.scene.collection.objects.link(root)

    galv = make_solid_mat("Lamp_PoleMat", (0.38, 0.41, 0.45), rough=0.40, metal=0.78)
    head_dark = make_solid_mat("Lamp_HeadMat", (0.16, 0.18, 0.21), rough=0.42, metal=0.65)
    glass = make_solid_mat("Lamp_GlassMat", (1.0, 0.94, 0.80), rough=0.14, metal=0.05,
                           emission=(1.0, 0.90, 0.66), em_strength=0.25)

    pb = PartBuilder("StreetLamp", origin_g=Vector((0, 0, 0)))
    # Mast-Sockel + Revisionsklappe + verjuengter Stahlmast (5.4 m hoch)
    pb.cyl((0.0, 0.42, 0.0), 0.095, 0.115, 0.84, galv, axis_g="y", seg=10)
    pb.box((0.0, 0.68, 0.095), (0.09, 0.32, 0.03), head_dark, bevel=0.005)
    pb.cyl((0.0, 2.85, 0.0), 0.062, 0.092, 4.10, galv, axis_g="y", seg=10)
    # Geschwungener Peitschen-Ausleger Richtung +Z (zur Fahrbahn!)
    arm_pts = [
        Vector((0.0, 4.82, 0.0)),
        Vector((0.0, 5.18, 0.16)),
        Vector((0.0, 5.42, 0.56)),
        Vector((0.0, 5.52, 1.18)),
    ]
    _add_branch_tube(pb, arm_pts, 0.058, 0.036, galv, seg=8)
    # Moderner flacher LED-Leuchtenkopf + Lichtglas
    pb.box((0.0, 5.52, 1.38), (0.28, 0.085, 0.58), head_dark, rot_g_deg=(-6.0, 0.0, 0.0), bevel=0.018)
    pb.box((0.0, 5.47, 1.40), (0.21, 0.03, 0.44), glass, rot_g_deg=(-6.0, 0.0, 0.0), bevel=0.006)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_street_lamp.glb"))


def build_fence_panel(tex: dict):
    _reset_scene()
    root = bpy.data.objects.new("FencePanelRoot", None)
    bpy.context.scene.collection.objects.link(root)

    anthr = make_solid_mat("Fence_SteelMat", (0.14, 0.16, 0.19), rough=0.45, metal=0.68)
    concrete = make_pbr_tex_mat("Fence_ConcreteMat", *tex["concrete"], rough=0.88, metal=0.0, normal_strength=0.7)

    pb = PartBuilder("FencePanel", origin_g=Vector((0, 0, 0)))
    # 2.50 m breites Doppelstabmatten-Segment (X = -1.25 .. +1.25), 1.85 m hoch
    pb.box((0.0, 0.10, 0.0), (2.50, 0.20, 0.14), concrete, bevel=0.015) # Beton-Bordsockel
    # Zwei Vierkant-Pfosten mit Regen-Kappen
    for px in (-1.25, 1.25):
        pb.box((px, 0.96, 0.0), (0.065, 1.92, 0.065), anthr, bevel=0.006)
        pb.box((px, 1.93, 0.0), (0.08, 0.025, 0.08), anthr, bevel=0.005)
    # Horizontale Doppelstaebe (8 Reihen) + vertikale Staebe (alle 16 cm)
    for hy in np.linspace(0.32, 1.80, 8):
        pb.box((0.0, float(hy), -0.012), (2.46, 0.016, 0.010), anthr, bevel=0.0)
        pb.box((0.0, float(hy),  0.012), (2.46, 0.016, 0.010), anthr, bevel=0.0)
    for vx in np.linspace(-1.12, 1.12, 15):
        pb.box((float(vx), 1.06, 0.0), (0.012, 1.56, 0.012), anthr, bevel=0.0)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_fence_panel.glb"))


def build_street_props(tex: dict):
    # 1. Deutscher Ueberflurhydrant
    _reset_scene()
    root = bpy.data.objects.new("HydrantRoot", None)
    bpy.context.scene.collection.objects.link(root)
    red = make_solid_mat("Hyd_Red", (0.76, 0.11, 0.10), rough=0.38, metal=0.25)
    iron = make_solid_mat("Hyd_Iron", (0.22, 0.24, 0.26), rough=0.52, metal=0.72)
    pb = PartBuilder("Hydrant", origin_g=Vector((0, 0, 0)))
    pb.cyl((0.0, 0.06, 0.0), 0.15, 0.16, 0.12, iron, axis_g="y", seg=14)
    pb.cyl((0.0, 0.44, 0.0), 0.095, 0.115, 0.68, red, axis_g="y", seg=16)
    pb.cyl((0.0, 0.80, 0.0), 0.125, 0.10, 0.10, red, axis_g="y", seg=16)
    pb.cyl((0.0, 0.88, 0.0), 0.06, 0.09, 0.08, iron, axis_g="y", seg=8)
    for sx in (-0.12, 0.12):
        pb.cyl((sx, 0.60, 0.0), 0.048, 0.048, 0.09, iron, axis_g="x", seg=12)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_hydrant.glb"))

    # 2. Gusseiserner Gullydeckel / Kanaldeckel
    _reset_scene()
    root = bpy.data.objects.new("ManholeRoot", None)
    bpy.context.scene.collection.objects.link(root)
    iron = make_solid_mat("Manhole_Iron", (0.19, 0.20, 0.21), rough=0.68, metal=0.75)
    dark = make_solid_mat("Manhole_Dark", (0.06, 0.06, 0.07), rough=0.90, metal=0.20)
    pb = PartBuilder("Manhole", origin_g=Vector((0, 0, 0)))
    pb.cyl((0.0, 0.008, 0.0), 0.36, 0.36, 0.016, iron, axis_g="y", seg=20)
    pb.cyl((0.0, 0.012, 0.0), 0.30, 0.30, 0.012, dark, axis_g="y", seg=20)
    for ri in range(6):
        ang = (ri / 6.0) * math.tau
        pb.box((math.cos(ang) * 0.14, 0.016, math.sin(ang) * 0.14), (0.22, 0.008, 0.03), iron,
               rot_g_deg=(0.0, math.degrees(ang), 0.0), bevel=0.002)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_manhole.glb"))

    # 3. Deutsche 240L-Muelltonne + grosser 1100L-Industriecontainer
    _reset_scene()
    root = bpy.data.objects.new("TrashBinRoot", None)
    bpy.context.scene.collection.objects.link(root)
    anthr = make_solid_mat("Bin_Anthr", (0.16, 0.18, 0.20), rough=0.58, metal=0.05)
    blue = make_solid_mat("Bin_Blue", (0.12, 0.32, 0.62), rough=0.52, metal=0.05)
    wheel = make_solid_mat("Bin_Wheel", (0.06, 0.06, 0.07), rough=0.85, metal=0.0)
    pb = PartBuilder("TrashBin", origin_g=Vector((0, 0, 0)))
    # 240L Tonne mit Deckel, Griff & 2 Raedern
    pb.box((0.0, 0.49, 0.0), (0.56, 0.88, 0.58), anthr, bevel=0.025)
    pb.box((0.0, 0.96, 0.0), (0.60, 0.09, 0.62), blue, bevel=0.02)
    pb.cyl((0.0, 0.94, 0.34), 0.022, 0.022, 0.52, anthr, axis_g="x", seg=10)
    for wx in (-0.28, 0.28):
        pb.cyl((wx, 0.11, 0.22), 0.11, 0.11, 0.05, wheel, axis_g="x", seg=14)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_trash_bin.glb"))

    # 4. Gestapelte Europaletten (3 Stueck)
    _reset_scene()
    root = bpy.data.objects.new("PalletStackRoot", None)
    bpy.context.scene.collection.objects.link(root)
    wood = make_solid_mat("Pallet_Wood", (0.64, 0.48, 0.30), rough=0.84, metal=0.0)
    wood_d = make_solid_mat("Pallet_WoodDark", (0.52, 0.38, 0.23), rough=0.86, metal=0.0)
    pb = PartBuilder("PalletStack", origin_g=Vector((0, 0, 0)))
    for layer in range(3):
        yb = layer * 0.155
        yaw = (layer - 1) * 3.5
        # 9 Holz-Kloetze + 5 obere Bretter + 3 Kufen
        for kx in (-0.52, 0.0, 0.52):
            for kz in (-0.32, 0.0, 0.32):
                pb.box((kx, yb + 0.06, kz), (0.14, 0.09, 0.10), wood_d, rot_g_deg=(0, yaw, 0), bevel=0.004)
        for bz in (-0.32, -0.16, 0.0, 0.16, 0.32):
            pb.box((0.0, yb + 0.125, bz), (1.20, 0.024, 0.11), wood, rot_g_deg=(0, yaw, 0), bevel=0.003)
        for kz in (-0.32, 0.0, 0.32):
            pb.box((0.0, yb + 0.012, kz), (1.20, 0.022, 0.10), wood_d, rot_g_deg=(0, yaw, 0), bevel=0.003)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_pallet_stack.glb"))

    # 5. Deutscher Kabelverzweiger / Stromverteilerkasten am Gehweg
    _reset_scene()
    root = bpy.data.objects.new("UtilityBoxRoot", None)
    bpy.context.scene.collection.objects.link(root)
    box_grey = make_solid_mat("UBox_Grey", (0.68, 0.70, 0.69), rough=0.66, metal=0.10)
    plinth = make_solid_mat("UBox_Plinth", (0.28, 0.30, 0.31), rough=0.84, metal=0.05)
    lock_m = make_solid_mat("UBox_Lock", (0.18, 0.20, 0.22), rough=0.45, metal=0.70)
    pb = PartBuilder("UtilityBox", origin_g=Vector((0, 0, 0)))
    pb.box((0.0, 0.14, 0.0), (1.06, 0.28, 0.42), plinth, bevel=0.012)
    pb.box((0.0, 0.76, 0.0), (1.10, 0.98, 0.44), box_grey, bevel=0.02)
    pb.box((0.0, 1.28, 0.0), (1.14, 0.08, 0.48), box_grey, rot_g_deg=(5.0, 0.0, 0.0), bevel=0.015)
    pb.box((0.0, 0.74, -0.225), (0.02, 0.86, 0.02), lock_m, bevel=0.002)
    pb.box((0.09, 0.72, -0.23), (0.05, 0.12, 0.03), lock_m, bevel=0.004)
    pb.build(root)
    _export_glb(os.path.join(OUT_MODELS_DIR, "ext_utility_box.glb"))


def main():
    tex = ensure_exterior_textures()
    build_logistics_hall(tex)
    build_office_tech(tex)
    build_substation_20kv(tex)
    build_shipping_container(tex)
    build_suburban_house(tex)
    build_hedge_and_grass()
    build_street_lamp()
    build_fence_panel(tex)
    build_street_props(tex)
    print("[EXT_WORLD] Alle 14 deutschen Aussenwelt-Blender-Modelle erfolgreich gebaut!")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
