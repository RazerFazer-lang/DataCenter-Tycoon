"""Prozeduraler PBR-Textur-Generator (Albedo, Normal, ORM) fuer DataCenter Tycoon Hardware-Modelle.

Reines NumPy + stdlib (zlib/struct) — laeuft direkt im Blender-5.2-Python ohne externe Pakete.
Erzeugt gestochen scharfe 2K-Mainboard-Platinen (echte Leiterbahnen, Bestueckungsdruck, Loetstopplack,
Durchkontaktierungen, Kontakt-AO), SAS-Backplane, gebuerstetes Serverblech, Waben-Lochblech,
80-PLUS-Netzteil-Typenschilder, ESD-Matte mit Raster/Logo, Industrie-Werkbank, gesleevte Kabel,
CPU-Lasergravur und Enterprise-Bauteil-Etiketten.
"""

import math
import os
import struct
import zlib
import numpy as np

# ---------------------------------------------------------------------------
# Schneller PNG-Export aus NumPy-Arrays (uint8, HxWx3 oder HxWx4)
# ---------------------------------------------------------------------------

def _png_chunk(chunk_type: bytes, data: bytes) -> bytes:
    c = chunk_type + data
    return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)


def save_png(path: str, arr: np.ndarray) -> None:
    arr = np.ascontiguousarray(arr, dtype=np.uint8)
    h, w, ch = arr.shape
    color_type = 2 if ch == 3 else 6
    # Filtertyp 0 (None) vor jeder Zeile
    raw = np.empty((h, w * ch + 1), dtype=np.uint8)
    raw[:, 0] = 0
    raw[:, 1:] = arr.reshape(h, w * ch)
    comp = zlib.compress(raw.tobytes(), level=6)
    ihdr = struct.pack(">IIBBBBB", w, h, 8, color_type, 0, 0, 0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(_png_chunk(b"IHDR", ihdr))
        f.write(_png_chunk(b"IDAT", comp))
        f.write(_png_chunk(b"IEND", b""))


# ---------------------------------------------------------------------------
# Hilfsfunktionen: Rauschen, Filter, Normal-Map, Vektor-Zeichnen, 5x7-Schrift
# ---------------------------------------------------------------------------

def _tile_noise(h: int, w: int, gy: int, gx: int, seed: int) -> np.ndarray:
    """Nahtlos kachelbares bilineares Wertrauschen (0..1) per NumPy."""
    rng = np.random.default_rng(seed)
    grid = rng.random((gy, gx), dtype=np.float32)
    ys = np.linspace(0, gy, h, endpoint=False, dtype=np.float32)
    xs = np.linspace(0, gx, w, endpoint=False, dtype=np.float32)
    y0 = np.floor(ys).astype(np.int32)
    x0 = np.floor(xs).astype(np.int32)
    ty = ys - y0
    tx = xs - x0
    # Smoothstep
    ty = ty * ty * (3.0 - 2.0 * ty)
    tx = tx * tx * (3.0 - 2.0 * tx)
    y1 = (y0 + 1) % gy
    x1 = (x0 + 1) % gx
    c00 = grid[y0[:, None], x0[None, :]]
    c10 = grid[y0[:, None], x1[None, :]]
    c01 = grid[y1[:, None], x0[None, :]]
    c11 = grid[y1[:, None], x1[None, :]]
    top = c00 * (1.0 - tx[None, :]) + c10 * tx[None, :]
    bot = c01 * (1.0 - tx[None, :]) + c11 * tx[None, :]
    return top * (1.0 - ty[:, None]) + bot * ty[:, None]


def fbm_tile(h: int, w: int, base_y: int, base_x: int, octaves: int = 4, seed: int = 1) -> np.ndarray:
    out = np.zeros((h, w), dtype=np.float32)
    amp = 1.0
    norm = 0.0
    for o in range(octaves):
        gy = min(h, base_y * (1 << o))
        gx = min(w, base_x * (1 << o))
        out += amp * _tile_noise(h, w, gy, gx, seed + o * 97)
        norm += amp
        amp *= 0.5
    return out / norm


def blur_separable(img: np.ndarray, radius: int, wrap: bool = False) -> np.ndarray:
    """Schneller separabler Gauss-Weichzeichner (2D float32)."""
    if radius <= 0:
        return img
    xs = np.arange(-radius, radius + 1, dtype=np.float32)
    sigma = max(radius * 0.45, 0.8)
    k = np.exp(-0.5 * (xs / sigma) ** 2)
    k /= k.sum()
    pad_mode = "wrap" if wrap else "edge"
    tmp = np.pad(img, ((0, 0), (radius, radius)), mode=pad_mode)
    out_x = np.zeros_like(img)
    for i, w in enumerate(k):
        out_x += w * tmp[:, i:i + img.shape[1]]
    tmp = np.pad(out_x, ((radius, radius), (0, 0)), mode=pad_mode)
    out = np.zeros_like(img)
    for i, w in enumerate(k):
        out += w * tmp[i:i + img.shape[0], :]
    return out


def height_to_normal(height: np.ndarray, strength: float = 2.0, wrap: bool = True) -> np.ndarray:
    """Konvertiert ein Hoehenfeld (float32, 0..1) in eine OpenGL-Normalmap (uint8, HxWx3)."""
    if wrap:
        dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
        dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    else:
        p = np.pad(height, 1, mode="edge")
        dx = (p[1:-1, 2:] - p[1:-1, :-2]) * 0.5
        dy = (p[2:, 1:-1] - p[:-2, 1:-1]) * 0.5
    # OpenGL: +X rechts, +Y oben (also -dy im Bildkoordinatensystem), +Z heraus
    nx = -dx * strength
    ny = dy * strength
    nz = np.ones_like(nx)
    inv = 1.0 / np.sqrt(nx * nx + ny * ny + nz * nz + 1e-12)
    nx = (nx * inv * 0.5 + 0.5) * 255.0
    ny = (ny * inv * 0.5 + 0.5) * 255.0
    nz = (nz * inv * 0.5 + 0.5) * 255.0
    return np.clip(np.stack([nx, ny, nz], axis=-1), 0, 255).astype(np.uint8)


def pack_orm(ao: np.ndarray, rough: np.ndarray, metal: np.ndarray) -> np.ndarray:
    return np.clip(np.stack([ao, rough, metal], axis=-1) * 255.0, 0, 255).astype(np.uint8)


# 5x7 Bitmap-Schrift fuer gestochen scharfen Bestueckungsdruck und Typenschilder
FONT_5X7 = {
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
    "G": ["01111", "10000", "10000", "10111", "10001", "10001", "01110"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["01110", "00100", "00100", "00100", "00100", "00100", "01110"],
    "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
    "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
    "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
    "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
    "0": ["01110", "10011", "10101", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["01110", "10000", "11110", "10001", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "_": ["00000", "00000", "00000", "00000", "00000", "00000", "11111"],
    ".": ["00000", "00000", "00000", "00000", "00000", "01100", "01100"],
    ":": ["00000", "01100", "01100", "00000", "01100", "01100", "00000"],
    "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
    "+": ["00000", "00100", "00100", "11111", "00100", "00100", "00000"],
    "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
    " ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
}


def draw_text(canvas: np.ndarray, x: int, y: int, text: str, color, scale: int = 2, vertical: bool = False):
    """Zeichnet gestochen scharfen Text auf canvas (HxWx3 float32 oder HxW float32)."""
    text = text.upper()
    h, w = canvas.shape[:2]
    cursor = 0
    for ch in text:
        glyph = FONT_5X7.get(ch, FONT_5X7[" "])
        for ry, row in enumerate(glyph):
            for rx, bit in enumerate(row):
                if bit != "1":
                    continue
                if vertical:
                    px0 = x + ry * scale
                    py0 = y - (cursor + rx) * scale - scale
                else:
                    px0 = x + (cursor + rx) * scale
                    py0 = y + ry * scale
                px1 = min(w, px0 + scale)
                py1 = min(h, py0 + scale)
                px0 = max(0, px0)
                py0 = max(0, py0)
                if px0 < px1 and py0 < py1:
                    canvas[py0:py1, px0:px1] = color
        cursor += 6


def fill_rect(canvas: np.ndarray, x0: int, y0: int, x1: int, y1: int, color):
    h, w = canvas.shape[:2]
    xa, xb = max(0, min(x0, x1)), min(w, max(x0, x1))
    ya, yb = max(0, min(y0, y1)), min(h, max(y0, y1))
    if xa < xb and ya < yb:
        canvas[ya:yb, xa:xb] = color


def stroke_rect(canvas: np.ndarray, x0: int, y0: int, x1: int, y1: int, color, thickness: int = 2):
    xa, xb = min(x0, x1), max(x0, x1)
    ya, yb = min(y0, y1), max(y0, y1)
    fill_rect(canvas, xa, ya, xb, ya + thickness, color)
    fill_rect(canvas, xa, yb - thickness, xb, yb, color)
    fill_rect(canvas, xa, ya, xa + thickness, yb, color)
    fill_rect(canvas, xb - thickness, ya, xb, yb, color)


def draw_circle(canvas: np.ndarray, cx: float, cy: float, r: float, color, inner_r: float = 0.0):
    h, w = canvas.shape[:2]
    x0 = max(0, int(math.floor(cx - r - 1)))
    x1 = min(w, int(math.ceil(cx + r + 2)))
    y0 = max(0, int(math.floor(cy - r - 1)))
    y1 = min(h, int(math.ceil(cy + r + 2)))
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.ogrid[y0:y1, x0:x1]
    d2 = (xx - cx) ** 2 + (yy - cy) ** 2
    mask = d2 <= r * r
    if inner_r > 0.0:
        mask &= d2 >= inner_r * inner_r
    canvas[y0:y1, x0:x1][mask] = color


def draw_segment(mask_arr: np.ndarray, x0: float, y0: float, x1: float, y1: float, half_w: float, value: float = 1.0):
    """Zeichnet ein anti-aliastes Liniensegment auf eine 2D-Float-Maske (max-blend)."""
    h, w = mask_arr.shape
    pad = half_w + 1.5
    xa = max(0, int(math.floor(min(x0, x1) - pad)))
    xb = min(w, int(math.ceil(max(x0, x1) + pad)))
    ya = max(0, int(math.floor(min(y0, y1) - pad)))
    yb = min(h, int(math.ceil(max(y0, y1) + pad)))
    if xa >= xb or ya >= yb:
        return
    yy, xx = np.mgrid[ya:yb, xa:xb].astype(np.float32)
    dx, dy = x1 - x0, y1 - y0
    l2 = dx * dx + dy * dy
    if l2 < 1e-6:
        dist = np.sqrt((xx - x0) ** 2 + (yy - y0) ** 2)
    else:
        t = np.clip(((xx - x0) * dx + (yy - y0) * dy) / l2, 0.0, 1.0)
        px = x0 + t * dx
        py = y0 + t * dy
        dist = np.sqrt((xx - px) ** 2 + (yy - py) ** 2)
    alpha = np.clip(half_w + 0.8 - dist, 0.0, 1.0) * value
    sub = mask_arr[ya:yb, xa:xb]
    np.maximum(sub, alpha, out=sub)


def draw_polyline(mask_arr: np.ndarray, pts, half_w: float, value: float = 1.0):
    for a, b in zip(pts[:-1], pts[1:]):
        draw_segment(mask_arr, a[0], a[1], b[0], b[1], half_w, value)


def add_ao_box(ao: np.ndarray, x0: int, y0: int, x1: int, y1: int, strength: float = 0.45):
    h, w = ao.shape
    xa, xb = max(0, min(x0, x1)), min(w, max(x0, x1))
    ya, yb = max(0, min(y0, y1)), min(h, max(y0, y1))
    if xa < xb and ya < yb:
        ao[ya:yb, xa:xb] = np.minimum(ao[ya:yb, xa:xb], 1.0 - strength)


# ---------------------------------------------------------------------------
# 1. Server-Mainboard 2K PBR (Enterprise Gruen & AI-Workstation Mattschwarz)
# ---------------------------------------------------------------------------

def _build_mainboard_arrays(variant: str = "green", damaged: bool = False) -> dict:
    """Erzeugt 2048x2048 Albedo, Normal und ORM Arrays fuer part_mainboard / part_mainboard_ai."""

    W, H = 2048, 2048
    x_min, x_max = -0.29, 0.25
    z_min, z_max = -0.24, 0.24

    def to_px(x: float, z: float):
        px = (x - x_min) / (x_max - x_min) * (W - 1)
        py = (z - z_min) / (z_max - z_min) * (H - 1)
        return px, py

    def to_ipx(x: float, z: float):
        px, py = to_px(x, z)
        return int(round(px)), int(round(py))

    # Basis-Loetstopplack + feine FR-4 Glasfaser-Webstruktur
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    weave = 0.5 + 0.25 * np.sin(xx * (2.0 * math.pi / 6.0)) * np.sin(yy * (2.0 * math.pi / 6.0)) \
            + 0.25 * np.sin((xx + yy) * (2.0 * math.pi / 10.0))
    micro = fbm_tile(H, W, 32, 32, octaves=4, seed=11 if variant == "green" else 23)

    if variant == "green":
        # Authentisches tiefes Enterprise-Server-Smaragdgruen
        base_col = np.array([0.048, 0.228, 0.114], dtype=np.float32)
        plane_col = np.array([0.078, 0.305, 0.154], dtype=np.float32)
        trace_col = np.array([0.150, 0.455, 0.232], dtype=np.float32)
        silk_col = np.array([0.90, 0.92, 0.89], dtype=np.float32)
    else:
        # Mattschwarzes AI-Workstation-PCB mit feinem Anthrazit-Kupferschimmer
        base_col = np.array([0.045, 0.050, 0.058], dtype=np.float32)
        plane_col = np.array([0.075, 0.082, 0.094], dtype=np.float32)
        trace_col = np.array([0.160, 0.175, 0.198], dtype=np.float32)
        silk_col = np.array([0.86, 0.88, 0.91], dtype=np.float32)

    albedo = np.empty((H, W, 3), dtype=np.float32)
    for c in range(3):
        albedo[:, :, c] = base_col[c] * (0.90 + 0.14 * weave + 0.08 * (micro - 0.5))

    height = 0.45 + 0.025 * weave + 0.015 * micro
    rough = np.full((H, W), 0.48 if variant == "green" else 0.52, dtype=np.float32) + 0.04 * (micro - 0.5)
    metal = np.full((H, W), 0.03, dtype=np.float32)

    # Kupfer-Masseflaechen (subtile hellere Zonen unter Loetstopplack)
    plane_mask = np.zeros((H, W), dtype=np.float32)
    for x0, z0, x1, z1 in [
        (-0.26, -0.20, 0.22, 0.20),
        (-0.14, -0.15, 0.02, 0.06),
        (0.02, -0.11, 0.17, 0.05),
        (-0.24, -0.09, -0.13, 0.18),
        (0.16, 0.03, 0.22, 0.13),
    ]:
        ix0, iy0 = to_ipx(x0, z0)
        ix1, iy1 = to_ipx(x1, z1)
        plane_mask[iy0:iy1, ix0:ix1] = 1.0
    # Isolations-Kanaele zwischen Power-Planes
    for x0, z0, x1, z1 in [
        (0.008, -0.21, 0.014, 0.21),
        (-0.145, -0.21, -0.139, 0.21),
        (-0.27, 0.062, 0.23, 0.068),
        (-0.27, -0.118, 0.23, -0.112),
    ]:
        ix0, iy0 = to_ipx(x0, z0)
        ix1, iy1 = to_ipx(x1, z1)
        plane_mask[iy0:iy1, ix0:ix1] = 0.0
    plane_mask = blur_separable(plane_mask, 2, wrap=False)
    for c in range(3):
        albedo[:, :, c] = albedo[:, :, c] * (1.0 - plane_mask * 0.45) + plane_col[c] * (plane_mask * 0.45)
    height += plane_mask * 0.025
    rough -= plane_mask * 0.05

    # Echte geroutete Kupfer-Bus-Leiterbahnen (CPU <-> DIMM, CPU <-> PCIe, CPU <-> VRM, PCH <-> SATA/M.2/IO)
    trace_mask = np.zeros((H, W), dtype=np.float32)

    def add_trace(pts_world, width_px=2.2):
        pts_px = [to_px(x, z) for x, z in pts_world]
        draw_polyline(trace_mask, pts_px, width_px * 0.5, 1.0)

    # 1) CPU (-0.07, -0.01) -> 8x DDR5 DIMM Bank (0.027..0.153, z -0.10..0.04): 24 parallele Datenbusse mit 45-Grad-Knick
    for k in range(24):
        zt = -0.068 + k * 0.0048
        bend_x = -0.002 + (k % 4) * 0.004
        add_trace([(-0.020, zt), (bend_x, zt), (bend_x + 0.014, zt - 0.014), (0.158, zt - 0.014)], width_px=2.0)

    # 2) CPU -> PCIe x16 (-0.21, -0.10..0.06) & PCIe x8 (-0.266, 0.01..0.11): 18 Differential-Paare
    for k in range(18):
        zt = -0.064 + k * 0.0062
        mx = -0.145 - (k % 5) * 0.004
        add_trace([(-0.125, zt), (mx, zt), (mx - 0.018, zt + 0.018), (-0.212, zt + 0.018)], width_px=2.0)
    for k in range(10):
        zt = 0.015 + k * 0.0065
        add_trace([(-0.205, zt), (-0.232, zt), (-0.244, zt + 0.012), (-0.265, zt + 0.012)], width_px=1.8)

    # 3) VRM (-0.065, -0.14) -> CPU Power Bus (breite Power-Spuren)
    for k in range(12):
        xt = -0.112 + k * 0.0085
        add_trace([(xt, -0.155), (xt, -0.065)], width_px=3.6)

    # 4) 24-Pin ATX (0.235, -0.06) -> VRM, RAM & PCH Power Distribution
    for k in range(10):
        zt = -0.098 + k * 0.0085
        add_trace([(0.235, zt), (0.185, zt), (0.168, zt - 0.017), (0.168, -0.175), (0.150, -0.193), (-0.110, -0.193)], width_px=2.4)

    # 5) PCH (0.190, 0.080) -> M.2 NVMe (0.04, 0.14) & SATA (0.237, 0.135..0.195) & Front Panel (0.175, 0.215)
    for k in range(12):
        zt = 0.072 + k * 0.0055
        add_trace([(0.168, zt), (0.122, zt), (0.102, zt + 0.020), (-0.015, zt + 0.020)], width_px=2.0)
    for k in range(8):
        xt = 0.174 + k * 0.0050
        add_trace([(xt, 0.104), (xt, 0.132 + k * 0.008), (0.236, 0.132 + k * 0.008)], width_px=2.2)
    for k in range(6):
        xt = 0.162 + k * 0.0055
        add_trace([(xt, 0.105), (xt, 0.214)], width_px=1.9)

    # 6) Rear I/O (-0.255..-0.070, -0.228) -> BMC (0.192, -0.04) & PCH & CPU
    for k in range(10):
        xt = -0.245 + k * 0.018
        add_trace([(xt, -0.220), (xt, -0.185), (xt + 0.014, -0.171), (xt + 0.014, -0.080)], width_px=2.0)
    for k in range(6):
        zt = -0.210 + k * 0.006
        add_trace([(-0.075, zt), (0.135, zt), (0.155, zt + 0.020), (0.188, zt + 0.020)], width_px=1.9)

    # 7) Luefter-Header & Front-Edge Bus
    for k in range(4):
        zt = 0.198 + k * 0.005
        add_trace([(-0.255, zt), (0.180, zt)], width_px=2.0)

    # 8) Feine Serpentine-Ausgleichsschleifen zwischen CPU & M.2
    for k in range(5):
        yb = 0.068 + k * 0.0065
        pts = [(-0.115, yb)]
        for s in range(6):
            sx = -0.095 + s * 0.012
            pts.append((sx, yb))
            pts.append((sx + 0.003, yb + (0.004 if s % 2 == 0 else -0.004)))
            pts.append((sx + 0.006, yb))
        pts.append((0.020, yb))
        add_trace(pts, width_px=1.7)

    for c in range(3):
        albedo[:, :, c] = albedo[:, :, c] * (1.0 - trace_mask * 0.78) + trace_col[c] * (trace_mask * 0.78)
    height += trace_mask * 0.095
    rough -= trace_mask * 0.10
    metal += trace_mask * 0.12

    # Goldene/verzinnte Durchkontaktierungen (Vias) & Loetpads
    via_gold = np.array([0.82, 0.66, 0.28], dtype=np.float32)
    via_hole = np.array([0.02, 0.02, 0.025], dtype=np.float32)
    rng = np.random.default_rng(42)

    def place_via(x: float, z: float, r_out: float = 3.6, r_in: float = 1.6):
        px, py = to_px(x, z)
        draw_circle(albedo, px, py, r_out, via_gold)
        draw_circle(albedo, px, py, r_in, via_hole)
        draw_circle(metal, px, py, r_out, 0.92, inner_r=r_in)
        draw_circle(rough, px, py, r_out, 0.22, inner_r=r_in)
        draw_circle(height, px, py, r_out, 0.62, inner_r=r_in)
        draw_circle(height, px, py, r_in, 0.20)

    # Via-Reihen entlang der Bus-Grenzen, ICs, Steckplaetze und Platinenraender
    for z in np.linspace(-0.215, 0.215, 36):
        place_via(-0.282, z, 3.0, 1.3)
        place_via(0.244, z, 3.0, 1.3)
    for x in np.linspace(-0.27, 0.23, 38):
        place_via(x, -0.234, 3.0, 1.3)
        place_via(x, 0.234, 3.0, 1.3)
    for x in np.linspace(-0.135, 0.015, 16):
        place_via(x, -0.090, 3.2, 1.4)
        place_via(x, 0.064, 3.2, 1.4)
    for x in np.linspace(0.025, 0.160, 14):
        place_via(x, -0.118, 3.0, 1.3)
        place_via(x, 0.062, 3.0, 1.3)
    for _ in range(120):
        vx = float(rng.uniform(-0.27, 0.23))
        vz = float(rng.uniform(-0.22, 0.22))
        place_via(vx, vz, 2.7, 1.2)

    # 8 Server-Befestigungsloecher mit vergoldeten Kranz-Loetpads
    for mx in (-0.275, -0.020, 0.235):
        for mz in (-0.225, 0.0, 0.225):
            if mx == -0.020 and mz == 0.0:
                continue
            px, py = to_px(mx, mz)
            draw_circle(albedo, px, py, 24.0, via_gold, inner_r=11.0)
            draw_circle(albedo, px, py, 11.0, via_hole)
            draw_circle(metal, px, py, 24.0, 0.94, inner_r=11.0)
            draw_circle(rough, px, py, 24.0, 0.20, inner_r=11.0)
            draw_circle(height, px, py, 24.0, 0.66, inner_r=11.0)
            for a_i in range(8):
                ang = a_i * math.pi / 4.0
                draw_circle(albedo, px + 18.0 * math.cos(ang), py + 18.0 * math.sin(ang), 2.8, via_hole)

    # SMD-Loetpads in regelmaessigen Arrays (wirkt extrem dicht und realistisch!)
    tin_col = np.array([0.74, 0.76, 0.79], dtype=np.float32)
    for sx, sz in [(-0.18, -0.18), (-0.17, -0.15), (0.04, -0.19), (0.15, -0.18), (0.14, 0.17), (-0.15, 0.16)]:
        for r in range(3):
            for c_i in range(5):
                ix, iy = to_ipx(sx + c_i * 0.008, sz + r * 0.006)
                fill_rect(albedo, ix - 4, iy - 2, ix - 1, iy + 2, tin_col)
                fill_rect(albedo, ix + 1, iy - 2, ix + 4, iy + 2, tin_col)
                fill_rect(metal, ix - 4, iy - 2, ix + 4, iy + 2, 0.85)

    # Gestochen scharfer weisser Bestueckungsdruck (Silkscreen)
    silk = np.zeros((H, W), dtype=np.float32)

    def silk_box(x0, z0, x1, z1, th=3):
        ix0, iy0 = to_ipx(x0, z0)
        ix1, iy1 = to_ipx(x1, z1)
        stroke_rect(silk, ix0, iy0, ix1, iy1, 1.0, thickness=th)

    def silk_txt(x, z, txt, scale=3, vertical=False):
        ix, iy = to_ipx(x, z)
        draw_text(silk, ix, iy, txt, 1.0, scale=scale, vertical=vertical)

    # Platinen-Randlinie
    stroke_rect(silk, 14, 14, W - 14, H - 14, 0.65, thickness=2)

    # Bauteil-Rahmen
    silk_box(-0.138, -0.078, -0.002, 0.058, th=3)      # CPU Socket
    silk_box(-0.120, -0.160, -0.010, -0.095, th=2)     # VRM
    silk_box(0.016, -0.108, 0.164, 0.048, th=2)        # 8x DIMM Bank
    silk_box(0.162, 0.052, 0.218, 0.108, th=2)         # PCH
    silk_box(0.223, -0.108, 0.246, -0.012, th=2)       # ATX 24P
    silk_box(-0.014, -0.172, 0.014, -0.152, th=2)      # EPS 8P
    silk_box(-0.028, 0.088, 0.112, 0.192, th=2)        # M.2 NVMe Zone
    silk_box(-0.222, -0.105, -0.198, 0.068, th=2)      # PCIe x16
    silk_box(-0.274, 0.012, -0.258, 0.118, th=2)       # PCIe x8
    silk_box(0.172, -0.160, 0.212, -0.120, th=2)       # BAT1

    # Hauptbeschriftung & Modell-Typenschild (gut sichtbar im freien Bereich!)
    title = "DCT-X13 AI-PRO" if variant == "black" else "DCT-X13 SR-2U"
    silk_txt(-0.268, 0.160, title, scale=5)
    silk_txt(-0.268, 0.180, "REV 2.4  ENTERPRISE SERVER", scale=2)
    silk_txt(-0.268, 0.194, "DESIGNED FOR DATACENTER", scale=2)
    silk_txt(-0.125, 0.064, "CPU1  LGA4677", scale=3)
    silk_txt(-0.112, -0.166, "VRM 16-PHASE", scale=2)
    silk_txt(-0.018, -0.184, "CPU_PWR1", scale=2)
    silk_txt(0.176, -0.169, "BAT1 CR2032", scale=2)
    silk_txt(0.166, -0.020, "BMC", scale=2)
    silk_txt(0.164, 0.040, "PCH_C741", scale=2)
    silk_txt(0.214, -0.025, "ATX_24P", scale=2, vertical=True)
    silk_txt(0.198, 0.122, "SATA0-3", scale=2)
    silk_txt(0.010, 0.075, "M.2_NVME GEN5", scale=2)
    silk_txt(-0.242, 0.060, "PCIE1 X16 GEN5", scale=2, vertical=True)
    silk_txt(-0.282, 0.088, "PCIE2 X8", scale=2, vertical=True)
    silk_txt(-0.260, 0.206, "FAN1", scale=2)
    silk_txt(-0.160, 0.206, "FAN2", scale=2)
    silk_txt(0.112, 0.206, "FAN3", scale=2)
    silk_txt(0.155, 0.202, "JFP1", scale=2)
    silk_txt(0.060, -0.188, "BIOS", scale=2)

    # DIMM-Slot-Namen A1..D2 direkt vor jedem Slot
    dimm_names = ["A1", "A2", "B1", "B2", "C1", "C2", "D1", "D2"]
    for i, dn in enumerate(dimm_names):
        dx = 0.021 + i * 0.018
        silk_txt(dx, 0.052, dn, scale=2)

    for c in range(3):
        albedo[:, :, c] = albedo[:, :, c] * (1.0 - silk * 0.88) + silk_col[c] * (silk * 0.88)
    rough = rough * (1.0 - silk * 0.5) + 0.72 * (silk * 0.5)
    metal = metal * (1.0 - silk)
    height += silk * 0.02

    # Gebaktes Kontakt-AO unter allen Haupt-Bauteilen (erzeugt realistische Tiefe!)
    ao = np.ones((H, W), dtype=np.float32)
    for x0, z0, x1, z1, st in [
        (-0.132, -0.072, -0.008, 0.052, 0.55),   # CPU Sockel
        (-0.118, -0.158, -0.012, -0.122, 0.55),  # VRM Heatsink
        (0.020, -0.105, 0.160, 0.045, 0.42),     # RAM Bank
        (-0.218, -0.100, -0.202, 0.065, 0.52),   # PCIe x16
        (-0.273, 0.016, -0.259, 0.114, 0.48),    # PCIe x8
        (0.163, 0.053, 0.217, 0.107, 0.52),      # PCH Heatsink
        (0.224, -0.106, 0.245, -0.014, 0.55),    # 24-Pin Header
        (-0.274, -0.240, -0.055, -0.210, 0.55),  # Rear I/O
        (0.172, -0.158, 0.212, -0.122, 0.40),    # CMOS Battery
        (-0.015, 0.095, 0.100, 0.185, 0.35),     # M.2 Zone
    ]:
        ix0, iy0 = to_ipx(x0, z0)
        ix1, iy1 = to_ipx(x1, z1)
        add_ao_box(ao, ix0, iy0, ix1, iy1, st)
    ao = blur_separable(ao, 14, wrap=False)
    # Leichte AO-Abdunklung auch ins Albedo mischen (wirkt selbst bei hartem Licht plastisch!)
    ao_shade = 0.65 + 0.35 * ao
    albedo *= ao_shade[:, :, None]

    if damaged:
        # Deutliche Kurzschluss-Brandflecken & verkohlte PCB-Risse rund um VRM/Elkos, PCH & Front-Bus
        c1 = to_ipx(-0.085, -0.175)  # VRM / Elko-Explosion hinten
        c2 = to_ipx(0.180, 0.030)    # PCH / BMC Kurzschluss
        c3 = to_ipx(-0.145, 0.135)   # Freier Frontbereich links
        _apply_pcb_burn_scorch(albedo, rough, metal, ao, height, [
            (c1[0], c1[1], 190.0),
            (c2[0], c2[1], 165.0),
            (c3[0], c3[1], 145.0),
        ])

    return {
        "albedo_u8": np.clip(albedo * 255.0, 0, 255).astype(np.uint8),
        "normal_u8": height_to_normal(height, strength=3.2, wrap=False),
        "orm_u8": pack_orm(ao, np.clip(rough, 0.15, 0.95), np.clip(metal, 0.0, 1.0)),
    }


def gen_mainboard_pbr(cache_dir: str, variant: str = "green") -> dict:
    prefix = os.path.join(cache_dir, f"mb_{variant}")
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    res = _build_mainboard_arrays(variant, damaged=False)
    save_png(paths["albedo"], res["albedo_u8"])
    save_png(paths["normal"], res["normal_u8"])
    save_png(paths["orm"], res["orm_u8"])
    return paths


# ---------------------------------------------------------------------------
# 2. SAS/SATA Drive Backplane PCB (1024x512, kein Kacheln!)
# ---------------------------------------------------------------------------

def gen_backplane_pbr(cache_dir: str) -> dict:
    prefix = os.path.join(cache_dir, "backplane_pcb")
    paths = {
        "albedo": prefix + "_albedo.png",
        "normal": prefix + "_normal.png",
        "orm": prefix + "_orm.png",
    }
    W, H = 1024, 512
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    weave = 0.5 + 0.25 * np.sin(xx * 0.9) * np.sin(yy * 0.9)
    micro = fbm_tile(H, W, 16, 32, octaves=3, seed=77)

    base = np.array([0.046, 0.215, 0.108], dtype=np.float32)
    trace_c = np.array([0.145, 0.435, 0.220], dtype=np.float32)
    gold = np.array([0.84, 0.68, 0.28], dtype=np.float32)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    for c in range(3):
        albedo[:, :, c] = base[c] * (0.90 + 0.12 * weave + 0.08 * (micro - 0.5))

    height = 0.45 + 0.02 * weave
    rough = np.full((H, W), 0.36, dtype=np.float32)
    metal = np.full((H, W), 0.05, dtype=np.float32)
    trace_mask = np.zeros((H, W), dtype=np.float32)

    # 8 Bay-Sektoren mit SAS-Differentialpaaren zu 2 Mini-SAS-HD-Zonen
    for b in range(8):
        bx = int((b + 0.5) * W / 8.0)
        target_x = int(W * (0.28 if b < 4 else 0.72))
        for t in range(4):
            ox = bx - 18 + t * 12
            mid_y = 220 + (b % 4) * 18 + t * 4
            draw_polyline(trace_mask, [(ox, 370), (ox, mid_y), (target_x + (t - 1.5) * 8, mid_y), (target_x + (t - 1.5) * 8, 120)], 1.3, 1.0)
        # Vias pro Bay
        for vy in (90, 150, 310, 420):
            draw_circle(albedo, bx - 38, vy, 3.5, gold)
            draw_circle(albedo, bx - 38, vy, 1.5, np.array([0.02, 0.02, 0.02]))
            draw_circle(metal, bx - 38, vy, 3.5, 0.9, inner_r=1.5)

    for c in range(3):
        albedo[:, :, c] = albedo[:, :, c] * (1.0 - trace_mask * 0.75) + trace_c[c] * (trace_mask * 0.75)
    height += trace_mask * 0.09
    rough -= trace_mask * 0.08

    # Bestueckungsdruck
    silk = np.zeros((H, W), dtype=np.float32)
    stroke_rect(silk, 10, 10, W - 10, H - 10, 0.7, 2)
    draw_text(silk, 26, 24, "DCT-BP8N SAS3/NVME BACKPLANE REV 3.1", 1.0, scale=2)
    for b in range(8):
        bx = int((b + 0.5) * W / 8.0)
        stroke_rect(silk, bx - 52, 65, bx + 52, 460, 0.45, 2)
        draw_text(silk, bx - 24, 468, f"BAY{b}", 1.0, scale=2)
    draw_text(silk, int(W * 0.22), 78, "SFF-8643 A", 1.0, scale=2)
    draw_text(silk, int(W * 0.66), 78, "SFF-8643 B", 1.0, scale=2)
    draw_text(silk, 28, 220, "PWR1", 1.0, scale=2)
    draw_text(silk, W - 95, 220, "PWR2", 1.0, scale=2)

    for c in range(3):
        albedo[:, :, c] = albedo[:, :, c] * (1.0 - silk * 0.85) + 0.90 * (silk * 0.85)
    height += silk * 0.02

    # Vertikales AO oben/unten an den Gehaeuse-Kanten
    ao = np.ones((H, W), dtype=np.float32)
    ao[:35, :] = 0.55
    ao[-35:, :] = 0.55
    ao = blur_separable(ao, 14, wrap=False)
    albedo *= (0.70 + 0.30 * ao)[:, :, None]

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(height, strength=3.0, wrap=False))
    save_png(paths["orm"], pack_orm(ao, np.clip(rough, 0.2, 0.9), metal))
    return paths


# ---------------------------------------------------------------------------
# 3. Gebuerstetes verzinktes Serverblech (SGCC) & Dunkel eloxiert / Alu / Kupfer
# ---------------------------------------------------------------------------

def gen_brushed_metal_pbr(cache_dir: str, name: str, base_rgb, metal_val: float, rough_base: float,
                          spangle: float = 0.0, seed: int = 101, size: int = 512) -> dict:
    prefix = os.path.join(cache_dir, name)
    paths = {
        "albedo": prefix + "_albedo.png",
        "normal": prefix + "_normal.png",
        "orm": prefix + "_orm.png",
    }
    W = H = size
    # Anisotrope Buerst-Striche (fein in Y, langgestreckt in X)
    streaks = fbm_tile(H, W, 128, 8, octaves=3, seed=seed)
    fine = fbm_tile(H, W, 256, 16, octaves=2, seed=seed + 31)
    broad = fbm_tile(H, W, 6, 6, octaves=3, seed=seed + 59)

    grain = 0.55 * streaks + 0.30 * fine + 0.15 * broad
    if spangle > 0.0:
        # Subtile Zinkblumen-Variation fuer echtes SGCC-Serverblech
        sp = fbm_tile(H, W, 18, 18, octaves=2, seed=seed + 99)
        grain = grain * (1.0 - spangle) + sp * spangle

    base = np.array(base_rgb, dtype=np.float32)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    var = 0.88 + 0.22 * grain
    for c in range(3):
        albedo[:, :, c] = np.clip(base[c] * var, 0.0, 1.0)

    rough = np.clip(rough_base + 0.14 * (0.5 - grain), 0.14, 0.85)
    metal = np.full((H, W), metal_val, dtype=np.float32)
    ao = np.clip(0.92 + 0.08 * grain, 0.0, 1.0)

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(grain, strength=1.4, wrap=True))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


# ---------------------------------------------------------------------------
# 4. Echtes scharfes Waben-Lochblech (Honeycomb Steel, 1:1 unverzerrt!)
# ---------------------------------------------------------------------------

def gen_honeycomb_pbr(cache_dir: str, name: str = "honeycomb_steel",
                      metal_rgb=(0.56, 0.58, 0.61), hole_ratio: float = 0.39) -> dict:
    """Kachelbare Wabenlochung mit sauberem exaktem Hex-Seitenverhaeltnis (sqrt(3)).
    8x5 Perioden in 512x554 (nahezu 1:1 physische Kachel) -> 100% regelmaessige Sechsecke!"""
    prefix = os.path.join(cache_dir, name)
    paths = {
        "albedo": prefix + "_albedo.png",
        "normal": prefix + "_normal.png",
        "orm": prefix + "_orm.png",
    }
    W, H = 512, 512
    # Hex-Raster: nx Spalten, ny Reihen so dass dx und dy exakt sqrt(3) Verhaeltnis haben
    nx = 10.0
    ny = round(nx / math.sqrt(3.0))  # 6 Reihen -> periodisch kachelbar!
    # Exaktes Seitenverhaeltnis der Kachel: phys_w / phys_h = (nx) / (ny * sqrt(3)) ~ 0.962 (nahezu quadratisch!)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ux = (xx / W) * nx
    uy = (yy / H) * (ny * math.sqrt(3.0))

    # Zwei versetzte Gitter fuer exakte Sechseck-Mittelpunkte
    def hex_sdf(px, py):
        # Abstand im Sechseck (Spitze oben/unten)
        ax = np.abs(px)
        ay = np.abs(py)
        return np.maximum(ax * 0.8660254 + ay * 0.5, ay)

    g1x = (ux + 0.5) % 1.0 - 0.5
    g1y = (uy + 0.8660254) % 1.7320508 - 0.8660254
    d1 = hex_sdf(g1x, g1y)

    g2x = (ux) % 1.0 - 0.5
    g2y = (uy) % 1.7320508 - 0.8660254
    d2 = hex_sdf(g2x, g2y)

    d = np.minimum(d1, d2)
    # Loch-Maske: d < hole_ratio -> tiefschwarzes Inneres, schmaler abgeschrägter Metallrand
    edge = 0.032
    metal_mask = np.clip((d - hole_ratio) / edge, 0.0, 1.0)
    bevel_h = np.clip((d - (hole_ratio - 0.015)) / 0.055, 0.0, 1.0)

    brush = fbm_tile(H, W, 64, 8, octaves=2, seed=204)
    base = np.array(metal_rgb, dtype=np.float32)
    hole_col = np.array([0.018, 0.020, 0.024], dtype=np.float32)

    albedo = np.empty((H, W, 3), dtype=np.float32)
    for c in range(3):
        m_c = base[c] * (0.90 + 0.16 * brush)
        albedo[:, :, c] = hole_col[c] * (1.0 - metal_mask) + m_c * metal_mask

    rough = 0.94 * (1.0 - metal_mask) + (0.34 + 0.08 * (0.5 - brush)) * metal_mask
    metal = 0.84 * metal_mask
    ao = 0.08 * (1.0 - metal_mask) + (0.85 + 0.15 * bevel_h) * metal_mask
    height = bevel_h * 0.85 + 0.04 * brush * metal_mask

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(height, strength=4.5, wrap=True))
    save_png(paths["orm"], pack_orm(ao, np.clip(rough, 0.18, 0.96), metal))
    return paths


# ---------------------------------------------------------------------------
# 5. Netzteil-Typenschild (1024x512, Effizienz PLATIN / GOLD + Tabelle + Barcode)
# ---------------------------------------------------------------------------

def gen_psu_label_pbr(cache_dir: str, name: str = "psu_label_std",
                      watt_text: str = "850W", rating: str = "GOLD") -> dict:
    prefix = os.path.join(cache_dir, name)
    paths = {
        "albedo": prefix + "_albedo.png",
        "normal": prefix + "_normal.png",
        "orm": prefix + "_orm.png",
    }
    W, H = 1024, 512
    albedo = np.full((H, W, 3), np.array([0.10, 0.11, 0.13], dtype=np.float32), dtype=np.float32)
    # Gediegenes satiniertes Datenblatt-Hellgrau (kein Ueberstrahlen unter Studiobeleuchtung!)
    fill_rect(albedo, 16, 16, W - 16, H - 16, np.array([0.76, 0.77, 0.79]))
    # Dunkler Kopfstreifen mit Marken-Akzent
    fill_rect(albedo, 16, 16, W - 16, 128, np.array([0.09, 0.105, 0.13]))
    accent = np.array([0.85, 0.65, 0.18]) if rating == "GOLD" else np.array([0.78, 0.82, 0.88])
    fill_rect(albedo, 16, 124, W - 16, 134, accent)

    # Kopfzeile Text
    draw_text(albedo, 40, 38, "DCT-POWER ENTERPRISE", np.array([0.94, 0.95, 0.97]), scale=4)
    draw_text(albedo, 40, 82, f"SERVER PSU  MODEL DCT-{watt_text}AB  ACTIVE PFC", accent, scale=3)

    # Effizienz-Plakette rechts oben (sauber zentriert mit Innenabstand)
    fill_rect(albedo, W - 232, 24, W - 26, 114, np.array([0.95, 0.95, 0.95]))
    fill_rect(albedo, W - 232, 78, W - 26, 114, accent)
    draw_text(albedo, W - 206, 42, "EFFIZIENZ", np.array([0.08, 0.09, 0.10]), scale=3)
    draw_text(albedo, W - 204, 86, rating, np.array([0.06, 0.06, 0.08]), scale=3)

    # Elektrische Spezifikationstabelle
    dark = np.array([0.10, 0.11, 0.13])
    grid_c = np.array([0.28, 0.30, 0.34])
    stroke_rect(albedo, 36, 152, W - 36, 360, grid_c, 3)
    fill_rect(albedo, 36, 152, W - 36, 198, np.array([0.65, 0.67, 0.71]))
    for yline in (198, 252, 306):
        fill_rect(albedo, 36, yline, W - 36, yline + 2, grid_c)
    for xline in (220, 410, 600, 790):
        fill_rect(albedo, xline, 152, xline + 2, 306, grid_c)

    draw_text(albedo, 52, 165, "DC OUTPUT", dark, scale=3)
    draw_text(albedo, 250, 165, "+12V", dark, scale=3)
    draw_text(albedo, 445, 165, "+5V", dark, scale=3)
    draw_text(albedo, 625, 165, "+3.3V", dark, scale=3)
    draw_text(albedo, 815, 165, "+5VSB", dark, scale=3)

    draw_text(albedo, 52, 214, "MAX LOAD", dark, scale=3)
    amps = "70.8A" if "850" in watt_text else "133.3A"
    draw_text(albedo, 240, 214, amps, dark, scale=3)
    draw_text(albedo, 438, 214, "20.0A", dark, scale=3)
    draw_text(albedo, 628, 214, "20.0A", dark, scale=3)
    draw_text(albedo, 825, 214, "3.5A", dark, scale=3)

    draw_text(albedo, 52, 268, "MAX POWER", dark, scale=3)
    draw_text(albedo, 240, 268, watt_text, dark, scale=3)
    draw_text(albedo, 438, 268, "120W", dark, scale=3)
    draw_text(albedo, 628, 268, "120W", dark, scale=3)
    draw_text(albedo, 825, 268, "17.5W", dark, scale=3)

    draw_text(albedo, 52, 322, "AC INPUT: 100-240V  50-60HZ  10A-5A   TOTAL CONTINUOUS: " + watt_text, dark, scale=2)

    # Warnhinweis + Barcode + CE/UL unten
    fill_rect(albedo, 36, 384, 340, 474, np.array([0.92, 0.72, 0.14]))
    stroke_rect(albedo, 36, 384, 340, 474, dark, 3)
    draw_text(albedo, 52, 398, "! CAUTION !", dark, scale=3)
    draw_text(albedo, 52, 434, "HIGH VOLTAGE INSIDE", dark, scale=2)
    draw_text(albedo, 52, 452, "DO NOT OPEN COVER", dark, scale=2)

    # Realistischer Barcode rechts
    rng = np.random.default_rng(314 if rating == "GOLD" else 628)
    bx = 380
    while bx < 770:
        bw = int(rng.choice([3, 5, 8, 11]))
        if rng.random() > 0.42:
            fill_rect(albedo, bx, 388, min(770, bx + bw), 452, dark)
        bx += bw + int(rng.choice([3, 5, 7]))
    draw_text(albedo, 405, 458, "S/N: DCT2611-884920-042", dark, scale=2)

    draw_text(albedo, 815, 396, "CE  FC", dark, scale=4)
    draw_text(albedo, 815, 444, "ROHS", dark, scale=2)

    paper = fbm_tile(H, W, 32, 64, octaves=2, seed=55)
    albedo *= (0.96 + 0.05 * paper)[:, :, None]
    rough = np.full((H, W), 0.48, dtype=np.float32) + 0.04 * (paper - 0.5)
    metal = np.zeros((H, W), dtype=np.float32)
    ao = np.ones((H, W), dtype=np.float32)

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(paper * 0.25, strength=0.6, wrap=False))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


# ---------------------------------------------------------------------------
# 6. Anti-Statik ESD-Reparaturmatte (1536x1024, tiefes Profi-Schieferblau + Raster + Lineal + Logo)
# ---------------------------------------------------------------------------

def gen_esd_mat_pbr(cache_dir: str) -> dict:
    prefix = os.path.join(cache_dir, "esd_mat")
    paths = {
        "albedo": prefix + "_albedo.png",
        "normal": prefix + "_normal.png",
        "orm": prefix + "_orm.png",
    }
    W, H = 1536, 1024
    # Feine Gummi-Noppen/Pebble-Struktur
    pebble = fbm_tile(H, W, 128, 192, octaves=3, seed=401)
    wear = fbm_tile(H, W, 8, 12, octaves=3, seed=409)

    # Hochwertiges, sattes Profi-ESD-Schieferblau (kein Babyblau!)
    base = np.array([0.135, 0.235, 0.320], dtype=np.float32)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    for c in range(3):
        albedo[:, :, c] = base[c] * (0.90 + 0.10 * pebble + 0.10 * (wear - 0.5))

    # Dezenter weisser technischer Aufdruck (Rahmen, Zentimeter-Raster, Lineal vorne, ESD-Logo)
    print_mask = np.zeros((H, W), dtype=np.float32)
    stroke_rect(print_mask, 36, 36, W - 36, H - 36, 0.55, 3)
    stroke_rect(print_mask, 48, 48, W - 48, H - 48, 0.28, 1)

    # Feines 5-cm-Raster (subtil, nicht aufdringlich)
    for gx in range(96, W - 64, 68):
        fill_rect(print_mask, gx, 52, gx + 1, H - 96, 0.16)
    for gy in range(96, H - 96, 68):
        fill_rect(print_mask, 52, gy, W - 52, gy + 1, 0.16)

    # Schnittkreuze an den Ecken der Server-Ablagezone
    for cx in (240, W - 240):
        for cy in (180, H - 180):
            fill_rect(print_mask, cx - 18, cy - 1, cx + 18, cy + 2, 0.45)
            fill_rect(print_mask, cx - 1, cy - 18, cx + 2, cy + 18, 0.45)

    # Millimeter/Zentimeter-Lineal entlang der Vorderkante (unten im Bild = +Z)
    fill_rect(print_mask, 100, H - 78, W - 100, H - 76, 0.55)
    for idx, rx in enumerate(range(100, W - 98, 14)):
        tick_h = 20 if idx % 10 == 0 else (13 if idx % 5 == 0 else 7)
        fill_rect(print_mask, rx, H - 78, rx + 2, H - 78 + tick_h, 0.55)
        if idx % 10 == 0 and rx < W - 130:
            draw_text(print_mask, rx - 6, H - 54, f"{idx}", 0.55, scale=2)

    # ESD-SAFE Technik-Aufdruck links vorne & rechts hinten
    draw_text(print_mask, 72, H - 122, "ESD-SAFE WORKSURFACE", 0.65, scale=3)
    draw_text(print_mask, 72, H - 94, "STATIC DISSIPATIVE MAT  10E6 - 10E9 OHM", 0.48, scale=2)
    draw_text(print_mask, W - 430, 66, "GROUNDED  EPA ZONE", 0.55, scale=2)
    draw_text(print_mask, 72, 66, "DCT SERVICE BENCH  REV.04", 0.50, scale=2)

    # Kleinteile-Sortierfelder sauber links unterhalb des Kopfstreifens (frei vom Schnittkreuz)
    for k in range(3):
        fy0 = 128 + k * 78
        stroke_rect(print_mask, 66, fy0, 128, fy0 + 58, 0.38, 2)
        draw_text(print_mask, 136, fy0 + 22, f"M{2 + k}", 0.44, scale=2)

    ink_col = np.array([0.78, 0.86, 0.93], dtype=np.float32)
    for c in range(3):
        albedo[:, :, c] = albedo[:, :, c] * (1.0 - print_mask) + ink_col[c] * print_mask

    # Subtiles Kontakt-AO unter der Server-Standflaeche in der Mitte
    ao = np.ones((H, W), dtype=np.float32)
    # Chassis steht bei x -0.37..0.37 (Matte 1.12 m -> 0.17..0.83), z -0.36..0.36 (Matte 1.02 m -> 0.15..0.85)
    add_ao_box(ao, int(W * 0.175), int(H * 0.155), int(W * 0.825), int(H * 0.845), 0.32)
    ao = blur_separable(ao, 36, wrap=False)
    albedo *= (0.76 + 0.24 * ao)[:, :, None]

    rough = np.clip(0.76 + 0.08 * (0.5 - pebble) + 0.06 * (wear - 0.5) - 0.10 * print_mask, 0.55, 0.92)
    metal = np.zeros((H, W), dtype=np.float32)
    height = 0.5 + 0.18 * pebble + 0.03 * print_mask

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(height, strength=1.8, wrap=False))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


# ---------------------------------------------------------------------------
# 7. Industrie-Werkbank-Arbeitsplatte (1024x1024, edles dunkles Anthrazit-Holz/Laminat)
# ---------------------------------------------------------------------------

def gen_workbench_pbr(cache_dir: str) -> dict:
    prefix = os.path.join(cache_dir, "workbench_top")
    paths = {
        "albedo": prefix + "_albedo.png",
        "normal": prefix + "_normal.png",
        "orm": prefix + "_orm.png",
    }
    W = H = 1024
    # Gediegenes dunkles Industrie-Werkbank-Laminat (leicht gemasert, blendet nicht wie grelles Weiss!)
    grain = fbm_tile(H, W, 64, 8, octaves=4, seed=501)
    speck = fbm_tile(H, W, 128, 128, octaves=2, seed=507)
    broad = fbm_tile(H, W, 6, 6, octaves=3, seed=511)

    base = np.array([0.23, 0.235, 0.245], dtype=np.float32)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    v = 0.86 + 0.14 * grain + 0.08 * (speck - 0.5) + 0.10 * (broad - 0.5)
    for c in range(3):
        albedo[:, :, c] = np.clip(base[c] * v, 0.0, 1.0)

    # Dezentes Kontakt-AO unter der ESD-Matte
    ao = np.ones((H, W), dtype=np.float32)
    add_ao_box(ao, int(W * 0.20), int(H * 0.13), int(W * 0.80), int(H * 0.87), 0.42)
    ao = blur_separable(ao, 28, wrap=False)
    albedo *= (0.72 + 0.28 * ao)[:, :, None]

    rough = np.clip(0.56 + 0.10 * (0.5 - grain) + 0.06 * (broad - 0.5), 0.40, 0.78)
    metal = np.full((H, W), 0.03, dtype=np.float32)
    height = 0.5 + 0.08 * grain + 0.04 * speck

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(height, strength=1.2, wrap=False))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


# ---------------------------------------------------------------------------
# 8. Gesleevter Nylon-Kabelschlauch (512x512, geflochtenes Paracord/Techflex-Muster)
# ---------------------------------------------------------------------------

def gen_cable_sleeve_pbr(cache_dir: str) -> dict:
    prefix = os.path.join(cache_dir, "cable_sleeve")
    paths = {
        "albedo": prefix + "_albedo.png",
        "normal": prefix + "_normal.png",
        "orm": prefix + "_orm.png",
    }
    W = H = 512
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # Rauten-Geflecht (2 kreuzende Diagonal-Sinuswellen)
    freq = 2.0 * math.pi * 16.0 / W
    w1 = 0.5 + 0.5 * np.sin((xx + yy) * freq)
    w2 = 0.5 + 0.5 * np.sin((xx - yy) * freq)
    weave = np.maximum(w1, w2)
    fine = fbm_tile(H, W, 64, 64, octaves=2, seed=601)

    albedo = np.empty((H, W, 3), dtype=np.float32)
    for c, b in enumerate((0.045, 0.048, 0.054)):
        albedo[:, :, c] = b * (0.55 + 0.85 * weave + 0.12 * fine)

    rough = np.clip(0.68 - 0.18 * weave, 0.38, 0.86)
    metal = np.full((H, W), 0.05, dtype=np.float32)
    ao = np.clip(0.45 + 0.55 * weave, 0.0, 1.0)
    height = weave * 0.85 + 0.10 * fine

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(height, strength=3.6, wrap=True))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


# ---------------------------------------------------------------------------
# 9. CPU-Heatspreader (Lasergravur), RAM- & NVMe-Aufkleber, GPU-Backplate
# ---------------------------------------------------------------------------

def gen_cpu_ihs_pbr(cache_dir: str) -> dict:
    prefix = os.path.join(cache_dir, "cpu_ihs")
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    W = H = 512
    brush = fbm_tile(H, W, 96, 8, octaves=3, seed=701)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    for c, b in enumerate((0.76, 0.77, 0.79)):
        albedo[:, :, c] = np.clip(b * (0.93 + 0.12 * brush), 0, 1)

    etch = np.zeros((H, W), dtype=np.float32)
    draw_text(etch, 80, 110, "DCT KERNOVA", 1.0, scale=4)
    draw_text(etch, 80, 165, "SERVER V32+  32C", 1.0, scale=3)
    draw_text(etch, 80, 215, "SRN72  3.20GHZ", 1.0, scale=3)
    draw_text(etch, 80, 265, "X428G914  SOCKET K1", 1.0, scale=2)
    # 2D-DataMatrix-Block
    rng = np.random.default_rng(709)
    for ry in range(10):
        for rx in range(10):
            if rng.random() > 0.45 or ry == 0 or rx == 0:
                fill_rect(etch, 340 + rx * 8, 300 + ry * 8, 348 + rx * 8, 308 + ry * 8, 1.0)
    # Pin-1 Dreieck unten links
    for k in range(36):
        fill_rect(albedo, 42, 430 + k, 42 + k, 431 + k, np.array([0.85, 0.68, 0.25]))

    for c in range(3):
        albedo[:, :, c] = albedo[:, :, c] * (1.0 - etch * 0.45) + 0.34 * (etch * 0.45)
    rough = np.clip(0.22 + 0.06 * (0.5 - brush) + 0.38 * etch, 0.16, 0.70)
    metal = np.clip(0.95 - 0.35 * etch, 0.4, 0.98)
    ao = np.ones((H, W), dtype=np.float32)

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(0.5 + 0.08 * brush - 0.08 * etch, strength=1.5, wrap=False))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


def gen_label_sticker_pbr(cache_dir: str, name: str, line1: str, line2: str,
                          dark_theme: bool = False, accent_rgb=(0.82, 0.62, 0.18)) -> dict:
    prefix = os.path.join(cache_dir, name)
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    W, H = 512, 192
    bg = np.array([0.09, 0.10, 0.12], dtype=np.float32) if dark_theme else np.array([0.90, 0.91, 0.92], dtype=np.float32)
    fg = np.array([0.92, 0.94, 0.96], dtype=np.float32) if dark_theme else np.array([0.10, 0.11, 0.13], dtype=np.float32)
    albedo = np.full((H, W, 3), bg, dtype=np.float32)
    fill_rect(albedo, 0, 0, W, 16, np.array(accent_rgb, dtype=np.float32))
    draw_text(albedo, 22, 30, line1, fg, scale=3)
    draw_text(albedo, 22, 74, line2, np.array(accent_rgb, dtype=np.float32) if dark_theme else fg, scale=2)
    # Barcode unten
    rng = np.random.default_rng(abs(hash(name)) % 10000)
    bx = 22
    while bx < W - 26:
        bw = int(rng.choice([2, 4, 6]))
        if rng.random() > 0.45:
            fill_rect(albedo, bx, 114, min(W - 26, bx + bw), 166, fg)
        bx += bw + int(rng.choice([2, 4]))

    rough = np.full((H, W), 0.42 if dark_theme else 0.55, dtype=np.float32)
    metal = np.full((H, W), 0.20 if dark_theme else 0.0, dtype=np.float32)
    ao = np.ones((H, W), dtype=np.float32)
    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], np.full((H, W, 3), np.array([128, 128, 255], dtype=np.uint8)))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


# ---------------------------------------------------------------------------
# Brand-/Schadens-Texturen (Russ, verkohltes PCB, Hitze-Verfaerbung)
# ---------------------------------------------------------------------------

def gen_burn_char_pbr(cache_dir: str) -> dict:
    prefix = os.path.join(cache_dir, "burn_char")
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    W = H = 512
    cracks = fbm_tile(H, W, 36, 36, octaves=4, seed=971)
    ash = fbm_tile(H, W, 96, 96, octaves=3, seed=983)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    # Tiefschwarzer Russ mit dunkelbraunen/kupferfarbenen Brandraendern
    albedo[:, :, 0] = np.clip(0.035 + 0.08 * cracks + 0.04 * ash, 0, 1)
    albedo[:, :, 1] = np.clip(0.028 + 0.045 * cracks + 0.03 * ash, 0, 1)
    albedo[:, :, 2] = np.clip(0.025 + 0.025 * cracks + 0.025 * ash, 0, 1)
    rough = np.clip(0.86 + 0.12 * (0.5 - ash), 0.72, 0.98)
    metal = np.full((H, W), 0.02, dtype=np.float32)
    ao = np.clip(0.45 + 0.45 * cracks, 0.2, 1.0)
    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(0.55 * cracks + 0.45 * ash, strength=3.6, wrap=True))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


def gen_scorch_metal_pbr(cache_dir: str) -> dict:
    prefix = os.path.join(cache_dir, "scorch_metal")
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    W = H = 512
    brush = fbm_tile(H, W, 96, 8, octaves=3, seed=991)
    heat = fbm_tile(H, W, 8, 8, octaves=3, seed=997)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    # Anlassfarben / dunkler verbrannter Stahl-Mix
    albedo[:, :, 0] = np.clip(0.14 + 0.16 * heat + 0.08 * brush, 0, 1)
    albedo[:, :, 1] = np.clip(0.11 + 0.10 * heat + 0.07 * brush, 0, 1)
    albedo[:, :, 2] = np.clip(0.10 + 0.14 * (1.0 - heat) + 0.06 * brush, 0, 1)
    rough = np.clip(0.56 + 0.22 * (1.0 - heat), 0.34, 0.88)
    metal = np.clip(0.55 - 0.30 * (1.0 - heat), 0.15, 0.78)
    ao = np.clip(0.60 + 0.35 * heat, 0.3, 1.0)
    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(0.4 * brush + 0.6 * heat, strength=2.4, wrap=True))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


def _apply_pcb_burn_scorch(albedo: np.ndarray, rough: np.ndarray, metal: np.ndarray,
                           ao: np.ndarray, height: np.ndarray,
                           centers) -> None:
    """Brennt realistische Brandflecken, Russ-Spritzer und verbranntes Kupfer direkt in die 2K-Platine."""
    h, w = ao.shape
    noise = fbm_tile(h, w, 32, 32, octaves=4, seed=953)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    for cx, cy, rad in centers:
        dist = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / max(rad, 1.0)
        soot = np.clip(1.0 - (dist + (noise - 0.5) * 0.42), 0.0, 1.0) ** 1.45
        char = np.clip(1.0 - (dist * 2.1 + (noise - 0.5) * 0.35), 0.0, 1.0) ** 1.8
        # Brauner Rand -> tiefschwarzer verkohlter Kern
        albedo[:, :, 0] = albedo[:, :, 0] * (1.0 - soot * 0.85) + 0.10 * soot * 0.85
        albedo[:, :, 1] = albedo[:, :, 1] * (1.0 - soot * 0.90) + 0.05 * soot * 0.90
        albedo[:, :, 2] = albedo[:, :, 2] * (1.0 - soot * 0.92) + 0.03 * soot * 0.92
        albedo *= (1.0 - char * 0.82)[:, :, None]
        rough[:] = np.clip(rough * (1.0 - soot * 0.7) + 0.95 * (soot * 0.7), 0.2, 0.98)
        metal[:] = metal * (1.0 - soot * 0.8)
        ao[:] = np.minimum(ao, 1.0 - 0.65 * soot)
        height[:] = height - char * 0.18


def gen_mainboard_broken_pbr(cache_dir: str, variant: str = "green") -> dict:
    """Erzeugt kaputte 2K-Mainboard-Texturen mit Kurzschluss-Krater an VRM/PCH/Front."""
    clean_p = os.path.join(cache_dir, f"mb_{variant}_albedo.png")
    if not os.path.exists(clean_p):
        gen_mainboard_pbr(cache_dir, variant)
    # Direkt auf gen_mainboard_pbr-Logik aufbauen, indem wir temporaer generieren und anbranden:
    prefix = os.path.join(cache_dir, f"mb_{variant}_broken")
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    # Wir rufen gen_mainboard_pbr mit internem Suffix auf nicht-destruktive Art nicht noetig: direkt neu berechnen
    res = _build_mainboard_arrays(variant, damaged=True)
    save_png(paths["albedo"], res["albedo_u8"])
    save_png(paths["normal"], res["normal_u8"])
    save_png(paths["orm"], res["orm_u8"])
    return paths


# ---------------------------------------------------------------------------
# Sammel-Generator: erzeugt alle Texturen in tools/blender/_pbr_cache/
# ---------------------------------------------------------------------------

def generate_all(cache_dir: str) -> dict:
    os.makedirs(cache_dir, exist_ok=True)
    return {
        "mb_green": gen_mainboard_pbr(cache_dir, "green"),
        "mb_black": gen_mainboard_pbr(cache_dir, "black"),
        "mb_green_broken": gen_mainboard_broken_pbr(cache_dir, "green"),
        "mb_black_broken": gen_mainboard_broken_pbr(cache_dir, "black"),
        "burn_char": gen_burn_char_pbr(cache_dir),
        "scorch_metal": gen_scorch_metal_pbr(cache_dir),
        "backplane": gen_backplane_pbr(cache_dir),
        "steel_brushed": gen_brushed_metal_pbr(cache_dir, "steel_brushed", (0.58, 0.60, 0.63), 0.86, 0.30, spangle=0.22, seed=101),
        "dark_anodized": gen_brushed_metal_pbr(cache_dir, "dark_anodized", (0.14, 0.15, 0.17), 0.62, 0.38, spangle=0.05, seed=113),
        "gunmetal": gen_brushed_metal_pbr(cache_dir, "gunmetal", (0.21, 0.23, 0.26), 0.78, 0.32, spangle=0.0, seed=127),
        "alu_brushed": gen_brushed_metal_pbr(cache_dir, "alu_brushed", (0.76, 0.78, 0.81), 0.92, 0.26, spangle=0.0, seed=139),
        "copper_brushed": gen_brushed_metal_pbr(cache_dir, "copper_brushed", (0.78, 0.45, 0.27), 0.95, 0.24, spangle=0.0, seed=149),
        "gold_metal": gen_brushed_metal_pbr(cache_dir, "gold_metal", (0.88, 0.69, 0.27), 0.96, 0.22, spangle=0.0, seed=157),
        "honeycomb_steel": gen_honeycomb_pbr(cache_dir, "honeycomb_steel", (0.58, 0.60, 0.63), hole_ratio=0.335),
        "honeycomb_dark": gen_honeycomb_pbr(cache_dir, "honeycomb_dark", (0.17, 0.18, 0.20), hole_ratio=0.345),
        "psu_label_std": gen_psu_label_pbr(cache_dir, "psu_label_std", "850W", "GOLD"),
        "psu_label_pro": gen_psu_label_pbr(cache_dir, "psu_label_pro", "1600W", "PLATIN"),
        "esd_mat": gen_esd_mat_pbr(cache_dir),
        "workbench_top": gen_workbench_pbr(cache_dir),
        "cable_sleeve": gen_cable_sleeve_pbr(cache_dir),
        "cpu_ihs": gen_cpu_ihs_pbr(cache_dir),
        "ram_label": gen_label_sticker_pbr(cache_dir, "ram_label", "DDR5-5600 ECC", "64GB 2RX4 RDIMM  DCT", dark_theme=False),
        "nvme_label": gen_label_sticker_pbr(cache_dir, "nvme_label", "DCT NVME GEN5", "ENTERPRISE 4TB  U.3/M.2", dark_theme=True),
        "gpu_label": gen_label_sticker_pbr(cache_dir, "gpu_label", "DCT TENSOR PRO", "80GB HBM3E  PCIE 5.0", dark_theme=True, accent_rgb=(0.24, 0.72, 0.46)),
    }


if __name__ == "__main__":
    import sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import dct_paths
    out = dct_paths.PBR_CACHE
    res = generate_all(out)
    print(f"PBR TEXTURES READY: {len(res)} sets in {out}")
