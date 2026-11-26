"""PBR-Textur-Generator fuer die neuen Server-Racks (rack.glb & rack_pro.glb).

Erzeugt mit reinem NumPy (baut auf pbr_textures.py auf):
- Feinkoernige matt-schwarze Pulverbeschichtung (Albedo, Normal, ORM)
- Echtes transparentes Waben-Lochblech (RGBA Alpha-Clip + Normal + ORM)
- Nummerierte 19-Zoll-Montageschienen (HE-Skala + Vierkantloecher)
- Industrie-Anschlussblenden hinten: PWR (Gelb/Gold), LAN (Blau), LINK (Violett)
- Markenplaketten (DCT-4200 & DCT-PRO 6U TITAN)
- Gebuerstetes Gold-Titan (Pro-Rack), Alu & verzinktes Blech
"""

import math
import os
import sys
import numpy as np

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

from pbr_textures import (
    draw_circle,
    draw_text,
    fbm_tile,
    fill_rect,
    gen_brushed_metal_pbr,
    height_to_normal,
    pack_orm,
    save_png,
    stroke_rect,
)


def gen_powder_coat_pbr(cache_dir: str, name: str = "rack_powder_black",
                        base_rgb=(0.078, 0.082, 0.090)) -> dict:
    """Authentische feinkoernige schwarze Industrie-Pulverbeschichtung (wie Rittal / APC NetShelter)."""
    prefix = os.path.join(cache_dir, name)
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    W = H = 512
    pebble = fbm_tile(H, W, 96, 96, octaves=3, seed=811)
    fine = fbm_tile(H, W, 192, 192, octaves=2, seed=823)
    broad = fbm_tile(H, W, 8, 8, octaves=3, seed=839)
    h = 0.55 * pebble + 0.30 * fine + 0.15 * broad

    base = np.array(base_rgb, dtype=np.float32)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    for c in range(3):
        albedo[:, :, c] = np.clip(base[c] * (0.86 + 0.28 * h), 0.0, 1.0)
    rough = np.clip(0.47 + 0.12 * (0.5 - h), 0.32, 0.65)
    metal = np.full((H, W), 0.36, dtype=np.float32)
    ao = np.clip(0.90 + 0.10 * h, 0.0, 1.0)

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(h, strength=1.8, wrap=True))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


def gen_hex_mesh_alpha_pbr(cache_dir: str, name: str = "rack_hex_mesh",
                           metal_rgb=(0.125, 0.132, 0.145), hole_ratio: float = 0.365) -> dict:
    """Echt durchsichtiges Waben-Lochblech (RGBA Alpha-Clip!) fuer Fronttuer-Fluegel, Hecktuer & Dach."""
    prefix = os.path.join(cache_dir, name)
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    W = H = 256
    nx = 6.0
    ny = round(nx / math.sqrt(3.0))  # 3 Reihen -> perfekt nahtlos!
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    ux = (xx / W) * nx
    uy = (yy / H) * (ny * math.sqrt(3.0))

    def hex_sdf(px, py):
        ax = np.abs(px)
        ay = np.abs(py)
        return np.maximum(ax * 0.8660254 + ay * 0.5, ay)

    d1 = hex_sdf((ux + 0.5) % 1.0 - 0.5, (uy + 0.8660254) % 1.7320508 - 0.8660254)
    d2 = hex_sdf((ux) % 1.0 - 0.5, (uy) % 1.7320508 - 0.8660254)
    d = np.minimum(d1, d2)

    # Harte Alpha-Maske (fuer glTF MASK / Alpha-Clip): 1 = Metallsteg, 0 = offenes Loch!
    alpha = np.clip((d - hole_ratio) / 0.025, 0.0, 1.0)
    bevel = np.clip((d - (hole_ratio - 0.01)) / 0.06, 0.0, 1.0)
    pebble = fbm_tile(H, W, 64, 64, octaves=2, seed=853)

    base = np.array(metal_rgb, dtype=np.float32)
    rgba = np.empty((H, W, 4), dtype=np.float32)
    for c in range(3):
        rgba[:, :, c] = np.clip(base[c] * (0.88 + 0.22 * pebble), 0.0, 1.0)
    rgba[:, :, 3] = alpha

    rough = np.clip(0.44 + 0.08 * (0.5 - pebble), 0.30, 0.60)
    metal = np.full((H, W), 0.48, dtype=np.float32)
    ao = np.clip(0.60 + 0.40 * bevel, 0.0, 1.0)

    save_png(paths["albedo"], np.clip(rgba * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(bevel * 0.8 + 0.08 * pebble, strength=3.2, wrap=True))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


def gen_numbered_rail_pbr(cache_dir: str, name: str = "rack_rail_numbered") -> dict:
    """Nummerierte 19-Zoll-Stahlschiene (4 HE pro Kachel -> wiederholt sich sauber mit Vierkantloechern & Skala)."""
    prefix = os.path.join(cache_dir, name)
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    W, H = 256, 1024  # 1024px = 8 HE (~35.56 cm)
    brush = fbm_tile(H, W, 16, 128, octaves=3, seed=863)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    for c, b in enumerate((0.62, 0.64, 0.67)):
        albedo[:, :, c] = np.clip(b * (0.90 + 0.16 * brush), 0.0, 1.0)

    height = 0.55 + 0.04 * brush
    rough = np.full((H, W), 0.32, dtype=np.float32)
    metal = np.full((H, W), 0.88, dtype=np.float32)
    ao = np.ones((H, W), dtype=np.float32)

    dark = np.array([0.025, 0.027, 0.030], dtype=np.float32)
    mark = np.array([0.14, 0.15, 0.17], dtype=np.float32)
    u_h = H // 8
    for u in range(8):
        y0 = u * u_h
        # Trennlinie pro 1U
        fill_rect(albedo, 16, y0, W - 16, y0 + 3, mark)
        # 3 Vierkant-Kaefigmutter-Loecher pro 1U rechts auf der Schiene
        for frac in (0.17, 0.50, 0.83):
            cy = int(y0 + frac * u_h)
            fill_rect(albedo, 134, cy - 13, 188, cy + 13, dark)
            fill_rect(height, 134, cy - 13, 188, cy + 13, 0.05)
            fill_rect(metal, 134, cy - 13, 188, cy + 13, 0.0)
            fill_rect(rough, 134, cy - 13, 188, cy + 13, 0.95)
            fill_rect(ao, 134, cy - 13, 188, cy + 13, 0.12)
        # HE-Strichmarkierung & Nummer links
        fill_rect(albedo, 26, y0 + u_h // 2 - 2, 56, y0 + u_h // 2 + 2, mark)
        draw_text(albedo, 64, y0 + u_h // 2 - 12, f"U{8 - u}", mark, scale=3)

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(height, strength=3.0, wrap=True))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


def gen_port_plate_pbr(cache_dir: str, name: str, title: str, subtitle: str,
                       accent_rgb) -> dict:
    """Industrielle Rueckwand-Anschlussblende (PWR, LAN, LINK) mit dezentem farbigem Rahmen & Laser-Beschriftung."""
    prefix = os.path.join(cache_dir, name)
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    W, H = 512, 256
    brush = fbm_tile(H, W, 64, 8, octaves=2, seed=abs(hash(name)) % 5000 + 17)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    for c, b in enumerate((0.105, 0.112, 0.125)):
        albedo[:, :, c] = np.clip(b * (0.90 + 0.18 * brush), 0.0, 1.0)

    acc = np.array(accent_rgb, dtype=np.float32)
    txt = np.array([0.92, 0.94, 0.96], dtype=np.float32)

    # Dezenter, hochwertiger farbiger Industrie-Rahmen (sofort erkennbar, aber 0% Neon!)
    stroke_rect(albedo, 10, 10, W - 10, H - 10, acc, thickness=9)
    stroke_rect(albedo, 24, 24, W - 24, H - 24, np.array([0.24, 0.26, 0.29]), thickness=2)
    # Farbstreifen ganz oben als klare Codierung
    fill_rect(albedo, 10, 10, W - 10, 62, np.array([0.07, 0.075, 0.088]))
    fill_rect(albedo, 10, 58, W - 10, 66, acc)

    draw_text(albedo, 30, 22, title, txt, scale=4)
    draw_text(albedo, 48, 206, subtitle, acc, scale=3)

    # 4 dezente Ecken-Schrauben-Markierungen
    for cx in (28, W - 28):
        for cy in (H - 28,):
            draw_circle(albedo, cx, cy, 8, np.array([0.62, 0.64, 0.68]))
            draw_circle(albedo, cx, cy, 3, np.array([0.12, 0.12, 0.14]))

    rough = np.full((H, W), 0.42, dtype=np.float32) + 0.05 * (0.5 - brush)
    metal = np.full((H, W), 0.55, dtype=np.float32)
    ao = np.ones((H, W), dtype=np.float32)

    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(0.5 + 0.06 * brush, strength=1.2, wrap=False))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


def gen_brand_badge_pbr(cache_dir: str, name: str, title: str, sub: str, is_pro: bool) -> dict:
    prefix = os.path.join(cache_dir, name)
    paths = {"albedo": prefix + "_albedo.png", "normal": prefix + "_normal.png", "orm": prefix + "_orm.png"}
    W, H = 512, 128
    brush = fbm_tile(H, W, 32, 8, octaves=2, seed=911 if is_pro else 907)
    albedo = np.empty((H, W, 3), dtype=np.float32)
    bg = (0.11, 0.115, 0.13) if is_pro else (0.14, 0.15, 0.165)
    acc = np.array([0.84, 0.65, 0.24] if is_pro else [0.72, 0.76, 0.82], dtype=np.float32)
    for c in range(3):
        albedo[:, :, c] = np.clip(bg[c] * (0.90 + 0.16 * brush), 0.0, 1.0)
    stroke_rect(albedo, 4, 4, W - 4, H - 4, acc, thickness=4)
    fill_rect(albedo, 16, 16, 26, H - 16, acc)
    draw_text(albedo, 44, 24, title, np.array([0.94, 0.95, 0.97]), scale=4)
    draw_text(albedo, 44, 78, sub, acc, scale=3)

    rough = np.full((H, W), 0.34, dtype=np.float32)
    metal = np.full((H, W), 0.72, dtype=np.float32)
    ao = np.ones((H, W), dtype=np.float32)
    save_png(paths["albedo"], np.clip(albedo * 255.0, 0, 255).astype(np.uint8))
    save_png(paths["normal"], height_to_normal(0.5 + 0.06 * brush, strength=1.1, wrap=False))
    save_png(paths["orm"], pack_orm(ao, rough, metal))
    return paths


def generate_rack_textures(cache_dir: str) -> dict:
    os.makedirs(cache_dir, exist_ok=True)
    return {
        "powder_black": gen_powder_coat_pbr(cache_dir, "rack_powder_black", (0.075, 0.080, 0.088)),
        "powder_pro": gen_powder_coat_pbr(cache_dir, "rack_powder_pro", (0.062, 0.066, 0.074)),
        "hex_mesh": gen_hex_mesh_alpha_pbr(cache_dir, "rack_hex_mesh", (0.125, 0.132, 0.145), hole_ratio=0.375),
        "rail_numbered": gen_numbered_rail_pbr(cache_dir, "rack_rail_numbered"),
        "alu_trim": gen_brushed_metal_pbr(cache_dir, "rack_alu_trim", (0.72, 0.74, 0.78), 0.90, 0.28, seed=921),
        "gold_titan": gen_brushed_metal_pbr(cache_dir, "rack_gold_titan", (0.78, 0.62, 0.30), 0.92, 0.26, seed=929),
        "galv_steel": gen_brushed_metal_pbr(cache_dir, "rack_galv_steel", (0.58, 0.60, 0.63), 0.86, 0.32, spangle=0.18, seed=937),
        "pdu_body": gen_brushed_metal_pbr(cache_dir, "rack_pdu_body", (0.13, 0.14, 0.155), 0.72, 0.36, seed=941),
        "port_pwr": gen_port_plate_pbr(cache_dir, "rack_port_pwr", "PWR  230V/32A", "IEC C19 INPUT", (0.86, 0.66, 0.16)),
        "port_lan": gen_port_plate_pbr(cache_dir, "rack_port_lan", "LAN  100G", "RJ45 / SFP+ UPLINK", (0.20, 0.50, 0.86)),
        "port_link": gen_port_plate_pbr(cache_dir, "rack_port_link", "LINK  CLUSTER", "RACK INTERCONNECT", (0.64, 0.34, 0.88)),
        "badge_std": gen_brand_badge_pbr(cache_dir, "rack_badge_std", "DCT-4200", "STANDARD SERIES", False),
        "badge_pro": gen_brand_badge_pbr(cache_dir, "rack_badge_pro", "DCT-PRO 6U", "TITAN ENTERPRISE", True),
    }


if __name__ == "__main__":
    import dct_paths
    out = dct_paths.PBR_CACHE
    res = generate_rack_textures(out)
    print(f"RACK PBR TEXTURES READY: {len(res)} sets in {out}")
