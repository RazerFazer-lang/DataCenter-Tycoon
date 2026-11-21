"""Baut die Server-Racks "rack" (Standard) und "rack_pro" (Enterprise) fuer DataCenter Tycoon.

Aufruf in Blender:
    p = r"<pfad>/build_racks.py"
    exec(compile(open(p, encoding="utf-8").read(), p, "exec"), {"__name__": "__main__", "__file__": p})

Koordinaten: Blender Z oben, Front zeigt nach -Y (wird beim glTF-Export zu Godot +Z), Boden bei Z=0.
Bewegliche Teile:
    <variante>_Hinge_FrontDoor, _Hinge_RearDoor_L, _Hinge_RearDoor_R
        Empty auf der Scharnierachse, Drehung um Z (Godot: Y). Property "dct_open_deg" = Oeffnungswinkel.
    <variante>_Panel_Side_L, _Panel_Side_R
        Empty in der Seitenwandmitte, wird abgenommen. Property "dct_slide_x" = Weg nach aussen (m).
    <variante>_Fan_Roof_L, _Fan_Roof_R
        Lueferrad mit Ursprung in der Nabe, dreht um Z (Godot: Y).
Das Skript ist wiederholbar: es leert die Collection "DCT_Racks" und baut alles neu.
"""
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

COLLECTION = "DCT_Racks"
U = 0.04445              # 1 Hoeheneinheit (HE) in Metern
HW = 0.462               # halbe Dachbreite
FRAME = 0.448            # Aussenkante Rahmenprofil
RAIL_X = 0.385           # Schienenmitte; die Spielserver sind 0,76 m breit
RAIL_Y = 0.37            # Abstand der Schienen von der Mitte (vorne/hinten)
PLINTH_TOP = 0.17        # Oberkante Sockel
ROOF_T = 0.025           # Dachblechstaerke inkl. Kantung
HEADER_H = 0.16          # Kopfzone ueber den Tueren (Strom-/Netzanschluss im Spiel)
PERF_TILE = 0.012        # Kachelgroesse der Lochblech-Textur in Metern
DOOR_OPEN_DEG = 105.0
SIDE_SLIDE = 0.30

VARIANTS = {
    "rack": {"height": 2.12, "x": -0.75, "preview_open": False},
    "rack_pro": {"height": 2.48, "x": 0.75, "preview_open": True},
}

try:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
except NameError:
    SCRIPT_DIR = ""


# ---------------------------------------------------------------------------
# Materialien
# ---------------------------------------------------------------------------

def _principled(mat):
    try:
        if not mat.use_nodes:
            mat.use_nodes = True
    except AttributeError:
        pass
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    out.location = (300, 0)
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.location = (0, 0)
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return nt, bsdf


def make_mat(name, color, metallic, roughness, emission=None, strength=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    _nt, bsdf = _principled(mat)
    rgba = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (emission[0], emission[1], emission[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = strength
    mat.diffuse_color = rgba
    mat.metallic = metallic
    mat.roughness = roughness
    return mat


def perforation_image():
    """Versetztes Rundloch-Muster (Lochabstand 8,5 mm, Loch 6,6 mm, ca. 48 % offen)."""
    name = "DCT_Perforation"
    old = bpy.data.images.get(name)
    if old is not None:
        bpy.data.images.remove(old)
    n = 96
    tile_mm = PERF_TILE * 1000.0
    radius = 3.3
    aa = 0.25
    steel = 0.15  # sRGB-Wert der schwarzen Pulverbeschichtung
    img = bpy.data.images.new(name, n, n, alpha=True)
    centers = ((3.0, 3.0), (9.0, 9.0))
    half = tile_mm * 0.5
    px = [0.0] * (n * n * 4)
    for j in range(n):
        y = (j + 0.5) * tile_mm / n
        for i in range(n):
            x = (i + 0.5) * tile_mm / n
            d = 1e9
            for cx, cy in centers:
                dx = ((x - cx + half) % tile_mm) - half
                dy = ((y - cy + half) % tile_mm) - half
                d = min(d, math.hypot(dx, dy))
            alpha = min(1.0, max(0.0, (d - radius) / aa + 0.5))
            k = (j * n + i) * 4
            px[k] = steel
            px[k + 1] = steel
            px[k + 2] = steel * 1.05
            px[k + 3] = alpha
    img.pixels.foreach_set(px)
    img.update()
    img.pack()
    return img


def make_perf_mat(img):
    name = "DCT_PerforatedSteel"
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    nt, bsdf = _principled(mat)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = img
    tex.interpolation = "Linear"
    tex.location = (-520, 0)
    rnd = nt.nodes.new("ShaderNodeMath")
    rnd.operation = "ROUND"  # glTF-Export erkennt das als Alpha-Clip (MASK)
    rnd.location = (-250, -180)
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(tex.outputs["Alpha"], rnd.inputs[0])
    nt.links.new(rnd.outputs[0], bsdf.inputs["Alpha"])
    bsdf.inputs["Metallic"].default_value = 0.0
    bsdf.inputs["Roughness"].default_value = 0.55
    try:
        mat.surface_render_method = "DITHERED"
    except (AttributeError, TypeError):
        pass
    mat.use_backface_culling = False
    mat.diffuse_color = (0.02, 0.02, 0.022, 1.0)
    return mat


def build_materials():
    return {
        "powder": make_mat("DCT_PowderBlack", (0.018, 0.019, 0.021), 0.0, 0.52),
        "galv": make_mat("DCT_GalvSteel", (0.55, 0.56, 0.57), 1.0, 0.36),
        "zinc": make_mat("DCT_ZincPlated", (0.70, 0.70, 0.68), 1.0, 0.28),
        "hole": make_mat("DCT_HoleDark", (0.002, 0.002, 0.002), 0.0, 0.95),
        "rubber": make_mat("DCT_Rubber", (0.012, 0.012, 0.012), 0.0, 0.88),
        "plastic": make_mat("DCT_PlasticBlack", (0.015, 0.015, 0.016), 0.0, 0.42),
        "chrome": make_mat("DCT_Chrome", (0.85, 0.85, 0.86), 1.0, 0.10),
        "fan": make_mat("DCT_FanBlade", (0.02, 0.02, 0.022), 0.0, 0.50),
        "brush": make_mat("DCT_Brush", (0.006, 0.006, 0.006), 0.0, 1.0),
        "pdu": make_mat("DCT_PduAlu", (0.02, 0.021, 0.023), 1.0, 0.40),
        "label": make_mat("DCT_Label", (0.75, 0.75, 0.72), 0.0, 0.60),
        "breaker": make_mat("DCT_BreakerRed", (0.35, 0.02, 0.02), 0.0, 0.45),
        "lcd": make_mat("DCT_PduDisplay", (0.05, 0.6, 0.15), 0.0, 0.30, emission=(0.05, 0.9, 0.2), strength=3.0),
        "perf": make_perf_mat(perforation_image()),
    }


# ---------------------------------------------------------------------------
# Geometrie-Helfer
# ---------------------------------------------------------------------------

class Part:
    """Sammelt Quader und Zylinder in einem Mesh. Koordinaten in Rack-Raum, Ursprung = origin."""

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

    def _finish(self, verts, mat, uv_scale, smooth_axis=None):
        idx = self._index(mat)
        faces = {f for v in verts for f in v.link_faces}
        for f in faces:
            f.normal_update()
            f.material_index = idx
            n = f.normal
            ax = max(range(3), key=lambda i: abs(n[i]))
            a, b = ((1, 2), (0, 2), (0, 1))[ax]
            for loop in f.loops:
                co = loop.vert.co + self.origin
                loop[self.uv].uv = (co[a] / uv_scale, co[b] / uv_scale)
            if smooth_axis is not None and abs(n.dot(smooth_axis)) < 0.5:
                f.smooth = True

    def box_m(self, matrix, mat, uv=1.0):
        m = Matrix.Translation(-self.origin) @ matrix
        verts = bmesh.ops.create_cube(self.bm, size=1.0, matrix=m)["verts"]
        self._finish(verts, mat, uv)

    def box(self, center, size, mat, uv=1.0, rot=(0.0, 0.0, 0.0)):
        m = (Matrix.Translation(Vector(center)) @ Euler(rot).to_matrix().to_4x4()
             @ Matrix.Diagonal((size[0], size[1], size[2], 1.0)))
        self.box_m(m, mat, uv)

    def cyl(self, center, radius, depth, mat, axis="Z", segs=16):
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
        self._finish(verts, mat, 1.0, smooth_axis=axis_v)

    def build(self, coll, parent, parent_origin=(0.0, 0.0, 0.0)):
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
    """Waagerechte Platte aus Rechtecken, die rechteckige Ausschnitte (hx0, hx1, hy0, hy1) frei laesst."""
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

def build_frame(coll, root, variant, height, m):
    top = height - HEADER_H
    roof_z0 = height - ROOF_T
    fr = Part(f"{variant}_Frame")
    post_h = roof_z0 - PLINTH_TOP
    pz = PLINTH_TOP + post_h * 0.5

    # Eckpfosten als L-Profil
    for sx in (-1, 1):
        for sy in (-1, 1):
            fr.box((sx * (FRAME - 0.0225), sy * (FRAME - 0.00125), pz), (0.045, 0.0025, post_h), m["powder"])
            fr.box((sx * (FRAME - 0.00125), sy * (FRAME - 0.0225), pz), (0.0025, 0.045, post_h), m["powder"])

    # Rahmenrohre unten und oben
    for z in (PLINTH_TOP + 0.02, roof_z0 - 0.02):
        for sy in (-1, 1):
            fr.box((0.0, sy * (FRAME - 0.02), z), (2 * FRAME - 0.09, 0.04, 0.04), m["powder"])
        for sx in (-1, 1):
            fr.box((sx * (FRAME - 0.02), 0.0, z), (0.04, 2 * FRAME - 0.09, 0.04), m["powder"])

    # Kopfblenden vorne und hinten (hier sitzen im Spiel Strom- und Netzanschluss)
    for s in (-1, 1):
        fr.box((0.0, s * 0.454, (top + roof_z0) * 0.5), (0.912, 0.012, roof_z0 - top), m["powder"])

    # 19-Zoll-Profilschienen (Z-Profil) mit Tiefenstreben
    rail_z0 = PLINTH_TOP + 0.045
    rail_z1 = roof_z0 - 0.04
    rail_len = rail_z1 - rail_z0
    rail_zc = (rail_z0 + rail_z1) * 0.5
    for sx in (-1, 1):
        for sy in (-1, 1):
            fr.box((sx * RAIL_X, sy * RAIL_Y, rail_zc), (0.022, 0.002, rail_len), m["galv"])
            fr.box((sx * (RAIL_X + 0.011), sy * (RAIL_Y - 0.015), rail_zc), (0.002, 0.03, rail_len), m["galv"])
        for z in (PLINTH_TOP + 0.02, roof_z0 - 0.02):
            fr.box((sx * (RAIL_X + 0.02), 0.0, z), (0.02, 0.82, 0.02), m["galv"])

    # Vierkantloecher 9,5 mm, drei pro HE (6,35 / 22,225 / 38,1 mm)
    n_u = int((top - 0.01 - rail_z0) / U)
    for sx in (-1, 1):
        for sy in (-1, 1):
            face_y = sy * (RAIL_Y + 0.001)
            for u in range(n_u):
                for off in (0.00635, 0.022225, 0.0381):
                    z = rail_z0 + u * U + off
                    fr.box((sx * RAIL_X, face_y + sy * 0.0002, z), (0.0095, 0.0008, 0.0095), m["hole"])
    fr.build(coll, root)
    return n_u


def build_plinth_and_feet(coll, root, variant, m):
    pl = Part(f"{variant}_Plinth")
    pl.box((0.0, 0.0, 0.115), (0.90, 0.90, 0.11), m["powder"])
    for sy in (-1, 1):
        pl.box((0.0, sy * 0.4505, 0.115), (0.70, 0.002, 0.08), m["hole"])
        for v in range(14):
            pl.box((-0.325 + v * 0.05, sy * 0.4515, 0.115), (0.03, 0.004, 0.07), m["powder"])
    pl.build(coll, root)

    cs = Part(f"{variant}_Casters")
    for sx in (-1, 1):
        for sy in (-1, 1):
            cx, cy = sx * 0.37, sy * 0.37
            cs.box((cx, cy, 0.058), (0.07, 0.07, 0.004), m["zinc"])
            cs.cyl((cx, cy, 0.053), 0.014, 0.006, m["zinc"])
            for side in (-1, 1):
                cs.box((cx + side * 0.013, cy, 0.035), (0.003, 0.03, 0.03), m["zinc"])
            cs.cyl((cx, cy, 0.022), 0.022, 0.02, m["rubber"], axis="X", segs=20)
            cs.cyl((cx, cy, 0.022), 0.004, 0.03, m["zinc"], axis="X", segs=8)
            # Stellfuss mit Gummiteller
            fx, fy = sx * 0.30, sy * 0.40
            cs.box((fx, fy, 0.056), (0.018, 0.018, 0.008), m["zinc"])
            cs.cyl((fx, fy, 0.033), 0.005, 0.046, m["zinc"], segs=10)
            cs.cyl((fx, fy, 0.012), 0.016, 0.004, m["zinc"])
            cs.cyl((fx, fy, 0.005), 0.020, 0.010, m["rubber"])
    cs.build(coll, root)


def build_roof(coll, root, variant, height, m):
    roof_z0 = height - ROOF_T
    rf = Part(f"{variant}_Roof")
    fan_holes = [(-0.35, -0.05, -0.10, 0.20), (0.05, 0.35, -0.10, 0.20)]
    brush = (-0.23, 0.23, -0.345, -0.275)
    plate_with_holes(rf, -HW, HW, -HW, HW, height - 0.0015, height, fan_holes + [brush], m["powder"])

    # Abkantung rundum
    for s in (-1, 1):
        rf.box((0.0, s * (HW - 0.00075), height - 0.0125), (2 * HW, 0.0015, 0.025), m["powder"])
        rf.box((s * (HW - 0.00075), 0.0, height - 0.0125), (0.0015, 2 * HW - 0.003, 0.025), m["powder"])

    # Buerstenleiste fuer die Kabeleinfuehrung (Schlitz in der Mitte)
    bz = height - 0.010
    rf.box((0.0, -0.328, bz), (0.46, 0.034, 0.016), m["brush"])
    rf.box((0.0, -0.292, bz), (0.46, 0.034, 0.016), m["brush"])

    fans = []
    for i, (hx0, hx1, hy0, hy1) in enumerate(fan_holes):
        fx, fy = (hx0 + hx1) * 0.5, (hy0 + hy1) * 0.5
        # Lochblech-Gitter ueber dem Luefter
        rf.box((fx, fy, height - 0.0008), (hx1 - hx0 + 0.004, hy1 - hy0 + 0.004, 0.0015), m["perf"], uv=PERF_TILE)
        # Luefterkasten mit Nabe und Streben
        wz = height - 0.0015 - 0.0225
        for s in (-1, 1):
            rf.box((fx + s * 0.148, fy, wz), (0.004, 0.30, 0.045), m["plastic"])
            rf.box((fx, fy + s * 0.148, wz), (0.30, 0.004, 0.045), m["plastic"])
        rf.cyl((fx, fy, height - 0.035), 0.036, 0.022, m["plastic"], segs=20)
        for ang in (math.pi / 4, -math.pi / 4):
            rf.box((fx, fy, height - 0.043), (0.41, 0.008, 0.004), m["plastic"], rot=(0.0, 0.0, ang))
        fans.append((fx, fy, "L" if i == 0 else "R"))
    rf.build(coll, root)

    for fx, fy, tag in fans:
        zc = height - 0.020
        fan = Part(f"{variant}_Fan_Roof_{tag}", origin=(fx, fy, zc))
        for b in range(7):
            a = b * 2.0 * math.pi / 7.0
            mtx = (Matrix.Translation((fx, fy, zc)) @ Matrix.Rotation(a, 4, "Z")
                   @ Matrix.Translation((0.078, 0.0, 0.0)) @ Matrix.Rotation(math.radians(28.0), 4, "X")
                   @ Matrix.Diagonal((0.105, 0.045, 0.0025, 1.0)))
            fan.box_m(mtx, m["fan"])
        fan.cyl((fx, fy, zc), 0.032, 0.016, m["plastic"], segs=20)
        fan.build(coll, root)


def build_door(coll, root, variant, name, hinge_x, side, x0, x1, z0, z1, m, handle=True, label=False):
    hy = side * 0.466
    open_dir = 1.0 if (x0 + x1) * 0.5 > hinge_x else -1.0
    hinge = make_empty(coll, f"{variant}_Hinge_{name}", root, (hinge_x, hy, 0.0))
    hinge["dct_open_deg"] = DOOR_OPEN_DEG * side * open_dir

    d = Part(f"{variant}_{name}", origin=(hinge_x, hy, 0.0))
    t, dep = 0.032, 0.018
    yc = side * 0.457
    cx, cz = (x0 + x1) * 0.5, (z0 + z1) * 0.5
    w, h = x1 - x0, z1 - z0
    # Tuerrahmen aus Rechteckrohr
    d.box((cx, yc, z1 - t * 0.5), (w, dep, t), m["powder"])
    d.box((cx, yc, z0 + t * 0.5), (w, dep, t), m["powder"])
    d.box((x0 + t * 0.5, yc, cz), (t, dep, h - 2 * t), m["powder"])
    d.box((x1 - t * 0.5, yc, cz), (t, dep, h - 2 * t), m["powder"])
    # Versteifung hinter dem Blech und das Lochblech selbst
    d.box((cx, side * 0.452, cz), (w - 2 * t, 0.008, 0.025), m["powder"])
    d.box((cx, side * 0.463, cz), (w - 2 * t + 0.01, 0.0015, h - 2 * t + 0.01), m["perf"], uv=PERF_TILE)
    # Scharniere
    for hz in (z0 + 0.12, cz, z1 - 0.12):
        d.cyl((hinge_x, hy, hz), 0.007, 0.05, m["zinc"], segs=12)

    hx = x0 + t * 0.5 if open_dir < 0 else x1 - t * 0.5
    if handle:
        zh = min(1.10, cz)
        d.box((hx, side * 0.4695, zh), (0.030, 0.007, 0.20), m["plastic"])
        d.box((hx, side * 0.4745, zh + 0.02), (0.016, 0.005, 0.13), m["chrome"])
        d.box((hx, side * 0.4775, zh + 0.075), (0.016, 0.004, 0.02), m["chrome"])
        d.cyl((hx, side * 0.4735, zh - 0.07), 0.007, 0.006, m["chrome"], axis="Y", segs=14)
        d.box((hx, side * 0.4768, zh - 0.07), (0.0015, 0.0008, 0.007), m["hole"])
    else:
        # Standfluegel: Riegel oben und unten
        d.box((hx, side * 0.469, z1 - 0.06), (0.010, 0.006, 0.08), m["zinc"])
        d.box((hx, side * 0.469, z0 + 0.06), (0.010, 0.006, 0.08), m["zinc"])
    if label:
        d.box((cx, side * 0.4665, z1 - t * 0.5), (0.07, 0.001, 0.02), m["label"])
    d.build(coll, hinge, (hinge_x, hy, 0.0))


def build_side_panel(coll, root, variant, sx, z0, z1, m):
    tag = "L" if sx < 0 else "R"
    cx, cz = sx * 0.454, (z0 + z1) * 0.5
    e = make_empty(coll, f"{variant}_Panel_Side_{tag}", root, (cx, 0.0, cz))
    e["dct_slide_x"] = sx * SIDE_SLIDE
    e["dct_closed_x"] = cx
    p = Part(f"{variant}_SidePanel_{tag}", origin=(cx, 0.0, cz))
    p.box((cx, 0.0, cz), (0.012, 0.892, z1 - z0), m["powder"])
    gz = z1 - 0.20
    for gy in (-0.25, 0.25):
        p.box((cx + sx * 0.0075, gy, gz), (0.003, 0.11, 0.035), m["plastic"])
        p.box((cx + sx * 0.0094, gy, gz), (0.0012, 0.09, 0.018), m["hole"])
    p.cyl((cx + sx * 0.008, 0.0, gz), 0.010, 0.004, m["chrome"], axis="X", segs=16)
    p.box((cx + sx * 0.0104, 0.0, gz), (0.0008, 0.0016, 0.008), m["hole"])
    p.build(coll, e, (cx, 0.0, cz))


def build_pdu(coll, root, variant, height, m):
    top = height - HEADER_H
    roof_z0 = height - ROOF_T
    p = Part(f"{variant}_PDU")
    px, py = 0.420, 0.405
    z0, z1 = 0.32, top - 0.12
    p.box((px, py, (z0 + z1) * 0.5), (0.044, 0.05, z1 - z0), m["pdu"])
    n = int((z1 - z0 - 0.12) / 0.048)
    for i in range(n):
        z = z0 + 0.08 + i * 0.048
        p.box((px, py + 0.0265, z), (0.028, 0.003, 0.036), m["plastic"])
        p.box((px, py + 0.0285, z), (0.019, 0.0015, 0.024), m["hole"])
    p.box((px, py + 0.0258, z1 - 0.03), (0.026, 0.0016, 0.014), m["lcd"])
    p.box((px, py + 0.0262, z1 - 0.06), (0.016, 0.0024, 0.022), m["breaker"])
    p.cyl((px + 0.012, py, (z1 + roof_z0) * 0.5), 0.007, roof_z0 - z1, m["rubber"], segs=10)
    p.build(coll, root)
    return n


def build_rack(coll, variant, cfg, m):
    height = cfg["height"]
    top = height - HEADER_H
    roof_z0 = height - ROOF_T
    root = bpy.data.objects.new(variant, None)
    coll.objects.link(root)
    root.empty_display_type = "PLAIN_AXES"
    root.empty_display_size = 0.2
    root.location = (cfg["x"], 0.0, 0.0)
    root["dct_model_id"] = variant

    n_u = build_frame(coll, root, variant, height, m)
    build_plinth_and_feet(coll, root, variant, m)
    build_roof(coll, root, variant, height, m)
    door_z0, door_z1 = PLINTH_TOP + 0.006, top - 0.004
    build_door(coll, root, variant, "FrontDoor", 0.450, -1, -0.446, 0.444, door_z0, door_z1, m, handle=True, label=True)
    build_door(coll, root, variant, "RearDoor_L", -0.450, 1, -0.446, -0.002, door_z0, door_z1, m, handle=False)
    build_door(coll, root, variant, "RearDoor_R", 0.450, 1, 0.002, 0.446, door_z0, door_z1, m, handle=True)
    for sx in (-1, 1):
        build_side_panel(coll, root, variant, sx, PLINTH_TOP + 0.004, roof_z0 - 0.002, m)
    outlets = build_pdu(coll, root, variant, height, m)
    return root, n_u, outlets


# ---------------------------------------------------------------------------
# Szene
# ---------------------------------------------------------------------------

def reset_collection():
    coll = bpy.data.collections.get(COLLECTION)
    if coll is None:
        coll = bpy.data.collections.new(COLLECTION)
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    for ob in list(coll.all_objects):
        data = ob.data
        bpy.data.objects.remove(ob, do_unlink=True)
        if isinstance(data, bpy.types.Mesh) and data.users == 0:
            bpy.data.meshes.remove(data)
    for child in list(coll.children):
        bpy.data.collections.remove(child)
    return coll


def set_open(root, opened):
    for ob in root.children_recursive:
        if "dct_open_deg" in ob:
            ob.rotation_euler.z = math.radians(float(ob["dct_open_deg"])) if opened else 0.0
        if "dct_slide_x" in ob:
            ob.location.x = float(ob["dct_closed_x"]) + (float(ob["dct_slide_x"]) if opened else 0.0)


def setup_preview():
    cube = bpy.data.objects.get("Cube")
    if cube is not None and cube.type == "MESH" and all(abs(d - 2.0) < 1e-3 for d in cube.dimensions):
        try:
            cube.hide_set(True)
        except RuntimeError:
            pass
        cube.hide_render = True
    cam = bpy.context.scene.camera
    if cam is not None:
        cam.location = (-2.9, -4.4, 2.1)
        target = Vector((0.15, 0.0, 1.15))
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 35


def save_blend():
    if not SCRIPT_DIR:
        return None
    path = os.path.join(SCRIPT_DIR, "dct_racks.blend")
    if bpy.data.filepath and os.path.normcase(bpy.data.filepath) != os.path.normcase(path):
        bpy.ops.wm.save_as_mainfile(filepath=path, copy=True)
    else:
        bpy.ops.wm.save_as_mainfile(filepath=path)
    return path


def main():
    coll = reset_collection()
    m = build_materials()
    for variant, cfg in VARIANTS.items():
        root, n_u, outlets = build_rack(coll, variant, cfg, m)
        set_open(root, cfg["preview_open"])
        meshes = [o for o in root.children_recursive if o.type == "MESH"]
        tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
        movable = sorted(o.name for o in root.children_recursive if "dct_open_deg" in o or "dct_slide_x" in o)
        print(f"{variant}: {len(meshes)} Meshes, {tris} Dreiecke, {n_u} HE, {outlets} PDU-Steckdosen")
        print(f"  beweglich: {', '.join(movable)}")
    setup_preview()
    path = save_blend()
    print(f"Gespeichert: {path}")


if __name__ == "__main__":
    main()