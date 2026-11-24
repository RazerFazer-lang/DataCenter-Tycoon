"""Blender 5.2 Generator fuer die neuen, anatomisch proportionierten 3D-Charaktere:
1. assets/models/delivery_driver.glb  (CLOUD EXPRESS Kurierfahrer mit exakten Gelenk-Pivots fuer delivery_driver.gd)
2. assets/models/player.glb           (IT-Techniker-Spielermodell mit Skin-Editor-Materialien & umschaltbaren Accessoires)

Godot-Koordinaten: X rechts, Y oben (Boden = 0), Front = -Z. g(x, y, z) -> Blender (x, -z, y).
Aufruf:
    blender --background --factory-startup --python-exit-code 1 --python tools/blender/build_characters.py
"""

import math
import os
import sys
import traceback

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_MODELS_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models"))


def g(x: float, y: float, z: float) -> Vector:
    return Vector((x, -z, y))


def make_mat(name: str, rgb, rough: float = 0.55, metal: float = 0.0, coat: float = 0.0):
    m = bpy.data.materials.new(name=name)
    if bpy.app.version < (5, 0, 0):
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (rgb[0], rgb[1], rgb[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if "Coat Weight" in bsdf.inputs and coat > 0.0:
        bsdf.inputs["Coat Weight"].default_value = coat
    return m


def make_pivot(name: str, local_pos_g: Vector, parent=None):
    emp = bpy.data.objects.new(name, None)
    emp.empty_display_type = "PLAIN_AXES"
    emp.empty_display_size = 0.06
    emp.location = g(local_pos_g.x, local_pos_g.y, local_pos_g.z)
    bpy.context.scene.collection.objects.link(emp)
    if parent is not None:
        emp.parent = parent
    return emp


class CharMesh:
    """Baut weiche, anatomisch geformte Koerperteile (Lofts, abgerundete Gliedmassen, Gesicht) in lokalen Godot-Koordinaten."""

    def __init__(self, name: str):
        self.name = name
        self.bm = bmesh.new()
        self.mats = []
        self.mat_map = {}

    def _mid(self, mat) -> int:
        if mat.name not in self.mat_map:
            self.mat_map[mat.name] = len(self.mats)
            self.mats.append(mat)
        return self.mat_map[mat.name]

    def loft_y(self, rings_spec: list, mat, seg: int = 20, cap_bot: bool = True, cap_top: bool = True):
        """Erzeugt eine organisch geformte, weich schattierte Silhouette entlang der lokalen Godot-Y-Achse.
        rings_spec: Liste von (y, rx, rz, ox, oz) -> elliptischer Querschnitt auf Hoehe y mit Versatz (ox, oz).
        """
        mid = self._mid(mat)
        rings = []
        for (y, rx, rz, ox, oz) in rings_spec:
            ring = []
            for k in range(seg):
                a = 2.0 * math.pi * k / seg
                px = ox + math.cos(a) * rx
                pz = oz + math.sin(a) * rz
                ring.append(self.bm.verts.new(g(px, y, pz)))
            rings.append(ring)
        faces = []
        for i in range(len(rings) - 1):
            r0, r1 = rings[i], rings[i + 1]
            for k in range(seg):
                kn = (k + 1) % seg
                f = self.bm.faces.new((r0[k], r0[kn], r1[kn], r1[k]))
                f.material_index = mid
                f.smooth = True
                faces.append(f)
        if cap_bot:
            c = self.bm.verts.new(g(rings_spec[0][3], rings_spec[0][0] - 0.004, rings_spec[0][4]))
            for k in range(seg):
                kn = (k + 1) % seg
                f = self.bm.faces.new((rings[0][kn], rings[0][k], c))
                f.material_index = mid
                f.smooth = True
                faces.append(f)
        if cap_top:
            c = self.bm.verts.new(g(rings_spec[-1][3], rings_spec[-1][0] + 0.004, rings_spec[-1][4]))
            for k in range(seg):
                kn = (k + 1) % seg
                f = self.bm.faces.new((rings[-1][k], rings[-1][kn], c))
                f.material_index = mid
                f.smooth = True
                faces.append(f)
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)

    def sphere(self, center_g, scale_g, mat, seg: int = 18, rings: int = 12):
        mid = self._mid(mat)
        ret = bmesh.ops.create_uvsphere(self.bm, u_segments=seg, v_segments=rings, radius=1.0)
        verts = ret["verts"]
        for v in verts:
            v.co.x *= scale_g[0]
            v.co.y *= scale_g[2]
            v.co.z *= scale_g[1]
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(g(*center_g)), verts=verts)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = mid
            f.smooth = True

    def box(self, center_g, size_g, mat, rot_g_deg=(0.0, 0.0, 0.0), bevel: float = 0.004, smooth: bool = True):
        mid = self._mid(mat)
        sx, sy, sz = size_g[0], size_g[2], size_g[1]
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
        rx, ry, rz = rot_g_deg
        rot_m = Euler((math.radians(rx), math.radians(-rz), math.radians(ry)), "XYZ").to_matrix().to_4x4()
        bmesh.ops.transform(self.bm, matrix=Matrix.Translation(g(*center_g)) @ rot_m, verts=verts)
        for f in {f for v in verts for f in v.link_faces}:
            f.material_index = mid
            f.smooth = smooth

    def build(self, parent=None):
        mesh = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(mesh)
        self.bm.free()
        for m in self.mats:
            mesh.materials.append(m)
        obj = bpy.data.objects.new(self.name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        if parent is not None:
            obj.parent = parent
        return obj


def _add_sculpted_head(H: CharMesh, M: dict):
    """Natuerlich proportionierter Kopf mit Kieferlinie, Nase, dezenten Augen, Brauen & Ohren (Front -Z)."""
    # Kopf-Silhouette von Kinn (0.025) bis Schaedeldecke (0.235)
    H.loft_y([
        (0.025, 0.036, 0.042, 0.0, -0.012),
        (0.055, 0.068, 0.078, 0.0, -0.014),
        (0.105, 0.088, 0.098, 0.0, -0.008),
        (0.160, 0.092, 0.104, 0.0, 0.000),
        (0.205, 0.084, 0.095, 0.0, 0.004),
        (0.234, 0.052, 0.060, 0.0, 0.004),
    ], M["skin"], seg=24)
    # Dezente Nase & Ohren (keine riesigen Kugeln!)
    H.box((0.0, 0.112, -0.105), (0.018, 0.032, 0.024), M["skin"], rot_g_deg=(12.0, 0.0, 0.0), bevel=0.005)
    for sx in (-1.0, 1.0):
        H.sphere((sx * 0.092, 0.125, 0.004), (0.014, 0.026, 0.018), M["skin"], seg=12, rings=8)
        # Natuerliche, klar sichtbare Augen (buedig auf der Gesichtsflaeche)
        H.sphere((sx * 0.032, 0.138, -0.099), (0.013, 0.009, 0.006), M["eye_white"], seg=12, rings=8)
        H.sphere((sx * 0.032, 0.138, -0.104), (0.007, 0.007, 0.003), M["eye_iris"], seg=10, rings=6)
        # Saubere Augenbrauen
        H.box((sx * 0.033, 0.156, -0.102), (0.030, 0.007, 0.008), M["hair"], rot_g_deg=(0.0, 0.0, sx * -4.0), bevel=0.002)
    # Dezenter freundlicher Mund
    H.box((0.0, 0.072, -0.095), (0.034, 0.006, 0.008), M["lip"], bevel=0.002)


def _add_cap_mesh(C: CharMesh, cap_mat, accent_mat):
    """Sitzende Kurier-/Tech-Basecap mit leicht gebogenem Schirm."""
    C.loft_y([
        (0.168, 0.096, 0.107, 0.0, 0.004),
        (0.205, 0.094, 0.104, 0.0, 0.005),
        (0.236, 0.074, 0.082, 0.0, 0.005),
        (0.248, 0.036, 0.040, 0.0, 0.005),
    ], cap_mat, seg=24)
    # Gebogener Schirm vorne (-Z)
    C.box((0.0, 0.172, -0.125), (0.145, 0.010, 0.095), cap_mat, rot_g_deg=(-9.0, 0.0, 0.0), bevel=0.004)
    C.box((0.0, 0.205, -0.105), (0.044, 0.022, 0.006), accent_mat, bevel=0.002)


def _add_short_hair(H: CharMesh, hair_mat):
    """Moderner Kurzhaarschnitt (sauber anliegend ohne Stirn zu verdecken)."""
    H.loft_y([
        (0.125, 0.092, 0.088, 0.0, 0.024),
        (0.168, 0.097, 0.104, 0.0, 0.012),
        (0.210, 0.094, 0.103, 0.0, 0.005),
        (0.242, 0.068, 0.078, 0.0, 0.004),
        (0.252, 0.028, 0.032, 0.0, 0.004),
    ], hair_mat, seg=22)


def _add_boot(B: CharMesh, y_ankle: float, shoe_mat, sole_mat, accent_mat=None):
    """Anatomischer Arbeitsschuh / Sneaker mit Sohle & Zehenkappe (Front -Z)."""
    B.box((0.0, y_ankle - 0.036, -0.034), (0.096, 0.068, 0.215), shoe_mat, bevel=0.014)
    B.sphere((0.0, y_ankle - 0.046, -0.122), (0.046, 0.032, 0.048), shoe_mat, seg=14, rings=8)
    B.box((0.0, y_ankle - 0.074, -0.040), (0.104, 0.024, 0.255), sole_mat, bevel=0.006)
    if accent_mat is not None:
        B.box((0.0, y_ankle - 0.056, -0.038), (0.100, 0.010, 0.220), accent_mat, bevel=0.002)


# ---------------------------------------------------------------------------
# 1. Realistischer CLOUD-EXPRESS Lieferfahrer (delivery_driver.glb)
# ---------------------------------------------------------------------------

def build_delivery_driver():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = {
        "jacket": make_mat("DRV_Jacket", (0.08, 0.19, 0.42), rough=0.68),
        "collar": make_mat("DRV_Collar", (0.05, 0.11, 0.24), rough=0.64),
        "reflect": make_mat("DRV_Reflect", (0.16, 0.80, 0.96), rough=0.22, metal=0.25),
        "amber": make_mat("DRV_Amber", (0.95, 0.68, 0.12), rough=0.35),
        "pants": make_mat("DRV_Pants", (0.13, 0.15, 0.19), rough=0.78),
        "belt": make_mat("DRV_Belt", (0.06, 0.06, 0.07), rough=0.45),
        "buckle": make_mat("DRV_Buckle", (0.78, 0.80, 0.84), rough=0.22, metal=0.92),
        "shoe": make_mat("DRV_Shoe", (0.10, 0.10, 0.12), rough=0.58),
        "sole": make_mat("DRV_Sole", (0.04, 0.04, 0.05), rough=0.88),
        "skin": make_mat("DRV_Skin", (0.87, 0.70, 0.58), rough=0.62),
        "hair": make_mat("DRV_Hair", (0.16, 0.11, 0.08), rough=0.82),
        "eye_white": make_mat("DRV_EyeWhite", (0.94, 0.94, 0.92), rough=0.18),
        "eye_iris": make_mat("DRV_EyeIris", (0.14, 0.18, 0.24), rough=0.12),
        "lip": make_mat("DRV_Lip", (0.66, 0.44, 0.38), rough=0.55),
    }

    p_body = make_pivot("Pivot_Body", Vector((0.0, 0.0, 0.0)))
    # Becken / Huefte
    pelvis = CharMesh("Driver_Pelvis")
    pelvis.loft_y([
        (0.84, 0.145, 0.095, 0.0, 0.0),
        (0.92, 0.162, 0.106, 0.0, 0.0),
        (0.97, 0.158, 0.102, 0.0, 0.0),
    ], M["pants"], seg=20)
    pelvis.loft_y([(0.955, 0.164, 0.108, 0.0, 0.0), (0.985, 0.164, 0.108, 0.0, 0.0)], M["belt"], seg=20)
    pelvis.box((0.0, 0.97, -0.110), (0.044, 0.030, 0.010), M["buckle"], bevel=0.002)
    pelvis.build(p_body)

    # Beine (Thigh + Knee)
    for side_name, sx in (("L", -0.095), ("R", 0.095)):
        p_thigh = make_pivot(f"Pivot_Thigh{side_name}", Vector((sx, 0.92, 0.0)), p_body)
        tm = CharMesh(f"Driver_Thigh{side_name}")
        tm.loft_y([
            (-0.46, 0.056, 0.060, 0.0, 0.0),
            (-0.24, 0.072, 0.078, 0.0, 0.0),
            (-0.02, 0.084, 0.088, 0.0, 0.0),
        ], M["pants"], seg=18)
        tm.build(p_thigh)

        p_knee = make_pivot(f"Pivot_Knee{side_name}", Vector((0.0, -0.45, 0.0)), p_thigh)
        km = CharMesh(f"Driver_Knee{side_name}")
        km.loft_y([
            (-0.39, 0.044, 0.048, 0.0, 0.0),
            (-0.22, 0.056, 0.060, 0.0, 0.0),
            (-0.02, 0.058, 0.060, 0.0, 0.0),
        ], M["pants"], seg=18)
        km.loft_y([(-0.31, 0.052, 0.056, 0.0, 0.0), (-0.285, 0.053, 0.057, 0.0, 0.0)], M["reflect"], seg=18)
        _add_boot(km, -0.385, M["shoe"], M["sole"])
        km.build(p_knee)

    # Oberkoerper (Torso Pivot bei Y = 0.92)
    p_torso = make_pivot("Pivot_Torso", Vector((0.0, 0.92, 0.0)), p_body)
    tr = CharMesh("Driver_Torso")
    tr.loft_y([
        (0.02, 0.156, 0.102, 0.0, 0.0),
        (0.18, 0.168, 0.112, 0.0, -0.004),
        (0.36, 0.194, 0.122, 0.0, -0.006),
        (0.49, 0.205, 0.114, 0.0, 0.0),
        (0.55, 0.120, 0.085, 0.0, 0.0),
    ], M["jacket"], seg=24)
    # Reflex-Streifen rund um Taille & Brust, Reissverschluss, Namensschild & Kragen
    tr.loft_y([(0.16, 0.171, 0.116, 0.0, -0.004), (0.195, 0.173, 0.117, 0.0, -0.004)], M["reflect"], seg=24)
    tr.box((0.0, 0.29, -0.122), (0.014, 0.46, 0.008), M["collar"], bevel=0.002)
    tr.box((-0.09, 0.39, -0.122), (0.078, 0.028, 0.008), M["amber"], bevel=0.002)
    tr.loft_y([(0.535, 0.072, 0.072, 0.0, 0.0), (0.580, 0.068, 0.068, 0.0, 0.0)], M["collar"], seg=18)
    # Hals
    tr.loft_y([(0.56, 0.048, 0.050, 0.0, 0.0), (0.635, 0.046, 0.048, 0.0, 0.0)], M["skin"], seg=16)
    tr.build(p_torso)

    # Kopf mit Gesicht & Kurier-Basecap
    p_head = make_pivot("Pivot_Head", Vector((0.0, 0.615, 0.0)), p_torso)
    hm = CharMesh("Driver_Head")
    _add_sculpted_head(hm, M)
    _add_short_hair(hm, M["hair"])
    _add_cap_mesh(hm, M["collar"], M["amber"])
    hm.build(p_head)

    # Arme (Shoulder + Elbow)
    for side_name, sx in (("L", -0.21), ("R", 0.21)):
        p_sh = make_pivot(f"Pivot_Shoulder{side_name}", Vector((sx, 0.45, 0.0)), p_torso)
        am = CharMesh(f"Driver_UpperArm{side_name}")
        am.sphere((0.0, 0.0, 0.0), (0.056, 0.056, 0.056), M["jacket"], seg=14, rings=10)
        am.loft_y([
            (-0.27, 0.044, 0.046, 0.0, 0.0),
            (-0.14, 0.050, 0.052, 0.0, 0.0),
            (0.00, 0.054, 0.056, 0.0, 0.0),
        ], M["jacket"], seg=16)
        am.build(p_sh)

        p_el = make_pivot(f"Pivot_Elbow{side_name}", Vector((0.0, -0.27, 0.0)), p_sh)
        fm = CharMesh(f"Driver_Forearm{side_name}")
        fm.loft_y([
            (-0.24, 0.034, 0.036, 0.0, 0.0),
            (-0.12, 0.042, 0.044, 0.0, 0.0),
            (0.00, 0.044, 0.046, 0.0, 0.0),
        ], M["jacket"], seg=16)
        fm.loft_y([(-0.25, 0.036, 0.038, 0.0, 0.0), (-0.23, 0.036, 0.038, 0.0, 0.0)], M["collar"], seg=16)
        # Geformte Hand mit Daumen
        fm.sphere((0.0, -0.285, -0.008), (0.026, 0.044, 0.036), M["skin"], seg=14, rings=10)
        fm.sphere((-0.022 if sx < 0 else 0.022, -0.275, -0.030), (0.012, 0.020, 0.016), M["skin"], seg=10, rings=8)
        fm.build(p_el)

    out_path = os.path.join(OUT_MODELS_DIR, "delivery_driver.glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format="GLB", export_materials="EXPORT",
        export_yup=True, export_apply=False
    )
    print(f"EXPORTED DRIVER: {out_path} ({os.path.getsize(out_path)} bytes)")


# ---------------------------------------------------------------------------
# 2. Neues IT-Techniker-Spielermodell mit Skin-Editor-Hooks (player.glb)
# ---------------------------------------------------------------------------

def build_player_model():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    M = {
        "jacket": make_mat("DCT_Jacket", (0.14, 0.28, 0.54), rough=0.66),
        "pants": make_mat("DCT_Pants", (0.15, 0.17, 0.21), rough=0.78),
        "skin": make_mat("DCT_Skin", (0.88, 0.72, 0.60), rough=0.60),
        "hair": make_mat("DCT_Hair", (0.16, 0.11, 0.08), rough=0.80),
        "shoe": make_mat("DCT_Shoes", (0.12, 0.13, 0.15), rough=0.52),
        "sole": make_mat("DCT_Sole", (0.90, 0.91, 0.93), rough=0.72),
        "accent": make_mat("DCT_Accent", (0.18, 0.76, 0.96), rough=0.35),
        "dark": make_mat("DCT_DarkTrim", (0.07, 0.08, 0.10), rough=0.45),
        "metal": make_mat("DCT_Metal", (0.80, 0.83, 0.86), rough=0.20, metal=0.92),
        "glass": make_mat("DCT_GlassesLens", (0.10, 0.18, 0.26), rough=0.08, metal=0.25, coat=0.8),
        "eye_white": make_mat("DCT_EyeWhite", (0.94, 0.94, 0.92), rough=0.18),
        "eye_iris": make_mat("DCT_EyeIris", (0.14, 0.20, 0.28), rough=0.12),
        "lip": make_mat("DCT_Lip", (0.68, 0.45, 0.39), rough=0.55),
    }

    # Torso & Becken (statisch an Root, Y = 0.74 .. 1.50)
    torso = CharMesh("Player_Torso")
    torso.loft_y([
        (0.75, 0.148, 0.095, 0.0, 0.0),
        (0.84, 0.162, 0.106, 0.0, 0.0),
    ], M["pants"], seg=22)
    torso.loft_y([(0.835, 0.164, 0.108, 0.0, 0.0), (0.865, 0.164, 0.108, 0.0, 0.0)], M["dark"], seg=22)
    torso.box((0.0, 0.85, -0.110), (0.042, 0.028, 0.010), M["metal"], bevel=0.002)
    # Moderner IT-Tech-Hoodie / Jacke mit Kapuze im Nacken, Reissverschluss & Lanyard
    torso.loft_y([
        (0.86, 0.162, 0.106, 0.0, 0.0),
        (1.06, 0.172, 0.116, 0.0, -0.004),
        (1.26, 0.198, 0.124, 0.0, -0.006),
        (1.39, 0.206, 0.112, 0.0, 0.0),
        (1.45, 0.114, 0.082, 0.0, 0.0),
    ], M["jacket"], seg=24)
    # Kapuze locker im Nacken
    torso.box((0.0, 1.41, 0.088), (0.18, 0.095, 0.082), M["jacket"], rot_g_deg=(18.0, 0.0, 0.0), bevel=0.022)
    # Reissverschluss + DataCenter-ID-Lanyard mit Badge
    torso.box((0.0, 1.15, -0.124), (0.014, 0.52, 0.008), M["dark"], bevel=0.002)
    torso.box((0.0, 1.14, -0.128), (0.052, 0.072, 0.006), M["accent"], bevel=0.002)
    for sx in (-0.036, 0.036):
        torso.box((sx, 1.30, -0.118), (0.010, 0.26, 0.006), M["accent"], rot_g_deg=(0.0, 0.0, sx * -160.0), bevel=0.002)
    # Hals (natuerliche Breite) & Hoodie-Kragen
    torso.loft_y([(1.43, 0.082, 0.080, 0.0, 0.0), (1.475, 0.074, 0.072, 0.0, 0.0)], M["jacket"], seg=18)
    torso.loft_y([(1.46, 0.056, 0.056, 0.0, 0.0), (1.535, 0.052, 0.052, 0.0, 0.0)], M["skin"], seg=16)
    torso.build()

    # Beine (Pivot_LegL / Pivot_LegR bei Y = 0.78)
    for side_name, sx in (("L", -0.095), ("R", 0.095)):
        p_leg = make_pivot(f"Pivot_Leg{side_name}", Vector((sx, 0.78, 0.0)))
        lm = CharMesh(f"Player_Leg{side_name}")
        lm.loft_y([
            (-0.70, 0.044, 0.048, 0.0, 0.0),
            (-0.42, 0.058, 0.062, 0.0, 0.0),
            (-0.20, 0.074, 0.078, 0.0, 0.0),
            (0.00, 0.084, 0.088, 0.0, 0.0),
        ], M["pants"], seg=20)
        # Cargo-Tasche seitlich am Oberschenkel
        lm.box((sx * 0.78, -0.26, 0.0), (0.022, 0.14, 0.10), M["pants"], bevel=0.006)
        _add_boot(lm, -0.695, M["shoe"], M["sole"], M["accent"])
        lm.build(p_leg)

    # Arme (Pivot_ArmL / Pivot_ArmR bei Y = 1.34)
    for side_name, sx in (("L", -0.215), ("R", 0.215)):
        p_arm = make_pivot(f"Pivot_Arm{side_name}", Vector((sx, 1.34, 0.0)))
        am = CharMesh(f"Player_Arm{side_name}")
        am.sphere((0.0, 0.0, 0.0), (0.056, 0.056, 0.056), M["jacket"], seg=14, rings=10)
        am.loft_y([
            (-0.50, 0.036, 0.038, 0.0, 0.0),
            (-0.26, 0.046, 0.048, 0.0, 0.0),
            (0.00, 0.054, 0.056, 0.0, 0.0),
        ], M["jacket"], seg=18)
        am.loft_y([(-0.51, 0.038, 0.040, 0.0, 0.0), (-0.48, 0.038, 0.040, 0.0, 0.0)], M["dark"], seg=16)
        am.sphere((0.0, -0.545, -0.008), (0.026, 0.044, 0.036), M["skin"], seg=14, rings=10)
        am.build(p_arm)

    # Kopf (Pivot_Head bei Y = 1.50) + einzeln schaltbare Frisuren, Kopfbedeckungen & Brillen fuer den Skin-Editor!
    p_head = make_pivot("Pivot_Head", Vector((0.0, 1.50, 0.0)))
    hm = CharMesh("Player_Head")
    _add_sculpted_head(hm, M)
    hm.build(p_head)

    # Frisur 1: Kurzhaar
    h_short = CharMesh("Hair_Short")
    _add_short_hair(h_short, M["hair"])
    h_short.build(p_head)

    # Frisur 2: Moderner Undercut (volleres Deckhaar)
    h_under = CharMesh("Hair_Undercut")
    h_under.loft_y([
        (0.165, 0.096, 0.105, 0.0, 0.006),
        (0.215, 0.098, 0.112, 0.0, -0.006),
        (0.258, 0.078, 0.094, 0.0, -0.014),
        (0.270, 0.032, 0.040, 0.0, -0.012),
    ], M["hair"], seg=22)
    h_under.build(p_head)

    # Kopfbedeckung 1: Tech-Basecap
    hat_cap = CharMesh("Hat_Cap")
    _add_cap_mesh(hat_cap, M["jacket"], M["accent"])
    hat_cap.build(p_head)

    # Kopfbedeckung 2: Beanie-Muetze
    hat_beanie = CharMesh("Hat_Beanie")
    hat_beanie.loft_y([
        (0.164, 0.102, 0.112, 0.0, 0.004),
        (0.192, 0.102, 0.112, 0.0, 0.004),
        (0.235, 0.088, 0.098, 0.0, 0.008),
        (0.268, 0.052, 0.060, 0.0, 0.014),
    ], M["accent"], seg=24)
    hat_beanie.build(p_head)

    # Accessoire: DataCenter-Headset mit Mikrofonarm
    hs = CharMesh("Acc_Headset")
    hs.box((0.0, 0.244, 0.0), (0.20, 0.016, 0.026), M["dark"], bevel=0.004)
    for sx in (-1.0, 1.0):
        hs.box((sx * 0.102, 0.185, 0.0), (0.012, 0.12, 0.022), M["dark"], bevel=0.003)
        hs.sphere((sx * 0.104, 0.128, 0.002), (0.022, 0.038, 0.038), M["dark"], seg=16, rings=10)
        hs.sphere((sx * 0.112, 0.128, 0.002), (0.010, 0.024, 0.024), M["accent"], seg=12, rings=8)
    hs.box((-0.072, 0.088, -0.058), (0.008, 0.008, 0.11), M["dark"], rot_g_deg=(12.0, 26.0, 0.0), bevel=0.002)
    hs.sphere((-0.036, 0.076, -0.102), (0.010, 0.008, 0.012), M["dark"], seg=10, rings=6)
    hs.build(p_head)

    # Brille 1: Moderne schmale Tech-Brille
    gl = CharMesh("Acc_Glasses")
    for sx in (-0.036, 0.036):
        gl.box((sx, 0.138, -0.112), (0.048, 0.026, 0.006), M["dark"], bevel=0.002)
        gl.box((sx, 0.138, -0.111), (0.040, 0.020, 0.004), M["glass"], bevel=0.001)
    gl.box((0.0, 0.140, -0.112), (0.026, 0.006, 0.005), M["dark"], bevel=0.001)
    for sx in (-0.088, 0.088):
        gl.box((sx, 0.140, -0.055), (0.006, 0.006, 0.115), M["dark"], bevel=0.001)
    gl.build(p_head)

    # Brille 2: Getoente Werkstatt-Schutzbrille
    sg = CharMesh("Acc_SafetyGlasses")
    sg.box((0.0, 0.138, -0.114), (0.152, 0.038, 0.012), M["glass"], bevel=0.004)
    sg.box((0.0, 0.158, -0.113), (0.156, 0.008, 0.014), M["accent"], bevel=0.002)
    for sx in (-0.088, 0.088):
        sg.box((sx, 0.140, -0.056), (0.008, 0.010, 0.115), M["dark"], bevel=0.002)
    sg.build(p_head)

    out_path = os.path.join(OUT_MODELS_DIR, "player.glb")
    bpy.ops.export_scene.gltf(
        filepath=out_path, export_format="GLB", export_materials="EXPORT",
        export_yup=True, export_apply=False
    )
    print(f"EXPORTED PLAYER: {out_path} ({os.path.getsize(out_path)} bytes)")


if __name__ == "__main__":
    try:
        build_delivery_driver()
        build_player_model()
        print("CHARACTERS DONE!")
    except Exception:
        traceback.print_exc()
        sys.exit(1)
