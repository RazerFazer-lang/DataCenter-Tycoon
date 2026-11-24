"""Blender 5.2 Generator fuer den realistischen 2K-PBR CLOUD-EXPRESS Lieferwagen (Sprinter-Klasse).
Exportiert nach assets/models/delivery_van.glb.

Godot-Koordinaten (g(x, y, z) -> Blender (x, -z, y)):
    +X = Vorne (Fahrtrichtung), -X = Hinten
    +Y = Oben (Boden Y = 0.0)
    -Z = Links (Garage / Schiebetuer / Fahrertuer), +Z = Rechts (Strasse)

Bekannte benannte Knoten fuer delivery_van.gd:
    Wheel_FL, Wheel_FR, Wheel_RL, Wheel_RR   (rotieren um Z)
    Side_Door                                (Schiebetuer bei (-0.08, 1.30, -1.04))
    Cab_Door_L                               (Fahrertuer-Scharnier bei (2.06, 1.05, -0.99))
    Materialien: Van_BeaconMat, Van_HazardMat, Van_BrakeMat
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

OUT_GLB = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models", "delivery_van.glb"))
CACHE_DIR = os.path.join(SCRIPT_DIR, "_pbr_cache")


def g(x: float, y: float, z: float) -> Vector:
    return Vector((x, -z, y))


def _save_rgb(path: str, arr_01: np.ndarray) -> None:
    pbr_textures.save_png(path, np.clip(arr_01 * 255.0, 0.0, 255.0).astype(np.uint8))


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


def make_solid_mat(name: str, rgba, rough: float = 0.35, metal: float = 0.0,
                   coat: float = 0.0, alpha: float = 1.0, emission=None, em_strength: float = 0.0):
    mat, _nt, bsdf = _new_mat(name)
    bsdf.inputs["Base Color"].default_value = (rgba[0], rgba[1], rgba[2], alpha)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.08
    if alpha < 1.0:
        bsdf.inputs["Alpha"].default_value = alpha
        mat.blend_method = "BLEND"
    if emission is not None and em_strength > 0.0:
        bsdf.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = em_strength
    return mat


def make_tex_mat(name: str, img_path: str, rough: float = 0.25, metal: float = 0.12, coat: float = 0.5, em_strength: float = 0.0):
    mat, nt, bsdf = _new_mat(name)
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = _load_img(img_path, "sRGB")
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.08
    if em_strength > 0.0:
        nt.links.new(t.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = em_strength
    return mat


# ---------------------------------------------------------------------------
# 2K Livery-, Kennzeichen-, Armaturenbrett- & Laderaum-Texturen
# ---------------------------------------------------------------------------

def _gen_livery_side(cache_dir: str) -> str:
    p = os.path.join(cache_dir, "van_livery_side.png")
    w, h = 1024, 512
    img = np.zeros((h, w, 3), dtype=np.float32)
    img[:, :] = np.array([0.93, 0.94, 0.96], dtype=np.float32)
    # Dynamische schraege Flottenstreifen (Royalblau + Cyan + Bernstein)
    yy, xx = np.mgrid[0:h, 0:w]
    diag = xx * 0.35 + yy
    blue_band = (diag > 420) & (diag < 540)
    cyan_band = (diag >= 540) & (diag < 568)
    amber_band = (diag >= 568) & (diag < 582)
    img[blue_band] = np.array([0.07, 0.25, 0.56], dtype=np.float32)
    img[cyan_band] = np.array([0.12, 0.68, 0.92], dtype=np.float32)
    img[amber_band] = np.array([0.95, 0.66, 0.10], dtype=np.float32)
    # Unterer anthrazitfarbener Schwellerbereich
    img[430:, :] = np.array([0.14, 0.15, 0.17], dtype=np.float32)
    # Typografie: CLOUD EXPRESS
    pbr_textures.fill_rect(img, 96, 130, 660, 224, (0.06, 0.22, 0.50))
    pbr_textures.fill_rect(img, 96, 224, 660, 234, (0.14, 0.72, 0.96))
    pbr_textures.draw_text(img, 122, 152, "CLOUD EXPRESS", (0.97, 0.98, 1.0), scale=5)
    pbr_textures.draw_text(img, 126, 252, "IT HARDWARE LOGISTICS  24/7", (0.10, 0.22, 0.42), scale=3)
    # Feine vertikale Karosseriefugen
    for sx in (320, 680):
        img[20:430, sx:sx + 2] *= 0.76
    _save_rgb(p, img)
    return p


def _gen_eu_plate(cache_dir: str) -> str:
    p = os.path.join(cache_dir, "van_eu_plate.png")
    w, h = 512, 128
    img = np.ones((h, w, 3), dtype=np.float32) * 0.96
    pbr_textures.stroke_rect(img, 2, 2, w - 3, h - 3, (0.06, 0.06, 0.07), thickness=5)
    pbr_textures.fill_rect(img, 7, 7, 68, h - 8, (0.06, 0.22, 0.66))
    pbr_textures.draw_text(img, 26, 74, "D", (0.98, 0.98, 0.98), scale=4)
    pbr_textures.draw_text(img, 92, 36, "DC  EX 404", (0.05, 0.05, 0.06), scale=6)
    _save_rgb(p, img)
    return p


def _gen_dash_tex(cache_dir: str) -> str:
    p = os.path.join(cache_dir, "van_dash_cluster.png")
    w, h = 512, 160
    img = np.zeros((h, w, 3), dtype=np.float32)
    img[:, :] = np.array([0.04, 0.05, 0.07], dtype=np.float32)
    pbr_textures.draw_circle(img, 110, 82, 52, (0.14, 0.76, 0.98), inner_r=46)
    pbr_textures.draw_circle(img, 402, 82, 52, (0.14, 0.76, 0.98), inner_r=46)
    pbr_textures.fill_rect(img, 194, 34, 318, 126, (0.06, 0.14, 0.22))
    pbr_textures.draw_text(img, 212, 50, "CLOUD NAV", (0.28, 0.88, 0.98), scale=2)
    pbr_textures.draw_text(img, 214, 86, "ROUTE OK", (0.24, 0.92, 0.44), scale=2)
    _save_rgb(p, img)
    return p


# ---------------------------------------------------------------------------
# Geometrie-Helfer in Godot-Koordinaten
# ---------------------------------------------------------------------------

class PartBuilder:
    def __init__(self, name: str, origin_g: Vector = Vector((0, 0, 0))):
        self.name = name
        self.origin_g = origin_g
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []
        self.mat_map = {}

    def _mid(self, mat) -> int:
        if mat.name not in self.mat_map:
            self.mat_map[mat.name] = len(self.mats)
            self.mats.append(mat)
        return self.mat_map[mat.name]

    def _local_b(self, p_g: Vector) -> Vector:
        d = p_g - self.origin_g
        return g(d.x, d.y, d.z)

    def _uv_box(self, faces, scale: float = 1.0, uv_mode: str = "box",
                center_b: Vector = Vector((0, 0, 0)), size_b: Vector = Vector((1, 1, 1))):
        for f in faces:
            n = f.normal
            ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
            for l in f.loops:
                co = l.vert.co
                if uv_mode == "side_x":
                    u = (co.x - center_b.x) / max(size_b.x, 1e-4) + 0.5
                    if n.y > 0.5:
                        u = 1.0 - u
                    v = (co.z - center_b.z) / max(size_b.z, 1e-4) + 0.5
                elif uv_mode == "front_y":
                    u = (co.y - center_b.y) / max(size_b.y, 1e-4) + 0.5
                    v = (co.z - center_b.z) / max(size_b.z, 1e-4) + 0.5
                else:
                    if az >= ax and az >= ay:
                        u, v = co.x / scale, co.y / scale
                    elif ay >= ax:
                        u, v = co.x / scale, co.z / scale
                    else:
                        u, v = co.y / scale, co.z / scale
                l[self.uv].uv = (u, v)

    def box(self, center_g, size_g, mat, rot_g_deg=(0.0, 0.0, 0.0), bevel: float = 0.012,
            uv_scale: float = 1.0, uv_mode: str = "box"):
        mid = self._mid(mat)
        sx, sy, sz = size_g[0], size_g[2], size_g[1] # Blender X, Y, Z
        ret = bmesh.ops.create_cube(self.bm, size=1.0)
        verts = ret["verts"]
        for v in verts:
            v.co.x *= sx
            v.co.y *= sy
            v.co.z *= sz
        if bevel > 0.0 and min(sx, sy, sz) > bevel * 2.8:
            edges = list({e for v in verts for e in v.link_edges})
            res = bmesh.ops.bevel(self.bm, geom=edges, offset=bevel, segments=2, affect="EDGES", clamp_overlap=True)
            verts = [v for v in ({v for v in verts} | {v for v in res.get("verts", [])}) if v.is_valid]
        # Godot Euler -> Blender Euler
        rx, ry, rz = rot_g_deg
        rot_m = Euler((math.radians(rx), math.radians(-rz), math.radians(ry)), "XYZ").to_matrix().to_4x4()
        cb = self._local_b(Vector(center_g))
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(cb) @ rot_m, verts=verts)
        faces = list({f for v in verts for f in v.link_faces})
        for f in faces:
            f.material_index = mid
            f.smooth = bevel >= 0.018
        self.bm.normal_update()
        self._uv_box(faces, uv_scale, uv_mode, cb, Vector((sx, sy, sz)))

    def cyl(self, center_g, r1: float, r2: float, depth: float, mat, axis_g: str = "z", seg: int = 28):
        mid = self._mid(mat)
        ret = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=seg,
            radius1=r1, radius2=r2, depth=depth
        )
        verts = ret["verts"]
        if axis_g == "x":
            rot_m = Euler((0.0, math.radians(90.0), 0.0), "XYZ").to_matrix().to_4x4()
        elif axis_g == "z":
            rot_m = Euler((math.radians(90.0), 0.0, 0.0), "XYZ").to_matrix().to_4x4()
        else:
            rot_m = Matrix.Identity(4)
        cb = self._local_b(Vector(center_g))
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(cb) @ rot_m, verts=verts)
        faces = list({f for v in verts for f in v.link_faces})
        for f in faces:
            f.material_index = mid
            f.smooth = True
        self.bm.normal_update()
        self._uv_box(faces, 0.5)

    def loft_x(self, stations: list, mat, cap_ends: bool = True, smooth: bool = True):
        """Erzeugt eine sauber geschwungene Sprinter-Karosserieform entlang der Godot-X-Achse.
        stations: Liste von (x_g, [(y_g, z_g), ...]) mit gleicher Punktzahl im Querschnitt.
        """
        mid = self._mid(mat)
        rings = []
        for xg, pts in stations:
            ring = [self.bm.verts.new(self._local_b(Vector((xg, yg, zg)))) for (yg, zg) in pts]
            rings.append(ring)
        n = len(rings[0])
        new_faces = []
        for s in range(len(rings) - 1):
            r0, r1 = rings[s], rings[s + 1]
            for i in range(n):
                j = (i + 1) % n
                try:
                    f = self.bm.faces.new((r0[i], r0[j], r1[j], r1[i]))
                    f.material_index = mid
                    f.smooth = smooth
                    new_faces.append(f)
                except ValueError:
                    pass
        if cap_ends:
            for ring, rev in ((rings[0], True), (rings[-1], False)):
                try:
                    f = self.bm.faces.new(list(reversed(ring)) if rev else ring)
                    f.material_index = mid
                    f.smooth = False
                    new_faces.append(f)
                except ValueError:
                    pass
        bmesh.ops.recalc_face_normals(self.bm, faces=new_faces)
        self.bm.normal_update()
        self._uv_box(new_faces, 1.2)

    def build(self, parent=None):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        obj.location = g(self.origin_g.x, self.origin_g.y, self.origin_g.z)
        bpy.context.scene.collection.objects.link(obj)
        if parent is not None:
            obj.parent = parent
        return obj


def _rounded_profile(y_bot: float, y_top: float, half_w_bot: float, half_w_mid: float, half_w_top: float, y_mid: float):
    """8-Punkt-Querschnitt mit leicht gewoelbten Seitenwaenden & gerundeter Dachkante (Sprinter-Silhouette)."""
    return [
        (y_bot, -half_w_bot),
        (y_mid, -half_w_mid),
        (y_top - 0.10, -half_w_mid * 0.96),
        (y_top, -half_w_top),
        (y_top, half_w_top),
        (y_top - 0.10, half_w_mid * 0.96),
        (y_mid, half_w_mid),
        (y_bot, half_w_bot),
    ]


def build_wheel(name: str, center_g: Vector, M: dict, is_left: bool):
    W = PartBuilder(name, origin_g=center_g)
    # Reifen-Aussenmantel (R = 0.40, Breite = 0.25) mit abgerundeten Schultern
    W.cyl(center_g, 0.40, 0.40, 0.21, M["tire"], axis_g="z", seg=32)
    W.cyl(center_g + Vector((0, 0, -0.115)), 0.37, 0.40, 0.03, M["tire"], axis_g="z", seg=32)
    W.cyl(center_g + Vector((0, 0, 0.115)), 0.40, 0.37, 0.03, M["tire"], axis_g="z", seg=32)
    # 5-Speichen-Alufelge + Bremsscheibe (sauber aussen sichtbar!)
    side = -1.0 if is_left else 1.0
    W.cyl(center_g + Vector((0, 0, side * 0.118)), 0.265, 0.265, 0.036, M["alloy"], axis_g="z", seg=28)
    W.cyl(center_g + Vector((0, 0, side * 0.128)), 0.220, 0.220, 0.024, M["dark_metal"], axis_g="z", seg=24)
    W.cyl(center_g + Vector((0, 0, side * 0.138)), 0.072, 0.072, 0.024, M["alloy"], axis_g="z", seg=20)
    # 5 Speichen sternfoermig aussen auf der Felge
    for k in range(5):
        ang = math.radians(k * 72.0)
        sx = math.cos(ang) * 0.145
        sy = math.sin(ang) * 0.145
        W.box(center_g + Vector((sx, sy, side * 0.136)), (0.165, 0.044, 0.018), M["alloy"],
              rot_g_deg=(0.0, 0.0, k * 72.0), bevel=0.003)
    return W.build()


def build_van():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    os.makedirs(CACHE_DIR, exist_ok=True)

    M = {
        "paint": make_solid_mat("Van_WhitePaint", (0.94, 0.95, 0.97), rough=0.20, metal=0.14, coat=0.75),
        "livery": make_tex_mat("Van_Livery", _gen_livery_side(CACHE_DIR), rough=0.22, metal=0.12, coat=0.65),
        "plate": make_tex_mat("Van_Plate", _gen_eu_plate(CACHE_DIR), rough=0.28, metal=0.18, coat=0.2),
        "dash": make_tex_mat("Van_Dash", _gen_dash_tex(CACHE_DIR), rough=0.25, metal=0.0, coat=0.1, em_strength=1.4),
        "cladding": make_solid_mat("Van_Cladding", (0.11, 0.12, 0.135), rough=0.68, metal=0.04),
        "bumper": make_solid_mat("Van_Bumper", (0.09, 0.095, 0.11), rough=0.58, metal=0.06),
        "grille": make_solid_mat("Van_Grille", (0.045, 0.048, 0.055), rough=0.52, metal=0.22),
        "chrome": make_solid_mat("Van_Chrome", (0.86, 0.89, 0.92), rough=0.10, metal=0.98),
        "alloy": make_solid_mat("Van_Alloy", (0.76, 0.79, 0.83), rough=0.22, metal=0.92),
        "dark_metal": make_solid_mat("Van_DarkMetal", (0.16, 0.17, 0.19), rough=0.45, metal=0.80),
        "tire": make_solid_mat("Van_Tire", (0.055, 0.058, 0.064), rough=0.88, metal=0.02),
        "glass": make_solid_mat("Van_Glass", (0.12, 0.22, 0.30), rough=0.06, metal=0.10, coat=0.8, alpha=0.42),
        "interior": make_solid_mat("Van_Interior", (0.14, 0.15, 0.17), rough=0.78, metal=0.02),
        "seat": make_solid_mat("Van_Seat", (0.18, 0.20, 0.24), rough=0.84, metal=0.0),
        "plywood": make_solid_mat("Van_Plywood", (0.68, 0.56, 0.39), rough=0.74, metal=0.0),
        "headlight": make_solid_mat("Van_Headlight", (0.98, 0.98, 1.0), rough=0.08, metal=0.1, emission=(0.96, 0.98, 1.0), em_strength=3.2),
        "beacon": make_solid_mat("Van_BeaconMat", (0.98, 0.62, 0.06), rough=0.15, metal=0.0, emission=(1.0, 0.56, 0.05), em_strength=2.4),
        "hazard": make_solid_mat("Van_HazardMat", (0.98, 0.56, 0.06), rough=0.20, metal=0.0, emission=(1.0, 0.52, 0.04), em_strength=1.8),
        "brake": make_solid_mat("Van_BrakeMat", (0.85, 0.06, 0.06), rough=0.18, metal=0.0, emission=(0.95, 0.08, 0.06), em_strength=1.6),
        "blue_acc": make_solid_mat("Van_BlueAcc", (0.07, 0.26, 0.58), rough=0.24, metal=0.14, coat=0.6),
    }

    B = PartBuilder("Van_Body")

    # 1. Geschwungene Sprinter-Motorhaube & Frontpartie (X = 1.96 .. 2.86)
    hood_stations = [
        (1.96, _rounded_profile(0.42, 1.48, 0.95, 0.98, 0.88, 0.96)),
        (2.34, _rounded_profile(0.42, 1.38, 0.94, 0.96, 0.84, 0.92)),
        (2.74, _rounded_profile(0.44, 1.24, 0.88, 0.91, 0.78, 0.86)),
        (2.86, _rounded_profile(0.50, 1.12, 0.80, 0.84, 0.72, 0.82)),
    ]
    B.loft_x(hood_stations, M["paint"], cap_ends=True, smooth=True)

    # 2. Aerodynamische Fahrerkabine Dach & A-Saeulen (X = 1.00 .. 2.02)
    cab_roof = [
        (0.95, _rounded_profile(2.14, 2.52, 0.97, 0.97, 0.82, 2.34)),
        (1.52, _rounded_profile(2.12, 2.46, 0.95, 0.95, 0.79, 2.30)),
        (1.98, _rounded_profile(2.06, 2.30, 0.88, 0.88, 0.75, 2.18)),
    ]
    B.loft_x(cab_roof, M["paint"], cap_ends=True, smooth=True)

    # A-Saeulen & B-Saeulen links/rechts + Dachstrebe
    for sz in (-0.91, 0.91):
        B.box((1.98, 1.78, sz), (0.09, 0.80, 0.08), M["paint"], rot_g_deg=(0.0, 0.0, 26.0), bevel=0.014)
        B.box((1.00, 1.70, sz * 1.04), (0.14, 1.02, 0.08), M["paint"], bevel=0.012)

    # Schraeg stehende Panorama-Windschutzscheibe (transparentes Glas!)
    B.box((1.96, 1.79, 0.0), (0.025, 0.78, 1.74), M["glass"], rot_g_deg=(0.0, 0.0, 26.0), bevel=0.004)
    # Scheibenwischer
    for wz in (-0.36, 0.30):
        B.box((2.12, 1.44, wz), (0.018, 0.022, 0.56), M["bumper"], rot_g_deg=(0.0, 8.0, 22.0), bevel=0.002)

    # Rechte Kabinentuer (+Z fest geschlossen mit Fenster)
    B.box((1.52, 0.92, 0.97), (1.02, 0.96, 0.07), M["paint"], bevel=0.015)
    B.box((1.52, 1.72, 0.95), (0.90, 0.68, 0.025), M["glass"], bevel=0.004)
    B.box((1.22, 1.12, 1.02), (0.14, 0.04, 0.035), M["bumper"], bevel=0.005)

    # 3. Ladeaufbau (Kastenaufbau X = -2.64 .. 1.02) mit offenem Schiebetuer-Ausschnitt links (-Z)!
    # Dach + Boden + Trennwand zur Kabine + Rechte Seitenwand + Hintere Ecke links + Hecktueren
    B.box((-0.82, 2.48, 0.0), (3.66, 0.11, 1.94), M["paint"], bevel=0.028) # Gerundetes Hochdach
    B.box((-0.82, 0.52, 0.0), (3.68, 0.16, 1.96), M["dark_metal"], bevel=0.012) # Chassis-Rahmen
    B.box((-0.82, 0.61, 0.0), (3.56, 0.04, 1.84), M["plywood"], bevel=0.004) # Laderaumboden Holz
    B.box((0.96, 1.50, 0.0), (0.08, 1.84, 1.88), M["interior"], bevel=0.008) # Trennwand Kabine/Laderaum
    # Rechte Seitenwand (+Z durchgehend mit 2K CLOUD EXPRESS Livery!)
    B.box((-0.82, 1.54, 0.99), (3.64, 1.86, 0.08), M["paint"], bevel=0.018)
    B.box((-0.82, 1.52, 1.036), (3.44, 1.62, 0.012), M["livery"], bevel=0.0, uv_mode="side_x")
    # Linke Seitenwand (-Z): hinterer Bereich fest (X = -2.64 .. -0.84), vorne Schiebetuer-Oeffnung (-0.84 .. +0.76)!
    B.box((-1.74, 1.54, -0.99), (1.80, 1.86, 0.08), M["paint"], bevel=0.018)
    B.box((-1.74, 1.52, -1.036), (1.72, 1.62, 0.012), M["livery"], bevel=0.0, uv_mode="side_x")
    B.box((0.88, 1.54, -0.99), (0.28, 1.86, 0.08), M["paint"], bevel=0.014)
    # Schiebetuer-Laufschiene aussen links (-Z)
    B.box((-1.72, 1.38, -1.055), (1.78, 0.045, 0.032), M["chrome"], bevel=0.004)
    # Innenverkleidung Birke rechts & links hinten
    B.box((-0.82, 1.52, 0.93), (3.50, 1.72, 0.03), M["plywood"], bevel=0.004)
    B.box((-1.74, 1.52, -0.93), (1.72, 1.72, 0.03), M["plywood"], bevel=0.004)
    # Radkasten-Verkleidungen innen
    for rz in (-0.78, 0.78):
        B.box((-1.62, 0.78, rz), (0.94, 0.34, 0.30), M["plywood"], bevel=0.010)

    # 4. Zweigeteilte Hecktueren (-X = -2.65) mit vertikalen LED-Rueckleuchten & Trittstufe
    B.box((-2.64, 1.54, -0.49), (0.08, 1.84, 0.94), M["paint"], bevel=0.016)
    B.box((-2.64, 1.54, 0.49), (0.08, 1.84, 0.94), M["paint"], bevel=0.016)
    # Blauer Flottenstreifen hinten
    B.box((-2.688, 1.56, 0.0), (0.012, 0.24, 1.86), M["blue_acc"], bevel=0.0)
    # Heckstossstange + Trittstufe + Kennzeichen hinten
    B.box((-2.68, 0.48, 0.0), (0.22, 0.26, 2.02), M["bumper"], bevel=0.018)
    B.box((-2.80, 0.44, 0.0), (0.14, 0.06, 1.32), M["dark_metal"], bevel=0.006)
    B.box((-2.70, 0.88, 0.0), (0.016, 0.13, 0.52), M["plate"], bevel=0.002, uv_mode="front_y")
    # Vertikale LED-Rueckleuchten & Blinker hinten + 3. Bremsleuchte oben
    for lz in (-0.88, 0.88):
        B.box((-2.68, 1.16, lz), (0.06, 0.46, 0.14), M["brake"], bevel=0.010)
        B.box((-2.685, 1.44, lz), (0.06, 0.14, 0.14), M["hazard"], bevel=0.008)
    B.box((-2.67, 2.44, 0.0), (0.04, 0.06, 0.34), M["brake"], bevel=0.006)

    # 5. Frontpartie: Stossstange, Kuehlergrill, LED-Scheinwerfer, Nebelscheinwerfer, EU-Kennzeichen
    B.box((2.82, 0.48, 0.0), (0.24, 0.30, 1.96), M["bumper"], bevel=0.024)
    B.box((2.87, 0.88, 0.0), (0.07, 0.36, 1.06), M["grille"], bevel=0.010)
    for gy in (0.78, 0.88, 0.98):
        B.box((2.905, gy, 0.0), (0.02, 0.022, 0.98), M["chrome"], bevel=0.003)
    B.cyl((2.91, 0.88, 0.0), 0.075, 0.075, 0.025, M["chrome"], axis_g="x", seg=20)
    B.box((2.945, 0.46, 0.0), (0.016, 0.13, 0.52), M["plate"], bevel=0.002, uv_mode="front_y")
    for lz in (-0.74, 0.74):
        B.box((2.82, 0.96, lz), (0.14, 0.22, 0.36), M["headlight"], bevel=0.016)
        B.box((2.86, 0.84, lz * 1.06), (0.08, 0.07, 0.22), M["hazard"], bevel=0.006)
        B.box((2.90, 0.46, lz * 0.92), (0.05, 0.09, 0.16), M["headlight"], bevel=0.008)

    # 6. Aussenspiegel (Doppelarm-Sprinter-Spiegel), Radlauf-Verbreiterungen & Dach-Rundumleuchte
    for sz in (-1.0, 1.0):
        B.box((2.06, 1.56, sz * 1.12), (0.10, 0.28, 0.16), M["bumper"], bevel=0.016)
        B.box((2.04, 1.50, sz * 1.02), (0.04, 0.03, 0.18), M["bumper"], bevel=0.004)
        B.box((2.04, 1.62, sz * 1.02), (0.04, 0.03, 0.18), M["bumper"], bevel=0.004)
        # Seiten-Kunststoffbeplankung & Radlaeufe
        B.box((0.08, 0.44, sz * 1.01), (2.26, 0.18, 0.07), M["cladding"], bevel=0.010)
        for wx in (-1.62, 1.78):
            B.box((wx, 0.78, sz * 1.03), (0.92, 0.10, 0.08), M["cladding"], bevel=0.014)
    # Dach-Warnleuchte (amber beacon)
    B.cyl((1.38, 2.52, 0.0), 0.11, 0.10, 0.04, M["bumper"], axis_g="y", seg=20)
    B.cyl((1.38, 2.60, 0.0), 0.085, 0.072, 0.12, M["beacon"], axis_g="y", seg=20)

    # 7. Sichtbares Kabinen-Interieur: Armaturenbrett, Tacho, Lenkrad, 2 Sitze
    B.box((1.92, 1.16, 0.0), (0.48, 0.32, 1.74), M["interior"], bevel=0.016)
    B.box((1.72, 1.24, -0.44), (0.04, 0.15, 0.48), M["dash"], bevel=0.004, uv_mode="front_y")
    # Lenkrad links (z = -0.46)
    B.cyl((1.62, 1.20, -0.46), 0.025, 0.025, 0.24, M["dark_metal"], axis_g="x", seg=12)
    B.cyl((1.52, 1.22, -0.46), 0.18, 0.18, 0.035, M["bumper"], axis_g="x", seg=24)
    # 2 Fahrer-/Beifahrersitze
    for sz in (-0.46, 0.46):
        B.box((1.34, 0.82, sz), (0.48, 0.14, 0.48), M["seat"], bevel=0.022)
        B.box((1.12, 1.22, sz), (0.14, 0.68, 0.46), M["seat"], rot_g_deg=(0.0, 0.0, -10.0), bevel=0.024)
        B.box((1.08, 1.66, sz), (0.11, 0.20, 0.24), M["seat"], bevel=0.018)

    B.build()

    # 8. Bewegliche Schiebetuer (Pivot bei (-0.08, 1.32, -1.05))
    SD = PartBuilder("Side_Door", origin_g=Vector((-0.08, 1.32, -1.05)))
    SD.box((-0.08, 1.54, -1.05), (1.58, 1.86, 0.07), M["paint"], bevel=0.016)
    SD.box((-0.08, 1.52, -1.092), (1.52, 1.62, 0.010), M["livery"], bevel=0.0, uv_mode="side_x")
    SD.box((-0.08, 0.62, -1.085), (1.56, 0.22, 0.03), M["cladding"], bevel=0.008)
    SD.box((0.52, 1.28, -1.105), (0.16, 0.045, 0.038), M["bumper"], bevel=0.006)
    SD.build()

    # 9. Bewegliche Fahrertuer links (Scharnier bei (2.04, 1.05, -0.99))
    CD = PartBuilder("Cab_Door_L", origin_g=Vector((2.04, 1.05, -0.99)))
    CD.box((1.54, 0.96, -0.99), (1.02, 0.98, 0.07), M["paint"], bevel=0.015)
    CD.box((1.54, 1.70, -0.97), (0.88, 0.64, 0.025), M["glass"], bevel=0.004)
    CD.box((1.16, 1.12, -1.035), (0.14, 0.04, 0.035), M["bumper"], bevel=0.005)
    CD.build()

    # 10. 4 realistische Raeder
    build_wheel("Wheel_FL", Vector((1.78, 0.40, -0.96)), M, True)
    build_wheel("Wheel_FR", Vector((1.78, 0.40, 0.96)), M, False)
    build_wheel("Wheel_RL", Vector((-1.62, 0.40, -0.96)), M, True)
    build_wheel("Wheel_RR", Vector((-1.62, 0.40, 0.96)), M, False)

    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=OUT_GLB,
        export_format="GLB",
        export_materials="EXPORT",
        export_yup=True,
        export_apply=True,
    )
    print(f"EXPORTED VAN: {OUT_GLB} ({os.path.getsize(OUT_GLB)} bytes)")


if __name__ == "__main__":
    try:
        build_van()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
