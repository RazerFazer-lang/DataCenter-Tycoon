"""AAA Hardware-Modell-Generator fuer DataCenter Tycoon (Blender 5.2+ -> .glb mit gepackten PBR-Texturen).

Aufruf (Hintergrundmodus):
    blender --background --factory-startup --python-exit-code 1 \
        --python tools/blender/build_hardware_parts.py -- assets/models

Erzeugt alle 34 Bauteile (Mainboards, CPU/RAM/GPU/Storage/Cooling/PSU t0..3, Chassis 4/8-Bay/Switch,
LFF/SFF-Caddies & Blanks, ESD-Reparaturwerkbank) mit echten 2K-PBR-Texturen (Albedo, Normal, ORM),
sauberer Innenverkabelung (24-Pin ATX, 8-Pin EPS, Mini-SAS HD, PWM), duennem gekantetem Serverblech,
echten Rueckwand-I/O-Ausschnitten und 100% Kompatibilitaet zu HardwareMeshFactory (Slot-Ursprung,
AABB-Hover-Picking und drehende Rotor_Z_*/Rotor_X_* Lueftergruppen).
"""

import math
import os
import sys
import traceback

import bmesh
import bpy
from mathutils import Matrix, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import pbr_textures

# Godot (x, y, z) -> Blender (x, -z, y). Der glTF-Export mit +Y oben rechnet das exakt zurueck.
C = Matrix(((1.0, 0.0, 0.0, 0.0), (0.0, 0.0, -1.0, 0.0), (0.0, 1.0, 0.0, 0.0), (0.0, 0.0, 0.0, 1.0)))
I4 = Matrix.Identity(4)
BEVEL = 0.0010

# ---------------------------------------------------------------------------
# Material-Namen (PBR_* wird von Godot direkt mit gepackten Texturen uebernommen,
# nicht von MatLib/PART_MODEL_DCX_MATS ueberschrieben!)
# ---------------------------------------------------------------------------
M_MB_GREEN = "PBR_mb_green"
M_MB_BLACK = "PBR_mb_black"
M_MB_GREEN_BRK = "PBR_mb_green_broken"
M_MB_BLACK_BRK = "PBR_mb_black_broken"
M_BURN = "PBR_burn_char"
M_SCORCH = "PBR_scorch_metal"
M_BACKPLANE = "PBR_backplane"
M_PCB_EDGE = "PBR_pcb_edge"
M_PCB_SUB_G = "PBR_pcb_sub_green"
M_PCB_SUB_B = "PBR_pcb_sub_black"

M_STEEL = "PBR_steel_brushed"
M_DARK_STEEL = "PBR_dark_anodized"
M_GUNMETAL = "PBR_gunmetal"
M_ALU = "PBR_alu_brushed"
M_COPPER = "PBR_copper_brushed"
M_GOLD = "PBR_gold_metal"
M_CHROME = "PBR_chrome"
M_HONEY_STEEL = "PBR_honeycomb_steel"
M_HONEY_DARK = "PBR_honeycomb_dark"

M_PSU_LBL_STD = "PBR_psu_label_std"
M_PSU_LBL_PRO = "PBR_psu_label_pro"
M_CPU_IHS = "PBR_cpu_ihs"
M_RAM_LBL = "PBR_ram_label"
M_NVME_LBL = "PBR_nvme_label"
M_GPU_LBL = "PBR_gpu_label"

M_ESD_MAT = "PBR_esd_mat"
M_WORKBENCH = "PBR_workbench_top"
M_CABLE = "PBR_cable_sleeve"

M_PLASTIC = "PBR_plastic_matte"
M_PLASTIC_GREY = "PBR_plastic_grey"
M_CAVITY = "PBR_cavity_black"
M_IC = "PBR_ic_package"
M_FERRITE = "PBR_ferrite_choke"
M_RUBBER = "PBR_rubber_matte"
M_EDGE_TRIM = "PBR_edge_trim"
M_GRIP_RED = "PBR_grip_red"
M_LATCH_GREEN = "PBR_latch_green"
M_USB_BLUE = "PBR_usb_blue"
M_VGA_BLUE = "PBR_vga_blue"
M_CAP_BLUE = "PBR_cap_blue"
M_PAPER = "PBR_paper_tag"
M_BLADE_FAN = "PBR_blade_fan"
M_BLADE_GPU = "PBR_blade_gpu"
M_LED_GREEN = "PBR_led_green"
M_LED_BLUE = "PBR_led_blue"
M_LED_AMBER = "PBR_led_amber"
M_SYRINGE = "PBR_syringe_body"

# Textur-Zuordnung (name -> (tex_key, clearcoat_weight, normal_strength))
TEXTURED_MATS = {
    M_MB_GREEN: ("mb_green", 0.0, 1.0),
    M_MB_BLACK: ("mb_black", 0.0, 1.0),
    M_MB_GREEN_BRK: ("mb_green_broken", 0.0, 1.0),
    M_MB_BLACK_BRK: ("mb_black_broken", 0.0, 1.0),
    M_BURN: ("burn_char", 0.0, 1.1),
    M_SCORCH: ("scorch_metal", 0.0, 0.9),
    M_BACKPLANE: ("backplane", 0.0, 1.0),
    M_STEEL: ("steel_brushed", 0.0, 0.75),
    M_DARK_STEEL: ("dark_anodized", 0.0, 0.70),
    M_GUNMETAL: ("gunmetal", 0.0, 0.75),
    M_ALU: ("alu_brushed", 0.0, 0.65),
    M_COPPER: ("copper_brushed", 0.0, 0.65),
    M_GOLD: ("gold_metal", 0.0, 0.45),
    M_HONEY_STEEL: ("honeycomb_steel", 0.0, 1.25),
    M_HONEY_DARK: ("honeycomb_dark", 0.0, 1.25),
    M_PSU_LBL_STD: ("psu_label_std", 0.08, 0.3),
    M_PSU_LBL_PRO: ("psu_label_pro", 0.08, 0.3),
    M_ESD_MAT: ("esd_mat", 0.0, 0.90),
    M_WORKBENCH: ("workbench_top", 0.05, 0.75),
    M_CABLE: ("cable_sleeve", 0.0, 1.15),
    M_CPU_IHS: ("cpu_ihs", 0.0, 0.65),
    M_RAM_LBL: ("ram_label", 0.05, 0.2),
    M_NVME_LBL: ("nvme_label", 0.08, 0.2),
    M_GPU_LBL: ("gpu_label", 0.12, 0.2),
}

# Reine PBR-Materialien: (sRGB, metallic, roughness, clearcoat, emission_strength)
SOLID_MATS = {
    M_PCB_EDGE: ((0.14, 0.24, 0.14), 0.02, 0.68, 0.0, 0.0),
    M_PCB_SUB_G: ((0.055, 0.23, 0.12), 0.06, 0.34, 0.25, 0.0),
    M_PCB_SUB_B: ((0.045, 0.048, 0.056), 0.06, 0.38, 0.20, 0.0),
    M_CHROME: ((0.88, 0.89, 0.91), 0.98, 0.14, 0.0, 0.0),
    M_PLASTIC: ((0.055, 0.058, 0.064), 0.0, 0.48, 0.05, 0.0),
    M_PLASTIC_GREY: ((0.44, 0.46, 0.49), 0.0, 0.52, 0.0, 0.0),
    M_CAVITY: ((0.015, 0.016, 0.019), 0.0, 0.94, 0.0, 0.0),
    M_IC: ((0.062, 0.064, 0.070), 0.04, 0.42, 0.0, 0.0),
    M_FERRITE: ((0.16, 0.165, 0.175), 0.22, 0.58, 0.0, 0.0),
    M_RUBBER: ((0.038, 0.040, 0.045), 0.0, 0.88, 0.0, 0.0),
    M_EDGE_TRIM: ((0.12, 0.13, 0.145), 0.15, 0.42, 0.0, 0.0),
    M_GRIP_RED: ((0.64, 0.085, 0.075), 0.0, 0.44, 0.08, 0.0),
    M_LATCH_GREEN: ((0.16, 0.56, 0.30), 0.08, 0.38, 0.08, 0.0),
    M_USB_BLUE: ((0.06, 0.30, 0.72), 0.0, 0.40, 0.10, 0.0),
    M_VGA_BLUE: ((0.08, 0.24, 0.58), 0.0, 0.45, 0.0, 0.0),
    M_CAP_BLUE: ((0.09, 0.24, 0.48), 0.15, 0.32, 0.20, 0.0),
    M_PAPER: ((0.88, 0.89, 0.90), 0.0, 0.72, 0.0, 0.0),
    M_BLADE_FAN: ((0.10, 0.105, 0.115), 0.08, 0.46, 0.05, 0.0),
    M_BLADE_GPU: ((0.13, 0.14, 0.155), 0.12, 0.42, 0.05, 0.0),
    M_LED_GREEN: ((0.18, 0.98, 0.42), 0.0, 0.22, 0.2, 2.4),
    M_LED_BLUE: ((0.22, 0.58, 1.00), 0.0, 0.22, 0.2, 2.0),
    M_LED_AMBER: ((1.00, 0.62, 0.12), 0.0, 0.22, 0.2, 1.8),
    M_SYRINGE: ((0.68, 0.71, 0.75), 0.12, 0.26, 0.35, 0.0),
}

TEX_PATHS = {}


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


def _ensure_gltf_ao_group():
    ng = bpy.data.node_groups.get("glTF Material Output")
    if ng is not None:
        return ng
    ng = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
    ng.interface.new_socket(name="Occlusion", in_out="INPUT", socket_type="NodeSocketFloat")
    return ng


def _load_image(path: str, colorspace: str):
    key = os.path.basename(path)
    img = bpy.data.images.get(key)
    if img is None:
        img = bpy.data.images.load(path)
        img.name = key
    img.colorspace_settings.name = colorspace
    return img


def get_material(name: str):
    mat = bpy.data.materials.get(name)
    if mat is not None:
        return mat

    mat = bpy.data.materials.new(name)
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (450, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])

    if name in TEXTURED_MATS:
        tex_key, coat, norm_str = TEXTURED_MATS[name]
        tp = TEX_PATHS[tex_key]

        n_alb = nt.nodes.new("ShaderNodeTexImage")
        n_alb.image = _load_image(tp["albedo"], "sRGB")
        n_alb.location = (-360, 220)
        nt.links.new(n_alb.outputs["Color"], bsdf.inputs["Base Color"])

        n_orm = nt.nodes.new("ShaderNodeTexImage")
        n_orm.image = _load_image(tp["orm"], "Non-Color")
        n_orm.location = (-360, -40)
        n_sep = nt.nodes.new("ShaderNodeSeparateColor")
        n_sep.location = (-100, -40)
        nt.links.new(n_orm.outputs["Color"], n_sep.inputs["Color"])
        nt.links.new(n_sep.outputs["Green"], bsdf.inputs["Roughness"])
        nt.links.new(n_sep.outputs["Blue"], bsdf.inputs["Metallic"])

        # glTF 2.0 native Occlusion (R-Kanal desselben ORM-Buffers!)
        ao_grp = nt.nodes.new("ShaderNodeGroup")
        ao_grp.node_tree = _ensure_gltf_ao_group()
        ao_grp.location = (120, -240)
        nt.links.new(n_sep.outputs["Red"], ao_grp.inputs["Occlusion"])

        n_nrm = nt.nodes.new("ShaderNodeTexImage")
        n_nrm.image = _load_image(tp["normal"], "Non-Color")
        n_nrm.location = (-360, -320)
        n_nmap = nt.nodes.new("ShaderNodeNormalMap")
        n_nmap.inputs["Strength"].default_value = norm_str
        n_nmap.location = (-100, -320)
        nt.links.new(n_nrm.outputs["Color"], n_nmap.inputs["Color"])
        nt.links.new(n_nmap.outputs["Normal"], bsdf.inputs["Normal"])

        if coat > 0.0 and "Coat Weight" in bsdf.inputs:
            bsdf.inputs["Coat Weight"].default_value = coat
            bsdf.inputs["Coat Roughness"].default_value = 0.20
        return mat

    col, metal, rough, coat, emit = SOLID_MATS[name]
    lin = tuple(srgb_to_linear(c) for c in col)
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Metallic"].default_value = metal
    bsdf.inputs["Roughness"].default_value = rough
    if coat > 0.0 and "Coat Weight" in bsdf.inputs:
        bsdf.inputs["Coat Weight"].default_value = coat
        bsdf.inputs["Coat Roughness"].default_value = 0.22
    if emit > 0.0:
        bsdf.inputs["Emission Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    mat.diffuse_color = (*lin, 1.0)
    mat.metallic = metal
    mat.roughness = rough
    return mat


# ---------------------------------------------------------------------------
# UV-Projektionen & Geometrie-Sammler (Part)
# ---------------------------------------------------------------------------

def _apply_box_uv(bm, scale: float):
    """Metrische Triplanar-Box-UVs: verhindert jegliches Verzerren von Waben & Buerstmetall."""
    uv = bm.loops.layers.uv.verify()
    inv = 1.0 / max(scale, 1e-5)
    for f in bm.faces:
        n = f.normal
        ax, ay, az = abs(n.x), abs(n.y), abs(n.z)
        for loop in f.loops:
            co = loop.vert.co
            if ay >= ax and ay >= az:
                loop[uv].uv = (co.x * inv, -co.z * inv)
            elif ax >= ay and ax >= az:
                loop[uv].uv = (co.z * inv, co.y * inv)
            else:
                loop[uv].uv = (co.x * inv, co.y * inv)


def _planar_uvs(t, uv, scale):
    inv = 1.0 / max(scale, 1e-5)
    for f in t.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uv].uv = (co.x * inv + 0.5, co.y * inv + 0.5)


def _catmull_rom(pts, subdiv: int = 8):
    """Weiche Catmull-Rom-Spline-Interpolation fuer realistisch verlegte Serverkabel."""
    pts = [Vector(p) for p in pts]
    if len(pts) < 2:
        return pts
    if len(pts) == 2:
        return [pts[0].lerp(pts[1], k / float(subdiv)) for k in range(subdiv + 1)]
    ext = [pts[0] + (pts[0] - pts[1])] + pts + [pts[-1] + (pts[-1] - pts[-2])]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        n = subdiv if i < len(ext) - 3 else subdiv + 1
        for k in range(n):
            t = k / float(subdiv)
            t2, t3 = t * t, t * t * t
            pos = 0.5 * (
                (2.0 * p1)
                + (-p0 + p2) * t
                + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
            )
            out.append(pos)
    return out


class Part:
    """Sammelt Geometrie pro Gruppe ('Body', 'Rotor_*', 'Cable_*') mit sauberen UVs."""

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
            if src_uv is not None:
                for src_loop, dst_loop in zip(f.loops, nf.loops):
                    dst_loop[dst_uv].uv = src_loop[src_uv].uv
        t.free()

    def box(self, pos, size, mat, M=None, rot=None, bevel=BEVEL, group="Body",
            uv_scale=0.16, uv_mode="box"):
        t = bmesh.new()
        uv = t.loops.layers.uv.new("UVMap")
        bmesh.ops.create_cube(t, size=1.0, calc_uvs=True)
        sx, sy, sz = size
        for v in t.verts:
            v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
        smallest = min(size)
        if bevel > 0.0 and smallest > 0.0045:
            bmesh.ops.bevel(
                t, geom=list(t.edges),
                offset=min(bevel, smallest * 0.22),
                segments=1, profile=0.5, affect="EDGES", clamp_overlap=True,
            )
        bmesh.ops.recalc_face_normals(t, faces=list(t.faces))
        if uv_mode == "box":
            _apply_box_uv(t, uv_scale if uv_scale else 0.16)
        elif uv_mode == "planar_top":
            # Exakte 0..1 Projektion fuer Oberseite (+Y): x -> u (0..1), z_min(Rear)->v=1, z_max(Front)->v=0
            for f in t.faces:
                for loop in f.loops:
                    co = loop.vert.co
                    u = (co.x / sx) + 0.5
                    v = 0.5 - (co.z / sz)
                    loop[uv].uv = (u, v)
        elif uv_mode == "planar_back_z":
            # Backplane (-Z zeigt zum Mainboard): +X links (u=0), -X rechts (u=1), +Y oben (v=1)
            for f in t.faces:
                for loop in f.loops:
                    co = loop.vert.co
                    u = 0.5 - (co.x / sx)
                    v = (co.y / sy) + 0.5
                    loop[uv].uv = (u, v)
        elif uv_mode == "sticker_x":
            # Aufkleber an Seitenflaeche (+/-X): -Z -> u=0..1, +Y -> v=0..1
            for f in t.faces:
                for loop in f.loops:
                    co = loop.vert.co
                    u = (co.z / sz) + 0.5 if f.normal.x < 0 else 0.5 - (co.z / sz)
                    v = (co.y / sy) + 0.5
                    loop[uv].uv = (u, v)
        elif uv_mode == "sticker_top_x":
            # Aufkleber oben (+Y), lesbar entlang X
            for f in t.faces:
                for loop in f.loops:
                    co = loop.vert.co
                    u = (co.x / sx) + 0.5
                    v = 0.5 - (co.z / sz)
                    loop[uv].uv = (u, v)
        elif uv_mode == "sticker_top_z":
            # Aufkleber oben (+Y), entlang Z gedreht (z.B. Netzteil-Deckel)
            for f in t.faces:
                for loop in f.loops:
                    co = loop.vert.co
                    u = 0.5 - (co.z / sz)
                    v = 0.5 - (co.x / sx)
                    loop[uv].uv = (u, v)
        mg = (M if M is not None else I4) @ T(pos) @ (rot if rot is not None else I4)
        self._add(t, mg, mat, group)

    def pcb_slab(self, pos, size, top_mat, edge_mat=M_PCB_EDGE, M=None, group="Body", uv_mode="planar_top"):
        """Leiterplatte mit eigenem 1:1-UV-Material oben/unten und FR-4-Kantenmaterial an den Seiten."""
        sx, sy, sz = size
        t = bmesh.new()
        uv = t.loops.layers.uv.new("UVMap")
        bmesh.ops.create_cube(t, size=1.0, calc_uvs=True)
        for v in t.verts:
            v.co = Vector((v.co.x * sx, v.co.y * sy, v.co.z * sz))
        bmesh.ops.recalc_face_normals(t, faces=list(t.faces))
        top_bm = bmesh.new()
        top_uv = top_bm.loops.layers.uv.new("UVMap")
        edge_bm = bmesh.new()
        edge_uv = edge_bm.loops.layers.uv.new("UVMap")

        for f in t.faces:
            is_face = abs(f.normal.y) > 0.7 if uv_mode == "planar_top" else abs(f.normal.z) > 0.7
            dst = top_bm if is_face else edge_bm
            duv = top_uv if is_face else edge_uv
            verts = [dst.verts.new(v.co) for v in f.verts]
            nf = dst.faces.new(verts)
            for loop in nf.loops:
                co = loop.vert.co
                if is_face:
                    if uv_mode == "planar_top":
                        loop[duv].uv = ((co.x / sx) + 0.5, 0.5 - (co.z / sz))
                    else:
                        loop[duv].uv = (0.5 - (co.x / sx), (co.y / sy) + 0.5)
                else:
                    loop[duv].uv = ((co.x + co.z) * 4.0, co.y * 4.0)
        t.free()
        mg = (M if M is not None else I4) @ T(pos)
        self._add(top_bm, mg, top_mat, group)
        self._add(edge_bm, mg, edge_mat, group)

    def cyl(self, pos, r, h, mat, M=None, axis="y", seg=18, group="Body", rot=None, r2=None):
        t = bmesh.new()
        t.loops.layers.uv.new("UVMap")
        rad2 = r if r2 is None else r2
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=seg, radius1=r, radius2=rad2, depth=h, calc_uvs=True)
        for v in t.verts:
            v.co = Vector((v.co.x, v.co.z, -v.co.y))
        for f in t.faces:
            f.smooth = len(f.verts) == 4
        if rot is None:
            rot = I4
            if axis == "z":
                rot = Rx(90.0)
            elif axis == "x":
                rot = Rz(90.0)
        mg = (M if M is not None else I4) @ T(pos) @ rot
        self._add(t, mg, mat, group)

    def cable(self, pts, r, mat, M=None, seg=10, subdiv=8, group="Body", uv_pitch=0.024):
        """Kontinuierliches, weich gebogenes Kabel/Rohr via Catmull-Rom + Parallel-Transport-Frames."""
        spine = _catmull_rom(pts, subdiv=subdiv)
        if len(spine) < 2:
            return
        t = bmesh.new()
        uv = t.loops.layers.uv.new("UVMap")

        # Tangenten und glatte Normalen (Bishop-Frame, kein Twist!)
        tangents = []
        for i in range(len(spine)):
            if i == 0:
                d = spine[1] - spine[0]
            elif i == len(spine) - 1:
                d = spine[-1] - spine[-2]
            else:
                d = spine[i + 1] - spine[i - 1]
            tangents.append(d.normalized() if d.length > 1e-7 else Vector((0, 0, 1)))

        ref = Vector((0.0, 1.0, 0.0)) if abs(tangents[0].y) < 0.9 else Vector((1.0, 0.0, 0.0))
        norm = tangents[0].cross(ref).normalized()
        binorm = tangents[0].cross(norm).normalized()

        rings = []
        dists = [0.0]
        for i, p in enumerate(spine):
            if i > 0:
                dists.append(dists[-1] + (spine[i] - spine[i - 1]).length)
                q = tangents[i - 1].rotation_difference(tangents[i])
                norm = (q @ norm).normalized()
                binorm = tangents[i].cross(norm).normalized()
            ring = []
            for k in range(seg):
                a = 2.0 * math.pi * k / seg
                vpos = p + (norm * math.cos(a) + binorm * math.sin(a)) * r
                ring.append(t.verts.new(vpos))
            rings.append(ring)

        for i in range(len(rings) - 1):
            v0 = dists[i] / uv_pitch
            v1 = dists[i + 1] / uv_pitch
            for k in range(seg):
                kn = (k + 1) % seg
                f = t.faces.new((rings[i][k], rings[i][kn], rings[i + 1][kn], rings[i + 1][k]))
                f.smooth = True
                u0 = k / float(seg) * 2.0
                u1 = (k + 1) / float(seg) * 2.0
                f.loops[0][uv].uv = (u0, v0)
                f.loops[1][uv].uv = (u1, v0)
                f.loops[2][uv].uv = (u1, v1)
                f.loops[3][uv].uv = (u0, v1)

        # Endkappen
        t.faces.new(list(reversed(rings[0])))
        t.faces.new(rings[-1])
        bmesh.ops.recalc_face_normals(t, faces=list(t.faces))
        self._add(t, M if M is not None else I4, mat, group)

    def tube(self, pts, r, mat, M=None, seg=10, group="Body"):
        self.cable(pts, r, mat, M=M, seg=seg, subdiv=5, group=group)

    def ring(self, M, r_in, r_out, depth, mat, square=False, seg=32, group="Body"):
        t = bmesh.new()
        uv = t.loops.layers.uv.new("UVMap")
        layers = []
        for z in (depth * 0.5, -depth * 0.5):
            inner, outer = [], []
            for i in range(seg):
                a = 2.0 * math.pi * i / seg
                c, s = math.cos(a), math.sin(a)
                k = r_out / max(abs(c), abs(s)) if square else r_out
                inner.append(t.verts.new((r_in * c, r_in * s, z)))
                outer.append(t.verts.new((k * c, k * s, z)))
            layers.append((inner, outer))
        (fi, fo), (bi, bo) = layers
        for i in range(seg):
            j = (i + 1) % seg
            t.faces.new((fi[i], fo[i], fo[j], fi[j]))
            t.faces.new((bi[j], bo[j], bo[i], bi[i]))
            wall = t.faces.new((fi[j], bi[j], bi[i], fi[i]))
            wall.smooth = True
            outer_wall = t.faces.new((fo[i], bo[i], bo[j], fo[j]))
            outer_wall.smooth = not square
        bmesh.ops.recalc_face_normals(t, faces=list(t.faces))
        _planar_uvs(t, uv, 2.0 * r_out)
        self._add(t, M if M is not None else I4, mat, group)

    def rotor(self, M, radius, count, blade_mat, hub_mat, group="Body",
              hub_ratio=0.36, depth_ratio=0.28, sweep=0.62, cap_mat=M_ALU, skip_blades=()):
        mg = M if M is not None else I4
        hub_r = radius * hub_ratio
        thick = max(radius * 0.036, 0.0007)
        steps = 7
        for i in range(count):
            is_snapped = i in skip_blades
            base = 2.0 * math.pi * i / count
            t = bmesh.new()
            uv = t.loops.layers.uv.new("UVMap")
            lt, tt, lb, tb = [], [], [], []
            for k in range(steps):
                s = k / float(steps - 1)
                eff_s = s * (0.28 if is_snapped else 1.0)
                rr = hub_r * 0.90 + (radius - hub_r * 0.90) * eff_s
                ca = base + sweep * (eff_s ** 1.15)
                half = math.pi / count * (0.82 - 0.16 * eff_s)
                depth = radius * depth_ratio * (1.0 - 0.40 * eff_s)
                for ang, z, top_l, bot_l in ((ca + half, depth * 0.5, lt, lb), (ca - half, -depth * 0.5, tt, tb)):
                    x = rr * math.cos(ang)
                    y = rr * math.sin(ang)
                    top_l.append(t.verts.new((x, y, z + thick * 0.5)))
                    bot_l.append(t.verts.new((x, y, z - thick * 0.5)))
            for k in range(steps - 1):
                for verts in (
                    (lt[k], lt[k + 1], tt[k + 1], tt[k]),
                    (lb[k], tb[k], tb[k + 1], lb[k + 1]),
                    (lt[k], lb[k], lb[k + 1], lt[k + 1]),
                    (tt[k], tt[k + 1], tb[k + 1], tb[k]),
                ):
                    f = t.faces.new(verts)
                    f.smooth = True
            t.faces.new((lt[0], tt[0], tb[0], lb[0]))
            t.faces.new((lt[-1], lb[-1], tb[-1], tt[-1]))
            bmesh.ops.recalc_face_normals(t, faces=list(t.faces))
            _planar_uvs(t, uv, 2.0 * radius)
            self._add(t, mg, blade_mat, group)
        hub_h = radius * depth_ratio * 1.18
        self.cyl((0.0, 0.0, 0.0), hub_r, hub_h, hub_mat, mg, axis="z", seg=28, group=group)
        if cap_mat is not None:
            self.cyl((0.0, 0.0, hub_h * 0.5 + 0.0002), hub_r * 0.66, 0.0005, cap_mat, mg, axis="z", seg=24, group=group)

    def fins(self, center, size, count, axis, mat, M=None, group="Body", fill_ratio=0.42):
        n = max(count, 1)
        span = size[axis]
        pitch = span / float(n)
        fin_size = list(size)
        fin_size[axis] = pitch * fill_ratio
        for i in range(n):
            off = [0.0, 0.0, 0.0]
            off[axis] = -span * 0.5 + (i + 0.5) * pitch
            self.box(Vector(center) + Vector(off), fin_size, mat, M, bevel=0.0, group=group, uv_scale=0.14)

    def screw_head(self, pos, r=0.0038, h=0.0022, mat=M_CHROME, M=None, axis="y", group="Body"):
        """Detailreiche Kreuzschlitz-/Torx-Schraube."""
        self.cyl(pos, r, h, mat, M, axis=axis, seg=14, group=group)
        d = h * 0.52
        slot_l = r * 1.15
        slot_w = r * 0.28
        if axis == "y":
            p = (pos[0], pos[1] + d, pos[2])
            self.box(p, (slot_l, 0.0005, slot_w), M_CAVITY, M, bevel=0.0, group=group)
            self.box(p, (slot_w, 0.0005, slot_l), M_CAVITY, M, bevel=0.0, group=group)
        elif axis == "z":
            p = (pos[0], pos[1], pos[2] + d)
            self.box(p, (slot_l, slot_w, 0.0005), M_CAVITY, M, bevel=0.0, group=group)
            self.box(p, (slot_w, slot_l, 0.0005), M_CAVITY, M, bevel=0.0, group=group)

    def export(self, path):
        faces = 0
        for key in self.order:
            g = self.groups[key]
            bm = g["bm"]
            faces += len(bm.faces)
            if len(bm.faces) == 0:
                bm.free()
                continue
            ngons = [f for f in bm.faces if len(f.verts) > 4]
            if ngons:
                bmesh.ops.triangulate(bm, faces=ngons)
            me = bpy.data.meshes.new(key)
            bm.to_mesh(me)
            bm.free()
            for name in g["mats"]:
                me.materials.append(get_material(name))
            ob = bpy.data.objects.new(key, me)
            ob.location = C @ g["origin"]
            bpy.context.scene.collection.objects.link(ob)
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            export_yup=True,
            export_apply=True,
            export_normals=True,
            export_tangents=True,
        )
        return faces


# ---------------------------------------------------------------------------
# 1. Server-Mainboard (2K PBR PCB + CNC VRM + Solid Caps + Rear I/O + Standoffs)
# ---------------------------------------------------------------------------

def build_mainboard(P: Part, pcb_mat: str):
    """Server-Mainboard (x -0.29..0.25, z -0.24..0.24, Oberseite y = 0.006).
    Frei bleiben die Steckzonen fuer CPU, RAM, GPU und M.2 in HardwareMeshFactory."""
    # Echte 3.6 mm FR-4 Platine auf 8 Messing-Abstandshaltern (y -0.006..0.0024)
    P.pcb_slab((-0.02, 0.0042, 0.0), (0.54, 0.0036, 0.48), pcb_mat, M_PCB_EDGE)
    top = 0.0060

    # 8 Messing-Abstandshalter + Edelstahl-Schrauben
    for sx in (-0.275, -0.020, 0.235):
        for sz in (-0.225, 0.0, 0.225):
            if sx == -0.020 and sz == 0.0:
                continue
            P.cyl((sx, -0.0018, sz), 0.0042, 0.0084, M_GOLD, seg=6)
            P.screw_head((sx, top + 0.0012, sz), r=0.0044, h=0.0024, mat=M_CHROME)

    # Rueckwand-I/O-Turm (hinten = -Z): VGA blau, 2x Doppel-USB3 (blau), 3x GbE RJ45 + IPMI mit LEDs
    rz = -0.224
    # VGA D-Sub blau mit Sechskant-Bolzen
    P.box((-0.256, top + 0.008, rz + 0.004), (0.036, 0.016, 0.020), M_STEEL)
    P.box((-0.256, top + 0.008, rz - 0.007), (0.024, 0.010, 0.004), M_VGA_BLUE, bevel=0.0)
    P.box((-0.256, top + 0.008, rz - 0.0092), (0.017, 0.006, 0.0008), M_CAVITY, bevel=0.0)
    for ox in (-0.0145, 0.0145):
        P.cyl((-0.256 + ox, top + 0.008, rz - 0.0075), 0.0022, 0.005, M_CHROME, axis="z", seg=6)
    # 2x gestapelter Doppel-USB-3.0-Kaefig
    for ux in (-0.214, -0.190):
        P.box((ux, top + 0.011, rz), (0.018, 0.022, 0.024), M_STEEL)
        for uy in (0.006, 0.0155):
            P.box((ux, top + uy, rz - 0.0122), (0.0135, 0.0056, 0.0008), M_CAVITY, bevel=0.0)
            P.box((ux, top + uy - 0.0012, rz - 0.0126), (0.0115, 0.0018, 0.0012), M_USB_BLUE, bevel=0.0)
    # 4x RJ45-Netzwerkkaefig (3x 10GbE + 1x IPMI Management) mit Link/Act-LEDs
    for idx, jx in enumerate((-0.158, -0.132, -0.106, -0.070)):
        P.box((jx, top + 0.012, rz), (0.021, 0.024, 0.026), M_STEEL)
        P.box((jx, top + 0.0105, rz - 0.0132), (0.014, 0.012, 0.0008), M_CAVITY, bevel=0.0)
        P.box((jx, top + 0.0055, rz - 0.0133), (0.008, 0.0022, 0.0006), M_GOLD, bevel=0.0)
        P.box((jx - 0.0065, top + 0.0195, rz - 0.0132), (0.0032, 0.0024, 0.0008), M_LED_GREEN, bevel=0.0)
        P.box((jx + 0.0065, top + 0.0195, rz - 0.0132), (0.0032, 0.0024, 0.0008),
              M_LED_AMBER if idx < 3 else M_LED_BLUE, bevel=0.0)

    # 16-Phasen-VRM: gefraester dunkel-eloxierter CNC-Kuehlkoerper (saubere breite Rippen, kein Aliasing!)
    vx, vz = -0.065, -0.140
    P.box((vx, top + 0.0045, vz), (0.106, 0.009, 0.032), M_DARK_STEEL, bevel=0.0014)
    P.fins((vx, top + 0.0175, vz), (0.104, 0.018, 0.030), 10, 0, M_DARK_STEEL, fill_ratio=0.48)
    # Gebuerstete Alu-Zierleiste & Haltestifte oben auf dem VRM-Kuehler
    P.box((vx, top + 0.0270, vz), (0.104, 0.0014, 0.008), M_ALU, bevel=0.0)
    for sx in (vx - 0.044, vx + 0.044):
        P.cyl((sx, top + 0.0278, vz), 0.0026, 0.0018, M_CHROME, seg=12)

    # DrMOS-MOSFETs & Ferrit-Leistungsdrosseln vor dem VRM
    for m in range(8):
        mx = -0.108 + m * 0.0124
        P.box((mx, top + 0.0011, -0.119), (0.0075, 0.0022, 0.0070), M_IC, bevel=0.0)
    for c in range(7):
        cx = -0.107 + c * 0.0142
        P.box((cx, top + 0.0052, -0.103), (0.0108, 0.0104, 0.0108), M_FERRITE, bevel=0.0012)
        P.box((cx, top + 0.0106, -0.103), (0.0068, 0.0004, 0.0042), M_ALU, bevel=0.0)

    # 7 Enterprise-Feststoff-Kondensatoren (Alu-Becher + blauer Polaritaetsstreifen + Entlastungskreuz)
    for c in range(7):
        cx = -0.114 + c * 0.0165
        cz = -0.175
        P.cyl((cx, top + 0.0075, cz), 0.0046, 0.015, M_ALU, seg=18)
        P.cyl((cx, top + 0.0152, cz), 0.0043, 0.0005, M_CHROME, seg=18)
        P.box((cx, top + 0.0154, cz - 0.0022), (0.0062, 0.0005, 0.0028), M_CAP_BLUE, bevel=0.0)
        P.cyl((cx, top + 0.0008, cz), 0.0050, 0.0016, M_PLASTIC, seg=18)

    # 8-Pin-EPS-CPU-Stromanschluss (wird vom PSU-EPS-Kabel angesteckt!)
    P.box((0.000, top + 0.0075, -0.162), (0.023, 0.015, 0.013), M_PLASTIC, bevel=0.0008)
    for px in range(4):
        for pz in range(2):
            P.box((-0.0075 + px * 0.005, top + 0.0152, -0.1645 + pz * 0.005), (0.0034, 0.0006, 0.0034), M_CAVITY, bevel=0.0)

    # Management-Controller (ASPEED BMC), Quarz-Oszillator & BIOS-SPI-Flash
    P.box((0.192, top + 0.0018, -0.040), (0.024, 0.0036, 0.024), M_IC, bevel=0.0005)
    P.box((0.192, top + 0.0038, -0.043), (0.012, 0.0003, 0.005), M_PAPER, bevel=0.0)
    P.box((0.192, top + 0.0014, -0.074), (0.010, 0.0028, 0.007), M_IC, bevel=0.0)
    P.box((0.172, top + 0.0016, -0.068), (0.008, 0.0032, 0.004), M_CHROME, bevel=0.0004)  # Quarz

    # CMOS-CR2032-Knopfzelle im tiefen Halter mit Edelstahl-Federbuegel
    P.cyl((0.192, top + 0.0026, -0.140), 0.0178, 0.0052, M_PLASTIC, seg=28)
    P.cyl((0.192, top + 0.0042, -0.140), 0.0146, 0.0034, M_CHROME, seg=28)
    P.box((0.192, top + 0.0066, -0.153), (0.011, 0.0014, 0.007), M_STEEL, bevel=0.0)
    P.box((0.192, top + 0.0064, -0.126), (0.008, 0.0012, 0.004), M_CHROME, bevel=0.0)

    # 24-Pin-ATX-Hauptstromanschluss am rechten Rand (x = 0.235, z = -0.060)
    P.box((0.235, top + 0.0085, -0.060), (0.018, 0.017, 0.092), M_PLASTIC, bevel=0.0008)
    for pz in range(12):
        for px in range(2):
            P.box((0.2305 + px * 0.009, top + 0.0172, -0.0995 + pz * 0.007), (0.0046, 0.0006, 0.0046), M_CAVITY, bevel=0.0)
    # Verriegelungsnase aussen
    P.box((0.245, top + 0.0095, -0.060), (0.0022, 0.006, 0.016), M_PLASTIC, bevel=0.0)

    # Chipsatz (PCH C741) mit CNC-gefraestem Gunmetal-Kuehlkoerper & Silber-Plakette
    P.box((0.190, top + 0.0040, 0.080), (0.052, 0.008, 0.052), M_GUNMETAL, bevel=0.0014)
    P.fins((0.190, top + 0.0120, 0.080), (0.048, 0.009, 0.048), 7, 0, M_GUNMETAL, fill_ratio=0.52)
    P.box((0.190, top + 0.0170, 0.080), (0.022, 0.0012, 0.016), M_ALU, bevel=0.0004)
    for dx, dz in ((-0.021, -0.021), (0.021, 0.021)):
        P.cyl((0.190 + dx, top + 0.013, 0.080 + dz), 0.0025, 0.008, M_CHROME, seg=10)

    # 4x gewinkelte Enterprise-SATA-Ports am rechten Rand + gruene Standby-Board-LED
    for s in range(4):
        sz = 0.135 + s * 0.020
        P.box((0.236, top + 0.0060, sz), (0.018, 0.012, 0.012), M_PLASTIC, bevel=0.0006)
        P.box((0.2452, top + 0.0062, sz), (0.0008, 0.0055, 0.008), M_CAVITY, bevel=0.0)
    P.box((0.226, top + 0.0014, 0.214), (0.004, 0.0028, 0.004), M_LED_GREEN, bevel=0.0)

    # Stahlverstaerkter PCIe-x8-Steckplatz (PCIe Steel Armor!) links aussen
    P.box((-0.266, top + 0.0060, 0.065), (0.0115, 0.012, 0.098), M_PLASTIC, bevel=0.0006)
    for sx in (-0.0060, 0.0060):
        P.box((-0.266 + sx, top + 0.0062, 0.065), (0.0008, 0.0112, 0.098), M_CHROME, bevel=0.0)
    P.box((-0.266, top + 0.0122, 0.065), (0.0036, 0.0006, 0.091), M_CAVITY, bevel=0.0)
    P.box((-0.266, top + 0.0080, 0.118), (0.0095, 0.015, 0.008), M_PLASTIC_GREY, bevel=0.0006)

    # 4-Pin-PWM-Luefter-Header & Front-Panel-Stiftleiste an der Vorderkante
    for hx in (-0.250, -0.150, 0.125):
        P.box((hx, top + 0.0045, 0.218), (0.012, 0.009, 0.0055), M_PLASTIC, bevel=0.0)
        P.box((hx, top + 0.0085, 0.2155), (0.009, 0.005, 0.0014), M_PLASTIC, bevel=0.0)
        for p in range(4):
            P.box((hx - 0.0039 + p * 0.0026, top + 0.0098, 0.2185), (0.0008, 0.0036, 0.0008), M_GOLD, bevel=0.0)
    P.box((0.175, top + 0.0014, 0.215), (0.028, 0.0028, 0.0085), M_PLASTIC, bevel=0.0)
    for p in range(9):
        for r in range(2):
            P.box((0.1646 + p * 0.0026, top + 0.0048, 0.2137 + r * 0.0026), (0.0008, 0.0052, 0.0008), M_GOLD, bevel=0.0)

    # Super-I/O QFP-Chip, Taktgeber & dichte SMD-Bestueckung in freien Zonen
    P.box((0.100, top + 0.0024, -0.205), (0.026, 0.0048, 0.026), M_IC, bevel=0.0004)
    P.box((0.100, top + 0.0050, -0.205), (0.010, 0.0003, 0.005), M_PAPER, bevel=0.0)
    for k in range(7):
        off = -0.009 + k * 0.003
        for s in (-0.0138, 0.0138):
            P.box((0.100 + off, top + 0.0007, -0.205 + s), (0.0010, 0.0014, 0.0016), M_CHROME, bevel=0.0)
            P.box((0.100 + s, top + 0.0007, -0.205 + off), (0.0016, 0.0014, 0.0010), M_CHROME, bevel=0.0)

    P.box((-0.200, top + 0.0020, -0.170), (0.018, 0.0040, 0.018), M_IC, bevel=0.0004)
    for k in range(5):
        off = -0.007 + k * 0.0035
        P.box((-0.200 + off, top + 0.0007, -0.180), (0.0012, 0.0014, 0.0016), M_GOLD, bevel=0.0)
        P.box((-0.200 + off, top + 0.0007, -0.160), (0.0012, 0.0014, 0.0016), M_GOLD, bevel=0.0)

    # SMD-Kondensator- & Widerstands-Cluster
    for i in range(10):
        P.box((-0.115 + i * 0.025, top + 0.0007, 0.072), (0.0042, 0.0014, 0.0022), M_IC, bevel=0.0)
        P.box((-0.108 + i * 0.025, top + 0.0007, 0.078), (0.0022, 0.0014, 0.0042), M_CAP_BLUE if i % 3 == 0 else M_GOLD, bevel=0.0)
    for i in range(7):
        P.box((0.009, top + 0.0007, -0.062 + i * 0.017), (0.0030, 0.0014, 0.0045), M_IC, bevel=0.0)
    for c in range(3):
        P.cyl((-0.255 + c * 0.016, top + 0.0055, -0.155), 0.0038, 0.011, M_ALU, seg=14)
        P.box((-0.255 + c * 0.016, top + 0.0112, -0.1565), (0.0052, 0.0004, 0.0022), M_CAP_BLUE, bevel=0.0)

    # LGA4677-Aussenrahmen (ausserhalb der CPU-Zone x -0.13..-0.01, z -0.07..0.05)
    fw, fh = 0.0065, 0.0055
    P.box((-0.1335, top + fh * 0.5, -0.010), (fw, fh, 0.133), M_DARK_STEEL, bevel=0.0006)
    P.box((-0.0065, top + fh * 0.5, -0.010), (fw, fh, 0.133), M_DARK_STEEL, bevel=0.0006)
    P.box((-0.070, top + fh * 0.5, 0.0535), (0.133, fh, fw), M_DARK_STEEL, bevel=0.0006)
    P.box((-0.070, top + fh * 0.5, -0.0735), (0.133, fh, fw), M_DARK_STEEL, bevel=0.0006)


# ---------------------------------------------------------------------------
# 2. CPU + LGA-Sockel + Hochwertige Kuehler (ohne Moire-Flimmern!)
# ---------------------------------------------------------------------------

def _captive_screw(P: Part, x, y, z):
    P.cyl((x, y + 0.0028, z), 0.0028, 0.0056, M_STEEL, seg=12)
    P.screw_head((x, y + 0.0072, z), r=0.0048, h=0.0032, mat=M_DARK_STEEL)


def build_cpu(P: Part, tier: int):
    # LGA-Sockel & ILM-Stahlrahmen
    for sz in (-0.0565, 0.0565):
        P.box((0.0, 0.0026, sz), (0.118, 0.0052, 0.0052), M_DARK_STEEL, bevel=0.0006)
    for sx in (-0.0565, 0.0565):
        P.box((sx, 0.0026, 0.0), (0.0052, 0.0052, 0.108), M_DARK_STEEL, bevel=0.0006)
    P.box((0.0, 0.0035, 0.0), (0.108, 0.0070, 0.108), M_PLASTIC, bevel=0.0008)
    P.box((0.0, 0.0072, 0.0), (0.092, 0.0005, 0.092), M_GOLD, bevel=0.0)

    # CPU-Substrat + SMD + Laser-gravierter Nickel-IHS (PBR_cpu_ihs!)
    P.box((0.0, 0.0084, 0.0), (0.086, 0.0022, 0.086), M_PCB_SUB_G, bevel=0.0)
    for i in range(7):
        o = -0.030 + i * 0.010
        for e in (-0.0405, 0.0405):
            P.box((o, 0.0099, e), (0.0035, 0.0008, 0.0020), M_IC, bevel=0.0)
            P.box((e, 0.0099, o), (0.0020, 0.0008, 0.0035), M_IC, bevel=0.0)
    P.box((0.0, 0.0108, 0.0), (0.075, 0.0026, 0.075), M_ALU, bevel=0.0006)
    P.box((0.0, 0.0136, 0.0), (0.066, 0.0030, 0.066), M_CPU_IHS, bevel=0.0008, uv_mode="planar_top")

    # Halteplatte, Scharnier & Spannhebel
    for sz in (-0.042, 0.042):
        P.box((0.0, 0.0128, sz), (0.100, 0.0018, 0.012), M_STEEL, bevel=0.0)
    for sx in (-0.042, 0.042):
        P.box((sx, 0.0128, 0.0), (0.012, 0.0018, 0.072), M_STEEL, bevel=0.0)
    P.cyl((-0.054, 0.0052, 0.0), 0.0019, 0.100, M_CHROME, axis="z", seg=10)
    P.cable([(0.056, 0.0055, -0.050), (0.056, 0.0055, 0.048), (0.065, 0.0060, 0.056)], 0.0017, M_CHROME, seg=8)
    P.box((0.056, 0.006, -0.054), (0.006, 0.004, 0.006), M_STEEL, bevel=0.0)

    if tier == 0:
        # 1U-Enterprise-Passivkuehler: Kupferkern, 13 kraeftige Alu-Rippen + dunkle obere Abschlussblende (kein Flimmern!)
        P.box((0.0, 0.0168, 0.0), (0.068, 0.0036, 0.068), M_COPPER, bevel=0.0)
        P.box((0.0, 0.0182, 0.0), (0.098, 0.0032, 0.098), M_ALU, bevel=0.0008)
        P.fins((0.0, 0.0290, 0.0), (0.096, 0.0185, 0.078), 13, 0, M_ALU, fill_ratio=0.45)
        # Mittlerer Klemmbuegel in Gunmetal ueber den Rippen
        P.box((0.0, 0.0392, 0.0), (0.100, 0.0024, 0.020), M_GUNMETAL, bevel=0.0006)
        P.box((0.0, 0.0406, 0.0), (0.036, 0.0005, 0.010), M_ALU, bevel=0.0)
        for sx in (-0.041, 0.041):
            for sz in (-0.043, 0.043):
                _captive_screw(P, sx, 0.0195, sz)
    elif tier == 1:
        # 2U-Enterprise-Alu/Kupfer-Kuehler mit 2 eingebetteten Kupfer-Heatpipes & Gunmetal-Top-Plate
        P.box((0.0, 0.0180, 0.0), (0.072, 0.0060, 0.072), M_COPPER, bevel=0.0008)
        P.box((0.0, 0.0235, 0.0), (0.104, 0.0052, 0.104), M_ALU, bevel=0.0010)
        P.fins((0.0, 0.0465, 0.0), (0.102, 0.040, 0.086), 15, 0, M_ALU, fill_ratio=0.44)
        for hx in (-0.026, 0.026):
            P.cable([(hx, 0.021, -0.042), (hx, 0.024, -0.049), (hx, 0.068, -0.049), (hx, 0.070, 0.049), (hx, 0.024, 0.049), (hx, 0.021, 0.042)], 0.0030, M_COPPER, seg=10)
        P.box((0.0, 0.0675, 0.0), (0.104, 0.0026, 0.088), M_DARK_STEEL, bevel=0.0008)
        P.box((0.0, 0.0692, 0.0), (0.048, 0.0006, 0.016), M_ALU, bevel=0.0)
        for sx in (-0.045, 0.045):
            for sz in (-0.048, 0.048):
                _captive_screw(P, sx, 0.0258, sz)
    elif tier == 2:
        # 4-Heatpipe-Enterprise-Turm mit eloxierter Deckplatte & Kupfer-Endkappen
        P.box((0.0, 0.0190, 0.0), (0.074, 0.0080, 0.074), M_COPPER, bevel=0.0010)
        P.box((0.0, 0.0245, 0.0), (0.112, 0.0034, 0.022), M_STEEL, bevel=0.0006)
        for sx in (-0.050, 0.050):
            _captive_screw(P, sx, 0.026, 0.0)
        for hz in (-0.024, -0.008, 0.008, 0.024):
            P.cable(
                [(-0.044, 0.101, hz), (-0.044, 0.032, hz), (-0.032, 0.021, hz), (0.032, 0.021, hz), (0.044, 0.032, hz), (0.044, 0.101, hz)],
                0.0033, M_COPPER, seg=10,
            )
            for hx in (-0.044, 0.044):
                P.cyl((hx, 0.102, hz), 0.0038, 0.0022, M_COPPER, seg=12)
        P.fins((0.0, 0.070, 0.0), (0.110, 0.056, 0.102), 14, 1, M_ALU, fill_ratio=0.42)
        P.box((0.0, 0.100, 0.0), (0.112, 0.0032, 0.104), M_DARK_STEEL, bevel=0.0010)
        P.box((0.0, 0.1018, 0.0), (0.052, 0.0006, 0.020), M_GUNMETAL, bevel=0.0)
    else:
        # Flaggschiff Vapor-Chamber-Kupferkuehler mit 5 Heatpipes & CNC-Spannbruecke
        P.box((0.0, 0.0195, 0.0), (0.112, 0.0085, 0.112), M_COPPER, bevel=0.0012)
        P.fins((0.0, 0.056, 0.0), (0.112, 0.064, 0.098), 18, 0, M_COPPER, fill_ratio=0.44)
        for hx in (-0.040, -0.020, 0.0, 0.020, 0.040):
            P.cable(
                [(hx, 0.021, -0.040), (hx, 0.026, -0.054), (hx, 0.080, -0.054), (hx, 0.086, -0.042),
                 (hx, 0.086, 0.042), (hx, 0.080, 0.054), (hx, 0.026, 0.054), (hx, 0.021, 0.040)],
                0.0035, M_COPPER, seg=10,
            )
        P.box((0.0, 0.0905, 0.0), (0.114, 0.0034, 0.100), M_DARK_STEEL, bevel=0.0010)
        P.box((0.0, 0.0938, 0.0), (0.110, 0.0034, 0.026), M_GUNMETAL, bevel=0.0008)
        P.box((0.0, 0.0958, 0.0), (0.046, 0.0006, 0.014), M_COPPER, bevel=0.0)
        for sx in (-0.050, 0.050):
            for sz in (-0.054, 0.054):
                _captive_screw(P, sx, 0.0235, sz)


# ---------------------------------------------------------------------------
# 3. GPU-Karten (PCIe Steel Armor, CNC Shroud, Heatpipes, Backplate, Rotor_X_*)
# ---------------------------------------------------------------------------

def _pcie_slot(P: Part, x: float, z0=-0.150, z1=0.010):
    zc = (z0 + z1) * 0.5
    ln = z1 - z0
    P.box((x, 0.006, zc), (0.0125, 0.016, ln), M_PLASTIC, bevel=0.0006)
    for sx in (-0.0065, 0.0065):
        P.box((x + sx, 0.0062, zc), (0.0008, 0.0148, ln), M_CHROME, bevel=0.0)
    P.box((x, 0.0142, zc), (0.0038, 0.0006, ln - 0.006), M_CAVITY, bevel=0.0)
    P.box((x, 0.0075, z1 + 0.0055), (0.012, 0.018, 0.0065), M_PLASTIC_GREY, bevel=0.0006)


def build_gpu(P: Part, tier: int):
    _pcie_slot(P, 0.0)
    if tier <= 0:
        return

    rotor_i = 0
    cards = 2 if tier >= 3 else 1
    card_len = 0.21 if tier == 1 else (0.28 if tier == 2 else 0.31)
    card_h = 0.072 if tier == 1 else 0.088
    half = card_len * 0.5
    mid = card_h * 0.5
    cz = -0.155 + half
    for c_idx in range(cards):
        cx = c_idx * 0.056
        if c_idx > 0:
            _pcie_slot(P, cx)
        card_pos = Vector((cx, 0.006, cz))
        M = T(card_pos)

        P.box((0.0, mid, 0.0), (0.0032, card_h, card_len), M_PCB_SUB_B, M, bevel=0.0)
        for z0, z1 in ((-0.146, -0.128), (-0.122, 0.004)):
            P.box((0.0, 0.005, (z0 + z1) * 0.5 - cz), (0.0036, 0.008, z1 - z0), M_GOLD, M, bevel=0.0)
        # Gebuerstete Backplate mit Entlueftungsschlitzen & Schrauben
        P.box((-0.0034, mid + 0.003, 0.002), (0.0018, card_h - 0.008, card_len - 0.010), M_GUNMETAL, M, bevel=0.0005)
        for v in range(6):
            P.box((-0.0044, mid + 0.003, half - 0.032 - v * 0.009), (0.0006, card_h * 0.52, 0.0038), M_CAVITY, M, bevel=0.0)
        P.box((-0.0044, mid + 0.004, -half + 0.068), (0.0005, 0.022, 0.088), M_GPU_LBL, M, bevel=0.0, uv_mode="sticker_x")

        # Slotblech hinten mit DisplayPort/HDMI-Ports & Waben-Auslass
        bz = -half - 0.003
        P.box((0.012, mid + 0.004, bz), (0.036, card_h + 0.010, 0.0022), M_STEEL, M, bevel=0.0)
        P.box((0.012, card_h + 0.009, bz + 0.006), (0.036, 0.0022, 0.012), M_STEEL, M, bevel=0.0)
        for p in range(4):
            py = 0.016 + p * 0.016
            if py > card_h - 0.008:
                break
            P.box((0.004, py, bz - 0.0016), (0.0105, 0.0068, 0.0012), M_CAVITY, M, bevel=0.0)
        P.box((0.022, mid, bz - 0.0012), (0.011, card_h * 0.72, 0.0008), M_HONEY_DARK, M, bevel=0.0, uv_scale=0.045)

        if tier >= 3:
            # Enterprise-KI-Tensor-Beschleuniger: CNC-Haube + Kupfer-Einlasslamellen + Gold-Akzent
            sx0, sw = 0.0145, 0.0235
            P.box((sx0, mid, -0.024), (sw, card_h - 0.004, card_len - 0.056), M_DARK_STEEL, M, bevel=0.0014)
            iz = half - 0.028
            P.fins((sx0, mid, iz), (sw, card_h - 0.012, 0.048), 10, 1, M_COPPER, M, fill_ratio=0.46)
            P.box((sx0, card_h - 0.004, iz), (sw, 0.004, 0.048), M_DARK_STEEL, M, bevel=0.0)
            P.box((sx0, 0.004, iz), (sw, 0.004, 0.048), M_DARK_STEEL, M, bevel=0.0)
            P.box((sx0, card_h + 0.0018, -0.010), (sw * 0.92, 0.0032, card_len * 0.68), M_GOLD, M, bevel=0.0006)
            face = sx0 + sw * 0.5 + 0.0004
            P.box((face, mid, -0.036), (0.0006, 0.026, 0.118), M_GPU_LBL, M, bevel=0.0, uv_mode="sticker_x")
            for n in range(2):
                nz = -half + 0.040 + n * 0.030
                P.box((0.0, card_h + 0.0016, nz), (0.0036, 0.0032, 0.022), M_GOLD, M, bevel=0.0)
            P.box((0.010, card_h + 0.006, half - 0.014), (0.016, 0.012, 0.018), M_PLASTIC, M, bevel=0.0006)
            P.box((0.010, card_h + 0.0122, half - 0.014), (0.010, 0.0005, 0.012), M_CAVITY, M, bevel=0.0)
            continue

        # Aktiv gekuehlte Karte mit Alu-Lamellen, CNC-Shroud, Heatpipes & Axial-Lueftern
        face_x = 0.027
        fan_r = 0.026 if tier == 1 else 0.034
        fan_zs = [0.012] if tier == 1 else [-0.062, 0.062]
        cut = fan_r + 0.0022
        P.fins((0.011, mid, 0.0), (0.012, card_h - 0.010, card_len - 0.024), 14 if tier == 1 else 20, 2, M_ALU, M, fill_ratio=0.44)
        P.box((face_x, card_h - 0.004, 0.0), (0.0045, 0.0085, card_len - 0.008), M_DARK_STEEL, M, bevel=0.0008)
        P.box((face_x, 0.004, 0.0), (0.0045, 0.0085, card_len - 0.008), M_DARK_STEEL, M, bevel=0.0008)
        inner_h = card_h - 0.016
        seg_start = -half + 0.004
        for fz in fan_zs:
            seg_end = fz - cut
            if seg_end > seg_start + 0.001:
                P.box((face_x, mid, (seg_start + seg_end) * 0.5), (0.0045, inner_h, seg_end - seg_start), M_DARK_STEEL, M, bevel=0.0008)
            seg_start = fz + cut
        last_end = half - 0.004
        if last_end > seg_start + 0.001:
            P.box((face_x, mid, (seg_start + last_end) * 0.5), (0.0045, inner_h, last_end - seg_start), M_DARK_STEEL, M, bevel=0.0008)
        P.box((face_x + 0.0024, card_h - 0.004, 0.0), (0.0006, 0.0020, card_len - 0.030), M_ALU, M, bevel=0.0)
        P.box((face_x + 0.0024, mid, -half + 0.022), (0.0005, 0.018, 0.032), M_GPU_LBL, M, bevel=0.0, uv_mode="sticker_x")

        for fz in fan_zs:
            P.ring(M @ T((face_x, mid, fz)) @ Ry(90.0), fan_r + 0.001, cut, 0.0045, M_DARK_STEEL, square=True, seg=32)
            key = "Rotor_X_%d" % rotor_i
            rotor_i += 1
            origin = card_pos + Vector((face_x - 0.003, mid, fz))
            P.new_group(key, origin)
            P.rotor(T(origin) @ Ry(90.0), fan_r - 0.001, 11, M_BLADE_GPU, M_GUNMETAL, group=key, hub_ratio=0.34, depth_ratio=0.22, sweep=0.75, cap_mat=M_CHROME)

        for hp in range(2 if tier == 1 else 3):
            px = 0.008 + hp * 0.0045
            z_a = -card_len * 0.18 + hp * 0.010
            z_b = card_len * 0.22 - hp * 0.012
            P.cable([(px, mid - 0.012, z_a), (px, card_h + 0.002, z_a - 0.014), (px, card_h + 0.002, z_b), (px, card_h - 0.010, z_b + 0.012)], 0.0028, M_COPPER, M, seg=10)

        for pc in range(1 if tier == 1 else 2):
            pz = half - 0.030 - pc * 0.024
            P.box((0.009, card_h + 0.0055, pz), (0.0105, 0.0115, 0.0215), M_PLASTIC, M, bevel=0.0006)
            for r_ in range(2):
                for k in range(4):
                    P.box((0.0065 + r_ * 0.005, card_h + 0.0114, pz - 0.0075 + k * 0.005), (0.0034, 0.0005, 0.0034), M_CAVITY, M, bevel=0.0)

    if tier >= 3:
        bridge_y = 0.006 + card_h + 0.006
        P.box((0.028, bridge_y, -0.100), (0.068, 0.0065, 0.052), M_GUNMETAL, bevel=0.0012)
        P.box((0.028, bridge_y + 0.0035, -0.100), (0.044, 0.0006, 0.024), M_GOLD, bevel=0.0)


# ---------------------------------------------------------------------------
# 4. RAM-Baenke (8x DDR5 ECC RDIMM + kontrastierende Verriegelungshebel + Aufkleber)
# ---------------------------------------------------------------------------

def _dimm_latch(P: Part, x: float, z: float, closed: bool):
    out = 1.0 if z > 0.0 else -1.0
    pivot = T((x, 0.003, z)) @ Rx(0.0 if closed else 28.0 * out)
    P.box((0.0, 0.0070, 0.0), (0.0086, 0.014, 0.0052), M_PLASTIC_GREY, pivot, bevel=0.0004)
    if closed:
        P.box((0.0, 0.0122, -0.0035 * out), (0.0062, 0.0032, 0.0018), M_PLASTIC_GREY, pivot, bevel=0.0)


def build_ram(P: Part, tier: int):
    populated = min(2 + tier * 2, 8)
    chips = (-0.058, -0.046, -0.034, -0.022, 0.006, 0.018, 0.030, 0.042, 0.054)
    for i in range(8):
        rx = -0.063 + i * 0.018
        filled = i < populated
        # Alternierende Slot-Farben (A/C Schwarz, B/D Dunkelgrau — klassischer Server-Look!)
        slot_m = M_PLASTIC if (i % 2 == 0) else M_GUNMETAL
        P.box((rx, 0.0042, 0.0), (0.0076, 0.0122, 0.146), slot_m, bevel=0.0005)
        P.box((rx, 0.0104, 0.0), (0.0022, 0.0005, 0.138), M_CAVITY, bevel=0.0)
        for z in (-0.071, 0.071):
            _dimm_latch(P, rx, z, filled)
        if not filled:
            continue

        mc = T((rx, 0.0, 0.0))
        P.box((0.0, 0.0215, 0.0), (0.0014, 0.031, 0.133), M_PCB_SUB_G if tier <= 1 else M_PCB_SUB_B, mc, bevel=0.0)
        for z0, z1 in ((-0.0655, -0.0055), (-0.0025, 0.0655)):
            P.box((0.0, 0.0085, (z0 + z1) * 0.5), (0.0016, 0.005, z1 - z0), M_GOLD, mc, bevel=0.0)
        for side in (-1.0, 1.0):
            for cz in chips:
                P.box((side * 0.0010, 0.0230, cz), (0.0008, 0.0082, 0.0095), M_IC, mc, bevel=0.0)
        P.box((0.0010, 0.0215, -0.008), (0.0009, 0.0062, 0.0110), M_IC, mc, bevel=0.0)
        P.box((0.0009, 0.0330, -0.008), (0.0006, 0.0042, 0.0050), M_CHROME, mc, bevel=0.0)

        if tier == 0:
            P.box((-0.0016, 0.0315, -0.030), (0.0004, 0.0085, 0.044), M_RAM_LBL, mc, bevel=0.0, uv_mode="sticker_x")
            continue

        sp_h = 0.029 if tier == 1 else 0.033
        sp_y = 0.011 + sp_h * 0.5
        sp_mat = M_GUNMETAL if tier == 1 else (M_ALU if tier == 2 else M_DARK_STEEL)
        for side in (-1.0, 1.0):
            P.box((side * 0.0022, sp_y, 0.0), (0.0011, sp_h, 0.129), sp_mat, mc, bevel=0.0)
            for g in range(3):
                P.box((side * 0.0028, 0.016 + g * 0.006, 0.028), (0.0003, 0.0012, 0.052), M_CHROME, mc, bevel=0.0)
        top = 0.011 + sp_h
        for cz in (-0.046, 0.046):
            P.box((0.0, top - 0.0018, cz), (0.0058, 0.004, 0.0065), M_CHROME, mc, bevel=0.0)
        P.box((0.0029, 0.023, -0.028), (0.0004, 0.013, 0.054), M_RAM_LBL, mc, bevel=0.0, uv_mode="sticker_x")
        if tier >= 2:
            P.box((0.0, top + 0.0006, 0.0), (0.0054, 0.0012, 0.129), sp_mat, mc, bevel=0.0)
            P.fins((0.0, top + 0.0036, 0.0), (0.0054, 0.0052, 0.124), 10, 2, M_ALU if tier == 2 else M_GUNMETAL, mc, fill_ratio=0.48)
        if tier >= 3:
            P.box((0.0, top + 0.0074, 0.0), (0.0054, 0.0028, 0.129), M_COPPER, mc, bevel=0.0)


# ---------------------------------------------------------------------------
# 5. M.2 NVMe Storage-Module (2280/22110 mit Enterprise-Etikett & CNC-Kuehlkoerper)
# ---------------------------------------------------------------------------

def build_storage(P: Part, tier: int):
    count = min(1 + tier, 3)
    length = 0.080 if tier <= 1 else 0.110
    x0 = -0.052
    board_x0 = x0 - 0.004
    xc = board_x0 + length * 0.5
    by = 0.0035
    top = by + 0.0005
    chip_top = top + 0.0013
    nand = 2 if tier <= 1 else 4
    for i in range(count):
        mz = -0.032 + i * 0.034
        P.box((x0 - 0.0035, 0.0026, mz), (0.0095, 0.0092, 0.0255), M_PLASTIC, bevel=0.0005)
        P.box((x0 + 0.0014, by, mz), (0.0012, 0.0030, 0.021), M_CAVITY, bevel=0.0)

        P.box((xc, by, mz), (length, 0.0010, 0.022), M_PCB_SUB_B, bevel=0.0)
        P.box((x0 + 0.0015, by, mz - 0.003), (0.0032, 0.0012, 0.014), M_GOLD, bevel=0.0)
        P.box((x0 + 0.0015, by, mz + 0.0085), (0.0032, 0.0012, 0.004), M_GOLD, bevel=0.0)
        P.box((board_x0 + 0.017, top + 0.0006, mz), (0.014, 0.0013, 0.014), M_CHROME, bevel=0.0)
        P.box((board_x0 + 0.030, top + 0.0005, mz + 0.003), (0.008, 0.0010, 0.012), M_IC, bevel=0.0)
        for k in range(nand):
            P.box((board_x0 + 0.044 + k * 0.018, top + 0.0006, mz), (0.015, 0.0013, 0.018), M_IC, bevel=0.0)

        sx = board_x0 + length - 0.0015
        P.cyl((sx, 0.00055, mz), 0.0028, 0.0051, M_GOLD, seg=12)
        P.screw_head((sx, top + 0.0008, mz), r=0.0028, h=0.0015, mat=M_CHROME)

        if tier == 0:
            P.box((board_x0 + 0.048, chip_top + 0.0002, mz), (0.046, 0.0003, 0.019), M_NVME_LBL, bevel=0.0, uv_mode="sticker_top_x")
        elif tier == 1:
            P.box((board_x0 + 0.039, chip_top + 0.0002, mz), (0.066, 0.0004, 0.020), M_COPPER, bevel=0.0)
            P.box((board_x0 + 0.048, chip_top + 0.0005, mz), (0.042, 0.0003, 0.016), M_NVME_LBL, bevel=0.0, uv_mode="sticker_top_x")
        else:
            sink = M_GUNMETAL if tier == 2 else M_COPPER
            base_len = length - 0.012
            sx_c = board_x0 + 0.004 + base_len * 0.5
            fin_h = 0.0042 if tier == 2 else 0.0052
            P.box((sx_c, chip_top + 0.0004, mz), (base_len, 0.0008, 0.021), M_DARK_STEEL, bevel=0.0)
            P.box((sx_c, chip_top + 0.0020, mz), (base_len, 0.0024, 0.023), sink, bevel=0.0005)
            P.fins((sx_c, chip_top + 0.0032 + fin_h * 0.5, mz), (base_len, fin_h, 0.0225), 5, 2, sink, fill_ratio=0.48)
            for bx in (board_x0 + 0.020, board_x0 + length - 0.024):
                P.box((bx, chip_top + 0.0032 + fin_h + 0.0003, mz), (0.0045, 0.0007, 0.0238), M_CHROME, bevel=0.0)


# ---------------------------------------------------------------------------
# 6. Hot-Swap Server-Luefterwand (92mm Delta-Stil + PWM-Kabel + Tier-3-Wakue)
# ---------------------------------------------------------------------------

def _server_fan(P: Part, i: int, fan_pos: Vector):
    M = T(fan_pos)
    # Robuster 92x38mm Industrie-Luefterrahmen mit Gummi-Antivibrations-Ecken
    P.ring(M, 0.0432, 0.0465, 0.038, M_PLASTIC, square=True, seg=32)
    for sx in (-0.0415, 0.0415):
        for sy in (-0.0415, 0.0415):
            P.box((sx, sy, 0.0), (0.010, 0.010, 0.0392), M_RUBBER, M, bevel=0.0008)
            P.cyl((sx, sy, 0.0198), 0.0024, 0.0008, M_CHROME, M, axis="z", seg=10)

    # Motorhalter & 4 geschwungene Statorstreben auf der Rueckseite
    P.cyl((0.0, 0.0, -0.0165), 0.018, 0.0045, M_PLASTIC, M, axis="z", seg=24)
    for k in range(4):
        deg = 45.0 + 90.0 * k
        a = math.radians(deg)
        P.box((0.031 * math.cos(a), 0.031 * math.sin(a), -0.0165), (0.028, 0.0032, 0.0042), M_PLASTIC, M, rot=Rz(deg), bevel=0.0)

    # Verchromter Draht-Fingerschutz auf der Einlassseite (+Z)
    gz = 0.0200
    for r in (0.018, 0.030, 0.0405):
        P.ring(M @ T((0.0, 0.0, gz)), r, r + 0.0012, 0.0012, M_CHROME, seg=28)
    P.cyl((0.0, 0.0, gz), 0.0085, 0.0014, M_GUNMETAL, M, axis="z", seg=16)
    for ang in (45.0, -45.0):
        P.box((0.0, 0.0, gz), (0.088, 0.0013, 0.0013), M_CHROME, M, rot=Rz(ang), bevel=0.0)

    # Hot-Swap-Ausziehgriff oben mit gruener Entriegelung & Status-LED
    for hx in (-0.014, 0.014):
        P.box((hx, 0.049, 0.008), (0.0045, 0.006, 0.010), M_PLASTIC, M, bevel=0.0005)
    P.box((0.0, 0.0535, 0.008), (0.036, 0.0036, 0.012), M_LATCH_GREEN, M, bevel=0.0008)
    P.box((0.0345, -0.039, 0.0196), (0.0036, 0.0024, 0.0008), M_LED_GREEN, M, bevel=0.0)

    # Feines gesleevtes 4-Pin-PWM-Kabel vom Luefterrahmen nach unten zum Fan-Backplane-Sockel
    P.cable([(0.038, -0.020, -0.016), (0.044, -0.032, -0.020), (0.032, -0.045, -0.022)], 0.0019, M_CABLE, M, seg=8)

    key = "Rotor_Z_%d" % i
    origin = fan_pos + Vector((0.0, 0.0, 0.002))
    P.new_group(key, origin)
    P.rotor(T(origin), 0.0415, 9, M_BLADE_FAN, M_PLASTIC, group=key, hub_ratio=0.38, depth_ratio=0.52, sweep=0.65, cap_mat=M_ALU)


def build_cooling(P: Part, tier: int):
    fan_count = min(3 + tier, 5)
    spacing = 0.115
    start_x = -(fan_count - 1) * spacing * 0.5
    width = (fan_count - 1) * spacing + 0.114

    # Gefaltete dunkel-eloxierte Luefter-Trennwand (Midplane Bulkhead!)
    P.box((0.0, 0.0014, 0.0), (width, 0.0028, 0.046), M_DARK_STEEL, bevel=0.0)
    P.box((0.0, 0.0955, -0.021), (width, 0.0026, 0.010), M_DARK_STEEL, bevel=0.0)
    for i in range(fan_count + 1):
        dx = start_x - spacing * 0.5 + i * spacing
        P.box((dx, 0.048, -0.021), (0.0028, 0.095, 0.008), M_DARK_STEEL, bevel=0.0)

    for i in range(fan_count):
        _server_fan(P, i, Vector((start_x + i * spacing, 0.048, 0.0)))

    if tier < 3:
        return

    # Tier 3: Enterprise-Kupferradiator + Pumpe + gesleevte Kuehlschlaeuche + Kupfer-Fittings
    rw = width - 0.024
    rz = -0.036
    P.fins((0.0, 0.048, rz), (rw, 0.080, 0.022), 48, 0, M_COPPER, fill_ratio=0.45)
    for ty in (0.0905, 0.0055):
        P.box((0.0, ty, rz), (rw, 0.005, 0.026), M_DARK_STEEL, bevel=0.0006)
    tank_x = rw * 0.5 + 0.008
    for tx in (-tank_x, tank_x):
        P.box((tx, 0.048, rz), (0.016, 0.092, 0.030), M_GUNMETAL, bevel=0.0012)

    px = rw * 0.5 - 0.012
    pz = -0.086
    P.cyl((px, 0.024, pz), 0.018, 0.042, M_GUNMETAL, seg=28)
    P.cyl((px, 0.0465, pz), 0.0186, 0.0045, M_DARK_STEEL, seg=28)
    P.cyl((px, 0.0490, pz), 0.010, 0.0006, M_COPPER, seg=20)
    for ty in (0.070, 0.026):
        P.cyl((tank_x, ty, rz - 0.019), 0.0062, 0.009, M_COPPER, axis="z", seg=14)
    P.cable([(tank_x, 0.070, rz - 0.023), (tank_x, 0.070, rz - 0.048), (px, 0.068, pz), (px, 0.050, pz)], 0.0050, M_CABLE, seg=12)
    P.cable([(tank_x, 0.026, rz - 0.023), (tank_x, 0.026, rz - 0.054), (px, 0.026, pz)], 0.0050, M_CABLE, seg=12)


# ---------------------------------------------------------------------------
# 7. Netzteil (PSU) mit 1:1-Wabengitter, 80-PLUS-Typenschild & ECHTEN gesleevten Kabeln!
# ---------------------------------------------------------------------------

def _c14_inlet(P: Part, x: float, y: float, face: float):
    P.box((x, y, face - 0.003), (0.025, 0.017, 0.006), M_PLASTIC, bevel=0.0005)
    P.box((x, y, face - 0.0062), (0.019, 0.012, 0.0008), M_CAVITY, bevel=0.0)
    for px, py in ((-0.0052, -0.0015), (0.0, 0.0022), (0.0052, -0.0015)):
        P.box((x + px, y + py, face - 0.0068), (0.0014, 0.0042, 0.0014), M_CHROME, bevel=0.0)


def _psu_module(P: Part, offset, size, hot_swap: bool, label_mat: str):
    off = Vector(offset)
    sx, sy, sz = size
    half = Vector(size) * 0.5
    cy = 0.048

    # Gebuerstetes Stahlgehaeuse mit sauberer Fase & 4 Torx-Deckelschrauben
    P.box(off + Vector((0.0, cy, 0.0)), size, M_STEEL, bevel=0.0018, uv_scale=0.18)
    # 1:1 UNVERZERRTES Waben-Lochblech oben im vertieften Rahmen (uv_scale=0.064 -> perfekte Sechsecke!)
    grill_w = sx - 0.016
    grill_d = sz * 0.52
    grill_z = off.z - 0.028
    P.box(Vector((off.x, cy + half.y + 0.0005, grill_z)), (grill_w + 0.005, 0.0014, grill_d + 0.005), M_DARK_STEEL, bevel=0.0)
    P.box(Vector((off.x, cy + half.y + 0.0011, grill_z)), (grill_w, 0.0008, grill_d), M_HONEY_STEEL, bevel=0.0, uv_scale=0.062)

    for dx in (-half.x + 0.008, half.x - 0.008):
        for dz in (-half.z + 0.008, half.z - 0.008):
            P.screw_head((off.x + dx, cy + half.y + 0.0008, off.z + dz), r=0.0026, h=0.0012, mat=M_DARK_STEEL)

    # Scharfes 80-PLUS-Typenschild OBEN vorne (sofort in der Draufsicht lesbar!) UND seitlich links zum Mainboard!
    if not hot_swap:
        P.box(Vector((off.x, cy + half.y + 0.0007, off.z + 0.095)), (sx - 0.016, 0.0005, 0.072), label_mat, bevel=0.0, uv_mode="sticker_top_x")
    else:
        P.box(Vector((off.x, cy + half.y + 0.0007, off.z + 0.105)), (sx - 0.008, 0.0005, 0.088), label_mat, bevel=0.0, uv_mode="sticker_top_z")
    # Zusaetzliches Seiten-Typenschild an der freien Innenseite (-X)
    if not hot_swap or off.x < 0:
        P.box(Vector((off.x - half.x - 0.0004, cy, off.z + 0.015)), (0.0006, sy * 0.62, sz * 0.44), label_mat, bevel=0.0, uv_mode="sticker_x")

    # Rueckwand (-Z): Auslass-Luefter mit verchromtem Drahtgitter, C14-Buchse & Griff/Schalter
    rz = off.z - half.z
    P.box(Vector((off.x, cy, rz - 0.0007)), (sx - 0.003, sy - 0.003, 0.0014), M_DARK_STEEL, bevel=0.0)
    face = rz - 0.0014
    fan_r = min(sx, sy) * 0.35
    fan_c = Vector((off.x, cy + sy * 0.12, face))
    P.cyl(fan_c + Vector((0.0, 0.0, -0.0003)), fan_r + 0.001, 0.0006, M_CAVITY, axis="z", seg=28)
    P.ring(T(fan_c + Vector((0.0, 0.0, -0.0035))), fan_r + 0.0005, fan_r + 0.0028, 0.007, M_DARK_STEEL, seg=32)
    P.rotor(T(fan_c + Vector((0.0, 0.0, -0.0040))), fan_r - 0.0005, 7, M_BLADE_FAN, M_PLASTIC, hub_ratio=0.38, depth_ratio=0.30, sweep=0.60, cap_mat=M_ALU)
    gz = face - 0.0082
    for r in (fan_r * 0.45, fan_r * 0.80):
        P.ring(T(fan_c + Vector((0.0, 0.0, gz - face))), r, r + 0.0010, 0.0010, M_CHROME, seg=24)
    for ang in (45.0, -45.0):
        P.box(Vector((fan_c.x, fan_c.y, gz)), (fan_r * 2.0, 0.0010, 0.0010), M_CHROME, rot=Rz(ang), bevel=0.0)

    if hot_swap:
        hy = cy - sy * 0.22
        P.cable([(off.x - 0.020, hy, face), (off.x - 0.020, hy, face - 0.015), (off.x + 0.020, hy, face - 0.015), (off.x + 0.020, hy, face)], 0.0023, M_DARK_STEEL, seg=10)
        _c14_inlet(P, off.x - 0.004, 0.011, face)
        P.box(Vector((off.x + 0.021, 0.013, face - 0.0035)), (0.007, 0.013, 0.007), M_LATCH_GREEN, bevel=0.0006)
        P.cyl((off.x - 0.022, 0.013, face - 0.0006), 0.0020, 0.0012, M_LED_GREEN, axis="z", seg=12)
    else:
        _c14_inlet(P, off.x - 0.044, 0.020, face)
        P.box(Vector((off.x - 0.044, 0.052, face - 0.0025)), (0.013, 0.017, 0.005), M_PLASTIC, bevel=0.0)
        P.box(Vector((off.x - 0.044, 0.055, face - 0.0052)), (0.009, 0.0065, 0.0018), M_GRIP_RED, rot=Rx(10.0), bevel=0.0)
        P.box(Vector((off.x + 0.045, 0.048, face - 0.0006)), (0.022, 0.056, 0.0008), M_HONEY_DARK, bevel=0.0, uv_scale=0.045)


def build_psu(P: Part, tier: int):
    """PSU-Baugruppe (Welt-Ursprung in HardwareMeshFactory: (0.285, 0.018, -0.170)).
    In PSU-Lokal-Koordinaten:
        Mainboard 24-Pin ATX Buchse: (-0.090, +0.027, +0.040)
        Mainboard  8-Pin EPS Buchse: (-0.325, +0.025, -0.062)
    Die Kabel sind in enge eigene Mesh-Gruppen (Cable_*) aufgeteilt, damit ihre AABBs beim
    Hover-Picking niemals die Mainboard-Mitte, CPU oder RAM verdecken!
    """
    lbl = M_PSU_LBL_PRO if tier >= 2 else M_PSU_LBL_STD
    if tier >= 2:
        for u in range(2):
            _psu_module(P, (-0.034 + u * 0.068, 0.0, 0.0), (0.060, 0.094, 0.32), True, lbl)
        # Power Distribution Board (PDB) vorne mit echter Backplane-Textur, Kupfer-Busbars & Elkos
        P.pcb_slab((0.0, 0.048, 0.165), (0.132, 0.082, 0.0034), M_BACKPLANE, M_PCB_EDGE, uv_mode="planar_back_z")
        P.box((0.0, 0.048, 0.1615), (0.136, 0.086, 0.0022), M_DARK_STEEL, bevel=0.0)
        for c in range(4):
            P.cyl((0.012 + c * 0.014, 0.070, 0.172), 0.0046, 0.011, M_ALU, axis="z", seg=16)
            P.cyl((0.012 + c * 0.014, 0.070, 0.1778), 0.0042, 0.0006, M_CAP_BLUE, axis="z", seg=16)
        for c in range(2):
            P.box((0.020 + c * 0.022, 0.038, 0.170), (0.013, 0.013, 0.007), M_FERRITE, bevel=0.0010)
        P.box((0.032, 0.084, 0.169), (0.056, 0.004, 0.004), M_COPPER, bevel=0.0)
        exit_z = 0.167
    else:
        _psu_module(P, (0.0, 0.0, 0.0), (0.125, 0.092, 0.30), False, lbl)
        # Kabel-Durchfuehrungstuelle (Grommet) vorne links
        P.cyl((-0.032, 0.036, 0.151), 0.014, 0.005, M_RUBBER, axis="z", seg=18)
        exit_z = 0.150

    # --- 1) ECHTER GESLEEVTER 24-PIN-ATX-KABELBAUM (direkt eingesteckt ins Mainboard!) ---
    # Enges AABB rechts neben dem Board: x -0.098..-0.018, z 0.00..0.18
    P.new_group("Cable_ATX24", (-0.060, 0.035, 0.100))
    # 24-Pin Molex-Stecker sitzt sauber AUF der Mainboard-Buchse (-0.090, 0.030, 0.040)
    P.box((-0.090, 0.032, 0.040), (0.017, 0.014, 0.090), M_PLASTIC, bevel=0.0008, group="Cable_ATX24")
    P.box((-0.0805, 0.033, 0.040), (0.0022, 0.010, 0.016), M_PLASTIC_GREY, bevel=0.0, group="Cable_ATX24")

    # 6 gesleevte Einzelleiter-Straenge in eleganter S-Kurve + 2 Kabelkaemme
    if tier >= 2:
        P.box((-0.036, 0.036, 0.171), (0.028, 0.018, 0.008), M_PLASTIC, bevel=0.0005, group="Cable_ATX24")
        exit_z = 0.174
    for k in range(6):
        z_plug = 0.004 + k * 0.0144
        x_exit = -0.044 + (k % 3) * 0.0080
        y_exit = 0.031 + (k // 3) * 0.009
        pts = [
            (x_exit, y_exit, exit_z - 0.004),
            (x_exit - 0.008, y_exit + 0.008, exit_z + 0.020),
            (-0.072 + (k % 2) * 0.006, 0.056 + (k // 3) * 0.005, 0.145),
            (-0.078 + (k % 2) * 0.005, 0.060 + (k // 3) * 0.004, 0.092),
            (-0.090, 0.052, z_plug + 0.014),
            (-0.090, 0.038, z_plug),
        ]
        P.cable(pts, 0.0031, M_CABLE, seg=8, subdiv=6, group="Cable_ATX24", uv_pitch=0.020)
    # Zwei sauber ausgerichtete schwarze Kabelkaemme
    P.box((-0.072, 0.058, 0.125), (0.015, 0.014, 0.0045), M_DARK_STEEL, bevel=0.0005, group="Cable_ATX24")
    P.box((-0.082, 0.058, 0.082), (0.014, 0.014, 0.0045), M_DARK_STEEL, bevel=0.0005, group="Cable_ATX24")

    # --- 2) GESLEEVTES 8-PIN-EPS-CPU-STROMKABEL (in 2 schmalen Segment-Gruppen entlang der Rueckwand!) ---
    # Segment A: entlang des schmalen Kanals hinter dem Board (z_psu = -0.162 -> z_world = -0.332, komplett hinter dem Board!)
    P.new_group("Cable_EPS_Run", (-0.190, 0.016, -0.160))
    for k, dy in enumerate((-0.0022, 0.0022)):
        pts_a = [
            (-0.063, 0.018 + dy, -0.125),
            (-0.078, 0.015 + dy, -0.158),
            (-0.180, 0.014 + dy, -0.162),
            (-0.312, 0.014 + dy, -0.162),
        ]
        P.cable(pts_a, 0.0026, M_CABLE, seg=8, subdiv=6, group="Cable_EPS_Run", uv_pitch=0.020)
    # Kleiner Kabelclip an der Rueckwand-Strecke
    P.box((-0.185, 0.016, -0.162), (0.008, 0.011, 0.010), M_PLASTIC_GREY, bevel=0.0005, group="Cable_EPS_Run")

    # Segment B: kurzer Bogen von der Rueckwand direkt in den 8-Pin-EPS-Stecker (-0.325, 0.026, -0.062)
    P.new_group("Cable_EPS_Plug", (-0.325, 0.025, -0.110))
    P.box((-0.325, 0.030, -0.062), (0.021, 0.013, 0.012), M_PLASTIC, bevel=0.0006, group="Cable_EPS_Plug")
    for k, dx in enumerate((-0.0045, 0.0045)):
        pts_b = [
            (-0.312, 0.014 + (k - 0.5) * 0.004, -0.162),
            (-0.325 + dx, 0.026, -0.140),
            (-0.325 + dx, 0.044, -0.095),
            (-0.325 + dx, 0.036, -0.062),
        ]
        P.cable(pts_b, 0.0026, M_CABLE, seg=8, subdiv=6, group="Cable_EPS_Plug", uv_pitch=0.020)


# ---------------------------------------------------------------------------
# 8. 2U-Server-Chassis (duennes gekantetes Blech, echte I/O- & PSU-Ausschnitte,
#    SAS-Backplane mit Mini-SAS-Kabeln, Rack-Ohren & Hot-Swap-Caddies)
# ---------------------------------------------------------------------------

BAY_LAYOUT = {4: (-0.245, 0.165, 0.145), 8: (-0.275, 0.078, 0.068)}
BAY_Y = 0.072
BAY_H = 0.092
CH_HALF_W = 0.370
CH_WALL_H = 0.132
CH_SHEET = 0.0022
CH_REAR_Z = -0.360
CH_FRONT_Z = 0.362


def _round_rect(w, d, r, seg=7):
    pts = []
    corners = (
        (w * 0.5 - r, d * 0.5 - r, 0.0),
        (-w * 0.5 + r, d * 0.5 - r, 90.0),
        (-w * 0.5 + r, -d * 0.5 + r, 180.0),
        (w * 0.5 - r, -d * 0.5 + r, 270.0),
    )
    for cx, cz, a0 in corners:
        for k in range(seg + 1):
            a = math.radians(a0 + 90.0 * k / seg)
            pts.append((cx + r * math.cos(a), cz + r * math.sin(a)))
    return pts


def _slab(P: Part, outline, y0, y1, top_mat, side_mat=None, uv_mode="planar_xz", bounds=None, group="Body"):
    t_top = bmesh.new()
    uv_t = t_top.loops.layers.uv.new("UVMap")
    t_side = bmesh.new()
    uv_s = t_side.loops.layers.uv.new("UVMap")

    top_v = [t_top.verts.new((x, y1, z)) for x, z in outline]
    bot_v = [t_top.verts.new((x, y0, z)) for x, z in outline]
    t_top.faces.new(top_v)
    t_top.faces.new(list(reversed(bot_v)))

    s_top = [t_side.verts.new((x, y1, z)) for x, z in outline]
    s_bot = [t_side.verts.new((x, y0, z)) for x, z in outline]
    n = len(outline)
    for i in range(n):
        j = (i + 1) % n
        t_side.faces.new((s_bot[i], s_bot[j], s_top[j], s_top[i]))

    bmesh.ops.recalc_face_normals(t_top, faces=list(t_top.faces))
    bmesh.ops.recalc_face_normals(t_side, faces=list(t_side.faces))

    xs = [p[0] for p in outline]
    zs = [p[1] for p in outline]
    x0, x1 = (bounds[0], bounds[1]) if bounds else (min(xs), max(xs))
    z0, z1 = (bounds[2], bounds[3]) if bounds else (min(zs), max(zs))

    for f in t_top.faces:
        for loop in f.loops:
            co = loop.vert.co
            u = (co.x - x0) / max(x1 - x0, 1e-5)
            v = (z1 - co.z) / max(z1 - z0, 1e-5)
            loop[uv_t].uv = (u, v)

    for f in t_side.faces:
        for loop in f.loops:
            co = loop.vert.co
            loop[uv_s].uv = ((co.x + co.z) * 2.0, co.y * 8.0)

    P._add(t_top, I4, top_mat, group)
    P._add(t_side, I4, side_mat if side_mat else top_mat, group)


def build_chassis(P: Part, bays: int):
    hw, wh, t, fz = CH_HALF_W, CH_WALL_H, CH_SHEET, CH_FRONT_Z

    # Bodenwanne mit gestanzten Versteifungssicken & Gummifuessen (y = -0.006 auf ESD-Matte)
    P.box((0.0, 0.008, 0.0), (2.0 * hw - 0.004, 0.016, 0.718), M_STEEL, bevel=0.0, uv_scale=0.22)
    for sx in (-0.342, 0.214, 0.345):
        P.box((sx, 0.0168, -0.06), (0.009, 0.0016, 0.56), M_STEEL, bevel=0.0004)
    # Zusaetzliche gestanzte Boden-Praegungen im leeren Bereich zwischen Mainboard & Luefterwand
    for px in (-0.22, -0.06, 0.10):
        P.box((px, 0.0166, 0.20), (0.10, 0.0012, 0.016), M_STEEL, bevel=0.0004)
    for fx in (-0.31, 0.31):
        for fzz in (-0.31, 0.31):
            P.cyl((fx, -0.003, fzz), 0.014, 0.006, M_RUBBER, seg=20)

    # Duenne gekantete Seitenwaende (2.2 mm SGCC) mit sauberer 9-mm-Umkantung + EMI-Federkontakten + Rack-Schienen
    for sx in (-1.0, 1.0):
        P.box((sx * (hw - t * 0.5), wh * 0.5, 0.0), (t, wh, 0.720), M_STEEL, bevel=0.0, uv_scale=0.22)
        P.box((sx * (hw - 0.0055), wh - t * 0.5, 0.0), (0.011, t, 0.720), M_STEEL, bevel=0.0, uv_scale=0.22)
        # Feine EMI-Masse-Federkontakte entlang der Oberkante (klassischer Enterprise-Server-Detailgrad!)
        for ez in (-0.28, -0.14, 0.0, 0.14, 0.28):
            P.box((sx * (hw - 0.006), wh + 0.0005, ez), (0.005, 0.0010, 0.014), M_CHROME, bevel=0.0)
        # Innere Kabel-Clips an den Seitenwaenden
        for cz in (-0.18, 0.02, 0.16):
            P.box((sx * (hw - 0.007), 0.028, cz), (0.010, 0.012, 0.008), M_PLASTIC_GREY, bevel=0.0006)
        # Aussere Rack-Auszugsschienen mit Nieten
        P.box((sx * (hw + 0.0022), 0.066, -0.02), (0.0044, 0.025, 0.62), M_GUNMETAL, bevel=0.0)
        for y in (0.052, 0.080):
            P.box((sx * (hw + 0.0040), y, -0.02), (0.0075, 0.0030, 0.62), M_STEEL, bevel=0.0)
        for z in (-0.27, -0.02, 0.23):
            P.cyl((sx * (hw + 0.0050), 0.066, z), 0.0038, 0.0016, M_CHROME, axis="x", seg=16)

    # Typenschild / Asset-Tag aussen links
    P.box((-(hw + 0.0004), 0.102, -0.17), (0.0006, 0.024, 0.078), M_RAM_LBL, bevel=0.0, uv_mode="sticker_x")

    # --- RUECKWAND MIT ECHTEN AUSSCHNITTEN (PSU-Schacht + Rear I/O + PCIe-Blenden + Waben-Auslass!) ---
    rz = CH_REAR_Z + t * 0.5
    # Obere Kante & Umkantung ueber volle Breite
    P.box((0.0, wh - t * 0.5, CH_REAR_Z + 0.0055), (2.0 * hw - 2.0 * t, t, 0.011), M_STEEL, bevel=0.0, uv_scale=0.22)
    P.box((0.0, wh - 0.014, rz), (2.0 * hw - 2.0 * t, 0.024, t), M_STEEL, bevel=0.0, uv_scale=0.22)
    # 1:1 Waben-Abluftstreifen oben in der Rueckwand (unverzerrt!)
    P.box((0.0, wh - 0.014, rz), (0.58, 0.015, t + 0.0008), M_HONEY_STEEL, bevel=0.0, uv_scale=0.055)

    # Linker Steg neben I/O-Ausschnitt
    P.box((-0.340, 0.060, rz), (0.058, 0.096, t), M_STEEL, bevel=0.0)
    # Mittelsteg zwischen I/O & PCIe sowie zwischen PCIe & PSU-Ausschnitt
    P.box((0.205, 0.060, rz), (0.026, 0.096, t), M_STEEL, bevel=0.0)
    # Rechter Rand neben PSU-Ausschnitt (PSU sitzt x = 0.285 +- 0.065 -> 0.220..0.350 bleibt OFFEN!)
    P.box((0.360, 0.060, rz), (0.018, 0.096, t), M_STEEL, bevel=0.0)
    # Unterer Rahmenstreifen
    P.box((0.0, 0.018, rz), (2.0 * hw - 2.0 * t, 0.014, t), M_STEEL, bevel=0.0)

    # Linker Rueckwandbereich (-0.311 .. +0.192): I/O-Blende & 3 gelochte PCIe-Slotblenden mit Raendelschrauben!
    P.box((-0.060, 0.060, rz), (0.502, 0.088, t), M_STEEL, bevel=0.0, uv_scale=0.20)
    # Vertiefte Edelstahl-I/O-Blende (aligned zu Mainboard-I/O x_world = -0.30..-0.09)
    P.box((-0.200, 0.050, rz - 0.0008), (0.215, 0.048, 0.0014), M_GUNMETAL, bevel=0.0)
    # I/O-Oeffnungen (VGA, 2x USB, 4x RJ45)
    P.box((-0.296, 0.046, rz - 0.0014), (0.026, 0.012, 0.0010), M_VGA_BLUE, bevel=0.0)
    for ux in (-0.254, -0.230):
        P.box((ux, 0.048, rz - 0.0014), (0.016, 0.020, 0.0010), M_CAVITY, bevel=0.0)
    for jx in (-0.198, -0.172, -0.146, -0.110):
        P.box((jx, 0.050, rz - 0.0014), (0.019, 0.022, 0.0010), M_CAVITY, bevel=0.0)

    # 3x gelochte Low-Profile-PCIe-Slotblenden (x = -0.05..+0.17) mit silbernen Raendelschrauben
    for s in range(3):
        sy = 0.036 + s * 0.023
        P.box((0.058, sy, rz - 0.0008), (0.142, 0.017, 0.0014), M_DARK_STEEL, bevel=0.0)
        P.box((0.058, sy, rz - 0.0014), (0.118, 0.011, 0.0008), M_HONEY_DARK, bevel=0.0, uv_scale=0.045)
        P.cyl((0.142, sy, rz - 0.0032), 0.0036, 0.0045, M_CHROME, axis="z", seg=14)

    # Niedrige gestanzte PSU-Fuehrungsschiene am Boden (kollidiert niemals mit dem 24-Pin-Kabelbaum!)
    P.box((0.216, 0.026, -0.175), (0.0022, 0.020, 0.290), M_STEEL, bevel=0.0)

    # --- RACK-OHREN VORNE: Winkelbleche, Raendelschrauben, eloxierte Griffe, Bedienfeld ---
    for sx in (-1.0, 1.0):
        P.box((sx * (hw + t * 0.5), wh * 0.5, 0.331), (t, wh - 0.004, 0.058), M_DARK_STEEL, bevel=0.0)
        for y in (0.030, 0.104):
            P.screw_head((sx * (hw + t + 0.0006), y, 0.318), r=0.0034, h=0.0016, mat=M_CHROME, axis="y")
        P.box((sx * (hw + 0.0225), wh * 0.5, fz - t * 0.5), (0.045, wh, t), M_DARK_STEEL, bevel=0.0008)
        slot_x = sx * (hw + 0.034)
        P.box((slot_x, 0.018, fz - t * 0.5), (0.007, 0.0062, t + 0.0010), M_CAVITY, bevel=0.0)
        P.cyl((slot_x, 0.116, fz + 0.0035), 0.0058, 0.007, M_CHROME, axis="z", seg=20)
        P.cyl((slot_x, 0.116, fz + 0.0072), 0.0042, 0.0010, M_GUNMETAL, axis="z", seg=20)
        hx = sx * (hw + 0.018)
        P.cable([(hx, 0.034, fz), (hx, 0.034, fz + 0.022), (hx, 0.098, fz + 0.022), (hx, 0.098, fz)], 0.0044, M_GUNMETAL, seg=12)
        for y in (0.034, 0.098):
            P.box((hx, y, fz + 0.0022), (0.012, 0.012, 0.0045), M_DARK_STEEL, bevel=0.0006)

    # Bedienfeld im linken Ohr (Power-Button + grüne/blaue Status-LEDs)
    cx = -(hw + 0.035)
    P.cyl((cx, 0.074, fz + 0.0008), 0.0060, 0.0018, M_CHROME, axis="z", seg=24)
    P.cyl((cx, 0.074, fz + 0.0026), 0.0046, 0.0040, M_PLASTIC, axis="z", seg=24)
    P.cyl((cx, 0.074, fz + 0.0048), 0.0014, 0.0006, M_LED_GREEN, axis="z", seg=12)
    P.cyl((cx, 0.055, fz + 0.0016), 0.0036, 0.0032, M_LED_BLUE, axis="z", seg=20)
    for y in (0.088, 0.095):
        P.cyl((cx, y, fz + 0.0007), 0.0016, 0.0014, M_LED_GREEN, axis="z", seg=12)
    # Service-Pull-Tag im rechten Ohr
    P.box((hw + 0.035, 0.068, fz + 0.0010), (0.011, 0.028, 0.0020), M_PAPER, bevel=0.0)

    if bays:
        start, step, bw = BAY_LAYOUT[bays]
        gap = 0.0015
        xs = [start + i * step for i in range(bays)]
        o_l = xs[0] - bw * 0.5 - gap
        o_r = xs[-1] + bw * 0.5 + gap
        o_b = BAY_Y - BAY_H * 0.5 - gap
        o_t = BAY_Y + BAY_H * 0.5 + gap
        bz = fz - 0.002

        # Frontblende als Rahmen mit 1:1 Wabenlochung
        for x0, x1 in ((-hw, o_l), (o_r, hw)):
            w_seg = x1 - x0
            P.box(((x0 + x1) * 0.5, wh * 0.5, bz), (w_seg, wh, 0.004), M_DARK_STEEL, bevel=0.0)
            if w_seg > 0.022:
                P.box(((x0 + x1) * 0.5, 0.068, fz + 0.0003), (w_seg - 0.014, 0.080, 0.0008), M_HONEY_DARK, bevel=0.0, uv_scale=0.048)
        P.box(((o_l + o_r) * 0.5, (wh + o_t) * 0.5, bz), (o_r - o_l, wh - o_t, 0.004), M_DARK_STEEL, bevel=0.0)
        P.box(((o_l + o_r) * 0.5, o_b * 0.5, bz), (o_r - o_l, o_b, 0.004), M_DARK_STEEL, bevel=0.0)
        for a, b in zip(xs[:-1], xs[1:]):
            left = a + bw * 0.5 + gap
            right = b - bw * 0.5 - gap
            P.box(((left + right) * 0.5, BAY_Y, bz), (right - left, o_t - o_b, 0.004), M_DARK_STEEL, bevel=0.0)
        P.box((o_l + 0.045, o_b * 0.5, fz + 0.0005), (0.064, 0.010, 0.0010), M_ALU, bevel=0.0)

        # Laufwerkskaefig-Deckel: gebuersteter Stahlrahmen + scharfes 1:1 Waben-Lochblech (KEINE aufgeklebten Punkte!)
        cz, cd = 0.305, 0.106
        P.box((0.0, wh - t * 1.5, cz), (2.0 * (hw - t), t, cd), M_STEEL, bevel=0.0, uv_scale=0.20)
        P.box((0.0, wh - t * 0.9, cz), (0.66, 0.0010, 0.086), M_HONEY_STEEL, bevel=0.0, uv_scale=0.064)
        for rx in (-0.345, -0.18, 0.0, 0.18, 0.345):
            P.screw_head((rx, wh - t * 0.6, 0.258), r=0.0026, h=0.0010, mat=M_CHROME)
            P.screw_head((rx, wh - t * 0.6, 0.352), r=0.0026, h=0.0010, mat=M_CHROME)

        guides = [o_l - 0.001] + [(a + b) * 0.5 for a, b in zip(xs[:-1], xs[1:])] + [o_r + 0.001]
        for x in guides:
            P.box((x, BAY_Y, cz), (0.0014, o_t - o_b, cd - 0.004), M_STEEL, bevel=0.0)

        # SAS/NVMe Drive Backplane mit eigener 1:1-PBR-Textur (KEIN Kacheln!), Mini-SAS-HD-Buchsen & Elkos!
        bpz = cz - cd * 0.5 - 0.0012
        bp_w = o_r - o_l + 0.012
        bp_cx = (o_l + o_r) * 0.5
        P.pcb_slab((bp_cx, 0.072, bpz), (bp_w, 0.104, 0.0024), M_BACKPLANE, M_PCB_EDGE, uv_mode="planar_back_z")
        for x in xs:
            P.box((x, 0.038, bpz - 0.0032), (min(0.032, bw * 0.6), 0.010, 0.0045), M_PLASTIC, bevel=0.0)
            P.cyl((x + 0.012, 0.095, bpz - 0.0045), 0.0032, 0.007, M_ALU, axis="z", seg=12)
        # 2x SFF-8643 Mini-SAS HD Metall-Buchsen + 2x 6-Pin-Backplane-Strombuchsen
        sas_xs = (bp_cx - bp_w * 0.22, bp_cx + bp_w * 0.22)
        for sx in sas_xs:
            P.box((sx, 0.074, bpz - 0.0052), (0.022, 0.014, 0.0085), M_CHROME, bevel=0.0006)
            P.box((sx, 0.074, bpz - 0.0105), (0.018, 0.011, 0.006), M_PLASTIC, bevel=0.0005)
        for px in (o_l + 0.022, o_r - 0.022):
            P.box((px, 0.068, bpz - 0.0050), (0.020, 0.012, 0.008), M_PLASTIC_GREY, bevel=0.0005)

        # --- ECHTE VERLEGTE MINI-SAS-HD- & FRONT-PANEL-KABEL IM GEHAEUSE (100% eingesteckt!) ---
        # Mini-SAS-Kabel B (rechts): von Backplane an der rechten Innenwand direkt in SATA0 + SATA1!
        P.box((0.207, 0.034, 0.065), (0.013, 0.011, 0.012), M_PLASTIC, bevel=0.0005)
        P.box((0.207, 0.034, 0.085), (0.013, 0.011, 0.012), M_PLASTIC, bevel=0.0005)
        P.cable([
            (sas_xs[1], 0.074, bpz - 0.012),
            (sas_xs[1] + 0.055, 0.058, 0.236),
            (0.335, 0.034, 0.232),
            (0.348, 0.028, 0.165),
            (0.346, 0.028, 0.082),
            (0.275, 0.032, 0.066),
            (0.211, 0.034, 0.065),
        ], 0.0038, M_CABLE, seg=10, subdiv=7, uv_pitch=0.022)
        P.cable([
            (0.344, 0.030, 0.145),
            (0.342, 0.030, 0.098),
            (0.275, 0.033, 0.086),
            (0.211, 0.034, 0.085),
        ], 0.0034, M_CABLE, seg=8, subdiv=6, uv_pitch=0.022)
        # Mini-SAS-Kabel A / Front-Control (links): sauber an der linken Wand direkt in FAN1-Header (-0.290, 0.034, 0.148)!
        P.box((-0.290, 0.034, 0.148), (0.012, 0.009, 0.007), M_PLASTIC, bevel=0.0004)
        P.cable([
            (sas_xs[0], 0.074, bpz - 0.012),
            (sas_xs[0] - 0.045, 0.048, 0.235),
            (-0.346, 0.028, 0.230),
            (-0.352, 0.026, 0.162),
            (-0.320, 0.030, 0.148),
            (-0.290, 0.034, 0.148),
        ], 0.0034, M_CABLE, seg=10, subdiv=7, uv_pitch=0.022)
        # Backplane-Stromkabel rechts vom rechten Power-Header sauber in den Chassis-Kabelclip am PSU-Schacht
        P.cable([
            (o_r - 0.022, 0.068, bpz - 0.009),
            (0.348, 0.055, 0.234),
            (0.352, 0.044, 0.120),
            (0.344, 0.042, -0.015),
        ], 0.0034, M_CABLE, seg=10, subdiv=7, uv_pitch=0.020)
    else:
        # Managed 24-Port Switch Frontblende
        P.box((0.0, wh * 0.5, fz - 0.002), (2.0 * hw, wh, 0.004), M_DARK_STEEL, bevel=0.0)
        for i in range(8):
            px = -0.28 + i * 0.076
            for k, d in enumerate((-0.012, 0.012)):
                lit = (i * 2 + k) % 5 != 3
                P.box((px + d, 0.112, fz + 0.0005), (0.0046, 0.0026, 0.0012), M_LED_GREEN if lit else M_PLASTIC_GREY, bevel=0.0)
        P.box((0.326, 0.070, fz + 0.0003), (0.064, 0.076, 0.0008), M_HONEY_DARK, bevel=0.0, uv_scale=0.048)
        P.box((-0.336, 0.072, fz + 0.0004), (0.016, 0.012, 0.0010), M_CAVITY, bevel=0.0)
        P.box((-0.336, 0.040, fz + 0.0005), (0.032, 0.009, 0.0010), M_ALU, bevel=0.0)


def build_caddy(P: Part, w: float, populated: bool):
    h = BAY_H - 0.001
    if not populated:
        P.box((0.0, 0.0, 0.003), (w, h, 0.006), M_PLASTIC, bevel=0.0008)
        P.box((0.0, 0.004, 0.0064), (w - 0.010, h - 0.024, 0.0010), M_HONEY_DARK, bevel=0.0, uv_scale=0.042)
        P.box((0.0, -h * 0.5 + 0.008, 0.0064), (min(0.026, w * 0.42), 0.005, 0.0010), M_GUNMETAL, bevel=0.0)
        return

    P.box((0.0, 0.0, 0.004), (w, h, 0.008), M_PLASTIC, bevel=0.0008)
    gy0, gy1 = -0.006, h * 0.5 - 0.008
    P.box((0.0, (gy0 + gy1) * 0.5, 0.0085), (w - 0.010, gy1 - gy0 + 0.003, 0.0010), M_HONEY_DARK, bevel=0.0, uv_scale=0.040)
    # Lichtleiter-LEDs (Aktivitaet gruen + Status)
    P.cyl((w * 0.5 - 0.007, h * 0.5 - 0.0045, 0.0089), 0.0017, 0.0016, M_LED_GREEN, axis="z", seg=12)
    P.cyl((w * 0.5 - 0.0125, h * 0.5 - 0.0045, 0.0089), 0.0016, 0.0016, M_LED_BLUE, axis="z", seg=12)
    # Auswurfhebel gebuerstetes Gunmetal + gruene Entriegelung + Edelstahl-Gelenkstift
    P.box((0.0, -0.024, 0.0105), (w - 0.009, 0.022, 0.0045), M_GUNMETAL, bevel=0.0008)
    P.cyl((-w * 0.5 + 0.010, -0.024, 0.0130), 0.0028, 0.0010, M_CHROME, axis="z", seg=16)
    P.box((w * 0.5 - 0.012, -0.024, 0.0132), (0.011, 0.015, 0.0020), M_LATCH_GREEN, bevel=0.0005)
    P.box((-w * 0.14, -h * 0.5 + 0.0055, 0.0085), (min(0.048, w * 0.55), 0.0068, 0.0006), M_PAPER, bevel=0.0)
    for sx in (-1.0, 1.0):
        P.box((sx * (w * 0.5 - 0.0018), 0.0, -0.052), (0.0016, h - 0.016, 0.104), M_STEEL, bevel=0.0)
    P.box((0.0, 0.0, -0.052), (w - 0.009, h - 0.030, 0.100), M_ALU, bevel=0.0010)


# ---------------------------------------------------------------------------
# 9. Hochwertige Techniker-Reparaturwerkbank (ESD-Matte + Wera-Schraubendreher
#    + Magnet-Schraubenschale + Waermeleitpaste + ESD-Pinzette!)
# ---------------------------------------------------------------------------

def build_workbench(P: Part):
    """Reparaturwerkbank unter dem Server. Chassis-Gummifuesse stehen exakt bei y = -0.006."""
    top = -0.0060
    mid = -0.0094
    desk = -0.0118

    # Edle dunkle Industrie-Arbeitsplatte mit abgeschrägter Alu/Anthrazit-Kante
    desk_outline = _round_rect(2.05, 1.50, 0.014)
    _slab(P, desk_outline, desk - 0.038, desk - 0.0012, M_EDGE_TRIM, M_EDGE_TRIM)
    _slab(P, desk_outline, desk - 0.0012, desk, M_WORKBENCH, M_EDGE_TRIM)

    # Zweilagige ESD-Matte (leitfaehige schwarze Unterlage + 1:1 PBR-ESD-Schieferblau-Matte)
    mat_w, mat_d = 1.18, 1.04
    mat_outline = _round_rect(mat_w, mat_d, 0.018)
    _slab(P, mat_outline, desk, mid, M_RUBBER, M_RUBBER)
    _slab(P, mat_outline, mid, top, M_ESD_MAT, M_RUBBER, bounds=(-mat_w * 0.5, mat_w * 0.5, -mat_d * 0.5, mat_d * 0.5))

    # Erdungsdruckknopf & sauber gewickeltes Spiralkabel hinten rechts
    sx, sz = 0.525, -0.455
    P.cyl((sx, top + 0.0008, sz), 0.0090, 0.0016, M_CHROME, seg=24)
    P.cyl((sx, top + 0.0056, sz), 0.0080, 0.0076, M_RUBBER, seg=24)
    P.cyl((sx, top + 0.0052, sz - 0.0135), 0.0036, 0.012, M_RUBBER, axis="z", seg=12)
    wire = 0.0017
    rc = 0.0058
    yc = desk + rc + wire
    z0, z1, turns, per_turn = -0.545, -0.680, 15, 8
    pts = [(sx, top + 0.0052, sz - 0.0195), (sx, top + 0.0032, sz - 0.044), (sx, top + wire, -0.518), (sx, desk + wire, -0.535)]
    steps = turns * per_turn
    for k in range(steps + 1):
        a = -math.pi * 0.5 + 2.0 * math.pi * k / per_turn
        pts.append((sx + rc * math.cos(a), yc + rc * math.sin(a), z0 + (z1 - z0) * k / steps))
    pts += [(sx + 0.022, desk + wire, -0.720), (sx + 0.026, desk - 0.006, -0.752), (sx + 0.028, desk - 0.072, -0.756)]
    P.cable(pts, wire, M_RUBBER, seg=6, subdiv=2)

    # Ergonomischer Profi-Schraubendreher (Wera/Wiha-Stil) rechts auf der Matte, frei neben dem Rack-Ohr
    sd = T((0.498, top + 0.0030, 0.010)) @ Ry(-6.0) @ Rx(-4.2)
    # Geschwaerzte PH2-Kreuzspitze + verchromter Schaft + Sechskant-Abrollschutz
    P.cyl((0.0, 0.0, 0.005), 0.0022, 0.011, M_DARK_STEEL, sd, axis="z", seg=8, r2=0.0008)
    P.cyl((0.0, 0.0, 0.056), 0.0027, 0.095, M_CHROME, sd, axis="z", seg=16)
    P.cyl((0.0, 0.0, 0.106), 0.0072, 0.010, M_RUBBER, sd, axis="z", seg=6)
    # Zweifarbiger ergonomisch taillierter Griff (Karmesinrot + schwarze Gummi-Einlagen)
    P.cyl((0.0, 0.0, 0.125), 0.0098, 0.028, M_GRIP_RED, sd, axis="z", seg=20, r2=0.0118)
    P.cyl((0.0, 0.0, 0.154), 0.0118, 0.032, M_GRIP_RED, sd, axis="z", seg=20, r2=0.0106)
    for i in range(6):
        a = 60.0 * i
        ra = math.radians(a)
        P.box((0.0108 * math.cos(ra), 0.0108 * math.sin(ra), 0.145), (0.0034, 0.0040, 0.048), M_RUBBER, sd, rot=Rz(a), bevel=0.0008)
    P.cyl((0.0, 0.0, 0.178), 0.0104, 0.016, M_RUBBER, sd, axis="z", seg=20, r2=0.0080)
    P.cyl((0.0, 0.0, 0.188), 0.0078, 0.004, M_GRIP_RED, sd, axis="z", seg=16, r2=0.0040)

    # Magnetische Edelstahl-Schraubenschale (sauber im Bild links mittig, NICHT am Rand abgeschnitten!)
    tx, tz = -0.462, -0.095
    P.cyl((tx, top + 0.0014, tz), 0.048, 0.0028, M_RUBBER, seg=40)
    P.cyl((tx, top + 0.0032, tz), 0.046, 0.0014, M_CHROME, seg=40)
    P.ring(T((tx, top + 0.0098, tz)) @ Rx(-90.0), 0.0442, 0.0462, 0.013, M_CHROME, seg=40)
    P.ring(T((tx, top + 0.0162, tz)) @ Rx(-90.0), 0.0445, 0.0505, 0.0016, M_CHROME, seg=40)
    for idx, (dx, dz, yaw) in enumerate((
        (-0.015, 0.008, 22.0), (0.012, -0.009, 78.0), (0.005, 0.018, 142.0),
        (-0.018, -0.015, 204.0), (0.019, 0.011, 305.0), (-0.002, -0.022, 48.0), (0.001, 0.002, 115.0),
    )):
        smat = M_CHROME if idx % 2 == 0 else M_DARK_STEEL
        sm = T((tx + dx, top + 0.0068, tz + dz)) @ Ry(yaw)
        P.cyl((0.0, 0.0, 0.0), 0.0016, 0.0095, smat, sm, axis="x", seg=10)
        P.cyl((0.0058, 0.0, 0.0), 0.0034, 0.0020, smat, sm, axis="x", seg=14)

    # Waermeleitpasten-Spritze (DCT-TIM PRO) links vorne auf der ESD-Matte
    sp = T((-0.465, top + 0.0080, 0.115)) @ Ry(16.0)
    P.cyl((0.0, 0.0, 0.0), 0.0076, 0.072, M_SYRINGE, sp, axis="z", seg=20)
    P.box((0.0, 0.0078, -0.004), (0.009, 0.0005, 0.036), M_RAM_LBL, sp, bevel=0.0, uv_mode="sticker_top_z")
    P.cyl((0.0, 0.0, 0.044), 0.0038, 0.018, M_PLASTIC, sp, axis="z", seg=14, r2=0.0022)
    P.cyl((0.0, 0.0, -0.048), 0.0048, 0.028, M_PLASTIC_GREY, sp, axis="z", seg=14)
    P.cyl((0.0, 0.0, -0.064), 0.0105, 0.0032, M_PLASTIC_GREY, sp, axis="z", seg=18)
    P.box((0.0, 0.0, -0.035), (0.024, 0.009, 0.0032), M_SYRINGE, sp, bevel=0.0008)

    # Praezisions-ESD-Pinzette neben der Waermeleitpaste
    tw = T((-0.456, top + 0.0022, 0.220)) @ Ry(8.0)
    P.box((-0.0032, 0.0, 0.0), (0.0024, 0.0016, 0.115), M_DARK_STEEL, tw, rot=Ry(2.4), bevel=0.0)
    P.box((0.0032, 0.0, 0.0), (0.0024, 0.0016, 0.115), M_DARK_STEEL, tw, rot=Ry(-2.4), bevel=0.0)
    P.box((0.0, 0.0, -0.056), (0.0090, 0.0022, 0.010), M_DARK_STEEL, tw, bevel=0.0004)


# ---------------------------------------------------------------------------
# Export-Ablauf
# ---------------------------------------------------------------------------

BACKGROUND_JOBS = [
    ("part_chassis_4bay", lambda P: build_chassis(P, 4)),
    ("part_chassis_8bay", lambda P: build_chassis(P, 8)),
    ("part_chassis_switch", lambda P: build_chassis(P, 0)),
    ("part_caddy_lff", lambda P: build_caddy(P, BAY_LAYOUT[4][2], True)),
    ("part_caddy_lff_blank", lambda P: build_caddy(P, BAY_LAYOUT[4][2], False)),
    ("part_caddy_sff", lambda P: build_caddy(P, BAY_LAYOUT[8][2], True)),
    ("part_caddy_sff_blank", lambda P: build_caddy(P, BAY_LAYOUT[8][2], False)),
    ("prop_workbench", build_workbench),
]


def clear_scene():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in list(bpy.data.meshes):
        bpy.data.meshes.remove(me)
    for mat in list(bpy.data.materials):
        bpy.data.materials.remove(mat)
    for img in list(bpy.data.images):
        bpy.data.images.remove(img)
    for ng in list(bpy.data.node_groups):
        bpy.data.node_groups.remove(ng)


# ---------------------------------------------------------------------------
# 10. Kaputte / beschaedigte Bauteil-Varianten (alle 7 Kategorien!)
# ---------------------------------------------------------------------------

def build_mainboard_broken(P: Part, is_ai: bool):
    """Kaputtes Mainboard: verbrannte 2K-Platine, geplatzte schiefe Elkos, verkohlter VRM & PCH."""
    build_mainboard(P, M_MB_BLACK_BRK if is_ai else M_MB_GREEN_BRK)
    top = 0.0060
    # Zwei geplatzte, schraeg gekippte Elkos + Russ-Krater hinten am VRM
    for cx, cz, tilt_x, tilt_z in ((-0.0975, -0.175, 16.0, -14.0), (-0.0645, -0.175, -18.0, 12.0)):
        cm = T((cx, top + 0.002, cz)) @ Rx(tilt_x) @ Rz(tilt_z)
        P.cyl((0.0, 0.006, 0.0), 0.0052, 0.014, M_SCORCH, cm, seg=14)
        P.cyl((0.0, 0.0135, 0.0), 0.0055, 0.0018, M_BURN, cm, seg=14)
    # Russflecken & verkohlte Deckschichten auf VRM-Kuehler, PCH und Front-Ecke
    P.box((-0.078, top + 0.0278, -0.140), (0.042, 0.0020, 0.032), M_BURN, rot=Ry(8.0), bevel=0.0, uv_scale=0.06)
    P.box((0.184, top + 0.0178, 0.072), (0.046, 0.0018, 0.044), M_BURN, rot=Ry(-12.0), bevel=0.0, uv_scale=0.06)
    P.box((0.192, top + 0.0042, -0.040), (0.026, 0.0014, 0.026), M_BURN, bevel=0.0, uv_scale=0.05)


def build_cpu_broken(P: Part):
    """Kaputter Prozessor / Kuehler: schraeg geloester, verbeulter & angebrannter Kuehlkoerper + verkohlte Leitpaste."""
    # Beschaedigter LGA-Sockel & verkohlter CPU-Rand
    for sz in (-0.0565, 0.0565):
        P.box((0.0, 0.0026, sz), (0.118, 0.0052, 0.0052), M_DARK_STEEL, bevel=0.0006)
    for sx in (-0.0565, 0.0565):
        P.box((sx, 0.0026, 0.0), (0.0052, 0.0052, 0.108), M_DARK_STEEL, bevel=0.0006)
    P.box((0.0, 0.0035, 0.0), (0.108, 0.0070, 0.108), M_PLASTIC, bevel=0.0008)
    P.box((0.0, 0.0084, 0.0), (0.086, 0.0022, 0.086), M_PCB_SUB_G, bevel=0.0)
    # Verkohlter Heatspreader
    P.box((0.0, 0.0124, 0.0), (0.072, 0.0032, 0.072), M_SCORCH, bevel=0.0006, uv_scale=0.08)
    P.box((-0.006, 0.0144, 0.008), (0.048, 0.0010, 0.044), M_BURN, rot=Ry(14.0), bevel=0.0, uv_scale=0.05)

    # Schraeg gekippter, verbeulter Kuehlkoerper (5.5° gekippt) mit verbogenen/abgeknickten Lamellen
    tilt = T((0.003, 0.017, 0.002)) @ Rx(4.5) @ Rz(-5.5)
    P.box((0.0, 0.003, 0.0), (0.102, 0.005, 0.102), M_SCORCH, tilt, bevel=0.0008, uv_scale=0.08)
    for i in range(13):
        fx = -0.045 + i * 0.0075
        bend = 0.0 if i < 6 else (8.0 + (i - 6) * 2.2)
        h_cut = 0.036 if i < 8 else 0.029
        fin_mat = M_BURN if 6 <= i <= 10 else (M_SCORCH if i >= 4 else M_ALU)
        P.box((fx, 0.006 + h_cut * 0.5, 0.0), (0.0032, h_cut, 0.084), fin_mat, tilt, rot=Rz(bend), bevel=0.0, uv_scale=0.08)
    # Lockere schiefe Kuehlerschraube
    P.cyl((-0.044, 0.025, 0.046), 0.0046, 0.006, M_CHROME, T((0, 0, 0)) @ Rx(22.0), seg=12)


def build_ram_broken(P: Part):
    """Kaputter RAM: 2 Module halb aus dem Slot gesprungen, verbrannte DRAM-Chips & aufgebrochene Verriegelung."""
    chips = (-0.058, -0.046, -0.034, -0.022, 0.006, 0.018, 0.030, 0.042, 0.054)
    for i in range(8):
        rx = -0.063 + i * 0.018
        slot_m = M_PLASTIC if (i % 2 == 0) else M_GUNMETAL
        P.box((rx, 0.0042, 0.0), (0.0076, 0.0122, 0.146), slot_m, bevel=0.0005)
        P.box((rx, 0.0104, 0.0), (0.0022, 0.0005, 0.138), M_CAVITY, bevel=0.0)
        is_bad = i in (2, 3)
        for z in (-0.071, 0.071):
            _dimm_latch(P, rx, z, not is_bad and i < 6)
        if i >= 6:
            continue
        if is_bad:
            # Halb ausgerastet, schief gekippt & angebrannt!
            tilt_x = 9.0 if i == 2 else -11.0
            lift = 0.011 if i == 2 else 0.008
            mc = T((rx + (0.003 if i == 3 else -0.002), lift, 0.0)) @ Rx(tilt_x) @ Rz(-5.0 if i == 2 else 6.0)
            P.box((0.0, 0.0215, 0.0), (0.0016, 0.031, 0.133), M_BURN, mc, bevel=0.0, uv_scale=0.06)
            for z0, z1 in ((-0.0655, -0.0055), (-0.0025, 0.0655)):
                P.box((0.0, 0.0085, (z0 + z1) * 0.5), (0.0018, 0.005, z1 - z0), M_SCORCH, mc, bevel=0.0, uv_scale=0.05)
            for side in (-1.0, 1.0):
                for cz in chips:
                    P.box((side * 0.0011, 0.0230, cz), (0.0009, 0.0082, 0.0095), M_BURN, mc, bevel=0.0, uv_scale=0.04)
        else:
            mc = T((rx, 0.0, 0.0))
            P.box((0.0, 0.0215, 0.0), (0.0014, 0.031, 0.133), M_PCB_SUB_G, mc, bevel=0.0)
            for side in (-1.0, 1.0):
                P.box((side * 0.0022, 0.026, 0.0), (0.0011, 0.030, 0.129), M_GUNMETAL, mc, bevel=0.0)
            P.box((0.0029, 0.023, -0.028), (0.0004, 0.013, 0.054), M_RAM_LBL, mc, bevel=0.0, uv_mode="sticker_x")


def build_gpu_broken(P: Part):
    """Kaputte GPU: haengt schief im PCIe-Slot, abgebrochene Luefterblaetter (steht still!) & verbrannter Stromstecker/Backplate."""
    _pcie_slot(P, 0.0)
    card_len = 0.27
    card_h = 0.086
    half = card_len * 0.5
    mid = card_h * 0.5
    cz = -0.155 + half
    # Karte haengt 5.5° nach vorne/aussen durch!
    M = T((0.0, 0.008, cz)) @ Rz(-5.5) @ Rx(-2.2)

    P.box((0.0, mid, 0.0), (0.0032, card_h, card_len), M_PCB_SUB_B, M, bevel=0.0)
    P.box((-0.0034, mid + 0.003, 0.002), (0.0018, card_h - 0.008, card_len - 0.010), M_SCORCH, M, bevel=0.0005, uv_scale=0.10)
    # Brandkrater direkt sichtbar auf der Backplate & Oberkante
    P.box((-0.0046, mid + 0.012, 0.028), (0.0008, 0.042, 0.068), M_BURN, M, rot=Rx(12.0), bevel=0.0, uv_scale=0.06)
    # Slotblech hinten
    bz = -half - 0.003
    P.box((0.012, mid + 0.004, bz), (0.036, card_h + 0.010, 0.0022), M_STEEL, M, bevel=0.0)

    face_x = 0.027
    fan_r = 0.032
    fan_zs = (-0.060, 0.060)
    cut = fan_r + 0.0022
    P.fins((0.011, mid, 0.0), (0.012, card_h - 0.010, card_len - 0.024), 16, 2, M_SCORCH, M, fill_ratio=0.44)
    P.box((face_x, card_h - 0.004, 0.0), (0.0045, 0.0085, card_len - 0.008), M_DARK_STEEL, M, bevel=0.0008)
    P.box((face_x, 0.004, 0.0), (0.0045, 0.0085, card_len - 0.008), M_DARK_STEEL, M, bevel=0.0008)
    inner_h = card_h - 0.016
    seg_start = -half + 0.004
    for fz in fan_zs:
        seg_end = fz - cut
        if seg_end > seg_start + 0.001:
            P.box((face_x, mid, (seg_start + seg_end) * 0.5), (0.0045, inner_h, seg_end - seg_start), M_DARK_STEEL, M, bevel=0.0008)
        seg_start = fz + cut
    last_end = half - 0.004
    if last_end > seg_start + 0.001:
        P.box((face_x, mid, (seg_start + last_end) * 0.5), (0.0045, inner_h, last_end - seg_start), M_DARK_STEEL, M, bevel=0.0008)

    # Beide Rotoren stillgelegt (NICHT Rotor_X_*, sondern fest in Body!); vorderer Rotor hat abgebrochene Blaetter + schiefe Nabe
    for idx, fz in enumerate(fan_zs):
        P.ring(M @ T((face_x, mid, fz)) @ Ry(90.0), fan_r + 0.001, cut, 0.0045, M_SCORCH if idx == 1 else M_DARK_STEEL, square=True, seg=32)
        rm = M @ T((face_x - 0.002, mid, fz)) @ Ry(90.0) @ (Rx(14.0) if idx == 1 else I4)
        P.rotor(rm, fan_r - 0.001, 11, M_BURN if idx == 1 else M_BLADE_GPU, M_GUNMETAL,
                skip_blades=(0, 1, 2, 6, 7) if idx == 1 else (3,))

    # Verbrannter 8-Pin-PCIe-Stromstecker oben vorne + Russ
    P.box((0.009, card_h + 0.0055, half - 0.032), (0.012, 0.012, 0.024), M_BURN, M, rot=Ry(8.0), bevel=0.0006, uv_scale=0.05)
    P.box((0.012, card_h + 0.001, half - 0.032), (0.026, 0.003, 0.055), M_BURN, M, bevel=0.0, uv_scale=0.06)


def build_storage_broken(P: Part):
    """Kaputte M.2 NVMe: geloeste Schraube -> Modul steht 17° hoch, angeknackste Ecke & verkohlter Controller."""
    length = 0.080
    x0 = -0.052
    board_x0 = x0 - 0.004
    by = 0.0035
    for i in range(2):
        mz = -0.032 + i * 0.034
        P.box((x0 - 0.0035, 0.0026, mz), (0.0095, 0.0092, 0.0255), M_PLASTIC, bevel=0.0005)
        P.box((x0 + 0.0014, by, mz), (0.0012, 0.0030, 0.021), M_CAVITY, bevel=0.0)
        if i == 0:
            # Geloester Riegel steht deutlich sichtbar schraeg nach oben + stark verkohlt!
            M = T((board_x0, by, mz)) @ Rz(17.0)
            P.box((length * 0.5, 0.0, 0.0), (length, 0.0012, 0.022), M_BURN, M, bevel=0.0, uv_scale=0.05)
            P.box((0.003, 0.0, 0.0), (0.006, 0.0014, 0.020), M_GOLD, M, bevel=0.0)
            P.box((0.019, 0.0012, 0.0), (0.015, 0.0016, 0.015), M_BURN, M, rot=Ry(12.0), bevel=0.0, uv_scale=0.04)
            P.box((0.048, 0.0012, 0.0), (0.042, 0.0008, 0.018), M_SCORCH, M, bevel=0.0, uv_scale=0.06)
            # Leerer Abstandshalter am Boardende (Schraube rausgesprungen)
            P.cyl((board_x0 + length - 0.0015, 0.00055, mz), 0.0028, 0.0051, M_GOLD, seg=12)
        else:
            xc = board_x0 + length * 0.5
            P.box((xc, by, mz), (length, 0.0010, 0.022), M_PCB_SUB_B, bevel=0.0)
            P.box((board_x0 + 0.048, by + 0.0018, mz), (0.046, 0.0003, 0.019), M_NVME_LBL, bevel=0.0, uv_mode="sticker_top_x")


def build_cooling_broken(P: Part):
    """Kaputte Luefterwand: mittlerer 92mm-Luefter schief herausgerutscht, 3 Blaetter abgebrochen (steht still!),
    verbrannte Motornabe & abgerissenes PWM-Kabel."""
    fan_count = 3
    spacing = 0.115
    start_x = -(fan_count - 1) * spacing * 0.5
    width = (fan_count - 1) * spacing + 0.114
    P.box((0.0, 0.0014, 0.0), (width, 0.0028, 0.046), M_DARK_STEEL, bevel=0.0)
    for i in range(fan_count + 1):
        dx = start_x - spacing * 0.5 + i * spacing
        P.box((dx, 0.048, -0.021), (0.0028, 0.095, 0.008), M_DARK_STEEL, bevel=0.0)

    for i in range(fan_count):
        pos = Vector((start_x + i * spacing, 0.048, 0.0))
        if i != 1:
            _server_fan(P, i, pos)
            continue
        # Mittlerer Luefter (i=1): deutlich sichtbar schief/ausgehoben + abgebrochene Blaetter + Brandfleck!
        M = T(pos + Vector((0.0, 0.016, 0.006))) @ Rx(-9.0) @ Rz(7.0)
        P.ring(M, 0.0432, 0.0465, 0.038, M_SCORCH, square=True, seg=32)
        P.cyl((0.0, 0.0, -0.0165), 0.018, 0.0045, M_BURN, M, axis="z", seg=20)
        P.box((0.0, 0.0535, 0.008), (0.036, 0.0036, 0.012), M_GRIP_RED, M, bevel=0.0008)
        P.box((0.0345, -0.039, 0.0196), (0.0036, 0.0024, 0.0008), M_CAVITY, M, bevel=0.0)
        # Abgebrochener, feststehender Rotor (kein Rotor_Z_* -> dreht sich nicht!)
        P.rotor(M @ T((0.0, 0.0, 0.002)), 0.0415, 9, M_BURN, M_BURN,
                hub_ratio=0.38, depth_ratio=0.52, sweep=0.65, cap_mat=M_SCORCH, skip_blades=(0, 1, 4, 5))
        # Hangendes durchgebranntes Kabel
        P.cable([(0.036, -0.020, -0.016), (0.048, -0.038, -0.028), (0.056, -0.052, -0.018)], 0.0020, M_BURN, M, seg=8)


def build_psu_broken(P: Part):
    """Kaputtes Netzteil: verbranntes/eingedelltes Waben-Lochblech, angekohlter 80-PLUS-Aufkleber,
    verschmorte Kabeltuelle & schief hängender 24-Pin-Stecker."""
    size = (0.125, 0.092, 0.30)
    sx, sy, sz = size
    half = Vector(size) * 0.5
    cy = 0.048

    # Angebranntes Netzteilgehaeuse
    P.box((0.0, cy, 0.0), size, M_SCORCH, bevel=0.0018, uv_scale=0.16)
    # Eingedelltes & verkohltes Lueftungsgitter oben
    grill_w = sx - 0.016
    grill_d = sz * 0.52
    grill_z = -0.028
    P.box((0.0, cy + half.y + 0.0005, grill_z), (grill_w + 0.005, 0.0014, grill_d + 0.005), M_BURN, bevel=0.0, uv_scale=0.06)
    P.box((0.0, cy + half.y + 0.0008, grill_z), (grill_w, 0.0008, grill_d), M_HONEY_DARK, rot=Rx(-4.0) @ Rz(3.5), bevel=0.0, uv_scale=0.062)
    # Stark sichtbarer Brandfleck & aufgeplatzter Becher-Kondensator durch das Gitter ragend
    P.box((-0.012, cy + half.y + 0.0022, grill_z + 0.010), (0.064, 0.0018, 0.078), M_BURN, rot=Ry(18.0), bevel=0.0, uv_scale=0.05)
    P.cyl((0.005, cy + half.y + 0.001, grill_z - 0.01), 0.010, 0.012, M_BURN, rot=Rz(18.0), seg=16)

    # Angesengtes Typenschild oben vorne
    P.box((0.0, cy + half.y + 0.0007, 0.095), (sx - 0.016, 0.0005, 0.072), M_PSU_LBL_STD, bevel=0.0, uv_mode="sticker_top_x")
    P.box((-0.022, cy + half.y + 0.0012, 0.082), (0.052, 0.0006, 0.044), M_BURN, rot=Ry(24.0), bevel=0.0, uv_scale=0.05)

    # Hinterer Luefter angebrannt / festgefressen
    rz = -half.z
    P.cyl((0.0, cy + sy * 0.12, rz - 0.002), min(sx, sy) * 0.35, 0.004, M_BURN, axis="z", seg=20)
    _c14_inlet(P, -0.044, 0.020, rz - 0.0014)

    # Verschmortes, halb rausgezogenes 24-Pin-Kabel
    P.new_group("Cable_ATX24", (-0.060, 0.035, 0.100))
    P.box((-0.086, 0.042, 0.044), (0.017, 0.014, 0.090), M_BURN, rot=Rx(11.0) @ Rz(-9.0), bevel=0.0008, group="Cable_ATX24", uv_scale=0.05)
    for k in range(5):
        z_plug = 0.008 + k * 0.015
        pts = [(-0.036, 0.032, 0.148), (-0.064, 0.056, 0.125), (-0.086, 0.048, z_plug)]
        P.cable(pts, 0.0031, M_BURN if k % 2 == 0 else M_CABLE, seg=8, subdiv=5, group="Cable_ATX24", uv_pitch=0.022)


def main():
    global TEX_PATHS
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    out_dir = os.path.abspath(argv[0]) if argv else os.path.abspath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models"))
    os.makedirs(out_dir, exist_ok=True)

    cache_dir = os.path.join(SCRIPT_DIR, "_pbr_cache")
    print("Generating/updating 2K PBR textures...")
    TEX_PATHS = pbr_textures.generate_all(cache_dir)

    jobs = [
        ("part_mainboard", lambda P: build_mainboard(P, M_MB_GREEN)),
        ("part_mainboard_ai", lambda P: build_mainboard(P, M_MB_BLACK)),
        ("part_mainboard_broken", lambda P: build_mainboard_broken(P, False)),
        ("part_mainboard_ai_broken", lambda P: build_mainboard_broken(P, True)),
        ("part_cpu_broken", build_cpu_broken),
        ("part_ram_broken", build_ram_broken),
        ("part_gpu_broken", build_gpu_broken),
        ("part_storage_broken", build_storage_broken),
        ("part_cooling_broken", build_cooling_broken),
        ("part_psu_broken", build_psu_broken),
    ]
    builders = [
        ("cpu", build_cpu), ("ram", build_ram), ("gpu", build_gpu),
        ("storage", build_storage), ("cooling", build_cooling), ("psu", build_psu),
    ]
    for cat, fn in builders:
        for tier in range(4):
            jobs.append(("part_%s_t%d" % (cat, tier), lambda P, fn=fn, tier=tier: fn(P, tier)))
    jobs += BACKGROUND_JOBS

    for name, build in jobs:
        clear_scene()
        part = Part()
        build(part)
        rotors = sum(1 for k in part.order if k.startswith("Rotor_"))
        faces = part.export(os.path.join(out_dir, name + ".glb"))
        print("PART %s: %d Flaechen, %d Rotoren" % (name, faces, rotors))
    print("PARTS DONE: %d Dateien in %s" % (len(jobs), out_dir))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
