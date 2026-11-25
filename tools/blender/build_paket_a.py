"""Blender 5.2: Modelle fuer Roadmap-Paket A.

  Kartons (assets/models/carton_*.glb): je Warenart ein eigener, mit einzeln drehbaren Klappen
      (Flap_F, Flap_B, Flap_L, Flap_R), Klebeband (Tape) und bedruckten Seiten.
      Pappe (Material CT_Kraft) bekommt ihre Texturen im Spiel aus assets/textures/carton/.
  Altpapier-Container (paper_bin.glb): Deckel als eigener Knoten "Lid".
  Leisten (power_strip.glb, lan_strip.glb): Buchsenpositionen wie in scripts/world/decor_prop.gd,
      Wippe "Switch", LED-Materialien PS_Led0..5 / LS_Link0..7 / LS_Act0..7, Displayglas.
  Notstrom (ups_small.glb, ups_cabinet.glb, ups_container.glb): LED-Materialien UPS_Bar0..9,
      UPS_Status, UPS_Mod0..n, Luefter Fan_0.., Warnleuchte UPS_Beacon.

Aufruf: blender --background --python tools/blender/build_paket_a.py -- [cartons|bin|strips|ups ...]
"""

import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector, noise

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import pbr_textures as pt
from build_delivery_van import PartBuilder, _load_img, _new_mat, _save_rgb, g, make_solid_mat
from hall_pbr_kit import (
    OUT_MODELS_DIR,
    ensure_hall_pbr_library,
    export_glb,
    make_emissive_mat,
    make_orm_mat,
    make_real_glass_mat,
    reset_scene,
)

ROOT = os.path.normpath(os.path.join(SCRIPT_DIR, "..", ".."))
TEX_DIR = os.path.join(ROOT, "assets", "textures", "carton")
TMP = os.path.join(SCRIPT_DIR, "_pbr_cache")


# ---------------------------------------------------------------------------
# Helfer
# ---------------------------------------------------------------------------

def solid(name, rgb, **kw):
    """Einfarbiges Material, Farbe in sRGB wie man sie sieht (Blender rechnet linear)."""
    return make_solid_mat(name, tuple(c ** 2.2 for c in rgb), **kw)


def new_root(name):
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    return root


def lathe(pb, center_g, profile, mat, axis="y", seg=24, smooth=True):
    """Drehkoerper: profile = [(radius, hoehe), ...] entlang der Achse."""
    mid = pb._mid(mat)
    rings = []
    for r, h in profile:
        ring = []
        for k in range(seg):
            a = math.tau * k / seg
            u, v = r * math.cos(a), r * math.sin(a)
            if axis == "y":
                p = (center_g[0] + u, center_g[1] + h, center_g[2] + v)
            elif axis == "z":
                p = (center_g[0] + u, center_g[1] + v, center_g[2] + h)
            else:
                p = (center_g[0] + h, center_g[1] + u, center_g[2] + v)
            ring.append(pb.bm.verts.new(pb._local_b(Vector(p))))
        rings.append(ring)
    faces = []
    for a, b in zip(rings, rings[1:]):
        for k in range(seg):
            j = (k + 1) % seg
            try:
                f = pb.bm.faces.new((a[k], a[j], b[j], b[k]))
            except ValueError:
                continue
            f.material_index = mid
            f.smooth = smooth
            faces.append(f)
    for ring in (rings[0], rings[-1]):
        try:
            f = pb.bm.faces.new(ring)
            f.material_index = mid
            faces.append(f)
        except ValueError:
            pass
    bmesh.ops.recalc_face_normals(pb.bm, faces=faces)
    pb.bm.normal_update()
    pb._uv_box(faces, 0.2)


def quad(pb, pts_g, mat):
    """Viereck mit UV 0..1 (Reihenfolge: links unten, rechts unten, rechts oben, links oben)."""
    mid = pb._mid(mat)
    vs = [pb.bm.verts.new(pb._local_b(Vector(p))) for p in pts_g]
    f = pb.bm.faces.new(vs)
    f.material_index = mid
    for l, uv in zip(f.loops, ((0, 0), (1, 0), (1, 1), (0, 1))):
        l[pb.uv].uv = uv
    pb.bm.normal_update()
    return f


def decal_mat(name, rgba, rough=0.75):
    """Material mit Alphatextur fuer Aufdrucke und Aufkleber."""
    path = os.path.join(TMP, name + ".png")
    save_rgba(path, rgba)
    mat, nt, bsdf = _new_mat(name)
    t = nt.nodes.new("ShaderNodeTexImage")
    t.image = _load_img(path, "sRGB")
    nt.links.new(t.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(t.outputs["Alpha"], bsdf.inputs["Alpha"])
    bsdf.inputs["Roughness"].default_value = rough
    mat.surface_render_method = "BLENDED"
    return mat


def save_rgba(path, arr):
    import struct
    import zlib
    a = (np.clip(arr, 0, 1) * 255 + 0.5).astype(np.uint8)
    h, w = a.shape[:2]
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def dent(obj, amp, seed, cuts=4):
    """Leichte Beulen: grosse Flaechen unterteilen und mit weichem Rauschen verschieben."""
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    long_edges = [e for e in bm.edges if e.calc_length() > 0.10]
    bmesh.ops.subdivide_edges(bm, edges=long_edges, cuts=cuts, use_grid_fill=True)
    off = Vector((seed * 3.17, seed * 1.31, seed * 7.7))
    for v in bm.verts:
        w = obj.location + v.co
        n = noise.noise_vector(w * 7.0 + off)
        v.co += n * amp
    bm.normal_update()
    bm.to_mesh(obj.data)
    bm.free()


# ---------------------------------------------------------------------------
# Kartons
# ---------------------------------------------------------------------------

def gen_kraft():
    os.makedirs(TEX_DIR, exist_ok=True)
    s = 1024
    n1 = pt.fbm_tile(s, s, 10, 10, octaves=4, seed=611)
    fine = pt.fbm_tile(s, s, 120, 120, octaves=2, seed=613)
    fib = pt.fbm_tile(s, s, 24, 160, octaves=3, seed=617)
    yy = np.linspace(0.0, math.tau * 88.0, s, dtype=np.float32)[:, None]
    flute = np.broadcast_to(0.5 + 0.5 * np.sin(yy), (s, s))
    rng = np.random.default_rng(619)
    specks = (rng.random((s, s)) > 0.9975).astype(np.float32)
    specks = pt.blur_separable(specks, 1, wrap=True)
    v = 0.92 + (n1 - 0.5) * 0.14 + (fine - 0.5) * 0.06 + (fib - 0.5) * 0.09 + (flute - 0.5) * 0.008 - specks * 0.30
    alb = np.stack([np.clip(0.640 * v, 0, 1), np.clip(0.510 * v, 0, 1), np.clip(0.372 * v, 0, 1)], axis=-1)
    h = n1 * 0.34 + fine * 0.26 + fib * 0.34 + flute * 0.06
    ao = np.clip(0.95 + (flute - 0.5) * 0.06, 0.8, 1)
    rough = np.clip(0.86 + (fine - 0.5) * 0.12 - (n1 - 0.5) * 0.08, 0.62, 0.98)
    _save_rgb(os.path.join(TEX_DIR, "kraft_alb.png"), alb)
    pt.save_png(os.path.join(TEX_DIR, "kraft_nrm.png"), pt.height_to_normal(h, strength=1.7))
    pt.save_png(os.path.join(TEX_DIR, "kraft_orm.png"), pt.pack_orm(ao, rough, np.zeros((s, s), dtype=np.float32)))


def print_canvas(w, h):
    return np.zeros((h, w, 4), dtype=np.float32)


INK = np.array([0.09, 0.075, 0.06], dtype=np.float32)


def ink(c, mask_fn):
    m = np.zeros(c.shape[:2], dtype=np.float32)
    mask_fn(m)
    rng = np.random.default_rng(c.shape[0] * 7 + c.shape[1])
    wear = 0.80 + 0.20 * pt.fbm_tile(256, 256, 24, 24, octaves=3, seed=5)
    wear = np.tile(wear, (c.shape[0] // 256 + 1, c.shape[1] // 256 + 1))[:c.shape[0], :c.shape[1]]
    c[..., :3] = INK
    c[..., 3] = np.maximum(c[..., 3], m * wear * 0.92)


def text_w(t, sc):
    return len(t) * 6 * sc


def sym_arrows(m, x, y, s):
    for dx in (0, s * 0.62):
        cx = x + s * 0.22 + dx
        pt.draw_segment(m, cx, y + s * 0.30, cx, y + s * 0.90, s * 0.055)
        for k in range(int(s * 0.34)):
            pt.fill_rect(m, int(cx - k * 0.62), int(y + k), int(cx + k * 0.62) + 1, int(y + k) + 1, 1.0)
    pt.fill_rect(m, int(x), int(y + s * 0.93), int(x + s * 1.06), int(y + s * 1.0), 1.0)


def sym_glass(m, x, y, s):
    for k in range(int(s * 0.5)):
        t = k / (s * 0.5)
        hw = s * 0.26 * (1.0 - 0.75 * t ** 2)
        pt.fill_rect(m, int(x + s * 0.4 - hw), int(y + k), int(x + s * 0.4 + hw), int(y + k) + 1, 1.0)
    pt.fill_rect(m, int(x + s * 0.36), int(y + s * 0.5), int(x + s * 0.44), int(y + s * 0.9), 1.0)
    pt.fill_rect(m, int(x + s * 0.16), int(y + s * 0.9), int(x + s * 0.64), int(y + s), 1.0)
    # Sprung
    pt.draw_polyline(m, [(x + s * 0.44, y), (x + s * 0.34, y + s * 0.14), (x + s * 0.46, y + s * 0.22), (x + s * 0.36, y + s * 0.40)], max(1.5, s * 0.02), 0.0)


def sym_umbrella(m, x, y, s):
    cx, cy = x + s * 0.5, y + s * 0.45
    yy, xx = np.ogrid[:m.shape[0], :m.shape[1]]
    dome = ((xx - cx) ** 2 + (yy - cy) ** 2 <= (s * 0.42) ** 2) & (yy <= cy)
    for k in (-1, 0, 1):
        dome &= ((xx - (cx + k * s * 0.28)) ** 2 + (yy - cy) ** 2) > (s * 0.10) ** 2
    m[dome] = 1.0
    pt.draw_segment(m, cx, cy - s * 0.05, cx, y + s * 0.92, s * 0.03)
    pt.draw_polyline(m, [(cx, y + s * 0.92), (cx + s * 0.06, y + s * 0.98), (cx + s * 0.13, y + s * 0.90)], s * 0.03)
    for k in (-0.3, 0.0, 0.3):
        pt.draw_segment(m, cx + k * s, y - s * 0.14, cx + k * s - s * 0.03, y - s * 0.04, s * 0.022)


def sym_bolt(m, x, y, s):
    """Akku-Warnung: Dreieck mit Blitz."""
    for k in range(int(s)):
        hw = k * 0.55
        pt.fill_rect(m, int(x + s * 0.55 - hw), int(y + k), int(x + s * 0.55 + hw) + 1, int(y + k) + 1, 1.0)
    for k in range(int(s * 0.16), int(s * 0.90)):
        hw = max(0.0, (k - s * 0.16) * 0.55 - s * 0.03)
        pt.fill_rect(m, int(x + s * 0.55 - hw), int(y + k), int(x + s * 0.55 + hw) + 1, int(y + k) + 1, 0.0)
    pt.draw_polyline(m, [(x + s * 0.62, y + s * 0.34), (x + s * 0.46, y + s * 0.62), (x + s * 0.60, y + s * 0.62), (x + s * 0.48, y + s * 0.86)], s * 0.045)


def sym_recycle(m, x, y, s):
    cx, cy, r = x + s * 0.5, y + s * 0.55, s * 0.36
    for k in range(3):
        a0 = math.radians(-90 + 120 * k + 18)
        a1 = math.radians(-90 + 120 * k + 92)
        pts = [(cx + r * math.cos(a0 + (a1 - a0) * t / 8), cy + r * math.sin(a0 + (a1 - a0) * t / 8)) for t in range(9)]
        pt.draw_polyline(m, pts, s * 0.07)
        ex, ey = pts[-1]
        d = a1 + math.pi / 2
        for q in range(10):
            w = s * 0.13 * (1 - q / 10)
            px, py = ex + math.cos(d) * q * s * 0.018, ey + math.sin(d) * q * s * 0.018
            pt.draw_segment(m, px - math.cos(a1) * w, py - math.sin(a1) * w, px + math.cos(a1) * w, py + math.sin(a1) * w, s * 0.014)


def gen_print(name, kind_text, w_m, h_m, warn=False):
    """Aufdruck einer Seite, ohne Pappe (Alpha). Aufloesung ca. 900 px/m."""
    W, H = int(w_m * 900), int(h_m * 900)
    c = print_canvas(W, H)
    u = min(H, W)

    def draw(m):
        s = max(18, int(u * 0.26))
        y = H - s - int(u * 0.09)
        x = W - int(s * 1.25) - int(u * 0.08)
        sym_arrows(m, x, y, s)
        if W > s * 5:
            sym_glass(m, x - s * 1.15, y, s)
            sym_umbrella(m, x - s * 2.35, y, s)
        if warn and W > s * 5:
            sym_bolt(m, int(u * 0.10), y, s)
        elif W > s * 6:
            sym_recycle(m, int(u * 0.10), y, s)
        sc = max(2, int(u / 130))
        while text_w(kind_text, sc) > W * 0.62 and sc > 2:
            sc -= 1
        pt.draw_text(m, int(u * 0.14) + 14, int(u * 0.10), kind_text, 1.0, scale=sc)
        sc2 = max(1, sc // 2)
        pt.draw_text(m, int(u * 0.14) + 14, int(u * 0.10) + sc * 9, "CLOUDPARTS.DE", 1.0, scale=sc2)

    ink(c, draw)
    return decal_mat(name, c, 0.85)


def gen_label(name, seed):
    """Versandaufkleber: Barcode, Adressfeld, freies Feld fuer den Produktnamen."""
    W, H = 512, 340
    a = np.full((H, W, 3), 0.93, dtype=np.float32)
    k = np.array([0.06, 0.06, 0.07])
    pt.stroke_rect(a, 6, 6, W - 6, H - 6, k, 3)
    pt.fill_rect(a, 6, 6, W - 6, 46, np.array([0.12, 0.30, 0.52]))
    pt.draw_text(a, 20, 16, "CLOUD EXPRESS", np.array([0.96, 0.97, 0.98]), scale=3)
    pt.draw_text(a, 400, 20, "24H", np.array([0.98, 0.80, 0.22]), scale=3)
    pt.fill_rect(a, 6, 168, W - 6, 171, k)
    pt.draw_text(a, 20, 182, "AN: DATACENTER, TECHPARK RING 4", k, scale=2)
    rng = np.random.default_rng(seed)
    pt.draw_text(a, 20, 204, "SENDUNG DC%07d" % rng.integers(1000000, 9999999), k, scale=2)
    x = 20
    while x < 380:
        w = int(rng.integers(2, 8))
        if rng.random() > 0.42:
            pt.fill_rect(a, x, 232, x + w, 318, k)
        x += w
    for ry in range(14):
        for rx in range(14):
            if rng.random() > 0.5 or rx == 0 or ry == 13:
                pt.fill_rect(a, 408 + rx * 6, 232 + ry * 6, 414 + rx * 6, 238 + ry * 6, k)
    grime = pt.fbm_tile(512, 512, 10, 10, octaves=4, seed=seed)[:H, :W]
    a *= (0.95 + 0.07 * grime)[..., None]
    out = np.ones((H, W, 4), dtype=np.float32)
    out[..., :3] = a
    return decal_mat(name, out, 0.48)


def carton(kind, w, h, d, title, warn=False, pallet=False, straps=0, film=False, corners=False, skid=False, label=(0.20, 0.133), dents=0.0022):
    reset_scene()
    root = new_root("Carton_" + kind)
    kraft = solid("CT_Kraft", (0.62, 0.47, 0.31), rough=0.88)
    edge = solid("CT_Edge", (0.50, 0.37, 0.24), rough=0.95)
    tape = solid("CT_Tape", (0.72, 0.60, 0.42), rough=0.26, coat=0.5)
    strap = solid("CT_Strap", (0.07, 0.075, 0.085), rough=0.42)
    clip = solid("CT_Clip", (0.55, 0.57, 0.60), rough=0.32, metal=0.85)
    foam = solid("CT_Foam", (0.86, 0.87, 0.88), rough=0.92)
    corner = solid("CT_Corner", (0.58, 0.46, 0.33), rough=0.82)
    wood = solid("CT_Wood", (0.70, 0.58, 0.42), rough=0.86)
    nail = solid("CT_Nail", (0.35, 0.36, 0.38), rough=0.4, metal=0.8)

    y0 = 0.0
    ex = PartBuilder("Extras", origin_g=Vector((0, 0, 0)))
    used = False
    if pallet or skid:
        used = True
        pw, pd = w + 0.08, d + 0.08
        if pallet:
            for lz in (-pd * 0.42, 0.0, pd * 0.42):
                ex.box((0, 0.009, lz), (pw, 0.018, 0.075), wood, bevel=0.002)
                for lx in (-pw * 0.43, 0.0, pw * 0.43):
                    ex.box((lx, 0.042, lz), (0.085, 0.050, 0.075), wood, bevel=0.003)
            for lx in (-pw * 0.43, 0.0, pw * 0.43):
                ex.box((lx, 0.075, 0), (0.085, 0.016, pd), wood, bevel=0.002)
            for i in range(5):
                lx = -pw * 0.44 + pw * 0.88 * i / 4
                ex.box((lx, 0.091, 0), (0.092 if i % 2 == 0 else 0.066, 0.016, pd), wood, bevel=0.002)
                for lz in (-pd * 0.42, 0.0, pd * 0.42):
                    ex.cyl((lx, 0.0995, lz), 0.004, 0.004, 0.002, nail, axis_g="y", seg=8)
            y0 = 0.10
        else:
            for lx in (-pw * 0.34, pw * 0.34):
                ex.box((lx, 0.025, 0), (0.07, 0.05, pd), wood, bevel=0.003)
            ex.box((0, 0.056, 0), (pw, 0.012, pd), wood, bevel=0.002)
            y0 = 0.062
    t = 0.0045
    b = PartBuilder("Body", origin_g=Vector((0, 0, 0)))
    b.box((0, y0 + t / 2, 0), (w, t, d), kraft, bevel=0.0, uv_scale=0.62)
    for s in (-1, 1):
        b.box((0, y0 + h / 2, s * (d / 2 - t / 2)), (w, h, t), kraft, bevel=0.0, uv_scale=0.62)
        b.box((s * (w / 2 - t / 2), y0 + h / 2, 0), (t, h, d - t * 2), kraft, bevel=0.0, uv_scale=0.62)
    # Schaumpolster innen (beim Oeffnen sichtbar)
    for sx in (-1, 1):
        b.box((sx * (w / 2 - 0.035), y0 + h * 0.40, 0), (0.05, h * 0.72, d * 0.84), foam, bevel=0.004)
    b.box((0, y0 + 0.02, 0), (w * 0.82, 0.025, d * 0.84), foam, bevel=0.004)
    body = b.build(root)
    dent(body, dents, seed=len(kind) + 1.0)

    # Aufdruck auf allen vier Seiten, Aufkleber vorn und oben
    lb = PartBuilder("Print", origin_g=Vector((0, 0, 0)))
    pf = gen_print("CTP_" + kind + "_f", title, w, h, warn)
    ps = gen_print("CTP_" + kind + "_s", title, d, h, warn)
    e = dents * 1.0 + 0.0012
    lb_m = gen_label("CTL_" + kind, 100 + len(title))
    z = d / 2 + e
    quad(lb, [(-w / 2, y0, z), (w / 2, y0, z), (w / 2, y0 + h, z), (-w / 2, y0 + h, z)], pf)
    quad(lb, [(w / 2, y0, -z), (-w / 2, y0, -z), (-w / 2, y0 + h, -z), (w / 2, y0 + h, -z)], pf)
    x = w / 2 + e
    quad(lb, [(x, y0, d / 2), (x, y0, -d / 2), (x, y0 + h, -d / 2), (x, y0 + h, d / 2)], ps)
    quad(lb, [(-x, y0, -d / 2), (-x, y0, d / 2), (-x, y0 + h, d / 2), (-x, y0 + h, -d / 2)], ps)
    lw, lh = label
    z2 = z + 0.0012
    lx0 = -w / 2 + (0.07 if corners else 0.03) if w > 0.5 else -lw / 2
    ly0 = y0 + h * 0.5 - lh * 0.5 + (0.02 if h > 0.3 else 0.0)
    quad(lb, [(lx0, ly0, z2), (lx0 + lw, ly0, z2), (lx0 + lw, ly0 + lh, z2), (lx0, ly0 + lh, z2)], lb_m)
    lb.build(root)

    # Klappen: lange (F/B) aussen, kurze (L/R) 5 mm darunter. Ursprung = Knickkante.
    top = y0 + h
    for s, nm in ((1, "Flap_F"), (-1, "Flap_B")):
        o = Vector((0, top, s * (d / 2 - t / 2)))
        f = PartBuilder(nm, origin_g=o)
        f.box((0, top, s * (d / 2 - t / 2 - d / 4)), (w - 0.004, t, d / 2 - 0.002), kraft, bevel=0.0, uv_scale=0.62)
        dent(f.build(root), dents * 0.8, seed=s * 2.0 + 9, cuts=3)
    fl = min(w / 2 - 0.002, d / 2)
    for s, nm in ((1, "Flap_R"), (-1, "Flap_L")):
        o = Vector((s * (w / 2 - t / 2), top - 0.0055, 0))
        f = PartBuilder(nm, origin_g=o)
        f.box((s * (w / 2 - t / 2 - fl / 2), top - 0.0055, 0), (fl, t, d - 0.012), kraft, bevel=0.0, uv_scale=0.62)
        dent(f.build(root), dents * 0.6, seed=s * 3.0 + 4, cuts=3)
    tb = PartBuilder("Tape", origin_g=Vector((0, top, 0)))
    tb.box((0, top + t / 2 + 0.0026, 0), (w + 0.004, 0.0012, 0.052), tape, bevel=0.0)
    for s in (-1, 1):
        tb.box((s * (w / 2 + 0.0026), top - 0.035, 0), (0.0012, 0.08, 0.052), tape, bevel=0.0)
    tb.build(root)

    if straps:
        sp = PartBuilder("Straps", origin_g=Vector((0, 0, 0)))
        for i in range(straps):
            sx = 0.0 if straps == 1 else -w * 0.28 + w * 0.56 * i / (straps - 1)
            for s in (-1, 1):
                sp.box((sx, y0 + h / 2, s * (d / 2 + 0.005)), (0.016, h + 0.014, 0.0016), strap, bevel=0.0)
            sp.box((sx, top + 0.0082, 0), (0.016, 0.0016, d + 0.012), strap, bevel=0.0)
            sp.box((sx, top + 0.0095, d * 0.22), (0.022, 0.004, 0.034), clip, bevel=0.001)
        sp.build(root)
    if corners:
        used = True
        for sx in (-1, 1):
            for sz in (-1, 1):
                ex.box((sx * (w / 2 + 0.003), y0 + h / 2, sz * (d / 2 - 0.022)), (0.005, h - 0.01, 0.048), corner, bevel=0.001)
                ex.box((sx * (w / 2 - 0.022), y0 + h / 2, sz * (d / 2 + 0.003)), (0.048, h - 0.01, 0.005), corner, bevel=0.001)
    if used:
        ex.build(root)
    if film:
        fm = make_real_glass_mat("CT_Film", (0.96, 0.98, 1.0), alpha=0.09, rough=0.10, metal=0.0, coat=0.9)
        fp = PartBuilder("Film_Glass", origin_g=Vector((0, 0, 0)))
        fp.box((0, y0 + h / 2 - 0.006, 0), (w + 0.028, h - 0.02, d + 0.028), fm, bevel=0.012)
        dent(fp.build(root), 0.006, seed=3.3, cuts=6)
    export_glb(os.path.join(OUT_MODELS_DIR, "carton_%s.glb" % kind))


def build_cartons():
    gen_kraft()
    carton("server", 0.64, 0.20, 0.58, "SERVER 19 ZOLL")
    carton("build", 0.50, 0.24, 0.42, "BAUSATZ WERKBANK")
    carton("cooler", 0.62, 0.46, 0.54, "KLIMATECHNIK", corners=True, straps=1)
    carton("ups", 0.52, 0.44, 0.46, "NOTSTROM AKKU", warn=True, skid=True, straps=2)
    carton("strip", 0.70, 0.10, 0.17, "VERTEILERLEISTE", label=(0.13, 0.086), dents=0.0012)
    carton("deco", 0.60, 0.36, 0.52, "EINRICHTUNG", straps=1)
    carton("parcel", 0.42, 0.26, 0.32, "SAMMELPAKET", label=(0.17, 0.113))
    carton("pallet", 0.62, 0.36, 0.50, "RACK BAUSATZ", pallet=True, film=True, corners=True, straps=2)


# ---------------------------------------------------------------------------
# Altpapier-Container
# ---------------------------------------------------------------------------

def build_bin():
    lib = ensure_hall_pbr_library()
    reset_scene()
    root = new_root("PaperBin")
    blue = make_orm_mat("PB_Blue", lib["euro_blue"], normal_strength=0.5)
    grey = solid("PB_Grey", (0.36, 0.38, 0.40), rough=0.52)
    rub = make_orm_mat("PB_Rubber", lib["rubber_black"], normal_strength=0.6)
    galv = solid("PB_Galv", (0.66, 0.68, 0.70), rough=0.38, metal=0.85)
    b = PartBuilder("Body", origin_g=Vector((0, 0, 0)))
    # Konischer Korpus aus vier geneigten Platten mit Sicken
    w0, w1, d0, d1, y0, y1 = 1.10, 1.30, 0.78, 0.98, 0.20, 1.18
    mid = b._mid(grey)
    tt = 0.02

    def wall(p):
        quad_pts = [b.bm.verts.new(b._local_b(Vector(q))) for q in p]
        f = b.bm.faces.new(quad_pts)
        f.material_index = mid
        return f

    faces = []
    for out in (0.0, -tt):
        a0, a1, c0, c1 = w0 / 2 + out, w1 / 2 + out, d0 / 2 + out, d1 / 2 + out
        sides = [
            [(-a0, y0, c0), (a0, y0, c0), (a1, y1, c1), (-a1, y1, c1)],
            [(a0, y0, -c0), (-a0, y0, -c0), (-a1, y1, -c1), (a1, y1, -c1)],
            [(a0, y0, c0), (a0, y0, -c0), (a1, y1, -c1), (a1, y1, c1)],
            [(-a0, y0, -c0), (-a0, y0, c0), (-a1, y1, c1), (-a1, y1, -c1)],
        ]
        for p in sides:
            faces.append(wall(p if out == 0.0 else list(reversed(p))))
    b.bm.normal_update()
    b._uv_box(faces, 0.5)
    b.box((0, y0 + 0.01, 0), (w0, 0.02, d0), grey, bevel=0.004)
    for s in (-1, 1):
        b.box((0, y1 - 0.01, s * d1 / 2), (w1 + 0.07, 0.05, 0.06), grey, bevel=0.012)
        b.box((s * w1 / 2, y1 - 0.01, 0), (0.06, 0.05, d1 + 0.07), grey, bevel=0.012)
        for i in range(4):
            lx = -0.36 + 0.24 * i
            b.box((lx, 0.69, s * ((d0 + d1) / 4 + 0.008)), (0.05, 0.86, 0.024), grey, rot_g_deg=(s * 5.8, 0, 0), bevel=0.008)
        b.cyl((s * (w1 / 2 + 0.07), 0.92, 0.0), 0.016, 0.016, 0.30, galv, axis_g="z", seg=14)
        for sz in (-1, 1):
            b.cyl((s * 0.46, 0.085, sz * 0.30), 0.085, 0.085, 0.045, rub, axis_g="x", seg=24)
            b.cyl((s * 0.46, 0.085, sz * 0.30), 0.045, 0.045, 0.050, galv, axis_g="x", seg=18)
            b.box((s * 0.46, 0.16, sz * 0.30), (0.075, 0.09, 0.10), galv, bevel=0.004)
    c = print_canvas(512, 256)

    def draw(m):
        sym_recycle(m, 170, 20, 150)
        pt.draw_text(m, 110, 190, "ALTPAPIER", 1.0, scale=5)

    ink(c, draw)
    c[..., :3] = np.array([0.93, 0.95, 0.97])
    sign = decal_mat("PB_Sign", c, 0.5)
    b.build(root)
    s2 = PartBuilder("Sign", origin_g=Vector((0, 0, 0)))

    def fz(y):
        return d0 / 2 + (d1 - d0) / 2 * (y - y0) / (y1 - y0) + 0.030
    quad(s2, [(-0.34, 0.52, fz(0.52)), (0.34, 0.52, fz(0.52)), (0.34, 0.86, fz(0.86)), (-0.34, 0.86, fz(0.86))], sign)
    s2.build(root)
    # Deckel mit Drehachse hinten
    o = Vector((0, y1 + 0.02, -d1 / 2 - 0.02))
    l = PartBuilder("Lid", origin_g=o)
    n = 9
    st = []
    for i in range(n):
        a = math.pi * i / (n - 1)
        st.append((y1 + 0.02 + math.sin(a) * 0.13, -math.cos(a) * (d1 / 2 + 0.02)))
    prof = st + [(y - 0.018, zz * 0.975) for y, zz in reversed(st)]
    l.loft_x([(-w1 / 2 - 0.03, prof), (w1 / 2 + 0.03, prof)], blue)
    for sx in (-0.42, 0.42):
        l.cyl((sx, y1 + 0.02, -d1 / 2 - 0.02), 0.024, 0.024, 0.12, galv, axis_g="x", seg=16)
    l.box((0, y1 + 0.045, d1 / 2 + 0.04), (0.30, 0.03, 0.05), blue, bevel=0.010)
    l.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "paper_bin.glb"))


# ---------------------------------------------------------------------------
# Strom- und LAN-Leiste
# ---------------------------------------------------------------------------

def rail(pb, w, d, h, mat, y=0.0):
    """Stranggepresstes Profil mit Kabelnut und Fasen."""
    hd = d / 2
    prof = [
        (y + 0.004, -hd + 0.004), (y + 0.012, -hd), (y + h * 0.34, -hd), (y + h * 0.38, -hd + 0.004), (y + h * 0.52, -hd + 0.004), (y + h * 0.56, -hd),
        (y + h - 0.008, -hd), (y + h, -hd + 0.008), (y + h, hd - 0.008), (y + h - 0.008, hd), (y + h * 0.56, hd), (y + h * 0.52, hd - 0.004),
        (y + h * 0.38, hd - 0.004), (y + h * 0.34, hd), (y + 0.012, hd), (y + 0.004, hd - 0.004),
    ]
    pb.loft_x([(-w / 2, prof), (w / 2, prof)], mat, smooth=False)


def build_power_strip(lib):
    reset_scene()
    root = new_root("PowerStripRoot")
    alu = make_orm_mat("PS_Alu", lib["alu_anodized"], normal_strength=0.55)
    dark = make_orm_mat("PS_Dark", lib["steel_anthracite"], normal_strength=0.45)
    plast = solid("PS_Plastic", (0.035, 0.037, 0.042), rough=0.46)
    well = solid("PS_Well", (0.018, 0.019, 0.022), rough=0.6)
    brass = solid("PS_Brass", (0.88, 0.70, 0.30), rough=0.24, metal=0.95)
    chrome = solid("PS_Screw", (0.75, 0.77, 0.80), rough=0.22, metal=0.95)
    yellow = solid("PS_Yellow", (0.90, 0.66, 0.06), rough=0.42)
    white = solid("PS_White", (0.86, 0.87, 0.88), rough=0.5)
    glass = solid("PS_DispGlass", (0.006, 0.010, 0.014), rough=0.06, coat=0.8)
    sw = make_emissive_mat("PS_Switch", (0.95, 0.16, 0.10), strength=1.6)
    B = PartBuilder("PowerStrip_Mesh", origin_g=Vector((0, 0, 0)))
    rail(B, 0.60, 0.100, 0.042, alu)
    for s in (-1, 1):
        # Endkappen mit Schraublaschen fuer Boden und Wand
        B.box((s * 0.310, 0.023, 0), (0.024, 0.047, 0.106), plast, bevel=0.006)
        B.box((s * 0.337, 0.004, 0), (0.036, 0.008, 0.064), dark, bevel=0.003)
        for sz in (-0.018, 0.018):
            lathe(B, (s * 0.340, 0.008, sz), [(0.0065, 0.0), (0.0065, 0.003), (0.003, 0.004), (0.003, 0.0015)], chrome, seg=14)
    B.box((0, 0.0425, 0), (0.590, 0.003, 0.084), plast, bevel=0.0)
    for sz in (-0.045, 0.045):
        B.box((0, 0.0424, sz), (0.596, 0.0022, 0.0035), yellow, bevel=0.0)
    for i in range(6):
        sx = -0.20 + 0.08 * i
        # Schuko-Topf: Kragen, schraeger Rand, 12 mm tiefe Mulde
        lathe(B, (sx, 0.0, 0.0), [(0.0345, 0.043), (0.0345, 0.0545), (0.0325, 0.0565), (0.0290, 0.0565), (0.0270, 0.0550), (0.0262, 0.0442), (0.0262, 0.0442)], plast, seg=32)
        lathe(B, (sx, 0.0, 0.0), [(0.0262, 0.0442), (0.0262, 0.0444)], well, seg=32)
        for s in (-1, 1):
            lathe(B, (sx + s * 0.0095, 0.0444, 0.0), [(0.0046, 0.0), (0.0046, 0.0016), (0.0030, 0.0016), (0.0030, 0.0003)], chrome, seg=14)
            # Schutzkontaktfedern
            B.box((sx, 0.0500, s * 0.0248), (0.0075, 0.010, 0.0016), brass, bevel=0.0)
            B.box((sx, 0.0552, s * 0.0240), (0.0075, 0.0016, 0.0040), brass, rot_g_deg=(s * 24, 0, 0), bevel=0.0)
            # Fuehrungsnasen
            B.box((sx + s * 0.0255, 0.0500, 0.0), (0.003, 0.012, 0.0045), plast, bevel=0.0)
        led = make_emissive_mat("PS_Led%d" % i, (0.12, 0.92, 0.34), strength=0.1)
        B.box((sx, 0.0448, -0.0388), (0.012, 0.0024, 0.0040), led, bevel=0.0)
        B.box((sx, 0.0443, 0.0388), (0.016, 0.0010, 0.0050), white, bevel=0.0)
    # Schalterrahmen und Displayglas
    B.box((-0.2680, 0.0470, 0.0), (0.036, 0.009, 0.052), plast, bevel=0.0015)
    B.box((0.2660, 0.0475, 0.0), (0.052, 0.009, 0.060), dark, bevel=0.0015)
    B.box((0.2660, 0.0526, 0.0), (0.046, 0.0016, 0.052), glass, bevel=0.0)
    B.build(root)
    S = PartBuilder("Switch", origin_g=Vector((-0.268, 0.0535, 0.0)))
    S.loft_x([(x, [(0.0500, -0.019), (0.0585, -0.019), (0.0550, 0.0), (0.0585, 0.019), (0.0500, 0.019)]) for x in (-0.2795, -0.2565)], sw, smooth=False)
    S.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "power_strip.glb"))


def build_lan_strip(lib):
    reset_scene()
    root = new_root("LanStripRoot")
    body = make_orm_mat("LS_Steel", lib["steel_anthracite"], normal_strength=0.55)
    blue = make_orm_mat("LS_Blue", lib["euro_blue"], normal_strength=0.4)
    shield = solid("LS_Shield", (0.70, 0.72, 0.75), rough=0.26, metal=0.92)
    hole = solid("LS_Hole", (0.012, 0.013, 0.016), rough=0.75)
    gold = solid("LS_Gold", (0.92, 0.74, 0.32), rough=0.2, metal=0.95)
    chrome = solid("LS_Screw", (0.75, 0.77, 0.80), rough=0.22, metal=0.95)
    plast = solid("LS_Plastic", (0.035, 0.037, 0.042), rough=0.46)
    white = solid("LS_White", (0.86, 0.87, 0.88), rough=0.5)
    glass = solid("LS_DispGlass", (0.006, 0.010, 0.014), rough=0.06, coat=0.8)
    sw = make_emissive_mat("LS_Switch", (0.14, 0.60, 1.0), strength=1.6)
    B = PartBuilder("LanStrip_Mesh", origin_g=Vector((0, 0, 0)))
    B.box((0, 0.0245, 0), (0.585, 0.045, 0.122), body, bevel=0.004)
    B.box((0, 0.0030, 0), (0.560, 0.006, 0.106), plast, bevel=0.0015)
    for sz in (-0.055, 0.055):
        B.box((0, 0.0475, sz), (0.575, 0.003, 0.006), blue, bevel=0.0)
    for s in (-1, 1):
        B.box((s * 0.308, 0.004, 0), (0.036, 0.008, 0.080), body, bevel=0.002)
        for sz in (-0.026, 0.026):
            lathe(B, (s * 0.311, 0.008, sz), [(0.0065, 0.0), (0.0065, 0.003), (0.003, 0.004), (0.003, 0.0015)], chrome, seg=14)
        for k in range(7):
            B.box((-0.18 + 0.06 * k, 0.024, s * 0.0612), (0.040, 0.004, 0.0015), hole, bevel=0.0)
            B.box((-0.18 + 0.06 * k, 0.034, s * 0.0612), (0.040, 0.004, 0.0015), hole, bevel=0.0)
    for i in range(8):
        px = -0.21 + 0.06 * i
        # Geschirmte Buchse: Rahmen aus vier Waenden, 13 mm tief, 8 Goldkontakte, Rastnase
        for s in (-1, 1):
            B.box((px + s * 0.0150, 0.0505, 0.0), (0.0045, 0.013, 0.0345), shield, bevel=0.0008)
            B.box((px, 0.0505, s * 0.0150), (0.0345, 0.013, 0.0045), shield, bevel=0.0008)
        B.box((px, 0.0474, 0.0), (0.026, 0.0014, 0.026), hole, bevel=0.0)
        B.box((px, 0.0505, -0.0150), (0.0100, 0.0134, 0.0047), hole, bevel=0.0)
        for k in range(8):
            B.box((px - 0.0087 + 0.0025 * k, 0.0500, 0.0085), (0.0012, 0.0016, 0.0085), gold, rot_g_deg=(-24, 0, 0), bevel=0.0)
        lk = make_emissive_mat("LS_Link%d" % i, (0.12, 0.94, 0.36), strength=0.1)
        ac = make_emissive_mat("LS_Act%d" % i, (0.98, 0.66, 0.10), strength=0.1)
        B.box((px - 0.0100, 0.0480, -0.0265), (0.0065, 0.0022, 0.0040), lk, bevel=0.0)
        B.box((px + 0.0100, 0.0480, -0.0265), (0.0065, 0.0022, 0.0040), ac, bevel=0.0)
        B.box((px, 0.0475, 0.0285), (0.018, 0.0012, 0.0055), white, bevel=0.0)
    B.box((-0.2610, 0.0482, 0.0), (0.030, 0.004, 0.050), plast, bevel=0.0012)
    B.box((0.2580, 0.0480, 0.0), (0.050, 0.003, 0.064), plast, bevel=0.0012)
    B.box((0.2580, 0.0500, 0.0), (0.044, 0.0016, 0.056), glass, bevel=0.0)
    B.build(root)
    S = PartBuilder("Switch", origin_g=Vector((-0.261, 0.0510, 0.0)))
    S.loft_x([(x, [(0.0475, -0.017), (0.0560, -0.017), (0.0525, 0.0), (0.0560, 0.017), (0.0475, 0.017)]) for x in (-0.2700, -0.2520)], sw, smooth=False)
    S.build(root)
    export_glb(os.path.join(OUT_MODELS_DIR, "lan_strip.glb"))


# ---------------------------------------------------------------------------
# Notstrom
# ---------------------------------------------------------------------------

def add_fan(root, name, pos, r, mats, axis="z", blades=7):
    """Luefterrad als eigener Knoten (dreht um die lokale Z- bzw. Y-Achse)."""
    dark, ring = mats
    f = PartBuilder(name, origin_g=Vector(pos))
    lathe(f, pos, [(r * 0.26, -0.010), (r * 0.26, 0.010), (r * 0.10, 0.014)], dark, axis=axis, seg=18)
    for k in range(blades):
        a = math.tau * k / blades
        rr = r * 0.58
        if axis == "z":
            f.box((pos[0] + math.cos(a) * rr, pos[1] + math.sin(a) * rr, pos[2]), (r * 0.70, r * 0.34, 0.003), dark, rot_g_deg=(0, 0, math.degrees(a)), bevel=0.0)
        else:
            f.box((pos[0] + math.cos(a) * rr, pos[1], pos[2] + math.sin(a) * rr), (r * 0.70, 0.003, r * 0.34), dark, rot_g_deg=(0, -math.degrees(a), 0), bevel=0.0)
    f.build(root)


def fan_grille(pb, pos, r, mat, axis="z"):
    for k in range(1, 5):
        rr = r * k / 4.0
        lathe(pb, pos, [(rr - 0.0016, -0.0014), (rr + 0.0016, -0.0014), (rr + 0.0016, 0.0014), (rr - 0.0016, 0.0014), (rr - 0.0016, -0.0014)], mat, axis=axis, seg=32)
    for k in range(4):
        a = 45 * k
        if axis == "z":
            pb.box(pos, (r * 2, 0.004, 0.003), mat, rot_g_deg=(0, 0, a), bevel=0.0)
        else:
            pb.box(pos, (r * 2, 0.003, 0.004), mat, rot_g_deg=(0, a, 0), bevel=0.0)


def power_port(pb, x, y, z, M):
    """Gelbe CEE-Dose auf der Front, Oeffnung bei z."""
    pb.box((x, y, z - 0.030), (0.15, 0.15, 0.04), M["dark"], bevel=0.006)
    lathe(pb, (x, y, z), [(0.052, -0.028), (0.052, -0.002), (0.046, 0.0), (0.038, 0.0), (0.036, -0.018), (0.036, -0.018)], M["yellow"], axis="z", seg=28)
    lathe(pb, (x, y, z), [(0.036, -0.0185), (0.036, -0.0180)], M["hole"], axis="z", seg=28)
    for k in range(5):
        a = math.radians(90 + 72 * k)
        pb.cyl((x + 0.020 * math.cos(a), y + 0.020 * math.sin(a), z - 0.014), 0.0045, 0.0045, 0.012, M["brass"], axis_g="z", seg=10)
    pb.box((x, y + 0.076, z + 0.012), (0.10, 0.006, 0.075), M["yellow"], rot_g_deg=(38, 0, 0), bevel=0.002)


def ups_mats(lib):
    M = {
        "body": solid("UPS_Body", (0.25, 0.27, 0.30), rough=0.46, metal=0.10),
        "light": make_orm_mat("UPS_Light", lib["ral_light_grey"], normal_strength=0.5),
        "alu": make_orm_mat("UPS_Alu", lib["alu_anodized"], normal_strength=0.5),
        "dark": solid("UPS_Dark", (0.03, 0.032, 0.037), rough=0.5),
        "hole": solid("UPS_Hole", (0.010, 0.010, 0.012), rough=0.9),
        "yellow": solid("UPS_Yellow", (0.90, 0.66, 0.06), rough=0.44),
        "brass": solid("UPS_Brass", (0.88, 0.70, 0.30), rough=0.24, metal=0.95),
        "chrome": solid("UPS_Chrome", (0.76, 0.78, 0.81), rough=0.2, metal=0.95),
        "orange": solid("UPS_Orange", (0.90, 0.34, 0.05), rough=0.5),
        "red": solid("UPS_Red", (0.72, 0.05, 0.04), rough=0.4),
        "rubber": solid("UPS_Rubber", (0.04, 0.04, 0.042), rough=0.85),
        "glass": solid("UPS_DispGlass", (0.005, 0.009, 0.013), rough=0.05, coat=0.9),
        "cell": solid("UPS_Cell", (0.13, 0.27, 0.46), rough=0.48),
        "copper": solid("UPS_Copper", (0.80, 0.46, 0.26), rough=0.3, metal=0.95),
    }
    M["status"] = make_emissive_mat("UPS_Status", (0.14, 0.92, 0.36), strength=0.4)
    for i in range(10):
        M["bar%d" % i] = make_emissive_mat("UPS_Bar%d" % i, (0.14, 0.92, 0.36), strength=0.1)
    return M


def warn_sign(root, name, pos, size, text, ry=0.0):
    c = np.zeros((256, 256, 4), dtype=np.float32)
    yy, xx = np.mgrid[0:256, 0:256]
    tri = (yy > 24) & (yy < 206) & (np.abs(xx - 128) < (yy - 24) * 0.58)
    inner = (yy > 46) & (yy < 194) & (np.abs(xx - 128) < (yy - 46) * 0.58 - 4)
    c[tri] = (0.04, 0.04, 0.04, 1)
    c[inner] = (0.95, 0.75, 0.08, 1)
    m = np.zeros((256, 256), dtype=np.float32)
    pt.draw_polyline(m, [(140, 82), (112, 130), (136, 130), (116, 180)], 8)
    c[m > 0.5] = (0.04, 0.04, 0.04, 1)
    t = np.zeros((256, 256), dtype=np.float32)
    pt.draw_text(t, max(2, 128 - len(text) * 6), 218, text, 1.0, scale=2)
    c[t > 0.5] = (0.9, 0.9, 0.9, 1)
    mat = decal_mat("UPS_Sign_" + name, c, 0.5)
    s = PartBuilder("Sign_" + name, origin_g=Vector((0, 0, 0)))
    x, y, z = pos
    h = size / 2
    if abs(ry) < 1:
        quad(s, [(x - h, y - h, z), (x + h, y - h, z), (x + h, y + h, z), (x - h, y + h, z)], mat)
    else:
        sg = 1 if ry > 0 else -1
        quad(s, [(x, y - h, z + h * sg), (x, y - h, z - h * sg), (x, y + h, z - h * sg), (x, y + h, z + h * sg)], mat)
    s.build(root)


def panel(pb, x, y, z, M, w=0.30, bars=10):
    """Bedienfeld: Displayglas, Ladebalken aus 10 Segmenten, Status-LED, Taster."""
    pb.box((x, y, z + 0.004), (w, 0.21, 0.012), M["dark"], bevel=0.004)
    pb.box((x, y + 0.028, z + 0.0115), (w - 0.03, 0.118, 0.003), M["glass"], bevel=0.0)
    step = (w - 0.07) / bars
    for i in range(bars):
        pb.box((x - (w - 0.07) / 2 + step * (i + 0.5) - 0.012, y - 0.066, z + 0.0115), (step * 0.74, 0.020, 0.004), M["bar%d" % i], bevel=0.0)
    lathe(pb, (x + w / 2 - 0.022, y - 0.066, z + 0.010), [(0.0095, 0.0), (0.0095, 0.004), (0.006, 0.006)], M["status"], axis="z", seg=16)


def build_ups_small(lib):
    reset_scene()
    root = new_root("UpsSmall")
    M = ups_mats(lib)
    w, h, d = 0.46, 0.92, 0.62
    fz = d / 2
    B = PartBuilder("Body", origin_g=Vector((0, 0, 0)))
    for sx in (-1, 1):
        for sz in (-1, 1):
            B.cyl((sx * 0.17, 0.022, sz * 0.24), 0.022, 0.022, 0.044, M["rubber"], axis_g="x", seg=18)
            B.box((sx * 0.17, 0.048, sz * 0.24), (0.045, 0.02, 0.05), M["chrome"], bevel=0.002)
    B.box((0, 0.06 + (h - 0.06) / 2, -0.01), (w, h - 0.06, d - 0.04), M["body"], bevel=0.010)
    B.box((0, 0.50, fz - 0.022), (w - 0.02, 0.80, 0.03), M["light"], bevel=0.010)
    panel(B, 0.0, 0.76, fz - 0.008, M)
    # Lueftungsschlitze und drei Akkufaecher mit Griff
    for k in range(3):
        cy = 0.54 - 0.135 * k
        B.box((0, cy, fz - 0.005), (w - 0.06, 0.120, 0.010), M["body"], bevel=0.004)
        for j in range(5):
            B.box((-0.04, cy - 0.034 + 0.017 * j, fz + 0.0005), (0.25, 0.006, 0.003), M["hole"], bevel=0.0)
        for sy in (-0.030, 0.030):
            B.box((0.145, cy + sy, fz + 0.010), (0.012, 0.012, 0.022), M["chrome"], bevel=0.002)
        B.box((0.145, cy, fz + 0.021), (0.014, 0.076, 0.010), M["chrome"], bevel=0.004)
        m = make_emissive_mat("UPS_Mod%d" % k, (0.14, 0.92, 0.36), strength=0.1)
        B.box((-0.185, cy + 0.040, fz + 0.001), (0.012, 0.012, 0.004), m, bevel=0.0)
    power_port(B, 0.0, 0.13, fz + 0.015, M)
    for s in (-1, 1):
        for j in range(12):
            B.box((s * (w / 2 + 0.0008), 0.30 + 0.032 * j, -0.06), (0.0016, 0.012, 0.34), M["hole"], bevel=0.0)
        B.box((s * (w / 2 + 0.001), 0.80, 0.18), (0.002, 0.10, 0.10), M["orange"], bevel=0.0)
        B.box((s * 0.15, h + 0.014, 0.0), (0.02, 0.028, 0.03), M["chrome"], bevel=0.002)
    B.cyl((0, h + 0.028, 0.0), 0.011, 0.011, 0.30, M["rubber"], axis_g="x", seg=16)
    fp = (0.0, 0.62, -d / 2 + 0.006)
    lathe(B, (0, 0.62, -d / 2 + 0.010), [(0.105, -0.016), (0.105, 0.0), (0.098, 0.0), (0.098, -0.014)], M["dark"], axis="z", seg=32)
    fan_grille(B, (0, 0.62, -d / 2 - 0.008), 0.100, M["chrome"])
    B.build(root)
    add_fan(root, "Fan_0", fp, 0.095, (M["dark"], M["chrome"]))
    warn_sign(root, "a", (0.190, 0.882, fz - 0.0055), 0.046, "48 V DC")
    export_glb(os.path.join(OUT_MODELS_DIR, "ups_small.glb"))


def build_ups_cabinet(lib):
    reset_scene()
    root = new_root("UpsCabinet")
    M = ups_mats(lib)
    w, h, d = 0.80, 2.00, 0.80
    fz = d / 2
    B = PartBuilder("Body", origin_g=Vector((0, 0, 0)))
    B.box((0, 0.05, 0), (w, 0.10, d), M["dark"], bevel=0.006)
    B.box((0, 0.10 + (h - 0.10) / 2, -0.06), (w, h - 0.10, d - 0.12), M["body"], bevel=0.010)
    for s in (-1, 1):
        B.box((s * (w / 2 - 0.03), 0.10 + (h - 0.10) / 2, fz - 0.06), (0.06, h - 0.10, 0.12), M["body"], bevel=0.008)
        for j in range(18):
            B.box((s * (w / 2 + 0.0008), 0.40 + 0.045 * j, -0.10), (0.0016, 0.014, 0.42), M["hole"], bevel=0.0)
    B.box((0, h - 0.17, fz - 0.06), (w, 0.34, 0.12), M["body"], bevel=0.008)
    B.box((0, 0.20, fz - 0.06), (w, 0.20, 0.12), M["body"], bevel=0.008)
    panel(B, 0.0, h - 0.16, fz + 0.001, M, w=0.42)
    # Batteriefach hinter der Glastuer: 6 Einschuebe mit Zellen, Kupferschienen und Modul-LED
    B.box((0, 1.0, 0.06), (w - 0.12, 1.36, 0.01), M["hole"], bevel=0.0)
    for k in range(6):
        cy = 0.43 + 0.215 * k
        B.box((0, cy, 0.17), (w - 0.16, 0.180, 0.22), M["dark"], bevel=0.006)
        for c in range(4):
            cx = -0.225 + 0.15 * c
            B.box((cx, cy, 0.285), (0.125, 0.135, 0.02), M["cell"], bevel=0.006)
            for s in (-1, 1):
                B.cyl((cx + s * 0.035, cy + 0.046, 0.300), 0.010, 0.010, 0.012, M["brass"], axis_g="z", seg=12)
        B.box((0, cy + 0.046, 0.308), (0.56, 0.012, 0.004), M["copper"], bevel=0.0)
        B.box((0, cy - 0.078, 0.300), (0.30, 0.012, 0.018), M["chrome"], bevel=0.003)
        m = make_emissive_mat("UPS_Mod%d" % k, (0.14, 0.92, 0.36), strength=0.1)
        B.box((0.300, cy + 0.070, 0.290), (0.016, 0.016, 0.016), m, bevel=0.0)
    power_port(B, 0.0, 0.17, fz + 0.022, M)
    # Not-Aus
    B.box((0.30, h - 0.16, fz + 0.006), (0.085, 0.085, 0.014), M["yellow"], bevel=0.004)
    lathe(B, (0.30, h - 0.16, fz + 0.012), [(0.018, 0.0), (0.018, 0.012), (0.030, 0.014), (0.030, 0.024), (0.022, 0.030)], M["red"], axis="z", seg=24)
    # Dachluefter
    for sx in (-0.19, 0.19):
        lathe(B, (sx, h, -0.05), [(0.150, 0.0), (0.150, 0.030), (0.140, 0.030), (0.140, 0.002)], M["dark"], axis="y", seg=36)
        fan_grille(B, (sx, h + 0.030, -0.05), 0.142, M["chrome"], axis="y")
    for s in (-1, 1):
        lathe(B, (s * 0.33, h, 0.28), [(0.012, 0.0), (0.012, 0.02), (0.026, 0.024), (0.026, 0.034)], M["chrome"], axis="y", seg=16)
    B.build(root)
    for i, sx in enumerate((-0.19, 0.19)):
        add_fan(root, "Fan_%d" % i, (sx, h + 0.014, -0.05), 0.135, (M["dark"], M["chrome"]), axis="y")
    # Glastuer mit Rahmen
    D = PartBuilder("Door", origin_g=Vector((0, 0, 0)))
    for s in (-1, 1):
        D.box((s * (w / 2 - 0.085), 1.0, fz - 0.015), (0.05, 1.40, 0.022), M["alu"], bevel=0.004)
        D.box((0, 1.0 + s * 0.68, fz - 0.015), (w - 0.12, 0.05, 0.022), M["alu"], bevel=0.004)
    D.box((w / 2 - 0.085, 1.0, fz + 0.012), (0.022, 0.17, 0.030), M["chrome"], bevel=0.006)
    D.build(root)
    gm = make_real_glass_mat("UPS_DoorGlass", (0.20, 0.26, 0.32), alpha=0.10, rough=0.03)
    G = PartBuilder("Door_Glass", origin_g=Vector((0, 0, 0)))
    G.box((0, 1.0, fz - 0.016), (w - 0.21, 1.31, 0.006), gm, bevel=0.0)
    G.build(root)
    warn_sign(root, "a", (-0.30, h - 0.16, fz + 0.003), 0.10, "400 V")
    warn_sign(root, "b", (w / 2 + 0.003, 1.55, 0.18), 0.16, "BATTERIE", ry=90)
    export_glb(os.path.join(OUT_MODELS_DIR, "ups_cabinet.glb"))


def build_ups_container(lib):
    reset_scene()
    root = new_root("UpsContainer")
    M = ups_mats(lib)
    w, h, d = 2.00, 2.20, 1.30
    fz, hx = d / 2, w / 2
    B = PartBuilder("Body", origin_g=Vector((0, 0, 0)))
    # Rahmen und Eckbeschlaege
    for sx in (-1, 1):
        for sz in (-1, 1):
            B.box((sx * (hx - 0.05), h / 2 + 0.04, sz * (fz - 0.05)), (0.10, h - 0.08, 0.10), M["body"], bevel=0.010)
            for yy in (0.06, h + 0.02):
                B.box((sx * (hx - 0.055), yy, sz * (fz - 0.055)), (0.13, 0.12, 0.13), M["dark"], bevel=0.012)
    for yy in (0.10, h - 0.02):
        for sz in (-1, 1):
            B.box((0, yy, sz * (fz - 0.04)), (w - 0.2, 0.10, 0.08), M["body"], bevel=0.008)
        for sx in (-1, 1):
            B.box((sx * (hx - 0.04), yy, 0), (0.08, 0.10, d - 0.2), M["body"], bevel=0.008)
    B.box((0, h + 0.005, 0), (w - 0.14, 0.03, d - 0.14), M["light"], bevel=0.004)
    B.box((0, 0.09, 0), (w - 0.14, 0.03, d - 0.14), M["dark"], bevel=0.0)

    # Trapez-Wellblech hinten und an den Seiten
    def corr_z(zc, sgn, x0, x1, y0, y1):
        n = int((x1 - x0) / 0.13)
        st = (x1 - x0) / n
        for i in range(n):
            cx = x0 + st * (i + 0.5)
            B.box((cx - st * 0.25, (y0 + y1) / 2, zc), (st * 0.46, y1 - y0, 0.02), M["light"], bevel=0.0)
            B.box((cx + st * 0.25, (y0 + y1) / 2, zc - sgn * 0.028), (st * 0.46, y1 - y0, 0.02), M["light"], bevel=0.0)
            for k in (-0.02, 0.48):
                B.box((cx + st * k, (y0 + y1) / 2, zc - sgn * 0.014), (0.016, y1 - y0, 0.034), M["light"], rot_g_deg=(0, 34 * (1 if k < 0 else -1), 0), bevel=0.0)

    corr_z(-fz + 0.035, -1, -hx + 0.09, hx - 0.09, 0.14, h - 0.06)
    for sx in (-1, 1):
        n = 8
        st = (d - 0.18) / n
        for i in range(n):
            cz = -d / 2 + 0.09 + st * (i + 0.5)
            B.box((sx * (hx - 0.035 - (0.026 if i % 2 else 0.0)), h / 2 + 0.04, cz), (0.02, h - 0.20, st * 0.96), M["light"], bevel=0.0)
    # Doppeltuer vorn mit Drehstangen
    for s in (-1, 1):
        cx = s * 0.415
        B.box((cx, h / 2 + 0.04, fz - 0.030), (0.80, h - 0.24, 0.035), M["light"], bevel=0.006)
        B.box((cx, h / 2 + 0.04, fz - 0.008), (0.66, h - 0.44, 0.012), M["light"], bevel=0.008)
        for k in (-0.20, 0.22):
            xx = cx + s * k
            if abs(xx) < 0.12:
                xx = s * 0.13
            B.cyl((xx, h / 2 + 0.04, fz + 0.016), 0.013, 0.013, h - 0.22, M["chrome"], axis_g="y", seg=14)
            for yy in (0.36, 1.1, 1.86):
                B.box((xx, yy, fz + 0.012), (0.06, 0.035, 0.032), M["dark"], bevel=0.004)
            B.box((xx + s * 0.07, 1.02, fz + 0.030), (0.16, 0.026, 0.012), M["chrome"], bevel=0.004)
        for yy in (0.40, 1.14, 1.88):
            B.cyl((s * (hx - 0.11), yy, fz + 0.004), 0.018, 0.018, 0.12, M["dark"], axis_g="y", seg=14)
    for k in range(6):
        B.box((-0.415, 1.66 + 0.035 * k, fz + 0.0005), (0.42, 0.014, 0.004), M["hole"], bevel=0.0)
    # Streifen
    B.box((0, 0.60, fz + 0.0005), (1.62, 0.09, 0.003), M["orange"], bevel=0.0)
    panel(B, 0.415, 1.50, fz + 0.001, M, w=0.42)
    for k in range(8):
        m = make_emissive_mat("UPS_Mod%d" % k, (0.14, 0.92, 0.36), strength=0.1)
        B.box((-0.415 - 0.14 + 0.04 * k, 1.50, fz + 0.002), (0.022, 0.022, 0.006), m, bevel=0.0)
    power_port(B, 0.0, 0.22, fz + 0.030, M)
    # Klimageraet an der rechten Seite
    B.box((hx + 0.10, 1.35, 0.0), (0.22, 0.95, 0.74), M["light"], bevel=0.014)
    for yy in (1.12, 1.58):
        lathe(B, (hx + 0.205, yy, 0.0), [(0.185, 0.0), (0.185, 0.012), (0.172, 0.012), (0.172, -0.02)], M["dark"], axis="x", seg=36)
    for k in range(9):
        B.box((hx + 0.10, 0.92 + 0.1 * k, 0.3725), (0.16, 0.05, 0.004), M["hole"], bevel=0.0)
    # Kabelkanal und Abgasventil aufs Dach
    for sx in (-0.5, 0.5):
        lathe(B, (sx, h + 0.02, -0.2), [(0.10, 0.0), (0.10, 0.10), (0.15, 0.12), (0.15, 0.16), (0.05, 0.21)], M["alu"], axis="y", seg=28)
    lathe(B, (0.0, h + 0.02, 0.30), [(0.05, 0.0), (0.05, 0.03), (0.04, 0.03)], M["dark"], axis="y", seg=20)
    B.build(root)
    bc = make_emissive_mat("UPS_Beacon", (1.0, 0.50, 0.06), strength=0.2)
    L = PartBuilder("Beacon", origin_g=Vector((0.0, h + 0.05, 0.30)))
    lathe(L, (0.0, h + 0.05, 0.30), [(0.040, 0.0), (0.042, 0.05), (0.034, 0.085), (0.012, 0.098)], bc, axis="y", seg=24)
    L.build(root)
    for i, yy in enumerate((1.12, 1.58)):
        f = PartBuilder("FanX_%d" % i, origin_g=Vector((hx + 0.196, yy, 0.0)))
        p = (hx + 0.196, yy, 0.0)
        lathe(f, p, [(0.045, -0.010), (0.045, 0.010), (0.02, 0.014)], M["dark"], axis="x", seg=18)
        for k in range(6):
            a = math.tau * k / 6
            f.box((p[0], p[1] + math.cos(a) * 0.10, p[2] + math.sin(a) * 0.10), (0.003, 0.12, 0.055), M["dark"], rot_g_deg=(math.degrees(a), 0, 0), bevel=0.0)
        f.build(root)
    warn_sign(root, "a", (-0.62, 1.50 - 0.28, fz + 0.004), 0.22, "HOCHVOLT")
    warn_sign(root, "b", (-hx - 0.004, 1.4, 0.0), 0.34, "BATTERIE", ry=-90)
    export_glb(os.path.join(OUT_MODELS_DIR, "ups_container.glb"))


def main():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    todo = args or ["cartons", "bin", "strips", "ups"]
    if "cartons" in todo:
        build_cartons()
    if "bin" in todo:
        build_bin()
    if "strips" in todo:
        lib = ensure_hall_pbr_library()
        build_power_strip(lib)
        build_lan_strip(lib)
    if "ups" in todo:
        lib = ensure_hall_pbr_library()
        build_ups_small(lib)
        build_ups_cabinet(lib)
        build_ups_container(lib)
    print("FERTIG", todo)


if __name__ == "__main__":
    main()
