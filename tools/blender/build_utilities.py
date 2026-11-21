"""Baut Sicherungskasten, Sicherungen, Feuerloescher-Station und alle 5 Router-Stufen fuer DataCenter Tycoon.

Aufruf in Blender:
    p = r"<pfad>/build_utilities.py"
    exec(compile(open(p, encoding="utf-8").read(), p, "exec"), {"__name__": "__main__", "__file__": p})

Alle Masse stammen aus scripts/world/garage_builder.gd und sind hier in GODOT-Koordinaten notiert
(X rechts, Y oben, Z zur Raummitte). g() rechnet sie nach Blender um (X, -Z, Y); der glTF-Export dreht
sie wieder zurueck. Der Ursprung jedes Modells ist der Node3D-Ursprung im Spiel (Property "dct_game_pos").

Bewegliche Teile (Empties als Drehpunkt, Mesh als Kind):
    *_Hinge_Door            Tuer, Drehung um Blender Z.        Property dct_open_deg   (Grad)
    *_Hinge_SocketLid_<n>   Klappdeckel, Drehung um Blender X. Property dct_open_deg_x (Grad)
    breaker_box_Pivot_MainLever  Hauptschalter, Blender X.     dct_on_deg_x / dct_off_deg_x
    breaker_box_FuseCap_F<n>     Schraubkappe, ein-/ausblenden (Spiel: leerer Steckplatz)
    *_Panel_Side_<L|R>      abnehmbare Seitenwand, Blender X.  dct_slide_x, dct_closed_x
    *_Pivot_Antenna*        Antennengelenk, Blender Y.         dct_tilt_deg_y
    extinguisher_Body       wird vom Spieler abgenommen.       dct_removable
    extinguisher_Pivot_Lever Schlaghebel, Blender Y.           dct_press_deg_y
Das Skript ist wiederholbar: es leert die Collection "DCT_Utilities" und baut alles neu.
"""
import importlib
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

try:
    SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
except NameError:
    SCRIPT_DIR = ""
if SCRIPT_DIR and SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import build_racks as br  # noqa: E402

importlib.reload(br)

COLLECTION = "DCT_Utilities"
DOOR_OPEN_DEG = -110.0
LID_OPEN_DEG = -100.0
SIDE_SLIDE = 0.25

ROUTER_GAME_POS = (-1.0, 1.62, -4.38)
BREAKER_AT = (3.0, 0.0, 1.55)
EXT_AT = (4.0, 0.0, 1.22)
FUSE_AT = (3.53, -0.60, 0.0245)   # stehend auf dem Boden, Kontaktfuss unten
ROUTER_X = (6.0, 7.1, 8.3, 9.5, 10.7)
ROUTER_Z = 1.62

# Name, Kameraposition, Ziel, Bildwinkel (Grad), Belichtung (Blendenstufen)
SHOTS = (
    ("preview_power", (2.55, -2.75, 1.95), (3.55, 0.0, 1.35), 38.0, 0.0),
    ("preview_breaker_open", (3.45, -1.25, 1.80), (3.0, -0.05, 1.45), 40.0, 0.0),
    ("preview_fuses", (3.60, -0.84, 0.10), (3.56, -0.60, 0.025), 32.0, 0.3),
    ("preview_routers", (8.35, -7.6, 2.5), (8.35, 0.0, 1.75), 45.0, 0.9),
    ("preview_router_dsl", (6.0, -1.6, 2.3), (6.0, 0.0, 2.0), 45.0, 0.8),
    ("preview_router_gateway", (8.3, -1.0, 1.75), (8.3, 0.0, 1.70), 40.0, 0.8),
)


# ---------------------------------------------------------------------------
# Godot -> Blender
# ---------------------------------------------------------------------------

def g(x, y, z):
    return Vector((x, -z, y))


def gs(sx, sy, sz):
    return (sx, sz, sy)


def off(o, d):
    return (o[0] + d[0], o[1] + d[1], o[2] + d[2])


_AXIS_ROT = {
    "Y": Matrix.Identity(4),
    "Z": Matrix.Rotation(math.pi / 2, 4, "X"),   # zeigt nach vorne (Godot +Z)
    "X": Matrix.Rotation(math.pi / 2, 4, "Y"),
}


def catmull(pts, sub):
    if len(pts) < 3:
        return list(pts)
    ext = [pts[0]] + list(pts) + [pts[-1]]
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for k in range(sub):
            t = k / sub
            t2, t3 = t * t, t * t * t
            out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
                              + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
    out.append(pts[-1])
    return out


class GPart(br.Part):
    """Part mit Godot-Koordinaten und zusaetzlichen Grundkoerpern (Kegelstumpf, Kugel, Torus, Schlauch)."""

    def __init__(self, name, origin_g=(0.0, 0.0, 0.0)):
        super().__init__(name, g(*origin_g))

    def _smooth(self, verts):
        for f in {f for v in verts for f in v.link_faces}:
            f.smooth = True

    def gbox(self, pos, size, m, rot=(0.0, 0.0, 0.0), uv=1.0):
        rx, ry, rz = (math.radians(a) for a in rot)
        self.box(g(*pos), gs(*size), m, uv=uv, rot=(rx, -rz, ry))

    def gcyl(self, pos, r_top, r_bot, h, m, axis="Y", segs=16):
        rot = _AXIS_ROT[axis]
        mtx = Matrix.Translation(g(*pos) - self.origin) @ rot
        verts = bmesh.ops.create_cone(
            self.bm, cap_ends=True, cap_tris=False, segments=segs,
            radius1=r_bot, radius2=r_top, depth=h, matrix=mtx,
        )["verts"]
        self._finish(verts, m, 1.0, smooth_axis=(rot.to_3x3() @ Vector((0.0, 0.0, 1.0))).normalized())

    def gsphere(self, pos, radius, height, m, segs=24):
        mtx = Matrix.Translation(g(*pos) - self.origin) @ Matrix.Diagonal((1.0, 1.0, height / (2.0 * radius), 1.0))
        verts = bmesh.ops.create_uvsphere(
            self.bm, u_segments=segs, v_segments=max(6, segs // 2), radius=radius, matrix=mtx,
        )["verts"]
        self._finish(verts, m, 1.0)
        self._smooth(verts)

    def gtorus(self, pos, r_in, r_out, m, axis="Y", major=32, minor=10):
        mtx = Matrix.Translation(g(*pos) - self.origin) @ _AXIS_ROT[axis]
        big, small = (r_in + r_out) * 0.5, (r_out - r_in) * 0.5
        rings = []
        for i in range(major):
            a = 2.0 * math.pi * i / major
            row = []
            for j in range(minor):
                b = 2.0 * math.pi * j / minor
                rr = big + small * math.cos(b)
                row.append(self.bm.verts.new(mtx @ Vector((rr * math.cos(a), rr * math.sin(a), small * math.sin(b)))))
            rings.append(row)
        faces = []
        for i in range(major):
            n = (i + 1) % major
            for j in range(minor):
                k = (j + 1) % minor
                faces.append(self.bm.faces.new((rings[i][j], rings[n][j], rings[n][k], rings[i][k])))
        bmesh.ops.recalc_face_normals(self.bm, faces=faces)
        verts = [v for row in rings for v in row]
        self._finish(verts, m, 1.0)
        self._smooth(verts)

    def ghose(self, pts_g, radius, m, segs=10, sub=6):
        path = catmull([g(*p) for p in pts_g], sub)
        for a, b in zip(path, path[1:]):
            d = b - a
            length = d.length
            if length < 1e-6:
                continue
            q = Vector((0.0, 0.0, 1.0)).rotation_difference(d.normalized())
            mtx = Matrix.Translation((a + b) * 0.5 - self.origin) @ q.to_matrix().to_4x4()
            verts = bmesh.ops.create_cone(
                self.bm, cap_ends=True, cap_tris=False, segments=segs,
                radius1=radius, radius2=radius, depth=length + radius * 0.6, matrix=mtx,
            )["verts"]
            self._finish(verts, m, 1.0, smooth_axis=d.normalized())


# ---------------------------------------------------------------------------
# Szene-Helfer
# ---------------------------------------------------------------------------

def make_root(coll, name, loc, game_pos):
    e = bpy.data.objects.new(name, None)
    coll.objects.link(e)
    e.empty_display_type = "PLAIN_AXES"
    e.empty_display_size = 0.15
    e.location = loc
    e["dct_model_id"] = name
    e["dct_game_pos"] = [float(v) for v in game_pos]
    return e


def pivot(coll, name, parent, pos_g, parent_origin_g=(0.0, 0.0, 0.0)):
    return br.make_empty(coll, name, parent, g(*pos_g), g(*parent_origin_g), size=0.04)


def add_text(coll, parent, name, text, pos_g, height, m, parent_origin_g=(0.0, 0.0, 0.0), wrap=None, depth=0.0004):
    """Flacher Text (als Mesh) mit Blick nach vorne. wrap = Abstand zur Zylinderachse, biegt den Text um sie."""
    cu = bpy.data.curves.new(name, "FONT")
    cu.body = text
    cu.size = height
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.extrude = depth * 0.5
    tmp = bpy.data.objects.new(name + "_tmp", cu)
    coll.objects.link(tmp)
    bpy.context.view_layer.update()
    deps = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(tmp.evaluated_get(deps))
    bpy.data.objects.remove(tmp, do_unlink=True)
    bpy.data.curves.remove(cu)
    if wrap:
        for v in me.vertices:
            x, y, z = v.co
            r = wrap + z
            a = x / wrap
            v.co = (r * math.sin(a), y, r * math.cos(a) - wrap)
    me.materials.clear()
    me.materials.append(m)
    for poly in me.polygons:
        poly.material_index = 0
    me.name = name
    ob = bpy.data.objects.new(name, me)
    coll.objects.link(ob)
    ob.parent = parent
    ob.location = g(*pos_g) - g(*parent_origin_g)
    ob.rotation_euler = (math.pi / 2, 0.0, 0.0)
    return ob


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


# ---------------------------------------------------------------------------
# Materialien (Farben = sRGB-Werte aus garage_builder.gd)
# ---------------------------------------------------------------------------

def _lin(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def mat(name, rgb, rough, metal=0.0, emission=None, strength=0.0):
    col = tuple(_lin(c) for c in rgb)
    em = tuple(_lin(c) for c in emission) if emission else None
    return br.make_mat("DCT_U_" + name, col, metal, rough, emission=em, strength=strength)


def glass_mat(name, rgb, alpha):
    m = mat(name, rgb, 0.08, 0.0)
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Alpha"].default_value = alpha
    try:
        m.surface_render_method = "BLENDED"
    except (AttributeError, TypeError):
        m.blend_method = "BLEND"
    m.diffuse_color = (m.diffuse_color[0], m.diffuse_color[1], m.diffuse_color[2], alpha)
    m.use_backface_culling = False
    return m


def build_materials():
    img = bpy.data.images.get("DCT_Perforation") or br.perforation_image()
    perf = bpy.data.materials.get("DCT_PerforatedSteel") or br.make_perf_mat(img)
    return {
        "perf": perf,
        "housing": mat("EnclosureGrey", (0.74, 0.75, 0.74), 0.52, 0.18),
        "housing_edge": mat("EnclosureEdge", (0.63, 0.64, 0.63), 0.46, 0.25),
        "mount": mat("MountPlate", (0.46, 0.49, 0.52), 0.40, 0.70),
        "galv": mat("Galv", (0.66, 0.67, 0.68), 0.36, 1.0),
        "module_white": mat("ModuleWhite", (0.93, 0.93, 0.91), 0.36),
        "module_grey": mat("ModuleGrey", (0.32, 0.34, 0.36), 0.45),
        "toggle_blue": mat("ToggleBlue", (0.14, 0.38, 0.72), 0.32),
        "toggle_dark": mat("ToggleDark", (0.16, 0.17, 0.19), 0.40),
        "window_grey": mat("WindowGrey", (0.22, 0.24, 0.26), 0.25),
        "window_green": mat("WindowGreen", (0.18, 0.62, 0.30), 0.40),
        "paper": mat("LabelPaper", (0.96, 0.95, 0.88), 0.85),
        "dark": mat("Dark", (0.10, 0.11, 0.13), 0.55, 0.20),
        "screen": mat("Screen", (0.04, 0.06, 0.05), 0.15),
        "screw": mat("Screw", (0.72, 0.74, 0.76), 0.30, 0.90),
        "lever_red": mat("LeverRed", (0.86, 0.14, 0.12), 0.30, 0.10),
        "warn_yellow": mat("WarnYellow", (0.95, 0.78, 0.10), 0.50, 0.10),
        "test_yellow": mat("TestYellow", (0.95, 0.80, 0.16), 0.40),
        "socket_yellow": mat("SocketYellow", (0.84, 0.66, 0.14), 0.48, 0.08),
        "conduit": mat("Conduit", (0.45, 0.49, 0.54), 0.40, 0.65),
        "gland": mat("Gland", (0.20, 0.21, 0.23), 0.60),
        "brass": mat("Brass", (0.78, 0.62, 0.30), 0.35, 0.85),
        "cap": mat("FuseCap", (0.86, 0.86, 0.84), 0.55),
        "fuse_ind": mat("FuseIndicator", (0.22, 0.85, 0.38), 0.40, emission=(0.22, 0.85, 0.38), strength=1.1),
        "ceramic": mat("Ceramic", (0.93, 0.92, 0.88), 0.30),
        "contact": mat("NickelContact", (0.80, 0.81, 0.82), 0.25, 1.0),
        "kenn_yellow": mat("KennmelderYellow", (0.95, 0.80, 0.10), 0.45),
        "soot": mat("Soot", (0.08, 0.07, 0.06), 0.95),
        "led_green": mat("StatusLED", (0.20, 1.0, 0.40), 0.30, emission=(0.20, 1.0, 0.40), strength=2.0),
        "load_bar": mat("LoadBar", (0.18, 0.92, 0.45), 0.30, emission=(0.18, 0.92, 0.45), strength=1.6),
        "glass": glass_mat("Glass", (0.55, 0.62, 0.66), 0.25),
        "rubber": mat("Rubber", (0.07, 0.07, 0.08), 0.75),
        "plastic_black": mat("PlasticBlack", (0.10, 0.10, 0.11), 0.42),
        "hole": mat("Hole", (0.03, 0.03, 0.03), 0.90),
        "text_dark": mat("TextDark", (0.08, 0.08, 0.09), 0.60),
        "text_light": mat("TextLight", (0.85, 0.86, 0.86), 0.50),
        "lcd_text": mat("LcdText", (0.35, 0.85, 0.95), 0.30, emission=(0.35, 0.85, 0.95), strength=1.5),
        "red_paint": mat("RedPaint", (0.80, 0.06, 0.05), 0.22, 0.25),
        "sign_red": mat("SignRed", (0.78, 0.08, 0.07), 0.55),
        "white": mat("White", (0.95, 0.95, 0.93), 0.55),
        "chrome": mat("Chrome", (0.82, 0.83, 0.85), 0.16, 0.95),
        "seal_yellow": mat("SealYellow", (0.95, 0.80, 0.10), 0.50),
        "gauge_green": mat("GaugeGreen", (0.16, 0.66, 0.30), 0.50),
        "sticker_green": mat("StickerGreen", (0.20, 0.58, 0.30), 0.60),
        "dsl_plastic": mat("DslPlastic", (0.84, 0.81, 0.73), 0.62),
        "dsl_plastic_dark": mat("DslPlasticDark", (0.74, 0.71, 0.63), 0.66),
        "dsl_bezel": mat("DslBezel", (0.42, 0.41, 0.39), 0.40),
        "slot": mat("Slot", (0.12, 0.12, 0.12), 0.80),
        "sticker": mat("Sticker", (0.93, 0.92, 0.84), 0.85),
        "port_blue": mat("PortBlue", (0.20, 0.44, 0.72), 0.45, 0.22),
        "jack": mat("Jack", (0.04, 0.04, 0.05), 0.75),
        "gold": mat("Gold", (0.86, 0.68, 0.26), 0.30, 0.90),
        "router_body": mat("RouterBody", (0.12, 0.13, 0.15), 0.45, 0.35),
        "gloss": mat("GlossBlack", (0.05, 0.05, 0.06), 0.12, 0.10),
        "silver": mat("Silver", (0.72, 0.74, 0.77), 0.25, 0.90),
        "gw_body": mat("GatewayBody", (0.16, 0.18, 0.21), 0.40, 0.55),
        "gw_face": mat("GatewayFace", (0.09, 0.10, 0.12), 0.50, 0.30),
        "console_blue": mat("ConsoleBlue", (0.48, 0.72, 0.90), 0.45, 0.10),
        "fiber": mat("FiberYellow", (0.95, 0.78, 0.10), 0.45),
        "lc_blue": mat("LcBlue", (0.20, 0.45, 0.85), 0.40),
        "inner": mat("CabinetInner", (0.06, 0.07, 0.08), 0.70, 0.20),
        "cab_face": mat("CabinetFace", (0.10, 0.11, 0.13), 0.45, 0.35),
        "router_led": mat("RouterLED", (0.20, 0.72, 0.36), 0.30, emission=(0.20, 0.72, 0.36), strength=1.2),
        "amber_led": mat("AmberLED", (1.0, 0.62, 0.10), 0.30, emission=(1.0, 0.62, 0.10), strength=1.0),
    }


# ---------------------------------------------------------------------------
# Gemeinsame Kleinteile
# ---------------------------------------------------------------------------

def rj45(p, x, y, z, M, frame="port_blue"):
    """RJ45-Buchse. z = Frontflaeche."""
    p.gbox((x, y, z - 0.004), (0.034, 0.030, 0.008), M[frame])
    p.gbox((x, y - 0.001, z + 0.0005), (0.022, 0.018, 0.001), M["jack"])
    p.gbox((x, y - 0.0115, z + 0.0005), (0.010, 0.005, 0.001), M["jack"])
    for k in range(8):
        p.gbox((x - 0.0077 + 0.0022 * k, y + 0.0055, z + 0.0011), (0.0011, 0.0035, 0.0006), M["gold"])
    p.gbox((x - 0.0125, y + 0.0125, z + 0.0005), (0.005, 0.003, 0.001), M["router_led"])
    p.gbox((x + 0.0125, y + 0.0125, z + 0.0005), (0.005, 0.003, 0.001), M["amber_led"])


def mcb(p, x, y, w, M, body, toggle, window):
    """Reiheneinbaugeraet mit Stufenprofil, Kipphebel (EIN = oben) und Aufdruckfenster."""
    p.gbox((x, y, 0.105), (w - 0.002, 0.11, 0.05), M[body])
    p.gbox((x, y, 0.1315), (w - 0.006, 0.045, 0.003), M[body])
    p.gbox((x, y + 0.012, 0.1365), (w * 0.45, 0.02, 0.010), M[toggle])
    p.gbox((x, y - 0.032, 0.1305), (w * 0.6, 0.014, 0.002), M[window])


# ---------------------------------------------------------------------------
# Sicherungskasten (Unterverteilung)
# ---------------------------------------------------------------------------

def build_breaker_box(coll, M):
    root = make_root(coll, "breaker_box", BREAKER_AT, (-4.2, 1.55, -4.38))
    p = GPart("breaker_box_Housing")

    # Gehaeuse, umlaufende Kante, Montageplatte
    p.gbox((0.0, 0.0, -0.01), (0.76, 1.02, 0.18), M["housing"])
    for y in (0.4925, -0.4925):
        p.gbox((0.0, y, 0.09), (0.76, 0.035, 0.02), M["housing_edge"])
    for x in (-0.3625, 0.3625):
        p.gbox((x, 0.0, 0.09), (0.035, 0.95, 0.02), M["housing_edge"])
    p.gbox((0.0, 0.0, 0.082), (0.69, 0.95, 0.006), M["mount"])

    # Tuerkragen um den Geraeteteil (die Tuer liegt bei z 0.18..0.192)
    p.gbox((0.0, 0.4925, 0.14), (0.76, 0.035, 0.08), M["housing_edge"])
    for x in (-0.3625, 0.3625):
        p.gbox((x, 0.1025, 0.14), (0.035, 0.745, 0.08), M["housing_edge"])
    p.gbox((0.0, -0.2525, 0.14), (0.69, 0.035, 0.08), M["housing_edge"])
    for hy in (0.40, -0.16):
        p.gbox((-0.383, hy, 0.168), (0.006, 0.05, 0.024), M["galv"])
    # Schliessblech fuer den Vierkantverschluss
    p.gbox((0.343, 0.05, 0.176), (0.012, 0.04, 0.008), M["galv"])

    # Abdeckung mit zwei Ausschnitten, Hutschienen, Abdeckungsschrauben
    p.gbox((0.0, 0.3175, 0.09), (0.69, 0.315, 0.012), M["housing"])
    p.gbox((0.0, -0.02, 0.09), (0.69, 0.12, 0.012), M["housing"])
    p.gbox((0.0, -0.3375, 0.09), (0.69, 0.275, 0.012), M["housing"])
    for y in (0.10, -0.14):
        p.gbox((0.0, y, 0.087), (0.66, 0.035, 0.006), M["galv"])
    for sx in (-0.32, 0.32):
        for sy in (0.455, -0.455):
            p.gcyl((sx, sy, 0.098), 0.008, 0.008, 0.004, M["screw"], axis="Z", segs=12)
            p.gbox((sx, sy, 0.1002), (0.011, 0.002, 0.001), M["dark"])

    # Warnschild und Lastanzeige
    p.gbox((0.0, 0.40, 0.0975), (0.66, 0.05, 0.003), M["warn_yellow"])
    p.gbox((0.0, 0.26, 0.100), (0.60, 0.10, 0.010), M["dark"])
    p.gbox((0.0, 0.26, 0.1065), (0.56, 0.07, 0.003), M["screen"])
    for i in range(5):
        p.gbox((-0.26 + 0.13 * i, 0.287, 0.1085), (0.002, 0.008, 0.001), M["paper"])

    # Reihe 1: Hauptschalter, LED-Meldemodul, 6 LS-Schalter, FI mit Pruefaste, Ueberspannungsschutz
    p.gbox((-0.27, 0.10, 0.105), (0.106, 0.11, 0.05), M["module_white"])
    p.gbox((-0.27, 0.060, 0.1305), (0.05, 0.012, 0.002), M["window_grey"])
    p.gbox((-0.18, 0.10, 0.105), (0.036, 0.11, 0.05), M["module_white"])
    p.gbox((-0.18, 0.075, 0.1305), (0.022, 0.024, 0.002), M["window_grey"])
    for i in range(6):
        mcb(p, -0.13 + 0.038 * i, 0.10, 0.038, M, "module_white", "toggle_blue", "window_grey")
    mcb(p, 0.135, 0.10, 0.072, M, "module_white", "toggle_dark", "window_grey")
    p.gcyl((0.158, 0.138, 0.1325), 0.007, 0.007, 0.006, M["test_yellow"], axis="Z", segs=12)
    mcb(p, 0.215, 0.10, 0.072, M, "module_grey", "toggle_dark", "window_green")
    p.gbox((0.30, 0.10, 0.09), (0.09, 0.12, 0.012), M["module_white"])

    # Reihe 2: vier D02-Sicherungssockel (Messing-Gewindering, dunkle Oeffnung), FI 2, Blindabdeckung
    fuse_x = [-0.27 + 0.11 * i for i in range(4)]
    for fx in fuse_x:
        p.gbox((fx, -0.14, 0.105), (0.10, 0.11, 0.05), M["module_white"])
        p.gcyl((fx, -0.14, 0.1315), 0.031, 0.031, 0.003, M["brass"], axis="Z", segs=24)
        p.gcyl((fx, -0.14, 0.1335), 0.022, 0.022, 0.002, M["dark"], axis="Z", segs=24)
        p.gcyl((fx, -0.14, 0.1342), 0.006, 0.006, 0.001, M["brass"], axis="Z", segs=12)
    mcb(p, 0.17, -0.14, 0.072, M, "module_white", "toggle_dark", "window_grey")
    p.gbox((0.2775, -0.14, 0.09), (0.135, 0.12, 0.012), M["module_white"])

    # Beschriftungsstreifen
    p.gbox((0.0, 0.028, 0.097), (0.66, 0.016, 0.002), M["paper"])
    p.gbox((0.0, -0.212, 0.097), (0.66, 0.016, 0.002), M["paper"])

    # Einspeisung: Klemmengehaeuse mit 3 Schuko-Steckdosen (Klappdeckel separat)
    p.gbox((0.0, -0.37, 0.112), (0.40, 0.17, 0.04), M["dark"])
    socket_x = [-0.12 + 0.12 * i for i in range(3)]
    for px in socket_x:
        p.gcyl((px, -0.378, 0.145), 0.030, 0.030, 0.03, M["socket_yellow"], axis="Z", segs=24)
        p.gcyl((px, -0.378, 0.161), 0.021, 0.021, 0.003, M["dark"], axis="Z", segs=24)
        for dx in (-0.0095, 0.0095):
            p.gcyl((px + dx, -0.378, 0.1630), 0.0042, 0.0042, 0.001, M["hole"], axis="Z", segs=10)
        for dy in (-0.0175, 0.0175):
            p.gbox((px, -0.378 + dy, 0.1628), (0.007, 0.004, 0.002), M["contact"])
        p.gbox((px, -0.338, 0.150), (0.05, 0.012, 0.014), M["socket_yellow"])

    # Kabelschutzrohre nach oben mit Verschraubung und Rohrschellen
    for cx in (-0.22, 0.22):
        p.gcyl((cx, 1.32, -0.02), 0.032, 0.032, 1.65, M["conduit"], segs=20)
        p.gcyl((cx, 0.525, -0.02), 0.044, 0.044, 0.035, M["gland"], segs=20)
        for k in range(2):
            p.gbox((cx, 0.95 + 0.6 * k, -0.045), (0.09, 0.022, 0.03), M["galv"])
    p.build(coll, root)

    # Lastbalken und Status-LED als eigene Meshes (das Spiel faerbt/skaliert sie)
    lb = GPart("breaker_box_LoadBar", (0.0, 0.255, 0.109))
    lb.gbox((0.0, 0.255, 0.109), (0.52, 0.035, 0.003), M["load_bar"])
    lb.build(coll, root, g(0.0, 0.0, 0.0))
    led = GPart("breaker_box_StatusLED", (-0.18, 0.125, 0.1325))
    led.gcyl((-0.18, 0.125, 0.1325), 0.010, 0.010, 0.005, M["led_green"], axis="Z", segs=16)
    led.build(coll, root)

    # Hauptschalter: Drehpunkt auf der Schalterachse, EIN = Hebel oben (Godot rotation_degrees.x = -28)
    lp = (-0.27, 0.10, 0.132)
    lev_e = pivot(coll, "breaker_box_Pivot_MainLever", root, lp)
    lev_e["dct_on_deg_x"] = -28.0
    lev_e["dct_off_deg_x"] = 28.0
    lev = GPart("breaker_box_MainLever", lp)
    lev.gcyl(lp, 0.008, 0.008, 0.09, M["dark"], axis="X", segs=12)
    lev.gbox(off(lp, (0.0, 0.0, 0.02)), (0.07, 0.024, 0.04), M["lever_red"])
    lev.gbox(off(lp, (0.0, 0.0, 0.044)), (0.082, 0.032, 0.014), M["lever_red"])
    for k in range(3):
        lev.gbox(off(lp, (0.0, -0.009 + 0.009 * k, 0.0515)), (0.07, 0.003, 0.001), M["dark"])
    lev.build(coll, lev_e, g(*lp))
    lev_e.rotation_euler.x = math.radians(-28.0)

    # Schraubkappen F1..F4 (Ursprung = Gewindeansatz, wie _fuse_caps im Spiel)
    for i, fx in enumerate(fuse_x):
        cp = (fx, -0.14, 0.133)
        cap = GPart(f"breaker_box_FuseCap_F{i + 1}", cp)
        cap.gcyl(off(cp, (0.0, 0.0, 0.006)), 0.029, 0.029, 0.012, M["cap"], axis="Z", segs=28)
        cap.gcyl(off(cp, (0.0, 0.0, 0.021)), 0.024, 0.026, 0.018, M["cap"], axis="Z", segs=28)
        for r in range(12):
            a = 2.0 * math.pi * r / 12.0
            cap.gbox(off(cp, (0.0252 * math.cos(a), 0.0252 * math.sin(a), 0.021)), (0.004, 0.004, 0.016),
                     M["cap"], rot=(0.0, 0.0, math.degrees(a)))
        cap.gcyl(off(cp, (0.0, 0.0, 0.0305)), 0.015, 0.015, 0.002, M["dark"], axis="Z", segs=20)
        cap.gcyl(off(cp, (0.0, 0.0, 0.0315)), 0.010, 0.010, 0.003, M["fuse_ind"], axis="Z", segs=16)
        cap.gcyl(off(cp, (0.0, 0.0, 0.0335)), 0.0125, 0.0125, 0.0012, M["glass"], axis="Z", segs=20)
        ob = cap.build(coll, root)
        ob["dct_fuse_slot"] = i

    # Klappdeckel der Steckdosen, Scharnier oben
    for i, px in enumerate(socket_x):
        hp = (px, -0.343, 0.1645)
        he = pivot(coll, f"breaker_box_Hinge_SocketLid_{i + 1}", root, hp)
        he["dct_open_deg_x"] = LID_OPEN_DEG
        lid = GPart(f"breaker_box_SocketLid_{i + 1}", hp)
        lid.gcyl((px, -0.378, 0.1645), 0.033, 0.033, 0.005, M["socket_yellow"], axis="Z", segs=28)
        lid.gbox((px, -0.346, 0.1645), (0.03, 0.010, 0.005), M["socket_yellow"])
        lid.gbox((px, -0.413, 0.1655), (0.02, 0.008, 0.007), M["socket_yellow"])
        lid.build(coll, he, g(*hp))

    # Tuer mit Sichtfenster ueber Warnschild/Lastanzeige, Scharnier links, oeffnet nach vorne links
    hp = (-0.38, 0.12, 0.186)
    de = pivot(coll, "breaker_box_Hinge_Door", root, hp)
    de["dct_open_deg"] = DOOR_OPEN_DEG
    d = GPart("breaker_box_Door", hp)
    z, t = 0.186, 0.012
    d.gbox((0.0, 0.475, z), (0.76, 0.07, t), M["housing"])
    d.gbox((0.0, -0.035, z), (0.76, 0.47, t), M["housing"])
    for x in (-0.345, 0.345):
        d.gbox((x, 0.32, z), (0.07, 0.24, t), M["housing"])
    d.gbox((0.0, 0.32, 0.1835), (0.64, 0.26, 0.003), M["glass"])
    for y in (0.4425, 0.1975):
        d.gbox((0.0, y, 0.1925), (0.63, 0.006, 0.002), M["rubber"])
    for x in (-0.3125, 0.3125):
        d.gbox((x, 0.32, 0.1925), (0.006, 0.25, 0.002), M["rubber"])
    # Abkantung hinten, Verschluss, Scharnierrollen, Schaltplantasche innen
    for y in (0.5095, -0.2685):
        d.gbox((0.0, y, 0.177), (0.76, 0.003, 0.018), M["housing"])
    d.gbox((0.3785, 0.12, 0.177), (0.003, 0.78, 0.018), M["housing"])
    d.gcyl((0.345, 0.05, 0.194), 0.011, 0.011, 0.006, M["chrome"], axis="Z", segs=20)
    d.gbox((0.345, 0.05, 0.1975), (0.006, 0.006, 0.002), M["dark"])
    for hy in (0.40, -0.16):
        d.gcyl((-0.38, hy, z), 0.006, 0.006, 0.05, M["galv"], segs=12)
    d.gbox((-0.06, -0.06, 0.1785), (0.30, 0.30, 0.003), M["paper"])
    d.gbox((-0.06, -0.06, 0.1765), (0.31, 0.31, 0.0015), M["glass"])
    d.gbox((0.0, 0.475, 0.1925), (0.30, 0.035, 0.001), M["paper"])
    d.gbox((0.24, -0.20, 0.1925), (0.06, 0.06, 0.001), M["warn_yellow"])
    d.build(coll, de, g(*hp))

    # Beschriftungen
    add_text(coll, root, "breaker_box_Txt_Warn", "ACHTUNG  400 V", (0.0, 0.40, 0.0995), 0.039, M["text_dark"])
    add_text(coll, root, "breaker_box_Txt_Load", "NETZLAST", (0.0, 0.335, 0.0965), 0.0308, M["text_dark"])
    add_text(coll, root, "breaker_box_Txt_On", "I", (-0.235, 0.135, 0.1311), 0.012, M["text_dark"])
    add_text(coll, root, "breaker_box_Txt_Off", "0", (-0.235, 0.065, 0.1311), 0.012, M["text_dark"])
    row1 = [(-0.27, "HS"), (-0.18, "LED")] + [(-0.13 + 0.038 * i, f"Q{i + 1}") for i in range(6)]
    row1 += [(0.135, "FI 1"), (0.215, "ÜSS")]
    for x, s in row1:
        add_text(coll, root, f"breaker_box_Txt_{s}", s, (x, 0.028, 0.0982), 0.009, M["text_dark"])
    for i, fx in enumerate(fuse_x):
        add_text(coll, root, f"breaker_box_Txt_F{i + 1}", f"F{i + 1}", (fx, -0.212, 0.0990), 0.0264, M["text_dark"])
    add_text(coll, root, "breaker_box_Txt_FI2", "FI 2", (0.17, -0.212, 0.0982), 0.009, M["text_dark"])
    add_text(coll, root, "breaker_box_Txt_Feed", "EINSPEISUNG 230 V", (0.0, -0.305, 0.1325), 0.0216, M["text_light"])
    add_text(coll, de, "breaker_box_Txt_DoorLabel", "UV-1  GARAGE", (0.0, 0.475, 0.1932), 0.022, M["text_dark"],
             parent_origin_g=hp)
    add_text(coll, de, "breaker_box_Txt_DoorWarn", "400 V", (0.24, -0.20, 0.1932), 0.016, M["text_dark"],
             parent_origin_g=hp)
    add_text(coll, de, "breaker_box_Txt_Plan", "STROMLAUFPLAN\nUV-1", (-0.06, 0.04, 0.1803), 0.022, M["text_dark"],
             parent_origin_g=hp)
    return root


# ---------------------------------------------------------------------------
# Sicherungen (D02-Schmelzeinsaetze als Lagerware)
# ---------------------------------------------------------------------------

def build_fuse_cartridge(coll, M, name, loc, blown):
    root = make_root(coll, name, loc, (0.0, 0.0, 0.0))
    root["dct_fuse_state"] = "blown" if blown else "ok"
    p = GPart(f"{name}_Body")
    p.gcyl((0.0, 0.0, 0.0), 0.0115, 0.0115, 0.030, M["ceramic"], segs=24)
    p.gcyl((0.0, -0.018, 0.0), 0.0115, 0.0075, 0.006, M["ceramic"], segs=24)
    p.gcyl((0.0, -0.0225, 0.0), 0.006, 0.006, 0.003, M["contact"], segs=16)
    p.gcyl((0.0, 0.0165, 0.0), 0.0118, 0.0118, 0.004, M["contact"], segs=24)
    if blown:
        p.gcyl((0.0, 0.0188, 0.0), 0.004, 0.004, 0.001, M["hole"], segs=16)
        p.gcyl((0.0, 0.0115, 0.0), 0.01155, 0.01155, 0.006, M["soot"], segs=24)
        p.gcyl((0.0, 0.0190, 0.0), 0.0085, 0.0085, 0.0004, M["soot"], segs=20)
    else:
        p.gcyl((0.0, 0.0193, 0.0), 0.004, 0.004, 0.0016, M["kenn_yellow"], segs=16)
    p.build(coll, root)
    add_text(coll, root, f"{name}_Txt_Rating", "25A", (0.0, 0.003, 0.0117), 0.0045, M["text_dark"], wrap=0.0117)
    add_text(coll, root, f"{name}_Txt_Type", "gG 400V", (0.0, -0.005, 0.0117), 0.0028, M["text_dark"], wrap=0.0117)
    return root


# ---------------------------------------------------------------------------
# Feuerloescher-Station
# ---------------------------------------------------------------------------

def build_extinguisher(coll, M):
    root = make_root(coll, "extinguisher_station", EXT_AT, (-2.8, 1.22, -4.36))
    st = GPart("extinguisher_station_Bracket")
    w = M["white"]
    # Brandschutzzeichen F001: weisser Rand, rotes Feld, Piktogramm
    st.gbox((0.0, 0.47, -0.068), (0.20, 0.20, 0.006), w)
    st.gbox((0.0, 0.47, -0.064), (0.184, 0.184, 0.006), M["sign_red"])
    st.gbox((-0.03, 0.445, -0.0605), (0.036, 0.085, 0.002), w)
    st.gbox((-0.03, 0.495, -0.0605), (0.018, 0.02, 0.002), w)
    st.gbox((-0.016, 0.512, -0.0605), (0.034, 0.006, 0.002), w, rot=(0.0, 0.0, 8.0))
    st.gbox((0.0, 0.475, -0.0605), (0.006, 0.055, 0.002), w, rot=(0.0, 0.0, -35.0))
    for i in range(3):
        st.gbox((0.03 + 0.02 * i, 0.42 + 0.014 * (i % 2), -0.0605), (0.017, 0.017, 0.002), w, rot=(0.0, 0.0, 45.0))
    # Wandhalterung: Rueckenblech, Haken unter dem Ventilhals, Spannband mit Schnalle
    st.gbox((0.0, 0.02, -0.066), (0.07, 0.30, 0.008), M["galv"])
    for sy in (0.14, -0.10):
        st.gcyl((0.0, sy, -0.061), 0.006, 0.006, 0.003, M["screw"], axis="Z", segs=12)
    st.gbox((0.0, 0.05, -0.03), (0.03, 0.025, 0.064), M["galv"])
    st.gbox((0.0, 0.205, -0.035), (0.03, 0.012, 0.054), M["galv"])
    st.gbox((0.0, 0.214, -0.008), (0.03, 0.018, 0.006), M["galv"])
    st.gtorus((0.0, 0.05, 0.09), 0.086, 0.095, M["galv"])
    st.gbox((0.0, 0.05, 0.1825), (0.022, 0.012, 0.006), M["chrome"])
    st.build(coll, root)

    body = br.make_empty(coll, "extinguisher_Body", root, Vector((0.0, 0.0, 0.0)), size=0.06)
    body["dct_removable"] = True
    cz = 0.09
    b = GPart("extinguisher_Cylinder")
    # 6-kg-Pulverloescher: Behaelter mit Kuppel, Kunststofffuss, Etikett, Pruefplakette
    b.gcyl((0.0, -0.03, cz), 0.085, 0.085, 0.40, M["red_paint"], segs=36)
    b.gsphere((0.0, 0.17, cz), 0.085, 0.11, M["red_paint"], segs=36)
    b.gcyl((0.0, -0.225, cz), 0.087, 0.087, 0.03, M["plastic_black"], segs=36)
    b.gcyl((0.0, -0.245, cz), 0.080, 0.084, 0.012, M["plastic_black"], segs=36)
    b.gcyl((0.0, -0.05, cz), 0.0865, 0.0865, 0.15, w, segs=36)
    b.gcyl((0.0, -0.165, cz + 0.0855), 0.016, 0.016, 0.002, M["sticker_green"], axis="Z", segs=16)
    # Armatur: Hals, Ventilkopf, Manometer, Tragegriff, Sicherungsstift mit Plombe
    b.gcyl((0.0, 0.235, cz), 0.024, 0.024, 0.05, M["chrome"], segs=20)
    b.gcyl((0.0, 0.275, cz), 0.030, 0.030, 0.045, M["chrome"], segs=24)
    b.gcyl((0.0, 0.282, cz + 0.036), 0.022, 0.022, 0.016, M["chrome"], axis="Z", segs=24)
    b.gcyl((0.0, 0.282, cz + 0.0445), 0.018, 0.018, 0.002, w, axis="Z", segs=24)
    b.gbox((0.0, 0.292, cz + 0.0458), (0.016, 0.004, 0.001), M["gauge_green"])
    b.gbox((0.003, 0.284, cz + 0.0462), (0.002, 0.014, 0.001), M["plastic_black"], rot=(0.0, 0.0, -35.0))
    b.gcyl((0.0, 0.282, cz + 0.0458), 0.0185, 0.0185, 0.0012, M["glass"], axis="Z", segs=24)
    b.gbox((-0.04, 0.293, cz), (0.15, 0.016, 0.034), M["plastic_black"], rot=(0.0, 0.0, 3.0))
    b.gcyl((0.022, 0.30, cz), 0.0022, 0.0022, 0.07, M["chrome"], axis="Z", segs=8)
    b.gtorus((0.032, 0.30, cz + 0.025), 0.007, 0.012, M["chrome"], axis="Z", major=20, minor=8)
    b.gbox((0.032, 0.287, cz + 0.027), (0.008, 0.012, 0.004), M["seal_yellow"])
    # Schlauch vom Ventil seitlich nach unten, Loeschpistole in der Klammer
    b.gcyl((0.03, 0.265, cz), 0.014, 0.014, 0.02, M["chrome"], axis="X", segs=12)
    b.ghose([(0.035, 0.265, cz), (0.075, 0.255, cz + 0.02), (0.11, 0.215, cz + 0.03), (0.115, -0.08, cz + 0.03)],
            0.011, M["rubber"])
    b.gcyl((0.115, -0.075, cz + 0.03), 0.0135, 0.0135, 0.02, M["chrome"], segs=12)
    b.gcyl((0.115, -0.135, cz + 0.03), 0.013, 0.026, 0.11, M["plastic_black"], segs=16)
    b.gcyl((0.115, -0.191, cz + 0.03), 0.010, 0.010, 0.002, M["hole"], segs=12)
    b.gbox((0.098, 0.04, cz + 0.022), (0.03, 0.018, 0.03), M["galv"])
    b.build(coll, body)

    # Schlaghebel separat: Druecken = Drehung um Blender Y
    lp = (0.025, 0.305, cz)
    le = pivot(coll, "extinguisher_Pivot_Lever", body, lp)
    le["dct_press_deg_y"] = -8.0
    lv = GPart("extinguisher_Lever", lp)
    lv.gbox((-0.045, 0.316, cz), (0.17, 0.016, 0.034), M["plastic_black"], rot=(0.0, 0.0, -10.0))
    for k in range(4):
        lv.gbox((-0.08 + 0.022 * k, 0.3245 + 0.0039 * k, cz), (0.004, 0.003, 0.034), M["rubber"], rot=(0.0, 0.0, -10.0))
    lv.build(coll, le, g(*lp))

    r = 0.0875
    add_text(coll, body, "extinguisher_Txt_Title", "FEUERLÖSCHER", (0.0, 0.012, cz + r), 0.0105, M["sign_red"], wrap=r)
    add_text(coll, body, "extinguisher_Txt_Agent", "ABC-PULVER\n6 kg", (0.0, -0.035, cz + r), 0.0252, M["text_dark"],
             wrap=r)
    add_text(coll, body, "extinguisher_Txt_Classes", "A   B   C", (0.0, -0.09, cz + r), 0.016, M["text_dark"], wrap=r)
    return root


# ---------------------------------------------------------------------------
# Router
# ---------------------------------------------------------------------------

def router_root(coll, name, tier, x):
    root = make_root(coll, name, (x, 0.0, ROUTER_Z), ROUTER_GAME_POS)
    root["dct_router_tier"] = tier
    return root


def build_router_conduit(coll, M):
    root = make_root(coll, "router_conduit", (ROUTER_X[0], 0.0, ROUTER_Z), ROUTER_GAME_POS)
    p = GPart("router_conduit_Pipe")
    p.gcyl((0.0, 1.02, -0.02), 0.024, 0.024, 1.65, M["galv"], segs=20)
    for y in (0.55, 1.25):
        p.gbox((0.0, y, -0.045), (0.07, 0.02, 0.03), M["galv"])
    # Verschraubung am unteren Rohrende (Kabeleinfuehrung)
    p.gcyl((0.0, 0.205, -0.02), 0.034, 0.034, 0.02, M["gland"], segs=20)
    p.gcyl((0.0, 0.1945, -0.02), 0.016, 0.016, 0.001, M["hole"], segs=16)
    p.build(coll, root)
    return root


def build_router_dsl(coll, M):
    n = "router_t0_dsl"
    root = router_root(coll, n, 0, ROUTER_X[0])
    p = GPart(f"{n}_Body")
    p.gbox((0.0, -0.02, -0.105), (0.30, 0.12, 0.01), M["galv"])
    p.gbox((0.0, -0.04, -0.02), (0.44, 0.20, 0.16), M["dsl_plastic"])
    p.gbox((0.0, 0.075, -0.025), (0.42, 0.03, 0.15), M["dsl_plastic_dark"])
    p.gbox((0.0, 0.094, -0.025), (0.40, 0.008, 0.14), M["dsl_plastic"])
    for i in range(8):
        p.gbox((-0.14 + 0.04 * i, 0.0985, -0.03), (0.022, 0.002, 0.10), M["slot"])
    p.gbox((0.0, -0.04, 0.066), (0.40, 0.16, 0.012), M["dsl_bezel"])
    for i in range(4):
        p.gcyl((-0.16 + 0.04 * i, 0.01, 0.073), 0.006, 0.006, 0.004, M["router_led"], axis="Z", segs=12)
    for i in range(4):
        p.gbox((0.11, -0.01 - 0.022 * i, 0.0725), (0.10, 0.006, 0.002), M["slot"])
    p.gbox((0.13, -0.11, 0.0725), (0.07, 0.03, 0.002), M["sticker"])
    for i in range(2):
        rj45(p, -0.12 + 0.08 * i, -0.08, 0.074, M)
    p.gcyl((0.02, -0.08, 0.0725), 0.006, 0.006, 0.003, M["jack"], axis="Z", segs=14)
    p.gcyl((0.045, -0.08, 0.0725), 0.0025, 0.0025, 0.003, M["hole"], axis="Z", segs=8)
    for sx in (-0.18, 0.18):
        p.gcyl((sx, -0.143, 0.03), 0.010, 0.010, 0.006, M["rubber"], segs=12)
    # DSL-Leitung von der Rueckseite hoch ins Leerrohr
    p.ghose([(-0.06, 0.03, -0.105), (-0.04, 0.12, -0.065), (-0.01, 0.20, -0.025), (0.0, 0.235, -0.02)],
            0.0035, M["plastic_black"])
    p.build(coll, root)

    ap = (0.18, 0.10, -0.04)
    ae = pivot(coll, f"{n}_Pivot_Antenna", root, ap)
    ae["dct_tilt_deg_y"] = 18.0
    a = GPart(f"{n}_Antenna", ap)
    a.gsphere(ap, 0.017, 0.034, M["rubber"], segs=16)
    a.gcyl(off(ap, (0.0, 0.13, 0.0)), 0.007, 0.011, 0.24, M["rubber"], segs=14)
    a.gcyl(off(ap, (0.0, 0.045, 0.0)), 0.0125, 0.0125, 0.012, M["dsl_bezel"], segs=14)
    a.gcyl(off(ap, (0.0, 0.10, 0.0)), 0.0105, 0.0105, 0.010, M["dsl_bezel"], segs=14)
    a.gsphere(off(ap, (0.0, 0.25, 0.0)), 0.008, 0.016, M["rubber"], segs=12)
    a.build(coll, ae, g(*ap))
    ae.rotation_euler.y = math.radians(18.0)

    add_text(coll, root, f"{n}_Txt_Model", "SpeedPort 50", (0.10, 0.03, 0.0725), 0.0264, M["text_light"])
    for i, s in enumerate(("Power", "DSL", "WLAN", "Online")):
        add_text(coll, root, f"{n}_Txt_{s}", s, (-0.16 + 0.04 * i, -0.004, 0.0725), 0.0065, M["text_light"])
    add_text(coll, root, f"{n}_Txt_SN", "SN 4711-0815", (0.13, -0.11, 0.0735), 0.007, M["text_dark"])
    return root


def build_router_vdsl(coll, M):
    n = "router_t1_vdsl"
    root = router_root(coll, n, 1, ROUTER_X[1])
    p = GPart(f"{n}_Body")
    p.gbox((0.0, 0.0, -0.115), (0.40, 0.16, 0.01), M["galv"])
    p.gbox((0.0, 0.0, 0.0), (0.58, 0.30, 0.20), M["router_body"])
    p.gbox((0.0, 0.158, -0.005), (0.56, 0.016, 0.19), M["router_body"])
    p.gbox((0.0, 0.1675, -0.01), (0.40, 0.003, 0.12), M["perf"], uv=br.PERF_TILE)
    for sx in (-0.2905, 0.2905):
        for k in range(6):
            p.gbox((sx, -0.08 + 0.03 * k, 0.0), (0.002, 0.012, 0.14), M["slot"])
    p.gbox((0.0, -0.01, 0.106), (0.54, 0.24, 0.012), M["gloss"])
    p.gbox((0.0, 0.09, 0.1135), (0.54, 0.006, 0.003), M["silver"])
    for i in range(5):
        p.gbox((-0.23 + 0.035 * i, 0.06, 0.1135), (0.018, 0.006, 0.003), M["router_led"])
    for i in range(3):
        rj45(p, -0.14 + 0.14 * i, -0.06, 0.12, M)
    p.gcyl((0.235, -0.06, 0.117), 0.012, 0.012, 0.010, M["rubber"], axis="Z", segs=16)
    for sx in (-0.22, 0.22):
        p.gcyl((sx, 0.168, -0.06), 0.018, 0.018, 0.034, M["rubber"], axis="X", segs=16)
    # VDSL-Leitung von der Rueckseite hoch ins Leerrohr
    p.ghose([(0.0, 0.12, -0.105), (0.0, 0.19, -0.06), (0.0, 0.235, -0.02)], 0.0035, M["plastic_black"])
    p.build(coll, root)

    for side, sx in enumerate((-0.22, 0.22)):
        ap = (sx, 0.168, -0.06)
        tag = "L" if side == 0 else "R"
        ae = pivot(coll, f"{n}_Pivot_Antenna_{tag}", root, ap)
        tilt = -10.0 if side == 0 else 10.0
        ae["dct_tilt_deg_y"] = tilt
        a = GPart(f"{n}_Antenna_{tag}", ap)
        a.gbox(off(ap, (0.0, 0.13, 0.0)), (0.034, 0.21, 0.014), M["rubber"])
        a.gcyl(off(ap, (0.0, 0.235, 0.0)), 0.017, 0.017, 0.014, M["rubber"], axis="Z", segs=16)
        a.gcyl(off(ap, (0.0, 0.025, 0.0)), 0.017, 0.017, 0.014, M["rubber"], axis="Z", segs=16)
        a.gbox(off(ap, (0.0, 0.04, 0.0)), (0.036, 0.004, 0.015), M["silver"])
        a.build(coll, ae, g(*ap))
        ae.rotation_euler.y = math.radians(tilt)

    add_text(coll, root, f"{n}_Txt_Model", "VDSL 250  BUSINESS", (0.13, 0.06, 0.1125), 0.0264, M["text_light"])
    for i, s in enumerate(("PWR", "DSL", "WAN", "LAN", "SYS")):
        add_text(coll, root, f"{n}_Txt_{s}", s, (-0.23 + 0.035 * i, 0.042, 0.1125), 0.007, M["text_light"])
    return root


def build_router_gateway(coll, M):
    n = "router_t2_gateway"
    root = router_root(coll, n, 2, ROUTER_X[2])
    p = GPart(f"{n}_Body")
    p.gbox((0.0, 0.0, 0.0), (0.74, 0.36, 0.24), M["gw_body"])
    p.gbox((0.0, 0.181, -0.02), (0.60, 0.003, 0.16), M["perf"], uv=br.PERF_TILE)
    p.gbox((0.0, 0.0, 0.1225), (0.66, 0.30, 0.005), M["gw_face"])
    for sx in (-0.385, 0.385):
        p.gbox((sx, 0.0, 0.11), (0.03, 0.36, 0.03), M["galv"])
        for k in range(2):
            sy = -0.12 + 0.24 * k
            p.gbox((sx, sy, 0.1255), (0.010, 0.022, 0.002), M["hole"])
            p.gcyl((sx, sy, 0.1265), 0.008, 0.008, 0.004, M["screw"], axis="Z", segs=12)
    p.gbox((-0.23, 0.08, 0.127), (0.14, 0.07, 0.004), M["screen"])
    for i in range(2):
        cx = -0.07 + 0.10 * i
        p.gbox((cx, 0.08, 0.134), (0.075, 0.045, 0.022), M["galv"])
        p.gbox((cx, 0.08, 0.1455), (0.06, 0.03, 0.002), M["jack"])
    p.gbox((-0.07, 0.08, 0.152), (0.03, 0.022, 0.016), M["lc_blue"])
    p.ghose([(-0.07, 0.08, 0.16), (-0.06, 0.15, 0.18), (-0.03, 0.205, 0.13), (0.0, 0.215, -0.02)], 0.005, M["fiber"])
    for i in range(4):
        p.gcyl((0.15 + 0.04 * i, 0.10, 0.127), 0.006, 0.006, 0.004, M["router_led"], axis="Z", segs=12)
    for i in range(5):
        rj45(p, -0.27 + 0.09 * i, -0.06, 0.14, M)
    rj45(p, 0.23, -0.06, 0.14, M, frame="console_blue")
    p.gbox((0.0, -0.135, 0.126), (0.66, 0.025, 0.003), M["perf"], uv=br.PERF_TILE)
    p.build(coll, root)
    add_text(coll, root, f"{n}_Txt_Lcd", "1G FIBER\nUPLINK OK", (-0.23, 0.08, 0.1295), 0.020, M["lcd_text"])
    add_text(coll, root, f"{n}_Txt_Model", "GLASFASER-GATEWAY 1G", (0.21, 0.055, 0.1255), 0.020, M["text_light"])
    add_text(coll, root, f"{n}_Txt_Console", "CONSOLE", (0.23, -0.088, 0.1255), 0.008, M["text_light"])
    return root


def build_router_cabinet(coll, M, is_100g):
    n = "router_t4_core100g" if is_100g else "router_t3_core10g"
    tier = 4 if is_100g else 3
    root = router_root(coll, n, tier, ROUTER_X[tier])
    cab_h = 0.72 if is_100g else 0.56
    cy = 0.06
    top, bottom = cy + cab_h * 0.5, cy - cab_h * 0.5
    zf, zb = 0.215, -0.15           # Vorderkante / Rueckwand
    zc, depth = (zf + zb) * 0.5, zf - zb
    p = GPart(f"{n}_Body")
    # Korpus: Rueckwand, Deckel, Boden, Eckprofile, dunkler Innenraum, Deckelgitter, Kabeleinfuehrung
    p.gbox((0.0, cy, -0.14), (0.84, cab_h, 0.02), M["gw_body"])
    p.gbox((0.0, top - 0.01, zc), (0.84, 0.02, depth), M["gw_body"])
    p.gbox((0.0, bottom + 0.01, zc), (0.84, 0.02, depth), M["gw_body"])
    for sx in (-0.39, 0.39):
        for z in (-0.12, 0.20):
            p.gbox((sx, cy, z), (0.02, cab_h - 0.04, 0.02), M["gw_body"])
    p.gbox((0.0, cy, -0.128), (0.80, cab_h - 0.04, 0.004), M["inner"])
    p.gbox((0.0, top + 0.002, 0.04), (0.50, 0.004, 0.18), M["perf"], uv=br.PERF_TILE)
    p.gcyl((0.0, top + 0.006, -0.02), 0.035, 0.035, 0.012, M["rubber"], segs=20)
    for sx in (-0.30, 0.30):
        p.gbox((sx, top - 0.06, -0.152), (0.06, 0.03, 0.004), M["galv"])
    # 19"-Profilschienen mit Rasterloechern
    hole_count = int((cab_h - 0.08) / 0.0445)
    for rx in (-0.375, 0.375):
        p.gbox((rx, cy, 0.14), (0.035, cab_h - 0.04, 0.02), M["galv"])
        for k in range(hole_count):
            p.gbox((rx, bottom + 0.06 + 0.0445 * k, 0.1505), (0.009, 0.009, 0.002), M["hole"])

    # Typenschild oben, bei Stufe 4 mit zusaetzlicher Lueftungsblende
    p.gbox((0.0, 0.285, 0.148), (0.72, 0.06, 0.006), M["cab_face"])
    if is_100g:
        p.gbox((0.0, 0.36, 0.150), (0.72, 0.06, 0.004), M["perf"], uv=br.PERF_TILE)

    # Patchpanel mit 12 Keystone-Buchsen, Beschriftungsstreifen und 2 Glasfaser-Jumpern
    p.gbox((0.0, 0.20, 0.155), (0.72, 0.08, 0.01), M["galv"])
    for i in range(12):
        p.gbox((-0.275 + 0.05 * i, 0.195, 0.1605), (0.03, 0.026, 0.002), M["hole"])
    p.gbox((0.0, 0.228, 0.1605), (0.60, 0.010, 0.002), M["paper"])
    for sx in (-0.345, 0.345):
        p.gcyl((sx, 0.20, 0.1615), 0.007, 0.007, 0.004, M["screw"], axis="Z", segs=12)
    for i in range(2):
        px = -0.275 + 0.05 * i
        p.gbox((px, 0.195, 0.168), (0.02, 0.022, 0.014), M["lc_blue"])
        p.ghose([(px, 0.195, 0.175), (px - 0.01, 0.15, 0.19), (-0.33 - 0.008 * i, 0.09, 0.185),
                 (-0.335 - 0.008 * i, 0.03, 0.17)], 0.0045, M["fiber"])

    # Kabelfuehrung mit Buerstenleiste und Fuehrungsbuegeln
    p.gbox((0.0, 0.05, 0.150), (0.72, 0.07, 0.006), M["cab_face"])
    p.gbox((0.0, 0.05, 0.1535), (0.66, 0.015, 0.001), M["hole"])
    for i in range(6):
        p.gbox((-0.25 + 0.10 * i, 0.05, 0.162), (0.012, 0.06, 0.018), M["galv"])

    # Switch mit 6 Ports und Port-LEDs
    p.gbox((0.0, -0.09, 0.152), (0.72, 0.08, 0.012), M["cab_face"])
    for i in range(6):
        sx = -0.26 + 0.104 * i
        rj45(p, sx, -0.095, 0.166, M)
        p.gbox((sx, -0.058, 0.1585), (0.012, 0.005, 0.002), M["router_led"])

    if is_100g:
        # 100G-Einschub mit 8 SFP-Kaefigen, 3 davon mit Glasfaser belegt
        p.gbox((0.0, -0.21, 0.152), (0.72, 0.08, 0.012), M["cab_face"])
        for i in range(8):
            qx = -0.28 + 0.08 * i
            p.gbox((qx, -0.215, 0.163), (0.06, 0.036, 0.012), M["galv"])
            p.gbox((qx, -0.215, 0.1695), (0.046, 0.024, 0.002), M["hole"])
            p.gbox((qx, -0.183, 0.1585), (0.010, 0.005, 0.002), M["router_led"])
            if i < 3:
                p.gbox((qx, -0.215, 0.177), (0.024, 0.02, 0.016), M["lc_blue"])
                p.ghose([(qx, -0.215, 0.185), (qx + 0.01, -0.25, 0.20), (qx + 0.03, -0.32, 0.19)],
                        0.0045, M["fiber"])
        p.gbox((0.0, -0.272, 0.150), (0.72, 0.03, 0.004), M["perf"], uv=br.PERF_TILE)
    else:
        p.gbox((0.0, -0.175, 0.150), (0.72, 0.07, 0.004), M["perf"], uv=br.PERF_TILE)
    p.build(coll, root)

    # Abnehmbare Seitenwaende mit Lueftungsschlitzen
    for side, sx in enumerate((-0.41, 0.41)):
        tag = "L" if side == 0 else "R"
        sign = -1.0 if side == 0 else 1.0
        sp = GPart(f"{n}_Panel_Side_{tag}", (sx, cy, zc))
        sp.gbox((sx, cy, zc), (0.02, cab_h, depth), M["gw_body"])
        for k in range(int((cab_h - 0.16) / 0.03)):
            sp.gbox((sx + sign * 0.0105, bottom + 0.09 + 0.03 * k, zc), (0.002, 0.010, 0.18), M["slot"])
        sp.gbox((sx + sign * 0.0115, top - 0.04, zc), (0.004, 0.02, 0.08), M["plastic_black"])
        ob = sp.build(coll, root)
        ob["dct_closed_x"] = float(ob.location.x)
        ob["dct_slide_x"] = sign * SIDE_SLIDE

    # Glastuer, Scharnier links, Schwenkhebelgriff rechts
    hp = (-0.42, cy, zf)
    de = pivot(coll, f"{n}_Hinge_Door", root, hp)
    de["dct_open_deg"] = DOOR_OPEN_DEG
    d = GPart(f"{n}_Door", hp)
    zd, t = zf + 0.008, 0.016
    d.gbox((0.0, top - 0.02, zd), (0.84, 0.04, t), M["gw_body"])
    d.gbox((0.0, bottom + 0.02, zd), (0.84, 0.04, t), M["gw_body"])
    for x in (-0.40, 0.40):
        d.gbox((x, cy, zd), (0.04, cab_h - 0.08, t), M["gw_body"])
    d.gbox((0.0, cy, zd), (0.762, cab_h - 0.078, 0.004), M["glass"])
    for hy in (top - 0.08, bottom + 0.08):
        d.gcyl((-0.42, hy, zf), 0.007, 0.007, 0.06, M["galv"], segs=12)
    d.gbox((0.40, cy, zd + 0.009), (0.022, 0.13, 0.004), M["chrome"])
    d.gbox((0.40, cy + 0.02, zd + 0.016), (0.016, 0.10, 0.010), M["chrome"])
    d.gcyl((0.40, cy - 0.045, zd + 0.012), 0.006, 0.006, 0.004, M["dark"], axis="Z", segs=12)
    d.build(coll, de, g(*hp))

    add_text(coll, root, f"{n}_Txt_Model", "CORE 100G" if is_100g else "CORE 10G", (0.0, 0.285, 0.1515),
             0.034, M["text_light"])
    for i in range(12):
        add_text(coll, root, f"{n}_Txt_Patch{i + 1}", str(i + 1), (-0.275 + 0.05 * i, 0.228, 0.1612),
                 0.007, M["text_dark"])
    return root


# ---------------------------------------------------------------------------
# Aufbau und Vorschau
# ---------------------------------------------------------------------------

def build_all():
    coll = reset_collection()
    M = build_materials()
    build_breaker_box(coll, M)
    build_fuse_cartridge(coll, M, "fuse_d02_ok", FUSE_AT, False)
    build_fuse_cartridge(coll, M, "fuse_d02_blown", (FUSE_AT[0] + 0.06, FUSE_AT[1], FUSE_AT[2]), True)
    build_extinguisher(coll, M)
    build_router_conduit(coll, M)
    build_router_dsl(coll, M)
    build_router_vdsl(coll, M)
    build_router_gateway(coll, M)
    build_router_cabinet(coll, M, False)
    build_router_cabinet(coll, M, True)
    return coll


def _set_open(names, opened):
    for nm in names:
        ob = bpy.data.objects.get(nm)
        if ob is None:
            continue
        if "dct_open_deg" in ob:
            ob.rotation_euler.z = math.radians(ob["dct_open_deg"]) if opened else 0.0
        if "dct_open_deg_x" in ob:
            ob.rotation_euler.x = math.radians(ob["dct_open_deg_x"]) if opened else 0.0
        if "dct_slide_x" in ob:
            ob.location.x = ob["dct_closed_x"] + (ob["dct_slide_x"] if opened else 0.0)


def render_previews():
    sc = bpy.context.scene
    r = sc.render
    sh = sc.display.shading
    keep = (sc.camera, r.engine, r.resolution_x, r.resolution_y, r.resolution_percentage, r.filepath,
            sh.light, sh.color_type, sc.view_settings.exposure)
    cam_data = bpy.data.cameras.new("DCT_U_PreviewCam")
    cam = bpy.data.objects.new("DCT_U_PreviewCam", cam_data)
    sc.collection.objects.link(cam)
    sc.camera = cam
    r.engine = "BLENDER_WORKBENCH"
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE"
    r.resolution_x, r.resolution_y, r.resolution_percentage = 1280, 900, 100
    r.image_settings.file_format = "PNG"
    # Nur fuer die Vorschau: Leerrohr-Kopien ueber den Routern 1-4 (im Spiel teilen sich alle Stufen ein Rohr)
    tmp_pipes = []
    src = bpy.data.objects.get("router_conduit_Pipe")
    if src is not None:
        for x in ROUTER_X[1:]:
            ob = src.copy()
            ob.name = "DCT_U_TmpConduit"
            sc.collection.objects.link(ob)
            ob.parent = None
            mw = src.matrix_world.copy()
            mw.translation.x += x - ROUTER_X[0]
            ob.matrix_world = mw
            tmp_pipes.append(ob)
    breaker_parts = ["breaker_box_Hinge_Door"] + [f"breaker_box_Hinge_SocketLid_{i}" for i in (1, 2, 3)]
    core_parts = ["router_t4_core100g_Hinge_Door", "router_t4_core100g_Panel_Side_R"]
    out = []
    try:
        for name, loc, target, fov, exposure in SHOTS:
            _set_open(breaker_parts, name == "preview_breaker_open")
            _set_open(core_parts, name == "preview_routers")
            sc.view_settings.exposure = exposure
            cam.location = loc
            cam_data.angle = math.radians(fov)
            cam.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
            r.filepath = os.path.join(SCRIPT_DIR or bpy.path.abspath("//"), name + ".png")
            bpy.ops.render.render(write_still=True)
            out.append(r.filepath)
    finally:
        _set_open(breaker_parts + core_parts, False)
        sc.camera, r.engine, r.resolution_x, r.resolution_y, r.resolution_percentage, r.filepath = keep[:6]
        sh.light, sh.color_type, sc.view_settings.exposure = keep[6:]
        for ob in tmp_pipes:
            bpy.data.objects.remove(ob, do_unlink=True)
        bpy.data.objects.remove(cam, do_unlink=True)
        bpy.data.cameras.remove(cam_data)
    return out


if __name__ == "__main__":
    built = build_all()
    roots = [ob for ob in built.objects if ob.parent is None]
    for ob in roots:
        meshes = [c for c in ob.children_recursive if c.type == "MESH"]
        tris = sum(len(c.data.loop_triangles) if c.data.loop_triangles else len(c.data.polygons) for c in meshes)
        print("%-22s Meshes %3d  Polys ~%d" % (ob.name, len(meshes), tris))
    for f in render_previews():
        print("Render", f)
    