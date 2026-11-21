"""Baut den Terminal-Schreibtisch fuer DataCenter Tycoon in Blender neu (Detailstufe 2).

Enthalten sind Tischplatte, Stahlgestell, Unterschrank, USV, Monitor mit Arm, PC-Turm
mit Innenleben, Tastatur mit einzelnen Tasten, Maus, Handy, Kleinteile, Schreibtischlampe,
Kaffeetasse und Buerostuhl.

Aufruf in Blender (Hintergrund):
    blender --background --factory-startup --python tools/blender/build_desk.py

Koordinaten: Godot-Werte (X rechts, Y oben, Z zur Raummitte). g() rechnet nach Blender um
(X, -Z, Y). Der Ursprung liegt am Boden in der Tischmitte, wie der Node3D-Ursprung im Spiel.

Ausgabe: assets/models/terminal_desk.glb
Geometrie wird je Material und Glattheit zu wenigen Meshes zusammengefasst, damit das GLB klein bleibt.
Das Objekt "PcScreenQuad" ist die Bildschirmflaeche. Das Spiel ersetzt sie durch den Live-Spiegel.
Benoetigt Blender 4.x oder neuer (Principled BSDF mit "Emission Color" und "Emission Strength").
"""
import math
import os

import bmesh
import bpy
from mathutils import Euler, Matrix, Vector

MODEL_ID = "terminal_desk"
COLLECTION = "DCT_Desk"
HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models"))
IDENT = Matrix.Identity(4)

# Achsen fuer Zylinder: Blender-Zylinder liegen auf Z, Godot-Y entspricht Blender-Z.
_AXIS = {
    "Y": Matrix.Identity(4),
    "X": Matrix.Rotation(math.pi / 2.0, 4, "Y"),
    "Z": Matrix.Rotation(math.pi / 2.0, 4, "X"),
}


def g(x, y, z):
    """Godot-Position nach Blender: X bleibt, Z wird -Y, Y wird Z."""
    return Vector((x, -z, y))


def gs(x, y, z):
    """Godot-Groesse nach Blender: Tiefe (Godot Z) wird Blender Y, Hoehe (Godot Y) wird Blender Z."""
    return Vector((x, z, y))


def grot(rx, ry, rz):
    """Godot-Drehung in Grad (Yaw um Y) nach Blender-Euler in Radiant."""
    return (math.radians(rx), math.radians(-rz), math.radians(ry))


def frame_of(pos, rot=(0.0, 0.0, 0.0)):
    """Godot-Position und -Drehung als Blender-Matrix."""
    return Matrix.Translation(g(*pos)) @ Euler(grot(*rot)).to_matrix().to_4x4()


def local_matrix(frame, pos, rot):
    """Lokale Godot-Position und -Drehung relativ zu einem Rahmen."""
    return frame @ frame_of(pos, rot)


def make_mat(name, col, rough, metal=0.0, emit=None, emit_strength=0.0, alpha=None):
    m = bpy.data.materials.get(name)
    if m is None:
        m = bpy.data.materials.new(name)
    m.use_nodes = True
    # Rueckseiten nicht zeichnen, sonst konkurrieren Unterseiten mit der Flaeche darunter (Flackern)
    m.use_backface_culling = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (col[0], col[1], col[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit is not None:
        bsdf.inputs["Emission Color"].default_value = (emit[0], emit[1], emit[2], 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_strength
    alpha_value = 1.0
    if alpha is not None:
        alpha_value = alpha
        bsdf.inputs["Alpha"].default_value = alpha
        try:
            m.surface_render_method = "BLENDED"
        except (AttributeError, TypeError):
            m.blend_method = "BLEND"
    m.diffuse_color = (col[0], col[1], col[2], alpha_value)
    return m


def build_materials():
    return {
        "wood": make_mat("DCT_Desk_Wood", (0.42, 0.28, 0.16), 0.50),
        "edge": make_mat("DCT_Desk_Edge", (0.20, 0.13, 0.08), 0.50),
        "frame": make_mat("DCT_Desk_Frame", (0.20, 0.21, 0.23), 0.42, 0.70),
        "steel": make_mat("DCT_Desk_Steel", (0.14, 0.16, 0.20), 0.40, 0.58),
        "steel_dark": make_mat("DCT_Desk_SteelDark", (0.16, 0.17, 0.19), 0.42, 0.58),
        "galv": make_mat("DCT_Desk_Galv", (0.66, 0.67, 0.68), 0.36, 1.0),
        "chrome": make_mat("DCT_Desk_Chrome", (0.85, 0.85, 0.86), 0.10, 1.0),
        "rubber": make_mat("DCT_Desk_Rubber", (0.06, 0.06, 0.07), 0.80),
        "pad": make_mat("DCT_Desk_Pad", (0.08, 0.08, 0.09), 0.92),
        "mouse": make_mat("DCT_Desk_Mouse", (0.50, 0.51, 0.53), 0.40, 0.10),
        "mouse_key": make_mat("DCT_Desk_MouseKey", (0.66, 0.67, 0.69), 0.35, 0.10),
        "plastic": make_mat("DCT_Desk_Plastic", (0.03, 0.03, 0.035), 0.45),
        "key": make_mat("DCT_Desk_Key", (0.24, 0.25, 0.27), 0.66, 0.04),
        "key_light": make_mat("DCT_Desk_KeyLight", (0.36, 0.37, 0.39), 0.62, 0.04),
        "accent_red": make_mat("DCT_Desk_AccentRed", (0.76, 0.24, 0.18), 0.55, 0.05),
        "led_red": make_mat("DCT_Desk_LedRed", (0.82, 0.20, 0.14), 0.40, 0.10,
                            emit=(0.82, 0.20, 0.14), emit_strength=2.0),
        "led_green": make_mat("DCT_Desk_LedGreen", (0.20, 0.90, 0.30), 0.40,
                              emit=(0.20, 0.90, 0.30), emit_strength=8.0),
        "led_blue": make_mat("DCT_Desk_LedBlue", (0.20, 0.60, 1.00), 0.40,
                             emit=(0.20, 0.60, 1.00), emit_strength=6.0),
        "mug": make_mat("DCT_Desk_Mug", (0.88, 0.87, 0.84), 0.28, 0.04),
        "coffee": make_mat("DCT_Desk_Coffee", (0.12, 0.07, 0.04), 0.12, 0.02),
        "cork": make_mat("DCT_Desk_Cork", (0.52, 0.36, 0.20), 0.85),
        "can": make_mat("DCT_Desk_Can", (0.12, 0.30, 0.70), 0.30, 0.60),
        "note": make_mat("DCT_Desk_Note", (0.96, 0.86, 0.30), 0.90),
        "note_pink": make_mat("DCT_Desk_NotePink", (0.96, 0.55, 0.65), 0.90),
        "pen": make_mat("DCT_Desk_Pen", (0.10, 0.20, 0.55), 0.40, 0.10),
        "phone": make_mat("DCT_Desk_Phone", (0.06, 0.06, 0.07), 0.25, 0.40),
        "phone_screen": make_mat("DCT_Desk_PhoneScreen", (0.12, 0.18, 0.28), 0.20,
                                 emit=(0.12, 0.22, 0.40), emit_strength=0.4),
        "pcb": make_mat("DCT_Desk_PCB", (0.03, 0.09, 0.05), 0.55, 0.10),
        "tower": make_mat("DCT_Desk_Tower", (0.07, 0.07, 0.08), 0.42, 0.55),
        "gpu_shroud": make_mat("DCT_Desk_GpuShroud", (0.06, 0.06, 0.07), 0.45, 0.30),
        "ram": make_mat("DCT_Desk_Ram", (0.10, 0.10, 0.12), 0.45, 0.20),
        "fan": make_mat("DCT_Desk_Fan", (0.04, 0.04, 0.05), 0.55, 0.10),
        "heatsink": make_mat("DCT_Desk_Heatsink", (0.75, 0.76, 0.78), 0.35, 1.0),
        "rgb": make_mat("DCT_Desk_RGB", (0.15, 0.75, 1.0), 0.40,
                        emit=(0.15, 0.75, 1.0), emit_strength=6.0),
        "glass": make_mat("DCT_Desk_Glass", (0.06, 0.07, 0.09), 0.04, alpha=0.22),
        "usv": make_mat("DCT_Desk_USV", (0.16, 0.17, 0.19), 0.55, 0.30),
        "screen": make_mat("DCT_Desk_Screen", (0.02, 0.04, 0.08), 0.10,
                           emit=(0.25, 0.55, 0.95), emit_strength=1.2),
        "fabric": make_mat("DCT_Desk_Fabric", (0.18, 0.19, 0.21), 0.86),
        "mesh": make_mat("DCT_Desk_Mesh", (0.05, 0.05, 0.06), 0.60, 0.60),
        "strip": make_mat("DCT_Desk_Strip", (0.10, 0.10, 0.11), 0.50, 0.10),
        "cable": make_mat("DCT_Desk_Cable", (0.05, 0.05, 0.06), 0.80),
        "bulb": make_mat("DCT_Desk_Bulb", (1.00, 0.86, 0.60), 0.30,
                         emit=(1.00, 0.86, 0.60), emit_strength=5.0),
    }


class Scene:
    """Sammelt Geometrie je Gruppe und Glattheit. Pro Gruppe entsteht genau ein Objekt."""

    def __init__(self):
        self._buckets = {}

    def _bm(self, m, smooth, group):
        key = (group or m.name, smooth)
        if key not in self._buckets:
            self._buckets[key] = (bmesh.new(), m)
        return self._buckets[key][0]

    def box(self, m, size, pos, rot=(0.0, 0.0, 0.0), frame=IDENT, group=None):
        bm = self._bm(m, False, group)
        mat = local_matrix(frame, pos, rot) @ Matrix.Diagonal(gs(*size).to_4d())
        bmesh.ops.create_cube(bm, size=1.0, matrix=mat)

    def cyl(self, m, rad, h, pos, axis="Y", rot=(0.0, 0.0, 0.0), frame=IDENT,
            r_top=None, segs=20, smooth=True, group=None):
        bm = self._bm(m, smooth, group)
        mat = local_matrix(frame, pos, rot) @ _AXIS[axis]
        bmesh.ops.create_cone(
            bm, cap_ends=True, cap_tris=False, segments=segs,
            radius1=rad, radius2=rad if r_top is None else r_top,
            depth=h, matrix=mat,
        )

    def sphere(self, m, radius, pos, scale=(1.0, 1.0, 1.0), frame=IDENT, group=None):
        bm = self._bm(m, True, group)
        mat = local_matrix(frame, pos, (0.0, 0.0, 0.0)) @ Matrix.Diagonal(gs(*scale).to_4d())
        bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=10, radius=radius, matrix=mat)

    def flush(self, coll, root):
        for (name, smooth), (bm, m) in self._buckets.items():
            me = bpy.data.meshes.new(name)
            if not smooth and len(bm.edges) > 0:
                bmesh.ops.bevel(
                    bm, geom=list(bm.edges), offset=0.003, offset_type="OFFSET",
                    segments=2, affect="EDGES", clamp_overlap=True,
                )
            bm.to_mesh(me)
            bm.free()
            me.materials.append(m)
            if smooth:
                for poly in me.polygons:
                    poly.use_smooth = True
            ob = bpy.data.objects.new(name, me)
            ob.parent = root
            coll.objects.link(ob)


def build_desk(s, m):
    # Tischplatte mit dunkler Kantenleiste rundum und einer unteren Lippe
    # Platte und Leisten teilen keine Flaeche: Platte (Oberkante 0.8075) liegt 2 mm unter den
    # Leisten (Oberkante 0.8095) und ragt 5 mm in sie hinein. Die Leisten stossen nur an.
    s.box(m["wood"], (1.89, 0.054, 0.89), (0.0, 0.7805, 0.0))
    s.box(m["edge"], (1.92, 0.057, 0.020), (0.0, 0.781, 0.45))
    s.box(m["edge"], (1.92, 0.057, 0.020), (0.0, 0.781, -0.45))
    s.box(m["edge"], (0.020, 0.057, 0.88), (0.95, 0.781, 0.0))
    s.box(m["edge"], (0.020, 0.057, 0.88), (-0.95, 0.781, 0.0))
    s.box(m["edge"], (1.86, 0.0275, 0.84), (0.0, 0.74125, 0.0))

    # Stahlgestell: vier Beine mit Fuss-Platte, Gleiter und Querstreben
    for lx in (-0.875, 0.875):
        for lz in (-0.40, 0.40):
            s.box(m["frame"], (0.045, 0.72, 0.045), (lx, 0.36, lz))
            s.box(m["frame"], (0.07, 0.0215, 0.07), (lx, 0.74425, lz))
            s.box(m["galv"], (0.05, 0.010, 0.05), (lx, 0.017, lz))
            s.cyl(m["rubber"], 0.030, 0.024, (lx, 0.012, lz))
    s.box(m["frame"], (1.75, 0.06, 0.03), (0.0, 0.72, 0.40))
    s.box(m["frame"], (1.75, 0.06, 0.03), (0.0, 0.72, -0.40))
    s.box(m["frame"], (0.03, 0.06, 0.80), (-0.875, 0.72, 0.0))
    s.box(m["frame"], (0.03, 0.06, 0.80), (0.875, 0.72, 0.0))
    s.box(m["frame"], (1.75, 0.03, 0.03), (0.0, 0.14, -0.40))

    # Kabelkanal unter der Platte: Boden plus Gitterstege
    s.box(m["frame"], (1.50, 0.012, 0.10), (0.0, 0.735, -0.33))
    for i in range(9):
        x = -0.60 + i * 0.15
        s.box(m["frame"], (0.008, 0.030, 0.10), (x, 0.735, -0.33))

    # Kabeldurchfuehrung in der Platte
    s.cyl(m["cable"], 0.030, 0.004, (0.50, 0.808, -0.12))


def build_pedestal(s, m):
    ped = frame_of((0.64, 0.0, 0.02))
    s.box(m["steel"], (0.42, 0.72, 0.56), (0.0, 0.385, 0.0), frame=ped)
    for i, dy in enumerate((0.14, 0.37, 0.60)):
        s.box(m["steel_dark"], (0.38, 0.19, 0.012), (0.0, dy, 0.284), frame=ped)
        s.box(m["galv"], (0.14, 0.014, 0.016), (0.0, dy + 0.02, 0.300), frame=ped)
        s.cyl(m["chrome"], 0.007, 0.006, (0.0, dy - 0.02, 0.292), axis="Z", frame=ped)
    for cx in (-0.16, 0.16):
        for cz in (-0.22, 0.22):
            s.cyl(m["rubber"], 0.022, 0.026, (cx, 0.024, cz), axis="X", frame=ped)


def build_usv(s, m):
    s.box(m["usv"], (0.30, 0.22, 0.40), (-0.66, 0.11, -0.10))
    # Front: Lueftungsgitter und Statusanzeige
    for i in range(5):
        s.box(m["fan"], (0.18, 0.006, 0.004), (-0.66, 0.04 + i * 0.03, 0.104))
    s.box(m["led_green"], (0.10, 0.012, 0.004), (-0.66, 0.19, 0.103))
    for fx in (-0.12, 0.12):
        for fz in (-0.14, 0.14):
            s.cyl(m["rubber"], 0.018, 0.010, (-0.66 + fx, 0.005, -0.10 + fz))


def build_monitor(s, m):
    # Fuss, Saeule mit Gelenkkopf und Halter
    s.cyl(m["steel"], 0.11, 0.02, (-0.10, 0.8185, -0.30))
    s.cyl(m["steel"], 0.022, 0.355, (-0.10, 1.00, -0.30), r_top=0.016)
    s.sphere(m["steel"], 0.024, (-0.10, 1.18, -0.30))
    s.box(m["steel"], (0.03, 0.03, 0.08), (-0.10, 1.18, -0.26))
    s.box(m["steel"], (0.06, 0.06, 0.012), (-0.10, 1.18, -0.236))

    # Gehaeuse, Blende und Standfuss-LED
    s.box(m["plastic"], (0.80, 0.44, 0.05), (-0.10, 1.24, -0.205))
    s.box(m["plastic"], (0.86, 0.48, 0.016), (-0.10, 1.24, -0.172))
    s.box(m["led_blue"], (0.012, 0.004, 0.002), (-0.10, 1.012, -0.164))
    # Bildschirmflaeche, im Spiel durch den Live-Spiegel des PCs ersetzt
    s.box(m["screen"], (0.82, 0.44, 0.002), (-0.10, 1.24, -0.1615), group="PcScreenQuad")


def build_tower(s, m):
    f = frame_of((0.68, 0.808, -0.10))
    # Fuesse
    for fx in (-0.10, 0.10):
        for fz in (-0.19, 0.19):
            s.cyl(m["rubber"], 0.018, 0.022, (fx, 0.011, fz), frame=f)
    # Gehaeuse: Boden, Deckel, massive rechte Wand, Rueckwand, Glasscheibe links mit Rahmen
    s.box(m["tower"], (0.24, 0.012, 0.46), (0.0, 0.006, 0.0), frame=f)
    s.box(m["tower"], (0.24, 0.012, 0.46), (0.0, 0.494, 0.0), frame=f)
    s.box(m["tower"], (0.012, 0.47, 0.46), (0.114, 0.25, 0.0), frame=f)
    s.box(m["tower"], (0.22, 0.47, 0.010), (0.0, 0.25, -0.225), frame=f)
    s.box(m["glass"], (0.004, 0.46, 0.44), (-0.114, 0.25, 0.0), frame=f)
    s.box(m["tower"], (0.012, 0.47, 0.012), (-0.114, 0.25, 0.224), frame=f)
    s.box(m["tower"], (0.012, 0.47, 0.012), (-0.114, 0.25, -0.224), frame=f)

    # Front: Lueftungsgitter aus Schlitzen, Power-Taster, LED und zwei USB-Ports
    s.box(m["tower"], (0.24, 0.47, 0.014), (0.0, 0.25, 0.223), frame=f)
    for i in range(10):
        s.box(m["fan"], (0.18, 0.006, 0.004), (0.0, 0.06 + i * 0.034, 0.232), frame=f)
    s.cyl(m["steel"], 0.011, 0.006, (0.06, 0.43, 0.236), axis="Z", frame=f)
    s.box(m["led_blue"], (0.006, 0.006, 0.002), (0.035, 0.43, 0.236), frame=f)
    for ux in (-0.04, -0.06, -0.08):
        s.box(m["plastic"], (0.012, 0.008, 0.004), (ux, 0.43, 0.236), frame=f)

    # Innenleben, sichtbar durch die Glasscheibe
    s.box(m["pcb"], (0.004, 0.40, 0.36), (0.095, 0.26, 0.0), frame=f)
    for i in range(8):
        s.box(m["heatsink"], (0.05, 0.006, 0.12), (0.072, 0.30 + i * 0.015, 0.06), frame=f)
    for i, z in enumerate((0.03, 0.045, 0.06, 0.075)):
        s.box(m["ram"], (0.010, 0.12, 0.006), (0.085, 0.33, z), frame=f)
    # Grafikkarte mit Kuehler-Gehaeuse, drei Luefter zur Glasscheibe und RGB-Leiste
    s.box(m["gpu_shroud"], (0.038, 0.14, 0.30), (0.068, 0.20, -0.02), frame=f)
    for z in (-0.10, -0.01, 0.08):
        s.cyl(m["fan"], 0.042, 0.006, (0.046, 0.20, z), axis="X", frame=f)
    s.box(m["rgb"], (0.004, 0.006, 0.28), (0.047, 0.13, -0.02), frame=f)
    # Netzteil mit Luefter, SSD und Kabelbuendel
    s.box(m["steel_dark"], (0.18, 0.10, 0.14), (-0.02, 0.09, 0.12), frame=f)
    s.cyl(m["fan"], 0.045, 0.006, (-0.02, 0.1435, 0.12), frame=f)
    s.box(m["strip"], (0.07, 0.008, 0.024), (0.05, 0.022, -0.17), frame=f)
    for i in range(3):
        s.cyl(m["cable"], 0.005, 0.10, (0.04, 0.16 + i * 0.012, 0.13), axis="X", frame=f)

    # Rueckseite: I/O-Blende mit Anschluessen und drei PCIe-Slotblenden
    s.box(m["strip"], (0.12, 0.10, 0.004), (-0.02, 0.40, -0.233), frame=f)
    for ix in (-0.060, -0.040, -0.020, 0.000):
        s.box(m["plastic"], (0.010, 0.012, 0.004), (ix, 0.41, -0.236), frame=f)
    for i in range(4):
        s.box(m["galv"], (0.002, 0.040, 0.003), (0.030 + i * 0.012, 0.40, -0.236), frame=f)
    for i in range(3):
        s.box(m["galv"], (0.10, 0.012, 0.004), (0.0, 0.16 + i * 0.050, -0.236), frame=f)


def build_keyboard(s, m):
    kb = frame_of((-0.18, 0.826, 0.16), (0.0, 4.0, 0.0))
    s.box(m["steel"], (0.44, 0.020, 0.145), (0.0, 0.0, 0.0), frame=kb)
    kcap = (0.020, 0.010, 0.020)
    # Hauptblock: vier Reihen mit je 13 Tasten, Escape rot, Modifikatoren hell
    for r in range(4):
        z = -0.052 + r * 0.026
        for c in range(13):
            x = -0.185 + c * 0.0245
            if r == 0 and c == 0:
                mat = m["accent_red"]
            elif c in (0, 12):
                mat = m["key_light"]
            else:
                mat = m["key"]
            s.box(mat, kcap, (x, 0.015, z), frame=kb)
    # Untere Reihe: Modifikatoren links und rechts, Leertaste in der Mitte
    for x in (-0.178, -0.142, -0.106):
        s.box(m["key_light"], (0.032, 0.010, 0.020), (x, 0.015, 0.052), frame=kb)
    s.box(m["key"], (0.14, 0.010, 0.020), (-0.02, 0.015, 0.052), frame=kb)
    for x in (0.078, 0.114, 0.150, 0.186):
        s.box(m["key_light"], (0.032, 0.010, 0.020), (x, 0.015, 0.052), frame=kb)
    # Nummernblock: vier Reihen mit je drei Tasten
    for r in range(4):
        z = -0.052 + r * 0.026
        for c in range(3):
            x = 0.140 + c * 0.0245
            s.box(m["key_light"], kcap, (x, 0.015, z), frame=kb)


def build_mouse(s, m):
    # Mauspad, Oberkante 0.8135 (Tischoberkante 0.808 ohne Z-Fighting)
    s.box(m["pad"], (0.30, 0.004, 0.24), (0.19, 0.8115, 0.16))

    # Kabellose Maus auf dem Pad, Vorderseite zeigt zum Monitor (-Z).
    # Ursprung liegt auf Pad-Oberkante; Laenge 12 cm, Breite 5.0-6.4 cm, Hoehe 3.8 cm.
    mo = frame_of((0.19, 0.8135, 0.16))
    half_len = 0.060

    def squarify(u):
        """Schiebt Einheitswerte nach aussen (f(0)=0, f(+-1)=+-1, glatt): kastigerer Grundriss statt Ei."""
        return u * (1.35 - 0.35 * u * u)

    def body(ux, uy, uz):
        """Punkt der Einheitskugel (ux Seite, uy oben, uz Laenge, vorn = -1) auf die Mausform.
        Abgerundeter Rechteck-Grundriss, hinten breiter, leichte Taille fuer den Daumen,
        flache Front, Buckel hinter der Mitte, Unterseite flach knapp unter dem Pad."""
        sx = squarify(ux)
        sz = squarify(uz)
        half_w = 0.0285 + 0.0035 * sz - 0.0020 * math.exp(-((sz - 0.1) / 0.3) ** 2)
        top = 0.020 + 0.018 * math.exp(-((sz - 0.25) / 0.75) ** 2)
        if uy >= 0.0:
            y = 0.004 + uy * (top - 0.004)
        else:
            y = 0.004 + uy * 0.004
        return Vector((sx * half_w, y, sz * half_len))

    def to_world(p):
        return mo @ g(p.x, p.y, p.z)

    def unit_dir(t, phi):
        """Richtung auf der Einheitskugel: t entlang der Laenge, phi um die Laengsachse (90 = oben)."""
        r = math.sqrt(max(1.0 - t * t, 0.0))
        return (r * math.cos(math.radians(phi)), r * math.sin(math.radians(phi)), t)

    def surface(t, phi, lift):
        """Punkt auf dem Gehaeuse, um lift entlang der Flaechennormale nach aussen versetzt."""
        p = body(*unit_dir(t, phi))
        da = body(*unit_dir(t + 1e-4, phi)) - p
        db = body(*unit_dir(t, phi + 1e-2)) - p
        n = da.cross(db).normalized()
        if n.dot(p - Vector((0.0, 0.004, 0.0))) < 0.0:
            n = -n
        return p + n * lift

    # Gehaeuse: eine verformte UV-Kugel, Pole vorn und hinten, damit oben keine Naht entsteht.
    body_bm = s._bm(m["mouse"], True, None)
    res = bmesh.ops.create_uvsphere(body_bm, u_segments=48, v_segments=32, radius=1.0)
    for v in res["verts"]:
        v.co = to_world(body(v.co.x, v.co.y, v.co.z))

    centre = to_world(Vector((0.0, 0.010, 0.0)))

    def patch(mat, t0, t1, ph0, ph1, lift, nu=12, nv=8, sink=-0.0006):
        """Taste als duenne Schale: Oberseite folgt der Gehaeusewoelbung im Abstand lift,
        rundum eine Randflaeche bis sink unter die Gehaeuseoberflaeche (kein sichtbarer Spalt)."""
        bm = s._bm(mat, True, None)

        def param(i, j):
            return t0 + (t1 - t0) * i / nu, ph0 + (ph1 - ph0) * j / nv

        def add_face(verts, ref):
            f = bm.faces.new(verts)
            f.normal_update()
            if f.normal.dot(f.calc_center_median() - ref) < 0.0:
                f.normal_flip()

        rows = [
            [bm.verts.new(to_world(surface(*param(i, j), lift))) for j in range(nv + 1)]
            for i in range(nu + 1)
        ]
        for i in range(nu):
            for j in range(nv):
                add_face((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]), centre)

        # Randflaeche entlang der Aussenkante, Normalen zeigen von der Tastenmitte weg
        ring = ([(0, j) for j in range(nv)] + [(i, nv) for i in range(nu)]
                + [(nu, j) for j in range(nv, 0, -1)] + [(i, 0) for i in range(nu, 0, -1)])
        mid = to_world(surface(*param(nu / 2.0, nv / 2.0), 0.0))
        low = {ij: bm.verts.new(to_world(surface(*param(*ij), sink))) for ij in ring}
        for k, a in enumerate(ring):
            b = ring[(k + 1) % len(ring)]
            add_face((rows[a[0]][a[1]], rows[b[0]][b[1]], low[b], low[a]), mid)

    # Zwei Haupttasten vorn (vorderes Drittel bis knapp vor die Mitte), 1.3 mm Spalt in der Mitte
    patch(m["mouse_key"], -0.96, -0.15, 92.0, 148.0, 0.0012)
    patch(m["mouse_key"], -0.96, -0.15, 32.0, 88.0, 0.0012)

    # Scrollrad: 4 mm breit, Achse entlang X, im Tastenspalt, 2.3 mm erhaben
    wt = -0.62
    wheel_pos = body(*unit_dir(wt, 90.0))
    s.cyl(m["rubber"], 0.0045, 0.004, (0.0, wheel_pos.y - 0.0022, wheel_pos.z), axis="X", frame=mo)

    # Zwei Daumentasten an der linken Flanke, je 1.2 cm lang, 2.8 mm Abstand
    patch(m["plastic"], -0.10, 0.12, 148.0, 166.0, 0.0008, nu=6, nv=4)
    patch(m["plastic"], 0.17, 0.40, 148.0, 166.0, 0.0008, nu=6, nv=4)


def build_strip_and_notes(s, m):
    # Steckdosenleiste mit vier Buchsen und Schalter
    s.box(m["strip"], (0.28, 0.030, 0.060), (-0.72, 0.823, 0.36))
    for sx in (-0.82, -0.77, -0.72, -0.67):
        s.box(m["galv"], (0.018, 0.002, 0.012), (sx, 0.839, 0.36))
    s.box(m["led_red"], (0.012, 0.010, 0.006), (-0.60, 0.823, 0.392))

    # Haftnotizen: drei leicht versetzte Blaetter
    for i, (col, yaw) in enumerate(((m["note"], 6.0), (m["note_pink"], -4.0), (m["note"], 1.0))):
        s.box(col, (0.07, 0.002, 0.07), (-0.36, 0.809 + i * 0.0025, 0.34), rot=(0.0, yaw, 0.0))

    # Kugelschreiber mit Spitze
    s.cyl(m["pen"], 0.005, 0.14, (-0.20, 0.816, 0.36), axis="X")
    s.cyl(m["steel"], 0.005, 0.02, (-0.12, 0.816, 0.36), axis="X", r_top=0.001)


def build_phone(s, m):
    ph = frame_of((0.50, 0.812, 0.30), (0.0, -8.0, 0.0))
    s.box(m["phone"], (0.072, 0.008, 0.144), (0.0, 0.004, 0.0), frame=ph)
    # Alurahmen als duenner Rand unter dem Gehaeuse, sichtbar an den Seiten
    s.box(m["galv"], (0.076, 0.004, 0.148), (0.0, 0.002, 0.0), frame=ph)
    s.box(m["phone_screen"], (0.064, 0.002, 0.128), (0.0, 0.0085, 0.0), frame=ph)
    s.cyl(m["phone"], 0.003, 0.002, (0.0, 0.0095, -0.058), frame=ph)
    s.box(m["phone_screen"], (0.020, 0.002, 0.003), (0.0, 0.0095, 0.060), frame=ph)
    s.box(m["galv"], (0.004, 0.004, 0.014), (0.038, 0.006, 0.020), frame=ph)
    s.box(m["galv"], (0.004, 0.004, 0.014), (-0.038, 0.006, -0.010), frame=ph)


def build_lamp_and_mug(s, m):
    lamp = frame_of((-0.80, 0.808, -0.28), (0.0, -32.0, 0.0))
    # Fuss mit Schalter, zwei Arme mit Gelenken und Schirm
    s.cyl(m["steel"], 0.078, 0.024, (0.0, 0.012, 0.0), frame=lamp)
    s.cyl(m["steel"], 0.014, 0.010, (0.0, 0.028, 0.040), frame=lamp)
    s.cyl(m["galv"], 0.008, 0.28, (0.0, 0.164, -0.02), rot=(-14.0, 0.0, 0.0), frame=lamp)
    s.sphere(m["steel"], 0.014, (0.0, 0.30, -0.04), frame=lamp)
    s.cyl(m["galv"], 0.008, 0.24, (0.0, 0.37, 0.05), rot=(58.0, 0.0, 0.0), frame=lamp)
    s.sphere(m["steel"], 0.014, (0.0, 0.42, 0.14), frame=lamp)
    s.cyl(m["steel"], 0.075, 0.10, (0.0, 0.44, 0.19), rot=(24.0, 0.0, 0.0), frame=lamp, r_top=0.028)
    s.sphere(m["bulb"], 0.030, (0.0, 0.42, 0.17), frame=lamp)

    # Kaffeetasse mit Untersetzer, Henkel als Bogen aus kurzen Stuecken
    mug = frame_of((-0.68, 0.808, 0.22))
    s.cyl(m["cork"], 0.052, 0.004, (0.0, 0.002, 0.0), frame=mug)
    s.cyl(m["mug"], 0.042, 0.006, (0.0, 0.003, 0.0), frame=mug)
    s.cyl(m["mug"], 0.040, 0.096, (0.0, 0.048, 0.0), frame=mug)
    s.cyl(m["mug"], 0.041, 0.004, (0.0, 0.096, 0.0), frame=mug)
    s.cyl(m["coffee"], 0.037, 0.004, (0.0, 0.088, 0.0), frame=mug)
    for i in range(7):
        t = -math.pi / 2.0 + i * math.pi / 6.0
        x = 0.040 + 0.022 * math.cos(t)
        y = 0.048 + 0.022 * math.sin(t)
        s.box(m["mug"], (0.012, 0.007, 0.010), (x, y, 0.0), rot=(0.0, 0.0, math.degrees(t) + 90.0),
              frame=mug)


def build_chair(s, m):
    ch = frame_of((-0.22, 0.0, 0.86), (0.0, 162.0, 0.0))
    s.cyl(m["steel_dark"], 0.036, 0.09, (0.0, 0.12, 0.0), frame=ch)
    for i in range(5):
        ang = i * 2.0 * math.pi / 5.0
        sx, cz = math.sin(ang), math.cos(ang)
        deg = math.degrees(ang)
        s.box(m["steel_dark"], (0.036, 0.026, 0.28), (sx * 0.14, 0.092, cz * 0.14),
              rot=(0.0, deg, 0.0), frame=ch)
        s.cyl(m["chrome"], 0.012, 0.035, (sx * 0.27, 0.058, cz * 0.27), frame=ch)
        s.cyl(m["rubber"], 0.028, 0.034, (sx * 0.27, 0.030, cz * 0.27), axis="X",
              rot=(0.0, deg, 0.0), frame=ch)
    s.cyl(m["chrome"], 0.030, 0.20, (0.0, 0.27, 0.0), frame=ch)
    s.box(m["steel_dark"], (0.46, 0.04, 0.44), (0.0, 0.40, 0.0), frame=ch)
    s.box(m["fabric"], (0.48, 0.08, 0.46), (0.0, 0.45, 0.0), frame=ch)
    s.box(m["fabric"], (0.46, 0.56, 0.05), (0.0, 0.78, -0.24), rot=(-8.0, 0.0, 0.0), frame=ch)
    s.box(m["mesh"], (0.44, 0.50, 0.01), (0.0, 0.78, -0.27), rot=(-8.0, 0.0, 0.0), frame=ch)
    s.box(m["steel_dark"], (0.46, 0.03, 0.06), (0.0, 1.06, -0.24), rot=(-8.0, 0.0, 0.0), frame=ch)
    for sx in (-0.25, 0.25):
        s.cyl(m["steel_dark"], 0.014, 0.14, (sx, 0.52, 0.0), frame=ch)
        s.box(m["fabric"], (0.05, 0.03, 0.26), (sx, 0.62, -0.01), frame=ch)


def fresh_collection():
    coll = bpy.data.collections.get(COLLECTION)
    if coll is None:
        coll = bpy.data.collections.new(COLLECTION)
    if COLLECTION not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    for ob in list(coll.objects):
        bpy.data.objects.remove(ob, do_unlink=True)
    for me in [me for me in bpy.data.meshes if me.users == 0]:
        bpy.data.meshes.remove(me)
    return coll


def print_bounds(root):
    """Prueft die Begrenzung in Godot-Koordinaten (X, Y oben, Z)."""
    bpy.context.view_layer.update()
    lo = [1e9, 1e9, 1e9]
    hi = [-1e9, -1e9, -1e9]
    count = 0
    for ob in root.children:
        if ob.type != "MESH":
            continue
        count += 1
        for v in ob.data.vertices:
            p = ob.matrix_world @ v.co
            gp = (p.x, p.z, -p.y)
            for i in range(3):
                lo[i] = min(lo[i], gp[i])
                hi[i] = max(hi[i], gp[i])
    print(f"CHECK meshes: {count}")
    print("CHECK bounds min: " + str([round(v, 3) for v in lo]) + " max: " + str([round(v, 3) for v in hi]))


def export_model(root):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, MODEL_ID + ".glb")
    objs = [root] + list(root.children)
    for ob in bpy.context.view_layer.objects:
        ob.select_set(False)
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True)
    print(f"EXPORT {path} ({len(objs)} objects)")


def main():
    coll = fresh_collection()
    root = bpy.data.objects.new(MODEL_ID, None)
    root["dct_model_id"] = MODEL_ID
    coll.objects.link(root)

    m = build_materials()
    s = Scene()
    build_desk(s, m)
    build_pedestal(s, m)
    build_usv(s, m)
    build_monitor(s, m)
    build_tower(s, m)
    build_keyboard(s, m)
    build_mouse(s, m)
    build_strip_and_notes(s, m)
    build_phone(s, m)
    build_lamp_and_mug(s, m)
    build_chair(s, m)
    s.flush(coll, root)

    print_bounds(root)
    export_model(root)


if __name__ == "__main__":
    main()