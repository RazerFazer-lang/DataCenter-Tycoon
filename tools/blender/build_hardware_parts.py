"""Baut die Hardware-Bauteile für DataCenter Tycoon in Blender und exportiert sie als .glb.

Aufruf (Hintergrundmodus):
    blender --background --factory-startup --python-exit-code 1 \
        --python tools/blender/build_hardware_parts.py -- assets/models

Erzeugte Dateien (Stufe t = 0..3):
    part_cpu_t<t>.glb, part_ram_t<t>.glb, part_gpu_t<t>.glb, part_storage_t<t>.glb,
    part_cooling_t<t>.glb, part_psu_t<t>.glb, part_mainboard.glb, part_mainboard_ai.glb

Konventionen, auf die HardwareMeshFactory sich verlässt:
    * Koordinaten und Ursprung entsprechen den build_*-Funktionen in hardware_mesh_factory.gd.
      Gebaut wird in Godot-Koordinaten (Y oben, Front +Z) und beim Anlegen nach Blender umgerechnet.
    * Materialien "DCT_<schlüssel>" ersetzt das Spiel durch MatLib.get_mat(<schlüssel>).
    * Objekte "Rotor_Z_<n>" / "Rotor_X_<n>" sind drehende Lüfterräder (Drehachse Z bzw. X).
"""

import math
import os
import sys
import traceback

import bmesh
import bpy
from mathutils import Matrix, Vector

# Godot (x, y, z) -> Blender (x, -z, y). Der glTF-Export mit +Y oben rechnet das wieder zurück.
C = Matrix(((1.0, 0.0, 0.0, 0.0), (0.0, 0.0, -1.0, 0.0), (0.0, 1.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)))
I4 = Matrix.Identity(4)
BEVEL = 0.0012

STEEL = "DCT_galvanized_steel"
PLASTIC = "DCT_plastic_black"
PCB_G = "DCT_pcb_green"
PCB_B = "DCT_pcb_black"
GOLD = "DCT_gold_contacts"
COPPER = "DCT_copper_metal"
IC = "DCT_ic_chip"
ALU = "DCT_heatsink_aluminum"
CUFIN = "DCT_heatsink_copper"
IHS = "DCT_cpu_ihs"
PERF = "DCT_perforated_mesh"

DARK_STEEL = "DCX_dark_steel"
ETCH = "DCX_etch"
DARK_TOP = "DCX_dark_top"
SHROUD = "DCX_shroud"
BACKPLATE = "DCX_backplate"
BLADE_GPU = "DCX_blade_gpu"
LABEL = "DCX_label"
DARK_AL = "DCX_dark_al"
PAPER = "DCX_paper"
BLADE_FAN = "DCX_blade_fan"
SHADE = "DCX_shade"
HANDLE_GREEN = "DCX_handle_green"

# Farbe (sRGB wie in MatLib), Metallic, Roughness
MATS = {
    STEEL: ((0.62, 0.64, 0.66), 0.80, 0.35),
    PLASTIC: ((0.05, 0.05, 0.055), 0.0, 0.55),
    PCB_G: ((0.08, 0.30, 0.15), 0.10, 0.45),
    PCB_B: ((0.05, 0.055, 0.06), 0.10, 0.45),
    GOLD: ((0.86, 0.68, 0.30), 1.0, 0.25),
    COPPER: ((0.76, 0.46, 0.28), 1.0, 0.30),
    IC: ((0.07, 0.07, 0.08), 0.0, 0.40),
    ALU: ((0.76, 0.78, 0.80), 0.90, 0.30),
    CUFIN: ((0.74, 0.44, 0.27), 1.0, 0.35),
    IHS: ((0.78, 0.79, 0.80), 0.95, 0.22),
    PERF: ((0.30, 0.31, 0.33), 0.70, 0.50),
    DARK_STEEL: ((0.18, 0.19, 0.21), 0.65, 0.38),
    ETCH: ((0.50, 0.51, 0.53), 0.55, 0.55),
    DARK_TOP: ((0.20, 0.21, 0.23), 0.70, 0.40),
    SHROUD: ((0.16, 0.17, 0.19), 0.62, 0.34),
    BACKPLATE: ((0.11, 0.12, 0.13), 0.70, 0.40),
    BLADE_GPU: ((0.22, 0.23, 0.25), 0.20, 0.58),
    LABEL: ((0.80, 0.81, 0.83), 0.25, 0.55),
    DARK_AL: ((0.22, 0.24, 0.27), 0.72, 0.32),
    PAPER: ((0.86, 0.87, 0.89), 0.0, 0.80),
    BLADE_FAN: ((0.17, 0.18, 0.20), 0.15, 0.60),
    SHADE: ((0.05, 0.05, 0.06), 0.0, 0.85),
    HANDLE_GREEN: ((0.24, 0.56, 0.34), 0.30, 0.42),
}


def T(v):
    return Matrix.Translation(Vector(v))


def Rx(deg):
    return Matrix.Rotation(math.radians(deg), 4, "X")


def Ry(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Y")


def Rz(deg):
    return Matrix.Rotation(math.radians(deg), 4, "Z")


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def get_material(name):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat
    col, metal, rough = MATS[name]
    lin = tuple(srgb_to_linear(c) for c in col)
    mat = bpy.data.materials.new(name)
    # Ab Blender 5.0 nutzen Materialien immer Nodes; use_nodes ist dort veraltet.
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True
    mat.diffuse_color = (*lin, 1.0)
    mat.metallic = metal
    mat.roughness = rough
    tree = mat.node_tree
    if tree is not None:
        bsdf = next((n for n in tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
        if bsdf is None:
            bsdf = tree.nodes.new("ShaderNodeBsdfPrincipled")
            out = next((n for n in tree.nodes if n.type == "OUTPUT_MATERIAL"), None)
            if out is None:
                out = tree.nodes.new("ShaderNodeOutputMaterial")
            tree.links.new(bsdf.outputs[0], out.inputs[0])
        bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Metallic"].default_value = metal
        bsdf.inputs["Roughness"].default_value = rough
    return mat


class Part:
    """Sammelt Geometrie pro Gruppe ("Body" oder ein Rotor) in je einem bmesh."""

    def __init__(self):
        self.groups = {}
        self.order = []
        self.new_group("Body", (0.0, 0.0, 0.0))

    def new_group(self, key, origin):
        self.groups[key] = {"bm": bmesh.new(), "mats": [], "origin": Vector(origin)}
        self.order.append(key)

    def _add(self, t, M, mat, group):
        g = self.groups[group]
        if mat not in g["mats"]:
            g["mats"].append(mat)
        idx = g["mats"].index(mat)
        mx = C @ T(-g["origin"]) @ M
        bm = g["bm"]
        src_uv = t.loops.layers.uv.active
        dst_uv = bm.loops.layers.uv.verify()
        vmap = {}
        for v in t.verts:
            vmap[v] = bm.verts.new(mx @ v.co)
        for f in t.faces:
            nf = bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = idx
            nf.smooth = f.smooth
            # UVs mitkopieren, sonst zeigen Platinen- und Kühlkörper-Texturen nur einen Farbpunkt.
            if src_uv is not None:
                for src_loop, dst_loop in zip(f.loops, nf.loops):
                    dst_loop[dst_uv].uv = src_loop[src_uv].uv
        t.free()

    def box(self, pos, size, mat, M=None, rot=None, bevel=BEVEL, group="Body"):
        t = bmesh.new()
        t.loops.layers.uv.new("UVMap")
        bmesh.ops.create_cube(t, size=1.0, calc_uvs=True)
        for v in t.verts:
            v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        smallest = min(size)
        if bevel > 0.0 and smallest > 0.006:
            bmesh.ops.bevel(
                t,
                geom=list(t.edges),
                offset=min(bevel, smallest * 0.2),
                segments=1,
                profile=0.5,
                affect="EDGES",
                clamp_overlap=True,
            )
        mg = (M if M is not None else I4) @ T(pos) @ (rot if rot is not None else I4)
        self._add(t, mg, mat, group)

    def cyl(self, pos, r, h, mat, M=None, axis="y", seg=16, group="Body"):
        t = bmesh.new()
        t.loops.layers.uv.new("UVMap")
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=r, depth=h, calc_uvs=True)
        # Kegel liegt auf lokaler Z-Achse, Godot-Zylinder auf Y: (x, y, z) -> (x, z, -y)
        for v in t.verts:
            v.co = Vector((v.co.x, v.co.z, -v.co.y))
        for f in t.faces:
            f.smooth = len(f.verts) == 4
        rot = I4
        if axis == "z":
            rot = Rx(90.0)
        elif axis == "x":
            rot = Rz(90.0)
        mg = (M if M is not None else I4) @ T(pos) @ rot
        self._add(t, mg, mat, group)

    def fins(self, center, size, count, axis, mat, M=None, group="Body"):
        n = max(count, 1)
        span = size[axis]
        pitch = span / float(n)
        fin_size = list(size)
        fin_size[axis] = pitch * 0.38
        for i in range(n):
            off = [0.0, 0.0, 0.0]
            off[axis] = -span * 0.5 + (i + 0.5) * pitch
            self.box(Vector(center) + Vector(off), fin_size, mat, M, bevel=0.0, group=group)

    def blades(self, M, radius, count, blade_mat, hub_mat, group="Body"):
        blade_len = radius * 0.66
        blade_w = radius * 0.44
        dist = radius * 0.30 + blade_len * 0.5
        for i in range(count):
            ang = 360.0 * i / count
            a = math.radians(ang)
            self.box(
                (math.cos(a) * dist, math.sin(a) * dist, 0.0),
                (blade_len, blade_w, radius * 0.04),
                blade_mat,
                M,
                rot=Rz(ang) @ Rx(28.0),
                bevel=0.0,
                group=group,
            )
        self.cyl((0.0, 0.0, 0.0), radius * 0.30, radius * 0.24, hub_mat, M, axis="z", group=group)

    def export(self, path):
        faces = 0
        for key in self.order:
            g = self.groups[key]
            bm = g["bm"]
            faces += len(bm.faces)
            if len(bm.faces) == 0:
                bm.free()
                continue
            me = bpy.data.meshes.new(key)
            bm.to_mesh(me)
            bm.free()
            for name in g["mats"]:
                me.materials.append(get_material(name))
            ob = bpy.data.objects.new(key, me)
            ob.location = C @ g["origin"]
            bpy.context.scene.collection.objects.link(ob)
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", export_yup=True, export_apply=True)
        return faces


# ---------------------------------------------------------------- Bauteile


def build_mainboard(P, pcb):
    P.box((0.0, 0.0, 0.0), (0.58, 0.012, 0.48), pcb)
    # Befestigungsschrauben in den Ecken
    for sx in (-0.27, 0.27):
        for sz in (-0.22, 0.22):
            P.cyl((sx, 0.0075, sz), 0.006, 0.003, STEEL)
    # Rückwand-Anschlüsse: 2x RJ45, 4x USB, VGA
    for io in range(4):
        P.box((-0.22 + io * 0.065, 0.028, -0.22), (0.044, 0.042, 0.048), STEEL)
        P.box((-0.22 + io * 0.065, 0.030, -0.2445), (0.030, 0.016, 0.002), PLASTIC, bevel=0.0)
    # Spannungswandler mit Rippenkühler hinter dem CPU-Sockel
    P.box((-0.07, 0.012, -0.14), (0.16, 0.008, 0.032), ALU)
    P.fins((-0.07, 0.030, -0.14), (0.16, 0.028, 0.032), 12, 0, ALU)
    for m in range(8):
        P.box((-0.14 + m * 0.02, 0.008, -0.118), (0.010, 0.003, 0.008), IC, bevel=0.0)
    # CMOS-Knopfzelle
    P.cyl((0.21, 0.012, -0.16), 0.018, 0.008, STEEL, seg=24)
    # Chipsatz mit Kühlkörper
    P.box((0.18, 0.022, 0.04), (0.068, 0.028, 0.068), DARK_STEEL)
    P.fins((0.18, 0.040, 0.04), (0.068, 0.010, 0.068), 7, 0, DARK_STEEL)
    # Elkos mit Deckel
    for cap in range(6):
        cx = -0.18 + cap * 0.024
        P.cyl((cx, 0.018, -0.09), 0.007, 0.022, STEEL)
        P.cyl((cx, 0.0295, -0.09), 0.0062, 0.001, PLASTIC)
    # 24-Pin-ATX-Stecker
    P.box((0.25, 0.018, -0.06), (0.024, 0.022, 0.095), PLASTIC)
    P.box((0.25, 0.028, -0.06), (0.016, 0.006, 0.088), GOLD)
    # SATA-Anschlüsse
    for s in range(4):
        P.box((0.24, 0.016, 0.12 + s * 0.024), (0.036, 0.016, 0.016), PLASTIC)
    # Kleine SMD-Bausteine verteilt auf der Platine
    for i in range(5):
        P.box((0.06 + i * 0.03, 0.0075, 0.20), (0.014, 0.003, 0.010), IC, bevel=0.0)


def build_cpu(P, tier):
    P.box((0.0, 0.006, 0.0), (0.115, 0.012, 0.115), PLASTIC)
    P.box((0.0, 0.012, 0.0), (0.095, 0.005, 0.095), GOLD, bevel=0.0)
    P.box((0.0, 0.016, 0.0), (0.088, 0.006, 0.088), PCB_G, bevel=0.0)
    P.box((0.0, 0.022, 0.0), (0.072, 0.009, 0.072), IHS)
    for i in range(6):
        o = -0.025 + i * 0.010
        P.box((o, 0.020, -0.039), (0.004, 0.002, 0.003), IC, bevel=0.0)
        P.box((o, 0.020, 0.039), (0.004, 0.002, 0.003), IC, bevel=0.0)
    P.box((0.0, 0.020, -0.048), (0.096, 0.008, 0.012), STEEL)
    P.box((0.0, 0.020, 0.048), (0.096, 0.008, 0.012), STEEL)
    P.box((0.062, 0.016, 0.0), (0.008, 0.008, 0.115), STEEL)
    P.box((0.068, 0.016, 0.058), (0.012, 0.006, 0.006), STEEL, bevel=0.0)
    P.cyl((-0.050, 0.016, 0.0), 0.004, 0.100, STEEL, axis="z", seg=12)

    if tier == 0:
        P.box((0.0, 0.027, 0.016), (0.046, 0.001, 0.018), ETCH, bevel=0.0)
        P.box((0.0, 0.0285, -0.022), (0.076, 0.004, 0.032), ALU, bevel=0.0)
        P.fins((0.0, 0.0375, -0.022), (0.076, 0.014, 0.032), 10, 0, ALU)
    elif tier == 1:
        P.box((0.0, 0.030, 0.0), (0.105, 0.006, 0.105), ALU, bevel=0.0)
        P.fins((0.0, 0.051, 0.0), (0.105, 0.036, 0.105), 18, 0, ALU)
        for sx in (-0.048, 0.048):
            for sz in (-0.048, 0.048):
                P.cyl((sx, 0.071, sz), 0.005, 0.006, STEEL, seg=12)
    elif tier == 2:
        P.box((0.0, 0.032, 0.0), (0.096, 0.014, 0.096), COPPER)
        for hx in (-0.036, -0.012, 0.012, 0.036):
            for hz in (-0.022, 0.022):
                P.cyl((hx, 0.067, hz), 0.004, 0.056, COPPER, seg=12)
                P.cyl((hx, 0.0995, hz), 0.0045, 0.004, COPPER, seg=12)
        P.fins((0.0, 0.070, 0.0), (0.112, 0.050, 0.110), 14, 1, ALU)
        P.box((0.0, 0.097, 0.0), (0.112, 0.004, 0.110), DARK_TOP, bevel=0.0)
    else:
        P.box((0.0, 0.032, 0.0), (0.125, 0.014, 0.125), COPPER)
        P.fins((0.0, 0.066, 0.0), (0.122, 0.062, 0.120), 24, 0, CUFIN)
        for hx in (-0.044, -0.022, 0.0, 0.022, 0.044):
            P.cyl((hx, 0.099, 0.0), 0.005, 0.110, COPPER, axis="z", seg=12)
        P.box((0.0, 0.100, 0.0), (0.126, 0.008, 0.046), STEEL)
        for sx in (-0.058, 0.058):
            P.cyl((sx, 0.106, 0.0), 0.006, 0.006, STEEL, seg=12)


def build_gpu(P, tier):
    P.box((0.0, 0.010, 0.0), (0.020, 0.016, 0.165), PLASTIC)
    P.box((0.0, 0.016, 0.0), (0.008, 0.006, 0.155), GOLD, bevel=0.0)
    P.box((0.0, 0.012, 0.092), (0.024, 0.016, 0.018), STEEL)
    if tier <= 0:
        return

    rotor_i = 0
    cards = 2 if tier >= 3 else 1
    for c_idx in range(cards):
        card_pos = Vector((c_idx * 0.056, 0.022, 0.0))
        M = T(card_pos)
        card_len = 0.21 if tier == 1 else (0.28 if tier == 2 else 0.31)
        card_h = 0.072 if tier == 1 else 0.088
        half = card_len * 0.5
        mid = card_h * 0.5

        P.box((0.0, mid, 0.0), (0.008, card_h, card_len), PCB_B)
        P.box((0.0, 0.002, -0.034), (0.009, 0.012, 0.082), GOLD, M, bevel=0.0)
        P.box((0.0, 0.002, 0.040), (0.009, 0.012, 0.030), GOLD, M, bevel=0.0)
        P.box((-0.0055, mid, 0.004), (0.003, card_h - 0.004, card_len - 0.012), BACKPLATE, M, bevel=0.0)

        bz = -half - 0.004
        P.box((0.012, mid, bz), (0.036, card_h + 0.012, 0.008), STEEL, M)
        for p in range(3):
            P.box((0.002, 0.014 + p * 0.014, bz - 0.004), (0.012, 0.007, 0.003), PLASTIC, M, bevel=0.0)
        for v in range(4):
            P.box((0.022, 0.012 + v * 0.013, bz - 0.004), (0.010, 0.004, 0.003), PLASTIC, M, bevel=0.0)

        if tier >= 3:
            P.box((0.016, mid, -0.024), (0.026, card_h - 0.006, card_len - 0.056), SHROUD, M)
            P.fins((0.016, mid, half - 0.028), (0.026, card_h - 0.012, 0.048), 10, 1, CUFIN, M)
            P.box((0.016, card_h - 0.004, half - 0.028), (0.026, 0.004, 0.048), SHROUD, M, bevel=0.0)
            P.box((0.016, 0.004, half - 0.028), (0.026, 0.004, 0.048), SHROUD, M, bevel=0.0)
            P.box((0.016, card_h + 0.002, 0.0), (0.026, 0.006, card_len * 0.72), COPPER, M, bevel=0.0)
            P.box((0.0295, mid, -0.05), (0.001, 0.018, 0.08), LABEL, M, bevel=0.0)
            P.box((0.010, card_h + 0.008, -half + 0.025), (0.018, 0.012, 0.024), PLASTIC, M)
            continue

        face_x = 0.027
        fan_r = 0.027 if tier == 1 else 0.034
        fan_zs = [0.0] if tier == 1 else [-0.068, 0.068]
        P.fins((0.015, mid, 0.0), (0.018, card_h - 0.006, card_len - 0.020), 16 if tier == 1 else 22, 2, ALU, M)
        P.box((face_x, card_h - 0.004, 0.0), (0.006, 0.008, card_len - 0.010), SHROUD, M)
        P.box((face_x, 0.004, 0.0), (0.006, 0.008, card_len - 0.010), SHROUD, M)
        inner_h = card_h - 0.016
        cut_half = fan_r + 0.002
        seg_start = -half + 0.005
        for fz in fan_zs:
            seg_end = fz - cut_half
            if seg_end > seg_start:
                P.box((face_x, mid, (seg_start + seg_end) * 0.5), (0.006, inner_h, seg_end - seg_start), SHROUD, M)
            seg_start = fz + cut_half
        last_end = half - 0.005
        if last_end > seg_start:
            P.box((face_x, mid, (seg_start + last_end) * 0.5), (0.006, inner_h, last_end - seg_start), SHROUD, M)

        for fz in fan_zs:
            P.cyl((face_x - 0.001, mid, fz), fan_r + 0.002, 0.004, PLASTIC, M, axis="x", seg=24)
            key = "Rotor_X_%d" % rotor_i
            rotor_i += 1
            origin = card_pos + Vector((face_x + 0.005, mid, fz))
            P.new_group(key, origin)
            P.blades(T(origin) @ Ry(90.0), fan_r, 9, BLADE_GPU, STEEL, group=key)

        for hp in range(2 if tier == 1 else 3):
            P.cyl((0.010 + hp * 0.006, card_h + 0.001, -card_len * 0.10), 0.0032, card_len * 0.50, COPPER, M, axis="z", seg=10)
        P.box((face_x + 0.0035, mid, half - 0.018), (0.001, 0.010, 0.020), LABEL, M, bevel=0.0)
        for pc in range(1 if tier == 1 else 2):
            pz = half * 0.60 + pc * 0.026
            P.box((0.012, card_h + 0.006, pz), (0.016, 0.012, 0.022), PLASTIC, M)
            P.box((0.012, card_h + 0.0125, pz), (0.010, 0.001, 0.016), IC, M, bevel=0.0)

    if tier >= 3:
        P.box((0.038, 0.114, 0.06), (0.072, 0.012, 0.058), STEEL)
        P.box((0.038, 0.121, 0.06), (0.050, 0.002, 0.036), LABEL, bevel=0.0)


def build_ram(P, tier):
    spreader_h = 0.036 if tier <= 1 else 0.040
    populated = min(max(2 + tier * 2, 2), 8)
    for i in range(8):
        rx = -0.063 + i * 0.018
        P.box((rx, 0.008, 0.0), (0.009, 0.012, 0.148), PLASTIC)
        mc = T((rx, 0.008, 0.0))
        P.box((0.0, 0.004, -0.078), (0.010, 0.020, 0.008), STEEL, mc, rot=Rx(-12.0))
        P.box((0.0, 0.004, 0.078), (0.010, 0.020, 0.008), STEEL, mc, rot=Rx(12.0))
        if i >= populated:
            continue
        ms = T((rx, 0.034, 0.0))
        P.box((0.0, 0.0, 0.0), (0.0016, 0.044, 0.138), PCB_G, ms, bevel=0.0)
        P.box((0.0, -0.0195, -0.026), (0.0018, 0.005, 0.080), GOLD, ms, bevel=0.0)
        P.box((0.0, -0.0195, 0.042), (0.0018, 0.005, 0.048), GOLD, ms, bevel=0.0)
        if tier == 0:
            for c in range(8):
                cz = -0.056 + c * 0.016
                P.box((0.0014, 0.004, cz), (0.0012, 0.012, 0.011), IC, ms, bevel=0.0)
                P.box((-0.0014, 0.004, cz), (0.0012, 0.012, 0.011), IC, ms, bevel=0.0)
            P.box((0.0015, 0.015, -0.03), (0.0004, 0.008, 0.040), PAPER, ms, bevel=0.0)
        else:
            sm = DARK_AL if tier == 1 else STEEL
            P.box((0.0018, 0.002, 0.0), (0.0012, spreader_h, 0.134), sm, ms, bevel=0.0)
            P.box((-0.0018, 0.002, 0.0), (0.0012, spreader_h, 0.134), sm, ms, bevel=0.0)
            if tier >= 2:
                for r in range(12):
                    P.box((0.0, 0.024, -0.060 + r * 0.011), (0.0048, 0.006 if tier == 2 else 0.010, 0.005), sm, ms, bevel=0.0)
            P.box((0.0025, 0.0, -0.02), (0.0003, 0.014, 0.060), PAPER, ms, bevel=0.0)
            if tier >= 3:
                P.box((0.0, 0.0225, 0.0), (0.0052, 0.003, 0.134), DARK_AL, ms, bevel=0.0)


def build_storage(P, tier):
    drive_count = min(max(1 + tier, 1), 3)
    for i in range(drive_count):
        mz = -0.032 + i * 0.034
        P.box((-0.056, 0.009, mz), (0.014, 0.012, 0.026), PLASTIC)
        P.box((0.002, 0.011, mz), (0.101, 0.0016, 0.022), PCB_B, bevel=0.0)
        P.box((-0.0505, 0.011, mz - 0.004), (0.008, 0.0018, 0.012), GOLD, bevel=0.0)
        P.box((-0.0505, 0.011, mz + 0.0075), (0.008, 0.0018, 0.005), GOLD, bevel=0.0)
        P.cyl((0.050, 0.008, mz), 0.004, 0.006, STEEL, seg=12)
        P.cyl((0.050, 0.0125, mz), 0.0035, 0.002, STEEL, seg=12)
        if tier >= 2:
            sink = CUFIN if tier >= 3 else ALU
            fin_h = 0.008 if tier >= 3 else 0.006
            P.box((0.004, 0.0135, mz), (0.088, 0.0034, 0.023), sink, bevel=0.0)
            P.fins((0.004, 0.0152 + fin_h * 0.5, mz), (0.088, fin_h, 0.023), 5, 2, sink)
        else:
            P.box((-0.030, 0.0125, mz), (0.014, 0.0016, 0.014), STEEL, bevel=0.0)
            P.box((-0.014, 0.0125, mz), (0.008, 0.0014, 0.010), IC, bevel=0.0)
            P.box((0.008, 0.0128, mz), (0.022, 0.002, 0.017), IC, bevel=0.0)
            P.box((0.034, 0.0128, mz), (0.020, 0.002, 0.017), IC, bevel=0.0)
            P.box((0.014, 0.0142, mz), (0.050, 0.0004, 0.016), PAPER, bevel=0.0)


def build_cooling(P, tier):
    fan_count = min(max(3 + tier, 3), 5)
    spacing = 0.115
    start_x = -(fan_count - 1) * spacing * 0.5
    for i in range(fan_count):
        fan_pos = Vector((start_x + i * spacing, 0.048, 0.0))
        M = T(fan_pos)
        # Rahmen und Motorstreben
        P.box((0.0, 0.042, 0.0), (0.095, 0.008, 0.042), PLASTIC, M)
        P.box((0.0, -0.042, 0.0), (0.095, 0.008, 0.042), PLASTIC, M)
        P.box((-0.0435, 0.0, 0.0), (0.008, 0.076, 0.042), PLASTIC, M)
        P.box((0.0435, 0.0, 0.0), (0.008, 0.076, 0.042), PLASTIC, M)
        P.box((0.0, 0.0, -0.018), (0.110, 0.004, 0.004), PLASTIC, M, rot=Rz(45.0), bevel=0.0)
        P.box((0.0, 0.0, -0.018), (0.110, 0.004, 0.004), PLASTIC, M, rot=Rz(-45.0), bevel=0.0)
        # Fingerschutz, Eckschrauben und Griff
        for gy in (-0.020, 0.0, 0.020):
            P.box((0.0, gy, 0.0215), (0.080, 0.0016, 0.0016), STEEL, M, bevel=0.0)
        P.box((0.0, 0.0, 0.0215), (0.0016, 0.078, 0.0016), STEEL, M, bevel=0.0)
        P.box((0.0, 0.049, 0.012), (0.030, 0.004, 0.008), STEEL, M, bevel=0.0)
        for sx in (-0.040, 0.040):
            for sy in (-0.039, 0.039):
                P.cyl((sx, sy, 0.0215), 0.0028, 0.002, STEEL, M, axis="z", seg=10)
        P.cyl((0.0, 0.0, -0.019), 0.040, 0.002, SHADE, M, axis="z", seg=24)
        P.cyl((0.0, 0.0, -0.010), 0.013, 0.014, PLASTIC, M, axis="z", seg=16)
        key = "Rotor_Z_%d" % i
        origin = fan_pos + Vector((0.0, 0.0, 0.006))
        P.new_group(key, origin)
        P.blades(T(origin), 0.037, 7, BLADE_FAN, STEEL, group=key)

    if tier >= 3:
        P.fins((0.0, 0.048, -0.034), (0.56, 0.080, 0.024), 70, 0, CUFIN)
        P.box((0.0, 0.090, -0.034), (0.56, 0.004, 0.026), COPPER, bevel=0.0)
        P.box((0.0, 0.006, -0.034), (0.56, 0.004, 0.026), COPPER, bevel=0.0)
        P.box((-0.288, 0.048, -0.034), (0.016, 0.092, 0.030), PLASTIC)
        P.box((0.288, 0.048, -0.034), (0.016, 0.092, 0.030), PLASTIC)
        P.cyl((-0.08, 0.096, -0.11), 0.009, 0.18, PLASTIC, axis="z")
        P.cyl((-0.05, 0.096, -0.11), 0.009, 0.18, PLASTIC, axis="z")
        P.cyl((-0.08, 0.096, -0.03), 0.011, 0.014, COPPER)
        P.cyl((-0.05, 0.096, -0.03), 0.011, 0.014, COPPER)


def _psu_module(P, offset, size, hot_swap):
    off = Vector(offset)
    half = Vector(size) * 0.5
    cy = 0.048
    P.box(off + Vector((0.0, cy, 0.0)), size, STEEL, bevel=0.002)
    P.box(off + Vector((0.0, cy + half.y + 0.0015, 0.02)), (size[0] - 0.010, 0.003, size[2] * 0.70), PERF, bevel=0.0)
    P.box(off + Vector((half.x + 0.0005, cy, 0.03)), (0.001, size[1] * 0.5, size[2] * 0.35), PAPER, bevel=0.0)

    rear = off + Vector((0.0, 0.0, -half.z))
    fan_r = min(size[0], size[1]) * 0.36
    fan_c = rear + Vector((0.0, cy + size[1] * 0.12, -0.001))
    P.cyl(fan_c, fan_r + 0.002, 0.002, SHADE, axis="z", seg=24)
    P.blades(T(fan_c + Vector((0.0, 0.0, -0.004))), fan_r, 7, BLADE_FAN, STEEL)
    gc = fan_c + Vector((0.0, 0.0, -0.010))
    for g in range(3):
        P.box(gc + Vector((0.0, (g - 1.0) * fan_r * 0.55, 0.0)), (fan_r * 2.0, 0.0016, 0.0016), STEEL, bevel=0.0)
    P.box(gc, (0.0016, fan_r * 2.0, 0.0016), STEEL, bevel=0.0)

    if hot_swap:
        hp = rear + Vector((0.0, 0.010, 0.0))
        P.box(hp + Vector((-0.022, 0.0, -0.008)), (0.005, 0.006, 0.016), STEEL, bevel=0.0)
        P.box(hp + Vector((0.022, 0.0, -0.008)), (0.005, 0.006, 0.016), STEEL, bevel=0.0)
        P.box(hp + Vector((0.0, 0.0, -0.0165)), (0.050, 0.006, 0.005), STEEL, bevel=0.0)
        P.box(rear + Vector((-0.012, 0.024, -0.003)), (0.018, 0.014, 0.006), PLASTIC, bevel=0.0)
        P.box(rear + Vector((0.018, 0.024, -0.003)), (0.010, 0.012, 0.006), HANDLE_GREEN, bevel=0.0)
    else:
        P.box(rear + Vector((-0.048, 0.020, -0.003)), (0.022, 0.016, 0.006), PLASTIC, bevel=0.0)
        P.box(rear + Vector((-0.048, 0.050, -0.003)), (0.010, 0.014, 0.006), PLASTIC, bevel=0.0)


def build_psu(P, tier):
    if tier >= 2:
        for u in range(2):
            _psu_module(P, (-0.034 + u * 0.068, 0.0, 0.0), (0.060, 0.094, 0.32), True)
        P.box((0.0, 0.048, 0.166), (0.130, 0.080, 0.010), PCB_G)
    else:
        _psu_module(P, (0.0, 0.0, 0.0), (0.125, 0.092, 0.30), False)
    P.cyl((-0.04, 0.032, 0.165), 0.010, 0.08, PLASTIC, axis="z")
    P.cyl((-0.02, 0.038, 0.165), 0.008, 0.08, COPPER, axis="z")
    P.box((-0.03, 0.035, 0.208), (0.034, 0.016, 0.012), PLASTIC)


# ---------------------------------------------------------------- Ablauf


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv:
        out_dir = os.path.abspath(argv[0])
    else:
        out_dir = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "models"))
    os.makedirs(out_dir, exist_ok=True)

    jobs = [("part_mainboard", lambda P: build_mainboard(P, PCB_G)), ("part_mainboard_ai", lambda P: build_mainboard(P, PCB_B))]
    builders = [("cpu", build_cpu), ("ram", build_ram), ("gpu", build_gpu), ("storage", build_storage), ("cooling", build_cooling), ("psu", build_psu)]
    for cat, fn in builders:
        for tier in range(4):
            jobs.append(("part_%s_t%d" % (cat, tier), lambda P, fn=fn, tier=tier: fn(P, tier)))

    for name, build in jobs:
        clear_scene()
        part = Part()
        build(part)
        rotors = len(part.order) - 1
        faces = part.export(os.path.join(out_dir, name + ".glb"))
        print("PART %s: %d Flaechen, %d Rotoren" % (name, faces, rotors))
    print("PARTS DONE: %d Dateien in %s" % (len(jobs), out_dir))


try:
    main()
except Exception:
    traceback.print_exc()
    sys.exit(1)