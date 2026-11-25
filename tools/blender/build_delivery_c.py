"""Blender 5.2: Lieferfahrzeuge fuer Paket C (Roadmap 21). Alle werden von hinten entladen.

  deliver_van.glb      E-Transporter      (Door_RL, Door_RR, Cab_Door_L, Wheel_*)
  deliver_truck.glb    7,5 t mit Ladebordwand (Rear_Door, Tail_Lift, ...)
  deliver_heavy.glb    18 t, Mitnahmestapler haengt hinten (Rear_Door, ...)
  forklift.glb         Mitnahmestapler    (Forks, Wheel_*)
  pallet_jack.glb      Hubwagen           (Handle)
  sack_truck.glb       Sackkarre          (Wheel_L, Wheel_R)

Ursprung der Fahrzeuge: Boden unter der Hinterachse. Vorn ist +Z, links (Fahrerseite) ist +X.
Leuchtende Materialien: Van_BeaconMat, Van_HazardMat, Van_BrakeMat, Van_HeadMat, Van_CargoMat.
Aufruf: blender --background --factory-startup --python tools/blender/build_delivery_c.py -- [name ...]
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import build_desk as bd
from build_desk import g
from build_paket_c import Model, mat, brace_x

IDENT = bd.IDENT


def extra_mats(m):
    m.update({
        "paint": mat("Van_Paint", (0.93, 0.94, 0.95), 0.24, 0.10),
        "teal": mat("Van_Teal", (0.03, 0.42, 0.50), 0.28, 0.15),
        "navy": mat("Van_Navy", (0.06, 0.13, 0.24), 0.30, 0.20),
        "trim": mat("Van_Trim", (0.10, 0.105, 0.115), 0.70, 0.05),
        "tire": mat("Van_Tire", (0.055, 0.057, 0.062), 0.88),
        "rim": mat("Van_Rim", (0.68, 0.70, 0.73), 0.28, 0.85),
        "wind": mat("Van_Glass", (0.07, 0.09, 0.11), 0.05, 0.3),
        "ply": mat("Van_Ply", (0.70, 0.58, 0.42), 0.80),
        "floor": mat("Van_Floor", (0.24, 0.22, 0.20), 0.85),
        "seat": mat("Van_Seat", (0.14, 0.15, 0.17), 0.85),
        "plate": mat("Van_Plate", (0.95, 0.95, 0.93), 0.4),
        "beacon": mat("Van_BeaconMat", (0.98, 0.62, 0.10), 0.25, emit=(1.0, 0.55, 0.08), strength=0.1),
        "hazard": mat("Van_HazardMat", (0.96, 0.54, 0.08), 0.25, emit=(1.0, 0.50, 0.06), strength=0.1),
        "brake": mat("Van_BrakeMat", (0.82, 0.10, 0.08), 0.25, emit=(1.0, 0.08, 0.06), strength=0.4),
        "head": mat("Van_HeadMat", (0.95, 0.96, 0.98), 0.15, emit=(1.0, 0.96, 0.88), strength=0.8),
        "cargo": mat("Van_CargoMat", (0.95, 0.95, 0.92), 0.3, emit=(1.0, 0.97, 0.90), strength=0.6),
        "forange": mat("Fork_Orange", (0.90, 0.34, 0.06), 0.36, 0.15),
    })
    return m


def put(s, mt, verts, faces, smooth=False, tag=""):
    bm = s._bm(mt, smooth, tag)
    vs = [bm.verts.new(Vector(g(*v))) for v in verts]
    for f in faces:
        try:
            bm.faces.new([vs[i] for i in f])
        except ValueError:
            pass


def extrude_z(s, mt, poly, z0, z1, smooth=False):
    """Vieleck in XY (gegen den Uhrzeigersinn, von vorn gesehen) entlang Z ausziehen."""
    n = len(poly)
    verts = [(x, y, z1) for x, y in poly] + [(x, y, z0) for x, y in poly]
    faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, n + i, n + j, j])
    put(s, mt, verts, faces, smooth)


def extrude_x(s, mt, poly, x0, x1):
    """Vieleck in ZY entlang X ausziehen."""
    n = len(poly)
    verts = [(x1, y, z) for z, y in poly] + [(x0, y, z) for z, y in poly]
    faces = [list(range(n)), list(range(2 * n - 1, n - 1, -1))]
    for i in range(n):
        j = (i + 1) % n
        faces.append([i, n + i, n + j, j])
    put(s, mt, verts, faces)


def rtrap(wb, wt, yb, yt, rb, rt, k=6):
    """Gerundetes Trapez als Ring, rechts unten beginnend."""
    out = []
    for cx, cy, r, a0 in ((wb - rb, yb + rb, rb, -90), (wt - rt, yt - rt, rt, 0), (-wt + rt, yt - rt, rt, 90), (-wb + rb, yb + rb, rb, 180)):
        for i in range(k + 1):
            a = math.radians(a0 + 90.0 * i / k)
            out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def van_half(y):
    """Halbe Breite des Transporters in Hoehe y."""
    pts = [(0.0, 1.0), (1.30, 1.0), (2.10, 0.93), (2.48, 0.86), (2.63, 0.80)]
    for (ya, xa), (yb, xb) in zip(pts, pts[1:]):
        if y <= yb:
            return xa + (xb - xa) * (y - ya) / (yb - ya)
    return 0.80


def van_ring(yb, yt, w=1.0, rb=0.10, rt=0.16):
    """Ring mit der Seitenlinie des Laderaums, oben und unten gerundet."""
    side = []
    xb = van_half(yb) * w
    for i in range(5):
        a = math.radians(-90 + 90.0 * i / 4)
        side.append((xb - rb + rb * math.cos(a), yb + rb + rb * math.sin(a)))
    y1 = yt - rt
    for i in range(1, 9):
        y = yb + rb + (y1 - yb - rb) * i / 8.0
        side.append((van_half(y) * w, y))
    xt = van_half(y1) * w
    for i in range(1, 6):
        a = math.radians(90.0 * i / 5)
        side.append((xt - rt + rt * math.cos(a), y1 + rt * math.sin(a)))
    return side + [(-x, y) for x, y in reversed(side)]


def loft_z(s, mt, stations, cap0=True, cap1=True, tag="loft"):
    """stations: [(z, ring)], Ringe mit gleicher Punktzahl."""
    n = len(stations[0][1])
    verts = []
    for z, ring in stations:
        verts += [(x, y, z) for x, y in ring]
    faces = []
    for k in range(len(stations) - 1):
        for i in range(n):
            j = (i + 1) % n
            faces.append([k * n + i, k * n + j, (k + 1) * n + j, (k + 1) * n + i])
    if cap0:
        faces.append(list(range(n - 1, -1, -1)))
    if cap1:
        o = (len(stations) - 1) * n
        faces.append([o + i for i in range(n)])
    put(s, mt, verts, faces, True, tag)


def wheel(o, name, x, y, z, r, w, dual=False):
    p = o.part(name, (x, y, z))
    m = o.m
    side = 1 if x > 0 else -1
    for k in ([0.0] if not dual else [0.0, -side * (w + 0.03)]):
        p.cyl(m["tire"], r, w, (k, 0, 0), axis="X", segs=36)
        p.cyl(m["tire"], r * 0.97, w + 0.02, (k, 0, 0), axis="X", segs=36)
    ox = side * (w * 0.5 + 0.008)
    p.cyl(m["rim"], r * 0.64, 0.014, (ox, 0, 0), axis="X", segs=32)
    p.cyl(m["black"], r * 0.50, 0.018, (ox, 0, 0), axis="X", segs=28)
    for i in range(6):
        a = i * 60.0
        p.box(m["rim"], (0.020, r * 0.50, r * 0.17), (ox + side * 0.004, r * 0.30 * math.cos(math.radians(a)), r * 0.30 * math.sin(math.radians(a))), rot=(a, 0, 0))
    p.cyl(m["rim"], r * 0.18, 0.030, (ox, 0, 0), axis="X", segs=20)


def arch(s, m, x, y, z, r):
    side = 1 if x > 0 else -1
    s.cyl(m["trim"], r + 0.075, 0.05, (x + side * 0.004, y, z), axis="X", segs=36)
    s.cyl(m["black"], r + 0.035, 0.054, (x + side * 0.004, y, z), axis="X", segs=36)


def plate(s, m, pos, rot=(0, 0, 0)):
    s.box(m["plate"], (0.52, 0.11, 0.008), pos, rot=rot)
    s.box(m["blue"], (0.045, 0.10, 0.010), (pos[0] - 0.235 if rot[1] == 0 else pos[0] + 0.235, pos[1], pos[2]), rot=rot)


def mirror(s, m, x, y, z, h=0.24):
    side = 1 if x > 0 else -1
    s.box(m["trim"], (0.16, 0.03, 0.03), (x + side * 0.07, y, z))
    s.box(m["trim"], (0.06, h, 0.15), (x + side * 0.16, y, z), rot=(0, side * 8, 0))
    s.box(m["chrome"], (0.04, h * 0.82, 0.004), (x + side * 0.16, y, z - 0.078), rot=(0, side * 8, 0))


def wipers(s, m, y, z, tilt, w):
    for dx in (-w, 0.12):
        s.box(m["black"], (0.55, 0.012, 0.012), (dx + 0.22, y + 0.04, z - 0.03), rot=(0, 0, 8))


def cab_interior(s, m, x0, floor_y, z_seat, seats):
    for x in seats:
        s.box(m["seat"], (0.48, 0.14, 0.46), (x, floor_y + 0.38, z_seat))
        s.box(m["seat"], (0.46, 0.62, 0.13), (x, floor_y + 0.72, z_seat - 0.24), rot=(-10, 0, 0))


# ---------------------------------------------------------------- E-Transporter

def van():
    o = Model("deliver_van")
    s, m = o.s, extra_mats(o.m)
    # Fahrerhaus
    st = [
        (1.95, van_ring(0.40, 2.63, 1.0, 0.06, 0.16)),
        (2.70, van_ring(0.40, 2.63, 1.0, 0.06, 0.16)),
        (3.10, van_ring(0.40, 2.59, 1.0, 0.08, 0.18)),
        (3.45, van_ring(0.38, 2.38, 1.0, 0.10, 0.20)),
        (4.22, van_ring(0.34, 1.40, 1.0, 0.12, 0.10)),
        (4.62, van_ring(0.30, 1.22, 0.985, 0.14, 0.14)),
        (4.82, van_ring(0.30, 1.05, 0.95, 0.16, 0.18)),
        (4.88, van_ring(0.36, 0.96, 0.89, 0.16, 0.18)),
    ]
    loft_z(s, m["paint"], st)
    # Laderaum: Boden, Waende, Dach als Schale
    z0, z1 = -1.05, 1.97
    wall = [(1.00, 0.40), (1.00, 1.30), (0.93, 2.10), (0.86, 2.48), (0.80, 2.46), (0.87, 2.08), (0.94, 1.30), (0.94, 0.40)]
    extrude_z(s, m["paint"], wall, z0, z1)
    extrude_z(s, m["paint"], [(-x, y) for x, y in reversed(wall)], z0, z1)
    roof = [(0.86, 2.48), (0.74, 2.59), (0.40, 2.63), (-0.40, 2.63), (-0.74, 2.59), (-0.86, 2.48), (-0.80, 2.46), (-0.70, 2.54), (0.70, 2.54), (0.80, 2.46)]
    extrude_z(s, m["paint"], roof, z0, z1)
    s.box(m["floor"], (1.90, 0.06, 3.02), (0, 0.59, 0.46))
    s.box(m["trim"], (2.00, 0.22, 0.10), (0, 0.50, -1.02))
    s.box(m["galv"], (1.60, 0.012, 0.20), (0, 0.622, -0.95))
    for sx in (-1, 1):
        s.box(m["ply"], (0.016, 1.20, 2.94), (sx * 0.93, 1.23, 0.46))
        for y in (1.00, 1.55):
            s.box(m["galv"], (0.020, 0.04, 2.90), (sx * 0.918, y, 0.46))
        # Seitenschutz und Streifen
        s.box(m["trim"], (0.03, 0.14, 2.10), (sx * 1.002, 0.52, 1.82))
        s.box(m["teal"], (0.010, 0.20, 2.94), (sx * 1.004, 0.96, 0.46))
        s.box(m["navy"], (0.010, 0.05, 2.94), (sx * 1.004, 0.82, 0.46))
        s.box(m["teal"], (0.012, 0.20, 2.10), (sx * 1.004, 0.96, 2.98))
        s.box(m["navy"], (0.012, 0.05, 2.10), (sx * 1.004, 0.82, 2.98))
    s.box(m["grey"], (1.86, 1.90, 0.03), (0, 1.56, 1.95))
    s.box(m["cargo"], (0.10, 0.02, 1.60), (0, 2.53, 0.40))
    # Scheiben: Front, seitlich
    put(s, m["wind"], [(0.80, 2.33, 3.50), (-0.80, 2.33, 3.50), (-0.91, 1.42, 4.22), (0.91, 1.42, 4.22)], [[0, 1, 2, 3]])
    for k in range(4):
        pass
    for sx in (-1, 1):
        pts = [(sx * (van_half(2.14) + 0.016), 2.14, 3.38), (sx * (van_half(1.44) + 0.016), 1.44, 4.02), (sx * (van_half(1.42) + 0.016), 1.42, 2.74), (sx * (van_half(2.20) + 0.016), 2.20, 2.74)]
        put(s, m["wind"], pts, [[0, 1, 2, 3] if sx > 0 else [3, 2, 1, 0]])
        arch(s, m, sx * 0.985, 0.35, 0.0, 0.35)
        arch(s, m, sx * 0.985, 0.35, 3.66, 0.35)
        mirror(s, m, sx * 1.00, 1.52, 3.78)
        s.box(m["trim"], (0.02, 0.03, 0.20), (sx * 1.012, 1.16, 2.86))
        # Scheinwerfer und Blinker
        s.box(m["trim"], (0.34, 0.20, 0.10), (sx * 0.70, 0.84, 4.870), rot=(0, sx * 20, 0))
        s.box(m["head"], (0.28, 0.14, 0.10), (sx * 0.70, 0.84, 4.885), rot=(0, sx * 20, 0))
        s.box(m["hazard"], (0.10, 0.09, 0.08), (sx * 0.915, 0.84, 4.74), rot=(0, sx * 50, 0))
        # Heckleuchten
        s.box(m["brake"], (0.09, 0.34, 0.05), (sx * 0.93, 1.30, -1.06))
        s.box(m["hazard"], (0.09, 0.14, 0.05), (sx * 0.93, 1.06, -1.06))
    s.box(m["black"], (1.10, 0.20, 0.06), (0, 0.80, 4.87))
    for k in range(4):
        s.box(m["trim"], (1.06, 0.014, 0.03), (0, 0.73 + 0.048 * k, 4.905))
    s.box(m["teal"], (0.20, 0.10, 0.02), (0, 0.98, 4.89))
    s.box(m["trim"], (1.86, 0.26, 0.22), (0, 0.42, 4.80))
    plate(s, m, (0, 0.48, 4.915))
    wipers(s, m, 1.40, 4.22, 0, 0.62)
    s.box(m["trim"], (1.96, 0.16, 0.12), (0, 0.46, -1.10))
    plate(s, m, (0, 0.46, -1.164), rot=(0, 180, 0))
    s.box(m["beacon"], (0.90, 0.09, 0.16), (0, 2.68, 2.30))
    s.box(m["trim"], (0.30, 0.03, 0.18), (0, 2.64, 2.30))
    # Ladebuchse
    s.cyl(m["trim"], 0.10, 0.012, (1.004, 1.02, 2.28), axis="X")
    # Fahrertuer (links, +X) als eigener Fluegel
    d = o.part("Cab_Door_L", (1.004, 0.50, 3.92))
    d.box(m["paint"], (0.024, 0.86, 1.18), (0.006, 0.42, -0.62))
    d.box(m["teal"], (0.028, 0.20, 1.18), (0.007, 0.46, -0.62))
    d.box(m["trim"], (0.03, 0.03, 0.18), (0.018, 0.66, -1.04))
    # Hecktueren: Angeln aussen
    for name, sx in (("Door_RL", 1), ("Door_RR", -1)):
        d = o.part(name, (sx * 0.945, 0.60, -1.06))
        d.box(m["paint"], (0.925, 1.90, 0.045), (-sx * 0.465, 0.93, 0.0))
        d.box(m["wind"], (0.50, 0.46, 0.012), (-sx * 0.465, 1.52, -0.022))
        d.box(m["ply"], (0.80, 0.90, 0.012), (-sx * 0.465, 0.60, 0.026))
        d.box(m["teal"], (0.92, 0.20, 0.012), (-sx * 0.465, 0.36, -0.022))
        d.box(m["trim"], (0.05, 0.18, 0.03), (-sx * 0.87, 0.78, -0.03))
        for y in (0.20, 0.95, 1.70):
            d.cyl(m["trim"], 0.018, 0.10, (0, y, -0.02))
    for nm, x, z in (("Wheel_FL", 0.89, 3.66), ("Wheel_FR", -0.89, 3.66), ("Wheel_RL", 0.89, 0.0), ("Wheel_RR", -0.89, 0.0)):
        wheel(o, nm, x, 0.35, z, 0.35, 0.23)
    o.save()


# ---------------------------------------------------------------- Lkw-Bauteile

def box_body(o, z0, z1, half, yf, yt, stripe=True):
    """Kofferaufbau als Schale, hinten offen."""
    s, m = o.s, o.m
    ln = z1 - z0
    zc = (z0 + z1) * 0.5
    s.box(m["floor"], (half * 2 - 0.04, 0.08, ln), (0, yf - 0.04, zc))
    s.box(m["galv"], (half * 2, 0.10, ln + 0.02), (0, yf - 0.10, zc))
    for sx in (-1, 1):
        s.box(m["paint"], (0.05, yt - yf, ln), (sx * (half - 0.025), (yf + yt) * 0.5, zc))
        s.box(m["ply"], (0.012, 1.30, ln - 0.08), (sx * (half - 0.056), yf + 0.65, zc))
        for k in range(2):
            s.box(m["galv"], (0.03, 0.04, ln - 0.1), (sx * (half - 0.066), yf + 0.55 + 0.55 * k, zc))
        if stripe:
            s.box(m["teal"], (0.010, 0.34, ln - 0.02), (sx * (half + 0.002), yf + 0.42, zc))
            s.box(m["navy"], (0.010, 0.08, ln - 0.02), (sx * (half + 0.002), yf + 0.20, zc))
        # Alu-Rahmen
        for z in (z0 + 0.03, z1 - 0.03):
            s.box(m["galv"], (0.07, yt - yf + 0.02, 0.07), (sx * (half - 0.02), (yf + yt) * 0.5, z))
        s.box(m["galv"], (0.06, 0.07, ln), (sx * (half - 0.02), yt - 0.02, zc))
    s.box(m["paint"], (half * 2, 0.05, ln), (0, yt, zc))
    s.box(m["paint"], (half * 2 - 0.08, yt - yf, 0.05), (0, (yf + yt) * 0.5, z1 - 0.025))
    s.box(m["galv"], (half * 2, 0.09, 0.08), (0, yt - 0.03, z0 + 0.04))
    s.box(m["cargo"], (0.12, 0.02, ln * 0.6), (0, yt - 0.035, zc))
    for sx in (-1, 1):
        s.box(m["beacon"], (0.12, 0.05, 0.05), (sx * (half - 0.16), yt + 0.05, z0 + 0.06))


def rear_frame(s, m, z0, half, yf):
    """Unterfahrschutz, Leuchten, Kennzeichen."""
    s.box(m["trim"], (half * 2 - 0.1, 0.12, 0.10), (0, 0.50, z0 + 0.10))
    for sx in (-1, 1):
        s.box(m["brake"], (0.34, 0.12, 0.05), (sx * (half - 0.28), yf - 0.26, z0 + 0.02))
        s.box(m["hazard"], (0.14, 0.12, 0.05), (sx * (half - 0.53), yf - 0.26, z0 + 0.02))
        s.box(m["trim"], (0.10, 0.60, 0.08), (sx * 0.60, 0.66, z0 + 0.12))
        for k in range(3):
            s.box(m["red"] if k % 2 == 0 else m["white"], (0.20, 0.08, 0.006), (sx * (half - 0.14), 0.50, z0 + 0.047 - 0.0 * k))
    plate(s, m, (0, yf - 0.26, z0 + 0.02), rot=(0, 180, 0))


def roller_door(o, z0, half, yf, yt):
    d = o.part("Rear_Door", (0, yt - 0.06, z0 + 0.02))
    m = o.m
    h = yt - yf - 0.08
    n = 10
    for k in range(n):
        y = -h * (k + 0.5) / n
        d.box(m["paint"], (half * 2 - 0.16, h / n - 0.012, 0.030), (0, y, 0))
    d.box(m["trim"], (half * 2 - 0.16, 0.05, 0.05), (0, -h + 0.02, -0.005))
    d.box(m["teal"], (half * 2 - 0.16, 0.30, 0.006), (0, -h + 0.50, -0.018))


def chassis(s, m, z0, z1, y=0.62):
    for sx in (-0.40, 0.40):
        s.box(m["trim"], (0.10, 0.22, z1 - z0), (sx, y, (z0 + z1) * 0.5))
    for k in range(5):
        s.box(m["trim"], (0.80, 0.12, 0.08), (0, y, z0 + 0.3 + (z1 - z0 - 0.6) * k / 4.0))


def truck_cab(o, z0, z1, half, y0, yt, floor_y, sleeper=False):
    """Fahrerhaus mit steiler Scheibe."""
    s, m = o.s, o.m
    ym = floor_y + 0.55
    st = [
        (z0, rtrap(half, half - 0.06, y0, yt, 0.08, 0.16)),
        (z0 + (z1 - z0) * 0.55, rtrap(half, half - 0.06, y0, yt, 0.08, 0.16)),
        (z1 - 0.42, rtrap(half, half - 0.07, y0, yt - 0.06, 0.08, 0.20)),
        (z1 - 0.14, rtrap(half - 0.01, half - 0.05, y0, ym + 0.02, 0.10, 0.10)),
        (z1 - 0.04, rtrap(half - 0.04, half - 0.06, y0 + 0.02, ym - 0.10, 0.12, 0.14)),
        (z1, rtrap(half - 0.10, half - 0.12, y0 + 0.08, ym - 0.22, 0.14, 0.14)),
    ]
    loft_z(s, m["paint"], st)
    w2 = half - 0.13
    put(s, m["wind"], [(w2 - 0.06, yt - 0.20, z1 - 0.385), (-w2 + 0.06, yt - 0.20, z1 - 0.385), (-w2, ym + 0.06, z1 - 0.135), (w2, ym + 0.06, z1 - 0.135)], [[0, 1, 2, 3]])
    for sx in (-1, 1):
        zf = z1 - 0.50
        zb = zf - 0.86
        xa = lambda y: half - 0.06 * (y - y0) / (yt - y0) + 0.008
        pts = [(sx * xa(yt - 0.26), yt - 0.26, zf + 0.04), (sx * xa(ym + 0.06), ym + 0.06, zf + 0.22), (sx * xa(ym + 0.04), ym + 0.04, zb), (sx * xa(yt - 0.24), yt - 0.24, zb)]
        put(s, m["wind"], pts, [[0, 1, 2, 3] if sx > 0 else [3, 2, 1, 0]])
        mirror(s, m, sx * half, ym + 0.36, z1 - 0.30, 0.44)
        mirror(s, m, sx * half, ym + 0.02, z1 - 0.28, 0.18)
        s.box(m["trim"], (0.46, 0.22, 0.10), (sx * (half - 0.32), y0 + 0.44, z1 - 0.01))
        s.box(m["head"], (0.30, 0.15, 0.10), (sx * (half - 0.38), y0 + 0.44, z1 + 0.005))
        s.box(m["hazard"], (0.10, 0.15, 0.10), (sx * (half - 0.15), y0 + 0.44, z1 + 0.005))
        # Trittstufen
        for k in range(2):
            s.box(m["trim"], (0.10, 0.04, 0.46), (sx * (half - 0.02), y0 + 0.10 + 0.26 * k, z0 + 0.62))
        s.box(m["teal"], (0.012, 0.22, z1 - z0 - 0.35), (sx * (half + 0.001), floor_y + 0.28, (z0 + z1) * 0.5 - 0.16))
    s.box(m["trim"], (half * 2 - 0.06, 0.34, 0.18), (0, y0 + 0.14, z1 - 0.02))
    s.box(m["black"], (half * 1.0, 0.34, 0.06), (0, y0 + 0.52, z1 - 0.01))
    for k in range(5):
        s.box(m["trim"], (half * 0.96, 0.018, 0.03), (0, y0 + 0.40 + 0.062 * k, z1 + 0.02))
    s.box(m["teal"], (0.34, 0.10, 0.03), (0, y0 + 0.80, z1 - 0.005))
    plate(s, m, (0, y0 + 0.14, z1 + 0.075))
    wipers(s, m, ym + 0.04, z1 - 0.12, 0, 0.70)
    s.box(m["trim"], (half * 1.5, 0.05, 0.10), (0, yt + 0.02, z1 - 0.62))
    s.box(m["beacon"], (half * 1.2, 0.10, 0.16), (0, yt + 0.07, z1 - 0.62))
    # Fahrertuer
    d = o.part("Cab_Door_L", (half + 0.004, floor_y - 0.30, z1 - 0.44))
    d.box(m["paint"], (0.024, 0.84, 0.94), (0.006, 0.40, -0.49))
    d.box(m["teal"], (0.028, 0.22, 0.94), (0.007, 0.58, -0.49))
    d.box(m["trim"], (0.03, 0.03, 0.18), (0.018, 0.76, -0.82))


def truck():
    o = Model("deliver_truck")
    s, m = o.s, extra_mats(o.m)
    z0, z1 = -1.25, 3.05
    half, yf, yt = 1.20, 0.95, 3.15
    chassis(s, m, z0 + 0.15, 4.6)
    box_body(o, z0, z1, half, yf, yt)
    rear_frame(s, m, z0, half, yf)
    roller_door(o, z0, half, yf, yt)
    truck_cab(o, 3.22, 5.10, 1.08, 0.42, 2.50, 0.95)
    # Windabweiser ueber dem Fahrerhaus
    extrude_x(s, m["paint"], [(3.25, 2.50), (4.35, 2.50), (3.40, 3.05), (3.25, 3.05)], -0.95, 0.95)
    for sx in (-1, 1):
        s.box(m["trim"], (0.04, 0.34, 1.50), (sx * 1.10, 0.62, 1.70))
        s.box(m["galv"], (0.30, 0.40, 0.80), (sx * 0.86, 0.60, 2.62))
        arch(s, m, sx * 1.055, 0.42, 4.15, 0.42)
        s.box(m["trim"], (0.30, 0.04, 1.02), (sx * 1.02, 0.88, 0.0))
    # Ladebordwand: Plattform am Scharnier (Oberkante = Ladeboden)
    t = o.part("Tail_Lift", (0, yf, z0))
    t.box(m["galv"], (2.20, 0.05, 1.30), (0, -0.025, -0.67))
    for k in range(9):
        t.box(m["steel"], (2.10, 0.006, 0.03), (0, 0.002, -0.12 - 0.135 * k))
    t.box(m["yellow"], (2.20, 0.052, 0.08), (0, -0.025, -1.30))
    for sx in (-1, 1):
        t.box(m["beacon"], (0.10, 0.02, 0.06), (sx * 0.98, 0.008, -1.22))
    for nm, x, z, r, w, du in (("Wheel_FL", 0.98, 4.15, 0.42, 0.26, False), ("Wheel_FR", -0.98, 4.15, 0.42, 0.26, False), ("Wheel_RL", 1.02, 0.0, 0.42, 0.22, True), ("Wheel_RR", -1.02, 0.0, 0.42, 0.22, True)):
        wheel(o, nm, x, r, z, r, w, du)
    o.save()


def heavy():
    o = Model("deliver_heavy")
    s, m = o.s, extra_mats(o.m)
    z0, z1 = -1.55, 3.75
    half, yf, yt = 1.25, 1.12, 3.55
    chassis(s, m, z0 + 0.15, 5.4, 0.74)
    box_body(o, z0, z1, half, yf, yt)
    rear_frame(s, m, z0, half, yf)
    roller_door(o, z0, half, yf, yt)
    truck_cab(o, 3.95, 6.0, 1.22, 0.46, 3.10, 1.22, True)
    extrude_x(s, m["paint"], [(3.98, 3.10), (5.0, 3.10), (4.15, 3.50), (3.98, 3.50)], -1.10, 1.10)
    for sx in (-1, 1):
        s.box(m["trim"], (0.04, 0.40, 1.30), (sx * 1.16, 0.72, 2.35))
        s.cyl(m["galv"], 0.26, 0.90, (sx * 0.88, 0.70, 3.35), axis="Z", segs=28)
        arch(s, m, sx * 1.195, 0.50, 4.95, 0.50)
        s.box(m["trim"], (0.32, 0.04, 2.40), (sx * 1.06, 1.06, 0.42))
        # Aufnahme fuer den Mitnahmestapler
        s.box(m["trim"], (0.16, 0.14, 0.40), (sx * 0.34, 0.72, z0 - 0.08))
    for nm, x, z, du in (("Wheel_FL", 1.12, 4.95, False), ("Wheel_FR", -1.12, 4.95, False), ("Wheel_ML", 1.08, 1.12, True), ("Wheel_MR", -1.08, 1.12, True), ("Wheel_RL", 1.08, 0.0, True), ("Wheel_RR", -1.08, 0.0, True)):
        wheel(o, nm, x, 0.50, z, 0.50, 0.26, du)
    o.save()


def forklift():
    """Mitnahmestapler, Ursprung Boden unter der Vorderachse, Gabel zeigt nach +Z."""
    o = Model("forklift")
    s, m = o.s, extra_mats(o.m)
    # Rahmen: zwei Radarme vorn, Heck mit Motor
    for sx in (-1, 1):
        s.box(m["trim"], (0.16, 0.20, 1.30), (sx * 0.62, 0.36, -0.40))
        s.box(m["forange"], (0.05, 0.26, 1.10), (sx * 0.715, 0.40, -0.45))
        s.box(m["forange"], (0.24, 0.04, 0.56), (sx * 0.62, 0.66, 0.0))
    s.box(m["forange"], (1.30, 0.52, 0.56), (0, 0.62, -1.02))
    s.box(m["trim"], (1.20, 0.10, 0.50), (0, 0.93, -1.02))
    for k in range(6):
        s.box(m["black"], (0.70, 0.02, 0.02), (0, 0.46 + 0.07 * k, -1.305))
    s.box(m["forange"], (0.90, 0.34, 0.40), (0, 0.46, -0.60))
    # Sitz, Lenkrad, Schutzdach
    s.box(m["seat"], (0.46, 0.12, 0.44), (0.12, 0.96, -0.72))
    s.box(m["seat"], (0.46, 0.50, 0.10), (0.12, 1.20, -0.96), rot=(-8, 0, 0))
    s.cyl(m["black"], 0.16, 0.025, (0.12, 1.18, -0.28), rot=(62, 0, 0), segs=28)
    s.cyl(m["black"], 0.03, 0.40, (0.12, 1.02, -0.20), rot=(-28, 0, 0))
    for sx in (-1, 1):
        for z in (-1.10, -0.16):
            s.box(m["black"], (0.06, 1.20, 0.06), (sx * 0.58, 1.42, z))
        s.box(m["black"], (0.06, 0.06, 1.0), (sx * 0.58, 2.00, -0.63))
    for k in range(6):
        s.box(m["black"], (1.16, 0.04, 0.03), (0, 2.00, -1.08 + 0.18 * k))
    s.cyl(m["beacon"], 0.06, 0.12, (-0.40, 2.08, -1.04), segs=20)
    s.box(m["head"], (0.14, 0.10, 0.06), (0.50, 1.94, -0.10))
    s.box(m["head"], (0.14, 0.10, 0.06), (-0.50, 1.94, -0.10))
    # Hubmast
    for sx in (-1, 1):
        s.box(m["trim"], (0.08, 1.96, 0.12), (sx * 0.34, 1.10, 0.20))
        s.box(m["steel"], (0.05, 1.90, 0.07), (sx * 0.26, 1.10, 0.20))
    for y in (0.30, 1.10, 2.05):
        s.box(m["trim"], (0.76, 0.08, 0.08), (0, y, 0.20))
    s.cyl(m["chrome"], 0.030, 1.60, (0, 1.10, 0.20))
    f = o.part("Forks", (0, 0.0, 0.32))
    f.box(m["trim"], (0.86, 0.36, 0.06), (0, 0.30, 0.0))
    for k in range(5):
        f.box(m["black"], (0.03, 0.80, 0.03), (-0.36 + 0.18 * k, 0.86, 0.0))
    f.box(m["black"], (0.80, 0.03, 0.03), (0, 1.26, 0.0))
    for sx in (-0.22, 0.22):
        f.box(m["steel"], (0.11, 0.42, 0.05), (sx, 0.27, 0.04))
        f.box(m["steel"], (0.11, 0.042, 1.02), (sx, 0.055, 0.55))
    for nm, x, z, r, w in (("Wheel_FL", 0.62, 0.0, 0.31, 0.20), ("Wheel_FR", -0.62, 0.0, 0.31, 0.20), ("Wheel_B", 0.0, -1.08, 0.28, 0.22)):
        wheel(o, nm, x + (0.0001 if x == 0 else 0), r, z, r, w)
    o.save()


def pallet_jack():
    """Hubwagen, Ursprung Boden unter den Lenkrollen, Gabel zeigt nach +Z."""
    o = Model("pallet_jack")
    s, m = o.s, extra_mats(o.m)
    for sx in (-0.19, 0.19):
        s.box(m["forange"], (0.15, 0.05, 1.06), (sx, 0.085, 0.66))
        s.box(m["forange"], (0.13, 0.05, 0.10), (sx, 0.07, 1.20), rot=(14, 0, 0))
        s.cyl(m["tire"], 0.040, 0.06, (sx, 0.040, 1.05), axis="X", segs=20)
    s.box(m["forange"], (0.54, 0.30, 0.12), (0, 0.24, 0.10))
    s.box(m["forange"], (0.40, 0.20, 0.10), (0, 0.46, 0.06))
    s.cyl(m["chrome"], 0.045, 0.34, (0, 0.40, 0.0))
    for sx in (-0.07, 0.07):
        s.cyl(m["tire"], 0.095, 0.05, (sx, 0.095, -0.02), axis="X", segs=28)
        s.cyl(m["rim"], 0.05, 0.054, (sx, 0.095, -0.02), axis="X", segs=20)
    h = o.part("Handle", (0, 0.34, -0.02))
    h.cyl(m["black"], 0.022, 0.80, (0, 0.40, -0.02))
    h.box(m["black"], (0.06, 0.10, 0.06), (0, 0.06, 0))
    bd.ring(h, m["black"], bd.frame_of((0, 0.86, -0.02)), (0, 0, 0), 0.12, "Z", tube=0.030)
    h.box(m["red"], (0.10, 0.02, 0.03), (0, 0.84, -0.02))
    o.save()


def sack_truck():
    """Sackkarre, Ursprung Boden unter der Achse, Schaufel zeigt nach -Z (wie die Figuren)."""
    o = Model("sack_truck")
    s, m = o.s, extra_mats(o.m)
    for sx in (-1, 1):
        s.cyl(m["blue"], 0.018, 1.10, (sx * 0.19, 0.60, -0.05))
        s.cyl(m["blue"], 0.018, 0.22, (sx * 0.19, 1.20, 0.03), rot=(40, 0, 0))
        s.cyl(m["black"], 0.022, 0.14, (sx * 0.19, 1.28, 0.10), rot=(72, 0, 0))
        s.box(m["blue"], (0.02, 0.34, 0.12), (sx * 0.19, 0.22, 0.0))
    for y in (0.20, 0.55, 0.85, 1.12):
        s.cyl(m["blue"], 0.013, 0.38, (0, y, -0.05), axis="X")
    s.box(m["blue"], (0.05, 0.90, 0.008), (0, 0.62, -0.062))
    s.box(m["steel"], (0.46, 0.012, 0.26), (0, 0.022, -0.19))
    s.box(m["steel"], (0.46, 0.10, 0.010), (0, 0.07, -0.062))
    s.cyl(m["galv"], 0.012, 0.54, (0, 0.13, 0.0), axis="X")
    for nm, sx in (("Wheel_L", 1), ("Wheel_R", -1)):
        p = o.part(nm, (sx * 0.265, 0.13, 0.0))
        p.cyl(m["tire"], 0.13, 0.065, (0, 0, 0), axis="X", segs=28)
        p.cyl(m["red"], 0.075, 0.070, (0, 0, 0), axis="X", segs=24)
        for i in range(5):
            a = math.radians(i * 72)
            p.box(m["black"], (0.073, 0.016, 0.016), (0, 0.045 * math.cos(a), 0.045 * math.sin(a)))
    o.save()


ALL = {"van": van, "truck": truck, "heavy": heavy, "forklift": forklift, "jack": pallet_jack, "sack": sack_truck}


def main():
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    for n in names or list(ALL):
        ALL[n]()


if __name__ == "__main__":
    main()
