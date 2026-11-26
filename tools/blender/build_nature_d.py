"""Natur fuer Paket D: Baeume mit echten Blaettern, Buesche, Voegel und Tiere.

    tree_oak_1..2, tree_birch_1..2, tree_maple_1..2, tree_pine_1..2, tree_apple_1, bush_1..2   (je Trunk + Leaves)
    tree_*_far   einfache Fassung fuer weit entfernte Baeume
    bird_sparrow / bird_crow / bird_pigeon / bird_swallow     (Body, Head, WingL, WingL2, WingR, WingR2, Tail, Legs)
    animal_cat / animal_squirrel / animal_hedgehog            (Body, Head, Tail, LegFL, LegFR, LegBL, LegBR)
    butterfly                                                 (Body, WingL, WingR)
    assets/textures/nature/leaf_*.png                         Blattwerk mit Alpha (selbst gerechnet, Ordner: dct_paths.TEXTURES_DIR)

Aufruf: blender --background --factory-startup --python tools/blender/build_nature_d.py [-- trees|birds|animals|tex ...]
"""
import math
import os
import random
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Vector as V, Matrix, noise

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_human as H
from build_human import g, back, Blob, set_mats, join, box, tube, move, vcol, smoothstep, bis, cut

import dct_paths

OUT = dct_paths.MODELS_DIR
TEX = os.path.join(dct_paths.TEXTURES_DIR, "nature")


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    H.MATS.clear()


def export(name):
    for o in bpy.data.objects:
        if o.type == "MESH" and len(o.data.color_attributes):
            o.data.color_attributes.active_color_index = 0
            o.data.color_attributes.render_color_index = 0
    bpy.ops.object.select_all(action="SELECT")
    path = os.path.join(OUT, name + ".glb")
    n = sum(len(o.data.polygons) for o in bpy.data.objects if o.type == "MESH")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True, export_apply=False, export_normals=True, export_tangents=False,
                              export_animations=False, export_vertex_color="ACTIVE", export_all_vertex_colors=True, export_image_format="NONE")
    print("NATUR %s %d Flaechen %.2f MB" % (name, n, os.path.getsize(path) / 1048576.0))


# ---------------------------------------------------------------- Blatt-Texturen (2x2 Zweige je Bild)

def leaf_outline(kind, n=64):
    """Umriss eines Blatts: Laenge entlang +y von 0 bis 1, halbe Breite je t."""
    t = np.linspace(0, 1, n)
    if kind == "oak":
        w = 0.30 * np.sin(np.pi * np.clip(t * 0.95 + 0.04, 0, 1)) ** 0.75 * (0.80 + 0.20 * np.cos(t * 2 * np.pi * 4.0))
    elif kind == "birch":
        w = 0.34 * np.sin(np.pi * t ** 0.62) ** 1.0 * (1 + 0.06 * np.abs(np.sin(t * 40)))
    elif kind == "maple":
        w = 0.46 * np.sin(np.pi * t ** 0.8) ** 0.8 * (0.60 + 0.40 * np.abs(np.cos(t * 2 * np.pi * 1.6 + 0.3)))
    elif kind == "apple":
        w = 0.27 * np.sin(np.pi * t ** 0.85) ** 0.9
    else:
        w = 0.25 * np.sin(np.pi * t ** 0.75)
    return t, w


def draw_leaf(img, alpha, cx, cy, ang, size, kind, shade, rng):
    S = img.shape[0]
    r = int(size * S * 1.1) + 2
    x0, x1 = max(0, int(cx * S) - r), min(S, int(cx * S) + r)
    y0, y1 = max(0, int(cy * S) - r), min(S, int(cy * S) + r)
    if x1 <= x0 or y1 <= y0:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    dx = (xx / S - cx) / size
    dy = (yy / S - cy) / size
    ca, sa = math.cos(ang), math.sin(ang)
    u = dx * ca + dy * sa
    v = -dx * sa + dy * ca
    t, w = leaf_outline(kind)
    wi = np.interp(np.clip(v, 0, 1), t, w)
    inside = (v > 0) & (v < 1) & (np.abs(u) < wi)
    vein = np.exp(-(u / 0.018) ** 2) * 0.22 + 0.10 * np.exp(-((np.abs(u) * 0.8 - (v * 7.0 % 1.0) / 7.0 * 0.9) / 0.02) ** 2)
    side = 1.0 + 0.10 * np.sign(u)
    lum = shade * side * (0.86 + 0.20 * v) * (1.0 - 0.10 * vein) + vein * 0.16
    for c, k in enumerate((1.0, 1.0, 1.0)):
        ch = img[y0:y1, x0:x1, c]
        ch[inside] = np.clip(lum[inside] * k, 0, 1)
    al = alpha[y0:y1, x0:x1]
    al[inside] = 1.0


def draw_line(img, alpha, a, b, w, col):
    S = img.shape[0]
    n = int(math.hypot(b[0] - a[0], b[1] - a[1]) * S * 1.5) + 2
    for i in range(n):
        t = i / (n - 1)
        x, y = (a[0] + (b[0] - a[0]) * t) * S, (a[1] + (b[1] - a[1]) * t) * S
        r = max(1.0, w * S * (1 - 0.6 * t))
        x0, x1, y0, y1 = int(max(0, x - r)), int(min(S, x + r + 1)), int(max(0, y - r)), int(min(S, y + r + 1))
        img[y0:y1, x0:x1] = col
        alpha[y0:y1, x0:x1] = 1.0


def leaf_texture(kind):
    """Graustufen-Blattwerk (Farbe kommt im Spiel aus der Jahreszeit). 4 Felder mit verschiedenen Zweigen."""
    S = 1024
    out = np.zeros((S, S, 4), np.float32)
    out[..., :3] = 0.55
    rng = random.Random({"oak": 11, "birch": 12, "maple": 13, "apple": 14, "pine": 15, "bush": 16}[kind])
    for q in range(4):
        C = S // 2
        img = np.full((C, C, 3), 0.55, np.float32)
        al = np.zeros((C, C), np.float32)
        # Zweig von unten Mitte nach oben
        stem = [(0.5, 0.02)]
        a = math.pi / 2
        for i in range(7):
            a += rng.uniform(-0.22, 0.22)
            p = stem[-1]
            stem.append((p[0] + math.cos(a) * 0.125, p[1] + math.sin(a) * 0.125))
        if kind == "pine":
            tw = []
            for i, p in enumerate(stem[1:]):
                for s in (-1, 1):
                    b = a + s * rng.uniform(0.6, 1.1)
                    ln = 0.36 * (1 - i / 9.0)
                    tw.append((p, (p[0] + math.cos(b) * ln, p[1] + math.sin(b) * ln)))
            tw.append((stem[0], stem[-1]))
            for (p, e) in tw:
                draw_line(img, al, p, e, 0.005, (0.34, 0.30, 0.26))
                L = math.hypot(e[0] - p[0], e[1] - p[1])
                ba = math.atan2(e[1] - p[1], e[0] - p[0])
                for k in range(int(L * 190)):
                    t = k / max(1.0, L * 190)
                    x, y = p[0] + (e[0] - p[0]) * t, p[1] + (e[1] - p[1]) * t
                    for s in (-1, 1):
                        na = ba + s * rng.uniform(0.55, 1.0)
                        nl = rng.uniform(0.045, 0.075)
                        sh = rng.uniform(0.45, 0.95)
                        draw_line(img, al, (x, y), (x + math.cos(na) * nl, y + math.sin(na) * nl), 0.0032, (sh, sh, sh))
        else:
            for p, e in zip(stem, stem[1:]):
                draw_line(img, al, p, e, 0.008, (0.36, 0.30, 0.24))
            leaves = []
            size = {"oak": 0.165, "birch": 0.115, "maple": 0.185, "apple": 0.135, "bush": 0.13}[kind]
            cnt = {"oak": 62, "birch": 105, "maple": 54, "apple": 84, "bush": 92}[kind]
            for i in range(cnt):
                t = rng.random() ** 0.8
                j = min(len(stem) - 2, int(t * (len(stem) - 1)))
                f = t * (len(stem) - 1) - j
                px = stem[j][0] + (stem[j + 1][0] - stem[j][0]) * f + rng.uniform(-0.20, 0.20) * (1 - 0.5 * t)
                py = stem[j][1] + (stem[j + 1][1] - stem[j][1]) * f + rng.uniform(-0.08, 0.10)
                da = math.atan2(py - 0.35, px - 0.5) - math.pi / 2 + rng.uniform(-0.8, 0.8)
                leaves.append((rng.random(), px, py, da, size * rng.uniform(0.7, 1.15)))
            leaves.sort()
            for z, px, py, da, sz in leaves:
                px = min(max(px, 0.10), 0.90)
                py = min(max(py, 0.06), 0.84)
                draw_leaf(img, al, px, py, da, sz, kind, 0.42 + 0.50 * z + rng.uniform(-0.06, 0.06), rng)
        # Rand frei halten
        al[:3, :] = 0; al[-3:, :] = 0; al[:, :3] = 0; al[:, -3:] = 0
        ox, oy = (q % 2) * C, (q // 2) * C
        # Farbe ueber den Rand hinausziehen, sonst saeumt Mipmapping dunkel
        for _ in range(6):
            m = al > 0.5
            avg = img.copy()
            for sh in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                r = np.roll(img, sh, (0, 1))
                rm = np.roll(m, sh, (0, 1))
                upd = (~m) & rm
                avg[upd] = r[upd]
            img = avg
        out[oy:oy + C, ox:ox + C, :3] = img
        out[oy:oy + C, ox:ox + C, 3] = al
    os.makedirs(TEX, exist_ok=True)
    im = bpy.data.images.new("leaf_" + kind, S, S, alpha=True)
    im.alpha_mode = "CHANNEL_PACKED"
    im.pixels.foreach_set(out.reshape(-1))
    im.filepath_raw = os.path.join(TEX, "leaf_%s.png" % kind)
    im.file_format = "PNG"
    im.save()
    print("BLATT", kind, round(float(out[..., 3].mean()), 3))


# ---------------------------------------------------------------- Baeume

SPECIES = {
    # hoehe, stamm-radius, kronen-start, kronenform(fn t->radius), aeste, zweige, kartengroesse, karten
    "oak": dict(h=7.4, r=0.30, start=0.30, spread=3.1, levels=3, boughs=9, up=0.55, card=1.05, cards=430, jitter=0.35, shape="round"),
    "birch": dict(h=8.2, r=0.15, start=0.34, spread=1.75, levels=3, boughs=15, up=0.95, card=0.85, cards=380, jitter=0.18, shape="oval", droop=0.28),
    "maple": dict(h=7.0, r=0.24, start=0.30, spread=2.6, levels=3, boughs=10, up=0.80, card=1.00, cards=420, jitter=0.25, shape="egg"),
    "pine": dict(h=9.0, r=0.22, start=0.16, spread=2.0, levels=2, boughs=52, up=-0.10, card=1.00, cards=560, jitter=0.12, shape="cone"),
    "apple": dict(h=3.9, r=0.15, start=0.34, spread=1.75, levels=3, boughs=7, up=0.50, card=0.70, cards=300, jitter=0.40, shape="round"),
}


def radius_at(shape, t, spread):
    if shape == "round":
        return spread * math.sin(math.pi * min(1.0, 0.16 + 0.80 * t)) ** 0.6
    if shape == "oval":
        return spread * math.sin(math.pi * min(1.0, 0.10 + 0.86 * t)) ** 0.85
    if shape == "egg":
        return spread * math.sin(math.pi * min(1.0, 0.22 + 0.76 * t)) ** 0.75
    return spread * (1.0 - t) ** 0.85 + 0.12


class TreeMesh:
    def __init__(self):
        self.bm = bmesh.new()

    def limb(self, pts, r0, r1, seg=7, cap=True):
        rows = []
        n = len(pts)
        for i, p in enumerate(pts):
            a, b = pts[max(0, i - 1)], pts[min(n - 1, i + 1)]
            q = V((0, 1, 0)).rotation_difference((b - a).normalized())
            r = r0 + (r1 - r0) * (i / (n - 1))
            row = []
            for k in range(seg):
                an = 2 * math.pi * k / seg
                rr = r * (1 + 0.10 * math.sin(an * 3 + i * 0.7))
                o = q @ V((math.cos(an) * rr, 0, math.sin(an) * rr)) + p
                row.append(self.bm.verts.new(g(*o)))
            rows.append(row)
        for i in range(n - 1):
            for k in range(seg):
                self.bm.faces.new((rows[i][k], rows[i][(k + 1) % seg], rows[i + 1][(k + 1) % seg], rows[i + 1][k]))
        if r1 > 0.004 and cap:
            self.bm.faces.new(rows[-1])

    def build(self, name, matname):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        for p in me.polygons:
            p.use_smooth = True
        set_mats(ob, [matname])
        return ob


def grow(p, d, length, steps, rng, jitter, bend):
    pts = [p.copy()]
    for i in range(steps):
        d = (d + V((rng.uniform(-1, 1), rng.uniform(-0.6, 0.8), rng.uniform(-1, 1))) * jitter / steps * 2.2 + V((0, bend / steps, 0))).normalized()
        pts.append(pts[-1] + d * (length / steps))
    return pts


def tree(kind, var, far=False):
    sp = SPECIES[kind]
    rng = random.Random(kind.__hash__() if False else sum(map(ord, kind)) * 31 + var * 7)
    reset()
    H.mat("Bark_" + kind, (0.35, 0.27, 0.20), 0.95)
    H.mat("Leaf_" + kind, (0.4, 0.5, 0.3), 0.8)
    tm = TreeMesh()
    h = sp["h"] * rng.uniform(0.94, 1.08)
    trunk_top = h * (0.97 if sp["shape"] == "cone" else 0.80)
    trunk = grow(V((0, -0.15, 0)), V((0, 1, 0)), trunk_top + 0.15, 12, rng, 0.06 if sp["shape"] == "cone" else 0.16, 0.5)
    if not far:
        # Wurzelanlauf
        tm.limb([V((0, -0.2, 0)), V((0, 0.0, 0)), V((0, 0.22, 0)), trunk[1] + V((0, 0.35, 0))], sp["r"] * 1.65, sp["r"] * 1.0, 9, False)
    tm.limb(trunk, sp["r"] * 1.08, sp["r"] * (0.10 if sp["shape"] == "cone" else 0.22), 5 if far else 9)

    def at(t):
        f = t * (len(trunk) - 1)
        j = min(len(trunk) - 2, int(f))
        return trunk[j].lerp(trunk[j + 1], f - j)
    tips = []
    boughs = sp["boughs"]
    for i in range(boughs):
        t = sp["start"] + (1 - sp["start"]) * ((i + rng.uniform(0.1, 0.9)) / boughs)
        if sp["shape"] == "cone":
            t = sp["start"] + (0.985 - sp["start"]) * (i / (boughs - 1.0))
        ct = (t - sp["start"]) / (1 - sp["start"])
        ang = i * 2.39996 + rng.uniform(-0.3, 0.3)
        out = V((math.cos(ang), 0, math.sin(ang)))
        ln = radius_at(sp["shape"], ct, sp["spread"]) * rng.uniform(0.82, 1.08)
        p = at(min(0.99, t))
        d = (out + V((0, sp["up"] * (0.6 + 0.8 * ct) if sp["shape"] != "cone" else sp["up"] + 0.35 * ct, 0))).normalized()
        br = sp["r"] * (0.46 if sp["shape"] != "cone" else 0.20) * (1 - 0.55 * ct)
        pts = grow(p, d, ln, 6, rng, sp["jitter"], 0.25 if sp["shape"] != "cone" else -0.18)
        tm.limb(pts, br, br * 0.18, 4 if far else 6)
        for k in range(2, 7):
            tips.append((pts[k], (pts[k] - pts[k - 1]).normalized(), out))
        if not far and sp["levels"] >= 3:
            for k in range(5):
                q = pts[2 + (k % 4)]
                side = (out.cross(V((0, 1, 0))) * (1 if k % 2 else -1) + out * 0.7 + V((0, rng.uniform(0.1, 0.8), 0))).normalized()
                sub = grow(q, side, ln * rng.uniform(0.34, 0.52), 4, rng, sp["jitter"] * 1.2, 0.15)
                tm.limb(sub, br * 0.36, br * 0.08, 4)
                for m in range(1, 5):
                    tips.append((sub[m], (sub[m] - sub[m - 1]).normalized(), out))
        elif far and sp["levels"] >= 3:
            for k in range(3):
                q = pts[3 + k]
                side = (out.cross(V((0, 1, 0))) * (1 if k % 2 else -1) + out * 0.7 + V((0, rng.uniform(0.1, 0.8), 0))).normalized()
                tips.append((q + side * ln * 0.35, side, out))
    trunk_ob = tm.build("Trunk", "Bark_" + kind)
    if sp["shape"] != "cone":
        for k in range(3):
            tips.append((trunk[-1] + V((rng.uniform(-0.2, 0.2), k * 0.22, rng.uniform(-0.2, 0.2))), V((0, 1, 0)), V((1, 0, 0))))
    else:
        tips.append((trunk[-1], V((0, 1, 0)), V((1, 0, 0))))
        tips.append((trunk[-2], V((0, 1, 0)), V((0, 0, 1))))
    # Blattkarten: quer stehende Vierecke an den Zweigspitzen
    cen = V((0, h * (sp["start"] + (1 - sp["start"]) * 0.48), 0))
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    colr = bm.loops.layers.float_color.new("Col")
    n_cards = (150 if sp["shape"] == "cone" else 110) if far else sp["cards"]
    nrm = []
    for c in range(n_cards):
        tip, d, out = tips[(c * len(tips)) // n_cards] if far else (tips[c % len(tips)] if c < len(tips) * 2 else tips[rng.randrange(len(tips))])
        sz = sp["card"] * rng.uniform(0.75, 1.15) * (1.55 if far else 1.0)
        o = tip + V((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * (0.16 if not far else 0.25)
        if far and sp["shape"] == "cone":
            sz *= 1.15
        if sp["shape"] == "cone":
            # Nadelzweige liegen flach und haengen leicht
            ydir = (d + V((0, rng.uniform(-0.35, 0.05), 0))).normalized()
            xdir = ydir.cross(V((rng.uniform(-0.5, 0.5), 1, rng.uniform(-0.5, 0.5)))).normalized()
            o = o - ydir * sz * 0.25
        else:
            ydir = (d * 0.7 + V((rng.uniform(-1, 1), rng.uniform(-0.4, 0.9) - sp.get("droop", 0) * 2.2, rng.uniform(-1, 1))) * 0.8).normalized()
            xdir = ydir.cross(V((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))).normalized()
        cell = rng.randrange(4)
        u0, v0 = (cell % 2) * 0.5, (cell // 2) * 0.5
        corners = [(-0.5, 0.0), (0.5, 0.0), (0.5, 1.0), (-0.5, 1.0)]
        vs = [bm.verts.new(g(*(o + xdir * (cx * sz) + ydir * (cy * sz)))) for cx, cy in corners]
        f = bm.faces.new(vs)
        mid = o + ydir * sz * 0.5
        nn = (mid - cen)
        nn.y *= 0.8
        nn = (nn.normalized() + V((0, 1.1 if sp["shape"] == "cone" else 0.35, 0))).normalized()
        # Tiefe im Baum: innen dunkler. Fallreihenfolge: jede Karte hat eine Zufallszahl.
        depth = min(1.0, ((mid - cen).length / (sp["spread"] * 1.1)))
        ao = 0.45 + 0.55 * depth
        rnd = rng.random()
        for lp, (cx, cy) in zip(f.loops, corners):
            lp[uv].uv = (u0 + (cx + 0.5) * 0.5, v0 + cy * 0.5)
            lp[colr] = (ao, rnd, max(0.0, min(1.0, cy)), 1.0)
        nrm += [nn] * 4
    me = bpy.data.meshes.new("Leaves")
    bm.to_mesh(me)
    bm.free()
    lo = bpy.data.objects.new("Leaves", me)
    bpy.context.scene.collection.objects.link(lo)
    set_mats(lo, ["Leaf_" + kind])
    me.normals_split_custom_set([tuple(V(g(*n))) for n in nrm])
    export("tree_%s_%s" % (kind, "far" if far else var))


def bush(var):
    rng = random.Random(90 + var)
    reset()
    H.mat("Bark_bush", (0.35, 0.27, 0.20), 0.95)
    H.mat("Leaf_bush", (0.4, 0.5, 0.3), 0.8)
    tm = TreeMesh()
    tips = []
    for i in range(14):
        a = i * 2.39996
        d = V((math.cos(a) * 0.7, 1.0, math.sin(a) * 0.7)).normalized()
        pts = grow(V((math.cos(a) * 0.08, -0.05, math.sin(a) * 0.08)), d, rng.uniform(0.55, 0.95), 5, rng, 0.5, 0.1)
        tm.limb(pts, 0.022, 0.006, 4)
        tips += [(p, d) for p in pts[2:]]
    tm.build("Trunk", "Bark_bush")
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    colr = bm.loops.layers.float_color.new("Col")
    nrm = []
    cen = V((0, 0.45, 0))
    for c in range(150):
        tip, d = tips[c % len(tips)]
        sz = rng.uniform(0.34, 0.52)
        o = tip + V((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.10
        ydir = (d * 0.6 + V((rng.uniform(-1, 1), rng.uniform(-0.2, 1), rng.uniform(-1, 1))) * 0.8).normalized()
        xdir = ydir.cross(V((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))).normalized()
        cell = rng.randrange(4)
        u0, v0 = (cell % 2) * 0.5, (cell // 2) * 0.5
        corners = [(-0.5, 0.0), (0.5, 0.0), (0.5, 1.0), (-0.5, 1.0)]
        f = bm.faces.new([bm.verts.new(g(*(o + xdir * (cx * sz) + ydir * (cy * sz)))) for cx, cy in corners])
        mid = o + ydir * sz * 0.5
        nn = ((mid - cen).normalized() + V((0, 0.4, 0))).normalized()
        ao = 0.45 + 0.55 * min(1.0, (mid - cen).length / 0.75)
        rnd = rng.random()
        for lp, (cx, cy) in zip(f.loops, corners):
            lp[uv].uv = (u0 + (cx + 0.5) * 0.5, v0 + cy * 0.5)
            lp[colr] = (ao, rnd, cy, 1.0)
        nrm += [nn] * 4
    me = bpy.data.meshes.new("Leaves")
    bm.to_mesh(me)
    bm.free()
    lo = bpy.data.objects.new("Leaves", me)
    bpy.context.scene.collection.objects.link(lo)
    set_mats(lo, ["Leaf_bush"])
    me.normals_split_custom_set([tuple(V(g(*n))) for n in nrm])
    export("bush_%d" % var)


# ---------------------------------------------------------------- Voegel (Schnabel zeigt nach -Z)

BIRDS = {
    # laenge, koerper(r), farben: ruecken, bauch, kopf, fluegel, spitze, schnabel, bein
    "sparrow": dict(L=0.15, fat=1.15, back=(0.46, 0.32, 0.20), belly=(0.74, 0.69, 0.62), head=(0.42, 0.38, 0.36), cap=(0.45, 0.25, 0.14), wing=(0.40, 0.28, 0.18), tip=(0.22, 0.17, 0.13), beak=(0.20, 0.18, 0.16), leg=(0.62, 0.44, 0.34), tail=0.40, span=0.115, beakl=0.013, beakr=0.0055, neck=0.0),
    "crow": dict(L=0.46, fat=0.95, back=(0.045, 0.05, 0.07), belly=(0.06, 0.06, 0.07), head=(0.045, 0.05, 0.06), cap=(0.04, 0.045, 0.06), wing=(0.04, 0.045, 0.07), tip=(0.03, 0.03, 0.04), beak=(0.05, 0.05, 0.05), leg=(0.05, 0.05, 0.05), tail=0.42, span=0.42, beakl=0.055, beakr=0.014, neck=0.2),
    "pigeon": dict(L=0.33, fat=1.18, back=(0.42, 0.46, 0.52), belly=(0.55, 0.57, 0.61), head=(0.26, 0.30, 0.38), cap=(0.26, 0.30, 0.38), wing=(0.46, 0.49, 0.55), tip=(0.16, 0.17, 0.20), beak=(0.16, 0.15, 0.16), leg=(0.70, 0.28, 0.28), tail=0.36, span=0.30, beakl=0.020, beakr=0.0065, neck=0.5, iris=(0.16, 0.38, 0.30)),
    "swallow": dict(L=0.17, fat=0.85, back=(0.07, 0.10, 0.22), belly=(0.90, 0.86, 0.78), head=(0.07, 0.10, 0.22), cap=(0.42, 0.16, 0.10), wing=(0.07, 0.09, 0.18), tip=(0.05, 0.06, 0.10), beak=(0.08, 0.08, 0.08), leg=(0.18, 0.14, 0.12), tail=0.65, span=0.165, beakl=0.008, beakr=0.004, neck=0.0, fork=True),
}


def mixc(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def feather_wing(name, s, root, span, chord, sp, tip, sweep):
    """Fluegelteil als gewoelbte Flaeche mit Federspitzen. Ursprung am Gelenk."""
    bm = bmesh.new()
    colr = bm.loops.layers.float_color.new("Col")
    nx, nz = 10, 6
    top, bot = [], []
    for i in range(nx + 1):
        t = i / nx
        row, row2 = [], []
        c = chord[0] + (chord[1] - chord[0]) * t
        if tip:
            c *= max(0.08, (1 - t ** 2.2))
        fr = 1.0 + (0.16 if tip else 0.08) * (i % 2)
        for k in range(nz + 1):
            u = k / nz
            z = -c * 0.32 + c * u * (fr if u > 0.85 else 1.0) + sweep * t * t * span
            y = 0.06 * c * math.sin(math.pi * min(1.0, u * 1.1)) - 0.10 * span * t * t * (0.5 if tip else 0.2)
            row.append(bm.verts.new(g(s * span * t, y + 0.0015 * (1 - u), z)))
            row2.append(bm.verts.new(g(s * span * t, y - 0.0012 * (1 - u) - 0.0004, z)))
        top.append(row)
        bot.append(row2)
    for i in range(nx):
        for k in range(nz):
            for rows, fl in ((top, False), (bot, True)):
                q = (rows[i][k], rows[i + 1][k], rows[i + 1][k + 1], rows[i][k + 1])
                f = bm.faces.new(q[::-1] if fl != (s < 0) else q)
                for lp in f.loops:
                    x, y, z = back(lp.vert.co)
                    t = abs(x) / span
                    u = (k + 0.5) / nz
                    col = mixc(sp["wing"], sp["tip"], smoothstep(0.35, 0.9, u) * (0.6 if not tip else 0.9) + (0.25 * t if tip else 0))
                    if fl:
                        col = mixc(col, sp["belly"], 0.45)
                    b = 0.92 + 0.08 * ((i % 2))
                    lp[colr] = ((col[0] * b) ** 2.2, (col[1] * b) ** 2.2, (col[2] * b) ** 2.2, 1.0)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for p in me.polygons:
        p.use_smooth = True
    set_mats(ob, ["Bird"])
    ob.location = V(g(*root))
    return ob


def bird(kind):
    sp = BIRDS[kind]
    reset()
    H.mat("Bird", (1, 1, 1), 0.75)
    H.mat("Beak", sp["beak"], 0.4)
    H.mat("Leg", sp["leg"], 0.6)
    H.mat("Eye", (0.02, 0.02, 0.02), 0.1)
    L = sp["L"]
    f = sp["fat"]
    b = Blob()
    # Rumpf: Ursprung zwischen den Fuessen, Ruecken 45 Grad geneigt
    cy = L * 0.40
    b.ell((0, cy, 0), (L * 0.185 * f, L * 0.195 * f, L * 0.34), (18, 0, 0))
    b.ell((0, cy + L * 0.06, -L * 0.18), (L * 0.150 * f, L * 0.165 * f, L * 0.19), (25, 0, 0))
    b.cap((0, cy - L * 0.02, L * 0.20), L * 0.11, (0, cy - L * 0.07, L * 0.36), L * 0.035)
    hy, hz = cy + L * (0.235 + 0.06 * sp["neck"]), -L * (0.285 + 0.04 * sp["neck"])
    b.cap((0, cy + L * 0.08, -L * 0.20), L * 0.115 * f, (0, hy - L * 0.03, hz + L * 0.02), L * 0.085)
    body = b.mesh("Body", L * 0.020, 5, 0.5, 900)

    def bc(x, y, z):
        t = smoothstep(cy - L * 0.10, cy + L * 0.10, y - z * 0.30)
        c = mixc(sp["belly"], sp["back"], t)
        if sp.get("iris") and z < -L * 0.14 and y > cy + L * 0.03:
            c = mixc(c, sp["iris"], 0.75)
        if kind == "sparrow":
            st = noise.noise(V((x * 190, y * 60, z * 60)))
            c = mixc(c, (0.16, 0.11, 0.08), max(0.0, st) * 0.9 * t)
        if kind == "swallow" and y > cy + L * 0.02 and z < -L * 0.22 and t < 0.5:
            c = (0.46, 0.17, 0.10)
        n = 0.92 + 0.10 * noise.noise(V((x, y, z)) * (30 / L * 0.15))
        return tuple(v * n for v in c)
    vcol(body, bc)
    set_mats(body, ["Bird"])
    # Kopf (Ursprung am Hals)
    hr = L * (0.118 if kind in ("sparrow", "swallow") else 0.098)
    hb = Blob()
    hb.ell((0, 0, 0), (hr * 0.92, hr * 0.95, hr * 1.10))
    hb.ell((0, -hr * 0.12, -hr * 0.5), (hr * 0.60, hr * 0.60, hr * 0.60))
    head = hb.mesh("Head", hr * 0.16, 4, 0.5, 420)

    def hc(x, y, z):
        c = mixc(sp["head"], sp["cap"], smoothstep(hr * 0.25, hr * 0.6, y))
        if kind == "sparrow":
            if y < -hr * 0.1 and z < -hr * 0.2:
                c = (0.10, 0.09, 0.08)
            elif abs(x) > hr * 0.55 and y < hr * 0.2:
                c = (0.78, 0.75, 0.70)
        if kind == "swallow":
            c = sp["cap"] if (y < -hr * 0.2 and z < 0) else sp["head"]
        return c
    vcol(head, hc)
    set_mats(head, ["Bird"])
    bl, br = sp["beakl"], sp["beakr"]
    bk = H.tube("k", [(0, -hr * 0.16, -hr * 0.95), (0, -hr * 0.20, -hr * 0.95 - bl * 0.55), (0, -hr * 0.30, -hr * 0.95 - bl)], br, "Beak", 8)
    mesh = bk.data
    for v in mesh.vertices:
        x, y, z = back(v.co)
        t = smoothstep(-hr * 0.9, -hr * 0.95 - bl, z)
        v.co = g(x * (1 - 0.88 * t), (y + hr * 0.2) * (1 - 0.75 * t) - hr * 0.2 - hr * 0.10 * t, z)
    ey = []
    for s in (-1, 1):
        e = Blob()
        e.sph((s * hr * 0.70, hr * 0.18, -hr * 0.52), hr * 0.155, 10)
        eo = e.mesh("e", hr * 0.05, 2, 0.4, 60)
        set_mats(eo, ["Eye"])
        ey.append(eo)
    if sp["neck"] >= 0.5:
        ce = Blob()
        ce.ell((0, hr * 0.02, -hr * 1.02), (hr * 0.22, hr * 0.16, hr * 0.16))
        co = ce.mesh("c", hr * 0.06, 1, 0.4, 40)
        H.mat("Cere", (0.85, 0.84, 0.82), 0.6)
        set_mats(co, ["Cere"])
        ey.append(co)
    for o in [bk] + ey:
        vcol(o, lambda x, y, z: (1, 1, 1))
    hd = join("Head", [head, bk] + ey)
    hd.location = V(g(0, hy, hz))
    # Fluegel: innen + aussen (Gelenk)
    sw = 0.45 if kind == "swallow" else 0.12
    ro = L * 0.150 * f
    inner = sp["span"] * 0.46
    outer = sp["span"] * (0.62 if kind != "swallow" else 0.85)
    ch = L * (0.46 if kind != "swallow" else 0.32)
    for s, n in ((-1, "L"), (1, "R")):
        wi = feather_wing("Wing" + n, s, (s * ro * 0.75, cy + L * 0.10, -L * 0.12), inner, (ch, ch * 0.95), sp, False, 0.0)
        wo = feather_wing("Wing" + n + "2", s, (0, 0, 0), outer, (ch * 0.95, ch * (0.35 if kind != "swallow" else 0.15)), sp, True, sw)
        wo.parent = wi
        wo.location = V(g(s * inner, -0.10 * inner * 0.2, 0))
    # Schwanz
    tl = L * sp["tail"]
    bm = bmesh.new()
    colr = bm.loops.layers.float_color.new("Col")
    nf = 6
    for k in range(nf):
        u = (k + 0.5) / nf * 2 - 1
        ln = tl * (1 - 0.10 * abs(u)) if not sp.get("fork") else tl * (0.45 + 0.65 * abs(u) ** 2.2)
        w = L * 0.042
        x0, x1 = u * L * 0.050, u * L * 0.115
        for sgn in (0, 1):
            y = 0.0016 * (k % 2) - 0.001 * sgn
            vs = [bm.verts.new(g(*p)) for p in ((x0 - w * 0.5, y, 0), (x0 + w * 0.5, y, 0), (x1 + w * 0.6, y - ln * 0.06, ln * 0.92), (x1, y - ln * 0.07, ln), (x1 - w * 0.6, y - ln * 0.06, ln * 0.92))]
            fc = bm.faces.new(vs if sgn else vs[::-1])
            for lp in fc.loops:
                z = back(lp.vert.co)[2]
                c = mixc(sp["wing"], sp["tip"], z / tl)
                lp[colr] = (*(q ** 2.2 for q in c), 1.0)
    me = bpy.data.meshes.new("Tail")
    bm.to_mesh(me)
    bm.free()
    tail = bpy.data.objects.new("Tail", me)
    bpy.context.scene.collection.objects.link(tail)
    set_mats(tail, ["Bird"])
    tail.location = V(g(0, cy - L * 0.045, L * 0.30))
    # Beine
    lg = []
    for s in (-1, 1):
        x = s * L * 0.065
        lg.append(H.tube("l", [(x, cy - L * 0.14, L * 0.02), (x, cy * 0.45, L * 0.05), (x, 0.004, -L * 0.005)], L * 0.014, "Leg", 6))
        for a in (-0.5, 0.0, 0.5):
            lg.append(H.tube("t", [(x, 0.004, 0), (x + math.sin(a) * L * 0.10, 0.003, -math.cos(a) * L * 0.11)], L * 0.010, "Leg", 5))
        lg.append(H.tube("t", [(x, 0.004, 0), (x, 0.003, L * 0.07)], L * 0.010, "Leg", 5))
    for o in lg:
        vcol(o, lambda x, y, z: (1, 1, 1))
    join("Legs", lg)
    export("bird_" + kind)


# ---------------------------------------------------------------- Tiere (Blick nach -Z)

def part(name, blob, voxel, faces, colfn, loc=(0, 0, 0), smooth=4):
    ob = blob.mesh(name, voxel, smooth, 0.5, faces)
    vcol(ob, colfn)
    set_mats(ob, ["Fur"])
    ob.location = V(g(*loc))
    return ob


def eyes(r, pts, mat="Eye"):
    out = []
    for p in pts:
        e = Blob()
        e.sph(p, r, 10)
        o = e.mesh("e", r * 0.3, 2, 0.4, 70)
        set_mats(o, [mat])
        vcol(o, lambda x, y, z: (1, 1, 1))
        out.append(o)
    return out


def cat():
    reset()
    H.mat("Fur", (1, 1, 1), 0.9)
    H.mat("Eye", (0.55, 0.62, 0.12), 0.1)
    H.mat("Pupil", (0.01, 0.01, 0.01), 0.1)
    H.mat("Nose", (0.72, 0.42, 0.40), 0.5)

    def col(x, y, z):
        st = math.sin(z * 62 + noise.noise(V((x * 9, y * 9, z * 9))) * 3.0)
        c = mixc((0.80, 0.50, 0.24), (0.52, 0.28, 0.11), smoothstep(0.2, 0.9, st) * 0.9)
        c = mixc(c, (0.93, 0.88, 0.80), smoothstep(0.02, -0.05, y - 0.20) * 0.8)
        return tuple(v * (0.95 + 0.07 * noise.noise(V((x, y, z)) * 60)) for v in c)
    b = Blob()
    b.ell((0, 0.235, 0.02), (0.066, 0.076, 0.155))
    b.ell((0, 0.240, -0.10), (0.060, 0.076, 0.075))
    b.ell((0, 0.228, 0.12), (0.066, 0.078, 0.080))
    b.cap((0, 0.262, -0.14), 0.046, (0, 0.300, -0.185), 0.040)
    part("Body", b, 0.012, 1400, col)
    h = Blob()
    h.ell((0, 0.018, -0.030), (0.052, 0.046, 0.050))
    h.ell((0, 0.002, -0.068), (0.026, 0.020, 0.024))
    for s in (-1, 1):
        h.cap((s * 0.032, 0.052, -0.022), 0.019, (s * 0.040, 0.094, -0.016), 0.004)
        h.ell((s * 0.014, -0.004, -0.080), (0.014, 0.012, 0.012))
    hd = h.mesh("Head", 0.0062, 3, 0.45, 1100)

    def hc(x, y, z):
        c = col(x * 1.4, y + 0.25, z)
        if z < -0.062 and y < 0.012:
            c = (0.95, 0.91, 0.85)
        if y > 0.062 and z < -0.018:
            c = mixc(c, (0.85, 0.62, 0.55), 0.6)
        return c
    vcol(hd, hc)
    set_mats(hd, ["Fur"])
    n = Blob(); n.ell((0, 0.006, -0.093), (0.007, 0.005, 0.005))
    no = n.mesh("n", 0.002, 2, 0.4, 60); set_mats(no, ["Nose"]); vcol(no, lambda x, y, z: (1, 1, 1))
    ex = eyes(0.0105, [(s * 0.024, 0.022, -0.070) for s in (-1, 1)]) + eyes(0.0052, [(s * 0.0250, 0.022, -0.0775) for s in (-1, 1)], "Pupil")
    wh = []
    H.mat("Whisk", (0.95, 0.95, 0.95), 0.6)
    for s in (-1, 1):
        for a in (-0.25, 0.0, 0.25):
            wh.append(tube("w", [(s * 0.018, -0.002, -0.086), (s * 0.075, -0.004 + a * 0.05, -0.084)], 0.0006, "Whisk", 4))
    for o in wh:
        vcol(o, lambda x, y, z: (1, 1, 1))
    hd = join("Head", [hd, no] + ex + wh)
    hd.location = V(g(0, 0.300, -0.175))
    t = Blob()
    t.chain([((0, 0, 0), 0.022), ((0, 0.015, 0.07), 0.021), ((0, 0.06, 0.14), 0.020), ((0, 0.13, 0.175), 0.020), ((0, 0.19, 0.165), 0.016)])
    part("Tail", t, 0.008, 400, lambda x, y, z: mixc(col(x, 0.25, z + y), (0.45, 0.24, 0.10), smoothstep(0.10, 0.19, y)), (0, 0.262, 0.185))
    for nme, x, z in (("LegFL", -0.036, -0.115), ("LegFR", 0.036, -0.115), ("LegBL", -0.042, 0.125), ("LegBR", 0.042, 0.125)):
        l = Blob()
        back_leg = "B" in nme[3]
        if back_leg:
            l.ell((0, -0.035, 0.0), (0.032, 0.058, 0.048))
            l.chain([((0, -0.06, 0.012), 0.026), ((0, -0.13, 0.030), 0.016), ((0, -0.195, 0.004), 0.014)])
        else:
            l.chain([((0, 0.0, 0), 0.030), ((0, -0.09, 0.006), 0.019), ((0, -0.195, 0.0), 0.0145)])
        l.ell((0, -0.205, -0.014), (0.016, 0.013, 0.024))
        part(nme, l, 0.008, 320, lambda x, y, z: mixc(col(x, 0.25, z * 2 + y), (0.94, 0.90, 0.84), smoothstep(-0.15, -0.19, y)), (x, 0.218, z))
    export("animal_cat")


def squirrel():
    reset()
    H.mat("Fur", (1, 1, 1), 0.9)
    H.mat("Eye", (0.02, 0.02, 0.02), 0.1)

    def col(x, y, z):
        c = mixc((0.58, 0.24, 0.10), (0.94, 0.88, 0.80), smoothstep(0.075, 0.045, y + abs(x) * 0.4 + z * 0.15))
        return tuple(v * (0.94 + 0.09 * noise.noise(V((x, y, z)) * 110)) for v in c)
    b = Blob()
    b.ell((0, 0.085, 0.025), (0.042, 0.050, 0.065))
    b.ell((0, 0.095, -0.035), (0.034, 0.042, 0.046))
    part("Body", b, 0.008, 800, col)
    h = Blob()
    h.ell((0, 0.0, -0.012), (0.026, 0.026, 0.030))
    h.ell((0, -0.008, -0.036), (0.014, 0.012, 0.014))
    for s in (-1, 1):
        h.cap((s * 0.016, 0.022, 0.0), 0.0085, (s * 0.020, 0.052, 0.004), 0.002)
    hd = h.mesh("Head", 0.004, 3, 0.45, 600)
    vcol(hd, lambda x, y, z: (0.56, 0.23, 0.10) if y > -0.010 else (0.92, 0.86, 0.78))
    set_mats(hd, ["Fur"])
    n = Blob(); n.sph((0, -0.006, -0.050), 0.0035, 8)
    no = n.mesh("n", 0.0014, 1, 0.4, 40); set_mats(no, ["Eye"]); vcol(no, lambda x, y, z: (1, 1, 1))
    hd = join("Head", [hd, no] + eyes(0.0062, [(s * 0.0205, 0.005, -0.020) for s in (-1, 1)]))
    hd.location = V(g(0, 0.138, -0.062))
    t = Blob()
    t.chain([((0, 0, 0), 0.016), ((0, 0.02, 0.05), 0.026), ((0, 0.08, 0.085), 0.034), ((0, 0.15, 0.080), 0.036), ((0, 0.195, 0.045), 0.028), ((0, 0.20, 0.015), 0.016)])
    part("Tail", t, 0.008, 700, lambda x, y, z: tuple(v * (0.85 + 0.25 * noise.noise(V((x * 140, y * 50, z * 50)))) for v in (0.62, 0.27, 0.11)), (0, 0.080, 0.080))
    for nme, x, z in (("LegFL", -0.020, -0.050), ("LegFR", 0.020, -0.050), ("LegBL", -0.030, 0.045), ("LegBR", 0.030, 0.045)):
        l = Blob()
        if nme[3] == "B":
            l.ell((0, -0.012, 0), (0.017, 0.030, 0.026))
            l.cap((0, -0.034, 0.006), 0.010, (0, -0.052, -0.012), 0.008)
            l.ell((0, -0.058, -0.018), (0.009, 0.007, 0.022))
        else:
            l.chain([((0, 0, 0), 0.013), ((0, -0.032, -0.004), 0.009), ((0, -0.066, -0.008), 0.007)])
            l.ell((0, -0.070, -0.014), (0.007, 0.006, 0.011))
        part(nme, l, 0.005, 200, lambda x, y, z: (0.54, 0.22, 0.09), (x, 0.066 if nme[3] == "B" else 0.076, z))
    export("animal_squirrel")


def hedgehog():
    reset()
    H.mat("Fur", (1, 1, 1), 0.95)
    H.mat("Eye", (0.02, 0.02, 0.02), 0.1)
    H.mat("Spike", (0.36, 0.28, 0.20), 0.8)
    b = Blob()
    b.ell((0, 0.072, 0.015), (0.070, 0.066, 0.100))
    part("Body", b, 0.010, 700, lambda x, y, z: (0.24, 0.18, 0.13) if y > 0.05 else (0.62, 0.52, 0.40))
    # Stacheln
    rng = random.Random(4)
    bm = bmesh.new()
    colr = bm.loops.layers.float_color.new("Col")
    k = 0
    while k < 620:
        d = V((rng.uniform(-1, 1), rng.uniform(-0.15, 1), rng.uniform(-0.85, 1)))
        if d.length < 0.2 or d.length > 1:
            continue
        d.normalize()
        p = V((d.x * 0.068, 0.072 + d.y * 0.064, 0.015 + d.z * 0.098))
        n = (V((d.x / 0.07, d.y / 0.066, d.z / 0.10))).normalized()
        n = (n + V((0, 0, 0.75))).normalized()
        side = n.cross(V((0, 1, 0.1))).normalized() * 0.0028
        up = n.cross(side).normalized() * 0.0028
        ln = rng.uniform(0.026, 0.038)
        base = [p + side, p - side * 0.5 + up, p - side * 0.5 - up]
        tipv = bm.verts.new(g(*(p + n * ln)))
        bv = [bm.verts.new(g(*q)) for q in base]
        for a in range(3):
            f = bm.faces.new((bv[a], bv[(a + 1) % 3], tipv))
            for lp in f.loops:
                lp[colr] = (1.0, 0.95, 0.85, 1) if lp.vert is tipv else (0.45, 0.40, 0.36, 1)
        k += 1
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new("Spikes")
    bm.to_mesh(me)
    bm.free()
    so = bpy.data.objects.new("Spikes", me)
    bpy.context.scene.collection.objects.link(so)
    set_mats(so, ["Spike"])
    h = Blob()
    h.ell((0, 0, 0), (0.040, 0.036, 0.036))
    h.cap((0, -0.006, -0.025), 0.022, (0, -0.014, -0.066), 0.008)
    for s in (-1, 1):
        h.ell((s * 0.028, 0.022, -0.012), (0.010, 0.012, 0.005))
    hd = h.mesh("Head", 0.005, 3, 0.45, 500)
    vcol(hd, lambda x, y, z: mixc((0.46, 0.36, 0.26), (0.66, 0.56, 0.44), smoothstep(-0.02, -0.05, z)))
    set_mats(hd, ["Fur"])
    hd = join("Head", [hd] + eyes(0.0055, [(s * 0.0200, 0.008, -0.036) for s in (-1, 1)]) + eyes(0.0075, [(0, -0.013, -0.074)]))
    hd.location = V(g(0, 0.060, -0.085))
    for nme, x, z in (("LegFL", -0.032, -0.050), ("LegFR", 0.032, -0.050), ("LegBL", -0.036, 0.070), ("LegBR", 0.036, 0.070)):
        l = Blob()
        l.cap((0, 0, 0), 0.013, (0, -0.020, 0), 0.010)
        l.ell((0, -0.027, -0.006), (0.010, 0.006, 0.014))
        part(nme, l, 0.005, 120, lambda x, y, z: (0.40, 0.32, 0.25), (x, 0.032, z))
    export("animal_hedgehog")


def butterfly():
    reset()
    H.mat("Wing", (1, 1, 1), 0.7)
    H.mat("Dark", (0.06, 0.05, 0.05), 0.7)
    b = Blob()
    b.cap((0, 0, -0.012), 0.0022, (0, 0, 0.012), 0.0014)
    bo = b.mesh("Body", 0.0008, 2, 0.4, 120)
    set_mats(bo, ["Dark"])
    for s, n in ((-1, "WingL"), (1, "WingR")):
        bm = bmesh.new()
        colr = bm.loops.layers.float_color.new("Col")
        fore = [(0, 0, -0.008), (0.018, 0, -0.026), (0.034, 0, -0.024), (0.034, 0, -0.010), (0.018, 0, 0.001), (0, 0, 0.002)]
        hind = [(0, 0, 0.000), (0.020, -0.0004, 0.000), (0.028, -0.0004, 0.010), (0.020, -0.0004, 0.022), (0.006, -0.0004, 0.014)]
        for poly in (fore, hind):
            cx = sum(p[0] for p in poly) / len(poly)
            cz = sum(p[2] for p in poly) / len(poly)
            cv = bm.verts.new(g(s * cx, 0, cz))
            vs = [bm.verts.new(g(s * p[0], p[1], p[2])) for p in poly]
            for i in range(len(vs)):
                f = bm.faces.new((cv, vs[i], vs[(i + 1) % len(vs)]))
                for lp in f.loops:
                    edge = lp.vert is not cv and abs(back(lp.vert.co)[0]) > 0.016
                    lp[colr] = (0.12, 0.10, 0.10, 1) if edge else (1, 1, 1, 1)
        me = bpy.data.meshes.new(n)
        bm.to_mesh(me)
        bm.free()
        ob = bpy.data.objects.new(n, me)
        bpy.context.scene.collection.objects.link(ob)
        set_mats(ob, ["Wing"])
    export("butterfly")


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else ["tex", "trees", "birds", "animals"]
    os.makedirs(TEX, exist_ok=True)
    if "tex" in args:
        reset()
        for k in ("oak", "birch", "maple", "apple", "pine", "bush"):
            leaf_texture(k)
    if "trees" in args:
        for k in ("oak", "birch", "maple", "pine"):
            for v in (1, 2):
                tree(k, v)
            tree(k, 1, True)
        tree("apple", 1)
        tree("apple", 1, True)
        bush(1)
        bush(2)
    if "birds" in args:
        for k in BIRDS:
            bird(k)
    if "animals" in args:
        cat()
        squirrel()
        hedgehog()
        butterfly()


if __name__ == "__main__":
    main()
