"""Detailliertere Router-Modelle der Stufen 1 bis 4 (PLAN.md Punkt 4).

Wird von build_utilities.build_all() aufgerufen. Die Helfer (GPart, rj45, pivot, add_text, router_root,
off, g, mat, br, ROUTER_X, DOOR_OPEN_DEG, SIDE_SLIDE) kommen per setup(globals()) aus build_utilities,
damit kein Zirkelimport entsteht.

Feste Vorgaben aus scripts/world/garage_builder.gd, die hier nicht verschoben werden duerfen:
    LAN-Buchsen  Stufe 1:   3 Stueck ab x=-0.14, Abstand 0.14,  y=-0.06,  Front z=0.12
                 Stufe 2:   5 Stueck ab x=-0.27, Abstand 0.09,  y=-0.06,  Front z=0.14
                 Stufe 3/4: 6 Stueck ab x=-0.26, Abstand 0.104, y=-0.095, Front z=0.166
    Knoten       *_Hinge_Door (dct_open_deg), *_Panel_Side_L/R (dct_closed_x, dct_slide_x),
                 *_Pivot_Antenna_L/R (dct_tilt_deg_y), Material RouterLED fuer Status-LEDs.
"""
import math
from types import SimpleNamespace

H = SimpleNamespace()

# (Anzahl, erste x, Abstand, y, Frontflaeche z) – muss zu ROUTER_JACK_* im Spiel passen
JACKS_T1 = (3, -0.14, 0.14, -0.06, 0.12)
JACKS_T2 = (5, -0.27, 0.09, -0.06, 0.14)
JACKS_CORE = (6, -0.26, 0.104, -0.095, 0.166)

# Schrankeinbauten (Stufe 3/4), Hoehen in Godot-Y relativ zum Router-Ursprung
PATCH_X0, PATCH_PITCH = -0.275, 0.05
TRAY_Y = 0.12
TRAY_X = tuple(-0.20 + 0.08 * i for i in range(6))
CM_Y = 0.035
SW_Y = -0.085
SFP_Y = -0.06
SFP_X = (-0.20, -0.12, -0.04, 0.04)
QSFP_X = tuple(-0.28 + 0.08 * i for i in range(8))
FACE_Z = 0.154          # Mitte der 19"-Frontblenden (0.150 .. 0.158)


def setup(ns):
    """Uebernimmt die Helfer aus dem Namensraum von build_utilities."""
    global H
    H = SimpleNamespace(**ns)


def _ensure_materials(M):
    if "rt_wan" in M:
        return
    mat = H.mat
    M.update({
        "rt_wan": mat("RtPortWan", (0.86, 0.62, 0.12), 0.45, 0.20),
        "rt_cord_blue": mat("RtCordBlue", (0.16, 0.36, 0.78), 0.50),
        "rt_cord_green": mat("RtCordGreen", (0.18, 0.62, 0.30), 0.50),
        "rt_cord_grey": mat("RtCordGrey", (0.55, 0.57, 0.60), 0.55),
        "rt_aqua": mat("RtFiberAqua", (0.20, 0.75, 0.80), 0.45),
        "rt_sfp": mat("RtSfpCage", (0.70, 0.72, 0.74), 0.30, 0.85),
        "rt_fan": mat("RtFanHub", (0.09, 0.09, 0.10), 0.55),
    })


# ---------------------------------------------------------------------------
# Kleinteile
# ---------------------------------------------------------------------------

def _jack_row(p, M, row, frame="port_blue"):
    count, x0, pitch, y, z = row
    xs = [x0 + pitch * i for i in range(count)]
    for x in xs:
        H.rj45(p, x, y, z, M, frame=frame)
    return xs


def _screw(p, M, x, y, z, r=0.006):
    """Schraubenkopf, z = Mitte (Kopfhoehe 4 mm), mit Schlitz."""
    p.gcyl((x, y, z), r, r, 0.004, M["screw"], axis="Z", segs=12)
    p.gbox((x, y, z + 0.0021), (r * 1.4, r * 0.3, 0.0004), M["hole"])


def _rack_screws(p, M, y, z, dy=0.0):
    for sx in (-0.37, 0.37):
        for sy in ((y - dy, y + dy) if dy else (y,)):
            _screw(p, M, sx, sy, z)


def _fan_grille(p, M, x, y, z, r, sign):
    """Runder Luefterausschnitt auf einer Seitenflaeche, sign = Richtung der Flaechennormalen (+-X)."""
    p.gcyl((x + sign * 0.0005, y, z), r, r, 0.001, M["hole"], axis="X", segs=32)
    for k in range(-3, 4):
        dz = r * k / 3.6
        chord = 2.0 * math.sqrt(max(r * r - dz * dz, 0.0))
        p.gbox((x + sign * 0.0015, y, z + dz), (0.002, chord, 0.003), M["galv"])
    p.gcyl((x + sign * 0.0028, y, z), r * 0.22, r * 0.22, 0.002, M["rt_fan"], axis="X", segs=16)


def _fiber_jumper(p, M, sx, sy, s_front, ax):
    """LC-Duplex-Jumper von einem SFP/QSFP-Modul (Front s_front) zum Adapter ax der Glasfaserleiste."""
    p.gbox((ax, TRAY_Y, 0.167), (0.026, 0.012, 0.010), M["lc_blue"])
    p.gcyl((ax, TRAY_Y, 0.177), 0.005, 0.006, 0.010, M["rt_aqua"], axis="Z", segs=12)
    p.gbox((sx, sy, s_front + 0.006), (0.022, 0.010, 0.012), M["lc_blue"])
    p.gcyl((sx, sy, s_front + 0.017), 0.005, 0.006, 0.010, M["rt_aqua"], axis="Z", segs=12)
    p.ghose([(sx, sy, s_front + 0.022), (sx, sy + 0.03, 0.202), (ax, 0.0, 0.204),
             (ax, TRAY_Y - 0.03, 0.198), (ax, TRAY_Y, 0.182)], 0.0028, M["rt_aqua"])


# ---------------------------------------------------------------------------
# Stufe 1: VDSL-Business-Router
# ---------------------------------------------------------------------------

def build_router_vdsl(coll, M):
    _ensure_materials(M)
    n = "router_t1_vdsl"
    root = H.router_root(coll, n, 1, H.ROUTER_X[1])
    p = H.GPart(f"{n}_Body")

    # Wandhalter, Gehaeuse, Deckel mit Lueftungsgitter, zweireihige Seitenschlitze
    p.gbox((0.0, 0.0, -0.115), (0.40, 0.16, 0.01), M["galv"])
    p.gbox((0.0, 0.0, 0.0), (0.58, 0.30, 0.20), M["router_body"])
    p.gbox((0.0, 0.158, -0.005), (0.56, 0.016, 0.19), M["router_body"])
    p.gbox((0.0, 0.1675, -0.01), (0.40, 0.003, 0.12), M["perf"], uv=H.br.PERF_TILE)
    for sx in (-0.2905, 0.2905):
        for col in range(2):
            for k in range(6):
                p.gbox((sx, -0.08 + 0.03 * k, -0.035 + 0.07 * col), (0.002, 0.012, 0.05), M["slot"])

    # Glanzfront mit Zierleisten, LED-Reihe und Sync-Anzeige
    p.gbox((0.0, -0.01, 0.106), (0.54, 0.24, 0.012), M["gloss"])
    p.gbox((0.0, 0.09, 0.1135), (0.54, 0.006, 0.003), M["silver"])
    p.gbox((0.0, -0.118, 0.1135), (0.54, 0.004, 0.003), M["silver"])
    leds = ("PWR", "DSL", "WAN", "LAN", "WLAN", "SYS")
    for i in range(len(leds)):
        p.gbox((-0.23 + 0.035 * i, 0.06, 0.1135), (0.018, 0.006, 0.003), M["router_led"])
    p.gbox((-0.17, 0.005, 0.1135), (0.12, 0.032, 0.003), M["screen"])

    # Buchsenfeld: WAN (gelb) + 3 LAN, Ein-Taster mit LED, Reset-Loch
    p.gbox((-0.045, -0.06, 0.1125), (0.43, 0.052, 0.001), M["dark"])
    lan_x = _jack_row(p, M, JACKS_T1)
    H.rj45(p, -0.23, -0.06, 0.12, M, frame="rt_wan")
    p.gcyl((0.235, -0.06, 0.117), 0.012, 0.012, 0.010, M["rubber"], axis="Z", segs=16)
    p.gcyl((0.235, -0.06, 0.1225), 0.004, 0.004, 0.001, M["router_led"], axis="Z", segs=12)
    p.gcyl((0.20, -0.06, 0.1123), 0.0025, 0.0025, 0.0006, M["hole"], axis="Z", segs=10)

    # Antennengelenke und Kabel von hinten ins Leerrohr (VDSL-Leitung + Netzteil)
    for sx in (-0.22, 0.22):
        p.gcyl((sx, 0.168, -0.06), 0.018, 0.018, 0.034, M["rubber"], axis="X", segs=16)
        p.gbox((sx, 0.1665, -0.06), (0.05, 0.003, 0.05), M["plastic_black"])
    p.ghose([(0.0, 0.12, -0.105), (0.0, 0.19, -0.06), (0.0, 0.235, -0.02)], 0.0035, M["plastic_black"])
    p.ghose([(0.06, 0.12, -0.105), (0.04, 0.19, -0.06), (0.008, 0.235, -0.02)], 0.003, M["rt_cord_grey"])
    p.build(coll, root)

    for side, sx in enumerate((-0.22, 0.22)):
        ap = (sx, 0.168, -0.06)
        tag = "L" if side == 0 else "R"
        ae = H.pivot(coll, f"{n}_Pivot_Antenna_{tag}", root, ap)
        tilt = -10.0 if side == 0 else 10.0
        ae["dct_tilt_deg_y"] = tilt
        a = H.GPart(f"{n}_Antenna_{tag}", ap)
        a.gbox(H.off(ap, (0.0, 0.13, 0.0)), (0.034, 0.21, 0.014), M["rubber"])
        a.gcyl(H.off(ap, (0.0, 0.235, 0.0)), 0.017, 0.017, 0.014, M["rubber"], axis="Z", segs=16)
        a.gcyl(H.off(ap, (0.0, 0.025, 0.0)), 0.017, 0.017, 0.014, M["rubber"], axis="Z", segs=16)
        a.gbox(H.off(ap, (0.0, 0.04, 0.0)), (0.036, 0.004, 0.015), M["silver"])
        for k in range(3):
            a.gbox(H.off(ap, (0.0, 0.07 + 0.012 * k, 0.0)), (0.036, 0.003, 0.0155), M["plastic_black"])
        a.build(coll, ae, H.g(*ap))
        ae.rotation_euler.y = math.radians(tilt)

    tl = M["text_light"]
    H.add_text(coll, root, f"{n}_Txt_Model", "VDSL 250  BUSINESS", (0.13, 0.06, 0.1125), 0.0264, tl)
    for i, s in enumerate(leds):
        H.add_text(coll, root, f"{n}_Txt_{s}", s, (-0.23 + 0.035 * i, 0.042, 0.1125), 0.007, tl)
    H.add_text(coll, root, f"{n}_Txt_Lcd", "SYNC 250/40", (-0.17, 0.005, 0.1154), 0.011, M["lcd_text"])
    for i, x in enumerate(lan_x):
        H.add_text(coll, root, f"{n}_Txt_Lan{i + 1}", f"LAN{i + 1}", (x, -0.095, 0.1125), 0.007, tl)
    H.add_text(coll, root, f"{n}_Txt_Wan", "WAN", (-0.23, -0.095, 0.1125), 0.007, tl)
    return root


# ---------------------------------------------------------------------------
# Stufe 2: Glasfaser-Gateway
# ---------------------------------------------------------------------------

def build_router_gateway(coll, M):
    _ensure_materials(M)
    n = "router_t2_gateway"
    root = H.router_root(coll, n, 2, H.ROUTER_X[2])
    p = H.GPart(f"{n}_Body")

    # Gehaeuse, Deckelgitter, Frontblende, Montagewinkel mit Langloechern, Seitenluefter
    p.gbox((0.0, 0.0, 0.0), (0.74, 0.36, 0.24), M["gw_body"])
    p.gbox((0.0, 0.181, -0.02), (0.60, 0.003, 0.16), M["perf"], uv=H.br.PERF_TILE)
    p.gbox((0.0, 0.0, 0.1225), (0.66, 0.30, 0.005), M["gw_face"])
    for sx in (-0.385, 0.385):
        p.gbox((sx, 0.0, 0.11), (0.03, 0.36, 0.03), M["galv"])
        for sy in (-0.12, 0.12):
            p.gbox((sx, sy, 0.1255), (0.010, 0.022, 0.002), M["hole"])
            p.gcyl((sx, sy, 0.1265), 0.008, 0.008, 0.004, M["screw"], axis="Z", segs=12)
    for sign in (-1.0, 1.0):
        _fan_grille(p, M, sign * 0.37, 0.02, -0.03, 0.07, sign)
    p.gbox((0.3705, 0.13, -0.03), (0.001, 0.03, 0.08), M["sticker"])

    # LCD mit Rahmen, zwei SFP-Kaefige (einer belegt) mit Link-LEDs
    p.gbox((-0.23, 0.08, 0.1255), (0.152, 0.082, 0.002), M["silver"])
    p.gbox((-0.23, 0.08, 0.127), (0.14, 0.07, 0.004), M["screen"])
    for i in range(2):
        cx = -0.07 + 0.10 * i
        p.gbox((cx, 0.08, 0.134), (0.075, 0.045, 0.022), M["galv"])
        p.gbox((cx, 0.08, 0.1455), (0.06, 0.03, 0.002), M["jack"])
        p.gbox((cx - 0.03, 0.11, 0.1255), (0.006, 0.004, 0.002), M["router_led" if i == 0 else "amber_led"])
    p.gbox((-0.07, 0.08, 0.152), (0.03, 0.022, 0.016), M["lc_blue"])
    p.gcyl((-0.07, 0.08, 0.164), 0.007, 0.0075, 0.012, M["fiber"], axis="Z", segs=12)
    p.ghose([(-0.07, 0.08, 0.17), (-0.06, 0.15, 0.18), (-0.03, 0.205, 0.13), (0.0, 0.215, -0.02)],
            0.005, M["fiber"])
    for i in range(4):
        p.gcyl((0.15 + 0.04 * i, 0.10, 0.127), 0.006, 0.006, 0.004, M["router_led"], axis="Z", segs=12)

    # Buchsenleiste (5 LAN), Konsole, USB, Reset
    p.gbox((-0.09, -0.06, 0.1285), (0.40, 0.05, 0.007), M["dark"])
    lan_x = _jack_row(p, M, JACKS_T2)
    p.gbox((0.23, -0.06, 0.1285), (0.05, 0.05, 0.007), M["dark"])
    H.rj45(p, 0.23, -0.06, 0.14, M, frame="console_blue")
    p.gbox((0.15, -0.06, 0.1265), (0.020, 0.010, 0.003), M["silver"])
    p.gbox((0.15, -0.06, 0.1281), (0.014, 0.004, 0.0006), M["jack"])
    p.gcyl((0.185, -0.06, 0.1253), 0.003, 0.003, 0.0006, M["hole"], axis="Z", segs=12)
    p.gbox((0.0, -0.135, 0.126), (0.66, 0.025, 0.003), M["perf"], uv=H.br.PERF_TILE)

    # Netzkabel durch Verschraubung im Deckel zum Leerrohr
    p.gcyl((0.28, 0.184, -0.06), 0.012, 0.012, 0.008, M["gland"], segs=16)
    p.ghose([(0.28, 0.186, -0.06), (0.26, 0.205, -0.05), (0.06, 0.212, -0.03), (0.008, 0.215, -0.02)],
            0.004, M["plastic_black"])
    p.build(coll, root)

    tl = M["text_light"]
    H.add_text(coll, root, f"{n}_Txt_Lcd", "1G FIBER\nUPLINK OK", (-0.23, 0.08, 0.1295), 0.020, M["lcd_text"])
    H.add_text(coll, root, f"{n}_Txt_Model", "GLASFASER-GATEWAY 1G", (0.21, 0.055, 0.1255), 0.020, tl)
    H.add_text(coll, root, f"{n}_Txt_Console", "CONSOLE", (0.23, -0.088, 0.1255), 0.008, tl)
    H.add_text(coll, root, f"{n}_Txt_Usb", "USB", (0.15, -0.075, 0.1255), 0.006, tl)
    for i, s in enumerate(("PWR", "SYS", "FIB", "ALM")):
        H.add_text(coll, root, f"{n}_Txt_Led_{s}", s, (0.15 + 0.04 * i, 0.118, 0.1255), 0.006, tl)
    for i in range(2):
        H.add_text(coll, root, f"{n}_Txt_Sfp{i + 1}", f"SFP{i + 1}", (-0.07 + 0.10 * i, 0.05, 0.1255), 0.007, tl)
    for i, x in enumerate(lan_x):
        H.add_text(coll, root, f"{n}_Txt_Lan{i + 1}", str(i + 1), (x, -0.093, 0.1255), 0.007, tl)
    return root


# ---------------------------------------------------------------------------
# Stufe 3/4: Wandschrank mit Core-Switch
# ---------------------------------------------------------------------------

def _cabinet_shell(p, M, cab_h, cy, top, bottom, zc, depth, is_100g):
    br = H.br
    # Korpus: Rueckwand, Deckel, Boden, Eckprofile, Innenraum, Deckelgitter, Kabeleinfuehrung, Wandlaschen
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
    # Bodenblech mit Buerstendurchfuehrung
    p.gbox((0.0, bottom - 0.002, 0.04), (0.36, 0.004, 0.10), M["dark"])
    p.gbox((0.0, bottom - 0.0045, 0.04), (0.30, 0.001, 0.012), M["hole"])

    # 19"-Profilschienen mit Rasterloechern
    hole_count = int((cab_h - 0.08) / 0.0445)
    for rx in (-0.375, 0.375):
        p.gbox((rx, cy, 0.14), (0.035, cab_h - 0.04, 0.02), M["galv"])
        for k in range(hole_count):
            p.gbox((rx, bottom + 0.06 + 0.0445 * k, 0.1505), (0.009, 0.009, 0.002), M["hole"])

    # Typenschild mit Status-LEDs, bei Stufe 4 zusaetzliche Lueftereinheit
    p.gbox((0.0, 0.285, 0.148), (0.72, 0.06, 0.006), M["cab_face"])
    for i in range(3):
        p.gbox((0.25 + 0.03 * i, 0.285, 0.1515), (0.010, 0.006, 0.001),
               M["router_led" if i < 2 else "amber_led"])
    if is_100g:
        p.gbox((0.0, 0.36, 0.150), (0.72, 0.06, 0.004), M["perf"], uv=br.PERF_TILE)


def _patch_panel(p, M):
    """Patchpanel mit 12 Keystones, Beschriftungsstreifen und 6 gesteckten Patchkabeln."""
    p.gbox((0.0, 0.20, 0.155), (0.78, 0.08, 0.01), M["galv"])
    p.gbox((0.0, 0.228, 0.1605), (0.60, 0.010, 0.002), M["paper"])
    for i in range(12):
        px = PATCH_X0 + PATCH_PITCH * i
        p.gbox((px, 0.195, 0.1605), (0.03, 0.026, 0.002), M["hole"])
        p.gbox((px, 0.195, 0.1615), (0.024, 0.020, 0.002), M["white"])
        p.gbox((px, 0.193, 0.1627), (0.014, 0.010, 0.0006), M["jack"])
    _rack_screws(p, M, 0.20, 0.162, dy=0.025)
    cords = ("rt_cord_blue", "rt_cord_blue", "rt_cord_green", "rt_cord_green", "rt_cord_grey", "rt_cord_grey")
    for i, cm in enumerate(cords):
        px = PATCH_X0 + PATCH_PITCH * i
        p.gbox((px, 0.193, 0.170), (0.014, 0.012, 0.014), M["sticker"])
        p.gbox((px, 0.193, 0.181), (0.012, 0.011, 0.010), M[cm])
        p.ghose([(px, 0.193, 0.186), (px, 0.165, 0.193), (px + 0.005, 0.10, 0.195),
                 (px + 0.02, 0.055, 0.176), (px + 0.04, CM_Y, 0.163)], 0.003, M[cm])


def _fiber_tray(p, M):
    """1 HE Glasfaser-Verteiler mit 6 LC-Duplex-Adaptern."""
    p.gbox((0.0, TRAY_Y, FACE_Z), (0.78, 0.0445, 0.008), M["cab_face"])
    for x in TRAY_X:
        p.gbox((x, TRAY_Y, 0.160), (0.034, 0.016, 0.004), M["lc_blue"])
        for dx in (-0.008, 0.008):
            p.gbox((x + dx, TRAY_Y, 0.1622), (0.007, 0.007, 0.0006), M["hole"])
    _rack_screws(p, M, TRAY_Y, 0.160)


def _cable_manager(p, M):
    """Kabelfuehrung mit Buerstenschlitz und sechs Fuehrungsbuegeln."""
    p.gbox((0.0, CM_Y, 0.153), (0.78, 0.07, 0.006), M["cab_face"])
    p.gbox((0.0, CM_Y, 0.1565), (0.66, 0.016, 0.001), M["hole"])
    for x in (-0.30, -0.18, -0.06, 0.06, 0.18, 0.30):
        for yy in (CM_Y + 0.025, CM_Y - 0.025):
            p.gbox((x, yy, 0.168), (0.008, 0.004, 0.024), M["galv"])
        p.gbox((x, CM_Y, 0.181), (0.008, 0.054, 0.004), M["galv"])
    _rack_screws(p, M, CM_Y, 0.158, dy=0.02)


def _core_switch(p, M):
    """2 HE Core-Switch: 6 RJ45 (Spielbuchsen), 4 SFP+-Kaefige, Management-Port, Status-LEDs."""
    p.gbox((0.0, SW_Y, 0.025), (0.70, 0.085, 0.25), M["gw_body"])
    p.gbox((0.0, SW_Y, FACE_Z), (0.78, 0.089, 0.008), M["cab_face"])
    _rack_screws(p, M, SW_Y, 0.160, dy=0.025)
    p.gbox((0.0, JACKS_CORE[3], 0.1585), (0.58, 0.040, 0.001), M["dark"])
    jack_x = _jack_row(p, M, JACKS_CORE)
    for x in SFP_X:
        p.gbox((x, SFP_Y, 0.163), (0.030, 0.013, 0.010), M["rt_sfp"])
        p.gbox((x, SFP_Y, 0.1683), (0.024, 0.008, 0.0006), M["jack"])
        p.gbox((x + 0.019, SFP_Y, 0.1585), (0.004, 0.004, 0.001), M["router_led"])
    H.rj45(p, 0.24, -0.058, 0.166, M, frame="console_blue")
    for i, y in enumerate((-0.06, -0.08, -0.10)):
        p.gbox((-0.32, y, 0.1585), (0.008, 0.005, 0.001), M["router_led" if i < 2 else "amber_led"])
    p.gbox((0.32, -0.105, 0.1585), (0.05, 0.03, 0.001), M["perf"], uv=H.br.PERF_TILE)
    return jack_x


def _qsfp_card(p, M, y):
    """1 HE 100G-Linecard mit 8 QSFP28-Kaefigen, 4 davon belegt und zur Glasfaserleiste gepatcht."""
    p.gbox((0.0, y, 0.025), (0.70, 0.040, 0.25), M["gw_body"])
    p.gbox((0.0, y, FACE_Z), (0.78, 0.0445, 0.008), M["cab_face"])
    _rack_screws(p, M, y, 0.160)
    for i, x in enumerate(QSFP_X):
        p.gbox((x, y, 0.163), (0.040, 0.016, 0.010), M["rt_sfp"])
        p.gbox((x, y, 0.1683), (0.032, 0.010, 0.0006), M["jack"])
        p.gbox((x, y + 0.016, 0.1585), (0.006, 0.004, 0.001), M["router_led" if i < 4 else "amber_led"])
        if i < 4:
            p.gbox((x, y, 0.174), (0.034, 0.012, 0.012), M["silver"])
            _fiber_jumper(p, M, x, y, 0.180, TRAY_X[2 + i])


def _pdu(p, M, y):
    """1 HE Steckdosenleiste mit 6 Dosen, beleuchtetem Schalter und zwei Netzkabeln zum Switch."""
    p.gbox((0.0, y, 0.05), (0.70, 0.040, 0.20), M["dark"])
    p.gbox((0.0, y, FACE_Z), (0.78, 0.0445, 0.008), M["dark"])
    _rack_screws(p, M, y, 0.160)
    for i in range(6):
        x = -0.25 + 0.09 * i
        p.gcyl((x, y, 0.160), 0.015, 0.015, 0.004, M["plastic_black"], axis="Z", segs=20)
        for dx in (-0.0045, 0.0045):
            p.gcyl((x + dx, y, 0.1622), 0.002, 0.002, 0.0006, M["hole"], axis="Z", segs=8)
    p.gbox((0.30, y, 0.161), (0.022, 0.026, 0.006), M["lever_red"])
    for i in range(2):
        x = -0.25 + 0.09 * i
        p.gcyl((x, y, 0.170), 0.012, 0.012, 0.016, M["plastic_black"], axis="Z", segs=16)
        p.ghose([(x, y, 0.178), (x - 0.01, y + 0.02, 0.19), (-0.335, y + 0.05, 0.175),
                 (-0.345, SW_Y, 0.14), (-0.352, SW_Y, 0.10)], 0.0035, M["plastic_black"])


def _side_panels(coll, M, root, n, cab_h, cy, top, bottom, zc, depth):
    for side, sx in enumerate((-0.41, 0.41)):
        tag = "L" if side == 0 else "R"
        sign = -1.0 if side == 0 else 1.0
        sp = H.GPart(f"{n}_Panel_Side_{tag}", (sx, cy, zc))
        sp.gbox((sx, cy, zc), (0.02, cab_h, depth), M["gw_body"])
        for k in range(int((cab_h - 0.16) / 0.03)):
            sp.gbox((sx + sign * 0.0105, bottom + 0.09 + 0.03 * k, zc), (0.002, 0.010, 0.18), M["slot"])
        sp.gbox((sx + sign * 0.0115, top - 0.04, zc), (0.004, 0.02, 0.08), M["plastic_black"])
        for zz in (zc - 0.12, zc + 0.12):
            sp.gcyl((sx + sign * 0.0115, cy, zz), 0.008, 0.008, 0.003, M["chrome"], axis="X", segs=12)
        ob = sp.build(coll, root)
        ob["dct_closed_x"] = float(ob.location.x)
        ob["dct_slide_x"] = sign * H.SIDE_SLIDE


def _door(coll, M, root, n, cab_h, cy, top, bottom, zf):
    """Glastuer, Scharnier links, Schwenkhebelgriff rechts, Lueftungsschlitze im unteren Rahmen."""
    hp = (-0.42, cy, zf)
    de = H.pivot(coll, f"{n}_Hinge_Door", root, hp)
    de["dct_open_deg"] = H.DOOR_OPEN_DEG
    d = H.GPart(f"{n}_Door", hp)
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
    for k in range(8):
        d.gbox((-0.21 + 0.06 * k, bottom + 0.02, zd + 0.0085), (0.04, 0.006, 0.001), M["slot"])
    d.build(coll, de, H.g(*hp))
    H.add_text(coll, de, f"{n}_Txt_DoorWarn", "NUR FUER BEFUGTE", (0.0, top - 0.02, zd + 0.0085), 0.010,
               M["text_light"], parent_origin_g=hp)


def build_router_cabinet(coll, M, is_100g):
    _ensure_materials(M)
    n = "router_t4_core100g" if is_100g else "router_t3_core10g"
    tier = 4 if is_100g else 3
    root = H.router_root(coll, n, tier, H.ROUTER_X[tier])
    cab_h = 0.72 if is_100g else 0.56
    cy = 0.06
    top, bottom = cy + cab_h * 0.5, cy - cab_h * 0.5
    zf, zb = 0.215, -0.15           # Vorderkante / Rueckwand
    zc, depth = (zf + zb) * 0.5, zf - zb

    p = H.GPart(f"{n}_Body")
    _cabinet_shell(p, M, cab_h, cy, top, bottom, zc, depth, is_100g)
    _patch_panel(p, M)
    _fiber_tray(p, M)
    _cable_manager(p, M)
    jack_x = _core_switch(p, M)
    for i in range(2):
        p.gbox((SFP_X[i], SFP_Y, 0.170), (0.026, 0.011, 0.004), M["silver"])
        _fiber_jumper(p, M, SFP_X[i], SFP_Y, 0.172, TRAY_X[i])
    if is_100g:
        _qsfp_card(p, M, -0.165)
        _pdu(p, M, -0.235)
    else:
        _pdu(p, M, -0.165)
    p.build(coll, root)

    _side_panels(coll, M, root, n, cab_h, cy, top, bottom, zc, depth)
    _door(coll, M, root, n, cab_h, cy, top, bottom, zf)

    tl, td = M["text_light"], M["text_dark"]
    H.add_text(coll, root, f"{n}_Txt_Model", "CORE 100G" if is_100g else "CORE 10G", (0.0, 0.285, 0.1515),
               0.034, tl)
    for i in range(12):
        H.add_text(coll, root, f"{n}_Txt_Patch{i + 1}", str(i + 1),
                   (PATCH_X0 + PATCH_PITCH * i, 0.228, 0.1620), 0.007, td)
    H.add_text(coll, root, f"{n}_Txt_Odf", "FIBER ODF", (0.30, TRAY_Y, 0.1585), 0.008, tl)
    H.add_text(coll, root, f"{n}_Txt_Switch", "L3 CORE", (0.14, -0.06, 0.1585), 0.008, tl)
    H.add_text(coll, root, f"{n}_Txt_Mgmt", "MGMT", (0.205, -0.058, 0.1585), 0.005, tl)
    for i, x in enumerate(jack_x):
        H.add_text(coll, root, f"{n}_Txt_Port{i + 1}", str(i + 1), (x, -0.119, 0.1585), 0.006, tl)
    pdu_y = -0.235 if is_100g else -0.165
    H.add_text(coll, root, f"{n}_Txt_Pdu", "230V", (0.30, pdu_y - 0.0175, 0.1585), 0.005, tl)
    if is_100g:
        H.add_text(coll, root, f"{n}_Txt_Qsfp", "100G", (0.335, -0.165, 0.1585), 0.007, tl)
    return root