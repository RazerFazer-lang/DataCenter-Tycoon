"""Blender 5.2: Modelle fuer Roadmap-Paket C (Regale und Einrichtung).

  Regale: shelf_small.glb, shelf_heavy.glb, shelf_pallet.glb, euro_pallet.glb (Masse: scripts/data/shelf_spec.gd)
  Einrichtung: decor_esd_workbench, decor_parts_cabinet, decor_cold_aisle_gate (Door_L/Door_R),
      decor_vending_lounge, decor_cctv_monitor + decor_cctv_cam_head, decor_sofa, decor_water,
      decor_tool_cart, decor_dehumidifier (Fan_0, Tank_Level), decor_logo_sign (Masse: scripts/data/decor_spec.gd)

Leuchtende Materialien heissen LIVE_*, das Spiel schaltet sie mit dem Strom.
Aufruf: blender --background --factory-startup --python tools/blender/build_paket_c.py -- [name ...]
Koordinaten wie im Spiel: X rechts, Y oben, Z nach vorn. Ursprung am Boden in der Mitte.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_desk as bd
from build_desk import Scene, frame_of, g, make_mat

OUT = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "models"))


def lin(c):
    return tuple(x ** 2.2 for x in c)


def mat(name, rgb, rough=0.5, metal=0.0, emit=None, strength=0.0, alpha=None):
    return make_mat(name, lin(rgb), rough, metal, emit=lin(emit) if emit else None, emit_strength=strength, alpha=alpha)


def M():
    return {
        "blue": mat("PC_Blue", (0.10, 0.30, 0.62), 0.38, 0.25),
        "orange": mat("PC_Orange", (0.93, 0.42, 0.10), 0.42, 0.15),
        "dark": mat("PC_Dark", (0.13, 0.14, 0.16), 0.45, 0.45),
        "black": mat("PC_Black", (0.055, 0.058, 0.065), 0.50, 0.20),
        "steel": mat("PC_Steel", (0.46, 0.48, 0.51), 0.36, 0.85),
        "galv": mat("PC_Galv", (0.66, 0.68, 0.70), 0.42, 0.90),
        "chrome": mat("PC_Chrome", (0.86, 0.87, 0.89), 0.12, 1.0),
        "chip": mat("PC_Chip", (0.70, 0.55, 0.36), 0.78),
        "oak": mat("PC_Oak", (0.60, 0.42, 0.24), 0.52),
        "wood": mat("PC_Wood", (0.66, 0.50, 0.32), 0.82),
        "wood_d": mat("PC_WoodDark", (0.54, 0.40, 0.25), 0.85),
        "yellow": mat("PC_Yellow", (0.96, 0.74, 0.10), 0.45, 0.10),
        "red": mat("PC_Red", (0.78, 0.12, 0.11), 0.36, 0.15),
        "white": mat("PC_White", (0.92, 0.93, 0.94), 0.42),
        "grey": mat("PC_Grey", (0.62, 0.64, 0.67), 0.48, 0.10),
        "rubber": mat("PC_Rubber", (0.05, 0.05, 0.055), 0.85),
        "esd": mat("PC_EsdMat", (0.10, 0.27, 0.33), 0.75),
        "glass": mat("PC_Glass", (0.78, 0.88, 0.94), 0.03, alpha=0.08),
        "glass_d": mat("PC_GlassDark", (0.10, 0.12, 0.15), 0.06, alpha=0.40),
        "water": mat("PC_Water", (0.45, 0.72, 0.92), 0.05, alpha=0.38),
        "fabric": mat("PC_Fabric", (0.23, 0.28, 0.36), 0.95),
        "fabric2": mat("PC_FabricCushion", (0.85, 0.50, 0.18), 0.95),
        "leather": mat("PC_Leather", (0.16, 0.10, 0.07), 0.55),
        "screen": mat("LIVE_Screen", (0.02, 0.04, 0.07), 0.10, emit=(0.05, 0.20, 0.36), strength=0.55),
        "led_w": mat("LIVE_White", (0.95, 0.95, 0.92), 0.30, emit=(1.0, 0.98, 0.92), strength=2.2),
        "led_g": mat("LIVE_Green", (0.15, 0.85, 0.35), 0.30, emit=(0.15, 0.95, 0.38), strength=2.4),
        "led_b": mat("LIVE_Blue", (0.15, 0.55, 1.0), 0.30, emit=(0.15, 0.55, 1.0), strength=2.4),
        "led_r": mat("LIVE_Red", (0.95, 0.15, 0.12), 0.30, emit=(1.0, 0.12, 0.10), strength=2.2),
        "led_a": mat("LIVE_Amber", (1.0, 0.65, 0.15), 0.30, emit=(1.0, 0.62, 0.12), strength=2.2),
        "sign": mat("LIVE_Sign", (0.92, 0.96, 1.0), 0.30, emit=(0.24, 0.62, 1.0), strength=2.4),
        "leaf": mat("PC_Leaf", (0.18, 0.42, 0.16), 0.55),
        "soil": mat("PC_Soil", (0.14, 0.10, 0.07), 0.95),
        "pot": mat("PC_Pot", (0.70, 0.69, 0.66), 0.60),
        "green": mat("PC_Green", (0.14, 0.55, 0.28), 0.5, 0.05),
        "can_o": mat("PC_CanO", (0.95, 0.48, 0.10), 0.3, 0.5),
        "can_b": mat("PC_CanB", (0.12, 0.30, 0.78), 0.3, 0.5),
        "can_g": mat("PC_CanG", (0.18, 0.62, 0.26), 0.3, 0.5),
        "can_r": mat("PC_CanR", (0.82, 0.12, 0.14), 0.3, 0.5),
        "paper": mat("PC_Paper", (0.94, 0.94, 0.91), 0.85),
        "cable_y": mat("PC_CableY", (0.95, 0.70, 0.10), 0.6),
        "cable_b": mat("PC_CableB", (0.12, 0.35, 0.85), 0.6),
    }


class Model:
    """Ein GLB mit Wurzel und beweglichen Teilen."""

    def __init__(self, name):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        self.name = name
        self.coll = bpy.context.scene.collection
        self.root = bpy.data.objects.new(name, None)
        self.coll.objects.link(self.root)
        self.m = M()
        self.s = Scene()
        self.parts = []

    def part(self, name, origin):
        e = bpy.data.objects.new(name, None)
        e.parent = self.root
        e.location = g(*origin)
        self.coll.objects.link(e)
        sc = Scene()
        self.parts.append((sc, e))
        return sc

    def save(self, file=None):
        self.s.flush(self.coll, self.root)
        for sc, e in self.parts:
            sc.flush(self.coll, e)
        bpy.context.view_layer.update()
        for ob in bpy.context.scene.objects:
            ob.select_set(True)
        path = os.path.join(OUT, (file or self.name) + ".glb")
        bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True)
        print("MODELL %s %.0f KB" % (os.path.basename(path), os.path.getsize(path) / 1024.0))


def tri(s, mt, size, pos, rot=(0, 0, 0), frame=bd.IDENT):
    s.box(mt, size, pos, rot=rot, frame=frame)


def bolt(s, mt, pos, axis="Z", r=0.008, h=0.006):
    s.cyl(mt, r, h, pos, axis=axis, segs=6, smooth=False)


def perf_post(s, mt, hole, x, z, h, w=0.055, front=1.0, step=0.10):
    """Regalstuetze: U-Profil mit Lochraster vorn."""
    s.box(mt, (w, h, 0.008), (x, h / 2.0, z + front * w * 0.45))
    s.box(mt, (0.008, h, w), (x - w * 0.45, h / 2.0, z))
    s.box(mt, (0.008, h, w), (x + w * 0.45, h / 2.0, z))
    y = 0.08
    while y < h - 0.04:
        s.box(hole, (w * 0.24, 0.030, 0.004), (x, y, z + front * (w * 0.45 + 0.0035)))
        y += step
    s.box(mt, (w + 0.05, 0.010, w + 0.05), (x, 0.005, z))
    for dx in (-0.034, 0.034):
        s.cyl(hole, 0.007, 0.012, (x + dx, 0.014, z + 0.02), segs=6, smooth=False)


def brace(s, mt, a, b, th=0.016, w=0.026):
    """Strebe zwischen zwei Punkten in der YZ-Ebene (gleiche X)."""
    dy, dz = b[1] - a[1], b[2] - a[2]
    ln = math.hypot(dy, dz)
    ang = math.degrees(math.atan2(dz, dy))
    s.box(mt, (w, ln, th), ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2), rot=(ang, 0, 0))


def brace_x(s, mt, a, b, th=0.006, w=0.026):
    """Strebe in der XY-Ebene (gleiche Z)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    ln = math.hypot(dx, dy)
    ang = -math.degrees(math.atan2(dx, dy))
    s.box(mt, (w, ln, th), ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, a[2]), rot=(0, 0, ang))


# ---------------------------------------------------------------- Regale

def shelf_small():
    o = Model("shelf_small")
    s, m = o.s, o.m
    W, H, D = 1.58, 1.84, 0.50
    for sx in (-1, 1):
        for sz in (-1, 1):
            x, z = sx * (W / 2 - 0.022), sz * (D / 2 - 0.022)
            s.box(m["galv"], (0.040, H, 0.004), (x, H / 2, z + sz * 0.018))
            s.box(m["galv"], (0.004, H, 0.040), (x + sx * 0.018, H / 2, z))
            y = 0.06
            while y < H - 0.04:
                s.box(m["black"], (0.010, 0.016, 0.002), (x, y, z + sz * 0.0205))
                y += 0.05
            s.box(m["rubber"], (0.050, 0.014, 0.050), (x, 0.007, z))
    for i, y in enumerate((0.10, 0.52, 0.94, 1.36, 1.82)):
        s.box(m["galv"], (W - 0.03, 0.012, D - 0.03), (0, y - 0.006, 0))
        s.box(m["blue"], (W - 0.07, 0.048, 0.010), (0, y - 0.026, D / 2 - 0.006))
        s.box(m["galv"], (W - 0.07, 0.036, 0.010), (0, y - 0.020, -D / 2 + 0.006))
        for sx in (-1, 1):
            s.box(m["galv"], (0.010, 0.036, D - 0.07), (sx * (W / 2 - 0.012), y - 0.020, 0))
            bolt(s, m["steel"], (sx * (W / 2 - 0.022), y - 0.022, D / 2 + 0.002))
        for k in range(3):
            s.box(m["steel"], (W - 0.10, 0.010, 0.020), (0, y - 0.018, -0.14 + 0.14 * k))
    brace_x(s, m["galv"], (-W / 2 + 0.05, 0.14, -D / 2 + 0.010), (W / 2 - 0.05, 1.78, -D / 2 + 0.010))
    brace_x(s, m["galv"], (W / 2 - 0.05, 0.14, -D / 2 + 0.004), (-W / 2 + 0.05, 1.78, -D / 2 + 0.004))
    for sx in (-1, 1):
        brace(s, m["galv"], (sx * (W / 2 - 0.008), 0.16, -D / 2 + 0.05), (sx * (W / 2 - 0.008), 0.90, D / 2 - 0.05), 0.016, 0.004)
        brace(s, m["galv"], (sx * (W / 2 - 0.008), 0.98, D / 2 - 0.05), (sx * (W / 2 - 0.008), 1.76, -D / 2 + 0.05), 0.016, 0.004)
    # Sichtlagerkaesten oben auf dem Deckblech
    for k, c in enumerate(("red", "blue", "yellow", "blue", "red", "green")):
        x = -0.60 + 0.24 * k
        s.box(m[c], (0.20, 0.010, 0.28), (x, 1.829, 0.02))
        s.box(m[c], (0.20, 0.10, 0.008), (x, 1.872, -0.12))
        s.box(m[c], (0.20, 0.05, 0.008), (x, 1.848, 0.156))
        for dx in (-0.096, 0.096):
            s.box(m[c], (0.008, 0.085, 0.28), (x + dx, 1.866, 0.02))
    o.save()


def shelf_heavy():
    o = Model("shelf_heavy")
    s, m = o.s, o.m
    W, H, D = 1.97, 2.14, 0.68
    for sx in (-1, 1):
        for sz in (-1, 1):
            perf_post(s, m["blue"], m["black"], sx * (W / 2 - 0.034), sz * (D / 2 - 0.034), H, 0.060, sz)
        x = sx * (W / 2 - 0.034)
        for y in (0.30, 0.98, 1.66):
            s.box(m["galv"], (0.026, 0.030, D - 0.10), (x, y, 0))
        brace(s, m["galv"], (x, 0.32, -D / 2 + 0.07), (x, 0.96, D / 2 - 0.07))
        brace(s, m["galv"], (x, 1.00, D / 2 - 0.07), (x, 1.64, -D / 2 + 0.07))
        # Rammschutz vorn
        s.box(m["yellow"], (0.085, 0.26, 0.012), (x, 0.15, D / 2 + 0.004))
        for k in range(3):
            s.box(m["black"], (0.086, 0.026, 0.013), (x, 0.07 + 0.08 * k, D / 2 + 0.0045), rot=(0, 0, 24))
    for y in (0.12, 0.71, 1.30, 1.89):
        s.box(m["chip"], (W - 0.12, 0.030, D - 0.06), (0, y - 0.015, 0))
        for sz in (-1, 1):
            s.box(m["orange"], (W - 0.13, 0.086, 0.030), (0, y - 0.050, sz * (D / 2 - 0.020)))
            s.box(m["orange"], (W - 0.13, 0.016, 0.044), (0, y - 0.010, sz * (D / 2 - 0.030)))
            for sx in (-1, 1):
                s.box(m["orange"], (0.012, 0.15, 0.052), (sx * (W / 2 - 0.070), y - 0.055, sz * (D / 2 - 0.028)))
                for dy in (-0.11, -0.02):
                    bolt(s, m["galv"], (sx * (W / 2 - 0.050), y + dy, sz * (D / 2 + 0.001)), r=0.009)
        for k in range(3):
            s.box(m["galv"], (0.040, 0.030, D - 0.08), (-0.60 + 0.60 * k, y - 0.044, 0))
    brace_x(s, m["galv"], (-W / 2 + 0.07, 0.20, -D / 2 + 0.004), (W / 2 - 0.07, 2.04, -D / 2 + 0.004))
    brace_x(s, m["galv"], (W / 2 - 0.07, 0.20, -D / 2 + 0.010), (-W / 2 + 0.07, 2.04, -D / 2 + 0.010))
    # Traglastschild
    s.box(m["yellow"], (0.34, 0.11, 0.004), (0, 2.075, D / 2 - 0.02))
    s.box(m["dark"], (0.38, 0.02, 0.02), (0, 2.135, D / 2 - 0.03))
    s.box(m["dark"], (W - 0.07, 0.024, 0.024), (0, 2.135, -D / 2 + 0.03))
    s.box(m["dark"], (W - 0.07, 0.024, 0.024), (0, 2.135, D / 2 - 0.034))
    for k in range(4):
        s.box(m["black"], (0.22 - 0.03 * (k % 2), 0.008, 0.002), (-0.02, 2.105 - 0.020 * k, D / 2 - 0.017))
    o.save()


def shelf_pallet():
    o = Model("shelf_pallet")
    s, m = o.s, o.m
    W, H, D = 3.04, 2.46, 1.06
    for sx in (-1, 1):
        for sz in (-1, 1):
            perf_post(s, m["blue"], m["black"], sx * (W / 2 - 0.050), sz * (D / 2 - 0.050), H, 0.092, sz)
            x, z = sx * (W / 2 - 0.050), sz * (D / 2 - 0.050)
        x = sx * (W / 2 - 0.050)
        for y in (0.22, 0.86, 1.50, 2.14):
            s.box(m["galv"], (0.034, 0.036, D - 0.14), (x, y, 0))
        for y, d in ((0.24, 1), (0.88, -1), (1.52, 1)):
            brace(s, m["galv"], (x, y, -d * (D / 2 - 0.10)), (x, y + 0.60, d * (D / 2 - 0.10)), 0.020, 0.030)
        # Anfahrschutz
        s.box(m["yellow"], (0.13, 0.40, 0.016), (x, 0.20, D / 2 + 0.012))
        for k in range(4):
            s.box(m["black"], (0.131, 0.034, 0.017), (x, 0.06 + 0.10 * k, D / 2 + 0.0125), rot=(0, 0, 26))
    for sz in (-1, 1):
        s.box(m["orange"], (W - 0.19, 0.120, 0.044), (0, 1.39, sz * (D / 2 - 0.034)))
        s.box(m["orange"], (W - 0.19, 0.020, 0.052), (0, 1.450, sz * (D / 2 - 0.038)))
        for sx in (-1, 1):
            s.box(m["orange"], (0.016, 0.22, 0.072), (sx * (W / 2 - 0.104), 1.38, sz * (D / 2 - 0.042)))
            for dy in (1.31, 1.46):
                bolt(s, m["galv"], (sx * (W / 2 - 0.070), dy, sz * (D / 2 + 0.002)), r=0.012)
    for k in range(6):
        s.box(m["galv"], (0.05, 0.045, D - 0.14), (-1.18 + 0.472 * k, 1.435, 0))
    # Rueckwandgitter der oberen Ebene
    for k in range(15):
        s.box(m["galv"], (0.005, 0.90, 0.005), (-1.40 + 0.20 * k, 1.95, -D / 2 + 0.012))
    for k in range(5):
        s.box(m["galv"], (W - 0.20, 0.005, 0.005), (0, 1.52 + 0.215 * k, -D / 2 + 0.016))
    s.box(m["blue"], (W - 0.10, 0.034, 0.034), (0, H - 0.03, -D / 2 + 0.05))
    s.box(m["yellow"], (0.46, 0.15, 0.004), (0, 1.39, D / 2 - 0.0105))
    for k in range(3):
        s.box(m["black"], (0.34 - 0.06 * k, 0.012, 0.002), (0, 1.425 - 0.032 * k, D / 2 - 0.0075))
    # Bodenmarkierung
    for sx in (-0.47, 0.47):
        s.box(m["yellow"], (0.04, 0.002, D - 0.10), (sx, 0.002, 0))
    o.save()


def euro_pallet():
    o = Model("euro_pallet")
    s, m = o.s, o.m
    W, D = 0.86, 0.98
    for k in range(5):
        x = -W / 2 + 0.07 + k * (W - 0.14) / 4
        s.box(m["wood"], (0.132 if k % 2 == 0 else 0.10, 0.022, D), (x, 0.133, 0), rot=(0, 0.2 * (k - 2), 0))
    for sz in (-1, 0, 1):
        s.box(m["wood_d"], (W, 0.022, 0.12), (0, 0.111, sz * (D / 2 - 0.06)))
        s.box(m["wood"], (W, 0.020, 0.10), (0, 0.010, sz * (D / 2 - 0.06)))
        for sx in (-1, 0, 1):
            s.box(m["wood_d"], (0.12, 0.080, 0.11), (sx * (W / 2 - 0.06), 0.060, sz * (D / 2 - 0.06)))
    for k in range(5):
        x = -W / 2 + 0.07 + k * (W - 0.14) / 4
        for sz in (-1, 0, 1):
            for dx in (-0.03, 0.03):
                s.cyl(m["steel"], 0.004, 0.003, (x + dx, 0.1448, sz * (D / 2 - 0.06)), segs=8)
    o.save()


# ---------------------------------------------------------------- Einrichtung

def esd_workbench():
    o = Model("decor_esd_workbench")
    s, m = o.s, o.m
    # Untergestell in C-Form, Hoehe der Matte 0.886 wie an der grossen Werkbank
    for sx in (-1, 1):
        x = sx * 0.72
        s.box(m["white"], (0.07, 0.05, 0.74), (x, 0.030, 0.0))
        s.box(m["white"], (0.07, 0.80, 0.09), (x, 0.44, -0.28))
        s.box(m["white"], (0.06, 0.05, 0.66), (x, 0.815, 0.02))
        for sz in (-0.32, 0.32):
            s.cyl(m["rubber"], 0.028, 0.012, (x, 0.006, sz))
    s.box(m["white"], (1.38, 0.07, 0.05), (0, 0.50, -0.30))
    s.box(m["grey"], (1.60, 0.040, 0.82), (0, 0.860, 0.0))
    s.box(m["dark"], (1.60, 0.042, 0.010), (0, 0.860, 0.414))
    s.box(m["esd"], (1.10, 0.006, 0.60), (0.0, 0.883, 0.06))
    s.cyl(m["chrome"], 0.012, 0.008, (-0.50, 0.889, 0.32))
    # Schubladenblock
    s.box(m["white"], (0.42, 0.46, 0.56), (0.46, 0.60, 0.02))
    for k in range(4):
        y = 0.425 + 0.112 * k
        s.box(m["grey"], (0.39, 0.098, 0.012), (0.46, y, 0.306))
        s.box(m["dark"], (0.16, 0.014, 0.018), (0.46, y + 0.02, 0.318))
    # Aufbau: zwei Saeulen, Lochwand, Geraeteboard, Leuchte
    for sx in (-1, 1):
        s.box(m["white"], (0.05, 0.84, 0.05), (sx * 0.76, 1.28, -0.37))
        s.box(m["white"], (0.04, 0.04, 0.42), (sx * 0.76, 1.665, -0.19))
    s.box(m["dark"], (1.46, 0.50, 0.014), (0, 1.20, -0.385))
    for ix in range(24):
        for iy in range(8):
            s.box(m["black"], (0.010, 0.010, 0.002), (-0.69 + 0.06 * ix, 0.99 + 0.06 * iy, -0.3775))
    s.box(m["grey"], (1.50, 0.022, 0.26), (0, 1.480, -0.26))
    s.box(m["grey"], (1.46, 0.045, 0.14), (0, 1.672, 0.0))
    s.box(m["led_w"], (1.38, 0.010, 0.09), (0, 1.646, 0.0))
    # Oszilloskop
    f = frame_of((-0.44, 1.491, -0.25))
    s.box(m["white"], (0.40, 0.17, 0.18), (0, 0.085, 0), frame=f)
    s.box(m["screen"], (0.21, 0.125, 0.004), (-0.07, 0.09, 0.0915), frame=f)
    for k in range(3):
        s.box(m["led_g"], (0.19, 0.0016, 0.002), (-0.07, 0.06 + 0.03 * k, 0.094), frame=f)
    for iy in range(2):
        for ix in range(3):
            s.cyl(m["dark"], 0.013, 0.014, (0.075 + 0.045 * ix, 0.07 + 0.055 * iy, 0.096), axis="Z", frame=f)
    for k in range(4):
        s.cyl(m["chrome"], 0.008, 0.016, (0.06 + 0.035 * k, 0.025, 0.096), axis="Z", frame=f)
    # Labornetzteil
    f = frame_of((0.04, 1.491, -0.25))
    s.box(m["dark"], (0.26, 0.15, 0.18), (0, 0.075, 0), frame=f)
    s.box(m["led_r"], (0.085, 0.030, 0.003), (-0.06, 0.105, 0.0915), frame=f)
    s.box(m["led_g"], (0.085, 0.030, 0.003), (0.06, 0.105, 0.0915), frame=f)
    for k, c in enumerate(("red", "black", "green")):
        s.cyl(m[c], 0.011, 0.020, (-0.06 + 0.06 * k, 0.035, 0.096), axis="Z", frame=f)
    # Loetstation mit Kolben im Halter
    f = frame_of((0.46, 1.491, -0.25))
    s.box(m["blue"], (0.20, 0.12, 0.16), (0, 0.06, 0), frame=f)
    s.box(m["led_a"], (0.07, 0.030, 0.003), (-0.03, 0.08, 0.0815), frame=f)
    s.cyl(m["dark"], 0.016, 0.014, (0.06, 0.06, 0.085), axis="Z", frame=f)
    s.cyl(m["steel"], 0.028, 0.10, (0.70 - 0.46, 0.05, 0.02), rot=(30, 0, 0), r_top=0.020, frame=f)
    # Werkzeug an der Lochwand
    for k, c in enumerate(("red", "yellow", "blue", "red", "yellow", "blue")):
        x = -0.60 + 0.075 * k
        s.cyl(m[c], 0.011, 0.085, (x, 1.30, -0.365))
        s.cyl(m["chrome"], 0.0035, 0.10, (x, 1.21, -0.365))
    for k in range(5):
        x = 0.02 + 0.085 * k
        ln = 0.15 + 0.022 * k
        s.box(m["chrome"], (0.016, ln, 0.006), (x, 1.36 - ln / 2, -0.368))
        s.cyl(m["chrome"], 0.017, 0.007, (x, 1.36 - ln, -0.368), axis="Z")
    s.box(m["red"], (0.13, 0.05, 0.03), (0.60, 1.10, -0.362))
    # ESD-Armband und Steckdosenleiste
    s.box(m["dark"], (0.60, 0.045, 0.05), (-0.36, 0.905, -0.34))
    for k in range(6):
        s.cyl(m["black"], 0.020, 0.004, (-0.60 + 0.096 * k, 0.929, -0.34))
    s.box(m["led_g"], (0.010, 0.010, 0.004), (-0.09, 0.905, -0.314))
    bd.ring(s, m["yellow"], frame_of((-0.62, 0.894, 0.30)), (0, 0, 0), 0.032, "X", tube=0.010)
    o.save()


def parts_cabinet():
    o = Model("decor_parts_cabinet")
    s, m = o.s, o.m
    W, H, D = 1.16, 2.06, 0.60
    s.box(m["dark"], (W, 0.10, D - 0.06), (0, 0.05, -0.02))
    for sx in (-1, 1):
        s.box(m["grey"], (0.022, H - 0.10, D - 0.02), (sx * (W / 2 - 0.011), H / 2 + 0.05, -0.01))
    s.box(m["grey"], (W, 0.022, D - 0.02), (0, H - 0.011, -0.01))
    s.box(m["grey"], (W, H - 0.10, 0.014), (0, H / 2 + 0.05, -D / 2 + 0.012))
    s.box(m["grey"], (W, 0.022, D - 0.04), (0, 0.112, -0.01))
    s.box(m["blue"], (W + 0.004, 0.13, 0.014), (0, H - 0.07, D / 2 - 0.018))
    s.box(m["led_w"], (W - 0.14, 0.012, 0.02), (0, H - 0.16, D / 2 - 0.05))
    # Unten zwei Stahltueren mit Lueftungsschlitzen
    for sx in (-1, 1):
        s.box(m["blue"], (W / 2 - 0.028, 0.74, 0.020), (sx * (W / 4 - 0.002), 0.50, D / 2 - 0.022))
        s.box(m["dark"], (0.020, 0.16, 0.026), (sx * 0.045, 0.56, D / 2 - 0.004))
        for k in range(5):
            s.box(m["dark"], (0.20, 0.008, 0.004), (sx * 0.29, 0.22 + 0.022 * k, D / 2 - 0.011))
        for y in (0.20, 0.80):
            s.cyl(m["steel"], 0.010, 0.07, (sx * (W / 2 - 0.020), y, D / 2 - 0.012))
    # Arbeitsplatte zwischen unten und oben
    s.box(m["oak"], (W - 0.01, 0.030, D), (0, 0.895, 0.0))
    # Boeden oben mit Sichtlagerkaesten und Kabeltrommeln
    cols = ["red", "blue", "yellow", "green", "blue", "red", "yellow", "blue"]
    for r, y in enumerate((0.93, 1.16, 1.39)):
        if r > 0:
            s.box(m["grey"], (W - 0.05, 0.016, D - 0.10), (0, y - 0.008, -0.04))
        if r < 2:
            for k in range(5):
                c = m[cols[(k + r * 3) % 8]]
                x = -0.43 + 0.215 * k
                s.box(c, (0.19, 0.010, 0.34), (x, y + 0.008, 0.02))
                s.box(c, (0.19, 0.15, 0.008), (x, y + 0.080, -0.146))
                s.box(c, (0.19, 0.075, 0.008), (x, y + 0.042, 0.186))
                for dx in (-0.091, 0.091):
                    s.box(c, (0.008, 0.125, 0.34), (x + dx, y + 0.066, 0.02))
                s.box(m["paper"], (0.10, 0.030, 0.002), (x, y + 0.042, 0.1915))
    for k, (c, x) in enumerate((("cable_y", -0.36), ("cable_b", 0.0), ("red", 0.36))):
        f = frame_of((x, 1.39 + 0.155, -0.02))
        for dz in (-0.075, 0.075):
            s.cyl(m["oak"], 0.150, 0.014, (0, 0, dz), axis="Z", frame=f, segs=32)
        for q in range(6):
            s.cyl(m[c], 0.118 - 0.002 * (q % 2), 0.022, (0, 0, -0.056 + 0.0224 * q), axis="Z", frame=f, segs=32)
        s.cyl(m["black"], 0.030, 0.172, (0, 0, 0), axis="Z", frame=f)
    s.box(m["grey"], (W - 0.05, 0.016, D - 0.10), (0, 1.72, -0.04))
    for k in range(4):
        s.box(m["wood"], (0.20, 0.12, 0.26), (-0.36 + 0.24 * k, 1.79, -0.02))
        s.box(m["paper"], (0.09, 0.05, 0.002), (-0.36 + 0.24 * k, 1.80, 0.1115))
    # Glastueren oben
    for sx in (-1, 1):
        x = sx * (W / 4 - 0.002)
        s.box(m["glass"], (W / 2 - 0.10, 0.90, 0.006), (x, 1.40, D / 2 - 0.020))
        for dx in (-1, 1):
            s.box(m["steel"], (0.030, 0.98, 0.018), (x + dx * (W / 4 - 0.030), 1.40, D / 2 - 0.020))
        for y in (0.925, 1.875):
            s.box(m["steel"], (W / 2 - 0.06, 0.034, 0.018), (x, y, D / 2 - 0.020))
        s.cyl(m["chrome"], 0.007, 0.18, (sx * 0.040, 1.36, D / 2 + 0.010))
    o.save()


def cold_aisle_gate():
    o = Model("decor_cold_aisle_gate")
    s, m = o.s, o.m
    for sx in (-1, 1):
        x = sx * 1.05
        s.box(m["dark"], (0.16, 2.40, 0.18), (x, 1.20, 0))
        s.box(m["black"], (0.30, 0.020, 0.26), (x, 0.010, 0))
        s.box(m["led_b"], (0.012, 2.10, 0.012), (x - sx * 0.080, 1.22, 0.085))
        s.box(m["led_b"], (0.012, 2.10, 0.012), (x - sx * 0.080, 1.22, -0.085))
        for k in range(4):
            bolt(s, m["galv"], (x + sx * 0.11, 0.024, -0.09 + 0.06 * k), axis="Y", r=0.010)
    s.box(m["dark"], (2.28, 0.24, 0.24), (0, 2.48, 0))
    s.box(m["black"], (0.62, 0.15, 0.010), (0, 2.485, 0.1245))
    s.box(m["screen"], (0.58, 0.12, 0.004), (0, 2.485, 0.1300))
    s.box(m["led_w"], (1.80, 0.010, 0.06), (0, 2.356, 0.06))
    s.box(m["galv"], (2.04, 0.026, 0.050), (0, 2.372, -0.04))
    s.box(m["galv"], (1.94, 0.006, 0.030), (0, 0.003, 0.0))
    # Bewegungsmelder
    s.box(m["black"], (0.14, 0.045, 0.030), (0.70, 2.43, 0.132))
    s.cyl(m["led_r"], 0.008, 0.006, (0.70, 2.43, 0.149), axis="Z")
    s.box(m["black"], (0.14, 0.045, 0.030), (-0.70, 2.43, -0.132))
    # Schiebetueren: eigene Knoten, Ursprung in der Fluegelmitte
    for name, sx in (("Door_L", -1), ("Door_R", 1)):
        d = o.part(name, (sx * 0.485, 0.0, -0.02 * sx))
        d.box(m["glass"], (0.90, 2.22, 0.010), (0, 1.22, 0))
        for dx in (-0.470, 0.470):
            d.box(m["steel"], (0.040, 2.30, 0.030), (dx, 1.20, 0))
        for y in (0.055, 2.335):
            d.box(m["steel"], (0.96, 0.070, 0.030), (0, y, 0))
        d.box(m["white"], (0.86, 0.10, 0.004), (0, 1.15, 0.008), )
        d.cyl(m["chrome"], 0.010, 0.50, (-sx * 0.40, 1.15, 0.045))
        for y in (0.94, 1.36):
            d.cyl(m["chrome"], 0.008, 0.03, (-sx * 0.40, y, 0.028), axis="Z")
        d.cyl(m["galv"], 0.028, 0.016, (-0.30, 2.372, 0), axis="Z")
        d.cyl(m["galv"], 0.028, 0.016, (0.30, 2.372, 0), axis="Z")
    o.save()


def vending():
    o = Model("decor_vending_lounge")
    s, m = o.s, o.m
    W, H, D = 0.98, 1.96, 0.82
    s.box(m["black"], (W, 0.06, D - 0.08), (0, 0.03, -0.02))
    s.box(m["dark"], (0.03, H - 0.06, D - 0.04), (-W / 2 + 0.015, H / 2 + 0.03, -0.02))
    s.box(m["dark"], (0.03, H - 0.06, D - 0.04), (W / 2 - 0.015, H / 2 + 0.03, -0.02))
    s.box(m["dark"], (W, 0.03, D - 0.04), (0, H - 0.015, -0.02))
    s.box(m["dark"], (W, H - 0.06, 0.03), (0, H / 2 + 0.03, -D / 2 + 0.035))
    # Front rechts: Kaffeeteil, links: Glasfenster mit Dosen
    s.box(m["red"], (W, 0.20, 0.05), (0, H - 0.115, D / 2 - 0.035))
    s.box(m["led_w"], (W - 0.16, 0.10, 0.006), (0, H - 0.115, D / 2 - 0.008))
    s.box(m["black"], (0.36, 1.42, 0.05), (0.31, 1.03, D / 2 - 0.035))
    s.box(m["black"], (0.64, 0.28, 0.05), (-0.17, 0.22, D / 2 - 0.035))
    s.box(m["dark"], (0.36, 0.28, 0.05), (0.31, 0.20, D / 2 - 0.035))
    for x in (-0.470, 0.125):
        s.box(m["black"], (0.040, 1.40, 0.05), (x, 1.05, D / 2 - 0.035))
    s.box(m["black"], (0.60, 0.040, 0.05), (-0.17, 1.735, D / 2 - 0.035))
    s.box(m["glass"], (0.56, 1.34, 0.006), (-0.17, 1.05, D / 2 - 0.016))
    s.box(m["white"], (0.60, 1.40, 0.010), (-0.17, 1.05, -0.18))
    s.box(m["led_w"], (0.02, 1.30, 0.02), (-0.445, 1.05, D / 2 - 0.085))
    cans = ["can_r", "can_b", "can_g", "can_o"]
    for r in range(5):
        y = 0.40 + 0.265 * r
        s.box(m["galv"], (0.56, 0.012, 0.42), (-0.17, y, 0.06))
        s.box(m["paper"], (0.54, 0.030, 0.004), (-0.17, y - 0.006, 0.272))
        for c in range(5):
            x = -0.40 + 0.115 * c
            for q in range(2):
                z = 0.20 - 0.11 * q
                cm = m[cans[(c + r) % 4]]
                if r < 3:
                    s.cyl(cm, 0.033, 0.115, (x, y + 0.066, z), segs=20)
                    s.cyl(m["chrome"], 0.030, 0.006, (x, y + 0.126, z), segs=20)
                else:
                    s.cyl(cm, 0.031, 0.14, (x, y + 0.078, z), segs=18)
                    s.cyl(cm, 0.031, 0.04, (x, y + 0.168, z), segs=18, r_top=0.013)
                    s.cyl(m["white"], 0.014, 0.020, (x, y + 0.198, z), segs=14)
    # Ausgabefach unten
    s.box(m["steel"], (0.50, 0.15, 0.010), (-0.17, 0.22, D / 2 - 0.006))
    s.box(m["black"], (0.44, 0.10, 0.012), (-0.17, 0.215, D / 2 - 0.002))
    # Kaffeeteil: Display, Tasten, Ausgabe mit Becher
    s.box(m["screen"], (0.24, 0.16, 0.006), (0.31, 1.50, D / 2 - 0.007))
    for r in range(3):
        for c in range(3):
            s.cyl(m["led_b"] if (r, c) == (0, 0) else m["grey"], 0.020, 0.010, (0.23 + 0.08 * c, 1.34 - 0.065 * r, D / 2 - 0.006), axis="Z", segs=16)
    s.box(m["steel"], (0.10, 0.06, 0.012), (0.36, 1.10, D / 2 - 0.006))
    s.box(m["led_g"], (0.050, 0.006, 0.004), (0.36, 1.125, D / 2))
    s.box(m["steel"], (0.06, 0.09, 0.014), (0.24, 1.09, D / 2 - 0.006))
    s.box(m["dark"], (0.26, 0.34, 0.012), (0.31, 0.80, D / 2 - 0.008))
    s.box(m["black"], (0.22, 0.28, 0.006), (0.31, 0.80, D / 2 - 0.001))
    s.box(m["steel"], (0.10, 0.04, 0.06), (0.31, 0.92, D / 2 + 0.02))
    s.cyl(m["chrome"], 0.008, 0.03, (0.29, 0.895, D / 2 + 0.03))
    s.cyl(m["chrome"], 0.008, 0.03, (0.33, 0.895, D / 2 + 0.03))
    s.box(m["steel"], (0.20, 0.012, 0.09), (0.31, 0.662, D / 2 + 0.03))
    s.cyl(m["paper"], 0.030, 0.085, (0.31, 0.711, D / 2 + 0.035), r_top=0.038, segs=20)
    s.cyl(m["leather"], 0.035, 0.004, (0.31, 0.748, D / 2 + 0.035), segs=20)
    for k in range(6):
        s.box(m["black"], (0.26, 0.008, 0.004), (0.31, 0.13 + 0.022 * k, D / 2 - 0.008))
    o.save()


def cctv():
    o = Model("decor_cctv_monitor")
    s, m = o.s, o.m
    s.box(m["black"], (0.50, 0.030, 0.42), (0, 0.015, 0))
    for sx in (-0.21, 0.21):
        for sz in (-0.17, 0.17):
            bolt(s, m["galv"], (sx, 0.034, sz), axis="Y", r=0.012, h=0.010)
    s.box(m["dark"], (0.34, 1.90, 0.18), (0, 0.98, 0))
    s.box(m["grey"], (0.30, 1.86, 0.012), (0, 0.98, 0.094))
    s.box(m["black"], (0.30, 0.46, 0.012), (0, 1.62, 0.106))
    s.box(m["screen"], (0.27, 0.40, 0.004), (0, 1.62, 0.1135))
    for k in range(3):
        s.box(m["led_b"], (0.22, 0.004, 0.002), (0, 1.50 + 0.035 * k, 0.1160))
    s.box(m["led_g"], (0.26, 0.010, 0.006), (0, 1.32, 0.102))
    # Lautsprecher, Notruftaste, Plakette
    for r in range(4):
        for c in range(6):
            s.cyl(m["black"], 0.006, 0.004, (-0.060 + 0.024 * c, 1.18 - 0.024 * r, 0.101), axis="Z", segs=8)
    s.cyl(m["red"], 0.034, 0.018, (0, 1.00, 0.106), axis="Z", segs=24)
    bd.ring(s, m["yellow"], frame_of((0, 1.00, 0.103)), (0, 0, 0), 0.046, "Z", tube=0.010)
    s.box(m["yellow"], (0.16, 0.16, 0.003), (0, 0.72, 0.101))
    s.box(m["black"], (0.085, 0.055, 0.002), (-0.008, 0.72, 0.1035))
    s.box(m["black"], (0.030, 0.034, 0.002), (0.052, 0.72, 0.1035), rot=(0, 0, 45))
    for k in range(5):
        s.box(m["black"], (0.22, 0.008, 0.004), (0, 0.16 + 0.024 * k, 0.101))
    # Mast fuer den Kamerakopf
    s.cyl(m["galv"], 0.034, 0.42, (0, 2.14, 0.0))
    s.cyl(m["dark"], 0.055, 0.030, (0, 1.945, 0.0))
    s.cyl(m["dark"], 0.050, 0.036, (0, 2.345, 0.03))
    s.box(m["dark"], (0.05, 0.05, 0.10), (0, 2.33, 0.03))
    o.save()
    o = Model("decor_cctv_cam_head")
    s, m = o.s, o.m
    s.cyl(m["white"], 0.046, 0.05, (0, -0.01, 0.0))
    s.box(m["white"], (0.11, 0.10, 0.26), (0, 0.05, 0.08), rot=(14, 0, 0))
    s.box(m["grey"], (0.13, 0.014, 0.30), (0, 0.105, 0.10), rot=(14, 0, 0))
    s.cyl(m["black"], 0.046, 0.03, (0, 0.018, 0.212), axis="Z", rot=(14, 0, 0), segs=28)
    s.cyl(m["glass_d"], 0.036, 0.006, (0, 0.014, 0.230), axis="Z", rot=(14, 0, 0), segs=28)
    for k in range(6):
        a = k * math.pi / 3
        s.cyl(m["led_r"], 0.005, 0.004, (0.038 * math.cos(a), 0.016 + 0.038 * math.sin(a), 0.231), axis="Z", segs=8)
    o.save()


def soft_box(o, name_mat, size, pos, rot=(0, 0, 0), r=0.06, frame=bd.IDENT):
    """Polster: stark gerundeter Quader."""
    bm = o.s._bm(o.m[name_mat], True, "soft_%s_%d" % (name_mat, len(o.s._buckets)))
    t = bmesh.new()
    bmesh.ops.create_cube(t, size=1.0, matrix=Matrix.Diagonal(bd.gs(*size).to_4d()))
    bmesh.ops.bevel(t, geom=list(t.edges), offset=r, offset_type="OFFSET", segments=6, profile=0.6, affect="EDGES", clamp_overlap=True)
    mw = bd.local_matrix(frame, pos, rot)
    vmap = {}
    for v in t.verts:
        vmap[v] = bm.verts.new(mw @ v.co)
    for f in t.faces:
        bm.faces.new([vmap[v] for v in f.verts])
    t.free()


def sofa():
    o = Model("decor_sofa")
    s, m = o.s, o.m
    for sx in (-0.92, 0.92):
        for sz in (-0.34, 0.34):
            s.cyl(m["oak"], 0.026, 0.12, (sx, 0.06, sz), r_top=0.032)
    s.box(m["fabric"], (1.96, 0.16, 0.80), (0, 0.20, 0.0))
    for sx in (-0.45, 0.45):
        soft_box(o, "fabric", (0.88, 0.20, 0.70), (sx, 0.36, 0.06), r=0.075)
        soft_box(o, "fabric", (0.88, 0.46, 0.20), (sx, 0.60, -0.26), rot=(-12, 0, 0), r=0.085)
    for sx in (-1, 1):
        soft_box(o, "fabric", (0.18, 0.44, 0.84), (sx * 0.96, 0.40, 0.0), r=0.075)
    soft_box(o, "fabric", (2.02, 0.56, 0.18), (0, 0.48, -0.37), r=0.07)
    soft_box(o, "fabric2", (0.40, 0.38, 0.15), (-0.68, 0.60, -0.06), rot=(-22, 18, 8), r=0.070)
    soft_box(o, "fabric2", (0.40, 0.38, 0.15), (0.66, 0.60, -0.08), rot=(-20, -14, -6), r=0.070)
    # Decke ueber der Lehne
    s.box(m["paper"], (0.44, 0.016, 0.30), (0.20, 0.775, -0.36), rot=(0, 3, 0))
    s.box(m["paper"], (0.44, 0.26, 0.014), (0.20, 0.66, -0.175), rot=(-12, 3, 0))
    o.save()


def water():
    o = Model("decor_water")
    s, m = o.s, o.m
    s.box(m["white"], (0.34, 0.90, 0.34), (0, 0.47, -0.02))
    s.box(m["grey"], (0.35, 0.04, 0.36), (0, 0.02, -0.02))
    s.box(m["grey"], (0.28, 0.28, 0.010), (0, 0.72, 0.152))
    s.box(m["black"], (0.24, 0.22, 0.008), (0, 0.72, 0.156))
    s.cyl(m["led_b"], 0.016, 0.05, (-0.055, 0.80, 0.175))
    s.cyl(m["red"], 0.016, 0.05, (0.055, 0.80, 0.175))
    s.box(m["grey"], (0.20, 0.015, 0.10), (0, 0.615, 0.195))
    s.box(m["led_b"], (0.10, 0.030, 0.004), (0, 0.885, 0.1515))
    s.box(m["white"], (0.26, 0.40, 0.008), (0, 0.32, 0.152))
    s.cyl(m["grey"], 0.130, 0.030, (0, 0.932, -0.02), segs=32)
    s.cyl(m["grey"], 0.060, 0.05, (0, 0.965, -0.02), segs=24)
    # Wasserflasche
    s.cyl(m["water"], 0.060, 0.05, (0, 0.995, -0.02), segs=32, r_top=0.128)
    s.cyl(m["water"], 0.130, 0.26, (0, 1.150, -0.02), segs=32)
    s.cyl(m["water"], 0.128, 0.03, (0, 1.295, -0.02), segs=32, r_top=0.10)
    for y in (1.06, 1.14, 1.22):
        bd.ring(s, m["water"], frame_of((0, y, -0.02), (90, 0, 0)), (0, 0, 0), 0.131, "Z", tube=0.010, segs=32)
    # Becherspender
    s.cyl(m["glass"], 0.042, 0.30, (0.195, 0.66, -0.04), segs=20)
    for k in range(7):
        s.cyl(m["paper"], 0.030, 0.07, (0.195, 0.56 + 0.028 * k, -0.04), r_top=0.037, segs=18)
    s.box(m["grey"], (0.03, 0.04, 0.05), (0.172, 0.80, -0.04))
    o.save()


def tool_cart():
    o = Model("decor_tool_cart")
    s, m = o.s, o.m
    W, D = 0.74, 0.46
    for sx in (-0.30, 0.30):
        for sz in (-0.17, 0.17):
            s.cyl(m["rubber"], 0.060, 0.034, (sx, 0.060, sz), axis="X", segs=24)
            s.cyl(m["galv"], 0.026, 0.038, (sx, 0.060, sz), axis="X", segs=16)
            s.box(m["galv"], (0.050, 0.030, 0.07), (sx, 0.130, sz))
            for dx in (-0.022, 0.022):
                s.box(m["galv"], (0.004, 0.075, 0.044), (sx + dx, 0.095, sz))
    s.box(m["red"], (W, 0.72, D), (0, 0.505, -0.005))
    s.box(m["black"], (W + 0.02, 0.030, D + 0.02), (0, 0.162, 0))
    for sx in (-1, 1):
        for sz in (-1, 1):
            s.box(m["black"], (0.030, 0.70, 0.030), (sx * (W / 2), 0.51, sz * (D / 2 - 0.005)))
    ys = [0.215, 0.320, 0.425, 0.530, 0.645, 0.765]
    hs = [0.095, 0.095, 0.095, 0.095, 0.115, 0.105]
    for k, (y, h) in enumerate(zip(ys, hs)):
        s.box(m["red"], (W - 0.06, h - 0.008, 0.018), (0, y + 0.012, D / 2 + 0.004))
        s.box(m["chrome"], (W - 0.10, 0.018, 0.022), (0, y + h * 0.5 - 0.002, D / 2 + 0.012))
        s.box(m["paper"], (0.11, 0.028, 0.002), (-0.22, y + 0.004, D / 2 + 0.014))
    s.box(m["black"], (W + 0.04, 0.040, D + 0.03), (0, 0.885, 0))
    s.box(m["rubber"], (W - 0.02, 0.010, D - 0.04), (0, 0.909, 0))
    for sx in (-1, 1):
        s.box(m["black"], (0.016, 0.05, D + 0.02), (sx * (W / 2 + 0.010), 0.925, 0))
    s.box(m["black"], (W + 0.03, 0.05, 0.016), (0, 0.925, -D / 2 - 0.005))
    # Griff
    s.cyl(m["chrome"], 0.013, D - 0.06, (W / 2 + 0.065, 0.83, 0), axis="Z")
    for sz in (-0.18, 0.18):
        s.cyl(m["chrome"], 0.010, 0.07, (W / 2 + 0.033, 0.83, sz), axis="X")
    # Anzeige und Werkzeug obenauf
    s.box(m["black"], (0.15, 0.07, 0.010), (0.255, 0.925, D / 2 + 0.012), rot=(0, 0, 0))
    s.cyl(m["yellow"], 0.030, 0.16, (-0.20, 0.944, 0.02), axis="X", segs=20)
    s.box(m["yellow"], (0.055, 0.11, 0.045), (-0.13, 0.945, 0.075), rot=(80, 0, 0))
    s.cyl(m["chrome"], 0.008, 0.07, (-0.31, 0.944, 0.02), axis="X")
    s.box(m["chrome"], (0.22, 0.008, 0.022), (0.10, 0.918, 0.06), rot=(0, 24, 0))
    s.box(m["chrome"], (0.19, 0.008, 0.020), (0.12, 0.918, -0.02), rot=(0, 12, 0))
    s.cyl(m["blue"], 0.013, 0.09, (0.02, 0.927, -0.12), axis="X")
    s.cyl(m["chrome"], 0.004, 0.11, (0.12, 0.927, -0.12), axis="X")
    for k in range(5):
        s.cyl(m["chrome"], 0.014 + 0.0015 * k, 0.030, (-0.28 + 0.045 * k, 0.930, -0.15), segs=12)
    o.save()


def dehumidifier():
    o = Model("decor_dehumidifier")
    s, m = o.s, o.m
    W, H, D = 0.58, 0.98, 0.50
    for sx in (-0.22, 0.22):
        for sz in (-0.17, 0.17):
            s.cyl(m["rubber"], 0.034, 0.026, (sx, 0.034, sz), axis="X", segs=20)
            s.box(m["galv"], (0.034, 0.030, 0.034), (sx, 0.066, sz))
    s.box(m["white"], (W, 0.60, D), (0, 0.66, 0))
    s.box(m["grey"], (W, 0.30, 0.03), (0, 0.23, -D / 2 + 0.015))
    for sx in (-1, 1):
        s.box(m["grey"], (0.03, 0.30, D), (sx * (W / 2 - 0.015), 0.23, 0))
    s.box(m["grey"], (W, 0.02, D), (0, 0.085, 0))
    s.box(m["dark"], (W + 0.01, 0.030, D + 0.01), (0, 0.970, 0))
    # Luftgitter vorn mit Luefter dahinter
    s.box(m["black"], (0.44, 0.40, 0.012), (0, 0.64, D / 2 - 0.004))
    for k in range(17):
        s.box(m["grey"], (0.42, 0.006, 0.010), (0, 0.46 + 0.0225 * k, D / 2 + 0.008), rot=(18, 0, 0))
    bd.ring(s, m["grey"], frame_of((0, 0.64, D / 2 + 0.004)), (0, 0, 0), 0.185, "Z", tube=0.012, segs=40)
    # Bedienfeld
    s.box(m["black"], (0.40, 0.075, 0.010), (0, 0.905, D / 2 + 0.002))
    s.box(m["led_g"], (0.085, 0.034, 0.003), (-0.11, 0.905, D / 2 + 0.009))
    for k, c in enumerate(("led_b", "led_g", "led_a")):
        s.cyl(m[c], 0.009, 0.006, (0.03 + 0.05 * k, 0.905, D / 2 + 0.008), axis="Z", segs=14)
    # Tank: durchsichtig, Fuellstand als eigener Knoten (Ursprung am Tankboden)
    s.box(m["glass"], (0.50, 0.24, 0.42), (0, 0.225, 0.025))
    s.box(m["grey"], (0.20, 0.022, 0.03), (0, 0.335, D / 2 + 0.012))
    t = o.part("Tank_Level", (0, 0.108, 0.025))
    t.box(m["water"], (0.48, 0.22, 0.40), (0, 0.11, 0))
    bd.add_fan(o.coll, o.root, "Fan_0", (0, 0.64, D / 2 - 0.030), 0.17, "Z", {"fan_blade": m["dark"]})
    # Schlauch und Griffe
    for sx in (-1, 1):
        s.box(m["dark"], (0.012, 0.030, 0.18), (sx * (W / 2 + 0.006), 0.86, 0))
    for k in range(6):
        s.box(m["grey"], (0.004, 0.008, 0.30), (W / 2 + 0.002, 0.50 + 0.030 * k, 0))
    o.save()


def logo_sign():
    o = Model("decor_logo_sign")
    s, m = o.s, o.m
    W, H = 1.80, 0.46
    s.box(m["dark"], (W, H, 0.050), (0, 0, -0.030))
    s.box(m["black"], (W - 0.06, H - 0.06, 0.012), (0, 0, 0.000))
    s.box(m["glass_d"], (W - 0.08, H - 0.08, 0.004), (0, 0, 0.012))
    # Umlaufender Leuchtrahmen
    for sy in (-1, 1):
        s.box(m["sign"], (W - 0.04, 0.014, 0.018), (0, sy * (H / 2 - 0.018), 0.012))
    for sx in (-1, 1):
        s.box(m["sign"], (0.014, H - 0.04, 0.018), (sx * (W / 2 - 0.018), 0, 0.012))
    for sx in (-0.78, 0.78):
        s.box(m["galv"], (0.05, 0.10, 0.012), (sx, 0, -0.056))
        bolt(s, m["galv"], (sx, 0.17, 0.004), r=0.010)
        bolt(s, m["galv"], (sx, -0.17, 0.004), r=0.010)
    o.save()


ALL = {
    "shelf_small": shelf_small, "shelf_heavy": shelf_heavy, "shelf_pallet": shelf_pallet, "euro_pallet": euro_pallet,
    "esd": esd_workbench, "cabinet": parts_cabinet, "gate": cold_aisle_gate, "vending": vending, "cctv": cctv,
    "sofa": sofa, "water": water, "tool_cart": tool_cart, "dehum": dehumidifier, "sign": logo_sign,
}


def main():
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for n in names or list(ALL):
        ALL[n]()


if __name__ == "__main__":
    main()
