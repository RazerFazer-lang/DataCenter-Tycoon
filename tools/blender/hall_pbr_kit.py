"""Gemeinsames Blender-5.2 AAA-Architektur-, Stahlbau- & High-Poly-Prop-Kit (v2.3.0 Overhaul).

Liefert fuer Halle Nord, Start-Garage (inkl. Halle B/C) und alle 6 kaufbaren Shop-Dekos:
  1. Echte 2K/1K glTF-ORM-PBR-Texturen (Albedo + Occlusion/Roughness/Metallic + OpenGL-Normalmap):
     - 2K Quarz-Epoxidharz-Industrieboden mit geschnittenen Fugen, Reifenspuren & Roughness-Glanzmap
     - 2K Akustik-/Sandwichpaneel-Hallenwand mit feiner Linierung, Stossfugen & Verschraubung
     - 2K Gefaster Sichtbeton (Schalungsanker, Poren, Kanten-AO) fuer Sockel & Fundamente
     - 1K Feuerverzinkter Stahl (Zinkblume), Pulverbeschichtungs-Lacke (RAL-Farben mit Microbump),
       Eichen-Stabverleimung, Palettenholz mit Maserung, 5-Rippen-Traenenblech & 2K-NOC/UI-Atlas
  2. Echte Blender-5.2 Glas-Transparenz (surface_render_method = 'BLENDED' + eigene *_Glass Meshes)
  3. Echte High-Poly-Bauteile (0 % Klotz-Optik!):
     - HEB/IPE-Doppel-T-Stahltraeger mit Flanschen, Steg, Kopfplatten, Knotenblechen & 6-Kant-Bolzen
     - Echtes 3D-profiliertes Trapezblechdach (extrudierte Trapez-Sicken)
     - Geschwungene 3D-Rohrleitungen & Schlaeuche mit Torus-Rohrboegen, Flanschen & Handrad-Ventilen
     - Echte gewickelte 3D-Torsionsfedern fuer Sektionaltore
     - High-Poly Industrie-Props: Hubwagen (Ameise), DIN-15155 Draht-Gitterbox, Werkstattwagen,
       Industriesauger mit Spiralschlauch, Alu-Stehleiter, Spinde, Wandhydrant, 6kg-Feuerloescher u.v.m.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Euler, Matrix, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import dct_paths
import pbr_textures
from build_delivery_van import PartBuilder, _ensure_gltf_ao_group, _load_img, _new_mat, _save_rgb, g

CACHE_DIR = dct_paths.PBR_CACHE
OUT_MODELS_DIR = dct_paths.MODELS_DIR


# ===========================================================================
# 1. Szene, Export & glTF-2.0 ORM/Glas-Materialien (Blender 5.2)
# ===========================================================================

def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    for img in list(bpy.data.images):
        bpy.data.images.remove(img)


def export_glb(out_path: str):
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
    kb = os.path.getsize(out_path) / 1024.0
    print(f"[HALL_KIT] Exported {os.path.basename(out_path)} ({kb:.1f} KB)")


def make_orm_mat(name: str, maps: dict, normal_strength: float = 1.0, coat: float = 0.0, coat_rough: float = 0.12):
    mat, nt, bsdf = _new_mat(name)
    t_alb = nt.nodes.new("ShaderNodeTexImage")
    t_alb.image = _load_img(maps["albedo"], "sRGB")
    nt.links.new(t_alb.outputs["Color"], bsdf.inputs["Base Color"])

    if "orm" in maps:
        t_orm = nt.nodes.new("ShaderNodeTexImage")
        t_orm.image = _load_img(maps["orm"], "Non-Color")
        sep = nt.nodes.new("ShaderNodeSeparateColor")
        nt.links.new(t_orm.outputs["Color"], sep.inputs["Color"])
        nt.links.new(sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(sep.outputs["Blue"], bsdf.inputs["Metallic"])
        ao_node = nt.nodes.new("ShaderNodeGroup")
        ao_node.node_tree = _ensure_gltf_ao_group()
        nt.links.new(sep.outputs["Red"], ao_node.inputs["Occlusion"])

    if "normal" in maps:
        t_nrm = nt.nodes.new("ShaderNodeTexImage")
        t_nrm.image = _load_img(maps["normal"], "Non-Color")
        nmap = nt.nodes.new("ShaderNodeNormalMap")
        nmap.inputs["Strength"].default_value = normal_strength
        nt.links.new(t_nrm.outputs["Color"], nmap.inputs["Color"])
        nt.links.new(nmap.outputs["Normal"], bsdf.inputs["Normal"])

    if coat > 0.0 and "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = coat_rough
    return mat


def make_real_glass_mat(name: str, rgb=(0.62, 0.76, 0.86), alpha: float = 0.20,
                        rough: float = 0.04, metal: float = 0.08, coat: float = 0.95):
    """Echtes transparentes Isolier-/Sicherheitsglas fuer Blender 5.2 -> glTF alphaMode: BLEND."""
    mat, _nt, bsdf = _new_mat(name)
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Alpha"].default_value = alpha
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.03
    if hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "BLENDED"
    if hasattr(mat, "blend_method"):
        mat.blend_method = "BLEND"
    mat.use_backface_culling = False
    return mat


def make_emissive_mat(name: str, rgb, strength: float = 1.6, rough: float = 0.18):
    mat, _nt, bsdf = _new_mat(name)
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Emission Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def make_screen_tex_mat(name: str, img_path: str, em_strength: float = 1.35, rough: float = 0.12):
    mat, nt, bsdf = _new_mat(name)
    t_img = nt.nodes.new("ShaderNodeTexImage")
    t_img.image = _load_img(img_path, "sRGB")
    nt.links.new(t_img.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(t_img.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = em_strength
    bsdf.inputs["Roughness"].default_value = rough
    if "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = 0.65
        bsdf.inputs["Coat Roughness"].default_value = 0.06
    return mat


# ===========================================================================
# 2. Volle 2K / 1K PBR-Textur-Pipeline (Albedo + ORM + Normal)
# ===========================================================================

def _cached(prefix: str) -> dict | None:
    a = os.path.join(CACHE_DIR, f"{prefix}_alb.png")
    o = os.path.join(CACHE_DIR, f"{prefix}_orm.png")
    n = os.path.join(CACHE_DIR, f"{prefix}_nrm.png")
    if os.path.exists(a) and os.path.exists(o) and os.path.exists(n):
        return {"albedo": a, "orm": o, "normal": n}
    return None


def _write_pbr(prefix: str, alb: np.ndarray, ao: np.ndarray, rough: np.ndarray,
               metal: np.ndarray, height: np.ndarray, nrm_strength: float) -> dict:
    a = os.path.join(CACHE_DIR, f"{prefix}_alb.png")
    o = os.path.join(CACHE_DIR, f"{prefix}_orm.png")
    n = os.path.join(CACHE_DIR, f"{prefix}_nrm.png")
    _save_rgb(a, np.clip(alb, 0.0, 1.0))
    pbr_textures.save_png(o, pbr_textures.pack_orm(np.clip(ao, 0.0, 1.0), np.clip(rough, 0.04, 0.99), np.clip(metal, 0.0, 1.0)))
    pbr_textures.save_png(n, pbr_textures.height_to_normal(height.astype(np.float32), strength=nrm_strength))
    return {"albedo": a, "orm": o, "normal": n}


def ensure_hall_pbr_library() -> dict:
    os.makedirs(CACHE_DIR, exist_ok=True)
    lib = {}

    # 1. 2K Quarz-Epoxidharz-Industrieboden (2048x2048: Fugen, Quarzsprenkel, Laufspuren-Roughness!)
    c = _cached("v230_epoxy_floor_2k")
    if c is None:
        s = 2048
        rng = np.random.default_rng(2301)
        macro = pbr_textures.fbm_tile(s, s, 6, 6, octaves=4, seed=11)
        scuff = pbr_textures.fbm_tile(s, s, 14, 14, octaves=4, seed=29)
        micro = rng.normal(0.0, 0.013, (s, s)).astype(np.float32)
        quartz_hi = (rng.random((s, s)) > 0.985).astype(np.float32) * 0.055
        quartz_lo = (rng.random((s, s)) < 0.015).astype(np.float32) * 0.045

        val = np.clip(0.425 + (macro - 0.5) * 0.055 + micro + quartz_hi - quartz_lo, 0.28, 0.56)
        # Dezente abgedunkelte Lauf-/Rollen-Spuren
        track_mask = np.clip((scuff - 0.56) * 2.2, 0.0, 1.0)
        val *= (1.0 - track_mask * 0.065)

        hgt = np.clip(0.72 + micro * 2.2 + (macro - 0.5) * 0.08, 0.0, 1.0)
        ao = np.clip(0.96 - track_mask * 0.06, 0.70, 1.0)
        # Seidenglanz-Epoxid (0.25) mit matteren Laufspuren (0.48)!
        rough = np.clip(0.26 + (macro - 0.5) * 0.08 + track_mask * 0.21 + np.abs(micro) * 1.4, 0.18, 0.62)
        metal = np.full((s, s), 0.03, dtype=np.float32)

        # Geschnittene Dehnungsfugen (2x2 Platten pro 3.2m Kachel -> 1.6m Beton/Epoxid-Plattenraster!)
        for jp in (0, s // 2):
            for d in range(-5, 6):
                idx = (jp + d) % s
                w = 1.0 - abs(d) / 6.0
                if abs(d) <= 2:
                    # Dunkle elastische PU-Fugenmasse in der Schnittrille
                    val[idx, :] = 0.16
                    val[:, idx] = 0.16
                    hgt[idx, :] = 0.10
                    hgt[:, idx] = 0.10
                    ao[idx, :] = 0.42
                    ao[:, idx] = 0.42
                    rough[idx, :] = 0.78
                    rough[:, idx] = 0.78
                else:
                    # Leichte Fasen-Abnutzung & Staub direkt neben der Fuge
                    val[idx, :] *= (1.0 - 0.08 * w)
                    val[:, idx] *= (1.0 - 0.08 * w)
                    hgt[idx, :] -= 0.12 * w
                    hgt[:, idx] -= 0.12 * w
                    ao[idx, :] = np.minimum(ao[idx, :], 0.84)
                    ao[:, idx] = np.minimum(ao[:, idx], 0.84)

        alb = np.stack([val * 0.98, val * 1.00, val * 1.02], axis=-1)
        c = _write_pbr("v230_epoxy_floor_2k", alb, ao, rough, metal, hgt, nrm_strength=2.6)
    lib["epoxy_floor"] = c

    # 2. 2K Akustik-Sandwichpaneel-Innenwand (2048x2048: helle Mikro-Linierung + Stossfugen + Nieten!)
    c = _cached("v230_sandwich_wall_2k")
    if c is None:
        s = 2048
        rng = np.random.default_rng(2302)
        subtle = pbr_textures.fbm_tile(s, s, 8, 8, octaves=3, seed=44)
        peel = rng.normal(0.0, 0.007, (s, s)).astype(np.float32)
        yy = np.linspace(0.0, 1.0, s, endpoint=False, dtype=np.float32)[:, None]
        # 4 horizontale Sandwich-Elemente pro Kachel + feine 16er Mikro-Sicken je Paneel
        micro_rib = 0.5 + 0.5 * np.sin(yy * math.pi * 2.0 * 64.0)
        val = np.broadcast_to(0.80 + (micro_rib - 0.5) * 0.018, (s, s)).copy()
        val += (subtle - 0.5) * 0.032 + peel
        hgt = np.broadcast_to(0.74 + (micro_rib - 0.5) * 0.08, (s, s)).copy() + peel * 1.5
        ao = np.full((s, s), 0.97, dtype=np.float32)
        rough = np.clip(0.46 + (subtle - 0.5) * 0.09, 0.34, 0.62)
        metal = np.full((s, s), 0.18, dtype=np.float32)

        # 4 tiefe horizontale Paneel-Stossfugen mit Schattenkante
        for r in range(4):
            y0 = r * (s // 4)
            for dy in range(-4, 5):
                yi = (y0 + dy) % s
                if abs(dy) <= 1:
                    val[yi, :] = 0.34
                    hgt[yi, :] = 0.08
                    ao[yi, :] = 0.38
                    rough[yi, :] = 0.72
                else:
                    val[yi, :] *= 0.92
                    hgt[yi, :] = 0.48
                    ao[yi, :] = 0.80

        # Dezente vertikale Elementfuge bei x=0 & x=s//2
        for x0 in (0, s // 2):
            for dx in range(-2, 3):
                xi = (x0 + dx) % s
                val[:, xi] *= 0.78 if abs(dx) <= 1 else 0.94
                hgt[:, xi] = 0.25 if abs(dx) <= 1 else 0.58
                ao[:, xi] = np.minimum(ao[:, xi], 0.62 if abs(dx) <= 1 else 0.88)

        alb = np.stack([val * 0.99, val * 1.00, val * 1.015], axis=-1)
        c = _write_pbr("v230_sandwich_wall_2k", alb, ao, rough, metal, hgt, nrm_strength=2.8)
    lib["sandwich_wall"] = c

    # 3. 2K Sichtbeton fuer Sockel, Stuetzenfuesse & Fundamente (Schalungsfugen, Spannloecher, Poren)
    c = _cached("v230_concrete_2k")
    if c is None:
        s = 2048
        rng = np.random.default_rng(2303)
        mottle = pbr_textures.fbm_tile(s, s, 8, 8, octaves=5, seed=63)
        fine = pbr_textures.fbm_tile(s, s, 32, 32, octaves=3, seed=71)
        pores = (rng.random((s, s)) < 0.012).astype(np.float32)
        val = np.clip(0.46 + (mottle - 0.5) * 0.11 + (fine - 0.5) * 0.05 - pores * 0.16, 0.24, 0.64)
        hgt = np.clip(0.72 + (fine - 0.5) * 0.16 - pores * 0.45, 0.05, 1.0)
        ao = np.clip(0.95 - pores * 0.35 - (0.5 - mottle) * 0.08, 0.50, 1.0)
        rough = np.clip(0.82 + (mottle - 0.5) * 0.12, 0.68, 0.95)
        metal = np.zeros((s, s), dtype=np.float32)

        # Schalungstafel-Stossfugen + konische Schalungsanker-Loecher!
        for jx in (0, s // 2):
            val[:, jx:jx + 4] *= 0.72
            hgt[:, jx:jx + 4] = 0.28
            ao[:, jx:jx + 4] = 0.55
        yy, xx = np.mgrid[0:s, 0:s]
        for tx in (256, 768, 1280, 1792):
            for ty in (380, 1660):
                dist = np.sqrt((xx - tx) ** 2 + (yy - ty) ** 2)
                cone = dist < 18.0
                rim = (dist >= 18.0) & (dist < 25.0)
                val[cone] = 0.24
                hgt[cone] = 0.12
                ao[cone] = 0.30
                val[rim] *= 0.88
                hgt[rim] = 0.52
        alb = np.stack([val * 1.00, val * 0.99, val * 0.96], axis=-1)
        c = _write_pbr("v230_concrete_2k", alb, ao, rough, metal, hgt, nrm_strength=3.1)
    lib["concrete"] = c

    # 4. 1K Feuerverzinkter Stahl (feine Zinkblumen-Kristallstruktur fuer Kabelpritschen, Lueftungsrohre & Schienen!)
    c = _cached("v230b_galv_1k")
    if c is None:
        s = 1024
        n1 = pbr_textures.fbm_tile(s, s, 48, 48, octaves=3, seed=88)
        n2 = pbr_textures.fbm_tile(s, s, 128, 128, octaves=2, seed=92)
        spangle = np.floor(n1 * 9.0) / 9.0 * 0.60 + n2 * 0.40
        val = np.clip(0.64 + (spangle - 0.5) * 0.11, 0.50, 0.78)
        rough = np.clip(0.30 + (0.5 - spangle) * 0.15, 0.20, 0.48)
        ao = np.full((s, s), 0.97, dtype=np.float32)
        metal = np.full((s, s), 0.86, dtype=np.float32)
        alb = np.stack([val * 0.97, val * 0.99, val * 1.02], axis=-1)
        c = _write_pbr("v230b_galv_1k", alb, ao, rough, metal, spangle, nrm_strength=0.65)
    lib["galv"] = c

    # 5. 1K 5-Rippen-Riffelblech / Traenenblech
    c = _cached("v230_treadplate_1k")
    if c is None:
        s = 1024
        yy, xx = np.mgrid[0:s, 0:s].astype(np.float32)
        u = (xx % 64.0) / 64.0
        v = (yy % 64.0) / 64.0
        cell = (((xx // 64).astype(np.int32) + (yy // 64).astype(np.int32)) % 2 == 0)
        d_a = np.maximum(np.abs(u - 0.5) * 2.2, np.abs(v - 0.5) * 0.9)
        d_b = np.maximum(np.abs(v - 0.5) * 2.2, np.abs(u - 0.5) * 0.9)
        lug = np.where(cell, d_a < 0.34, d_b < 0.34).astype(np.float32)
        lug = pbr_textures.blur_separable(lug, 2, wrap=True)
        grain = pbr_textures.fbm_tile(s, s, 16, 16, octaves=3, seed=105)
        val = np.clip(0.46 + lug * 0.22 + (grain - 0.5) * 0.06, 0.32, 0.76)
        hgt = np.clip(0.35 + lug * 0.58 + (grain - 0.5) * 0.05, 0.0, 1.0)
        ao = np.clip(0.84 + lug * 0.16, 0.72, 1.0)
        rough = np.clip(0.44 - lug * 0.18 + (grain - 0.5) * 0.08, 0.20, 0.58)
        metal = np.full((s, s), 0.84, dtype=np.float32)
        alb = np.stack([val * 0.97, val * 0.99, val * 1.02], axis=-1)
        c = _write_pbr("v230_treadplate_1k", alb, ao, rough, metal, hgt, nrm_strength=4.0)
    lib["treadplate"] = c

    # 6. Pulverbeschichtete Industrie-Lacke (1K Micro-Bump + Roughness-Variation!)
    coat_specs = {
        "steel_anthracite": ((0.14, 0.16, 0.19), 0.38, 0.74, 201),
        "steel_grey":       ((0.29, 0.32, 0.35), 0.42, 0.68, 202),
        "ral_light_grey":   ((0.62, 0.65, 0.68), 0.38, 0.42, 203),
        "alu_anodized":     ((0.72, 0.75, 0.79), 0.26, 0.88, 204),
        "safety_yellow":    ((0.91, 0.67, 0.08), 0.34, 0.14, 205),
        "flame_red":        ((0.76, 0.12, 0.10), 0.30, 0.22, 206),
        "euro_blue":        ((0.13, 0.37, 0.66), 0.42, 0.08, 207),
        "safety_green":     ((0.12, 0.50, 0.24), 0.38, 0.10, 208),
        "rubber_black":     ((0.075, 0.08, 0.085), 0.84, 0.02, 209),
    }
    for key, (rgb, r_val, m_val, sd) in coat_specs.items():
        pref = f"v230b_{key}"
        c = _cached(pref)
        if c is None:
            s = 512
            n1 = pbr_textures.fbm_tile(s, s, 64, 64, octaves=3, seed=sd)
            n2 = pbr_textures.fbm_tile(s, s, 128, 128, octaves=2, seed=sd + 31)
            g_tex = n1 * 0.50 + n2 * 0.50
            alb = np.stack([
                np.clip(rgb[0] + (g_tex - 0.5) * 0.028, 0.0, 1.0),
                np.clip(rgb[1] + (g_tex - 0.5) * 0.028, 0.0, 1.0),
                np.clip(rgb[2] + (g_tex - 0.5) * 0.028, 0.0, 1.0),
            ], axis=-1)
            ao = np.clip(0.97 + (g_tex - 0.5) * 0.05, 0.88, 1.0)
            rough = np.clip(r_val + (g_tex - 0.5) * 0.08, 0.14, 0.95)
            metal = np.full((s, s), m_val, dtype=np.float32)
            c = _write_pbr(pref, alb, ao, rough, metal, g_tex, nrm_strength=0.40)
        lib[key] = c

    # 7. 1K Echtes Holz (Palettenholz & geölte Buche/Eiche-Werkbankplatte mit Maserung!)
    for key, base_rgb, r_base, sd in (
        ("wood_pallet", (0.55, 0.42, 0.26), 0.82, 301),
        ("wood_oak",    (0.48, 0.34, 0.21), 0.44, 302),
    ):
        pref = f"v230_{key}"
        c = _cached(pref)
        if c is None:
            s = 1024
            fibers = pbr_textures.fbm_tile(s, s, 6, 48, octaves=4, seed=sd)
            rings = 0.5 + 0.5 * np.sin((fibers * 14.0 + np.linspace(0, 6, s)[:, None]) * math.pi)
            grain = fibers * 0.65 + rings * 0.35
            alb = np.stack([
                np.clip(base_rgb[0] * (0.82 + 0.34 * grain), 0.0, 1.0),
                np.clip(base_rgb[1] * (0.82 + 0.34 * grain), 0.0, 1.0),
                np.clip(base_rgb[2] * (0.82 + 0.34 * grain), 0.0, 1.0),
            ], axis=-1)
            ao = np.clip(0.90 + (grain - 0.5) * 0.14, 0.72, 1.0)
            rough = np.clip(r_base + (0.5 - grain) * 0.16, 0.26, 0.95)
            metal = np.zeros((s, s), dtype=np.float32)
            # Stabverleimungs-/Bretterfugen
            for py in range(0, s, s // 6):
                alb[py:py + 2, :] *= 0.68
                ao[py:py + 2, :] = 0.58
            c = _write_pbr(pref, alb, ao, rough, metal, grain, nrm_strength=2.2)
        lib[key] = c

    # 8. 1K Wellpappe (Versandkartons)
    c = _cached("v230_cardboard_1k")
    if c is None:
        s = 1024
        n1 = pbr_textures.fbm_tile(s, s, 14, 14, octaves=4, seed=331)
        yy = np.linspace(0.0, math.pi * 2.0 * 72.0, s, dtype=np.float32)[:, None]
        flute = np.broadcast_to(0.5 + 0.5 * np.sin(yy), (s, s))
        h = n1 * 0.72 + flute * 0.28
        alb = np.stack([
            np.clip(0.58 + (h - 0.5) * 0.13, 0.0, 1.0),
            np.clip(0.45 + (h - 0.5) * 0.11, 0.0, 1.0),
            np.clip(0.30 + (h - 0.5) * 0.09, 0.0, 1.0),
        ], axis=-1)
        ao = np.clip(0.90 + (flute - 0.5) * 0.10, 0.75, 1.0)
        rough = np.clip(0.84 + (n1 - 0.5) * 0.10, 0.68, 0.96)
        metal = np.zeros((s, s), dtype=np.float32)
        c = _write_pbr("v230_cardboard_1k", alb, ao, rough, metal, h, nrm_strength=2.4)
    lib["cardboard"] = c

    # 9. Hochaufloesende UI-/Display-Texturen fuer NOC-Videowall, Schaltanlage, Kiosk & CCTV!
    p_noc = os.path.join(CACHE_DIR, "v230_noc_screen.png")
    if not os.path.exists(p_noc):
        w, h = 1024, 512
        img = np.zeros((h, w, 3), dtype=np.float32)
        img[:, :] = np.array([0.035, 0.055, 0.085], dtype=np.float32)
        pbr_textures.fill_rect(img, 0, 0, w - 1, 48, (0.06, 0.13, 0.22))
        pbr_textures.draw_text(img, 24, 14, "VERION NOC TELEMETRY  //  CLUSTER HEALTH 99.98%", (0.36, 0.88, 1.0), scale=2)
        # 3 Dashboard-Karten mit Kurven & Balken
        for ci, x0 in enumerate((24, 356, 688)):
            pbr_textures.stroke_rect(img, x0, 68, x0 + 308, 484, (0.12, 0.32, 0.48), thickness=2)
            pbr_textures.fill_rect(img, x0 + 2, 70, x0 + 306, 104, (0.05, 0.10, 0.16))
            titles = ("CORE THROUGHPUT", "RACK THERMAL MAP", "400V UPS & GRID")
            pbr_textures.draw_text(img, x0 + 14, 80, titles[ci], (0.78, 0.92, 1.0), scale=2)
            if ci == 0:
                for x in range(x0 + 18, x0 + 290):
                    yv = int(260 + 55 * math.sin(x * 0.045) + 22 * math.cos(x * 0.13))
                    img[max(115, yv - 3):min(470, yv + 3), x] = (0.14, 0.90, 0.98)
                    img[yv:468, x] = img[yv:468, x] * 0.85 + np.array([0.02, 0.14, 0.18]) * 0.15
            elif ci == 1:
                for rr in range(5):
                    for rc in range(6):
                        bx = x0 + 20 + rc * 45
                        by = 128 + rr * 64
                        hot = (rr == 2 and rc == 3)
                        col = (0.96, 0.64, 0.14) if hot else (0.14, 0.78, 0.46)
                        pbr_textures.fill_rect(img, bx, by, bx + 36, by + 48, col)
            else:
                for bi, bh in enumerate((190, 245, 220, 275, 260, 210)):
                    bx = x0 + 24 + bi * 44
                    pbr_textures.fill_rect(img, bx, 464 - bh, bx + 30, 464, (0.18, 0.82, 0.56))
        _save_rgb(p_noc, img)
    lib["noc_screen_tex"] = p_noc

    p_meter = os.path.join(CACHE_DIR, "v230_multimeter_ui.png")
    if not os.path.exists(p_meter):
        w, h = 512, 256
        img = np.zeros((h, w, 3), dtype=np.float32)
        img[:, :] = np.array([0.03, 0.08, 0.12], dtype=np.float32)
        pbr_textures.stroke_rect(img, 6, 6, w - 7, h - 7, (0.14, 0.48, 0.68), thickness=3)
        pbr_textures.draw_text(img, 24, 24, "L1  400.2 V   50.00 HZ", (0.28, 0.94, 0.62), scale=3)
        pbr_textures.draw_text(img, 24, 84, "L2  399.8 V   PF 0.99", (0.28, 0.94, 0.62), scale=3)
        pbr_textures.draw_text(img, 24, 144, "L3  400.4 V   THD 1.2%", (0.28, 0.94, 0.62), scale=3)
        pbr_textures.fill_rect(img, 24, 202, 420, 228, (0.16, 0.84, 0.48))
        _save_rgb(p_meter, img)
    lib["meter_screen_tex"] = p_meter

    return lib


# ===========================================================================
# 3. High-Poly Geometrie-Builder: Stahltraeger, 3D-Trapezblech, Rohre & Federn
# ===========================================================================

def add_trapezoidal_deck(pb: PartBuilder, center_g, span_x: float, span_z: float, y_base: float,
                         rib_h: float, pitch_z: float, mat, uv_scale: float = 2.0):
    """Extrudiertes echtes 3D-Trapezblech-Dachprofil (Sicken & Stege statt flacher Box!)."""
    mid = pb._mid(mat)
    cx, cz = center_g[0], center_g[2]
    x0, x1 = cx - span_x * 0.5, cx + span_x * 0.5
    z_start = cz - span_z * 0.5
    n_waves = max(2, int(round(span_z / pitch_z)))
    step = span_z / float(n_waves)

    # Profilpunkte entlang Z (Untergurt -> Flanke hoch -> Obergurt -> Flanke runter)
    prof = []
    for i in range(n_waves):
        z0 = z_start + i * step
        prof.append((z0 + step * 0.00, y_base))
        prof.append((z0 + step * 0.22, y_base))
        prof.append((z0 + step * 0.34, y_base + rib_h))
        prof.append((z0 + step * 0.74, y_base + rib_h))
        prof.append((z0 + step * 0.86, y_base))
    prof.append((z_start + span_z, y_base))

    thick = 0.018
    n_pts = len(prof)
    # Vorder- und Hinterkante bei x0 und x1, mit Ober- & Unterseite
    verts_front_bot = [pb.bm.verts.new(pb._local_b(Vector((x0, y, z)))) for (z, y) in prof]
    verts_back_bot  = [pb.bm.verts.new(pb._local_b(Vector((x1, y, z)))) for (z, y) in prof]
    verts_front_top = [pb.bm.verts.new(pb._local_b(Vector((x0, y + thick, z)))) for (z, y) in prof]
    verts_back_top  = [pb.bm.verts.new(pb._local_b(Vector((x1, y + thick, z)))) for (z, y) in prof]

    faces = []
    for i in range(n_pts - 1):
        # Untere Sichtflaeche in die Halle (Normal zeigt nach Blender -Z = Godot -Y) + obere Deckflaeche (+Z)
        f_bot = pb.bm.faces.new((verts_front_bot[i], verts_back_bot[i], verts_back_bot[i + 1], verts_front_bot[i + 1]))
        f_bot.normal_update()
        if f_bot.normal.z > 0.0:
            f_bot.normal_flip()
        f_top = pb.bm.faces.new((verts_front_top[i], verts_back_top[i], verts_back_top[i + 1], verts_front_top[i + 1]))
        f_top.normal_update()
        if f_top.normal.z < 0.0:
            f_top.normal_flip()
        # Stirnkappen vorne & hinten schliessen das Profil sauber ab
        f_cap0 = pb.bm.faces.new((verts_front_bot[i], verts_front_bot[i + 1], verts_front_top[i + 1], verts_front_top[i]))
        f_cap1 = pb.bm.faces.new((verts_back_top[i], verts_back_top[i + 1], verts_back_bot[i + 1], verts_back_bot[i]))
        faces.extend((f_bot, f_top, f_cap0, f_cap1))
    for f in faces:
        f.material_index = mid
        f.smooth = False
    pb.bm.normal_update()
    pb._uv_box(faces, uv_scale)


def add_heb_column(pb: PartBuilder, x: float, z: float, h: float, width: float, depth: float,
                   steel_mat, plate_mat, bolt_mat):
    """Echte ausmodellierte HEB-Doppel-T-Stahlstuetze inkl. Fussplatte, Steifen & 4 Sechskant-Ankerbolzen."""
    tf = max(0.016, depth * 0.085)   # Flanschdicke
    tw = max(0.012, width * 0.065)   # Stegdicke
    cy = h * 0.5 + 0.025
    # Vorderflansch, Hinterflansch, Mittelsteg
    pb.box((x, cy, z - depth * 0.5 + tf * 0.5), (width, h, tf), steel_mat, bevel=0.003, uv_scale=1.6)
    pb.box((x, cy, z + depth * 0.5 - tf * 0.5), (width, h, tf), steel_mat, bevel=0.003, uv_scale=1.6)
    pb.box((x, cy, z), (tw, h, depth - tf * 1.8), steel_mat, bevel=0.002, uv_scale=1.6)
    # Horizontale Aussteifungsrippen (Steifenbleche) auf halber Hoehe & am Kopf
    for sy in (0.35, h * 0.52, h - 0.14):
        for side in (-1.0, 1.0):
            pb.box((x + side * (width * 0.24), sy, z), (width * 0.42, 0.014, depth - tf * 2.0), plate_mat, bevel=0.002)
    # Massive vergossene Fussplatte + 4 Sechskant-Ankerbolzen mit Unterlegscheiben!
    bp_w, bp_d = width + 0.12, depth + 0.12
    pb.box((x, 0.016, z), (bp_w, 0.032, bp_d), plate_mat, bevel=0.004)
    for bx in (-bp_w * 0.36, bp_w * 0.36):
        for bz in (-bp_d * 0.36, bp_d * 0.36):
            pb.cyl((x + bx, 0.036, z + bz), 0.018, 0.018, 0.008, bolt_mat, axis_g="y", seg=12)
            pb.cyl((x + bx, 0.050, z + bz), 0.012, 0.012, 0.022, bolt_mat, axis_g="y", seg=6)  # 6-Kant-Mutter!


def add_heb_beam_z(pb: PartBuilder, x: float, y: float, z0: float, z1: float,
                   width: float, height: float, steel_mat, plate_mat=None, bolt_mat=None):
    """Horizontaler IPE/HEB-Doppel-T-Stahltraeger entlang der Z-Achse inkl. geschraubter Stirnplatten."""
    span = abs(z1 - z0)
    cz = (z0 + z1) * 0.5
    tf = max(0.014, height * 0.085)
    tw = max(0.011, width * 0.07)
    pb.box((x, y + height * 0.5 - tf * 0.5, cz), (width, tf, span), steel_mat, bevel=0.003, uv_scale=1.6)
    pb.box((x, y - height * 0.5 + tf * 0.5, cz), (width, tf, span), steel_mat, bevel=0.003, uv_scale=1.6)
    pb.box((x, y, cz), (tw, height - tf * 1.8, span), steel_mat, bevel=0.002, uv_scale=1.6)
    if plate_mat is not None and bolt_mat is not None:
        for ez in (z0 + 0.012, z1 - 0.012):
            pb.box((x, y, ez), (width + 0.04, height + 0.06, 0.020), plate_mat, bevel=0.003)
            for by in (-height * 0.30, 0.0, height * 0.30):
                for bx in (-width * 0.32, width * 0.32):
                    pb.cyl((x + bx, y + by, ez + (0.016 if ez < cz else -0.016)),
                           0.009, 0.009, 0.014, bolt_mat, axis_g="z", seg=6)


def add_pipe_run(pb: PartBuilder, pts_g: list, radius: float, mat, seg: int = 16, bend_r: float = 0.11):
    """Geschmeidig gebogenes 3D-Rohr / Schlauch entlang einer Punktliste (echte abgerundete Rohrboegen!)."""
    if len(pts_g) < 2:
        return
    mid = pb._mid(mat)
    vecs = [Vector(p) for p in pts_g]

    # Abgerundete Eckboegen per quadratischer Bezier-Unterteilung erzeugen
    smooth_pts = [vecs[0]]
    for i in range(1, len(vecs) - 1):
        p_prev, p_cur, p_next = vecs[i - 1], vecs[i], vecs[i + 1]
        v_in = p_cur - p_prev
        v_out = p_next - p_cur
        l_in, l_out = v_in.length, v_out.length
        if l_in < 1e-4 or l_out < 1e-4:
            continue
        r = min(bend_r, l_in * 0.42, l_out * 0.42)
        a = p_cur - v_in.normalized() * r
        b = p_cur + v_out.normalized() * r
        for step in range(7):
            t = step / 6.0
            pt = (1.0 - t) ** 2 * a + 2.0 * (1.0 - t) * t * p_cur + t ** 2 * b
            smooth_pts.append(pt)
    smooth_pts.append(vecs[-1])

    # Schlauch-Ringquerschnitte entlang Tangente extrudieren
    rings = []
    up_ref = Vector((0.0, 0.0, 1.0))
    for idx, p_g in enumerate(smooth_pts):
        p_b = pb._local_b(p_g)
        if idx == 0:
            tang = (pb._local_b(smooth_pts[1]) - p_b).normalized()
        elif idx == len(smooth_pts) - 1:
            tang = (p_b - pb._local_b(smooth_pts[idx - 1])).normalized()
        else:
            tang = (pb._local_b(smooth_pts[idx + 1]) - pb._local_b(smooth_pts[idx - 1])).normalized()
        if tang.length < 1e-5:
            tang = Vector((1.0, 0.0, 0.0))
        ref = Vector((0.0, 1.0, 0.0)) if abs(tang.dot(up_ref)) > 0.92 else up_ref
        n1 = tang.cross(ref).normalized()
        n2 = tang.cross(n1).normalized()
        ring_v = []
        for s_i in range(seg):
            ang = (s_i / float(seg)) * math.pi * 2.0
            off = n1 * (math.cos(ang) * radius) + n2 * (math.sin(ang) * radius)
            ring_v.append(pb.bm.verts.new(p_b + off))
        rings.append(ring_v)

    faces = []
    for r_i in range(len(rings) - 1):
        r0, r1 = rings[r_i], rings[r_i + 1]
        for s_i in range(seg):
            sn = (s_i + 1) % seg
            f = pb.bm.faces.new((r0[s_i], r1[s_i], r1[sn], r0[sn]))
            f.material_index = mid
            f.smooth = True
            faces.append(f)
    # Endkappen
    for end_ring, rev in ((rings[0], True), (rings[-1], False)):
        fc = pb.bm.faces.new(list(reversed(end_ring)) if rev else end_ring)
        fc.material_index = mid
        fc.smooth = False
        faces.append(fc)
    bmesh.ops.recalc_face_normals(pb.bm, faces=faces)
    pb._uv_box(faces, 0.5)


def add_spoked_valve(pb: PartBuilder, pos_g, pipe_axis: str, stem_dir: Vector, body_mat, wheel_mat):
    """Echtes Industrie-Absperrventil mit Flanschen, Spindel & rundem Speichen-Handrad."""
    px, py, pz = pos_g
    pb.cyl((px, py, pz), 0.068, 0.068, 0.12, body_mat, axis_g=pipe_axis, seg=14)
    for off in (-0.065, 0.065):
        fp = (px + (off if pipe_axis == "x" else 0.0),
              py + (off if pipe_axis == "y" else 0.0),
              pz + (off if pipe_axis == "z" else 0.0))
        pb.cyl(fp, 0.088, 0.088, 0.018, body_mat, axis_g=pipe_axis, seg=14)
    sd = stem_dir.normalized()
    stem_mid = Vector(pos_g) + sd * 0.085
    wheel_c = Vector(pos_g) + sd * 0.145
    ax = "z" if abs(sd.z) > 0.7 else ("y" if abs(sd.y) > 0.7 else "x")
    pb.cyl(tuple(stem_mid), 0.016, 0.016, 0.11, body_mat, axis_g=ax, seg=10)
    # Handrad-Kranz (12-Eck-Torus aus Rohrsegmenten + 4 Speichen)
    ring_pts = []
    r_w = 0.095
    for k in range(13):
        a = (k / 12.0) * math.pi * 2.0
        if ax == "z":
            ring_pts.append((wheel_c.x + math.cos(a) * r_w, wheel_c.y + math.sin(a) * r_w, wheel_c.z))
        elif ax == "y":
            ring_pts.append((wheel_c.x + math.cos(a) * r_w, wheel_c.y, wheel_c.z + math.sin(a) * r_w))
        else:
            ring_pts.append((wheel_c.x, wheel_c.y + math.cos(a) * r_w, wheel_c.z + math.sin(a) * r_w))
    add_pipe_run(pb, ring_pts, 0.011, wheel_mat, seg=8, bend_r=0.02)
    for sp_a in (0.0, 90.0):
        if ax == "z":
            pb.box(tuple(wheel_c), (r_w * 1.9, 0.014, 0.014), wheel_mat, rot_g_deg=(0, 0, sp_a), bevel=0.002)
        else:
            pb.box(tuple(wheel_c), (r_w * 1.9, 0.014, 0.014), wheel_mat, rot_g_deg=(0, sp_a, 0), bevel=0.002)


def add_torsion_spring_x(pb: PartBuilder, center_g, length_x: float, coil_r: float, wire_r: float,
                         turns: int, mat):
    """Echte 3D-gewickelte Spiral-Torsionsfeder entlang der X-Achse fuer Sektionaltore."""
    cx, cy, cz = center_g
    pts = []
    steps = turns * 10
    x0 = cx - length_x * 0.5
    for i in range(steps + 1):
        u = i / float(steps)
        ang = u * turns * math.pi * 2.0
        pts.append((x0 + u * length_x, cy + math.cos(ang) * coil_r, cz + math.sin(ang) * coil_r))
    add_pipe_run(pb, pts, wire_r, mat, seg=7, bend_r=0.008)


# ===========================================================================
# 4. Separate Echtglas-Objekt-Helfer (verhindert Schattenwurf auf Fenstern!)
# ===========================================================================

def build_glass_child(root_obj, name: str, glass_specs: list):
    """Erzeugt ein eigenes *_Glass Mesh-Objekt fuer transparente Fensterscheiben.
    glass_specs: Liste aus (center_g, size_g, glass_mat, rot_g_deg).
    """
    pb_g = PartBuilder(name, origin_g=Vector((0, 0, 0)))
    for item in glass_specs:
        cg, sg, gmat = item[0], item[1], item[2]
        rot = item[3] if len(item) > 3 else (0.0, 0.0, 0.0)
        pb_g.box(cg, sg, gmat, rot_g_deg=rot, bevel=0.0)
    return pb_g.build(root_obj)


# ===========================================================================
# 5. High-Poly Industrie- & Werkstatt-Props (0 % Low-Poly-Klötze!)
# ===========================================================================

def add_euro_pallet_hq(pb: PartBuilder, pos_g, wood_mat, nail_mat, yaw_deg: float = 0.0):
    """Echte Europalette DIN EN 13698-1 (1.20 x 0.144 x 0.80 m): 9 Kloetze, 3 Bodenbretter, 3 Querbretter, 5 Deckbretter."""
    cx, cy, cz = pos_g
    ya = math.radians(yaw_deg)
    ca, sa = math.cos(ya), math.sin(ya)

    def _lp(lx: float, ly: float, lz: float):
        return (cx + lx * ca + lz * sa, cy + ly, cz - lx * sa + lz * ca)

    # 3 Bodenbretter + 9 Distanzkloetze
    for lz in (-0.34, 0.0, 0.34):
        pb.box(_lp(0.0, 0.011, lz), (1.20, 0.022, 0.10), wood_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.003, uv_scale=0.9)
        for lx in (-0.52, 0.0, 0.52):
            pb.box(_lp(lx, 0.061, lz), (0.14, 0.078, 0.10), wood_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.004, uv_scale=0.5)
    # 3 Querbretter
    for lx in (-0.52, 0.0, 0.52):
        pb.box(_lp(lx, 0.111, 0.0), (0.14, 0.022, 0.80), wood_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.003, uv_scale=0.9)
    # 5 Deckbretter (breit/schmal im Wechsel wie beim Original!)
    for lx, bw in ((-0.52, 0.145), (-0.26, 0.10), (0.0, 0.145), (0.26, 0.10), (0.52, 0.145)):
        pb.box(_lp(lx, 0.133, 0.0), (bw, 0.022, 0.80), wood_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.003, uv_scale=0.9)
        for lz in (-0.34, 0.0, 0.34):
            pb.cyl(_lp(lx, 0.145, lz), 0.004, 0.004, 0.002, nail_mat, axis_g="y", seg=6)


def add_pallet_jack_hq(pb: PartBuilder, pos_g, yellow_mat, dark_steel, chrome_mat, rubber_mat, yaw_deg: float = 0.0):
    """High-Poly Gabelhubwagen ('Ameise'): geformte Gabelzinken, Tandem-Lastrollen, Hydraulikzylinder & runde Deichsel."""
    cx, cy, cz = pos_g
    ya = math.radians(yaw_deg)
    ca, sa = math.cos(ya), math.sin(ya)

    def _lp(lx: float, ly: float, lz: float):
        return (cx + lx * ca + lz * sa, cy + ly, cz - lx * sa + lz * ca)

    # 2 geformte U-Profil-Gabelzinken mit abgeschrägter Einfahrspitze & Lastrollen
    for fz in (-0.185, 0.185):
        pb.box(_lp(0.32, 0.072, fz), (0.98, 0.048, 0.155), yellow_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.010)
        pb.box(_lp(0.85, 0.062, fz), (0.14, 0.030, 0.135), yellow_mat, rot_g_deg=(0, yaw_deg, -8.0), bevel=0.008)
        for rx in (0.72, 0.80):
            pb.cyl(_lp(rx, 0.038, fz), 0.038, 0.038, 0.075, rubber_mat, axis_g="z", seg=16)
            pb.cyl(_lp(rx, 0.038, fz), 0.016, 0.016, 0.082, chrome_mat, axis_g="z", seg=10)
    # Geschwungene Hubbruecke (Schulter) + Hydraulik-Pumpeneinheit
    pb.box(_lp(-0.18, 0.19, 0.0), (0.16, 0.24, 0.52), yellow_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.018)
    pb.cyl(_lp(-0.28, 0.28, 0.0), 0.068, 0.076, 0.26, dark_steel, axis_g="y", seg=20)
    pb.cyl(_lp(-0.28, 0.44, 0.0), 0.028, 0.028, 0.14, chrome_mat, axis_g="y", seg=16)  # Verchromter Hubkolben
    # Drehschemel-Gabel + Zwillings-Lenkraeder mit Alufelge
    pb.box(_lp(-0.30, 0.15, 0.0), (0.14, 0.10, 0.22), dark_steel, rot_g_deg=(0, yaw_deg, 0), bevel=0.01)
    for wz in (-0.085, 0.085):
        pb.cyl(_lp(-0.30, 0.090, wz), 0.090, 0.090, 0.052, rubber_mat, axis_g="z", seg=22)
        pb.cyl(_lp(-0.30, 0.090, wz), 0.048, 0.048, 0.056, chrome_mat, axis_g="z", seg=14)
    # Gebogene Rundrohr-Deichsel + ovaler ergonomischer Handgriff mit Ablasshebel!
    pts_bar = [_lp(-0.31, 0.34, 0.0), _lp(-0.36, 0.68, 0.0), _lp(-0.42, 1.08, 0.0)]
    add_pipe_run(pb, pts_bar, 0.019, dark_steel, seg=12, bend_r=0.08)
    pts_loop = [
        _lp(-0.42, 1.08, -0.02),
        _lp(-0.43, 1.12, -0.14),
        _lp(-0.45, 1.25, -0.14),
        _lp(-0.45, 1.25,  0.14),
        _lp(-0.43, 1.12,  0.14),
        _lp(-0.42, 1.08,  0.02),
    ]
    add_pipe_run(pb, pts_loop, 0.016, rubber_mat, seg=10, bend_r=0.045)
    pb.box(_lp(-0.43, 1.18, 0.05), (0.015, 0.06, 0.08), chrome_mat, rot_g_deg=(0, yaw_deg, 18.0), bevel=0.003)


def add_wire_gitterbox_hq(pb: PartBuilder, pos_g, steel_mat, galv_mat, wood_mat, card_mat, tape_mat, yaw_deg: float = 0.0):
    """Echte deutsche DB-Gitterboxpalette DIN 15155 mit offenem 3D-Stahldrahtgitter & sichtbaren Kartons im Inneren!"""
    cx, cy, cz = pos_g
    ya = math.radians(yaw_deg)
    ca, sa = math.cos(ya), math.sin(ya)

    def _lp(lx: float, ly: float, lz: float):
        return (cx + lx * ca + lz * sa, cy + ly, cz - lx * sa + lz * ca)

    w, h, d = 0.84, 0.96, 1.22
    # 4 Staplerfuesse + Holz-Einlegeboden + unterer Stahlrahmen
    for fx in (-w * 0.45, w * 0.45):
        for fz in (-d * 0.45, d * 0.45):
            pb.box(_lp(fx, 0.06, fz), (0.10, 0.12, 0.10), steel_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.008)
            # 4 Eck-Winkelpfosten mit Stapeltaschen oben
            pb.box(_lp(fx, 0.54, fz), (0.048, 0.86, 0.048), steel_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.005)
            pb.box(_lp(fx, 0.98, fz), (0.072, 0.035, 0.072), steel_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.004)
    pb.box(_lp(0.0, 0.13, 0.0), (w - 0.04, 0.032, d - 0.04), wood_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.004)
    # Unterer gesickter Blechrand + oberer Abschlussrahmen + Klappen-Schild an der Front (-X)
    for ry in (0.20, 0.56, 0.94):
        for fz in (-d * 0.46, d * 0.46):
            pb.box(_lp(0.0, ry, fz), (w, 0.032, 0.022), steel_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.003)
        for fx in (-w * 0.46, w * 0.46):
            pb.box(_lp(fx, ry, 0.0), (0.022, 0.032, d), steel_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.003)
    pb.box(_lp(-w * 0.465, 0.74, 0.0), (0.012, 0.18, 0.34), steel_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.002)

    # Echtes 3D-Drahtgitter an allen 4 Waenden (man schaut durch das Gitter auf die Kartons!)
    for wy in (0.30, 0.42, 0.66, 0.80):
        for side in (-1.0, 1.0):
            add_pipe_run(pb, [_lp(side * w * 0.46, wy, -d * 0.43), _lp(side * w * 0.46, wy, d * 0.43)], 0.0048, galv_mat, seg=6)
            add_pipe_run(pb, [_lp(-w * 0.43, wy, side * d * 0.46), _lp(w * 0.43, wy, side * d * 0.46)], 0.0048, galv_mat, seg=6)
    for wz in np.linspace(-d * 0.40, d * 0.40, 9):
        for side in (-1.0, 1.0):
            pb.cyl(_lp(side * w * 0.46, 0.57, float(wz)), 0.0048, 0.0048, 0.72, galv_mat, axis_g="y", seg=6)
    for wx in np.linspace(-w * 0.38, w * 0.38, 6):
        for side in (-1.0, 1.0):
            pb.cyl(_lp(float(wx), 0.57, side * d * 0.46), 0.0048, 0.0048, 0.72, galv_mat, axis_g="y", seg=6)

    # 4 realistisch leicht versetzte Versandkartons IM INNEREN der Gitterbox!
    for bx, by, bz, sx, sy, sz, rot_c in (
        (-0.08, 0.31, -0.26, 0.46, 0.32, 0.48,  6.0),
        ( 0.06, 0.29,  0.28, 0.44, 0.28, 0.46, -8.0),
        (-0.04, 0.61, -0.18, 0.42, 0.26, 0.44, 14.0),
        ( 0.05, 0.56,  0.26, 0.38, 0.24, 0.40, -5.0),
    ):
        pb.box(_lp(bx, by, bz), (sx, sy, sz), card_mat, rot_g_deg=(0, yaw_deg + rot_c, 0), bevel=0.008)
        pb.box(_lp(bx, by + sy * 0.5 + 0.002, bz), (sx + 0.004, 0.003, 0.048), tape_mat, rot_g_deg=(0, yaw_deg + rot_c, 0))


def add_rolling_tool_chest_hq(pb: PartBuilder, pos_g, red_mat, dark_mat, alu_mat, rubber_mat, yaw_deg: float = 0.0):
    """High-Poly Werkstattwagen mit 6 kugelgelagerten Schubladen, Lenkrollen mit Gabeln & rundem Schiebebuegel."""
    cx, cy, cz = pos_g
    ya = math.radians(yaw_deg)
    ca, sa = math.cos(ya), math.sin(ya)

    def _lp(lx: float, ly: float, lz: float):
        return (cx + lx * ca + lz * sa, cy + ly, cz - lx * sa + lz * ca)

    # Korpus + Kantenschutzprofile + geriffelte Gummi-Arbeitsmatte oben
    pb.box(_lp(0.0, 0.54, 0.0), (0.86, 0.80, 0.50), red_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.018)
    for ex in (-0.425, 0.425):
        for ez in (-0.245, 0.245):
            pb.box(_lp(ex, 0.54, ez), (0.032, 0.81, 0.032), dark_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.006)
    pb.box(_lp(0.0, 0.955, 0.0), (0.88, 0.032, 0.52), dark_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.008)
    pb.box(_lp(0.0, 0.974, 0.0), (0.82, 0.012, 0.46), rubber_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.004)

    # 6 Schubladen an der Vorderseite (-Z lokal) mit durchgehenden eloxierten Alu-Griffleisten & Zylinderschloss
    d_heights = (0.085, 0.085, 0.105, 0.105, 0.135, 0.165)
    cur_y = 0.875
    for dh in d_heights:
        dy = cur_y - dh * 0.5
        pb.box(_lp(0.0, dy, -0.256), (0.76, dh - 0.010, 0.018), red_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.005)
        pb.box(_lp(0.0, dy + dh * 0.24, -0.272), (0.72, 0.020, 0.022), alu_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.004)
        cur_y -= dh
    pb.cyl(_lp(0.35, 0.89, -0.262), 0.012, 0.012, 0.012, alu_mat, axis_g="z", seg=12)

    # Runder Edelstahl-Schiebebuegel seitlich links
    add_pipe_run(pb, [
        _lp(-0.43, 0.86, -0.17),
        _lp(-0.52, 0.86, -0.17),
        _lp(-0.52, 0.86,  0.17),
        _lp(-0.43, 0.86,  0.17),
    ], 0.015, alu_mat, seg=12, bend_r=0.035)

    # 4 Schwerlast-Lenkrollen mit verzinkter Gabel & Radbremse
    for rx in (-0.34, 0.34):
        for rz in (-0.18, 0.18):
            pb.box(_lp(rx, 0.125, rz), (0.085, 0.022, 0.085), alu_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.003)
            pb.box(_lp(rx, 0.085, rz), (0.056, 0.068, 0.072), alu_mat, rot_g_deg=(0, yaw_deg, 0), bevel=0.005)
            pb.cyl(_lp(rx, 0.056, rz), 0.056, 0.056, 0.042, rubber_mat, axis_g="x", seg=18)
            pb.cyl(_lp(rx, 0.056, rz), 0.028, 0.028, 0.046, red_mat, axis_g="x", seg=12)


def add_industrial_vacuum_hq(pb: PartBuilder, pos_g, yellow_mat, dark_mat, alu_mat, rubber_mat):
    """High-Poly Industrie-Nass-/Trockensauger mit Fahrgestell, Motorkopf, gebogenem Saugschlauch & Bodenduese!"""
    cx, cy, cz = pos_g
    # Fahrgestell-Ring mit Rammschutz & 5 Lenkrollen
    pb.cyl((cx, cy + 0.09, cz), 0.235, 0.245, 0.08, dark_mat, axis_g="y", seg=24)
    for k in range(5):
        a = (k / 5.0) * math.pi * 2.0
        wx, wz = cx + math.cos(a) * 0.21, cz + math.sin(a) * 0.21
        pb.cyl((wx, cy + 0.032, wz), 0.032, 0.032, 0.028, rubber_mat, axis_g="x", seg=12)
    # Edelstahl-Kessel mit Sicke + gelbem Motorkopf + Drehschalter + Klappbuegel
    pb.cyl((cx, cy + 0.32, cz), 0.195, 0.205, 0.40, alu_mat, axis_g="y", seg=26)
    pb.cyl((cx, cy + 0.36, cz), 0.206, 0.206, 0.026, alu_mat, axis_g="y", seg=26)
    pb.cyl((cx, cy + 0.58, cz), 0.175, 0.202, 0.15, yellow_mat, axis_g="y", seg=26)
    pb.box((cx, cy + 0.67, cz), (0.22, 0.05, 0.14), dark_mat, bevel=0.012)
    pb.cyl((cx, cy + 0.59, cz + 0.185), 0.028, 0.028, 0.025, dark_mat, axis_g="z", seg=14)  # Drehschalter
    # Geschwungener schwarzer Saugschlauch + verchromtes Saugrohr + breite Bodenduese!
    add_pipe_run(pb, [
        (cx + 0.02, cy + 0.42, cz + 0.20),
        (cx + 0.18, cy + 0.40, cz + 0.30),
        (cx + 0.28, cy + 0.18, cz + 0.24),
        (cx + 0.32, cy + 0.54, cz + 0.12),
        (cx + 0.34, cy + 0.86, cz + 0.06),
    ], 0.021, rubber_mat, seg=12, bend_r=0.09)
    add_pipe_run(pb, [
        (cx + 0.34, cy + 0.86, cz + 0.06),
        (cx + 0.38, cy + 0.44, cz + 0.14),
        (cx + 0.42, cy + 0.04, cz + 0.22),
    ], 0.017, alu_mat, seg=12, bend_r=0.06)
    pb.box((cx + 0.42, cy + 0.028, cz + 0.23), (0.32, 0.045, 0.095), dark_mat, rot_g_deg=(0, -14.0, 0), bevel=0.008)


def add_fire_extinguisher_hq(pb: PartBuilder, pos_g, red_mat, chrome_mat, dark_mat, label_mat):
    """High-Poly 6kg ABC-Pulverfeuerloescher mit gewoelbter Schulter, Manometer, Griffarmatur & Schlauch."""
    cx, cy, cz = pos_g
    pb.cyl((cx, cy + 0.02, cz), 0.088, 0.090, 0.04, dark_mat, axis_g="y", seg=24)
    pb.cyl((cx, cy + 0.24, cz), 0.085, 0.085, 0.42, red_mat, axis_g="y", seg=28)
    pb.cyl((cx, cy + 0.47, cz), 0.032, 0.085, 0.07, red_mat, axis_g="y", seg=28)
    pb.cyl((cx, cy + 0.25, cz), 0.0865, 0.0865, 0.18, label_mat, axis_g="y", seg=28)
    pb.cyl((cx, cy + 0.53, cz), 0.026, 0.028, 0.065, chrome_mat, axis_g="y", seg=18)
    pb.cyl((cx, cy + 0.54, cz + 0.032), 0.018, 0.018, 0.015, chrome_mat, axis_g="z", seg=16)  # Manometer
    pb.box((cx - 0.045, cy + 0.575, cz), (0.15, 0.014, 0.028), dark_mat, rot_g_deg=(0, 0, -10.0), bevel=0.003)
    pb.box((cx - 0.040, cy + 0.548, cz), (0.14, 0.014, 0.028), dark_mat, rot_g_deg=(0, 0, 3.0), bevel=0.003)
    add_pipe_run(pb, [
        (cx + 0.03, cy + 0.53, cz),
        (cx + 0.10, cy + 0.50, cz + 0.02),
        (cx + 0.11, cy + 0.18, cz + 0.02),
    ], 0.011, dark_mat, seg=10, bend_r=0.04)
    pb.cyl((cx + 0.11, cy + 0.12, cz + 0.02), 0.013, 0.026, 0.11, dark_mat, axis_g="y", seg=14)


def add_sculpted_leaf(pb: PartBuilder, base_g, yaw_deg: float, pitch_deg: float,
                      length: float, width: float, arch: float, leaf_mat):
    """Echtes geformtes, spitz zulaufendes & leicht gewölbtes Pflanzenblatt (statt flacher Box!)."""
    mid = pb._mid(leaf_mat)
    # 6 Querschnitte vom Blattstiel bis zur Blattspitze (lokal entlang +Z = Auslegerichtung)
    prof = (
        (0.00, 0.006,  0.000),
        (0.18, 0.55,   0.35),
        (0.42, 1.00,   0.78),
        (0.68, 0.82,   0.85),
        (0.88, 0.38,   0.45),
        (1.00, 0.002, -0.15),
    )
    rot_m = Euler((math.radians(pitch_deg), 0.0, math.radians(yaw_deg)), "XYZ").to_matrix()
    base_b = pb._local_b(Vector(base_g))

    rows_top = []
    rows_bot = []
    for u, w_f, a_f in prof:
        hw = width * 0.5 * w_f
        z_up = arch * a_f - (u * u) * arch * 0.65
        y_fwd = u * length
        pts_t = [
            Vector((-hw, -y_fwd, z_up - hw * 0.16)),
            Vector((0.0, -y_fwd, z_up + 0.005)),
            Vector(( hw, -y_fwd, z_up - hw * 0.16)),
        ]
        pts_b = [p - Vector((0.0, 0.0, 0.0025)) for p in pts_t]
        rows_top.append([pb.bm.verts.new(base_b + (rot_m @ p)) for p in pts_t])
        rows_bot.append([pb.bm.verts.new(base_b + (rot_m @ p)) for p in pts_b])

    faces = []
    for i in range(len(rows_top) - 1):
        rt0, rt1 = rows_top[i], rows_top[i + 1]
        rb0, rb1 = rows_bot[i], rows_bot[i + 1]
        for c in range(2):
            f_top = pb.bm.faces.new((rt0[c], rt0[c + 1], rt1[c + 1], rt1[c]))
            f_bot = pb.bm.faces.new((rb1[c], rb1[c + 1], rb0[c + 1], rb0[c]))
            for f in (f_top, f_bot):
                f.material_index = mid
                f.smooth = True
                faces.append(f)
    pb.bm.normal_update()
    pb._uv_box(faces, 0.4)
