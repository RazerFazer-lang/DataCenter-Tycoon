"""AAA Blender-5.2-Generator fuer die Server-Racks 'rack' (4U Standard) & 'rack_pro' (6U Pro Enterprise).

Aufruf (Hintergrundmodus — erzeugt Texturen, baut beide Racks, speichert dct_racks.blend UND exportiert .glb):
    blender --background --factory-startup --python-exit-code 1 \
        --python tools/blender/build_racks.py

Koordinaten: Blender Z oben, Front -Y (wird beim glTF-Export zu Godot +Z), Rueckseite +Y (Godot -Z), Boden Z=0.
Bewegliche Knoten (kompatibel zu rack_prop.gd):
    <var>_Hinge_FrontDoor, <var>_Hinge_RearDoor_L, <var>_Hinge_RearDoor_R  ("dct_open_deg")
    <var>_Panel_Side_L, <var>_Panel_Side_R                                 ("dct_slide_x", "dct_closed_x")
    <var>_Fan_Roof_L, <var>_Fan_Roof_R                                     (drehen um Z -> Godot Y)
3 hintere Industrie-Anschluesse direkt im Modell:
    - Oben links  (-0.25, +0.46, height - 0.08): PWR 230V/32A IEC C19
    - Oben rechts (+0.25, +0.46, height - 0.08): LAN 100G RJ45/SFP+
    - Unten Mitte ( 0.00, +0.454, 0.115):        LINK Cluster Interconnect (Dual-Fiber)
"""

import math
import os
import sys
import traceback

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import rack_pbr_textures

COLLECTION = "DCT_Racks"
OUT_MODELS_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", "assets", "models"))

U = 0.04445
HW = 0.464               # halbe Dachbreite
FRAME = 0.450            # Aussenkante Rahmenprofil
RAIL_X = 0.386           # 19-Zoll-Schienenmitte
RAIL_Y = 0.372           # Schienenabstand von Mitte (vorne/hinten)
PLINTH_TOP = 0.172       # Oberkante Sockel
ROOF_T = 0.028           # Dachblechstaerke inkl. Abkantung
HEADER_H = 0.160         # Kopfzone ueber den Tueren
DOOR_OPEN_DEG = 105.0
SIDE_SLIDE = 0.36        # Ausfahrweg beim Abnehmen der Seitenwand

VARIANTS = {
    "rack": {"height": 2.12, "x": -0.80, "is_pro": False},
    "rack_pro": {"height": 2.48, "x": 0.80, "is_pro": True},
}


# ---------------------------------------------------------------------------
# PBR-Material-Builder (glTF 2.0 kompatibel mit ORM + Normal + Alpha-Mask/Blend)
# ---------------------------------------------------------------------------

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


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


def _principled(mat):
    if bpy.app.version < (5, 0, 0):
        mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (450, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (100, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return nt, bsdf


def make_pbr_mat(name: str, tex_paths: dict, norm_str: float = 1.0, alpha_clip: bool = False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt, bsdf = _principled(mat)

    n_alb = nt.nodes.new("ShaderNodeTexImage")
    n_alb.image = _load_img(tex_paths["albedo"], "sRGB")
    n_alb.location = (-360, 220)
    nt.links.new(n_alb.outputs["Color"], bsdf.inputs["Base Color"])

    if alpha_clip:
        n_gt = nt.nodes.new("ShaderNodeMath")
        n_gt.operation = "GREATER_THAN"
        n_gt.inputs[1].default_value = 0.5
        n_gt.location = (-100, 120)
        nt.links.new(n_alb.outputs["Alpha"], n_gt.inputs[0])
        nt.links.new(n_gt.outputs["Value"], bsdf.inputs["Alpha"])
        mat.use_backface_culling = False

    n_orm = nt.nodes.new("ShaderNodeTexImage")
    n_orm.image = _load_img(tex_paths["orm"], "Non-Color")
    n_orm.location = (-360, -40)
    n_sep = nt.nodes.new("ShaderNodeSeparateColor")
    n_sep.location = (-100, -40)
    nt.links.new(n_orm.outputs["Color"], n_sep.inputs["Color"])
    nt.links.new(n_sep.outputs["Green"], bsdf.inputs["Roughness"])
    nt.links.new(n_sep.outputs["Blue"], bsdf.inputs["Metallic"])

    ao_grp = nt.nodes.new("ShaderNodeGroup")
    ao_grp.node_tree = _ensure_gltf_ao_group()
    ao_grp.location = (120, -240)
    nt.links.new(n_sep.outputs["Red"], ao_grp.inputs["Occlusion"])

    n_nrm = nt.nodes.new("ShaderNodeTexImage")
    n_nrm.image = _load_img(tex_paths["normal"], "Non-Color")
    n_nrm.location = (-360, -320)
    n_nmap = nt.nodes.new("ShaderNodeNormalMap")
    n_nmap.inputs["Strength"].default_value = norm_str
    n_nmap.location = (-100, -320)
    nt.links.new(n_nrm.outputs["Color"], n_nmap.inputs["Color"])
    nt.links.new(n_nmap.outputs["Normal"], bsdf.inputs["Normal"])
    return mat


def make_solid_mat(name: str, srgb, metallic: float, roughness: float,
                   alpha: float = 1.0, emission=None, emit_str: float = 0.0, double_sided: bool = False):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    _nt, bsdf = _principled(mat)
    lin = tuple(srgb_to_linear(c) for c in srgb)
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    if emission is not None and emit_str > 0.0:
        elin = tuple(srgb_to_linear(c) for c in emission)
        bsdf.inputs["Emission Color"].default_value = (*elin, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_str
    mat.diffuse_color = (*lin, alpha)
    mat.metallic = metallic
    mat.roughness = roughness
    if double_sided:
        mat.use_backface_culling = False
    return mat


def build_materials(tp: dict):
    return {
        "powder": make_pbr_mat("Rack_PowderBlack", tp["powder_black"], norm_str=0.85),
        "powder_pro": make_pbr_mat("Rack_PowderPro", tp["powder_pro"], norm_str=0.85),
        "hex_mesh": make_pbr_mat("Rack_HexMesh", tp["hex_mesh"], norm_str=1.1, alpha_clip=True),
        "rail": make_pbr_mat("Rack_RailNumbered", tp["rail_numbered"], norm_str=0.9),
        "alu": make_pbr_mat("Rack_AluTrim", tp["alu_trim"], norm_str=0.65),
        "gold": make_pbr_mat("Rack_GoldTitan", tp["gold_titan"], norm_str=0.65),
        "galv": make_pbr_mat("Rack_GalvSteel", tp["galv_steel"], norm_str=0.70),
        "pdu": make_pbr_mat("Rack_PduBody", tp["pdu_body"], norm_str=0.65),
        "port_pwr": make_pbr_mat("Rack_PortPwrPlate", tp["port_pwr"], norm_str=0.5),
        "port_lan": make_pbr_mat("Rack_PortLanPlate", tp["port_lan"], norm_str=0.5),
        "port_link": make_pbr_mat("Rack_PortLinkPlate", tp["port_link"], norm_str=0.5),
        "badge_std": make_pbr_mat("Rack_BadgeStd", tp["badge_std"], norm_str=0.5),
        "badge_pro": make_pbr_mat("Rack_BadgePro", tp["badge_pro"], norm_str=0.5),
        "glass": make_solid_mat("Rack_SmokedGlass", (0.04, 0.065, 0.09), 0.06, 0.07, alpha=0.20, double_sided=True),
        "lcd_glass": make_solid_mat("Rack_LcdGlass", (0.015, 0.022, 0.030), 0.10, 0.12),
        "chrome": make_solid_mat("Rack_Chrome", (0.88, 0.89, 0.91), 0.98, 0.14),
        "brass": make_solid_mat("Rack_BrassPins", (0.88, 0.70, 0.24), 0.96, 0.22),
        "plastic": make_solid_mat("Rack_PlasticMatte", (0.045, 0.048, 0.055), 0.0, 0.46),
        "rubber": make_solid_mat("Rack_Rubber", (0.032, 0.034, 0.038), 0.0, 0.88),
        "hole": make_solid_mat("Rack_Cavity", (0.012, 0.013, 0.016), 0.0, 0.94),
        "brush": make_solid_mat("Rack_Brush", (0.025, 0.026, 0.030), 0.0, 0.96),
        "fan": make_solid_mat("Rack_FanBlade", (0.09, 0.095, 0.105), 0.10, 0.44),
        "breaker": make_solid_mat("Rack_BreakerRed", (0.68, 0.08, 0.06), 0.05, 0.38),
        "pdu_lcd": make_solid_mat("Rack_PduLcd", (0.10, 0.78, 0.34), 0.0, 0.25, emission=(0.12, 0.92, 0.38), emit_str=2.2),
        "amber_trim": make_solid_mat("Rack_AccentAmber", (0.86, 0.65, 0.16), 0.35, 0.36),
        "blue_trim": make_solid_mat("Rack_AccentBlue", (0.18, 0.48, 0.86), 0.35, 0.36),
        "purple_trim": make_solid_mat("Rack_AccentPurple", (0.60, 0.32, 0.86), 0.35, 0.36),
        "led_bar": make_solid_mat("Rack_InteriorLed", (0.96, 0.97, 1.0), 0.0, 0.25, emission=(0.95, 0.97, 1.0), emit_str=1.6),
    }


# ---------------------------------------------------------------------------
# Geometrie-Helfer mit sauberer Triangulation & orientierter UV-Projektion
# ---------------------------------------------------------------------------

class Part:
    """Sammelt Geometrie im Rack-Raum (Blender Z oben, Front -Y) relativ zu origin."""

    def __init__(self, name, origin=(0.0, 0.0, 0.0)):
        self.name = name
        self.origin = Vector(origin)
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.mats = []

    def _index(self, mat):
        if mat not in self.mats:
            self.mats.append(mat)
        return self.mats.index(mat)

    def _finish(self, verts, mat, uv_scale=0.35, smooth_axis=None, uv_mode="box", center=None, size=None):
        idx = self._index(mat)
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.normal_update()
            f.material_index = idx
            n = f.normal
            if uv_mode == "front_plate" and center is not None and size is not None:
                # Front -Y: links=-X (u=0), rechts=+X (u=1), oben=+Z (v=1)
                cx, _cy, cz = center
                sx, _sy, sz = size
                for loop in f.loops:
                    co = loop.vert.co + self.origin
                    loop[self.uv].uv = ((co.x - cx) / sx + 0.5, (co.z - cz) / sz + 0.5)
            elif uv_mode == "rear_plate" and center is not None and size is not None:
                # Rueck +Y (man schaut von hinten nach vorne): links=+X (u=0), rechts=-X (u=1), oben=+Z (v=1)!
                cx, _cy, cz = center
                sx, _sy, sz = size
                for loop in f.loops:
                    co = loop.vert.co + self.origin
                    loop[self.uv].uv = (0.5 - (co.x - cx) / sx, (co.z - cz) / sz + 0.5)
            elif uv_mode == "rail_v" and center is not None and size is not None:
                cx, _cy, _cz = center
                sx = max(size[0], 0.001)
                for loop in f.loops:
                    co = loop.vert.co + self.origin
                    loop[self.uv].uv = ((co.x - cx) / sx + 0.5, co.z / (8.0 * U))
            else:
                ax = max(range(3), key=lambda i: abs(n[i]))
                a, b = ((1, 2), (0, 2), (0, 1))[ax]
                for loop in f.loops:
                    co = loop.vert.co + self.origin
                    loop[self.uv].uv = (co[a] / uv_scale, co[b] / uv_scale)
            if smooth_axis is not None and abs(n.dot(smooth_axis)) < 0.5:
                f.smooth = True

    def box_m(self, matrix, mat, uv=0.35):
        m = Matrix.Translation(-self.origin) @ matrix
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"]
        self._finish(verts, mat, uv)

    def box(self, center, size, mat, uv=0.35, rot=(0.0, 0.0, 0.0), uv_mode="box"):
        m = (Matrix.Translation(Vector(center)) @ Euler(rot).to_matrix().to_4x4()
             @ Matrix.Diagonal((size[0], size[1], size[2], 1.0)))
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=Matrix.Translation(-self.origin) @ m)["verts"]
        self._finish(verts, mat, uv, uv_mode=uv_mode, center=center, size=size)

    def quad_y(self, center, width, height, y_normal_sign, mat, uv=0.055):
        """Einschichtige Flaeche in der XZ-Ebene (ideal fuer rauchgetoentes Glas & alpha-clipped Wabenblech ohne Sortierfehler!)."""
        cx, cy, cz = center
        hw, hh = width * 0.5, height * 0.5
        if y_normal_sign < 0:
            pts = [(cx - hw, cy, cz - hh), (cx + hw, cy, cz - hh), (cx + hw, cy, cz + hh), (cx - hw, cy, cz + hh)]
        else:
            pts = [(cx + hw, cy, cz - hh), (cx - hw, cy, cz - hh), (cx - hw, cy, cz + hh), (cx + hw, cy, cz + hh)]
        vs = [self.bm.verts.new(Vector(p) - self.origin) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = self._index(mat)
        for loop in f.loops:
            co = loop.vert.co + self.origin
            loop[self.uv].uv = (co.x / uv, co.z / uv)

    def quad_x(self, center, depth, height, x_normal_sign, mat, uv=0.055):
        """Einschichtige Flaeche in der YZ-Ebene (ideal fuer Seiten-Glasfenster!)."""
        cx, cy, cz = center
        hd, hh = depth * 0.5, height * 0.5
        if x_normal_sign > 0:
            pts = [(cx, cy - hd, cz - hh), (cx, cy + hd, cz - hh), (cx, cy + hd, cz + hh), (cx, cy - hd, cz + hh)]
        else:
            pts = [(cx, cy + hd, cz - hh), (cx, cy - hd, cz - hh), (cx, cy - hd, cz + hh), (cx, cy + hd, cz + hh)]
        vs = [self.bm.verts.new(Vector(p) - self.origin) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = self._index(mat)
        for loop in f.loops:
            co = loop.vert.co + self.origin
            loop[self.uv].uv = (co.y / uv, co.z / uv)

    def cyl(self, center, radius, depth, mat, axis="Z", segs=18):
        rot = {
            "X": Euler((0.0, math.pi / 2, 0.0)),
            "Y": Euler((math.pi / 2, 0.0, 0.0)),
            "Z": Euler((0.0, 0.0, 0.0)),
        }[axis].to_matrix().to_4x4()
        m = Matrix.Translation(Vector(center) - self.origin) @ rot
        verts = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=segs,
            radius1=radius, radius2=radius, depth=depth, matrix=m,
        )["verts"]
        axis_v = (rot.to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized()
        self._finish(verts, mat, 0.35, smooth_axis=axis_v)

    def rotor_z(self, center, radius, count, blade_mat, hub_mat):
        """Aerodynamisches 9-Blatt-Dachluefterrad (dreht um Z = Godot Y)."""
        cx, cy, cz = center
        hub_r = radius * 0.30
        thick = 0.0028
        steps = 6
        b_idx = self._index(blade_mat)
        for i in range(count):
            base = 2.0 * math.pi * i / count
            lt, tt, lb, tb = [], [], [], []
            for k in range(steps):
                s = k / float(steps - 1)
                rr = hub_r * 0.90 + (radius - hub_r * 0.90) * s
                ca = base + 0.55 * s
                half = math.pi / count * (0.78 - 0.16 * s)
                depth = 0.026 * (1.0 - 0.35 * s)
                for ang, zoff, top_l, bot_l in ((ca + half, depth * 0.5, lt, lb), (ca - half, -depth * 0.5, tt, tb)):
                    vx = cx + rr * math.cos(ang)
                    vy = cy + rr * math.sin(ang)
                    top_l.append(self.bm.verts.new(Vector((vx, vy, cz + zoff + thick * 0.5)) - self.origin))
                    bot_l.append(self.bm.verts.new(Vector((vx, vy, cz + zoff - thick * 0.5)) - self.origin))
            for k in range(steps - 1):
                for vs in (
                    (lt[k], lt[k + 1], tt[k + 1], tt[k]),
                    (lb[k], tb[k], tb[k + 1], lb[k + 1]),
                    (lt[k], lb[k], lb[k + 1], lt[k + 1]),
                    (tt[k], tt[k + 1], tb[k + 1], tb[k]),
                ):
                    f = self.bm.faces.new(vs)
                    f.material_index = b_idx
                    f.smooth = True
                    for loop in f.loops:
                        loop[self.uv].uv = (loop.vert.co.x * 4.0, loop.vert.co.y * 4.0)
            for vs in ((lt[0], tt[0], tb[0], lb[0]), (lt[-1], lb[-1], tb[-1], tt[-1])):
                f = self.bm.faces.new(vs)
                f.material_index = b_idx
        self.cyl(center, hub_r, 0.024, hub_mat, axis="Z", segs=24)

    def build(self, coll, parent, parent_origin=(0.0, 0.0, 0.0)):
        bmesh.ops.recalc_face_normals(self.bm, faces=list(self.bm.faces))
        ngons = [f for f in self.bm.faces if len(f.verts) > 4]
        if ngons:
            bmesh.ops.triangulate(self.bm, faces=ngons)
        me = bpy.data.meshes.new(self.name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        me.update()
        ob = bpy.data.objects.new(self.name, me)
        coll.objects.link(ob)
        ob.parent = parent
        ob.location = self.origin - Vector(parent_origin)
        return ob


def make_empty(coll, name, parent, loc, parent_origin=(0.0, 0.0, 0.0), size=0.08):
    e = bpy.data.objects.new(name, None)
    coll.objects.link(e)
    e.empty_display_type = "ARROWS"
    e.empty_display_size = size
    e.parent = parent
    e.location = Vector(loc) - Vector(parent_origin)
    return e


def plate_with_holes(part, x0, x1, y0, y1, z0, z1, holes, mat):
    xs = sorted({x0, x1, *[h[0] for h in holes], *[h[1] for h in holes]})
    ys = sorted({y0, y1, *[h[2] for h in holes], *[h[3] for h in holes]})
    zc = (z0 + z1) * 0.5
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            cx = (xs[i] + xs[i + 1]) * 0.5
            cy = (ys[j] + ys[j + 1]) * 0.5
            if any(h[0] < cx < h[1] and h[2] < cy < h[3] for h in holes):
                continue
            part.box((cx, cy, zc), (xs[i + 1] - xs[i], ys[j + 1] - ys[j], z1 - z0), mat)


# ---------------------------------------------------------------------------
# Baugruppen
# ---------------------------------------------------------------------------

def _build_rear_ports(fr: Part, height: float, m: dict):
    """Baut die 3 realistischen 3D-Industrie-Buchsen direkt an der Rueckseite (+Y):
        1) Oben links  (-0.25, +0.460, top_y): PWR 230V/32A IEC C19 mit gelbem Rahmen
        2) Oben rechts (+0.25, +0.460, top_y): LAN 100G RJ45/SFP+ mit blauem Rahmen
        3) Unten Mitte ( 0.00, +0.454, 0.115): LINK Cluster Interconnect mit violettem Rahmen
    """
    top_y = height - 0.080

    # --- 1) STROM-PORT OBEN LINKS (x = -0.25, z = top_y) ---
    px, py = -0.25, 0.460
    fr.box((px, py, top_y), (0.245, 0.012, 0.116), m["port_pwr"], uv_mode="rear_plate")
    # 3D IEC C19 / CEE Industrie-Buchsenkragen + 3 Messing-Kontakte
    bx = px - 0.020
    fr.box((bx, py + 0.014, top_y - 0.004), (0.086, 0.022, 0.056), m["plastic"])
    fr.box((bx, py + 0.016, top_y - 0.004), (0.092, 0.012, 0.062), m["amber_trim"])
    fr.box((bx, py + 0.0255, top_y - 0.004), (0.068, 0.002, 0.038), m["hole"])
    for ox, oz in ((-0.018, -0.006), (0.0, 0.009), (0.018, -0.006)):
        fr.box((bx + ox, py + 0.021, top_y - 0.004 + oz), (0.005, 0.012, 0.011), m["brass"])
    # LED-Fassung rechts neben Buchse (-0.145)
    fr.cyl((px + 0.105, py + 0.009, top_y - 0.002), 0.012, 0.008, m["chrome"], axis="Y", segs=16)

    # --- 2) LAN-PORT OBEN RECHTS (x = +0.25, z = top_y) ---
    nx, ny = 0.25, 0.460
    fr.box((nx, ny, top_y), (0.245, 0.012, 0.116), m["port_lan"], uv_mode="rear_plate")
    # 3D Dual-RJ45 + SFP+ Uplink-Kaefig aus gebuerstetem Edelstahl
    lx = nx - 0.020
    fr.box((lx, ny + 0.013, top_y - 0.004), (0.092, 0.020, 0.056), m["alu"])
    fr.box((lx, ny + 0.015, top_y - 0.004), (0.098, 0.010, 0.062), m["blue_trim"])
    for ox in (-0.022, 0.022):
        fr.box((lx + ox, ny + 0.0235, top_y - 0.004), (0.028, 0.002, 0.026), m["hole"])
        fr.box((lx + ox, ny + 0.0225, top_y - 0.013), (0.018, 0.003, 0.004), m["brass"])
    fr.cyl((nx + 0.105, ny + 0.009, top_y - 0.002), 0.012, 0.008, m["chrome"], axis="Y", segs=16)

    # --- 3) RACK-VERBINDUNGS- / CLUSTER-PORT GANZ UNTEN MITTIG AM RUECKSOCKEL (x = 0.0, z = 0.115) ---
    cx, cy, cz = 0.0, 0.454, 0.115
    fr.box((cx, cy, cz), (0.285, 0.014, 0.098), m["port_link"], uv_mode="rear_plate")
    # Robuster Dual-Glasfaser / High-Speed-Cluster-Koppler (fuer bis zu 2 verbundene Nachbar-Racks)
    fr.box((cx - 0.015, cy + 0.015, cz - 0.003), (0.126, 0.022, 0.050), m["pdu"])
    fr.box((cx - 0.015, cy + 0.016, cz - 0.003), (0.132, 0.010, 0.056), m["purple_trim"])
    for ox in (-0.030, 0.030):
        fr.box((cx - 0.015 + ox, cy + 0.0265, cz - 0.003), (0.038, 0.002, 0.026), m["hole"])
        fr.box((cx - 0.015 + ox, cy + 0.024, cz + 0.013), (0.028, 0.008, 0.004), m["chrome"])
        fr.box((cx - 0.015 + ox, cy + 0.024, cz - 0.019), (0.028, 0.008, 0.004), m["chrome"])
    fr.cyl((cx + 0.105, cy + 0.010, cz - 0.002), 0.012, 0.008, m["chrome"], axis="Y", segs=16)


def build_frame(coll, root, variant, height, is_pro, m):
    top = height - HEADER_H
    roof_z0 = height - ROOF_T
    body_mat = m["powder_pro"] if is_pro else m["powder"]
    trim_mat = m["gold"] if is_pro else m["alu"]

    fr = Part(f"{variant}_Frame")
    post_h = roof_z0 - PLINTH_TOP
    pz = PLINTH_TOP + post_h * 0.5

    # 4 schwere pulverbeschichtete Eckpfosten (L-Profil)
    for sx in (-1, 1):
        for sy in (-1, 1):
            fr.box((sx * (FRAME - 0.024), sy * (FRAME - 0.003), pz), (0.048, 0.006, post_h), body_mat)
            fr.box((sx * (FRAME - 0.003), sy * (FRAME - 0.024), pz), (0.006, 0.048, post_h), body_mat)
        # Gebuerstete Alu- (Standard) bzw. Gold-Titan-Zierleisten (Pro) an den vorderen Ecken!
        fr.box((sx * (FRAME + 0.003), -FRAME + 0.004, pz), (0.012, 0.016, post_h - 0.02), trim_mat)

    # Untere & obere Rahmen-Quertraeger
    for z in (PLINTH_TOP + 0.020, roof_z0 - 0.020):
        for sy in (-1, 1):
            fr.box((0.0, sy * (FRAME - 0.020), z), (2 * FRAME - 0.09, 0.040, 0.040), body_mat)
        for sx in (-1, 1):
            fr.box((sx * (FRAME - 0.020), 0.0, z), (0.040, 2 * FRAME - 0.09, 0.040), body_mat)

    # --- KOPFBLENDE VORNE (-Y) MIT INTEGRIERTEM OLED/LCD-DISPLAY-RAHMEN & MARKENPLAKETTE ---
    hdr_zc = (top + roof_z0) * 0.5
    hdr_h = roof_z0 - top
    fr.box((0.0, -0.454, hdr_zc), (0.912, 0.014, hdr_h), body_mat)
    # Zierstreifen oben & unten an der Front-Kopfblende
    fr.box((0.0, -0.4615, roof_z0 - 0.004), (0.914, 0.004, 0.006), trim_mat)
    fr.box((0.0, -0.4615, top + 0.004), (0.914, 0.004, 0.006), trim_mat)

    # Eingelassenes OLED/LCD-Display mittig in der Kopfblende (Breite 0.44m, Hoehe 0.096m)
    lcd_w, lcd_h = 0.44, 0.092
    fr.box((0.0, -0.461, hdr_zc), (lcd_w + 0.016, 0.008, lcd_h + 0.014), trim_mat)
    fr.box((0.0, -0.4628, hdr_zc), (lcd_w, 0.006, lcd_h), m["lcd_glass"])
    # Markenplakette links neben dem OLED-Display
    badge_mat = m["badge_pro"] if is_pro else m["badge_std"]
    fr.box((-0.342, -0.462, hdr_zc), (0.185, 0.004, 0.050), badge_mat, uv_mode="front_plate")
    # Dezente Status-Streifen rechts neben dem OLED-Display
    for k in range(3):
        fr.box((0.310 + k * 0.040, -0.462, hdr_zc), (0.022, 0.004, 0.006), trim_mat)

    # --- KOPFBLENDE HINTEN (+Y) + ALLE 3 RUECKWAND-ANSCHLUESSE (PWR, LAN oben; LINK ganz unten) ---
    fr.box((0.0, 0.454, hdr_zc), (0.912, 0.014, hdr_h), body_mat)
    _build_rear_ports(fr, height, m)

    # --- INTERNE LED-LICHTLEISTE UNTER DER VORDEREN DACHKANTE ---
    fr.box((0.0, -0.385, top - 0.010), (0.68, 0.024, 0.014), m["alu"])
    fr.box((0.0, -0.385, top - 0.018), (0.64, 0.014, 0.004), m["led_bar"])

    # --- NUMMERIERTE 19-ZOLL-MONTAGESCHIENEN (Z-Profil) + VERTIKALE KABELMANAGEMENT-FINGERKANAELE ---
    rail_z0 = PLINTH_TOP + 0.045
    rail_z1 = roof_z0 - 0.040
    rail_len = rail_z1 - rail_z0
    rail_zc = (rail_z0 + rail_z1) * 0.5
    n_u = int((top - 0.01 - rail_z0) / U)
    for sx in (-1, 1):
        for sy in (-1, 1):
            fr.box((sx * RAIL_X, sy * RAIL_Y, rail_zc), (0.026, 0.003, rail_len), m["rail"], uv_mode="rail_v")
            fr.box((sx * (RAIL_X + 0.013), sy * (RAIL_Y - 0.016), rail_zc), (0.003, 0.032, rail_len), m["galv"])
        # Tiefenstreben oben, mittig & unten
        for z in (PLINTH_TOP + 0.022, rail_zc, roof_z0 - 0.022):
            fr.box((sx * (RAIL_X + 0.022), 0.0, z), (0.018, 0.80, 0.020), m["galv"])

        # Vertikaler Kabelmanagement-Kanal hinten innen (mit geformten Kabel-Fingern!)
        kx, ky = sx * 0.412, 0.285
        fr.box((kx, ky, rail_zc), (0.022, 0.044, rail_len - 0.10), m["plastic"])
        fingers = int((rail_len - 0.16) / 0.068)
        for fi in range(fingers):
            fz = rail_z0 + 0.08 + fi * 0.068
            fr.box((kx - sx * 0.014, ky + 0.012, fz), (0.024, 0.008, 0.010), m["plastic"])

    fr.build(coll, root)
    return n_u


def build_plinth_and_feet(coll, root, variant, is_pro, m):
    body_mat = m["powder_pro"] if is_pro else m["powder"]
    trim_mat = m["gold"] if is_pro else m["alu"]

    pl = Part(f"{variant}_Plinth")
    pl.box((0.0, 0.0, 0.115), (0.904, 0.904, 0.112), body_mat)
    # Feine Metall-Zierleiste unten vorne am Sockel
    pl.box((0.0, -0.453, 0.168), (0.906, 0.004, 0.006), trim_mat)

    # Vorderseite (-Y): volle belueftete Sockel-Schlitze
    pl.box((0.0, -0.4525, 0.115), (0.72, 0.002, 0.072), m["hole"])
    for v in range(15):
        pl.box((-0.35 + v * 0.05, -0.4535, 0.115), (0.028, 0.004, 0.066), body_mat)

    # Rueckseite (+Y): Lueftungsschlitze sauber LINKS & RECHTS neben dem mittleren Cluster-Port!
    for side_x in (-0.285, 0.285):
        pl.box((side_x, 0.4525, 0.115), (0.21, 0.002, 0.072), m["hole"])
        for k in range(5):
            pl.box((side_x - 0.09 + k * 0.045, 0.4535, 0.115), (0.022, 0.004, 0.066), body_mat)
    pl.build(coll, root)

    # 4 Schwerlast-Lenkrollen + 4 Nivellierfuesse
    cs = Part(f"{variant}_Casters")
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * 0.37, sy * 0.37
            cs.box((cx, cy, 0.058), (0.074, 0.074, 0.005), m["galv"])
            cs.cyl((cx, cy, 0.053), 0.015, 0.007, m["chrome"])
            for side in (-1, 1):
                cs.box((cx + side * 0.014, cy, 0.035), (0.004, 0.032, 0.032), m["galv"])
            cs.cyl((cx, cy, 0.022), 0.022, 0.022, m["rubber"], axis="X", segs=22)
            cs.cyl((cx, cy, 0.022), 0.005, 0.032, m["chrome"], axis="X", segs=10)
            fx, fy = sx * 0.295, sy * 0.395
            cs.box((fx, fy, 0.056), (0.020, 0.020, 0.008), m["galv"])
            cs.cyl((fx, fy, 0.033), 0.006, 0.046, m["chrome"], segs=12)
            cs.cyl((fx, fy, 0.012), 0.017, 0.004, m["galv"])
            cs.cyl((fx, fy, 0.005), 0.022, 0.010, m["rubber"])
    cs.build(coll, root)


def build_roof(coll, root, variant, height, is_pro, m):
    body_mat = m["powder_pro"] if is_pro else m["powder"]
    trim_mat = m["gold"] if is_pro else m["alu"]

    rf = Part(f"{variant}_Roof")
    fan_holes = [(-0.35, -0.05, -0.10, 0.20), (0.05, 0.35, -0.10, 0.20)]
    brush_front = (-0.24, 0.24, -0.355, -0.285)
    brush_rear = (-0.24, 0.24, 0.285, 0.355)
    plate_with_holes(rf, -HW, HW, -HW, HW, height - 0.002, height, fan_holes + [brush_front, brush_rear], body_mat)

    for s in (-1, 1):
        rf.box((0.0, s * (HW - 0.0015), height - 0.014), (2 * HW, 0.003, 0.028), body_mat)
        rf.box((s * (HW - 0.0015), 0.0, height - 0.014), (0.003, 2 * HW - 0.004, 0.028), body_mat)

    # Kabeleinfuehrungs-Buerstenleisten vorne & hinten
    bz = height - 0.010
    for by in (-0.320, 0.320):
        rf.box((0.0, by - 0.017, bz), (0.48, 0.032, 0.016), m["brush"])
        rf.box((0.0, by + 0.017, bz), (0.48, 0.032, 0.016), m["brush"])

    # 2 grosse Dach-Abluftluefter (180 mm) mit durchsichtigem Waben-Schutzgitter & Chrom-Ringen
    fans = []
    for i, (hx0, hx1, hy0, hy1) in enumerate(fan_holes):
        fx, fy = (hx0 + hx1) * 0.5, (hy0 + hy1) * 0.5
        # Durchsichtiges Wabenblech oben auf dem Dach
        rf.box((fx, fy, height + 0.0005), (hx1 - hx0 + 0.014, hy1 - hy0 + 0.014, 0.002), m["hex_mesh"], uv=0.055)
        # Rahmenkranz um den Luefterauslass
        for s in (-1, 1):
            rf.box((fx + s * 0.154, fy, height + 0.002), (0.010, 0.316, 0.005), trim_mat if is_pro else m["pdu"])
            rf.box((fx, fy + s * 0.154, height + 0.002), (0.316, 0.010, 0.005), trim_mat if is_pro else m["pdu"])
            rf.box((fx + s * 0.148, fy, height - 0.024), (0.005, 0.30, 0.044), m["plastic"])
            rf.box((fx, fy + s * 0.148, height - 0.024), (0.30, 0.005, 0.044), m["plastic"])
        rf.cyl((fx, fy, height - 0.036), 0.038, 0.020, m["plastic"], segs=22)
        for ang in (math.pi / 4, -math.pi / 4):
            rf.box((fx, fy, height - 0.044), (0.40, 0.009, 0.004), m["plastic"], rot=(0.0, 0.0, ang))
        fans.append((fx, fy, "L" if i == 0 else "R"))
    rf.build(coll, root)

    for fx, fy, tag in fans:
        zc = height - 0.021
        fan = Part(f"{variant}_Fan_Roof_{tag}", origin=(fx, fy, zc))
        fan.rotor_z((fx, fy, zc), 0.132, 9, m["fan"], m["plastic"])
        fan.build(coll, root)


def build_front_door(coll, root, variant, z0, z1, is_pro, m):
    """Fronttuer: feines durchsichtiges Wabenblech aussen + grosses zentrales Rauchglas-Sichtfenster!"""
    hinge_x = 0.450
    hy = -0.466
    hinge = make_empty(coll, f"{variant}_Hinge_FrontDoor", root, (hinge_x, hy, 0.0))
    hinge["dct_open_deg"] = DOOR_OPEN_DEG  # oeffnet sauber nach rechts aussen (+105° in Godot)

    body_mat = m["powder_pro"] if is_pro else m["powder"]
    trim_mat = m["gold"] if is_pro else m["alu"]

    d = Part(f"{variant}_FrontDoor", origin=(hinge_x, hy, 0.0))
    x0, x1 = -0.448, 0.448
    t, dep = 0.036, 0.020
    yc = -0.458
    cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
    w, h = x1 - x0, z1 - z0
    inner_h = h - 2 * t

    # Aeusserer Tuerrahmen (Stahl-Rechteckrohr)
    d.box((cx, yc, z1 - t * 0.5), (w, dep, t), body_mat)
    d.box((cx, yc, z0 + t * 0.5), (w, dep, t), body_mat)
    d.box((x0 + t * 0.5, yc, cz), (t, dep, inner_h), body_mat)
    d.box((x1 - t * 0.5, yc, cz), (t, dep, inner_h), body_mat)

    # Vertikale Sprossen trennen die 2 aeusseren Wabenblech-Fluegel vom zentralen Glasfenster!
    glass_hw = 0.275  # 55 cm breites klares Rauchglas-Sichtfenster (Server-Fronten voll sichtbar!)
    for sx in (-1, 1):
        mx = sx * (glass_hw + 0.009)
        d.box((mx, yc, cz), (0.018, dep, inner_h), body_mat)
        # Feine gebuerstete Alu-/Gold-Zierkante direkt am Glasrand
        d.box((sx * (glass_hw + 0.002), yc - dep * 0.5 - 0.001, cz), (0.005, 0.004, inner_h), trim_mat)
        # Durchsichtiger Waben-Lochblech-Fluegel links & rechts neben dem Glas
        wing_x0 = x0 + t if sx < 0 else (glass_hw + 0.018)
        wing_x1 = -(glass_hw + 0.018) if sx < 0 else (x1 - t)
        d.quad_y(((wing_x0 + wing_x1) * 0.5, -0.464, cz), wing_x1 - wing_x0 + 0.006, inner_h + 0.006, -1, m["hex_mesh"], uv=0.052)

    # Zentrales rauchgetoentes Echtglas-Sichtfenster (einschichtig -> 0 Sortierfehler!)
    d.quad_y((cx, -0.462, cz), glass_hw * 2.0 + 0.004, inner_h + 0.004, -1, m["glass"], uv=0.5)

    # 3 verchromte Lift-Off-Scharniere rechts
    for hz in (z0 + 0.14, cz, z1 - 0.14):
        d.cyl((hinge_x, hy, hz), 0.0075, 0.054, m["chrome"], segs=14)

    # Hochwertiger Enterprise-Schwenkgriff links
    hx = x0 + t * 0.5
    zh = min(1.12, cz)
    d.box((hx, -0.471, zh), (0.032, 0.010, 0.22), m["plastic"])
    d.box((hx, -0.477, zh + 0.022), (0.018, 0.007, 0.14), trim_mat)
    d.box((hx, -0.482, zh + 0.082), (0.018, 0.008, 0.024), m["chrome"])
    d.cyl((hx, -0.476, zh - 0.078), 0.008, 0.007, m["chrome"], axis="Y", segs=16)
    d.box((hx, -0.480, zh - 0.078), (0.0018, 0.0010, 0.008), m["hole"])

    d.build(coll, hinge, (hinge_x, hy, 0.0))


def build_rear_door(coll, root, variant, name, hinge_x, x0, x1, z0, z1, is_pro, m, handle=True):
    """Geteilte Hecktuer mit durchsichtigem Waben-Lochblech (laesst obere & untere Ports komplett frei!)."""
    hy = 0.466
    open_dir = 1.0 if (x0 + x1) * 0.5 > hinge_x else -1.0
    hinge = make_empty(coll, f"{variant}_Hinge_{name}", root, (hinge_x, hy, 0.0))
    hinge["dct_open_deg"] = DOOR_OPEN_DEG * open_dir

    body_mat = m["powder_pro"] if is_pro else m["powder"]
    d = Part(f"{variant}_{name}", origin=(hinge_x, hy, 0.0))
    t, dep = 0.032, 0.018
    yc = 0.458
    cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
    w, h = x1 - x0, z1 - z0
    inner_h = h - 2 * t

    d.box((cx, yc, z1 - t * 0.5), (w, dep, t), body_mat)
    d.box((cx, yc, z0 + t * 0.5), (w, dep, t), body_mat)
    d.box((x0 + t * 0.5, yc, cz), (t, dep, inner_h), body_mat)
    d.box((x1 - t * 0.5, yc, cz), (t, dep, inner_h), body_mat)
    d.box((cx, 0.453, cz), (w - 2 * t, 0.008, 0.022), body_mat)
    d.quad_y((cx, 0.464, cz), w - 2 * t + 0.008, inner_h + 0.008, 1, m["hex_mesh"], uv=0.052)

    for hz in (z0 + 0.14, cz, z1 - 0.14):
        d.cyl((hinge_x, hy, hz), 0.007, 0.050, m["chrome"], segs=12)

    hx = x0 + t * 0.5 if open_dir < 0 else x1 - t * 0.5
    if handle:
        zh = min(1.10, cz)
        d.box((hx, 0.470, zh), (0.028, 0.008, 0.19), m["plastic"])
        d.box((hx, 0.476, zh + 0.018), (0.015, 0.006, 0.12), m["chrome"])
        d.cyl((hx, 0.475, zh - 0.068), 0.007, 0.006, m["chrome"], axis="Y", segs=14)
    else:
        d.box((hx, 0.470, z1 - 0.06), (0.010, 0.006, 0.075), m["galv"])
        d.box((hx, 0.470, z0 + 0.06), (0.010, 0.006, 0.075), m["galv"])

    d.build(coll, hinge, (hinge_x, hy, 0.0))


def build_side_panel(coll, root, variant, sx, z0, z1, is_pro, m):
    """Abnehmbare Seitenwand mit grossem getoentem Glas-Sichtfenster (Mainboards & GPUs von aussen sichtbar!)."""
    tag = "L" if sx < 0 else "R"
    cx, cz = sx * 0.455, (z0 + z1) * 0.5
    e = make_empty(coll, f"{variant}_Panel_Side_{tag}", root, (cx, 0.0, cz))
    e["dct_slide_x"] = sx * SIDE_SLIDE
    e["dct_closed_x"] = cx

    body_mat = m["powder_pro"] if is_pro else m["powder"]
    trim_mat = m["gold"] if is_pro else m["alu"]

    p = Part(f"{variant}_SidePanel_{tag}", origin=(cx, 0.0, cz))
    h = z1 - z0
    depth = 0.892
    frame_y = 0.095   # vordere/hintere Stahl-Seitenrahmen
    frame_top = 0.165 # oberer Stahlstreifen (enthaelt Griffmulden & Schloss)
    frame_bot = 0.110 # unterer Stahlstreifen

    win_d = depth - 2 * frame_y
    win_z0 = z0 + frame_bot
    win_z1 = z1 - frame_top
    win_h = win_z1 - win_z0
    win_zc = (win_z0 + win_z1) * 0.5

    # Stahlrahmen um das grosse Seiten-Sichtfenster
    p.box((cx, 0.0, z1 - frame_top * 0.5), (0.014, depth, frame_top), body_mat)
    p.box((cx, 0.0, z0 + frame_bot * 0.5), (0.014, depth, frame_bot), body_mat)
    for sy in (-1, 1):
        p.box((cx, sy * (depth * 0.5 - frame_y * 0.5), win_zc), (0.014, frame_y, win_h), body_mat)

    # Dezente Zier-Einfassung rund um das Glasfenster
    for sz in (win_z0 + 0.004, win_z1 - 0.004):
        p.box((cx + sx * 0.006, 0.0, sz), (0.004, win_d + 0.012, 0.008), trim_mat)
    for sy in (-1, 1):
        p.box((cx + sx * 0.006, sy * (win_d * 0.5 + 0.004), win_zc), (0.004, 0.008, win_h + 0.012), trim_mat)

    # Grosses rauchgetoentes Echtglas-Seitenfenster (einschichtig!)
    p.quad_x((cx, 0.0, win_zc), win_d + 0.006, win_h + 0.006, sx, m["glass"], uv=0.5)

    # Griffmulden & Chrom-Schloss im oberen Stahlrahmen (gut greifbar zum Abnehmen!)
    gz = z1 - frame_top * 0.5
    for gy in (-0.24, 0.24):
        p.box((cx + sx * 0.008, gy, gz), (0.004, 0.115, 0.038), m["plastic"])
        p.box((cx + sx * 0.0102, gy, gz), (0.0014, 0.094, 0.020), m["hole"])
    p.cyl((cx + sx * 0.0085, 0.0, gz), 0.011, 0.005, m["chrome"], axis="X", segs=16)
    p.box((cx + sx * 0.0112, 0.0, gz), (0.0008, 0.0018, 0.009), m["hole"])

    # Lueftungsschlitze im unteren Stahlstreifen
    for k in range(10):
        ly = -0.32 + k * 0.071
        p.box((cx + sx * 0.0075, ly, z0 + frame_bot * 0.5), (0.002, 0.036, 0.042), m["hole"])

    p.build(coll, e, (cx, 0.0, cz))


def build_pdu(coll, root, variant, height, is_pro, m):
    """Vertikale 0U-Enterprise-PDU hinten rechts (Pro-Rack: Dual-Redundant A+B mit Gold/Alu-Akzent!)."""
    top = height - HEADER_H
    roof_z0 = height - ROOF_T
    p = Part(f"{variant}_PDU")
    xs = (0.375, 0.424) if is_pro else (0.418,)
    py = 0.402
    z0, z1 = 0.28, top - 0.10
    total_outlets = 0
    for idx, px in enumerate(xs):
        p.box((px, py, (z0 + z1) * 0.5), (0.042, 0.048, z1 - z0), m["pdu"])
        if is_pro:
            # A/B-Farbstreifen (Gold fuer Feed A, Alu fuer Feed B)
            p.box((px, py + 0.0245, (z0 + z1) * 0.5), (0.005, 0.002, z1 - z0 - 0.04), m["gold"] if idx == 0 else m["alu"])
        n = int((z1 - z0 - 0.14) / 0.050)
        total_outlets += n
        for i in range(n):
            z = z0 + 0.07 + i * 0.050
            p.box((px, py + 0.0255, z), (0.028, 0.004, 0.036), m["plastic"])
            p.box((px, py + 0.0278, z), (0.019, 0.0015, 0.024), m["hole"])
        # Beleuchtetes Amp/Watt-LCD & roter Sicherungsautomat oben an der PDU
        p.box((px, py + 0.0252, z1 - 0.035), (0.028, 0.0020, 0.018), m["pdu_lcd"])
        p.box((px, py + 0.0258, z1 - 0.070), (0.016, 0.0030, 0.024), m["breaker"])
        p.cyl((px, py, (z1 + roof_z0) * 0.5), 0.0075, roof_z0 - z1, m["rubber"], segs=12)
    p.build(coll, root)
    return total_outlets


def build_rack(coll, variant, cfg, m):
    height = cfg["height"]
    is_pro = cfg["is_pro"]
    top = height - HEADER_H
    roof_z0 = height - ROOF_T

    root = bpy.data.objects.new(variant, None)
    coll.objects.link(root)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.2
    root.location = (cfg["x"], 0.0, 0.0)
    root["dct_model_id"] = variant

    n_u = build_frame(coll, root, variant, height, is_pro, m)
    build_plinth_and_feet(coll, root, variant, is_pro, m)
    build_roof(coll, root, variant, height, is_pro, m)

    door_z0, door_z1 = PLINTH_TOP + 0.006, top - 0.004
    build_front_door(coll, root, variant, door_z0, door_z1, is_pro, m)
    build_rear_door(coll, root, variant, "RearDoor_L", -0.450, -0.446, -0.002, door_z0, door_z1, is_pro, m, handle=False)
    build_rear_door(coll, root, variant, "RearDoor_R", 0.450, 0.002, 0.446, door_z0, door_z1, is_pro, m, handle=True)
    for sx in (-1, 1):
        build_side_panel(coll, root, variant, sx, PLINTH_TOP + 0.004, roof_z0 - 0.002, is_pro, m)
    outlets = build_pdu(coll, root, variant, height, is_pro, m)
    return root, n_u, outlets


# ---------------------------------------------------------------------------
# Export & Szene
# ---------------------------------------------------------------------------

def clear_all():
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


def export_rack_glb(root, out_dir):
    objs = [root] + list(root.children_recursive)
    saved_loc = root.location.copy()
    path = os.path.join(out_dir, str(root["dct_model_id"]) + ".glb")
    try:
        root.location = (0.0, 0.0, 0.0)
        bpy.context.view_layer.update()
        for o in bpy.context.view_layer.objects:
            o.select_set(False)
        for o in objs:
            o.hide_set(False)
            o.select_set(True)
        bpy.context.view_layer.objects.active = root
        bpy.ops.export_scene.gltf(
            filepath=path,
            export_format="GLB",
            use_selection=True,
            export_yup=True,
            export_apply=True,
            export_extras=True,
            export_normals=True,
            export_tangents=True,
        )
    finally:
        root.location = saved_loc
        bpy.context.view_layer.update()
    return path


def main():
    clear_all()
    cache_dir = os.path.join(SCRIPT_DIR, "_pbr_cache")
    print("Generating rack PBR textures...")
    tp = rack_pbr_textures.generate_rack_textures(cache_dir)

    coll = bpy.data.collections.new(COLLECTION)
    bpy.context.scene.collection.children.link(coll)
    m = build_materials(tp)

    os.makedirs(OUT_MODELS_DIR, exist_ok=True)
    roots = []
    for variant, cfg in VARIANTS.items():
        root, n_u, outlets = build_rack(coll, variant, cfg, m)
        roots.append(root)
        meshes = [o for o in root.children_recursive if o.type == "MESH"]
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
        movable = sorted(o.name for o in root.children_recursive if "dct_open_deg" in o or "dct_slide_x" in o)
        glb_path = export_rack_glb(root, OUT_MODELS_DIR)
        print(f"{variant}: {len(meshes)} Meshes, {tris} Dreiecke, {n_u} HE, {outlets} PDU-Dosen -> {os.path.getsize(glb_path)/1024.0:.1f} KB")
        print(f"  beweglich: {', '.join(movable)}")

    blend_path = os.path.join(SCRIPT_DIR, "dct_racks.blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path)
    print(f"RACKS DONE: {blend_path}")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        traceback.print_exc()
        sys.exit(1)
