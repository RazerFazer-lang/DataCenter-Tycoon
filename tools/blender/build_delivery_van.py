"""Gemeinsame Blender-5.2-Helfer fuer viele Generatoren (PartBuilder, Materialien, Bild-Laden).

Frueher baute dieses Skript den Lieferwagen delivery_van.glb. Den nutzt das Spiel nicht mehr
(heute: deliver_van/deliver_truck/deliver_heavy aus build_delivery_c.py), daher exportiert die
Datei selbst nichts mehr. Sie bleibt als Bibliothek, weil u. a. hall_pbr_kit.py, build_paket_a.py,
build_exterior_world.py, build_exterior_vehicles.py und build_halle_nord.py daraus importieren.

Godot-Koordinaten (g(x, y, z) -> Blender (x, -z, y)), Boden Y = 0.0.
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

import pbr_textures


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
        """Erzeugt eine sauber geschwungene Lieferwagen-Karosserieform entlang der Godot-X-Achse.
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
