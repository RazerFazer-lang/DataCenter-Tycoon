"""Blender 5.2 Generator fuer die neuen IT-Werkstatt-Modelle (2K PBR):
- workshop_workbench.glb      (Industrielle IT-Werkbank mit Lochwand, LED-Leiste, Labornetzteil, Loetstation, ESD-Matte)
- workshop_storage_shelf.glb  (Funktionales Schwerlast-Lagerregal mit 4 Ebenen x 3 freien Stellplaetzen & Etikettenleisten)
- repair_kit_case.glb         (Robuster Reparatur-Kit-Koffer mit Griff, Schnallen & Etikettenfeld)
- delivery_build_box.glb      (Industrieller Versandkarton mit Klebeband, Umreifung & Versandetikett)

Aufruf:
    blender --background --factory-startup --python-exit-code 1 --python tools/blender/build_workshop_models.py

Koordinaten: Blender Z oben, Front -Y (wird beim glTF-Export zu Godot +Z), Boden Z = 0.
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

OUT_MODELS_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models"))
CACHE_DIR = os.path.join(SCRIPT_DIR, "_pbr_cache")


# ---------------------------------------------------------------------------
# 2K PBR Texturen fuer Werkstatt, Lagerregal, Oszilloskop & Versandkarton
# ---------------------------------------------------------------------------

def _save_rgb(path: str, arr_01: np.ndarray) -> None:
    pbr_textures.save_png(path, np.clip(arr_01 * 255.0, 0.0, 255.0).astype(np.uint8))


def _gen_powder_coat(cache_dir: str, name: str, base_rgb, rough_val: float, metal_val: float, size: int = 512) -> dict:
    alb_p = os.path.join(cache_dir, f"{name}_albedo.png")
    orm_p = os.path.join(cache_dir, f"{name}_orm.png")
    nrm_p = os.path.join(cache_dir, f"{name}_normal.png")
    if os.path.exists(alb_p) and os.path.exists(orm_p) and os.path.exists(nrm_p):
        return {"albedo": alb_p, "orm": orm_p, "normal": nrm_p}
    n1 = pbr_textures.fbm_tile(size, size, 16, 16, octaves=4, seed=41)
    n2 = pbr_textures.fbm_tile(size, size, 64, 64, octaves=2, seed=73)
    grain = (n1 * 0.55 + n2 * 0.45)
    alb = np.zeros((size, size, 3), dtype=np.float32)
    for c in range(3):
        alb[:, :, c] = np.clip(base_rgb[c] + (grain - 0.5) * 0.045, 0.0, 1.0)
    ao = np.clip(0.94 + (grain - 0.5) * 0.08, 0.75, 1.0)
    rough = np.clip(rough_val + (grain - 0.5) * 0.12, 0.12, 0.95)
    metal = np.full((size, size), metal_val, dtype=np.float32)
    _save_rgb(alb_p, alb)
    pbr_textures.save_png(orm_p, pbr_textures.pack_orm(ao, rough, metal))
    pbr_textures.save_png(nrm_p, pbr_textures.height_to_normal(grain, strength=1.4))
    return {"albedo": alb_p, "orm": orm_p, "normal": nrm_p}


def _gen_pegboard_pbr(cache_dir: str, size: int = 1024) -> dict:
    alb_p = os.path.join(cache_dir, "ws_pegboard_albedo.png")
    orm_p = os.path.join(cache_dir, "ws_pegboard_orm.png")
    nrm_p = os.path.join(cache_dir, "ws_pegboard_normal.png")
    if os.path.exists(alb_p) and os.path.exists(orm_p) and os.path.exists(nrm_p):
        return {"albedo": alb_p, "orm": orm_p, "normal": nrm_p}
    grain = pbr_textures.fbm_tile(size, size, 16, 16, octaves=3, seed=91)
    alb = np.zeros((size, size, 3), dtype=np.float32)
    alb[:, :, 0] = 0.095 + (grain - 0.5) * 0.025
    alb[:, :, 1] = 0.105 + (grain - 0.5) * 0.025
    alb[:, :, 2] = 0.120 + (grain - 0.5) * 0.025
    h = np.full((size, size), 0.75, dtype=np.float32) + (grain - 0.5) * 0.04
    ao = np.full((size, size), 0.95, dtype=np.float32)
    rough = np.full((size, size), 0.44, dtype=np.float32)
    metal = np.full((size, size), 0.72, dtype=np.float32)

    # 32x32 Lochraster (gestanzte Rundloecher mit dunklem Inneren & glatter Kante)
    step = size // 32
    yy, xx = np.mgrid[0:size, 0:size]
    gx = (xx % step) - step * 0.5
    gy = (yy % step) - step * 0.5
    dist = np.sqrt(gx * gx + gy * gy)
    hole = dist < (step * 0.22)
    rim = (dist >= step * 0.22) & (dist < step * 0.30)
    alb[hole] = np.array([0.015, 0.018, 0.022], dtype=np.float32)
    h[hole] = 0.05
    ao[hole] = 0.20
    rough[hole] = 0.90
    metal[hole] = 0.10
    h[rim] = 0.58
    ao[rim] = 0.78

    _save_rgb(alb_p, alb)
    pbr_textures.save_png(orm_p, pbr_textures.pack_orm(ao, rough, metal))
    pbr_textures.save_png(nrm_p, pbr_textures.height_to_normal(h, strength=3.2))
    return {"albedo": alb_p, "orm": orm_p, "normal": nrm_p}


def _gen_cardboard_pbr(cache_dir: str, size: int = 1024) -> dict:
    alb_p = os.path.join(cache_dir, "ws_cardboard_albedo.png")
    orm_p = os.path.join(cache_dir, "ws_cardboard_orm.png")
    nrm_p = os.path.join(cache_dir, "ws_cardboard_normal.png")
    if os.path.exists(alb_p) and os.path.exists(orm_p) and os.path.exists(nrm_p):
        return {"albedo": alb_p, "orm": orm_p, "normal": nrm_p}
    n1 = pbr_textures.fbm_tile(size, size, 12, 12, octaves=4, seed=117)
    n2 = pbr_textures.fbm_tile(size, size, 48, 8, octaves=3, seed=131)
    yy = np.linspace(0.0, 2.0 * math.pi * 64.0, size, dtype=np.float32)[:, None]
    flute = np.broadcast_to(0.5 + 0.5 * np.sin(yy), (size, size)).astype(np.float32)
    fibers = n1 * 0.55 + n2 * 0.35 + flute * 0.10
    alb = np.zeros((size, size, 3), dtype=np.float32)
    alb[:, :, 0] = np.clip(0.58 + (fibers - 0.5) * 0.12, 0.0, 1.0)
    alb[:, :, 1] = np.clip(0.45 + (fibers - 0.5) * 0.10, 0.0, 1.0)
    alb[:, :, 2] = np.clip(0.30 + (fibers - 0.5) * 0.08, 0.0, 1.0)
    ao = np.clip(0.88 + (flute - 0.5) * 0.10, 0.72, 1.0)
    rough = np.clip(0.84 + (n1 - 0.5) * 0.12, 0.65, 0.98)
    metal = np.zeros((size, size), dtype=np.float32)
    _save_rgb(alb_p, alb)
    pbr_textures.save_png(orm_p, pbr_textures.pack_orm(ao, rough, metal))
    pbr_textures.save_png(nrm_p, pbr_textures.height_to_normal(fibers, strength=2.2))
    return {"albedo": alb_p, "orm": orm_p, "normal": nrm_p}


def _gen_scope_screen(cache_dir: str) -> str:
    p = os.path.join(cache_dir, "ws_scope_screen.png")
    if os.path.exists(p):
        return p
    w, h = 512, 320
    img = np.zeros((h, w, 3), dtype=np.float32)
    img[:, :] = np.array([0.025, 0.065, 0.055], dtype=np.float32)
    # Messraster
    for gx in range(32, w, 48):
        img[:, gx:gx + 1] = np.array([0.06, 0.18, 0.15], dtype=np.float32)
    for gy in range(32, h, 48):
        img[gy:gy + 1, :] = np.array([0.06, 0.18, 0.15], dtype=np.float32)
    # 12V-Spannungskurve (Cyan) & PWM-Takt (Gelb)
    for x in range(16, w - 16):
        y1 = int(120 + 28 * math.sin(x * 0.055) + 8 * math.sin(x * 0.19))
        y2 = 220 if ((x // 28) % 2 == 0) else 258
        img[max(0, y1 - 2):min(h, y1 + 3), x] = np.array([0.16, 0.95, 0.78], dtype=np.float32)
        img[max(0, y2 - 2):min(h, y2 + 2), x] = np.array([0.96, 0.78, 0.18], dtype=np.float32)
    pbr_textures.draw_text(img, 18, 16, "CH1 12.04V  3.8A", (0.28, 0.98, 0.82), scale=2)
    pbr_textures.draw_text(img, 18, 42, "CH2 3.31V  PWM OK", (0.98, 0.82, 0.25), scale=2)
    _save_rgb(p, img)
    return p


def _gen_shelf_plaque(cache_dir: str) -> str:
    p = os.path.join(cache_dir, "ws_shelf_plaque.png")
    if os.path.exists(p):
        return p
    w, h = 512, 128
    img = np.zeros((h, w, 3), dtype=np.float32)
    img[:, :] = np.array([0.92, 0.72, 0.10], dtype=np.float32)
    pbr_textures.stroke_rect(img, 4, 4, w - 5, h - 5, (0.06, 0.06, 0.07), thickness=5)
    pbr_textures.fill_rect(img, 12, 12, w - 13, 52, (0.08, 0.08, 0.09))
    pbr_textures.draw_text(img, 26, 22, "DCT TEILE-LAGER  HD-250", (0.95, 0.78, 0.18), scale=2)
    pbr_textures.draw_text(img, 24, 72, "MAX 250 KG / EBENE  ESD-SAFE", (0.06, 0.06, 0.07), scale=2)
    _save_rgb(p, img)
    return p


# ---------------------------------------------------------------------------
# Blender Material- & Geometrie-Helfer
# ---------------------------------------------------------------------------

def _ensure_gltf_ao_group():
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is not None:
        return ng
    ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    ng.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return ng


def _load_img(path: str, colorspace: str):
    key = os.path.basename(path)
    img = bpy.data.images.get(key)
    if img is None:
        img = bpy.data.images.load(path)
        img.name = key
    img.colorspace_settings.name = colorspace
    return img


def _new_mat(name: str):
    mat = bpy.data.materials.new(name=name)
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (450, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat, nt, bsdf


def make_pbr_mat(name: str, maps: dict, normal_strength: float = 1.0):
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
    return mat


def make_solid_mat(name: str, rgba, rough: float = 0.45, metal: float = 0.0, emission=None, em_strength: float = 0.0):
    mat, _nt, bsdf = _new_mat(name)
    bsdf.inputs["Base Color"].default_value = (rgba[0], rgba[1], rgba[2], rgba[3] if len(rgba) > 3 else 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emission is not None and em_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = em_strength
    return mat


def make_emissive_tex_mat(name: str, img_path: str, em_strength: float = 1.2, rough: float = 0.22):
    mat, nt, bsdf = _new_mat(name)
    t_img = nt.nodes.new("ShaderNodeTexImage")
    t_img.image = _load_img(img_path, "sRGB")
    nt.links.new(t_img.outputs["Color"], bsdf.inputs["Base Color"])
    if em_strength > 0.0:
        nt.links.new(t_img.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = em_strength
    bsdf.inputs["Roughness"].default_value = rough
    return mat


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


class MeshBuilder:
    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.uv_layer = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []
        self.mat_idx = {}

    def _mid(self, mat) -> int:
        if mat.name not in self.mat_idx:
            self.mat_idx[mat.name] = len(self.mats)
            self.mats.append(mat)
        return self.mat_idx[mat.name]

    def _apply_box_uv(self, faces, scale: float, uv_mode: str = "box", origin=Vector((0, 0, 0)), size=Vector((1, 1, 1))):
        for f in faces:
            n = f.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            for l in f.loops:
                co = l.vert.co
                if uv_mode == "planar_top":
                    u = (co.x - origin.x) / max(size.x, 1e-4) + 0.5
                    v = (co.y - origin.y) / max(size.y, 1e-4) + 0.5
                elif uv_mode == "planar_front":
                    u = (co.x - origin.x) / max(size.x, 1e-4) + 0.5
                    v = (co.z - origin.z) / max(size.z, 1e-4) + 0.5
                else:
                    if az >= ax and az >= ay:
                        u, v = co.x / scale, co.y / scale
                    elif ay >= ax:
                        u, v = co.x / scale, co.z / scale
                    else:
                        u, v = co.y / scale, co.z / scale
                l[self.uv_layer].uv = (u, v)

    def box(self, center, size, mat, rot_deg=(0.0, 0.0, 0.0), bevel: float = 0.002, uv_scale: float = 0.5, uv_mode: str = "box"):
        mid = self._mid(mat)
        sx, sy, sz = size
        cx, cy, cz = center
        ret = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = ret["verts"]
        for v in verts:
            v.co.x *= sx
            v.co.y *= sy
            v.co.z *= sz
        if bevel > 0.0 and min(sx, sy, sz) > bevel * 3.0:
            edges = list({e for v in verts for e in v.link_edges})
            res = bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, affect="EDGES", clamp_overlap=True)
            verts = [v for v in ({v for v in verts} | {v for v in res.get("verts", [])}) if v.is_valid]
        rot_m = Euler((math.radians(rot_deg[0]), math.radians(rot_deg[1]), math.radians(rot_deg[2])), "XYZ").to_matrix().to_4x4()
        xf = Matrix.Translation((cx, cy, cz)) @ rot_m
        bmesh.ops.transform(self.bm, matrix=xf, verts=verts)
        faces = list({f for v in verts for f in v.link_faces})
        for f in faces:
            f.material_index = mid
            f.smooth = False
        self.bm.normal_update()
        self._apply_box_uv(faces, uv_scale, uv_mode, Vector((cx, cy, cz)), Vector((sx, sy, sz)))

    def cyl(self, center, radius: float, height: float, mat, axis: str = "z", seg: int = 20, uv_scale: float = 0.4):
        mid = self._mid(mat)
        ret = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=seg,
            radius1=radius, radius2=radius, depth=height
        )
        verts = ret["verts"]
        if axis == "x":
            rot_m = Euler((0.0, math.radians(90.0), 0.0), "XYZ").to_matrix().to_4x4()
        elif axis == "y":
            rot_m = Euler((math.radians(90.0), 0.0, 0.0), "XYZ").to_matrix().to_4x4()
        else:
            rot_m = Matrix.Identity(4)
        xf = Matrix.Translation(center) @ rot_m
        bmesh.ops.transform(self.bm, matrix=xf, verts=verts)
        faces = list({f for v in verts for f in v.link_faces})
        for f in faces:
            f.material_index = mid
            f.smooth = abs(f.normal.z if axis == "z" else (f.normal.y if axis == "y" else f.normal.x)) < 0.85
        self.bm.normal_update()
        self._apply_box_uv(faces, uv_scale)

    def build_object(self):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj


def export_glb(out_path: str):
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=out_path,
        export_format="GLB",
        export_materials="EXPORT",
        export_yup=True,
        export_apply=True,
    )
    print(f"EXPORTED: {out_path} ({os.path.getsize(out_path)} bytes)")


# ---------------------------------------------------------------------------
# Gemeinsame Materialien initialisieren
# ---------------------------------------------------------------------------

def build_materials():
    os.makedirs(CACHE_DIR, exist_ok=True)
    m_anthracite = make_pbr_mat("WS_AnthraciteSteel", _gen_powder_coat(CACHE_DIR, "ws_anthracite", (0.085, 0.092, 0.105), 0.42, 0.78), 0.9)
    m_galv = make_pbr_mat("WS_GalvSteel", pbr_textures.gen_brushed_metal_pbr(CACHE_DIR, "ws_galv_steel", (0.58, 0.60, 0.63), 0.88, 0.34), 0.7)
    m_dark_bench = make_pbr_mat("WS_BenchTop", _gen_powder_coat(CACHE_DIR, "ws_benchtop_dark", (0.14, 0.15, 0.165), 0.56, 0.10), 0.8)
    m_oak_shelf = make_pbr_mat("WS_WoodShelf", _gen_powder_coat(CACHE_DIR, "ws_wood_oak", (0.28, 0.19, 0.11), 0.62, 0.02), 1.1)
    m_esd = make_pbr_mat("WS_EsdMat", pbr_textures.gen_esd_mat_pbr(CACHE_DIR), 0.7)
    m_pegboard = make_pbr_mat("WS_Pegboard", _gen_pegboard_pbr(CACHE_DIR), 1.2)
    m_cardboard = make_pbr_mat("WS_Cardboard", _gen_cardboard_pbr(CACHE_DIR), 1.0)
    m_scope_scr = make_emissive_tex_mat("WS_ScopeScreen", _gen_scope_screen(CACHE_DIR), em_strength=1.35, rough=0.15)
    m_plaque = make_emissive_tex_mat("WS_ShelfPlaque", _gen_shelf_plaque(CACHE_DIR), em_strength=0.0, rough=0.35)

    return {
        "anthracite": m_anthracite,
        "galv": m_galv,
        "bench_top": m_dark_bench,
        "wood": m_oak_shelf,
        "esd": m_esd,
        "pegboard": m_pegboard,
        "cardboard": m_cardboard,
        "scope_scr": m_scope_scr,
        "plaque": m_plaque,
        "chrome": make_solid_mat("WS_Chrome", (0.82, 0.85, 0.88, 1.0), 0.16, 0.96),
        "rubber": make_solid_mat("WS_Rubber", (0.045, 0.048, 0.052, 1.0), 0.86, 0.02),
        "plastic_dark": make_solid_mat("WS_PlasticDark", (0.10, 0.11, 0.125, 1.0), 0.45, 0.04),
        "plastic_grey": make_solid_mat("WS_PlasticGrey", (0.58, 0.60, 0.62, 1.0), 0.42, 0.05),
        "accent_red": make_solid_mat("WS_AccentRed", (0.76, 0.14, 0.12, 1.0), 0.36, 0.08),
        "accent_blue": make_solid_mat("WS_AccentBlue", (0.10, 0.38, 0.78, 1.0), 0.36, 0.08),
        "accent_amber": make_solid_mat("WS_AccentAmber", (0.88, 0.56, 0.08, 1.0), 0.36, 0.08),
        "safety_yellow": make_solid_mat("WS_SafetyYellow", (0.92, 0.72, 0.08, 1.0), 0.38, 0.10),
        "led_bar": make_solid_mat("WS_LedBar", (0.98, 0.99, 1.0, 1.0), 0.15, 0.0, emission=(0.95, 0.97, 1.0), em_strength=4.5),
        "led_green": make_solid_mat("WS_LedGreen", (0.12, 0.92, 0.36, 1.0), 0.2, 0.0, emission=(0.15, 0.95, 0.38), em_strength=2.8),
        "copper": make_solid_mat("WS_Copper", (0.78, 0.46, 0.24, 1.0), 0.28, 0.92),
        "tape": make_solid_mat("WS_PackingTape", (0.72, 0.62, 0.44, 1.0), 0.22, 0.02),
        "strap": make_solid_mat("WS_Strap", (0.08, 0.24, 0.52, 1.0), 0.48, 0.05),
        "paper": make_solid_mat("WS_ShippingLabel", (0.94, 0.94, 0.92, 1.0), 0.78, 0.0),
        "kit_stripe": make_solid_mat("WS_KitStripe", (0.20, 0.62, 0.95, 1.0), 0.30, 0.14),
        "pcb_green": make_solid_mat("WS_PcbGreen", (0.06, 0.32, 0.16, 1.0), 0.42, 0.12),
        "gold": make_solid_mat("WS_Gold", (0.92, 0.72, 0.20, 1.0), 0.22, 0.94),
        "foam": make_solid_mat("WS_FoamDark", (0.06, 0.065, 0.075, 1.0), 0.94, 0.0),
        "poly_glass": make_solid_mat("WS_ClearWindow", (0.12, 0.20, 0.28, 0.18), 0.06, 0.05),
    }


# ---------------------------------------------------------------------------
# 1. Industrielle IT-Werkbank (workshop_workbench.glb)
# ---------------------------------------------------------------------------

def build_workbench():
    clear_scene()
    M = build_materials()
    B = MeshBuilder("WorkshopWorkbench")

    W, D, H_TOP = 1.62, 0.84, 0.88
    LEG = 0.048
    # 4 schwere Vierkant-Stahlbeine + Gummifuesse
    for sx in (-W * 0.5 + 0.04, W * 0.5 - 0.04):
        for sy in (-D * 0.5 + 0.04, D * 0.5 - 0.04):
            B.box((sx, sy, (H_TOP - 0.04) * 0.5), (LEG, LEG, H_TOP - 0.04), M["anthracite"], bevel=0.003)
            B.cyl((sx, sy, 0.012), 0.028, 0.024, M["rubber"], seg=16)

    # Unterer Rahmen & Querstreben
    for sy in (-D * 0.5 + 0.04, D * 0.5 - 0.04):
        B.box((0.0, sy, 0.22), (W - 0.08, 0.036, 0.036), M["anthracite"], bevel=0.002)
        B.box((0.0, sy, H_TOP - 0.06), (W - 0.08, 0.038, 0.042), M["anthracite"], bevel=0.002)
    for sx in (-W * 0.5 + 0.04, W * 0.5 - 0.04):
        B.box((sx, 0.0, 0.22), (0.036, D - 0.08, 0.036), M["anthracite"], bevel=0.002)
        B.box((sx, 0.0, H_TOP - 0.06), (0.038, D - 0.08, 0.042), M["anthracite"], bevel=0.002)

    # Unterer Ablageboden (Z = 0.24..0.265) + 2 Industrie-Euroboxen links/rechts unten
    B.box((0.0, 0.0, 0.248), (W - 0.12, D - 0.12, 0.024), M["wood"], bevel=0.002)
    for bx, col_m in ((-0.46, M["accent_blue"]), (0.48, M["plastic_dark"])):
        B.box((bx, 0.02, 0.365), (0.42, 0.52, 0.21), col_m, bevel=0.004)
        B.box((bx, -0.242, 0.415), (0.14, 0.008, 0.035), M["paper"], bevel=0.001)

    # Arbeitsplatte (Z = 0.84..0.88) mit verzinkter Alu-Schutzkante vorne
    B.box((0.0, 0.0, H_TOP - 0.02), (W, D, 0.040), M["bench_top"], bevel=0.003)
    B.box((0.0, -D * 0.5 - 0.002, H_TOP - 0.02), (W, 0.008, 0.042), M["galv"], bevel=0.001)

    # Grosse 2K-ESD-Antistatikmatte rechts/mittig (freie Arbeitsflaeche fuer Kartons & Server-Chassis!)
    B.box((0.12, -0.04, H_TOP + 0.0022), (1.14, 0.64, 0.0044), M["esd"], bevel=0.0005, uv_mode="planar_top")
    # ESD-Erdungsdruckknopf vorne rechts + Spiralerdungskabel
    B.cyl((0.65, -0.32, H_TOP + 0.006), 0.009, 0.006, M["chrome"], seg=14)

    # Rueckwand-Pylone + Lochwand (Pegboard, Y = +0.39, Z = 0.88..1.72)
    for sx in (-W * 0.5 + 0.04, W * 0.5 - 0.04):
        B.box((sx, D * 0.5 - 0.035, 1.32), (0.044, 0.044, 0.90), M["anthracite"], bevel=0.002)
    B.box((0.0, D * 0.5 - 0.045, 1.30), (W - 0.10, 0.018, 0.76), M["pegboard"], bevel=0.002, uv_scale=0.65)
    # Obere & untere Werkzeugschiene
    B.box((0.0, D * 0.5 - 0.056, 1.66), (W - 0.12, 0.022, 0.028), M["galv"], bevel=0.001)
    B.box((0.0, D * 0.5 - 0.062, 0.98), (W - 0.14, 0.022, 0.026), M["galv"], bevel=0.001)

    # LED-Arbeitsleuchte ueber der Werkbank (Z = 1.76, nach vorne ragend)
    for sx in (-0.54, 0.54):
        B.box((sx, 0.14, 1.75), (0.024, 0.54, 0.024), M["anthracite"], bevel=0.002)
    B.box((0.0, -0.06, 1.74), (1.28, 0.095, 0.036), M["anthracite"], bevel=0.003)
    B.box((0.0, -0.06, 1.719), (1.22, 0.062, 0.008), M["led_bar"], bevel=0.0)

    # Werkzeuge an der Lochwand (Schraubendreher, Schluessel, Kleinteileboxen)
    for i, (tx, col_m) in enumerate(((-0.52, M["accent_red"]), (-0.43, M["accent_blue"]), (-0.34, M["accent_amber"]))):
        B.cyl((tx, D * 0.5 - 0.072, 1.46), 0.013, 0.105, col_m, seg=14)
        B.cyl((tx, D * 0.5 - 0.072, 1.34), 0.0032, 0.14, M["chrome"], seg=10)
    # 3 Gabelschluessel mittig-links
    for i, tx in enumerate((-0.14, -0.06, 0.02)):
        hlen = 0.15 + i * 0.028
        B.box((tx, D * 0.5 - 0.068, 1.40), (0.012, 0.005, hlen), M["chrome"], bevel=0.001)
        B.cyl((tx, D * 0.5 - 0.068, 1.40 + hlen * 0.5), 0.014, 0.006, M["chrome"], axis="y", seg=14)
        B.cyl((tx, D * 0.5 - 0.068, 1.40 - hlen * 0.5), 0.012, 0.006, M["chrome"], axis="y", seg=14)
    # 4 Sortimentskaesten fuer Schrauben/Clips rechts an der Lochwand
    for i, col_m in enumerate((M["accent_red"], M["accent_blue"], M["accent_amber"], M["accent_blue"])):
        bx = 0.24 + i * 0.145
        B.box((bx, D * 0.5 - 0.11, 1.04), (0.125, 0.11, 0.088), col_m, bevel=0.003)
        B.box((bx, D * 0.5 - 0.167, 1.05), (0.065, 0.004, 0.026), M["paper"], bevel=0.0)

    # Labor-Netzteil / Oszilloskop links hinten auf der Werkbank (X = -0.58, Y = +0.16)
    B.box((-0.58, 0.14, H_TOP + 0.095), (0.30, 0.24, 0.19), M["plastic_grey"], bevel=0.004)
    B.box((-0.58, 0.018, H_TOP + 0.122), (0.21, 0.008, 0.105), M["scope_scr"], bevel=0.0, uv_mode="planar_front")
    for kx in (-0.66, -0.59, -0.52):
        B.cyl((kx, 0.014, H_TOP + 0.042), 0.014, 0.016, M["plastic_dark"], axis="y", seg=16)
    B.cyl((-0.47, 0.014, H_TOP + 0.042), 0.008, 0.012, M["accent_red"], axis="y", seg=12)
    B.cyl((-0.445, 0.014, H_TOP + 0.042), 0.008, 0.012, M["plastic_dark"], axis="y", seg=12)
    B.cyl((-0.695, 0.016, H_TOP + 0.155), 0.005, 0.006, M["led_green"], axis="y", seg=10)

    # Digitale Loetstation links vorne (X = -0.62, Y = -0.18)
    B.box((-0.62, -0.18, H_TOP + 0.046), (0.16, 0.15, 0.092), M["accent_blue"], bevel=0.003)
    B.box((-0.62, -0.256, H_TOP + 0.060), (0.085, 0.006, 0.032), M["plastic_dark"], bevel=0.001)
    B.cyl((-0.51, -0.18, H_TOP + 0.016), 0.042, 0.032, M["anthracite"], seg=16)
    B.cyl((-0.51, -0.18, H_TOP + 0.075), 0.010, 0.12, M["chrome"], seg=12)

    # Magnet-Schraubenschale vorne rechts auf der ESD-Matte. Die Waermeleitpaste ist ein greifbares
    # Werkzeug (asm_tools.glb, Objekt "Syringe") und gehoert deshalb nicht zum Tischmodell.
    B.cyl((0.56, -0.22, H_TOP + 0.012), 0.048, 0.018, M["chrome"], seg=24)

    B.build_object()
    export_glb(os.path.join(OUT_MODELS_DIR, "workshop_workbench.glb"))


# ---------------------------------------------------------------------------
# 2. Funktionales Schwerlast-Lagerregal (workshop_storage_shelf.glb)
# ---------------------------------------------------------------------------

def build_storage_shelf():
    clear_scene()
    M = build_materials()
    B = MeshBuilder("WorkshopStorageShelf")

    W, D, H = 1.62, 0.58, 2.08
    POST = 0.042
    # 4 Schwerlast-Steckpfosten + gelbe Anfahrschutz-Ecken unten
    for sx in (-W * 0.5 + 0.025, W * 0.5 - 0.025):
        for sy in (-D * 0.5 + 0.025, D * 0.5 - 0.025):
            B.box((sx, sy, H * 0.5), (POST, POST, H), M["anthracite"], bevel=0.002)
            B.box((sx, sy, 0.014), (0.056, 0.056, 0.028), M["rubber"], bevel=0.002)
            if sy < 0:
                B.box((sx, sy - 0.008, 0.10), (0.048, 0.014, 0.14), M["safety_yellow"], bevel=0.002)

    # 4 Ebenen (exakte Oberkanten Z = 0.18, 0.68, 1.18, 1.68) + oberer Abschlussrahmen Z = 2.04
    shelf_tops = [0.18, 0.68, 1.18, 1.68]
    for zt in shelf_tops:
        # Verzinkter Einlegeboden
        B.box((0.0, 0.0, zt - 0.014), (W - 0.05, D - 0.04, 0.028), M["galv"], bevel=0.002)
        # Vordere & hintere Schwerlast-Traverse in Anthrazit
        B.box((0.0, -D * 0.5 + 0.022, zt - 0.026), (W - 0.02, 0.024, 0.044), M["anthracite"], bevel=0.002)
        B.box((0.0, D * 0.5 - 0.022, zt - 0.026), (W - 0.02, 0.024, 0.044), M["anthracite"], bevel=0.002)
        # Etiketten-Leiste vorne (3 dezente Stellplatz-Markierungen je Ebene)
        for slot_x in (-0.50, 0.0, 0.50):
            B.box((slot_x, -D * 0.5 + 0.008, zt - 0.026), (0.24, 0.006, 0.024), M["plastic_dark"], bevel=0.001)
            B.box((slot_x, -D * 0.5 + 0.005, zt - 0.026), (0.21, 0.003, 0.016), M["paper"], bevel=0.0)
        # Seiten-Traversen
        for sx in (-W * 0.5 + 0.025, W * 0.5 - 0.025):
            B.box((sx, 0.0, zt - 0.026), (0.024, D - 0.06, 0.036), M["anthracite"], bevel=0.001)

    # Oberer Dachrahmen + Traglast-Plakette vorne
    B.box((0.0, -D * 0.5 + 0.022, H - 0.03), (W - 0.02, 0.030, 0.056), M["anthracite"], bevel=0.002)
    B.box((0.0, D * 0.5 - 0.022, H - 0.03), (W - 0.02, 0.030, 0.056), M["anthracite"], bevel=0.002)
    B.box((0.0, 0.0, H - 0.018), (W - 0.06, D - 0.05, 0.016), M["galv"], bevel=0.001)
    B.box((0.0, -D * 0.5 + 0.005, H - 0.03), (0.34, 0.006, 0.064), M["plaque"], bevel=0.0, uv_mode="planar_front")

    # Seitliche & hintere Diagonalstreben (Industrie-Look)
    for sx in (-W * 0.5 + 0.025, W * 0.5 - 0.025):
        B.box((sx, 0.0, 1.08), (0.010, 0.018, 1.88), M["galv"], rot_deg=(16.0, 0.0, 0.0), bevel=0.0)
        B.box((sx, 0.0, 1.08), (0.010, 0.018, 1.88), M["galv"], rot_deg=(-16.0, 0.0, 0.0), bevel=0.0)
    B.box((0.0, D * 0.5 - 0.018, 1.08), (0.018, 0.010, 2.18), M["galv"], rot_deg=(0.0, 34.0, 0.0), bevel=0.0)
    B.box((0.0, D * 0.5 - 0.018, 1.08), (0.018, 0.010, 2.18), M["galv"], rot_deg=(0.0, -34.0, 0.0), bevel=0.0)

    B.build_object()
    export_glb(os.path.join(OUT_MODELS_DIR, "workshop_storage_shelf.glb"))


# ---------------------------------------------------------------------------
# 3. AAA Pro-Reparatur-Kit-Koffer (repair_kit_case.glb — Pelican/iFixit-Style)
# ---------------------------------------------------------------------------

def build_repair_kit_case():
    clear_scene()
    M = build_materials()
    # Kristallklares getoentes Sichtfenster (niedrige Alpha, keine milchige Reflexion)
    M["poly_glass"].blend_method = "BLEND"
    bsdf_pg = M["poly_glass"].node_tree.nodes.get("Principled BSDF")
    if bsdf_pg is not None:
        bsdf_pg.inputs["Alpha"].default_value = 0.16
        bsdf_pg.inputs["Roughness"].default_value = 0.06
        if "Specular IOR Level" in bsdf_pg.inputs:
            bsdf_pg.inputs["Specular IOR Level"].default_value = 0.25

    B = MeshBuilder("RepairKitCase")

    W, D, H = 0.34, 0.24, 0.122
    # 1. Unterwanne (robuste Hartschale, Z = 0.008 .. 0.074) + Bodenfueße
    B.box((0.0, 0.0, 0.041), (W, D, 0.066), M["plastic_dark"], bevel=0.006)
    for fx in (-W * 0.40, W * 0.40):
        for fy in (-D * 0.38, D * 0.38):
            B.box((fx, fy, 0.005), (0.042, 0.036, 0.010), M["rubber"], bevel=0.002)

    # 2. Farbcodierte umlaufende Dichtungs- & Kategorie-Banderole (leuchtet je Kit-Typ!)
    B.box((0.0, 0.0, 0.077), (W + 0.008, D + 0.008, 0.014), M["kit_stripe"], bevel=0.002)

    # 3. Oberdeckel-Rahmen mit eingelassener Mulde fuer Sichtfenster & Werkzeug-Innenleben!
    # Aeusserer Deckelrahmen rund um die Werkzeug-Kammer (X = -0.115..+0.115, Y = -0.055..+0.085)
    B.box((0.0, 0.095, 0.102), (W, 0.052, 0.038), M["anthracite"], bevel=0.005)      # hinten
    B.box((0.0, -0.092, 0.102), (W, 0.058, 0.038), M["anthracite"], bevel=0.005)     # vorne
    B.box((-0.140, 0.002, 0.102), (0.062, 0.140, 0.038), M["anthracite"], bevel=0.004) # links
    B.box((0.140, 0.002, 0.102), (0.062, 0.140, 0.038), M["anthracite"], bevel=0.004)  # rechts
    # Dunkler ESD-Schaumstoff-Boden in der sichtbaren Innenmulde
    B.box((0.0, 0.005, 0.088), (0.228, 0.138, 0.008), M["foam"], bevel=0.001)

    # 4. Miniatur-Innenleben im Koffer (durchs klare Sichtfenster direkt erkennbar!):
    # 4a) Praezisions-ESD-Schraubendreher (farbcodierter Griff + Chrom-Klinge)
    B.cyl((-0.048, 0.042, 0.100), 0.0085, 0.072, M["kit_stripe"], axis="x", seg=14)
    B.cyl((0.022, 0.042, 0.100), 0.0028, 0.072, M["chrome"], axis="x", seg=10)
    B.cyl((-0.084, 0.042, 0.100), 0.0095, 0.008, M["rubber"], axis="x", seg=12)
    # 4b) Waermeleitpaste-Spritze / Ersatzkartusche
    B.cyl((-0.035, 0.006, 0.099), 0.0065, 0.064, M["plastic_grey"], axis="x", seg=12)
    B.cyl((0.012, 0.006, 0.099), 0.0025, 0.030, M["anthracite"], axis="x", seg=10)
    B.cyl((-0.074, 0.006, 0.099), 0.0035, 0.022, M["accent_amber"], axis="x", seg=10)
    # 4c) Gruene Ersatz-Platine / Hardware-Modul mit Goldkontakten & IC-Chip
    B.box((0.058, -0.028, 0.096), (0.078, 0.044, 0.006), M["pcb_green"], bevel=0.001)
    B.box((0.058, -0.048, 0.097), (0.064, 0.007, 0.007), M["gold"], bevel=0.0)
    B.box((0.045, -0.024, 0.101), (0.022, 0.022, 0.006), M["plastic_dark"], bevel=0.001)
    B.box((0.078, -0.024, 0.100), (0.016, 0.016, 0.005), M["chrome"], bevel=0.001)
    # 4d) 4 kleine Messing-/Stahl-Precision-Bits + ESD-Pinzette links unten
    for bi in range(4):
        B.cyl((-0.088 + bi * 0.018, -0.032, 0.098), 0.0038, 0.026, M["gold"] if bi % 2 == 0 else M["chrome"], axis="y", seg=10)

    # 5. Kristallklares Schutzfenster (hauchduenn) + farbcodierte Deckelrippen
    B.box((0.0, 0.005, 0.119), (0.220, 0.130, 0.002), M["poly_glass"], bevel=0.0)
    # 10. Saubere Typenschilder: Frontleiste + kleines Schild vorne oben (verdeckt das Sichtfenster NICHT!)
    B.box((0.0, -0.095, 0.123), (0.170, 0.030, 0.003), M["paper"], bevel=0.0005)
    B.box((0.0, -D * 0.5 - 0.002, 0.098), (0.145, 0.003, 0.026), M["anthracite"], bevel=0.001)
    # Seitliche Schutzrippen auf dem Deckel (Pelican-Look) + Kategorie-Farb-Akzente
    for sx in (-0.140, 0.140):
        B.box((sx, 0.002, 0.123), (0.036, 0.136, 0.006), M["kit_stripe"], bevel=0.002)
        for ry in (-0.045, 0.0, 0.045):
            B.box((sx, ry, 0.125), (0.044, 0.012, 0.006), M["rubber"], bevel=0.001)

    # 6. 4 wuchtige Gummi-Eck-Bumper (Schlagschutz oben & unten an allen 4 Ecken!)
    for cx in (-W * 0.5 + 0.010, W * 0.5 - 0.010):
        for cy in (-D * 0.5 + 0.010, D * 0.5 - 0.010):
            B.box((cx, cy, H * 0.52), (0.036, 0.036, H + 0.008), M["rubber"], bevel=0.005)
            # Kleine Chrom-Niete an jeder Ecke
            B.cyl((cx, cy, H + 0.006), 0.0045, 0.004, M["chrome"], seg=10)

    # 7. Zwei massive Edelstahl-Klappverschluesse vorne (-Y) + Druckausgleichsventil
    for lx in (-0.102, 0.102):
        B.box((lx, -D * 0.5 - 0.008, 0.068), (0.036, 0.016, 0.056), M["chrome"], bevel=0.003)
        B.box((lx, -D * 0.5 - 0.016, 0.068), (0.024, 0.008, 0.024), M["kit_stripe"], bevel=0.002)
        B.cyl((lx, -D * 0.5 - 0.008, 0.095), 0.004, 0.040, M["anthracite"], axis="x", seg=10)
    # Druckventil vorne rechts neben dem Griff
    B.cyl((0.062, -D * 0.5 - 0.004, 0.034), 0.009, 0.010, M["chrome"], axis="y", seg=14)

    # 8. Ergonomischer Soft-Grip-Tragegriff vorne (-Y)
    for hx in (-0.056, 0.056):
        B.box((hx, -D * 0.5 - 0.018, 0.056), (0.016, 0.036, 0.022), M["anthracite"], bevel=0.003)
    B.box((0.0, -D * 0.5 - 0.036, 0.056), (0.128, 0.018, 0.024), M["rubber"], bevel=0.005)
    B.box((0.0, -D * 0.5 - 0.044, 0.056), (0.088, 0.005, 0.012), M["kit_stripe"], bevel=0.001)

    # 9. Zwei robuste Rueckwand-Scharniere (+Y)
    for bx in (-0.095, 0.095):
        B.cyl((bx, D * 0.5 + 0.005, 0.078), 0.008, 0.044, M["chrome"], axis="x", seg=12)

    B.build_object()
    export_glb(os.path.join(OUT_MODELS_DIR, "repair_kit_case.glb"))


# ---------------------------------------------------------------------------
# 3b. Mengen-Kiste / Multi-Pack Logistics Crate (bulk_pack_crate.glb, bis 6x)
# ---------------------------------------------------------------------------

def build_bulk_pack_crate():
    clear_scene()
    M = build_materials()
    B = MeshBuilder("BulkPackCrate")

    W, D, H = 0.42, 0.34, 0.245
    # 1. Schwerlast-Eurobox-Korpus (gerippter Industrie-Behaelter)
    B.box((0.0, 0.0, H * 0.46), (W, D, H * 0.92), M["anthracite"], bevel=0.006)
    # Oberer verstaerkter Stapelrand + zweiteiliger Klappdeckel
    B.box((0.0, 0.0, H - 0.014), (W + 0.016, D + 0.016, 0.028), M["plastic_dark"], bevel=0.004)
    # 2 ineinandergreifende Deckelklappen-Fuge + 6 Fach-Praegungen oben (Symbol fuer 6er-Pack!)
    B.box((0.0, 0.0, H + 0.001), (W - 0.02, 0.006, 0.004), M["rubber"], bevel=0.0)
    for gx in (-0.12, 0.0, 0.12):
        for gy in (-0.08, 0.08):
            B.box((gx, gy, H + 0.002), (0.095, 0.065, 0.005), M["anthracite"], bevel=0.002)

    # 2. Breite farbcodierte Kategorie-Banderole rundum (zeigt sofort den Inhalt: RAM/CPU/GPU/etc.!)
    B.box((0.0, 0.0, H * 0.66), (W + 0.010, D + 0.010, 0.044), M["kit_stripe"], bevel=0.002)

    # 3. Vertikale Verstaerkungsrippen an Front/Heck/Seiten (Industrie-Kisten-Look)
    for rx in (-0.16, -0.08, 0.08, 0.16):
        B.box((rx, -D * 0.5 - 0.004, H * 0.42), (0.014, 0.008, H * 0.72), M["plastic_dark"], bevel=0.002)
        B.box((rx, D * 0.5 + 0.004, H * 0.42), (0.014, 0.008, H * 0.72), M["plastic_dark"], bevel=0.002)
    for ry in (-0.10, 0.0, 0.10):
        B.box((-W * 0.5 - 0.004, ry, H * 0.42), (0.008, 0.016, H * 0.72), M["plastic_dark"], bevel=0.002)
        B.box((W * 0.5 + 0.004, ry, H * 0.42), (0.008, 0.016, H * 0.72), M["plastic_dark"], bevel=0.002)

    # 4. 4 Chrom-Eckbeschlaege & seitliche Tragegriffe
    for sx in (-W * 0.5 - 0.006, W * 0.5 + 0.006):
        B.box((sx, 0.0, H * 0.78), (0.016, 0.125, 0.022), M["rubber"], bevel=0.003)
    for cx in (-W * 0.5 + 0.008, W * 0.5 - 0.008):
        for cy in (-D * 0.5 + 0.008, D * 0.5 - 0.008):
            B.box((cx, cy, 0.020), (0.036, 0.036, 0.040), M["galv"], bevel=0.003)

    # 5. Zwei straffe Spannbaender ueber den Deckel + Metall-Schnallen
    for sx in (-0.115, 0.115):
        B.box((sx, 0.0, H * 0.50), (0.018, D + 0.022, H + 0.012), M["safety_yellow"], bevel=0.001)
        B.box((sx, -D * 0.5 - 0.012, H * 0.86), (0.026, 0.012, 0.028), M["chrome"], bevel=0.002)

    # 6. Grosse weisse Versand- & Mengen-Etiketten vorne (-Y -> Godot +Z) und oben (+Z -> Godot +Y)
    B.box((0.0, -D * 0.5 - 0.006, 0.140), (0.24, 0.004, 0.095), M["paper"], bevel=0.001)
    B.box((0.0, 0.01, H + 0.005), (0.24, 0.115, 0.003), M["paper"], bevel=0.001)

    B.build_object()
    export_glb(os.path.join(OUT_MODELS_DIR, "bulk_pack_crate.glb"))


# ---------------------------------------------------------------------------
# 4. Beschrifteter Versandkarton (delivery_build_box.glb)
# ---------------------------------------------------------------------------

def build_delivery_box():
    clear_scene()
    M = build_materials()
    B = MeshBuilder("DeliveryBuildBox")

    W, D, H = 0.46, 0.40, 0.22
    B.box((0.0, 0.0, H * 0.5), (W, D, H), M["cardboard"], bevel=0.004, uv_scale=0.45)
    # Paketband mittig ueber die Deckelklappen
    B.box((0.0, 0.0, H + 0.0012), (W + 0.003, 0.052, 0.002), M["tape"], bevel=0.0)
    B.box((-W * 0.5 - 0.001, 0.0, H - 0.03), (0.002, 0.052, 0.06), M["tape"], bevel=0.0)
    B.box((W * 0.5 + 0.001, 0.0, H - 0.03), (0.002, 0.052, 0.06), M["tape"], bevel=0.0)
    # 2 blaue Industrie-Umreifungsbaender
    for sx in (-0.13, 0.13):
        B.box((sx, 0.0, H * 0.5), (0.014, D + 0.005, H + 0.005), M["strap"], bevel=0.0)
    # Grosses weisses Versandetikett vorne (-Y) und oben (+Z) fuer "Rack 1 · Slot 1"
    B.box((0.0, -D * 0.5 - 0.002, H * 0.54), (0.24, 0.002, 0.115), M["paper"], bevel=0.0)
    B.box((0.0, -0.06, H + 0.0022), (0.22, 0.12, 0.002), M["paper"], bevel=0.0)

    B.build_object()
    export_glb(os.path.join(OUT_MODELS_DIR, "delivery_build_box.glb"))


def main():
    build_workbench()
    build_storage_shelf()
    build_repair_kit_case()
    build_bulk_pack_crate()
    build_delivery_box()
    print("WORKSHOP MODELS DONE!")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
